import { spawn } from "node:child_process";
import * as roleReporting from "./role-reporting.js";
import { loadCompletionSnapshot } from "./state-store";
import {
	renderEvaluatorReport,
	renderRoleHandoffReport,
} from "./structured-renderers.ts";
import type {
	StructuredEvaluatorReport,
	StructuredRoleHandoffReport,
} from "./structured-contracts.ts";
import type { CompletionRole, JsonRecord } from "./types";

function asString(value: unknown): string | undefined {
	return typeof value === "string" && value.trim().length > 0 ? value.trim() : undefined;
}

export type TranscriptionResult = {
	appended: string[];
	skipped: string[];
	errors: string[];
};

export function parseReportFields(text: string): Record<string, string> {
	return roleReporting.parseReportFields(text);
}

export function buildRoleReportRepairPrompt(role: CompletionRole, errors: string[]): string | undefined {
	return roleReporting.buildRoleReportRepairPrompt(role, errors);
}

async function gitHeadSha(cwd: string): Promise<string | undefined> {
	return await new Promise((resolve) => {
		const proc = spawn("git", ["rev-parse", "HEAD"], { cwd, stdio: ["ignore", "pipe", "ignore"] });
		let stdout = "";
		proc.stdout.on("data", (chunk) => {
			stdout += chunk.toString();
		});
		proc.on("close", (code) => {
			resolve(code === 0 ? asString(stdout) : undefined);
		});
		proc.on("error", () => resolve(undefined));
	});
}

export type TranscriptionOptions = {
	structuredEvaluatorReport?: StructuredEvaluatorReport;
	structuredRoleHandoffReport?: StructuredRoleHandoffReport;
};

export function validateStructuredRoleReport(role: CompletionRole, structured: StructuredEvaluatorReport | StructuredRoleHandoffReport) {
	const output =
		"rubric" in structured && Array.isArray(structured.rubric)
			? renderEvaluatorReport(structured as StructuredEvaluatorReport)
			: renderRoleHandoffReport(structured as StructuredRoleHandoffReport);
	const reportFields = parseReportFields(output);
	return roleReporting.validateRoleReport(role, output, reportFields);
}

export async function transcribeRoleOutput(
	role: CompletionRole,
	cwd: string,
	output: string,
	reportFields: Record<string, string>,
	options?: TranscriptionOptions,
): Promise<TranscriptionResult> {
	let effectiveOutput = output;
	let effectiveFields = reportFields;
	if (options?.structuredEvaluatorReport) {
		effectiveOutput = renderEvaluatorReport(options.structuredEvaluatorReport);
		effectiveFields = parseReportFields(effectiveOutput);
	} else if (options?.structuredRoleHandoffReport) {
		effectiveOutput = renderRoleHandoffReport(options.structuredRoleHandoffReport);
		effectiveFields = parseReportFields(effectiveOutput);
	}
	const snapshot = await loadCompletionSnapshot(cwd);
	if (!snapshot) {
		return { appended: [], skipped: ["No canonical completion snapshot found."], errors: [] };
	}
	const headSha = await gitHeadSha(snapshot.files.root);
	if (!headSha) {
		return { appended: [], skipped: [], errors: ["Could not resolve git HEAD for transcription."] };
	}

	const sliceId =
		asString(snapshot.active?.slice_id) ??
		asString(snapshot.activeSlice?.slice_id) ??
		asString(snapshot.state?.latest_completed_slice);

	return await roleReporting.transcribeCanonicalRoleReport({
		role,
		output: effectiveOutput,
		reportFields: effectiveFields,
		structuredReport: options?.structuredEvaluatorReport ?? options?.structuredRoleHandoffReport,
		snapshotFiles: snapshot.files,
		headSha,
		sliceId,
	});
}

export async function appendJsonlRecord(filePath: string, record: JsonRecord): Promise<void> {
	const fs = await import("node:fs/promises");
	const path = await import("node:path");
	await fs.mkdir(path.dirname(filePath), { recursive: true });
	await fs.appendFile(filePath, `${JSON.stringify(record)}\n`, "utf8");
}
