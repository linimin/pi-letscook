import { createHash } from "node:crypto";
import * as fs from "node:fs";
import { promises as fsp } from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import { StringEnum } from "@mariozechner/pi-ai";
import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";
import { DynamicBorder } from "@mariozechner/pi-coding-agent";
import { Container, matchesKey, SelectList, Text } from "@mariozechner/pi-tui";
import { Type } from "typebox";
import {
	autoContinueWorkflowIfNeeded,
	registerCookCommand,
} from "./driver";
import {
	assessMissionAnchor,
	collectRecentSessionMessages,
	finalizeContextProposalAnalysis,
	isWeakMissionAnchor,
	missionAnchorsStrictlyEquivalent,
	normalizeMissionAnchorText,
	resolveContextProposalConfirmationAction,
	stripCodeBlocks,
} from "./proposal";
import type {
	ContextProposal,
	ContextProposalAnalysis,
	ContextProposalConfirmAction,
	ContextProposalConfirmOptions,
	ContextProposalConfirmationLayout,
	ContextProposalDecision,
} from "./proposal";
import {
	buildContextProposalConfirmationLayout as buildExtractedContextProposalConfirmationLayout,
	buildContextProposalConfirmationSelectItems,
	buildContextProposalContinuationReason as buildExtractedContextProposalContinuationReason,
	buildCookHandoffBoundaryReminder as buildExtractedCookHandoffBoundaryReminder,
	buildEvaluationRoleContextLines as buildExtractedEvaluationRoleContextLines,
	buildEvaluationRoleReminderText as buildExtractedEvaluationRoleReminderText,
	buildResumeCapsule as buildExtractedResumeCapsule,
	buildStoppedWorkflowBoundaryReminder as buildExtractedStoppedWorkflowBoundaryReminder,
	buildSystemReminder as buildExtractedSystemReminder,
	maybeWriteContextProposalConfirmationSnapshot,
	maybeWriteContextProposalSnapshot,
} from "./prompt-surfaces";
import { deriveCookContextProposalWithSynthesis } from "./startup-intent";
import type { CookContextProposalResult, CookProposalDeps } from "./startup-intent";
import { toolCallBlockReason } from "./policy-guards";
import { generateCookHandoffWithAgent, runCompletionRole } from "./role-runner";
import { canRoleUseCompletionAssist, COMPLETION_ASSIST_TOOL_NAME } from "./helper-policy.ts";
import { runCompletionAssistTool } from "./helper-runner.ts";
import { COMPLETION_HELPER_NAMES, type CompletionHelperName } from "./helper-types.ts";
import {
	applyLiveRoleEvent,
	buildInlineRunningLines,
	cloneLiveRoleActivity,
	createLiveRoleActivity,
	formatElapsed,
	formatInlineRunningText,
	nowMs,
	refreshCompletionStatus,
	truncateInline,
} from "./status-surface";
import {
	asNumber,
	asString,
	asStringArray,
	completionRootKey,
	currentEvaluationProfile,
	currentTaskType,
	findCompletionRoot,
	findRepoRoot,
	isRecord,
	loadCompletionDataForReminder,
	loadCompletionSnapshot,
	loadCompletionStateProbe,
	pathExists,
	readText,
	removeCompletionAgentDir,
	scaffoldCompletionFiles as scaffoldCompletionFilesOnDisk,
} from "./state-store";
import type { TranscriptionResult } from "./transcription";
import type {
	CompletionStateSnapshot,
	CompletionRole,
	JsonRecord,
	LiveRoleActivity,
	StartupAnalysisConfidence,
	StartupWorkflowRelation,
} from "./types";

const ROLE_NAMES = [
	"completion-bootstrapper",
	"completion-regrounder",
	"completion-implementer",
	"completion-reviewer",
	"completion-auditor",
	"completion-stop-judge",
] as const;
const AGENT_HOME = path.join(os.homedir(), ".pi", "agent");
const COMPLETION_STATUS_KEY = "completion";
const EXTENSION_DIR = typeof __dirname === "string" ? __dirname : process.cwd();
const PACKAGE_ROOT_CANDIDATE = path.resolve(EXTENSION_DIR, "..", "..");
const PACKAGE_ROOT = fs.existsSync(path.join(PACKAGE_ROOT_CANDIDATE, "package.json")) ? PACKAGE_ROOT_CANDIDATE : undefined;
const PACKAGE_SKILL_PATH = PACKAGE_ROOT ? path.join(PACKAGE_ROOT, "skills", "completion-protocol", "SKILL.md") : undefined;
const PACKAGE_RUNTIME_QUICK_REFERENCES_DIR = PACKAGE_ROOT
	? path.join(PACKAGE_ROOT, "skills", "completion-protocol", "references")
	: undefined;
const PACKAGE_RUNTIME_QUICK_REFERENCE_PATH = PACKAGE_RUNTIME_QUICK_REFERENCES_DIR
	? path.join(PACKAGE_RUNTIME_QUICK_REFERENCES_DIR, "runtime-quick.md")
	: undefined;
const PACKAGE_REFERENCE_PATH = PACKAGE_ROOT
	? path.join(PACKAGE_ROOT, "skills", "completion-protocol", "references", "completion.md")
	: undefined;
const SKILL_PATH = PACKAGE_SKILL_PATH ?? path.join(AGENT_HOME, "skills", "completion-protocol", "SKILL.md");
const RUNTIME_QUICK_REFERENCE_DIR = path.join(AGENT_HOME, "skills", "completion-protocol", "references");
const RUNTIME_QUICK_REFERENCE_PATH = PACKAGE_RUNTIME_QUICK_REFERENCE_PATH
	?? path.join(RUNTIME_QUICK_REFERENCE_DIR, "runtime-quick.md");
const ROLE_RUNTIME_QUICK_REFERENCE_FILENAMES: Record<CompletionRole | "driver", string> = {
	driver: "runtime-quick-driver.md",
	"completion-bootstrapper": "runtime-quick-bootstrapper.md",
	"completion-regrounder": "runtime-quick-regrounder.md",
	"completion-implementer": "runtime-quick-implementer.md",
	"completion-reviewer": "runtime-quick-reviewer.md",
	"completion-auditor": "runtime-quick-auditor.md",
	"completion-stop-judge": "runtime-quick-stop-judge.md",
};
const REFERENCE_PATH = PACKAGE_REFERENCE_PATH ?? path.join(RUNTIME_QUICK_REFERENCE_DIR, "completion.md");
const DEFAULT_TASK_TYPE = "completion-workflow";
const DEFAULT_EVALUATION_PROFILE = "completion-rubric-v1";
const RUBRIC_EVALUATION_ROLES = ["completion-reviewer", "completion-auditor", "completion-stop-judge"] as const;

type RubricEvaluationRole = (typeof RUBRIC_EVALUATION_ROLES)[number];

const liveRoleActivityByRoot = new Map<string, LiveRoleActivity>();
const LIVE_ROLE_HEARTBEAT_MS = 5_000;

function asBoolean(value: unknown): boolean | undefined {
	return typeof value === "boolean" ? value : undefined;
}

function roleFromEnv(): string | undefined {
	return asString(process.env.PI_COMPLETION_ROLE);
}

function roleModelFromEnv(): string | undefined {
	return asString(process.env.PI_COMPLETION_ROLE_MODEL);
}

function modelArgFromContextModel(model: unknown): string | undefined {
	if (!isRecord(model)) return undefined;
	const provider = asString(model.provider);
	const id = asString(model.id);
	return provider && id ? `${provider}/${id}` : undefined;
}

function candidateSlices(plan: JsonRecord | undefined): JsonRecord[] {
	const slices = plan?.candidate_slices;
	return Array.isArray(slices) ? slices.filter(isRecord) : [];
}

type ActiveWorkflowProposalAssessmentReason =
	| "workflow_relation_continue"
	| "workflow_relation_refocus"
	| "missing_replacement_proposal"
	| "missing_routing_signal"
	| "primary_agent_handoff";

type ActiveWorkflowRoutingSignalSource = "none" | "startup_analysis" | "explicit_structured_artifact";

type ActiveWorkflowProposalAssessment = {
	action: "continue" | "refocus";
	currentMissionAnchor: string;
	proposal?: ContextProposal;
	reason: ActiveWorkflowProposalAssessmentReason;
	workflowRelation?: StartupWorkflowRelation;
	confidence?: StartupAnalysisConfidence;
	signalSource: ActiveWorkflowRoutingSignalSource;
};

function completionTestWorkflowActionOverride(): "continue" | "refocus" | "cancel" | undefined {
	const raw = process.env.PI_COMPLETION_EXISTING_WORKFLOW_ACTION?.trim().toLowerCase();
	return raw === "continue" || raw === "refocus" || raw === "cancel" ? raw : undefined;
}

function completionTestWorkflowMissionOverride(): string | undefined {
	return asString(process.env.PI_COMPLETION_EXISTING_WORKFLOW_MISSION);
}

function shouldSkipDriverKickoffForTests(): boolean {
	return process.env.PI_COMPLETION_SKIP_DRIVER_KICKOFF === "1";
}

function completionTestContextProposalActionOverride(): "accept" | "cancel" | undefined {
	const raw = process.env.PI_COMPLETION_CONTEXT_PROPOSAL_ACTION?.trim().toLowerCase();
	return raw === "accept" || raw === "cancel" ? raw : undefined;
}

function completionTestContextProposalUiActionOverride(): ContextProposalConfirmAction | undefined {
	const raw = process.env.PI_COMPLETION_TEST_CONTEXT_PROPOSAL_UI_ACTION?.trim().toLowerCase();
	return raw === "start" || raw === "cancel" ? raw : undefined;
}

function completionTestExistingWorkflowChooserSnapshotPath(): string | undefined {
	return asString(process.env.PI_COMPLETION_TEST_EXISTING_WORKFLOW_CHOOSER_PATH);
}

