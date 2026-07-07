import { spawn, type ChildProcess } from "node:child_process";
import * as path from "node:path";

export type SpawnMode = "agent_terminal" | "background";

export type SpawnPiKickoffArgs = {
	workspaceRoot: string;
	confirmationId: string;
	piExtensionPath?: string;
	mode?: SpawnMode;
};

export type SpawnPiKickoffResult = {
	ok: boolean;
	spawn_mode: SpawnMode;
	pi_pid?: number;
	command: string;
	terminal: {
		surface: "integrated_terminal_panel" | "background_detached";
		launch_required: boolean;
		not_in_chat: true;
		hint: string;
	};
	error?: string;
};

function isProcessAlive(pid: number): boolean {
	try {
		process.kill(pid, 0);
		return true;
	} catch {
		return false;
	}
}

function waitMs(ms: number): Promise<void> {
	return new Promise((resolve) => setTimeout(resolve, ms));
}

export function buildPiKickoffCommand(args: SpawnPiKickoffArgs): string {
	const extension = args.piExtensionPath ?? process.env.PI_LETSCOOK_EXTENSION_PATH ?? ".";
	const cwd = path.resolve(args.workspaceRoot);
	return [
		`cd ${JSON.stringify(cwd)} &&`,
		`PI_COMPLETION_CURSOR_HANDOFF_CONFIRMED=${JSON.stringify(args.confirmationId)}`,
		`pi -e ${JSON.stringify(extension)} -p "/cook"`,
	].join(" ");
}

function agentTerminalResult(command: string): SpawnPiKickoffResult {
	return {
		ok: true,
		spawn_mode: "agent_terminal",
		command,
		terminal: {
			surface: "integrated_terminal_panel",
			launch_required: true,
			not_in_chat: true,
			hint: "Run the returned command in the integrated Terminal panel (bottom of the IDE) so Pi output is visible.",
		},
	};
}

async function verifyBackgroundProcessAlive(child: ChildProcess, pid: number, piBinary: string): Promise<string | undefined> {
	let exitCode: number | null = null;
	const onExit = (code: number | null) => {
		exitCode = code ?? -1;
	};
	child.on("exit", onExit);
	for (const delayMs of [300, 450]) {
		await waitMs(delayMs);
		if (exitCode !== null || !isProcessAlive(pid)) {
			child.off("exit", onExit);
			return `${piBinary} exited shortly after spawn`;
		}
	}
	child.off("exit", onExit);
	return undefined;
}

async function spawnPiBackground(args: {
	workspaceRoot: string;
	confirmationId: string;
	extension: string;
	command: string;
}): Promise<SpawnPiKickoffResult> {
	const piBinary = process.env.PI_BINARY ?? "pi";
	return await new Promise((resolve) => {
		let settled = false;
		const finish = (result: SpawnPiKickoffResult) => {
			if (settled) return;
			settled = true;
			resolve(result);
		};
		const child = spawn(piBinary, ["-e", args.extension, "-p", "/cook"], {
			cwd: path.resolve(args.workspaceRoot),
			env: {
				...process.env,
				PI_COMPLETION_CURSOR_HANDOFF_CONFIRMED: args.confirmationId,
			},
			detached: true,
			stdio: "ignore",
		});
		child.on("error", (error) => {
			finish({
				ok: false,
				spawn_mode: "background",
				command: args.command,
				error: `failed to spawn ${piBinary}: ${error.message}`,
				terminal: {
					surface: "background_detached",
					launch_required: false,
					not_in_chat: true,
					hint: "Background spawn failed. Run the returned command in the integrated Terminal panel instead.",
				},
			});
		});
		child.on("spawn", () => {
			void (async () => {
				if (!child.pid) {
					finish({
						ok: false,
						spawn_mode: "background",
						command: args.command,
						error: `failed to spawn ${piBinary}: missing child pid`,
						terminal: {
							surface: "background_detached",
							launch_required: false,
							not_in_chat: true,
							hint: "Background spawn failed. Run the returned command in the integrated Terminal panel instead.",
						},
					});
					return;
				}
				const livenessError = await verifyBackgroundProcessAlive(child, child.pid, piBinary);
				if (livenessError) {
					finish({
						ok: false,
						spawn_mode: "background",
						command: args.command,
						error: livenessError,
						terminal: {
							surface: "background_detached",
							launch_required: false,
							not_in_chat: true,
							hint: "Background spawn failed. Run the returned command in the integrated Terminal panel instead.",
						},
					});
					return;
				}
				child.unref();
				finish({
					ok: true,
					spawn_mode: "background",
					pi_pid: child.pid,
					command: args.command,
					terminal: {
						surface: "background_detached",
						launch_required: false,
						not_in_chat: true,
						hint: "Pi is running as a detached background process. Run the command in Terminal for visible output.",
					},
				});
			})();
		});
	});
}

export async function spawnPiKickoff(args: SpawnPiKickoffArgs): Promise<SpawnPiKickoffResult> {
	const extension = path.resolve(args.piExtensionPath ?? process.env.PI_LETSCOOK_EXTENSION_PATH ?? process.cwd());
	const command = buildPiKickoffCommand({ ...args, piExtensionPath: extension });
	const mode = args.mode ?? "agent_terminal";
	if (mode === "agent_terminal") {
		return agentTerminalResult(command);
	}
	return await spawnPiBackground({
		workspaceRoot: args.workspaceRoot,
		confirmationId: args.confirmationId,
		extension,
		command,
	});
}
