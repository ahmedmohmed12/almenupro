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
  return {
    customerName: customer.customerName || '',
    phone: customer.phone || '',
    governorate: customer.governorate || '',
    areaName: customer.areaName || '',
    deliveryZoneId: customer.deliveryZoneId || null,
    addressDetails: normalizeAddressDetails(customer.addressDetails || {}),
    paymentMethod: customer.paymentMethod || 'كاش',
  };
}

function customerProfileFromOrder(order) {
  return {
    customerName: order.customerName || '',
    phone: order.phone || '',
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
      customerName: String(raw.customerName || raw.customer_name || '').trim(),
      address: String(raw.address || '').trim(),
      governorate: String(raw.governorate || '').trim(),
      areaName: String(raw.areaName || raw.area_name || '').trim(),
      deliveryZoneId:
        raw.deliveryZoneId?.toString() || raw.delivery_zone_id?.toString() || null,
      addressDetails: normalizeAddressDetails(raw.addressDetails || raw.address_details || {}),
      paymentMethod: String(raw.paymentMethod || raw.payment_method || 'كash').trim() || 'كاش',
      totalOrders: Number(raw.totalOrders ?? raw.total_orders ?? 0) || 0,
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
  const phone = normalizePhoneDigits(profile.phone);
  if (!phone || phone.length < 8) {
    return customers;
  }

  const next = [...customers];
  const existingIndex = next.findIndex(
    (customer) =>
      String(customer.restaurant_id || customer.restaurantId || '') ===
        String(restaurantId) && phonesMatch(customer.phone, phone),
  );

  const now = new Date().toISOString();
  const addressDetails = normalizeAddressDetails(profile.addressDetails || {});
  const address =
    String(source.address || '').trim() ||
    formatCustomerAddress({
      governorate: profile.governorate,
      areaName: profile.areaName,
      addressDetails,
    });

  if (existingIndex === -1) {
    const id = `cust_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`;
    next.unshift(
      normalizeCustomer(
        {
          ...profile,
          phone,
          address,
          addressDetails,
          totalOrders: 1,
          createdAt: now,
          updatedAt: now,
        },
        id,
        restaurantId,
      ),
    );
    return next;
  }

  const existing = next[existingIndex];
  next[existingIndex] = normalizeCustomer(
    {
      ...existing,
      customerName: profile.customerName || existing.customerName,
      phone,
      address: address || existing.address,
      governorate: profile.governorate || existing.governorate,
      areaName: profile.areaName || existing.areaName,
      deliveryZoneId: profile.deliveryZoneId || existing.deliveryZoneId,
      addressDetails,
      paymentMethod: profile.paymentMethod || existing.paymentMethod || 'كاش',
      totalOrders: Number(existing.totalOrders || 0) + 1,
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
      const orderCount = scopedOrders.filter((order) =>
        phonesMatch(order.phone, customer.phone),
      ).length;
      return {
        ...customer,
        totalOrders: orderCount || customer.totalOrders || 0,
        formattedAddress: formatCustomerAddress(customer),
      };
    })
    .sort((a, b) => {
      const aTime = Date.parse(a.updatedAt || a.createdAt || 0);
      const bTime = Date.parse(b.updatedAt || b.createdAt || 0);
      return bTime - aTime;
    });
}

function migrateCustomersFromOrders(customers, orders) {
  let next = [...customers];
  const sortedOrders = [...orders].sort((a, b) => {
    const aTime = Date.parse(a.createdAt || 0);
    const bTime = Date.parse(b.createdAt || 0);
    return aTime - bTime;
  });

  for (const order of sortedOrders) {
    const restaurantId = order.restaurant_id || order.restaurantId;
    if (!restaurantId || !order.phone) continue;
    if (findCustomerByPhone(next, restaurantId, order.phone)) continue;
    next = upsertCustomerFromSource(next, order, restaurantId);
    const index = findCustomerByPhone(next, restaurantId, order.phone);
    if (index) {
      // Keep migrated totalOrders at 1; listing recomputes accurate counts.
    }
  }

  return next;
}

module.exports = {
  normalizePhoneDigits,
  phonesMatch,
  normalizeAddressDetails,
  formatCustomerAddress,
  customerProfileFromRecord,
  customerProfileFromOrder,
  normalizeCustomer,
  findCustomerByPhone,
  upsertCustomerFromSource,
  enrichCustomersForRestaurant,
  migrateCustomersFromOrders,
};