function completionTestContextProposalUiSnapshotPath(): string | undefined {
	return asString(process.env.PI_COMPLETION_TEST_CONTEXT_PROPOSAL_UI_PATH);
}

function completionTestContextProposalSnapshotPath(): string | undefined {
	return asString(process.env.PI_COMPLETION_TEST_CONTEXT_PROPOSAL_PATH);
}

function completionTestActiveWorkflowRoutingSnapshotPath(): string | undefined {
	return asString(process.env.PI_COMPLETION_TEST_ACTIVE_WORKFLOW_ROUTING_PATH);
}

function completionTestDriverPromptPath(): string | undefined {
	return asString(process.env.PI_COMPLETION_TEST_DRIVER_PROMPT_PATH);
}

function completionTestForcedCompletionRole(): CompletionRole | undefined {
	const raw = asString(process.env.PI_COMPLETION_TEST_FORCE_COMPLETION_ROLE);
	return ROLE_NAMES.includes(raw as CompletionRole) ? raw as CompletionRole : undefined;
}

function completionTestForcedCompletionTask(): string | undefined {
	return asString(process.env.PI_COMPLETION_TEST_FORCE_COMPLETION_TASK);
}

function completionTestAutoContinuePromptPath(): string | undefined {
	return asString(process.env.PI_COMPLETION_TEST_AUTO_CONTINUE_PROMPT_PATH);
}

function shouldTestAutoContinueOnSessionStart(): boolean {
	return process.env.PI_COMPLETION_TEST_AUTO_CONTINUE_ON_SESSION_START === "1";
}

function completionTestSystemReminderPath(): string | undefined {
	return asString(process.env.PI_COMPLETION_TEST_SYSTEM_REMINDER_PATH);
}

function completionTestCookHandoffReminderPath(): string | undefined {
	return asString(process.env.PI_COMPLETION_TEST_COOK_HANDOFF_REMINDER_PATH);
}

function maybeWriteTestSnapshot(targetPath: string | undefined, content: string): void {
	if (!targetPath) return;
	try {
		fs.mkdirSync(path.dirname(targetPath), { recursive: true });
		fs.writeFileSync(targetPath, content, "utf8");
	} catch {
		// ignore malformed or unwritable test snapshot paths
	}
}

const COOK_MAIN_CHAT_RERUN_GUIDANCE = "Discuss changes in the main chat and rerun /cook.";
const COOK_STRUCTURED_DISCUSSION_FAILURE_DETAIL =
	"/cook failed closed because the primary-agent startup step could not prepare a workflow startup brief from the current task context. Clarify the mission, repo-change intent, or key constraints in the main chat, then rerun /cook.";

function isWorkflowDone(snapshot: CompletionStateSnapshot | undefined): boolean {
	return asString(snapshot?.state?.continuation_policy) === "done";
}

function hasWorkflowRecord(snapshot: CompletionStateSnapshot | undefined): boolean {
	return Boolean(snapshot) && !isWorkflowDone(snapshot);
}

function workflowEntryStatus(snapshot: CompletionStateSnapshot | undefined): string | undefined {
	if (!hasWorkflowRecord(snapshot)) return undefined;
	return asString(snapshot?.state?.workflow_entry_status)?.toLowerCase() ?? "active";
}

function activateCompletionRoutingForRoot(_root: string | undefined): void {
	// Workflow-entry legitimacy is derived from canonical .agent state rather than in-memory routing activation.
}

function hasActiveWorkflowEntry(snapshot: CompletionStateSnapshot | undefined): boolean {
	return workflowEntryStatus(snapshot) === "active";
}

function workflowHardLockActive(snapshot: CompletionStateSnapshot | undefined): boolean {
	return hasActiveWorkflowEntry(snapshot);
}

function hasCompletionRoutingActivation(snapshot: CompletionStateSnapshot | undefined): boolean {
	if (!snapshot) return false;
	if (roleFromEnv()) return true;
	return false;
}

function latestUserOrCustomTurnText(ctx: { sessionManager?: any }): string | undefined {
	const messages = collectRecentSessionMessages(ctx as { sessionManager: any }, { isRecord, asString, asNumber, isStaleContextError }, 4);
	return messages.find((entry) => entry.role === "user" || entry.role === "custom")?.text;
}

function hashDriverPrompt(prompt: string): string {
	return createHash("sha256").update(prompt).digest("hex");
}

function queuedDriverPromptMetadata(snapshot: CompletionStateSnapshot | undefined): JsonRecord | undefined {
	const promptPath = snapshot?.files.driverPromptPath;
	if (!promptPath || !fs.existsSync(promptPath)) return undefined;
	try {
		const raw = fs.readFileSync(promptPath, "utf8");
		const parsed = JSON.parse(raw);
		return isRecord(parsed) ? parsed : undefined;
	} catch {
		return undefined;
	}
}

function isCookCommandTurn(ctx: { sessionManager?: any }): boolean {
	const latest = latestUserOrCustomTurnText(ctx);
	if (!latest) return false;
	return /^\/cook\b/.test(latest.trim());
}

function extractWorkflowSessionIdFromPrompt(text: string): string | undefined {
	const match = text.match(/^- workflow_session_id:\s*(.+)$/m);
	return match?.[1]?.trim() || undefined;
}

function isCompletionDriverPromptTurn(snapshot: CompletionStateSnapshot | undefined, ctx: { sessionManager?: any }): boolean {
	const latest = latestUserOrCustomTurnText(ctx);
	if (!latest) return false;
	const canonicalSessionId = asString(snapshot?.state?.workflow_session_id);
	const promptSessionId = extractWorkflowSessionIdFromPrompt(latest);
	if (canonicalSessionId && promptSessionId && canonicalSessionId !== promptSessionId) return false;
	const queuedPrompt = queuedDriverPromptMetadata(snapshot);
	const queuedPromptHash = asString(queuedPrompt?.prompt_hash);
	if (queuedPromptHash && queuedPromptHash === hashDriverPrompt(latest)) {
		const queuedSessionId = asString(queuedPrompt?.workflow_session_id);
		if (canonicalSessionId && queuedSessionId && queuedSessionId !== canonicalSessionId) return false;
		return true;
	}
	const isLegacySkillPrompt = /^\/skill:completion-protocol\b/.test(latest);
	const isWorkflowDriverPrompt = /^COMPLETION WORKFLOW DRIVER\b/m.test(latest);
	if (!isLegacySkillPrompt && !isWorkflowDriverPrompt) return false;
	if (!/(?:Start or continue the completion workflow for this repo\.|Resume the completion workflow from canonical state\.)/.test(latest)) return false;
	return true;
}

function workflowContinuationIntentText(text: string | undefined): string {
	return (text ?? "").trim().toLowerCase();
}

function hasStickyWorkflowContinuation(snapshot: CompletionStateSnapshot | undefined): boolean {
	if (!hasActiveWorkflowEntry(snapshot)) return false;
	if (asString(snapshot?.state?.continuation_policy) !== "continue") return false;
	return !!asString(snapshot?.state?.next_mandatory_role);
}

function isLikelyWorkflowContinuationTurn(
	snapshot: CompletionStateSnapshot | undefined,
	ctx: { sessionManager?: any },
): boolean {
	if (!hasActiveWorkflowEntry(snapshot)) return false;
	const latest = workflowContinuationIntentText(latestUserOrCustomTurnText(ctx));
	if (!latest) return false;
	if (isCookCommandTurn(ctx) || isCompletionDriverPromptTurn(snapshot, ctx)) return true;
	if (asString(snapshot?.state?.continuation_policy) === "await_user_input") return true;
	return /(\b(continue|resume|proceed|go ahead|keep going|next|finish|fix|repair|reconcile|commit|stash|audit|review|reground|implement|phase|slice|batch)\b|\.agent\b|\bworktree\b|\bworkflow\b|\bdirty\b|繼續|继续|開始|开始|先做|先把|修好|修復|修复|清理|處理|处理|提交|下一步|接著|继续做|做完|完成)/iu.test(latest);
}

function isCompletionWorkflowSessionTurn(snapshot: CompletionStateSnapshot | undefined, ctx: { sessionManager?: any }): boolean {
	if (hasCompletionRoutingActivation(snapshot)) return true;
	if (!hasWorkflowRecord(snapshot)) return false;
	if (isCookCommandTurn(ctx) || isCompletionDriverPromptTurn(snapshot, ctx)) return true;
	if (!hasActiveWorkflowEntry(snapshot)) return false;
	return isLikelyWorkflowContinuationTurn(snapshot, ctx);
}

function isCompletionWorkflowDispatchContext(snapshot: CompletionStateSnapshot | undefined, ctx: { sessionManager?: any }): boolean {
	return isCompletionWorkflowSessionTurn(snapshot, ctx) || hasStickyWorkflowContinuation(snapshot);
}

function shouldInjectCompletionWorkflowContext(snapshot: CompletionStateSnapshot | undefined, ctx: { sessionManager?: any }): boolean {
	return isCompletionWorkflowSessionTurn(snapshot, ctx);
}

function isStoppedWorkflowPolicy(snapshot: CompletionStateSnapshot | undefined): boolean {
	const continuationPolicy = asString(snapshot?.state?.continuation_policy);
	return continuationPolicy === "await_user_input" || continuationPolicy === "blocked" || continuationPolicy === "paused";
}

function shouldInjectStoppedWorkflowBoundary(
	event: { prompt?: string },
	ctx: { sessionManager?: any },
	snapshot?: CompletionStateSnapshot,
): boolean {
	if (roleFromEnv()) return false;
	if (!snapshot || isWorkflowDone(snapshot)) return false;
	if (!workflowHardLockActive(snapshot) || !isStoppedWorkflowPolicy(snapshot)) return false;
	if (isCompletionWorkflowSessionTurn(snapshot, ctx)) return false;
	const prompt = typeof event.prompt === "string" ? event.prompt.trim() : "";
	if (!prompt) return false;
	if (prompt.startsWith("/") || /^COMPLETION WORKFLOW DRIVER\b/m.test(prompt)) return false;
	return true;
}

