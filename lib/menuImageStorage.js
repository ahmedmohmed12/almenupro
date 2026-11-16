const fs = require('fs');
const path = require('path');

const PUBLIC_PREFIX = '/api/uploads/menu';
const UPLOAD_ROOT = path.join(__dirname, '..', 'uploads', 'menu');
const BUNDLED_MENU_ROOT = path.join(__dirname, '..', 'public', 'menu-images');
const IS_VERCEL = Boolean(process.env.VERCEL);

const CONTENT_TYPES = {
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.png': 'image/png',
  '.webp': 'image/webp',
  '.gif': 'image/gif',
};

function ensureUploadDir() {
  // Vercel serverless FS under /var/task is read-only — never mkdir there.
  if (IS_VERCEL) return false;
  try {
    if (!fs.existsSync(UPLOAD_ROOT)) {
      fs.mkdirSync(UPLOAD_ROOT, { recursive: true });
    }
    return true;
  } catch (error) {
    console.warn('[menuImageStorage] ensureUploadDir failed:', error?.message || error);
    return false;
  }
}

function isExternalCdnUrl(url) {
  if (!url || typeof url !== 'string') return false;
  try {
    const host = new URL(url).hostname.toLowerCase();
    return (
      host.includes('deliveryhero.io') ||
      host.includes('talabat.com') ||
      host.includes('dhmedia.io') ||
      host.includes('dh-cdn.net') ||
      host.includes('cloudinary.com')
    );
  } catch {
    return false;
  }
}

function isLocalMenuImageUrl(url) {
  return typeof url === 'string' && url.startsWith(`${PUBLIC_PREFIX}/`);
}

