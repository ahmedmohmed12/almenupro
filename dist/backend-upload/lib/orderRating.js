'use strict';

const crypto = require('crypto');
const { createReviewRecord, findReviewForOrder } = require('./reviewsStore');

function isDeliveredStatus(status) {
  const value = String(status || '').trim().toLowerCase();
  return value === 'delivered' || value === 'completed' || value === 'تم التوصيل';
}

function createRatingToken() {
  return crypto.randomBytes(18).toString('base64url');
}

function ensureRatingToken(order) {
  const existing = String(order?.ratingToken || order?.rating_token || '').trim();
  if (existing) return existing;
  return createRatingToken();
}

function tokensMatch(order, token) {
  const expected = String(order?.ratingToken || order?.rating_token || '').trim();
  const got = String(token || '').trim();
  return expected.length > 0 && got.length > 0 && expected === got;
}

function waPhone(raw) {
  let digits = String(raw || '').replace(/\D/g, '');
  if (digits.startsWith('00')) digits = digits.slice(2);
  if (digits.startsWith('0') && digits.length >= 8) digits = `965${digits.slice(1)}`;
  if (digits.length === 8) digits = `965${digits}`;
  return digits;
}

function frontendOrigin() {
  return String(
    process.env.FRONTEND_URL ||
      process.env.FRONTEND_ORIGIN ||
      'https://frontend-six-lime-13.vercel.app',
  ).replace(/\/+$/, '');
}

function ratingUrlFor(orderId, token) {
  return `${frontendOrigin()}/order/${encodeURIComponent(orderId)}/rate?token=${encodeURIComponent(token)}`;
}

function displayOrderNumber(order) {
  return String(order?.invoiceNumber || order?.invoice_number || order?.id || '').replace(/^ord_/, '');
}

function ratingMessage({ restaurantName, order, ratingUrl }) {
  const number = displayOrderNumber(order);
  return (
    `عليكم بالعافية، شكراً لطلبك من ${restaurantName}! 🌸\n` +
    `يهمنا رأيك لتطوير خدمتنا، يرجى تقييم تجربتك للطلب رقم #${number} عبر الرابط التالي:\n` +
    ratingUrl
  );
}

function publicRatingPayload(order, restaurant) {
  const rated = order.isRated === true || order.is_rated === true || Number(order.rating) >= 1;
  return {
    orderId: order.id,
    invoiceNumber: order.invoiceNumber || order.invoice_number || '',
    createdAt: order.createdAt || order.created_at,
    paymentMethod: order.paymentMethod || order.payment_method || '',
    totalPrice: Number(order.totalPrice || order.total_price || 0),
    restaurantName: restaurant?.name || '',
    items: (order.items || []).map((line) => ({
      name: line.name,
      quantity: Number(line.quantity) || 1,
      unitPrice: Number(line.unitPrice ?? line.price ?? 0),
      lineTotal: Number(
        line.lineTotal ??
          (Number(line.unitPrice ?? line.price ?? 0) * (Number(line.quantity) || 1)),
      ),
    })),
    isRated: rated,
    rating: rated ? Number(order.rating) || null : null,
    reviewNote: rated ? String(order.reviewNote || order.review_note || '') : '',
  };
}

function applyRatingToOrder(order, { rating, reviewNote }) {
  const now = new Date().toISOString();
  return {
    ...order,
    rating,
    review_note: reviewNote,
    reviewNote,
    is_rated: true,
    isRated: true,
    ratedAt: now,
    rated_at: now,
  };
}

