import { promises as fsp } from "node:fs";
import * as path from "node:path";
import { extractCookHandoffProposalFromText, type ContextProposal } from "./proposal.ts";
import type { CookProposalDeps } from "./startup-intent.ts";

function asString(value: unknown): string | undefined {
	return typeof value === "string" && value.trim().length > 0 ? value.trim() : undefined;
}

export const DEFAULT_CURSOR_HANDOFF_PATH = ".agent/tmp/cursor-handoff.json";

export function isArchivedCursorHandoffPath(handoffPath: string): boolean {
	const base = path.basename(handoffPath);
	return base.startsWith("cursor-handoff.consumed.") || base.startsWith("cursor-handoff.quarantined.");
}

export function resolveCursorHandoffPath(root: string, explicitPath?: string): string {
	const configured = asString(process.env.PI_COMPLETION_CURSOR_HANDOFF_PATH);
	if (explicitPath && explicitPath !== "default") {
		return path.isAbsolute(explicitPath) ? explicitPath : path.resolve(root, explicitPath);
	}
	const relative = configured ?? DEFAULT_CURSOR_HANDOFF_PATH;
	return path.resolve(root, relative);
}

export async function readCursorHandoffText(root: string, explicitPath?: string): Promise<string | undefined> {
	const handoffPath = resolveCursorHandoffPath(root, explicitPath);
	try {
		const raw = await fsp.readFile(handoffPath, "utf8");
		return raw.trim() ? raw : undefined;
	} catch {
		return undefined;
	}
}

export function cookHandoffBlockFromJsonText(raw: string): string {
	const trimmed = raw.trim();
	if (trimmed.includes("```cook_handoff")) return trimmed;
	if (trimmed.startsWith("{")) {
		return `\`\`\`cook_handoff\n${trimmed}\n\`\`\``;
	}
	return trimmed;
}

export async function loadCursorHandoffProposal(
	root: string,
	projectName: string,
	deps: CookProposalDeps,
	explicitPath?: string,
): Promise<{ proposal?: ContextProposal; handoffPath: string; error?: string }> {
	const handoffPath = resolveCursorHandoffPath(root, explicitPath);
	if (isArchivedCursorHandoffPath(handoffPath)) {
		return {
			handoffPath,
			error: `Cursor handoff path points to an archived import file and cannot be reused: ${handoffPath}`,
		};
	}
	const raw = await readCursorHandoffText(root, explicitPath);
	if (!raw) {
		return {
			handoffPath,
			error: `Cursor handoff file not found or empty: ${handoffPath}`,
		};
	}
	const block = cookHandoffBlockFromJsonText(raw);
	const proposal = extractCookHandoffProposalFromText(block, projectName, deps, {
		messageId: "cursor-handoff-import",
		timestampMs: Date.now(),
		source: "handoff_capsule",
	});
	if (!proposal) {
		return {
			handoffPath,
			error: `Cursor handoff file is present but not startable: ${handoffPath}`,
		};
	}
	return { proposal, handoffPath };
}

function consumedHandoffPath(handoffPath: string): string {
	const dir = path.dirname(handoffPath);
	return path.join(dir, `cursor-handoff.consumed.${new Date().toISOString().replace(/[:.]/g, "-")}.json`);
}

function quarantinedHandoffPath(handoffPath: string): string {
	const dir = path.dirname(handoffPath);
	return path.join(dir, `cursor-handoff.quarantined.${new Date().toISOString().replace(/[:.]/g, "-")}.json`);
}

export async function consumeCursorHandoffFile(handoffPath: string): Promise<string> {
	const dir = path.dirname(handoffPath);
	await fsp.mkdir(dir, { recursive: true });
	const consumedPath = consumedHandoffPath(handoffPath);
	try {
		await fsp.rename(handoffPath, consumedPath);
		return consumedPath;
	} catch (renameError) {
		try {
			const raw = await fsp.readFile(handoffPath, "utf8");
			await fsp.writeFile(consumedPath, raw, { encoding: "utf8", mode: 0o600 });
			await fsp.unlink(handoffPath);
			return consumedPath;
		} catch (copyError) {
			const renameMessage = renameError instanceof Error ? renameError.message : String(renameError);
			const copyMessage = copyError instanceof Error ? copyError.message : String(copyError);
			throw new Error(
				`failed to consume Cursor handoff at ${handoffPath}: rename failed (${renameMessage}); copy fallback failed (${copyMessage})`,
			);
		}
	}
}

export async function quarantineCursorHandoffFile(handoffPath: string): Promise<string | undefined> {
	try {
		const dir = path.dirname(handoffPath);
		await fsp.mkdir(dir, { recursive: true });
		const quarantinePath = quarantinedHandoffPath(handoffPath);
		try {
			await fsp.rename(handoffPath, quarantinePath);
			return quarantinePath;
		} catch {
			const raw = await fsp.readFile(handoffPath, "utf8");
			await fsp.writeFile(quarantinePath, raw, { encoding: "utf8", mode: 0o600 });
			await fsp.unlink(handoffPath);
			return quarantinePath;
		}
	} catch {
		return undefined;
	}
}
