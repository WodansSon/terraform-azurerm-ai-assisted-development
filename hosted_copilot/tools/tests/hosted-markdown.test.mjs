import assert from "node:assert/strict";
import { mkdtempSync, mkdirSync, rmSync, writeFileSync } from "node:fs";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { formatHostedMarkdownResults, lintHostedMarkdown } from "../npm/Lint-Markdown.mjs";

function fixture(t) {
  const root = mkdtempSync(path.join(os.tmpdir(), "hosted-markdown-test-"));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  const write = (file, content) => {
    const destination = path.join(root, file);
    mkdirSync(path.dirname(destination), { recursive: true });
    writeFileSync(destination, content);
  };
  write(".github/.markdownlint.json", JSON.stringify({ default: false, MD013: false, MD018: true }));
  write("docs/HOSTED_COPILOT_CODE_REVIEW_ARCHITECTURE.md", "# Architecture\n");
  return { root, write };
}

test("Hosted Markdown lint covers nested and hidden content but excludes installed packages", async (t) => {
  const { root, write } = fixture(t);
  write("hosted_copilot/README.md", "# Hosted\n");
  write("hosted_copilot/.github/instructions/nested.md", "# Missing-space heading\n");
  write("hosted_copilot/tools/npm/node_modules/dependency/README.md", "#Invalid\n");
  write("hosted_copilot/NewTools/npm/node_modules/dependency/README.md", "#Invalid\n");
  write("hosted_copilot/NewDocs/source.md", "# New Workbench\n");
  write("hosted_copilot/docs/long-line.md", `${"Long line ".repeat(30)}\n`);
  const results = await lintHostedMarkdown(root);
  assert.deepEqual(Object.keys(results).sort(), [
    "docs/HOSTED_COPILOT_CODE_REVIEW_ARCHITECTURE.md",
    "hosted_copilot/.github/instructions/nested.md",
    "hosted_copilot/NewDocs/source.md",
    "hosted_copilot/README.md",
    "hosted_copilot/docs/long-line.md"
  ].sort());
  assert.equal(formatHostedMarkdownResults(results), "");
});

test("Hosted Markdown lint reports rule, relative file, and line for every scoped failure", async (t) => {
  const { root, write } = fixture(t);
  write("hosted_copilot/.github/instructions/nested.md", "#Invalid\n");
  write("docs/HOSTED_COPILOT_CODE_REVIEW_ARCHITECTURE.md", "#Invalid architecture\n");
  const results = await lintHostedMarkdown(root);
  assert.equal(results["hosted_copilot/.github/instructions/nested.md"][0].lineNumber, 1);
  const diagnostics = formatHostedMarkdownResults(results);
  assert.ok(diagnostics.includes("MD018"));
  assert.ok(diagnostics.includes("docs/HOSTED_COPILOT_CODE_REVIEW_ARCHITECTURE.md:1"));
  assert.ok(!diagnostics.includes(root));
});

test("Hosted Markdown lint rejects unreadable configuration rather than using defaults", async (t) => {
  const { root, write } = fixture(t);
  write("hosted_copilot/README.md", "# Hosted\n");
  write(".github/.markdownlint.json", "{");
  await assert.rejects(lintHostedMarkdown(root));
});
