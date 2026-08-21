'use strict';

const {
  isTableManagementEnabled,
  normalizeFeatures,
  createTableRecord,
  updateTableRecord,
  createOpenSession,
  sanitizeTablePublic,
  sortTables,
  normalizeTableStatus,
} = require('./diningTables');

function featureDisabled(res, sendJson) {
  sendJson(res, 403, {
    error: 'إدارة الطاولات غير مفعّلة لهذا المطعم',
    code: 'TABLE_MANAGEMENT_DISABLED',
  });
}

function findTableIndex(tables, restaurantId, tableId) {
  return tables.findIndex(
    (table) =>
      String(table.id) === String(tableId) &&
      String(table.restaurant_id || table.restaurantId) === String(restaurantId),
  );
}

function normalizeOrderItems(items) {
  return (Array.isArray(items) ? items : []).map((item) => {
    const quantity = Math.max(1, Number(item.quantity) || 1);
    const unitPrice = Number(item.unitPrice ?? item.unit_price ?? item.price) || 0;
    const name = String(item.name || item.menuItem?.name || 'صنف').trim() || 'صنف';
    return {
      ...item,
      menuItemId: String(item.menuItemId ?? item.menu_item_id ?? item.menuItem?.id ?? ''),
      name,
      unitPrice,
      quantity,
      selectedOptions: Array.isArray(item.selectedOptions) ? item.selectedOptions : [],
      lineTotal: Number(item.lineTotal ?? item.line_total ?? unitPrice * quantity) || unitPrice * quantity,
    };
  });
}

function cartSubtotal(items) {
  return normalizeOrderItems(items).reduce(
    (sum, item) => sum + (Number(item.lineTotal) || 0),
    0,
  );
}

function buildOrder({ body, table, restaurantId, status, paymentMethod }) {
  const cartItems = normalizeOrderItems(
    body.cartItems || body.items || table.activeSession?.cartItems || [],
  );
  const subtotal = cartSubtotal(cartItems);
  return {
    id: `ord_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`,
    restaurant_id: restaurantId,
    restaurantId,
    customerName:
      body.customerName ||
      table.activeSession?.customerName ||
      `طاولة ${table.number}`,
    phone: body.phone || table.activeSession?.phone || '00000000',
    address: `طاولة ${table.number} — ${table.zone || ''}`.trim(),
    items: cartItems,
    subtotal,
    deliveryFee: 0,
    totalPrice: subtotal,
    orderType: 'dineIn',
    status,
    paymentMethod: paymentMethod || null,
    invoiceNumber: body.invoiceNumber || body.invoice_number || Date.now().toString().slice(-8),
    orderSource: 'pos-dine-in',
    tableId: table.id,
    tableNumber: table.number,
    tableZone: table.zone,
    tableSessionId: table.activeSession?.id || null,
    createdAt: new Date().toISOString(),
  };
}

