const { scrapeTalabatMenu } = require('../functions/talabatScraper');

async function main() {
  const result = await scrapeTalabatMenu(
    'https://www.talabat.com/ar/kuwait/restaurant/20426/molton-cookies?aid=62',
  );
  const html = await (
    await fetch(result.menuUrl, {
      headers: { 'User-Agent': 'Mozilla/5.0' },
    })
  ).text();
  const match = html.match(
    /<script id="__NEXT_DATA__" type="application\/json">([\s\S]*?)<\/script>/,
  );
  const menu = JSON.parse(match[1]).props.pageProps.initialMenuState.menuData;

  const all = [];
  for (const category of menu.categories || []) {
    for (const item of category.items || []) {
      all.push({ category: category.name, item });
    }
  }

  console.log('total raw:', all.length);
  console.log('sample keys:', Object.keys(all[0]?.item || {}));
  console.log('sample item:', JSON.stringify(all[0]?.item, null, 2));

  const byName = new Map();
  const byId = new Map();
  const dupes = [];
  for (const entry of all) {
    const key = (entry.item.name || '').trim().toLowerCase();
    const id = entry.item.id;
    if (byName.has(key)) {
      dupes.push({
        key,
        idA: byName.get(key).id,
        idB: entry.item.id,
        catA: byName.get(key).category,
        catB: entry.category,
        sameId: byName.get(key).id === id,
      });
    } else {
      byName.set(key, { id, category: entry.category });
    }
    byId.set(id, entry.category);
  }
  console.log('unique names:', byName.size);
  console.log('unique ids:', byId.size);
  console.log('duplicate names:', dupes.length);
  console.log('dupe samples:', dupes.slice(0, 8));
}

main().catch(console.error);
