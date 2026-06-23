import { spawn } from "node:child_process";
import * as fs from "node:fs";
import { promises as fsp } from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import { DynamicBorder, parseFrontmatter } from "@mariozechner/pi-coding-agent";
import { Container, Text } from "@mariozechner/pi-tui";
import {
	type ContextProposal,
	type RecentDiscussionEntry,
} from "./proposal";
import {
	buildStartupAnalysisPromptFromEntries,
	parseStartupAnalysisOutput,
} from "./startup-analysis";
import { contextProposalAnalystProgressLines, primaryAgentHandoffProgressLines } from "./prompt-surfaces";
import {
	buildCompletionRoleSubprocessEnv,
	effectiveRoleToolAllowlist,
	resolveEffectiveCompletionRoleModel,
} from "./helper-policy.ts";
import {
	applyLiveRoleEvent,
	buildInlineRunningLines,
	cloneLiveRoleActivity,
	createLiveRoleActivity,
	formatInlineRunningText,
	nowMs,
	pushRecentActivity,
	refreshCompletionStatus,
	type RoleMessage,
} from "./status-surface";
import { completionRootKey, findCompletionRoot, findRepoRoot } from "./state-store";
import { buildRoleReportRepairPrompt, parseReportFields, transcribeRoleOutput, type TranscriptionResult } from "./transcription";
import type { AgentDefinition, CompletionRole, JsonRecord, LiveRoleActivity } from "./types";

export type RunCompletionRoleParams = {
	root: string;
	role: CompletionRole;
	task?: string;
	signal?: AbortSignal;
	requestedModel?: string;
	systemPromptPreamble: string[];
	evaluationContextLines?: string[];
	onUpdate?: (activity: LiveRoleActivity) => void;
	onConsoleMessage?: (level: "info" | "warning", text: string) => void;
	createLiveRoleActivity: (role: string) => LiveRoleActivity;
	cloneLiveRoleActivity: (activity: LiveRoleActivity, overrides?: Partial<LiveRoleActivity>) => LiveRoleActivity;
	applyLiveRoleEvent: (activity: LiveRoleActivity, event: JsonRecord, messages: Array<{ role: string; content: Array<{ type: string; text?: string }> }>) => boolean;
	nowMs: () => number;
	heartbeatMs: number;
};

export type RunCompletionRoleResult = {
	role: CompletionRole;
	ok: boolean;
	exitCode: number;
	output: string;
	stderr?: string;
	reportFields: Record<string, string>;
	transcription?: TranscriptionResult;
	activity: LiveRoleActivity;
};

export type AnalyzeContextProposalWithAgentParams = {
	ctx: { cwd: string; hasUI: boolean; ui: any; model?: any };
	projectName: string;
	recentEntries: RecentDiscussionEntry[];
	workflowContextLines?: string[];
	liveRoleActivityByRoot: Map<string, LiveRoleActivity>;
	completionStatusKey: string;
	safeUiCall: (action: () => void) => void;
	getCtxCwd: (ctx: { cwd: string }) => string;
	getCtxHasUI: (ctx: { hasUI: boolean }) => boolean;
	getCtxUi: <T extends { ui: any }>(ctx: T) => any | undefined;
};

export type GenerateCookHandoffWithAgentParams = AnalyzeContextProposalWithAgentParams;

