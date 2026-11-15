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
  await connectionPool.query(`
    CREATE TABLE IF NOT EXISTS platform_item_mappings (
      id VARCHAR(120) NOT NULL,
      restaurant_id VARCHAR(100) NOT NULL,
      pos_item_id VARCHAR(120) NOT NULL,
      platform_name VARCHAR(30) NOT NULL,
      platform_item_id VARCHAR(190) NULL,
      platform_item_name VARCHAR(500) NOT NULL DEFAULT '',
      sku VARCHAR(190) NULL,
      parent_mapping_id VARCHAR(120) NULL,
      pos_option_id VARCHAR(120) NULL,
      entity_type ENUM('item', 'option', 'variant') NOT NULL DEFAULT 'item',
      created_at VARCHAR(40) NOT NULL,
      updated_at VARCHAR(40) NOT NULL,
      PRIMARY KEY (id),
      UNIQUE KEY uq_platform_mapping_identity (
        restaurant_id,
        platform_name,
        entity_type,
        platform_item_id
      ),
      KEY idx_platform_mapping_sku (
        restaurant_id,
        platform_name,
        entity_type,
        sku
      ),
      KEY idx_platform_mapping_name (
        restaurant_id,
        platform_name,
        entity_type,
        platform_item_name(120)
      ),
      KEY idx_platform_mapping_pos (
        restaurant_id,
        pos_item_id,
        entity_type
      ),
      KEY idx_platform_mapping_parent (parent_mapping_id)
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

async function queryWithSchema(sql, params) {
  const db = await connect();
  try {
    return await db.query(sql, params);
  } catch (error) {
    if (error?.code !== 'ER_NO_SUCH_TABLE') throw error;
    await ensureSchema(db);
    return db.query(sql, params);
  }
}

async function getDoc(id) {
  const [rows] = await queryWithSchema(
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
  const payload = JSON.stringify(data);
  const updatedAt = new Date().toISOString();
  await queryWithSchema(
    `INSERT INTO platform_docs (id, payload, updated_at)
     VALUES (?, ?, ?)
     ON DUPLICATE KEY UPDATE payload = VALUES(payload), updated_at = VALUES(updated_at)`,
    [id, payload, updatedAt],
  );
}

async function countDocs() {
  const [rows] = await queryWithSchema('SELECT COUNT(*) AS n FROM platform_docs');
  return Number(rows[0]?.n || 0);
}

async function listPlatformItemMappings(restaurantId, platformName = '') {
  const db = await connect();
  const params = [];
  let sql = 'SELECT * FROM platform_item_mappings';
  if (restaurantId) {
    sql += ' WHERE restaurant_id = ?';
    params.push(String(restaurantId));
  }
  if (platformName) {
    sql += restaurantId ? ' AND platform_name = ?' : ' WHERE platform_name = ?';
    params.push(String(platformName));
  }
  sql += ' ORDER BY updated_at DESC, id ASC';
  const [rows] = await db.query(sql, params);
  return rows;
}

async function upsertPlatformItemMapping(mapping) {
  const db = await connect();
  await db.query(
    `INSERT INTO platform_item_mappings (
       id, restaurant_id, pos_item_id, platform_name, platform_item_id,
       platform_item_name, sku, parent_mapping_id, pos_option_id, entity_type,
       created_at, updated_at
     ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
     ON DUPLICATE KEY UPDATE
       pos_item_id = VALUES(pos_item_id),
       platform_item_name = VALUES(platform_item_name),
       sku = VALUES(sku),
       parent_mapping_id = VALUES(parent_mapping_id),
       pos_option_id = VALUES(pos_option_id),
       updated_at = VALUES(updated_at)`,
    [
      mapping.id,
      mapping.restaurant_id,
      mapping.pos_item_id,
      mapping.platform_name,
      mapping.platform_item_id || null,
      mapping.platform_item_name || '',
      mapping.sku || null,
      mapping.parent_mapping_id || null,
      mapping.pos_option_id || null,
      mapping.entity_type || 'item',
      mapping.created_at,
      mapping.updated_at,
    ],
  );
  const [rows] = await db.query(
    'SELECT * FROM platform_item_mappings WHERE id = ? LIMIT 1',
    [mapping.id],
  );
  return rows[0] || mapping;
}

async function deletePlatformItemMapping(id, restaurantId) {
  const db = await connect();
  const [result] = await db.query(
    'DELETE FROM platform_item_mappings WHERE id = ? AND restaurant_id = ?',
    [String(id), String(restaurantId)],
  );
  return Number(result?.affectedRows || 0) > 0;
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
  listPlatformItemMappings,
  upsertPlatformItemMapping,
  deletePlatformItemMapping,
  close,
};
