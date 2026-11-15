const { readKitchens, writeKitchens, readDeliveryZones, writeDeliveryZones, readStaffUsers, writeStaffUsers } = require('./dataStore');
const { hashPin, createStaffRecord, updateStaffRecord } = require('./staffUsers');

function kitchenRestaurantId(kitchen) {
  return String(kitchen?.restaurant_id || kitchen?.restaurantId || '').trim();
}

function kitchenLabel(kitchen) {
  return String(
    kitchen?.name_ar || kitchen?.nameAr || kitchen?.name || kitchen?.name_en || kitchen?.id || '',
  );
}

function defaultKitchenTemplates(restaurantId) {
  const now = new Date().toISOString();
  const rid = String(restaurantId);
  const idPrefix = rid === 'rest_molton' ? '' : `__${rid.replace(/[^\w.-]/g, '_')}`;
  return [
    {
      id: `kitchen_ardiya${idPrefix}`,
      restaurant_id: rid,
      restaurantId: rid,
      name: 'مطبخ العارضية',
      name_ar: 'مطبخ العارضية',
      nameAr: 'مطبخ العارضية',
      name_en: 'Al-Ardiya Kitchen',
      nameEn: 'Al-Ardiya Kitchen',
      code: 'ARD',
      status: 'active',
      is_default: true,
      isDefault: true,
      sort_order: 1,
      sortOrder: 1,
      kds_enabled: true,
      kdsEnabled: true,
      createdAt: now,
      updatedAt: now,
    },
    {
      id: `kitchen_sabah${idPrefix}`,
      restaurant_id: rid,
      restaurantId: rid,
      name: 'مطبخ صباح السالم',
      name_ar: 'مطبخ صباح السالم',
      nameAr: 'مطبخ صباح السالم',
      name_en: 'Sabah Al-Salem Kitchen',
      nameEn: 'Sabah Al-Salem Kitchen',
      code: 'SBH',
      status: 'active',
      is_default: false,
      isDefault: false,
      sort_order: 2,
      sortOrder: 2,
      kds_enabled: true,
      kdsEnabled: true,
      createdAt: now,
      updatedAt: now,
    },
  ];
}

function guessKitchenForZone(zone, kitchens) {
  if (!Array.isArray(kitchens) || kitchens.length === 0) return null;
  const text = `${zone?.areaName || zone?.area_name || ''} ${zone?.governorate || ''}`.trim();
  const sabah = kitchens.find((kitchen) =>
    /صباح|sabah|sbh/i.test(`${kitchenLabel(kitchen)}${kitchen.code || ''}`),
  );
  const ardiya =
    kitchens.find((kitchen) =>
      /عارض|ardiya|ard/i.test(`${kitchenLabel(kitchen)}${kitchen.code || ''}`),
    ) ||
    kitchens.find((kitchen) => kitchen.is_default === true || kitchen.isDefault === true) ||
    kitchens[0];

  if (/صباح السالم|الأحمدي|الاحمدي|مبارك الكبير|فحيحيل|فنطاس|المهبولة|الرقة|هدية/.test(text)) {
    return sabah || ardiya;
  }
  if (/عارض|فروانية|الجهراء|الري|الشويخ/.test(text)) {
    return ardiya;
  }
  return ardiya;
}

async function getActiveKitchens(restaurantId) {
  const kitchens = await readKitchens();
  const active = kitchens.filter(
    (kitchen) =>
      kitchenRestaurantId(kitchen) === String(restaurantId) &&
      String(kitchen.status || 'active') === 'active',
  );
  if (active.length > 0) return active;
  const seeded = await ensureDefaultKitchens(restaurantId);
  return seeded.filter((kitchen) => String(kitchen.status || 'active') === 'active');
}

async function getDefaultKitchen(restaurantId, kitchens = null) {
  const active = kitchens || (await getActiveKitchens(restaurantId));
  return active.find((k) => k.is_default === true || k.isDefault === true) || active[0] || null;
}

function zoneDefaultKitchenId(zone) {
  if (!zone) return null;
  return (
    zone.default_kitchen_id ||
    zone.defaultKitchenId ||
    zone.kitchen_id ||
    zone.kitchenId ||
    null
  );
}

async function ensureDefaultKitchens(restaurantId) {
  if (!restaurantId) return [];
  const all = await readKitchens();
  const existing = all.filter(
    (kitchen) => kitchenRestaurantId(kitchen) === String(restaurantId),
  );
  if (existing.length > 0) {
    return existing;
  }

  const seeded = defaultKitchenTemplates(restaurantId);
  await writeKitchens([...all, ...seeded]);
  await backfillZoneKitchens(restaurantId, seeded);
  return seeded;
}

