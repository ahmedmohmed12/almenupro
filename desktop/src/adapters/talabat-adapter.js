'use strict';

const { BaseAdapter } = require('./base-adapter');
const selectors = require('../selectors/talabat.json');
const {
  chooseTalabatTodayOption,
  collectTalabatTodayRows,
  extractTalabatColumnOrderId,
  focusTalabatTodayFilter,
  talabatHistoryCreatedAt,
} = require('../services/talabat-history-dom');

function normalizedText(node) {
  return String(node?.textContent || '').replace(/\s+/g, ' ').trim();
}

function cleanCustomerName(value) {
  return String(value || '')
    .replace(/^(person(?:_outline)?|account_circle)\s*/i, '')
    .trim();
}

function cleanCustomerPhone(value) {
  const cleaned = String(value || '')
    .replace(/^(phone(?:_in_talk)?|call)\s*/i, '')
    .trim();
  return cleaned.match(/\+?\d[\d\s()-]{7,}/)?.[0]?.trim() || cleaned;
}

function cleanCustomerAddress(value) {
  return String(value || '')
    .replace(/^(location_on|location|place|pin_drop)\s*/i, '')
    .trim();
}

function findCustomerDetailsHeading(root) {
  if (!root?.querySelectorAll) return null;
  const matches = Array.from(root.querySelectorAll('*')).filter((node) => {
    const text = normalizedText(node);
    return (
      text.length <= 80 &&
      /(customer details|بيانات العميل|تفاصيل العميل)/i.test(text)
    );
  });
  return (
    matches.sort(
      (left, right) => normalizedText(left).length - normalizedText(right).length,
    )[0] || null
  );
}

function customerDetailsToggle(heading) {
  let node = heading;
  for (let depth = 0; node && depth < 7; depth += 1) {
    const expanded = node.getAttribute?.('aria-expanded');
    const role = node.getAttribute?.('role');
    if (
      expanded !== null && expanded !== undefined ||
      String(node.tagName || '').toLowerCase() === 'button' ||
      role === 'button' ||
      node.classList?.contains('MuiAccordionSummary-root')
    ) {
      return node;
    }
    const nestedToggle = node.querySelector?.(
      "[aria-expanded], button, [role='button'], [data-testid*='expand' i], [aria-label*='expand' i], [aria-label*='collapse' i]",
    );
    if (nestedToggle) return nestedToggle;
    const arrow = node.querySelector?.(
      "svg[data-testid*='Expand' i], svg[data-testid*='Chevron' i], svg[data-testid*='Arrow' i]",
    );
    if (arrow) {
      return (
        arrow.closest?.("button, [role='button'], [aria-expanded]") ||
        arrow.parentElement ||
        arrow
      );
    }
    node = node.parentElement;
  }
  return null;
}

function customerDetailsAreCollapsed(toggle) {
  if (!toggle) return false;
  const expanded = toggle.getAttribute?.('aria-expanded');
  if (expanded != null) return String(expanded).toLowerCase() !== 'true';
  const state = toggle.getAttribute?.('data-state');
  if (state) return /closed|collapsed/i.test(state);
  // Talabat sometimes renders the chevron as a sibling icon without ARIA.
  // This fallback is only used when no customer values were rendered.
  return true;
}

function isVisible(node) {
  if (!node || node.hidden) return false;
  if (String(node.getAttribute?.('aria-hidden') || '').toLowerCase() === 'true') {
    return false;
  }
  const hiddenParent = node.closest?.("[hidden], [aria-hidden='true']");
  if (hiddenParent) return false;
  const view = node.ownerDocument?.defaultView;
  if (view?.getComputedStyle) {
    const style = view.getComputedStyle(node);
    if (
      style.display === 'none' ||
      style.visibility === 'hidden' ||
      style.visibility === 'collapse'
    ) {
      return false;
    }
  }
  if (
    view &&
    node.isConnected !== false &&
    typeof node.getClientRects === 'function' &&
    node.getClientRects().length === 0
  ) {
    return false;
  }
  return true;
}

