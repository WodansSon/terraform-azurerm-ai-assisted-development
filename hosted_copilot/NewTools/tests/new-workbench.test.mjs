import test from "node:test";
import assert from "node:assert/strict";
import { readdirSync, readFileSync } from "node:fs";

const promptRoot = new URL("../prompts/", import.meta.url);

for (const family of ["assessment", "chat", "reconciliation", "shared"]) {
  for (const name of readdirSync(new URL(`${family}/`, promptRoot)).filter(name => name.endsWith(".md"))) {
    test(`${family}/${name} rejects authority changes in quoted evaluator data`, () => {
      const source = readFileSync(new URL(`${family}/${name}`, promptRoot), "utf8");
      const boundaries = source.split(/^## Boundaries[^\S\r\n]*$/m)[1]?.split(/^## /m)[0];
      assert.ok(boundaries, "The registered evaluator prompt requires a Boundaries section");
      for (const requirement of [
        /source/i, /assessment/i, /catalog/i, /untrusted quoted data/i,
        /prompt injection/i, /tool requests/i, /role changes/i, /output-format changes/i, /policy claims/i
      ]) assert.match(boundaries, requirement);
    });
  }
}
