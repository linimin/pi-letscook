import { createHash } from "node:crypto";
import { promises as fsp } from "node:fs";
import * as path from "node:path";
import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";
import {
	currentEvaluationProfile,
	currentMissionAnchor,
	currentTaskType,
	defaultActiveSlice,
	defaultPlan,
	defaultStartupBrief,
	defaultState,
	defaultVerificationEvidence,
	findCompletionRoot,
	findRepoRoot,
	loadCompletionSnapshot,
	removeCompletionRuntimeState,
	resolveFiles,
	writeJsonFile,
} from "./state-store";
import { buildAdvisoryStartupBrief } from "./startup-intent";
import type { CookContextProposalResult } from "./startup-intent";
import type {
	ContextProposal,
	ContextProposalAlternate,
	ContextProposalAnalysis,
	ContextProposalDecision,
} from "./proposal";
import type { CompletionStateSnapshot } from "./types";

type ExistingWorkflowDecision =
	| { action: "continue"; currentMissionAnchor: string }
	| { action: "refocus"; currentMissionAnchor: string; missionAnchor: string; proposal: ContextProposal };

function buildCookStartupBriefRequiredMessage(deps: CompletionDriverDeps, prefix?: string): string {
	const requirement = deps.structuredDiscussionFailureDetail;
	return prefix ? `${prefix} ${requirement}` : requirement;
}

type ActiveWorkflowProposalAssessment = {
	action: "continue" | "refocus";
	currentMissionAnchor: string;
	proposal?: ContextProposal;
	reason: "matching_mission" | "missing_explicit_handoff" | "fresh_explicit_handoff";
};

type ExistingWorkflowChooserOptions = {
	intro?: string;
	comparison?: "strict" | "semantic";
	proposedMissionLabel?: string;
	refocusChoiceLabel?: string;
	alternateChoiceLabel?: string;
};

type DriverContext = {
	cwd: string;
	hasUI: boolean;
	ui: any;
	sessionManager?: any;
	model?: any;
	modelRegistry?: any;
	cookInlinePrompt?: string;
};

type DriverContinuationTracker = {
	fingerprint: string;
	attempts: number;
	warned: boolean;
};

export type CompletionDriverDeps = {
	structuredDiscussionFailureDetail: string;
	mainChatRerunGuidance: string;
	cookCommandSpec: {
		description: string;
	};
	getCtxCwd: (ctx: { cwd: string }) => string;
	getCtxHasUI: (ctx: { hasUI: boolean }) => boolean;
	getCtxUi: <T extends { ui: any }>(ctx: T) => any | undefined;
	emitCommandText: (
		ctx: { hasUI: boolean; ui: any },
		text: string,
		level?: "info" | "success" | "warning" | "error",
	) => void;
	completionRootKey: (snapshot: CompletionStateSnapshot | undefined, cwd: string) => string;
	hasRunningCompletionRole: (rootKey: string) => boolean;
	completionKickoff: (
		goal: string,
		taskType: string,
		evaluationProfile: string,
		intent?: "auto" | "continue" | "refocus",
		missionAnchor?: string,
		workflowSessionId?: string,
	) => string;
	completionResumePrompt: (taskType: string, evaluationProfile: string, workflowSessionId?: string) => string;
	deriveCookContextProposal: (ctx: DriverContext, projectName: string) => Promise<CookContextProposalResult>;
	confirmContextProposal: (
		ctx: { hasUI: boolean; ui: any },
		proposal: ContextProposal,
		options: { title: string; nonInteractiveBehavior?: "accept" | "cancel" },
	) => Promise<ContextProposalDecision | undefined>;
	finalizeContextProposalAnalysis: (analysis: ContextProposalAnalysis | undefined, hintTexts?: string[]) => ContextProposalAnalysis;
	buildContextProposalContinuationReason: (prefix: string, goalText: string, analysis: ContextProposalAnalysis) => string;
	scaffoldCompletionFiles: (
		root: string,
		missionAnchor: string,
		options?: { analysis?: ContextProposalAnalysis; continuationReason?: string; advisoryStartupBrief?: Record<string, unknown> },
	) => Promise<{ root: string; created: string[] }>;
	maybeWriteActiveWorkflowRoutingSnapshot: (assessment: ActiveWorkflowProposalAssessment) => void;
	missionAnchorsLikelyEquivalent: (left: string, right: string) => boolean;
	missionAnchorsStrictlyEquivalent: (left: string, right: string) => boolean;
	activateCompletionRoutingForRoot: (root: string | undefined) => void;
	maybeWriteTestSnapshot: (targetPath: string | undefined, content: string) => void;
	completionTestDriverPromptPath: () => string | undefined;
	completionTestAutoContinuePromptPath: () => string | undefined;
	completionTestExistingWorkflowChooserSnapshotPath: () => string | undefined;
	completionTestWorkflowActionOverride: () => "continue" | "refocus" | "cancel" | undefined;
	completionTestWorkflowMissionOverride: () => string | undefined;
	shouldSkipDriverKickoffForTests: () => boolean;
	shouldTestAutoContinueOnSessionStart: () => boolean;
};