function customerDetailValueNodes(root) {
  const heading = findCustomerDetailsHeading(root);
  const parseNodes = (nodes) => {
    const usable = nodes.filter(
      (node) =>
        normalizedText(node) &&
        !/^(customer details|info|person|location_on|phone|call|expand_less|expand_more)$/i.test(
          normalizedText(node),
        ),
    );
    const phoneNode = usable.find((node) =>
      /^\+?[\d\s()-]{8,}$/.test(normalizedText(node)),
    );
    if (!phoneNode) return null;
    const remaining = usable.filter((node) => node !== phoneNode);
    const addressNode = remaining.find((node) => {
      const value = normalizedText(node);
      return /,/.test(value) || (/\d/.test(value) && value.length > 8);
    });
    const nameNode = remaining.find((node) => {
      const value = normalizedText(node);
      return (
        node !== addressNode &&
        /[A-Za-z\u0600-\u06ff]/.test(value) &&
        !/^\d/.test(value)
      );
    });
    return { nameNode, addressNode, phoneNode };
  };

  let section = heading?.parentElement;
  for (let depth = 0; section && depth < 7; depth += 1) {
    if (typeof section.querySelectorAll !== 'function') {
      section = section.parentElement;
      continue;
    }
    const nodes = Array.from(section.querySelectorAll('*')).filter(
      (node) => node.children.length === 0 && normalizedText(node),
    );
    const parsed = parseNodes(nodes);
    if (parsed) return parsed;
    section = section.parentElement;
  }

  // Production Talabat may portal-render the accordion body as siblings of
  // its header. Read leaf values following the heading until the next section.
  if (heading && root?.querySelectorAll) {
    const all = Array.from(root.querySelectorAll('*'));
    const headingIndex = all.indexOf(heading);
    if (headingIndex >= 0) {
      const following = [];
      for (
        let index = headingIndex + 1;
        index < all.length && following.length < 40;
        index += 1
      ) {
        const node = all[index];
        const text = normalizedText(node);
        if (/^(order timeline|مسار الطلب|order details|تفاصيل الطلب)$/i.test(text)) {
          break;
        }
        if (node.children.length === 0 && text) following.push(node);
      }
      const parsed = parseNodes(following);
      if (parsed) return parsed;
    }
  }
  return { nameNode: null, addressNode: null, phoneNode: null };
}

function customerDetailsFieldsAreVisible(root) {
  const { nameNode, addressNode, phoneNode } = customerDetailValueNodes(root);
  return Boolean(
    nameNode &&
    addressNode &&
    phoneNode &&
    isVisible(nameNode) &&
    isVisible(addressNode) &&
    isVisible(phoneNode),
  );
}

function isExplicitCashPayment(blob) {
  const text = String(blob || '');
  // Avoid Arabic "كاشير" (cashier). Require explicit cash / COD / collect cash.
  return (
    /\b(cash(?:\s+on\s+delivery)?|cash\s*payment|collect\s+cash|\bCOD\b)\b/i.test(
      text,
    ) || /كاش(?!ير)|نقدي|الدفع\s*عند\s*الاستلام/i.test(text)
  );
}

function isExplicitGatewayPayment(blob) {
  const text = String(blob || '');
  return (
    /\bK[\s-]?NET\b|كي\s*نت/i.test(text) ||
    /\bapple\s*pay\b/i.test(text) ||
    /\b(online\s*payment|paid\s*online|pre[-\s]?paid|card\s*payment|bank\s*card(?:\s*payment)?|credit\s*card|debit\s*card|visa|mastercard|mada)\b/i.test(
      text,
    ) ||
    /دفع\s*إلكتروني|مدفوع(?:ة)?\s*إلكتروني|مدفوع(?:ة)?\s*مسبق|مسبق(?:ا|ً|اً)?\s*(?:ال)?دفع/i.test(
      text,
    )
  );
}

function classifyTalabatPaymentText(value) {
  const blob = String(value || '').replace(/\s+/g, ' ').trim();
  if (!blob) return '';

  // Settlement-critical: explicit Cash always wins over ambiguous "paid" UI text.
  if (isExplicitCashPayment(blob)) return 'Cash';
  if (/\bK[\s-]?NET\b|كي\s*نت/i.test(blob)) return 'KNET';
  if (/\bapple\s*pay\b/i.test(blob)) return 'Apple Pay';
  // Prepaid only with explicit online/card/prepaid metadata — never bare "Paid".
  if (isExplicitGatewayPayment(blob)) return 'Prepaid';
  return '';
}

