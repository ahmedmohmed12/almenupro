'use strict';

const path = require('node:path');
const { build } = require('esbuild');

const root = path.resolve(__dirname, '..');

build({
  entryPoints: [path.join(root, 'src', 'preload', 'scraper-preload.js')],
  outfile: path.join(root, 'dist', 'scraper-preload.cjs'),
  bundle: true,
  platform: 'node',
  format: 'cjs',
  target: 'node22',
  external: ['electron'],
  sourcemap: false,
  minify: false,
}).catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
