'use strict';

const { orderDateKey } = require('../../../lib/kuwaitBusinessDay');

function talabatCellText(value) {
  return String(value || '').replace(/\s+/g, ' ').trim();
}

function extractTalabatColumnOrderId(value) {
  const text = talabatCellText(value);
  const portal = text.match(/\b(39\d{8})\b/);
  if (portal) return portal[1];
  const generic = text.match(/\b(\d{9,12})\b/);
  if (generic) return generic[1];
  const prefixed = text.match(/\b(TB_KW\|\d{6,16})\b/);
  return prefixed ? prefixed[1] : '';
}

function talabatHistoryCreatedAt(value, now = new Date()) {
  const text = talabatCellText(value);
  const time = text.match(/\b(\d{1,2}):(\d{2})\b/);
  const hour = String(time?.[1] || '12').padStart(2, '0');
  const minute = time?.[2] || '00';
  let key = '';
  if (/\b(today|اليوم)\b/i.test(text)) {
    key = orderDateKey(now);
  } else if (/\b(yesterday|أمس)\b/i.test(text)) {
    key = orderDateKey(new Date(now.getTime() - 24 * 60 * 60 * 1000));
  } else {
    const dmy = text.match(/\b(\d{1,2})[./-](\d{1,2})[./-](\d{4})\b/);
    if (dmy) {
      key = `${dmy[3]}-${dmy[2].padStart(2, '0')}-${dmy[1].padStart(2, '0')}`;
    }
  }
  if (!key) return '';
  const parsed = new Date(`${key}T${hour}:${minute}:00+03:00`);
  return Number.isNaN(parsed.getTime()) ? '' : parsed.toISOString();
}

function talabatStampIsToday(value, now = new Date()) {
  const created = talabatHistoryCreatedAt(value, now);
  return Boolean(created && orderDateKey(created) === orderDateKey(now));
}

function dateFilterNodes(document) {
  return Array.from(
    document?.querySelectorAll?.(
      "button, [role='tab'], [role='button'], [role='option'], [role='menuitem']",
    ) || [],
  ).filter((node) => {
    const text = talabatCellText(node.textContent);
    return (
      text.length > 0 &&
      text.length <= 40 &&
      /today|yesterday|last\s*7\s*days|اليوم|أمس|آخر\s*7|اخر\s*7/i.test(text)
    );
  });
}

function nodeIsSelected(node) {
  return (
    node?.getAttribute?.('aria-pressed') === 'true' ||
    node?.getAttribute?.('aria-selected') === 'true' ||
    node?.getAttribute?.('aria-current') === 'true' ||
    node?.getAttribute?.('aria-current') === 'page' ||
    node?.classList?.contains?.('Mui-selected') ||
    node?.classList?.contains?.('selected') ||
    node?.classList?.contains?.('active')
  );
}

function talabatActiveRangeLabel(document) {
  const nodes = dateFilterNodes(document);
  const selected = nodes.find(nodeIsSelected);
  if (selected) return talabatCellText(selected.textContent);
  if (nodes.length === 1) return talabatCellText(nodes[0].textContent);
  return '';
}

function talabatRangeButton(document) {
  return (
    dateFilterNodes(document).find((node) =>
      /last\s*7\s*days|yesterday|today|اليوم|أمس|آخر\s*7|اخر\s*7/i.test(
        talabatCellText(node.textContent),
      ),
    ) || null
  );
}

function talabatRangeIsLast7Days(document) {
  const label = talabatActiveRangeLabel(document);
  return /last\s*7\s*days|آخر\s*7|اخر\s*7/i.test(label);
}

function todayTab(document) {
  return (
    dateFilterNodes(document).find((node) =>
      /^(today|اليوم)(?:\s*\(?\d+\)?)?$/i.test(talabatCellText(node.textContent)),
    ) || null
  );
}

function openTalabatRangeMenu(document) {
  const button =
    dateFilterNodes(document).find((node) =>
      /last\s*7\s*days|آخر\s*7|اخر\s*7/i.test(talabatCellText(node.textContent)),
    ) || null;
  if (!button || typeof button.click !== 'function') return false;
  if (button.getAttribute?.('aria-expanded') === 'true') return false;
  button.click();
  return true;
}

function chooseTalabatTodayOption(document) {
  const option = todayTab(document);
  if (!option || nodeIsSelected(option) || typeof option.click !== 'function') return false;
  option.click();
  return true;
}

/**
 * On the Order History page, click the Today tab when the visible range is
 * wider than the current Kuwait day. Returns ready, clicked, opened, or waiting.
 */
function focusTalabatTodayFilter(document) {
  const label = talabatActiveRangeLabel(document);
  if (/^(today|اليوم)\b/i.test(label)) return 'ready';
  if (chooseTalabatTodayOption(document)) return 'clicked';
  if (/last\s*7|yesterday|أمس|آخر|اخر/i.test(label) && openTalabatRangeMenu(document)) {
    return 'opened';
  }
  return 'waiting';
}

const ACTIVE_STATUS =
  /\b(accepted|preparing|pending|picked\s*up)\b|مقبول|قيد التحضير|يتم التحضير|قيد الانتظار|تم الاستلام/i;
const TERMINAL_STATUS =
  /\b(completed|delivered)\b|مكتمل|تم التوصيل|تم التسليم/i;

function talabatRowStatus(value) {
  const text = talabatCellText(value);
  if (/\bpicked\s*up\b|تم الاستلام/i.test(text)) return 'PICKED UP';
  if (/\bpreparing\b|قيد التحضير|يتم التحضير/i.test(text)) return 'PREPARING';
  if (/\bpending\b|قيد الانتظار/i.test(text)) return 'PENDING';
  if (/\baccepted\b|مقبول/i.test(text)) return 'ACCEPTED';
  if (/\bdelivered\b|تم التوصيل|تم التسليم/i.test(text)) return 'DELIVERED';
  if (/\bcompleted\b|مكتمل/i.test(text)) return 'COMPLETED';
  if (ACTIVE_STATUS.test(text)) return 'ACCEPTED';
  if (TERMINAL_STATUS.test(text)) return 'COMPLETED';
  return '';
}