function preferPaymentMethod(...values) {
  // Cash outranks Prepaid so enrich/DOM merges never flip drawer settlement.
  const rank = {
    KNET: 6,
    'Apple Pay': 6,
    Cash: 5,
    Prepaid: 3,
    'Online Payment': 3,
  };
  const labels = [];
  for (const value of values) {
    const raw = String(value || '').trim();
    if (!raw) continue;
    let label = rank[raw] != null ? raw : classifyTalabatPaymentText(raw);
    if (label === 'Online Payment') label = 'Prepaid';
    if (!label) continue;
    labels.push(label);
  }
  if (labels.includes('Cash')) return 'Cash';
  if (labels.includes('KNET')) return 'KNET';
  if (labels.includes('Apple Pay')) return 'Apple Pay';
  if (labels.includes('Prepaid')) return 'Prepaid';
  let best = '';
  let bestRank = -1;
  for (const label of labels) {
    const score = rank[label] || 1;
    if (score > bestRank) {
      best = label;
      bestRank = score;
    }
  }
  return best;
}

function extractTalabatPaymentMethod(root) {
  if (!root?.querySelectorAll) return '';
  const leafValues = Array.from(root.querySelectorAll('*'))
    .filter((node) => node.children.length === 0)
    .map(normalizedText)
    .filter(Boolean);
  // Prefer short payment-looking leaves so filter chips don't drown the value.
  const paymentLeaves = leafValues.filter(
    (value) =>
      value.length <= 64 &&
      /cash|cod|knet|prepaid|online|apple|visa|card|كاش|نقدي|مدفوع|كي\s*نت|إلكتروني/i.test(
        value,
      ),
  );
  for (const leaf of paymentLeaves) {
    if (isExplicitCashPayment(leaf)) return 'Cash';
  }
  for (const leaf of paymentLeaves) {
    const classified = classifyTalabatPaymentText(leaf);
    if (classified) return classified;
  }
  const blob = [normalizedText(root), ...leafValues].join('\n');
  return classifyTalabatPaymentText(blob);
}

function talabatOutcome(root) {
  const text = normalizedText(root).toLowerCase();
  return /cancel|refund|reject|void|ملغ|مرفوض|مسترد/.test(text)
    ? 'cancelled'
    : 'successful';
}

function talabatCreatedAt(root, fallback) {
  const fromColumn = talabatHistoryCreatedAt(normalizedText(root));
  if (fromColumn) return fromColumn;
  const text = normalizedText(root);
  const time = text.match(/\b(\d{1,2}):(\d{2})(?:\s*(AM|PM|ص|م))?\b/i);
  let hour = Number(time?.[1] || 12);
  const meridiem = String(time?.[3] || '').toUpperCase();
  if ((meridiem === 'PM' || meridiem === 'م') && hour < 12) hour += 12;
  if ((meridiem === 'AM' || meridiem === 'ص') && hour === 12) hour = 0;

  let year;
  let month;
  let day;
  const dmy = text.match(/\b(\d{1,2})[./-](\d{1,2})[./-](\d{4})\b/);
  const ymd = text.match(/\b(\d{4})[./-](\d{1,2})[./-](\d{1,2})\b/);
  const named = text.match(
    /\b(\d{1,2})\s+(Jan(?:uary)?|Feb(?:ruary)?|Mar(?:ch)?|Apr(?:il)?|May|Jun(?:e)?|Jul(?:y)?|Aug(?:ust)?|Sep(?:tember)?|Oct(?:ober)?|Nov(?:ember)?|Dec(?:ember)?)\s+(\d{4})\b/i,
  );
  if (dmy) {
    [, day, month, year] = dmy;
  } else if (ymd) {
    [, year, month, day] = ymd;
  } else if (named) {
    const months = [
      'jan', 'feb', 'mar', 'apr', 'may', 'jun',
      'jul', 'aug', 'sep', 'oct', 'nov', 'dec',
    ];
    day = named[1];
    month = String(months.indexOf(named[2].slice(0, 3).toLowerCase()) + 1);
    year = named[3];
  } else if (/\b(today|اليوم)\b/i.test(text)) {
    const parts = Object.fromEntries(
      new Intl.DateTimeFormat('en', {
        timeZone: 'Asia/Kuwait',
        year: 'numeric',
        month: '2-digit',
        day: '2-digit',
      })
        .formatToParts(new Date())
        .map((part) => [part.type, part.value]),
    );
    ({ year, month, day } = parts);
  } else {
    return fallback;
  }
  const iso = `${year}-${String(month).padStart(2, '0')}-${String(day).padStart(
    2,
    '0',
  )}T${String(hour).padStart(2, '0')}:${time?.[2] || '00'}:00+03:00`;
  const parsed = new Date(iso);
  return Number.isNaN(parsed.getTime()) ? fallback : parsed.toISOString();
}

