import { requireSourceObject, requireSourceText, requireSourceHash, sourceTextHash, normalizeCapturedSourceFiles } from './WorkbenchSourceRecords.mjs';

const blockFields = ['id', 'title', 'surfaceCode', 'relativePath', 'content', 'contentSha256', 'text', 'provenance', 'protectionReason'];

function identity(value) {
  if (!Number.isSafeInteger(value) || value < 1) throw new Error('Protected repository context must be a positive safe integer');
}

function relativePath(value) {
  requireSourceText(value, 'Protected relative path');
  if (!/^[A-Za-z0-9._/-]+$/.test(value) || value.startsWith('/') || value.split('/').some(part => !part || part === '..' || part === '.')) throw new Error('Protected paths must be scoped repository-relative paths');
  return value;
}

function transaction(connection, operation) {
  connection.exec('SAVEPOINT workbench_protected_capture');
  try {
    const result = operation();
    connection.exec('RELEASE workbench_protected_capture');
    return result;
  } catch (error) {
    try { connection.exec('ROLLBACK TO workbench_protected_capture; RELEASE workbench_protected_capture'); }
    catch (rollbackError) { throw new AggregateError([error, rollbackError], 'Protected capture and rollback failed'); }
    throw error;
  }
}

export function createProtectedSnapshotSchema(connection) {
  for (const [table, columns] of Object.entries({
    repository_contexts: ['id', 'repository_id', 'branch_ref', 'commit_oid', 'observed_at'],
    guidance_surfaces: ['id', 'code', 'label'],
    rules: ['id', 'displayed_id', 'rule_kind', 'naming_scheme_id'],
    wording_versions: ['id', 'text', 'content_sha256', 'created_at'],
    rule_versions: ['id', 'rule_id', 'revision', 'wording_version_id', 'lifecycle', 'retirement_reason', 'origin_code', 'documentation_gap'],
    rule_provenances: ['rule_version_id', 'ordinal', 'code'],
  })) {
    const existing = new Set(connection.all('SELECT name FROM pragma_table_info(?)', [table]).map(column => column.name));
    if (columns.some(column => !existing.has(column))) throw new Error('Protected schema requires complete context, surface, rule and wording dependencies');
  }
  transaction(connection, () => {
    connection.exec(`
      CREATE TABLE protected_snapshots (
        id INTEGER PRIMARY KEY, repository_context_id INTEGER NOT NULL REFERENCES repository_contexts(id), captured_at TEXT NOT NULL,
        content_sha256 TEXT NOT NULL CHECK(length(content_sha256) = 64 AND content_sha256 NOT GLOB '*[^0-9a-f]*'),
        parser_contract_sha256 TEXT NOT NULL CHECK(length(parser_contract_sha256) = 64 AND parser_contract_sha256 NOT GLOB '*[^0-9a-f]*'),
        finalized INTEGER NOT NULL DEFAULT 0 CHECK(finalized IN (0, 1)), UNIQUE(repository_context_id, content_sha256)
      ) STRICT;
      CREATE TABLE protected_files (
        id INTEGER PRIMARY KEY, snapshot_id INTEGER NOT NULL REFERENCES protected_snapshots(id), relative_path TEXT NOT NULL,
        content BLOB NOT NULL, content_sha256 TEXT NOT NULL CHECK(length(content_sha256) = 64 AND content_sha256 NOT GLOB '*[^0-9a-f]*'),
        UNIQUE(snapshot_id, relative_path), UNIQUE(id, snapshot_id)
      ) STRICT;
      CREATE TABLE protected_rule_details (
        rule_version_id INTEGER PRIMARY KEY REFERENCES rule_versions(id), surface_id INTEGER NOT NULL REFERENCES guidance_surfaces(id),
        title TEXT NOT NULL, canonical_block TEXT NOT NULL, block_sha256 TEXT NOT NULL CHECK(length(block_sha256) = 64 AND block_sha256 NOT GLOB '*[^0-9a-f]*'),
        protection_reason TEXT NOT NULL
      ) STRICT;
      CREATE TABLE protected_members (
        file_id INTEGER NOT NULL, rule_version_id INTEGER NOT NULL REFERENCES protected_rule_details(rule_version_id),
        snapshot_id INTEGER NOT NULL, rule_id INTEGER NOT NULL,
        PRIMARY KEY(file_id, rule_version_id), UNIQUE(snapshot_id, rule_id),
        FOREIGN KEY(file_id, snapshot_id) REFERENCES protected_files(id, snapshot_id),
        FOREIGN KEY(rule_id, rule_version_id) REFERENCES rule_versions(rule_id, id)
      ) STRICT;
      CREATE TRIGGER protected_rule_kind BEFORE INSERT ON protected_rule_details
        WHEN NOT EXISTS(SELECT 1 FROM rule_versions version JOIN rules rule ON rule.id = version.rule_id
          WHERE version.id = NEW.rule_version_id AND rule.rule_kind = 'protected' AND version.lifecycle = 'active')
        BEGIN SELECT RAISE(ABORT, 'Protected details require an active protected rule version'); END;
    `);
    for (const operation of ['UPDATE', 'DELETE']) {
      connection.exec(`CREATE TRIGGER protected_snapshot_${operation} BEFORE ${operation} ON protected_snapshots WHEN OLD.finalized = 1 BEGIN SELECT RAISE(ABORT, 'Finalized protected snapshots are immutable'); END`);
      connection.exec(`CREATE TRIGGER protected_details_${operation} BEFORE ${operation} ON protected_rule_details BEGIN SELECT RAISE(ABORT, 'Protected block details are immutable'); END`);
    }
    for (const table of ['protected_files', 'protected_members']) for (const operation of ['INSERT', 'UPDATE', 'DELETE']) {
      const row = operation === 'INSERT' ? 'NEW' : 'OLD';
      const destination = operation === 'UPDATE' ? ' OR EXISTS(SELECT 1 FROM protected_snapshots WHERE id = NEW.snapshot_id AND finalized = 1)' : '';
      connection.exec(`CREATE TRIGGER ${table}_${operation} BEFORE ${operation} ON ${table} WHEN EXISTS(SELECT 1 FROM protected_snapshots WHERE id = ${row}.snapshot_id AND finalized = 1)${destination} BEGIN SELECT RAISE(ABORT, 'Finalized protected capture is immutable'); END`);
    }
    for (const operation of ['UPDATE', 'DELETE']) {
      for (const [table, condition] of [
        ['rule_versions', 'EXISTS(SELECT 1 FROM protected_rule_details WHERE rule_version_id = OLD.id)'],
        ['rules', 'EXISTS(SELECT 1 FROM rule_versions version JOIN protected_rule_details detail ON detail.rule_version_id = version.id WHERE version.rule_id = OLD.id)'],
        ['wording_versions', 'EXISTS(SELECT 1 FROM rule_versions version JOIN protected_rule_details detail ON detail.rule_version_id = version.id WHERE version.wording_version_id = OLD.id)'],
        ['rule_provenances', 'EXISTS(SELECT 1 FROM protected_rule_details WHERE rule_version_id = OLD.rule_version_id)'],
      ]) connection.exec(`CREATE TRIGGER protected_${table}_${operation} BEFORE ${operation} ON ${table} WHEN ${condition} BEGIN SELECT RAISE(ABORT, 'Captured protected rule facts are immutable'); END`);
    }
    connection.exec(`CREATE TRIGGER protected_provenance_INSERT BEFORE INSERT ON rule_provenances
      WHEN EXISTS(SELECT 1 FROM protected_rule_details WHERE rule_version_id = NEW.rule_version_id)
      BEGIN SELECT RAISE(ABORT, 'Captured protected provenance is immutable'); END`);
  });
}

