import { join } from "node:path";
import { connectToLocalServer, type McpSession } from "./client.js";

// ---------------------------------------------------------------------------
// Server registry
// ---------------------------------------------------------------------------

/** All local MCP servers the pipeline can connect to. */
export type LocalServerName =
  | "knowledge-corpus"
  | "mail-intelligence"
  | "apple-mail"
  | "apple-messages"
  | "apple-notes";

interface ServerDef {
  /** Directory name under repo root. */
  directory: string;
}

const SERVER_DEFS: Record<LocalServerName, ServerDef> = {
  "knowledge-corpus": { directory: "knowledge-corpus" },
  "mail-intelligence": { directory: "mail-intelligence" },
  "apple-mail": { directory: "mail" },
  "apple-messages": { directory: "messages" },
  "apple-notes": { directory: "notes" },
};

// ---------------------------------------------------------------------------
// Script path resolution
// ---------------------------------------------------------------------------

export function serverScriptPath(serverName: LocalServerName, repoRoot: string): string {
  const def = SERVER_DEFS[serverName];
  return join(repoRoot, def.directory, "build", "index.js");
}

// ---------------------------------------------------------------------------
// Connection factory
// ---------------------------------------------------------------------------

/**
 * Connect to a local MCP server by name.
 *
 * Callers are responsible for calling `session.close()` when done.
 * The server process is kept alive for the duration of the session.
 */
export async function connectToServer(
  serverName: LocalServerName,
  repoRoot: string,
  env?: Record<string, string>,
): Promise<McpSession> {
  const scriptPath = serverScriptPath(serverName, repoRoot);
  return connectToLocalServer({ serverName, scriptPath, env });
}

// ---------------------------------------------------------------------------
// Multi-server convenience
// ---------------------------------------------------------------------------

export interface ServerPool {
  sessions: Partial<Record<LocalServerName, McpSession>>;
  get(name: LocalServerName): McpSession;
  closeAll(): Promise<void>;
}

/**
 * Connect to multiple servers in parallel and return a pool.
 * Servers that fail to connect are excluded from the pool and logged.
 * Use `pool.get(name)` to access a session — throws if not connected.
 */
export async function connectServerPool(
  names: LocalServerName[],
  repoRoot: string,
  env?: Record<string, string>,
): Promise<ServerPool> {
  const settled = await Promise.allSettled(
    names.map((name) => connectToServer(name, repoRoot, env).then((s) => ({ name, session: s }))),
  );

  const sessions: Partial<Record<LocalServerName, McpSession>> = {};

  for (const result of settled) {
    if (result.status === "fulfilled") {
      sessions[result.value.name] = result.value.session;
    } else {
      process.stderr.write(`[LocalServers] Failed to connect: ${String(result.reason)}\n`);
    }
  }

  return {
    sessions,
    get(name: LocalServerName): McpSession {
      const session = sessions[name];
      if (!session) {
        throw new Error(`[LocalServers] Server "${name}" is not connected in this pool.`);
      }
      return session;
    },
    async closeAll(): Promise<void> {
      await Promise.allSettled(Object.values(sessions).map((s) => s?.close()));
    },
  };
}
