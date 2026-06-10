/**
 * Regression fixture for agent_end auto-resume delivery.
 *
 * The completion driver calls autoContinueWorkflowIfNeeded() from agent_end.
 * This fixture records the extension-injected input event and asserts that
 * streamingBehavior arrives as followUp instead of being omitted.
 */
import * as fs from "node:fs";
import { promises as fsp } from "node:fs";
import * as path from "node:path";
import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";
import { autoContinueWorkflowIfNeeded } from "../../extensions/completion/driver";
import { completionRootKey, scaffoldCompletionFiles } from "../../extensions/completion/state-store";

function requiredEnv(name: string): string {
	const value = process.env[name]?.trim();
	if (!value) throw new Error(`Missing required environment variable: ${name}`);
	return value;
}

async function writeJson(targetPath: string, value: unknown): Promise<void> {
	await fsp.mkdir(path.dirname(targetPath), { recursive: true });
	await fsp.writeFile(targetPath, `${JSON.stringify(value, null, 2)}\n`, "utf8");
}

export default function (pi: ExtensionAPI) {
	const root = requiredEnv("PI_COMPLETION_AUTO_RESUME_TEST_ROOT");
	const capturePath = requiredEnv("PI_COMPLETION_AUTO_RESUME_CAPTURE_PATH");
	const promptSnapshotPath = requiredEnv("PI_COMPLETION_AUTO_RESUME_PROMPT_PATH");
	const resumePrompt = process.env.PI_COMPLETION_AUTO_RESUME_PROMPT?.trim() || "AUTO-RESUME-REGRESSION queued from agent_end.";
	const transformedPrompt = process.env.PI_COMPLETION_AUTO_RESUME_TRANSFORMED_PROMPT?.trim() || "ok";
	let seeded = false;
	let agentEndCount = 0;

	const seedState = async (): Promise<void> => {
		if (seeded) return;
		seeded = true;
		await fsp.mkdir(root, { recursive: true });
		await scaffoldCompletionFiles(root, "Exercise agent_end auto-resume followUp delivery.");
	};

	const maybeWriteTestSnapshot = (targetPath: string | undefined, content: string): void => {
		if (!targetPath) return;
		fs.mkdirSync(path.dirname(targetPath), { recursive: true });
		fs.writeFileSync(targetPath, content, "utf8");
	};

	const deps = {
		getCtxCwd: (ctx: { cwd: string }) => ctx.cwd,
		emitCommandText: () => {},
		completionRootKey,
		hasRunningCompletionRole: () => false,
		completionResumePrompt: () => resumePrompt,
		completionTestAutoContinuePromptPath: () => promptSnapshotPath,
		maybeWriteTestSnapshot,
		shouldSkipDriverKickoffForTests: () => false,
	};

	pi.on("session_start", async () => {
		await seedState();
	});

	pi.on("before_agent_start", async (event) => ({
		systemPrompt:
			`${event.systemPrompt}\n\nTEST HARNESS INSTRUCTIONS:\n- Reply with the single word ok.\n- Do not call any tools.\n- Do not ask follow-up questions.`,
	}));

	pi.on("input", async (event, ctx) => {
		if (event.source !== "extension" || event.text !== resumePrompt) return { action: "continue" as const };
		await writeJson(capturePath, {
			text: event.text,
			source: event.source,
			streamingBehavior: event.streamingBehavior ?? null,
			isIdle: ctx.isIdle(),
			hasPendingMessages: ctx.hasPendingMessages(),
		});
		// Transform instead of handling so prompt() still reaches the streaming-state
		// queue path. Without deliverAs, the old implementation would throw here.
		return { action: "transform" as const, text: transformedPrompt };
	});

	pi.on("agent_end", async (_event, ctx) => {
		agentEndCount += 1;
		if (agentEndCount !== 1) return;
		await seedState();
		await autoContinueWorkflowIfNeeded(pi, ctx, deps);
	});
}
