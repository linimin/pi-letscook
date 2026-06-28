import { promises as fsp } from "node:fs";
import * as path from "node:path";
import {
	asNumber,
	asString,
	asStringArray,
	completionRootKey,
	isRecord,
	loadCompletionSnapshot,
} from "./state-store.ts";
import type { CompletionStatusSurface, CompletionStateSnapshot, JsonRecord, LiveRoleActivity } from "./types.ts";

export const LIVE_ROLE_WAITING_MS = 15_000;
export const LIVE_ROLE_STALLED_MS = 45_000;

type LiveActivitySignal = {
	state: "active" | "waiting" | "stalled";
	idleMs: number;
};

export type RoleMessage = {
	role: string;
	content: Array<{ type: string; text?: string }>;
};

function formatCount(count: number, singular: string, plural = `${singular}s`): string {
	return `${count} ${count === 1 ? singular : plural}`;
}

function completionRemainingSummary(surface: {
	remainingContractCount: number;
	releaseBlockerCount: number;
	highValueGapCount: number;
	remainingStopJudgeCount: number;
}): string {
	return [
		formatCount(surface.remainingContractCount, "contract"),
		formatCount(surface.releaseBlockerCount, "blocker"),
		formatCount(surface.highValueGapCount, "gap"),
		formatCount(surface.remainingStopJudgeCount, "stop judge", "stop judges"),
	].join(" · ");
}

function envNumber(name: string): number | undefined {
	const raw = asString(process.env[name]);
	if (!raw) return undefined;
	const parsed = Number(raw);
	return Number.isFinite(parsed) ? parsed : undefined;
}

export function nowMs(): number {
	return envNumber("PI_COMPLETION_TEST_NOW") ?? Date.now();
}

export function formatElapsed(ms: number | undefined): string {
	if (!ms || ms < 0) return "00:00";
	const totalSeconds = Math.floor(ms / 1000);
	const hours = Math.floor(totalSeconds / 3600);
	const minutes = Math.floor((totalSeconds % 3600) / 60);
	const seconds = totalSeconds % 60;
	if (hours > 0) return `${String(hours).padStart(2, "0")}:${String(minutes).padStart(2, "0")}:${String(seconds).padStart(2, "0")}`;
	return `${String(minutes).padStart(2, "0")}:${String(seconds).padStart(2, "0")}`;
}

export function truncateInline(text: string, maxLength = 120): string {
	const singleLine = text.replace(/\s+/g, " ").trim();
	return singleLine.length > maxLength ? `${singleLine.slice(0, maxLength - 3)}...` : singleLine;
}

function formatToolActivity(toolName: string, args: JsonRecord): string {
	if (toolName === "bash") return `$ ${truncateInline(asString(args.command) ?? "...")}`;
	if (toolName === "read") return `read ${asString(args.filePath) ?? asString(args.path) ?? "..."}`;
	if (toolName === "write") return `write ${asString(args.filePath) ?? asString(args.path) ?? "..."}`;
	if (toolName === "edit") return `edit ${asString(args.filePath) ?? asString(args.path) ?? "..."}`;
	if (toolName === "grep") return `grep ${asString(args.pattern) ?? "..."}`;
	if (toolName === "find") return `find ${asString(args.pattern) ?? "..."}`;
	if (toolName === "ls") return `ls ${asString(args.path) ?? "."}`;
	if (toolName === "completion_assist") {
		const helper = asString(args.helper) ?? "helper";
		const task = truncateInline(asString(args.task) ?? "", 80);
		return task ? `helper ${helper}: ${task}` : `helper ${helper}`;
	}
	return `${toolName} ${truncateInline(JSON.stringify(args))}`;
}

export function pushRecentActivity(items: string[], line: string, maxItems = 8): string[] {
	const normalized = truncateInline(line, 160);
	if (!normalized) return items;
	if (items[items.length - 1] === normalized) return items;
	const next = [...items, normalized];
	return next.slice(-maxItems);
}

