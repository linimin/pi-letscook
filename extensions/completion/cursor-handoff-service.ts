import { createHash, randomUUID } from "node:crypto";
import { promises as fsp } from "node:fs";
import * as path from "node:path";
import {
	COMPLETION_COOK_HANDOFF_CONTRACT_ID,
	getStructuredContract,
} from "./structured-contracts.ts";
import { finalizeContextProposalAnalysis, type ContextProposal, type ContextProposalConfirmationLayout } from "./proposal.ts";
import { buildContextProposalConfirmationLayout } from "./prompt-surfaces.ts";
import type { CookProposalDeps } from "./startup-intent.ts";
import {
	cookHandoffBlockFromJsonText,
	DEFAULT_CURSOR_HANDOFF_PATH,
	isArchivedCursorHandoffPath,
	loadCursorHandoffProposal,
	resolveCursorHandoffPath,
} from "./cursor-handoff.ts";

export const COOK_HANDOFF_PENDING_SIDECAR_PATH = ".agent/tmp/cursor-handoff.pending.json";
export const COOK_HANDOFF_MAX_AGE_MS = 45 * 60 * 1000;
export const CURSOR_HANDOFF_CONFIRMED_ENV = "PI_COMPLETION_CURSOR_HANDOFF_CONFIRMED";

function asString(value: unknown): string | undefined {
	return typeof value === "string" && value.trim().length > 0 ? value.trim() : undefined;
}

function isRecord(value: unknown): value is Record<string, unknown> {
	return typeof value === "object" && value !== null && !Array.isArray(value);
}

function asStringArray(value: unknown): string[] {
	return Array.isArray(value)
		? value.filter((item): item is string => typeof item === "string" && item.trim().length > 0)
		: [];
}

function localAsBoolean(value: unknown): boolean | undefined {
	if (typeof value === "boolean") return value;
	if (typeof value !== "string") return undefined;
	const normalized = value.trim().toLowerCase();
	if (normalized === "true") return true;
	if (normalized === "false") return false;
	return undefined;
}

export type CookHandoffSidecar = {
	workspace_root: string;
	branch?: string;
	path: string;
	prepared_at: string;
	confirmation_id: string;
	handoff_sha256: string;
	status: "pending_review" | "confirmed" | "awaiting_terminal_launch" | "kickoff_started";
	source: string;
	mission_preview?: string;
	confirmed_at?: string;
	confirmed_by?: string;
	last_spawn_error?: string;
};

export type PendingCookHandoffState =
	| { state: "none" }
	| { state: "stale" | "archived_consumed" | "archived_quarantined" | "not_startable"; error: string; handoffPath?: string }
	| { state: "pending" | "confirmed" | "awaiting_launch" | "kickoff_started"; handoffPath: string; sidecar: CookHandoffSidecar; proposal?: ContextProposal; error?: string };

export type WorkspaceRootResolution = {
	workspaceRoot: string;
	source: "arg" | "sidecar" | "env" | "cwd";
};

export class CookHandoffServiceError extends Error {
	code: string;

	constructor(message: string, code: string) {
		super(message);
		this.name = "CookHandoffServiceError";
		this.code = code;
	}
}

export function resolveWorkspaceRoot(args: {
	workspaceRoot?: string;
	env?: NodeJS.ProcessEnv;
	sidecar?: Pick<CookHandoffSidecar, "workspace_root">;
	cwd?: string;
	requireExplicit?: boolean;
}): WorkspaceRootResolution {
	const env = args.env ?? process.env;
	const argRoot = asString(args.workspaceRoot);
	const sidecarRoot = asString(args.sidecar?.workspace_root);
	const envRoot = asString(env.WORKSPACE_ROOT);
	const cwdRoot = path.resolve(args.cwd ?? process.cwd());

	if (argRoot && sidecarRoot && path.resolve(argRoot) !== path.resolve(sidecarRoot)) {
		throw new CookHandoffServiceError(
			`workspace_root mismatch: request=${path.resolve(argRoot)} sidecar=${path.resolve(sidecarRoot)}`,
			"workspace_root_mismatch",
		);
	}
	if (argRoot) return { workspaceRoot: path.resolve(argRoot), source: "arg" };
	if (sidecarRoot) return { workspaceRoot: path.resolve(sidecarRoot), source: "sidecar" };
	if (envRoot) return { workspaceRoot: path.resolve(envRoot), source: "env" };
	if (args.requireExplicit) {
		throw new CookHandoffServiceError("workspace_root is required", "workspace_root_required");
	}
	return { workspaceRoot: cwdRoot, source: "cwd" };
}