async function backfillZoneKitchens(restaurantId, kitchens) {
  const zones = await readDeliveryZones();
  let changed = false;
  const next = zones.map((zone) => {
    if (String(zone.restaurant_id || zone.restaurantId) !== String(restaurantId)) {
      return zone;
    }
    if (zoneDefaultKitchenId(zone)) return zone;
    const guessed = guessKitchenForZone(zone, kitchens);
    if (!guessed) return zone;
    changed = true;
    return {
      ...zone,
      defaultKitchenId: guessed.id,
      default_kitchen_id: guessed.id,
    };
  });
  if (changed) {
    await writeDeliveryZones(next);
  }
}

async function resolveKitchenForZone({ restaurantId, deliveryZoneId, kitchens = null }) {
  const activeKitchens = kitchens || (await getActiveKitchens(restaurantId));
  if (!deliveryZoneId) {
    const kitchen = await getDefaultKitchen(restaurantId, activeKitchens);
    return { kitchen, source: 'platform_default' };
  }

  const zones = await readDeliveryZones();
  const zone = zones.find(
    (entry) =>
      String(entry.id) === String(deliveryZoneId) &&
      String(entry.restaurant_id || entry.restaurantId) === String(restaurantId),
  );

  const mappedId = zoneDefaultKitchenId(zone);
  if (!mappedId) {
    const guessed = guessKitchenForZone(zone, activeKitchens);
    if (guessed) return { kitchen: guessed, source: 'zone_auto' };
    const kitchen = await getDefaultKitchen(restaurantId, activeKitchens);
    return { kitchen, source: 'platform_default' };
  }

  const kitchen = activeKitchens.find((entry) => String(entry.id) === String(mappedId));
  if (!kitchen) {
    const fallback = await getDefaultKitchen(restaurantId, activeKitchens);
    return { kitchen: fallback, source: 'platform_default' };
  }

  return { kitchen, source: 'zone_auto' };
}

async function assignTargetKitchen({
  body,
  restaurantId,
  auth,
  deliveryZoneId,
}) {
  const kitchens = await getActiveKitchens(restaurantId);
  const requestedId = String(
    body.targetKitchenId || body.target_kitchen_id || '',
  ).trim();

  const orderType = String(body.orderType || body.order_type || 'Delivery')
    .trim()
    .toLowerCase();
  const isDelivery =
    orderType === 'delivery' ||
    orderType === 'توصيل' ||
    Boolean(deliveryZoneId || body.deliveryZoneId || body.delivery_zone_id);

  let kitchen;
  let source = 'platform_default';
  let overridden = false;
  let previousKitchenId = null;

  if (isDelivery) {
    const zoneId =
      deliveryZoneId || body.deliveryZoneId || body.delivery_zone_id || null;
    const resolved = await resolveKitchenForZone({
      restaurantId,
      deliveryZoneId: zoneId,
      kitchens,
    });
    kitchen = resolved.kitchen;
    source = resolved.source;
    previousKitchenId = kitchen?.id || null;

    if (requestedId && kitchen && requestedId !== kitchen.id) {
      const manual = kitchens.find((entry) => String(entry.id) === requestedId);
      if (!manual) {
        const err = new Error('Invalid target kitchen');
        err.code = 'INVALID_TARGET_KITCHEN';
        throw err;
      }
      overridden = true;
      source = 'cashier_override';
      previousKitchenId = kitchen.id;
      kitchen = manual;
    } else if (requestedId && !kitchen) {
      kitchen = kitchens.find((entry) => String(entry.id) === requestedId) || null;
      if (!kitchen) {
        const err = new Error('Invalid target kitchen');
        err.code = 'INVALID_TARGET_KITCHEN';
        throw err;
      }
      source = 'cashier_override';
    }
  } else if (requestedId) {
    kitchen = kitchens.find((entry) => String(entry.id) === requestedId) || null;
    source = 'cashier_override';
  } else {
    kitchen = await getDefaultKitchen(restaurantId, kitchens);
    source = 'platform_default';
  }

  if (!kitchen) {
    return null;
  }

  const now = new Date().toISOString();
  return {
    targetKitchenId: kitchen.id,
    target_kitchen_id: kitchen.id,
    targetKitchenName: kitchen.name_ar || kitchen.name || kitchen.name_en || kitchen.id,
    target_kitchen_name: kitchen.name_ar || kitchen.name || kitchen.name_en || kitchen.id,
    kitchenAssignment: {
      source,
      assignedAt: now,
      assigned_at: now,
      assignedById: auth?.staffId || auth?.id || null,
      assigned_by_id: auth?.staffId || auth?.id || null,
      assignedByName: auth?.name || auth?.cashierName || null,
      assigned_by_name: auth?.name || auth?.cashierName || null,
      overridden,
      previousKitchenId: overridden ? previousKitchenId : null,
      previous_kitchen_id: overridden ? previousKitchenId : null,
    },
    kitchen_assignment: {
      source,
      assigned_at: now,
      assigned_by_id: auth?.staffId || auth?.id || null,
      assigned_by_name: auth?.name || auth?.cashierName || null,
      overridden,
      previous_kitchen_id: overridden ? previousKitchenId : null,
    },
  };
}

