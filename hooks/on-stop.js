#!/usr/bin/env node

/**
 * Stop hook — Captures the latest assistant response and writes it
 * to ~/.claude-annotator/current-response.json for the annotation TUI.
 *
 * Receives on stdin: { session_id, transcript_path, last_assistant_message, ... }
 * Outputs: {} (don't interfere with stop decision)
 */

const fs = require("fs");
const path = require("path");
const crypto = require("crypto");

const IPC_DIR = path.join(
  process.env.HOME || process.env.USERPROFILE,
  ".claude-annotator"
);
const RESPONSE_FILE = path.join(IPC_DIR, "current-response.json");

async function main() {
  // Read hook input from stdin
  const chunks = [];
  for await (const chunk of process.stdin) {
    chunks.push(chunk);
  }
  const input = JSON.parse(Buffer.concat(chunks).toString("utf-8"));

  const content = input.last_assistant_message;
  if (!content || content.trim() === "") {
    // No assistant message — nothing to capture
    process.stdout.write("{}");
    return;
  }

  // Ensure IPC directory exists
  fs.mkdirSync(IPC_DIR, { recursive: true });

  const response = {
    session_id: input.session_id || "unknown",
    message_id: crypto.randomUUID(),
    content: content,
    timestamp: new Date().toISOString(),
  };

  fs.writeFileSync(RESPONSE_FILE, JSON.stringify(response, null, 2), "utf-8");

  // Don't interfere with the stop decision
  process.stdout.write("{}");
}

main().catch((err) => {
  process.stderr.write(`claude-annotator stop hook error: ${err.message}\n`);
  process.stdout.write("{}");
  process.exit(0); // Don't break Claude Code on hook errors
});
