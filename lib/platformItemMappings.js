'use strict';

const crypto = require('crypto');
const fs = require('fs');
const path = require('path');
const mysqlStore = require('./mysqlStore');

const DATA_DIR = path.join(__dirname, '..', 'data');
const MAPPINGS_FILE = path.join(DATA_DIR, 'platform_item_mappings.json');
const UNMAPPED_FILE = path.join(DATA_DIR, 'platform_unmapped_items.json');
const MAPPINGS_DOC = 'platform_item_mappings';
const UNMAPPED_DOC = 'platform_unmapped_items';
const PLATFORMS = new Set(['talabat', 'jahez', 'keeta']);
const ENTITY_TYPES = new Set(['item', 'option', 'variant']);

function dataStore() {
  return require('./dataStore');
}

function cleanText(value, max = 500) {
  return String(value ?? '').replace(/\s+/g, ' ').trim().slice(0, max);
}

function normalizePlatform(value) {
  const platform = cleanText(value, 30).toLowerCase();
  return platform === 'keta' ? 'keeta' : platform;
}

function normalizeName(value) {
  return cleanText(value)
    .normalize('NFKD')
    .replace(/[\u064B-\u065F\u0670]/g, '')
    .toLocaleLowerCase('en')
    .replace(/[^\p{L}\p{N}]+/gu, '');
}

function readFile(filePath) {
  try {
    const parsed = JSON.parse(fs.readFileSync(filePath, 'utf8'));
    return Array.isArray(parsed) ? parsed : [];
  } catch {
    return [];
  }
}

function writeFile(filePath, rows) {
  if (process.env.VERCEL) return;
  fs.writeFileSync(filePath, JSON.stringify(rows, null, 2), 'utf8');
}

async function readFallback(docId, filePath) {
  if (dataStore().usesPersistent()) {
    const stored = await dataStore().readNamedDoc(docId, []);
    return Array.isArray(stored) ? stored : [];
  }
  return readFile(filePath);
}

async function writeFallback(docId, filePath, rows) {
  if (dataStore().usesPersistent()) {
    await dataStore().writeNamedDoc(docId, rows);
  } else {
    writeFile(filePath, rows);
  }
  return rows;
}

function normalizeMapping(input, restaurantId, existing = null) {
  const platform = normalizePlatform(input.platformName || input.platform_name);
  const entityType = cleanText(
    input.entityType || input.entity_type || 'item',
    20,
  ).toLowerCase();
  if (!PLATFORMS.has(platform)) throw new Error('Unsupported platform name');
  if (!ENTITY_TYPES.has(entityType)) throw new Error('Unsupported mapping entity type');
  const posItemId = cleanText(input.posItemId || input.pos_item_id, 120);
  if (!posItemId) throw new Error('pos_item_id is required');
  const platformItemId = cleanText(
    input.platformItemId || input.platform_item_id,
    190,
  );
  const platformItemName = cleanText(
    input.platformItemName || input.platform_item_name,
    500,
  );
  const sku = cleanText(input.sku, 190);
  if (!platformItemId && !sku && !platformItemName) {
    throw new Error('A platform item id, SKU, or name is required');
  }
  const now = new Date().toISOString();
  return {
    id:
      cleanText(input.id, 120) ||
      `pmap_${crypto.randomBytes(12).toString('hex')}`,
    restaurant_id: String(restaurantId),
    pos_item_id: posItemId,
    platform_name: platform,
    platform_item_id: platformItemId,
    platform_item_name: platformItemName,
    sku,
    parent_mapping_id: cleanText(
      input.parentMappingId || input.parent_mapping_id,
      120,
    ),
    pos_option_id: cleanText(
      input.posOptionId || input.pos_option_id,
      120,
    ),
    entity_type: entityType,
    created_at: existing?.created_at || now,
    updated_at: now,
  };
}

async function listMappings(restaurantId, platform = '') {
  const normalizedPlatform = platform ? normalizePlatform(platform) : '';
  if (dataStore().usesMysql()) {
    return mysqlStore.listPlatformItemMappings(
      restaurantId,
      normalizedPlatform,
    );
  }
  const rows = await readFallback(MAPPINGS_DOC, MAPPINGS_FILE);
  return rows.filter(
    (row) =>
      String(row.restaurant_id || row.restaurantId) === String(restaurantId) &&
      (!normalizedPlatform ||
        normalizePlatform(row.platform_name || row.platformName) ===
          normalizedPlatform),
  );
}

