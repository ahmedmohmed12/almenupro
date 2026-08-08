const fs = require('fs');
const path = require('path');
const {
  persistMenuItemsImages,
  ensureUploadDir,
} = require('../lib/menuImageStorage');

const DATA_FILE = path.join(__dirname, '..', 'data', 'menu_items.json');

async function main() {
  ensureUploadDir();

  const raw = fs.readFileSync(DATA_FILE, 'utf8');
  const items = JSON.parse(raw || '[]');
  if (!Array.isArray(items)) {
    throw new Error('menu_items.json must contain an array');
  }

  console.log(`Migrating ${items.length} menu item images to local storage...`);
  const migrated = await persistMenuItemsImages(items);
  fs.writeFileSync(DATA_FILE, JSON.stringify(migrated, null, 2), 'utf8');

  const localCount = migrated.filter((item) =>
    String(item.image_url || '').startsWith('/api/uploads/menu/'),
  ).length;

  console.log(`Done. ${localCount}/${migrated.length} items now use local image URLs.`);
}

main().catch((error) => {
  console.error(error.message || error);
  process.exit(1);
});
