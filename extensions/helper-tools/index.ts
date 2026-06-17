import { createHash } from "node:crypto";
import * as fs from "node:fs";
import * as path from "node:path";
import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";
import { Type } from "typebox";
import { buildHelperProxyToolDefinitions } from "../completion/helper-proxy-tools.ts";

type JsonRecord = Record<string, unknown>;

type HelperAssetReport = {
	relativePath: string;
	absolutePath: string;
	exists: boolean;
	size: number | null;
	sha256: string | null;
};

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
const EXTENSION_DIR = path.join(PACKAGE_ROOT, "extensions", "helper-tools");
const PACKAGE_JSON_PATH = path.join(PACKAGE_ROOT, "package.json");
const HELPER_ASSET_PATHS = {
	scout: path.join(PACKAGE_ROOT, "helpers", "scout.md"),
	critic: path.join(PACKAGE_ROOT, "helpers", "critic.md"),
} as const;
const PROBE_TOOL = "completion_helper_capability_probe";

function asString(value: unknown): string | null {
	return typeof value === "string" && value.trim().length > 0 ? value.trim() : null;
}

function parsePackageMeta(): JsonRecord {
	if (!fs.existsSync(PACKAGE_JSON_PATH)) return {};
	try {
		const raw = fs.readFileSync(PACKAGE_JSON_PATH, "utf8");
		const parsed = JSON.parse(raw);
		return typeof parsed === "object" && parsed !== null && !Array.isArray(parsed) ? (parsed as JsonRecord) : {};
	} catch {
		return {};
	}
}

function sha256ForFile(filePath: string): string | null {
	try {
		const data = fs.readFileSync(filePath);
		return createHash("sha256").update(data).digest("hex");
	} catch {
		return null;
	}
}

function inspectHelperAsset(filePath: string): HelperAssetReport {
	const relativePath = path.relative(PACKAGE_ROOT, filePath) || path.basename(filePath);
	if (!fs.existsSync(filePath)) {
		return {
			relativePath,
			absolutePath: filePath,
			exists: false,
			size: null,
			sha256: null,
		};
	}
	const stat = fs.statSync(filePath);
	return {
		relativePath,
		absolutePath: filePath,
		exists: true,
		size: stat.size,
		sha256: sha256ForFile(filePath),
	};
}

function optionValues(longFlag: string, shortFlag?: string): string[] {
	const values: string[] = [];
	for (let index = 0; index < process.argv.length; index += 1) {
		const value = process.argv[index];
		if (value !== longFlag && (!shortFlag || value !== shortFlag)) continue;
		const next = process.argv[index + 1];
		if (typeof next === "string" && next.length > 0) values.push(next);
	}
	return values;
}

function hasFlag(longFlag: string, shortFlag?: string): boolean {
	return process.argv.includes(longFlag) || (shortFlag ? process.argv.includes(shortFlag) : false);
}

function currentMode(): string | null {
	const explicit = optionValues("--mode")[0];
	if (explicit) return explicit;
	if (hasFlag("--print", "-p")) return "print";
	return null;
}

export default function helperToolsExtension(pi: ExtensionAPI) {
	pi.registerTool({
		name: PROBE_TOOL,
		label: "Completion Helper Capability Probe",
		description: "Internal helper-runtime capability probe for packaged release verification.",
		promptSnippet: "Internal probe for packaged helper extension loading and JSON-mode capability checks.",
		promptGuidelines: [
			"Use completion_helper_capability_probe only when an explicit helper-runtime capability test asks for packaged helper extension proof.",
			"After calling completion_helper_capability_probe, return exactly the JSON object from the tool result and nothing else.",
		],
		parameters: Type.Object({}),
		async execute(_toolCallId, _params, _signal, onUpdate, ctx) {
			const packageMeta = parsePackageMeta();
			const helperAssets = {
				scout: inspectHelperAsset(HELPER_ASSET_PATHS.scout),
				critic: inspectHelperAsset(HELPER_ASSET_PATHS.critic),
			};
			const extensionArgs = optionValues("--extension", "-e");
			const toolsArg = optionValues("--tools", "-t")[0] ?? null;
			const payload = {
				ok: true,
				probe: PROBE_TOOL,
				mode: ctx.mode,
				cwd: ctx.cwd,
				packageName: asString(packageMeta.name),
				packageVersion: asString(packageMeta.version),
				packageRoot: PACKAGE_ROOT,
				extensionDir: EXTENSION_DIR,
				packageJsonPath: PACKAGE_JSON_PATH,
				argv: process.argv.slice(1),
				extensionArgs,
				toolsArg,
				observedFlags: {
					modeJson: currentMode() === "json",
					noExtensions: hasFlag("--no-extensions", "-ne"),
					noBuiltinTools: hasFlag("--no-builtin-tools", "-nbt"),
					noSkills: hasFlag("--no-skills", "-ns"),
					noPromptTemplates: hasFlag("--no-prompt-templates", "-np"),
					noContextFiles: hasFlag("--no-context-files", "-nc"),
					noSession: hasFlag("--no-session"),
					printMode: hasFlag("--print", "-p"),
				},
				helperAssets,
				env: {
					PI_COMPLETION_HELPER: process.env.PI_COMPLETION_HELPER ?? null,
					PI_COMPLETION_CALLER_ROLE: process.env.PI_COMPLETION_CALLER_ROLE ?? null,
					PI_COMPLETION_HELPER_ROOT: process.env.PI_COMPLETION_HELPER_ROOT ?? null,
					PI_COMPLETION_HELPER_CWD: process.env.PI_COMPLETION_HELPER_CWD ?? null,
					PI_COMPLETION_ROLE_MODEL: process.env.PI_COMPLETION_ROLE_MODEL ?? null,
				},
			};

			onUpdate?.({
				content: [{ type: "text", text: "probe: loaded packaged helper-tools extension" }],
				details: {
					stage: "loaded-extension",
					packageRoot: PACKAGE_ROOT,
					extensionDir: EXTENSION_DIR,
				},
			});
			await new Promise((resolve) => setTimeout(resolve, 5));
			onUpdate?.({
				content: [{ type: "text", text: "probe: verified packaged helper assets" }],
				details: {
					stage: "verified-assets",
					helperAssets,
				},
			});
			return {
				content: [{ type: "text", text: JSON.stringify(payload) }],
				details: payload,
			};
		},
	});

	for (const tool of buildHelperProxyToolDefinitions(Type)) {
		pi.registerTool(tool as any);
	}
}