function resolvePendingSidecarPath(root: string): string {
	return path.resolve(root, COOK_HANDOFF_PENDING_SIDECAR_PATH);
}

export function isTimestampFreshEnough(isoTimestamp: string | undefined, nowMs = Date.now()): boolean {
	if (!isoTimestamp) return false;
	const parsed = Date.parse(isoTimestamp);
	if (!Number.isFinite(parsed)) return false;
	return nowMs - parsed <= COOK_HANDOFF_MAX_AGE_MS;
}

export function computeHandoffContentHash(content: string): string {
	return createHash("sha256").update(content.trim()).digest("hex");
}

export function isPendingHandoffFresh(args: {
	preparedAt?: string;
	capturedAt?: string;
	nowMs?: number;
}): boolean {
	const nowMs = args.nowMs ?? Date.now();
	if (args.preparedAt && isTimestampFreshEnough(args.preparedAt, nowMs)) return true;
	if (args.capturedAt && isTimestampFreshEnough(args.capturedAt, nowMs)) return true;
	return false;
}

export type PlainCookPendingImportDecision =
	| { kind: "import"; handoffPath: string; proposal: ContextProposal }
	| { kind: "fail"; error: string; handoffPath?: string }
	| { kind: "ignore" };

export type PlainCookPendingImportOptions = {
	hasActiveWorkflow?: boolean;
};

export function resolvePlainCookPendingImport(
	pending: PendingCookHandoffState,
	options?: PlainCookPendingImportOptions,
): PlainCookPendingImportDecision {
	const hasActiveWorkflow = options?.hasActiveWorkflow === true;
	if (
		pending.state === "stale" ||
		pending.state === "not_startable" ||
		pending.state === "archived_consumed" ||
		pending.state === "archived_quarantined"
	) {
		return {
			kind: "fail",
			handoffPath: pending.handoffPath,
			error: pending.error ?? "cursor handoff is not usable for /cook",
		};
	}
	if (pending.state === "pending" && pending.proposal && pending.handoffPath) {
		return { kind: "import", handoffPath: pending.handoffPath, proposal: pending.proposal };
	}
	if (pending.state === "awaiting_launch") {
		return {
			kind: "fail",
			handoffPath: pending.handoffPath,
			error:
				"Cursor handoff is awaiting terminal launch. Run the command returned by start_cook_workflow in the integrated Terminal panel instead of /cook or /cook <prompt>.",
		};
	}
	if (pending.state === "confirmed") {
		return {
			kind: "fail",
			handoffPath: pending.handoffPath,
			error:
				"Cursor handoff is already confirmed. Run the command returned by start_cook_workflow in the integrated Terminal panel instead of /cook or /cook <prompt>.",
		};
	}
	if (pending.state === "kickoff_started") {
		if (hasActiveWorkflow) {
			return { kind: "ignore" };
		}
		return {
			kind: "fail",
			handoffPath: pending.handoffPath,
			error:
				"Cursor handoff kickoff is in progress but no workflow state exists yet. Cancel via start_cook_workflow action cancel, or retry MCP start. Do not use /cook or /cook <prompt> until the handoff is resolved.",
		};
	}
	return { kind: "ignore" };
}

async function readHandoffFileContent(root: string, relativePath = DEFAULT_CURSOR_HANDOFF_PATH): Promise<string | undefined> {
	const handoffPath = path.resolve(root, relativePath);
	try {
		const raw = (await fsp.readFile(handoffPath, "utf8")).trim();
		return raw.length > 0 ? raw : undefined;
	} catch {
		return undefined;
	}
}

export async function readHandoffFileHash(root: string, relativePath = DEFAULT_CURSOR_HANDOFF_PATH): Promise<string | undefined> {
	const content = await readHandoffFileContent(root, relativePath);
	return content ? computeHandoffContentHash(content) : undefined;
}

async function assertHandoffMatchesSidecar(root: string, sidecar: CookHandoffSidecar): Promise<void> {
	if (!sidecar.handoff_sha256) {
		throw new CookHandoffServiceError(
			"handoff integrity hash missing from sidecar; rerun prepare_cook_handoff",
			"handoff_integrity_missing",
		);
	}
	const currentHash = await readHandoffFileHash(root, sidecar.path);
	if (!currentHash || currentHash !== sidecar.handoff_sha256) {
		throw new CookHandoffServiceError(
			"handoff content changed since prepare; rerun prepare_cook_handoff",
			"handoff_integrity_mismatch",
		);
	}
}