function shouldInjectCookHandoffBoundary(
	event: { prompt?: string },
	ctx: { sessionManager?: any },
	snapshot?: CompletionStateSnapshot,
): boolean {
	if (roleFromEnv()) return false;
	if (!snapshot || isWorkflowDone(snapshot)) return false;
	if (isCompletionWorkflowSessionTurn(snapshot, ctx)) return false;
	const prompt = typeof event.prompt === "string" ? event.prompt.trim() : "";
	if (!prompt) return false;
	if (prompt.startsWith("/") || /^COMPLETION WORKFLOW DRIVER\b/m.test(prompt)) return false;
	return true;
}

function buildCookHandoffBoundaryReminder(): string {
	return buildExtractedCookHandoffBoundaryReminder();
}

function buildStoppedWorkflowBoundaryReminder(snapshot: CompletionStateSnapshot): string {
	return buildExtractedStoppedWorkflowBoundaryReminder({
		missionAnchor: asString(snapshot.state?.mission_anchor) ?? asString(snapshot.plan?.mission_anchor),
		continuationPolicy: asString(snapshot.state?.continuation_policy),
		continuationReason: asString(snapshot.state?.continuation_reason),
	});
}

function buildDoneWorkflowBoundaryReminder(snapshot: CompletionStateSnapshot): string {
	const missionAnchor = asString(snapshot.state?.mission_anchor) ?? asString(snapshot.plan?.mission_anchor) ?? "(unknown)";
	const continuationReason = asString(snapshot.state?.continuation_reason) ?? "(unknown)";
	return [
		"A previous completion workflow exists for this repo, but it is closed.",
		`Mission anchor: ${missionAnchor}`,
		`Continuation policy: ${asString(snapshot.state?.continuation_policy) ?? "unknown"}`,
		`Continuation reason: ${continuationReason}`,
		"Treat the previous completion workflow as historical context only.",
		"Do not resume, reground, refocus, reopen, or otherwise restart completion workflow from this context unless the user explicitly runs /cook.",
		"For ordinary user requests, respond normally and ignore prior completion-protocol instructions that were only relevant to the finished workflow.",
		"Only /cook may reactivate workflow routing for the next round.",
	].join(" ");
}

async function cleanupClosedWorkflowRuntimeIfNeeded(cwd: string): Promise<boolean> {
	const probe = await loadCompletionStateProbe(cwd);
	if (!probe?.isClosed) return false;
	await removeCompletionAgentDir(probe.files);
	return true;
}

function maybeWriteActiveWorkflowRoutingSnapshot(assessment: ActiveWorkflowProposalAssessment): void {
	const snapshotPath = completionTestActiveWorkflowRoutingSnapshotPath();
	if (!snapshotPath) return;
	maybeWriteTestSnapshot(
		snapshotPath,
		`${JSON.stringify(
			{
				mode: "bare",
				action: assessment.action,
				reason: assessment.reason,
				signalSource: assessment.signalSource,
				workflowRelation: assessment.workflowRelation ?? assessment.proposal?.analysis.workflowRelation ?? null,
				confidence: assessment.confidence ?? assessment.proposal?.analysis.confidence ?? null,
				startupVerdict: assessment.proposal?.analysis.startupVerdict ?? null,
				currentMissionAnchor: assessment.currentMissionAnchor,
				blockedFailureMessage: null,
				proposedMissionAnchor: assessment.proposal?.mission ?? null,
				proposalSource: assessment.proposal?.source ?? null,
				possibleNoise: assessment.proposal?.analysis.possibleNoise ?? [],
				alternateMissions: assessment.proposal?.analysis.alternateMissions ?? [],
				suppressedCompletedTopics: assessment.proposal?.analysis.suppressedCompletedTopics ?? [],
				suppressedNegatedTopics: assessment.proposal?.analysis.suppressedNegatedTopics ?? [],
				scope: assessment.proposal?.scope ?? [],
				constraints: assessment.proposal?.constraints ?? [],
				acceptance: assessment.proposal?.acceptance ?? [],
			},
			null,
			2,
		)}\n`,
	);
}

function buildContextProposalContinuationReason(prefix: string, goalText: string, analysis: ContextProposalAnalysis): string {
	return buildExtractedContextProposalContinuationReason(prefix, goalText, analysis, {
		defaultTaskType: DEFAULT_TASK_TYPE,
		defaultEvaluationProfile: DEFAULT_EVALUATION_PROFILE,
		truncateInline,
	});
}

function buildContextProposalConfirmationLayout(
	title: string,
	proposal: ContextProposal,
): ContextProposalConfirmationLayout {
	return buildExtractedContextProposalConfirmationLayout({
		title,
		proposal,
		analysis: finalizeContextProposalAnalysis(proposal.analysis),
		mainChatRerunGuidance: COOK_MAIN_CHAT_RERUN_GUIDANCE,
		defaultTaskType: DEFAULT_TASK_TYPE,
		defaultEvaluationProfile: DEFAULT_EVALUATION_PROFILE,
	});
}

async function promptContextProposalConfirmationAction(
	ui: any,
	layout: ContextProposalConfirmationLayout,
): Promise<ContextProposalConfirmAction | undefined> {
	const items = buildContextProposalConfirmationSelectItems(layout);
	return await ui.custom<ContextProposalConfirmAction | undefined>((tui: any, theme: any, _kb: any, done: any) => {
		const container = new Container();
		container.addChild(new DynamicBorder((s: string) => theme.fg("accent", s)));
		container.addChild(new Text(theme.fg("accent", theme.bold(layout.title)), 1, 0));
		container.addChild(new Text(layout.intro, 1, 0));
		container.addChild(new Text("", 0, 0));
		container.addChild(new Text(theme.fg("accent", theme.bold(layout.proposalHeading)), 1, 0));
		container.addChild(new Text(layout.proposalBody, 1, 0));
		if (layout.critiqueHeading && layout.critiqueBody) {
			container.addChild(new Text("", 0, 0));
			container.addChild(new Text(theme.fg("accent", theme.bold(layout.critiqueHeading)), 1, 0));
			container.addChild(new Text(layout.critiqueBody, 1, 0));
		}
		if (layout.routingHeading && layout.routingBody) {
			container.addChild(new Text("", 0, 0));
			container.addChild(new Text(theme.fg("accent", theme.bold(layout.routingHeading)), 1, 0));
			container.addChild(new Text(layout.routingBody, 1, 0));
		}
		container.addChild(new Text("", 0, 0));
		container.addChild(new Text(theme.fg("accent", theme.bold(layout.actionsHeading)), 1, 0));
		const selectList = new SelectList(items, items.length, {
			selectedPrefix: (text) => theme.fg("accent", text),
			selectedText: (text) => theme.fg("accent", text),
			description: (text) => theme.fg("muted", text),
			scrollInfo: (text) => text,
			noMatch: (text) => theme.fg("warning", text),
		});
		selectList.onSelect = (item) => done(item.value as ContextProposalConfirmAction);
		selectList.onCancel = () => done(undefined);
		container.addChild(selectList);
		container.addChild(new Text(layout.footer, 1, 0));
		container.addChild(new DynamicBorder((s: string) => theme.fg("accent", s)));

		return {
			render: (width: number) => container.render(width),
			invalidate: () => container.invalidate(),
			handleInput: (data: string) => {
				if (matchesKey(data, "escape")) {
					done(undefined);
					return;
				}
				selectList.handleInput(data);
				tui.requestRender();
			},
		};
	});
}

type CookProposalContext = {
	cwd: string;
	hasUI: boolean;
	ui: any;
	sessionManager: any;
	model?: any;
	modelRegistry?: any;
	cookInlinePrompt?: string;
};

function cookInlinePromptFromContext(ctx: { cookInlinePrompt?: string }): string | undefined {
	return asString(ctx.cookInlinePrompt);
}

