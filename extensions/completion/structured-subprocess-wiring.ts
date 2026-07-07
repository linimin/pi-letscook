import * as fs from "node:fs";
import * as path from "node:path";
import {
	contractIdForCompletionRole,
	COMPLETION_COOK_HANDOFF_CONTRACT_ID,
	EMIT_COOK_HANDOFF_TOOL,
	EMIT_STARTUP_ANALYSIS_TOOL,
	getStructuredContract,
	type StructuredCookHandoffPayload,
	type StructuredEvaluatorReport,
	type StructuredRoleHandoffReport,
} from "./structured-contracts.ts";
import { requireSubprocessFinalOutput, StructuredSubprocessOutputError } from "./subprocess-final-output.ts";
import { renderEvaluatorReport, renderRoleHandoffReport } from "./structured-renderers.ts";
import * as roleReporting from "./role-reporting.js";
import type { CompletionRole, JsonRecord } from "./types";

export { StructuredSubprocessOutputError };

export type CookHandoffGenerationResult =
	| { kind: "handoff"; text: string }
	| { kind: "no_handoff"; reason: string }
	| { kind: "failed" };

function asString(value: unknown): string | undefined {
	return typeof value === "string" && value.trim().length > 0 ? value.trim() : undefined;
}

function cookHandoffKind(capsule: JsonRecord): string | undefined {
	return asString(capsule.handoff_kind ?? capsule.handoffKind);
}

function cookHandoffReason(capsule: JsonRecord): string | undefined {
	return asString(capsule.reason ?? capsule.notes);
}

export function formatCookHandoffNoHandoffSummary(reason: string): string {
	return `Structured no-handoff: ${reason}`;
}

export function resolveCookHandoffSubprocessResult(args: {
	assistantText?: string;
	eventLines?: string[];
}): CookHandoffGenerationResult {
	try {
		const { payload } = requireSubprocessFinalOutput<StructuredCookHandoffPayload>({
			eventLines: args.eventLines,
			contractId: COMPLETION_COOK_HANDOFF_CONTRACT_ID,
			assistantText: args.assistantText,
		});
		const handoffKind = cookHandoffKind(payload.capsule);
		if (handoffKind === "unable_to_prepare") {
			return {
				kind: "no_handoff",
				reason: cookHandoffReason(payload.capsule) ?? "primary agent could not prepare a workflow-startable handoff",
			};
		}
		if (handoffKind !== "implementation_workflow_handoff") return { kind: "failed" };
		return {
			kind: "handoff",
			text: `\`\`\`cook_handoff\n${JSON.stringify(payload.capsule, null, 2)}\n\`\`\``,
		};
	} catch {
		return { kind: "failed" };
	}
}

export function resolveCookHandoffSubprocessText(args: { assistantText?: string; eventLines?: string[] }): string | undefined {
	const result = resolveCookHandoffSubprocessResult(args);
	return result.kind === "handoff" ? result.text : undefined;
}

export function completionStructuredToolsExtensionPath(): string {
	const candidates = [
		typeof __dirname === "string" ? path.resolve(__dirname, "..", "completion-structured-tools") : undefined,
		path.join(process.cwd(), "extensions", "completion-structured-tools"),
	].filter((candidate): candidate is string => Boolean(candidate));
	for (const candidate of candidates) {
		if (fs.existsSync(path.join(candidate, "index.ts"))) return candidate;
	}
	return candidates[0] ?? path.join(process.cwd(), "extensions", "completion-structured-tools");
}

export function structuredEmitToolForRole(role: CompletionRole): string | undefined {
	const contractId = contractIdForCompletionRole(role);
	if (!contractId) return undefined;
	return getStructuredContract(contractId)?.terminatingToolName;
}

