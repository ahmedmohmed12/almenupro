'use strict';

const fs = require('fs');
const path = require('path');

function loadDotEnv() {
  const envPath = path.join(__dirname, '..', '.env');
  if (!fs.existsSync(envPath)) return;
  const text = fs.readFileSync(envPath, 'utf8');
  for (const raw of text.split(/\r?\n/)) {
    const line = raw.trim();
    if (!line || line.startsWith('#')) continue;
    const eq = line.indexOf('=');
    if (eq < 1) continue;
    const key = line.slice(0, eq).trim();
    let value = line.slice(eq + 1).trim();
    if (
      (value.startsWith('"') && value.endsWith('"')) ||
      (value.startsWith("'") && value.endsWith("'"))
    ) {
      value = value.slice(1, -1);
    }
    if (key && process.env[key] == null) process.env[key] = value;
  }
}

loadDotEnv();

let mysql = null;
try {
  mysql = require('mysql2/promise');
} catch {
  mysql = null;
}

let pool = null;
let ready = false;
let initPromise = null;
let lastError = '';

function parseMysqlUrl(raw) {
  const url = new URL(String(raw));
  return {
    host: url.hostname,
    port: Number(url.port || 3306),
    user: decodeURIComponent(url.username || ''),
    password: decodeURIComponent(url.password || ''),
    database: decodeURIComponent(url.pathname.replace(/^\//, '')),
  };
}

function mysqlConfig() {
  const url = String(process.env.MYSQL_URL || process.env.DATABASE_URL || '').trim();
  if (url.startsWith('mysql://') || url.startsWith('mysql2://')) {
    return parseMysqlUrl(url.replace(/^mysql2:\/\//, 'mysql://'));
  }
  const host = String(process.env.MYSQL_HOST || '').trim();
  const database = String(process.env.MYSQL_DATABASE || process.env.MYSQL_DB || '').trim();
  if (!host && !database) return null;
  return {
    host: host || '127.0.0.1',
    port: Number(process.env.MYSQL_PORT || 3306),
    user: String(process.env.MYSQL_USER || process.env.MYSQL_USERNAME || 'root'),
    password: String(process.env.MYSQL_PASSWORD || ''),
    database: database || 'almenupro',
  };
}

function isConfigured() {
  return Boolean(mysqlConfig()) && Boolean(mysql);
}

function isReady() {
  return ready && Boolean(pool);
}

function errorMessage() {
  return lastError;
}

async function ensureSchema(connectionPool) {
  await connectionPool.query(`
    CREATE TABLE IF NOT EXISTS platform_docs (
      id VARCHAR(64) NOT NULL,
      payload LONGTEXT NOT NULL,
      updated_at VARCHAR(40) NOT NULL,
      PRIMARY KEY (id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  `);
}

async function connect() {
  if (isReady()) return pool;
  if (initPromise) return initPromise;

  initPromise = (async () => {
    if (!mysql) {
      throw new Error('mysql2 package is not installed (npm install mysql2)');
    }
    const config = mysqlConfig();
    if (!config || !config.database) {
      throw new Error('MYSQL_HOST / MYSQL_DATABASE (or MYSQL_URL) is required');
    }
    const next = mysql.createPool({
      host: config.host,
      port: config.port,
      user: config.user,
      password: config.password,
      database: config.database,
      waitForConnections: true,
      connectionLimit: Number(process.env.MYSQL_POOL_SIZE || 5),
      charset: 'utf8mb4',
      enableKeepAlive: true,
    });
    await next.query('SELECT 1');
    await ensureSchema(next);
    pool = next;
    ready = true;
    lastError = '';
    return pool;
  })().catch((error) => {
    ready = false;
    pool = null;
    initPromise = null;
    lastError = String(error?.message || error);
    throw error;
  });

  return initPromise;
}

function parsePayload(raw) {
  if (raw == null) return undefined;
  if (Buffer.isBuffer(raw)) return JSON.parse(raw.toString('utf8'));
  if (typeof raw === 'object') return raw;
  return JSON.parse(String(raw));
}

async function getDoc(id) {
  const db = await connect();
  const [rows] = await db.query(
    'SELECT payload FROM platform_docs WHERE id = ? LIMIT 1',
    [id],
  );
  if (!rows.length) return undefined;
  try {
    return parsePayload(rows[0].payload);
  } catch {
    return undefined;
  }
}

async function setDoc(id, data) {
  const db = await connect();
  const payload = JSON.stringify(data);
  const updatedAt = new Date().toISOString();
  await db.query(
    `INSERT INTO platform_docs (id, payload, updated_at)
     VALUES (?, ?, ?)
     ON DUPLICATE KEY UPDATE payload = VALUES(payload), updated_at = VALUES(updated_at)`,
    [id, payload, updatedAt],
  );
}

async function countDocs() {
  const db = await connect();
  const [rows] = await db.query('SELECT COUNT(*) AS n FROM platform_docs');
  return Number(rows[0]?.n || 0);
}

async function close() {
  if (pool) {
    await pool.end();
  }
  pool = null;
  ready = false;
  initPromise = null;
}

module.exports = {
  loadDotEnv,
  isConfigured,
  isReady,
  errorMessage,
  connect,
  getDoc,
  setDoc,
  countDocs,
  close,
};
