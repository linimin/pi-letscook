import {
	type CompletionHelperName,
	type CompletionHelperPolicy,
	type HelperProxyToolName,
	HELPER_PROXY_TOOL_NAMES,
} from "./helper-types.ts";

const HELPER_ALLOWED_CALLER_ROLES: Record<CompletionHelperName, string[]> = {
	scout: ["completion-implementer", "completion-regrounder"],
	critic: ["completion-implementer", "completion-regrounder"],
};

const HELPER_TIMEOUTS: Record<CompletionHelperName, { defaultTimeoutMs: number; maxTimeoutMs: number }> = {
	scout: { defaultTimeoutMs: 60_000, maxTimeoutMs: 120_000 },
	critic: { defaultTimeoutMs: 90_000, maxTimeoutMs: 180_000 },
};

const HELPER_TOOL_ALLOWLIST: Record<CompletionHelperName, HelperProxyToolName[]> = {
	scout: [...HELPER_PROXY_TOOL_NAMES],
	critic: [...HELPER_PROXY_TOOL_NAMES],
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

export function helperToolAllowlist(helper: CompletionHelperName): HelperProxyToolName[] {
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
