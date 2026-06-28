import * as fs from "node:fs";
import * as path from "node:path";
import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";
import { Type } from "typebox";
import {
	COMPLETION_COOK_HANDOFF_CONTRACT_ID,
	COMPLETION_EVALUATOR_AUDITOR_CONTRACT_ID,
	COMPLETION_EVALUATOR_REVIEWER_CONTRACT_ID,
	COMPLETION_EVALUATOR_STOP_JUDGE_CONTRACT_ID,
	COMPLETION_ROLE_BOOTSTRAPPER_CONTRACT_ID,
	COMPLETION_ROLE_IMPLEMENTER_CONTRACT_ID,
	COMPLETION_ROLE_REGROUNDER_CONTRACT_ID,
	COMPLETION_STARTUP_ANALYSIS_CONTRACT_ID,
	EMIT_AUDITOR_REPORT_TOOL,
	EMIT_BOOTSTRAPPER_HANDOFF_TOOL,
	EMIT_COOK_HANDOFF_TOOL,
	EMIT_IMPLEMENTER_HANDOFF_TOOL,
	EMIT_REGROUNDER_RECONCILIATION_TOOL,
	EMIT_REVIEWER_REPORT_TOOL,
	EMIT_STARTUP_ANALYSIS_TOOL,
	EMIT_STOP_JUDGE_REPORT_TOOL,
} from "../completion/structured-contracts.ts";

function resolvePackageRoot(): string {
	const candidates = [
		typeof __dirname === "string" ? path.resolve(__dirname, "..", "..") : undefined,
		process.cwd(),
	].filter((candidate): candidate is string => Boolean(candidate));
	for (const candidate of candidates) {
		if (fs.existsSync(path.join(candidate, "package.json")) && fs.existsSync(path.join(candidate, "extensions", "completion"))) {
			return candidate;
		}
	}
	return candidates[0] ?? process.cwd();
}

export const COMPLETION_STRUCTURED_TOOLS_EXTENSION_DIR = path.join(resolvePackageRoot(), "extensions", "completion-structured-tools");

export function completionStructuredToolsExtensionPath(): string {
	return COMPLETION_STRUCTURED_TOOLS_EXTENSION_DIR;
}

const RubricLineSchema = Type.Object(
	{
		dimension: Type.String(),
		verdict: Type.Union([Type.Literal("pass"), Type.Literal("concern"), Type.Literal("fail")]),
		explanation: Type.String(),
	},
	{ additionalProperties: false },
);

const EvaluatorEmitSchema = Type.Object(
	{
		mission_anchor: Type.String(),
		remaining_contract_ids: Type.String(),
		rubric: Type.Array(RubricLineSchema),
		fields: Type.Record(Type.String(), Type.String()),
	},
	{ additionalProperties: false },
);

const RoleHandoffEmitSchema = Type.Object(
	{
		fields: Type.Record(Type.String(), Type.String()),
	},
	{ additionalProperties: false },
);

const StartupAnalysisEmitSchema = Type.Object(
	{
		record: Type.Record(Type.String(), Type.Unknown()),
	},
	{ additionalProperties: false },
);

const CookHandoffEmitSchema = Type.Object(
	{
		capsule: Type.Record(Type.String(), Type.Unknown()),
	},
	{ additionalProperties: false },
);

function buildEmitTool(args: {
	name: string;
	label: string;
	description: string;
	contractId: string;
	parameters: ReturnType<typeof Type.Object>;
	renderSummary: (params: Record<string, unknown>) => string;
}) {
	return {
		name: args.name,
		label: args.label,
		description: args.description,
		terminate: true,
		promptSnippet: `Emit structured ${args.label} as the terminating completion output.`,
		promptGuidelines: [
			`Call ${args.name} exactly once as your final action.`,
			"The tool result details are authoritative; do not continue after the emit tool returns.",
		],
		parameters: args.parameters,
		async execute(_toolCallId: string, params: Record<string, unknown>) {
			const payload = {
				contractId: args.contractId,
				schemaVersion: 1,
				...params,
			};
			return {
				content: [{ type: "text" as const, text: args.renderSummary(params) }],
				details: payload,
			};
		},
	};
}