function collapseRecentActivity(items: string[], maxItems = 4): string[] {
	const collapsed: string[] = [];
	for (const rawItem of items) {
		const item = truncateInline(rawItem, 120);
		if (!item || item.startsWith("done ") || item.startsWith("result ")) continue;
		if (item.startsWith("assistant:")) continue;
		if (collapsed[collapsed.length - 1] === item) continue;
		collapsed.push(item);
	}
	return collapsed.slice(-maxItems);
}

function liveActivitySignal(activity: { status?: string; startedAt?: number; updatedAt?: number } | undefined): LiveActivitySignal | undefined {
	if (!activity || activity.status !== "running") return undefined;
	const anchor = activity.updatedAt ?? activity.startedAt;
	if (anchor === undefined) return undefined;
	const idleMs = Math.max(0, nowMs() - anchor);
	return {
		state: idleMs >= LIVE_ROLE_STALLED_MS ? "stalled" : idleMs >= LIVE_ROLE_WAITING_MS ? "waiting" : "active",
		idleMs,
	};
}

function livePreviewForStatus(activity: LiveRoleActivity | undefined): string | undefined {
	if (!activity || activity.status !== "running") return undefined;
	return truncateInline(
		activity.progress ?? activity.verifying ?? activity.toolActivity ?? activity.assistantSummary ?? activity.currentAction ?? activity.lastAssistantText ?? "",
		120,
	) || undefined;
}

export function cloneLiveRoleActivity(activity: LiveRoleActivity, overrides: Partial<LiveRoleActivity> = {}): LiveRoleActivity {
	return {
		...activity,
		...overrides,
		toolRecentActivity: [...(overrides.toolRecentActivity ?? activity.toolRecentActivity)],
		recentActivity: [...(overrides.recentActivity ?? activity.recentActivity)],
		stateDeltas: [...(overrides.stateDeltas ?? activity.stateDeltas)],
	};
}

export function createLiveRoleActivity(role: string, startedAt = nowMs()): LiveRoleActivity {
	const currentAction = "Starting role subprocess";
	return {
		role,
		status: "running",
		currentAction,
		toolActivity: currentAction,
		toolRecentActivity: [currentAction],
		recentActivity: [currentAction],
		stateDeltas: [],
		startedAt,
		updatedAt: startedAt,
	};
}

function activityTimestampMs(event: JsonRecord | undefined): number | undefined {
	return asNumber(event?.updatedAt) ?? asNumber(event?.timestampMs) ?? asNumber(event?.timestamp) ?? asNumber(event?.at);
}

function asRoleMessage(value: unknown): RoleMessage | undefined {
	if (!isRecord(value)) return undefined;
	const role = asString(value.role);
	const content = Array.isArray(value.content)
		? value.content.flatMap((item) => {
				if (!isRecord(item)) return [];
				const type = asString(item.type);
				if (!type) return [];
				return [{ type, text: asString(item.text) }];
		  })
		: [];
	if (!role) return undefined;
	return { role, content };
}

function parseStructuredProgress(text: string): {
	progress?: string;
	rationale?: string;
	nextStep?: string;
	verifying?: string;
	stateDeltas: string[];
} {
	const result: { progress?: string; rationale?: string; nextStep?: string; verifying?: string; stateDeltas: string[] } = {
		stateDeltas: [],
	};
	for (const rawLine of text.split("\n")) {
		const line = rawLine.trim();
		if (!line) continue;
		const match = line.match(/^(PROGRESS|RATIONALE|NEXT|VERIFYING|STATE-DELTA):\s*(.+)$/i);
		if (!match) continue;
		const [, rawKey, rawValue] = match;
		const key = rawKey.toUpperCase();
		const value = rawValue.trim();
		if (!value) continue;
		if (key === "PROGRESS") result.progress = value;
		else if (key === "RATIONALE") result.rationale = value;
		else if (key === "NEXT") result.nextStep = value;
		else if (key === "VERIFYING") result.verifying = value;
		else if (key === "STATE-DELTA") result.stateDeltas.push(value);
	}
	if (result.stateDeltas.length > 6) result.stateDeltas = result.stateDeltas.slice(-6);
	return result;
}

