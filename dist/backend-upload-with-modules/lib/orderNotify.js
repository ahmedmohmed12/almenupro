'use strict';

const { sendNewOrderSuperAdminNotification } = require('./mailer');

/**
 * Super-admin email when any restaurant creates an order.
 * Never throws to callers — order persistence must not fail because of mail.
 * Must be awaited on Vercel serverless (background promises die after the response).
 */
async function notifySuperAdminNewOrder(order, deps = {}) {
  try {
    if (!order || typeof order !== 'object') {
      console.warn('[orderNotify] skipped: missing order payload');
      return { sent: false, reason: 'no_order' };
    }

    const restaurantId = String(
      order.restaurantId || order.restaurant_id || '',
    ).trim();

    let restaurantName = String(
      order.restaurantName || order.restaurant_name || '',
    ).trim();

    if (!restaurantName && typeof deps.readRestaurants === 'function') {
      try {
        const restaurants = await deps.readRestaurants();
        const match = (Array.isArray(restaurants) ? restaurants : []).find(
          (entry) => String(entry?.id) === restaurantId,
        );
        restaurantName = String(
          match?.name || match?.nameAr || match?.name_ar || '',
        ).trim();
      } catch (error) {
        console.warn(
          '[orderNotify] restaurant lookup failed:',
          error?.message || error,
        );
      }
    }

    if (!restaurantName) {
      restaurantName = restaurantId ? `مطعم ${restaurantId}` : 'مطعم غير معروف';
    }

    console.log(
      `[orderNotify] new order id=${order.id || '—'} restaurant=${restaurantName} (${restaurantId || 'n/a'})`,
    );

    const result = await sendNewOrderSuperAdminNotification({
      restaurantName,
      order,
    });
    console.log(
      `[orderNotify] mail result sent=${Boolean(result?.sent)} reason=${result?.reason || 'ok'} order=${order.id || '—'}`,
    );
    return result;
  } catch (error) {
    console.error('[orderNotify] unexpected failure:', error);
    return {
      sent: false,
      reason: 'notify_failed',
      detail: String(error?.message || error),
    };
  }
}

/** Awaitable wrapper that still never rejects. */
async function scheduleSuperAdminOrderNotify(order, deps = {}) {
  try {
    return await notifySuperAdminNewOrder(order, deps);
  } catch (error) {
    console.error('[orderNotify] schedule failed:', error);
    return {
      sent: false,
      reason: 'schedule_failed',
      detail: String(error?.message || error),
    };
  }
}

module.exports = {
  notifySuperAdminNewOrder,
  scheduleSuperAdminOrderNotify,
};
