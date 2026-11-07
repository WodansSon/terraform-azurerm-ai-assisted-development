import { closeSync, lstatSync, openSync, unlinkSync } from 'node:fs';
import { dirname, isAbsolute, resolve } from 'node:path';

let sqlite;
try {
  sqlite = await import('node:sqlite');
} catch {
  throw new Error('Workbench requires native Node node:sqlite support; install the verified Node 26.13.0 runtime. The sqlite3 CLI is not required.');
}

const inspectionPragmas = new Set([
  'foreign_key_check', 'foreign_key_list', 'index_info', 'index_list',
  'index_xinfo', 'integrity_check', 'quick_check', 'table_info',
  'table_list', 'table_xinfo',
]);

function verifyEngine(database) {
  const version = database.prepare('SELECT sqlite_version() AS version').get().version;
  const components = version.split('.').map(Number);
  if (components[0] < 3 || (components[0] === 3 && components[1] < 37)) {
    throw new Error('Workbench requires embedded SQLite 3.37.0 or newer with STRICT tables; upgrade the native Node runtime, not the sqlite3 CLI.');
  }
  if (typeof database.setAuthorizer !== 'function') {
    throw new Error('Workbench requires the native SQLite authorizer API; install the verified Node 26.13.0 runtime.');
  }
  return version;
}

function installGuards(database) {
  const { constants } = sqlite;
  database.setAuthorizer((operation, argument, value) => {
    if (operation === constants.SQLITE_ATTACH || operation === constants.SQLITE_DETACH) {
      return constants.SQLITE_DENY;
    }
    if (operation === constants.SQLITE_PRAGMA && value !== null && !inspectionPragmas.has(argument.toLowerCase())) {
      return constants.SQLITE_DENY;
    }
    return constants.SQLITE_OK;
  });
}

function openConnection(databasePath, readOnly, busyTimeoutMilliseconds, durable = false) {
  const database = new sqlite.DatabaseSync(databasePath, {
    readOnly,
    enableForeignKeyConstraints: true,
    enableDoubleQuotedStringLiterals: false,
    allowExtension: false,
  });
  try {
    const engineVersion = verifyEngine(database);
    database.exec('PRAGMA foreign_keys = ON');
    if (database.prepare('PRAGMA foreign_keys').get()?.foreign_keys !== 1) {
      throw new Error('Workbench refused a SQLite connection without foreign-key enforcement.');
    }
    database.exec(`PRAGMA busy_timeout = ${busyTimeoutMilliseconds}`);
    if (database.prepare('PRAGMA busy_timeout').get()?.timeout !== busyTimeoutMilliseconds) {
      throw new Error('Workbench could not establish its bounded SQLite busy timeout.');
    }
    if (durable) {
      if (database.prepare('PRAGMA journal_mode = WAL').get()?.journal_mode !== 'wal') {
        throw new Error('Workbench could not establish WAL mode for its writable database.');
      }
      database.exec('PRAGMA synchronous = FULL');
      if (database.prepare('PRAGMA synchronous').get()?.synchronous !== 2) {
        throw new Error('Workbench could not establish durable synchronous writes.');
      }
    }
    if (readOnly) {
      database.exec('PRAGMA query_only = ON');
      if (database.prepare('PRAGMA query_only').get()?.query_only !== 1) {
        throw new Error('Workbench could not establish its read-only SQLite connection.');
      }
    }
    installGuards(database);
    return Object.freeze({
      engineVersion,
      readOnly,
      get isTransaction() { return database.isTransaction; },
      all(sql, parameters = []) { return database.prepare(sql).all(...parameters); },
      get(sql, parameters = []) { return database.prepare(sql).get(...parameters); },
      run(sql, parameters = []) { return database.prepare(sql).run(...parameters); },
      exec(sql) { database.exec(sql); },
      close() { database.close(); },
    });
  } catch (error) {
    database.close();
    throw error;
  }
}

function verifyStrictSupport(busyTimeoutMilliseconds) {
  const probe = openConnection(':memory:', false, busyTimeoutMilliseconds);
  try {
    probe.exec('CREATE TABLE capability_probe (id INTEGER PRIMARY KEY) STRICT');
    if (probe.get("SELECT strict FROM pragma_table_list WHERE name = 'capability_probe'")?.strict !== 1) {
      throw new Error('Workbench requires working STRICT-table support in its embedded SQLite binding.');
    }
  } finally {
    probe.close();
  }
}

function verifyDatabasePath(databasePath, creation = false) {
  if (typeof databasePath !== 'string' || !isAbsolute(databasePath) || databasePath.includes('\0') || databasePath.startsWith('\\\\') || databasePath.startsWith('//')) {
    throw new Error('SQLite inspection requires an explicit absolute local database path.');
  }
  const selectedPath = resolve(databasePath);
  let currentPath = selectedPath;
  while (true) {
    let entry;
    try { entry = lstatSync(currentPath); }
    catch (error) {
      if (!(creation && currentPath === selectedPath && error.code === 'ENOENT')) throw error;
    }
    if (entry && creation && currentPath === selectedPath) {
      throw new Error('SQLite creation requires a new database path; the existing destination is preserved.');
    }
    if (entry?.isSymbolicLink()) {
      throw new Error('SQLite inspection paths must not use symbolic links or junctions.');
    }
    if (entry && currentPath === selectedPath && !entry.isFile()) {
      throw new Error('SQLite inspection requires an existing database file.');
    }
    const parentPath = dirname(currentPath);
    if (parentPath === currentPath) break;
    currentPath = parentPath;
  }
  return selectedPath;
}

export function openWorkbenchSqlite({ mode, databasePath, busyTimeoutMilliseconds = 1000 } = {}) {
  if (!Number.isInteger(busyTimeoutMilliseconds) || busyTimeoutMilliseconds < 0 || busyTimeoutMilliseconds > 5000) {
    throw new Error('SQLite busy timeout must be an integer between 0 and 5000 milliseconds.');
  }
  if (!['memory', 'create', 'read-only', 'read-write'].includes(mode)) {
    throw new Error('Select memory, create, read-only, or read-write SQLite mode explicitly.');
  }
  if (mode === 'memory' && databasePath !== undefined) {
    throw new Error('In-memory SQLite connections do not accept a database path.');
  }
  const selectedPath = mode === 'memory' ? ':memory:' : verifyDatabasePath(databasePath, mode === 'create');
  verifyStrictSupport(busyTimeoutMilliseconds);
  if (mode === 'create') {
    const descriptor = openSync(selectedPath, 'wx', 0o600);
    closeSync(descriptor);
    const created = lstatSync(selectedPath);
    try { return openConnection(selectedPath, false, busyTimeoutMilliseconds, true); }
    catch (error) {
      const current = lstatSync(selectedPath, { throwIfNoEntry: false });
      if (current && current.dev === created.dev && current.ino === created.ino) unlinkSync(selectedPath);
      throw error;
    }
  }
  const original = mode === 'read-write' ? lstatSync(selectedPath) : null;
  const connection = openConnection(selectedPath, mode === 'read-only', busyTimeoutMilliseconds, mode === 'read-write');
  if (original) {
    const current = lstatSync(selectedPath, { throwIfNoEntry: false });
    if (!current || current.dev !== original.dev || current.ino !== original.ino) {
      connection.close();
      throw new Error('Writable database identity changed while opening; no replacement workspace is accepted.');
    }
  }
  return connection;
}
