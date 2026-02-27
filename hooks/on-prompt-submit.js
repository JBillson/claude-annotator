#!/usr/bin/env node

/**
 * UserPromptSubmit hook — Reads pending annotations from
 * ~/.claude-annotator/pending-annotations.json and injects them
 * as additionalContext on the user's next prompt.
 *
 * Receives on stdin: { session_id, prompt, ... }
 * Outputs: { hookSpecificOutput: { hookEventName, additionalContext } } or {}
 */

const fs = require("fs");
const path = require("path");

const IPC_DIR = path.join(
  process.env.HOME || process.env.USERPROFILE,
  ".claude-annotator"
);
const PENDING_FILE = path.join(IPC_DIR, "pending-annotations.json");

function composeAnnotations(annotations) {
  const notes = annotations.filter((a) => a.type === "note");
  const questions = annotations.filter((a) => a.type === "question");

  const sections = [];

  if (notes.length > 0) {
    const parts = ["**Context notes** (keep these in mind going forward):"];
    for (const n of notes) {
      parts.push(`\n> ${n.anchor_text}\n\n${n.content}`);
    }
    sections.push(parts.join("\n"));
  }

  if (questions.length > 0) {
    const parts = ["**Questions:**"];
    for (const q of questions) {
      parts.push(`\n> ${q.anchor_text}\n\n${q.content}`);
    }
    sections.push(parts.join("\n"));
  }

  return sections.join("\n\n---\n\n");
}

async function main() {
  // Read hook input from stdin (required even if we don't use it)
  const chunks = [];
  for await (const chunk of process.stdin) {
    chunks.push(chunk);
  }

  // Check for pending annotations
  if (!fs.existsSync(PENDING_FILE)) {
    process.stdout.write("{}");
    return;
  }

  let annotations;
  try {
    const raw = fs.readFileSync(PENDING_FILE, "utf-8");
    annotations = JSON.parse(raw);
  } catch {
    process.stdout.write("{}");
    return;
  }

  if (!Array.isArray(annotations) || annotations.length === 0) {
    process.stdout.write("{}");
    return;
  }

  const composed = composeAnnotations(annotations);

  // Clear the pending file after reading
  fs.writeFileSync(PENDING_FILE, "[]", "utf-8");

  const output = {
    hookSpecificOutput: {
      hookEventName: "UserPromptSubmit",
      additionalContext: composed,
    },
  };

  process.stdout.write(JSON.stringify(output));
}

main().catch((err) => {
  process.stderr.write(
    `claude-annotator prompt-submit hook error: ${err.message}\n`
  );
  process.stdout.write("{}");
  process.exit(0); // Don't break Claude Code on hook errors
});
