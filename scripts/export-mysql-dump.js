'use strict';

const fs = require('fs');
const path = require('path');

const DATA_DIR = path.join(__dirname, '..', 'data');
const OUT_PATH = path.join(DATA_DIR, 'almenupro.sql');

const DOCS = [
  ['menu_items', 'menu_items.json', []],
  ['orders', 'orders.json', []],
  ['restaurants', 'restaurants.json', []],
  ['delivery_zones', 'delivery_zones.json', []],
  ['kitchens', 'kitchens.json', []],
  ['menu_categories', 'menu_categories.json', []],
  ['reviews', 'reviews.json', []],
  ['expenses', 'expenses.json', []],
  ['offers', 'offers.json', []],
  ['staff_users', 'staff_users.json', []],
  ['dining_tables', 'tables.json', []],
  ['shift_sessions', 'shift_sessions.json', []],
  ['signup_requests', 'signup_requests.json', []],
  ['drivers', 'drivers.json', []],
  ['delivery_requests', 'delivery_requests.json', []],
  ['settings', 'settings.json', {}],
  ['customers', 'customers.json', []],
  ['audit_events', 'audit_events.json', []],
  ['upsell_events', 'upsell_events.json', []],
  ['platform_item_mappings', 'platform_item_mappings.json', []],
  ['platform_unmapped_items', 'platform_unmapped_items.json', []],
  ['store_assets', null, {}],
];

function loadJson(fileName, fallback) {
  if (!fileName) return fallback;
  const filePath = path.join(DATA_DIR, fileName);
  try {
    if (!fs.existsSync(filePath)) return fallback;
    const parsed = JSON.parse(fs.readFileSync(filePath, 'utf8'));
    return parsed ?? fallback;
  } catch {
    return fallback;
  }
}

function sqlString(value) {
  return `'${String(value).replace(/\\/g, '\\\\').replace(/'/g, "''")}'`;
}

function sqlNullable(value) {
  return value == null || String(value).trim() === ''
    ? 'NULL'
    : sqlString(value);
}

function buildSql() {
  const now = new Date().toISOString();
  const lines = [
    '-- AlMenuPro MySQL dump for shared hosting (utf8mb4)',
    `-- Generated ${now}`,
    '-- Import with phpMyAdmin or: mysql -u USER -p DATABASE < data/almenupro.sql',
    'SET NAMES utf8mb4;',
    'SET FOREIGN_KEY_CHECKS=0;',
    '',
    'CREATE TABLE IF NOT EXISTS platform_docs (',
    '  id VARCHAR(64) NOT NULL,',
    '  payload LONGTEXT NOT NULL,',
    '  updated_at VARCHAR(40) NOT NULL,',
    '  PRIMARY KEY (id)',
    ') ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;',
    '',
    'CREATE TABLE IF NOT EXISTS platform_item_mappings (',
    '  id VARCHAR(120) NOT NULL,',
    '  restaurant_id VARCHAR(100) NOT NULL,',
    '  pos_item_id VARCHAR(120) NOT NULL,',
    '  platform_name VARCHAR(30) NOT NULL,',
    '  platform_item_id VARCHAR(190) NULL,',
    "  platform_item_name VARCHAR(500) NOT NULL DEFAULT '',",
    '  sku VARCHAR(190) NULL,',
    '  parent_mapping_id VARCHAR(120) NULL,',
    '  pos_option_id VARCHAR(120) NULL,',
    "  entity_type ENUM('item','option','variant') NOT NULL DEFAULT 'item',",
    '  created_at VARCHAR(40) NOT NULL,',
    '  updated_at VARCHAR(40) NOT NULL,',
    '  PRIMARY KEY (id),',
    '  UNIQUE KEY uq_platform_mapping_identity (restaurant_id, platform_name, entity_type, platform_item_id),',
    '  KEY idx_platform_mapping_sku (restaurant_id, platform_name, entity_type, sku),',
    '  KEY idx_platform_mapping_name (restaurant_id, platform_name, entity_type, platform_item_name(120)),',
    '  KEY idx_platform_mapping_pos (restaurant_id, pos_item_id, entity_type),',
    '  KEY idx_platform_mapping_parent (parent_mapping_id)',
    ') ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;',
    '',
  ];

  for (const [id, fileName, fallback] of DOCS) {
    const payload = JSON.stringify(loadJson(fileName, fallback));
    lines.push(
      `REPLACE INTO platform_docs (id, payload, updated_at) VALUES (${sqlString(id)}, ${sqlString(payload)}, ${sqlString(now)});`,
      '',
    );
  }

  const mappings = loadJson('platform_item_mappings.json', []);
  for (const row of Array.isArray(mappings) ? mappings : []) {
    lines.push(
      `REPLACE INTO platform_item_mappings (id, restaurant_id, pos_item_id, platform_name, platform_item_id, platform_item_name, sku, parent_mapping_id, pos_option_id, entity_type, created_at, updated_at) VALUES (${[
        sqlString(row.id),
        sqlString(row.restaurant_id || row.restaurantId),
        sqlString(row.pos_item_id || row.posItemId),
        sqlString(row.platform_name || row.platformName),
        sqlNullable(row.platform_item_id || row.platformItemId),
        sqlString(row.platform_item_name || row.platformItemName || ''),
        sqlNullable(row.sku),
        sqlNullable(row.parent_mapping_id || row.parentMappingId),
        sqlNullable(row.pos_option_id || row.posOptionId),
        sqlString(row.entity_type || row.entityType || 'item'),
        sqlString(row.created_at || row.createdAt || now),
        sqlString(row.updated_at || row.updatedAt || now),
      ].join(', ')});`,
      '',
    );
  }

  lines.push('SET FOREIGN_KEY_CHECKS=1;');
  return lines.join('\n');
}

const sql = buildSql();
fs.writeFileSync(OUT_PATH, sql, 'utf8');
console.log(`Wrote ${OUT_PATH} (${sql.length} bytes)`);