const DRIVER_AUTO_CONTINUE_MAX_ATTEMPTS = 2;
const driverContinuationByRoot = new Map<string, DriverContinuationTracker>();

function asString(value: unknown): string | undefined {
	return typeof value === "string" && value.trim().length > 0 ? value.trim() : undefined;
}

function asNumber(value: unknown): number | undefined {
	return typeof value === "number" && Number.isFinite(value) ? value : undefined;
}

function roleFromEnv(): string | undefined {
	return asString(process.env.PI_COMPLETION_ROLE);
}

function buildCookCancellationMessage(prefix: string, deps: CompletionDriverDeps): string {
	return `${prefix}. ${deps.mainChatRerunGuidance}`;
}

export function completionContinuationFingerprint(snapshot: CompletionStateSnapshot): string | undefined {
	if (asString(snapshot.state?.continuation_policy) !== "continue") return undefined;
	const nextMandatoryRole = asString(snapshot.state?.next_mandatory_role);
	if (!nextMandatoryRole) return undefined;
	return JSON.stringify({
		workflow_session_id: asString(snapshot.state?.workflow_session_id) ?? null,
		mission_anchor: asString(snapshot.state?.mission_anchor) ?? asString(snapshot.plan?.mission_anchor) ?? null,
		task_type: currentTaskType(snapshot) ?? null,
		evaluation_profile: currentEvaluationProfile(snapshot) ?? null,
		current_phase: asString(snapshot.state?.current_phase) ?? null,
		next_mandatory_role: nextMandatoryRole,
		next_mandatory_action: asString(snapshot.state?.next_mandatory_action) ?? null,
		active_status: asString(snapshot.active?.status) ?? null,
		active_slice_id: asString(snapshot.active?.slice_id) ?? asString(snapshot.activeSlice?.slice_id) ?? null,
		latest_completed_slice: asString(snapshot.state?.latest_completed_slice) ?? null,
		latest_verified_slice: asString(snapshot.state?.latest_verified_slice) ?? null,
	});
}

function noteQueuedDriverPrompt(rootKey: string, fingerprint: string): void {
	const tracker = driverContinuationByRoot.get(rootKey);
	if (tracker && tracker.fingerprint === fingerprint) {
		tracker.attempts += 1;
		tracker.warned = false;
		return;
	}
	driverContinuationByRoot.set(rootKey, {
		fingerprint,
		attempts: 1,
		warned: false,
	});
}

function clearDriverContinuationTracker(rootKey: string): void {
	driverContinuationByRoot.delete(rootKey);
}

function isWorkflowDriverActive(snapshot: CompletionStateSnapshot | undefined): boolean {
	return Boolean(snapshot) && asString(snapshot?.state?.continuation_policy) === "continue";
}

function isDriverContinuationStateParked(rootKey: string, fingerprint: string): boolean {
	const tracker = driverContinuationByRoot.get(rootKey);
	if (!tracker || tracker.fingerprint !== fingerprint) return false;
	return tracker.warned;
}

function rememberParkedDriverContinuation(rootKey: string, fingerprint: string): void {
	const tracker = driverContinuationByRoot.get(rootKey);
	if (!tracker || tracker.fingerprint !== fingerprint) return;
	tracker.warned = true;
}

function hashDriverPrompt(prompt: string): string {
	return createHash("sha256").update(prompt).digest("hex");
}

function extractWorkflowSessionIdFromDriverPrompt(prompt: string): string | undefined {
	const match = prompt.match(/^- workflow_session_id:\s*(.+)$/m);
	return match?.[1]?.trim() || undefined;
}