export function normalizeCookHandoffCapsule(
	input: unknown,
	meta?: { sourceTurnId?: string; capturedAt?: string },
): Record<string, unknown> {
	if (!isRecord(input)) {
		throw new CookHandoffServiceError("cook handoff capsule must be an object", "invalid_capsule");
	}
	const mission = asString(input.mission);
	if (!mission) {
		throw new CookHandoffServiceError("cook handoff mission is required", "invalid_capsule");
	}
	return {
		kind: "cook_handoff",
		source: asString(input.source) ?? "primary_agent",
		captured_at: asString(input.captured_at) ?? meta?.capturedAt ?? new Date().toISOString(),
		source_turn_id: asString(input.source_turn_id) ?? meta?.sourceTurnId ?? "cursor-handoff",
		mission,
		scope: asStringArray(input.scope),
		constraints: asStringArray(input.constraints),
		non_goals: asStringArray(input.non_goals ?? input.nonGoals),
		acceptance: asStringArray(input.acceptance),
		risks: asStringArray(input.risks),
		notes: asStringArray(input.notes),
		handoff_kind: asString(input.handoff_kind ?? input.handoffKind) ?? "implementation_workflow_handoff",
		first_slice_goal: asString(input.first_slice_goal ?? input.firstSliceGoal),
		first_slice_non_goals: asStringArray(input.first_slice_non_goals ?? input.firstSliceNonGoals),
		implementation_surfaces: asStringArray(input.implementation_surfaces ?? input.implementationSurfaces),
		verification_commands: asStringArray(input.verification_commands ?? input.verificationCommands),
		why_this_slice_first: asString(input.why_this_slice_first ?? input.whyThisSliceFirst),
		verification_truth_mode: asString(input.verification_truth_mode ?? input.verificationTruthMode),
		deterministic_verifier_ready: localAsBoolean(input.deterministic_verifier_ready ?? input.deterministicVerifierReady),
		verification_latency: asString(input.verification_latency ?? input.verificationLatency),
		verification_noise_risk: asString(input.verification_noise_risk ?? input.verificationNoiseRisk),
		verifier_gap: asString(input.verifier_gap ?? input.verifierGap),
		recommended_first_slice_kind: asString(input.recommended_first_slice_kind ?? input.recommendedFirstSliceKind),
		task_type: asString(input.task_type) ?? "completion-workflow",
		evaluation_profile: asString(input.evaluation_profile) ?? "completion-rubric-v1",
		why_cook_now: asString(input.why_cook_now),
	};
}

export function validateCookHandoffSchema(capsule: Record<string, unknown>): { ok: true } | { ok: false; errors: string[] } {
	const contract = getStructuredContract(COMPLETION_COOK_HANDOFF_CONTRACT_ID);
	if (!contract?.parseDetails) {
		return { ok: false, errors: ["cook handoff structured contract is unavailable"] };
	}
	const parsed = contract.parseDetails({ capsule });
	if (!parsed.ok) return parsed;
	return { ok: true };
}

export async function assessCookHandoffStartability(
	root: string,
	capsule: Record<string, unknown>,
	projectName: string,
	deps: CookProposalDeps,
): Promise<{ startable: boolean; proposal?: ContextProposal; errors: string[]; warnings: string[] }> {
	const schema = validateCookHandoffSchema(capsule);
	if (!schema.ok) {
		return { startable: false, errors: schema.errors, warnings: [] };
	}
	const block = cookHandoffBlockFromJsonText(JSON.stringify(capsule));
	const { extractCookHandoffProposalFromText } = await import("./proposal.ts");
	const proposal = extractCookHandoffProposalFromText(block, projectName, deps, {
		messageId: asString(capsule.source_turn_id) ?? "cursor-handoff",
		timestampMs: Date.parse(asString(capsule.captured_at) ?? "") || Date.now(),
		source: "handoff_capsule",
	});
	if (!proposal) {
		return {
			startable: false,
			errors: ["cook handoff capsule is present but not startable after full proposal assessment"],
			warnings: [],
		};
	}
	return { startable: true, proposal, errors: [], warnings: [] };
}

