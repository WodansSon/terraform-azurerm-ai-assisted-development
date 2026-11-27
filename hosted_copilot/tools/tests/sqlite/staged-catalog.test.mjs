import test from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { mkdtemp, mkdir, readFile, writeFile, rm, cp, readdir } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { buildInitialStagedCatalog, readInitialCatalogSource } from '../../modules/workbench/WorkbenchPublishedGuidance.mjs';
import { parseInitialRulesJson } from '../../modules/workbench/WorkbenchInitialCatalog.mjs';

const root = fileURLToPath(new URL('../../../', import.meta.url));
const profile = JSON.parse(await readFile(join(root, 'tools/config/workbench-terraform-profile.json'), 'utf8'));
const hash = bytes => createHash('sha256').update(bytes).digest('hex');

const jsonCapture = content => ({ format: 'initial-rules-json', relativePath: 'copilot-rule-catalog/initial-rules.json', contentSha256: hash(content), content });
const minimalJson = () => ({ instructionFiles: profile.categories.map((category, index) => ({ fileName: category.outputPath.split('/').at(-1),
  applyTo: category.patterns[0], rules: [{ id: `SYN-${index + 1}`, text: `Synthetic ${category.code} wording.` }] })) });

test('initial JSON validates explicit file settings rules and model applicability', () => {
  const input = { instructionFiles: profile.categories.map((category, index) => ({ fileName: category.outputPath.split('/').at(-1),
    applyTo: category.patterns[0], rules: [{ id: `SYN-${index + 1}`, text: `Synthetic ${category.code} wording.` }] })) };
  input.instructionFiles[0].rules[0].implementationModels = ['legacy', 'typed'];
  input.instructionFiles[0].rulesPostText = 'Review nearby code.\n\n## Evidence\nPreserve exact text.';
  const parse = value => {
    const content = JSON.stringify(value);
    return parseInitialRulesJson({ format: 'initial-rules-json', relativePath: 'copilot-rule-catalog/initial-rules.json',
      contentSha256: hash(content), content }, profile);
  };
  const parsed = parse(input);
  assert.equal(parsed.rules.length, 3);
  assert.deepEqual(parsed.rules[0].implementationModels, ['legacy', 'typed']);
  assert.equal(parsed.rules[0].sourcePointer, '/instructionFiles/0/rules/0');
  assert.equal(parsed.surfaces[0].closing, input.instructionFiles[0].rulesPostText);
  assert.equal(parsed.surfaces[1].description, '');
  for (const [change, pattern] of [
    [value => { value.instructionFiles[1].rules[0].id = 'SYN-1'; }, /repeated managed rule ID/],
    [value => { value.instructionFiles[0].fileName = '../outside.instructions.md'; }, /filename must match/],
    [value => { value.instructionFiles[0].unknown = true; }, /unsupported fields/],
    [value => { value.instructionFiles[0].rules[0].implementationModels = ['other']; }, /invalid Terraform/],
    [value => { value.instructionFiles[1].rules[0].implementationModels = ['typed']; }, /invalid Terraform/],
    [value => { value.instructionFiles[0].rules[0].implementationModels = null; }, /invalid Terraform/],
  ]) {
    const copy = structuredClone(input);
    change(copy);
    assert.throws(() => parse(copy), pattern);
  }
});

test('initial JSON preserves actual IDs wording models and post text without legacy lookups', async () => {
  const content = await readFile(join(root, 'copilot-rule-catalog/initial-rules.json'), 'utf8');
  const input = JSON.parse(content);
  const parsed = parseInitialRulesJson(jsonCapture(content), profile);
  const entries = input.instructionFiles.flatMap(file => file.rules);
  assert.equal(parsed.rules.length, entries.length);
  assert.deepEqual(parsed.rules.map(rule => rule.id), entries.map(entry => entry.id));
  for (const [index, rule] of parsed.rules.entries()) {
    assert.equal(rule.text, entries[index].text);
    assert.deepEqual(rule.implementationModels, entries[index].implementationModels ?? []);
    const located = rule.sourcePointer.slice(1).split('/').reduce((value, key) => value[key], input);
    assert.equal(located.id, rule.id);
  }
  assert.deepEqual(parsed.rules.find(rule => rule.id === 'IMPL-PATCH-001').implementationModels, ['legacy', 'typed']);
  assert.deepEqual(parsed.surfaces.map(surface => [surface.description, surface.introduction, surface.closing]),
    input.instructionFiles.map(file => [file.description, file.taskDescription, file.rulesPostText]));
  assert.ok(parsed.surfaces.every(surface => surface.description && surface.introduction && surface.closing));
});

