#!/usr/bin/env node
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";
import {
  getCorpusOverview,
  getCorpusSection,
  getMailIntelligenceConfig,
  getReportSection,
  getSource,
  listCorpusSections,
  listReportSections,
  listSources,
  searchCorpus,
} from "./corpus.js";
import { exportLaravelBrainPack, getLaravelBrainBlueprint } from "./laravel.js";

const server = new McpServer({
  name: "knowledge-corpus",
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
  "get_corpus_overview",
  {
    description:
      "Return corpus metadata, the available top-level sections, source counts, and report availability.",
    inputSchema: z.object({}),
  },
  async () => {
    try {
      return jsonResponse(getCorpusOverview());
    } catch (error) {
      return errorResponse(error);
    }
  }
);

server.registerTool(
  "list_corpus_sections",
  {
    description: "List the top-level sections in the structured corpus with lightweight summaries.",
    inputSchema: z.object({}),
  },
  async () => {
    try {
      return jsonResponse(listCorpusSections());
    } catch (error) {
      return errorResponse(error);
    }
  }
);

server.registerTool(
  "get_corpus_section",
  {
    description: "Get a full top-level section from the structured corpus by name.",
    inputSchema: z.object({
      section: z.string().describe("Top-level section name, for example canonical_profile or source_registry."),
    }),
  },
  async ({ section }) => {
    try {
      return jsonResponse(getCorpusSection(section));
    } catch (error) {
      return errorResponse(error);
    }
  }
);

server.registerTool(
  "get_mail_intelligence_config",
  {
    description: "Return the mail-intelligence configuration embedded inside the canonical brain corpus.",
    inputSchema: z.object({}),
  },
  async () => {
    try {
      return jsonResponse(getMailIntelligenceConfig());
    } catch (error) {
      return errorResponse(error);
    }
  }
);

server.registerTool(
  "search_corpus",
  {
    description:
      "Search the structured corpus, the attached research report, or both. Returns ranked snippets and locations.",
    inputSchema: z.object({
      query: z.string().describe("Case-insensitive text to search for."),
      scope: z
        .enum(["corpus", "report", "all"])
        .default("all")
        .describe("Choose whether to search only the structured corpus, only the report, or both."),
      section: z
        .string()
        .optional()
        .describe("Optional top-level corpus section filter. Only applies when searching the structured corpus."),
      limit: z
        .number()
        .int()
        .min(1)
        .max(25)
        .default(10)
        .describe("Maximum number of matches to return."),
    }),
  },
  async ({ query, scope, section, limit }) => {
    try {
      return jsonResponse({
        query,
        scope,
        section: section ?? null,
        results: searchCorpus(query, { scope, section, limit }),
      });
    } catch (error) {
      return errorResponse(error);
    }
  }
);

server.registerTool(
  "get_laravel_brain_blueprint",
  {
    description: "Return a Laravel-ready projection of the canonical brain, including tables, routes, and seed data.",
    inputSchema: z.object({}),
  },
  async () => {
    try {
      return jsonResponse(getLaravelBrainBlueprint());
    } catch (error) {
      return errorResponse(error);
    }
  }
);

server.registerTool(
  "export_laravel_brain_pack",
  {
    description: "Write a Laravel integration pack for the canonical brain into a target directory.",
    inputSchema: z.object({
      target_dir: z.string().describe("Directory where Laravel config, migrations, seeders, controller, and routes should be written."),
    }),
  },
  async ({ target_dir }) => {
    try {
      return jsonResponse(exportLaravelBrainPack(target_dir));
    } catch (error) {
      return errorResponse(error);
    }
  }
);

server.registerTool(
  "list_sources",
  {
    description: "List the sources referenced by the corpus, including ids, URLs, and trust levels.",
    inputSchema: z.object({}),
  },
  async () => {
    try {
      return jsonResponse(listSources());
    } catch (error) {
      return errorResponse(error);
    }
  }
);

server.registerTool(
  "get_source",
  {
    description: "Return a single source entry from source_registry by id.",
    inputSchema: z.object({
      source_id: z.string().describe("Source identifier from source_registry, for example src_aaru_home."),
    }),
  },
  async ({ source_id }) => {
    try {
      return jsonResponse(getSource(source_id));
    } catch (error) {
      return errorResponse(error);
    }
  }
);

server.registerTool(
  "list_report_sections",
  {
    description: "List the markdown report sections that were bundled with the knowledge corpus.",
    inputSchema: z.object({}),
  },
  async () => {
    try {
      return jsonResponse(listReportSections());
    } catch (error) {
      return errorResponse(error);
    }
  }
);

server.registerTool(
  "get_report_section",
  {
    description: "Return a section from the bundled markdown research report by title or slug.",
    inputSchema: z.object({
      title: z.string().describe("Report section title or slug, for example executive-summary."),
    }),
  },
  async ({ title }) => {
    try {
      return jsonResponse(getReportSection(title));
    } catch (error) {
      return errorResponse(error);
    }
  }
);

async function main() {
  const transport = new StdioServerTransport();
  await server.connect(transport);
  console.error("Knowledge Corpus MCP server running on stdio");
}

main().catch((error) => {
  console.error("Fatal error:", error);
  process.exit(1);
});
