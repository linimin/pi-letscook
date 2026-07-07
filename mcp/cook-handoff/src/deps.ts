import * as path from "node:path";
import { fileURLToPath } from "node:url";
import {
	assessMissionAnchor,
	isWeakMissionAnchor,
	missionAnchorsStrictlyEquivalent,
	normalizeMissionAnchorText,
	stripCodeBlocks,
} from "../../../extensions/completion/proposal.ts";
import type { CookProposalDeps } from "../../../extensions/completion/startup-intent.ts";
import {
	assessCookHandoffStartability,
	buildCookHandoffConfirmationLayout,
	CookHandoffServiceError,
	cancelPendingHandoff,
	ensureHandoffSidecarIntegrity,
	markHandoffAwaitingTerminalLaunch,
	markHandoffConfirmed,
	markHandoffKickoffStarted,
	markHandoffSpawnFailed,
	normalizeCookHandoffCapsule,
	readCookHandoffSidecar,
	readPendingCookHandoff,
	recoverStaleKickoffWithoutWorkflow,
	resolvePlainCookPendingImport,
	resolveWorkspaceRoot,
	validateCookHandoffSchema,
	writeCookHandoffFile,
} from "../../../extensions/completion/cursor-handoff-service.ts";
import { getCookWorkflowStatus, pollCookWorkflowUpdates } from "../../../extensions/completion/workflow-monitor.ts";
import { DEFAULT_CURSOR_HANDOFF_PATH } from "../../../extensions/completion/cursor-handoff.ts";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
export const PACKAGE_ROOT = path.resolve(__dirname, "../../..");

function asString(value: unknown): string | undefined {
	return typeof value === "string" && value.trim().length > 0 ? value.trim() : undefined;
}

function asStringArray(value: unknown): string[] {
	return Array.isArray(value)
		? value.filter((item): item is string => typeof item === "string" && item.trim().length > 0)
		: [];
}

export function cookProposalDeps(): CookProposalDeps {
	return {
		asString,
		asStringArray,
		assessMissionAnchor,
		normalizeMissionAnchorText,
		isWeakMissionAnchor,
		missionAnchorsStrictlyEquivalent,
		stripCodeBlocks,
	};
}

export function defaultPiExtensionPath(): string {
	return process.env.PI_LETSCOOK_EXTENSION_PATH ?? PACKAGE_ROOT;
}

export {
	assessCookHandoffStartability,
	buildCookHandoffConfirmationLayout,
	CookHandoffServiceError,
	cancelPendingHandoff,
	ensureHandoffSidecarIntegrity,
	DEFAULT_CURSOR_HANDOFF_PATH,
	getCookWorkflowStatus,
	markHandoffAwaitingTerminalLaunch,
	markHandoffConfirmed,
	markHandoffKickoffStarted,
	markHandoffSpawnFailed,
	normalizeCookHandoffCapsule,
	pollCookWorkflowUpdates,
	readCookHandoffSidecar,
	readPendingCookHandoff,
	recoverStaleKickoffWithoutWorkflow,
	resolvePlainCookPendingImport,
	resolveWorkspaceRoot,
	validateCookHandoffSchema,
	writeCookHandoffFile,
};

export const COOK_HANDOFF_SCHEMA_EXAMPLE = {
	kind: "cook_handoff",
	source: "primary_agent",
	captured_at: "2026-01-01T00:00:00.000Z",
	source_turn_id: "cursor-handoff",
	mission: "Implement feature X with verification",
	scope: ["src/feature"],
	constraints: ["Keep existing API stable"],
	non_goals: ["Unrelated refactors"],
	acceptance: ["npm test passes", "docs updated"],
	risks: ["Migration edge cases"],
	notes: ["Prepared from Cursor planning"],
	handoff_kind: "implementation_workflow_handoff",
	task_type: "completion-workflow",
	evaluation_profile: "completion-rubric-v1",
	why_cook_now: "Long-running workflow with review/audit gates",
};
