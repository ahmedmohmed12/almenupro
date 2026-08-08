const fs = require('fs');

const html = fs.readFileSync(process.argv[2], 'utf8');
const next = JSON.parse(
  html.match(
    /<script id="__NEXT_DATA__" type="application\/json">([\s\S]*?)<\/script>/,
  )[1],
);

const { cmsData, data } = next.props.pageProps;
console.log('cmsData keys', Object.keys(cmsData || {}));
console.log(JSON.stringify(cmsData, null, 2).slice(0, 4000));
