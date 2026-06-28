import * as roleReporting from "./role-reporting.js";
import {
	RUBRIC_DIMENSIONS,
	type StructuredEvaluatorReport,
	type StructuredRoleHandoffReport,
	type StructuredRubricLine,
} from "./structured-contracts.ts";
import type { JsonRecord } from "./types";

function formatRubricLine(line: StructuredRubricLine): string {
	return `- ${line.dimension}: ${line.verdict} - ${line.explanation}`;
}

function renderFieldLines(fields: JsonRecord, orderedKeys?: string[]): string[] {
	const keys = orderedKeys ?? Object.keys(fields);
	const lines: string[] = [];
	for (const key of keys) {
		const value = fields[key];
		if (typeof value !== "string" || value.trim().length === 0) continue;
		lines.push(`${key}: ${value.trim()}`);
	}
	return lines;
}

export function renderReviewerReport(report: StructuredEvaluatorReport): string {
	const lines = [
		`MISSION ANCHOR: ${report.missionAnchor}`,
		`Remaining contract IDs: ${report.remainingContractIds}`,
		"Rubric:",
		...report.rubric.map(formatRubricLine),
		...renderFieldLines(report.fields, ["Findings", "Acceptable as-is", "Smallest follow-up slice"]),
	];
	return lines.join("\n");
}

export function renderAuditorReport(report: StructuredEvaluatorReport): string {
	const lines = [
		`MISSION ANCHOR: ${report.missionAnchor}`,
		`Remaining contract IDs: ${report.remainingContractIds}`,
		"Rubric:",
		...report.rubric.map(formatRubricLine),
		...renderFieldLines(report.fields, [
			"Why the project is still not done",
			"Open top-level contract IDs",
			"Blocker count",
			"High-value gap count",
			"Tracked and unignored worktree is clean",
			"Worktree blockers",
			"Next mandatory slice",
			"Stale or conflicting canonical state",
			"Plan truthfully captures remaining slice backlog",
		]),
	];
	return lines.join("\n");
}

export function renderStopJudgeReport(report: StructuredEvaluatorReport): string {
	const lines = [
		`MISSION ANCHOR: ${report.missionAnchor}`,
		`Remaining contract IDs: ${report.remainingContractIds}`,
		"Rubric:",
		...report.rubric.map(formatRubricLine),
		...renderFieldLines(report.fields, [
			"Can the project stop now",
			"Exact remaining open top-level contract IDs",
			"Blocker count",
			"High-value gap count",
			"Latest completed slice commit",
			"Docs/config/runbooks match shipped behavior",
			"Tracked and unignored worktree is clean",
			"Brief justification",
		]),
	];
	return lines.join("\n");
}

export function renderEvaluatorReport(report: StructuredEvaluatorReport): string {
	switch (report.contractId) {
		case "completion.evaluator.reviewer.v1":
			return renderReviewerReport(report);
		case "completion.evaluator.auditor.v1":
			return renderAuditorReport(report);
		case "completion.evaluator.stop_judge.v1":
			return renderStopJudgeReport(report);
		default:
			return [
				`MISSION ANCHOR: ${report.missionAnchor}`,
				`Remaining contract IDs: ${report.remainingContractIds}`,
				"Rubric:",
				...report.rubric.map(formatRubricLine),
				...renderFieldLines(report.fields),
			].join("\n");
	}
}

export function renderBootstrapperReport(report: StructuredRoleHandoffReport): string {
	const lines = [
		`MISSION ANCHOR: ${report.fields["MISSION ANCHOR"] ?? report.fields.mission_anchor ?? ""}`,
		`Remaining contract IDs: ${report.fields["Remaining contract IDs"] ?? report.fields.remaining_contract_ids ?? ""}`,
		...renderFieldLines(report.fields, [
			"Bootstrap applied",
			"Local helper files repaired",
			"Execution-state files initialized",
			"Gitignore updated",
			"Next role to invoke",
			"Exact handoff payload",
			"Canonical blockers",
		]),
	];
	return lines.filter((line) => line.trim().length > 0).join("\n");
}

export function renderRegrounderReport(report: StructuredRoleHandoffReport): string {
	const lines = [
		`MISSION ANCHOR: ${report.fields["MISSION ANCHOR"] ?? report.fields.mission_anchor ?? ""}`,
		`Remaining contract IDs: ${report.fields["Remaining contract IDs"] ?? report.fields.remaining_contract_ids ?? ""}`,
		...renderFieldLines(report.fields, [
			"Canonical re-ground applied",
			"Acceptance criteria revalidated",
			"Tracked and unignored worktree is clean",
			"Reopened slices",
			"Reconciliation decision",
			"Reconciled slice ID",
			"Current selected slice",
			"Next role to invoke",
			"Exact handoff payload",
			"Canonical blockers or deviations",
		]),
	];
	return lines.filter((line) => line.trim().length > 0).join("\n");
}

export function renderImplementerReport(report: StructuredRoleHandoffReport): string {
	const lines = [
		`MISSION ANCHOR: ${report.fields["MISSION ANCHOR"] ?? report.fields.mission_anchor ?? ""}`,
		`Remaining contract IDs before slice: ${report.fields["Remaining contract IDs before slice"] ?? report.fields.remaining_contract_ids_before_slice ?? ""}`,
		...renderFieldLines(report.fields, [
			"Slice ID",
			"Slice goal",
			"Contract IDs closed or advanced",
			"Files changed",
			"Tests added or strengthened",
			"Verification commands run",
			"Verification results",
			"Commit SHA",
			"What release gap this closed",
			"Plan adjustment required",
			"Residual risks discovered",
			"Remaining contract IDs after slice",
		]),
	];
	return lines.filter((line) => line.trim().length > 0).join("\n");
}

export function renderRoleHandoffReport(report: StructuredRoleHandoffReport): string {
	switch (report.contractId) {
		case "completion.role.bootstrapper.v1":
			return renderBootstrapperReport(report);
		case "completion.role.regrounder.v1":
			return renderRegrounderReport(report);
		case "completion.role.implementer.v1":
			return renderImplementerReport(report);
		default:
			return renderFieldLines(report.fields).join("\n");
	}
}

export function structuredReportFieldsFromRenderedText(text: string): Record<string, string> {
	return roleReporting.parseReportFields(text);
}

export function emptyRubricTemplate(): StructuredRubricLine[] {
	return RUBRIC_DIMENSIONS.map((dimension) => ({
		dimension,
		verdict: "pass" as const,
		explanation: "placeholder",
	}));
}

export function roundTripReportFieldsParity(text: string): boolean {
	const fields = roleReporting.parseReportFields(text);
	return Object.keys(fields).length > 0;
}
