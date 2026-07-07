import type { AgentDefinition, CompletionRole } from "./types";

export type RoleBackendKind = "pi" | "cursor-sdk" | "cursor-cli-ask";

function asString(value: unknown): string | undefined {
	return typeof value === "string" && value.trim().length > 0 ? value.trim() : undefined;
}

function truthyEnv(name: string): boolean {
	const raw = asString(process.env[name]);
	return raw === "1" || raw?.toLowerCase() === "true" || raw?.toLowerCase() === "yes";
}

function parseRoleList(raw: string | undefined, fallback: CompletionRole[]): CompletionRole[] {
	if (!raw) return fallback;
	return raw
		.split(",")
		.map((item) => item.trim())
		.filter(Boolean) as CompletionRole[];
}

const DEFAULT_CURSOR_SDK_ROLES: CompletionRole[] = ["completion-implementer"];
const DEFAULT_CURSOR_CLI_ASK_ROLES: CompletionRole[] = [
	"completion-reviewer",
	"completion-auditor",
	"completion-stop-judge",
];

export function isCursorBackendEnabled(): boolean {
	return truthyEnv("PI_COMPLETION_CURSOR_ENABLED");
}

export function resolveCursorApiKey(): string | undefined {
	return asString(process.env.PI_COMPLETION_CURSOR_API_KEY) ?? asString(process.env.CURSOR_API_KEY);
}

export function resolveCursorCliBinary(): string {
	return asString(process.env.PI_COMPLETION_CURSOR_CLI) ?? "agent";
}

function roleEnvSuffix(role: CompletionRole): string {
	return role.replace(/^completion-/, "").replace(/-/g, "_").toUpperCase();
}

export function resolveCursorModel(role: CompletionRole, agent?: Pick<AgentDefinition, "cursorModel">): string {
	const perRole = asString(process.env[`PI_COMPLETION_CURSOR_MODEL_${roleEnvSuffix(role)}`]);
	if (perRole) return perRole;
	if (agent?.cursorModel) return agent.cursorModel;
	return asString(process.env.PI_COMPLETION_CURSOR_MODEL) ?? "composer-2.5";
}

function backendFromAgent(agent?: Pick<AgentDefinition, "roleBackend">): RoleBackendKind | undefined {
	const raw = agent?.roleBackend?.trim().toLowerCase();
	if (raw === "pi" || raw === "cursor-sdk" || raw === "cursor-cli-ask") return raw;
	return undefined;
}

export function resolveRoleBackend(role: CompletionRole, agent?: Pick<AgentDefinition, "roleBackend">): RoleBackendKind {
	if (!isCursorBackendEnabled()) return "pi";
	const agentBackend = backendFromAgent(agent);
	if (agentBackend) return agentBackend;
	const sdkRoles = parseRoleList(process.env.PI_COMPLETION_CURSOR_SDK_ROLES, DEFAULT_CURSOR_SDK_ROLES);
	if (sdkRoles.includes(role)) return "cursor-sdk";
	const cliRoles = parseRoleList(process.env.PI_COMPLETION_CURSOR_CLI_ASK_ROLES, DEFAULT_CURSOR_CLI_ASK_ROLES);
	if (cliRoles.includes(role)) return "cursor-cli-ask";
	return "pi";
}

export function requireCursorApiKey(): string {
	const apiKey = resolveCursorApiKey();
	if (!apiKey) {
		throw new Error(
			"PI_COMPLETION_CURSOR_ENABLED requires CURSOR_API_KEY or PI_COMPLETION_CURSOR_API_KEY to be set.",
		);
	}
	return apiKey;
}
