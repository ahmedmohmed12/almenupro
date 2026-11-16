const fs = require('fs');
const path = require('path');

const sourceDir = path.join(__dirname, '..', 'uploads', 'menu');
const targetDir = path.join(__dirname, '..', 'public', 'menu-images');
const legacyPublicApiDir = path.join(__dirname, '..', 'public', 'api');

if (!fs.existsSync(sourceDir)) {
  if (!fs.existsSync(targetDir)) {
    console.log('No uploads/menu or public/menu-images; skipping.');
    process.exit(0);
  }
  console.log('No uploads/menu; menu images served from public/menu-images only.');
  process.exit(0);
}

if (fs.existsSync(legacyPublicApiDir)) {
  fs.rmSync(legacyPublicApiDir, { recursive: true, force: true });
}

fs.mkdirSync(targetDir, { recursive: true });

let copied = 0;
for (const filename of fs.readdirSync(sourceDir)) {
  if (filename.startsWith('.')) continue;
  fs.copyFileSync(path.join(sourceDir, filename), path.join(targetDir, filename));
  copied += 1;
}

console.log(`Copied ${copied} menu images to public/menu-images`);
