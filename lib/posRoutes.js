const {
  normalizePosRoles,
  findRoleById,
  PERMISSION_KEYS,
} = require('./posPermissions');
const {
  sanitizeStaffPublic,
  createStaffRecord,
  updateStaffRecord,
  findStaffByPin,
  resolveStaffPermissions,
  verifyManagerOverride,
} = require('./staffUsers');
const {
  normalizeShiftSession,
  findOpenShift,
  createOpenShift,
  closeShift,
} = require('./shiftSessions');
const { buildAuditEvent } = require('./auditLog');

function parsePosSettings(settings = {}) {
  return {
    posRoles: normalizePosRoles(settings.posRoles || settings.pos_roles),
    posAutoLockMinutes:
      Number(settings.posAutoLockMinutes ?? settings.pos_auto_lock_minutes ?? 5) ||
      5,
  };
}

async function appendAudit(deps, event) {
  await deps.appendAuditEvents([buildAuditEvent(event)]);
}

async function handlePosRoutes(req, res, url, deps) {
  const {
    readBody,
    sendJson,
    authError,
    parseAuthHeader,
    requireAuth,
    isSuperAdmin,
    assertRestaurantAccess,
    resolveScopedRestaurantId,
    filterByRestaurant,
    readSettings,
    readRestaurants,
    readStaffUsers,
    writeStaffUsers,
    readShiftSessions,
    writeShiftSessions,
    readOrders,
    writeOrders,
    appendAuditEvents,
  } = deps;

  if (url.pathname === '/api/pos/staff/login' && req.method === 'POST') {
    try {
      const body = JSON.parse((await readBody(req)) || '{}');
      const auth = requireAuth(req, res);
      if (!auth) return true;

      const restaurantId = await resolveScopedRestaurantId(req, url, auth);
      if (!restaurantId || !assertRestaurantAccess(auth, restaurantId, authError, res)) {
        return true;
      }

      const pin = String(body.pin || body.pinCode || '').trim();
      const staffUsers = filterByRestaurant(await readStaffUsers(), restaurantId);
      const settings = await readSettings(restaurantId);
      const { posRoles } = parsePosSettings(settings);
      const staff = findStaffByPin(staffUsers, restaurantId, pin, posRoles);
      if (!staff) {
        sendJson(res, 401, { error: 'Invalid PIN' });
        return true;
      }

      sendJson(res, 200, {
        staff: sanitizeStaffPublic(staff),
        permissions: resolveStaffPermissions(staff, posRoles),
        role: findRoleById(posRoles, staff.roleId || staff.role_id),
      });
    } catch (error) {
      sendJson(res, 400, { error: error.message || 'Invalid payload' });
    }
    return true;
  }

  if (url.pathname === '/api/pos/override' && req.method === 'POST') {
    try {
      const body = JSON.parse((await readBody(req)) || '{}');
      const auth = requireAuth(req, res);
      if (!auth) return true;

      const restaurantId = await resolveScopedRestaurantId(req, url, auth);
      if (!restaurantId || !assertRestaurantAccess(auth, restaurantId, authError, res)) {
        return true;
      }

      const pin = String(body.pin || body.pinCode || '').trim();
      const action = String(body.action || 'manager_override').trim();
      const staffUsers = filterByRestaurant(await readStaffUsers(), restaurantId);
      const settings = await readSettings(restaurantId);
      const { posRoles } = parsePosSettings(settings);
      const restaurants = await readRestaurants();
      const restaurantRecord = restaurants.find((entry) => entry.id === restaurantId);
      const result = verifyManagerOverride({
        staffUsers,
        restaurantId,
        pin,
        roles: posRoles,
        restaurantRecord,
      });

      if (!result.authorized) {
        sendJson(res, 403, { error: 'Manager authorization failed' });
        return true;
      }

      await appendAudit(deps, {
        restaurantId,
        action,
        entityType: 'pos_override',
        entityId: body.entityId || body.entity_id || '',
        performedById: String(body.performedById || body.performed_by_id || auth.restaurantId || 'admin'),
        performedByName: String(body.performedByName || body.performed_by_name || 'Admin'),
        authorizedById: result.staffId,
        authorizedByName: result.staffName,
        metadata: {
          source: result.source,
          roleId: result.roleId,
        },
      });

      sendJson(res, 200, {
        authorized: true,
        authorizedById: result.staffId,
        authorizedByName: result.staffName,
        expiresAt: new Date(Date.now() + 5 * 60 * 1000).toISOString(),
      });
    } catch (error) {
      sendJson(res, 400, { error: error.message || 'Invalid payload' });
    }
    return true;
  }

  if (url.pathname === '/api/pos/shifts/current' && req.method === 'GET') {
    const auth = requireAuth(req, res);
    if (!auth) return true;

    const restaurantId = await resolveScopedRestaurantId(req, url, auth);
    if (!restaurantId || !assertRestaurantAccess(auth, restaurantId, authError, res)) {
      return true;
    }

    const cashierId = url.searchParams.get('cashierId') || url.searchParams.get('cashier_id');
    const shifts = filterByRestaurant(await readShiftSessions(), restaurantId);
    const openShift = findOpenShift(shifts, restaurantId, cashierId || null);
    sendJson(res, 200, { shift: openShift || null });
    return true;
  }

  if (url.pathname === '/api/pos/shifts' && req.method === 'GET') {
    const auth = requireAuth(req, res);
    if (!auth) return true;

    const restaurantId = await resolveScopedRestaurantId(req, url, auth);
    if (!restaurantId || !assertRestaurantAccess(auth, restaurantId, authError, res)) {
      return true;
    }

    const cashierId = url.searchParams.get('cashierId') || url.searchParams.get('cashier_id');
    const from = url.searchParams.get('from');
    const to = url.searchParams.get('to');
    let shifts = filterByRestaurant(await readShiftSessions(), restaurantId);
    if (cashierId) {
      shifts = shifts.filter(
        (shift) => String(shift.cashierId || shift.cashier_id) === String(cashierId),
      );
    }
    if (from) {
      const fromMs = Date.parse(from);
      shifts = shifts.filter((shift) => Date.parse(shift.openedAt || 0) >= fromMs);
    }
    if (to) {
      const toMs = Date.parse(to);
      shifts = shifts.filter((shift) => Date.parse(shift.openedAt || 0) <= toMs);
    }
    shifts.sort((a, b) => Date.parse(b.openedAt || 0) - Date.parse(a.openedAt || 0));
    sendJson(res, 200, shifts);
    return true;
  }

  if (url.pathname === '/api/pos/shifts/open' && req.method === 'POST') {
    try {
      const body = JSON.parse((await readBody(req)) || '{}');
      const auth = requireAuth(req, res);
      if (!auth) return true;

      const restaurantId = await resolveScopedRestaurantId(req, url, auth);
      if (!restaurantId || !assertRestaurantAccess(auth, restaurantId, authError, res)) {
        return true;
      }

      const shifts = filterByRestaurant(await readShiftSessions(), restaurantId);
      const existing = findOpenShift(
        shifts,
        restaurantId,
        body.cashierId || body.cashier_id || null,
      );
      if (existing) {
        sendJson(res, 409, { error: 'Shift already open for this cashier', shift: existing });
        return true;
      }

      const shift = createOpenShift(body, restaurantId);
      shifts.unshift(shift);
      await writeShiftSessions(shifts);
      await appendAudit(deps, {
        restaurantId,
        action: 'shift_open',
        entityType: 'shift',
        entityId: shift.id,
        performedById: shift.cashierId,
        performedByName: shift.cashierName,
        metadata: { openingFloat: shift.openingFloat },
      });
      sendJson(res, 201, shift);
    } catch (error) {
      sendJson(res, 400, { error: error.message || 'Invalid payload' });
    }
    return true;
  }

  const closeShiftMatch = url.pathname.match(/^\/api\/pos\/shifts\/([^/]+)\/close$/);
  if (closeShiftMatch && req.method === 'POST') {
    try {
      const shiftId = decodeURIComponent(closeShiftMatch[1]);
      const body = JSON.parse((await readBody(req)) || '{}');
      const auth = requireAuth(req, res);
      if (!auth) return true;

      const restaurantId = await resolveScopedRestaurantId(req, url, auth);
      if (!restaurantId || !assertRestaurantAccess(auth, restaurantId, authError, res)) {
        return true;
      }

      const shifts = await readShiftSessions();
      const index = shifts.findIndex((shift) => String(shift.id) === shiftId);
      if (index === -1) {
        sendJson(res, 404, { error: 'Shift not found' });
        return true;
      }
      const current = shifts[index];
      if (String(current.restaurantId || current.restaurant_id) !== String(restaurantId)) {
        authError(res, 403, 'Access denied for this shift');
        return true;
      }
      if (String(current.status || '').toLowerCase() === 'closed') {
        sendJson(res, 409, { error: 'Shift already closed', shift: current });
        return true;
      }

      const orders = filterByRestaurant(await readOrders(), restaurantId);
      const closed = closeShift(current, body, orders);
      shifts[index] = closed;
      await writeShiftSessions(shifts);
      await appendAudit(deps, {
        restaurantId,
        action: 'shift_close',
        entityType: 'shift',
        entityId: closed.id,
        performedById: closed.closedById,
        performedByName: closed.closedByName,
        metadata: closed.summary,
      });
      sendJson(res, 200, closed);
    } catch (error) {
      sendJson(res, 400, { error: error.message || 'Invalid payload' });
    }
    return true;
  }

  if (url.pathname === '/api/pos/staff' && req.method === 'GET') {
    const auth = requireAuth(req, res);
    if (!auth) return true;

    const restaurantId = await resolveScopedRestaurantId(req, url, auth);
    if (!restaurantId || !assertRestaurantAccess(auth, restaurantId, authError, res)) {
      return true;
    }

    const staffUsers = filterByRestaurant(await readStaffUsers(), restaurantId).map(
      sanitizeStaffPublic,
    );
    sendJson(res, 200, staffUsers);
    return true;
  }

  if (url.pathname === '/api/pos/staff' && req.method === 'POST') {
    try {
      const body = JSON.parse((await readBody(req)) || '{}');
      const auth = requireAuth(req, res);
      if (!auth) return true;

      const restaurantId = await resolveScopedRestaurantId(req, url, auth);
      if (!restaurantId || !assertRestaurantAccess(auth, restaurantId, authError, res)) {
        return true;
      }

      const staffUsers = await readStaffUsers();
      const record = createStaffRecord(body, restaurantId);
      if (
        staffUsers.some(
          (entry) =>
            String(entry.restaurantId || entry.restaurant_id) === String(restaurantId) &&
            String(entry.name).toLowerCase() === String(record.name).toLowerCase(),
        )
      ) {
        sendJson(res, 409, { error: 'Staff name already exists' });
        return true;
      }
      staffUsers.unshift(record);
      await writeStaffUsers(staffUsers);
      sendJson(res, 201, sanitizeStaffPublic(record));
    } catch (error) {
      sendJson(res, 400, { error: error.message || 'Invalid payload' });
    }
    return true;
  }

  const staffMatch = url.pathname.match(/^\/api\/pos\/staff\/([^/]+)$/);
  if (staffMatch && req.method === 'PATCH') {
    try {
      const staffId = decodeURIComponent(staffMatch[1]);
      const body = JSON.parse((await readBody(req)) || '{}');
      const auth = requireAuth(req, res);
      if (!auth) return true;

      const restaurantId = await resolveScopedRestaurantId(req, url, auth);
      if (!restaurantId || !assertRestaurantAccess(auth, restaurantId, authError, res)) {
        return true;
      }

      const staffUsers = await readStaffUsers();
      const index = staffUsers.findIndex((entry) => String(entry.id) === staffId);
      if (index === -1) {
        sendJson(res, 404, { error: 'Staff user not found' });
        return true;
      }
      if (
        String(staffUsers[index].restaurantId || staffUsers[index].restaurant_id) !==
        String(restaurantId)
      ) {
        authError(res, 403, 'Access denied');
        return true;
      }

      staffUsers[index] = updateStaffRecord(staffUsers[index], body);
      await writeStaffUsers(staffUsers);
      sendJson(res, 200, sanitizeStaffPublic(staffUsers[index]));
    } catch (error) {
      sendJson(res, 400, { error: error.message || 'Invalid payload' });
    }
    return true;
  }

  const voidOrderMatch = url.pathname.match(/^\/api\/orders\/([^/]+)\/void$/);
  if (voidOrderMatch && req.method === 'PATCH') {
    try {
      const orderId = decodeURIComponent(voidOrderMatch[1]);
      const body = JSON.parse((await readBody(req)) || '{}');
      const auth = requireAuth(req, res);
      if (!auth) return true;

      if (isSuperAdmin(auth)) {
        authError(res, 403, 'Orders are managed by restaurant admins only');
        return true;
      }

      const orders = await readOrders();
      const index = orders.findIndex((order) => String(order.id) === orderId);
      if (index === -1) {
        sendJson(res, 404, { error: 'Order not found' });
        return true;
      }

      const restaurantId =
        orders[index].restaurant_id || orders[index].restaurantId || deps.DEFAULT_RESTAURANT_ID;
      if (!assertRestaurantAccess(auth, restaurantId, authError, res)) {
        return true;
      }

      if (String(orders[index].status || '').toLowerCase() === 'cancelled') {
        sendJson(res, 409, { error: 'Order already voided' });
        return true;
      }

      const settings = await readSettings(restaurantId);
      const { posRoles } = parsePosSettings(settings);
      const staffUsers = filterByRestaurant(await readStaffUsers(), restaurantId);
      const performedById = String(body.performedById || body.performed_by_id || '').trim();
      const performedByName = String(body.performedByName || body.performed_by_name || '').trim();
      const performer = staffUsers.find((entry) => String(entry.id) === performedById);
      const performerAllowed =
        performer &&
        resolveStaffPermissions(performer, posRoles)[PERMISSION_KEYS.VOID_ORDERS] === true;

      let authorizedById = body.authorizedById || body.authorized_by_id || null;
      let authorizedByName = body.authorizedByName || body.authorized_by_name || null;

      if (!performerAllowed) {
        const pin = String(body.managerPin || body.manager_pin || body.pin || '').trim();
        const restaurants = await readRestaurants();
        const restaurantRecord = restaurants.find((entry) => entry.id === restaurantId);
        const override = verifyManagerOverride({
          staffUsers,
          restaurantId,
          pin,
          roles: posRoles,
          restaurantRecord,
        });
        if (!override.authorized) {
          sendJson(res, 403, { error: 'Manager override required to void order' });
          return true;
        }
        authorizedById = override.staffId;
        authorizedByName = override.staffName;
      }

      const now = new Date().toISOString();
      orders[index] = {
        ...orders[index],
        status: 'cancelled',
        voidedAt: now,
        voidReason: String(body.reason || body.voidReason || '').trim(),
        voidedById: performedById || null,
        voidedByName: performedByName || null,
        voidAuthorizedById: authorizedById,
        voidAuthorizedByName: authorizedByName,
      };
      await writeOrders(orders);
      await appendAudit(deps, {
        restaurantId,
        action: 'order_void',
        entityType: 'order',
        entityId: orderId,
        performedById: performedById || 'admin',
        performedByName: performedByName || 'Admin',
        authorizedById,
        authorizedByName,
        metadata: { reason: orders[index].voidReason },
      });
      sendJson(res, 200, orders[index]);
    } catch (error) {
      sendJson(res, 400, { error: error.message || 'Invalid payload' });
    }
    return true;
  }

  const refundOrderMatch = url.pathname.match(/^\/api\/orders\/([^/]+)\/refund$/);
  if (refundOrderMatch && req.method === 'PATCH') {
    try {
      const orderId = decodeURIComponent(refundOrderMatch[1]);
      const body = JSON.parse((await readBody(req)) || '{}');
      const auth = requireAuth(req, res);
      if (!auth) return true;

      if (isSuperAdmin(auth)) {
        authError(res, 403, 'Orders are managed by restaurant admins only');
        return true;
      }

      const orders = await readOrders();
      const index = orders.findIndex((order) => String(order.id) === orderId);
      if (index === -1) {
        sendJson(res, 404, { error: 'Order not found' });
        return true;
      }

      const restaurantId =
        orders[index].restaurant_id || orders[index].restaurantId || deps.DEFAULT_RESTAURANT_ID;
      if (!assertRestaurantAccess(auth, restaurantId, authError, res)) {
        return true;
      }

      const refundAmount = Number(body.refundAmount ?? body.refund_amount ?? 0) || 0;
      if (refundAmount <= 0) {
        sendJson(res, 400, { error: 'refundAmount must be greater than zero' });
        return true;
      }

      const settings = await readSettings(restaurantId);
      const { posRoles } = parsePosSettings(settings);
      const staffUsers = filterByRestaurant(await readStaffUsers(), restaurantId);
      const performedById = String(body.performedById || body.performed_by_id || '').trim();
      const performedByName = String(body.performedByName || body.performed_by_name || '').trim();
      const performer = staffUsers.find((entry) => String(entry.id) === performedById);
      const performerAllowed =
        performer &&
        resolveStaffPermissions(performer, posRoles)[PERMISSION_KEYS.PROCESS_REFUNDS] === true;

      let authorizedById = body.authorizedById || body.authorized_by_id || null;
      let authorizedByName = body.authorizedByName || body.authorized_by_name || null;

      if (!performerAllowed) {
        const pin = String(body.managerPin || body.manager_pin || body.pin || '').trim();
        const restaurants = await readRestaurants();
        const restaurantRecord = restaurants.find((entry) => entry.id === restaurantId);
        const override = verifyManagerOverride({
          staffUsers,
          restaurantId,
          pin,
          roles: posRoles,
          restaurantRecord,
        });
        if (!override.authorized) {
          sendJson(res, 403, { error: 'Manager override required to process refund' });
          return true;
        }
        authorizedById = override.staffId;
        authorizedByName = override.staffName;
      }

      const now = new Date().toISOString();
      const existingRefund = Number(orders[index].refundAmount ?? orders[index].refund_amount ?? 0) || 0;
      orders[index] = {
        ...orders[index],
        refundAmount: existingRefund + refundAmount,
        refundReason: String(body.reason || body.refundReason || '').trim(),
        refundedAt: now,
        refundedById: performedById || null,
        refundedByName: performedByName || null,
        refundAuthorizedById: authorizedById,
        refundAuthorizedByName: authorizedByName,
      };
      await writeOrders(orders);
      await appendAudit(deps, {
        restaurantId,
        action: 'order_refund',
        entityType: 'order',
        entityId: orderId,
        performedById: performedById || 'admin',
        performedByName: performedByName || 'Admin',
        authorizedById,
        authorizedByName,
        metadata: { refundAmount, reason: orders[index].refundReason },
      });
      sendJson(res, 200, orders[index]);
    } catch (error) {
      sendJson(res, 400, { error: error.message || 'Invalid payload' });
    }
    return true;
  }

  return false;
}

module.exports = {
  handlePosRoutes,
  parsePosSettings,
  PERMISSION_KEYS,
};
