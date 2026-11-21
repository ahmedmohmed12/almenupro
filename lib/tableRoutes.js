'use strict';

const {
  findDuplicateOrder,
  stampOfflineTx,
} = require('./orderIdempotency');
const { scheduleSuperAdminOrderNotify } = require('./orderNotify');
const {
  normalizeKitchenLine,
  stampKitchenSent,
  enforceKitchenItemMutation,
} = require('./kitchenDispatchLock');
const {
  isTableManagementEnabled,
  isKitchenManagementEnabled,
  isDeliveryManagementEnabled,
  normalizeFeatures,
  createTableRecord,
  updateTableRecord,
  createOpenSession,
  ensureActiveSession,
  findRestaurantTableIndex,
  sanitizeTablePublic,
  sanitizeTableCustomer,
  sortTables,
  statusFromActiveSession,
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
  return (Array.isArray(items) ? items : []).map((item) => normalizeKitchenLine(item));
}

const ALLOWED_TIP_AMOUNTS = [0, 0.5, 1, 2, 5];

function cartSubtotal(items) {
  return normalizeOrderItems(items).reduce(
    (sum, item) => sum + (Number(item.lineTotal) || 0),
    0,
  );
}

function normalizeTipAmount(raw) {
  const tip = Number(raw) || 0;
  const matched = ALLOWED_TIP_AMOUNTS.find(
    (value) => Math.abs(value - tip) < 0.0001,
  );
  return matched == null ? 0 : matched;
}

function buildOrder({ body, table, restaurantId, status, paymentMethod }) {
  const cartItems = normalizeOrderItems(
    body.cartItems || body.items || table.activeSession?.cartItems || [],
  );
  const subtotal = cartSubtotal(cartItems);
  const tipAmount =
    status === 'delivered'
      ? normalizeTipAmount(
          body.tipAmount ??
            body.tip_amount ??
            table.activeSession?.tipAmount ??
            0,
        )
      : 0;
  const totalPrice = Number((subtotal + tipAmount).toFixed(3));
  const requestedId = String(body.id || body.offline_tx_id || body.offlineTxId || '').trim();
  return stampOfflineTx({
    id: requestedId || `ord_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`,
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
    tipAmount,
    tip_amount: tipAmount,
    deliveryFee: 0,
    totalPrice,
    orderType: 'dineIn',
    status,
    paymentMethod: paymentMethod || body.paymentMethod || body.payment_method || null,
    paymentStatus: status === 'delivered' ? 'paid' : 'pending_payment',
    payment_status: status === 'delivered' ? 'paid' : 'pending_payment',
    invoiceNumber: body.invoiceNumber || body.invoice_number || Date.now().toString().slice(-8),
    orderSource: 'pos-dine-in',
    createdFromPos: true,
    created_from_pos: true,
    tableId: table.id,
    tableNumber: table.number,
    table_number: table.number,
    tableZone: table.zone,
    tableSessionId: table.activeSession?.id || null,
    shiftId: body.shiftId || body.shift_id || null,
    shift_id: body.shiftId || body.shift_id || null,
    cashierId: body.cashierId || body.cashier_id || null,
    cashier_id: body.cashierId || body.cashier_id || null,
    cashierName: body.cashierName || body.cashier_name || null,
    cashier_name: body.cashierName || body.cashier_name || null,
    createdAt: body.createdAt || new Date().toISOString(),
  }, body);
}

function resolvePublicRestaurant(restaurants, branchKey) {
  const key = String(branchKey || '').trim().toLowerCase();
  if (!key || key === 'branch' || key === 'undefined' || key === 'null') {
    return null;
  }
  return (restaurants || []).find(
    (entry) =>
      String(entry.id || '').toLowerCase() === key ||
      String(entry.slug || '').toLowerCase() === key,
  );
}

function findTableAnywhere(tables, tableKey) {
  const key = String(tableKey || '').trim();
  const keyLower = key.toLowerCase();
  return (tables || []).find(
    (table) =>
      String(table.id) === key ||
      String(table.number) === key ||
      String(table.number || '').toLowerCase() === keyLower,
  );
}