async function handleTableRoutes(req, res, url, deps) {
  const {
    readBody,
    sendJson,
    authError,
    requireAuth,
    isCashier,
    assertRestaurantAccess,
    resolveScopedRestaurantId,
    filterByRestaurant,
    readRestaurants,
    readTables,
    writeTables,
    readOrders,
    writeOrders,
  } = deps;

  const pathname = url.pathname;
  if (!pathname.startsWith('/api/tables')) return false;

  const auth = requireAuth(req, res);
  if (!auth) return true;

  const restaurantId = await resolveScopedRestaurantId(req, url, auth);
  if (!restaurantId || !assertRestaurantAccess(auth, restaurantId, authError, res)) {
    return true;
  }

  const restaurants = await readRestaurants();
  const restaurant = restaurants.find((entry) => String(entry.id) === String(restaurantId));
  if (!restaurant) {
    sendJson(res, 404, { error: 'المطعم غير موجود' });
    return true;
  }

  const isSessionPath = /\/(open-session|session|send-kitchen|checkout|release)$/.test(
    pathname,
  );
  if (isSessionPath && !isTableManagementEnabled(restaurant)) {
    featureDisabled(res, sendJson);
    return true;
  }

  if (pathname === '/api/tables' && req.method === 'GET') {
    const tables = sortTables(filterByRestaurant(await readTables(), restaurantId)).map(
      sanitizeTablePublic,
    );
    sendJson(res, 200, { tables, features: normalizeFeatures(restaurant.features) });
    return true;
  }

  if (pathname === '/api/tables' && req.method === 'POST') {
    if (isCashier(auth)) {
      authError(res, 403, 'الكاشير لا يستطيع إضافة طاولات');
      return true;
    }
    try {
      const body = JSON.parse((await readBody(req)) || '{}');
      const tables = await readTables();
      const scoped = filterByRestaurant(tables, restaurantId);
      const number = String(body.number || body.tableNumber || '').trim();
      if (scoped.some((table) => String(table.number) === number)) {
        sendJson(res, 409, { error: 'رقم الطاولة مستخدم مسبقاً' });
        return true;
      }
      const record = createTableRecord(body, restaurantId);
      tables.push(record);
      await writeTables(tables);
      sendJson(res, 201, sanitizeTablePublic(record));
    } catch (error) {
      sendJson(res, 400, { error: error.message || 'بيانات غير صالحة' });
    }
    return true;
  }

  const tableMatch = pathname.match(/^\/api\/tables\/([^/]+)(?:\/([^/]+))?$/);
  if (!tableMatch) return false;

  const tableId = decodeURIComponent(tableMatch[1]);
  const action = tableMatch[2] || null;

  if (!action && (req.method === 'PATCH' || req.method === 'PUT')) {
    if (isCashier(auth)) {
      authError(res, 403, 'الكاشير لا يستطيع تعديل الطاولات');
      return true;
    }
    try {
      const body = JSON.parse((await readBody(req)) || '{}');
      const tables = await readTables();
      const index = findTableIndex(tables, restaurantId, tableId);
      if (index === -1) {
        sendJson(res, 404, { error: 'الطاولة غير موجودة' });
        return true;
      }
      const nextNumber = String(
        body.number ?? body.tableNumber ?? tables[index].number ?? '',
      ).trim();
      const duplicate = tables.some(
        (table, idx) =>
          idx !== index &&
          String(table.restaurant_id || table.restaurantId) === String(restaurantId) &&
          String(table.number) === nextNumber,
      );
      if (duplicate) {
        sendJson(res, 409, { error: 'رقم الطاولة مستخدم مسبقاً' });
        return true;
      }
      tables[index] = updateTableRecord(tables[index], body);
      await writeTables(tables);
      sendJson(res, 200, sanitizeTablePublic(tables[index]));
    } catch (error) {
      sendJson(res, 400, { error: error.message || 'بيانات غير صالحة' });
    }
    return true;
  }

  if (!action && req.method === 'DELETE') {
    if (isCashier(auth)) {
      authError(res, 403, 'الكاشير لا يستطيع حذف الطاولات');
      return true;
    }
    const tables = await readTables();
    const index = findTableIndex(tables, restaurantId, tableId);
    if (index === -1) {
      sendJson(res, 404, { error: 'الطاولة غير موجودة' });
      return true;
    }
    if (tables[index].activeSession) {
      sendJson(res, 409, {
        error: 'لا يمكن حذف طاولة عليها جلسة مفتوحة',
        code: 'TABLE_HAS_ACTIVE_SESSION',
      });
      return true;
    }
    tables.splice(index, 1);
    await writeTables(tables);
    sendJson(res, 200, { ok: true, id: tableId });
    return true;
  }

  if (action === 'open-session' && req.method === 'POST') {
    try {
      const body = JSON.parse((await readBody(req)) || '{}');
      const tables = await readTables();
      const index = findTableIndex(tables, restaurantId, tableId);
      if (index === -1) {
        sendJson(res, 404, { error: 'الطاولة غير موجودة' });
        return true;
      }
      const table = tables[index];
      if (table.activeSession) {
        sendJson(res, 200, { table: sanitizeTablePublic(table), created: false });
        return true;
      }
      const session = createOpenSession({
        staffId: body.staffId || auth.staffId || auth.sub || auth.id,
        staffName: body.staffName || auth.staffName || auth.name || auth.username,
        cartItems: body.cartItems || body.items || [],
        notes: body.notes || '',
      });
      tables[index] = {
        ...table,
        status: 'occupied',
        activeSession: session,
        updatedAt: new Date().toISOString(),
      };
      await writeTables(tables);
      sendJson(res, 200, { table: sanitizeTablePublic(tables[index]), created: true });
    } catch (error) {
      sendJson(res, 400, { error: error.message || 'بيانات غير صالحة' });
    }
    return true;
  }

  if (action === 'session' && (req.method === 'PUT' || req.method === 'PATCH')) {
    try {
      const body = JSON.parse((await readBody(req)) || '{}');
      const tables = await readTables();
      const index = findTableIndex(tables, restaurantId, tableId);
      if (index === -1) {
        sendJson(res, 404, { error: 'الطاولة غير موجودة' });
        return true;
      }
      const table = tables[index];
      if (!table.activeSession) {
        sendJson(res, 409, {
          error: 'لا توجد جلسة مفتوحة على هذه الطاولة',
          code: 'NO_ACTIVE_SESSION',
        });
        return true;
      }
      const nextSession = {
        ...table.activeSession,
        cartItems:
          body.cartItems != null || body.items != null
            ? body.cartItems || body.items || []
            : table.activeSession.cartItems || [],
        notes: body.notes != null ? String(body.notes).trim() : table.activeSession.notes || '',
        customerName:
          body.customerName != null || body.customer_name != null
            ? String(body.customerName ?? body.customer_name ?? '').trim()
            : table.activeSession.customerName || '',
        phone: body.phone != null ? String(body.phone).trim() : table.activeSession.phone || '',
        updatedAt: new Date().toISOString(),
      };
      let nextStatus = table.status;
      if (body.status != null) nextStatus = normalizeTableStatus(body.status);
      else if ((nextSession.cartItems || []).length > 0) nextStatus = 'occupied';

      tables[index] = {
        ...table,
        status: nextStatus,
        activeSession: nextSession,
        updatedAt: new Date().toISOString(),
      };
      await writeTables(tables);
      sendJson(res, 200, sanitizeTablePublic(tables[index]));
    } catch (error) {
      sendJson(res, 400, { error: error.message || 'بيانات غير صالحة' });
    }
    return true;
  }

  if (action === 'send-kitchen' && req.method === 'POST') {
    try {
      const body = JSON.parse((await readBody(req)) || '{}');
      const tables = await readTables();
      const index = findTableIndex(tables, restaurantId, tableId);
      if (index === -1) {
        sendJson(res, 404, { error: 'الطاولة غير موجودة' });
        return true;
      }
      const table = tables[index];
      if (!table.activeSession) {
        sendJson(res, 409, {
          error: 'افتح جلسة الطاولة قبل إرسال الطلب للمطبخ',
          code: 'NO_ACTIVE_SESSION',
        });
        return true;
      }
      const cartItems = body.cartItems || body.items || table.activeSession.cartItems || [];
      if (!Array.isArray(cartItems) || cartItems.length === 0) {
        sendJson(res, 400, { error: 'السلة فارغة' });
        return true;
      }
      const order = buildOrder({
        body: { ...body, cartItems },
        table,
        restaurantId,
        status: 'preparing',
      });
      const orders = await readOrders();
      orders.unshift(order);
      await writeOrders(orders);

      tables[index] = {
        ...table,
        status: 'occupied',
        activeSession: {
          ...table.activeSession,
          cartItems,
          kitchenOrderIds: [...(table.activeSession.kitchenOrderIds || []), order.id],
          updatedAt: new Date().toISOString(),
        },
        updatedAt: new Date().toISOString(),
      };
      await writeTables(tables);
      sendJson(res, 200, { order, table: sanitizeTablePublic(tables[index]) });
    } catch (error) {
      sendJson(res, 400, { error: error.message || 'بيانات غير صالحة' });
    }
    return true;
  }

  if (action === 'checkout' && req.method === 'POST') {
    try {
      const body = JSON.parse((await readBody(req)) || '{}');
      const tables = await readTables();
      const index = findTableIndex(tables, restaurantId, tableId);
      if (index === -1) {
        sendJson(res, 404, { error: 'الطاولة غير موجودة' });
        return true;
      }
      const table = tables[index];
      if (!table.activeSession) {
        sendJson(res, 409, {
          error: 'لا توجد جلسة لإغلاق الحساب',
          code: 'NO_ACTIVE_SESSION',
        });
        return true;
      }
      const cartItems = body.cartItems || body.items || table.activeSession.cartItems || [];
      if (!Array.isArray(cartItems) || cartItems.length === 0) {
        sendJson(res, 400, { error: 'السلة فارغة' });
        return true;
      }
      const order = buildOrder({
        body: { ...body, cartItems },
        table,
        restaurantId,
        status: 'delivered',
        paymentMethod: String(body.paymentMethod || body.payment_method || 'كاش').trim(),
      });
      const orders = await readOrders();
      orders.unshift(order);
      await writeOrders(orders);

      tables[index] = {
        ...table,
        status: 'available',
        activeSession: null,
        updatedAt: new Date().toISOString(),
      };
      await writeTables(tables);
      sendJson(res, 200, {
        order,
        table: sanitizeTablePublic(tables[index]),
        released: true,
      });
    } catch (error) {
      sendJson(res, 400, { error: error.message || 'بيانات غير صالحة' });
    }
    return true;
  }

  if (action === 'release' && req.method === 'POST') {
    const tables = await readTables();
    const index = findTableIndex(tables, restaurantId, tableId);
    if (index === -1) {
      sendJson(res, 404, { error: 'الطاولة غير موجودة' });
      return true;
    }
    const session = tables[index].activeSession;
    const hasItems =
      session && Array.isArray(session.cartItems) && session.cartItems.length > 0;
    if (isCashier(auth) && hasItems) {
      authError(res, 403, 'يجب إغلاق الحساب قبل تفريغ طاولة عليها أصناف');
      return true;
    }
    tables[index] = {
      ...tables[index],
      status: 'available',
      activeSession: null,
      updatedAt: new Date().toISOString(),
    };
    await writeTables(tables);
    sendJson(res, 200, { table: sanitizeTablePublic(tables[index]), released: true });
    return true;
  }

  return false;
}

module.exports = { handleTableRoutes, isTableManagementEnabled, normalizeFeatures };
