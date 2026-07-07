import { spawn } from "node:child_process";
import * as fs from "node:fs";
import * as path from "node:path";
import { shouldParseSubprocessEventLine, shouldRetainSubprocessFinalOutputEvent } from "./subprocess-final-output.ts";
import type { JsonRecord } from "./types";

function asString(value: unknown): string | undefined {
	return typeof value === "string" && value.trim().length > 0 ? value.trim() : undefined;
}

function isRecord(value: unknown): value is JsonRecord {
	return typeof value === "object" && value !== null && !Array.isArray(value);
}

export type RoleSubprocessSpawnSpec = {
	command: string;
	args: string[];
	cwd: string;
	env: NodeJS.ProcessEnv;
	signal?: AbortSignal;
	onStdoutLine?: (line: string) => void;
	onJsonEvent?: (event: JsonRecord, rawLine: string) => void;
};

export type RoleSubprocessSpawnResult = {
	exitCode: number;
	stderr?: string;
	assistantText?: string;
	eventLines: string[];
};

export type RoleRunnerBackend = (spec: RoleSubprocessSpawnSpec) => Promise<RoleSubprocessSpawnResult>;

type RoleSpawnTestOverride = {
	events?: JsonRecord[];
	exitCode?: number;
	stderr?: string;
	assistantText?: string;
	eventLines?: string[];
};

export function roleSpawnTestOverride(): RoleSpawnTestOverride | undefined {
	const raw = asString(process.env.PI_COMPLETION_TEST_ROLE_SPAWN_RESULT_JSON);
	if (!raw) return undefined;
	try {
		const parsed = JSON.parse(raw);
		if (!isRecord(parsed)) return undefined;
		return {
			events: Array.isArray(parsed.events) ? parsed.events.filter(isRecord) : undefined,
			exitCode: typeof parsed.exitCode === "number" && Number.isFinite(parsed.exitCode) ? parsed.exitCode : undefined,
			stderr: asString(parsed.stderr),
			assistantText: typeof parsed.assistantText === "string" ? parsed.assistantText : undefined,
			eventLines: Array.isArray(parsed.eventLines)
				? parsed.eventLines.filter((line): line is string => typeof line === "string")
				: undefined,
		};
	} catch {
		return undefined;
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

export async function defaultPiRoleRunner(spec: RoleSubprocessSpawnSpec): Promise<RoleSubprocessSpawnResult> {
	const testOverride = roleSpawnTestOverride();
	if (testOverride) {
		const eventLines: string[] = [];
		let assistantText = testOverride.assistantText;
		for (const event of testOverride.events ?? []) {
			const rawLine = JSON.stringify(event);
			spec.onStdoutLine?.(rawLine);
			spec.onJsonEvent?.(event, rawLine);
			if (shouldRetainSubprocessFinalOutputEvent(event)) eventLines.push(rawLine);
		}
		if (testOverride.eventLines?.length) {
			for (const line of testOverride.eventLines) {
				if (!eventLines.includes(line)) eventLines.push(line);
			}
		}
		return {
			exitCode: testOverride.exitCode ?? 0,
			stderr: testOverride.stderr,
			assistantText,
			eventLines,
		};
	}

	return await new Promise<RoleSubprocessSpawnResult>((resolve) => {
		const proc = spawn(spec.command, spec.args, {
			cwd: spec.cwd,
			env: spec.env,
			stdio: ["ignore", "pipe", "pipe"],
			shell: false,
		});
		let buffer = "";
		let stderr = "";
		const eventLines: string[] = [];
		let assistantText: string | undefined;

		const processLine = (line: string) => {
			if (!line.trim()) return;
			spec.onStdoutLine?.(line);
			if (!shouldParseSubprocessEventLine(line)) return;
			try {
				const event = JSON.parse(line) as JsonRecord;
				if (shouldRetainSubprocessFinalOutputEvent(event)) eventLines.push(line);
				spec.onJsonEvent?.(event, line);
				if (asString(event.type) === "message_end" && isRecord(event.message)) {
					const content = event.message.content;
					if (Array.isArray(content)) {
						const text = content
							.filter((block): block is { type: string; text?: string } => isRecord(block) && block.type === "text")
							.map((block) => asString(block.text) ?? "")
							.join("")
							.trim();
						if (text) assistantText = text;
					}
				}
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
			resolve({
				exitCode: code ?? 0,
				stderr: stderr.trim() || undefined,
				assistantText,
				eventLines,
			});
		});

		proc.on("error", () => {
			resolve({
				exitCode: 1,
				stderr: stderr.trim() || "spawn failed",
				assistantText,
				eventLines,
			});
		});

		if (spec.signal) {
			const abort = () => proc.kill("SIGTERM");
			if (spec.signal.aborted) abort();
			else spec.signal.addEventListener("abort", abort, { once: true });
		}
	});
}
