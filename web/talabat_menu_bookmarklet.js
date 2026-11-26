/**
 * AlMenuPro — Talabat menu export (bookmarklet source).
 * Minified one-liner: web/talabat_menu_bookmarklet.txt (npm run build:talabat-bookmarklet)
 */
(function exportTalabatMenuForAlMenuPro() {
  const SOURCE = 'almenupro-talabat-bookmarklet';
  const VERSION = 2;
  const SUCCESS_MSG =
    'تم نسخ بيانات المنيو بنجاح — الصقها الآن في المنصة';

  function decodeHtml(value) {
    return String(value || '')
      .replace(/&amp;/g, '&')
      .replace(/&#x27;/g, "'")
      .replace(/&quot;/g, '"')
      .trim();
  }

  function normalizeImageUrl(raw) {
    let url = typeof raw === 'string' ? raw : raw?.url || raw?.src || '';
    url = decodeHtml(url);
    if (!url) return '';
    if (url.startsWith('//')) return 'https:' + url;
    if (url.startsWith('http')) return url;
    if (url.startsWith('/')) return 'https://images.deliveryhero.io' + url;
    return 'https://' + url.replace(/^\/+/, '');
  }

  function imageFromItem(item) {
    const candidates = [
      item.originalImage,
      item.image,
      item.imageUrl,
      item.thumbnail,
      item.nmrImage,
      Array.isArray(item.images) ? item.images[0] : null,
    ];
    for (const raw of candidates) {
      const url = normalizeImageUrl(raw);
      if (url) return url;
    }
    return '';
  }

  function categoryName(item, fallback) {
    return (
      (item.originalSection || item.sectionName || fallback || 'عام').trim() ||
      'عام'
    );
  }

  function collectCategory(category, bucket, parentName) {
    const name = category.name || parentName || 'عام';
    for (const item of category.items || []) {
      const n = (item.name || '').trim();
      if (!n) continue;
      bucket.push({
        talabatId: item.id != null ? item.id : null,
        name: n,
        description: (item.description || '').trim(),
        price: Math.round((Number(item.price) || 0) * 1000) / 1000,
        categoryName: categoryName(item, name),
        imageUrl: imageFromItem(item),
      });
    }
    for (const sub of category.subCategories || category.subcategories || []) {
      collectCategory(
        { ...sub, name: sub.name || name },
        bucket,
        sub.name || name,
      );
    }
  }

  function fromNextData() {
    const el = document.getElementById('__NEXT_DATA__');
    if (!el) return null;
    let next;
    try {
      next = JSON.parse(el.textContent || '');
    } catch (_) {
      return null;
    }
    const menuState =
      next.props?.pageProps?.initialMenuState?.menuData ||
      next.props?.pageProps?.menuData;
    if (!menuState?.categories?.length) return null;
    const items = [];
    for (const cat of menuState.categories) collectCategory(cat, items, cat.name);
    const byId = new Map();
    const byName = new Map();
    for (const item of items) {
      if (item.talabatId != null) {
        if (!byId.has(item.talabatId)) byId.set(item.talabatId, item);
      } else {
        const key = item.name.toLowerCase();
        if (!byName.has(key)) byName.set(key, item);
      }
    }
    return [...byId.values(), ...byName.values()];
  }

  function sectionTitleFor(card) {
    const section =
      card.closest('section') ||
      card.closest('[data-testid*="menu-category"]') ||
      card.closest('[class*="category" i]') ||
      card.parentElement;
    if (!section) return 'عام';
    const heading =
      section.querySelector('h2, h3, h4, [data-testid*="category-name"]') ||
      section.querySelector('[class*="title" i]');
    const text = (heading?.textContent || '').trim();
    return text.length > 1 && text.length < 80 ? text : 'عام';
  }

  function parsePriceFromText(text) {
    const priceRe = /(\d{1,4}[.,]\d{1,3}|\d{1,4})\s*(?:د\.?ك|kd|kwd)?/i;
    const m = String(text || '').match(priceRe);
    if (!m) return 0;
    const num = m[1].replace(',', '.');
    return Math.round((parseFloat(num) || 0) * 1000) / 1000;
  }

  function fromDom() {
    const items = [];
    const seen = new Set();
    const priceRe = /(\d{1,4}[.,]\d{1,3}|\d{1,4})/;
    const imgSelectors =
      'img[src*="deliveryhero"], img[src*="dhmedia"], img[src*="talabat"]';
    document.querySelectorAll(imgSelectors).forEach((img) => {
      const card =
        img.closest('[data-testid*="menu-item"]') ||
        img.closest('article') ||
        img.closest('li') ||
        img.closest('[class*="MenuItem" i]') ||
        img.closest('[class*="menu-item" i]') ||
        img.closest('[class*="dish" i]') ||
        img.parentElement?.parentElement;
      if (!card) return;
      const text = (card.innerText || '').trim();
      const lines = text
        .split('\n')
        .map((l) => l.trim())
        .filter(Boolean);
      const name = (lines[0] || '').replace(priceRe, '').trim();
      if (!name || name.length < 2 || seen.has(name.toLowerCase())) return;
      let price = 0;
      for (const line of lines) {
        if (priceRe.test(line)) {
          price = parsePriceFromText(line);
          if (price > 0) break;
        }
      }
      let description = '';
      for (let i = 1; i < lines.length; i++) {
        const line = lines[i];
        if (priceRe.test(line)) continue;
        if (line.length > 2 && line !== name) {
          description = line;
          break;
        }
      }
      seen.add(name.toLowerCase());
      items.push({
        talabatId: null,
        name,
        description,
        price,
        categoryName: sectionTitleFor(card),
        imageUrl: normalizeImageUrl(img.src || img.getAttribute('data-src')),
      });
    });
    return items.length ? items : null;
  }

  function showNotice(message, isError) {
    const existing = document.getElementById('almenupro-talabat-toast');
    if (existing) existing.remove();
    const box = document.createElement('div');
    box.id = 'almenupro-talabat-toast';
    box.setAttribute('dir', 'rtl');
    box.style.cssText = [
      'position:fixed',
      'top:16px',
      'left:50%',
      'transform:translateX(-50%)',
      'z-index:2147483647',
      'max-width:min(420px,92vw)',
      'padding:14px 18px',
      'border-radius:12px',
      'font:600 15px/1.5 Tahoma,Arial,sans-serif',
      'color:#fff',
      'text-align:center',
      'box-shadow:0 8px 32px rgba(0,0,0,.25)',
      isError ? 'background:#b91c1c' : 'background:#166534',
    ].join(';');
    box.textContent = message;
    document.body.appendChild(box);
    setTimeout(() => box.remove(), isError ? 8000 : 12000);
  }

  function showSummary(items) {
    const byCat = {};
    for (const item of items) {
      const c = item.categoryName || 'عام';
      byCat[c] = (byCat[c] || 0) + 1;
    }
    const lines = Object.keys(byCat)
      .slice(0, 8)
      .map((k) => `${k}: ${byCat[k]}`);
    const more =
      Object.keys(byCat).length > 8
        ? `… و${Object.keys(byCat).length - 8} أقسام أخرى`
        : '';
    const summary = lines.join(' · ') + (more ? ' ' + more : '');
    showNotice(`${SUCCESS_MSG}\n(${items.length} صنف — ${summary})`, false);
  }

  let items = fromNextData();
  if (!items?.length) items = fromDom();
  if (!items?.length) {
    showNotice(
      'لم أجد أصنافاً. افتح صفحة المنيو في Talabat، مرّر للأسفل لتحميل كل الأقسام، ثم اضغط الأداة مرة أخرى.',
      true,
    );
    return;
  }

  const payload = {
    source: SOURCE,
    version: VERSION,
    menuUrl: location.href,
    scrapedAt: new Date().toISOString(),
    itemCount: items.length,
    items,
  };
  const json = JSON.stringify(payload);

  const finishOk = () => showSummary(items);

  if (navigator.clipboard?.writeText) {
    navigator.clipboard
      .writeText(json)
      .then(finishOk)
      .catch(() => {
        try {
          const ta = document.createElement('textarea');
          ta.value = json;
          ta.style.cssText = 'position:fixed;left:-9999px';
          document.body.appendChild(ta);
          ta.select();
          document.execCommand('copy');
          ta.remove();
          finishOk();
        } catch (_) {
          showNotice(
            'تعذر النسخ التلقائي. انسخ النص من نافذة المتصفح بعد الموافقة.',
            true,
          );
          prompt('انسخ هذا النص والصقه في المنصة:', json.slice(0, 500) + '…');
        }
      });
  } else {
    try {
      const ta = document.createElement('textarea');
      ta.value = json;
      document.body.appendChild(ta);
      ta.select();
      document.execCommand('copy');
      ta.remove();
      finishOk();
    } catch (_) {
      showNotice('المتصفح لا يدعم النسخ — جرّب Chrome أو Edge.', true);
    }
  }
})();