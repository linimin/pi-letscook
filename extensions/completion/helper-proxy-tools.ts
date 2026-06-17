import * as fs from "node:fs";
import { promises as fsp } from "node:fs";
import * as path from "node:path";
import { HELPER_PROXY_TOOL_NAMES, utf8Length } from "./helper-types.ts";

const READ_DEFAULT_LIMIT = 120;
const READ_MAX_LIMIT = 200;
const READ_MAX_BYTES = 24 * 1024;
const GREP_DEFAULT_MAX_MATCHES = 40;
const GREP_MAX_MATCHES = 80;
const GREP_MAX_BYTES = 24 * 1024;
const GREP_LINE_PREVIEW_MAX_BYTES = 240;
const FIND_DEFAULT_MAX_RESULTS = 100;
const FIND_MAX_RESULTS = 200;
const LS_DEFAULT_MAX_RESULTS = 100;
const LS_MAX_RESULTS = 200;

type HelperToolEnv = NodeJS.ProcessEnv;

type HelperBoundaryContext = {
	rootRealpath: string;
	cwdRealpath: string;
};

type HelperFindResultType = "file" | "dir" | "any";

type TypeBuilderLike = {
	Object: (properties: Record<string, unknown>, options?: Record<string, unknown>) => unknown;
	String: (options?: Record<string, unknown>) => unknown;
	Number: (options?: Record<string, unknown>) => unknown;
	Optional: (schema: unknown) => unknown;
	Union: (items: unknown[], options?: Record<string, unknown>) => unknown;
	Literal: (value: string, options?: Record<string, unknown>) => unknown;
};

class HelperProxyToolError extends Error {
	constructor(message: string) {
		super(message);
		this.name = "HelperProxyToolError";
	}
}

function normalizePathForOutput(value: string): string {
	return value.split(path.sep).join("/");
}

function isPathInside(root: string, candidate: string): boolean {
	return candidate === root || candidate.startsWith(`${root}${path.sep}`);
}

function truncateUtf8(value: string, maxBytes: number): string {
	if (utf8Length(value) <= maxBytes) return value;
	let result = "";
	let usedBytes = 0;
	for (const chunk of value) {
		const chunkBytes = utf8Length(chunk);
		if (usedBytes + chunkBytes > maxBytes) break;
		result += chunk;
		usedBytes += chunkBytes;
	}
	return result;
}

function asNonEmptyString(value: unknown, fieldName: string): string {
	if (typeof value !== "string" || value.trim().length === 0) {
		throw new HelperProxyToolError(`${fieldName} must be a non-empty string`);
	}
	return value.trim();
}

function asPositiveInteger(value: unknown, fieldName: string, defaultValue: number, maxValue: number): number {
	if (value === undefined) return defaultValue;
	if (typeof value !== "number" || !Number.isFinite(value)) {
		throw new HelperProxyToolError(`${fieldName} must be a finite number`);
	}
	const rounded = Math.max(1, Math.floor(value));
	return Math.min(rounded, maxValue);
}

