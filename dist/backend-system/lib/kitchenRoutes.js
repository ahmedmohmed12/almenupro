const {
  normalizeKitchen,
  kitchenRestaurantId,
  ensureDefaultKitchens,
  publicKitchen,
  upsertKitchenLoginStaff,
} = require('./kitchenRouting');

async function handleKitchenRoutes(req, res, url, ctx) {
  const {
    readBody,
    sendJson,
    authError,
    parseAuthHeader,
    requireAuth,
    rejectCashier,
    resolveScopedRestaurantId,
    resolveRestaurantId,
    assertRestaurantAccess,
    filterByRestaurant,
    readKitchens,
    writeKitchens,
    readOrders,
    readRestaurants,
    isKitchenManagementEnabled,
    DEFAULT_RESTAURANT_ID,
  } = ctx;

  async function rejectIfKitchenAddonDisabled(restaurantId) {
    const restaurants = await readRestaurants();
    const restaurant = restaurants.find((entry) => String(entry.id) === String(restaurantId));
    if (!isKitchenManagementEnabled(restaurant)) {
      sendJson(res, 403, {
        error: 'إدارة المطابخ غير مفعّلة في اشتراك هذا المطعم',
        code: 'KITCHEN_MANAGEMENT_DISABLED',
      });
      return true;
    }
    return false;
  }

  if (req.method === 'GET' && url.pathname === '/api/kitchens') {
    const auth = parseAuthHeader(req);
    const restaurantId = await resolveScopedRestaurantId(req, url, auth, {
      allowPublicDefault: true,
    });

    if (!restaurantId) {
      sendJson(res, 404, { error: 'Restaurant not found', code: 'RESTAURANT_NOT_FOUND' });
      return true;
    }

    const restaurants = await readRestaurants();
    const restaurant = restaurants.find((entry) => String(entry.id) === String(restaurantId));
    if (!isKitchenManagementEnabled(restaurant)) {
      sendJson(res, 200, []);
      return true;
    }

    await ensureDefaultKitchens(restaurantId);

    const includeInactive = url.searchParams.get('include_inactive') === '1';
    const allKitchens = filterByRestaurant(await readKitchens(), restaurantId);
    const kitchens = includeInactive
      ? allKitchens
      : allKitchens.filter((kitchen) => String(kitchen.status || 'active') === 'active');

    kitchens.sort(
      (a, b) =>
        (Number(a.sort_order ?? a.sortOrder ?? 0) || 0) -
        (Number(b.sort_order ?? b.sortOrder ?? 0) || 0),
    );
    sendJson(res, 200, kitchens.map((kitchen) => publicKitchen(kitchen)));
    return true;
  }

  if (req.method === 'POST' && url.pathname === '/api/kitchens') {
    const auth = requireAuth(req, res);
    if (!auth) return true;
    if (rejectCashier(auth, res, 'Cashiers cannot manage kitchens')) return true;

    try {
      const body = JSON.parse((await readBody(req)) || '{}');
      const restaurantId = resolveRestaurantId(
        auth,
        body.restaurantId ||
          body.restaurant_id ||
          req.headers['x-restaurant-id'],
        { allowPublicDefault: false },
      );

      if (!restaurantId || !assertRestaurantAccess(auth, restaurantId, authError, res)) {
        return true;
      }
      if (await rejectIfKitchenAddonDisabled(restaurantId)) return true;

      const name = String(body.name || body.name_ar || body.nameAr || '').trim();
      if (!name) {
        sendJson(res, 400, { error: 'Kitchen name is required' });
        return true;
      }

      const id = `kitchen_${Date.now()}_${Math.random().toString(36).slice(2, 6)}`;
      const kitchen = normalizeKitchen(body, id, restaurantId);
      kitchen.name = name;

      const kitchens = await readKitchens();
      if (kitchen.is_default || kitchen.isDefault) {
        for (const entry of kitchens) {
          if (kitchenRestaurantId(entry) === String(restaurantId)) {
            entry.is_default = false;
            entry.isDefault = false;
          }
        }
      }

      kitchens.push(kitchen);
      await writeKitchens(kitchens);
      const pin = String(body.pin || body.password || body.loginPassword || '').trim();
      await upsertKitchenLoginStaff(kitchen, pin);
      sendJson(res, 201, publicKitchen(kitchen));
    } catch (error) {
      sendJson(res, 400, { error: error.message || 'Invalid payload' });
    }
    return true;
  }

  const kitchenMatch = url.pathname.match(/^\/api\/kitchens\/([^/]+)$/);
  if (!kitchenMatch) {
    return false;
  }

  const kitchenId = decodeURIComponent(kitchenMatch[1]);
  const auth = requireAuth(req, res);
  if (!auth) return true;
  if (rejectCashier(auth, res, 'Cashiers cannot manage kitchens')) return true;

  const kitchens = await readKitchens();
  const index = kitchens.findIndex((kitchen) => String(kitchen.id) === kitchenId);
  if (index === -1) {
    sendJson(res, 404, { error: 'Kitchen not found' });
    return true;
  }

  const existing = kitchens[index];
  const restaurantId = String(
    existing.restaurant_id || existing.restaurantId || DEFAULT_RESTAURANT_ID,
  );
  if (!assertRestaurantAccess(auth, restaurantId, authError, res)) {
    return true;
  }
  if (await rejectIfKitchenAddonDisabled(restaurantId)) return true;

  if (req.method === 'PUT') {
    try {
      const body = JSON.parse((await readBody(req)) || '{}');
      const next = normalizeKitchen({ ...existing, ...body }, kitchenId, restaurantId);
      if (next.is_default || next.isDefault) {
        for (let i = 0; i < kitchens.length; i += 1) {
          if (kitchenRestaurantId(kitchens[i]) === restaurantId) {
            kitchens[i].is_default = kitchens[i].id === kitchenId;
            kitchens[i].isDefault = kitchens[i].id === kitchenId;
          }
        }
      }
      kitchens[index] = next;
      await writeKitchens(kitchens);
      const pin = String(body.pin || body.password || body.loginPassword || '').trim();
      await upsertKitchenLoginStaff(next, pin);
      sendJson(res, 200, publicKitchen(next));
    } catch (error) {
      sendJson(res, 400, { error: error.message || 'Invalid payload' });
    }
    return true;
  }

  if (req.method === 'DELETE') {
    const activeOrders = (await readOrders()).some(
      (order) =>
        String(order.target_kitchen_id || order.targetKitchenId || '') === kitchenId &&
        String(order.restaurant_id || order.restaurantId) === restaurantId &&
        !['delivered', 'cancelled'].includes(String(order.status || '').toLowerCase()),
    );
    if (activeOrders) {
      sendJson(res, 409, {
        error: 'Cannot delete kitchen with active orders',
        code: 'KITCHEN_HAS_ACTIVE_ORDERS',
      });
      return true;
    }
    kitchens.splice(index, 1);
    await writeKitchens(kitchens);
    sendJson(res, 200, { ok: true, id: kitchenId });
    return true;
  }

  return false;
}

module.exports = {
  handleKitchenRoutes,
};
