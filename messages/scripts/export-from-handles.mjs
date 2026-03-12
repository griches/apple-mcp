#!/usr/bin/env node
/**
 * Export Apple Messages from specific handles (e.g. mojosolo@mac.com, david@mojosolo.com).
 * Run from the messages package directory. Requires Full Disk Access for Terminal/Cursor.
 *
 * Usage: node scripts/export-from-handles.mjs [output.json]
 *        Default output: messages-export.json
 */

import { join } from "node:path";
import { homedir } from "node:os";
import { writeFileSync } from "node:fs";
import { pathToFileURL } from "node:url";

const HANDLES = ["mojosolo@mac.com", "david@mojosolo.com"];

async function main() {
  const buildPath = join(process.cwd(), "build", "database.js");
  const mod = await import(pathToFileURL(buildPath).href);
  const { getMessagesFromHandles, listChats } = mod;

  let messages;
  try {
    messages = getMessagesFromHandles(HANDLES);
    if (messages.length === 0) {
      const { findHandlesContaining } = mod;
      const discovered = findHandlesContaining(HANDLES);
      if (discovered.length > 0) {
        console.error(`No exact match; found handles: ${discovered.join(", ")}. Retrying with those.`);
        messages = getMessagesFromHandles(discovered);
      }
    }
  } catch (err) {
    if (err.message?.includes("unable to open") || err.message?.includes("authorization denied")) {
      console.error("Error: Cannot read ~/Library/Messages/chat.db");
      console.error("Grant Full Disk Access to Terminal (or Cursor) in System Settings > Privacy & Security > Full Disk Access");
      process.exit(1);
    }
    throw err;
  }

  // Group by chat for readability
  const byChat = new Map();
  for (const m of messages) {
    const key = m.chat_id;
    if (!byChat.has(key)) {
      byChat.set(key, { chat_id: key, display_name: m.display_name, messages: [] });
    }
    byChat.get(key).messages.push({
      date: m.date,
      from_me: m.is_from_me,
      sender: m.sender,
      text: m.text || "(no text)",
    });
  }

  const result = {
    exported_at: new Date().toISOString(),
    handles: HANDLES,
    total_messages: messages.length,
    chats: Array.from(byChat.values()),
  };

  const outPath = process.argv[2] || "messages-export.json";
  writeFileSync(outPath, JSON.stringify(result, null, 2), "utf8");
  console.log(`Exported ${messages.length} messages from ${HANDLES.join(", ")} to ${outPath}`);

  // Print summary for quick view
  console.log("\n--- Summary by chat ---");
  for (const [chatId, data] of byChat) {
    console.log(`\n${data.display_name || chatId} (${data.messages.length} messages)`);
    data.messages.slice(-5).forEach((m) => {
      const dir = m.from_me ? "→" : "←";
      const preview = (m.text || "").slice(0, 60).replace(/\n/g, " ");
      console.log(`  ${m.date} ${dir} ${preview}${preview.length >= 60 ? "…" : ""}`);
    });
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
