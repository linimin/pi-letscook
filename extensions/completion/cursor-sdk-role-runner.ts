import type { LiveRoleActivity } from "./types";
import { requireCursorApiKey, resolveCursorModel } from "./cursor-role-config.ts";
import type { CompletionRole } from "./types";

export type CursorSdkRoleAttemptArgs = {
	root: string;
	role: CompletionRole;
	combinedPrompt: string;
	cursorModel?: string;
	signal?: AbortSignal;
	onUpdate?: (activity: LiveRoleActivity) => void;
};

export type CursorSdkRoleAttemptResult = {
	exitCode: number;
	assistantText?: string;
	stderr?: string;
};

type CursorSdkAgent = {
	send: (prompt: string) => Promise<CursorSdkRun>;
	[Symbol.asyncDispose]?: () => Promise<void>;
};

type CursorSdkRun = {
	wait: () => Promise<{ status: string; result?: unknown }>;
	supports?: (operation: string) => boolean;
	cancel?: () => Promise<void>;
};

export class CursorSdkAbortedError extends Error {
	constructor() {
		super("aborted during Cursor SDK run");
		this.name = "CursorSdkAbortedError";
	}
}

async function loadCursorSdk(): Promise<typeof import("@cursor/sdk")> {
	try {
		return await import("@cursor/sdk");
	} catch {
		throw new Error(
			"Cursor SDK backend requires @cursor/sdk. Install it in the environment running pi-letscook, then retry.",
		);
	}
}

async function disposeCursorSdkAgent(agent: CursorSdkAgent | undefined): Promise<void> {
	if (!agent) return;
	const dispose = agent[Symbol.asyncDispose];
	if (typeof dispose === "function") await dispose.call(agent);
}

async function cancelCursorSdkRun(run: CursorSdkRun): Promise<void> {
	if (typeof run.supports === "function" && run.supports("cancel") && typeof run.cancel === "function") {
		await run.cancel();
	}
}

export async function waitForCursorSdkRun(run: CursorSdkRun, signal?: AbortSignal): Promise<{ status: string; result?: unknown }> {
	if (!signal) return run.wait();
	if (signal.aborted) {
		await cancelCursorSdkRun(run);
		throw new CursorSdkAbortedError();
	}

	const waitPromise = run.wait();
	waitPromise.catch(() => {
		// Suppress unhandled rejection when abort settles the race first.
	});

	return await new Promise((resolve, reject) => {
		let settled = false;
		let abortListener: (() => void) | undefined;
		const settle = (callback: () => void) => {
			if (settled) return;
			settled = true;
			if (abortListener) signal.removeEventListener("abort", abortListener);
			callback();
		};

		waitPromise.then(
			(result) => {
				if (signal.aborted) {
					void cancelCursorSdkRun(run).finally(() => settle(() => reject(new CursorSdkAbortedError())));
					return;
				}
				settle(() => resolve(result));
			},
			(error: unknown) => settle(() => reject(error)),
		);

		abortListener = () => {
			void cancelCursorSdkRun(run).finally(() => settle(() => reject(new CursorSdkAbortedError())));
		};
		signal.addEventListener("abort", abortListener, { once: true });
	});
}

export async function runCursorSdkRoleAttempt(args: CursorSdkRoleAttemptArgs): Promise<CursorSdkRoleAttemptResult> {
	let apiKey: string;
	try {
		apiKey = requireCursorApiKey();
	} catch (error) {
		const message = error instanceof Error ? error.message : String(error);
		return { exitCode: 1, stderr: message };
	}

	let Agent: typeof import("@cursor/sdk").Agent;
	let CursorAgentError: typeof import("@cursor/sdk").CursorAgentError;
	try {
		({ Agent, CursorAgentError } = await loadCursorSdk());
	} catch (error) {
		const message = error instanceof Error ? error.message : String(error);
		return { exitCode: 1, stderr: message };
	}

	const modelId = args.cursorModel ?? resolveCursorModel(args.role);
	args.onUpdate?.({
		role: args.role,
		status: "running",
		currentAction: `Running ${args.role} via Cursor SDK`,
		toolRecentActivity: [],
		recentActivity: [],
		stateDeltas: [],
		startedAt: Date.now(),
		updatedAt: Date.now(),
	});

	if (args.signal?.aborted) {
		return { exitCode: 1, stderr: "aborted before Cursor SDK run" };
	}

	let agent: CursorSdkAgent | undefined;
	try {
		agent = (await Agent.create({
			apiKey,
			model: { id: modelId },
			local: { cwd: args.root, settingSources: [] },
		})) as CursorSdkAgent;

		const run = await agent.send(args.combinedPrompt);
		const result = await waitForCursorSdkRun(run, args.signal);
		const assistantText = asString(result.result);
		const ok = result.status === "finished";
		return {
			exitCode: ok ? 0 : 1,
			assistantText,
			stderr: ok ? undefined : `Cursor SDK run status: ${result.status}`,
		};
	} catch (error) {
		if (error instanceof CursorSdkAbortedError) {
			return { exitCode: 1, stderr: error.message };
		}
		if (error instanceof CursorAgentError) {
			return {
				exitCode: 1,
				stderr: `Cursor SDK startup failed: ${error.message}`,
			};
		}
		const message = error instanceof Error ? error.message : String(error);
		return { exitCode: 1, stderr: message };
	} finally {
		await disposeCursorSdkAgent(agent);
	}
}

function asString(value: unknown): string | undefined {
	return typeof value === "string" && value.trim().length > 0 ? value.trim() : undefined;
}
