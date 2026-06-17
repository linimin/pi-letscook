import { randomUUID } from "node:crypto";
import { spawn } from "node:child_process";
import * as fs from "node:fs";
import { promises as fsp } from "node:fs";
import * as path from "node:path";
import {
	clampHelperTimeoutMs,
	helperToolAllowlist,
	isHelperAllowedForRole,
} from "./helper-policy.ts";
import {
	type CompletionHelperFailure,
	type CompletionHelperFailureKind,
	type CompletionHelperName,
	type CompletionHelperProgressEvent,
	type CompletionHelperResult,
	type StructuredHelperOutput,
	STRUCTURED_HELPER_OUTPUT_LIMITS,
	utf8Length,
} from "./helper-types.ts";
import { helperArtifactsDir, helperRunLockDir, resolveFiles } from "./state-store.ts";

type JsonRecord = Record<string, unknown>;

type ParsedFrontmatter = {
	frontmatter: Record<string, string>;
	body: string;
};

export type LoadedHelperDefinition = {
	helper: CompletionHelperName;
	name: string;
	description?: string;
	model?: string;
	systemPrompt: string;
	filePath: string;
};

export type ResolvedHelperModel = {
	usedModel?: string;
	callerRoleModel?: string;
};

export type CompletionHelperSpawnSpec = {
	command: string;
	args: string[];
	cwd: string;
	env: NodeJS.ProcessEnv;
	signal: AbortSignal;
	onJsonEvent?: (event: JsonRecord, rawLine: string) => void;
};

export type CompletionHelperSpawnResult = {
	exitCode: number;
	stderr?: string;
	assistantText?: string;
	eventLines: string[];
};

export type RunCompletionHelperArgs = {
	root: string;
	helper: CompletionHelperName;
	callerRole: string;
	task: string;
	cwd?: string;
	timeoutMs?: number;
	signal?: AbortSignal;
	roleModel?: string;
	onProgress?: (event: CompletionHelperProgressEvent) => void;
	subprocessRunner?: (spec: CompletionHelperSpawnSpec) => Promise<CompletionHelperSpawnResult>;
	runId?: string;
};

export const HELPER_REQUIRED_FLAGS = [
	"--mode",
	"json",
	"-p",
	"--no-session",
	"--no-extensions",
	"--no-builtin-tools",
	"--no-skills",
	"--no-prompt-templates",
	"--no-context-files",
] as const;

function resolvePackageRoot(): string {
	const candidates = [
		typeof __dirname === "string" ? path.resolve(__dirname, "..", "..") : undefined,
		process.cwd(),
	].filter((candidate): candidate is string => Boolean(candidate));
	for (const candidate of candidates) {
		if (fs.existsSync(path.join(candidate, "package.json")) && fs.existsSync(path.join(candidate, "helpers", "scout.md"))) {
			return candidate;
		}
	}
	return candidates[0] ?? process.cwd();
}

const PACKAGE_ROOT = resolvePackageRoot();
const HELPERS_DIR = path.join(PACKAGE_ROOT, "helpers");
const PACKAGE_AGENTS_DIR = path.join(PACKAGE_ROOT, "agents");
const HELPER_TOOLS_EXTENSION_DIR = path.join(PACKAGE_ROOT, "extensions", "helper-tools");

class CompletionHelperRunnerError extends Error {
	readonly failureKind: CompletionHelperFailureKind;
	readonly rawText?: string;
	readonly stderr?: string;
	readonly exitCode?: number;

	constructor(
		failureKind: CompletionHelperFailureKind,
		message: string,
		options?: { rawText?: string; stderr?: string; exitCode?: number },
	) {
		super(message);
		this.name = "CompletionHelperRunnerError";
		this.failureKind = failureKind;
		this.rawText = options?.rawText;
		this.stderr = options?.stderr;
		this.exitCode = options?.exitCode;
	}
}

function asString(value: unknown): string | undefined {
	return typeof value === "string" && value.trim().length > 0 ? value.trim() : undefined;
}

function isRecord(value: unknown): value is JsonRecord {
	return typeof value === "object" && value !== null && !Array.isArray(value);
}

function normalizePathForOutput(value: string): string {
	return value.split(path.sep).join("/");
}

function isPathInside(root: string, candidate: string): boolean {
	return candidate === root || candidate.startsWith(`${root}${path.sep}`);
}