export function lastAssistantText(messages: RoleMessage[]): string {
	for (let i = messages.length - 1; i >= 0; i--) {
		const message = messages[i];
		if (message.role !== "assistant") continue;
		const texts = message.content
			.filter((part) => part.type === "text" && typeof part.text === "string")
			.map((part) => part.text?.trim())
			.filter((part): part is string => Boolean(part));
		if (texts.length > 0) return texts.join("\n\n");
	}
	return "";
}

function applyAssistantTextToLiveRoleActivity(activity: LiveRoleActivity, text: string, activityAt = nowMs()): boolean {
	if (!text) return false;
	activity.lastAssistantText = text;
	const parsed = parseStructuredProgress(text);
	if (parsed.progress) activity.progress = parsed.progress;
	if (parsed.rationale) activity.rationale = parsed.rationale;
	if (parsed.nextStep) activity.nextStep = parsed.nextStep;
	if (parsed.verifying) activity.verifying = parsed.verifying;
	if (parsed.stateDeltas.length > 0) activity.stateDeltas = parsed.stateDeltas;
	const preview = truncateInline(text, 140);
	activity.assistantSummary = activity.progress ?? activity.verifying ?? preview;
	activity.currentAction = activity.assistantSummary;
	if (activity.assistantSummary) activity.recentActivity = pushRecentActivity(activity.recentActivity, `assistant: ${activity.assistantSummary}`);
	activity.updatedAt = activityAt;
	return true;
}

export function applyLiveRoleEvent(activity: LiveRoleActivity, event: JsonRecord, messages: RoleMessage[]): boolean {
	const eventType = asString(event.type);
	if (!eventType) return false;
	const activityAt = activityTimestampMs(event) ?? nowMs();
	if (eventType === "tool_execution_start") {
		const toolName = asString(event.toolName) ?? "tool";
		const toolArgs = isRecord(event.args) ? event.args : isRecord(event.input) ? event.input : {};
		activity.toolActivity = formatToolActivity(toolName, toolArgs);
		activity.currentAction = activity.toolActivity;
		activity.toolRecentActivity = pushRecentActivity(activity.toolRecentActivity, activity.toolActivity, 6);
		activity.recentActivity = pushRecentActivity(activity.recentActivity, activity.toolActivity);
		activity.updatedAt = activityAt;
		return true;
	}
	if (eventType === "tool_execution_update") {
		// Keep the currently selected tool label stable and suppress streaming tool-output lines.
		activity.updatedAt = activityAt;
		return true;
	}
	if (eventType === "tool_execution_end" || eventType === "tool_result_end") {
		activity.updatedAt = activityAt;
		return true;
	}
	if ((eventType === "message_update" || eventType === "message_end") && isRecord(event.message)) {
		const message = asRoleMessage(event.message);
		if (message && eventType === "message_end") messages.push(message);
		const nextOutput = message ? lastAssistantText(eventType === "message_end" ? messages : [message]) : "";
		if (nextOutput) return applyAssistantTextToLiveRoleActivity(activity, nextOutput, activityAt);
		activity.updatedAt = activityAt;
		return true;
	}
	return false;
}