const AGENT_HOME = path.join(os.homedir(), ".pi", "agent");
const EXTENSION_DIR = typeof __dirname === "string" ? __dirname : process.cwd();
const PACKAGE_ROOT_CANDIDATE = path.resolve(EXTENSION_DIR, "..", "..");
const PACKAGE_ROOT = fs.existsSync(path.join(PACKAGE_ROOT_CANDIDATE, "package.json")) ? PACKAGE_ROOT_CANDIDATE : undefined;
const PACKAGE_AGENTS_DIR = PACKAGE_ROOT ? path.join(PACKAGE_ROOT, "agents") : undefined;
const CONTEXT_PROPOSAL_ANALYST_SYSTEM_PROMPT = [
	"You analyze recent /cook startup discussion and return a strict JSON object.",
	"Do not emit markdown, code fences, or commentary.",
	"Return exactly one JSON object with keys: verdict, workflow_relation, confidence, mission, scope, constraints, acceptance, diagnostics, critique, risks, possible_noise.",
	"You may additionally include optional keys alternate_missions, completed_topics, and negated_topics when they are clearly supported by the discussion and canonical workflow context.",
	"Use verdict values: startable, needs_clarification, planning_only, not_repo_change, or unsafe.",
	"Use workflow_relation values: new_workflow, continue_current_workflow, replace_current_workflow, or unclear.",
	"Use confidence values: high, medium, or low.",
	"mission must be a concise implementation mission anchor sentence when verdict is startable; do not invent a generic mission when the discussion is weak or ambiguous.",
	"Prefer the latest clear user implementation intent over older background context when they differ.",
	"Treat /cook itself as the workflow-entry signal; do not require English implementation-intent keywords before analyzing recent discussion.",
	"Use recent user/custom discussion plus canonical workflow context only; do not infer startup intent from slash-command arguments or let planning-only artifacts bypass approval-only confirmation.",
	"Do not reopen work that the canonical workflow context says is done, completed, historical, or already covered unless the latest discussion clearly asks to revisit it.",
	"Treat stale, weakly related, or explicitly negated topics as noise instead of mission scope.",
	"scope must contain only work items that directly support the mission when verdict is startable.",
	"constraints must contain guardrails or non-goals explicitly stated or strongly implied by the discussion when verdict is startable.",
	"acceptance must contain verifiable outcomes explicitly stated or strongly implied by the discussion when verdict is startable.",
	"diagnostics must explain why the verdict, workflow_relation, and confidence were chosen.",
	"critique must contain operator-facing cautions, concerns, or reminders that should be shown separately from mission and scope later.",
	"risks must contain concrete failure modes or regressions that the later workflow should keep in view.",
	"Do not include task_type or evaluation_profile in startup-analysis output from free-text discussion. Only explicit structured startup artifacts may supply those routing fields elsewhere in /cook.",
	"possible_noise should list discussion points that look stale, weakly related, unsafe to promote into scope, or already completed elsewhere.",
	"When discussion is insufficient, contradictory, planning-only, or low-confidence, prefer a non-startable verdict with diagnostics over invention.",
].join(" ");
const STARTUP_ANALYST_ROLE = "cook-proposal-analyst";
const ANALYST_HEARTBEAT_MS = 5_000;

const PRIMARY_AGENT_HANDOFF_SYSTEM_PROMPT = [
	"You are the primary agent preparing an explicit /cook handoff after the user already chose workflow mode.",
	"Return either exactly one fenced ```cook_handoff JSON block or one brief plain sentence explaining why no workflow startup handoff can be prepared.",
	"If you can prepare a handoff, the JSON must use kind cook_handoff, source primary_agent, and handoff_kind implementation_workflow_handoff.",
	"Capture the best mission-level startup brief you can from recent discussion and canonical workflow context so /cook can move directly into Start/Cancel confirmation.",
	"If canonical workflow context includes inline /cook startup intent, treat that inline prompt as the highest-priority explicit mission signal for this generation step.",
	"When the user has clearly accepted a concrete assistant-proposed slice, carry that slice forward into the handoff instead of broadening or re-guessing the mission.",
	"Do not make /cook infer or rediscover the mission from recent discussion later; author the handoff now from the primary-agent view of the task.",
	"When recent discussion is meta-discussion about how to implement a change, recover the underlying repo-change mission instead of echoing planning-only wording.",
	"Do not emit markdown commentary before or after the capsule.",
	"A valid workflow-startable handoff must include mission, scope, constraints or non_goals, acceptance, risks, and notes.",
	"first_slice_goal, first_slice_non_goals, implementation_surfaces, verification_commands, and why_this_slice_first are optional startup hints. Include them when they are clearly supported, but do not refuse the handoff solely because the first slice is still under-specified.",
	"If the first slice is not concrete enough yet, leave the slice-hint fields empty instead of refusing the startup handoff.",
].join(" ");
const PRIMARY_AGENT_HANDOFF_ROLE = "cook-primary-agent-handoff";

type CookStartupOverlayOptions = {
	title: string;
	footer: string;
};

class CookStartupOverlay extends Container {
	private readonly border: DynamicBorder;
	private readonly title: Text;
	private readonly body: Text;
	private readonly footer: Text;
	private lines: string[] = [];
	onAbort?: () => void;

	constructor(
		private readonly theme: any,
		private readonly options: CookStartupOverlayOptions,
	) {
		super();
		this.border = new DynamicBorder((s: string) => this.theme.fg("accent", s));
		this.title = new Text("", 1, 0);
		this.body = new Text("", 1, 1);
		this.footer = new Text("", 1, 0);
		this.addChild(this.border);
		this.addChild(this.title);
		this.addChild(this.body);
		this.addChild(this.footer);
		this.updateDisplay();
	}

