#!/usr/bin/env node
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";
import { getConfigSummary } from "./config.js";
import { analyzeSignalTrends, generateDailyBrief, scanPersonaInboxes } from "./intelligence.js";
import { listAccounts } from "./mail.js";

const server = new McpServer({
  name: "apple-mail-intelligence",
  version: "1.0.0",
});

function jsonResponse(value: unknown) {
  return { content: [{ type: "text" as const, text: JSON.stringify(value, null, 2) }] };
}

function errorResponse(error: unknown) {
  return {
    content: [{ type: "text" as const, text: `Error: ${(error as Error).message}` }],
    isError: true,
  };
}

server.registerTool(
  "discover_mail_accounts",
  {
    description:
      "List Apple Mail account object names and their configured email addresses so persona config can be aligned to the local Mail setup.",
    inputSchema: z.object({}),
  },
  async () => {
    try {
      return jsonResponse(await listAccounts());
    } catch (error) {
      return errorResponse(error);
    }
  }
);

server.registerTool(
  "get_persona_map",
  {
    description: "Return the configured three-persona inbox map, note output settings, and domain taxonomy.",
    inputSchema: z.object({}),
  },
  async () => {
    try {
      return jsonResponse(getConfigSummary());
    } catch (error) {
      return errorResponse(error);
    }
  }
);

server.registerTool(
  "scan_persona_inboxes",
  {
    description:
      "Read the configured Apple Mail accounts, classify recent messages by persona/domain/lane, and return ranked signals.",
    inputSchema: z.object({
      lookback_days: z.number().int().min(1).max(365).optional().describe("How many days back to scan."),
      limit_per_account: z.number().int().min(1).max(250).optional().describe("Maximum messages to inspect per account."),
      include_snippets: z.boolean().optional().describe("Fetch message content snippets for richer summaries."),
    }),
  },
  async ({ lookback_days, limit_per_account, include_snippets }) => {
    try {
      return jsonResponse(
        await scanPersonaInboxes({
          lookbackDays: lookback_days,
          limitPerAccount: limit_per_account,
          includeSnippets: include_snippets,
        })
      );
    } catch (error) {
      return errorResponse(error);
    }
  }
);

server.registerTool(
  "analyze_signal_trends",
  {
    description:
      "Compare cumulative signal distributions over multiple time windows such as 30, 60, and 90 days.",
    inputSchema: z.object({
      windows: z.array(z.number().int().min(1).max(365)).optional().describe("Time windows in days, for example [30, 60, 90]."),
      limit_per_account: z.number().int().min(1).max(250).optional().describe("Maximum messages to inspect per account for each window."),
    }),
  },
  async ({ windows, limit_per_account }) => {
    try {
      return jsonResponse(
        await analyzeSignalTrends({
          windows,
          limitPerAccount: limit_per_account,
        })
      );
    } catch (error) {
      return errorResponse(error);
    }
  }
);

server.registerTool(
  "generate_daily_brief",
  {
    description:
      "Generate a Superhuman-style Daily Intel brief from the configured inbox personas and optionally save it to Apple Notes.",
    inputSchema: z.object({
      lookback_days: z.number().int().min(1).max(30).optional().describe("How many recent days to include in the brief."),
      limit_per_account: z.number().int().min(1).max(100).optional().describe("Maximum messages to inspect per account."),
      save_to_notes: z.boolean().optional().describe("If true or omitted, write the brief into Apple Notes."),
    }),
  },
  async ({ lookback_days, limit_per_account, save_to_notes }) => {
    try {
      return jsonResponse(
        await generateDailyBrief({
          lookbackDays: lookback_days,
          limitPerAccount: limit_per_account,
          saveToNotes: save_to_notes,
        })
      );
    } catch (error) {
      return errorResponse(error);
    }
  }
);

async function main() {
  const transport = new StdioServerTransport();
  await server.connect(transport);
  console.error("Apple Mail Intelligence MCP server running on stdio");
}

main().catch((error) => {
  console.error("Fatal error:", error);
  process.exit(1);
});
