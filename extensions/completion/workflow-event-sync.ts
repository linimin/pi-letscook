import { promises as fsp } from "node:fs";
import * as path from "node:path";
import { loadCompletionSnapshot, resolveFiles } from "./state-store.ts";
import { appendWorkflowEvent, type WorkflowEvent } from "./workflow-events.ts";
import type { CompletionStateSnapshot, JsonRecord } from "./types.ts";

type WorkflowMonitorCursor = {
	workflow_entry_status?: string;
	continuation_policy?: string;
	active_slice_id?: string;
	active_slice_status?: string;
	latest_completed_slice?: string;
};

function asString(value: unknown): string | undefined {
	return typeof value === "string" && value.trim().length > 0 ? value.trim() : undefined;
}

function monitorCursorPath(root: string): string {
	return path.join(resolveFiles(root).tmpDir, "workflow-monitor-cursor.json");
}

function snapshotCursor(snapshot: CompletionStateSnapshot): WorkflowMonitorCursor {
	return {
		workflow_entry_status: asString(snapshot.state?.workflow_entry_status)?.toLowerCase(),
		continuation_policy: asString(snapshot.state?.continuation_policy),
		active_slice_id: asString(snapshot.active?.slice_id),
		active_slice_status: asString(snapshot.active?.status)?.toLowerCase(),
		latest_completed_slice: asString(snapshot.state?.latest_completed_slice) ?? undefined,
	};
}

async function readMonitorCursor(root: string): Promise<WorkflowMonitorCursor | undefined> {
	try {
		const raw = await fsp.readFile(monitorCursorPath(root), "utf8");
		const parsed = JSON.parse(raw) as WorkflowMonitorCursor;
		return parsed && typeof parsed === "object" ? parsed : undefined;
	} catch {
		return undefined;
	}
}

async function writeMonitorCursor(root: string, cursor: WorkflowMonitorCursor): Promise<void> {
	const filePath = monitorCursorPath(root);
	await fsp.mkdir(path.dirname(filePath), { recursive: true });
	await fsp.writeFile(filePath, `${JSON.stringify(cursor, null, 2)}\n`, { encoding: "utf8", mode: 0o600 });
}

function activeSliceGoal(snapshot: CompletionStateSnapshot): string | undefined {
	return asString(snapshot.active?.goal);
}

function missionHeadline(snapshot: CompletionStateSnapshot): string {
	return (
		asString(snapshot.state?.mission_anchor) ??
		asString(snapshot.plan?.mission_anchor) ??
		asString(snapshot.active?.mission_anchor) ??
		"completion workflow"
	);
}

async function emitBaselineEvents(
	root: string,
	next: WorkflowMonitorCursor,
	snapshot: CompletionStateSnapshot,
): Promise<WorkflowEvent[]> {
	const mission = missionHeadline(snapshot);
	const sliceGoal = activeSliceGoal(snapshot);
	const emitted: WorkflowEvent[] = [];

	if (next.continuation_policy === "blocked") {
		emitted.push(
			await appendWorkflowEvent(root, {
				kind: "blocked",
				headline: `Workflow blocked: ${mission}`,
				detail: asString(snapshot.state?.continuation_reason),
				needs_attention: true,
			}),
		);
	} else if (next.continuation_policy === "await_user_input") {
		emitted.push(
			await appendWorkflowEvent(root, {
				kind: "await_user_input",
				headline: `Workflow needs input: ${mission}`,
				detail: asString(snapshot.state?.continuation_reason),
				needs_attention: true,
			}),
		);
	} else if (next.continuation_policy === "done") {
		const cancelled = next.workflow_entry_status === "cancelled";
		emitted.push(
			await appendWorkflowEvent(root, {
				kind: cancelled ? "cancelled" : "done",
				headline: cancelled ? `Workflow cancelled: ${mission}` : `Workflow done: ${mission}`,
				detail: asString(snapshot.state?.continuation_reason),
			}),
		);
	} else if (next.workflow_entry_status === "parked") {
		emitted.push(
			await appendWorkflowEvent(root, {
				kind: "parked",
				headline: `Workflow parked: ${mission}`,
				detail: asString(snapshot.state?.continuation_reason),
				needs_attention: true,
			}),
		);
	} else if (next.active_slice_id) {
		emitted.push(
			await appendWorkflowEvent(root, {
				kind: "slice_selected",
				headline: `Slice selected: ${next.active_slice_id}`,
				detail: sliceGoal,
			}),
		);
	} else if (next.continuation_policy === "continue") {
		emitted.push(
			await appendWorkflowEvent(root, {
				kind: "workflow_active",
				headline: `Workflow active: ${mission}`,
				detail: asString(snapshot.state?.continuation_reason),
			}),
		);
	}

	return emitted;
}

