const fs = require('fs');
const path = require('path');
const {
  autoTranslateMenuItems,
  itemNeedsAutoTranslation,
} = require('../lib/bilingualItemMigration');
const { itemNeedsBilingualMigration } = require('../lib/bilingualMenu');

const DATA_FILE = path.join(__dirname, '..', 'data', 'menu_items.json');

async function main() {
  const raw = fs.readFileSync(DATA_FILE, 'utf8');
  const items = JSON.parse(raw || '[]');
  if (!Array.isArray(items)) {
    throw new Error('menu_items.json must contain an array');
  }

  const pending = items.filter(
    (item) => itemNeedsBilingualMigration(item) || itemNeedsAutoTranslation(item),
  ).length;

  console.log(`Scanning ${items.length} menu items (${pending} need bilingual auto-translate)...`);

  const { items: migrated, updated, scanned } = await autoTranslateMenuItems(items, {
    delayMs: 200,
    onProgress: (current, total, id, translated) => {
      const label = translated ? 'translated' : 'ok';
      console.log(`[${current}/${total}] item #${id} — ${label}`);
    },
  });

  fs.writeFileSync(DATA_FILE, JSON.stringify(migrated, null, 2), 'utf8');

  console.log(`Done. ${updated}/${scanned} items updated with full bilingual fields.`);
  console.log(`File written: ${DATA_FILE}`);
}

main().catch((error) => {
  console.error(error.message || error);
  process.exit(1);
});