export function maybeInjectTestLiveRoleActivity(liveRoleActivityByRoot: Map<string, LiveRoleActivity>, rootKey: string): void {
	const raw = asString(process.env.PI_COMPLETION_TEST_LIVE_ROLE_ACTIVITY_JSON);
	if (!raw) return;
	try {
		const parsed = JSON.parse(raw);
		if (!isRecord(parsed)) return;
		const currentAction = asString(parsed.currentAction);
		const recentActivity = asStringArray(parsed.recentActivity).length > 0 ? asStringArray(parsed.recentActivity) : currentAction ? [currentAction] : [];
		const toolActivity =
			asString(parsed.toolActivity) ??
			(currentAction && !currentAction.startsWith("assistant:") && !currentAction.startsWith("progress:") ? currentAction : undefined);
		const assistantSummary =
			asString(parsed.assistantSummary) ??
			(currentAction?.startsWith("assistant:") ? currentAction.slice("assistant:".length).trim() : undefined);
		liveRoleActivityByRoot.set(rootKey, {
			role: asString(parsed.role) ?? "completion-implementer",
			status: asString(parsed.status) === "ok" ? "ok" : asString(parsed.status) === "error" ? "error" : "running",
			currentAction,
			toolActivity,
			toolRecentActivity: asStringArray(parsed.toolRecentActivity).length > 0 ? asStringArray(parsed.toolRecentActivity) : toolActivity ? [toolActivity] : [],
			recentActivity,
			assistantSummary,
			lastAssistantText: asString(parsed.lastAssistantText),
			progress: asString(parsed.progress),
			rationale: asString(parsed.rationale),
			nextStep: asString(parsed.nextStep),
			verifying: asString(parsed.verifying),
			stateDeltas: asStringArray(parsed.stateDeltas),
			startedAt: asNumber(parsed.startedAt) ?? nowMs(),
			updatedAt: asNumber(parsed.updatedAt) ?? nowMs(),
		});
	} catch {
		// ignore malformed test override
	}
}

export type InlineRunningDetails = {
	role?: string;
	startedAt?: number;
	updatedAt?: number;
	currentAction?: string;
	toolActivity?: string;
	toolRecentActivity?: string[];
	recentActivity?: string[];
	assistantSummary?: string;
	progress?: string;
	rationale?: string;
	nextStep?: string;
	verifying?: string;
	stateDeltas?: string[];
};

export type InlineRunningMode = "compact" | "expanded";

function isStartingPlaceholder(text: string | undefined): boolean {
	return text === "Starting role subprocess";
}

function runningActivitySignal(details: Pick<InlineRunningDetails, "startedAt" | "updatedAt">): LiveActivitySignal | undefined {
	return liveActivitySignal({ status: "running", startedAt: details.startedAt, updatedAt: details.updatedAt });
}

export function formatRoleHeaderLine(
	details: Pick<InlineRunningDetails, "role" | "startedAt" | "updatedAt">,
	signal = runningActivitySignal(details),
): string {
	const role = details.role ?? "completion-role";
	const chunks = [role];
	if (details.startedAt !== undefined) chunks.push(formatElapsed(nowMs() - details.startedAt));
	const activity = signal?.state ?? "active";
	if (signal && signal.state !== "active") {
		chunks.push(`${activity} (${formatElapsed(signal.idleMs)} since update)`);
	} else {
		chunks.push(activity);
	}
	return chunks.join(" · ");
}

export function pickNowLine(details: InlineRunningDetails): string | undefined {
	const toolLine = details.toolActivity?.trim();
	const hasActiveTool = Boolean(toolLine && !isStartingPlaceholder(toolLine));
	if (hasActiveTool && toolLine) return toolLine;
	if (details.progress?.trim()) return details.progress.trim();
	if (details.verifying?.trim()) return details.verifying.trim();
	const assistant = details.assistantSummary?.trim();
	if (assistant) return assistant;
	const currentAction = details.currentAction?.trim();
	if (currentAction && currentAction !== toolLine) {
		return currentAction.replace(/^assistant:\s*/, "");
	}
	return undefined;
}

function shouldShowPlan(signal: LiveActivitySignal | undefined, mode: InlineRunningMode): boolean {
	if (mode === "expanded") return true;
	return signal?.state === "waiting" || signal?.state === "stalled";
}

function pickPlanHintLine(details: InlineRunningDetails): string | undefined {
	if (details.nextStep?.trim()) return `next: ${details.nextStep.trim()}`;
	if (details.rationale?.trim()) return `rationale: ${details.rationale.trim()}`;
	return undefined;
}

function nowLineUsesTool(details: InlineRunningDetails): boolean {
	const toolLine = details.toolActivity?.trim();
	return Boolean(toolLine && !isStartingPlaceholder(toolLine) && pickNowLine(details) === toolLine);
}

