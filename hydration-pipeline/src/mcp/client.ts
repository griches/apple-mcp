import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StdioClientTransport } from "@modelcontextprotocol/sdk/client/stdio.js";
import { existsSync } from "node:fs";

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

export interface McpContent {
  type: string;
  text?: string;
}

export interface McpToolResult {
  content: McpContent[];
  isError?: boolean;
}

/** A live, connected session to one MCP server process. */
export interface McpSession {
  readonly serverName: string;
  callTool(name: string, args?: Record<string, unknown>): Promise<McpToolResult>;
  close(): Promise<void>;
}

// ---------------------------------------------------------------------------
// Implementation
// ---------------------------------------------------------------------------

class McpSessionImpl implements McpSession {
  readonly serverName: string;
  private readonly client: Client;
  private readonly transport: StdioClientTransport;

  constructor(serverName: string, client: Client, transport: StdioClientTransport) {
    this.serverName = serverName;
    this.client = client;
    this.transport = transport;
  }

  async callTool(name: string, args: Record<string, unknown> = {}): Promise<McpToolResult> {
    const result = await this.client.callTool({ name, arguments: args });
    return result as McpToolResult;
  }

  async close(): Promise<void> {
    await this.transport.close();
  }
}

// ---------------------------------------------------------------------------
// Factory
// ---------------------------------------------------------------------------

export interface ConnectOptions {
  /** Human-readable server name for logging and error messages. */
  serverName: string;
  /** Absolute path to the built server script (build/index.js). */
  scriptPath: string;
  /** Environment variables to pass to the server process. */
  env?: Record<string, string>;
}

/**
 * Spawn a local MCP server as a child process and return a connected session.
 *
 * The server must already be built (build/index.js must exist). Throws if the
 * artifact is missing so callers get a clear error rather than a silent hang.
 */
export async function connectToLocalServer(options: ConnectOptions): Promise<McpSession> {
  const { serverName, scriptPath, env } = options;

  if (!existsSync(scriptPath)) {
    throw new Error(
      `[McpClient] Server artifact not found for "${serverName}": ${scriptPath}\n` +
        `Run "npm run build" inside the server directory first.`,
    );
  }

  const transport = new StdioClientTransport({
    command: "node",
    args: [scriptPath],
    env: env ?? (process.env as Record<string, string>),
  });

  const client = new Client({
    name: "hydration-pipeline",
    version: "0.1.0",
  });

  await client.connect(transport);

  return new McpSessionImpl(serverName, client, transport);
}

// ---------------------------------------------------------------------------
// Convenience helpers
// ---------------------------------------------------------------------------

/**
 * Parse the text content from a tool result into a typed value.
 * Returns null if the result is an error or has no text content.
 */
export function parseToolResult<T>(result: McpToolResult): T | null {
  if (result.isError) return null;
  const textContent = result.content.find((c) => c.type === "text" && c.text !== undefined);
  if (!textContent?.text) return null;
  try {
    return JSON.parse(textContent.text) as T;
  } catch {
    return null;
  }
}

/**
 * Extract raw text from a tool result (for non-JSON responses).
 */
export function extractText(result: McpToolResult): string {
  const textContent = result.content.find((c) => c.type === "text" && c.text !== undefined);
  return textContent?.text ?? "";
}