	setLines(lines: string[]): void {
		this.lines = [...lines];
		this.updateDisplay();
		this.invalidate();
	}

	private updateDisplay(): void {
		this.title.setText(this.theme.fg("accent", this.theme.bold(this.options.title)));
		this.body.setText(formatInlineRunningText(this.theme, this.lines, { primaryAssistant: true }));
		this.footer.setText(this.theme.fg("muted", this.options.footer));
	}

	override handleInput(data: string): void {
		if (data === "\u001b" || data === "\u0003") {
			this.onAbort?.();
			return;
		}
	}

	override invalidate(): void {
		super.invalidate();
		this.updateDisplay();
	}
}

function asString(value: unknown): string | undefined {
	return typeof value === "string" && value.trim().length > 0 ? value.trim() : undefined;
}

function isRecord(value: unknown): value is JsonRecord {
	return typeof value === "object" && value !== null && !Array.isArray(value);
}

function walkUpForDir(startCwd: string, segments: string[]): string | undefined {
	let current = path.resolve(startCwd);
	while (true) {
		const candidate = path.join(current, ...segments);
		if (fs.existsSync(candidate)) return candidate;
		const parent = path.dirname(current);
		if (parent === current) return undefined;
		current = parent;
	}
}

function contextProposalAnalystModelArg(model: unknown): string | undefined {
	if (!isRecord(model)) return undefined;
	const provider = asString(model.provider);
	const id = asString(model.id);
	return provider && id ? `${provider}/${id}` : undefined;
}