test('initial JSON permits omitted metadata and rejects ambiguous or unsupported input', () => {
  const input = minimalJson();
  const content = JSON.stringify(input);
  const parsed = parseInitialRulesJson(jsonCapture(content), profile);
  assert.equal(parsed.rules.length, profile.categories.length);
  assert.ok(parsed.surfaces.every(surface => surface.description === '' && surface.introduction === '' && surface.closing === ''));
  for (const [change, pattern] of [
    [value => { value.instructionFiles[0].applyTo = ''; }, /applyTo/],
    [value => { value.instructionFiles[0].applyTo = 'internal/**\nother/**'; }, /one glob/],
    [value => { value.instructionFiles[0].rules = []; }, /at least one/],
    [value => { value.instructionFiles[0].rules[0].text = ''; }, /text/],
    [value => { value.instructionFiles[0].rules[0].implementationModels = ['typed', 'typed']; }, /invalid Terraform/],
    [value => { value.instructionFiles[0].description = null; }, /must be text/],
    [value => { value.instructionFiles[1].fileName = value.instructionFiles[0].fileName; }, /repeated instruction filename/],
    [value => { value.instructionFiles.pop(); }, /every configured Terraform/],
  ]) {
    const copy = structuredClone(input);
    change(copy);
    assert.throws(() => parseInitialRulesJson(jsonCapture(JSON.stringify(copy)), profile), pattern);
  }
  assert.throws(() => parseInitialRulesJson(jsonCapture('{'), profile), /invalid JSON/);
  assert.throws(() => parseInitialRulesJson({ ...jsonCapture(content), contentSha256: '0'.repeat(64) }, profile), /capture is invalid/);
  input.instructionFiles[0].rules[0].text = ' Exact wording.\nSecond line. ';
  assert.equal(parseInitialRulesJson(jsonCapture(JSON.stringify(input)), profile).rules[0].text, input.instructionFiles[0].rules[0].text);
});

test('initial baseline selection prefers published input and falls back only when it is absent', async context => {
  const directory = await mkdtemp(join(tmpdir(), 'hosted-initial-baseline-'));
  context.after(() => rm(directory, { recursive: true, force: true }));
  const publishedDirectory = join(directory, 'copilot-rule-catalog/published');
  await mkdir(publishedDirectory, { recursive: true });
  const initial = JSON.stringify(minimalJson());
  await writeFile(join(directory, 'copilot-rule-catalog/initial-rules.json'), initial);
  assert.deepEqual(await readInitialCatalogSource({ root: directory }), {
    format: 'initial-rules-json', relativePath: 'copilot-rule-catalog/initial-rules.json', contentSha256: hash(initial), content: initial,
  });
  const published = '{"schemaVersion":1}\n';
  await writeFile(join(publishedDirectory, 'instruction-catalog.json'), published);
  const selected = await readInitialCatalogSource({ root: directory });
  assert.deepEqual(selected, { format: 'published-catalog', relativePath: 'copilot-rule-catalog/published/instruction-catalog.json',
    contentSha256: hash(published), content: published });
  await rm(join(directory, 'copilot-rule-catalog/initial-rules.json'));
  assert.deepEqual(await readInitialCatalogSource({ root: directory }), selected);
});

test('initial baseline selection refuses invalid publication rather than using initial JSON', async context => {
  const directory = await mkdtemp(join(tmpdir(), 'hosted-invalid-publication-'));
  context.after(() => rm(directory, { recursive: true, force: true }));
  const publishedDirectory = join(directory, 'copilot-rule-catalog/published');
  await mkdir(publishedDirectory, { recursive: true });
  await writeFile(join(directory, 'copilot-rule-catalog/initial-rules.json'), JSON.stringify(minimalJson()));
  for (const invalid of ['', '{', '[]', 'null', Buffer.from([0xff])]) {
    await writeFile(join(publishedDirectory, 'instruction-catalog.json'), invalid);
    await assert.rejects(readInitialCatalogSource({ root: directory }), /invalid content|invalid JSON|must be an object|not UTF-8/);
  }
  await rm(join(publishedDirectory, 'instruction-catalog.json'));
  await rm(join(directory, 'copilot-rule-catalog/initial-rules.json'));
  await assert.rejects(readInitialCatalogSource({ root: directory }), /missing or unreadable: copilot-rule-catalog\/initial-rules.json/);
});