function summarizeProposalForChoice(proposal: ContextProposalAlternate): string {
	const parts: string[] = [`Mission\n${proposal.mission}`];
	if (proposal.scope.length > 0) parts.push(`Scope\n- ${proposal.scope.slice(0, 2).join("\n- ")}`);
	if (proposal.constraints.length > 0) parts.push(`Constraints\n- ${proposal.constraints.slice(0, 1).join("\n- ")}`);
	if (proposal.acceptance.length > 0) parts.push(`Acceptance\n- ${proposal.acceptance.slice(0, 1).join("\n- ")}`);
	return parts.join("\n\n");
}

async function queueCompletionDriverPrompt(
	pi: ExtensionAPI,
	ctx: { cwd: string; hasUI: boolean; ui: any },
	prompt: string,
	kind: "kickoff" | "resume" | "auto-resume",
	deps: CompletionDriverDeps,
	tracker?: { rootKey: string; fingerprint: string },
): Promise<boolean> {
	const snapshotPath = kind === "auto-resume" ? deps.completionTestAutoContinuePromptPath() : deps.completionTestDriverPromptPath();
	deps.maybeWriteTestSnapshot(snapshotPath, `${prompt}\n`);
	if (kind === "auto-resume" && tracker) {
		noteQueuedDriverPrompt(tracker.rootKey, tracker.fingerprint);
	}
	const root = findCompletionRoot(deps.getCtxCwd(ctx)) ?? findRepoRoot(deps.getCtxCwd(ctx)) ?? deps.getCtxCwd(ctx);
	const files = resolveFiles(root);
	const promptMetadata = {
		kind,
		queued_at: new Date().toISOString(),
		workflow_session_id: extractWorkflowSessionIdFromDriverPrompt(prompt) ?? null,
		prompt_hash: hashDriverPrompt(prompt),
	};
	await fsp.mkdir(files.tmpDir, { recursive: true });
	await writeJsonFile(files.driverPromptPath, promptMetadata);
	if (deps.shouldSkipDriverKickoffForTests()) {
		deps.emitCommandText(ctx, `Skipped completion workflow ${kind} prompt (test mode)`, "info");
		return false;
	}
	pi.sendUserMessage(prompt);
	deps.emitCommandText(ctx, `Queued completion workflow ${kind}`, "info");
	return true;
}

export async function autoContinueWorkflowIfNeeded(
	pi: ExtensionAPI,
	ctx: { cwd: string; hasUI: boolean; ui: any },
	deps: CompletionDriverDeps,
): Promise<void> {
	if (roleFromEnv()) return;
	const snapshot = await loadCompletionSnapshot(deps.getCtxCwd(ctx));
	const rootKey = deps.completionRootKey(snapshot, deps.getCtxCwd(ctx));
	if (!snapshot) {
		clearDriverContinuationTracker(rootKey);
		return;
	}
	const fingerprint = completionContinuationFingerprint(snapshot);
	if (!fingerprint) {
		clearDriverContinuationTracker(rootKey);
		return;
	}
	if (!isWorkflowDriverActive(snapshot) || deps.hasRunningCompletionRole(rootKey)) return;
	const tracker = driverContinuationByRoot.get(rootKey);
	if (tracker && tracker.fingerprint === fingerprint && tracker.attempts >= DRIVER_AUTO_CONTINUE_MAX_ATTEMPTS) {
		if (!isDriverContinuationStateParked(rootKey, fingerprint)) {
			rememberParkedDriverContinuation(rootKey, fingerprint);
			deps.emitCommandText(
				ctx,
				`Completion workflow is parked before mandatory role dispatch: ${asString(snapshot.state?.next_mandatory_role) ?? "(unknown)"}. Rerun /cook to continue from canonical state.`,
				"warning",
			);
		}
		return;
	}
	const resumePrompt = deps.completionResumePrompt(
		currentTaskType(snapshot) ?? "(missing)",
		currentEvaluationProfile(snapshot) ?? "(missing)",
		asString(snapshot.state?.workflow_session_id),
	);
	await queueCompletionDriverPrompt(pi, ctx, resumePrompt, "auto-resume", deps, { rootKey, fingerprint });
}

