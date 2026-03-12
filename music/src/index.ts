#!/usr/bin/env node
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";
import * as applescript from "./applescript.js";

const server = new McpServer({
  name: "apple-music",
  version: "1.0.0",
});

// ---- now_playing ----
server.registerTool(
  "now_playing",
  {
    description: "Get the currently playing track and playback state in Apple Music",
    inputSchema: z.object({}),
  },
  async () => {
    try {
      const info = await applescript.getNowPlaying();
      return { content: [{ type: "text", text: JSON.stringify(info, null, 2) }] };
    } catch (err) {
      return { content: [{ type: "text", text: `Error: ${(err as Error).message}` }], isError: true };
    }
  }
);

// ---- play ----
server.registerTool(
  "play",
  {
    description: "Resume or start playback in Apple Music",
    inputSchema: z.object({}),
  },
  async () => {
    try {
      const result = await applescript.play();
      return { content: [{ type: "text", text: result }] };
    } catch (err) {
      return { content: [{ type: "text", text: `Error: ${(err as Error).message}` }], isError: true };
    }
  }
);

// ---- pause ----
server.registerTool(
  "pause",
  {
    description: "Pause playback in Apple Music",
    inputSchema: z.object({}),
  },
  async () => {
    try {
      const result = await applescript.pause();
      return { content: [{ type: "text", text: result }] };
    } catch (err) {
      return { content: [{ type: "text", text: `Error: ${(err as Error).message}` }], isError: true };
    }
  }
);

// ---- next_track ----
server.registerTool(
  "next_track",
  {
    description: "Skip to the next track in Apple Music",
    inputSchema: z.object({}),
  },
  async () => {
    try {
      const result = await applescript.nextTrack();
      return { content: [{ type: "text", text: result }] };
    } catch (err) {
      return { content: [{ type: "text", text: `Error: ${(err as Error).message}` }], isError: true };
    }
  }
);

// ---- previous_track ----
server.registerTool(
  "previous_track",
  {
    description: "Go back to the previous track in Apple Music",
    inputSchema: z.object({}),
  },
  async () => {
    try {
      const result = await applescript.previousTrack();
      return { content: [{ type: "text", text: result }] };
    } catch (err) {
      return { content: [{ type: "text", text: `Error: ${(err as Error).message}` }], isError: true };
    }
  }
);

// ---- set_volume ----
server.registerTool(
  "set_volume",
  {
    description: "Set the volume in Apple Music (0–100)",
    inputSchema: z.object({
      volume: z.number().min(0).max(100).describe("Volume level from 0 (mute) to 100 (max)"),
    }),
  },
  async ({ volume }) => {
    try {
      const result = await applescript.setVolume(volume);
      return { content: [{ type: "text", text: result }] };
    } catch (err) {
      return { content: [{ type: "text", text: `Error: ${(err as Error).message}` }], isError: true };
    }
  }
);

// ---- set_shuffle ----
server.registerTool(
  "set_shuffle",
  {
    description: "Enable or disable shuffle in Apple Music",
    inputSchema: z.object({
      enabled: z.boolean().describe("true to enable shuffle, false to disable"),
    }),
  },
  async ({ enabled }) => {
    try {
      const result = await applescript.setShuffle(enabled);
      return { content: [{ type: "text", text: result }] };
    } catch (err) {
      return { content: [{ type: "text", text: `Error: ${(err as Error).message}` }], isError: true };
    }
  }
);

// ---- set_repeat ----
server.registerTool(
  "set_repeat",
  {
    description: "Set the repeat mode in Apple Music",
    inputSchema: z.object({
      mode: z.enum(["off", "one", "all"]).describe("Repeat mode: off, one (repeat current track), or all (repeat playlist)"),
    }),
  },
  async ({ mode }) => {
    try {
      const result = await applescript.setRepeat(mode);
      return { content: [{ type: "text", text: result }] };
    } catch (err) {
      return { content: [{ type: "text", text: `Error: ${(err as Error).message}` }], isError: true };
    }
  }
);

// ---- seek ----
server.registerTool(
  "seek",
  {
    description: "Seek to a position in the current track (in seconds)",
    inputSchema: z.object({
      seconds: z.number().min(0).describe("Position to seek to in seconds"),
    }),
  },
  async ({ seconds }) => {
    try {
      const result = await applescript.seek(seconds);
      return { content: [{ type: "text", text: result }] };
    } catch (err) {
      return { content: [{ type: "text", text: `Error: ${(err as Error).message}` }], isError: true };
    }
  }
);

// ---- search ----
server.registerTool(
  "search",
  {
    description: "Search for tracks in the Apple Music library",
    inputSchema: z.object({
      query: z.string().describe("Search query (matches track name, artist, album)"),
      limit: z.number().optional().describe("Maximum number of results to return (default 25)"),
    }),
  },
  async ({ query, limit }) => {
    try {
      const results = await applescript.search(query, limit);
      return { content: [{ type: "text", text: JSON.stringify(results, null, 2) }] };
    } catch (err) {
      return { content: [{ type: "text", text: `Error: ${(err as Error).message}` }], isError: true };
    }
  }
);

// ---- play_track ----
server.registerTool(
  "play_track",
  {
    description: "Search for a track and play the first match",
    inputSchema: z.object({
      name: z.string().describe("Track name to search for"),
      artist: z.string().optional().describe("Artist name to narrow the search"),
    }),
  },
  async ({ name, artist }) => {
    try {
      const result = await applescript.playTrack(name, artist);
      return { content: [{ type: "text", text: result }] };
    } catch (err) {
      return { content: [{ type: "text", text: `Error: ${(err as Error).message}` }], isError: true };
    }
  }
);

// ---- list_playlists ----
server.registerTool(
  "list_playlists",
  {
    description: "List all playlists in Apple Music",
    inputSchema: z.object({}),
  },
  async () => {
    try {
      const playlists = await applescript.listPlaylists();
      return { content: [{ type: "text", text: JSON.stringify(playlists, null, 2) }] };
    } catch (err) {
      return { content: [{ type: "text", text: `Error: ${(err as Error).message}` }], isError: true };
    }
  }
);

// ---- play_playlist ----
server.registerTool(
  "play_playlist",
  {
    description: "Play a playlist by name in Apple Music",
    inputSchema: z.object({
      name: z.string().describe("Name of the playlist to play"),
    }),
  },
  async ({ name }) => {
    try {
      const result = await applescript.playPlaylist(name);
      return { content: [{ type: "text", text: result }] };
    } catch (err) {
      return { content: [{ type: "text", text: `Error: ${(err as Error).message}` }], isError: true };
    }
  }
);

// ---- set_loved ----
server.registerTool(
  "set_loved",
  {
    description: "Mark or unmark the currently playing track as loved in Apple Music",
    inputSchema: z.object({
      loved: z.boolean().describe("true to mark as loved, false to remove loved"),
    }),
  },
  async ({ loved }) => {
    try {
      const result = await applescript.setLoved(loved);
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
  console.error("Apple Music MCP server running on stdio");
}

main().catch((err) => {
  console.error("Fatal error:", err);
  process.exit(1);
});