async function saveMapping(input, restaurantId) {
  const rows = await listMappings(restaurantId);
  const current = rows.find((row) => String(row.id) === String(input.id));
  const mapping = normalizeMapping(input, restaurantId, current);
  const menuItems = (await dataStore().readItems()).filter(
    (item) =>
      String(item.restaurant_id || item.restaurantId) === String(restaurantId),
  );
  const posItem = menuItems.find(
    (item) => String(item.id) === mapping.pos_item_id,
  );
  if (!posItem) throw new Error('Mapped POS item does not exist');
  if (mapping.entity_type !== 'item') {
    if (!mapping.pos_option_id) {
      throw new Error('pos_option_id is required for option and variant mappings');
    }
    const options = Array.isArray(posItem.options) ? posItem.options : [];
    if (
      !options.some(
        (option) => String(option.id) === String(mapping.pos_option_id),
      )
    ) {
      throw new Error('Mapped POS option does not exist on the selected item');
    }
  }
  if (dataStore().usesMysql()) {
    const saved = await mysqlStore.upsertPlatformItemMapping(mapping);
    await dataStore().writeNamedDoc(
      MAPPINGS_DOC,
      await mysqlStore.listPlatformItemMappings(''),
    );
    return saved;
  }
  const all = await readFallback(MAPPINGS_DOC, MAPPINGS_FILE);
  const duplicateIndex = all.findIndex(
    (row) =>
      String(row.restaurant_id || row.restaurantId) === String(restaurantId) &&
      normalizePlatform(row.platform_name || row.platformName) ===
        mapping.platform_name &&
      String(row.entity_type || row.entityType || 'item') ===
        mapping.entity_type &&
      ((mapping.platform_item_id &&
        String(row.platform_item_id || row.platformItemId) ===
          mapping.platform_item_id) ||
        String(row.id) === mapping.id),
  );
  if (duplicateIndex >= 0) {
    mapping.id = all[duplicateIndex].id;
    mapping.created_at = all[duplicateIndex].created_at || mapping.created_at;
    all[duplicateIndex] = mapping;
  } else {
    all.push(mapping);
  }
  await writeFallback(MAPPINGS_DOC, MAPPINGS_FILE, all);
  return mapping;
}

async function deleteMapping(id, restaurantId) {
  if (dataStore().usesMysql()) {
    const deleted = await mysqlStore.deletePlatformItemMapping(
      id,
      restaurantId,
    );
    if (deleted) {
      await dataStore().writeNamedDoc(
        MAPPINGS_DOC,
        await mysqlStore.listPlatformItemMappings(''),
      );
    }
    return deleted;
  }
  const all = await readFallback(MAPPINGS_DOC, MAPPINGS_FILE);
  const next = all.filter(
    (row) =>
      !(
        String(row.id) === String(id) &&
        String(row.restaurant_id || row.restaurantId) === String(restaurantId)
      ),
  );
  if (next.length === all.length) return false;
  await writeFallback(MAPPINGS_DOC, MAPPINGS_FILE, next);
  return true;
}

function uniqueMatch(rows, predicate) {
  const matches = rows.filter(predicate);
  return matches.length === 1 ? matches[0] : null;
}

function menuNames(item) {
  return [item.name, item.name_ar, item.nameAr, item.name_en, item.nameEn]
    .map((value) => cleanText(value))
    .filter(Boolean);
}

