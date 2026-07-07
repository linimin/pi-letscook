#!/usr/bin/env node
import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { CallToolRequestSchema, ListToolsRequestSchema } from "@modelcontextprotocol/sdk/types.js";
import { handleCookHandoffTool } from "./tools.ts";

const TOOLS = [
	{
		name: "ensure_cook_worktree",
		description: "Create or resolve a dedicated cook git worktree under .worktrees/cook-<slug>/",
		inputSchema: {
			type: "object",
			properties: {
				repo_root: { type: "string", description: "Git repo root (defaults to cwd repo)" },
				branch: { type: "string", description: "Branch name for the cook worktree" },
				slug: { type: "string", description: "Short slug used in .worktrees/cook-<slug>/" },
				base_ref: { type: "string", description: "Base ref for git worktree add (default HEAD)" },
			},
			required: ["slug"],
		},
	},
	{
		name: "prepare_cook_handoff",
		description: "Validate and write cook_handoff JSON + pending sidecar in workspace_root",
		inputSchema: {
			type: "object",
			properties: {
				workspace_root: { type: "string" },
				branch: { type: "string" },
				capsule: { type: "object" },
			},
			required: ["workspace_root", "capsule"],
		},
	},
	{
		name: "preview_cook_handoff_confirmation",
		description: "Return the same startup brief confirmation layout Pi would show",
		inputSchema: {
			type: "object",
			properties: { workspace_root: { type: "string" } },
			required: ["workspace_root"],
		},
	},
	{
		name: "start_cook_workflow",
		description: "Confirm handoff in sidecar and return a Pi /cook launch command for the integrated terminal",
		inputSchema: {
			type: "object",
			properties: {
				workspace_root: { type: "string" },
				confirmation_id: { type: "string" },
				action: { type: "string", enum: ["start", "cancel"] },
				dry_run: { type: "boolean" },
				spawn_mode: {
					type: "string",
					enum: ["agent_terminal", "background"],
					description: "Default agent_terminal returns a command for the IDE terminal; background spawns detached Pi.",
				},
			},
			required: ["workspace_root"],
		},
	},
	{
		name: "validate_cook_handoff",
		description: "Validate a cook_handoff capsule without writing",
		inputSchema: {
			type: "object",
			properties: {
				workspace_root: { type: "string" },
				capsule: { type: "object" },
			},
		},
	},
	{
		name: "get_cook_handoff_status",
		description: "Handoff lifecycle status for workspace_root",
		inputSchema: {
			type: "object",
			properties: { workspace_root: { type: "string" } },
			required: ["workspace_root"],
		},
	},
	{
		name: "get_cook_handoff_schema",
		description: "Canonical cook_handoff schema example and paths",
		inputSchema: { type: "object", properties: {} },
	},
	{
		name: "get_cook_workflow_status",
		description: "Snapshot of active /cook workflow from .agent/current in workspace_root",
		inputSchema: {
			type: "object",
			properties: { workspace_root: { type: "string" } },
			required: ["workspace_root"],
		},
	},
	{
		name: "poll_cook_workflow_updates",
		description: "Poll workflow-events.jsonl deltas for chat monitoring",
		inputSchema: {
			type: "object",
			properties: {
				workspace_root: { type: "string" },
				since_event_id: { type: "string" },
			},
			required: ["workspace_root"],
		},
	},
] as const;

async function main() {
	const server = new Server(
		{ name: "cook-handoff", version: "0.1.0" },
		{ capabilities: { tools: {} } },
	);

	server.setRequestHandler(ListToolsRequestSchema, async () => ({ tools: [...TOOLS] }));
	server.setRequestHandler(CallToolRequestSchema, async (request) => {
		const args = (request.params.arguments ?? {}) as Record<string, unknown>;
		return await handleCookHandoffTool(request.params.name, args);
	});

	const transport = new StdioServerTransport();
	await server.connect(transport);
}

main().catch((error) => {
	console.error(error);
	process.exit(1);
});
