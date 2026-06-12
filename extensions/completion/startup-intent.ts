import {
	assessLatestCookHandoffProposal,
	deriveCookContextProposalFromRecentDiscussion,
} from "./proposal";
import type {
	ContextProposal,
	ContextProposalAnalysis,
	ContextProposalWorkflowContext,
	RecentDiscussionEntry,
	RecentSessionMessage,
} from "./proposal";
import type { CompletionStateSnapshot } from "./types";

export type CookProposalDeps = {
	asString: (value: unknown) => string | undefined;
	asStringArray: (value: unknown) => string[];
	assessMissionAnchor: (text: string, projectName: string) => { derived: string };
	normalizeMissionAnchorText: (text: string) => string;
	isWeakMissionAnchor: (text: string) => boolean;
	missionAnchorsStrictlyEquivalent: (left: string, right: string) => boolean;
	missionAnchorsLikelyEquivalent: (left: string, right: string) => boolean;
	stripCodeBlocks: (text: string) => string;
};

export type CookContextProposalResult = {
	proposal?: ContextProposal;
};

export type StartupIntentHints = {
	firstSliceGoal?: string;
	firstSliceNonGoals: string[];
	implementationSurfaces: string[];
	verificationCommands: string[];
	whyThisSliceFirst?: string;
};

export type CookSynthesisContext = {
	recentEntries: RecentDiscussionEntry[];
	workflowContext?: ContextProposalWorkflowContext;
	workflowContextLines: string[];
	explicit: CookContextProposalResult;
	shouldTightenExplicitProposal: boolean;
	shouldAnalyzeRecentDiscussion: boolean;
};

export type AdvisoryStartupBrief = {
	kind: "startup_brief";
	source: "recent_discussion" | "primary_agent_handoff" | "deferred_primary_agent_handoff";
	confirmed: true;
	captured_at: string;
	goal_text: string;
	mission: string;
	scope: string[];
	constraints: string[];
	acceptance: string[];
	risks: string[];
	notes: string[];
	first_slice_goal_hint?: string;
	first_slice_non_goals_hint?: string[];
	implementation_surfaces_hint?: string[];
	verification_commands_hint?: string[];
	why_this_slice_first_hint?: string;
	task_type?: string;
	evaluation_profile?: string;
};

const COOK_HANDOFF_BLOCK_REGEX = /```cook_handoff\s*[\s\S]*?```/giu;

function asString(value: unknown): string | undefined {
	return typeof value === "string" && value.trim().length > 0 ? value.trim() : undefined;
}

function stripCookHandoffBlocks(text: string): string {
	return text.replace(COOK_HANDOFF_BLOCK_REGEX, " ").replace(/\s+/g, " ").trim();
}

function buildAdvisoryStartupBriefNotes(analysis: ContextProposalAnalysis): string[] {
	const notes = [
		...analysis.diagnostics.map((item) => `Diagnostic: ${item}`),
		...analysis.critique,
		...analysis.possibleNoise.map((item) => `Possible noise: ${item}`),
	];
	return notes.length > 0 ? notes : ["No additional operator notes were derived from recent discussion."];
}

export function startupHintsPresent(hints: StartupIntentHints | undefined): boolean {
	if (!hints) return false;
	return Boolean(
		hints.firstSliceGoal ||
			hints.firstSliceNonGoals.length > 0 ||
			hints.implementationSurfaces.length > 0 ||
			hints.verificationCommands.length > 0 ||
			hints.whyThisSliceFirst,
	);
}

export function proposalNeedsCookStartupTightening(
	proposal: Pick<ContextProposal, "source" | "startupHints" | "analysis">,
): boolean {
	if (proposal.source !== "handoff_capsule") return false;
	const startupHints = proposal.startupHints;
	if (!startupHints?.firstSliceGoal) return true;
	if (startupHints.implementationSurfaces.length === 0) return true;
	if (startupHints.verificationCommands.length === 0) return true;
	return proposal.analysis.critique.some((item) => /startup acceptance (?:was not fully captured|remained high-level)/iu.test(item));
}

export function workflowContextFromSnapshot(
	snapshot: CompletionStateSnapshot | undefined,
): ContextProposalWorkflowContext | undefined {
	if (!snapshot) return undefined;
	return {
		currentMissionAnchor: asString(snapshot.state?.mission_anchor) ?? asString(snapshot.plan?.mission_anchor) ?? asString(snapshot.active?.mission_anchor),
		continuationPolicy: asString(snapshot.state?.continuation_policy),
		latestCompletedSlice: asString(snapshot.state?.latest_completed_slice),
		latestVerifiedSlice: asString(snapshot.state?.latest_verified_slice),
		activeSliceGoal: asString(snapshot.active?.goal),
		activeSliceWhyNow: asString(snapshot.active?.why_now),
		verificationGoal: asString(snapshot.verificationEvidence?.goal),
		verificationSummary: asString(snapshot.verificationEvidence?.summary),
	};
}

