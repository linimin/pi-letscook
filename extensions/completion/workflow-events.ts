import { promises as fsp } from "node:fs";
import * as path from "node:path";
import { resolveFiles } from "./state-store.ts";

export type WorkflowEventKind =
	| "kickoff_started"
	| "workflow_active"
	| "slice_selected"
	| "slice_in_progress"
	| "slice_committed"
	| "slice_done"
	| "await_user_input"
	| "blocked"
	| "parked"
	| "done"
	| "cancelled";

export type WorkflowEvent = {
	id: string;
	at: string;
	kind: WorkflowEventKind;
	headline: string;
	detail?: string;
	needs_attention?: boolean;
};

function workflowEventsPath(root: string): string {
	return path.join(resolveFiles(root).currentDir, "workflow-events.jsonl");
}

export async function appendWorkflowEvent(root: string, event: Omit<WorkflowEvent, "id" | "at"> & { id?: string; at?: string }): Promise<WorkflowEvent> {
	const record: WorkflowEvent = {
		id: event.id ?? `${Date.now()}-${Math.random().toString(36).slice(2, 10)}`,
		at: event.at ?? new Date().toISOString(),
		kind: event.kind,
		headline: event.headline,
		detail: event.detail,
		needs_attention: event.needs_attention,
	};
	const filePath = workflowEventsPath(root);
	await fsp.mkdir(path.dirname(filePath), { recursive: true });
	await fsp.appendFile(filePath, `${JSON.stringify(record)}\n`, { encoding: "utf8", mode: 0o600 });
	return record;
}

export async function readWorkflowEvents(root: string): Promise<WorkflowEvent[]> {
	const filePath = workflowEventsPath(root);
	try {
		const raw = await fsp.readFile(filePath, "utf8");
		const events: WorkflowEvent[] = [];
		for (const line of raw.split("\n")) {
			const trimmed = line.trim();
			if (!trimmed) continue;
			try {
				const parsed = JSON.parse(trimmed) as WorkflowEvent;
				if (parsed && typeof parsed.id === "string" && typeof parsed.kind === "string") {
					events.push(parsed);
				}
			} catch {
				// skip malformed lines
			}
		}
		return events;
	} catch {
		return [];
	}
}
