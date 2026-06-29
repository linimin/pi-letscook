/**
 * Regression fixture for stale completion driver follow-up suppression after /cook park/cancel.
 *
 * After the workflow is closed for driver continuation, this fixture queues a previously
 * authored COMPLETION WORKFLOW DRIVER follow-up and records whether that prompt still
 * reaches the agent input path.
 */
import * as fs from "node:fs";
import * as path from "node:path";
import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";

function requiredEnv(name: string): string {
	const value = process.env[name]?.trim();
	if (!value) throw new Error(`Missing required environment variable: ${name}`);
	return value;
}

function optionalEnv(name: string): string | undefined {
	const value = process.env[name]?.trim();
	return value || undefined;
}

function writeCapture(targetPath: string | undefined, content: string): void {
	if (!targetPath) return;
	fs.mkdirSync(path.dirname(targetPath), { recursive: true });
	fs.writeFileSync(targetPath, content, "utf8");
}

export default function (pi: ExtensionAPI) {
	const stalePrompt = requiredEnv("PI_COMPLETION_TEST_STALE_DRIVER_PROMPT");
	const agentPromptCapturePath = optionalEnv("PI_COMPLETION_TEST_STALE_DRIVER_AGENT_PROMPT_CAPTURE_PATH");
	const inputLeakCapturePath = optionalEnv("PI_COMPLETION_TEST_STALE_DRIVER_INPUT_LEAK_CAPTURE_PATH");
	let queuedStaleFollowUp = false;

	pi.on("input", async (event) => {
		if (event.source !== "extension" || event.text !== stalePrompt) return;
		writeCapture(inputLeakCapturePath, event.text);
	});

	pi.on("before_agent_start", async (event) => {
		const prompt = typeof event.prompt === "string" ? event.prompt : "";
		if (!/^COMPLETION WORKFLOW DRIVER\b/m.test(prompt)) return;
		writeCapture(agentPromptCapturePath, prompt);
	});

	pi.on("agent_end", async () => {
		if (queuedStaleFollowUp) return;
		queuedStaleFollowUp = true;
		pi.sendUserMessage(stalePrompt, { deliverAs: "followUp" });
	});
}
