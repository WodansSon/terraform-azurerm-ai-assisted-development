import { readFileSync, readdirSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { lint, readConfig } from "markdownlint/promise";

const repositoryRoot = fileURLToPath(new URL("../../../", import.meta.url));

export async function lintHostedMarkdown(root = repositoryRoot) {
  const files = [];
  function collect(directory) {
    const entries = readdirSync(path.join(root, directory), { withFileTypes: true })
      .sort((left, right) => left.name.localeCompare(right.name));
    for (const entry of entries) {
      const relativePath = `${directory}/${entry.name}`;
      if (entry.name === "node_modules") {
        continue;
      }
      if (entry.isDirectory()) {
        collect(relativePath);
      } else if (entry.isFile() && entry.name.endsWith(".md")) {
        files.push(relativePath);
      }
    }
  }
  collect("hosted_copilot");
  files.push("docs/HOSTED_COPILOT_CODE_REVIEW_ARCHITECTURE.md");
  const config = await readConfig(path.join(root, ".github", ".markdownlint.json"));
  if (!config) {
    throw new Error("The repository Markdown lint configuration could not be loaded");
  }
  const strings = Object.fromEntries(files.map((file) => [
    file,
    readFileSync(path.join(root, file), "utf8")
  ]));
  return lint({ strings, config });
}

export function formatHostedMarkdownResults(results) {
  return Object.entries(results).flatMap(([file, errors]) => errors.map((error) => {
    const column = error.errorRange ? `:${error.errorRange[0]}` : "";
    const detail = error.errorDetail ? ` [${error.errorDetail}]` : "";
    const context = error.errorContext ? ` [Context: "${error.errorContext}"]` : "";
    return `${file}:${error.lineNumber}${column} ${error.ruleNames.join("/")} ${error.ruleDescription}${detail}${context}`;
  })).join("\n");
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const results = await lintHostedMarkdown();
  const diagnostics = formatHostedMarkdownResults(results);
  if (diagnostics) {
    console.error(diagnostics);
    process.exitCode = 1;
  } else {
    console.log(`Markdownlint passed for ${Object.keys(results).length} Hosted Markdown files.`);
  }
}
