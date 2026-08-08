const { scrapeTalabatMenu } = require('../functions/talabatScraper');

async function main() {
  const url =
    'https://www.talabat.com/ar/kuwait/restaurant/20426/molton-cookies?aid=62';
  const result = await scrapeTalabatMenu(url);
  const html = await (
    await fetch(result.menuUrl, { headers: { 'User-Agent': 'Mozilla/5.0' } })
  ).text();
  const menu = JSON.parse(
    html.match(
      /<script id="__NEXT_DATA__" type="application\/json">([\s\S]*?)<\/script>/,
    )[1],
  ).props.pageProps.initialMenuState.menuData;

  const all = [];
  for (const category of menu.categories || []) {
    for (const item of category.items || []) {
      all.push({ cat: category.name, item });
    }
  }

  const byName = new Map();
  for (const entry of all) {
    const name = (entry.item.name || '').trim();
    if (!byName.has(name)) byName.set(name, []);
    byName.get(name).push({ id: entry.item.id, cat: entry.cat });
  }

  console.log('parsed items:', result.items.length);
  console.log('raw entries:', all.length);
  console.log('unique names:', byName.size);

  for (const [name, entries] of byName.entries()) {
    const ids = [...new Set(entries.map((entry) => entry.id))];
    if (ids.length > 1) {
      console.log('DIFFERENT IDS same name:', name, entries);
    }
  }

  const parsedIds = new Set(result.items.map((item) => item.talabatId));
  const allIds = [...new Set(all.map((entry) => entry.item.id))];
  const missingIds = allIds.filter((id) => !parsedIds.has(id));
  console.log('missing ids in parsed:', missingIds.length, missingIds);

  for (const id of missingIds) {
    const entry = all.find((e) => e.item.id === id);
    console.log('missing:', id, entry?.item?.name, entry?.cat);
  }
}

main().catch(console.error);
