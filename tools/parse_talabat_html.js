const fs = require('fs');
const html = fs.readFileSync(
  process.argv[2] || 'tmp_talabat.html',
  'utf8',
);

console.log('html length', html.length);

const imgs = [...html.matchAll(/images\.deliveryhero\.io\/image\/talabat\/MenuItems\/[^"']+/g)];
console.log('images', imgs.length, imgs.slice(0, 2).map((m) => m[0]));

const testIds = [
  'menu-item-name',
  'menu-section-name',
  'menu-item',
  'item-name',
  'menuSection',
  'vendor-menu',
];

for (const id of testIds) {
  const re = new RegExp(id, 'g');
  console.log(id, (html.match(re) || []).length);
}

const nextData = html.match(
  /<script id="__NEXT_DATA__" type="application\/json">([\s\S]*?)<\/script>/,
);
if (nextData) {
  console.log('NEXT_DATA length', nextData[1].length);
  try {
    const data = JSON.parse(nextData[1]);
    console.log('page', data.page);
    console.log('keys pageProps', Object.keys(data.props?.pageProps || {}));
  } catch (e) {
    console.log('NEXT_DATA parse error', e.message);
  }
} else {
  console.log('no NEXT_DATA');
}