function extensionPathAlreadyLoaded(args: string[], extensionPath: string): boolean {
	const normalizedTarget = path.resolve(extensionPath);
	for (let index = 0; index < args.length; index += 1) {
		const arg = args[index];
		if (arg !== "-e" && arg !== "--extension") continue;
		const candidate = args[index + 1];
		if (typeof candidate === "string" && path.resolve(candidate) === normalizedTarget) return true;
	}
	return false;
}

export function appendStructuredToolsToPiArgs(args: string[], emitToolNames: string[]): string[] {
	if (emitToolNames.length === 0) return args;
	const extensionPath = completionStructuredToolsExtensionPath();
	if (!fs.existsSync(path.join(extensionPath, "index.ts"))) return args;

	const next = [...args];
	if (!extensionPathAlreadyLoaded(next, extensionPath)) {
		next.push("-e", extensionPath);
	}

	const toolsIndex = next.findIndex((value) => value === "--tools" || value === "-t");
	if (toolsIndex >= 0) {
		const existing = next[toolsIndex + 1];
		const merged = new Set(
			(typeof existing === "string" ? existing.split(",") : [])
				.map((tool) => tool.trim())
				.filter(Boolean),
		);
		for (const tool of emitToolNames) merged.add(tool);
		next[toolsIndex + 1] = Array.from(merged).join(",");
	} else {
		next.push("--tools", emitToolNames.join(","));
	}
	return next;
}

export function effectiveRoleToolAllowlistWithStructured(role: CompletionRole, declaredTools?: string[]): string[] | undefined {
	const emitTool = structuredEmitToolForRole(role);
	const base = declaredTools === undefined ? undefined : declaredTools.map((tool) => tool.trim()).filter(Boolean);
	if (!emitTool) {
		if (base === undefined) return undefined;
		return base.length > 0 ? base : undefined;
	}
	const merged = new Set(base ?? []);
	merged.add(emitTool);
	return Array.from(merged);
}

export function startupAnalystEmitToolName(): string {
	return EMIT_STARTUP_ANALYSIS_TOOL;
}

export function cookHandoffEmitToolName(): string {
	return EMIT_COOK_HANDOFF_TOOL;
}

export type ResolvedRoleSubprocessOutput = {
	output: string;
	reportFields: Record<string, string>;
	structuredEvaluatorReport?: StructuredEvaluatorReport;
	structuredRoleHandoffReport?: StructuredRoleHandoffReport;
};

export function resolveRoleSubprocessOutput(args: {
	role: CompletionRole;
	assistantText?: string;
	eventLines?: string[];
	fallbackOutput: string;
	/** When false, missing structured emit output fails closed (Pi subprocess path). */
	allowTextFallback?: boolean;
}): ResolvedRoleSubprocessOutput {
	const contractId = contractIdForCompletionRole(args.role);
	if (!contractId) {
		const output = args.assistantText || args.fallbackOutput;
		return { output, reportFields: roleReporting.parseReportFields(output) };
	}

	try {
		const { payload } = requireSubprocessFinalOutput<StructuredEvaluatorReport | StructuredRoleHandoffReport>({
			eventLines: args.eventLines,
			contractId,
			assistantText: args.assistantText,
		});

		if ("rubric" in payload && Array.isArray(payload.rubric)) {
			const structured = payload as StructuredEvaluatorReport;
			const output = renderEvaluatorReport(structured);
			return {
				output,
				reportFields: roleReporting.parseReportFields(output),
				structuredEvaluatorReport: structured,
			};
		}

		const structured = payload as StructuredRoleHandoffReport;
		const output = renderRoleHandoffReport(structured);
		return {
			output,
			reportFields: roleReporting.parseReportFields(output),
			structuredRoleHandoffReport: structured,
		};
	} catch (error) {
		if (!(error instanceof StructuredSubprocessOutputError)) throw error;
		if (!args.allowTextFallback) throw error;
		const output = args.assistantText || args.fallbackOutput;
		return { output, reportFields: roleReporting.parseReportFields(output) };
	}
}
