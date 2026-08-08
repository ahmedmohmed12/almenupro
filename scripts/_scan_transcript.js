const fs = require('fs');
const p = process.argv[2];
const text = fs.readFileSync(p, 'utf8');
const paths = new Map();
for (const line of text.split('\n')) {
  if (!line.includes('"Write"')) continue;
  if (!line.includes('"contents"')) continue;
  const re = /"path":"([^"]+)"/g;
  let m;
  while ((m = re.exec(line)) !== null) {
    const full = m[1].replace(/\\\\/g, '/');
    const idx = full.toLowerCase().indexOf('almenupro/');
    const rel = idx >= 0 ? full.slice(idx + 'almenupro/'.length) : full;
    if (rel.startsWith('backend/') || rel.startsWith('lib/')) {
      paths.set(rel, (paths.get(rel) || 0) + 1);
    }
  }
}
const arr = [...paths.keys()].sort();
console.log('Unique backend-related Write paths:', arr.length);
for (const x of arr) console.log(x);
console.log('POS-related count:', arr.filter((x) => /pos|staff|shift|permission|analytics|delivery/i.test(x)).length);
