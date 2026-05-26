import * as fs from "node:fs";
import { promises as fsp } from "node:fs";
import * as path from "node:path";
import type { CompletionStateSnapshot, JsonRecord } from "./types";

const PROTOCOL_ID = "completion";
const DEFAULT_TASK_TYPE = "completion-workflow";
const DEFAULT_EVALUATION_PROFILE = "completion-rubric-v1";
const DEFAULT_REQUIRED_STOP_JUDGES = 2;
const DEFAULT_STOP_AGGREGATION_POLICY = "unanimous-current-head-v1";
const AGENT_DIRNAME = ".agent";
const CURRENT_DIRNAME = "current";

function isRecord(value: unknown): value is JsonRecord {
	return typeof value === "object" && value !== null && !Array.isArray(value);
}

function asString(value: unknown): string | undefined {
	return typeof value === "string" && value.trim().length > 0 ? value.trim() : undefined;
}

function asStringArray(value: unknown): string[] {
	return Array.isArray(value)
		? value.filter((item): item is string => typeof item === "string" && item.trim().length > 0)
		: [];
}

function asNumber(value: unknown): number | undefined {
	return typeof value === "number" && Number.isFinite(value) ? value : undefined;
}

function shellQuote(value: string): string {
	return `'${value.replace(/'/g, `'"'"'`)}'`;
}