async function runContextProposalAnalystSubprocess(params: AnalyzeContextProposalWithAgentParams): Promise<string | undefined> {
	const { ctx, projectName, recentEntries } = params;
	const modelArg = contextProposalAnalystModelArg(ctx.model);
	if (!modelArg) return undefined;
	const cwd = params.getCtxCwd(ctx);
	const runCwd = findCompletionRoot(cwd) ?? findRepoRoot(cwd) ?? cwd;
	const rootKey = completionRootKey(undefined, cwd);
	const prompt = buildStartupAnalysisPromptFromEntries(projectName, recentEntries, params.workflowContextLines);
	const systemPromptTemp = await writeTempFile(runCwd, "pi-cook-proposal-analyst-", CONTEXT_PROPOSAL_ANALYST_SYSTEM_PROMPT);
	const args: string[] = ["--mode", "json", "-p", "--no-session", "--no-extensions", "--append-system-prompt", systemPromptTemp.filePath];
	const inheritedHeadroomExtensionArgs = getInheritedHeadroomWrapPiExtensionArgs();
	if (inheritedHeadroomExtensionArgs.length > 0) args.push(...inheritedHeadroomExtensionArgs);
	args.push("--model", modelArg, prompt);
	const invocation = getPiInvocation(args);
	const liveActivity = createLiveRoleActivity(STARTUP_ANALYST_ROLE);
	liveActivity.toolActivity = undefined;
	liveActivity.toolRecentActivity = [];
	liveActivity.recentActivity = [];
	liveActivity.progress = "Analyzing recent discussion";
	liveActivity.currentAction = "Reading recent discussion and preparing a startup proposal";
	liveActivity.assistantSummary = liveActivity.progress;
	liveActivity.recentActivity = pushRecentActivity(liveActivity.recentActivity, `assistant: ${liveActivity.progress}`);
	const messages: RoleMessage[] = [];
	let overlay: CookStartupOverlay | undefined;
	let finishOverlay: ((value: string | undefined) => void) | undefined;
	let overlaySettled = false;
	const settleOverlay = (value: string | undefined) => {
		if (overlaySettled) return;
		overlaySettled = true;
		finishOverlay?.(value);
	};
	const updateActivity = (fresh = false) => {
		if (fresh) liveActivity.updatedAt = nowMs();
		params.liveRoleActivityByRoot.set(rootKey, cloneLiveRoleActivity(liveActivity, { status: "running" }));
		void refreshCompletionStatus({
			ctx,
			liveRoleActivityByRoot: params.liveRoleActivityByRoot,
			completionStatusKey: params.completionStatusKey,
			safeUiCall: params.safeUiCall,
			getCtxCwd: params.getCtxCwd,
			getCtxHasUI: params.getCtxHasUI,
			getCtxUi: params.getCtxUi,
		});
		overlay?.setLines(contextProposalAnalystProgressLines(liveActivity, buildInlineRunningLines));
	};
	const heartbeat = setInterval(() => updateActivity(false), ANALYST_HEARTBEAT_MS);
	const run = async (): Promise<string | undefined> => {
		try {
			updateActivity(true);
			const output = await new Promise<string | undefined>((resolve) => {
				const proc = spawn(invocation.command, invocation.args, {
					cwd: runCwd,
					env: process.env,
					stdio: ["ignore", "pipe", "pipe"],
					shell: false,
				});
				let settled = false;
				const resolveOnce = (value: string | undefined) => {
					if (settled) return;
					settled = true;
					resolve(value);
				};
				const abort = () => {
					proc.kill("SIGTERM");
					resolveOnce(undefined);
				};
				const handleSigint = () => abort();
				let buffer = "";
				const processLine = (line: string) => {
					if (!line.trim()) return;
					try {
						const event = JSON.parse(line) as JsonRecord;
						if (applyLiveRoleEvent(liveActivity, event, messages)) updateActivity(true);
					} catch {
						// ignore malformed lines
					}
				};
				proc.stdout.on("data", (chunk) => {
					buffer += chunk.toString();
					const lines = buffer.split("\n");
					buffer = lines.pop() ?? "";
					for (const line of lines) processLine(line);
				});
				proc.stderr.on("data", (_chunk) => {
					// ignore analyst stderr unless the subprocess exits without assistant output
				});
				proc.on("close", (code) => {
					process.off("SIGINT", handleSigint);
					if (buffer.trim()) processLine(buffer);
					resolveOnce(code === 0 ? liveActivity.lastAssistantText?.trim() || undefined : undefined);
				});
				proc.on("error", () => {
					process.off("SIGINT", handleSigint);
					resolveOnce(undefined);
				});
				process.once("SIGINT", handleSigint);
				if (overlay) {
					overlay.onAbort = () => {
						process.off("SIGINT", handleSigint);
						abort();
					};
				}
			});
			params.liveRoleActivityByRoot.set(rootKey, cloneLiveRoleActivity(liveActivity, { status: output ? "ok" : "error" }));
			await refreshCompletionStatus({
				ctx,
				liveRoleActivityByRoot: params.liveRoleActivityByRoot,
				completionStatusKey: params.completionStatusKey,
				safeUiCall: params.safeUiCall,
				getCtxCwd: params.getCtxCwd,
				getCtxHasUI: params.getCtxHasUI,
				getCtxUi: params.getCtxUi,
			});
			return output;
		} finally {
			clearInterval(heartbeat);
			setTimeout(() => {
				const current = params.liveRoleActivityByRoot.get(rootKey);
				if (current && current.role === STARTUP_ANALYST_ROLE && current.status !== "running") {
					params.liveRoleActivityByRoot.delete(rootKey);
					void refreshCompletionStatus({
						ctx,
						liveRoleActivityByRoot: params.liveRoleActivityByRoot,
						completionStatusKey: params.completionStatusKey,
						safeUiCall: params.safeUiCall,
						getCtxCwd: params.getCtxCwd,
						getCtxHasUI: params.getCtxHasUI,
						getCtxUi: params.getCtxUi,
					});
				}
			}, 10_000);
			await fsp.rm(systemPromptTemp.dir, { recursive: true, force: true });
		}
	};
	if (params.getCtxHasUI(ctx)) {
		const ui = params.getCtxUi(ctx);
		if (ui) {
			return await ui.custom<string | undefined>((_tui, theme, _kb, done) => {
				finishOverlay = done;
				overlay = new CookStartupOverlay(theme, {
					title: "/cook proposal analyst",
					footer: "Esc/Ctrl+C cancel • This analysis runs before /cook writes canonical workflow state",
				});
				overlay.setLines(contextProposalAnalystProgressLines(liveActivity, buildInlineRunningLines));
				run().then(settleOverlay).catch(() => settleOverlay(undefined));
				return overlay;
			});
		}
	}
	return await run();
}

function serializeRecentConversationEntries(entries: RecentDiscussionEntry[]): string {
	return entries
		.slice()
		.reverse()
		.map((entry, index) => `[${index + 1}] ${entry.role.toUpperCase()}\n${entry.text}`)
		.join("\n\n");
}