async function handleOrderRatingRoutes(req, res, url, deps) {
  const {
    readBody,
    sendJson,
    requireAuth,
    parseJson,
    assertRestaurantAccess,
    authError,
    readOrders,
    patchOrderById,
    readRestaurants,
    readReviews,
    writeReviews,
  } = deps;

  const ratingLinkMatch = url.pathname.match(/^\/api\/orders\/([^/]+)\/rating-link$/);
  const ratingMatch = url.pathname.match(/^\/api\/orders\/([^/]+)\/rating$/);

  if (ratingLinkMatch && req.method === 'POST') {
    const auth = requireAuth(req, res);
    if (!auth) return true;
    const orderId = decodeURIComponent(ratingLinkMatch[1]);
    const orders = await readOrders();
    const order = orders.find((row) => String(row.id) === String(orderId));
    if (!order) {
      sendJson(res, 404, { error: 'Order not found' });
      return true;
    }
    const restaurantId = order.restaurant_id || order.restaurantId;
    if (!assertRestaurantAccess(auth, restaurantId, authError, res)) return true;
    if (!isDeliveredStatus(order.status)) {
      sendJson(res, 409, { error: 'Order is not delivered yet' });
      return true;
    }
    const token = ensureRatingToken(order);
    const next = {
      ...order,
      ratingToken: token,
      rating_token: token,
    };
    if (token !== String(order.ratingToken || order.rating_token || '')) {
      await patchOrderById(orderId, next, orders);
    }
    const restaurants = await readRestaurants();
    const restaurant = restaurants.find((row) => String(row.id) === String(restaurantId));
    const restaurantName = restaurant?.name || 'المطعم';
    const ratingUrl = ratingUrlFor(order.id, token);
    const message = ratingMessage({ restaurantName, order: next, ratingUrl });
    const phone = waPhone(order.phone);
    sendJson(res, 200, {
      ratingUrl,
      ratingToken: token,
      alreadyRated: next.isRated === true || next.is_rated === true || Number(next.rating) >= 1,
      whatsappUrl: phone
        ? `https://wa.me/${phone}?text=${encodeURIComponent(message)}`
        : null,
      message,
      phone: order.phone || '',
    });
    return true;
  }

  if (ratingMatch && req.method === 'GET') {
    const orderId = decodeURIComponent(ratingMatch[1]);
    const token = url.searchParams.get('token') || '';
    const orders = await readOrders();
    const order = orders.find((row) => String(row.id) === String(orderId));
    if (!order || !tokensMatch(order, token)) {
      sendJson(res, 404, { error: 'Rating link is invalid' });
      return true;
    }
    if (!isDeliveredStatus(order.status)) {
      sendJson(res, 409, { error: 'Order is not delivered yet' });
      return true;
    }
    const restaurants = await readRestaurants();
    const restaurant = restaurants.find(
      (row) => String(row.id) === String(order.restaurant_id || order.restaurantId),
    );
    sendJson(res, 200, publicRatingPayload(order, restaurant));
    return true;
  }

  if (ratingMatch && req.method === 'POST') {
    const orderId = decodeURIComponent(ratingMatch[1]);
    const body = parseJson(await readBody(req));
    const token = body.token || url.searchParams.get('token') || '';
    const rating = Math.round(Number(body.rating));
    if (!Number.isFinite(rating) || rating < 1 || rating > 5) {
      sendJson(res, 400, { error: 'Rating must be between 1 and 5' });
      return true;
    }
    const reviewNote = String(body.reviewNote || body.review_note || body.comment || '')
      .trim()
      .slice(0, 1000);
    const orders = await readOrders();
    const order = orders.find((row) => String(row.id) === String(orderId));
    if (!order || !tokensMatch(order, token)) {
      sendJson(res, 404, { error: 'Rating link is invalid' });
      return true;
    }
    if (!isDeliveredStatus(order.status)) {
      sendJson(res, 409, { error: 'Order is not delivered yet' });
      return true;
    }
    if (order.isRated === true || order.is_rated === true || Number(order.rating) >= 1) {
      sendJson(res, 409, { error: 'This order was already rated' });
      return true;
    }
    const next = applyRatingToOrder(order, { rating, reviewNote });
    await patchOrderById(orderId, next, orders);

    const restaurantId = order.restaurant_id || order.restaurantId;
    const reviews = await readReviews();
    if (!findReviewForOrder(reviews, restaurantId, orderId)) {
      try {
        reviews.push(
          createReviewRecord(
            {
              rating,
              comment: reviewNote,
              customerName: order.customerName,
              phone: order.phone,
              invoiceNumber: order.invoiceNumber,
            },
            restaurantId,
            order,
          ),
        );
        await writeReviews(reviews);
      } catch (_) {}
    }
    const restaurants = await readRestaurants();
    const restaurant = restaurants.find((row) => String(row.id) === String(restaurantId));
    sendJson(res, 201, publicRatingPayload(next, restaurant));
    return true;
  }

  return false;
}

module.exports = {
  handleOrderRatingRoutes,
  createRatingToken,
  ensureRatingToken,
};