export function roleOutcomeSummaryLines(
	role: string | undefined,
	reportFields: Record<string, string>,
	ok: boolean,
	exitCode?: number,
): string[] {
	if (!ok) return [`exit ${exitCode ?? 1} · expand for details`];
	const field = (key: string) => reportFields[key]?.trim();
	const lines: string[] = [];
	switch (role) {
		case "completion-bootstrapper": {
			const bootstrap = field("Bootstrap applied");
			const nextRole = field("Next role to invoke");
			if (bootstrap) lines.push(bootstrap);
			if (nextRole) lines.push(`→ ${nextRole}`);
			break;
		}
		case "completion-regrounder": {
			const decision = field("Reconciliation decision");
			const slice = field("Current selected slice");
			if (decision) lines.push(decision);
			if (slice) lines.push(`slice: ${slice}`);
			break;
		}
		case "completion-implementer": {
			const sliceId = field("Slice ID");
			const commit = field("Commit SHA");
			const verification = field("Verification results");
			if (sliceId && commit) lines.push(`${sliceId} · ${commit}`);
			else if (sliceId) lines.push(sliceId);
			else if (commit) lines.push(commit);
			if (verification && /fail|error|block/i.test(verification)) {
				lines.push(truncateInline(verification, 120));
			} else if (lines.length < 2) {
				lines.push("→ completion-reviewer");
			}
			break;
		}
		case "completion-reviewer": {
			const acceptable = field("Acceptable as-is");
			const followUp = field("Smallest follow-up slice");
			if (acceptable) lines.push(`acceptable: ${acceptable}`);
			if (followUp) lines.push(followUp === "none" ? "no follow-up slice" : followUp);
			break;
		}
		case "completion-auditor": {
			const nextSlice = field("Next mandatory slice");
			const blockers = field("Blocker count");
			const worktree = field("Tracked and unignored worktree is clean");
			if (nextSlice) lines.push(`next slice: ${nextSlice}`);
			if (blockers) lines.push(`${blockers} blocker(s)`);
			else if (worktree) lines.push(`worktree clean: ${worktree}`);
			break;
		}
		case "completion-stop-judge": {
			const canStop = field("Can the project stop now");
			const justification = field("Brief justification");
			if (canStop) lines.push(`stop: ${canStop}`);
			if (justification) lines.push(truncateInline(justification, 120));
			break;
		}
		default: {
			const nextRole = field("Next role to invoke");
			if (nextRole) lines.push(`→ ${nextRole}`);
			break;
		}
	}
	if (lines.length === 0) {
		const nextRole = field("Next role to invoke");
		if (nextRole) lines.push(`→ ${nextRole}`);
	}
	return lines.slice(0, 2);
}

function formatTranscriptionLines(
	transcription: { appended?: string[]; skipped?: string[]; errors?: string[] } | undefined,
	expanded: boolean,
): string[] {
	if (!transcription) return [];
	const lines: string[] = [];
	if (transcription.appended?.length) lines.push(`state updated: ${transcription.appended.join(", ")}`);
	if (transcription.errors?.length) lines.push(`warnings: ${transcription.errors.join(" | ")}`);
	if (expanded && transcription.skipped?.length) lines.push(`skipped: ${transcription.skipped.join(" | ")}`);
	return lines;
}

export function maybeReplayTestLiveRoleEvents(liveRoleActivityByRoot: Map<string, LiveRoleActivity>, rootKey: string): void {
	const raw = asString(process.env.PI_COMPLETION_TEST_ROLE_EVENT_STREAM_JSON);
	if (!raw) return;
	try {
		const parsed = JSON.parse(raw);
		let role = "completion-implementer";
		let status: LiveRoleActivity["status"] = "running";
		let startedAt = nowMs();
		let events: JsonRecord[] = [];
		if (Array.isArray(parsed)) {
			events = parsed.filter(isRecord);
		} else if (isRecord(parsed)) {
			role = asString(parsed.role) ?? role;
			status = asString(parsed.status) === "ok" ? "ok" : asString(parsed.status) === "error" ? "error" : "running";
			startedAt = asNumber(parsed.startedAt) ?? asNumber(parsed.started_at) ?? startedAt;
			events = Array.isArray(parsed.events) ? parsed.events.filter(isRecord) : [];
		} else {
			return;
		}
		const activity = createLiveRoleActivity(role, startedAt);
		const messages: RoleMessage[] = [];
		for (const event of events) applyLiveRoleEvent(activity, event, messages);
		liveRoleActivityByRoot.set(rootKey, cloneLiveRoleActivity(activity, { status }));
	} catch {
		// ignore malformed event stream override
	}
}