function buildPrimaryAgentHandoffPrompt(projectName: string, recentEntries: RecentDiscussionEntry[], workflowContextLines: string[] = []): string {
	const lines = [
		`Project: ${projectName}`,
		"",
		"Recent session transcript:",
		serializeRecentConversationEntries(recentEntries),
	];
	if (workflowContextLines.length > 0) lines.push("", "Canonical workflow context:", ...workflowContextLines);
	lines.push(
		"",
		"Task:",
		"The user explicitly invoked /cook. Prepare the primary-agent handoff that /cook should consume immediately for Start/Cancel confirmation.",
	);
	return lines.join("\n");
}

async function runPrimaryAgentHandoffSubprocess(params: GenerateCookHandoffWithAgentParams): Promise<string | undefined> {
	const { ctx, projectName, recentEntries } = params;
	const modelArg = contextProposalAnalystModelArg(ctx.model);
	if (!modelArg) return undefined;
	const cwd = params.getCtxCwd(ctx);
	const runCwd = findCompletionRoot(cwd) ?? findRepoRoot(cwd) ?? cwd;
	const rootKey = completionRootKey(undefined, cwd);
	const prompt = buildPrimaryAgentHandoffPrompt(projectName, recentEntries, params.workflowContextLines ?? []);
	const systemPromptTemp = await writeTempFile(runCwd, "pi-cook-primary-agent-handoff-", PRIMARY_AGENT_HANDOFF_SYSTEM_PROMPT);
	const args: string[] = ["--mode", "json", "-p", "--no-session", "--no-extensions", "--append-system-prompt", systemPromptTemp.filePath];
	const inheritedHeadroomExtensionArgs = getInheritedHeadroomWrapPiExtensionArgs();
	if (inheritedHeadroomExtensionArgs.length > 0) args.push(...inheritedHeadroomExtensionArgs);
	args.push("--model", modelArg, prompt);
	const invocation = getPiInvocation(args);
	const liveActivity = createLiveRoleActivity(PRIMARY_AGENT_HANDOFF_ROLE);
	liveActivity.toolActivity = undefined;
	liveActivity.toolRecentActivity = [];
	liveActivity.recentActivity = [];
	liveActivity.currentAction = "Reading current task context";
	liveActivity.rationale = "Loading canonical workflow context";
	liveActivity.nextStep = "Synthesizing startup plan";
	liveActivity.verifying = "Waiting for model response...";
	let overlay: CookStartupOverlay | undefined;
	let finishOverlay: ((value: string | undefined) => void) | undefined;
	let overlaySettled = false;
	const settleOverlay = (value: string | undefined) => {
		if (overlaySettled) return;
		overlaySettled = true;
		finishOverlay?.(value);
	};
	const updateActivity = (fresh = false) => {
		if (fresh) liveActivity.updatedAt = nowMs();
		params.liveRoleActivityByRoot.set(rootKey, cloneLiveRoleActivity(liveActivity, { status: "running" }));
		void refreshCompletionStatus({
			ctx,
			liveRoleActivityByRoot: params.liveRoleActivityByRoot,
			completionStatusKey: params.completionStatusKey,
			safeUiCall: params.safeUiCall,
			getCtxCwd: params.getCtxCwd,
			getCtxHasUI: params.getCtxHasUI,
			getCtxUi: params.getCtxUi,
		});
		overlay?.setLines(primaryAgentHandoffProgressLines(liveActivity, buildInlineRunningLines));
	};
	const heartbeat = setInterval(() => updateActivity(false), ANALYST_HEARTBEAT_MS);
	const run = async (): Promise<string | undefined> => {
		try {
			updateActivity(true);
			const output = await new Promise<string | undefined>((resolve) => {
				const proc = spawn(invocation.command, invocation.args, {
					cwd: runCwd,
					env: process.env,
					stdio: ["ignore", "pipe", "pipe"],
					shell: false,
				});
				let settled = false;
				const resolveOnce = (value: string | undefined) => {
					if (settled) return;
					settled = true;
					resolve(value);
				};
				const abort = () => {
					proc.kill("SIGTERM");
					resolveOnce(undefined);
				};
				const handleSigint = () => abort();
				let buffer = "";
				const messages: RoleMessage[] = [];
				const processLine = (line: string) => {
					if (!line.trim()) return;
					try {
						const event = JSON.parse(line) as JsonRecord;
						if (applyLiveRoleEvent(liveActivity, event, messages)) updateActivity(true);
					} catch {
						// ignore malformed lines
					}
				};
				proc.stdout.on("data", (chunk) => {
					buffer += chunk.toString();
					const lines = buffer.split("\n");
					buffer = lines.pop() ?? "";
					for (const line of lines) processLine(line);
				});
				proc.stderr.on("data", (_chunk) => {
					// ignore handoff stderr unless the subprocess exits without assistant output
				});
				proc.on("close", (code) => {
					process.off("SIGINT", handleSigint);
					if (buffer.trim()) processLine(buffer);
					resolveOnce(code === 0 ? liveActivity.lastAssistantText?.trim() || undefined : undefined);
				});
				proc.on("error", () => {
					process.off("SIGINT", handleSigint);
					resolveOnce(undefined);
				});
				process.once("SIGINT", handleSigint);
				if (overlay) {
					overlay.onAbort = () => {
						process.off("SIGINT", handleSigint);
						abort();
					};
				}
			});
			params.liveRoleActivityByRoot.set(rootKey, cloneLiveRoleActivity(liveActivity, { status: output ? "ok" : "error" }));
			await refreshCompletionStatus({
				ctx,
				liveRoleActivityByRoot: params.liveRoleActivityByRoot,
				completionStatusKey: params.completionStatusKey,
				safeUiCall: params.safeUiCall,
				getCtxCwd: params.getCtxCwd,
				getCtxHasUI: params.getCtxHasUI,
				getCtxUi: params.getCtxUi,
			});
			return output;
		} finally {
			clearInterval(heartbeat);
			setTimeout(() => {
				const current = params.liveRoleActivityByRoot.get(rootKey);
				if (current && current.role === PRIMARY_AGENT_HANDOFF_ROLE && current.status !== "running") {
					params.liveRoleActivityByRoot.delete(rootKey);
					void refreshCompletionStatus({
						ctx,
						liveRoleActivityByRoot: params.liveRoleActivityByRoot,
						completionStatusKey: params.completionStatusKey,
						safeUiCall: params.safeUiCall,
						getCtxCwd: params.getCtxCwd,
						getCtxHasUI: params.getCtxHasUI,
						getCtxUi: params.getCtxUi,
					});
				}
			}, 10_000);
			await fsp.rm(systemPromptTemp.dir, { recursive: true, force: true });
		}
	};
	if (params.getCtxHasUI(ctx)) {
		const ui = params.getCtxUi(ctx);
		if (ui) {
			return await ui.custom<string | undefined>((_tui, theme, _kb, done) => {
				finishOverlay = done;
				overlay = new CookStartupOverlay(theme, {
					title: "/cook startup plan",
					footer: "Esc/Ctrl+C cancel • This startup-plan synthesis runs before /cook writes canonical workflow state",
				});
				overlay.setLines(primaryAgentHandoffProgressLines(liveActivity, buildInlineRunningLines));
				run().then(settleOverlay).catch(() => settleOverlay(undefined));
				return overlay;
			});
		}
	}
	return await run();
}