export function protectedCaptureFromParser(capture, authority) {
  requireSourceObject(capture, ['Files', 'Blocks', 'Catalog'], ['Files', 'Blocks', 'Catalog'], 'Parsed protected capture');
  const authorityFields = ['repositoryContextId', 'parserContractSha256', 'requiredFiles'];
  requireSourceObject(authority, authorityFields, authorityFields, 'Protected capture authority');
  if (!Array.isArray(capture.Files) || !Array.isArray(capture.Blocks)) throw new Error('Parsed protected capture requires file and block arrays');
  const files = normalizeCapturedSourceFiles(capture.Files.map(file => {
    if (!Array.isArray(file.contentBytes) || file.contentBytes.some(value => !Number.isInteger(value) || value < 0 || value > 255)) throw new Error('Parsed file transport requires exact byte values');
    return { ...file, contentBytes: Buffer.from(file.contentBytes) };
  }));
  const blocks = capture.Blocks.map(block => {
    const fields = ['id', 'title', 'surface', 'fields', 'sourcePath', 'relativeSourcePath', 'normalizedContent', 'contentSha256', 'frontmatter'];
    requireSourceObject(block, fields, fields, 'Parsed protected block');
    requireSourceObject(block.fields, ['Rule', 'Provenance', 'Rationale'], ['Rule', 'Provenance', 'Rationale'], 'Protected block fields');
    return { id: block.id, title: block.title, surfaceCode: block.surface, relativePath: block.relativeSourcePath, content: block.normalizedContent,
      contentSha256: block.contentSha256, text: block.fields.Rule, provenance: block.fields.Provenance, protectionReason: block.fields.Rationale };
  });
  requireSourceObject(capture.Catalog, ['$schema', 'schemaVersion', 'rules'], ['$schema', 'schemaVersion', 'rules'], 'Protected parser projection');
  if (capture.Catalog.$schema !== 'protected-rules.schema.json' || capture.Catalog.schemaVersion !== 1 || !Array.isArray(capture.Catalog.rules) || capture.Catalog.rules.length !== blocks.length) throw new Error('Protected parser projection does not match captured blocks');
  for (const block of blocks) {
    const matches = capture.Catalog.rules.filter(rule => rule.id === block.id);
    if (matches.length !== 1) throw new Error('Protected parser projection does not match captured identity');
    const rule = matches[0];
    const expected = { id: block.id, status: 'protected', surfaceId: block.surfaceCode, title: block.title, text: block.text, provenance: block.provenance,
      protectionReason: block.protectionReason, impact: 100, sourcePath: block.relativePath, contentSha256: block.contentSha256 };
    requireSourceObject(rule, Object.keys(expected), Object.keys(expected), 'Projected protected rule');
    if (Object.entries(expected).some(([field, value]) => rule[field] !== value)) throw new Error('Protected projection fields differ from the captured block');
  }
  return { ...authority, files, blocks };
}