async function expandTalabatCustomerDetails(root, delayMs = 250) {
  const heading = findCustomerDetailsHeading(root);
  const toggle = customerDetailsToggle(heading);
  if (!toggle) return false;
  const hasExplicitState =
    toggle.getAttribute?.('aria-expanded') != null ||
    toggle.getAttribute?.('data-state') != null;
  const collapsed = customerDetailsAreCollapsed(toggle);
  if (hasExplicitState && !collapsed) {
    return false;
  }
  if (!hasExplicitState && customerDetailsFieldsAreVisible(root)) {
    return false;
  }
  if (typeof toggle.click !== 'function') return false;
  toggle.click();
  if (delayMs > 0) {
    await new Promise((resolve) => setTimeout(resolve, delayMs));
  }
  return true;
}

async function waitForTalabatCustomerDetails(
  root,
  { timeoutMs = 2500, pollMs = 100 } = {},
) {
  await expandTalabatCustomerDetails(root);
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    if (customerDetailsFieldsAreVisible(root)) {
      return extractTalabatCustomerDetails(root);
    }
    await new Promise((resolve) => setTimeout(resolve, pollMs));
  }
  return extractTalabatCustomerDetails(root);
}

function extractTalabatCustomerDetails(root) {
  const { nameNode, addressNode, phoneNode } = customerDetailValueNodes(root);
  return {
    customerName: cleanCustomerName(normalizedText(nameNode)),
    phone: cleanCustomerPhone(normalizedText(phoneNode)),
    address: cleanCustomerAddress(normalizedText(addressNode)),
  };
}

class TalabatAdapter extends BaseAdapter {
  constructor(document) {
    super({ platform: 'talabat', selectors, document });
  }

  historyRows(limit = 500) {
    const cap = Math.max(1, Math.min(500, Number(limit) || 500));
    const todayRows = collectTalabatTodayRows(this.document, cap);
    if (todayRows.length) return todayRows;
    return super.historyRows(cap);
  }

  ensureTodayFilter() {
    return focusTalabatTodayFilter(this.document);
  }

  async prepareHistoryScan({ wait }) {
    const step = this.ensureTodayFilter();
    if (step === 'opened') {
      if (typeof wait === 'function') await wait(400);
      chooseTalabatTodayOption(this.document);
      if (typeof wait === 'function') await wait(700);
      return;
    }
    if (step === 'clicked' && typeof wait === 'function') await wait(700);
  }

  historyContainer() {
    const row = this.historyRows(1)[0];
    let node = row?.parentElement || null;
    let best = super.historyContainer();
    let bestRoom = 0;
    while (node) {
      const room = Number(node.scrollHeight) - Number(node.clientHeight);
      if (room > bestRoom + 40 && Number(node.clientHeight) > 80) {
        best = node;
        bestRoom = room;
      }
      node = node.parentElement || null;
    }
    return best;
  }

  readLiveOrderRows(limit = 500) {
    try {
      return this.historyRows(limit);
    } catch (error) {
      console.warn(
        `[talabat] history selector failed: ${String(error?.message || error).slice(0, 200)}`,
      );
      return [];
    }
  }

