import {
	assessCookHandoffStartability,
	buildCookHandoffConfirmationLayout,
	COOK_HANDOFF_SCHEMA_EXAMPLE,
	cookProposalDeps,
	DEFAULT_CURSOR_HANDOFF_PATH,
	ensureHandoffSidecarIntegrity,
	getCookWorkflowStatus,
	markHandoffAwaitingTerminalLaunch,
	markHandoffConfirmed,
	markHandoffSpawnFailed,
	normalizeCookHandoffCapsule,
	pollCookWorkflowUpdates,
	readCookHandoffSidecar,
	readPendingCookHandoff,
	recoverStaleKickoffWithoutWorkflow,
	resolveWorkspaceRoot,
	validateCookHandoffSchema,
	writeCookHandoffFile,
} from "./deps.ts";
import { buildPiKickoffCommand, spawnPiKickoff, type SpawnMode } from "./spawn-pi.ts";
import { defaultPiExtensionPath } from "./deps.ts";
import { ensureCookWorktree, findGitRepoRoot } from "./worktree.ts";
import { CookHandoffServiceError, cancelPendingHandoff } from "./deps.ts";
import { loadCompletionSnapshot } from "../../../extensions/completion/state-store.ts";
import * as path from "node:path";

function textResult(payload: unknown) {
	return {
		content: [{ type: "text" as const, text: JSON.stringify(payload, null, 2) }],
	};
}

function toolError(message: string, code?: string) {
	return textResult({ ok: false, error: message, code });
}

function requireWorkspaceRoot(args: Record<string, unknown>): string {
	const resolved = resolveWorkspaceRoot({
		workspaceRoot: typeof args.workspace_root === "string" ? args.workspace_root : undefined,
		requireExplicit: true,
	});
	return resolved.workspaceRoot;
}

function resolveSpawnMode(value: unknown): SpawnMode {
	return value === "background" ? "background" : "agent_terminal";
}

async function buildMonitoringPayload(workspaceRoot: string, sidecarStatus?: string, spawnMode?: SpawnMode) {
	const hasWorkflow = Boolean(await loadCompletionSnapshot(workspaceRoot));
	if (hasWorkflow) {
		return { enabled: true, mode: "post_kickoff_watch" as const };
	}
	if (sidecarStatus === "awaiting_terminal_launch") {
		if (spawnMode === "background") {
			return {
				enabled: false,
				mode: "awaiting_background_spawn" as const,
				awaiting_background_spawn: true,
				note: "Pi was spawned in the background. Poll again after .agent/current appears in the worktree.",
			};
		}
		return {
			enabled: false,
			mode: "awaiting_terminal_launch" as const,
			awaiting_terminal_launch: true,
			note: "Run the returned command in the integrated Terminal panel, then poll for workflow updates.",
		};
	}
	return {
		enabled: false,
		mode: "awaiting_workflow_state" as const,
		note: "Workflow state is not available yet; poll again after Pi starts in the worktree.",
	};
}