export function buildInlineRunningLines(details: InlineRunningDetails, options?: { mode?: InlineRunningMode }): string[] {
	const mode = options?.mode ?? "compact";
	const signal = runningActivitySignal(details);
	const lines: string[] = [formatRoleHeaderLine(details, signal)];
	const nowLine = pickNowLine(details);
	if (nowLine) lines.push(`now: ${nowLine}`);
	if (mode === "compact") {
		if (shouldShowPlan(signal, mode)) {
			const planLine = pickPlanHintLine(details);
			if (planLine) lines.push(planLine);
		}
		return lines;
	}
	const toolLine = details.toolActivity?.trim();
	if (details.progress?.trim() && nowLineUsesTool(details)) lines.push(`progress: ${details.progress.trim()}`);
	if (details.rationale?.trim()) lines.push(`rationale: ${details.rationale.trim()}`);
	if (details.nextStep?.trim()) lines.push(`next: ${details.nextStep.trim()}`);
	if (details.verifying?.trim() && pickNowLine(details) !== details.verifying.trim()) {
		lines.push(`verifying: ${details.verifying.trim()}`);
	}
	for (const delta of (details.stateDeltas ?? []).slice(-2)) lines.push(`state-delta: ${delta}`);
	const recentTools = collapseRecentActivity(details.toolRecentActivity ?? details.recentActivity ?? [], 3);
	const recentWithoutCurrent = recentTools.filter((item) => item !== toolLine);
	if (recentWithoutCurrent.length > 0) {
		lines.push("recent:");
		for (const item of recentWithoutCurrent) lines.push(`- ${item}`);
	}
	return lines;
}

export function buildCompletionRoleDoneLines(
	details: InlineRunningDetails & {
		status?: string;
		exitCode?: number;
		reportFields?: Record<string, string>;
		transcription?: { appended?: string[]; skipped?: string[]; errors?: string[] };
	},
	options: { expanded: boolean; isError: boolean },
): string[] {
	const role = details.role ?? "completion-role";
	const ok = details.status === "ok" && !options.isError;
	const elapsed = details.startedAt !== undefined ? formatElapsed(nowMs() - details.startedAt) : undefined;
	const lines: string[] = [`${ok ? "done" : "error"}: ${role}${elapsed ? ` · ${elapsed}` : ""}`];
	lines.push(...roleOutcomeSummaryLines(role, details.reportFields ?? {}, ok, details.exitCode));
	lines.push(...formatTranscriptionLines(details.transcription, options.expanded));
	return lines;
}

