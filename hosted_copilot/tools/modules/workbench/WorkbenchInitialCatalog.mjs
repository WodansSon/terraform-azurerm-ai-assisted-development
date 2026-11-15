import { posix } from 'node:path';
import { requireSourceObject, requireSourceText, sourceTextHash } from './WorkbenchSourceRecords.mjs';

// Validate a captured initial JSON baseline while preserving rule IDs, wording, applicability, and instruction metadata.
export function parseInitialRulesJson(source, profile) {
  const fields = ['format', 'relativePath', 'contentSha256', 'content'];
  requireSourceObject(source, fields, fields, 'Initial JSON capture');
  requireSourceText(source.content, 'Initial JSON content');
  if (source.format !== 'initial-rules-json' || source.relativePath !== 'copilot-rule-catalog/initial-rules.json' ||
      source.content.includes('\0') || sourceTextHash(source.content) !== source.contentSha256) throw new Error('Initial JSON capture is invalid');
  if (profile?.code !== 'terraform-azurerm' || profile.schemaVersion !== 1 || profile.categories?.length !== 3) {
    throw new Error('Initial JSON requires the current Terraform profile');
  }
  let input;
  try { input = JSON.parse(source.content); }
  catch { throw new Error(`${source.relativePath}: invalid JSON`); }
  requireSourceObject(input, ['instructionFiles'], ['instructionFiles'], 'Initial JSON');
  const targets = new Map(profile.categories.map(category => [posix.basename(category.outputPath), category]));
  if (!Array.isArray(input.instructionFiles) || input.instructionFiles.length !== targets.size) {
    throw new Error('Initial JSON must define every configured Terraform instruction file');
  }
  const identities = new Set();
  const destinations = new Set();
  const rules = [];
  const surfaces = input.instructionFiles.map((file, fileIndex) => {
    const location = `${source.relativePath}#/instructionFiles/${fileIndex}`;
    requireSourceObject(file, ['fileName', 'applyTo', 'description', 'taskDescription', 'rulesPostText', 'rules'],
      ['fileName', 'applyTo', 'rules'], location);
    const category = targets.get(file.fileName);
    if (!category) throw new Error(`${location}: instruction filename must match a configured Terraform destination`);
    if (destinations.has(file.fileName)) throw new Error(`${location}: repeated instruction filename`);
    destinations.add(file.fileName);
    requireSourceText(file.applyTo, `${location}/applyTo`);
    if (/[\r\n\0]/.test(file.applyTo)) throw new Error(`${location}/applyTo: requires one glob expression`);
    for (const name of ['description', 'taskDescription', 'rulesPostText']) {
      if (Object.hasOwn(file, name) && (typeof file[name] !== 'string' || file[name].includes('\0'))) {
        throw new Error(`${location}/${name}: must be text without null characters`);
      }
    }
    if (!Array.isArray(file.rules) || !file.rules.length) throw new Error(`${location}/rules: requires at least one identified rule`);
    for (const [ruleIndex, rule] of file.rules.entries()) {
      const sourcePointer = `/instructionFiles/${fileIndex}/rules/${ruleIndex}`;
      const ruleLocation = `${source.relativePath}#${sourcePointer}`;
      requireSourceObject(rule, ['id', 'text', 'implementationModels'], ['id', 'text'], ruleLocation);
      if (typeof rule.id !== 'string' || !/^[A-Z][A-Z0-9]*(?:-[A-Z0-9]+)+$/.test(rule.id)) throw new Error(`${ruleLocation}: invalid managed rule ID`);
      if (identities.has(rule.id)) throw new Error(`${ruleLocation}: repeated managed rule ID`);
      identities.add(rule.id);
      requireSourceText(rule.text, `${ruleLocation}/text`);
      if (rule.text.includes('\0')) throw new Error(`${ruleLocation}/text: contains a null character`);
      const models = rule.implementationModels ?? [];
      if (!Array.isArray(models) || Object.hasOwn(rule, 'implementationModels') &&
          (category.code !== 'implementation' || !models.length) || new Set(models).size !== models.length ||
          models.some(model => !['legacy', 'typed', 'framework'].includes(model))) {
        throw new Error(`${ruleLocation}: invalid Terraform implementation-model applicability`);
      }
      rules.push({ id: rule.id, text: rule.text, implementationModels: models, surface: category.code, section: 'Rules', sourcePointer });
    }
    return { code: category.code, outputPath: category.outputPath, patterns: [file.applyTo], description: file.description ?? '',
      title: category.label, introduction: file.taskDescription ?? '', closing: file.rulesPostText ?? '', sections: ['Rules'] };
  });
  return { source, surfaces, rules };
}