export async function handleCookHandoffTool(name: string, args: Record<string, unknown>) {
	try {
		switch (name) {
			case "ensure_cook_worktree": {
				const repoRoot = path.resolve(
					typeof args.repo_root === "string" ? args.repo_root : findGitRepoRoot(process.cwd()) ?? process.cwd(),
				);
				const branch = typeof args.branch === "string" ? args.branch : `cook/${typeof args.slug === "string" ? args.slug : "task"}`;
				const slug = typeof args.slug === "string" ? args.slug : branch.replace(/^cook\//, "");
				const result = await ensureCookWorktree({
					repoRoot,
					branch,
					slug,
					baseRef: typeof args.base_ref === "string" ? args.base_ref : "HEAD",
				});
				return textResult({ ok: true, ...result });
			}
			case "prepare_cook_handoff": {
				const workspaceRoot = requireWorkspaceRoot(args);
				const capsule = normalizeCookHandoffCapsule(args.capsule ?? args);
				const schema = validateCookHandoffSchema(capsule);
				if (!schema.ok) return toolError(schema.errors.join("; "), "schema_invalid");
				const assessment = await assessCookHandoffStartability(
					workspaceRoot,
					capsule,
					path.basename(workspaceRoot),
					cookProposalDeps(),
				);
				if (!assessment.startable || !assessment.proposal) {
					return toolError(assessment.errors.join("; ") || "handoff not startable", "not_startable");
				}
				const written = await writeCookHandoffFile(workspaceRoot, capsule, {
					workspace_root: workspaceRoot,
					branch: typeof args.branch === "string" ? args.branch : undefined,
				});
				const layout = buildCookHandoffConfirmationLayout(assessment.proposal);
				return textResult({
					ok: true,
					workspace_root: workspaceRoot,
					path: path.relative(workspaceRoot, written.handoffPath) || DEFAULT_CURSOR_HANDOFF_PATH,
					pending_sidecar: ".agent/tmp/cursor-handoff.pending.json",
					confirmation_id: written.confirmationId,
					mission: capsule.mission,
					warnings: assessment.warnings,
					confirmation_preview: layout,
					next_steps: [
						"Review confirmation_preview in chat",
						"Choose Start or Cancel",
						"On Start, call start_cook_workflow with workspace_root and confirmation_id",
						"Run the returned command in the integrated Terminal panel when launch_required is true",
					],
				});
			}
			case "preview_cook_handoff_confirmation": {
				const workspaceRoot = requireWorkspaceRoot(args);
				const pending = await readPendingCookHandoff(workspaceRoot, path.basename(workspaceRoot), cookProposalDeps());
				if (!pending.proposal || !pending.sidecar) {
					return toolError(pending.error ?? `no startable pending handoff under ${workspaceRoot}`, pending.state);
				}
				if (pending.state === "kickoff_started") {
					return toolError("handoff already kicked off", "kickoff_already_started");
				}
				try {
					await ensureHandoffSidecarIntegrity(workspaceRoot, pending.sidecar);
				} catch (error) {
					const message = error instanceof Error ? error.message : String(error);
					return toolError(message, "handoff_integrity_mismatch");
				}
				return textResult({
					ok: true,
					workspace_root: workspaceRoot,
					confirmation_id: pending.sidecar.confirmation_id,
					handoff_sha256: pending.sidecar.handoff_sha256,
					layout: buildCookHandoffConfirmationLayout(pending.proposal),
				});
			}
			case "start_cook_workflow": {
				const workspaceRoot = requireWorkspaceRoot(args);
				const sidecar = await readCookHandoffSidecar(workspaceRoot);
				resolveWorkspaceRoot({
					workspaceRoot,
					sidecar,
					requireExplicit: true,
				});
				const action = typeof args.action === "string" ? args.action : "start";
				if (action === "cancel") {
					await cancelPendingHandoff(workspaceRoot);
					return textResult({ ok: true, cancelled: true, workspace_root: workspaceRoot });
				}
				const confirmationId = typeof args.confirmation_id === "string" ? args.confirmation_id : sidecar?.confirmation_id;
				if (!confirmationId) return toolError("confirmation_id is required", "confirmation_required");
				if (sidecar?.status === "kickoff_started") {
					const hasWorkflow = Boolean(await loadCompletionSnapshot(workspaceRoot));
					if (hasWorkflow) {
						return toolError("cook handoff workflow already kicked off", "kickoff_already_started");
					}
					await recoverStaleKickoffWithoutWorkflow(workspaceRoot, confirmationId);
				}
				const spawnMode = resolveSpawnMode(args.spawn_mode);
				const launchCommand = buildPiKickoffCommand({
					workspaceRoot,
					confirmationId,
					piExtensionPath: defaultPiExtensionPath(),
				});
				if (args.dry_run === true) {
					const dryRunSidecar = (await readCookHandoffSidecar(workspaceRoot)) ?? sidecar;
					if (!dryRunSidecar) {
						return toolError("pending handoff sidecar not found", "sidecar_missing");
					}
					try {
						await ensureHandoffSidecarIntegrity(workspaceRoot, dryRunSidecar);
					} catch (error) {
						const message = error instanceof Error ? error.message : String(error);
						return toolError(message, "handoff_integrity_mismatch");
					}
					return textResult({
						ok: true,
						workspace_root: workspaceRoot,
						confirmation_id: confirmationId,
						dry_run: true,
						spawn_mode: spawnMode,
						command: launchCommand,
						terminal: {
							surface: "integrated_terminal_panel" as const,
							launch_required: true,
							not_in_chat: true as const,
							hint: "Dry run only; sidecar state was not changed.",
						},
					});
				}
				await markHandoffConfirmed(workspaceRoot, confirmationId);
				const spawn = await spawnPiKickoff({
					workspaceRoot,
					confirmationId,
					piExtensionPath: defaultPiExtensionPath(),
					mode: spawnMode,
				});
				if (!spawn.ok) {
					await markHandoffSpawnFailed(workspaceRoot, confirmationId, spawn.error ?? "failed to spawn pi");
					return toolError(spawn.error ?? "failed to spawn pi", "spawn_failed");
				}
				await markHandoffAwaitingTerminalLaunch(workspaceRoot, confirmationId);
				return textResult({
					ok: true,
					workspace_root: workspaceRoot,
					confirmation_id: confirmationId,
					...spawn,
					monitoring: await buildMonitoringPayload(workspaceRoot, "awaiting_terminal_launch", spawnMode),
				});
			}
			case "validate_cook_handoff": {
				const workspaceRoot = typeof args.workspace_root === "string" ? requireWorkspaceRoot(args) : undefined;
				const capsule = normalizeCookHandoffCapsule(args.capsule ?? args);
				const schema = validateCookHandoffSchema(capsule);
				if (!schema.ok) return textResult({ ok: false, startable: false, errors: schema.errors });
				if (!workspaceRoot) {
					return textResult({
						ok: true,
						startable: false,
						schema: "valid",
						note: "full startability requires workspace_root",
					});
				}
				const assessment = await assessCookHandoffStartability(
					workspaceRoot,
					capsule,
					path.basename(workspaceRoot),
					cookProposalDeps(),
				);
				return textResult({
					ok: assessment.startable,
					startable: assessment.startable,
					errors: assessment.errors,
					warnings: assessment.warnings,
					proposal_preview: assessment.proposal
						? {
								mission: assessment.proposal.mission,
								scope: assessment.proposal.scope,
								acceptance: assessment.proposal.acceptance,
							}
						: undefined,
				});
			}
			case "get_cook_handoff_status": {
				const workspaceRoot = requireWorkspaceRoot(args);
				const pending = await readPendingCookHandoff(workspaceRoot, path.basename(workspaceRoot), cookProposalDeps());
				const sidecar = await readCookHandoffSidecar(workspaceRoot);
				return textResult({
					ok: true,
					workspace_root: workspaceRoot,
					state: pending.state,
					sidecar,
					error: pending.error,
					would_plain_cook_pick_up: pending.state === "pending",
				});
			}
			case "get_cook_handoff_schema": {
				return textResult({
					ok: true,
					schema: COOK_HANDOFF_SCHEMA_EXAMPLE,
					default_handoff_path: DEFAULT_CURSOR_HANDOFF_PATH,
					pending_sidecar_path: ".agent/tmp/cursor-handoff.pending.json",
				});
			}
			case "get_cook_workflow_status": {
				const workspaceRoot = requireWorkspaceRoot(args);
				const status = await getCookWorkflowStatus(workspaceRoot);
				if ("error" in status) return toolError(status.error, "workflow_not_found");
				return textResult({ ok: true, ...status });
			}
			case "poll_cook_workflow_updates": {
				const workspaceRoot = requireWorkspaceRoot(args);
				const polled = await pollCookWorkflowUpdates({
					workspaceRoot,
					sinceEventId: typeof args.since_event_id === "string" ? args.since_event_id : undefined,
				});
				if ("error" in polled) return toolError(polled.error, "workflow_not_found");
				return textResult({ ok: true, ...polled });
			}
			default:
				return toolError(`unknown tool: ${name}`, "unknown_tool");
		}
	} catch (error) {
		if (error instanceof CookHandoffServiceError) {
			return toolError(error.message, error.code);
		}
		const message = error instanceof Error ? error.message : String(error);
		return toolError(message, "internal_error");
	}
}
