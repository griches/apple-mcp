#!/usr/bin/env node
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";
import * as applescript from "./applescript.js";

const readOnly = process.argv.includes("--read-only");
const confirmDestructive = process.argv.includes("--confirm-destructive");

const server = new McpServer({
  name: "apple-notes",
  version: "1.0.0",
});

// ---- list_folders ----
server.registerTool(
  "list_folders",
  {
    description: "List all folders in Apple Notes",
    inputSchema: z.object({}),
  },
  async () => {
    try {
      const folders = await applescript.listFolders();
      return { content: [{ type: "text", text: JSON.stringify(folders, null, 2) }] };
    } catch (err) {
      return { content: [{ type: "text", text: `Error: ${(err as Error).message}` }], isError: true };
    }
  }
);

// ---- create_folder ----
server.registerTool(
  "create_folder",
  {
    description: "Create a new folder in Apple Notes",
    inputSchema: z.object({
      name: z.string().describe("Name of the folder to create"),
    }),
  },
  async ({ name }) => {
    try {
      const result = await applescript.createFolder(name);
      return { content: [{ type: "text", text: result }] };
    } catch (err) {
      return { content: [{ type: "text", text: `Error: ${(err as Error).message}` }], isError: true };
    }
  }
);

// ---- list_notes ----
server.registerTool(
  "list_notes",
  {
    description: "List all notes in a specified Apple Notes folder",
    inputSchema: z.object({
      folder: z.string().describe("Name of the folder to list notes from"),
    }),
  },
  async ({ folder }) => {
    try {
      const notes = await applescript.listNotes(folder);
      return { content: [{ type: "text", text: JSON.stringify(notes, null, 2) }] };
    } catch (err) {
      return { content: [{ type: "text", text: `Error: ${(err as Error).message}` }], isError: true };
    }
  }
);

// ---- get_note ----
server.registerTool(
  "get_note",
  {
    description: "Get the full content of a specific note by title",
    inputSchema: z.object({
      title: z.string().describe("Title of the note to retrieve"),
      folder: z.string().optional().describe("Folder to search in (searches all folders if omitted)"),
    }),
  },
  async ({ title, folder }) => {
    try {
      const note = await applescript.getNote(title, folder);
      return { content: [{ type: "text", text: JSON.stringify(note, null, 2) }] };
    } catch (err) {
      return { content: [{ type: "text", text: `Error: ${(err as Error).message}` }], isError: true };
    }
  }
);

// ---- create_note ----
server.registerTool(
  "create_note",
  {
    description: "Create a new note in a specified Apple Notes folder",
    inputSchema: z.object({
      title: z.string().describe("Title of the new note"),
      body: z.string().describe("HTML body content of the note"),
      folder: z.string().describe("Folder to create the note in"),
    }),
  },
  async ({ title, body, folder }) => {
    try {
      const result = await applescript.createNote(title, body, folder);
      return { content: [{ type: "text", text: result }] };
    } catch (err) {
      return { content: [{ type: "text", text: `Error: ${(err as Error).message}` }], isError: true };
    }
  }
);

// ---- update_note ----
server.registerTool(
  "update_note",
  {
    description: "Update the body of an existing note",
    inputSchema: z.object({
      title: z.string().describe("Title of the note to update"),
      body: z.string().describe("New HTML body content for the note"),
      folder: z.string().optional().describe("Folder the note is in (searches all folders if omitted)"),
    }),
  },
  async ({ title, body, folder }) => {
    try {
      const result = await applescript.updateNote(title, body, folder);
      return { content: [{ type: "text", text: result }] };
    } catch (err) {
      return { content: [{ type: "text", text: `Error: ${(err as Error).message}` }], isError: true };
    }
  }
);

if (!readOnly) {
  // ---- delete_note ----
  server.registerTool(
    "delete_note",
    {
      description: "Delete a note from Apple Notes",
      inputSchema: z.object({
        title: z.string().describe("Title of the note to delete"),
        folder: z.string().optional().describe("Folder the note is in (searches all folders if omitted)"),
        ...(confirmDestructive ? { confirm: z.boolean().optional().describe("Set to true to confirm this destructive action") } : {}),
      }),
    },
    async ({ title, folder, confirm }: { title: string; folder?: string; confirm?: unknown }) => {
      if (confirmDestructive && !confirm) {
        return { content: [{ type: "text", text: "This will permanently delete the note. Please confirm with the user, then call again with confirm: true." }] };
      }
      try {
        const result = await applescript.deleteNote(title, folder);
        return { content: [{ type: "text", text: result }] };
      } catch (err) {
        return { content: [{ type: "text", text: `Error: ${(err as Error).message}` }], isError: true };
      }
    }
  );
}

// ---- search_notes ----
server.registerTool(
  "search_notes",
  {
    description: "Search notes by keyword across all folders or within a specific folder",
    inputSchema: z.object({
      query: z.string().describe("Search keyword to match against note titles"),
      folder: z.string().optional().describe("Folder to search in (searches all folders if omitted)"),
    }),
  },
  async ({ query, folder }) => {
    try {
      const results = await applescript.searchNotes(query, folder);
      return { content: [{ type: "text", text: JSON.stringify(results, null, 2) }] };
    } catch (err) {
      return { content: [{ type: "text", text: `Error: ${(err as Error).message}` }], isError: true };
    }
  }
);

// ---- Start server ----
async function main() {
  const transport = new StdioServerTransport();
  await server.connect(transport);
  console.error("Apple Notes MCP server running on stdio");
}

main().catch((err) => {
  console.error("Fatal error:", err);
  process.exit(1);
});