function normalizeRepoRelativePath(rawPath: string, fieldName: string): string {
	if (rawPath.includes("\0")) throw new HelperProxyToolError(`${fieldName} must not contain NUL bytes`);
	if (path.isAbsolute(rawPath)) throw new HelperProxyToolError(`${fieldName} must be repo-relative, not absolute`);
	const normalized = path.posix.normalize(rawPath.replace(/\\/g, "/"));
	if (normalized === ".." || normalized.startsWith("../")) {
		throw new HelperProxyToolError(`${fieldName} must not escape the repo root with parent segments`);
	}
	if (normalized.startsWith("/")) {
		throw new HelperProxyToolError(`${fieldName} must be repo-relative, not absolute`);
	}
	if (normalized === ".") return ".";
	return normalized.replace(/^\.\//, "");
}

async function resolveHelperBoundaryContext(env: HelperToolEnv = process.env): Promise<HelperBoundaryContext> {
	const rawRoot = env.PI_COMPLETION_HELPER_ROOT?.trim();
	if (!rawRoot) throw new HelperProxyToolError("missing PI_COMPLETION_HELPER_ROOT boundary env");
	const rootRealpath = await fsp.realpath(rawRoot).catch(() => undefined);
	if (!rootRealpath) throw new HelperProxyToolError("PI_COMPLETION_HELPER_ROOT must resolve to an existing repo root");
	const rawCwd = env.PI_COMPLETION_HELPER_CWD?.trim();
	const cwdRealpath = rawCwd ? await fsp.realpath(rawCwd).catch(() => undefined) : rootRealpath;
	if (!cwdRealpath) throw new HelperProxyToolError("PI_COMPLETION_HELPER_CWD must resolve to an existing directory when provided");
	if (!isPathInside(rootRealpath, cwdRealpath)) {
		throw new HelperProxyToolError("PI_COMPLETION_HELPER_CWD must stay inside PI_COMPLETION_HELPER_ROOT");
	}
	const cwdStat = await fsp.stat(cwdRealpath).catch(() => undefined);
	if (!cwdStat?.isDirectory()) throw new HelperProxyToolError("PI_COMPLETION_HELPER_CWD must resolve to a directory");
	return { rootRealpath, cwdRealpath };
}

async function resolveExistingTarget(
	boundary: HelperBoundaryContext,
	relativePath: string,
	expectedType?: "file" | "dir",
): Promise<{ absolutePath: string; repoRelativePath: string; stat: fs.Stats; realpath: string }> {
	const absolutePath = path.resolve(boundary.rootRealpath, relativePath === "." ? "." : relativePath);
	if (!isPathInside(boundary.rootRealpath, absolutePath)) {
		throw new HelperProxyToolError("path escapes the repo root");
	}
	const stat = await fsp.lstat(absolutePath).catch(() => undefined);
	if (!stat) throw new HelperProxyToolError(`path does not exist: ${relativePath}`);
	const realpath = await fsp.realpath(absolutePath).catch(() => undefined);
	if (!realpath || !isPathInside(boundary.rootRealpath, realpath)) {
		throw new HelperProxyToolError(`path escapes the repo root via symlink or realpath: ${relativePath}`);
	}
	const resolvedStat = stat.isSymbolicLink()
		? await fsp.stat(absolutePath).catch(() => undefined)
		: stat;
	if (!resolvedStat) throw new HelperProxyToolError(`path could not be resolved: ${relativePath}`);
	if (expectedType === "file" && !resolvedStat.isFile()) {
		throw new HelperProxyToolError(`path must resolve to a file: ${relativePath}`);
	}
	if (expectedType === "dir" && !resolvedStat.isDirectory()) {
		throw new HelperProxyToolError(`path must resolve to a directory: ${relativePath}`);
	}
	return {
		absolutePath,
		realpath,
		repoRelativePath: relativePath === "." ? "." : normalizePathForOutput(path.relative(boundary.rootRealpath, absolutePath)),
		stat: resolvedStat,
	};
}

function isProbablyTextBuffer(buffer: Buffer): boolean {
	if (buffer.includes(0)) return false;
	const sample = buffer.subarray(0, Math.min(buffer.length, 1024));
	let suspicious = 0;
	for (const byte of sample) {
		if (byte === 9 || byte === 10 || byte === 13) continue;
		if (byte < 32 || byte === 127) suspicious += 1;
	}
	return suspicious <= Math.max(4, Math.floor(sample.length * 0.15));
}

function contentLines(text: string): string[] {
	if (text.length === 0) return [];
	const lines = text.split(/\r?\n/);
	if (lines[lines.length - 1] === "") lines.pop();
	return lines;
}

async function readTextFile(boundary: HelperBoundaryContext, relativePath: string): Promise<{ repoRelativePath: string; text: string }> {
	const target = await resolveExistingTarget(boundary, relativePath, "file");
	const buffer = await fsp.readFile(target.absolutePath);
	if (!isProbablyTextBuffer(buffer)) {
		throw new HelperProxyToolError(`path is not a text file: ${relativePath}`);
	}
	return {
		repoRelativePath: target.repoRelativePath,
		text: buffer.toString("utf8"),
	};
}

function linePreview(line: string): string {
	return truncateUtf8(line, GREP_LINE_PREVIEW_MAX_BYTES);
}

async function classifyPath(boundary: HelperBoundaryContext, absolutePath: string): Promise<{
	type: "file" | "dir" | "other";
	insideRoot: boolean;
	followDirectory: boolean;
}> {
	const stat = await fsp.lstat(absolutePath).catch(() => undefined);
	if (!stat) return { type: "other", insideRoot: false, followDirectory: false };
	if (!stat.isSymbolicLink()) {
		if (stat.isFile()) return { type: "file", insideRoot: true, followDirectory: false };
		if (stat.isDirectory()) return { type: "dir", insideRoot: true, followDirectory: true };
		return { type: "other", insideRoot: true, followDirectory: false };
	}
	const realpath = await fsp.realpath(absolutePath).catch(() => undefined);
	if (!realpath || !isPathInside(boundary.rootRealpath, realpath)) {
		return { type: "other", insideRoot: false, followDirectory: false };
	}
	const resolvedStat = await fsp.stat(absolutePath).catch(() => undefined);
	if (!resolvedStat) return { type: "other", insideRoot: false, followDirectory: false };
	if (resolvedStat.isFile()) return { type: "file", insideRoot: true, followDirectory: false };
	if (resolvedStat.isDirectory()) return { type: "dir", insideRoot: true, followDirectory: false };
	return { type: "other", insideRoot: true, followDirectory: false };
}

async function walkRepoFiles(boundary: HelperBoundaryContext, baseRelativePath: string): Promise<Array<{ absolutePath: string; repoRelativePath: string }>> {
	const base = await resolveExistingTarget(boundary, baseRelativePath, undefined);
	if (base.stat.isFile()) {
		return [{ absolutePath: base.absolutePath, repoRelativePath: base.repoRelativePath }];
	}
	if (!base.stat.isDirectory()) {
		throw new HelperProxyToolError(`path must resolve to a file or directory: ${baseRelativePath}`);
	}
	const files: Array<{ absolutePath: string; repoRelativePath: string }> = [];
	const queue: Array<{ absolutePath: string; repoRelativePath: string }> = [{
		absolutePath: base.absolutePath,
		repoRelativePath: base.repoRelativePath,
	}];
	while (queue.length > 0) {
		const current = queue.shift()!;
		const names = (await fsp.readdir(current.absolutePath)).sort((left, right) => left.localeCompare(right));
		for (const name of names) {
			const absolutePath = path.join(current.absolutePath, name);
			const repoRelativePath = current.repoRelativePath === "."
				? normalizePathForOutput(name)
				: `${current.repoRelativePath}/${normalizePathForOutput(name)}`;
			const classification = await classifyPath(boundary, absolutePath);
			if (!classification.insideRoot) continue;
			if (classification.type === "file") {
				files.push({ absolutePath, repoRelativePath });
				continue;
			}
			if (classification.type === "dir" && classification.followDirectory) {
				queue.push({ absolutePath, repoRelativePath });
			}
		}
	}
	files.sort((left, right) => left.repoRelativePath.localeCompare(right.repoRelativePath));
	return files;
}

function toolSuccessResult(payload: Record<string, unknown>) {
	return {
		content: [{ type: "text", text: JSON.stringify(payload) }],
		details: payload,
	};
}

function toolFailureResult(error: unknown) {
	const message = error instanceof Error ? error.message : "helper proxy tool failed";
	const payload = { ok: false, error: message };
	return {
		content: [{ type: "text", text: JSON.stringify(payload) }],
		details: payload,
		isError: true,
	};
}

export async function executeHelperRead(
	params: { path: string; offset?: number; limit?: number },
	env: HelperToolEnv = process.env,
): Promise<{ path: string; startLine: number; endLine: number; truncated: boolean; content: string }> {
	const boundary = await resolveHelperBoundaryContext(env);
	const relativePath = normalizeRepoRelativePath(asNonEmptyString(params.path, "path"), "path");
	const offset = asPositiveInteger(params.offset, "offset", 1, Number.MAX_SAFE_INTEGER);
	const limit = asPositiveInteger(params.limit, "limit", READ_DEFAULT_LIMIT, READ_MAX_LIMIT);
	const file = await readTextFile(boundary, relativePath);
	const lines = contentLines(file.text);
	const startIndex = Math.max(0, offset - 1);
	const selectedLines = lines.slice(startIndex, startIndex + limit);
	let content = selectedLines.join("\n");
	let truncated = startIndex + limit < lines.length;
	if (utf8Length(content) > READ_MAX_BYTES) {
		content = truncateUtf8(content, READ_MAX_BYTES);
		truncated = true;
	}
	return {
		path: file.repoRelativePath,
		startLine: selectedLines.length === 0 ? 0 : startIndex + 1,
		endLine: selectedLines.length === 0 ? 0 : startIndex + selectedLines.length,
		truncated,
		content,
	};
}

export async function executeHelperGrep(
	params: { pattern: string; path?: string; maxMatches?: number },
	env: HelperToolEnv = process.env,
): Promise<{ basePath: string; truncated: boolean; matches: Array<{ path: string; line: number; text: string }> }> {
	const boundary = await resolveHelperBoundaryContext(env);
	const pattern = asNonEmptyString(params.pattern, "pattern");
	const basePath = normalizeRepoRelativePath(params.path?.trim() || ".", "path");
	const maxMatches = asPositiveInteger(params.maxMatches, "maxMatches", GREP_DEFAULT_MAX_MATCHES, GREP_MAX_MATCHES);
	const files = await walkRepoFiles(boundary, basePath);
	const matches: Array<{ path: string; line: number; text: string }> = [];
	let truncated = false;
	for (const file of files) {
		const buffer = await fsp.readFile(file.absolutePath).catch(() => undefined);
		if (!buffer || !isProbablyTextBuffer(buffer)) continue;
		const text = buffer.toString("utf8");
		const lines = contentLines(text);
		for (let index = 0; index < lines.length; index += 1) {
			if (!lines[index]?.includes(pattern)) continue;
			matches.push({
				path: file.repoRelativePath,
				line: index + 1,
				text: linePreview(lines[index] ?? ""),
			});
			if (matches.length >= maxMatches) {
				truncated = true;
				break;
			}
		}
		if (truncated) break;
	}
	matches.sort((left, right) => left.path.localeCompare(right.path) || left.line - right.line);
	const payload = {
		basePath,
		truncated,
		matches,
	};
	while (payload.matches.length > 0 && utf8Length(JSON.stringify(payload)) > GREP_MAX_BYTES) {
		payload.matches.pop();
		payload.truncated = true;
	}
	return payload;
}

export async function executeHelperFind(
	params: { path?: string; nameIncludes?: string; type?: HelperFindResultType; maxResults?: number },
	env: HelperToolEnv = process.env,
): Promise<{ basePath: string; truncated: boolean; results: Array<{ path: string; type: "file" | "dir" }> }> {
	const boundary = await resolveHelperBoundaryContext(env);
	const basePath = normalizeRepoRelativePath(params.path?.trim() || ".", "path");
	const nameIncludes = typeof params.nameIncludes === "string" && params.nameIncludes.length > 0 ? params.nameIncludes : undefined;
	const type = params.type === "file" || params.type === "dir" || params.type === "any" ? params.type : "any";
	const maxResults = asPositiveInteger(params.maxResults, "maxResults", FIND_DEFAULT_MAX_RESULTS, FIND_MAX_RESULTS);
	const base = await resolveExistingTarget(boundary, basePath, "dir");
	const results: Array<{ path: string; type: "file" | "dir" }> = [];
	const queue: Array<{ absolutePath: string; repoRelativePath: string }> = [{ absolutePath: base.absolutePath, repoRelativePath: base.repoRelativePath }];
	let truncated = false;
	while (queue.length > 0 && !truncated) {
		const current = queue.shift()!;
		const names = (await fsp.readdir(current.absolutePath)).sort((left, right) => left.localeCompare(right));
		for (const name of names) {
			const absolutePath = path.join(current.absolutePath, name);
			const repoRelativePath = current.repoRelativePath === "."
				? normalizePathForOutput(name)
				: `${current.repoRelativePath}/${normalizePathForOutput(name)}`;
			const classification = await classifyPath(boundary, absolutePath);
			if (!classification.insideRoot || classification.type === "other") continue;
			const resultType = classification.type;
			const matchesFilter = (!nameIncludes || name.includes(nameIncludes)) && (type === "any" || type === resultType);
			if (matchesFilter) {
				results.push({ path: repoRelativePath, type: resultType });
				if (results.length >= maxResults) {
					truncated = true;
					break;
				}
			}
			if (classification.type === "dir" && classification.followDirectory) {
				queue.push({ absolutePath, repoRelativePath });
			}
		}
	}
	results.sort((left, right) => left.path.localeCompare(right.path));
	return { basePath, truncated, results };
}

export async function executeHelperLs(
	params: { path?: string; maxResults?: number },
	env: HelperToolEnv = process.env,
): Promise<{ path: string; truncated: boolean; entries: Array<{ name: string; path: string; type: "file" | "dir" }> }> {
	const boundary = await resolveHelperBoundaryContext(env);
	const relativePath = normalizeRepoRelativePath(params.path?.trim() || ".", "path");
	const maxResults = asPositiveInteger(params.maxResults, "maxResults", LS_DEFAULT_MAX_RESULTS, LS_MAX_RESULTS);
	const target = await resolveExistingTarget(boundary, relativePath, "dir");
	const names = (await fsp.readdir(target.absolutePath)).sort((left, right) => left.localeCompare(right));
	const entries: Array<{ name: string; path: string; type: "file" | "dir" }> = [];
	let truncated = false;
	for (const name of names) {
		const absolutePath = path.join(target.absolutePath, name);
		const repoRelativePath = relativePath === "."
			? normalizePathForOutput(name)
			: `${relativePath}/${normalizePathForOutput(name)}`;
		const classification = await classifyPath(boundary, absolutePath);
		if (!classification.insideRoot || classification.type === "other") continue;
		entries.push({ name, path: repoRelativePath, type: classification.type });
		if (entries.length >= maxResults) {
			truncated = true;
			break;
		}
	}
	return {
		path: relativePath,
		truncated,
		entries,
	};
}

export function buildHelperProxyToolDefinitions(Type: TypeBuilderLike) {
	const readSchema = Type.Object(
		{
			path: Type.String({ description: "Repo-relative text file path." }),
			offset: Type.Optional(Type.Number({ description: "1-indexed start line. Default 1." })),
			limit: Type.Optional(Type.Number({ description: `Max lines to return. Default ${READ_DEFAULT_LIMIT}; max ${READ_MAX_LIMIT}.` })),
		},
		{ additionalProperties: false },
	);
	const grepSchema = Type.Object(
		{
			pattern: Type.String({ description: "Literal case-sensitive substring to search for." }),
			path: Type.Optional(Type.String({ description: "Optional repo-relative file or directory path. Defaults to ." })),
			maxMatches: Type.Optional(Type.Number({ description: `Default ${GREP_DEFAULT_MAX_MATCHES}; max ${GREP_MAX_MATCHES}.` })),
		},
		{ additionalProperties: false },
	);
	const findSchema = Type.Object(
		{
			path: Type.Optional(Type.String({ description: "Optional repo-relative directory path. Defaults to ." })),
			nameIncludes: Type.Optional(Type.String({ description: "Optional case-sensitive basename substring filter." })),
			type: Type.Optional(
				Type.Union([
					Type.Literal("file"),
					Type.Literal("dir"),
					Type.Literal("any"),
				], { description: 'Optional result-type filter. Defaults to "any".' }),
			),
			maxResults: Type.Optional(Type.Number({ description: `Default ${FIND_DEFAULT_MAX_RESULTS}; max ${FIND_MAX_RESULTS}.` })),
		},
		{ additionalProperties: false },
	);
	const lsSchema = Type.Object(
		{
			path: Type.Optional(Type.String({ description: "Optional repo-relative directory path. Defaults to ." })),
			maxResults: Type.Optional(Type.Number({ description: `Default ${LS_DEFAULT_MAX_RESULTS}; max ${LS_MAX_RESULTS}.` })),
		},
		{ additionalProperties: false },
	);

	return [
		{
			name: HELPER_PROXY_TOOL_NAMES[0],
			label: "Completion Helper Read",
			description: "Read a repo-bounded text file for internal helper subprocesses.",
			promptSnippet: "Read a repo-relative text file inside the helper boundary.",
			promptGuidelines: [
				"Use only repo-relative paths.",
				"Do not expect this tool to follow parent-path, absolute-path, or outside-root symlink escapes.",
			],
			parameters: readSchema,
			async execute(_toolCallId: string, params: { path: string; offset?: number; limit?: number }) {
				try {
					return toolSuccessResult(await executeHelperRead(params));
				} catch (error) {
					return toolFailureResult(error);
				}
			},
		},
		{
			name: HELPER_PROXY_TOOL_NAMES[1],
			label: "Completion Helper Grep",
			description: "Literal substring search across repo-bounded text files for internal helper subprocesses.",
			promptSnippet: "Search repo-relative text files inside the helper boundary.",
			promptGuidelines: [
				"Pattern matching is literal and case-sensitive in V1.",
				"Use repo-relative paths only.",
			],
			parameters: grepSchema,
			async execute(_toolCallId: string, params: { pattern: string; path?: string; maxMatches?: number }) {
				try {
					return toolSuccessResult(await executeHelperGrep(params));
				} catch (error) {
					return toolFailureResult(error);
				}
			},
		},
		{
			name: HELPER_PROXY_TOOL_NAMES[2],
			label: "Completion Helper Find",
			description: "Find repo-bounded files or directories for internal helper subprocesses.",
			promptSnippet: "Find repo-relative files or directories inside the helper boundary.",
			promptGuidelines: [
				"Find is recursive inside the repo root only.",
				"Do not expect outside-root symlinks to appear or be traversed.",
			],
			parameters: findSchema,
			async execute(
				_toolCallId: string,
				params: { path?: string; nameIncludes?: string; type?: HelperFindResultType; maxResults?: number },
			) {
				try {
					return toolSuccessResult(await executeHelperFind(params));
				} catch (error) {
					return toolFailureResult(error);
				}
			},
		},
		{
			name: HELPER_PROXY_TOOL_NAMES[3],
			label: "Completion Helper Ls",
			description: "List a repo-bounded directory for internal helper subprocesses.",
			promptSnippet: "List a repo-relative directory inside the helper boundary.",
			promptGuidelines: [
				"Ls is non-recursive in V1.",
				"Do not expect outside-root symlinks to appear in the result.",
			],
			parameters: lsSchema,
			async execute(_toolCallId: string, params: { path?: string; maxResults?: number }) {
				try {
					return toolSuccessResult(await executeHelperLs(params));
				} catch (error) {
					return toolFailureResult(error);
				}
			},
		},
	];
}
