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
const pageProps = next.props.pageProps;
console.log('brandSlug', pageProps.brandSlug);
console.log('top keys in data', Object.keys(pageProps.data || {}));

const data = pageProps.data;
if (data) {
  for (const [k, v] of Object.entries(data)) {
    if (Array.isArray(v)) {
      console.log(k, 'array', v.length);
      if (v[0]) console.log(' sample keys', Object.keys(v[0]));
    } else if (v && typeof v === 'object') {
      console.log(k, 'object keys', Object.keys(v).slice(0, 10));
    } else {
      console.log(k, v);
    }
  }
}

console.log('\nmostSellingItems', JSON.stringify(pageProps.mostSellingItems?.slice?.(0, 2), null, 2));

// dump menu-related paths
function findMenu(obj, path = '') {
  if (!obj || typeof obj !== 'object') return;
  if (Array.isArray(obj)) {
    if (obj.length && obj[0]?.name && (obj[0]?.price != null || obj[0]?.unitPrice != null)) {
      console.log('candidate items at', path, 'count', obj.length);
      console.log(JSON.stringify(obj[0], null, 2));
    }
    obj.forEach((item, i) => findMenu(item, `${path}[${i}]`));
    return;
  }
  for (const [k, v] of Object.entries(obj)) {
    if (/menu|section|item|categor/i.test(k)) {
      console.log('key', path + '.' + k, Array.isArray(v) ? `array(${v.length})` : typeof v);
    }
    findMenu(v, path ? `${path}.${k}` : k);
  }
}

findMenu(pageProps);
