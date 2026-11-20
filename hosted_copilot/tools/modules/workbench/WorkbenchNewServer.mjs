import { createServer } from 'node:http';
import { createHash, randomBytes, timingSafeEqual } from 'node:crypto';
import { readFile, realpath } from 'node:fs/promises';
import { resolve, sep, extname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { openWorkbenchSqlite } from './WorkbenchSqlite.mjs';
import { validateWorkbenchApplicationSchema } from './WorkbenchApplicationSchema.mjs';
import { readNativeWorkspaceView, readNativeWorkspaceReadiness } from './WorkbenchWorkspace.mjs';
import { saveSourceChange, updatePlanMembership, WorkbenchChangeError } from './WorkbenchChanges.mjs';
import { readPublishedGuidance } from './WorkbenchPublishedGuidance.mjs';
import { createWorkbenchAudit } from './WorkbenchAudit.mjs';

const nativeAssets = fileURLToPath(new URL('../../../workbench/', import.meta.url));
const nativeClient = fileURLToPath(new URL('../../../workbench/app.js', import.meta.url));
const mimeTypes = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.svg': 'image/svg+xml', '.json': 'application/json', '.woff2': 'font/woff2' };
const fixedAssets = ['index.html', 'app.js', 'styles.css', 'hierarchical-view.js', 'statusbar.js', 'favicon.svg', 'assistance-waiting-phrases.json', 'llm-brands.json'];

export class WorkbenchNewLaunchError extends Error {
  constructor(checks) {
    super('Workbench New launch requirements are not satisfied');
    this.checks = checks;
  }
}

// Combine SQL readiness with local asset, guidance, publication, and capacity checks before opening the UI.
export async function inspectWorkbenchNewLaunch(connection, binding) {
  const readiness = readNativeWorkspaceReadiness(connection, { binding });
  let assetsAvailable = true;
  try {
    const root = await realpath(nativeAssets);
    for (const name of [...fixedAssets, 'sprite/sprite.svg']) {
      const path = await realpath(resolve(root, name));
      if (!path.startsWith(root + sep) || (await readFile(path)).length === 0) assetsAvailable = false;
    }
  } catch { assetsAvailable = false; }
  const view = readNativeWorkspaceView(connection, { binding });
  const published = await readPublishedGuidance(view.guidanceCapacity, { catalog: view.publishedCatalog });
  const files = new Map((published.files ?? []).map(file => [file.bucketId, file]));
  const requiresGuidanceMatch = !view.publishedCatalog && view.stagedCatalog?.captureKind === 'manual-guidance';
  const stagedMatchesGuidance = requiresGuidanceMatch
    ? view.stagedCatalog.guidanceFiles.length === published.files.length && view.stagedCatalog.guidanceFiles.every(captured =>
      published.files.some(current => current.relativePath === captured.relativePath && current.contentSha256 === captured.contentSha256))
    : true;
  const capacityFits = published.available && view.guidanceCapacity.buckets.every(bucket =>
    files.has(bucket.bucketId) && files.get(bucket.bucketId).currentGuardedTokens <= bucket.budgetTokens) &&
    [...files.values()].reduce((total, file) => total + file.currentGuardedTokens, 0) <= view.guidanceCapacity.policy.guidanceTokenBudget;
  readiness.checks.push(
    { name: 'runtime-assets', status: assetsAvailable ? 'passed' : 'failed', detail: 'All required New UI assets must be readable inside the New asset root' },
    { name: 'required-guidance', status: published.failures.length === 0 ? 'passed' : 'failed', detail: 'The current Terraform profile requires its manual instruction files and review skill' },
    ...published.failures.map(failure => ({ name: `required-guidance/${failure.relativePath}`, status: 'failed',
      detail: `Required repository guidance is ${failure.reason}: ${failure.relativePath}; restore or correct the file before relaunching` })),
    ...(view.publishedCatalog ? [{ name: 'published-catalog-file', status: published.catalogSha256 === view.publishedCatalog.contentSha256 ? 'passed' : 'failed',
      detail: published.catalogSha256 === view.publishedCatalog.contentSha256 ? 'Established catalog file matches its SQL publication' : `Established catalog file validation failed: ${published.reason}` }] : []),
    ...(requiresGuidanceMatch ? [{ name: 'staged-guidance-current', status: stagedMatchesGuidance ? 'passed' : 'failed',
      detail: 'Initial staged guidance must match all current required repository guidance files' }] : []),
    { name: 'guidance-capacity', status: capacityFits ? 'passed' : 'failed', detail: 'Required guidance must fit every safety-adjusted bucket and the total token budget' },
  );
  readiness.ready = readiness.checks.every(check => check.status === 'passed');
  return readiness;
}

// Check token shape before timing-safe comparison so malformed input cannot cause a buffer-length exception.
function validToken(candidate, expected) {
  return typeof candidate === 'string' && candidate.length === expected.length && /^[0-9a-f]+$/.test(candidate) &&
    timingSafeEqual(Buffer.from(candidate, 'utf8'), Buffer.from(expected, 'utf8'));
}

// Serve the bound workspace on loopback with a per-launch capability and separately supplied guarded mutation handlers.
export async function startWorkbenchNewServer({ connection, binding, port = 43143, ownerProcessId = null, saveChanges = null, changePlan = null, targetRepository = null, databasePath = null }) {
  if (!connection.readOnly || !Number.isInteger(port) || port < 0 || port > 65535) throw new Error('Workbench New requires a read-only selected workspace and valid port');
  const readiness = readNativeWorkspaceReadiness(connection, { binding });
  if (!readiness.ready) throw new WorkbenchNewLaunchError(readiness.checks);
  const operationToken = randomBytes(32).toString('hex');
  let origin;
  // Apply consistent browser isolation and no-store headers to both API responses and static assets.
  const respond = (response, status, body, contentType = 'application/json', head = false) => {
    const bytes = Buffer.isBuffer(body) ? body : Buffer.from(typeof body === 'string' ? body : JSON.stringify(body));
    response.writeHead(status, {
      'Content-Type': contentType + (contentType.startsWith('text/') || contentType === 'application/json' ? '; charset=utf-8' : ''),
      'Content-Length': bytes.length,
      'Cache-Control': 'no-store',
      'Content-Security-Policy': "default-src 'self'; script-src 'self'; style-src 'self'; font-src 'self'; connect-src 'self'; img-src 'self' data:; object-src 'none'; base-uri 'none'; frame-ancestors 'none'",
      'Cross-Origin-Resource-Policy': 'same-origin',
      'X-Content-Type-Options': 'nosniff',
      'Referrer-Policy': 'no-referrer',
    });
    response.end(head ? undefined : bytes);
  };
  const server = createServer(async (request, response) => {
    try {
      const expectedPort = server.address().port;
      if (![`127.0.0.1:${expectedPort}`, `localhost:${expectedPort}`].includes(request.headers.host)) {
        respond(response, 421, { error: 'misdirected-request' });
        return;
      }
      if (request.headers.origin && ![`http://127.0.0.1:${expectedPort}`, `http://localhost:${expectedPort}`].includes(request.headers.origin)) {
        respond(response, 403, { error: 'forbidden' });
        return;
      }
      const target = new URL(request.url, origin);
      if (target.pathname === '/api/changes' || target.pathname === '/api/plan') {
        if (!validToken(request.headers['x-workbench-operation-token'], operationToken)) { respond(response, 403, { error: 'forbidden' }); return; }
        if (target.search || request.headers['transfer-encoding']) { respond(response, 400, { error: 'unsupported-request-input' }); return; }
        if (request.method !== 'POST') { respond(response, 405, { error: 'method-not-allowed' }); return; }
        const mutate = target.pathname === '/api/plan' ? changePlan : saveChanges;
        if (typeof mutate !== 'function') { respond(response, 503, { error: 'sql-writes-unavailable' }); return; }
        const length = Number(request.headers['content-length']);
        if (!Number.isSafeInteger(length) || length < 1 || length > 1048576 || !/^application\/json(?:\s*;\s*charset=utf-8)?$/i.test(request.headers['content-type'] ?? '')) {
          respond(response, 400, { error: 'invalid-change-body' }); return;
        }
        const chunks = [];
        let received = 0;
        for await (const chunk of request) {
          received += chunk.length;
          if (received > 1048576) { respond(response, 413, { error: 'change-body-too-large' }); return; }
          chunks.push(chunk);
        }
        let change;
        try { change = JSON.parse(new TextDecoder('utf-8', { fatal: true }).decode(Buffer.concat(chunks))); } catch { respond(response, 400, { error: 'invalid-change-json' }); return; }
        try {
          const view = await mutate(change);
          view.publishedGuidance = await readPublishedGuidance(view.guidanceCapacity, { catalog: view.publishedCatalog });
          respond(response, 200, view);
        }
        catch (error) {
          if (error instanceof WorkbenchChangeError) respond(response, error.status, { error: error.code });
          else respond(response, 400, { error: 'source-change-refused' });
        }
        return;
      }
      if (target.pathname === '/api/workspace' || target.pathname === '/shutdown') {
        if (!validToken(request.headers['x-workbench-operation-token'], operationToken)) {
          respond(response, 403, { error: 'forbidden' });
          return;
        }
        if (target.search || request.headers['transfer-encoding'] || Number(request.headers['content-length'] || 0) !== 0) {
          respond(response, 400, { error: 'unsupported-request-input' });
          return;
        }
        const method = target.pathname === '/shutdown' ? 'POST' : 'GET';
        if (request.method !== method) { respond(response, 405, { error: 'method-not-allowed' }); return; }
        if (method === 'POST') {
          const audit = createWorkbenchAudit({ databasePath, binding, actionCode: 'exit-workbench' });
          const facts = { requestedPort: port, listenerPort: expectedPort, stateSaveOutcome: 'unknown' };
          audit.start('exit-workbench', facts);
          await audit.run(async () => {
            server.close();
            if (server.listening) throw new Error('Workbench listener shutdown could not be confirmed');
            audit.finish('succeeded', facts);
          });
          respond(response, 200, { status: 'closed', listenerStopped: true, stateSaveOutcome: 'unknown',
            audit: audit.result() });
        } else {
          const view = readNativeWorkspaceView(connection, { binding });
          view.publishedGuidance = await readPublishedGuidance(view.guidanceCapacity, { catalog: view.publishedCatalog });
          respond(response, 200, view);
        }
        return;
      }
      if (!['GET', 'HEAD'].includes(request.method)) { respond(response, 405, { error: 'method-not-allowed' }); return; }
      const head = request.method === 'HEAD';
      if (target.search) { respond(response, 400, { error: 'unsupported-request-input' }, 'application/json', head); return; }
      if (target.pathname === '/runtime-config') {
        respond(response, 200, { application: 'workbench-new', operationToken, targetRepository, workspaceEndpoint: '/api/workspace', capabilities: { read: true, save: typeof saveChanges === 'function', plan: typeof changePlan === 'function' } }, 'application/json', head);
        return;
      }
      if (target.pathname === '/shutdown-config.js') {
        respond(response, 200, 'globalThis.__HOSTED_RULE_WORKBENCH__ = Object.freeze({ application: "workbench-new" });', 'text/javascript', head);
        return;
      }
      if (target.pathname === '/app.js') { respond(response, 200, await readFile(nativeClient), 'text/javascript', head); return; }
      const name = target.pathname === '/' ? 'index.html' : target.pathname.slice(1);
      if (!fixedAssets.includes(name) && !/^sprite\/[A-Za-z0-9_./-]+$/.test(name)) { respond(response, 404, { error: 'not-found' }, 'application/json', head); return; }
      const path = await realpath(resolve(nativeAssets, name));
      const root = await realpath(nativeAssets);
      if (!path.startsWith(root + sep)) { respond(response, 404, { error: 'not-found' }, 'application/json', head); return; }
      respond(response, 200, await readFile(path), mimeTypes[extname(path)] ?? 'application/octet-stream', head);
    } catch {
      if (!response.headersSent) respond(response, 500, { error: 'workspace-read-failed' });
      else response.end();
    }
  });
  server.requestTimeout = 10000;
  server.headersTimeout = 10000;
  await new Promise((accept, reject) => {
    server.once('error', reject);
    server.listen(port, '127.0.0.1', accept);
  });
  origin = `http://127.0.0.1:${server.address().port}`;
  let ownerTimer;
  if (ownerProcessId) {
    ownerTimer = setInterval(() => {
      try { process.kill(ownerProcessId, 0); }
      catch { server.close(); }
    }, 1000);
    ownerTimer.unref();
  }
  server.once('close', () => clearInterval(ownerTimer));
  return { server, url: origin + '/', close: () => new Promise((accept, reject) => server.close(error =>
    error && error.code !== 'ERR_SERVER_NOT_RUNNING' ? reject(error) : accept())) };
}

let startupPhase = 'launch-input';

// Validate launcher-selected repository/model context before starting the server and wiring short-lived SQL writers.
async function main() {
  let input = '';
  for await (const chunk of process.stdin) {
    input += chunk;
    if (Buffer.byteLength(input) > 32768) throw new Error('Invalid launch input');
  }
  const selected = JSON.parse(input);
  if (typeof selected.repositoryRoot !== 'string' || typeof selected.branchRef !== 'string' || !Number.isSafeInteger(selected.ownerProcessId) || selected.ownerProcessId < 1) throw new Error('Invalid repository launch context');
  startupPhase = 'sqlite-runtime-and-database';
  const connection = openWorkbenchSqlite({ mode: 'read-only', databasePath: selected.databasePath });
  try {
    startupPhase = 'database-schema';
    if (!validateWorkbenchApplicationSchema(connection).valid) throw new Error('Invalid current workspace schema');
    startupPhase = 'repository-branch-binding';
    const workspace = connection.get(`SELECT workspace.database_guid AS databaseGuid, context.repository_id AS repositoryId,
      context.branch_ref AS branchRef, repository.canonical_name AS canonicalName
      FROM workspace_identity workspace JOIN repository_contexts context ON context.id = workspace.origin_context_id
      JOIN repositories repository ON repository.id = context.repository_id WHERE workspace.id = 1`);
    const canonicalName = 'local:' + createHash('sha256').update(resolve(selected.repositoryRoot)).digest('hex');
    if (!workspace || workspace.canonicalName !== canonicalName || workspace.branchRef !== selected.branchRef) throw new Error('Workspace does not belong to this repository and branch');
    const binding = { databaseGuid: workspace.databaseGuid, repositoryId: workspace.repositoryId, branchRef: workspace.branchRef };
    startupPhase = 'workspace-readiness';
    const readiness = await inspectWorkbenchNewLaunch(connection, binding);
    if (selected.preflightOnly === true) {
      console.log(JSON.stringify({ kind: 'preflight', ...readiness }));
      connection.close();
      return;
    }
    if (!readiness.ready) throw new WorkbenchNewLaunchError(readiness.checks);
    const assignmentKeys = ['taskCode', 'model', 'providerCode', 'adapterCode', 'reasoningEffort'];
    const assignmentKey = assignment => JSON.stringify(assignmentKeys.map(key => assignment[key]));
    if (!Array.isArray(selected.llmAssignments) || JSON.stringify(selected.llmAssignments.map(assignmentKey).sort()) !==
      JSON.stringify(readiness.llmAssignments.map(assignmentKey).sort())) {
      throw new WorkbenchNewLaunchError([{ name: 'llm-preflight-binding', status: 'failed', detail: 'Current model assignments must match the assignments verified by CLI preflight; relaunch after configuration changes' }]);
    }
    // Keep the server's reader separate from each guarded write and return state from the writer's committed view.
    const mutate = (command, input) => {
      const writer = openWorkbenchSqlite({ mode: 'read-write', databasePath: selected.databasePath });
      try {
        command(writer, binding, input);
        return readNativeWorkspaceView(writer, { binding });
      } finally { writer.close(); }
    };
    startupPhase = 'loopback-server';
    const instance = await startWorkbenchNewServer({ connection, binding, port: selected.port, ownerProcessId: selected.ownerProcessId,
      saveChanges: input => mutate(saveSourceChange, input), changePlan: input => mutate(updatePlanMembership, input),
      targetRepository: selected.targetRepository ?? null, databasePath: selected.databasePath });
    instance.server.once('close', () => connection.close());
    console.log(JSON.stringify({ kind: 'ready', url: instance.url }));
  } catch (error) { connection.close(); throw error; }
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main().catch(error => {
    console.log(JSON.stringify({ kind: 'failed', checks: error instanceof WorkbenchNewLaunchError ? error.checks : [
      { name: startupPhase, status: 'failed', detail: 'Launch failed during this phase; verify its required inputs and runtime. Private diagnostics are omitted' },
    ] }));
    process.exitCode = 1;
  });
}
