import {
	HELPER_EMIT_CRITIC_TOOL,
	HELPER_EMIT_SCOUT_TOOL,
} from "./structured-contracts.ts";
import {
	type CompletionHelperName,
	type CompletionHelperPolicy,
	HELPER_PROXY_TOOL_NAMES,
} from "./helper-types.ts";

export const COMPLETION_ASSIST_TOOL_NAME = "completion_assist";

const HELPER_ALLOWED_CALLER_ROLES: Record<CompletionHelperName, string[]> = {
	scout: ["completion-implementer", "completion-regrounder"],
	critic: ["completion-implementer", "completion-regrounder"],
};

const HELPER_TIMEOUTS: Record<CompletionHelperName, { defaultTimeoutMs: number; maxTimeoutMs: number }> = {
	scout: { defaultTimeoutMs: 60_000, maxTimeoutMs: 120_000 },
	critic: { defaultTimeoutMs: 90_000, maxTimeoutMs: 180_000 },
};

const HELPER_EMIT_TOOLS: Record<CompletionHelperName, string> = {
	scout: HELPER_EMIT_SCOUT_TOOL,
	critic: HELPER_EMIT_CRITIC_TOOL,
};

const HELPER_TOOL_ALLOWLIST: Record<CompletionHelperName, string[]> = {
	scout: [...HELPER_PROXY_TOOL_NAMES, HELPER_EMIT_SCOUT_TOOL],
	critic: [...HELPER_PROXY_TOOL_NAMES, HELPER_EMIT_CRITIC_TOOL],
};

export function allowedHelpersForRole(role: string | undefined): CompletionHelperName[] {
	if (!role) return [];
	const helpers = Object.entries(HELPER_ALLOWED_CALLER_ROLES)
		.filter(([, roles]) => roles.includes(role))
		.map(([helper]) => helper as CompletionHelperName);
	return helpers.sort();
}

export function isHelperAllowedForRole(role: string | undefined, helper: CompletionHelperName): boolean {
	return Boolean(role && HELPER_ALLOWED_CALLER_ROLES[helper].includes(role));
}

export function canRoleUseCompletionAssist(role: string | undefined): boolean {
	return allowedHelpersForRole(role).length > 0;
}

function normalizedDeclaredTools(declaredTools?: string[]): string[] {
	return (declaredTools ?? []).map((tool) => (typeof tool === "string" ? tool.trim() : "")).filter(Boolean);
}

export function effectiveRoleToolAllowlist(role: string | undefined, declaredTools?: string[]): string[] | undefined {
	if (declaredTools === undefined) return undefined;
	const unique = new Set(normalizedDeclaredTools(declaredTools));
	if (canRoleUseCompletionAssist(role)) unique.add(COMPLETION_ASSIST_TOOL_NAME);
	else unique.delete(COMPLETION_ASSIST_TOOL_NAME);
	return unique.size > 0 ? Array.from(unique) : undefined;
}

export function resolveEffectiveCompletionRoleModel(pinnedModel?: string, requestedModel?: string): string | undefined {
	const normalizedPinned = typeof pinnedModel === "string" && pinnedModel.trim().length > 0 ? pinnedModel.trim() : undefined;
	if (normalizedPinned) return normalizedPinned;
	return typeof requestedModel === "string" && requestedModel.trim().length > 0 ? requestedModel.trim() : undefined;
}

export function buildCompletionRoleSubprocessEnv(role: string, roleModel?: string): NodeJS.ProcessEnv {
	const env: NodeJS.ProcessEnv = { ...process.env, PI_COMPLETION_ROLE: role };
	delete env.PI_COMPLETION_HELPER;
	delete env.PI_COMPLETION_CALLER_ROLE;
	delete env.PI_COMPLETION_HELPER_ROOT;
	delete env.PI_COMPLETION_HELPER_CWD;
	if (typeof roleModel === "string" && roleModel.trim().length > 0) env.PI_COMPLETION_ROLE_MODEL = roleModel.trim();
	else delete env.PI_COMPLETION_ROLE_MODEL;
	return env;
}

export function helperDefaultTimeoutMs(helper: CompletionHelperName): number {
	return HELPER_TIMEOUTS[helper].defaultTimeoutMs;
}

export function helperMaxTimeoutMs(helper: CompletionHelperName): number {
	return HELPER_TIMEOUTS[helper].maxTimeoutMs;
}

export function clampHelperTimeoutMs(helper: CompletionHelperName, requestedTimeoutMs?: number): number {
	const defaultTimeout = helperDefaultTimeoutMs(helper);
	const maxTimeout = helperMaxTimeoutMs(helper);
	if (typeof requestedTimeoutMs !== "number" || !Number.isFinite(requestedTimeoutMs)) return defaultTimeout;
	const rounded = Math.max(1, Math.floor(requestedTimeoutMs));
	return Math.min(rounded, maxTimeout);
}

export function helperEmitToolName(helper: CompletionHelperName): string {
	return HELPER_EMIT_TOOLS[helper];
}

export function helperToolAllowlist(helper: CompletionHelperName): string[] {
	return [...HELPER_TOOL_ALLOWLIST[helper]];
}

export function helperPolicy(helper: CompletionHelperName): CompletionHelperPolicy {
	return {
		readonly: true,
		allowedCallerRoles: [...HELPER_ALLOWED_CALLER_ROLES[helper]],
		toolAllowlist: helperToolAllowlist(helper),
		defaultTimeoutMs: helperDefaultTimeoutMs(helper),
		maxTimeoutMs: helperMaxTimeoutMs(helper),
	};
}