export function readProtectedSnapshot(connection, snapshotId) {
  identity(snapshotId);
  const snapshot = connection.get('SELECT * FROM protected_snapshots WHERE id = ? AND finalized = 1', [snapshotId]);
  if (!snapshot) throw new Error('A complete protected snapshot is required');
  const files = connection.all('SELECT relative_path, content, content_sha256 FROM protected_files WHERE snapshot_id = ? ORDER BY relative_path', [snapshotId]).map(file => ({
    relativePath: file.relative_path, contentBytes: Buffer.from(file.content), contentSha256: file.content_sha256,
  }));
  const blocks = connection.all(`SELECT rule.displayed_id, detail.*, surface.code AS surface_code, wording.text, provenance.code AS provenance,
      file.relative_path, member.rule_version_id
    FROM protected_members member JOIN protected_files file ON file.id = member.file_id
    JOIN rules rule ON rule.id = member.rule_id JOIN rule_versions version ON version.id = member.rule_version_id
    JOIN protected_rule_details detail ON detail.rule_version_id = version.id
    JOIN wording_versions wording ON wording.id = version.wording_version_id JOIN guidance_surfaces surface ON surface.id = detail.surface_id
    JOIN rule_provenances provenance ON provenance.rule_version_id = version.id AND provenance.ordinal = 0
    WHERE member.snapshot_id = ? ORDER BY rule.displayed_id`, [snapshotId]).map(block => ({
    id: block.displayed_id, title: block.title, surfaceCode: block.surface_code, relativePath: block.relative_path,
    content: block.canonical_block, contentSha256: block.block_sha256, text: block.text, provenance: block.provenance,
    protectionReason: block.protection_reason, ruleVersionId: block.rule_version_id,
  }));
  return { snapshotId, repositoryContextId: snapshot.repository_context_id, capturedAt: snapshot.captured_at, contentSha256: snapshot.content_sha256, parserContractSha256: snapshot.parser_contract_sha256, files, blocks };
}

