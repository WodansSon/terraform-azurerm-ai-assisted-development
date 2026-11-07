import { createHash } from 'node:crypto';

export const normalizedSourceContractVersion = 2;

const requiredFields = ['sourceId', 'title', 'content', 'contentSha256', 'location', 'presence', 'sourceLifecycle'];
const listFields = ['provenanceCodes', 'evidence', 'sourceIds', 'replacementIds', 'applicabilityCodes'];
const nullableFields = ['contractPath', 'ruleText', 'rationale', 'deprecatedOn', 'retiredOn', 'lifecycleReason', 'removedAt', 'originRepository', 'originCommit', 'originReferenceUrl'];
const commonLegacyFields = [...requiredFields, 'removedAt', 'provenance', 'evidence'];

export function sourceTextHash(text) {
  return createHash('sha256').update(text, 'utf8').digest('hex');
}

export function requireSourceObject(value, allowed, required, label) {
  if (!value || typeof value !== 'object' || Array.isArray(value) || ![Object.prototype, null].includes(Object.getPrototypeOf(value))) {
    throw new Error(`${label} must be a plain object`);
  }
  if (Reflect.ownKeys(value).some(key => typeof key !== 'string' || !allowed.includes(key) || !Object.hasOwn(Object.getOwnPropertyDescriptor(value, key), 'value')) || required.some(key => !Object.hasOwn(value, key))) {
    throw new Error(`${label} has missing or unsupported fields`);
  }
}

export function requireSourceText(value, label) {
  if (typeof value !== 'string' || value.trim().length === 0 || value.includes('\0') || !value.isWellFormed()) {
    throw new Error(`${label} must be nonempty text without NUL characters`);
  }
  return value;
}

export function requireSourceHash(value, label) {
  if (typeof value !== 'string' || !/^[a-f0-9]{64}$/.test(value)) throw new Error(`${label} must be a SHA-256 digest`);
  return value;
}

export function normalizeCapturedSourceFiles(files) {
  if (!Array.isArray(files)) throw new Error('Captured source files must be an array');
  const normalized = files.map(file => {
    const fields = ['relativePath', 'contentBytes', 'contentSha256'];
    requireSourceObject(file, fields, fields, 'Captured source file');
    requireSourceText(file.relativePath, 'Captured relative path');
    if (!/^[A-Za-z0-9._/-]+$/.test(file.relativePath) || file.relativePath.startsWith('/') || file.relativePath.split('/').some(part => !part || part === '.' || part === '..')) throw new Error('Captured source paths must be scoped repository-relative paths');
    requireSourceHash(file.contentSha256, 'Captured file hash');
    if (!(file.contentBytes instanceof Uint8Array)) throw new Error('Captured file content must contain exact bytes');
    const bytes = Buffer.from(file.contentBytes);
    if (createHash('sha256').update(bytes).digest('hex') !== file.contentSha256) throw new Error('Captured file hash does not match its bytes');
    return { relativePath: file.relativePath, contentBytes: bytes, contentSha256: file.contentSha256 };
  }).sort((left, right) => left.relativePath < right.relativePath ? -1 : left.relativePath > right.relativePath ? 1 : 0);
  if (new Set(normalized.map(file => file.relativePath)).size !== normalized.length) throw new Error('Captured source paths must be unique');
  return normalized;
}

function uniqueTextList(value, label, unique = true) {
  if (!Array.isArray(value)) throw new Error(`${label} must be an array`);
  for (const item of value) requireSourceText(item, label);
  if (unique && new Set(value).size !== value.length) throw new Error(`${label} must not contain duplicates`);
  return Object.freeze([...value]);
}

function sourceDate(value, label) {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value) || !Number.isFinite(Date.parse(value)) || new Date(value).toISOString().slice(0, 10) !== value) {
    throw new Error(`${label} must be a valid calendar date`);
  }
}

