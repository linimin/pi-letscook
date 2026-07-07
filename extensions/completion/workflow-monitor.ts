import * as path from "node:path";
import { loadCompletionSnapshot, resolveFiles } from "./state-store.ts";
import { readCookHandoffSidecar } from "./cursor-handoff-service.ts";
import { readWorkflowEvents, type WorkflowEvent } from "./workflow-events.ts";
import { syncWorkflowEventsForRoot } from "./workflow-event-sync.ts";
import type { JsonRecord } from "./types.ts";

function asString(value: unknown): string | undefined {
	return typeof value === "string" && value.trim().length > 0 ? value.trim() : undefined;
}

function isRecord(value: unknown): value is JsonRecord {
	return typeof value === "object" && value !== null && !Array.isArray(value);
}

function candidateSlices(plan: JsonRecord | undefined): JsonRecord[] {
	if (!plan) return [];
	const slices = plan.slices ?? plan.candidate_slices;
	return Array.isArray(slices) ? slices.filter(isRecord) : [];
}

function sliceCounts(plan: JsonRecord | undefined): { done: number; total: number } {
	const slices = candidateSlices(plan);
	const total = slices.length;
	const done = slices.filter((slice) => {
		const status = asString(slice.status)?.toLowerCase();
		return status === "done" || status === "cancelled";
	}).length;
	return { done, total };
}

function needsAttentionFromState(workflowEntryStatus: string | undefined, continuationPolicy: string | undefined): boolean {
	const entry = workflowEntryStatus?.toLowerCase();
	const policy = continuationPolicy?.toLowerCase();
	return (
		entry === "parked" ||
		entry === "blocked" ||
		policy === "await_user_input" ||
		policy === "blocked" ||
		policy === "paused"
	);
}

export type CookWorkflowStatus = {
	workspace_root: string;
	workflow_entry_status?: string;
	continuation_policy?: string;
	mission?: string;
	active_slice?: { id?: string; goal?: string; status?: string };
	slices_done: number;
	slices_total: number;
	needs_attention: boolean;
	last_event_id?: string;
	handoff_sidecar_status?: string;
};

export async function getCookWorkflowStatus(workspaceRoot: string): Promise<CookWorkflowStatus | { error: string }> {
	const root = path.resolve(workspaceRoot);
	await syncWorkflowEventsForRoot(root);
	const snapshot = await loadCompletionSnapshot(root);
	const sidecar = await readCookHandoffSidecar(root);
	const events = await readWorkflowEvents(root);
	const lastEvent = events.at(-1);
	if (!snapshot) {
		return {
			error: `no active completion workflow state under ${path.join(root, ".agent/current/state.json")}`,
		};
	}
	const { done, total } = sliceCounts(snapshot.plan);
	const workflowEntryStatus = asString(snapshot.state?.workflow_entry_status);
	const continuationPolicy = asString(snapshot.state?.continuation_policy);
	return {
		workspace_root: root,
		workflow_entry_status: workflowEntryStatus,
		continuation_policy: continuationPolicy,
		mission:
			asString(snapshot.state?.mission_anchor) ??
			asString(snapshot.plan?.mission_anchor) ??
			asString(snapshot.active?.mission_anchor),
		active_slice: {
			id: asString(snapshot.active?.slice_id),
			goal: asString(snapshot.active?.goal),
			status: asString(snapshot.active?.status),
		},
		slices_done: done,
		slices_total: total,
		needs_attention: needsAttentionFromState(workflowEntryStatus, continuationPolicy),
		last_event_id: lastEvent?.id,
		handoff_sidecar_status: sidecar?.status,
	};
}

export type CookWorkflowPollResult = {
	workspace_root: string;
	events: WorkflowEvent[];
	headline?: string;
	detail?: string;
	needs_attention: boolean;
	status?: CookWorkflowStatus;
};

export async function pollCookWorkflowUpdates(args: {
	workspaceRoot: string;
	sinceEventId?: string;
}): Promise<CookWorkflowPollResult | { error: string }> {
	const root = path.resolve(args.workspaceRoot);
	const status = await getCookWorkflowStatus(root);
	if ("error" in status) {
		return status;
	}
	const events = await readWorkflowEvents(root);
	let startIndex = 0;
	if (args.sinceEventId) {
		const index = events.findIndex((event) => event.id === args.sinceEventId);
		startIndex = index >= 0 ? index + 1 : 0;
	}
	const delta = events.slice(startIndex);
	const latest = delta.at(-1);
	const headline = latest?.headline ?? (delta.length === 0 ? "No workflow changes since last poll." : undefined);
	const detail = latest?.detail;
	return {
		workspace_root: root,
		events: delta,
		headline,
		detail,
		needs_attention: status.needs_attention || delta.some((event) => event.needs_attention),
		status,
	};
}

export function resolveWorkflowEventsPath(workspaceRoot: string): string {
	return path.join(resolveFiles(workspaceRoot).currentDir, "workflow-events.jsonl");
}
