const { randomUUID } = require('crypto');
const { ensureRestaurantId } = require('./tenantStore');

function clampRating(raw) {
  const n = Number(raw);
  if (!Number.isFinite(n)) return null;
  const rounded = Math.round(n);
  if (rounded < 1 || rounded > 5) return null;
  return rounded;
}

function normalizeReview(raw = {}, restaurantId) {
  const rating = clampRating(raw.rating ?? raw.stars);
  const createdAt =
    raw.createdAt ||
    raw.created_at ||
    new Date().toISOString();
  const updatedAt =
    raw.updatedAt || raw.updated_at || createdAt;

  const review = ensureRestaurantId(
    {
      id: String(raw.id || `rev_${randomUUID()}`),
      orderId: String(raw.orderId || raw.order_id || '').trim() || null,
      rating,
      comment: String(raw.comment || raw.feedback || raw.text || '')
        .trim()
        .slice(0, 1000),
      customerName: String(
        raw.customerName || raw.customer_name || '',
      ).trim().slice(0, 120),
      phone: String(raw.phone || '').trim().slice(0, 32),
      invoiceNumber: String(
        raw.invoiceNumber || raw.invoice_number || '',
      ).trim().slice(0, 64),
      status: String(raw.status || 'published').toLowerCase() === 'hidden'
        ? 'hidden'
        : 'published',
      createdAt,
      updatedAt,
    },
    restaurantId || raw.restaurant_id || raw.restaurantId,
  );

  return review;
}

function sanitizeReviewPublic(review) {
  return {
    id: review.id,
    rating: review.rating,
    comment: review.comment,
    customerName: review.customerName
      ? maskCustomerName(review.customerName)
      : '',
    createdAt: review.createdAt,
  };
}

function sanitizeReviewAdmin(review) {
  return {
    id: review.id,
    restaurantId: review.restaurant_id || review.restaurantId,
    orderId: review.orderId,
    rating: review.rating,
    comment: review.comment,
    customerName: review.customerName,
    phone: review.phone,
    invoiceNumber: review.invoiceNumber,
    status: review.status,
    createdAt: review.createdAt,
    updatedAt: review.updatedAt,
  };
}

function maskCustomerName(name) {
  const trimmed = String(name || '').trim();
  if (!trimmed) return '';
  if (trimmed.length <= 2) return `${trimmed[0] || ''}*`;
  return `${trimmed.slice(0, 2)}${'*'.repeat(Math.min(4, trimmed.length - 2))}`;
}

function isPublished(review) {
  return String(review?.status || 'published').toLowerCase() !== 'hidden';
}

function aggregateReviews(reviews, restaurantId) {
  const scoped = (reviews || [])
    .filter((row) => String(row.restaurant_id || row.restaurantId) === String(restaurantId))
    .filter(isPublished)
    .filter((row) => Number(row.rating) >= 1 && Number(row.rating) <= 5);

  const count = scoped.length;
  if (count === 0) {
    return {
      average: 0,
      count: 0,
      distribution: { 1: 0, 2: 0, 3: 0, 4: 0, 5: 0 },
    };
  }

  const distribution = { 1: 0, 2: 0, 3: 0, 4: 0, 5: 0 };
  let sum = 0;
  for (const row of scoped) {
    const rating = Number(row.rating);
    sum += rating;
    distribution[rating] = (distribution[rating] || 0) + 1;
  }

  return {
    average: Number((sum / count).toFixed(2)),
    count,
    distribution,
  };
}

function findReviewForOrder(reviews, restaurantId, orderId) {
  const oid = String(orderId || '').trim();
  if (!oid) return null;
  return (reviews || []).find(
    (row) =>
      String(row.restaurant_id || row.restaurantId) === String(restaurantId) &&
      String(row.orderId || row.order_id || '') === oid,
  ) || null;
}

function createReviewRecord(body, restaurantId, order) {
  const rating = clampRating(body.rating ?? body.stars);
  if (rating == null) {
    const error = new Error('Rating must be an integer from 1 to 5');
    error.code = 'INVALID_RATING';
    throw error;
  }

  return normalizeReview(
    {
      id: `rev_${randomUUID()}`,
      orderId: order?.id || body.orderId || body.order_id,
      rating,
      comment: body.comment || body.feedback || body.text,
      customerName:
        body.customerName ||
        body.customer_name ||
        order?.customerName ||
        order?.customer_name,
      phone: body.phone || order?.phone,
      invoiceNumber:
        body.invoiceNumber ||
        body.invoice_number ||
        order?.invoiceNumber ||
        order?.invoice_number,
      status: 'published',
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString(),
    },
    restaurantId,
  );
}

function ratingsByDay(reviews, restaurantId, days = 30) {
  const scoped = (reviews || [])
    .filter((row) => String(row.restaurant_id || row.restaurantId) === String(restaurantId))
    .filter(isPublished);

  const end = new Date();
  const start = new Date();
  start.setUTCDate(end.getUTCDate() - (Math.max(1, Number(days) || 30) - 1));
  start.setUTCHours(0, 0, 0, 0);

  const buckets = [];
  for (let d = new Date(start); d <= end; d.setUTCDate(d.getUTCDate() + 1)) {
    const key = d.toISOString().slice(0, 10);
    buckets.push({ date: key, count: 0, average: 0, sum: 0 });
  }
  const byDate = Object.fromEntries(buckets.map((b) => [b.date, b]));

  for (const row of scoped) {
    const key = String(row.createdAt || '').slice(0, 10);
    const bucket = byDate[key];
    if (!bucket) continue;
    bucket.count += 1;
    bucket.sum += Number(row.rating) || 0;
  }

  return buckets.map((b) => ({
    date: b.date,
    count: b.count,
    average: b.count > 0 ? Number((b.sum / b.count).toFixed(2)) : 0,
  }));
}

module.exports = {
  normalizeReview,
  sanitizeReviewPublic,
  sanitizeReviewAdmin,
  aggregateReviews,
  findReviewForOrder,
  createReviewRecord,
  ratingsByDay,
  clampRating,
  isPublished,
};