async function emitTransitionEvents(
	root: string,
	previous: WorkflowMonitorCursor,
	next: WorkflowMonitorCursor,
	snapshot: CompletionStateSnapshot,
): Promise<WorkflowEvent[]> {
	const emitted: WorkflowEvent[] = [];
	const mission = missionHeadline(snapshot);
	const sliceGoal = activeSliceGoal(snapshot);

	if (previous.continuation_policy !== next.continuation_policy) {
		if (next.continuation_policy === "blocked") {
			emitted.push(
				await appendWorkflowEvent(root, {
					kind: "blocked",
					headline: `Workflow blocked: ${mission}`,
					detail: asString(snapshot.state?.continuation_reason),
					needs_attention: true,
				}),
			);
		} else if (next.continuation_policy === "await_user_input") {
			emitted.push(
				await appendWorkflowEvent(root, {
					kind: "await_user_input",
					headline: `Workflow needs input: ${mission}`,
					detail: asString(snapshot.state?.continuation_reason),
					needs_attention: true,
				}),
			);
		} else if (next.continuation_policy === "done") {
			const cancelled = next.workflow_entry_status === "cancelled";
			emitted.push(
				await appendWorkflowEvent(root, {
					kind: cancelled ? "cancelled" : "done",
					headline: cancelled ? `Workflow cancelled: ${mission}` : `Workflow done: ${mission}`,
					detail: asString(snapshot.state?.continuation_reason),
				}),
			);
		}
	}

	if (
		previous.workflow_entry_status !== next.workflow_entry_status &&
		next.workflow_entry_status === "parked"
	) {
		emitted.push(
			await appendWorkflowEvent(root, {
				kind: "parked",
				headline: `Workflow parked: ${mission}`,
				detail: asString(snapshot.state?.continuation_reason),
				needs_attention: true,
			}),
		);
	}

	if (previous.active_slice_id !== next.active_slice_id && next.active_slice_id) {
		emitted.push(
			await appendWorkflowEvent(root, {
				kind: "slice_selected",
				headline: `Slice selected: ${next.active_slice_id}`,
				detail: sliceGoal,
			}),
		);
	}

	if (previous.active_slice_status !== next.active_slice_status && next.active_slice_status) {
		if (next.active_slice_status === "in_progress") {
			emitted.push(
				await appendWorkflowEvent(root, {
					kind: "slice_in_progress",
					headline: `Slice in progress: ${next.active_slice_id ?? "(unknown)"}`,
					detail: sliceGoal,
				}),
			);
		} else if (next.active_slice_status === "done") {
			emitted.push(
				await appendWorkflowEvent(root, {
					kind: "slice_done",
					headline: `Slice done: ${next.active_slice_id ?? "(unknown)"}`,
					detail: sliceGoal,
				}),
			);
		}
	}

	if (
		previous.latest_completed_slice !== next.latest_completed_slice &&
		next.latest_completed_slice
	) {
		emitted.push(
			await appendWorkflowEvent(root, {
				kind: "slice_committed",
				headline: `Slice committed: ${next.latest_completed_slice}`,
				detail: sliceGoal,
			}),
		);
	}

	return emitted;
}

export async function syncWorkflowEventsFromSnapshot(
	root: string,
	snapshot: CompletionStateSnapshot,
): Promise<WorkflowEvent[]> {
	const resolvedRoot = path.resolve(root);
	const previous = await readMonitorCursor(resolvedRoot);
	const next = snapshotCursor(snapshot);
	const emitted = previous
		? await emitTransitionEvents(resolvedRoot, previous, next, snapshot)
		: await emitBaselineEvents(resolvedRoot, next, snapshot);
	await writeMonitorCursor(resolvedRoot, next);
	return emitted;
}

export async function syncWorkflowEventsForRoot(root: string): Promise<WorkflowEvent[]> {
	const snapshot = await loadCompletionSnapshot(root);
	if (!snapshot) return [];
	return await syncWorkflowEventsFromSnapshot(root, snapshot);
}