function normalizeRepoRelativePath(rawPath: string, fieldName: string): string {
	if (rawPath.includes("\0")) {
		throw new CompletionHelperRunnerError("policy", `${fieldName} must not contain NUL bytes`);
	}
	if (path.isAbsolute(rawPath)) {
		throw new CompletionHelperRunnerError("policy", `${fieldName} must be repo-relative, not absolute`);
	}
	const normalized = path.posix.normalize(rawPath.replace(/\\/g, "/"));
	if (normalized === ".." || normalized.startsWith("../")) {
		throw new CompletionHelperRunnerError("policy", `${fieldName} must stay inside the repo root`);
	}
	if (normalized.startsWith("/")) {
		throw new CompletionHelperRunnerError("policy", `${fieldName} must be repo-relative, not absolute`);
	}
	return normalized === "." ? "." : normalized.replace(/^\.\//, "");
}

function resolveHelperArtifactDir(artifactsRoot: string, runId: string): string {
	if (runId.includes("\0")) {
		throw new CompletionHelperRunnerError("policy", "helper runId must not contain NUL bytes");
	}
	if (runId.trim().length === 0) {
		throw new CompletionHelperRunnerError("policy", "helper runId must be non-empty");
	}
	if (path.isAbsolute(runId)) {
		throw new CompletionHelperRunnerError("policy", "helper runId must stay under canonical helper scratch");
	}
	if (runId.includes("/") || runId.includes("\\")) {
		throw new CompletionHelperRunnerError("policy", "helper runId must not contain path separators");
	}
	const resolvedArtifactsRoot = path.resolve(artifactsRoot);
	const artifactDir = path.resolve(resolvedArtifactsRoot, runId);
	if (artifactDir === resolvedArtifactsRoot || !isPathInside(resolvedArtifactsRoot, artifactDir)) {
		throw new CompletionHelperRunnerError("policy", "helper runId must stay under canonical helper scratch");
	}
	return artifactDir;
}

function truncateUtf8(value: string, maxBytes: number): string {
	if (utf8Length(value) <= maxBytes) return value;
	let result = "";
	let usedBytes = 0;
	for (const chunk of value) {
		const chunkBytes = utf8Length(chunk);
		if (usedBytes + chunkBytes > maxBytes) break;
		result += chunk;
		usedBytes += chunkBytes;
	}
	return result;
}

function parseSimpleFrontmatter(raw: string): ParsedFrontmatter {
	const source = raw.replace(/^\uFEFF/, "");
	if (!source.startsWith("---\n") && source.trimStart() !== source) {
		return { frontmatter: {}, body: source.trim() };
	}
	if (!source.startsWith("---")) return { frontmatter: {}, body: source.trim() };
	const lines = source.split(/\r?\n/);
	if (lines[0] !== "---") return { frontmatter: {}, body: source.trim() };
	const frontmatter: Record<string, string> = {};
	let index = 1;
	for (; index < lines.length; index += 1) {
		const line = lines[index] ?? "";
		if (line === "---") break;
		const separator = line.indexOf(":");
		if (separator <= 0) continue;
		const key = line.slice(0, separator).trim();
		const value = line.slice(separator + 1).trim();
		if (key.length > 0 && value.length > 0) frontmatter[key] = value;
	}
	if (index >= lines.length) return { frontmatter: {}, body: source.trim() };
	return {
		frontmatter,
		body: lines.slice(index + 1).join("\n").trim(),
	};
}

export function parseHelperDefinitionText(helper: CompletionHelperName, raw: string, filePath: string): LoadedHelperDefinition {
	const parsed = parseSimpleFrontmatter(raw);
	const systemPrompt = parsed.body.trim();
	if (!systemPrompt) {
		throw new CompletionHelperRunnerError("policy", `helper prompt body is empty: ${filePath}`);
	}
	return {
		helper,
		name: parsed.frontmatter.name ?? helper,
		description: parsed.frontmatter.description,
		model: parsed.frontmatter.model,
		systemPrompt,
		filePath,
	};
}

export async function loadHelperDefinition(helper: CompletionHelperName): Promise<LoadedHelperDefinition> {
	const filePath = path.join(HELPERS_DIR, `${helper}.md`);
	if (!fs.existsSync(filePath)) {
		throw new CompletionHelperRunnerError("policy", `missing package-owned helper definition: ${filePath}`);
	}
	const raw = await fsp.readFile(filePath, "utf8");
	return parseHelperDefinitionText(helper, raw, filePath);
}

async function loadPackagedCallerRoleModel(callerRole: string): Promise<string | undefined> {
	const filePath = path.join(PACKAGE_AGENTS_DIR, `${callerRole}.md`);
	if (!fs.existsSync(filePath)) return undefined;
	const raw = await fsp.readFile(filePath, "utf8");
	return asString(parseSimpleFrontmatter(raw).frontmatter.model);
}

export async function resolveHelperModel(args: {
	helperDefinition: LoadedHelperDefinition;
	callerRole: string;
	roleModel?: string;
}): Promise<ResolvedHelperModel> {
	const callerRoleModel =
		asString(args.roleModel) ?? asString(process.env.PI_COMPLETION_ROLE_MODEL) ?? await loadPackagedCallerRoleModel(args.callerRole);
	return {
		callerRoleModel,
		usedModel: args.helperDefinition.model ?? callerRoleModel,
	};
}

async function resolveRepoRootRealpath(root: string): Promise<string> {
	const realRoot = await fsp.realpath(root).catch(() => undefined);
	if (!realRoot) throw new CompletionHelperRunnerError("policy", `repo root must exist before running a helper: ${root}`);
	const stat = await fsp.stat(realRoot).catch(() => undefined);
	if (!stat?.isDirectory()) throw new CompletionHelperRunnerError("policy", `repo root must be a directory: ${realRoot}`);
	return realRoot;
}

export async function resolveHelperCwd(root: string, cwd?: string): Promise<string> {
	const rootRealpath = await resolveRepoRootRealpath(root);
	if (!cwd || cwd.trim().length === 0) return rootRealpath;
	const relativePath = normalizeRepoRelativePath(cwd.trim(), "cwd");
	const absolutePath = path.resolve(rootRealpath, relativePath === "." ? "." : relativePath);
	if (!isPathInside(rootRealpath, absolutePath)) {
		throw new CompletionHelperRunnerError("policy", `cwd escapes the repo root: ${cwd}`);
	}
	const realCwd = await fsp.realpath(absolutePath).catch(() => undefined);
	if (!realCwd || !isPathInside(rootRealpath, realCwd)) {
		throw new CompletionHelperRunnerError("policy", `cwd escapes the repo root via symlink or realpath: ${cwd}`);
	}
	const stat = await fsp.stat(realCwd).catch(() => undefined);
	if (!stat?.isDirectory()) {
		throw new CompletionHelperRunnerError("policy", `cwd must resolve to an existing directory: ${cwd}`);
	}
	return realCwd;
}

export function helperToolsExtensionPath(): string {
	return HELPER_TOOLS_EXTENSION_DIR;
}

async function ensureHelperArtifactsRoot(root: string): Promise<string> {
	const files = resolveFiles(root);
	const canonicalTmpRoot = files.tmpDir;
	const tmpStat = await fsp.stat(canonicalTmpRoot).catch(() => undefined);
	if (!tmpStat?.isDirectory()) {
		throw new CompletionHelperRunnerError(
			"policy",
			`canonical helper scratch root is missing or not a directory: ${canonicalTmpRoot}`,
		);
	}
	await fsp.access(canonicalTmpRoot, fs.constants.R_OK | fs.constants.W_OK).catch(() => {
		throw new CompletionHelperRunnerError("policy", `canonical helper scratch root is not writable: ${canonicalTmpRoot}`);
	});
	const artifactsRoot = helperArtifactsDir(root);
	await fsp.mkdir(artifactsRoot, { recursive: true });
	return artifactsRoot;
}

async function writeTextArtifact(artifactDir: string, fileName: string, content: string): Promise<void> {
	await fsp.writeFile(path.join(artifactDir, fileName), content, { encoding: "utf8", mode: 0o600 });
}

async function writeJsonArtifact(artifactDir: string, fileName: string, value: Record<string, unknown>): Promise<void> {
	await writeTextArtifact(artifactDir, fileName, `${JSON.stringify(value, null, 2)}\n`);
}

async function tryWriteTextArtifact(artifactDir: string, fileName: string, content: string | undefined): Promise<void> {
	if (typeof content !== "string") return;
	try {
		await writeTextArtifact(artifactDir, fileName, content);
	} catch {
		// best-effort cleanup artifact
	}
}

async function tryWriteJsonArtifact(artifactDir: string, fileName: string, value: Record<string, unknown>): Promise<void> {
	try {
		await writeJsonArtifact(artifactDir, fileName, value);
	} catch {
		// best-effort cleanup artifact
	}
}

function emitProgress(onProgress: RunCompletionHelperArgs["onProgress"], event: CompletionHelperProgressEvent): void {
	onProgress?.(event);
}

function buildHelperEnvContract(args: {
	helper: CompletionHelperName;
	callerRole: string;
	rootRealpath: string;
	resolvedCwd: string;
	callerRoleModel?: string;
}): NodeJS.ProcessEnv {
	const env: NodeJS.ProcessEnv = { ...process.env };
	delete env.PI_COMPLETION_ROLE;
	delete env.PI_COMPLETION_HELPER;
	delete env.PI_COMPLETION_CALLER_ROLE;
	delete env.PI_COMPLETION_HELPER_ROOT;
	delete env.PI_COMPLETION_HELPER_CWD;
	delete env.PI_COMPLETION_ROLE_MODEL;
	env.PI_COMPLETION_HELPER = args.helper;
	env.PI_COMPLETION_CALLER_ROLE = args.callerRole;
	env.PI_COMPLETION_HELPER_ROOT = args.rootRealpath;
	env.PI_COMPLETION_HELPER_CWD = args.resolvedCwd;
	if (args.callerRoleModel) env.PI_COMPLETION_ROLE_MODEL = args.callerRoleModel;
	return env;
}

export function buildHelperInvocationArgs(args: {
	helperDefinition: LoadedHelperDefinition;
	promptPath: string;
	toolAllowlist: string[];
	usedModel?: string;
	task: string;
}): string[] {
	const trimmedTask = args.task.trim();
	if (!trimmedTask) throw new CompletionHelperRunnerError("policy", "helper task must be non-empty");
	const toolExtension = helperToolsExtensionPath();
	if (!fs.existsSync(path.join(toolExtension, "index.ts"))) {
		throw new CompletionHelperRunnerError("policy", `missing helper-tools extension entrypoint: ${toolExtension}/index.ts`);
	}
	const cliArgs = [
		"--mode",
		"json",
		"-p",
		"--no-session",
		"--no-extensions",
		"--no-builtin-tools",
		"--no-skills",
		"--no-prompt-templates",
		"--no-context-files",
		"-e",
		toolExtension,
		"--append-system-prompt",
		args.promptPath,
		"--tools",
		args.toolAllowlist.join(","),
	];
	if (args.usedModel) cliArgs.push("--model", args.usedModel);
	cliArgs.push(trimmedTask);
	return cliArgs;
}

function getPiInvocation(args: string[]): { command: string; args: string[] } {
	const currentScript = process.argv[1];
	const isBunVirtualScript = currentScript?.startsWith("/$bunfs/root/");
	if (currentScript && !isBunVirtualScript && fs.existsSync(currentScript)) {
		return { command: process.execPath, args: [currentScript, ...args] };
	}
	const execName = path.basename(process.execPath).toLowerCase();
	const isGenericRuntime = /^(node|bun)(\.exe)?$/.test(execName);
	if (!isGenericRuntime) return { command: process.execPath, args };
	return { command: "pi", args };
}

function assistantTextFromMessage(message: JsonRecord): string | undefined {
	if (asString(message.role) !== "assistant") return undefined;
	const content = message.content;
	if (!Array.isArray(content)) return undefined;
	const text = content
		.filter((item): item is JsonRecord => isRecord(item))
		.filter((item) => asString(item.type) === "text")
		.map((item) => asString(item.text) ?? "")
		.join("")
		.trim();
	return text.length > 0 ? text : undefined;
}

function progressEventFromJsonEvent(event: JsonRecord): CompletionHelperProgressEvent | undefined {
	const eventType = asString(event.type);
	if (!eventType) return undefined;
	if (eventType === "tool_execution_start") {
		return {
			kind: "tool",
			message: `tool: ${asString(event.toolName) ?? "tool"}`,
		};
	}
	if (eventType === "tool_execution_update") {
		const partial = isRecord(event.partialResult) ? event.partialResult : undefined;
		const details = isRecord(partial?.details) ? partial?.details : undefined;
		const stage = asString(details?.stage);
		if (stage) return { kind: "stage", message: `stage: ${stage}`, details };
	}
	if (eventType === "message_update" && isRecord(event.message)) {
		const text = assistantTextFromMessage(event.message);
		if (text) return { kind: "stage", message: truncateUtf8(text, 160) };
	}
	return undefined;
}

type HelperSpawnTestOverride = {
	events?: JsonRecord[];
	exitCode?: number;
	stderr?: string;
	assistantText?: string;
	eventLines?: string[];
};

function helperSpawnTestOverride(): HelperSpawnTestOverride | undefined {
	const raw = asString(process.env.PI_COMPLETION_TEST_HELPER_SPAWN_RESULT_JSON);
	if (!raw) return undefined;
	try {
		const parsed = JSON.parse(raw);
		if (!isRecord(parsed)) return undefined;
		return {
			events: Array.isArray(parsed.events) ? parsed.events.filter(isRecord) : undefined,
			exitCode: typeof parsed.exitCode === "number" && Number.isFinite(parsed.exitCode) ? parsed.exitCode : undefined,
			stderr: asString(parsed.stderr),
			assistantText: typeof parsed.assistantText === "string" ? parsed.assistantText : undefined,
			eventLines: Array.isArray(parsed.eventLines)
				? parsed.eventLines.filter((line): line is string => typeof line === "string")
				: undefined,
		};
	} catch {
		return undefined;
	}
}

export async function defaultHelperSubprocessRunner(spec: CompletionHelperSpawnSpec): Promise<CompletionHelperSpawnResult> {
	const testOverride = helperSpawnTestOverride();
	if (testOverride) {
		const eventLines: string[] = [];
		for (const event of testOverride.events ?? []) {
			const rawLine = JSON.stringify(event);
			eventLines.push(rawLine);
			spec.onJsonEvent?.(event, rawLine);
		}
		if (testOverride.eventLines?.length) eventLines.push(...testOverride.eventLines);
		return {
			exitCode: testOverride.exitCode ?? 0,
			stderr: testOverride.stderr,
			assistantText: testOverride.assistantText,
			eventLines,
		};
	}
	return await new Promise<CompletionHelperSpawnResult>((resolve, reject) => {
		const proc = spawn(spec.command, spec.args, {
			cwd: spec.cwd,
			env: spec.env,
			stdio: ["ignore", "pipe", "pipe"],
			shell: false,
		});
		let stderr = "";
		let stdoutBuffer = "";
		const eventLines: string[] = [];
		let assistantText: string | undefined;

		const processLine = (line: string) => {
			if (!line.trim()) return;
			eventLines.push(line);
			try {
				const parsed = JSON.parse(line);
				if (isRecord(parsed)) {
					spec.onJsonEvent?.(parsed, line);
					if (asString(parsed.type) === "message_end" && isRecord(parsed.message)) {
						assistantText = assistantTextFromMessage(parsed.message) ?? assistantText;
					}
				}
			} catch {
				// ignore malformed event lines
			}
		};

		proc.stdout.on("data", (chunk) => {
			stdoutBuffer += chunk.toString();
			const lines = stdoutBuffer.split("\n");
			stdoutBuffer = lines.pop() ?? "";
			for (const line of lines) processLine(line);
		});
		proc.stderr.on("data", (chunk) => {
			stderr += chunk.toString();
		});
		proc.on("error", reject);
		proc.on("close", (code) => {
			if (stdoutBuffer.trim()) processLine(stdoutBuffer);
			resolve({
				exitCode: code ?? 0,
				stderr: stderr.trim() || undefined,
				assistantText,
				eventLines,
			});
		});
		const abort = () => proc.kill("SIGTERM");
		if (spec.signal.aborted) abort();
		else spec.signal.addEventListener("abort", abort, { once: true });
	});
}

async function acquireHelperLock(root: string, artifactDir: string, helper: CompletionHelperName, callerRole: string): Promise<void> {
	const lockDir = helperRunLockDir(root);
	try {
		await fsp.mkdir(lockDir);
	} catch (error: any) {
		if (error?.code === "EEXIST") {
			throw new CompletionHelperRunnerError(
				"policy",
				`another helper is already running for this repo root; stale locks fail closed in V1: ${lockDir}`,
			);
		}
		throw error;
	}
	await writeJsonArtifact(lockDir, "holder.json", {
		helper,
		callerRole,
		artifactDir,
		lockedAt: new Date().toISOString(),
	});
}

async function releaseHelperLock(root: string): Promise<void> {
	await fsp.rm(helperRunLockDir(root), { recursive: true, force: true });
}

function parseStringArrayField(value: unknown, fieldName: string): string[] {
	if (!Array.isArray(value)) {
		throw new CompletionHelperRunnerError("invalid_output", `helper output ${fieldName} must be an array of strings`);
	}
	const normalized: string[] = [];
	for (const item of value) {
		const text = asString(item);
		if (!text) {
			throw new CompletionHelperRunnerError("invalid_output", `helper output ${fieldName} must contain only non-empty strings`);
		}
		normalized.push(text);
	}
	return normalized;
}

export function parseStructuredHelperOutput(rawText: string): StructuredHelperOutput {
	let parsed: unknown;
	try {
		parsed = JSON.parse(rawText);
	} catch (error: any) {
		throw new CompletionHelperRunnerError("invalid_output", `helper output was not valid JSON: ${error?.message ?? error}`);
	}
	if (!isRecord(parsed)) {
		throw new CompletionHelperRunnerError("invalid_output", "helper output must be a JSON object");
	}
	const summary = asString(parsed.summary);
	if (!summary) {
		throw new CompletionHelperRunnerError(
			"invalid_output",
			"helper output must include summary, evidence, paths, and open_questions fields",
		);
	}
	const evidence = parseStringArrayField(parsed.evidence, "evidence");
	const paths = parseStringArrayField(parsed.paths, "paths");
	const openQuestions = parseStringArrayField(parsed.open_questions, "open_questions");
	if (utf8Length(summary) > STRUCTURED_HELPER_OUTPUT_LIMITS.summaryMaxBytes) {
		throw new CompletionHelperRunnerError("invalid_output", "helper output summary exceeded the V1 byte cap");
	}
	if (evidence.length > STRUCTURED_HELPER_OUTPUT_LIMITS.evidenceMaxItems) {
		throw new CompletionHelperRunnerError("invalid_output", "helper output evidence exceeded the V1 item cap");
	}
	if (paths.length > STRUCTURED_HELPER_OUTPUT_LIMITS.pathsMaxItems) {
		throw new CompletionHelperRunnerError("invalid_output", "helper output paths exceeded the V1 item cap");
	}
	if (openQuestions.length > STRUCTURED_HELPER_OUTPUT_LIMITS.openQuestionsMaxItems) {
		throw new CompletionHelperRunnerError("invalid_output", "helper output open_questions exceeded the V1 item cap");
	}
	const normalized: StructuredHelperOutput = {
		summary,
		evidence,
		paths,
		open_questions: openQuestions,
	};
	if (utf8Length(JSON.stringify(normalized)) > STRUCTURED_HELPER_OUTPUT_LIMITS.totalMaxBytes) {
		throw new CompletionHelperRunnerError("invalid_output", "helper output exceeded the V1 serialized JSON byte cap");
	}
	return normalized;
}

function buildFailureResult(args: {
	helper: CompletionHelperName;
	failureKind: CompletionHelperFailureKind;
	message: string;
	artifactDir: string;
	resolvedCwd: string;
	usedModel?: string;
	rawText?: string;
	stderr?: string;
	exitCode?: number;
}): CompletionHelperFailure {
	return {
		ok: false,
		helper: args.helper,
		failureKind: args.failureKind,
		message: args.message,
		artifactDir: args.artifactDir,
		resolvedCwd: args.resolvedCwd,
		usedModel: args.usedModel,
		rawText: args.rawText,
		stderr: args.stderr,
		exitCode: args.exitCode,
	};
}

export function completionAssistFailureContract(args: {
	helper: CompletionHelperName;
	failureKind: CompletionHelperFailureKind | string;
	message: string;
	resolvedCwd: string;
	artifactDir: string;
}) {
	return {
		ok: false,
		helper: args.helper,
		failureKind: args.failureKind,
		message: args.message,
		resolvedCwd: args.resolvedCwd,
		artifactDir: args.artifactDir,
	};
}

export function completionAssistProgressText(helper: CompletionHelperName, event: CompletionHelperProgressEvent): string {
	const message = event.message.trim();
	if (message.startsWith("helper ")) return message;
	return `helper ${helper}: ${message}`;
}

function artifactRelativePath(root: string, targetPath: string): string {
	return normalizePathForOutput(path.relative(root, targetPath));
}

export async function runCompletionHelper(args: RunCompletionHelperArgs): Promise<CompletionHelperResult> {
	let rootRealpath = path.resolve(args.root);
	const runId = args.runId ?? `${args.helper}-${Date.now()}-${randomUUID().slice(0, 8)}`;
	let artifactDir = path.join(helperArtifactsDir(rootRealpath), "_rejected-run-id");
	let resolvedCwd = rootRealpath;
	let usedModel: string | undefined;
	let callerRoleModel: string | undefined;
	let lockHeld = false;
	let timeoutTriggered = false;
	let externalAbortTriggered = false;
	let timer: NodeJS.Timeout | undefined;
	let unlinkAbort: (() => void) | undefined;
	const onProgress = args.onProgress;

	const finalizeFailure = async (failure: CompletionHelperFailure): Promise<CompletionHelperFailure> => {
		emitProgress(onProgress, {
			kind: failure.failureKind === "timeout" ? "timeout" : failure.failureKind === "aborted" ? "aborted" : "failure",
			message: failure.message,
			details: {
				helper: failure.helper,
				artifactDir: failure.artifactDir,
				resolvedCwd: failure.resolvedCwd,
				usedModel: failure.usedModel,
				failureKind: failure.failureKind,
			},
		});
		await tryWriteJsonArtifact(artifactDir, "result.json", failure as unknown as Record<string, unknown>);
		if (failure.rawText) await tryWriteTextArtifact(artifactDir, "assistant-output.txt", failure.rawText);
		if (failure.stderr) await tryWriteTextArtifact(artifactDir, "stderr.txt", failure.stderr);
		return failure;
	};

	try {
		if (!isHelperAllowedForRole(args.callerRole, args.helper)) {
			throw new CompletionHelperRunnerError("policy", `${args.callerRole} may not run helper ${args.helper} in V1`);
		}
		rootRealpath = await resolveRepoRootRealpath(args.root);
		artifactDir = path.join(helperArtifactsDir(rootRealpath), "_rejected-run-id");
		artifactDir = resolveHelperArtifactDir(helperArtifactsDir(rootRealpath), runId);
		resolvedCwd = rootRealpath;
		const helperDefinition = await loadHelperDefinition(args.helper);
		resolvedCwd = await resolveHelperCwd(rootRealpath, args.cwd);
		const modelResolution = await resolveHelperModel({
			helperDefinition,
			callerRole: args.callerRole,
			roleModel: args.roleModel,
		});
		usedModel = modelResolution.usedModel;
		callerRoleModel = modelResolution.callerRoleModel;
		const timeoutMs = clampHelperTimeoutMs(args.helper, args.timeoutMs);
		const artifactsRoot = await ensureHelperArtifactsRoot(rootRealpath);
		artifactDir = resolveHelperArtifactDir(artifactsRoot, runId);
		await fsp.mkdir(artifactDir, { recursive: false });
		const promptPath = path.join(artifactDir, "prompt.md");
		await writeTextArtifact(artifactDir, "prompt.md", helperDefinition.systemPrompt);
		const toolAllowlist = helperToolAllowlist(args.helper);
		const fixedEnv = buildHelperEnvContract({
			helper: args.helper,
			callerRole: args.callerRole,
			rootRealpath,
			resolvedCwd,
			callerRoleModel,
		});
		const helperArgs = buildHelperInvocationArgs({
			helperDefinition,
			promptPath: path.join(artifactDir, "prompt.md"),
			toolAllowlist,
			usedModel,
			task: args.task,
		});
		const invocation = getPiInvocation(helperArgs);
		await writeJsonArtifact(artifactDir, "invocation.json", {
			helper: args.helper,
			callerRole: args.callerRole,
			resolvedCwd,
			usedModel,
			callerRoleModel,
			timeoutMs,
			helperDefinitionPath: artifactRelativePath(PACKAGE_ROOT, helperDefinition.filePath),
			helperToolsExtensionPath: artifactRelativePath(PACKAGE_ROOT, helperToolsExtensionPath()),
			toolAllowlist,
			env: {
				PI_COMPLETION_HELPER: fixedEnv.PI_COMPLETION_HELPER,
				PI_COMPLETION_CALLER_ROLE: fixedEnv.PI_COMPLETION_CALLER_ROLE,
				PI_COMPLETION_HELPER_ROOT: fixedEnv.PI_COMPLETION_HELPER_ROOT,
				PI_COMPLETION_HELPER_CWD: fixedEnv.PI_COMPLETION_HELPER_CWD,
				PI_COMPLETION_ROLE_MODEL: fixedEnv.PI_COMPLETION_ROLE_MODEL ?? null,
			},
			command: invocation.command,
			args: invocation.args,
		});
		await acquireHelperLock(rootRealpath, artifactDir, args.helper, args.callerRole);
		lockHeld = true;
		emitProgress(onProgress, {
			kind: "start",
			message: `starting ${args.helper}`,
			details: {
				artifactDir,
				resolvedCwd,
				usedModel,
			},
		});

		const abortController = new AbortController();
		if (args.signal) {
			const abortFromCaller = () => {
				externalAbortTriggered = true;
				abortController.abort();
			};
			if (args.signal.aborted) abortFromCaller();
			else {
				args.signal.addEventListener("abort", abortFromCaller, { once: true });
				unlinkAbort = () => args.signal?.removeEventListener("abort", abortFromCaller);
			}
		}
		timer = setTimeout(() => {
			timeoutTriggered = true;
			abortController.abort();
		}, timeoutMs);
		const subprocessRunner = args.subprocessRunner ?? defaultHelperSubprocessRunner;
		const spawnResult = await subprocessRunner({
			command: invocation.command,
			args: invocation.args,
			cwd: resolvedCwd,
			env: fixedEnv,
			signal: abortController.signal,
			onJsonEvent: (event, rawLine) => {
				const progressEvent = progressEventFromJsonEvent(event);
				if (progressEvent) emitProgress(onProgress, progressEvent);
				void rawLine;
			},
		});
		if (timer) clearTimeout(timer);
		timer = undefined;
		unlinkAbort?.();
		unlinkAbort = undefined;
		await writeTextArtifact(artifactDir, "events.jsonl", `${spawnResult.eventLines.join("\n")}${spawnResult.eventLines.length ? "\n" : ""}`);
		if (spawnResult.stderr) await writeTextArtifact(artifactDir, "stderr.txt", spawnResult.stderr);
		if (spawnResult.assistantText) await writeTextArtifact(artifactDir, "assistant-output.txt", spawnResult.assistantText);

		if (timeoutTriggered) {
			throw new CompletionHelperRunnerError(
				"timeout",
				`helper timed out after ${timeoutMs}ms`,
				{ rawText: spawnResult.assistantText, stderr: spawnResult.stderr, exitCode: spawnResult.exitCode },
			);
		}
		if (externalAbortTriggered) {
			throw new CompletionHelperRunnerError(
				"aborted",
				"helper execution was aborted",
				{ rawText: spawnResult.assistantText, stderr: spawnResult.stderr, exitCode: spawnResult.exitCode },
			);
		}
		if (spawnResult.exitCode !== 0) {
			throw new CompletionHelperRunnerError(
				"process_error",
				`helper subprocess exited with code ${spawnResult.exitCode}`,
				{ rawText: spawnResult.assistantText, stderr: spawnResult.stderr, exitCode: spawnResult.exitCode },
			);
		}
		const output = parseStructuredHelperOutput(spawnResult.assistantText ?? "");
		const result: CompletionHelperResult = {
			ok: true,
			helper: args.helper,
			output,
			rawText: spawnResult.assistantText,
			stderr: spawnResult.stderr,
			artifactDir,
			resolvedCwd,
			usedModel,
			exitCode: spawnResult.exitCode,
		};
		await writeJsonArtifact(artifactDir, "result.json", result as unknown as Record<string, unknown>);
		emitProgress(onProgress, {
			kind: "result",
			message: `${args.helper} completed`,
			details: {
				artifactDir,
				resolvedCwd,
				usedModel,
			},
		});
		return result;
	} catch (error: any) {
		if (timer) clearTimeout(timer);
		timer = undefined;
		unlinkAbort?.();
		unlinkAbort = undefined;
		if (error instanceof CompletionHelperRunnerError) {
			return await finalizeFailure(buildFailureResult({
				helper: args.helper,
				failureKind: error.failureKind,
				message: error.message,
				artifactDir,
				resolvedCwd,
				usedModel,
				rawText: error.rawText,
				stderr: error.stderr,
				exitCode: error.exitCode,
			}));
		}
		const failureKind: CompletionHelperFailureKind = timeoutTriggered
			? "timeout"
			: externalAbortTriggered || args.signal?.aborted
				? "aborted"
				: "process_error";
		const message = failureKind === "timeout"
			? `helper timed out after ${clampHelperTimeoutMs(args.helper, args.timeoutMs)}ms`
			: failureKind === "aborted"
				? "helper execution was aborted"
				: `helper subprocess failed: ${error?.message ?? error}`;
		return await finalizeFailure(buildFailureResult({
			helper: args.helper,
			failureKind,
			message,
			artifactDir,
			resolvedCwd,
			usedModel,
			stderr: asString(error?.stderr),
		}));
	} finally {
		if (lockHeld) await releaseHelperLock(rootRealpath);
	}
}

export async function runCompletionAssistTool(args: {
	root: string;
	helper: CompletionHelperName;
	callerRole?: string;
	task: string;
	cwd?: string;
	timeoutMs?: number;
	signal?: AbortSignal;
	roleModel?: string;
	onUpdate?: (partialResult: { content: Array<{ type: "text"; text: string }>; details: Record<string, unknown> }) => void;
}): Promise<{ content: Array<{ type: "text"; text: string }>; details: CompletionHelperResult | ReturnType<typeof completionAssistFailureContract>; isError: boolean }> {
	const callerRole = asString(args.callerRole);
	const runRoot = path.resolve(args.root);
	if (!callerRole) {
		const failure = completionAssistFailureContract({
			helper: args.helper,
			failureKind: "policy",
			message: "completion_assist may only be used from an active completion role inside /cook.",
			resolvedCwd: runRoot,
			artifactDir: path.join(runRoot, ".agent", "current", "tmp", "helpers", "_rejected-role"),
		});
		return {
			content: [{ type: "text", text: JSON.stringify(failure) }],
			details: failure,
			isError: true,
		};
	}
	const result = await runCompletionHelper({
		root: runRoot,
		helper: args.helper,
		callerRole,
		task: args.task,
		cwd: args.cwd,
		timeoutMs: args.timeoutMs,
		roleModel: args.roleModel,
		signal: args.signal,
		onProgress: (event) => {
			const line = completionAssistProgressText(args.helper, event);
			args.onUpdate?.({
				content: [{ type: "text", text: line }],
				details: {
					...(event.details ?? {}),
					helper: args.helper,
					kind: event.kind,
					stage: line,
					message: line,
				},
			});
		},
	});
	if (result.ok) {
		return {
			content: [{ type: "text", text: JSON.stringify(result.output) }],
			details: result,
			isError: false,
		};
	}
	const failure = completionAssistFailureContract({
		helper: result.helper,
		failureKind: result.failureKind,
		message: result.message,
		resolvedCwd: result.resolvedCwd,
		artifactDir: result.artifactDir,
	});
	return {
		content: [{ type: "text", text: JSON.stringify(failure) }],
		details: result,
		isError: true,
	};
}