export async function generateCookHandoffWithAgent(params: GenerateCookHandoffWithAgentParams): Promise<string | undefined> {
	if (process.env.PI_COMPLETION_DISABLE_PRIMARY_HANDOFF_SYNTHESIS === "1") return undefined;
	const testOutput = asString(process.env.PI_COMPLETION_PRIMARY_HANDOFF_OUTPUT);
	if (testOutput) return testOutput;
	if (params.recentEntries.length === 0) return undefined;
	try {
		return await runPrimaryAgentHandoffSubprocess(params);
	} catch (error) {
		console.warn("[completion] primary-agent handoff generation failed", error);
		return undefined;
	}
}

export async function analyzeContextProposalWithAgent(params: AnalyzeContextProposalWithAgentParams): Promise<ContextProposal | undefined> {
	if (process.env.PI_COMPLETION_DISABLE_CONTEXT_PROPOSAL_ANALYST === "1") return undefined;
	const testOutput = asString(process.env.PI_COMPLETION_CONTEXT_PROPOSAL_ANALYST_OUTPUT);
	if (testOutput) return parseStartupAnalysisOutput(testOutput, params.projectName);
	if (params.recentEntries.length === 0) return undefined;
	try {
		const raw = await runContextProposalAnalystSubprocess(params);
		if (!raw) return undefined;
		return parseStartupAnalysisOutput(raw, params.projectName);
	} catch (error) {
		console.warn("[completion] context proposal analyst failed", error);
		return undefined;
	}
}