export function formatInlineRunningText(theme: any, lines: string[], options?: { primaryAssistant?: boolean }): string {
	let text = "";
	for (const [index, line] of lines.entries()) {
		if (index > 0) text += "\n";
		if (index === 0 && (line.startsWith("done:") || line.startsWith("error:"))) {
			const [status, ...rest] = line.split(": ");
			const ok = status === "done";
			text += `${theme.fg(ok ? "success" : "error", status)}: ${theme.fg("toolTitle", theme.bold(rest.join(": ")))}`;
			continue;
		}
		if (index === 0) {
			const segments = line.split(" · ");
			text += theme.fg("accent", segments[0] ?? line);
			for (const segment of segments.slice(1)) {
				const stalled = segment.startsWith("stalled") || segment.startsWith("waiting");
				text += theme.fg("muted", " · ");
				text += stalled ? theme.fg("warning", segment) : theme.fg("muted", segment);
			}
			continue;
		}
		if (line.startsWith("now: ")) {
			text += theme.fg("toolOutput", line.slice(5));
			continue;
		}
		if (line.startsWith("tool:") || line.startsWith("progress:")) {
			text += theme.fg("toolOutput", line);
			continue;
		}
		if (line === "recent:" || line === "recent tools:") {
			text += theme.fg("muted", line);
			continue;
		}
		if (line.startsWith("- ")) {
			text += `${theme.fg("muted", "- ")}${theme.fg("muted", line.slice(2))}`;
			continue;
		}
		if (line.startsWith("next:") || line.startsWith("verifying:") || line.startsWith("rationale:") || line.startsWith("state-delta:")) {
			text += theme.fg("muted", line);
			continue;
		}
		if (line.startsWith("state updated:") || line.startsWith("warnings:") || line.startsWith("skipped:")) {
			const [label, ...rest] = line.split(": ");
			const value = rest.join(": ");
			const color = line.startsWith("warnings:") ? "warning" : line.startsWith("state updated:") ? "success" : "muted";
			text += `${theme.fg("muted", `${label}: `)}${theme.fg(color, value)}`;
			continue;
		}
		if (line.startsWith("exit ")) {
			text += theme.fg("error", line);
			continue;
		}
		if (line.startsWith("→ ") || line.startsWith("acceptable:") || line.startsWith("stop:") || line.startsWith("slice:") || line.startsWith("next slice:")) {
			text += options?.primaryAssistant ? line : theme.fg("muted", line);
			continue;
		}
		if (line.includes(": ") && !line.startsWith("assistant:")) {
			const colonIndex = line.indexOf(": ");
			const label = line.slice(0, colonIndex);
			const value = line.slice(colonIndex + 2);
			text += `${theme.fg("muted", `${label}: `)}${value}`;
			continue;
		}
		if (line.startsWith("assistant:")) {
			text += options?.primaryAssistant ? line : theme.fg("muted", line);
			continue;
		}
		text += theme.fg("muted", line);
	}
	return text;
}

export function formatCompletionRoleResultText(
	theme: any,
	details: InlineRunningDetails & {
		status?: string;
		exitCode?: number;
		stderr?: string;
		reportFields?: Record<string, string>;
		transcription?: { appended?: string[]; skipped?: string[]; errors?: string[] };
	},
	options: { expanded: boolean; isError: boolean; bodyText?: string },
): string {
	const lines = buildCompletionRoleDoneLines(details, options);
	let text = formatInlineRunningText(theme, lines);
	if (options.expanded && options.bodyText) {
		text += `\n\n${options.bodyText}`;
	}
	if (options.expanded && details.stderr) {
		text += `\n${theme.fg("error", details.stderr)}`;
	}
	return text;
}