export function normalizeSourceRecord(record) {
  requireSourceObject(record, [...requiredFields, ...listFields, ...nullableFields], requiredFields, 'Source record');
  const normalized = {};
  for (const field of requiredFields) normalized[field] = requireSourceText(record[field], field);
  requireSourceHash(record.contentSha256, 'contentSha256');
  if (sourceTextHash(record.content) !== record.contentSha256) throw new Error('Source content hash does not match captured text');
  if (!['present', 'missing-last-known'].includes(record.presence)) throw new Error('Unsupported source presence');
  if (!['active', 'deprecated', 'retired'].includes(record.sourceLifecycle)) throw new Error('Unsupported source lifecycle');
  for (const field of listFields) normalized[field] = uniqueTextList(record[field] === undefined ? [] : record[field], field, field !== 'evidence');
  for (const field of nullableFields) normalized[field] = record[field] === undefined || record[field] === null ? null : requireSourceText(record[field], field);
  if ([normalized.originRepository, normalized.originCommit, normalized.originReferenceUrl].some(value => value !== null)) {
    requireSourceText(normalized.originRepository, 'originRepository');
    if (typeof normalized.originCommit !== 'string' || !/^[a-f0-9]{40}$/.test(normalized.originCommit)) throw new Error('Remote source origin requires a resolved commit');
    requireSourceText(normalized.originReferenceUrl, 'originReferenceUrl');
    let reference;
    try { reference = new URL(normalized.originReferenceUrl); }
    catch { throw new Error('Invalid remote source reference URL'); }
    if (reference.protocol !== 'https:' || reference.username || reference.password || reference.search || reference.hash) throw new Error('Remote source references require HTTPS without credentials, query or fragment');
  }
  for (const field of ['deprecatedOn', 'retiredOn']) if (normalized[field] !== null) sourceDate(normalized[field], field);
  if (normalized.presence === 'missing-last-known') {
    if (normalized.removedAt === null || !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,7})?Z$/.test(normalized.removedAt) || !Number.isFinite(Date.parse(normalized.removedAt)) || new Date(normalized.removedAt).toISOString().slice(0, 19) !== normalized.removedAt.slice(0, 19)) {
      throw new Error('Missing source records require a valid UTC removedAt observation');
    }
  } else if (normalized.removedAt !== null) {
    throw new Error('Present source records must not declare removedAt');
  }
  if (normalized.replacementIds.includes(normalized.sourceId)) throw new Error('A source cannot replace itself');
  return Object.freeze(normalized);
}

export function normalizeSourceRecords(records) {
  if (!Array.isArray(records)) throw new Error('Source records must be an array');
  const normalized = records.map(normalizeSourceRecord);
  if (new Set(normalized.map(record => record.sourceId)).size !== normalized.length) throw new Error('Duplicate source keys within a definition');
  return Object.freeze(normalized);
}

