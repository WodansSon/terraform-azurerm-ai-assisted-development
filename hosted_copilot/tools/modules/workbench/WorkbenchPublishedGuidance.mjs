import { createHash } from 'node:crypto';
import { lstat, readFile, realpath } from 'node:fs/promises';
import { resolve, sep } from 'node:path';
import { fileURLToPath } from 'node:url';

const hostedRoot = fileURLToPath(new URL('../../../', import.meta.url));
const fingerprint = bytes => createHash('sha256').update(bytes).digest('hex');

// Prefer a stable published capture; fall back to initial JSON only when publication is absent, not invalid.
export async function readInitialCatalogSource({ root = hostedRoot } = {}) {
  const resolvedRoot = await realpath(root);
  for (const [format, relativePath] of [
    ['published-catalog', 'copilot-rule-catalog/published/instruction-catalog.json'],
    ['initial-rules-json', 'copilot-rule-catalog/initial-rules.json'],
  ]) {
    let path;
    try { await lstat(resolve(resolvedRoot, relativePath)); }
    catch (error) {
      if (format === 'published-catalog' && error.code === 'ENOENT') continue;
      throw new Error(`Initial catalog input is missing or unreadable: ${relativePath}`);
    }
    try { path = await realpath(resolve(resolvedRoot, relativePath)); }
    catch { throw new Error(`Initial catalog input is unreadable: ${relativePath}`); }
    if (!path.startsWith(resolvedRoot + sep)) throw new Error(`Initial catalog input is outside the Hosted root: ${relativePath}`);
    const bytes = await readFile(path);
    let content;
    try { content = new TextDecoder('utf-8', { fatal: true, ignoreBOM: true }).decode(bytes); }
    catch { throw new Error(`Initial catalog input is not UTF-8: ${relativePath}`); }
    if (!content.trim() || content.includes('\0')) throw new Error(`Initial catalog input has invalid content: ${relativePath}`);
    if (format === 'published-catalog') {
      let catalog;
      try { catalog = JSON.parse(content); }
      catch { throw new Error('Published catalog is invalid JSON; the initial rules fallback was not selected'); }
      if (!catalog || Array.isArray(catalog) || typeof catalog !== 'object') throw new Error('Published catalog must be an object; the initial rules fallback was not selected');
    }
    if (await realpath(resolve(resolvedRoot, relativePath)) !== path || fingerprint(await readFile(path)) !== fingerprint(bytes)) {
      throw new Error(`Initial catalog input changed during capture: ${relativePath}`);
    }
    return { format, relativePath, contentSha256: fingerprint(bytes), content };
  }
}