export function buildCompletionStatusSurface(
	snapshot: CompletionStateSnapshot | undefined,
	liveActivity: LiveRoleActivity | undefined,
): CompletionStatusSurface {
	if (!snapshot) return { snapshotPresent: false, widgetLines: [] };
	const currentPhase = asString(snapshot.state?.current_phase) ?? "unknown";
	const sliceId = asString(snapshot.active?.slice_id) ?? asString(snapshot.activeSlice?.slice_id) ?? "(none)";
	const sliceGoal = truncateInline(asString(snapshot.active?.goal) ?? asString(snapshot.activeSlice?.goal) ?? "(unknown)", 140);
	const nextMandatoryRole = asString(snapshot.state?.next_mandatory_role) ?? "unknown";
	const remainingContractCount = asStringArray(snapshot.state?.unsatisfied_contract_ids).length;
	const releaseBlockerCount = asNumber(snapshot.state?.remaining_release_blockers) ?? 0;
	const highValueGapCount = asNumber(snapshot.state?.remaining_high_value_gaps) ?? 0;
	const remainingStopJudgeCount = asNumber(snapshot.state?.remaining_stop_judges) ?? 0;
	const requiredStopJudges = asNumber(snapshot.profile?.required_stop_judges) ?? 0;
	const stopAggregationPolicy = asString(snapshot.profile?.stop_aggregation_policy);
	const activeRole = liveActivity?.status === "running" ? liveActivity.role : undefined;
	const liveSignal = liveActivitySignal(liveActivity);
	const livePreview = livePreviewForStatus(liveActivity);
	const liveDetailsLines = activeRole
		? buildInlineRunningLines({
				role: activeRole,
				currentAction: liveActivity?.currentAction,
				toolActivity: liveActivity?.toolActivity,
				toolRecentActivity: liveActivity?.toolRecentActivity,
				recentActivity: liveActivity?.recentActivity,
				assistantSummary: liveActivity?.assistantSummary,
				progress: liveActivity?.progress,
				rationale: liveActivity?.rationale,
				nextStep: liveActivity?.nextStep,
				verifying: liveActivity?.verifying,
				stateDeltas: liveActivity?.stateDeltas,
				startedAt: liveActivity?.startedAt,
				updatedAt: liveActivity?.updatedAt,
		  })
		: [];
	const remainingSummary = completionRemainingSummary({
		remainingContractCount,
		releaseBlockerCount,
		highValueGapCount,
		remainingStopJudgeCount,
	});
	const widgetLines = activeRole
		? []
		: [
				"completion workflow",
				`phase: ${currentPhase}`,
				`slice: ${sliceId}`,
				`goal: ${sliceGoal}`,
				`next: ${nextMandatoryRole}`,
				`remaining: ${remainingSummary}`,
		  ];
	return {
		snapshotPresent: true,
		widgetLines,
		currentPhase,
		sliceId,
		nextMandatoryRole,
		remainingContractCount,
		releaseBlockerCount,
		highValueGapCount,
		remainingStopJudgeCount,
		requiredStopJudges,
		stopAggregationPolicy,
		activeRole,
		livePreview,
		liveState: liveSignal?.state,
		liveIdleMs: liveSignal?.idleMs,
		liveToolActivity: liveActivity?.toolActivity,
		liveAssistantSummary: liveActivity?.assistantSummary,
		liveProgress: liveActivity?.progress,
		liveRationale: liveActivity?.rationale,
		liveNextStep: liveActivity?.nextStep,
		liveVerifying: liveActivity?.verifying,
		liveStateDeltas: liveActivity?.stateDeltas ?? [],
		liveDetailsLines,
	};
}

async function writeCompletionStatusProbe(surface: CompletionStatusSurface): Promise<void> {
	const outputPath = asString(process.env.PI_COMPLETION_STATUS_SNAPSHOT_FILE);
	if (!outputPath) return;
	await fsp.mkdir(path.dirname(outputPath), { recursive: true });
	await fsp.writeFile(outputPath, `${JSON.stringify(surface, null, 2)}\n`, "utf8");
}

export async function refreshCompletionStatus(args: {
	ctx: { cwd: string; hasUI: boolean; ui: any };
	liveRoleActivityByRoot: Map<string, LiveRoleActivity>;
	completionStatusKey: string;
	safeUiCall: (action: () => void) => void;
	getCtxCwd: (ctx: { cwd: string }) => string;
	getCtxHasUI: (ctx: { hasUI: boolean }) => boolean;
	getCtxUi: <T extends { ui: any }>(ctx: T) => any | undefined;
}): Promise<void> {
	const cwd = args.getCtxCwd(args.ctx);
	const snapshot = await loadCompletionSnapshot(cwd);
	const rootKey = completionRootKey(snapshot, cwd);
	maybeInjectTestLiveRoleActivity(args.liveRoleActivityByRoot, rootKey);
	maybeReplayTestLiveRoleEvents(args.liveRoleActivityByRoot, rootKey);
	const surface = buildCompletionStatusSurface(snapshot, args.liveRoleActivityByRoot.get(rootKey));
	await writeCompletionStatusProbe(surface);
	if (!args.getCtxHasUI(args.ctx)) return;
	const ui = args.getCtxUi(args.ctx);
	if (!ui) return;
	args.safeUiCall(() => {
		ui.setWidget(args.completionStatusKey, surface.widgetLines.length > 0 ? surface.widgetLines : undefined);
	});
}
