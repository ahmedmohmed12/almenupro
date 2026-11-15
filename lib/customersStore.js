const { ensureRestaurantId } = require('./tenantStore');

function normalizePhoneDigits(raw) {
  return String(raw || '').replace(/\D/g, '');
}

function phonesMatch(storedPhone, lookupPhone) {
  const stored = normalizePhoneDigits(storedPhone);
  const lookup = normalizePhoneDigits(lookupPhone);
  if (!stored || !lookup) return false;
  if (stored === lookup) return true;
  if (stored.length >= 8 && lookup.length >= 8) {
    return stored.slice(-8) === lookup.slice(-8);
  }
  return false;
}

function normalizeAddressDetails(raw = {}) {
  return {
    block: String(raw.block || '').trim(),
    street: String(raw.street || '').trim(),
    avenue: String(raw.avenue || '').trim(),
    houseNumber: String(raw.houseNumber || raw.house_number || '').trim(),
    floorApartment: String(
      raw.floorApartment || raw.floor_apartment || '',
    ).trim(),
  };
}

function cleanAddress(value) {
  return String(value || '').replace(/\s+/g, ' ').trim();
}

function normalizeAddresses(raw) {
  const list = Array.isArray(raw) ? raw : [];
  const seen = new Set();
  const out = [];
  for (const row of list) {
    const address = cleanAddress(typeof row === 'string' ? row : row?.address);
    if (!address) continue;
    const key = address.toLowerCase();
    if (seen.has(key)) continue;
    seen.add(key);
    out.push({
      address,
      savedAt: (row && (row.savedAt || row.saved_at)) || null,
    });
    if (out.length >= 40) break;
  }
  return out;
}

function rememberAddress(addresses, address, savedAt) {
  const text = cleanAddress(address);
  const current = normalizeAddresses(addresses);
  if (!text) return current;
  const rest = current.filter((row) => row.address.toLowerCase() !== text.toLowerCase());
  return [{ address: text, savedAt: savedAt || new Date().toISOString() }, ...rest].slice(0, 40);
}

function normalizeInvoices(raw) {
  const list = Array.isArray(raw) ? raw : [];
  const seen = new Set();
  const out = [];
  for (const row of list) {
    const orderId = String(row?.orderId || row?.order_id || row?.id || '').trim();
    if (!orderId || seen.has(orderId)) continue;
    seen.add(orderId);
    out.push({
      orderId,
      invoiceNumber: String(row.invoiceNumber || row.invoice_number || '').trim(),
      platform: String(row.platform || row.orderSource || row.order_source || '')
        .trim()
        .toLowerCase(),
      total: Number(row.total ?? row.totalPrice ?? row.total_price ?? 0) || 0,
      address: cleanAddress(row.address),
      createdAt: row.createdAt || row.created_at || null,
    });
    if (out.length >= 300) break;
  }
  return out;
}

function invoiceFromSource(source, address) {
  const orderId = String(source.id || source.orderId || source.order_id || '').trim();
  if (!orderId) return null;
  return {
    orderId,
    invoiceNumber: String(
      source.invoiceNumber ||
        source.invoice_number ||
        source.externalOrderId ||
        source.external_order_id ||
        '',
    ).trim(),
    platform: String(source.orderSource || source.order_source || '')
      .trim()
      .toLowerCase(),
    total:
      Number(
        source.customerPayableTotal ??
          source.customer_payable_total ??
          source.totalPrice ??
          source.total_price ??
          0,
      ) || 0,
    address: cleanAddress(address),
    createdAt: source.createdAt || source.created_at || null,
  };
}

function rememberInvoice(invoices, invoice) {
  const current = normalizeInvoices(invoices);
  if (!invoice?.orderId) return current;
  const rest = current.filter((row) => row.orderId !== invoice.orderId);
  return [invoice, ...rest].slice(0, 300);
}

function collectCustomerAddresses(customer, orders = []) {
  let addresses = rememberAddress(
    customer?.addresses,
    customer?.address,
    customer?.updatedAt || customer?.updated_at,
  );
  const sorted = [...orders].sort((a, b) => {
    const aTime = Date.parse(a.createdAt || a.created_at || 0);
    const bTime = Date.parse(b.createdAt || b.created_at || 0);
    return aTime - bTime;
  });
  for (const order of sorted) {
    addresses = rememberAddress(addresses, order.address, order.createdAt || order.created_at);
  }
  return addresses;
}

