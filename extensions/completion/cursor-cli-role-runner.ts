import { spawn, spawnSync } from "node:child_process";
import { promises as fsp } from "node:fs";
import * as path from "node:path";
import type { LiveRoleActivity } from "./types";
import { requireCursorApiKey, resolveCursorCliBinary, resolveCursorModel } from "./cursor-role-config.ts";
import type { CompletionRole } from "./types";

export type CursorCliRoleAttemptArgs = {
	root: string;
	role: CompletionRole;
	combinedPrompt: string;
	cursorModel?: string;
	signal?: AbortSignal;
	onUpdate?: (activity: LiveRoleActivity) => void;
};

export type CursorCliRoleAttemptResult = {
	exitCode: number;
	assistantText?: string;
	stderr?: string;
};

function asString(value: unknown): string | undefined {
	return typeof value === "string" && value.trim().length > 0 ? value.trim() : undefined;
}

function isRecord(value: unknown): value is Record<string, unknown> {
	return typeof value === "object" && value !== null && !Array.isArray(value);
}

function workspaceRelativeAtReference(root: string, filePath: string): string {
	const relative = path.relative(root, filePath);
	const posixRelative = relative.split(path.sep).join("/");
	return `@${posixRelative}`;
}

async function writeCursorCliRolePromptFile(
	root: string,
	role: CompletionRole,
	content: string,
): Promise<{ promptPath: string; cleanupPath: string }> {
	const promptDir = path.join(root, ".agent", "tmp", "cursor-cli-role");
	await fsp.mkdir(promptDir, { recursive: true });
	const promptPath = path.join(promptDir, `${role}-${process.pid}-${Date.now()}.md`);
	await fsp.writeFile(promptPath, content, { encoding: "utf8", mode: 0o600 });
	return { promptPath, cleanupPath: promptPath };
}

function extractTextFromContentBlocks(content: unknown): string | undefined {
	if (!Array.isArray(content)) return undefined;
	const parts: string[] = [];
	for (const block of content) {
		if (!isRecord(block)) continue;
		if (block.type === "text" && typeof block.text === "string" && block.text.trim()) {
			parts.push(block.text.trim());
		}
	}
	const joined = parts.join("\n").trim();
	return joined.length > 0 ? joined : undefined;
}

function extractTextFromParsedJson(parsed: unknown): string | undefined {
	if (typeof parsed === "string") return parsed;
	if (!isRecord(parsed)) return undefined;

	const direct =
		asString(parsed.result) ??
		asString(parsed.text) ??
		asString(parsed.output) ??
		(isRecord(parsed.message) ? asString(parsed.message.content) ?? extractTextFromContentBlocks(parsed.message.content) : undefined);
	if (direct) return direct;

	const eventType = asString(parsed.type);
	if (eventType === "assistant" && isRecord(parsed.message)) {
		const fromMessage =
			asString(parsed.message.content) ?? extractTextFromContentBlocks(parsed.message.content);
		if (fromMessage) return fromMessage;
	}
	if (eventType === "result") {
		return asString(parsed.result) ?? extractTextFromParsedJson(parsed.data);
	}
	if (isRecord(parsed.data)) {
		const fromData = extractTextFromParsedJson(parsed.data);
		if (fromData) return fromData;
	}

	return undefined;
}

export function parseCursorCliJsonOutput(stdout: string): string | undefined {
	const trimmed = stdout.trim();
	if (!trimmed) return undefined;

	try {
		const fromParsed = extractTextFromParsedJson(JSON.parse(trimmed));
		if (fromParsed) return fromParsed;
	} catch {
		// try NDJSON / stream-json lines below
	}

	const lines = trimmed.split("\n").map((line) => line.trim()).filter(Boolean);
	let lastAssistantText: string | undefined;
	for (const line of lines) {
		try {
			const text = extractTextFromParsedJson(JSON.parse(line));
			if (text) lastAssistantText = text;
		} catch {
			// ignore malformed line
		}
	}
	if (lastAssistantText) return lastAssistantText;

	return undefined;
}