export function buildWorkflowContextLines(workflowContext: ContextProposalWorkflowContext | undefined): string[] {
	if (!workflowContext) return [];
	return [
		`current mission anchor: ${workflowContext.currentMissionAnchor ?? "(none)"}`,
		`continuation policy: ${workflowContext.continuationPolicy ?? "(none)"}`,
		`latest completed slice: ${workflowContext.latestCompletedSlice ?? "(none)"}`,
		`latest verified slice: ${workflowContext.latestVerifiedSlice ?? "(none)"}`,
		`active slice goal: ${workflowContext.activeSliceGoal ?? "(none)"}`,
		`active slice why_now: ${workflowContext.activeSliceWhyNow ?? "(none)"}`,
		`verification goal: ${workflowContext.verificationGoal ?? "(none)"}`,
		`verification summary: ${workflowContext.verificationSummary ?? "(none)"}`,
	];
}

export function buildCookRecentEntries(args: {
	inlinePrompt?: string;
	recentMessages: RecentSessionMessage[];
	limit?: number;
}): RecentDiscussionEntry[] {
	const limit = args.limit ?? 12;
	return [
		...(args.inlinePrompt ? [{ role: "user" as const, text: args.inlinePrompt }] : []),
		...args.recentMessages
			.filter((entry) => !entry.isCommand && (entry.role === "user" || entry.role === "assistant" || entry.role === "custom" || entry.role === "summary"))
			.slice(0, limit)
			.map((entry) => ({ role: entry.role, text: stripCookHandoffBlocks(entry.text) }))
			.filter((entry) => entry.text.length > 0),
	];
}

export function shouldAnalyzeCookRecentDiscussion(recentEntries: RecentDiscussionEntry[]): boolean {
	return recentEntries.some((entry) => entry.text.trim().length > 0);
}

function sharedNormalizedPrefixLength(left: string, right: string): number {
	const max = Math.min(left.length, right.length);
	let index = 0;
	while (index < max && left[index] === right[index]) index += 1;
	return index;
}

function synthesizedMissionTightensExplicitMission(
	explicitMission: string,
	candidateMission: string,
	deps: Pick<CookProposalDeps, "missionAnchorsLikelyEquivalent" | "normalizeMissionAnchorText">,
): boolean {
	if (deps.missionAnchorsLikelyEquivalent(explicitMission, candidateMission)) return true;
	const normalizedExplicit = deps.normalizeMissionAnchorText(explicitMission).toLowerCase();
	const normalizedCandidate = deps.normalizeMissionAnchorText(candidateMission).toLowerCase();
	if (!normalizedExplicit || !normalizedCandidate) return false;
	if (normalizedExplicit.includes(normalizedCandidate) || normalizedCandidate.includes(normalizedExplicit)) return true;
	const sharedPrefixLength = sharedNormalizedPrefixLength(normalizedExplicit, normalizedCandidate);
	return sharedPrefixLength >= 24 && sharedPrefixLength / Math.min(normalizedExplicit.length, normalizedCandidate.length) >= 0.5;
}

export function buildCookSynthesisContext(args: {
	inlinePrompt?: string;
	recentMessages: RecentSessionMessage[];
	snapshot?: CompletionStateSnapshot;
	explicit: CookContextProposalResult;
	stripCodeBlocks: (text: string) => string;
}): CookSynthesisContext {
	const shouldTightenExplicitProposal = args.explicit.proposal ? proposalNeedsCookStartupTightening(args.explicit.proposal) : false;
	const recentEntries = buildCookRecentEntries({
		inlinePrompt: args.inlinePrompt,
		recentMessages: args.recentMessages,
	});
	const workflowContext = workflowContextFromSnapshot(args.snapshot);
	const workflowContextLines = buildWorkflowContextLines(workflowContext);
	if (args.inlinePrompt) {
		workflowContextLines.push(`inline /cook startup intent: ${args.inlinePrompt}`);
		workflowContextLines.push("Treat the inline /cook prompt as the highest-priority explicit startup intent for this workflow entry.");
	}
	if (args.explicit.proposal && shouldTightenExplicitProposal) {
		workflowContextLines.push("A fresh explicit primary-agent handoff is available. Use it as startup input, but tighten weak acceptance or initial-slice hints from recent discussion when possible.");
		workflowContextLines.push(`Explicit handoff summary:\n${args.explicit.proposal.basisPreview}`);
	}
	const shouldAnalyzeRecentDiscussion = shouldAnalyzeCookRecentDiscussion(recentEntries);
	return {
		recentEntries,
		workflowContext,
		workflowContextLines,
		explicit: args.explicit,
		shouldTightenExplicitProposal,
		shouldAnalyzeRecentDiscussion,
	};
}

