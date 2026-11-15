const {
  sanitizeReviewPublic,
  sanitizeReviewAdmin,
  aggregateReviews,
  findReviewForOrder,
  createReviewRecord,
  ratingsByDay,
  isPublished,
} = require('./reviewsStore');

function isDeliveredStatus(status) {
  const value = String(status || '').trim().toLowerCase();
  return (
    value === 'delivered' ||
    value === 'completed' ||
    value === 'تم التوصيل'
  );
}

async function handleReviewRoutes(req, res, url, deps) {
  const {
    readBody,
    sendJson,
    authError,
    requireAuth,
    parseAuthHeader,
    isCashier,
    assertRestaurantAccess,
    resolveScopedRestaurantId,
    filterByRestaurant,
    readReviews,
    writeReviews,
    readOrders,
    rejectCashier,
  } = deps;

  if (!url.pathname.startsWith('/api/reviews')) {
    return false;
  }

  // Public aggregate for storefront header.
  if (url.pathname === '/api/reviews/summary' && req.method === 'GET') {
    const auth = parseAuthHeader?.(req) || null;
    const restaurantId = await resolveScopedRestaurantId(req, url, auth, {
      allowPublicDefault: true,
    });
    if (!restaurantId) {
      sendJson(res, 404, { error: 'Restaurant not found' });
      return true;
    }
    const summary = aggregateReviews(await readReviews(), restaurantId);
    sendJson(res, 200, summary);
    return true;
  }

  // Public: check whether a customer may rate this order (delivered + no review).
  if (url.pathname === '/api/reviews/eligibility' && req.method === 'GET') {
    const auth = parseAuthHeader?.(req) || null;
    const restaurantId = await resolveScopedRestaurantId(req, url, auth, {
      allowPublicDefault: true,
    });
    if (!restaurantId) {
      sendJson(res, 404, { error: 'Restaurant not found' });
      return true;
    }

    const orderId = String(
      url.searchParams.get('orderId') ||
        url.searchParams.get('order_id') ||
        '',
    ).trim();
    if (!orderId) {
      sendJson(res, 400, { error: 'orderId is required' });
      return true;
    }

    const orders = filterByRestaurant(await readOrders(), restaurantId);
    const order = orders.find((row) => String(row.id) === orderId);
    if (!order) {
      sendJson(res, 200, {
        eligible: false,
        reason: 'order_not_found',
        status: null,
      });
      return true;
    }

    const status = String(order.status || '').toLowerCase();
    if (!isDeliveredStatus(status)) {
      sendJson(res, 200, {
        eligible: false,
        reason: 'not_delivered',
        status,
        orderId,
        invoiceNumber: order.invoiceNumber || order.invoice_number || '',
      });
      return true;
    }

    const existing = findReviewForOrder(
      await readReviews(),
      restaurantId,
      orderId,
    );
    if (existing) {
      sendJson(res, 200, {
        eligible: false,
        reason: 'already_reviewed',
        status,
        orderId,
        reviewId: existing.id,
      });
      return true;
    }

    sendJson(res, 200, {
      eligible: true,
      reason: 'ready',
      status,
      orderId,
      invoiceNumber: order.invoiceNumber || order.invoice_number || '',
      customerName: order.customerName || order.customer_name || '',
    });
    return true;
  }

  // Public recent reviews (optional display).
  if (url.pathname === '/api/reviews/public' && req.method === 'GET') {
    const auth = parseAuthHeader?.(req) || null;
    const restaurantId = await resolveScopedRestaurantId(req, url, auth, {
      allowPublicDefault: true,
    });
    if (!restaurantId) {
      sendJson(res, 404, { error: 'Restaurant not found' });
      return true;
    }
    const limit = Math.min(
      50,
      Math.max(1, Number(url.searchParams.get('limit') || 10) || 10),
    );
    const reviews = filterByRestaurant(await readReviews(), restaurantId)
      .filter(isPublished)
      .sort(
        (a, b) =>
          String(b.createdAt || '').localeCompare(String(a.createdAt || '')),
      )
      .slice(0, limit)
      .map(sanitizeReviewPublic);
    sendJson(res, 200, {
      reviews,
      summary: aggregateReviews(await readReviews(), restaurantId),
    });
    return true;
  }

  // Public submit — only allowed when order is delivered and not yet reviewed.
  if (url.pathname === '/api/reviews' && req.method === 'POST') {
    try {
      const body = JSON.parse((await readBody(req)) || '{}');
      const auth = parseAuthHeader?.(req) || null;
      const restaurantId =
        body.restaurantId ||
        body.restaurant_id ||
        (await resolveScopedRestaurantId(req, url, auth, {
          allowPublicDefault: true,
        }));
      if (!restaurantId) {
        sendJson(res, 404, { error: 'Restaurant not found' });
        return true;
      }

      const orderId = String(body.orderId || body.order_id || '').trim();
      if (!orderId) {
        sendJson(res, 400, { error: 'orderId is required' });
        return true;
      }

      const orders = filterByRestaurant(await readOrders(), restaurantId);
      const order = orders.find((row) => String(row.id) === orderId);
      if (!order) {
        sendJson(res, 404, { error: 'Order not found' });
        return true;
      }

      if (!isDeliveredStatus(order.status)) {
        sendJson(res, 409, {
          error: 'Reviews are only accepted after the order is delivered',
          status: order.status,
        });
        return true;
      }

      const reviews = await readReviews();
      if (findReviewForOrder(reviews, restaurantId, orderId)) {
        sendJson(res, 409, { error: 'This order was already reviewed' });
        return true;
      }

      // Optional phone check when provided (soft match).
      const submittedPhone = String(body.phone || '')
        .replace(/\D/g, '')
        .slice(-8);
      const orderPhone = String(order.phone || '')
        .replace(/\D/g, '')
        .slice(-8);
      if (
        submittedPhone &&
        orderPhone &&
        submittedPhone.length >= 7 &&
        submittedPhone !== orderPhone
      ) {
        sendJson(res, 403, { error: 'Phone does not match this order' });
        return true;
      }

      const review = createReviewRecord(body, restaurantId, order);
      reviews.push(review);
      await writeReviews(reviews);

      sendJson(res, 201, {
        review: sanitizeReviewPublic(review),
        summary: aggregateReviews(reviews, restaurantId),
      });
    } catch (error) {
      const status = error.code === 'INVALID_RATING' ? 400 : 400;
      sendJson(res, status, { error: error.message || 'Invalid review' });
    }
    return true;
  }

  // Admin list + analytics.
  if (url.pathname === '/api/reviews' && req.method === 'GET') {
    const auth = requireAuth(req, res);
    if (!auth) return true;
    if (rejectCashier?.(auth, res, 'Cashiers cannot manage reviews')) return true;

    const restaurantId = await resolveScopedRestaurantId(req, url, auth, {
      allowPublicDefault: false,
    });
    if (!restaurantId || !assertRestaurantAccess(auth, restaurantId, authError, res)) {
      return true;
    }

    const days = Number(url.searchParams.get('days') || 30) || 30;
    const includeHidden = url.searchParams.get('includeHidden') === 'true';
    let reviews = filterByRestaurant(await readReviews(), restaurantId);
    if (!includeHidden) {
      reviews = reviews.filter(isPublished);
    }
    reviews = reviews
      .slice()
      .sort(
        (a, b) =>
          String(b.createdAt || '').localeCompare(String(a.createdAt || '')),
      );

    sendJson(res, 200, {
      reviews: reviews.map(sanitizeReviewAdmin),
      summary: aggregateReviews(await readReviews(), restaurantId),
      trend: ratingsByDay(await readReviews(), restaurantId, days),
    });
    return true;
  }

  const patchMatch = url.pathname.match(/^\/api\/reviews\/([^/]+)$/);
  if (patchMatch && req.method === 'PATCH') {
    const auth = requireAuth(req, res);
    if (!auth) return true;
    if (rejectCashier?.(auth, res, 'Cashiers cannot manage reviews')) return true;

    const restaurantId = await resolveScopedRestaurantId(req, url, auth, {
      allowPublicDefault: false,
    });
    if (!restaurantId || !assertRestaurantAccess(auth, restaurantId, authError, res)) {
      return true;
    }

    try {
      const body = JSON.parse((await readBody(req)) || '{}');
      const reviewId = decodeURIComponent(patchMatch[1]);
      const reviews = await readReviews();
      const index = reviews.findIndex(
        (row) =>
          String(row.id) === reviewId &&
          String(row.restaurant_id || row.restaurantId) === String(restaurantId),
      );
      if (index < 0) {
        sendJson(res, 404, { error: 'Review not found' });
        return true;
      }

      const nextStatus =
        body.status === 'hidden'
          ? 'hidden'
          : body.status === 'published'
            ? 'published'
            : reviews[index].status;

      reviews[index] = {
        ...reviews[index],
        status: nextStatus,
        updatedAt: new Date().toISOString(),
      };
      await writeReviews(reviews);
      sendJson(res, 200, {
        review: sanitizeReviewAdmin(reviews[index]),
        summary: aggregateReviews(reviews, restaurantId),
      });
    } catch (error) {
      sendJson(res, 400, { error: error.message || 'Invalid payload' });
    }
    return true;
  }

  sendJson(res, 405, { error: 'Method not allowed' });
  return true;
}

module.exports = { handleReviewRoutes };