export function resolveFiles(root: string) {
	const agentDir = path.join(root, AGENT_DIRNAME);
	const currentDir = path.join(agentDir, CURRENT_DIRNAME);
	const tmpDir = path.join(currentDir, "tmp");
	return {
		root,
		agentDir,
		currentDir,
		tmpDir,
		statePath: path.join(currentDir, "state.json"),
		planPath: path.join(currentDir, "plan.json"),
		activePath: path.join(currentDir, "active-slice.json"),
		sliceHistoryPath: path.join(currentDir, "slice-history.jsonl"),
		stopHistoryPath: path.join(currentDir, "stop-check-history.jsonl"),
		startupBriefPath: path.join(currentDir, "startup-brief.json"),
		verificationEvidencePath: path.join(currentDir, "verification-evidence.json"),
		compactionMarkerPath: path.join(tmpDir, "post-compaction-recovery.json"),
		driverPromptPath: path.join(tmpDir, "driver-prompt.json"),
	};
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

function completionSearchRoots(startCwd: string): string[] {
	return [...new Set([path.resolve(startCwd), path.resolve(process.cwd())])];
}

export function findCompletionRoot(startCwd: string): string | undefined {
	for (const candidateRoot of completionSearchRoots(startCwd)) {
		const statePath = walkUpForDir(candidateRoot, [AGENT_DIRNAME, CURRENT_DIRNAME, "state.json"]);
		if (statePath) return path.dirname(path.dirname(path.dirname(statePath)));
	}
	return undefined;
}

export function findRepoRoot(startCwd: string): string | undefined {
	for (const candidateRoot of completionSearchRoots(startCwd)) {
		const gitPath = walkUpForDir(candidateRoot, [".git"]);
		if (gitPath) return path.dirname(gitPath);
	}
	return undefined;
}

export function completionRootKey(snapshot: CompletionStateSnapshot | undefined, cwd: string): string {
	return snapshot?.files.root ?? findCompletionRoot(cwd) ?? findRepoRoot(cwd) ?? path.resolve(cwd);
}

export async function readJson(filePath: string): Promise<JsonRecord | undefined> {
	try {
		const raw = await fsp.readFile(filePath, "utf8");
		const parsed = JSON.parse(raw);
		return isRecord(parsed) ? parsed : undefined;
	} catch {
		return undefined;
	}
}

export async function readJsonl(filePath: string): Promise<JsonRecord[]> {
	try {
		const raw = await fsp.readFile(filePath, "utf8");
		return raw
			.split("\n")
			.map((line) => line.trim())
			.filter(Boolean)
			.flatMap((line) => {
				try {
					const parsed = JSON.parse(line);
					return isRecord(parsed) ? [parsed] : [];
				} catch {
					return [];
				}
			});
	} catch {
		return [];
	}
}

export async function writeJsonFile(filePath: string, value: JsonRecord): Promise<void> {
	await fsp.writeFile(filePath, `${JSON.stringify(value, null, 2)}\n`, "utf8");
}

function candidateSlices(plan: JsonRecord | undefined): JsonRecord[] {
	const slices = plan?.candidate_slices;
	return Array.isArray(slices) ? slices.filter(isRecord) : [];
}

function findActiveSlice(plan: JsonRecord | undefined, active: JsonRecord | undefined): JsonRecord | undefined {
	const sliceId = asString(active?.slice_id);
	if (!sliceId) return undefined;
	return candidateSlices(plan).find((slice) => asString(slice.slice_id) === sliceId);
}

async function hasCompleteRuntimeState(files: ReturnType<typeof resolveFiles>): Promise<boolean> {
	const requiredRuntimePaths = [
		files.statePath,
		files.planPath,
		files.activePath,
		files.verificationEvidencePath,
		files.sliceHistoryPath,
		files.stopHistoryPath,
	];
	for (const targetPath of requiredRuntimePaths) {
		if (!(await pathExists(targetPath))) return false;
	}
	return true;
}

export async function removeCompletionRuntimeState(target: string | ReturnType<typeof resolveFiles>): Promise<void> {
	const files = typeof target === "string" ? resolveFiles(target) : target;
	await fsp.rm(files.currentDir, { recursive: true, force: true });
}

async function ensureCanonicalStartupBrief(root: string, files: ReturnType<typeof resolveFiles>, state: JsonRecord): Promise<JsonRecord | undefined> {
	const existing = await readJson(files.startupBriefPath);
	if (existing) return existing;
	if (!isRecord(state.advisory_startup_brief)) return undefined;
	const rebuilt = defaultStartupBrief(
		asString(state.mission_anchor) ?? path.basename(root),
		{
			taskType: asString(state.task_type) ?? DEFAULT_TASK_TYPE,
			evaluationProfile: asString(state.evaluation_profile) ?? DEFAULT_EVALUATION_PROFILE,
		},
		state.advisory_startup_brief,
	);
	await writeJsonFile(files.startupBriefPath, rebuilt);
	return rebuilt;
}

export async function loadCompletionSnapshot(startCwd: string): Promise<CompletionStateSnapshot | undefined> {
	const root = findCompletionRoot(startCwd);
	if (!root) return undefined;
	const files = resolveFiles(root);
	if (!(await hasCompleteRuntimeState(files))) return undefined;
	const state = await readJson(files.statePath);
	const plan = await readJson(files.planPath);
	const active = await readJson(files.activePath);
	const verificationEvidence = await readJson(files.verificationEvidencePath);
	if (!state || !plan || !active || !verificationEvidence) return undefined;
	const startupBrief = await ensureCanonicalStartupBrief(root, files, state);
	if (!startupBrief) return undefined;
	const workflow = buildWorkflowRecord();
	const profile = buildProfileRecord({
		projectName: path.basename(root),
		requiredStopJudges: DEFAULT_REQUIRED_STOP_JUDGES,
		stopAggregationPolicy: DEFAULT_STOP_AGGREGATION_POLICY,
		docsSurfaces: await detectDocsSurfaces(root),
		taskType: asString(state.task_type) ?? DEFAULT_TASK_TYPE,
		evaluationProfile: asString(state.evaluation_profile) ?? DEFAULT_EVALUATION_PROFILE,
	});
	return {
		files,
		workflow,
		profile,
		state,
		plan,
		active,
		startupBrief,
		verificationEvidence,
		activeSlice: findActiveSlice(plan, active),
	};
}

export async function loadCompletionDataForReminder(startCwd: string) {
	const snapshot = await loadCompletionSnapshot(startCwd);
	if (!snapshot) return undefined;
	const sliceHistory = await readJsonl(snapshot.files.sliceHistoryPath);
	const stopHistory = await readJsonl(snapshot.files.stopHistoryPath);
	return { snapshot, sliceHistory, stopHistory };
}

export function canonicalStartupBrief(snapshot: CompletionStateSnapshot | undefined): JsonRecord | undefined {
	if (!snapshot) return undefined;
	return isRecord(snapshot.startupBrief) ? snapshot.startupBrief : undefined;
}

export async function pathExists(targetPath: string): Promise<boolean> {
	try {
		await fsp.access(targetPath);
		return true;
	} catch {
		return false;
	}
}

export async function readText(filePath: string): Promise<string | undefined> {
	try {
		return await fsp.readFile(filePath, "utf8");
	} catch {
		return undefined;
	}
}

export async function detectDocsSurfaces(root: string): Promise<string[]> {
	const candidates = ["README.md", "docs/", "docs", "CHANGELOG.md"];
	const found: string[] = [];
	for (const candidate of candidates) {
		if (await pathExists(path.join(root, candidate))) found.push(candidate.endsWith("/") ? candidate : candidate.replace(/\/$/, ""));
	}
	return found.length > 0 ? found : ["README.md"];
}

async function detectVerifierCommand(root: string): Promise<string | undefined> {
	const packageJsonPath = path.join(root, "package.json");
	const packageJson = await readJson(packageJsonPath);
	if (packageJson) {
		const scripts = isRecord(packageJson.scripts) ? packageJson.scripts : undefined;
		const packageManager = asString((packageJson as JsonRecord).packageManager) ?? "";
		const runner = packageManager.startsWith("pnpm") ? "pnpm" : packageManager.startsWith("yarn") ? "yarn" : packageManager.startsWith("bun") ? "bun" : "npm";
		if (scripts && asString(scripts["release-check"])) return runner === "npm" ? "npm run release-check >/dev/null" : `${runner} run release-check >/dev/null`;
		if (scripts && asString(scripts.test)) return runner === "npm" ? "npm test" : `${runner} test`;
		if (scripts && asString(scripts.check)) return runner === "npm" ? "npm run check" : `${runner} check`;
		if (scripts && asString(scripts.lint)) return runner === "npm" ? "npm run lint" : `${runner} lint`;
	}
	if (await pathExists(path.join(root, "pnpm-lock.yaml"))) return "pnpm test";
	if ((await pathExists(path.join(root, "bun.lockb"))) || (await pathExists(path.join(root, "bun.lock")))) return "bun test";
	if (await pathExists(path.join(root, "yarn.lock"))) return "yarn test";
	if (await pathExists(path.join(root, "Cargo.toml"))) return "cargo test";
	if ((await pathExists(path.join(root, "pyproject.toml"))) || (await pathExists(path.join(root, "pytest.ini")))) return "pytest";
	if (await pathExists(path.join(root, "go.mod"))) return "go test ./...";
	if (await pathExists(path.join(root, "Makefile"))) return "make test";
	return undefined;
}

export function buildWorkflowRecord(): JsonRecord {
	return {
		schema_version: 1,
		protocol_id: PROTOCOL_ID,
		layout_version: 5,
		config_dir: null,
		runtime_dir: `.agent/${CURRENT_DIRNAME}`,
		runtime_artifacts: [
			"state.json",
			"startup-brief.json",
			"plan.json",
			"active-slice.json",
			"slice-history.jsonl",
			"stop-check-history.jsonl",
			"verification-evidence.json",
			"tmp/",
		],
		cleanup_on: ["replacement", "cancel", "done"],
		archive_policy: "disabled",
	};
}

export function buildProfileRecord(args: {
	projectName: string;
	requiredStopJudges: number;
	stopAggregationPolicy?: string;
	priorityPolicyId?: string;
	docsSurfaces: string[];
	taskType?: string;
	evaluationProfile?: string;
}): JsonRecord {
	return {
		schema_version: 1,
		protocol_id: PROTOCOL_ID,
		project_name: args.projectName,
		required_stop_judges: args.requiredStopJudges,
		stop_aggregation_policy: args.stopAggregationPolicy ?? DEFAULT_STOP_AGGREGATION_POLICY,
		priority_policy_id: args.priorityPolicyId ?? "completion-default",
		task_type: args.taskType ?? DEFAULT_TASK_TYPE,
		evaluation_profile: args.evaluationProfile ?? DEFAULT_EVALUATION_PROFILE,
		docs_surfaces: args.docsSurfaces,
	};
}

function buildWorkflowSessionId(): string {
	return `wf-${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 8)}`;
}

export function defaultState(
	missionAnchor: string,
	routing?: { taskType?: string; evaluationProfile?: string; continuationReason?: string },
	advisoryStartupBrief?: JsonRecord,
	stopPolicy?: { requiredStopJudges?: number },
): JsonRecord {
	const confirmedAt = asString(advisoryStartupBrief?.captured_at) ?? new Date().toISOString();
	const requiredStopJudges = stopPolicy?.requiredStopJudges ?? DEFAULT_REQUIRED_STOP_JUDGES;
	return {
		schema_version: 1,
		mission_anchor: missionAnchor,
		workflow_entry_status: "active",
		workflow_entry_source: "/cook",
		workflow_entry_confirmed_at: confirmedAt,
		workflow_session_id: buildWorkflowSessionId(),
		startup_brief_path: ".agent/current/startup-brief.json",
		current_phase: "reground",
		continuation_policy: "continue",
		continuation_reason: routing?.continuationReason ?? "Fresh completion bootstrap requires canonical re-ground",
		project_done: false,
		task_type: routing?.taskType ?? DEFAULT_TASK_TYPE,
		evaluation_profile: routing?.evaluationProfile ?? DEFAULT_EVALUATION_PROFILE,
		requires_reground: true,
		slices_since_last_reground: 0,
		remaining_release_blockers: null,
		remaining_high_value_gaps: null,
		unsatisfied_contract_ids: [],
		release_blocker_ids: [],
		next_mandatory_action: "Reconcile canonical state from current repo truth",
		next_mandatory_role: "completion-regrounder",
		remaining_stop_judges: requiredStopJudges,
		current_stop_wave_id: 0,
		last_reground_at: null,
		last_auditor_verdict: null,
		contract_status: "unknown",
		latest_completed_slice: null,
		latest_verified_slice: null,
	};
}

export function defaultPlan(
	missionAnchor: string,
	routing?: { taskType?: string; evaluationProfile?: string },
): JsonRecord {
	return {
		schema_version: 1,
		mission_anchor: missionAnchor,
		task_type: routing?.taskType ?? DEFAULT_TASK_TYPE,
		evaluation_profile: routing?.evaluationProfile ?? DEFAULT_EVALUATION_PROFILE,
		last_reground_at: null,
		plan_basis: "bootstrap",
		candidate_slices: [],
	};
}

export function defaultActiveSlice(
	missionAnchor: string,
	routing?: { taskType?: string; evaluationProfile?: string },
): JsonRecord {
	return {
		schema_version: 1,
		mission_anchor: missionAnchor,
		task_type: routing?.taskType ?? DEFAULT_TASK_TYPE,
		evaluation_profile: routing?.evaluationProfile ?? DEFAULT_EVALUATION_PROFILE,
		status: "idle",
		slice_id: null,
		goal: null,
		contract_ids: [],
		acceptance_criteria: [],
		priority: null,
		why_now: null,
		blocked_on: [],
		locked_notes: [],
		must_fix_findings: [],
		implementation_surfaces: [],
		verification_commands: [],
		basis_commit: null,
		remaining_contract_ids_before: [],
		release_blocker_count_before: null,
		high_value_gap_count_before: null,
	};
}

export function defaultStartupBrief(
	missionAnchor: string,
	routing?: { taskType?: string; evaluationProfile?: string },
	advisoryStartupBrief?: JsonRecord,
): JsonRecord {
	return {
		schema_version: 1,
		artifact_type: "completion-startup-brief",
		source: asString(advisoryStartupBrief?.source) ?? "primary_agent",
		confirmed: true,
		confirmed_at: asString(advisoryStartupBrief?.captured_at) ?? new Date().toISOString(),
		mission: asString(advisoryStartupBrief?.mission) ?? missionAnchor,
		goal_text: asString(advisoryStartupBrief?.goal_text) ?? `Mission: ${missionAnchor}`,
		scope: asStringArray(advisoryStartupBrief?.scope),
		constraints: asStringArray(advisoryStartupBrief?.constraints),
		acceptance: asStringArray(advisoryStartupBrief?.acceptance),
		risks: asStringArray(advisoryStartupBrief?.risks),
		notes:
			asStringArray(advisoryStartupBrief?.notes).length > 0
				? asStringArray(advisoryStartupBrief?.notes)
				: ["No additional startup notes were preserved for this workflow entry."],
		first_slice_goal_hint: asString(advisoryStartupBrief?.first_slice_goal_hint),
		first_slice_non_goals_hint: asStringArray(advisoryStartupBrief?.first_slice_non_goals_hint),
		implementation_surfaces_hint: asStringArray(advisoryStartupBrief?.implementation_surfaces_hint),
		verification_commands_hint: asStringArray(advisoryStartupBrief?.verification_commands_hint),
		why_this_slice_first_hint: asString(advisoryStartupBrief?.why_this_slice_first_hint),
		task_type: asString(advisoryStartupBrief?.task_type) ?? routing?.taskType ?? DEFAULT_TASK_TYPE,
		evaluation_profile: asString(advisoryStartupBrief?.evaluation_profile) ?? routing?.evaluationProfile ?? DEFAULT_EVALUATION_PROFILE,
	};
}

export function defaultVerificationEvidence(): JsonRecord {
	return {
		schema_version: 1,
		artifact_type: "completion-verification-evidence",
		subject_type: "none",
		slice_id: null,
		goal: null,
		contract_ids: [],
		basis_commit: null,
		head_sha: null,
		verification_commands: [],
		outcome: "not_recorded",
		recorded_at: null,
		summary: "No deterministic verification evidence is recorded yet because no selected slice or current-HEAD verification subject exists.",
	};
}

export function buildVerifyStopScript(verifierCommand?: string): string {
	const packageScriptPath = path.resolve(__dirname, "..", "..", "scripts", "verify-completion-stop.sh");
	const repoRelativeScript = '"$SCRIPT_DIR/../scripts/verify-completion-stop.sh"';
	const packageScript = shellQuote(packageScriptPath);
	const repoCommandExport = `export COMPLETION_REPO_VERIFY_COMMAND=${shellQuote(verifierCommand ?? "")}`;
	return `#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "\${BASH_SOURCE[0]}")" && pwd -P)"
${repoCommandExport}
export COMPLETION_REPO_VERIFY_CWD="$(cd "$SCRIPT_DIR/.." && pwd -P)"
if [[ -f "$SCRIPT_DIR/../scripts/verify-completion-stop.sh" ]]; then
  exec bash ${repoRelativeScript} "$@"
fi
exec bash ${packageScript} "$@"
`;
}

export function buildVerifyControlPlaneScript(): string {
	const packageScriptPath = path.resolve(__dirname, "..", "..", "scripts", "verify-completion-control-plane.js");
	const packageScript = shellQuote(packageScriptPath);
	return `#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "\${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$SCRIPT_DIR/../scripts/verify-completion-control-plane.js" ]]; then
  exec node "$SCRIPT_DIR/../scripts/verify-completion-control-plane.js" "$@"
fi
exec node ${packageScript} "$@"
`;
}

async function ensureGitignore(root: string): Promise<boolean> {
	const gitignorePath = path.join(root, ".gitignore");
	const blockLines = [
		"# completion workflow local state",
		".agent/",
	];
	const block = blockLines.join("\n");
	const existing = (await pathExists(gitignorePath)) ? await fsp.readFile(gitignorePath, "utf8") : "";
	const legacyBlockLines = [
		"!.agent/README.md",
		"!.agent/config/",
		".agent/config/*",
		"!.agent/config/workflow.json",
		"!.agent/config/profile.json",
		"!.agent/profile.json",
		"!.agent/verify_completion_stop.sh",
		"!.agent/verify_completion_control_plane.sh",
		".agent/current/",
		"!.agent/mission.md",
		".agent/tmp/",
	];
	const filteredLines = existing
		.split(/\r?\n/)
		.filter((line) => !blockLines.includes(line.trim()) && !legacyBlockLines.includes(line.trim()));
	while (filteredLines.length > 0 && filteredLines[filteredLines.length - 1]?.trim() === "") {
		filteredLines.pop();
	}
	const base = filteredLines.join("\n").trimEnd();
	const content = base.length > 0 ? `${base}\n\n${block}\n` : `${block}\n`;
	if (content === existing) return false;
	await fsp.writeFile(gitignorePath, content, "utf8");
	return true;
}

async function stageTrackedContractFiles(_root: string): Promise<void> {
	return;
}

export type ScaffoldResult = {
	root: string;
	created: string[];
	updated: string[];
	missionAnchor: string;
};

export async function scaffoldCompletionFiles(
	root: string,
	missionAnchor: string,
	options?: { analysis?: { taskType?: string; evaluationProfile?: string }; continuationReason?: string; advisoryStartupBrief?: JsonRecord },
): Promise<ScaffoldResult> {
	const files = resolveFiles(root);
	const created: string[] = [];
	const updated: string[] = [];
	await fsp.mkdir(files.agentDir, { recursive: true });
	await removeCompletionRuntimeState(files);
	await fsp.mkdir(files.currentDir, { recursive: true });
	await fsp.mkdir(files.tmpDir, { recursive: true });
	const verifierCommand = await detectVerifierCommand(root);
	const requiredStopJudges = DEFAULT_REQUIRED_STOP_JUDGES;
	const localRuntimeHelperFiles: Array<{ path: string; content: string; executable?: boolean }> = [
		{ path: path.join(files.agentDir, "verify_completion_stop.sh"), content: buildVerifyStopScript(verifierCommand), executable: true },
		{ path: path.join(files.agentDir, "verify_completion_control_plane.sh"), content: buildVerifyControlPlaneScript(), executable: true },
	];
	const runtimeFiles: Array<{ path: string; content: string }> = [
		{
			path: files.statePath,
			content: `${JSON.stringify(defaultState(missionAnchor, { taskType: options?.analysis?.taskType, evaluationProfile: options?.analysis?.evaluationProfile, continuationReason: options?.continuationReason }, options?.advisoryStartupBrief, { requiredStopJudges }), null, 2)}\n`,
		},
		{
			path: files.startupBriefPath,
			content: `${JSON.stringify(defaultStartupBrief(missionAnchor, { taskType: options?.analysis?.taskType, evaluationProfile: options?.analysis?.evaluationProfile }, options?.advisoryStartupBrief), null, 2)}\n`,
		},
		{ path: files.planPath, content: `${JSON.stringify(defaultPlan(missionAnchor, { taskType: options?.analysis?.taskType, evaluationProfile: options?.analysis?.evaluationProfile }), null, 2)}\n` },
		{ path: files.activePath, content: `${JSON.stringify(defaultActiveSlice(missionAnchor, { taskType: options?.analysis?.taskType, evaluationProfile: options?.analysis?.evaluationProfile }), null, 2)}\n` },
		{ path: files.verificationEvidencePath, content: `${JSON.stringify(defaultVerificationEvidence(), null, 2)}\n` },
		{ path: files.sliceHistoryPath, content: "" },
		{ path: files.stopHistoryPath, content: "" },
	];
	for (const file of localRuntimeHelperFiles) {
		await fsp.mkdir(path.dirname(file.path), { recursive: true });
		await fsp.writeFile(file.path, file.content, "utf8");
		if (file.executable) await fsp.chmod(file.path, 0o755);
		created.push(path.relative(root, file.path));
	}
	for (const file of runtimeFiles) {
		await fsp.mkdir(path.dirname(file.path), { recursive: true });
		await fsp.writeFile(file.path, file.content, "utf8");
		created.push(path.relative(root, file.path));
	}
	if (await ensureGitignore(root)) updated.push(".gitignore");
	await stageTrackedContractFiles(root);
	return { root, created, updated, missionAnchor };
}

export function currentTaskType(snapshot: CompletionStateSnapshot): string | undefined {
	return (
		asString(snapshot.active?.task_type) ??
		asString(snapshot.state?.task_type) ??
		asString(snapshot.plan?.task_type) ??
		asString(snapshot.profile?.task_type)
	);
}

export function currentEvaluationProfile(snapshot: CompletionStateSnapshot): string | undefined {
	return (
		asString(snapshot.active?.evaluation_profile) ??
		asString(snapshot.state?.evaluation_profile) ??
		asString(snapshot.plan?.evaluation_profile) ??
		asString(snapshot.profile?.evaluation_profile)
	);
}

export function currentMissionAnchor(snapshot: CompletionStateSnapshot): string {
	return (
		asString(snapshot.state?.mission_anchor) ??
		asString(snapshot.plan?.mission_anchor) ??
		asString(snapshot.active?.mission_anchor) ??
		path.basename(snapshot.files.root)
	);
}

export { asNumber, asString, asStringArray, isRecord };