export async function loadAgentDefinition(cwd: string, role: CompletionRole): Promise<AgentDefinition> {
	const projectAgent = walkUpForDir(cwd, [".pi", "agents", `${role}.md`]);
	const packageAgent = PACKAGE_AGENTS_DIR ? path.join(PACKAGE_AGENTS_DIR, `${role}.md`) : undefined;
	const candidates = [projectAgent, packageAgent, path.join(AGENT_HOME, "agents", `${role}.md`)].filter(
		(candidate): candidate is string => Boolean(candidate),
	);
	for (const candidate of candidates) {
		if (!fs.existsSync(candidate)) continue;
		const raw = await fsp.readFile(candidate, "utf8");
		const { frontmatter, body } = parseFrontmatter<Record<string, string>>(raw);
		return {
			name: frontmatter.name ?? role,
			description: frontmatter.description,
			tools: frontmatter.tools?.split(",").map((tool) => tool.trim()).filter(Boolean),
			model: frontmatter.model,
			systemPrompt: body.trim(),
			filePath: candidate,
		};
	}
	throw new Error(`Missing completion agent definition for ${role}`);
}

export async function writeTempFile(root: string, prefix: string, content: string): Promise<{ dir: string; filePath: string }> {
	const canonicalCurrentDir = path.join(root, ".agent", "current");
	const canonicalTmpRoot = path.join(canonicalCurrentDir, "tmp");
	const scopedOsTmpRoot = path.join(os.tmpdir(), "pi-completion", path.basename(root) || "repo");
	try {
		if (!fs.existsSync(canonicalCurrentDir)) throw new Error("canonical completion runtime is not initialized yet");
		await fsp.mkdir(canonicalTmpRoot, { recursive: true });
		const dir = await fsp.mkdtemp(path.join(canonicalTmpRoot, prefix));
		const filePath = path.join(dir, "prompt.md");
		await fsp.writeFile(filePath, content, { encoding: "utf8", mode: 0o600 });
		return { dir, filePath };
	} catch {
		await fsp.mkdir(scopedOsTmpRoot, { recursive: true });
		const dir = await fsp.mkdtemp(path.join(scopedOsTmpRoot, prefix));
		const filePath = path.join(dir, "prompt.md");
		await fsp.writeFile(filePath, content, { encoding: "utf8", mode: 0o600 });
		return { dir, filePath };
	}
}

export function getPiInvocation(args: string[]): { command: string; args: string[] } {
	const currentScript = process.argv[1];
	const isBunVirtualScript = currentScript?.startsWith("/$bunfs/root/");
	if (currentScript && !isBunVirtualScript && fs.existsSync(currentScript)) {
		return { command: process.execPath, args: [currentScript, ...args] };
	}
	const execName = path.basename(process.execPath).toLowerCase();
	const isGenericRuntime = /^(node|bun)(\.exe)?$/.test(execName);
	if (!isGenericRuntime) return { command: process.execPath, args };
	return { command: "pi", args };
}

function getInheritedHeadroomWrapPiExtensionArgs(): string[] {
	const explicitExtensionPath = process.env.HEADROOM_PI_EXTENSION_PATH?.trim();
	if (explicitExtensionPath && fs.existsSync(explicitExtensionPath)) {
		return ["--extension", explicitExtensionPath];
	}

	const sessionConfigPath = process.env.HEADROOM_PI_SESSION_CONFIG?.trim();
	if (!sessionConfigPath) return [];

	const extensionPath = path.join(path.dirname(sessionConfigPath), "extension.ts");
	if (!fs.existsSync(extensionPath)) return [];

	return ["--extension", extensionPath];
}