export function finalizeCursorCliRoleAttemptResult(args: {
	exitCode: number;
	stdout: string;
	stderr?: string;
}): CursorCliRoleAttemptResult {
	const assistantText = parseCursorCliJsonOutput(args.stdout);
	const parseFailure =
		!assistantText && args.stdout.trim()
			? "Cursor CLI stdout was present but did not contain a parseable JSON assistant result."
			: undefined;
	const missingResult =
		!assistantText && !args.stdout.trim() ? "Cursor CLI produced no assistant output." : undefined;
	let exitCode = args.exitCode;
	if (parseFailure || missingResult) exitCode = 1;
	const stderr = [args.stderr?.trim(), parseFailure, missingResult].filter(Boolean).join("\n") || undefined;
	return { exitCode, assistantText, stderr };
}

export function assertCursorCliAvailable(cli: string): void {
	const probe = spawnSync(cli, ["--version"], { encoding: "utf8" });
	if (probe.error || probe.status !== 0) {
		const detail = probe.error?.message ?? probe.stderr?.trim() ?? probe.stdout?.trim() ?? `exit ${probe.status ?? "unknown"}`;
		throw new Error(
			`Cursor CLI not available: ${cli} (${detail}). Install Cursor CLI and ensure it is on PATH, or set PI_COMPLETION_CURSOR_CLI.`,
		);
	}
}

export async function runCursorCliAskRoleAttempt(args: CursorCliRoleAttemptArgs): Promise<CursorCliRoleAttemptResult> {
	let apiKey: string;
	try {
		apiKey = requireCursorApiKey();
	} catch (error) {
		const message = error instanceof Error ? error.message : String(error);
		return { exitCode: 1, stderr: message };
	}

	const cli = resolveCursorCliBinary();
	try {
		assertCursorCliAvailable(cli);
	} catch (error) {
		const message = error instanceof Error ? error.message : String(error);
		return { exitCode: 1, stderr: message };
	}

	const modelId = args.cursorModel ?? resolveCursorModel(args.role);
	args.onUpdate?.({
		role: args.role,
		status: "running",
		currentAction: `Running ${args.role} via Cursor CLI ask mode`,
		toolRecentActivity: [],
		recentActivity: [],
		stateDeltas: [],
		startedAt: Date.now(),
		updatedAt: Date.now(),
	});

	const { promptPath, cleanupPath } = await writeCursorCliRolePromptFile(args.root, args.role, args.combinedPrompt);
	const promptReference = workspaceRelativeAtReference(args.root, promptPath);

	const cliArgs = [
		"--mode",
		"ask",
		"-p",
		"--output-format",
		"json",
		"--workspace",
		args.root,
		"--model",
		modelId,
		"--trust",
		promptReference,
	];

	try {
		const result = await new Promise<CursorCliRoleAttemptResult>((resolve) => {
			const proc = spawn(cli, cliArgs, {
				cwd: args.root,
				env: {
					...process.env,
					CURSOR_API_KEY: apiKey,
					PI_COMPLETION_ROLE: args.role,
				},
				stdio: ["ignore", "pipe", "pipe"],
				shell: false,
			});
			let stdout = "";
			let stderr = "";
			proc.stdout.on("data", (chunk) => {
				stdout += chunk.toString();
			});
			proc.stderr.on("data", (chunk) => {
				stderr += chunk.toString();
			});
			proc.on("close", (code) => {
				resolve(
					finalizeCursorCliRoleAttemptResult({
						exitCode: code ?? 0,
						stdout,
						stderr: stderr.trim() || undefined,
					}),
				);
			});
			proc.on("error", (error) => {
				resolve({
					exitCode: 1,
					stderr: `Failed to spawn ${cli}: ${error.message}`,
				});
			});
			if (args.signal) {
				const abort = () => proc.kill("SIGTERM");
				if (args.signal.aborted) abort();
				else args.signal.addEventListener("abort", abort, { once: true });
			}
		});
		return result;
	} finally {
		await fsp.rm(cleanupPath, { force: true });
	}
}