function itemFileKey(item) {
  return String(item.talabat_id ?? item.talabatId ?? item.id ?? 'item').replace(
    /[^\w.-]/g,
    '_',
  );
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

function menuImageDiskPath(filename) {
  const safe = path.basename(String(filename || ''));
  if (!safe || safe.includes('..')) return null;
  const candidates = [path.join(UPLOAD_ROOT, safe), path.join(BUNDLED_MENU_ROOT, safe)];
  for (const diskPath of candidates) {
    try {
      if (fs.existsSync(diskPath)) return diskPath;
    } catch {
      // ignore unreadable paths
    }
  }
  return null;
}

function findBundledLocalUrl(fileKey) {
  if (IS_VERCEL) return null;
  for (const ext of Object.keys(CONTENT_TYPES)) {
    const filename = `${fileKey}${ext}`;
    if (menuImageDiskPath(filename)) {
      return `${PUBLIC_PREFIX}/${filename}`;
    }
  }
  return null;
}

async function downloadImageToLocal(externalUrl, fileKey) {
  if (IS_VERCEL) {
    return externalUrl;
  }
  if (!ensureUploadDir()) {
    return externalUrl;
  }

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
  fs.writeFileSync(diskPath, buffer);

  return `${PUBLIC_PREFIX}/${filename}`;
}

async function persistItemImage(item) {
  const current = String(item.image_url || item.imageUrl || '').trim();

  // On Vercel keep CDN / existing URLs — local uploads are not writable.
  if (IS_VERCEL) {
    return {
      ...item,
      image_url: current,
      imageUrl: current,
    };
  }

  if (isLocalMenuImageUrl(current)) {
    const filename = path.basename(current);
    if (menuImageDiskPath(filename)) {
      return { ...item, image_url: current, imageUrl: current };
    }
  }

  const fileKey = itemFileKey(item);
  const bundled = findBundledLocalUrl(fileKey);
  if (bundled) {
    return { ...item, image_url: bundled, imageUrl: bundled };
  }

  if (!isExternalCdnUrl(current)) {
    return { ...item, image_url: current, imageUrl: current };
  }

  try {
    const localUrl = await downloadImageToLocal(current, fileKey);
    return { ...item, image_url: localUrl, imageUrl: localUrl };
  } catch (error) {
    console.warn(`Image download failed for ${item.name || fileKey}: ${error.message}`);
    return { ...item, image_url: current, imageUrl: current };
  }
}

async function persistMenuItemsImages(items) {
  const list = Array.isArray(items) ? items : [];
  if (IS_VERCEL) {
    return list.map((item) => {
      const current = String(item?.image_url || item?.imageUrl || '').trim();
      return { ...item, image_url: current, imageUrl: current };
    });
  }
  const results = [];
  for (const item of list) {
    results.push(await persistItemImage(item));
  }
  return results;
}

const PROXY_HOST_ALLOW =
  /(^|\.)deliveryhero\.io$|(^|\.)talabat\.com$|(^|\.)dhmedia\.io$|(^|\.)dh-cdn\.net$|(^|\.)cloudinary\.com$|(^|\.)googleusercontent\.com$|(^|\.)fbcdn\.net$|(^|\.)cdninstagram\.com$|(^|\.)instagram\.com$|(^|\.)facebook\.com$/i;
const PROXY_MAX_BYTES = 5 * 1024 * 1024;

function isProxyableImageHost(hostname) {
  const host = String(hostname || '').toLowerCase();
  return PROXY_HOST_ALLOW.test(host);
}

async function fetchUpstreamImage(rawUrl) {
  let target;
  try {
    target = new URL(String(rawUrl || '').trim());
  } catch {
    return { error: 'Invalid image url', status: 400 };
  }

  if (!['http:', 'https:'].includes(target.protocol)) {
    return { error: 'Invalid image url', status: 400 };
  }

  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 12000);
  try {
    const socialHost = /fbcdn\.net|cdninstagram\.com|instagram\.com|facebook\.com/i.test(
      target.hostname,
    );
    const response = await fetch(target.toString(), {
      signal: controller.signal,
      redirect: 'follow',
      headers: {
        Accept: 'image/avif,image/webp,image/apng,image/*,*/*;q=0.8',
        'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
        Referer: socialHost ? 'https://www.instagram.com/' : 'https://www.talabat.com/',
      },
    });

    if (!response.ok) {
      return {
        error: `Upstream image ${response.status}`,
        status: response.status === 404 ? 404 : 502,
      };
    }

    const contentType = String(response.headers.get('content-type') || '').split(';')[0];
    if (contentType && contentType.startsWith('image/')) {
      const buffer = Buffer.from(await response.arrayBuffer());
      if (buffer.length > PROXY_MAX_BYTES) {
        return { error: 'Image too large', status: 413 };
      }
      return { buffer, contentType };
    }

    if (contentType.includes('text/html') || contentType.includes('application/xhtml')) {
      const html = await response.text();
      const og =
        html.match(/property=["']og:image["'][^>]*content=["']([^"']+)["']/i) ||
        html.match(/content=["']([^"']+)["'][^>]*property=["']og:image["']/i);
      const ogUrl = og && og[1] ? og[1].replace(/&amp;/g, '&').trim() : '';
      if (ogUrl && ogUrl !== target.toString()) {
        let nested;
        try {
          nested = new URL(ogUrl);
        } catch {
          nested = null;
        }
        if (
          nested &&
          ['http:', 'https:'].includes(nested.protocol) &&
          isProxyableImageHost(nested.hostname)
        ) {
          return fetchUpstreamImage(nested.toString());
        }
      }
      return {
        error:
          'This Instagram/Facebook link is a post page, not an image file. Upload a photo or paste a direct image URL (cdninstagram.com / .jpg).',
        status: 422,
      };
    }

    return { error: 'Upstream did not return an image', status: 502 };
  } catch (error) {
    return { error: error.message || 'Image proxy failed', status: 502 };
  } finally {
    clearTimeout(timer);
  }
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

  const result = await fetchUpstreamImage(target.toString());
  if (result.error) {
    res.statusCode = result.status || 502;
    res.setHeader('Content-Type', 'application/json; charset=utf-8');
    res.end(JSON.stringify({ error: result.error }));
    return;
  }

  res.statusCode = 200;
  res.setHeader('Content-Type', result.contentType);
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Cache-Control', 'public, max-age=86400');
  res.end(result.buffer);
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

  const diskPath = menuImageDiskPath(filename);
  if (!diskPath) {
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
  BUNDLED_MENU_ROOT,
  menuImageDiskPath,
  ensureUploadDir,
  isExternalCdnUrl,
  isLocalMenuImageUrl,
  persistItemImage,
  persistMenuItemsImages,
  serveMenuImage,
  proxyExternalImage,
  fetchUpstreamImage,
};