export function deriveCookStartupProposalFromRecentMessages(args: {
	inlinePrompt?: string;
	recentMessages: RecentSessionMessage[];
	projectName: string;
	deps: CookProposalDeps;
}): CookContextProposalResult {
	const explicitHandoff = assessLatestCookHandoffProposal(args.recentMessages, args.projectName, args.deps);
	return explicitHandoff.status === "startable" ? { proposal: explicitHandoff.proposal } : {};
}

export async function deriveCookContextProposalWithSynthesis(args: {
	inlinePrompt?: string;
	recentMessages: RecentSessionMessage[];
	snapshot?: CompletionStateSnapshot;
	projectName: string;
	deps: CookProposalDeps;
	generateCookHandoff?: (params: { recentEntries: RecentDiscussionEntry[]; workflowContextLines: string[] }) => Promise<string | undefined>;
	analyzeContextProposal?: (params: {
		recentEntries: RecentDiscussionEntry[];
		workflowContextLines: string[];
	}) => Promise<ContextProposal | undefined>;
}): Promise<CookContextProposalResult> {
	const explicit = deriveCookStartupProposalFromRecentMessages({
		inlinePrompt: args.inlinePrompt,
		recentMessages: args.recentMessages,
		projectName: args.projectName,
		deps: args.deps,
	});
	const explicitProposal = explicit.proposal;
	const shouldTightenExplicitProposal = explicitProposal ? proposalNeedsCookStartupTightening(explicitProposal) : false;
	if (explicitProposal && !shouldTightenExplicitProposal) return explicit;
	const synthesisContext = buildCookSynthesisContext({
		inlinePrompt: args.inlinePrompt,
		recentMessages: args.recentMessages,
		snapshot: args.snapshot,
		explicit,
		stripCodeBlocks: args.deps.stripCodeBlocks,
	});
	const { recentEntries, workflowContext, workflowContextLines } = synthesisContext;
	const raw = await args.generateCookHandoff?.({ recentEntries, workflowContextLines });
	if (raw) {
		const generated = assessLatestCookHandoffProposal(
			[{ role: "assistant", text: raw, messageId: "generated-primary-agent-handoff", timestampMs: Date.now(), isCommand: false }],
			args.projectName,
			args.deps,
		);
		if (generated.status === "startable") {
			if (!explicitProposal) return { proposal: generated.proposal };
			if (synthesizedMissionTightensExplicitMission(explicitProposal.mission, generated.proposal.mission, args.deps)) {
				return { proposal: generated.proposal };
			}
			return explicit;
		}
	}
	if (!explicitProposal && synthesisContext.shouldAnalyzeRecentDiscussion) {
		const derivedFromRecentDiscussion = await deriveCookContextProposalFromRecentDiscussion(args.projectName, recentEntries, {
			...args.deps,
			analyzeContextProposal: args.analyzeContextProposal
				? async (candidateEntries) => args.analyzeContextProposal?.({ recentEntries: candidateEntries, workflowContextLines })
				: undefined,
			workflowContext,
		});
		if (derivedFromRecentDiscussion) return { proposal: derivedFromRecentDiscussion };
	}
	if (explicitProposal) return explicit;
	return {};
}

export function buildAdvisoryStartupBrief(args: {
	proposal: Pick<ContextProposal, "goalText" | "mission" | "scope" | "constraints" | "acceptance" | "source" | "startupHints">;
	analysis: ContextProposalAnalysis;
	capturedAt?: string;
}): AdvisoryStartupBrief {
	return {
		kind: "startup_brief",
		source:
			args.proposal.source === "handoff_capsule"
				? "primary_agent_handoff"
				: args.proposal.source === "deferred_primary_agent_handoff"
					? "deferred_primary_agent_handoff"
					: "recent_discussion",
			confirmed: true,
			captured_at: args.capturedAt ?? new Date().toISOString(),
			goal_text: args.proposal.goalText,
			mission: args.proposal.mission,
			scope: [...args.proposal.scope],
			constraints: [...args.proposal.constraints],
			acceptance: [...args.proposal.acceptance],
			risks: [...args.analysis.risks],
			notes: buildAdvisoryStartupBriefNotes(args.analysis),
			first_slice_goal_hint: args.proposal.startupHints?.firstSliceGoal,
			first_slice_non_goals_hint:
				args.proposal.startupHints && args.proposal.startupHints.firstSliceNonGoals.length > 0
					? [...args.proposal.startupHints.firstSliceNonGoals]
					: undefined,
			implementation_surfaces_hint:
				args.proposal.startupHints && args.proposal.startupHints.implementationSurfaces.length > 0
					? [...args.proposal.startupHints.implementationSurfaces]
					: undefined,
			verification_commands_hint:
				args.proposal.startupHints && args.proposal.startupHints.verificationCommands.length > 0
					? [...args.proposal.startupHints.verificationCommands]
					: undefined,
			why_this_slice_first_hint: args.proposal.startupHints?.whyThisSliceFirst,
			task_type: args.analysis.taskType,
			evaluation_profile: args.analysis.evaluationProfile,
		};
}