function resolveLine({ line, platform, mappings, menuItems, entityType = 'item' }) {
  const normalizedPlatform = normalizePlatform(platform);
  const platformItemId = cleanText(
    line.platformItemId ||
      line.platform_item_id ||
      line.externalItemId ||
      line.external_item_id,
    190,
  );
  const sku = cleanText(line.sku, 190).toLocaleLowerCase('en');
  const name = cleanText(line.name || line.title);
  const exactName = name.toLocaleLowerCase('en');
  const normalized = normalizeName(name);
  const scoped = mappings.filter(
    (row) =>
      normalizePlatform(row.platform_name || row.platformName) ===
        normalizedPlatform &&
      String(row.entity_type || row.entityType || 'item') === entityType,
  );

  let mapping = null;
  let method = '';
  if (platformItemId) {
    mapping = uniqueMatch(
      scoped,
      (row) =>
        cleanText(row.platform_item_id || row.platformItemId, 190) ===
        platformItemId,
    );
    if (mapping) method = 'platform_item_id';
  }
  if (!mapping && sku) {
    mapping = uniqueMatch(
      scoped,
      (row) => cleanText(row.sku, 190).toLocaleLowerCase('en') === sku,
    );
    if (mapping) method = 'sku';
  }
  if (!mapping && exactName) {
    mapping = uniqueMatch(
      scoped,
      (row) =>
        cleanText(row.platform_item_name || row.platformItemName)
          .toLocaleLowerCase('en') === exactName,
    );
    if (mapping) method = 'exact_name';
  }
  if (!mapping && normalized) {
    mapping = uniqueMatch(
      scoped,
      (row) =>
        normalizeName(row.platform_item_name || row.platformItemName) ===
        normalized,
    );
    if (mapping) method = 'normalized_name';
  }

  let posItemId = cleanText(mapping?.pos_item_id || mapping?.posItemId, 120);
  if (!posItemId && entityType === 'item' && exactName) {
    const exactItem = uniqueMatch(menuItems, (item) =>
      menuNames(item).some(
        (candidate) => candidate.toLocaleLowerCase('en') === exactName,
      ),
    );
    if (exactItem) {
      posItemId = cleanText(exactItem.id, 120);
      method = 'catalog_exact_name';
    }
  }
  if (!posItemId && entityType === 'item' && normalized) {
    const normalizedItem = uniqueMatch(menuItems, (item) =>
      menuNames(item).some((candidate) => normalizeName(candidate) === normalized),
    );
    if (normalizedItem) {
      posItemId = cleanText(normalizedItem.id, 120);
      method = 'catalog_normalized_name';
    }
  }

  return {
    isMapped: Boolean(posItemId),
    posItemId,
    posOptionId: cleanText(
      mapping?.pos_option_id || mapping?.posOptionId,
      120,
    ),
    mappingId: cleanText(mapping?.id, 120),
    method: method || 'unmapped',
    platformItemId,
    sku,
    normalizedName: normalized,
  };
}

function resolveCanonicalMenuItemId(line, order, mappings, menuItems) {
  const raw = line?.menuItemId ?? line?.menu_item_id;
  const direct = Number(raw);
  if (Number.isFinite(direct) && direct > 0) return direct;
  const resolved = resolveLine({
    line: line || {},
    platform: order?.orderSource || order?.order_source || order?.platform,
    mappings: mappings || [],
    menuItems: menuItems || [],
    entityType: 'item',
  });
  const mapped = Number(resolved.posItemId);
  return Number.isFinite(mapped) && mapped > 0 ? mapped : null;
}

async function listUnmapped(restaurantId, platform = '') {
  const rows = await readFallback(UNMAPPED_DOC, UNMAPPED_FILE);
  const normalizedPlatform = platform ? normalizePlatform(platform) : '';
  return rows.filter(
    (row) =>
      String(row.restaurant_id || row.restaurantId) === String(restaurantId) &&
      (!normalizedPlatform ||
        normalizePlatform(row.platform_name || row.platformName) ===
          normalizedPlatform),
  );
}

async function recordUnmapped(input, restaurantId) {
  const rows = await readFallback(UNMAPPED_DOC, UNMAPPED_FILE);
  const platform = normalizePlatform(input.platformName || input.platform_name);
  const entityType = cleanText(input.entityType || input.entity_type || 'item', 20);
  const platformItemId = cleanText(
    input.platformItemId || input.platform_item_id,
    190,
  );
  const platformItemName = cleanText(
    input.platformItemName || input.platform_item_name,
  );
  const sku = cleanText(input.sku, 190);
  const key = [
    restaurantId,
    platform,
    entityType,
    platformItemId || sku || normalizeName(platformItemName),
  ].join('|');
  const id = `unmapped_${crypto.createHash('sha256').update(key).digest('hex').slice(0, 24)}`;
  const now = new Date().toISOString();
  const index = rows.findIndex((row) => row.id === id);
  const next = {
    ...(index >= 0 ? rows[index] : {}),
    id,
    restaurant_id: String(restaurantId),
    platform_name: platform,
    platform_item_id: platformItemId,
    platform_item_name: platformItemName,
    sku,
    entity_type: entityType,
    parent_platform_item_id: cleanText(
      input.parentPlatformItemId || input.parent_platform_item_id,
      190,
    ),
    occurrences: Number(index >= 0 ? rows[index].occurrences : 0) + 1,
    first_seen_at: index >= 0 ? rows[index].first_seen_at : now,
    last_seen_at: now,
  };
  if (index >= 0) rows[index] = next;
  else rows.push(next);
  await writeFallback(UNMAPPED_DOC, UNMAPPED_FILE, rows);
  return next;
}