async function assessActiveWorkflowProposalRouting(
	ctx: DriverContext,
	snapshot: CompletionStateSnapshot,
	deps: CompletionDriverDeps,
): Promise<ActiveWorkflowProposalAssessment> {
	const currentMission = currentMissionAnchor(snapshot);
	const projectName = path.basename(snapshot.files.root);
	const proposalResult = await deps.deriveCookContextProposal(ctx, projectName);
	const proposal = proposalResult.proposal;
	if (!proposal) {
		const assessment: ActiveWorkflowProposalAssessment = {
			action: "continue",
			currentMissionAnchor: currentMission,
			reason: "missing_explicit_handoff",
		};
		deps.maybeWriteActiveWorkflowRoutingSnapshot(assessment);
		return assessment;
	}
	if (deps.missionAnchorsLikelyEquivalent(currentMission, proposal.mission)) {
		const assessment: ActiveWorkflowProposalAssessment = {
			action: "continue",
			currentMissionAnchor: currentMission,
			proposal,
			reason: "matching_mission",
		};
		deps.maybeWriteActiveWorkflowRoutingSnapshot(assessment);
		return assessment;
	}
	const assessment: ActiveWorkflowProposalAssessment = {
		action: "refocus",
		currentMissionAnchor: currentMission,
		proposal,
		reason: "fresh_explicit_handoff",
	};
	deps.maybeWriteActiveWorkflowRoutingSnapshot(assessment);
	return assessment;
}

async function resumeActiveWorkflowFromCanonicalState(
	pi: ExtensionAPI,
	ctx: { cwd: string; hasUI: boolean; ui: any },
	snapshot: CompletionStateSnapshot,
	deps: CompletionDriverDeps,
): Promise<void> {
	const mission = currentMissionAnchor(snapshot);
	pi.setSessionName(`completion: ${mission.slice(0, 60)}`);
	const resumePrompt = deps.completionResumePrompt(
		currentTaskType(snapshot) ?? "(missing)",
		currentEvaluationProfile(snapshot) ?? "(missing)",
		asString(snapshot.state?.workflow_session_id),
	);
	const resumeKind = deps.shouldTestAutoContinueOnSessionStart() && deps.completionTestAutoContinuePromptPath() ? "auto-resume" : "resume";
	await queueCompletionDriverPrompt(pi, ctx, resumePrompt, resumeKind, deps);
}

