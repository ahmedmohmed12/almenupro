const fs = require('fs');
const path = require('path');

const PUBLIC_PREFIX = '/api/uploads/menu';
const UPLOAD_ROOT = path.join(__dirname, '..', 'uploads', 'menu');
const IS_VERCEL = Boolean(process.env.VERCEL);

const CONTENT_TYPES = {
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.png': 'image/png',
  '.webp': 'image/webp',
  '.gif': 'image/gif',
};

function ensureUploadDir() {
  if (!fs.existsSync(UPLOAD_ROOT)) {
    fs.mkdirSync(UPLOAD_ROOT, { recursive: true });
  }
}

function isExternalCdnUrl(url) {
  if (!url || typeof url !== 'string') return false;
  try {
    const host = new URL(url).hostname.toLowerCase();
    return host.includes('deliveryhero.io') || host.includes('talabat.com');
  } catch {
    return false;
  }
}

function isLocalMenuImageUrl(url) {
  return typeof url === 'string' && url.startsWith(`${PUBLIC_PREFIX}/`);
}

function itemFileKey(item) {
  return String(item.talabat_id ?? item.id ?? 'item').replace(/[^\w.-]/g, '_');
}

function extensionFromContentType(contentType, sourceUrl) {
  const type = String(contentType || '').toLowerCase();
  if (type.includes('png')) return '.png';
  if (type.includes('webp')) return '.webp';
  if (type.includes('gif')) return '.gif';
  if (type.includes('jpeg') || type.includes('jpg')) return '.jpg';

  const match = String(sourceUrl || '').match(/\.(jpe?g|png|webp|gif)(\?|$)/i);
  if (match) {
    const ext = match[1].toLowerCase();
    return ext === 'jpeg' ? '.jpg' : `.${ext}`;
  }
  return '.jpg';
}

function findBundledLocalUrl(fileKey) {
  ensureUploadDir();
  for (const ext of Object.keys(CONTENT_TYPES)) {
    const filename = `${fileKey}${ext}`;
    if (fs.existsSync(path.join(UPLOAD_ROOT, filename))) {
      return `${PUBLIC_PREFIX}/${filename}`;
    }
  }
  return null;
}

async function downloadImageToLocal(externalUrl, fileKey) {
  ensureUploadDir();

  const response = await fetch(externalUrl, {
    headers: {
      'User-Agent': 'AlmenuproMenuSync/1.0',
      Accept: 'image/*,*/*;q=0.8',
    },
  });

  if (!response.ok) {
    throw new Error(`HTTP ${response.status}`);
  }

  const contentType = response.headers.get('content-type') || 'image/jpeg';
  const ext = extensionFromContentType(contentType, externalUrl);
  const filename = `${fileKey}${ext}`;
  const diskPath = path.join(UPLOAD_ROOT, filename);
  const buffer = Buffer.from(await response.arrayBuffer());

  if (!IS_VERCEL) {
    fs.writeFileSync(diskPath, buffer);
  }

  return `${PUBLIC_PREFIX}/${filename}`;
}

async function persistItemImage(item) {
  const current = String(item.image_url || item.imageUrl || '').trim();

  if (isLocalMenuImageUrl(current)) {
    const filename = path.basename(current);
    if (fs.existsSync(path.join(UPLOAD_ROOT, filename))) {
      return { ...item, image_url: current };
    }
  }

  const fileKey = itemFileKey(item);
  const bundled = findBundledLocalUrl(fileKey);
  if (bundled) {
    return { ...item, image_url: bundled };
  }

  if (!isExternalCdnUrl(current)) {
    return { ...item, image_url: current };
  }

  if (IS_VERCEL) {
    return { ...item, image_url: current };
  }

  try {
    const localUrl = await downloadImageToLocal(current, fileKey);
    return { ...item, image_url: localUrl };
  } catch (error) {
    console.warn(`Image download failed for ${item.name || fileKey}: ${error.message}`);
    return { ...item, image_url: current };
  }
}

async function persistMenuItemsImages(items) {
  const results = [];
  for (const item of items) {
    results.push(await persistItemImage(item));
  }
  return results;
}

