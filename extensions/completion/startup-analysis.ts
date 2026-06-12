import {
	assessMissionAnchor,
	extractJsonObjectFromText,
	finalizeContextProposalAnalysis,
	isWeakMissionAnchor,
	normalizeMissionAnchorText,
	parseContextProposalAnalystOutput,
	serializeRecentDiscussionEntries,
	type ContextProposal,
	type RecentDiscussionEntry,
} from "./proposal";
import { validateStartupAnalysisRecord, startupAnalysisValidationDefaults } from "./startup-validation";
import type { JsonRecord } from "./types";

function isRecord(value: unknown): value is JsonRecord {
	return typeof value === "object" && value !== null && !Array.isArray(value);
}

export function buildStartupAnalysisPrompt(projectName: string, discussion: string, contextLines: string[] = []): string {
	const lines = [
		`Project: ${projectName}`,
		"Analyze whether the user has provided enough repo-change intent to start /cook safely.",
		"Treat /cook itself as the workflow-entry signal; do not require English implementation-intent keywords before analyzing recent discussion.",
		"Prefer the latest clear user implementation intent and canonical workflow context over older background discussion.",
		"Use recent user/custom discussion plus canonical workflow context only; do not assume a workflow-startable mission when the discussion is planning-only, ambiguous, or weak.",
		"When startup intent is unclear, contradictory, or low-confidence, return a non-startable analysis instead of inventing a generic mission anchor.",
	];
	if (contextLines.length > 0) lines.push("", "Canonical workflow context:", ...contextLines);
	lines.push("", "Recent discussion:", discussion || "(none)");
	return lines.join("\n");
}

export function buildStartupAnalysisPromptFromEntries(
	projectName: string,
	recentEntries: RecentDiscussionEntry[],
	contextLines: string[] = [],
	serializeEntries: (entries: RecentDiscussionEntry[]) => string = serializeRecentDiscussionEntries,
): string {
	return buildStartupAnalysisPrompt(projectName, serializeEntries(recentEntries), contextLines);
}

export function parseStartupAnalysisOutput(raw: string, projectName: string): ContextProposal | undefined {
	const jsonText = extractJsonObjectFromText(raw);
	if (!jsonText) return undefined;
	let parsed: unknown;
	try {
		parsed = JSON.parse(jsonText);
	} catch {
		return undefined;
	}
	if (!isRecord(parsed)) return undefined;
	const validated = validateStartupAnalysisRecord(parsed, projectName, {
		...startupAnalysisValidationDefaults,
		assessMissionAnchor,
		normalizeMissionAnchorText,
		isWeakMissionAnchor,
	});
	if (!validated) return undefined;
	if (validated.verdict !== "startable") return undefined;
	const proposal = parseContextProposalAnalystOutput(
		JSON.stringify({
			mission: validated.mission,
			scope: validated.scope,
			constraints: validated.constraints,
			acceptance: validated.acceptance,
			diagnostics: validated.diagnostics,
			critique: validated.critique,
			risks: validated.risks,
			possible_noise: validated.possibleNoise,
			alternate_missions: validated.alternateMissions,
			completed_topics: validated.suppressedCompletedTopics,
			negated_topics: validated.suppressedNegatedTopics,
			task_type: validated.taskType,
			evaluation_profile: validated.evaluationProfile,
		}),
		projectName,
	);
	if (!proposal) return undefined;
	return {
		...proposal,
		basisPreview: validated.basisPreview,
		analysis: finalizeContextProposalAnalysis(
			{
				...proposal.analysis,
				startupVerdict: validated.verdict,
				workflowRelation: validated.workflowRelation,
				confidence: validated.confidence,
				diagnostics: validated.diagnostics,
			},
			[proposal.goalText, proposal.mission, ...validated.diagnostics],
		),
	};
}
