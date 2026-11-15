'use strict';

const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const packageJson = require('../package.json');
const source = path.join(root, packageJson.build.directories.output);
const destination = path.join(root, 'dist', 'windows');

if (!fs.existsSync(source)) {
  throw new Error(`Windows build output not found: ${source}`);
}

fs.rmSync(destination, { recursive: true, force: true });
fs.mkdirSync(destination, { recursive: true });

const copied = [];
for (const name of fs.readdirSync(source)) {
  const input = path.join(source, name);
  if (!fs.statSync(input).isFile()) continue;
  if (!/\.(exe|blockmap|yml)$/i.test(name)) continue;
  fs.copyFileSync(input, path.join(destination, name));
  copied.push(name);
}

if (!copied.some((name) => /Setup .*\.exe$/i.test(name))) {
  throw new Error('The Windows setup executable was not produced');
}

console.log(`Exported Windows artifacts to ${destination}`);
for (const name of copied) console.log(`- ${name}`);
