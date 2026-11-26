const fs = require('fs');
const path = require('path');

const sourcePath = path.join(__dirname, '..', 'web', 'talabat_menu_bookmarklet.js');
const outTxt = path.join(__dirname, '..', 'web', 'talabat_menu_bookmarklet.txt');

let code = fs.readFileSync(sourcePath, 'utf8');
code = code.replace(/\/\*[\s\S]*?\*\//g, '');
code = code.replace(/^[ \t]*\/\/[^\n]*\n?/gm, '');
code = code.replace(/\s+/g, ' ').trim();
if (code.startsWith('(function')) {
  code = code;
} else {
  code = `(function(){${code}})();`;
}
const bookmarklet = `javascript:${code}`;
fs.writeFileSync(outTxt, `${bookmarklet}\n`, 'utf8');
console.log('Wrote', outTxt, 'length', bookmarklet.length);