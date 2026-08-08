const fs = require('fs');
const html = fs.readFileSync(process.argv[2], 'utf8');
const links = [
  ...html.matchAll(/restaurant\/20426\/[^"'?\s]+(?:\?aid=\d+)?/g),
];
console.log([...new Set(links.map((m) => m[0]))]);