function cookProposalDeps(): CookProposalDeps {
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

async function deriveCookContextProposal(
	ctx: CookProposalContext,
	projectName: string,
): Promise<CookContextProposalResult> {
	const inlinePrompt = cookInlinePromptFromContext(ctx);
	const recentMessages = collectRecentSessionMessages(ctx, { isRecord, asString, asNumber, isStaleContextError });
	const snapshot = await loadCompletionSnapshot(getCtxCwd(ctx));
	return await deriveCookContextProposalWithSynthesis({
		inlinePrompt,
		recentMessages,
		snapshot,
		projectName,
		deps: cookProposalDeps(),
		generateCookHandoff: async ({ recentEntries, workflowContextLines }) =>
			generateCookHandoffWithAgent({
				ctx,
				projectName,
				recentEntries,
				workflowContextLines,
				liveRoleActivityByRoot,
				completionStatusKey: COMPLETION_STATUS_KEY,
				safeUiCall,
				getCtxCwd,
				getCtxHasUI,
				getCtxUi,
			}),
	});
}

async function confirmContextProposal(
	ctx: { hasUI: boolean; ui: any },
	proposal: ContextProposal,
	options: ContextProposalConfirmOptions,
): Promise<ContextProposalDecision | undefined> {
	maybeWriteContextProposalSnapshot(proposal, completionTestContextProposalSnapshotPath());
	const actionOverride = completionTestContextProposalActionOverride();
	if (actionOverride === "cancel") return undefined;
	if (actionOverride === "accept") {
		return resolveContextProposalConfirmationAction(proposal, "start");
	}
	const layout = buildContextProposalConfirmationLayout(options.title, proposal);
	maybeWriteContextProposalConfirmationSnapshot(layout, completionTestContextProposalUiSnapshotPath());
	const uiActionOverride = completionTestContextProposalUiActionOverride();
	if (uiActionOverride) {
		return resolveContextProposalConfirmationAction(proposal, uiActionOverride);
	}
	if (!getCtxHasUI(ctx)) {
		return options.nonInteractiveBehavior === "accept" ? resolveContextProposalConfirmationAction(proposal, "start") : undefined;
	}
	const ui = getCtxUi(ctx);
	if (!ui) {
		return options.nonInteractiveBehavior === "accept" ? resolveContextProposalConfirmationAction(proposal, "start") : undefined;
	}
	const choice = await promptContextProposalConfirmationAction(ui, layout);
	if (!choice) return undefined;
	return resolveContextProposalConfirmationAction(proposal, choice);
}



async function scaffoldCompletionFiles(
	root: string,
	missionAnchor: string,
	options?: { analysis?: ContextProposalAnalysis; continuationReason?: string; advisoryStartupBrief?: JsonRecord },
) {
	const routing = finalizeContextProposalAnalysis(options?.analysis);
	return await scaffoldCompletionFilesOnDisk(root, missionAnchor, {
		analysis: { taskType: routing.taskType, evaluationProfile: routing.evaluationProfile },
		continuationReason: options?.continuationReason,
		advisoryStartupBrief: options?.advisoryStartupBrief,
	});
}

function remainingSliceCount(plan: JsonRecord | undefined): number {
	return candidateSlices(plan).filter((slice) => {
		const status = asString(slice.status);
		return status !== "done" && status !== "cancelled";
	}).length;
}

function historyCounts(sliceHistory: JsonRecord[], stopHistory: JsonRecord[]) {
	return {
		reviewed: sliceHistory.filter((item) => asString(item.type) === "reviewed").length,
		audited: sliceHistory.filter((item) => asString(item.type) === "audited").length,
		accepted: sliceHistory.filter((item) => asString(item.type) === "accepted").length,
		reopened: sliceHistory.filter((item) => asString(item.type) === "reopened").length,
		judgments: stopHistory.filter((item) => asString(item.type) === "judgment").length,
	};
}

function sameStringArrays(left: string[], right: string[]): boolean {
	return left.length === right.length && left.every((item, index) => item === right[index]);
}

function hasOwnField(record: JsonRecord | undefined, field: string): boolean {
	return !!record && Object.prototype.hasOwnProperty.call(record, field);
}

function activeCarriesExactHandoff(active: JsonRecord | undefined): boolean {
	const status = asString(active?.status);
	return status === "selected" || status === "in_progress" || status === "committed" || status === "done";
}

function activeSliceContractDriftFields(snapshot: CompletionStateSnapshot): string[] | undefined {
	const active = snapshot.active;
	const planSlice = snapshot.activeSlice;
	const activeId = asString(active?.slice_id);
	if (!activeId || !planSlice) return undefined;
	const drift: string[] = [];
	const expectPlanArrayMirror = (field: string) => {
		if (!hasOwnField(planSlice, field) || !sameStringArrays(asStringArray(planSlice[field]), asStringArray(active?.[field]))) {
			drift.push(field);
		}
	};
	const expectPlanStringMirror = (field: string) => {
		if (!hasOwnField(planSlice, field) || asString(planSlice[field]) !== asString(active?.[field])) {
			drift.push(field);
		}
	};
	const expectPlanNumberMirror = (field: string) => {
		if (!hasOwnField(planSlice, field) || asNumber(planSlice[field]) !== asNumber(active?.[field])) {
			drift.push(field);
		}
	};
	if (asString(planSlice.slice_id) !== activeId) drift.push("slice_id");
	if (asString(planSlice.goal) !== asString(active?.goal)) drift.push("goal");
	if (!sameStringArrays(asStringArray(planSlice.contract_ids), asStringArray(active?.contract_ids))) drift.push("contract_ids");
	if (!sameStringArrays(asStringArray(planSlice.acceptance_criteria), asStringArray(active?.acceptance_criteria))) drift.push("acceptance_criteria");
	if (!sameStringArrays(asStringArray(planSlice.blocked_on), asStringArray(active?.blocked_on))) drift.push("blocked_on");
	if (asNumber(planSlice.priority) !== asNumber(active?.priority)) drift.push("priority");
	if (asString(planSlice.why_now) !== asString(active?.why_now)) drift.push("why_now");
	expectPlanArrayMirror("implementation_surfaces");
	expectPlanArrayMirror("verification_commands");
	expectPlanArrayMirror("locked_notes");
	expectPlanArrayMirror("must_fix_findings");
	expectPlanStringMirror("basis_commit");
	expectPlanArrayMirror("remaining_contract_ids_before");
	expectPlanNumberMirror("release_blocker_count_before");
	expectPlanNumberMirror("high_value_gap_count_before");
	return Array.from(new Set(drift));
}

function activeSliceContractDriftSummary(snapshot: CompletionStateSnapshot): string {
	const activeId = asString(snapshot.active?.slice_id);
	if (!activeId) return "unknown";
	if (!snapshot.activeSlice) return "slice_id (no matching plan slice)";
	const drift = activeSliceContractDriftFields(snapshot);
	return drift && drift.length > 0 ? drift.join(", ") : "none";
}

function activeSliceMatchesPlan(snapshot: CompletionStateSnapshot): "yes" | "no" | "unknown" {
	const activeId = asString(snapshot.active?.slice_id);
	if (!activeId) return "unknown";
	const drift = activeSliceContractDriftFields(snapshot);
	if (!snapshot.activeSlice || drift === undefined) return "no";
	return drift.length === 0 ? "yes" : "no";
}

function handoffSnapshotState(active: JsonRecord | undefined): "present" | "missing_or_unclear" {
	const exactArrays = [
		asStringArray(active?.acceptance_criteria),
		asStringArray(active?.implementation_surfaces),
		asStringArray(active?.verification_commands),
	];
	const required = [
		active?.priority,
		active?.why_now,
		active?.blocked_on,
		active?.locked_notes,
		active?.must_fix_findings,
		active?.basis_commit,
		active?.remaining_contract_ids_before,
		active?.release_blocker_count_before,
		active?.high_value_gap_count_before,
	];
	return activeCarriesExactHandoff(active) && exactArrays.every((items) => items.length > 0) && required.every((value) => value !== undefined && value !== null)
		? "present"
		: "missing_or_unclear";
}

function hasRunningCompletionRole(rootKey: string): boolean {
	return liveRoleActivityByRoot.get(rootKey)?.status === "running";
}

function hasRecentlyCompletedCompletionRole(rootKey: string): boolean {
	const activity = liveRoleActivityByRoot.get(rootKey);
	return !!activity && activity.status !== "running";
}

function isRubricEvaluationRole(role: string | undefined): role is RubricEvaluationRole {
	return RUBRIC_EVALUATION_ROLES.includes(role as RubricEvaluationRole);
}

function activeSliceContext(snapshot: CompletionStateSnapshot) {
	const active = snapshot.active;
	const activeSlice = snapshot.activeSlice;
	return {
		sliceId: asString(active?.slice_id) ?? asString(activeSlice?.slice_id),
		status: asString(active?.status) ?? asString(activeSlice?.status),
		goal: asString(active?.goal) ?? asString(activeSlice?.goal),
		contractIds:
			asStringArray(active?.contract_ids).length > 0 ? asStringArray(active?.contract_ids) : asStringArray(activeSlice?.contract_ids),
		acceptance:
			asStringArray(active?.acceptance_criteria).length > 0
				? asStringArray(active?.acceptance_criteria)
				: asStringArray(activeSlice?.acceptance_criteria),
		implementationSurfaces: asStringArray(active?.implementation_surfaces),
		verificationCommands: asStringArray(active?.verification_commands),
		lockedNotes: asStringArray(active?.locked_notes),
		mustFixFindings: asStringArray(active?.must_fix_findings),
		remainingBefore: asStringArray(active?.remaining_contract_ids_before),
		basisCommit: asString(active?.basis_commit),
		releaseBlockerCountBefore: asNumber(active?.release_blocker_count_before),
		highValueGapCountBefore: asNumber(active?.high_value_gap_count_before),
	};
}

function verificationEvidenceContext(snapshot: CompletionStateSnapshot) {
	const evidence = snapshot.verificationEvidence;
	return {
		path: path.relative(snapshot.files.root, snapshot.files.verificationEvidencePath) || ".agent/current/verification-evidence.json",
		status: evidence ? "present" : "missing",
		subjectType: asString(evidence?.subject_type),
		sliceId: asString(evidence?.slice_id),
		goal: asString(evidence?.goal),
		contractIds: asStringArray(evidence?.contract_ids),
		basisCommit: asString(evidence?.basis_commit),
		headSha: asString(evidence?.head_sha),
		verificationCommands: asStringArray(evidence?.verification_commands),
		outcome: asString(evidence?.outcome),
		recordedAt: asString(evidence?.recorded_at),
		summary:
			asString(evidence?.summary) ??
			(evidence ? "Canonical verification evidence is present but its summary is missing." : "Canonical verification evidence is missing."),
	};
}

function startupVerifierPostureSummary(snapshot: CompletionStateSnapshot): string | undefined {
	const startupBrief = snapshot.startupBrief;
	const parts = [
		asString(startupBrief?.verification_truth_mode)
			? `verification_truth_mode=${asString(startupBrief?.verification_truth_mode)}`
			: undefined,
		asBoolean(startupBrief?.deterministic_verifier_ready) !== undefined
			? `deterministic_verifier_ready=${asBoolean(startupBrief?.deterministic_verifier_ready) ? "yes" : "no"}`
			: undefined,
		asString(startupBrief?.verification_latency)
			? `verification_latency=${asString(startupBrief?.verification_latency)}`
			: undefined,
		asString(startupBrief?.verification_noise_risk)
			? `verification_noise_risk=${asString(startupBrief?.verification_noise_risk)}`
			: undefined,
		asString(startupBrief?.verifier_gap) ? `verifier_gap=${asString(startupBrief?.verifier_gap)}` : undefined,
		asString(startupBrief?.recommended_first_slice_kind)
			? `recommended_first_slice_kind=${asString(startupBrief?.recommended_first_slice_kind)}`
			: undefined,
	].filter((part): part is string => Boolean(part));
	return parts.length > 0 ? parts.join("; ") : undefined;
}

function buildEvaluationRoleContextLines(snapshot: CompletionStateSnapshot, role: RubricEvaluationRole): string[] {
	return buildExtractedEvaluationRoleContextLines(snapshot, role, {
		asString,
		currentTaskType,
		currentEvaluationProfile,
		activeSliceContext,
		verificationEvidenceContext,
	});
}

function buildEvaluationRoleReminderText(snapshot: CompletionStateSnapshot, role: RubricEvaluationRole): string {
	return buildExtractedEvaluationRoleReminderText(snapshot, role, {
		asString,
		currentTaskType,
		currentEvaluationProfile,
		activeSliceContext,
		verificationEvidenceContext,
	});
}

function composeSystemReminder(snapshot: CompletionStateSnapshot): string {
	const implementationSurfaces = asStringArray(snapshot.active?.implementation_surfaces);
	const verificationCommands = asStringArray(snapshot.active?.verification_commands);
	const activePriority = asNumber(snapshot.active?.priority);
	const activeWhyNow = asString(snapshot.active?.why_now);
	const nextRole = asString(snapshot.state?.next_mandatory_role);
	const exactActiveContract = activeCarriesExactHandoff(snapshot.active);
	const activeContractDrift = activeSliceContractDriftSummary(snapshot);
	const evidence = verificationEvidenceContext(snapshot);
	const startupVerifierPosture = startupVerifierPostureSummary(snapshot);
	const activePriorityLine = activePriority !== undefined ? `Active slice priority: ${activePriority}` : undefined;
	const activeWhyNowLine = activeWhyNow ? `Active slice why_now: ${activeWhyNow}` : undefined;
	const implementationSurfacesLine =
		implementationSurfaces.length > 0 ? `Active implementation surfaces: ${implementationSurfaces.join(", ")}` : undefined;
	const verificationCommandsLine =
		verificationCommands.length > 0 ? `Active verification commands: ${verificationCommands.join(" | ")}` : undefined;
	return buildExtractedSystemReminder({
		missionAnchor: asString(snapshot.state?.mission_anchor),
		taskType: currentTaskType(snapshot),
		evaluationProfile: currentEvaluationProfile(snapshot),
		currentPhase: asString(snapshot.state?.current_phase),
		continuationPolicy: asString(snapshot.state?.continuation_policy),
		nextMandatoryRole: nextRole,
		nextMandatoryAction: asString(snapshot.state?.next_mandatory_action),
		remainingSliceCount: remainingSliceCount(snapshot.plan),
		exactActiveContract,
		activeContractDrift,
		activePriority,
		activeWhyNow,
		implementationSurfaces,
		verificationCommands,
		activePriorityLine,
		activeWhyNowLine,
		implementationSurfacesLine,
		verificationCommandsLine,
		startupVerifierPostureLine:
			startupVerifierPosture ? `Startup verifier posture: ${startupVerifierPosture}` : undefined,
		evidence,
	});
}

function buildPostCompactionDriverInstructions(snapshot: CompletionStateSnapshot, marker: JsonRecord | undefined): string {
	const markerAt = typeof marker?.recorded_at === "number" ? new Date(marker.recorded_at).toISOString() : "(unknown time)";
	const nextRole = asString(snapshot.state?.next_mandatory_role) ?? "unknown";
	const nextAction = asString(snapshot.state?.next_mandatory_action) ?? "unknown";
	const continuation = asString(snapshot.state?.continuation_policy) ?? "unknown";
	const activeSliceId = asString(snapshot.active?.slice_id) ?? asString(snapshot.activeSlice?.slice_id) ?? "(none)";
	const taskType = currentTaskType(snapshot) ?? "(missing)";
	const evaluationProfile = currentEvaluationProfile(snapshot) ?? "(missing)";
	const implementationSurfaces = asStringArray(snapshot.active?.implementation_surfaces);
	const verificationCommands = asStringArray(snapshot.active?.verification_commands);
	const activePriority = asNumber(snapshot.active?.priority);
	const activeWhyNow = asString(snapshot.active?.why_now);
	const exactActiveContract = activeCarriesExactHandoff(snapshot.active);
	const activeContractDrift = activeSliceContractDriftSummary(snapshot);
	const evidence = verificationEvidenceContext(snapshot);
	const startupVerifierPosture = startupVerifierPostureSummary(snapshot);
	const lines = [
		"POST-COMPACTION RECOVERY MODE is active.",
		`Compaction marker time: ${markerAt}`,
		"Treat the previous conversation as lossy continuity support only.",
		"Before taking any substantive action, re-read .agent/current/state.json, .agent/current/plan.json, .agent/current/active-slice.json, .agent/current/slice-history.jsonl, .agent/current/stop-check-history.jsonl, and .agent/current/verification-evidence.json from disk.",
		`Canonical task_type is currently: ${taskType}`,
		`Canonical evaluation_profile is currently: ${evaluationProfile}`,
		`Canonical next mandatory role is currently: ${nextRole}`,
		`Canonical next mandatory action is currently: ${nextAction}`,
		`Canonical continuation policy is currently: ${continuation}`,
		`Canonical active slice is currently: ${activeSliceId}`,
		`Canonical verification evidence artifact is currently: ${evidence.path} (${evidence.status})`,
		...(startupVerifierPosture ? [`Canonical startup verifier posture is currently: ${startupVerifierPosture}`] : []),
		"Do not trust pre-compaction memory over canonical files.",
		"If the canonical state is ambiguous, inconsistent, missing, or stale after re-reading it, your first mandatory action is to dispatch completion-regrounder rather than guessing.",
		"If continuation_policy == continue and canonical state is coherent, continue dispatching the mandatory role directly without asking the user whether to continue.",
		"If you are about to implement after compaction, confirm the active slice snapshot still matches .agent/current/plan.json before doing any work.",
	];
	if (exactActiveContract) {
		lines.push("For selected/in-progress/committed/done slices, .agent/current/active-slice.json is the canonical implementation contract.");
		lines.push(`Canonical active-slice contract drift is currently: ${activeContractDrift}`);
	}
	if (activePriority !== undefined) lines.push(`Canonical active-slice priority is currently: ${activePriority}`);
	if (activeWhyNow) lines.push(`Canonical active-slice why_now is currently: ${activeWhyNow}`);
	if (implementationSurfaces.length > 0) lines.push(`Canonical implementation surfaces are currently: ${implementationSurfaces.join(", ")}`);
	if (verificationCommands.length > 0) lines.push(`Canonical verification commands are currently: ${verificationCommands.join(" | ")}`);
	if (evidence.subjectType) lines.push(`Canonical verification evidence subject is currently: ${evidence.subjectType}`);
	if (evidence.outcome) lines.push(`Canonical verification evidence outcome is currently: ${evidence.outcome}`);
	if (evidence.recordedAt) lines.push(`Canonical verification evidence recorded_at is currently: ${evidence.recordedAt}`);
	if (evidence.headSha) lines.push(`Canonical verification evidence head_sha is currently: ${evidence.headSha}`);
	if (evidence.basisCommit) lines.push(`Canonical verification evidence basis_commit is currently: ${evidence.basisCommit}`);
	if (evidence.verificationCommands.length > 0) {
		lines.push(`Canonical verification evidence commands are currently: ${evidence.verificationCommands.join(" | ")}`);
	}
	lines.push(`Canonical verification evidence summary is currently: ${evidence.summary}`);
	if (isRubricEvaluationRole(nextRole)) lines.push(buildEvaluationRoleReminderText(snapshot, nextRole));
	return lines.join(" ");
}

function isStaleContextError(error: unknown): boolean {
	const message = error instanceof Error ? error.message : String(error);
	return message.includes("This extension ctx is stale after session replacement or reload");
}

function safeUiCall(action: () => void) {
	try {
		action();
	} catch (error) {
		if (isStaleContextError(error)) return;
		throw error;
	}
}

function getCtxCwd(ctx: { cwd: string }): string {
	try {
		return ctx.cwd;
	} catch (error) {
		if (isStaleContextError(error)) return process.cwd();
		throw error;
	}
}

function getCtxHasUI(ctx: { hasUI: boolean }): boolean {
	try {
		return ctx.hasUI;
	} catch (error) {
		if (isStaleContextError(error)) return false;
		throw error;
	}
}

function getCtxUi<T extends { ui: any }>(ctx: T): any | undefined {
	try {
		return ctx.ui;
	} catch (error) {
		if (isStaleContextError(error)) return undefined;
		throw error;
	}
}

function getSystemPromptSafe(ctx: { getSystemPrompt: () => string }): string | undefined {
	try {
		return ctx.getSystemPrompt();
	} catch (error) {
		if (isStaleContextError(error)) return undefined;
		throw error;
	}
}

function emitCommandText(ctx: { hasUI: boolean; ui: any }, text: string, level: "info" | "success" | "warning" | "error" = "info") {
	if (getCtxHasUI(ctx)) {
		const ui = getCtxUi(ctx);
		if (ui) safeUiCall(() => ui.notify(text, level));
		else console.log(text);
	} else {
		console.log(text);
	}
}

function composeResumeCapsule(snapshot: CompletionStateSnapshot, sliceHistory: JsonRecord[], stopHistory: JsonRecord[]): string {
	const history = historyCounts(sliceHistory, stopHistory);
	const acceptance = asStringArray(snapshot.active?.acceptance_criteria).length > 0
		? asStringArray(snapshot.active?.acceptance_criteria)
		: asStringArray(snapshot.activeSlice?.acceptance_criteria);
	const contractIds = asStringArray(snapshot.active?.contract_ids).length > 0
		? asStringArray(snapshot.active?.contract_ids)
		: asStringArray(snapshot.activeSlice?.contract_ids);
	const blockedOn = asStringArray(snapshot.active?.blocked_on).length > 0
		? asStringArray(snapshot.active?.blocked_on)
		: asStringArray(snapshot.activeSlice?.blocked_on);
	const lockedNotes = asStringArray(snapshot.active?.locked_notes);
	const mustFixFindings = asStringArray(snapshot.active?.must_fix_findings);
	const implementationSurfaces = asStringArray(snapshot.active?.implementation_surfaces);
	const verificationCommands = asStringArray(snapshot.active?.verification_commands);
	const remainingBefore = asStringArray(snapshot.active?.remaining_contract_ids_before);
	const evidence = verificationEvidenceContext(snapshot);
	const startupVerifierPosture = startupVerifierPostureSummary(snapshot);
	const implementationSurfacesLine =
		implementationSurfaces.length > 0 ? `- implementation_surfaces: ${implementationSurfaces.join(" | ")}` : undefined;
	const verificationCommandsLine =
		verificationCommands.length > 0 ? `- verification_commands: ${verificationCommands.join(" | ")}` : undefined;
	return buildExtractedResumeCapsule({
		missionAnchor: asString(snapshot.state?.mission_anchor),
		taskType: currentTaskType(snapshot),
		evaluationProfile: currentEvaluationProfile(snapshot),
		currentPhase: asString(snapshot.state?.current_phase),
		continuationPolicy: asString(snapshot.state?.continuation_policy),
		continuationReason: asString(snapshot.state?.continuation_reason),
		requiresReground: asBoolean(snapshot.state?.requires_reground) ?? "unknown",
		nextMandatoryRole: asString(snapshot.state?.next_mandatory_role),
		nextMandatoryAction: asString(snapshot.state?.next_mandatory_action),
		remainingSliceCount: remainingSliceCount(snapshot.plan),
		remainingStopJudges: asNumber(snapshot.state?.remaining_stop_judges) ?? "(unknown)",
		history,
		activeSliceMatchesPlan: activeSliceMatchesPlan(snapshot),
		activeSliceContractDrift: activeSliceContractDriftSummary(snapshot),
		implementerHandoffSnapshot: handoffSnapshotState(snapshot.active),
		startupVerifierPostureLine:
			startupVerifierPosture ? `startup_verifier_posture: ${startupVerifierPosture}` : undefined,
		evidence,
		activeSlice: {
			sliceId: asString(snapshot.active?.slice_id) ?? asString(snapshot.activeSlice?.slice_id),
			status: asString(snapshot.active?.status) ?? asString(snapshot.activeSlice?.status),
			goal: asString(snapshot.active?.goal) ?? asString(snapshot.activeSlice?.goal),
			priority: asNumber(snapshot.active?.priority),
			whyNow: asString(snapshot.active?.why_now),
			contractIds,
			blockedOn,
			lockedNotes,
			mustFixFindings,
			implementationSurfaces,
			verificationCommands,
			implementationSurfacesLine,
			verificationCommandsLine,
			basisCommit: asString(snapshot.active?.basis_commit),
			remainingContractIdsBefore: remainingBefore,
			releaseBlockerCountBefore: asNumber(snapshot.active?.release_blocker_count_before),
			highValueGapCountBefore: asNumber(snapshot.active?.high_value_gap_count_before),
			acceptanceCriteria: acceptance,
		},
	});
}

function runtimeQuickReferencePathForRole(role: CompletionRole | "driver"): string {
	const fileName = ROLE_RUNTIME_QUICK_REFERENCE_FILENAMES[role];
	const packageCandidate = PACKAGE_RUNTIME_QUICK_REFERENCES_DIR ? path.join(PACKAGE_RUNTIME_QUICK_REFERENCES_DIR, fileName) : undefined;
	if (packageCandidate && fs.existsSync(packageCandidate)) return packageCandidate;
	const agentCandidate = path.join(RUNTIME_QUICK_REFERENCE_DIR, fileName);
	if (fs.existsSync(agentCandidate)) return agentCandidate;
	return RUNTIME_QUICK_REFERENCE_PATH;
}

function completionProtocolReadBlock(role: CompletionRole | "driver"): string {
	const quickReferencePath = runtimeQuickReferencePathForRole(role);
	return `Read first:\n- ${quickReferencePath}\n\nEscalate only if runtime protocol details remain ambiguous after the quick reference and canonical .agent/** state:\n- ${SKILL_PATH}\n- ${REFERENCE_PATH}`;
}

function completionKickoff(
	goal: string,
	taskType: string,
	evaluationProfile: string,
	intent: "auto" | "continue" | "refocus" = "auto",
	missionAnchor?: string,
	workflowSessionId?: string,
): string {
	const intentBlock =
		intent === "continue" && missionAnchor
			? `Existing canonical mission anchor:\n${missionAnchor}\n\nWorkflow intent:\n- Continue the existing workflow.\n- Treat the new user text as supplemental direction unless canonical reconciliation proves the mission itself must change.\n\n`
			: intent === "refocus" && missionAnchor
				? `Updated canonical mission anchor:\n${missionAnchor}\n\nWorkflow intent:\n- The user explicitly refocused the workflow before this kickoff.\n- Re-read canonical .agent/** state and continue from the refocused mission.\n\n`
				: "";
	const sessionBlock = workflowSessionId ? `Workflow session:\n- workflow_session_id: ${workflowSessionId}\n\n` : "";
	return `COMPLETION WORKFLOW DRIVER\nStart or continue the completion workflow for this repo.\n\n${completionProtocolReadBlock("driver")}\n\nCanonical routing profile:\n- task_type: ${taskType}\n- evaluation_profile: ${evaluationProfile}\n\n${sessionBlock}User goal:\n${goal}\n\n${intentBlock}Driver instructions:\n- Canonical truth is in package defaults plus ignored .agent/** runtime state. Re-read .agent/current/state.json, .agent/current/startup-brief.json, .agent/current/plan.json, .agent/current/active-slice.json, and .agent/current/verification-evidence.json before acting when they exist.\n- If local .agent helper forwarders or canonical execution-state scaffolding are missing and truthful onboarding or repair is required, invoke completion_role with role completion-bootstrapper.\n- Otherwise follow the mandatory dispatch rules from completion-protocol.\n- Treat .agent/current/startup-brief.json as canonical intake, not as the canonical slice plan. Mission, scope, constraints, acceptance, risks, and notes there are workflow-level startup intent. Optional *_hint fields remain advisory until completion-regrounder authors canonical slices.\n- For selected, in-progress, committed, or done slices, treat .agent/current/active-slice.json as the canonical implementation contract and route to completion-regrounder if it drifts from the selected plan slice or the exact handoff is unclear.\n- Consume .agent/current/verification-evidence.json instead of temp-only verification summaries when it is populated.\n- Use completion_role for all completion-* role work. Do not directly implement tracked product changes yourself.\n- Continue dispatching mandatory roles while continuation_policy == continue.\n- If canonical closeout cleanup removes repo-local .agent/ after the workflow reaches done or cancelled, treat that disappearance as expected final cleanup rather than as a missing tracked-file anomaly, and do not recreate local helper forwarders merely to narrate completion.\n- Only stop for the user when continuation_policy is await_user_input, blocked, paused, or done.`;
}

function completionResumePrompt(taskType: string, evaluationProfile: string, workflowSessionId?: string): string {
	const sessionBlock = workflowSessionId ? `Workflow session:\n- workflow_session_id: ${workflowSessionId}\n\n` : "";
	return `COMPLETION WORKFLOW DRIVER\nResume the completion workflow from canonical state.\n\n${completionProtocolReadBlock("driver")}\n\nCanonical routing profile:\n- task_type: ${taskType}\n- evaluation_profile: ${evaluationProfile}\n\n${sessionBlock}Resume instructions:\n- Re-read .agent/current/state.json, .agent/current/startup-brief.json, .agent/current/plan.json, .agent/current/active-slice.json, and .agent/current/verification-evidence.json before acting.\n- If canonical state is missing, invalid, contradictory, stale, or ambiguous, route to completion-regrounder first.\n- Treat .agent/current/startup-brief.json as canonical intake, not as the canonical slice plan. Mission, scope, constraints, acceptance, risks, and notes there are workflow-level startup intent. Optional *_hint fields remain advisory until completion-regrounder authors canonical slices.\n- For selected, in-progress, committed, or done slices, treat .agent/current/active-slice.json as the canonical implementation contract and route to completion-regrounder if it drifts from the selected plan slice or the exact handoff is unclear.\n- Consume .agent/current/verification-evidence.json instead of temp-only verification summaries when it is populated.\n- Continue from next_mandatory_role and next_mandatory_action.\n- When canonical state is stopped (await_user_input, blocked, or paused), rerun /cook or /cook resume to continue, /cook park to record a parked paused posture for ordinary direct edits after canonical state is updated, or /cook cancel to close the workflow.\n- Use completion_role for all completion-* role work.\n- Continue dispatching mandatory roles while continuation_policy == continue.\n- If canonical closeout cleanup removes repo-local .agent/ after the workflow reaches done or cancelled, treat that disappearance as expected final cleanup rather than as a missing tracked-file anomaly, and do not recreate local helper forwarders merely to narrate completion.\n- Only stop for the user when continuation_policy is await_user_input, blocked, paused, or done.`;
}

export default function completionExtension(pi: ExtensionAPI) {
	const statusSurfaceArgs = {
		liveRoleActivityByRoot,
		completionStatusKey: COMPLETION_STATUS_KEY,
		safeUiCall,
		getCtxCwd,
		getCtxHasUI,
		getCtxUi,
	};
	const driverDeps = {
		structuredDiscussionFailureDetail: COOK_STRUCTURED_DISCUSSION_FAILURE_DETAIL,
		mainChatRerunGuidance: COOK_MAIN_CHAT_RERUN_GUIDANCE,
		cookCommandSpec: {
			description: "/cook workflow: start or replace workflow by asking the primary agent to synthesize a startup handoff from the current task context or inline prompt (fail closed when no startable handoff is produced); resume the current workflow from canonical state, or use /cook resume|park|cancel for explicit stopped-workflow controls",
		},
		buildContextProposalContinuationReason,
		completionKickoff,
		completionResumePrompt,
		completionRootKey,
		completionTestAutoContinuePromptPath,
		completionTestDriverPromptPath,
		completionTestExistingWorkflowChooserSnapshotPath,
		completionTestWorkflowActionOverride,
		completionTestWorkflowMissionOverride,
		confirmContextProposal,
		deriveCookContextProposal,
		emitCommandText,
		finalizeContextProposalAnalysis,
		getCtxCwd,
		getCtxHasUI,
		getCtxUi,
		hasRunningCompletionRole,
		maybeWriteActiveWorkflowRoutingSnapshot,
		activateCompletionRoutingForRoot,
		maybeWriteTestSnapshot,
		missionAnchorsStrictlyEquivalent,
		scaffoldCompletionFiles,
		shouldSkipDriverKickoffForTests,
		shouldTestAutoContinueOnSessionStart,
	};


	pi.on("session_start", async (_event, ctx) => {
		await refreshCompletionStatus({ ctx, ...statusSurfaceArgs });
		if (shouldTestAutoContinueOnSessionStart()) {
			const snapshot = await loadCompletionSnapshot(getCtxCwd(ctx));
			if (isCompletionWorkflowSessionTurn(snapshot, ctx)) {
				await autoContinueWorkflowIfNeeded(pi, ctx, driverDeps);
			}
		}
	});

	pi.on("turn_end", async (_event, ctx) => {
		await cleanupClosedWorkflowRuntimeIfNeeded(getCtxCwd(ctx));
		await refreshCompletionStatus({ ctx, ...statusSurfaceArgs });
	});

	pi.on("agent_end", async (_event, ctx) => {
		const cwd = getCtxCwd(ctx);
		let snapshot = await loadCompletionSnapshot(cwd);
		if (snapshot && (await pathExists(snapshot.files.compactionMarkerPath))) {
			await fsp.rm(snapshot.files.compactionMarkerPath, { force: true });
		}
		if (await cleanupClosedWorkflowRuntimeIfNeeded(cwd)) {
			snapshot = undefined;
		}
		await refreshCompletionStatus({ ctx, ...statusSurfaceArgs });
		const rootKey = completionRootKey(snapshot, cwd);
		if (isCompletionWorkflowSessionTurn(snapshot, ctx) || (hasStickyWorkflowContinuation(snapshot) && hasRecentlyCompletedCompletionRole(rootKey))) {
			await autoContinueWorkflowIfNeeded(pi, ctx, driverDeps);
		}
	});

	pi.on("before_agent_start", async (event, ctx) => {
		const agentCwd = getCtxCwd(ctx);
		await cleanupClosedWorkflowRuntimeIfNeeded(agentCwd);
		const loaded = await loadCompletionDataForReminder(agentCwd);
		const systemPrompt = getSystemPromptSafe(ctx);
		if (!systemPrompt) return;
		if (loaded && shouldInjectCompletionWorkflowContext(loaded.snapshot, ctx)) {
			const additions = isWorkflowDone(loaded.snapshot)
				? [buildDoneWorkflowBoundaryReminder(loaded.snapshot)]
				: [composeSystemReminder(loaded.snapshot)];
			if (!isWorkflowDone(loaded.snapshot)) {
				const markerText = await readText(loaded.snapshot.files.compactionMarkerPath);
				let marker: JsonRecord | undefined;
				if (markerText) {
					try {
						const parsed = JSON.parse(markerText);
						marker = isRecord(parsed) ? parsed : undefined;
					} catch {
						marker = undefined;
					}
				}
				if (marker) additions.push(buildPostCompactionDriverInstructions(loaded.snapshot, marker));
			}
			maybeWriteTestSnapshot(completionTestSystemReminderPath(), additions.join("\n\n"));
			return {
				systemPrompt: `${systemPrompt}\n\n${additions.join("\n\n")}`,
			};
		}
		if (loaded && shouldInjectStoppedWorkflowBoundary(event, ctx, loaded.snapshot)) {
			const stoppedWorkflowReminder = buildStoppedWorkflowBoundaryReminder(loaded.snapshot);
			maybeWriteTestSnapshot(completionTestCookHandoffReminderPath(), stoppedWorkflowReminder);
			return {
				systemPrompt: `${systemPrompt}\n\n${stoppedWorkflowReminder}`,
			};
		}
		if (!shouldInjectCookHandoffBoundary(event, ctx, loaded?.snapshot)) return;
		const handoffReminder = buildCookHandoffBoundaryReminder();
		maybeWriteTestSnapshot(completionTestCookHandoffReminderPath(), handoffReminder);
		return {
			systemPrompt: `${systemPrompt}\n\n${handoffReminder}`,
		};
	});

	pi.on("session_before_compact", async (event, ctx) => {
		const loaded = await loadCompletionDataForReminder(getCtxCwd(ctx));
		if (!loaded || isWorkflowDone(loaded.snapshot)) return;
		const { preparation } = event;
		const summary = composeResumeCapsule(loaded.snapshot, loaded.sliceHistory, loaded.stopHistory);
		await fsp.mkdir(loaded.snapshot.files.tmpDir, { recursive: true });
		await fsp.writeFile(
			loaded.snapshot.files.compactionMarkerPath,
			`${JSON.stringify({
				recorded_at: Date.now(),
				mission_anchor: asString(loaded.snapshot.state?.mission_anchor) ?? null,
				next_mandatory_role: asString(loaded.snapshot.state?.next_mandatory_role) ?? null,
				next_mandatory_action: asString(loaded.snapshot.state?.next_mandatory_action) ?? null,
				continuation_policy: asString(loaded.snapshot.state?.continuation_policy) ?? null,
				active_slice_id: asString(loaded.snapshot.active?.slice_id) ?? asString(loaded.snapshot.activeSlice?.slice_id) ?? null,
			}, null, 2)}\n`,
			"utf8",
		);
		emitCommandText(ctx, "Completion continuity capsule injected for compaction", "info");
		return {
			compaction: {
				summary,
				firstKeptEntryId: preparation.firstKeptEntryId,
				tokensBefore: preparation.tokensBefore,
				details: preparation.fileOps,
			},
		};
	});

	pi.on("tool_call", async (event, ctx) => {
		const role = roleFromEnv();
		const cwd = getCtxCwd(ctx);
		const snapshot = await loadCompletionSnapshot(cwd);
		const workflowHardLockActiveNow = workflowHardLockActive(snapshot);
		const root = snapshot?.files.root ?? findRepoRoot(cwd) ?? cwd;
		const completionRoleDispatchAllowed = Boolean(role) || isCompletionWorkflowDispatchContext(snapshot, ctx);
		const reason = toolCallBlockReason({
			toolName: event.toolName,
			input: isRecord(event.input) ? event.input : undefined,
			role,
			workflowHardLockActive: workflowHardLockActiveNow,
			completionRoleDispatchAllowed,
			root,
		});
		if (reason) return { block: true, reason };
	});

	const activeCompletionRole = roleFromEnv();
	if (canRoleUseCompletionAssist(activeCompletionRole)) {
		pi.registerTool({
			name: COMPLETION_ASSIST_TOOL_NAME,
			label: "Completion Assist",
			description: "Internal bounded helper for completion-implementer and completion-regrounder only.",
			promptSnippet: "Run a bounded scout or critic helper inside the active completion role.",
			promptGuidelines: [
				"Use completion_assist only from completion-implementer or completion-regrounder when bounded reconnaissance or critique will help the active slice.",
				"Valid helpers are scout and critic. The final tool result must stay exact JSON on both success and failure.",
				"Treat helper output as non-authoritative input beneath the active completion role.",
			],
			parameters: Type.Object({
				helper: StringEnum(COMPLETION_HELPER_NAMES, { description: "Which bounded helper to run." }),
				task: Type.String({ description: "The bounded helper task to perform." }),
				cwd: Type.Optional(Type.String({ description: "Optional repo-relative helper working directory convenience." })),
				timeoutMs: Type.Optional(Type.Number({ description: "Optional timeout request that may only narrow the helper budget." })),
			}),
			async execute(_toolCallId, params, signal, onUpdate, ctx) {
				const helper = params.helper as CompletionHelperName;
				const cwd = getCtxCwd(ctx);
				const runCwd = findCompletionRoot(cwd) ?? findRepoRoot(cwd) ?? cwd;
				return await runCompletionAssistTool({
					root: runCwd,
					helper,
					callerRole: roleFromEnv(),
					task: params.task,
					cwd: typeof params.cwd === "string" ? params.cwd : undefined,
					timeoutMs: typeof params.timeoutMs === "number" ? params.timeoutMs : undefined,
					roleModel: roleModelFromEnv(),
					signal,
					onUpdate,
				});
			},
		});
	}

	pi.registerTool({
		name: "completion_role",
		label: "Completion Role",
		description: "Run one completion workflow role in an isolated pi subprocess. Only the main workflow driver should call this tool.",
		promptSnippet: "Dispatch one completion workflow role in isolated context.",
		promptGuidelines: [
			"Use completion_role when driving the completion workflow and a mandatory completion role must act next.",
			"Use completion_role only for completion-bootstrapper, completion-regrounder, completion-implementer, completion-reviewer, completion-auditor, or completion-stop-judge.",
			"Do not use completion_role from inside a completion role; only the workflow driver may dispatch roles.",
			"Do not call completion_role from ordinary chat; it is reserved for active /cook workflow sessions.",
		],
		parameters: Type.Object({
			role: StringEnum(ROLE_NAMES, { description: "The completion role to invoke." }),
			task: Type.Optional(Type.String({ description: "Optional extra task context for the selected role." })),
		}),
		async execute(_toolCallId, params, signal, onUpdate, ctx) {
			const role = completionTestForcedCompletionRole() ?? (params.role as CompletionRole);
			const cwd = getCtxCwd(ctx);
			const runCwd = findCompletionRoot(cwd) ?? findRepoRoot(cwd) ?? cwd;
			const rootKey = runCwd;
			type RunningDetails = {
				role: string;
				status: "running" | "ok" | "error";
				currentAction?: string;
				toolActivity?: string;
				toolRecentActivity?: string[];
				recentActivity?: string[];
				assistantSummary?: string;
				lastAssistantText?: string;
				progress?: string;
				rationale?: string;
				nextStep?: string;
				verifying?: string;
				stateDeltas?: string[];
				startedAt?: number;
				updatedAt?: number;
				stderr?: string;
				reportFields?: Record<string, string>;
				transcription?: TranscriptionResult;
				exitCode?: number;
			};
			const emitActivityUpdate = (activity: LiveRoleActivity) => {
				const details: RunningDetails = {
					role,
					status: activity.status,
					currentAction: activity.currentAction,
					toolActivity: activity.toolActivity,
					toolRecentActivity: activity.toolRecentActivity,
					recentActivity: activity.recentActivity,
					assistantSummary: activity.assistantSummary,
					lastAssistantText: activity.lastAssistantText,
					progress: activity.progress,
					rationale: activity.rationale,
					nextStep: activity.nextStep,
					verifying: activity.verifying,
					stateDeltas: activity.stateDeltas,
					startedAt: activity.startedAt,
					updatedAt: activity.updatedAt,
				};
				liveRoleActivityByRoot.set(rootKey, cloneLiveRoleActivity(activity, { status: activity.status }));
				void refreshCompletionStatus({ ctx: ctx as { cwd: string; hasUI: boolean; ui: any }, ...statusSurfaceArgs });
				onUpdate?.({
					content: [{ type: "text", text: activity.lastAssistantText || activity.currentAction || `Running ${role}...` }],
					details,
				});
			};
			const loaded = await loadCompletionDataForReminder(runCwd);
			const result = await runCompletionRole({
				root: runCwd,
				role,
				task: completionTestForcedCompletionTask() ?? params.task,
				signal,
				requestedModel: modelArgFromContextModel((ctx as { model?: unknown }).model),
				systemPromptPreamble: [
					`Completion role: ${role}`,
					"Read first:",
					`- ${runtimeQuickReferencePathForRole(role)}`,
					"Escalate only if runtime protocol details remain ambiguous after the quick reference and canonical .agent/** state:",
					`- ${SKILL_PATH}`,
					`- ${REFERENCE_PATH}`,
					"Use canonical .agent/** state as the source of truth.",
				],
				evaluationContextLines: loaded && isRubricEvaluationRole(role) ? buildEvaluationRoleContextLines(loaded.snapshot, role) : undefined,
				onUpdate: emitActivityUpdate,
				onConsoleMessage: (level, message) => emitCommandText(ctx, message, level),
				createLiveRoleActivity: (name) => createLiveRoleActivity(name),
				cloneLiveRoleActivity,
				applyLiveRoleEvent,
				nowMs,
				heartbeatMs: LIVE_ROLE_HEARTBEAT_MS,
			});
			const closedWorkflowCleanupApplied = await cleanupClosedWorkflowRuntimeIfNeeded(runCwd);
			const closedWorkflowCleanupNote = closedWorkflowCleanupApplied
				? "\n\nWORKFLOW DRIVER NOTE: Canonical workflow state closed and the extension removed repo-local .agent/ as expected cleanup. Treat missing .agent/current/** and .agent/verify_completion_*.sh after this point as normal closeout behavior, not as a missing tracked-file anomaly, and do not recreate local helper forwarders merely to narrate completion."
				: "";

			liveRoleActivityByRoot.set(rootKey, cloneLiveRoleActivity(result.activity, { status: result.ok ? "ok" : "error" }));
			await refreshCompletionStatus({ ctx: ctx as { cwd: string; hasUI: boolean; ui: any }, ...statusSurfaceArgs });
			setTimeout(() => {
				const current = liveRoleActivityByRoot.get(rootKey);
				if (current && current.role === role && current.status !== "running") {
					liveRoleActivityByRoot.delete(rootKey);
				}
			}, 10_000);
			return {
				content: [{ type: "text", text: `${result.output}${closedWorkflowCleanupNote}` }],
				details: {
					role,
					status: result.ok ? "ok" : "error",
					exitCode: result.exitCode,
					stderr: result.stderr,
					reportFields: result.reportFields,
					transcription: result.transcription,
					closedWorkflowCleanupApplied,
					currentAction: result.activity.currentAction,
					toolActivity: result.activity.toolActivity,
					toolRecentActivity: result.activity.toolRecentActivity,
					recentActivity: result.activity.recentActivity,
					assistantSummary: result.activity.assistantSummary,
					lastAssistantText: result.activity.lastAssistantText,
					progress: result.activity.progress,
					rationale: result.activity.rationale,
					nextStep: result.activity.nextStep,
					verifying: result.activity.verifying,
					stateDeltas: result.activity.stateDeltas,
					startedAt: result.activity.startedAt,
					updatedAt: result.activity.updatedAt,
				},
				isError: !result.ok,
			};
		},
		renderCall(args, theme) {
			const role = args.role || "completion-role";
			const task = typeof args.task === "string" ? args.task.trim() : "";
			let text = theme.fg("toolTitle", theme.bold("completion_role ")) + theme.fg("accent", role);
			if (task) {
				text += `\n${theme.fg("muted", task)}`;
			}
			return new Text(text, 0, 0);
		},
		renderResult(result, { expanded, isPartial }, theme) {
			const details = (result.details ?? {}) as {
				role?: string;
				status?: string;
				exitCode?: number;
				stderr?: string;
				reportFields?: Record<string, string>;
				transcription?: TranscriptionResult;
				currentAction?: string;
				toolActivity?: string;
				toolRecentActivity?: string[];
				recentActivity?: string[];
				assistantSummary?: string;
				lastAssistantText?: string;
				progress?: string;
				rationale?: string;
				nextStep?: string;
				verifying?: string;
				stateDeltas?: string[];
				startedAt?: number;
				updatedAt?: number;
			};
			if (isPartial) {
				const lines = buildInlineRunningLines(details);
				return new Text(formatInlineRunningText(theme, lines), 0, 0);
			}
			const role = details.role ?? "completion-role";
			const ok = details.status === "ok" && !result.isError;
			let text = `${theme.fg(ok ? "success" : "error", ok ? "done" : "error")} ${theme.fg("toolTitle", theme.bold(role))}`;
			if (details.startedAt !== undefined) text += `\n${theme.fg("muted", `elapsed: ${formatElapsed(nowMs() - details.startedAt)}`)}`;
			if (details.toolActivity) text += `\n${theme.fg("toolOutput", `tool: ${details.toolActivity}`)}`;
			if (details.progress) text += `\n${theme.fg("toolOutput", `progress: ${details.progress}`)}`;
			else if (details.assistantSummary) text += `\nassistant: ${details.assistantSummary}`;
			if (details.rationale) text += `\n${theme.fg("muted", `rationale: ${details.rationale}`)}`;
			if (details.nextStep) text += `\n${theme.fg("muted", `next: ${details.nextStep}`)}`;
			if (details.verifying) text += `\n${theme.fg("muted", `verifying: ${details.verifying}`)}`;
			if (details.stateDeltas?.length) {
				for (const delta of details.stateDeltas.slice(-4)) text += `\n${theme.fg("muted", `state-delta: ${delta}`)}`;
			}
			if (details.transcription?.appended?.length) {
				text += `\n${theme.fg("success", `transcribed: ${details.transcription.appended.join(", ")}`)}`;
			}
			if (details.transcription?.skipped?.length && expanded) {
				text += `\n${theme.fg("muted", `skipped: ${details.transcription.skipped.join(" | ")}`)}`;
			}
			if (details.transcription?.errors?.length) {
				text += `\n${theme.fg("warning", `warnings: ${details.transcription.errors.join(" | ")}`)}`;
			}
			const reportFields = details.reportFields ?? {};
			const summaryKeys = [
				"MISSION ANCHOR",
				"Remaining contract IDs",
				"Next role to invoke",
				"Reconciliation decision",
				"Can the project stop now",
				"Acceptable as-is",
				"Plan adjustment required",
			];
			for (const key of summaryKeys) {
				const value = reportFields[key];
				if (!value) continue;
				text += `\n${theme.fg("muted", `${key}: `)}${value}`;
			}
			const body = result.content.find((item) => item.type === "text");
			if (expanded && body?.type === "text") {
				text += `\n\n${body.text}`;
			} else if (!expanded && body?.type === "text") {
				const preview = body.text.split("\n").slice(0, 4).join("\n");
				text += `\n${theme.fg("muted", preview)}`;
			}
			if (details.stderr && expanded) text += `\n${theme.fg("error", details.stderr)}`;
			return new Text(text, 0, 0);
		},
	});

	registerCookCommand(pi, driverDeps);

}