// Capture complete guidance files and identified rules as an unapproved baseline without publishing or rewriting them.
export async function buildInitialStagedCatalog({ root = hostedRoot, profile }) {
  if (profile?.code !== 'terraform-azurerm' || profile.schemaVersion !== 1 || profile.categories?.length !== 3 || profile.fixedGuidanceFiles?.length !== 2) {
    throw new Error('Initial catalog requires the complete Terraform guidance profile');
  }
  const resolvedRoot = await realpath(root);
  const inputs = [
    ...profile.categories.map(category => ({ relativePath: category.outputPath, role: 'instructions', surface: category.code, patterns: category.patterns })),
    ...profile.fixedGuidanceFiles.map(file => ({ relativePath: file.path, role: file.code === 'repository' ? 'repository' : 'skill' })),
  ];
  if (new Set(inputs.map(input => input.relativePath)).size !== inputs.length) throw new Error('Required guidance paths must be unique');
  const files = [];
  const rules = [];
  const identities = new Set();
  for (const input of inputs) {
    const path = await realpath(resolve(resolvedRoot, input.relativePath)).catch(() => { throw new Error(`Required guidance is missing or unreadable: ${input.relativePath}`); });
    if (!path.startsWith(resolvedRoot + sep)) throw new Error(`Required guidance is outside the Hosted root: ${input.relativePath}`);
    const bytes = await readFile(path);
    let content;
    try { content = new TextDecoder('utf-8', { fatal: true, ignoreBOM: true }).decode(bytes); }
    catch { throw new Error(`Required guidance is not UTF-8: ${input.relativePath}`); }
    if (!content.trim() || content.includes('\0')) throw new Error(`Required guidance has invalid content: ${input.relativePath}`);
    files.push({ ...input, contentSha256: fingerprint(bytes), content });
    if (input.role !== 'instructions') continue;
    if (!/^---\r?\n[\s\S]*?\r?\n---\r?\n/.test(content) || !/^# .+/m.test(content)) {
      throw new Error(`Required instructions lack frontmatter or title: ${input.relativePath}`);
    }
    let section = null;
    let count = 0;
    for (const [index, line] of content.split(/\r?\n/).entries()) {
      if (line.startsWith('## ')) section = line.slice(3).trim();
      const match = /^- `\[([A-Z]+-[A-Z0-9]+-[0-9]+[A-Z]?)\]` (.+)$/.exec(line);
      if (!match) {
        if (/^- `\[/.test(line)) throw new Error(`Malformed rule at ${input.relativePath}:${index + 1}`);
        continue;
      }
      if (!section || identities.has(match[1])) throw new Error(`Missing section or duplicate rule at ${input.relativePath}:${index + 1}`);
      identities.add(match[1]);
      const models = /^\[(legacy|typed|framework)(?:, (?:legacy|typed|framework))*\] /.exec(match[2]);
      rules.push({ id: match[1], surface: input.surface, kind: section === 'Protected Rules' ? 'protected' : 'managed',
        section, sourcePath: input.relativePath, sourceLine: index + 1, text: match[2],
        ...(models ? { implementationModels: models[0].slice(1, -2).split(', ') } : {}) });
      count++;
    }
    if (!count) throw new Error(`Required instructions contain no identified rules: ${input.relativePath}`);
  }
  for (const file of files) {
    const path = await realpath(resolve(resolvedRoot, file.relativePath));
    if (!path.startsWith(resolvedRoot + sep) || fingerprint(await readFile(path)) !== file.contentSha256) {
      throw new Error(`Required guidance changed during capture: ${file.relativePath}`);
    }
  }
  return { $schema: '../../contracts/catalog/instruction-catalog-bootstrap.schema.json', schemaVersion: 1, kind: 'hosted-guidance-bootstrap',
    state: 'staged', approval: 'not-recorded', profileCode: profile.code, source: 'repository-guidance-files', files, rules };
}

// Verify required guidance remains inside the Hosted root and unchanged while measuring guarded token usage.
export async function readRequiredGuidance(capacity, { root = hostedRoot } = {}) {
  const files = [];
  const failures = [];
  let resolvedRoot;
  try { resolvedRoot = await realpath(root); }
  catch { return { available: false, source: 'repository-guidance-files', files: [], failures: [{ relativePath: '.', reason: 'unreadable' }] }; }
  for (const bucket of capacity.buckets) {
    let path;
    let bytes;
    try {
      path = await realpath(resolve(resolvedRoot, bucket.relativePath));
      if (!path.startsWith(resolvedRoot + sep)) {
        failures.push({ relativePath: bucket.relativePath, reason: 'outside-hosted-root' });
        continue;
      }
      bytes = await readFile(path);
    } catch (error) {
      failures.push({ relativePath: bucket.relativePath, reason: error.code === 'ENOENT' ? 'missing' : 'unreadable' });
      continue;
    }
    let text;
    try { text = new TextDecoder('utf-8', { fatal: true }).decode(bytes); }
    catch {
      failures.push({ relativePath: bucket.relativePath, reason: 'invalid-utf8' });
      continue;
    }
    if (!text.trim() || text.includes('\0')) {
      failures.push({ relativePath: bucket.relativePath, reason: 'invalid-content' });
      continue;
    }
    const estimatedTokens = Math.ceil(text.length / capacity.policy.charactersPerToken);
    files.push({ bucketId: bucket.bucketId, relativePath: bucket.relativePath, contentSha256: fingerprint(bytes),
      currentGuardedTokens: Math.ceil(estimatedTokens * (1 + capacity.policy.safetyMarginPercent / 100)), path });
  }
  for (const file of files) {
    try {
      if (await realpath(resolve(resolvedRoot, file.relativePath)) !== file.path || fingerprint(await readFile(file.path)) !== file.contentSha256) {
        failures.push({ relativePath: file.relativePath, reason: 'changed-during-read' });
      }
    } catch { failures.push({ relativePath: file.relativePath, reason: 'changed-during-read' }); }
  }
  return { available: failures.length === 0, source: 'repository-guidance-files',
    files: files.map(({ path, ...file }) => file), failures };
}

// Combine guidance availability with an optional exact published-catalog check, keeping unpublished state explicit.
export async function readPublishedGuidance(capacity, { root = hostedRoot, catalog = null } = {}) {
  const guidance = await readRequiredGuidance(capacity, { root });
  const result = { ...guidance, catalogState: catalog === null ? 'unpublished' : 'published', catalogSha256: null, catalogRuleCount: null };
  if (!guidance.available) return { ...result, reason: 'required-guidance-invalid' };
  if (catalog === null) return result;
  try {
    const resolvedRoot = await realpath(root);
    const catalogPath = await realpath(resolve(resolvedRoot, 'copilot-rule-catalog/published/instruction-catalog.json'));
    if (!catalogPath.startsWith(resolvedRoot + sep)) return { ...result, available: false, reason: 'published-catalog-outside-hosted-root' };
    const catalogBytes = await readFile(catalogPath);
    if (fingerprint(catalogBytes) !== catalog.contentSha256) return { ...result, available: false, reason: 'published-catalog-mismatch' };
    if (await realpath(resolve(resolvedRoot, 'copilot-rule-catalog/published/instruction-catalog.json')) !== catalogPath ||
        fingerprint(await readFile(catalogPath)) !== fingerprint(catalogBytes)) return { ...result, available: false, reason: 'published-catalog-changed-during-read' };
    return { ...result, catalogSha256: fingerprint(catalogBytes), catalogRuleCount: catalog.rules.length };
  } catch (error) { return { ...result, available: false, reason: error.code === 'ENOENT' ? 'published-catalog-missing' : 'published-catalog-unreadable' }; }
}
