#!/usr/bin/env node
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";
import * as applescript from "./applescript.js";

const readOnly = process.argv.includes("--read-only");
const confirmDestructive = process.argv.includes("--confirm-destructive");

const server = new McpServer({
  name: "apple-mail",
  version: "1.0.0",
});

// ---- list_mailboxes ----
server.registerTool(
  "list_mailboxes",
  {
    description: "List all mailboxes across all accounts with unread counts",
    inputSchema: z.object({}),
  },
  async () => {
    try {
      const mailboxes = await applescript.listMailboxes();
      return { content: [{ type: "text", text: JSON.stringify(mailboxes, null, 2) }] };
    } catch (err) {
      return { content: [{ type: "text", text: `Error: ${(err as Error).message}` }], isError: true };
    }
  }
);

// ---- list_messages ----
server.registerTool(
  "list_messages",
  {
    description: "List recent messages in a mailbox",
    inputSchema: z.object({
      mailbox: z.string().describe("Name of the mailbox (e.g. 'INBOX')"),
      account: z.string().describe("Name of the email account"),
      limit: z.number().optional().describe("Maximum number of messages to return (default 25)"),
    }),
  },
  async ({ mailbox, account, limit }) => {
    try {
      const messages = await applescript.listMessages(mailbox, account, limit);
      return { content: [{ type: "text", text: JSON.stringify(messages, null, 2) }] };
    } catch (err) {
      return { content: [{ type: "text", text: `Error: ${(err as Error).message}` }], isError: true };
    }
  }
);

// ---- get_message ----
server.registerTool(
  "get_message",
  {
    description: "Get the full content of an email message by ID",
    inputSchema: z.object({
      mailbox: z.string().describe("Name of the mailbox"),
      account: z.string().describe("Name of the email account"),
      message_id: z.number().describe("ID of the message to retrieve"),
    }),
  },
  async ({ mailbox, account, message_id }) => {
    try {
      const message = await applescript.getMessage(mailbox, account, message_id);
      return { content: [{ type: "text", text: JSON.stringify(message, null, 2) }] };
    } catch (err) {
      return { content: [{ type: "text", text: `Error: ${(err as Error).message}` }], isError: true };
    }
  }
);

// ---- search_messages ----
server.registerTool(
  "search_messages",
  {
    description: "Search emails by subject across mailboxes",
    inputSchema: z.object({
      query: z.string().describe("Text to search for in email subjects"),
      mailbox: z.string().optional().describe("Mailbox to search in (searches all if omitted)"),
      account: z.string().optional().describe("Account to search in (required if mailbox is specified)"),
      limit: z.number().optional().describe("Maximum number of results (default 25)"),
    }),
  },
  async ({ query, mailbox, account, limit }) => {
    try {
      const results = await applescript.searchMessages(query, mailbox, account, limit);
      return { content: [{ type: "text", text: JSON.stringify(results, null, 2) }] };
    } catch (err) {
      return { content: [{ type: "text", text: `Error: ${(err as Error).message}` }], isError: true };
    }
  }
);

if (!readOnly) {
  // ---- send_email ----
  server.registerTool(
    "send_email",
    {
      description: "Send an email via Apple Mail",
      inputSchema: z.object({
        to: z.string().describe("Recipient email address"),
        subject: z.string().describe("Email subject"),
        body: z.string().describe("Email body text"),
        cc: z.string().optional().describe("CC recipient email address"),
        bcc: z.string().optional().describe("BCC recipient email address"),
        from_account: z.string().optional().describe("Account to send from (uses default if omitted)"),
        ...(confirmDestructive ? { confirm: z.boolean().optional().describe("Set to true to confirm this destructive action") } : {}),
      }),
    },
    async ({ to, subject, body, cc, bcc, from_account, confirm }: { to: string; subject: string; body: string; cc?: string; bcc?: string; from_account?: string; confirm?: unknown }) => {
      if (confirmDestructive && !confirm) {
        return { content: [{ type: "text", text: "This will send an email to the recipient. Please confirm with the user, then call again with confirm: true." }] };
      }
      try {
        const result = await applescript.sendEmail(to, subject, body, {
          cc,
          bcc,
          from: from_account,
        });
        return { content: [{ type: "text", text: result }] };
      } catch (err) {
        return { content: [{ type: "text", text: `Error: ${(err as Error).message}` }], isError: true };
      }
    }
  );

  // ---- move_message ----
  server.registerTool(
    "move_message",
    {
      description: "Move an email message to a different mailbox",
      inputSchema: z.object({
        message_id: z.number().describe("ID of the message to move"),
        from_mailbox: z.string().describe("Source mailbox name"),
        from_account: z.string().describe("Source account name"),
        to_mailbox: z.string().describe("Destination mailbox name"),
        to_account: z.string().optional().describe("Destination account (same as source if omitted)"),
        ...(confirmDestructive ? { confirm: z.boolean().optional().describe("Set to true to confirm this destructive action") } : {}),
      }),
    },
    async ({ message_id, from_mailbox, from_account, to_mailbox, to_account, confirm }: { message_id: number; from_mailbox: string; from_account: string; to_mailbox: string; to_account?: string; confirm?: unknown }) => {
      if (confirmDestructive && !confirm) {
        return { content: [{ type: "text", text: "This will move the email to a different mailbox. Please confirm with the user, then call again with confirm: true." }] };
      }
      try {
        const result = await applescript.moveMessage(message_id, from_mailbox, from_account, to_mailbox, to_account);
        return { content: [{ type: "text", text: result }] };
      } catch (err) {
        return { content: [{ type: "text", text: `Error: ${(err as Error).message}` }], isError: true };
      }
    }
  );
}

// ---- get_unread_count ----
server.registerTool(
  "get_unread_count",
  {
    description: "Get the unread email count for a mailbox or across all mailboxes",
    inputSchema: z.object({
      mailbox: z.string().optional().describe("Mailbox name (returns total across all if omitted)"),
      account: z.string().optional().describe("Account name (required if mailbox is specified)"),
    }),
  },
  async ({ mailbox, account }) => {
    try {
      const count = await applescript.getUnreadCount(mailbox, account);
      return { content: [{ type: "text", text: JSON.stringify({ unread_count: count }, null, 2) }] };
    } catch (err) {
      return { content: [{ type: "text", text: `Error: ${(err as Error).message}` }], isError: true };
    }
  }
);

// ---- Start server ----
async function main() {
  const transport = new StdioServerTransport();
  await server.connect(transport);
  console.error("Apple Mail MCP server running on stdio");
}

main().catch((err) => {
  console.error("Fatal error:", err);
  process.exit(1);
});
