const fs = require('fs');
const path = require('path');
const { scrapeTalabatMenu } = require('../functions/talabatScraper');
const {
  persistMenuItemsImages,
  ensureUploadDir,
} = require('./lib/menuImageStorage');

const DATA_FILE = path.join(__dirname, 'data', 'menu_items.json');
const DEFAULT_URL =
  'https://www.talabat.com/ar/kuwait/restaurant/20426/molton-cookies?aid=62';

async function main() {
  ensureUploadDir();

  const url = process.argv[2] || DEFAULT_URL;
  const result = await scrapeTalabatMenu(url);

  const categoryIds = new Map();
  let nextCategoryId = 1;
  const categoryIdFor = (name) => {
    const key = String(name || 'عام').trim() || 'عام';
    if (!categoryIds.has(key)) categoryIds.set(key, nextCategoryId++);
    return categoryIds.get(key);
  };

  const items = result.items.map((item, index) => ({
    id: item.talabatId || index + 1,
    category_id: categoryIdFor(item.categoryName),
    category_name: item.categoryName || 'عام',
    name: item.name,
    description: item.description || '',
    price: item.price,
    image_url: item.imageUrl || '',
    is_available: 1,
    talabat_id: item.talabatId,
    source: 'Talabat',
  }));

  console.log(`Downloaded scrape: ${items.length} items. Saving images locally...`);
  const withLocalImages = await persistMenuItemsImages(items);

  fs.mkdirSync(path.dirname(DATA_FILE), { recursive: true });
  fs.writeFileSync(DATA_FILE, JSON.stringify(withLocalImages, null, 2), 'utf8');

  const localCount = withLocalImages.filter((item) =>
    String(item.image_url || '').startsWith('/api/uploads/menu/'),
  ).length;

  console.log(`Saved ${withLocalImages.length} items to ${DATA_FILE}`);
  console.log(`${localCount} images stored under uploads/menu/`);
}

main().catch((error) => {
  console.error(error.message || error);
  process.exit(1);
});