function talabatStatusRank(value) {
  const status = talabatRowStatus(value);
  if (status === 'PENDING') return 0;
  if (status === 'ACCEPTED') return 1;
  if (status === 'PREPARING') return 2;
  if (status === 'PICKED UP') return 3;
  return 4;
}

function talabatRowShouldScan(value, sessionStartedAt, now = new Date()) {
  const status = talabatRowStatus(value);
  if (status !== 'COMPLETED' && status !== 'DELIVERED') return true;
  const created = talabatHistoryCreatedAt(value, now);
  const started =
    sessionStartedAt instanceof Date
      ? sessionStartedAt.getTime()
      : Number(sessionStartedAt) || 0;
  if (!created || !started) return false;
  return new Date(created).getTime() >= started;
}

function collectTalabatTodayRows(document, cap = 500, now = new Date()) {
  const last7 = talabatRangeIsLast7Days(document);
  const nodes = Array.from(
    document?.querySelectorAll?.(
      "[role='row'], tbody tr, [data-testid='order-history-row']",
    ) || [],
  );
  const ranked = nodes
    .filter((node) => {
      const text = talabatCellText(node.textContent);
      return text.length > 0 && text.length <= 600 && extractTalabatColumnOrderId(text);
    })
    .sort(
      (left, right) =>
        talabatCellText(left.textContent).length - talabatCellText(right.textContent).length,
    );
  const seen = new Set();
  const rows = [];
  for (const node of ranked) {
    const text = talabatCellText(node.textContent);
    const id = extractTalabatColumnOrderId(text);
    if (!id || seen.has(id)) continue;
    const created = talabatHistoryCreatedAt(text, now);
    if (created && orderDateKey(created) !== orderDateKey(now)) continue;
    if (!created && last7) continue;
    seen.add(id);
    rows.push(node);
    if (rows.length >= cap) break;
  }
  return rows;
}

function collectTalabatOrderIds(document) {
  const nodes = Array.from(
    document?.querySelectorAll?.(
      "[data-order-id], [data-order-no], [data-id], td, [role='gridcell'], [role='row']",
    ) || [],
  );
  const ids = [];
  for (const node of nodes) {
    const fromAttribute = extractTalabatColumnOrderId(
      node.getAttribute?.('data-order-id') ||
        node.getAttribute?.('data-order-no') ||
        node.getAttribute?.('data-id') ||
        '',
    );
    const ownText = String(node.textContent || '').replace(/\s+/g, ' ').trim();
    const fromCell = ownText.length <= 40 ? extractTalabatColumnOrderId(ownText) : '';
    const id = fromAttribute || fromCell;
    if (id && !ids.includes(id)) ids.push(id);
    if (ids.length >= 500) break;
  }
  return ids;
}

function dumpTalabatHistoryContainer(document) {
  const root =
    document?.querySelector?.(
      ".MuiDataGrid-virtualScroller, [role='grid'], [data-testid='order-history'], table",
    ) || null;
  const text = String(root?.innerText || root?.textContent || '')
    .replace(/\s+/g, ' ')
    .trim()
    .slice(0, 2500);
  return {
    url: String(document?.location?.href || ''),
    title: String(document?.title || ''),
    visibility: String(document?.visibilityState || ''),
    found: Boolean(root),
    tag: String(root?.tagName || ''),
    text,
    html: String(root?.innerHTML || '').replace(/\s+/g, ' ').trim().slice(0, 2500),
    ids: collectTalabatOrderIds(document),
  };
}

function describeTalabatHistoryDom(document) {
  const href = String(document?.location?.href || '');
  const path = String(document?.location?.pathname || '');
  const title = String(document?.title || '');
  const text = String(document?.body?.innerText || document?.body?.textContent || '')
    .replace(/\s+/g, ' ')
    .trim()
    .slice(0, 1600);
  const rows = Array.from(
    document?.querySelectorAll?.(
      "[role='row'][data-id], [role='row'][data-rowindex], tbody tr, [data-testid='order-history-row']",
    ) || [],
  );
  const ids = collectTalabatOrderIds(document);
  if (!ids.length) {
    for (const row of rows) {
      const cells = row.querySelectorAll?.('td, [role="gridcell"]') || [];
      const raw = cells.length
        ? Array.from(cells)
            .map((cell) => extractTalabatColumnOrderId(cell.textContent))
            .find(Boolean)
        : extractTalabatColumnOrderId(row.textContent);
      if (raw && !ids.includes(raw)) ids.push(raw);
    }
  }
  const blob = `${href} ${path} ${title} ${text}`;
  return {
    href,
    path,
    title,
    historyPage: /\/orders\/history|الطلبات السابقة|order history|سجل الطلبات/i.test(blob),
    loginWall: /login|sign-?in|تسجيل الدخول/i.test(blob) && ids.length === 0,
    rowCount: rows.length,
    ids,
  };
}

module.exports = {
  chooseTalabatTodayOption,
  collectTalabatOrderIds,
  collectTalabatTodayRows,
  describeTalabatHistoryDom,
  dumpTalabatHistoryContainer,
  extractTalabatColumnOrderId,
  focusTalabatTodayFilter,
  openTalabatRangeMenu,
  talabatHistoryCreatedAt,
  talabatRangeIsLast7Days,
  talabatRowShouldScan,
  talabatRowStatus,
  talabatStampIsToday,
  talabatStatusRank,
};