function formatCustomerAddress(customer) {
  const saved = String(customer.address || '').trim();
  if (saved) return saved;

  const details = normalizeAddressDetails(customer.addressDetails || {});
  const parts = [
    customer.governorate,
    customer.areaName,
    details.block ? `قطعة ${details.block}` : '',
    details.street ? `شارع ${details.street}` : '',
    details.avenue ? `جادة ${details.avenue}` : '',
    details.houseNumber ? `مبنى ${details.houseNumber}` : '',
    details.floorApartment ? `طابق/شقة ${details.floorApartment}` : '',
  ].filter(Boolean);
  return parts.join('، ');
}

function customerProfileFromRecord(customer) {
  const walletBalance =
    Number(customer.walletBalance ?? customer.wallet_balance ?? 0) || 0;
  const totalOrders = Number(customer.totalOrders ?? customer.total_orders ?? 0) || 0;
  return {
    customerId: customer.id || null,
    customerName: customer.customerName || '',
    phone: customer.phone || '',
    governorate: customer.governorate || '',
    areaName: customer.areaName || '',
    deliveryZoneId: customer.deliveryZoneId || null,
    addressDetails: normalizeAddressDetails(customer.addressDetails || {}),
    paymentMethod: customer.paymentMethod || 'كاش',
    walletBalance,
    wallet_balance: walletBalance,
    totalOrders,
    total_orders: totalOrders,
  };
}

function isMissingCustomerName(value) {
  const text = String(value || '').trim();
  if (!text) return true;
  if (/^\*+$/.test(text) || /\*{2,}/.test(text)) return true;
  return /^(unknown|customer|n\/a|na|null|undefined|عميل|بدون اسم)$/i.test(text);
}

function customerNameFromPlatform(name) {
  const cleaned = String(name || '').replace(/\s+/g, ' ').trim();
  if (!isMissingCustomerName(cleaned)) return cleaned.slice(0, 200);
  return 'عميل منصات';
}

function nameLooksLikePhone(name, phone) {
  const nameDigits = normalizePhoneDigits(name);
  const phoneDigits = normalizePhoneDigits(phone);
  if (nameDigits.length < 8 || phoneDigits.length < 8) return false;
  return nameDigits === phoneDigits || nameDigits.slice(-8) === phoneDigits.slice(-8);
}

function customerProfileFromOrder(order) {
  const phone = order.phone || order.customer_phone || '';
  return {
    customerName: customerNameFromPlatform(
      order.customerName || order.customer_name,
      phone,
    ),
    phone,
    governorate: order.governorate || '',
    areaName: order.areaName || '',
    deliveryZoneId: order.deliveryZoneId || null,
    addressDetails: normalizeAddressDetails(order.addressDetails || {}),
    paymentMethod: order.paymentMethod || 'كاش',
  };
}

function normalizeCustomer(raw, id, restaurantId) {
  const phone = normalizePhoneDigits(raw.phone);
  const now = new Date().toISOString();

  return ensureRestaurantId(
    {
      id: String(id),
      phone,
      customerName: customerNameFromPlatform(
        raw.customerName || raw.customer_name,
        raw.phone,
      ),
      origin: 'almenupro',
      address: String(raw.address || '').trim(),
      governorate: String(raw.governorate || '').trim(),
      areaName: String(raw.areaName || raw.area_name || '').trim(),
      deliveryZoneId:
        raw.deliveryZoneId?.toString() || raw.delivery_zone_id?.toString() || null,
      addressDetails: normalizeAddressDetails(raw.addressDetails || raw.address_details || {}),
      paymentMethod: String(raw.paymentMethod || raw.payment_method || 'كاش').trim() || 'كاش',
      totalOrders: Number(raw.totalOrders ?? raw.total_orders ?? 0) || 0,
      walletBalance: Number(raw.walletBalance ?? raw.wallet_balance ?? 0) || 0,
      wallet_balance: Number(raw.walletBalance ?? raw.wallet_balance ?? 0) || 0,
      walletHistory: Array.isArray(raw.walletHistory)
        ? raw.walletHistory
        : Array.isArray(raw.wallet_history)
          ? raw.wallet_history
          : [],
      orderIds: Array.isArray(raw.orderIds)
        ? raw.orderIds.map((id) => String(id)).filter(Boolean).slice(0, 300)
        : Array.isArray(raw.order_ids)
          ? raw.order_ids.map((id) => String(id)).filter(Boolean).slice(0, 300)
          : [],
      addresses: normalizeAddresses(raw.addresses),
      invoices: normalizeInvoices(raw.invoices),
      createdAt: raw.createdAt || raw.created_at || now,
      updatedAt: raw.updatedAt || raw.updated_at || now,
    },
    restaurantId,
  );
}