export function normalizeLegacySourceRecords(parserId, records) {
  if (!Array.isArray(records)) throw new Error('Legacy source records must be an array');
  if (parserId === 'contributor-guidance-v4') return normalizeSourceRecords(records.map(normalizeContributorRecord));
  const interactive = parserId === 'interactive-toolkit-v4';
  const proposals = parserId === 'maintainer-proposals-v4';
  if (!interactive && !proposals) throw new Error('Unsupported legacy source parser adapter');
  const specificFields = interactive
    ? ['contractPath', 'sourceIds', 'replacementIds', 'deprecatedOn', 'retiredOn', 'lifecycleReason']
    : ['surface', 'ruleText', 'rationale'];
  const required = interactive ? ['contractPath', 'sourceIds'] : ['surface', 'ruleText', 'rationale'];
  return normalizeSourceRecords(records.map(record => {
    requireSourceObject(record, [...commonLegacyFields, ...specificFields], [...requiredFields, 'provenance', 'evidence', ...required], 'Legacy source record');
    for (const field of [...required.filter(field => field !== 'sourceIds'), ...nullableFields.filter(field => Object.hasOwn(record, field))]) requireSourceText(record[field], field);
    if (!['present', 'removed'].includes(record.presence)) throw new Error('Unsupported legacy source presence');
    if (record.presence === 'present' && Object.hasOwn(record, 'removedAt')) throw new Error('Present legacy records must not declare removedAt');
    const provenance = interactive
      ? ['published-upstream-standard', 'inferred-maintainer-convention', 'local-safeguard', 'unclassified']
      : ['confirmed-maintainer-convention', 'inferred-maintainer-convention', 'local-safeguard'];
    if (!provenance.includes(record.provenance)) throw new Error('Unsupported legacy provenance');
    const keyPattern = interactive ? /^[A-Z]+(?:-[A-Z0-9]+)+-[0-9]{3}[A-Z]?$/ : /^[A-Z]+-[A-Z0-9]+-[0-9]+[A-Z]?$/;
    if (!keyPattern.test(record.sourceId)) throw new Error('Invalid legacy source key');
    if (proposals && record.sourceId.length > 32) throw new Error('Legacy proposal source key exceeds its contract limit');
    if (interactive && (!Array.isArray(record.evidence) || new Set(record.evidence).size !== record.evidence.length)) throw new Error('Interactive source evidence must be unique');
    if (interactive && !/^\.github\/instructions\/[a-z0-9-]+-compliance-contract\.instructions\.md$/.test(record.contractPath)) throw new Error('Invalid legacy contract locator');
    if (interactive && (!Array.isArray(record.sourceIds) || record.sourceIds.some(value => typeof value !== 'string' || !/^[a-z][a-z0-9-]*$/.test(value)))) throw new Error('Invalid legacy document references');
    if (interactive && Object.hasOwn(record, 'replacementIds') && (!Array.isArray(record.replacementIds) || record.replacementIds.length === 0 || record.replacementIds.some(value => typeof value !== 'string' || !keyPattern.test(value)))) throw new Error('Invalid legacy replacement keys');
    if (proposals && !['active', 'retired'].includes(record.sourceLifecycle)) throw new Error('Unsupported proposal lifecycle');
    if (proposals && !['implementation', 'testing', 'documentation'].includes(record.surface)) throw new Error('Unsupported legacy proposal surface');
    return {
      ...Object.fromEntries(requiredFields.map(field => [field, record[field]])),
      presence: record.presence === 'removed' ? 'missing-last-known' : 'present',
      provenanceCodes: [requireSourceText(record.provenance, 'provenance')],
      evidence: record.evidence,
      sourceIds: interactive ? record.sourceIds : [],
      replacementIds: interactive ? record.replacementIds ?? [] : [],
      applicabilityCodes: proposals ? [record.surface] : [],
      ...Object.fromEntries(nullableFields.map(field => [field, record[field] ?? null])),
    };
  }));
}

function normalizeContributorRecord(record) {
  const originFields = ['repository', 'resolvedCommit', 'referenceUrl'];
  requireSourceObject(record, [...requiredFields, 'removedAt', ...originFields], [...requiredFields, ...originFields], 'Contributor source record');
  if (!['present', 'removed'].includes(record.presence) || record.sourceLifecycle !== 'active') throw new Error('Unsupported contributor source presence or lifecycle');
  if (record.presence === 'present' && Object.hasOwn(record, 'removedAt')) throw new Error('Present legacy records must not declare removedAt');
  if (record.repository !== 'hashicorp/terraform-provider-azurerm') throw new Error('Unsupported legacy contributor repository');
  if (typeof record.location !== 'string' || !/^contributing\/(?:README\.md|topics\/[a-z0-9-]+(?:\/[a-z0-9-]+)*\.md)$/.test(record.location)) throw new Error('Invalid contributor source locator');
  const sourceId = record.location === 'contributing/README.md' ? 'contributing-readme' : record.location.slice('contributing/topics/'.length, -'.md'.length).replaceAll('/', '-');
  if (record.sourceId !== sourceId) throw new Error('Contributor source key does not match its locator');
  if (typeof record.resolvedCommit !== 'string' || !/^[a-f0-9]{40}$/.test(record.resolvedCommit)) throw new Error('Invalid contributor resolved commit');
  const reference = `https://github.com/${record.repository}/blob/${record.resolvedCommit}/${record.location}`;
  if (record.referenceUrl !== reference) throw new Error('Contributor reference does not match captured repository, commit and locator');
  return {
    ...Object.fromEntries(requiredFields.map(field => [field, record[field]])),
    presence: record.presence === 'removed' ? 'missing-last-known' : 'present',
    removedAt: record.removedAt ?? null,
    provenanceCodes: ['published-upstream-standard'],
    originRepository: record.repository,
    originCommit: record.resolvedCommit,
    originReferenceUrl: record.referenceUrl,
  };
}