export function ingestProtectedCapture(connection, request) {
  const fields = ['repositoryContextId', 'parserContractSha256', 'requiredFiles', 'files', 'blocks'];
  requireSourceObject(request, fields, fields, 'Protected capture');
  identity(request.repositoryContextId);
  requireSourceHash(request.parserContractSha256, 'Protected parser contract hash');
  if (!Array.isArray(request.requiredFiles) || request.requiredFiles.length === 0 || !Array.isArray(request.files) || !Array.isArray(request.blocks)) throw new Error('A complete protected capture and required file set are required');
  const required = request.requiredFiles.map(relativePath);
  if (new Set(required).size !== required.length) throw new Error('Required protected paths must be unique');
  const files = normalizeCapturedSourceFiles(request.files);
  const paths = new Set(files.map(file => file.relativePath));
  if (paths.size !== files.length || required.some(path => !paths.has(path))) throw new Error('Protected capture has duplicate or missing required files');
  const blocks = request.blocks.map(block => {
    requireSourceObject(block, blockFields, blockFields, 'Protected block');
    for (const field of blockFields) requireSourceText(block[field], field);
    requireSourceHash(block.contentSha256, 'Protected block hash');
    if (sourceTextHash(block.content) !== block.contentSha256 || !paths.has(block.relativePath)) throw new Error('Protected block hash or captured file does not match');
    if (!['local-safeguard', 'confirmed-maintainer-convention', 'inferred-maintainer-convention'].includes(block.provenance)) throw new Error('Unsupported protected provenance');
    return Object.fromEntries(blockFields.map(field => [field, block[field]]));
  }).sort((left, right) => left.id < right.id ? -1 : left.id > right.id ? 1 : 0);
  if (new Set(blocks.map(block => block.id)).size !== blocks.length) throw new Error('Duplicate protected rule identity');
  const fingerprint = sourceTextHash(JSON.stringify({ parserContractSha256: request.parserContractSha256, files: files.map(({ relativePath: path, contentSha256 }) => ({ path, contentSha256 })), blocks }));
  return transaction(connection, () => {
    const reused = connection.get('SELECT id FROM protected_snapshots WHERE repository_context_id = ? AND content_sha256 = ? AND finalized = 1', [request.repositoryContextId, fingerprint]);
    if (reused) return readProtectedSnapshot(connection, reused.id);
    const now = new Date().toISOString();
    const snapshotId = Number(connection.run('INSERT INTO protected_snapshots(repository_context_id, captured_at, content_sha256, parser_contract_sha256) VALUES (?, ?, ?, ?)', [request.repositoryContextId, now, fingerprint, request.parserContractSha256]).lastInsertRowid);
    const fileIds = new Map(files.map(file => [file.relativePath, Number(connection.run('INSERT INTO protected_files(snapshot_id, relative_path, content, content_sha256) VALUES (?, ?, ?, ?)', [snapshotId, file.relativePath, file.contentBytes, file.contentSha256]).lastInsertRowid)]));
    for (const block of blocks) {
      const surface = connection.get('SELECT id FROM guidance_surfaces WHERE code = ?', [block.surfaceCode]);
      if (!surface) throw new Error('Protected surface is not registered by the selected profile');
      connection.run("INSERT INTO rules(displayed_id, rule_kind, naming_scheme_id) VALUES (?, 'protected', NULL) ON CONFLICT(displayed_id) DO NOTHING", [block.id]);
      const rule = connection.get('SELECT id, rule_kind FROM rules WHERE displayed_id = ?', [block.id]);
      if (rule.rule_kind !== 'protected') throw new Error('Rule identity is defined by both managed and protected sources');
      let version = connection.get(`SELECT version.id FROM rule_versions version JOIN protected_rule_details detail ON detail.rule_version_id = version.id
        JOIN wording_versions wording ON wording.id = version.wording_version_id JOIN rule_provenances provenance ON provenance.rule_version_id = version.id AND provenance.ordinal = 0
        WHERE version.rule_id = ? AND detail.canonical_block = ? AND detail.block_sha256 = ? AND detail.title = ? AND detail.protection_reason = ?
          AND detail.surface_id = ? AND wording.text = ? AND provenance.code = ?`, [rule.id, block.content, block.contentSha256, block.title, block.protectionReason, surface.id, block.text, block.provenance]);
      if (!version) {
        let wording = connection.get('SELECT id, text FROM wording_versions WHERE content_sha256 = ? AND text = ?', [sourceTextHash(block.text), block.text]);
        if (!wording) wording = { id: Number(connection.run('INSERT INTO wording_versions(text, content_sha256, created_at) VALUES (?, ?, ?)', [block.text, sourceTextHash(block.text), now]).lastInsertRowid) };
        const revision = connection.get('SELECT coalesce(max(revision), 0) + 1 AS revision FROM rule_versions WHERE rule_id = ?', [rule.id]).revision;
        version = { id: Number(connection.run("INSERT INTO rule_versions(rule_id, revision, wording_version_id, lifecycle, retirement_reason, origin_code, documentation_gap) VALUES (?, ?, ?, 'active', NULL, NULL, NULL)", [rule.id, revision, wording.id]).lastInsertRowid) };
        connection.run('INSERT INTO rule_provenances VALUES (?, 0, ?)', [version.id, block.provenance]);
        connection.run('INSERT INTO protected_rule_details VALUES (?, ?, ?, ?, ?, ?)', [version.id, surface.id, block.title, block.content, block.contentSha256, block.protectionReason]);
      }
      connection.run('INSERT INTO protected_members VALUES (?, ?, ?, ?)', [fileIds.get(block.relativePath), version.id, snapshotId, rule.id]);
    }
    connection.run('UPDATE protected_snapshots SET finalized = 1 WHERE id = ?', [snapshotId]);
    return readProtectedSnapshot(connection, snapshotId);
  });
}