  externalOrderId(root) {
    const cells = root?.querySelectorAll?.("td, [role='gridcell']") || [];
    for (const cell of cells) {
      const id = extractTalabatColumnOrderId(cell.textContent);
      if (id) return id;
    }
    return (
      extractTalabatColumnOrderId(super.externalOrderId(root)) ||
      super.externalOrderId(root)
    );
  }

  parseItem(node) {
    const parsed = super.parseItem(node);
    if (parsed.name) return parsed;
    const text = String(node.textContent || '').replace(/\s+/g, ' ').trim();
    const match = text.match(
      /^(\d+)\s*[×x]\s*(.+?)\s*KWD\s*([\d.,]+)/i,
    );
    if (!match) return parsed;
    const quantity = this.quantity(match[1]);
    const lineTotal = this.amount(match[3]);
    const unitPrice = Number((lineTotal / quantity).toFixed(3));
    const platformItemId =
      node.getAttribute?.('data-product-id') ||
      node.getAttribute?.('data-item-id') ||
      '';
    const sku = node.getAttribute?.('data-sku') || '';
    return {
      name: match[2].trim(),
      ...(platformItemId ? { platformItemId } : {}),
      ...(sku ? { sku } : {}),
      quantity,
      unitPrice,
      lineTotal,
      options: [],
    };
  }

  providerCreatedAt(root) {
    return talabatCreatedAt(root, null);
  }

  async prepareOrderDetail(root) {
    this._preparedCustomerDetails = null;
    this._preparedPaymentMethod = '';
    const scope = findCustomerDetailsHeading(root) ? root : this.document;
    this._preparedCustomerDetails =
      await waitForTalabatCustomerDetails(scope);
    this._preparedPaymentMethod = extractTalabatPaymentMethod(scope);
  }

  parseOrder(root, externalOrderIdOverride = '') {
    const order = super.parseOrder(root, externalOrderIdOverride);
    const createdAtNode = this.selectors.createdAt
      ? root.querySelector(this.selectors.createdAt)
      : null;
    const createdAtRaw =
      createdAtNode?.getAttribute?.('datetime') ||
      createdAtNode?.textContent ||
      '';
    const explicitCreatedAt = new Date(String(createdAtRaw).trim());
    const providerCreatedAt = talabatCreatedAt(
      root,
      createdAtRaw && !Number.isNaN(explicitCreatedAt.getTime())
        ? explicitCreatedAt.toISOString()
        : null,
    );
    const parsedCustomer = extractTalabatCustomerDetails(root);
    const preparedCustomer = this._preparedCustomerDetails || {};
    const customer = {
      customerName:
        parsedCustomer.customerName || preparedCustomer.customerName || '',
      phone: parsedCustomer.phone || preparedCustomer.phone || '',
      address: parsedCustomer.address || preparedCustomer.address || '',
    };
    const paymentMethod = preferPaymentMethod(
      extractTalabatPaymentMethod(root),
      this._preparedPaymentMethod,
      order.paymentMethod,
    );
    this._preparedCustomerDetails = null;
    this._preparedPaymentMethod = '';
    const result = {
      ...order,
      customerName:
        cleanCustomerName(order.customerName) || customer.customerName,
      phone: cleanCustomerPhone(order.phone) || customer.phone,
      address: cleanCustomerAddress(order.address) || customer.address,
      paymentMethod,
      externalStatus: talabatOutcome(root),
    };
    if (providerCreatedAt) {
      result.createdAt = providerCreatedAt;
    } else {
      delete result.createdAt;
    }
    return result;
  }
}

module.exports = {
  classifyTalabatPaymentText,
  cleanCustomerAddress,
  cleanCustomerName,
  cleanCustomerPhone,
  customerDetailsFieldsAreVisible,
  expandTalabatCustomerDetails,
  extractTalabatCustomerDetails,
  extractTalabatPaymentMethod,
  findCustomerDetailsHeading,
  preferPaymentMethod,
  waitForTalabatCustomerDetails,
  talabatCreatedAt,
  talabatOutcome,
  TalabatAdapter,
};