async function removeUnmapped(id, restaurantId) {
  const rows = await readFallback(UNMAPPED_DOC, UNMAPPED_FILE);
  const next = rows.filter(
    (row) =>
      !(
        String(row.id) === String(id) &&
        String(row.restaurant_id || row.restaurantId) === String(restaurantId)
      ),
  );
  await writeFallback(UNMAPPED_DOC, UNMAPPED_FILE, next);
  return next.length !== rows.length;
}

async function resolveExternalOrderItems(body, restaurantId) {
  const platform = normalizePlatform(
    body?.platform || body?.orderSource || body?.source,
  );
  if (!PLATFORMS.has(platform) || !Array.isArray(body?.items)) return body;
  const [mappings, allItems] = await Promise.all([
    listMappings(restaurantId, platform),
    dataStore().readItems(),
  ]);
  const menuItems = allItems.filter(
    (item) =>
      String(item.restaurant_id || item.restaurantId) === String(restaurantId),
  );
  const items = [];
  for (const source of body.items) {
    const line = { ...source };
    const resolved = resolveLine({
      line,
      platform,
      mappings,
      menuItems,
      entityType: 'item',
    });
    line.platformItemId =
      resolved.platformItemId ||
      cleanText(line.platformItemId || line.platform_item_id, 190);
    line.sku = resolved.sku || cleanText(line.sku, 190);
    line.mappingMethod = resolved.method;
    line.isUnmapped = !resolved.isMapped;
    line.is_unmapped = !resolved.isMapped;
    if (resolved.posItemId) {
      line.menuItemId = resolved.posItemId;
      line.menu_item_id = resolved.posItemId;
      line.mappingId = resolved.mappingId;
    } else {
      await recordUnmapped(
        {
          platformName: platform,
          platformItemId: line.platformItemId,
          platformItemName: line.name || line.title,
          sku: line.sku,
          entityType: 'item',
        },
        restaurantId,
      );
    }

    const sourceOptions =
      line.selectedOptions || line.options || line.addOns || line.addons;
    if (Array.isArray(sourceOptions)) {
      const selectedOptions = [];
      for (const rawOption of sourceOptions) {
        const option =
          typeof rawOption === 'string' ? { name: rawOption } : { ...rawOption };
        const optionResolved = resolveLine({
          line: option,
          platform,
          mappings: mappings.filter(
            (mapping) =>
              !resolved.mappingId ||
              !mapping.parent_mapping_id ||
              String(mapping.parent_mapping_id) === resolved.mappingId,
          ),
          menuItems,
          entityType:
            String(option.entityType || option.entity_type).toLowerCase() ===
            'variant'
              ? 'variant'
              : 'option',
        });
        option.platformItemId = optionResolved.platformItemId;
        option.sku = optionResolved.sku;
        option.mappingMethod = optionResolved.method;
        option.isUnmapped = !optionResolved.isMapped;
        option.is_unmapped = !optionResolved.isMapped;
        if (optionResolved.posOptionId) {
          option.posOptionId = optionResolved.posOptionId;
          option.pos_option_id = optionResolved.posOptionId;
        }
        if (!optionResolved.isMapped) {
          await recordUnmapped(
            {
              platformName: platform,
              platformItemId: option.platformItemId,
              platformItemName: option.name || option.title,
              sku: option.sku,
              entityType:
                option.entityType || option.entity_type || 'option',
              parentPlatformItemId: line.platformItemId,
            },
            restaurantId,
          );
        }
        selectedOptions.push(option);
      }
      line.selectedOptions = selectedOptions;
      line.options = selectedOptions;
    }
    items.push(line);
  }
  return { ...body, platform, items };
}

module.exports = {
  ENTITY_TYPES,
  PLATFORMS,
  deleteMapping,
  listMappings,
  listUnmapped,
  normalizeMapping,
  normalizeName,
  normalizePlatform,
  recordUnmapped,
  removeUnmapped,
  resolveExternalOrderItems,
  resolveCanonicalMenuItemId,
  resolveLine,
  saveMapping,
};