function normalizeKitchen(raw, id, restaurantId) {
  const status = String(raw.status || 'active').trim().toLowerCase();
  const normalizedStatus = ['active', 'paused', 'archived'].includes(status)
    ? status
    : 'active';

  return {
    id: String(id),
    restaurant_id: String(restaurantId),
    restaurantId: String(restaurantId),
    name: String(raw.name || raw.name_ar || raw.nameAr || '').trim(),
    name_ar: String(raw.name_ar || raw.nameAr || raw.name || '').trim(),
    nameAr: String(raw.name_ar || raw.nameAr || raw.name || '').trim(),
    name_en: String(raw.name_en || raw.nameEn || raw.name || '').trim(),
    nameEn: String(raw.name_en || raw.nameEn || raw.name || '').trim(),
    code: String(raw.code || '').trim().toUpperCase(),
    status: normalizedStatus,
    is_default: raw.is_default === true || raw.isDefault === true,
    isDefault: raw.is_default === true || raw.isDefault === true,
    sort_order: Number(raw.sort_order ?? raw.sortOrder ?? 0) || 0,
    sortOrder: Number(raw.sort_order ?? raw.sortOrder ?? 0) || 0,
    kds_enabled:
      raw.kds_enabled !== false &&
      raw.kdsEnabled !== false &&
      raw.kds?.enabled !== false,
    kdsEnabled:
      raw.kds_enabled !== false &&
      raw.kdsEnabled !== false &&
      raw.kds?.enabled !== false,
    createdAt: raw.createdAt || raw.created_at || new Date().toISOString(),
    updatedAt: new Date().toISOString(),
    loginName: String(raw.loginName || raw.login_name || '').trim(),
    login_name: String(raw.loginName || raw.login_name || '').trim(),
    pinHash: (() => {
      const pin = String(raw.pin || raw.password || raw.loginPassword || '').trim();
      if (pin) return hashPin(pin, restaurantId);
      return String(raw.pinHash || raw.pin_hash || '');
    })(),
  };
}

function publicKitchen(kitchen) {
  if (!kitchen || typeof kitchen !== 'object') return kitchen;
  const copy = { ...kitchen };
  delete copy.pinHash;
  delete copy.pin_hash;
  delete copy.pin;
  delete copy.password;
  copy.loginName = kitchen.loginName || kitchen.login_name || '';
  copy.hasPassword = Boolean(kitchen.pinHash || kitchen.pin_hash);
  return copy;
}

async function upsertKitchenLoginStaff(kitchen, pin) {
  const loginName = String(kitchen.loginName || kitchen.login_name || '').trim();
  if (!loginName) return;
  const restaurantId = kitchenRestaurantId(kitchen);
  const staffUsers = await readStaffUsers();
  const index = staffUsers.findIndex(
    (entry) =>
      String(entry.kitchenId || entry.kitchen_id) === String(kitchen.id) &&
      String(entry.restaurantId || entry.restaurant_id) === String(restaurantId),
  );
  if (index >= 0) {
    staffUsers[index] = updateStaffRecord(staffUsers[index], {
      name: loginName,
      roleId: 'kitchen',
      kitchenId: kitchen.id,
      kitchen_id: kitchen.id,
      ...(pin ? { pin } : {}),
    });
  } else if (pin || kitchen.pinHash) {
    const record = createStaffRecord(
      {
        name: loginName,
        roleId: 'kitchen',
        kitchenId: kitchen.id,
        kitchen_id: kitchen.id,
        pin: pin || undefined,
        pinHash: kitchen.pinHash,
      },
      restaurantId,
    );
    staffUsers.push(record);
  } else {
    return;
  }
  await writeStaffUsers(staffUsers);
}

function orderTargetKitchenId(order) {
  return String(order?.targetKitchenId || order?.target_kitchen_id || '').trim();
}

function findKitchenByLogin(kitchens, restaurantId, loginName, pin) {
  const name = String(loginName || '').trim().toLowerCase();
  if (!name || !pin) return null;
  const hash = hashPin(pin, restaurantId);
  return (kitchens || []).find(
    (kitchen) =>
      kitchenRestaurantId(kitchen) === String(restaurantId) &&
      String(kitchen.loginName || kitchen.login_name || '').trim().toLowerCase() === name &&
      String(kitchen.pinHash || kitchen.pin_hash || '') === hash,
  ) || null;
}

module.exports = {
  getActiveKitchens,
  getDefaultKitchen,
  zoneDefaultKitchenId,
  resolveKitchenForZone,
  assignTargetKitchen,
  normalizeKitchen,
  kitchenRestaurantId,
  ensureDefaultKitchens,
  publicKitchen,
  upsertKitchenLoginStaff,
  findKitchenByLogin,
  orderTargetKitchenId,
};