export async function runCompletionRole(params: RunCompletionRoleParams): Promise<RunCompletionRoleResult> {
	const agent = await loadAgentDefinition(params.root, params.role);
	const roleModel = resolveEffectiveCompletionRoleModel(agent.model, params.requestedModel);
	const effectiveToolAllowlist = effectiveRoleToolAllowlist(params.role, agent.tools);
	const roleEnv = buildCompletionRoleSubprocessEnv(params.role, roleModel);
	const systemPromptTemp = await writeTempFile(params.root, "pi-completion-role-", agent.systemPrompt);
	const baseTaskLines = [...params.systemPromptPreamble];
	if (params.evaluationContextLines?.length) baseTaskLines.push("", ...params.evaluationContextLines);
	if (params.task?.trim()) baseTaskLines.push("", "Supplemental task context:", params.task.trim());

	const runAttempt = async (repairPrompt?: string, previousOutput?: string): Promise<RunCompletionRoleResult> => {
		const taskLines = [...baseTaskLines];
		if (repairPrompt) {
			taskLines.push(
				"",
				"Structured report repair mode:",
				"Canonical transcription rejected the previous structured report for a repairable consistency error.",
				"Previous report:",
				"```text",
				(previousOutput ?? "").trim(),
				"```",
				repairPrompt,
			);
		}
		const prompt = taskLines.join("\n");
		const args: string[] = ["--mode", "json", "-p", "--no-session", "--append-system-prompt", systemPromptTemp.filePath];
		const inheritedHeadroomExtensionArgs = getInheritedHeadroomWrapPiExtensionArgs();
		if (inheritedHeadroomExtensionArgs.length > 0) args.push(...inheritedHeadroomExtensionArgs);
		if (roleModel) args.push("--model", roleModel);
		if (effectiveToolAllowlist && effectiveToolAllowlist.length > 0) args.push("--tools", effectiveToolAllowlist.join(","));
		args.push(prompt);

		const invocation = getPiInvocation(args);
		let stderr = "";
		const messages: Array<{ role: string; content: Array<{ type: string; text?: string }> }> = [];
		const liveActivity = params.createLiveRoleActivity(params.role);
		params.onUpdate?.(liveActivity);
		const heartbeat = setInterval(() => params.onUpdate?.(liveActivity), params.heartbeatMs);

		try {
			const exitCode = await new Promise<number>((resolve) => {
				const proc = spawn(invocation.command, invocation.args, {
					cwd: params.root,
					env: roleEnv,
					stdio: ["ignore", "pipe", "pipe"],
					shell: false,
				});
				let buffer = "";

				const processLine = (line: string) => {
					if (!line.trim()) return;
					try {
						const event = JSON.parse(line) as JsonRecord;
						if (params.applyLiveRoleEvent(liveActivity, event, messages)) params.onUpdate?.(liveActivity);
					} catch {
						// ignore malformed lines
					}
				};

				proc.stdout.on("data", (chunk) => {
					buffer += chunk.toString();
					const lines = buffer.split("\n");
					buffer = lines.pop() ?? "";
					for (const line of lines) processLine(line);
				});

				proc.stderr.on("data", (chunk) => {
					stderr += chunk.toString();
				});

				proc.on("close", (code) => {
					if (buffer.trim()) processLine(buffer);
					resolve(code ?? 0);
				});

				proc.on("error", () => resolve(1));

				if (params.signal) {
					const abort = () => proc.kill("SIGTERM");
					if (params.signal.aborted) abort();
					else params.signal.addEventListener("abort", abort, { once: true });
				}
			});

			const output = liveActivity.lastAssistantText || stderr.trim() || `${params.role} finished with no text output.`;
			const reportFields = parseReportFields(output);
			const transcription = exitCode === 0 ? await transcribeRoleOutput(params.role, params.root, output, reportFields) : undefined;
			return {
				role: params.role,
				ok: exitCode === 0,
				exitCode,
				output,
				stderr: stderr.trim(),
				reportFields,
				transcription,
				activity: params.cloneLiveRoleActivity(liveActivity, { status: exitCode === 0 ? "ok" : "error" }),
			};
		} finally {
			clearInterval(heartbeat);
		}
	};

	try {
		let result = await runAttempt();
		const repairPrompt = result.ok && result.transcription?.errors.length
			? buildRoleReportRepairPrompt(params.role, result.transcription.errors)
			: undefined;
		if (repairPrompt) {
			params.onConsoleMessage?.("info", `Retrying ${params.role} once to repair structured report consistency.`);
			result = await runAttempt(repairPrompt, result.output);
		}
		if (result.transcription?.appended.length) params.onConsoleMessage?.("info", `Completion transcription appended: ${result.transcription.appended.join(", ")}`);
		if (result.transcription?.errors.length) params.onConsoleMessage?.("warning", `Completion transcription warning: ${result.transcription.errors.join(" | ")}`);
		return result;
	} finally {
		await fsp.rm(systemPromptTemp.dir, { recursive: true, force: true });
	}
}