function findCustomerByPhone(customers, restaurantId, phone) {
  const normalized = normalizePhoneDigits(phone);
  if (!normalized) return null;

  return (
    customers.find(
      (customer) =>
        String(customer.restaurant_id || customer.restaurantId || '') ===
          String(restaurantId) && phonesMatch(customer.phone, normalized),
    ) || null
  );
}

function upsertCustomerFromSource(customers, source, restaurantId) {
  const profile = source.customerName != null ? source : customerProfileFromOrder(source);
  const rawPhone = String(profile.phone || source.phone || '').trim();
  const phone = normalizePhoneDigits(rawPhone);
  if (!phone || phone.length < 8) {
    return customers;
  }

  const now = new Date().toISOString();
  const addressDetails = normalizeAddressDetails(profile.addressDetails || {});
  const address =
    String(source.address || profile.address || '').trim() ||
    formatCustomerAddress({
      governorate: profile.governorate,
      areaName: profile.areaName,
      addressDetails,
    });
  const orderId = String(source.id || source.orderId || source.order_id || '').trim();
  const resolvedName = customerNameFromPlatform(profile.customerName, rawPhone || phone);
  const existingIndex = customers.findIndex(
    (customer) =>
      String(customer.restaurant_id || customer.restaurantId || '') ===
        String(restaurantId) && phonesMatch(customer.phone, phone),
  );

  if (existingIndex === -1) {
    const id = `cust_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`;
    return [
      normalizeCustomer(
        {
          customerName: resolvedName,
          phone: rawPhone || phone,
          address,
          governorate: profile.governorate,
          areaName: profile.areaName,
          deliveryZoneId: profile.deliveryZoneId,
          addressDetails,
          paymentMethod: profile.paymentMethod || 'كاش',
          origin: 'almenupro',
          orderIds: orderId ? [orderId] : [],
          addresses: rememberAddress([], address, source.createdAt || source.created_at || now),
          invoices: rememberInvoice([], invoiceFromSource(source, address)),
          totalOrders: 1,
          createdAt: now,
          updatedAt: now,
        },
        id,
        restaurantId,
      ),
      ...customers,
    ];
  }

  const existing = customers[existingIndex];
  const knownOrders = Array.isArray(existing.orderIds) ? existing.orderIds.map(String) : [];
  const alreadyCounted = Boolean(orderId) && knownOrders.includes(orderId);
  const orderIds =
    alreadyCounted || !orderId ? knownOrders : [orderId, ...knownOrders].slice(0, 300);
  const incomingMissing =
    isMissingCustomerName(profile.customerName) ||
    nameLooksLikePhone(profile.customerName, rawPhone);
  const existingMissing =
    isMissingCustomerName(existing.customerName) ||
    nameLooksLikePhone(existing.customerName, existing.phone || phone);
  const nextName =
    !existingMissing && incomingMissing
      ? existing.customerName
      : existingMissing && incomingMissing
        ? normalizePhoneDigits(existing.customerName).length >=
          normalizePhoneDigits(resolvedName).length
          ? existing.customerName || resolvedName
          : resolvedName || existing.customerName
        : resolvedName || existing.customerName;
  const addresses = rememberAddress(
    rememberAddress(existing.addresses, existing.address, existing.updatedAt),
    address,
    source.createdAt || source.created_at || now,
  );
  const invoices = rememberInvoice(existing.invoices, invoiceFromSource(source, address));
  const latestAddress = !alreadyCounted && address ? address : existing.address || address;
  const nameChanged = String(nextName || '') !== String(existing.customerName || '');
  const zoneChanged =
    Boolean(profile.deliveryZoneId) &&
    String(profile.deliveryZoneId) !== String(existing.deliveryZoneId || '');
  const governorateChanged =
    Boolean(profile.governorate) &&
    String(profile.governorate) !== String(existing.governorate || '');
  const areaChanged =
    Boolean(profile.areaName) && String(profile.areaName) !== String(existing.areaName || '');
  const addressKey = (list) =>
    normalizeAddresses(list)
      .map((row) => row.address.toLowerCase())
      .join('\n');
  const invoiceKey = (list) =>
    normalizeInvoices(list)
      .map((row) => [row.orderId, row.invoiceNumber, row.platform, row.total, row.address].join('|'))
      .join('\n');
  const addressesChanged = addressKey(addresses) !== addressKey(existing.addresses);
  const invoicesChanged = invoiceKey(invoices) !== invoiceKey(existing.invoices);
  const contactUnchanged =
    !nameChanged && !zoneChanged && !governorateChanged && !areaChanged && !addressesChanged && !invoicesChanged;
  if ((alreadyCounted || !orderId) && contactUnchanged) {
    return customers;
  }

  const next = [...customers];
  next[existingIndex] = normalizeCustomer(
    {
      ...existing,
      customerName: nextName,
      phone: rawPhone || phone,
      address: latestAddress,
      governorate: profile.governorate || existing.governorate,
      areaName: profile.areaName || existing.areaName,
      deliveryZoneId: profile.deliveryZoneId || existing.deliveryZoneId,
      addressDetails: address ? addressDetails : existing.addressDetails,
      paymentMethod: profile.paymentMethod || existing.paymentMethod || 'كاش',
      origin: 'almenupro',
      orderIds,
      addresses,
      invoices,
      totalOrders: orderId ? orderIds.length : Number(existing.totalOrders || 0),
      createdAt: existing.createdAt,
      updatedAt: now,
    },
    existing.id,
    restaurantId,
  );

  return next;
}