const PROXY_HOST_ALLOW =
  /(^|\.)deliveryhero\.io$|(^|\.)talabat\.com$|(^|\.)cloudinary\.com$|(^|\.)googleusercontent\.com$|(^|\.)fbcdn\.net$/i;
const PROXY_MAX_BYTES = 5 * 1024 * 1024;

function isProxyableImageHost(hostname) {
  const host = String(hostname || '').toLowerCase();
  return PROXY_HOST_ALLOW.test(host);
}

async function proxyExternalImage(res, rawUrl) {
  let target;
  try {
    target = new URL(String(rawUrl || '').trim());
  } catch {
    res.statusCode = 400;
    res.setHeader('Content-Type', 'application/json; charset=utf-8');
    res.end(JSON.stringify({ error: 'Invalid image url' }));
    return;
  }

  if (!['http:', 'https:'].includes(target.protocol) || !isProxyableImageHost(target.hostname)) {
    res.statusCode = 400;
    res.setHeader('Content-Type', 'application/json; charset=utf-8');
    res.end(JSON.stringify({ error: 'Image host not allowed' }));
    return;
  }

  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 12000);
  try {
    const response = await fetch(target.toString(), {
      signal: controller.signal,
      redirect: 'follow',
      headers: {
        Accept: 'image/avif,image/webp,image/apng,image/*,*/*;q=0.8',
        'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
        Referer: 'https://www.talabat.com/',
      },
    });

    if (!response.ok) {
      res.statusCode = response.status === 404 ? 404 : 502;
      res.setHeader('Content-Type', 'application/json; charset=utf-8');
      res.end(JSON.stringify({ error: `Upstream image ${response.status}` }));
      return;
    }

    const contentType = String(response.headers.get('content-type') || 'image/jpeg').split(';')[0];
    if (contentType && !contentType.startsWith('image/')) {
      res.statusCode = 502;
      res.setHeader('Content-Type', 'application/json; charset=utf-8');
      res.end(JSON.stringify({ error: 'Upstream did not return an image' }));
      return;
    }

    const buffer = Buffer.from(await response.arrayBuffer());
    if (buffer.length > PROXY_MAX_BYTES) {
      res.statusCode = 413;
      res.setHeader('Content-Type', 'application/json; charset=utf-8');
      res.end(JSON.stringify({ error: 'Image too large' }));
      return;
    }

    res.statusCode = 200;
    res.setHeader('Content-Type', contentType || 'image/jpeg');
    res.setHeader('Access-Control-Allow-Origin', '*');
    res.setHeader('Cache-Control', 'public, max-age=86400');
    res.end(buffer);
  } catch (error) {
    if (!res.headersSent) {
      res.statusCode = 502;
      res.setHeader('Content-Type', 'application/json; charset=utf-8');
      res.end(JSON.stringify({ error: error.message || 'Image proxy failed' }));
    }
  } finally {
    clearTimeout(timer);
  }
}

function serveMenuImage(res, filename) {
  if (!filename || filename.includes('..') || filename.includes('/') || filename.includes('\\')) {
    res.writeHead(400, {
      'Content-Type': 'application/json; charset=utf-8',
      'Access-Control-Allow-Origin': '*',
    });
    res.end(JSON.stringify({ error: 'Invalid filename' }));
    return;
  }

  const diskPath = path.join(UPLOAD_ROOT, filename);
  if (!fs.existsSync(diskPath)) {
    res.writeHead(404, {
      'Content-Type': 'application/json; charset=utf-8',
      'Access-Control-Allow-Origin': '*',
    });
    res.end(JSON.stringify({ error: 'Image not found' }));
    return;
  }

  const ext = path.extname(filename).toLowerCase();
  res.writeHead(200, {
    'Content-Type': CONTENT_TYPES[ext] || 'application/octet-stream',
    'Access-Control-Allow-Origin': '*',
    'Cache-Control': 'public, max-age=31536000, immutable',
  });
  fs.createReadStream(diskPath).pipe(res);
}

module.exports = {
  PUBLIC_PREFIX,
  UPLOAD_ROOT,
  ensureUploadDir,
  isExternalCdnUrl,
  isLocalMenuImageUrl,
  persistItemImage,
  persistMenuItemsImages,
  serveMenuImage,
  proxyExternalImage,
};