async function persistTableSignal({
  tables,
  restaurant,
  tableKey,
  mutateSession,
  writeTables,
}) {
  const restaurantId = restaurant.id;
  let index = findRestaurantTableIndex(tables, restaurantId, tableKey);
  if (index === -1) {
    index = (tables || []).findIndex(
      (table) => String(table.id) === String(tableKey).trim(),
    );
  }
  if (index === -1) return { error: 'الطاولة غير موجودة', status: 404 };
  const table = tables[index];
  const session = ensureActiveSession(table, {
    staffId: 'qr-guest',
    staffName: 'زبون QR',
  });
  const nextSession = mutateSession(session);
  tables[index] = {
    ...table,
    status: statusFromActiveSession(nextSession),
    activeSession: nextSession,
    updatedAt: new Date().toISOString(),
  };
  await writeTables(tables);
  return { table: tables[index] };
}

async function handlePublicTableRoutes(req, res, url, deps) {
  const { readBody, sendJson, readRestaurants, readTables, writeTables } = deps;
  const match = url.pathname.match(
    /^\/api\/public\/tables\/([^/]+)\/([^/]+)(?:\/([^/]+))?$/,
  );
  if (!match) return false;

  const branchKey = decodeURIComponent(match[1]);
  const tableKey = decodeURIComponent(match[2]);
  const action = match[3] || null;

  const [restaurants, tables] = await Promise.all([readRestaurants(), readTables()]);
  let restaurant = resolvePublicRestaurant(restaurants, branchKey);
  if (!restaurant) {
    const orphan = findTableAnywhere(tables, tableKey);
    if (orphan) {
      const rid = String(orphan.restaurant_id || orphan.restaurantId || '');
      restaurant = restaurants.find((entry) => String(entry.id) === rid);
    }
  }
  if (!restaurant || String(restaurant.status || 'active') !== 'active') {
    sendJson(res, 404, { error: 'المطعم غير موجود' });
    return true;
  }

  if (!isTableManagementEnabled(restaurant)) {
    featureDisabled(res, sendJson);
    return true;
  }

  const restaurantPublic = {
    id: restaurant.id,
    slug: restaurant.slug || restaurant.id,
    name: restaurant.name || restaurant.nameAr || '',
    logoUrl: restaurant.logoUrl || restaurant.logo_url || '',
  };

  if (!action && req.method === 'GET') {
    const index = findRestaurantTableIndex(tables, restaurant.id, tableKey);
    const fallback = index === -1
      ? tables.findIndex((table) => String(table.id) === String(tableKey).trim())
      : index;
    if (fallback === -1) {
      sendJson(res, 404, { error: 'الطاولة غير موجودة' });
      return true;
    }
    sendJson(res, 200, {
      table: sanitizeTableCustomer(tables[fallback]),
      restaurant: restaurantPublic,
    });
    return true;
  }

  if (action === 'call-waiter' && req.method === 'POST') {
    const body = JSON.parse((await readBody(req)) || '{}');
    const note = String(body.note || body.waiterNote || body.notes || '').trim();
    const result = await persistTableSignal({
      tables,
      restaurant,
      tableKey,
      writeTables,
      mutateSession: (session) => ({
        ...session,
        waiterRequested: true,
        waiterNote: note,
        waiterRequestedAt: new Date().toISOString(),
        updatedAt: new Date().toISOString(),
      }),
    });
    if (result.error) {
      sendJson(res, result.status || 400, { error: result.error });
      return true;
    }
    sendJson(res, 200, {
      table: sanitizeTableCustomer(result.table),
      restaurant: restaurantPublic,
    });
    return true;
  }

  if (action === 'request-check' && req.method === 'POST') {
    const body = JSON.parse((await readBody(req)) || '{}');
    const paymentMethod = String(
      body.paymentMethod || body.payment_method || '',
    ).trim().toLowerCase();
    if (!['cash', 'knet'].includes(paymentMethod)) {
      sendJson(res, 400, {
        error: 'اختر طريقة الدفع: كاش أو كي نت',
        code: 'PAYMENT_METHOD_REQUIRED',
      });
      return true;
    }
    const requestedTip = Number(body.tipAmount ?? body.tip_amount ?? 0);
    const tipAmount = ALLOWED_TIP_AMOUNTS.find(
      (value) => Math.abs(value - requestedTip) < 0.0001,
    );
    if (tipAmount == null) {
      sendJson(res, 400, {
        error: 'قيمة الإكرامية غير صالحة',
        code: 'INVALID_TIP_AMOUNT',
      });
      return true;
    }
    let requestedTable = tables[
      findRestaurantTableIndex(tables, restaurant.id, tableKey)
    ];
    if (!requestedTable) {
      requestedTable = findTableAnywhere(tables, tableKey);
    }
    const subtotal = cartSubtotal(requestedTable?.activeSession?.cartItems || []);
    if (subtotal <= 0) {
      sendJson(res, 409, {
        error: 'لا توجد أصناف في حساب الطاولة',
        code: 'EMPTY_TABLE_BILL',
      });
      return true;
    }
    const billTotal = Number((subtotal + tipAmount).toFixed(3));
    const result = await persistTableSignal({
      tables,
      restaurant,
      tableKey,
      writeTables,
      mutateSession: (session) => ({
        ...session,
        checkRequested: true,
        checkRequestedAt: new Date().toISOString(),
        tipAmount,
        paymentMethod,
        billTotal,
        updatedAt: new Date().toISOString(),
      }),
    });
    if (result.error) {
      sendJson(res, result.status || 400, { error: result.error });
      return true;
    }
    sendJson(res, 200, {
      table: sanitizeTableCustomer(result.table),
      restaurant: restaurantPublic,
    });
    return true;
  }

  return false;
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
    readSettings,
    readStaffUsers,
    appendAuditEvents,
    isRestaurantAdmin,
  } = deps;

  const pathname = url.pathname;
  if (pathname.startsWith('/api/public/tables')) {
    return handlePublicTableRoutes(req, res, url, {
      readBody,
      sendJson,
      readRestaurants,
      readTables,
      writeTables,
    });
  }
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

  const isMutating = req.method !== 'GET' && req.method !== 'HEAD';
  if (isMutating && !isTableManagementEnabled(restaurant)) {
    featureDisabled(res, sendJson);
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
        status: statusFromActiveSession(session),
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
      if (
        table.activeSession.checkRequested === true &&
        (body.cartItems != null || body.items != null)
      ) {
        sendJson(res, 409, {
          error: 'تم طلب الحساب ولا يمكن تعديل أصناف الطاولة',
          code: 'TABLE_AWAITING_CHECK',
        });
        return true;
      }
      const previousCart = table.activeSession.cartItems || [];
      const incomingCartRaw =
        body.cartItems != null || body.items != null
          ? body.cartItems || body.items || []
          : previousCart;
      if (body.cartItems != null || body.items != null) {
        const lock = await enforceKitchenItemMutation({
          previousItems: previousCart,
          nextItems: incomingCartRaw,
          body,
          auth,
          restaurantId,
          deps: {
            readSettings,
            readStaffUsers,
            readRestaurants,
            filterByRestaurant,
          },
          context: {
            entityType: 'table_session',
            entityId: tableId,
            orderType: 'dineIn',
          },
        });
        if (!lock.ok) {
          sendJson(res, lock.status || 403, {
            error: lock.error,
            code: lock.code,
            violations: lock.violations,
          });
          return true;
        }
        if (lock.auditEvents?.length && typeof appendAuditEvents === 'function') {
          await appendAuditEvents(lock.auditEvents);
        }
      }
      const nextSession = {
        ...table.activeSession,
        cartItems: normalizeOrderItems(incomingCartRaw),
        notes: body.notes != null ? String(body.notes).trim() : table.activeSession.notes || '',
        customerName:
          body.customerName != null || body.customer_name != null
            ? String(body.customerName ?? body.customer_name ?? '').trim()
            : table.activeSession.customerName || '',
        phone: body.phone != null ? String(body.phone).trim() : table.activeSession.phone || '',
        checkRequested:
          body.checkRequested === true ||
          body.check_requested === true ||
          (body.checkRequested !== false &&
            body.check_requested !== false &&
            table.activeSession.checkRequested === true),
        checkRequestedAt:
          body.checkRequested === true || body.check_requested === true
            ? new Date().toISOString()
            : table.activeSession.checkRequestedAt || null,
        waiterRequested:
          body.waiterRequested === true ||
          body.waiter_requested === true ||
          (body.waiterRequested !== false &&
            body.waiter_requested !== false &&
            table.activeSession.waiterRequested === true),
        waiterNote:
          body.waiterNote != null || body.waiter_note != null
            ? String(body.waiterNote ?? body.waiter_note ?? '').trim()
            : table.activeSession.waiterNote || '',
        waiterRequestedAt:
          body.waiterRequested === true || body.waiter_requested === true
            ? new Date().toISOString()
            : table.activeSession.waiterRequestedAt || null,
        updatedAt: new Date().toISOString(),
      };
      if (body.checkRequested === false || body.check_requested === false) {
        nextSession.checkRequested = false;
        nextSession.checkRequestedAt = null;
      }
      if (body.waiterRequested === false || body.waiter_requested === false) {
        nextSession.waiterRequested = false;
        nextSession.waiterNote = '';
        nextSession.waiterRequestedAt = null;
      }
      let nextStatus = statusFromActiveSession(nextSession);
      if (body.status != null && nextSession.checkRequested) {
        nextStatus = 'awaiting_check';
      }

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
      const [tables, orders] = await Promise.all([readTables(), readOrders()]);
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
      if (table.activeSession.checkRequested === true) {
        sendJson(res, 409, {
          error: 'تم طلب الحساب ولا يمكن إرسال أصناف جديدة للمطبخ',
          code: 'TABLE_AWAITING_CHECK',
        });
        return true;
      }
      const cartItemsRaw =
        body.cartItems || body.items || table.activeSession.cartItems || [];
      if (!Array.isArray(cartItemsRaw) || cartItemsRaw.length === 0) {
        sendJson(res, 400, { error: 'السلة فارغة' });
        return true;
      }
      const sentAt = new Date().toISOString();
      const cartItems = stampKitchenSent(normalizeOrderItems(cartItemsRaw), {
        sentAt,
        onlyUnsent: true,
      });
      const existing = findDuplicateOrder(orders, body);
      const order = existing || buildOrder({
        body: { ...body, cartItems },
        table,
        restaurantId,
        status: 'preparing',
      });
      if (existing) {
        order.items = cartItems;
        const orderIndex = orders.findIndex((entry) => String(entry.id) === String(order.id));
        if (orderIndex >= 0) {
          orders[orderIndex] = { ...orders[orderIndex], items: cartItems, updatedAt: sentAt };
        }
      }
      if (!existing) {
        orders.unshift(order);
      }

      tables[index] = {
        ...table,
        status: 'occupied',
        activeSession: {
          ...table.activeSession,
          cartItems,
          kitchenOrderIds: [...(table.activeSession.kitchenOrderIds || []), order.id],
          currentOrderNumber: String(
            order.invoiceNumber || order.invoice_number || order.id,
          ),
          updatedAt: new Date().toISOString(),
        },
        updatedAt: new Date().toISOString(),
      };
      await Promise.all([writeOrders(orders), writeTables(tables)]);
      if (!existing) {
        await scheduleSuperAdminOrderNotify(order, { readRestaurants });
      }
      sendJson(res, 200, { order, table: sanitizeTablePublic(tables[index]) });
    } catch (error) {
      sendJson(res, 400, { error: error.message || 'بيانات غير صالحة' });
    }
    return true;
  }

  if (action === 'checkout' && req.method === 'POST') {
    try {
      const body = JSON.parse((await readBody(req)) || '{}');
      const [tables, orders] = await Promise.all([readTables(), readOrders()]);
      const index = findTableIndex(tables, restaurantId, tableId);
      if (index === -1) {
        sendJson(res, 404, { error: 'الطاولة غير موجودة' });
        return true;
      }
      const table = tables[index];
      const existing = findDuplicateOrder(orders, body);
      if (!table.activeSession && !existing) {
        sendJson(res, 409, {
          error: 'لا توجد جلسة لإغلاق الحساب',
          code: 'NO_ACTIVE_SESSION',
        });
        return true;
      }
      const cartItems = body.cartItems || body.items || table.activeSession?.cartItems || [];
      if (!existing && (!Array.isArray(cartItems) || cartItems.length === 0)) {
        sendJson(res, 400, { error: 'السلة فارغة' });
        return true;
      }
      const order = existing || buildOrder({
        body: { ...body, cartItems },
        table,
        restaurantId,
        status: 'delivered',
        paymentMethod: String(body.paymentMethod || body.payment_method || 'كاش').trim(),
      });
      if (!existing) {
        orders.unshift(order);
      }

      tables[index] = {
        ...table,
        status: 'available',
        activeSession: null,
        updatedAt: new Date().toISOString(),
      };
      await Promise.all([
        existing ? Promise.resolve() : writeOrders(orders),
        writeTables(tables),
      ]);
      if (!existing) {
        await scheduleSuperAdminOrderNotify(order, { readRestaurants });
      }
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

module.exports = {
  handleTableRoutes,
  isTableManagementEnabled,
  isKitchenManagementEnabled,
  isDeliveryManagementEnabled,
  normalizeFeatures,
};
