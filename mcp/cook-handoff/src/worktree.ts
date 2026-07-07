import { spawnSync } from "node:child_process";
import { realpathSync } from "node:fs";
import { promises as fsp } from "node:fs";
import * as path from "node:path";

export type EnsureCookWorktreeArgs = {
	repoRoot: string;
	branch: string;
	slug: string;
	baseRef?: string;
};

export type EnsureCookWorktreeResult = {
	workspace_root: string;
	branch: string;
	path: string;
	created: boolean;
	repo_root: string;
};

function runGit(cwd: string, args: string[]): { ok: boolean; stdout: string; stderr: string } {
	const result = spawnSync("git", args, { cwd, encoding: "utf8" });
	return {
		ok: result.status === 0,
		stdout: (result.stdout ?? "").trim(),
		stderr: (result.stderr ?? "").trim(),
	};
}

function sanitizeSlug(slug: string): string {
	return slug.trim().toLowerCase().replace(/[^a-z0-9._-]+/g, "-").replace(/^-+|-+$/g, "") || "task";
}

function worktreePath(repoRoot: string, slug: string): string {
	return path.join(repoRoot, ".worktrees", `cook-${sanitizeSlug(slug)}`);
}

function normalizePath(candidate: string): string {
	try {
		return realpathSync.native(candidate);
	} catch {
		return path.resolve(candidate);
	}
}

function isGitWorktreePath(repoRoot: string, candidate: string): boolean {
	const listed = runGit(repoRoot, ["worktree", "list", "--porcelain"]);
	if (!listed.ok) return false;
	const resolved = normalizePath(candidate);
	for (const line of listed.stdout.split("\n")) {
		if (line.startsWith("worktree ")) {
			const listedPath = line.slice("worktree ".length).trim();
			if (normalizePath(listedPath) === resolved) return true;
		}
	}
	return false;
}

export async function ensureCookWorktree(args: EnsureCookWorktreeArgs): Promise<EnsureCookWorktreeResult> {
	const repoRoot = path.resolve(args.repoRoot);
	const branch = args.branch.trim();
	const slug = sanitizeSlug(args.slug);
	const targetPath = worktreePath(repoRoot, slug);
	const baseRef = args.baseRef?.trim() || "HEAD";

	if (!runGit(repoRoot, ["rev-parse", "--is-inside-work-tree"]).ok) {
		throw new Error(`not a git repository: ${repoRoot}`);
	}

	if (isGitWorktreePath(repoRoot, targetPath)) {
		const currentBranch = runGit(targetPath, ["rev-parse", "--abbrev-ref", "HEAD"]);
		if (currentBranch.ok && currentBranch.stdout !== branch) {
			throw new Error(`worktree branch mismatch: expected ${branch}, found ${currentBranch.stdout}`);
		}
		return {
			workspace_root: targetPath,
			branch,
			path: targetPath,
			created: false,
			repo_root: repoRoot,
		};
	}

	try {
		const stat = await fsp.stat(targetPath);
		if (stat.isDirectory()) {
			throw new Error(`refusing to reuse non-worktree path: ${targetPath}`);
		}
	} catch (error) {
		if (!(error instanceof Error) || !("code" in error) || (error as NodeJS.ErrnoException).code !== "ENOENT") {
			throw error;
		}
	}

	await fsp.mkdir(path.dirname(targetPath), { recursive: true });
	const branchExists = runGit(repoRoot, ["show-ref", "--verify", "--quiet", `refs/heads/${branch}`]).ok;
	const add = branchExists
		? runGit(repoRoot, ["worktree", "add", targetPath, branch])
		: runGit(repoRoot, ["worktree", "add", "-b", branch, targetPath, baseRef]);
	if (!add.ok) {
		if (!isGitWorktreePath(repoRoot, targetPath)) {
			await fsp.rm(targetPath, { recursive: true, force: true });
		}
		throw new Error(`git worktree add failed: ${add.stderr || add.stdout}`);
	}

	return {
		workspace_root: targetPath,
		branch,
		path: targetPath,
		created: true,
		repo_root: repoRoot,
	};
}

export function findGitRepoRoot(startCwd: string): string | undefined {
	const result = runGit(path.resolve(startCwd), ["rev-parse", "--show-toplevel"]);
	return result.ok ? path.resolve(result.stdout) : undefined;
}