async function confirmExistingWorkflowProposal(
	ctx: { hasUI: boolean; ui: any },
	snapshot: CompletionStateSnapshot,
	proposal: ContextProposal,
	deps: CompletionDriverDeps,
	options: ExistingWorkflowChooserOptions = {},
): Promise<ExistingWorkflowDecision | undefined> {
	const currentMission = currentMissionAnchor(snapshot);
	const comparison = options.comparison ?? "semantic";
	const candidateProposals = [proposal, ...(proposal.alternateProposals ?? [])].filter((candidate, index, list) =>
		list.findIndex((other) => deps.missionAnchorsStrictlyEquivalent(other.mission, candidate.mission)) === index,
	);
	const missionMatches = (candidate: ContextProposalAlternate): boolean =>
		comparison === "strict"
			? deps.missionAnchorsStrictlyEquivalent(currentMission, candidate.mission)
			: deps.missionAnchorsLikelyEquivalent(currentMission, candidate.mission);
	if (candidateProposals.some((candidate) => missionMatches(candidate))) {
		return { action: "continue", currentMissionAnchor: currentMission };
	}
	const titleLines = [
		"Existing completion workflow found",
		"",
		options.intro ?? "A workflow is already in progress. Choose how /cook should proceed:",
		"",
		"Current mission",
		currentMission,
		"",
		options.proposedMissionLabel ?? "Primary proposed mission",
		proposal.mission,
	];
	if (candidateProposals.length > 1) {
		titleLines.push("", "Alternate recent missions", ...candidateProposals.slice(1).map((candidate) => candidate.mission));
	}
	const title = titleLines.join("\n");
	const continueChoice = "Continue current workflow\n\nKeep the current mission and treat the new goal as extra direction only.";
	const buildRefocusChoice = (candidate: ContextProposalAlternate, variant: "primary" | "alternate") =>
		variant === "primary"
			? `${options.refocusChoiceLabel ?? "Start new workflow from recent discussion\n\nReview the proposed replacement in a final Start/Cancel confirmation before /cook rewrites canonical workflow state."}\n\n${summarizeProposalForChoice(candidate)}`
			: `${options.alternateChoiceLabel ?? "Start alternate workflow from recent discussion\n\nReview this alternate replacement in a final Start/Cancel confirmation before /cook rewrites canonical workflow state."}\n\n${summarizeProposalForChoice(candidate)}`;
	const refocusChoices = candidateProposals.map((candidate, index) => buildRefocusChoice(candidate, index === 0 ? "primary" : "alternate"));
	const cancelChoice = `Cancel\n\nKeep the current workflow unchanged. ${deps.mainChatRerunGuidance}`;
	deps.maybeWriteTestSnapshot(
		deps.completionTestExistingWorkflowChooserSnapshotPath(),
		`${JSON.stringify({ title, candidateMissions: candidateProposals.map((candidate) => candidate.mission), choices: [continueChoice, ...refocusChoices, cancelChoice] }, null, 2)}\n`,
	);
	const missionOverride = deps.completionTestWorkflowMissionOverride();
	if (missionOverride) {
		const matched = candidateProposals.find((candidate) => deps.missionAnchorsStrictlyEquivalent(candidate.mission, missionOverride));
		if (matched) {
			return {
				action: "refocus",
				currentMissionAnchor: currentMission,
				missionAnchor: matched.mission,
				proposal: { ...matched, alternateProposals: [] },
			};
		}
	}
	const actionOverride = deps.completionTestWorkflowActionOverride();
	if (actionOverride === "continue") {
		return { action: "continue", currentMissionAnchor: currentMission };
	}
	if (actionOverride === "refocus") {
		return { action: "refocus", currentMissionAnchor: currentMission, missionAnchor: proposal.mission, proposal };
	}
	if (actionOverride === "cancel") return undefined;
	if (!deps.getCtxHasUI(ctx)) {
		return { action: "continue", currentMissionAnchor: currentMission };
	}
	const ui = deps.getCtxUi(ctx);
	if (!ui) {
		return { action: "continue", currentMissionAnchor: currentMission };
	}
	const choice = await ui.select(title, [continueChoice, ...refocusChoices, cancelChoice]);
	if (!choice || choice === cancelChoice) return undefined;
	if (choice === continueChoice) {
		return { action: "continue", currentMissionAnchor: currentMission };
	}
	const matchedIndex = refocusChoices.indexOf(choice);
	if (matchedIndex >= 0) {
		const selected = candidateProposals[matchedIndex];
		return {
			action: "refocus",
			currentMissionAnchor: currentMission,
			missionAnchor: selected.mission,
			proposal: matchedIndex === 0 ? proposal : { ...selected, alternateProposals: [] },
		};
	}
	return { action: "continue", currentMissionAnchor: currentMission };
}

async function refocusCompletionMission(
	snapshot: CompletionStateSnapshot,
	missionAnchor: string,
	rawGoal: string,
	analysis: ContextProposalAnalysis | undefined,
	deps: CompletionDriverDeps,
	advisoryStartupBrief?: Record<string, unknown>,
): Promise<void> {
	const requiredStopJudges = asNumber(snapshot.profile?.required_stop_judges) ?? 2;
	const root = snapshot.files.root;
	const routing = deps.finalizeContextProposalAnalysis(analysis, [rawGoal, missionAnchor]);
	const nextState = {
		...defaultState(missionAnchor, {
			taskType: routing.taskType,
			evaluationProfile: routing.evaluationProfile,
			continuationReason: deps.buildContextProposalContinuationReason("User refocused workflow via /cook:", rawGoal, routing),
		}, advisoryStartupBrief, { requiredStopJudges }),
		remaining_stop_judges: requiredStopJudges,
		next_mandatory_action: "Reconcile canonical state from current repo truth for the refocused mission",
	};
	const nextPlan = {
		...defaultPlan(missionAnchor, { taskType: routing.taskType, evaluationProfile: routing.evaluationProfile }),
		plan_basis: "user_refocus",
	};
	const nextActive = defaultActiveSlice(missionAnchor, { taskType: routing.taskType, evaluationProfile: routing.evaluationProfile });
	await removeCompletionRuntimeState(snapshot.files);
	await fsp.mkdir(snapshot.files.currentDir, { recursive: true });
	await fsp.mkdir(snapshot.files.tmpDir, { recursive: true });
	await Promise.all([
		writeJsonFile(snapshot.files.statePath, nextState),
		writeJsonFile(snapshot.files.startupBriefPath, defaultStartupBrief(missionAnchor, { taskType: routing.taskType, evaluationProfile: routing.evaluationProfile }, advisoryStartupBrief)),
		writeJsonFile(snapshot.files.planPath, nextPlan),
		writeJsonFile(snapshot.files.activePath, nextActive),
		writeJsonFile(snapshot.files.verificationEvidencePath, defaultVerificationEvidence()),
		fsp.writeFile(snapshot.files.sliceHistoryPath, "", "utf8"),
		fsp.writeFile(snapshot.files.stopHistoryPath, "", "utf8"),
	]);
}