function enrichCustomersForRestaurant(customers, orders, restaurantId) {
  const scopedCustomers = customers.filter(
    (customer) =>
      String(customer.restaurant_id || customer.restaurantId || '') ===
      String(restaurantId),
  );
  const scopedOrders = orders.filter(
    (order) =>
      String(order.restaurant_id || order.restaurantId || '') === String(restaurantId),
  );

  return scopedCustomers
    .map((customer) => {
      const matchedOrders = scopedOrders.filter(
        (order) =>
          phonesMatch(order.phone, customer.phone) ||
          (Array.isArray(customer.orderIds) &&
            customer.orderIds.map(String).includes(String(order.id))),
      );
      const addresses = collectCustomerAddresses(customer, matchedOrders);
      return {
        ...customer,
        customerName: customerNameFromPlatform(customer.customerName, customer.phone),
        totalOrders: matchedOrders.length || customer.totalOrders || 0,
        addresses,
        formattedAddress: addresses[0]?.address || formatCustomerAddress(customer),
      };
    })
    .sort((a, b) => {
      const aTime = Date.parse(a.updatedAt || a.createdAt || 0);
      const bTime = Date.parse(b.updatedAt || b.createdAt || 0);
      return bTime - aTime;
    });
}

function migrateCustomersFromOrders(customers, orders) {
  let next = customers;
  const sortedOrders = [...orders].sort((a, b) => {
    const aTime = Date.parse(a.createdAt || 0);
    const bTime = Date.parse(b.createdAt || 0);
    return aTime - bTime;
  });

  for (const order of sortedOrders) {
    const restaurantId = order.restaurant_id || order.restaurantId;
    if (!restaurantId || !order.phone) continue;
    next = upsertCustomerFromSource(next, order, restaurantId);
  }

  return next;
}

function identifyCustomerByPhone(customers, restaurantId, phone) {
  const normalized = normalizePhoneDigits(phone);
  if (!normalized || normalized.length < 8) {
    throw new Error('يرجى إدخال رقم هاتف صحيح');
  }

  const existing = findCustomerByPhone(customers, restaurantId, normalized);
  if (existing) {
    return { customers, isNew: false, customer: existing };
  }

  const now = new Date().toISOString();
  const created = normalizeCustomer(
    {
      phone: normalized,
      customerName: '',
      totalOrders: 0,
      walletBalance: 0,
      createdAt: now,
      updatedAt: now,
    },
    `cust_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`,
    restaurantId,
  );
  return {
    customers: [created, ...customers],
    isNew: true,
    customer: created,
  };
}

module.exports = {
  normalizePhoneDigits,
  phonesMatch,
  normalizeAddressDetails,
  formatCustomerAddress,
  customerProfileFromRecord,
  customerProfileFromOrder,
  normalizeCustomer,
  collectCustomerAddresses,
  customerNameFromPlatform,
  findCustomerByPhone,
  isMissingCustomerName,
  upsertCustomerFromSource,
  enrichCustomersForRestaurant,
  migrateCustomersFromOrders,
  identifyCustomerByPhone,
};
