const { scrapeTalabatMenu } = require('../functions/talabatScraper');

function extractItemsFromCategory(category, categoryName, bucket) {
  const name = categoryName || category.name || 'عام';

  for (const item of category.items || []) {
    bucket.push({ ...item, categoryName: name });
  }

  for (const sub of category.subCategories || category.subcategories || []) {
    extractItemsFromCategory(sub, sub.name || name, bucket);
  }
}

async function analyze(url) {
  const result = await scrapeTalabatMenu(url);
  const html = await (
    await fetch(result.menuUrl, {
      headers: { 'User-Agent': 'Mozilla/5.0' },
    })
  ).text();

  const match = html.match(
    /<script id="__NEXT_DATA__" type="application\/json">([\s\S]*?)<\/script>/,
  );
  const next = JSON.parse(match[1]);
  const menu = next.props?.pageProps?.initialMenuState?.menuData;

  const rawItems = [];
  let topLevel = 0;
  let subLevel = 0;
  for (const category of menu?.categories || []) {
    topLevel += (category.items || []).length;
    for (const sub of category.subCategories || category.subcategories || []) {
      subLevel += (sub.items || []).length;
    }
    extractItemsFromCategory(category, category.name, rawItems);
  }

  console.log('top-level items:', topLevel);
  console.log('subcategory items:', subLevel);

  const parsedNames = new Set(
    result.items.map((item) => item.name.trim().toLowerCase()),
  );

  const rawNamed = rawItems.filter((item) => (item.name || '').trim());
  const missing = rawNamed.filter(
    (item) => !parsedNames.has(item.name.trim().toLowerCase()),
  );

  console.log('URL:', url);
  console.log('resolved:', result.menuUrl);
  console.log('parsed items:', result.items.length);
  console.log('raw items (incl. subcategories):', rawNamed.length);
  console.log('missing from parser:', missing.length);
  if (missing.length) {
    console.log(
      'missing samples:',
      missing.slice(0, 5).map((item) => ({
        name: item.name,
        category: item.categoryName,
      })),
    );
  }

  const noImage = result.items.filter((item) => !item.imageUrl);
  console.log('parsed without image:', noImage.length);
}

const url =
  process.argv[2] || 'https://www.talabat.com/kuwait/molton-cookies';
analyze(url).catch((error) => {
  console.error(error);
  process.exit(1);
});