export async function readCookHandoffSidecar(root: string): Promise<CookHandoffSidecar | undefined> {
	const sidecarPath = resolvePendingSidecarPath(root);
	try {
		const raw = await fsp.readFile(sidecarPath, "utf8");
		const parsed = JSON.parse(raw) as unknown;
		if (!isRecord(parsed)) return undefined;
		const workspaceRoot = asString(parsed.workspace_root);
		const confirmationId = asString(parsed.confirmation_id);
		const preparedAt = asString(parsed.prepared_at);
		const handoffPath = asString(parsed.path) ?? DEFAULT_CURSOR_HANDOFF_PATH;
		const handoffSha256 = asString(parsed.handoff_sha256);
		const status = asString(parsed.status);
		if (!workspaceRoot || !confirmationId || !preparedAt || !handoffSha256) return undefined;
		return {
			workspace_root: workspaceRoot,
			branch: asString(parsed.branch),
			path: handoffPath,
			prepared_at: preparedAt,
			confirmation_id: confirmationId,
			handoff_sha256: handoffSha256,
			status:
				status === "confirmed" ||
				status === "awaiting_terminal_launch" ||
				status === "kickoff_started" ||
				status === "pending_review"
					? status
					: "pending_review",
			source: asString(parsed.source) ?? "cursor-mcp",
			mission_preview: asString(parsed.mission_preview),
			confirmed_at: asString(parsed.confirmed_at),
			confirmed_by: asString(parsed.confirmed_by),
			last_spawn_error: asString(parsed.last_spawn_error),
		};
	} catch {
		return undefined;
	}
}

async function writeCookHandoffSidecar(root: string, sidecar: CookHandoffSidecar): Promise<string> {
	const sidecarPath = resolvePendingSidecarPath(root);
	await fsp.mkdir(path.dirname(sidecarPath), { recursive: true });
	await fsp.writeFile(sidecarPath, `${JSON.stringify(sidecar, null, 2)}\n`, { encoding: "utf8", mode: 0o600 });
	return sidecarPath;
}

export async function writeCookHandoffFile(
	root: string,
	capsule: Record<string, unknown>,
	meta?: { branch?: string; workspace_root?: string },
): Promise<{ handoffPath: string; pendingSidecarPath: string; confirmationId: string }> {
	const workspaceRoot = path.resolve(meta?.workspace_root ?? root);
	const handoffPath = resolveCursorHandoffPath(workspaceRoot);
	if (isArchivedCursorHandoffPath(handoffPath)) {
		throw new CookHandoffServiceError(`refusing to write archived handoff path: ${handoffPath}`, "archived_handoff_path");
	}
	await fsp.mkdir(path.dirname(handoffPath), { recursive: true });
	const handoffContent = `${JSON.stringify(capsule, null, 2)}\n`;
	await fsp.writeFile(handoffPath, handoffContent, { encoding: "utf8", mode: 0o600 });
	const confirmationId = randomUUID();
	const sidecar: CookHandoffSidecar = {
		workspace_root: workspaceRoot,
		branch: meta?.branch,
		path: path.relative(workspaceRoot, handoffPath) || DEFAULT_CURSOR_HANDOFF_PATH,
		prepared_at: new Date().toISOString(),
		confirmation_id: confirmationId,
		handoff_sha256: computeHandoffContentHash(handoffContent),
		status: "pending_review",
		source: "cursor-mcp",
		mission_preview: asString(capsule.mission),
	};
	const pendingSidecarPath = await writeCookHandoffSidecar(workspaceRoot, sidecar);
	return { handoffPath, pendingSidecarPath, confirmationId };
}