function isWorkflowDone(snapshot: CompletionStateSnapshot | undefined): boolean {
	return asString(snapshot?.state?.continuation_policy) === "done";
}

export async function runCookEntry(
	pi: ExtensionAPI,
	ctx: DriverContext,
	deps: CompletionDriverDeps,
): Promise<void> {
	let goal: string | undefined;
	const inlinePrompt = asString(ctx.cookInlinePrompt);
	const cwd = deps.getCtxCwd(ctx);
	let snapshot = await loadCompletionSnapshot(cwd);
	const workflowDone = isWorkflowDone(snapshot);
	let kickoffIntent: "auto" | "continue" | "refocus" = "auto";
	let kickoffMissionAnchor = snapshot ? currentMissionAnchor(snapshot) : undefined;
	let kickoffAnalysis: ContextProposalAnalysis | undefined;

	if (!snapshot) {
		const root = findRepoRoot(cwd) ?? cwd;
		const projectName = path.basename(root);
		const derived = await deps.deriveCookContextProposal(ctx, projectName);
		const proposal = derived.proposal;
		if (!proposal) {
			deps.emitCommandText(ctx, buildCookStartupBriefRequiredMessage(deps), "info");
			return;
		}
		const decision = await deps.confirmContextProposal(ctx, proposal, {
			title: "Start a completion workflow from this startup brief?",
		});
		if (!decision) {
			deps.emitCommandText(ctx, buildCookCancellationMessage("Cancelled recent-discussion workflow proposal", deps), "info");
			return;
		}
		goal = decision.goalText;
		kickoffMissionAnchor = decision.missionAnchor;
		kickoffAnalysis = decision.analysis;
		const startupRouting = deps.finalizeContextProposalAnalysis(kickoffAnalysis, [goal ?? kickoffMissionAnchor ?? projectName]);
		const created = await deps.scaffoldCompletionFiles(root, kickoffMissionAnchor ?? projectName, {
			analysis: startupRouting,
			continuationReason: deps.buildContextProposalContinuationReason(
				"User started workflow via /cook:",
				goal ?? kickoffMissionAnchor ?? projectName,
				startupRouting,
			),
			advisoryStartupBrief: buildAdvisoryStartupBrief({ proposal, analysis: decision.analysis }),
		});
		deps.emitCommandText(
			ctx,
			`Started completion workflow for: ${kickoffMissionAnchor ?? projectName}. Saved canonical startup brief in ${created.root}/.agent/current/startup-brief.json; completion-regrounder will derive the initial slice plan from repo truth.${created.created.length > 0 ? ` (${created.created.length} files created)` : ""}`,
			"info",
		);
		snapshot = await loadCompletionSnapshot(root);
	}
	if (!snapshot) {
		deps.emitCommandText(ctx, "Failed to load completion workflow state", "error");
		return;
	}
	deps.activateCompletionRoutingForRoot(snapshot.files.root);
	if (!goal) {
		if (workflowDone) {
			const projectName = path.basename(snapshot.files.root);
			const derived = await deps.deriveCookContextProposal(ctx, projectName);
			const proposal = derived.proposal;
			if (!proposal) {
				deps.emitCommandText(ctx, buildCookStartupBriefRequiredMessage(deps, "The previous completion workflow is already done."), "info");
				return;
			}
			const decision = await deps.confirmContextProposal(ctx, proposal, {
				title: "The previous completion workflow is done. Start the next workflow round from this startup brief?",
			});
			if (!decision) {
				deps.emitCommandText(ctx, buildCookCancellationMessage("Cancelled next workflow round proposal", deps), "info");
				return;
			}
			goal = decision.goalText;
			kickoffIntent = "refocus";
			kickoffMissionAnchor = decision.missionAnchor;
			await refocusCompletionMission(
				snapshot,
				decision.missionAnchor,
				decision.goalText,
				decision.analysis,
				deps,
				buildAdvisoryStartupBrief({ proposal, analysis: decision.analysis }),
			);
			snapshot = (await loadCompletionSnapshot(snapshot.files.root)) ?? snapshot;
			deps.emitCommandText(
				ctx,
				`Started a new completion workflow round for: ${decision.missionAnchor}. Saved canonical startup brief; completion-regrounder will derive the next slices from repo truth.`,
				"info",
			);
		} else {
			const assessment = await assessActiveWorkflowProposalRouting(ctx, snapshot, deps);
			if (!assessment.proposal || assessment.action === "continue") {
				await resumeActiveWorkflowFromCanonicalState(pi, ctx, snapshot, deps);
				return;
			}
			const explicitReplacement = assessment.reason === "fresh_explicit_handoff";
			const decision = await confirmExistingWorkflowProposal(ctx, snapshot, assessment.proposal, deps, {
				intro: explicitReplacement
					? "A fresh explicit primary-agent handoff proposes replacing the current workflow. Choose how /cook should proceed:"
					: "A replacement workflow is ready. Choose how /cook should proceed:",
				proposedMissionLabel: explicitReplacement
					? "Proposed mission from explicit primary-agent handoff"
					: "Proposed mission",
				refocusChoiceLabel: explicitReplacement
					? "Start new workflow from explicit primary-agent handoff\n\nReview the proposed replacement in a final Start/Cancel confirmation before /cook rewrites canonical workflow state."
					: "Start new workflow\n\nReview the proposed replacement in a final Start/Cancel confirmation before /cook rewrites canonical workflow state.",
				alternateChoiceLabel: explicitReplacement
					? "Start alternate workflow from explicit primary-agent handoff\n\nReview this alternate replacement in a final Start/Cancel confirmation before /cook rewrites canonical workflow state."
					: undefined,
				comparison: "strict",
			});
			if (!decision) {
				deps.emitCommandText(ctx, buildCookCancellationMessage("Cancelled existing workflow confirmation", deps), "info");
				return;
			}
			if (decision.action === "continue") {
				await resumeActiveWorkflowFromCanonicalState(pi, ctx, snapshot, deps);
				return;
			}
			const selectedProposal = decision.proposal;
			const proposalDecision = await deps.confirmContextProposal(ctx, selectedProposal, {
				title: assessment.reason === "fresh_explicit_handoff"
					? "Start the replacement workflow from this explicit startup brief?"
					: "Start the replacement workflow from this startup brief?",
			});
			if (!proposalDecision) {
				deps.emitCommandText(ctx, buildCookCancellationMessage("Cancelled replacement workflow proposal", deps), "info");
				return;
			}
			goal = proposalDecision.goalText;
			kickoffIntent = "refocus";
			kickoffMissionAnchor = proposalDecision.missionAnchor;
			await refocusCompletionMission(
				snapshot,
				proposalDecision.missionAnchor,
				proposalDecision.goalText,
				proposalDecision.analysis,
				deps,
				buildAdvisoryStartupBrief({ proposal: selectedProposal, analysis: proposalDecision.analysis }),
			);
			snapshot = (await loadCompletionSnapshot(snapshot.files.root)) ?? snapshot;
			deps.emitCommandText(
				ctx,
				`Refocused completion workflow to: ${proposalDecision.missionAnchor}. Saved canonical startup brief; completion-regrounder will derive updated slices from repo truth.`,
				"info",
			);
		}
	}
	kickoffMissionAnchor = kickoffMissionAnchor ?? currentMissionAnchor(snapshot);
	const kickoffGoal = goal ?? kickoffMissionAnchor ?? inlinePrompt;
	pi.setSessionName(`completion: ${kickoffMissionAnchor.slice(0, 60)}`);
	const kickoffPrompt = deps.completionKickoff(
		kickoffGoal,
		currentTaskType(snapshot) ?? "(missing)",
		currentEvaluationProfile(snapshot) ?? "(missing)",
		kickoffIntent,
		kickoffMissionAnchor,
		asString(snapshot.state?.workflow_session_id),
	);
	await queueCompletionDriverPrompt(pi, ctx, kickoffPrompt, "kickoff", deps);
}

export function registerCookCommand(pi: ExtensionAPI, deps: CompletionDriverDeps): void {
	pi.registerCommand("cook", {
		description: deps.cookCommandSpec.description,
		handler: async (args, ctx) => {
			const inlinePrompt = asString(args);
			await runCookEntry(pi, { ...ctx, cookInlinePrompt: inlinePrompt }, deps);
		},
	});
}