export default function completionStructuredToolsExtension(pi: ExtensionAPI) {
	const tools = [
		buildEmitTool({
			name: EMIT_STARTUP_ANALYSIS_TOOL,
			label: "Startup Analysis",
			description: "Emit structured startup analysis for /cook entry.",
			contractId: COMPLETION_STARTUP_ANALYSIS_CONTRACT_ID,
			parameters: StartupAnalysisEmitSchema,
			renderSummary: () => "startup analysis emitted",
		}),
		buildEmitTool({
			name: EMIT_COOK_HANDOFF_TOOL,
			label: "Cook Handoff",
			description: "Emit structured cook_handoff capsule for /cook startup synthesis.",
			contractId: COMPLETION_COOK_HANDOFF_CONTRACT_ID,
			parameters: CookHandoffEmitSchema,
			renderSummary: (params) => {
				const capsule = params.capsule;
				if (typeof capsule === "object" && capsule !== null && "mission" in capsule && typeof capsule.mission === "string") {
					return `cook handoff: ${capsule.mission}`;
				}
				return "cook handoff emitted";
			},
		}),
		buildEmitTool({
			name: EMIT_REVIEWER_REPORT_TOOL,
			label: "Reviewer Report",
			description: "Emit structured completion-reviewer report.",
			contractId: COMPLETION_EVALUATOR_REVIEWER_CONTRACT_ID,
			parameters: EvaluatorEmitSchema,
			renderSummary: () => "reviewer report emitted",
		}),
		buildEmitTool({
			name: EMIT_AUDITOR_REPORT_TOOL,
			label: "Auditor Report",
			description: "Emit structured completion-auditor report.",
			contractId: COMPLETION_EVALUATOR_AUDITOR_CONTRACT_ID,
			parameters: EvaluatorEmitSchema,
			renderSummary: () => "auditor report emitted",
		}),
		buildEmitTool({
			name: EMIT_STOP_JUDGE_REPORT_TOOL,
			label: "Stop Judge Report",
			description: "Emit structured completion-stop-judge report.",
			contractId: COMPLETION_EVALUATOR_STOP_JUDGE_CONTRACT_ID,
			parameters: EvaluatorEmitSchema,
			renderSummary: () => "stop-judge report emitted",
		}),
		buildEmitTool({
			name: EMIT_BOOTSTRAPPER_HANDOFF_TOOL,
			label: "Bootstrapper Handoff",
			description: "Emit structured completion-bootstrapper handoff.",
			contractId: COMPLETION_ROLE_BOOTSTRAPPER_CONTRACT_ID,
			parameters: RoleHandoffEmitSchema,
			renderSummary: () => "bootstrapper handoff emitted",
		}),
		buildEmitTool({
			name: EMIT_REGROUNDER_RECONCILIATION_TOOL,
			label: "Regrounder Reconciliation",
			description: "Emit structured completion-regrounder reconciliation report.",
			contractId: COMPLETION_ROLE_REGROUNDER_CONTRACT_ID,
			parameters: RoleHandoffEmitSchema,
			renderSummary: () => "regrounder reconciliation emitted",
		}),
		buildEmitTool({
			name: EMIT_IMPLEMENTER_HANDOFF_TOOL,
			label: "Implementer Handoff",
			description: "Emit structured completion-implementer handoff.",
			contractId: COMPLETION_ROLE_IMPLEMENTER_CONTRACT_ID,
			parameters: RoleHandoffEmitSchema,
			renderSummary: () => "implementer handoff emitted",
		}),
	];

	for (const tool of tools) {
		pi.registerTool(tool as any);
	}
}
