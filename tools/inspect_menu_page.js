const fs = require('fs');

const html = fs.readFileSync(process.argv[2], 'utf8');
const match = html.match(
  /<script id="__NEXT_DATA__" type="application\/json">([\s\S]*?)<\/script>/,
);
if (!match) {
  console.error('No NEXT_DATA');
  process.exit(1);
}

const next = JSON.parse(match[1]);
console.log('page', next.page);
const pageProps = next.props.pageProps;
console.log('pageProps keys', Object.keys(pageProps));

function summarize(obj, depth = 0, maxDepth = 3) {
  if (depth > maxDepth || obj == null) return typeof obj;
  if (Array.isArray(obj)) {
    if (!obj.length) return '[]';
    const sample = obj[0];
    return `array(${obj.length}) sampleKeys=${Object.keys(sample || {}).join(',')}`;
  }
  if (typeof obj === 'object') {
    const out = {};
    for (const [k, v] of Object.entries(obj)) {
      if (/menu|section|item|categor|vendor|branch/i.test(k)) {
        out[k] = summarize(v, depth + 1, maxDepth);
      }
    }
    return out;
  }
  return obj;
}

console.log(JSON.stringify(summarize(pageProps), null, 2));

function findItems(obj, path = '') {
  if (!obj || typeof obj !== 'object') return;
  if (Array.isArray(obj)) {
    if (
      obj.length &&
      obj[0]?.name &&
      (obj[0]?.price != null ||
        obj[0]?.originalPrice != null ||
        obj[0]?.unitPrice != null)
    ) {
      console.log('\nITEMS at', path, 'count', obj.length);
      console.log(JSON.stringify(obj[0], null, 2));
    }
    obj.forEach((x, i) => findItems(x, `${path}[${i}]`));
    return;
  }
  for (const [k, v] of Object.entries(obj)) {
    findItems(v, path ? `${path}.${k}` : k);
  }
}

findItems(pageProps);