test('initial staged catalog preserves all current guidance bytes and identified rules without publication', async () => {
  const catalog = await buildInitialStagedCatalog({ root, profile });
  assert.equal(catalog.files.length, 5);
  assert.equal(catalog.approval, 'not-recorded');
  assert.equal(catalog.state, 'staged');
  assert.ok(catalog.files.some(file => file.role === 'skill' && file.content.includes('## Boundaries')));
  assert.ok(catalog.files.some(file => file.role === 'repository'));
  const expectedIds = [];
  for (const file of catalog.files) {
    const bytes = await readFile(join(root, file.relativePath));
    assert.deepEqual(Buffer.from(file.content, 'utf8'), bytes);
    assert.equal(file.contentSha256, hash(bytes));
    for (const match of file.content.matchAll(/^- `\[([A-Z]+-[A-Z0-9]+-[0-9]+[A-Z]?)\]` (.+)$/gm)) expectedIds.push(match[1]);
  }
  assert.deepEqual(catalog.rules.map(rule => rule.id), expectedIds);
  assert.equal(new Set(expectedIds).size, expectedIds.length);
  for (const rule of catalog.rules) {
    const file = catalog.files.find(file => file.relativePath === rule.sourcePath);
    assert.equal(file.content.split(/\r?\n/)[rule.sourceLine - 1], `- \`[${rule.id}]\` ${rule.text}`);
  }
  assert.equal(catalog.rules.find(rule => rule.id === 'IMPL-WF-000').kind, 'protected');
  assert.deepEqual(catalog.rules.find(rule => rule.id === 'IMPL-PATCH-001').implementationModels, ['legacy', 'typed']);
});

test('initial staging refuses overwrite and missing guidance and never writes published output', async context => {
  const directory = await mkdtemp(join(tmpdir(), 'hosted-staged-catalog-'));
  context.after(() => rm(directory, { recursive: true, force: true }));
  await cp(join(root, '.github'), join(directory, '.github'), { recursive: true });
  for (const relativePath of ['tools/internal/workbench/New-InitialStagedCatalog.ps1',
    'tools/modules/workbench/WorkbenchPublishedGuidance.mjs', 'tools/config/workbench-terraform-profile.json',
    'contracts/catalog/instruction-catalog-bootstrap.schema.json']) {
    const destination = join(directory, relativePath);
    await mkdir(join(destination, '..'), { recursive: true });
    await cp(join(root, relativePath), destination);
  }
  const published = join(directory, 'copilot-rule-catalog/published');
  await mkdir(published, { recursive: true });
  const sentinel = Buffer.from('synthetic prior publication\n');
  await writeFile(join(published, 'instruction-catalog.json'), sentinel);
  const command = () => execFileSync('pwsh', ['-NoProfile', '-File', join(directory, 'tools/internal/workbench/New-InitialStagedCatalog.ps1')], { encoding: 'utf8', stdio: 'pipe' });
  assert.match(command(), /Captured 5 guidance files and \d+ identified rules/);
  const destination = join(directory, 'copilot-rule-catalog/staged/instruction-catalog.json');
  const staged = await readFile(destination);
  assert.deepEqual(JSON.parse(staged), await buildInitialStagedCatalog({ root: directory, profile }));
  assert.throws(command, error => /refuses an existing staged catalog/.test(error.stderr));
  assert.deepEqual(await readFile(destination), staged);
  assert.deepEqual(await readdir(published), ['instruction-catalog.json']);
  assert.deepEqual(await readFile(join(published, 'instruction-catalog.json')), sentinel);
  await rm(join(directory, '.github/skills/code-review/SKILL.md'));
  await assert.rejects(buildInitialStagedCatalog({ root: directory, profile }), /Required guidance is missing or unreadable: .github\/skills\/code-review\/SKILL.md/);
  assert.deepEqual(await readFile(destination), staged);
  await rm(destination);
  assert.throws(command, error => /Required guidance is missing or unreadable/.test(error.stderr));
  await assert.rejects(readFile(destination), { code: 'ENOENT' });
  await writeFile(join(directory, '.github/skills/code-review/SKILL.md'), Buffer.from([0xff]));
  assert.throws(command, error => /Required guidance is not UTF-8/.test(error.stderr));
  await assert.rejects(readFile(destination), { code: 'ENOENT' });
  await cp(join(root, '.github/skills/code-review/SKILL.md'), join(directory, '.github/skills/code-review/SKILL.md'));
  const instructionPath = join(directory, profile.categories[0].outputPath);
  const instructions = await readFile(instructionPath, 'utf8');
  await writeFile(instructionPath, instructions + '\n- `[IMPL-EVID-001]` Duplicate synthetic rule.\n');
  assert.throws(command, error => /duplicate rule/.test(error.stderr));
  await assert.rejects(readFile(destination), { code: 'ENOENT' });
  assert.deepEqual(await readFile(join(published, 'instruction-catalog.json')), sentinel);
});