export async function readPendingCookHandoff(
	root: string,
	projectName: string,
	deps: CookProposalDeps,
): Promise<PendingCookHandoffState> {
	const workspaceRoot = path.resolve(root);
	const sidecar = await readCookHandoffSidecar(workspaceRoot);
	const handoffPath = resolveCursorHandoffPath(workspaceRoot);
	if (isArchivedCursorHandoffPath(handoffPath)) {
		const base = path.basename(handoffPath);
		if (base.startsWith("cursor-handoff.consumed.")) {
			return { state: "archived_consumed", error: `archived consumed handoff: ${handoffPath}`, handoffPath };
		}
		return { state: "archived_quarantined", error: `archived quarantined handoff: ${handoffPath}`, handoffPath };
	}
	const hasSidecar = Boolean(sidecar);
	const hasHandoffFile = await fsp
		.access(handoffPath)
		.then(() => true)
		.catch(() => false);
	if (!hasSidecar && !hasHandoffFile) {
		return { state: "none" };
	}
	const preparedAt = sidecar?.prepared_at;
	let rawHandoff: string | undefined;
	try {
		rawHandoff = (await fsp.readFile(handoffPath, "utf8")).trim();
	} catch {
		rawHandoff = undefined;
	}
	if (!rawHandoff) {
		return { state: "not_startable", error: `handoff file missing or empty: ${handoffPath}`, handoffPath };
	}
	let capturedAt: string | undefined;
	try {
		const parsed = JSON.parse(rawHandoff) as unknown;
		if (isRecord(parsed)) capturedAt = asString(parsed.captured_at);
	} catch {
		capturedAt = undefined;
	}
	if (!isPendingHandoffFresh({ preparedAt, capturedAt })) {
		return { state: "stale", error: "cursor handoff is stale; rerun handoff prep or use /cook <prompt>", handoffPath };
	}
	const loaded = await loadCursorHandoffProposal(workspaceRoot, projectName, deps);
	if (!loaded.proposal) {
		return {
			state: "not_startable",
			error: loaded.error ?? "cursor handoff is not startable",
			handoffPath: loaded.handoffPath,
		};
	}
	if (sidecar?.status === "kickoff_started") {
		return { state: "kickoff_started", handoffPath: loaded.handoffPath, sidecar, proposal: loaded.proposal };
	}
	if (sidecar?.status === "awaiting_terminal_launch" || sidecar?.status === "confirmed") {
		return { state: sidecar.status === "awaiting_terminal_launch" ? "awaiting_launch" : "confirmed", handoffPath: loaded.handoffPath, sidecar, proposal: loaded.proposal };
	}
	if (!sidecar) {
		if (capturedAt && isTimestampFreshEnough(capturedAt) && loaded.proposal) {
			return {
				state: "pending",
				handoffPath: loaded.handoffPath,
				sidecar: {
					workspace_root: workspaceRoot,
					path: path.relative(workspaceRoot, loaded.handoffPath) || DEFAULT_CURSOR_HANDOFF_PATH,
					prepared_at: capturedAt,
					confirmation_id: "legacy-handoff",
					handoff_sha256: computeHandoffContentHash(rawHandoff),
					status: "pending_review",
					source: "legacy-file",
					mission_preview: loaded.proposal.mission,
				},
				proposal: loaded.proposal,
			};
		}
		return {
			state: "not_startable",
			error:
				"cursor handoff file exists without MCP sidecar and without a fresh captured_at; rerun prepare_cook_handoff, add captured_at, or use /cook import",
			handoffPath: loaded.handoffPath,
		};
	}
	return {
		state: "pending",
		handoffPath: loaded.handoffPath,
		sidecar,
		proposal: loaded.proposal,
	};
}

export function buildCookHandoffConfirmationLayout(
	proposal: ContextProposal,
	options?: { title?: string },
): ContextProposalConfirmationLayout {
	return buildContextProposalConfirmationLayout({
		title: options?.title ?? "Start a completion workflow from this Cursor handoff?",
		proposal,
		analysis: finalizeContextProposalAnalysis(proposal.analysis),
		mainChatRerunGuidance:
			"Discuss changes in the main chat, then rerun /cook or prepare a fresh Cursor handoff.",
		defaultTaskType: "completion-workflow",
		defaultEvaluationProfile: "completion-rubric-v1",
	});
}

export async function ensureHandoffSidecarIntegrity(root: string, sidecar: CookHandoffSidecar): Promise<void> {
	await assertHandoffMatchesSidecar(root, sidecar);
}

export async function markHandoffConfirmed(root: string, confirmationId: string): Promise<CookHandoffSidecar> {
	const sidecar = await readCookHandoffSidecar(root);
	if (!sidecar) {
		throw new CookHandoffServiceError("pending handoff sidecar not found", "sidecar_missing");
	}
	if (sidecar.confirmation_id !== confirmationId) {
		throw new CookHandoffServiceError("confirmation_id does not match pending handoff sidecar", "confirmation_mismatch");
	}
	if (sidecar.status === "kickoff_started") {
		throw new CookHandoffServiceError("cook handoff workflow already kicked off", "kickoff_already_started");
	}
	await assertHandoffMatchesSidecar(root, sidecar);
	if (sidecar.status === "confirmed" || sidecar.status === "awaiting_terminal_launch") {
		const refreshed: CookHandoffSidecar = {
			...sidecar,
			confirmed_at: new Date().toISOString(),
			last_spawn_error: undefined,
		};
		await writeCookHandoffSidecar(root, refreshed);
		return refreshed;
	}
	if (!isTimestampFreshEnough(sidecar.prepared_at)) {
		throw new CookHandoffServiceError("pending handoff sidecar is stale", "sidecar_stale");
	}
	const updated: CookHandoffSidecar = {
		...sidecar,
		status: "confirmed",
		confirmed_at: new Date().toISOString(),
		confirmed_by: "cursor-mcp",
		last_spawn_error: undefined,
	};
	await writeCookHandoffSidecar(root, updated);
	return updated;
}

