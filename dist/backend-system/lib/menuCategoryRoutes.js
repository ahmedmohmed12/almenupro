'use strict';

const {
  normalizeMenuCategory,
  publicMenuCategory,
  sortCategories,
  categoryNameOf,
  syncCategoriesFromItemNames,
  applyCategoryReorder,
} = require('./menuCategories');

async function handleMenuCategoryRoutes(req, res, url, deps) {
  const {
    readBody,
    sendJson,
    authError,
    requireAuth,
    assertRestaurantAccess,
    resolveScopedRestaurantId,
    filterByRestaurant,
    readMenuCategories,
    writeMenuCategories,
    readItems,
    renameItemCategory,
  } = deps;

  const pathname = url.pathname;
  if (!pathname.startsWith('/api/menu-categories')) return false;

  if (pathname === '/api/menu-categories' && req.method === 'GET') {
    const auth = requireAuth(req, res);
    if (!auth) return true;
    const restaurantId = await resolveScopedRestaurantId(req, url, auth);
    if (!restaurantId || !assertRestaurantAccess(auth, restaurantId, authError, res)) {
      return true;
    }

    let categories = filterByRestaurant(await readMenuCategories(), restaurantId);
    const sync = url.searchParams.get('sync') !== '0';
    if (sync) {
      const items = filterByRestaurant(await readItems(), restaurantId);
      const names = items.map(
        (item) => item.category_name || item.categoryName || '',
      );
      const all = await readMenuCategories();
      const others = all.filter(
        (entry) =>
          String(entry.restaurant_id || entry.restaurantId) !== String(restaurantId),
      );
      const synced = syncCategoriesFromItemNames(categories, restaurantId, names);
      categories = synced.categories;
      if (synced.created > 0) {
        await writeMenuCategories([...others, ...categories]);
      }
    }

    sendJson(res, 200, sortCategories(categories).map(publicMenuCategory));
    return true;
  }

  if (pathname === '/api/menu-categories' && req.method === 'POST') {
    const auth = requireAuth(req, res);
    if (!auth) return true;
    try {
      const body = JSON.parse((await readBody(req)) || '{}');
      const restaurantId =
        body.restaurantId ||
        body.restaurant_id ||
        (await resolveScopedRestaurantId(req, url, auth));
      if (!restaurantId || !assertRestaurantAccess(auth, restaurantId, authError, res)) {
        return true;
      }
      const name = categoryNameOf(body);
      if (!name) {
        sendJson(res, 400, { error: 'اسم القسم مطلوب' });
        return true;
      }

      const all = await readMenuCategories();
      const scoped = filterByRestaurant(all, restaurantId);
      const duplicate = scoped.find(
        (entry) => categoryNameOf(entry).toLowerCase() === name.toLowerCase(),
      );
      if (duplicate) {
        sendJson(res, 409, { error: 'يوجد قسم بنفس الاسم', category: publicMenuCategory(duplicate) });
        return true;
      }
      const maxOrder = scoped.reduce(
        (max, entry) =>
          Math.max(max, Number(entry.sort_order ?? entry.sortOrder ?? 0) || 0),
        -1,
      );
      const created = normalizeMenuCategory(
        { ...body, sort_order: body.sort_order ?? body.sortOrder ?? maxOrder + 1 },
        restaurantId,
      );
      await writeMenuCategories([...all, created]);
      sendJson(res, 201, publicMenuCategory(created));
    } catch (error) {
      sendJson(res, 400, { error: error.message || 'Invalid category payload' });
    }
    return true;
  }

  if (pathname === '/api/menu-categories/reorder' && req.method === 'PUT') {
    const auth = requireAuth(req, res);
    if (!auth) return true;
    try {
      const body = JSON.parse((await readBody(req)) || '{}');
      const restaurantId =
        body.restaurantId ||
        body.restaurant_id ||
        (await resolveScopedRestaurantId(req, url, auth));
      if (!restaurantId || !assertRestaurantAccess(auth, restaurantId, authError, res)) {
        return true;
      }
      const orderedIds = body.orderedIds || body.ordered_ids || [];
      const all = await readMenuCategories();
      const next = applyCategoryReorder(all, restaurantId, orderedIds);
      await writeMenuCategories(next);
      const scoped = sortCategories(
        next.filter(
          (entry) =>
            String(entry.restaurant_id || entry.restaurantId) === String(restaurantId),
        ),
      );
      sendJson(res, 200, { ok: true, categories: scoped.map(publicMenuCategory) });
    } catch (error) {
      sendJson(res, 400, { error: error.message || 'Reorder failed' });
    }
    return true;
  }

  const match = pathname.match(/^\/api\/menu-categories\/([^/]+)$/);
  if (match && req.method === 'PATCH') {
    const auth = requireAuth(req, res);
    if (!auth) return true;
    try {
      const categoryId = decodeURIComponent(match[1]);
      const body = JSON.parse((await readBody(req)) || '{}');
      const all = await readMenuCategories();
      const index = all.findIndex((entry) => String(entry.id) === String(categoryId));
      if (index === -1) {
        sendJson(res, 404, { error: 'القسم غير موجود' });
        return true;
      }
      const restaurantId =
        all[index].restaurant_id ||
        all[index].restaurantId ||
        body.restaurantId ||
        (await resolveScopedRestaurantId(req, url, auth));
      if (!restaurantId || !assertRestaurantAccess(auth, restaurantId, authError, res)) {
        return true;
      }
      const previousName = categoryNameOf(all[index]);
      const updated = normalizeMenuCategory(body, restaurantId, all[index]);
      all[index] = updated;
      await writeMenuCategories(all);
      const nextName = categoryNameOf(updated);
      if (
        previousName &&
        nextName &&
        previousName !== nextName &&
        typeof renameItemCategory === 'function'
      ) {
        try {
          await renameItemCategory(restaurantId, previousName, nextName);
        } catch (renameError) {
          console.warn(
            '[menu-categories] rename items failed:',
            renameError?.message || renameError,
          );
        }
      }
      sendJson(res, 200, publicMenuCategory(updated));
    } catch (error) {
      sendJson(res, 400, { error: error.message || 'Invalid category payload' });
    }
    return true;
  }

  if (match && req.method === 'DELETE') {
    const auth = requireAuth(req, res);
    if (!auth) return true;
    const categoryId = decodeURIComponent(match[1]);
    const all = await readMenuCategories();
    const index = all.findIndex((entry) => String(entry.id) === String(categoryId));
    if (index === -1) {
      sendJson(res, 404, { error: 'القسم غير موجود' });
      return true;
    }
    const restaurantId = all[index].restaurant_id || all[index].restaurantId;
    if (!restaurantId || !assertRestaurantAccess(auth, restaurantId, authError, res)) {
      return true;
    }
    all.splice(index, 1);
    await writeMenuCategories(all);
    sendJson(res, 200, { ok: true });
    return true;
  }

  return false;
}

module.exports = { handleMenuCategoryRoutes };
