const { scrapeTalabatMenu, parseMenuFromHtml } = require('../functions/talabatScraper');

async function main() {
  const result = await scrapeTalabatMenu(
    'https://www.talabat.com/ar/kuwait/restaurant/20426/molton-cookies?aid=62',
  );
  const html = await (
    await fetch(result.menuUrl, { headers: { 'User-Agent': 'Mozilla/5.0' } })
  ).text();
  const menu = JSON.parse(
    html.match(
      /<script id="__NEXT_DATA__" type="application\/json">([\s\S]*?)<\/script>/,
    )[1],
  ).props.pageProps.initialMenuState.menuData;

  const ids = new Set();
  const all = [];
  for (const category of menu.categories || []) {
    for (const item of category.items || []) {
      all.push({ category: category.name, item });
      ids.add(item.id);
    }
  }

  const parsed = parseMenuFromHtml(html);
  const parsedIds = new Set(
    all
      .filter((entry) =>
        parsed.some(
          (item) =>
            item.name.trim().toLowerCase() ===
            (entry.item.name || '').trim().toLowerCase(),
        ),
      )
      .map((entry) => entry.item.id),
  );

  const missingIds = [...ids].filter((id) => {
    const entry = all.find((e) => e.item.id === id);
    const inParsed = parsed.some(
      (p) =>
        p.name.trim().toLowerCase() ===
        (entry.item.name || '').trim().toLowerCase(),
    );
    return !inParsed;
  });

  console.log('unique ids in html:', ids.size);
  console.log('parsed count:', parsed.length);
  console.log('missing ids:', missingIds.length, missingIds);
  for (const id of missingIds) {
    const entry = all.find((e) => e.item.id === id);
    console.log('missing item:', entry);
  }
}

main().catch(console.error);