export async function markHandoffSpawnFailed(root: string, confirmationId: string, error: string): Promise<void> {
	const sidecar = await readCookHandoffSidecar(root);
	if (!sidecar || sidecar.confirmation_id !== confirmationId) return;
	await writeCookHandoffSidecar(root, {
		...sidecar,
		status: "confirmed",
		last_spawn_error: error,
		confirmed_at: sidecar.confirmed_at ?? new Date().toISOString(),
	});
}

export async function markHandoffAwaitingTerminalLaunch(root: string, confirmationId: string): Promise<void> {
	const sidecar = await readCookHandoffSidecar(root);
	if (!sidecar || sidecar.confirmation_id !== confirmationId) return;
	if (sidecar.status === "kickoff_started") return;
	await writeCookHandoffSidecar(root, {
		...sidecar,
		status: "awaiting_terminal_launch",
		confirmed_at: new Date().toISOString(),
		last_spawn_error: undefined,
	});
}

export async function recoverStaleKickoffWithoutWorkflow(root: string, confirmationId: string): Promise<boolean> {
	const sidecar = await readCookHandoffSidecar(root);
	if (!sidecar || sidecar.confirmation_id !== confirmationId || sidecar.status !== "kickoff_started") {
		return false;
	}
	const { loadCompletionSnapshot } = await import("./state-store.ts");
	if (await loadCompletionSnapshot(root)) {
		return false;
	}
	await writeCookHandoffSidecar(root, {
		...sidecar,
		status: "confirmed",
		last_spawn_error: "recovered stale kickoff_started with no workflow state",
		confirmed_at: new Date().toISOString(),
	});
	return true;
}

export async function markHandoffKickoffStarted(root: string, confirmationId: string): Promise<void> {
	const sidecar = await readCookHandoffSidecar(root);
	if (!sidecar || sidecar.confirmation_id !== confirmationId) return;
	await writeCookHandoffSidecar(root, { ...sidecar, status: "kickoff_started" });
}

export async function consumeCursorConfirmedKickoffEnv(
	root: string,
	envConfirmationId: string | undefined,
): Promise<{ accepted: boolean; confirmationId?: string; reason?: string }> {
	const confirmationId = asString(envConfirmationId);
	if (!confirmationId) {
		return { accepted: false, reason: "missing PI_COMPLETION_CURSOR_HANDOFF_CONFIRMED" };
	}
	const sidecar = await readCookHandoffSidecar(root);
	if (!sidecar) {
		return { accepted: false, reason: "pending handoff sidecar not found" };
	}
	if (sidecar.confirmation_id !== confirmationId) {
		return { accepted: false, reason: "confirmation_id mismatch" };
	}
	if (sidecar.status !== "confirmed" && sidecar.status !== "awaiting_terminal_launch" && sidecar.status !== "kickoff_started") {
		return { accepted: false, reason: "handoff not confirmed in Cursor" };
	}
	if (!isTimestampFreshEnough(sidecar.confirmed_at ?? sidecar.prepared_at)) {
		return { accepted: false, reason: "cursor handoff confirmation is stale" };
	}
	if (path.resolve(sidecar.workspace_root) !== path.resolve(root)) {
		return { accepted: false, reason: "workspace_root mismatch" };
	}
	try {
		await assertHandoffMatchesSidecar(root, sidecar);
	} catch (error) {
		const message = error instanceof Error ? error.message : String(error);
		return { accepted: false, reason: message };
	}
	return { accepted: true, confirmationId };
}

export async function cancelPendingHandoff(root: string): Promise<void> {
	const workspaceRoot = path.resolve(root);
	const sidecar = await readCookHandoffSidecar(workspaceRoot);
	const handoffPath = path.resolve(workspaceRoot, sidecar?.path ?? DEFAULT_CURSOR_HANDOFF_PATH);
	await clearPendingSidecar(workspaceRoot);
	try {
		await fsp.unlink(handoffPath);
	} catch {
		// ignore missing handoff file
	}
}

export async function clearPendingSidecar(root: string): Promise<void> {
	const sidecarPath = resolvePendingSidecarPath(root);
	try {
		await fsp.unlink(sidecarPath);
	} catch {
		// ignore missing sidecar
	}
}
