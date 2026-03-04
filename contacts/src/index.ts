#!/usr/bin/env node
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";
import * as applescript from "./applescript.js";

const readOnly = process.argv.includes("--read-only");
const confirmDestructive = process.argv.includes("--confirm-destructive");

const server = new McpServer({
  name: "apple-contacts",
  version: "1.0.0",
});

// ---- list_groups ----
server.registerTool(
  "list_groups",
  {
    description: "List all groups in Apple Contacts",
    inputSchema: z.object({}),
  },
  async () => {
    try {
      const groups = await applescript.listGroups();
      return { content: [{ type: "text", text: JSON.stringify(groups, null, 2) }] };
    } catch (err) {
      return { content: [{ type: "text", text: `Error: ${(err as Error).message}` }], isError: true };
    }
  }
);

// ---- list_contacts ----
server.registerTool(
  "list_contacts",
  {
    description: "List all contacts, optionally filtered by group",
    inputSchema: z.object({
      group: z.string().optional().describe("Group name to filter contacts (lists all if omitted)"),
    }),
  },
  async ({ group }) => {
    try {
      const contacts = await applescript.listContacts(group);
      return { content: [{ type: "text", text: JSON.stringify(contacts, null, 2) }] };
    } catch (err) {
      return { content: [{ type: "text", text: `Error: ${(err as Error).message}` }], isError: true };
    }
  }
);

// ---- get_contact ----
server.registerTool(
  "get_contact",
  {
    description: "Get full details of a contact by name including emails, phones, organization, and addresses",
    inputSchema: z.object({
      name: z.string().describe("Full name of the contact to retrieve"),
    }),
  },
  async ({ name }) => {
    try {
      const contact = await applescript.getContact(name);
      return { content: [{ type: "text", text: JSON.stringify(contact, null, 2) }] };
    } catch (err) {
      return { content: [{ type: "text", text: `Error: ${(err as Error).message}` }], isError: true };
    }
  }
);

// ---- search_contacts ----
server.registerTool(
  "search_contacts",
  {
    description: "Search contacts by name",
    inputSchema: z.object({
      query: z.string().describe("Text to search for in contact names"),
    }),
  },
  async ({ query }) => {
    try {
      const results = await applescript.searchContacts(query);
      return { content: [{ type: "text", text: JSON.stringify(results, null, 2) }] };
    } catch (err) {
      return { content: [{ type: "text", text: `Error: ${(err as Error).message}` }], isError: true };
    }
  }
);

// ---- create_contact ----
server.registerTool(
  "create_contact",
  {
    description: "Create a new contact in Apple Contacts",
    inputSchema: z.object({
      first_name: z.string().describe("First name of the contact"),
      last_name: z.string().describe("Last name of the contact"),
      email: z.string().optional().describe("Email address"),
      phone: z.string().optional().describe("Phone number"),
      organization: z.string().optional().describe("Company or organization"),
      job_title: z.string().optional().describe("Job title"),
      note: z.string().optional().describe("Note about the contact"),
    }),
  },
  async ({ first_name, last_name, email, phone, organization, job_title, note }) => {
    try {
      const result = await applescript.createContact(first_name, last_name, {
        email,
        phone,
        organization,
        jobTitle: job_title,
        note,
      });
      return { content: [{ type: "text", text: result }] };
    } catch (err) {
      return { content: [{ type: "text", text: `Error: ${(err as Error).message}` }], isError: true };
    }
  }
);

if (!readOnly) {
  // ---- delete_contact ----
  server.registerTool(
    "delete_contact",
    {
      description: "Delete a contact by name",
      inputSchema: z.object({
        name: z.string().describe("Full name of the contact to delete"),
        ...(confirmDestructive ? { confirm: z.boolean().optional().describe("Set to true to confirm this destructive action") } : {}),
      }),
    },
    async ({ name, confirm }: { name: string; confirm?: unknown }) => {
      if (confirmDestructive && !confirm) {
        return { content: [{ type: "text", text: "This will permanently delete the contact. Please confirm with the user, then call again with confirm: true." }] };
      }
      try {
        const result = await applescript.deleteContact(name);
        return { content: [{ type: "text", text: result }] };
      } catch (err) {
        return { content: [{ type: "text", text: `Error: ${(err as Error).message}` }], isError: true };
      }
    }
  );
}

// ---- create_group ----
server.registerTool(
  "create_group",
  {
    description: "Create a new group in Apple Contacts",
    inputSchema: z.object({
      name: z.string().describe("Name of the group to create"),
    }),
  },
  async ({ name }) => {
    try {
      const result = await applescript.createGroup(name);
      return { content: [{ type: "text", text: result }] };
    } catch (err) {
      return { content: [{ type: "text", text: `Error: ${(err as Error).message}` }], isError: true };
    }
  }
);

// ---- add_contact_to_group ----
server.registerTool(
  "add_contact_to_group",
  {
    description: "Add an existing contact to a group",
    inputSchema: z.object({
      contact_name: z.string().describe("Full name of the contact"),
      group_name: z.string().describe("Name of the group to add the contact to"),
    }),
  },
  async ({ contact_name, group_name }) => {
    try {
      const result = await applescript.addContactToGroup(contact_name, group_name);
      return { content: [{ type: "text", text: result }] };
    } catch (err) {
      return { content: [{ type: "text", text: `Error: ${(err as Error).message}` }], isError: true };
    }
  }
);

// ---- Start server ----
async function main() {
  const transport = new StdioServerTransport();
  await server.connect(transport);
  console.error("Apple Contacts MCP server running on stdio");
}

main().catch((err) => {
  console.error("Fatal error:", err);
  process.exit(1);
});
