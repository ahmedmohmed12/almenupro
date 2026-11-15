const { DEFAULT_RESTAURANT_ID, isSuperAdmin } = require('./adminAuth');

function resolveEntityRestaurantId(entity, fallback = DEFAULT_RESTAURANT_ID) {
  return String(entity?.restaurant_id || entity?.restaurantId || fallback);
}

function entityMatchesRestaurant(entity, restaurantId) {
  return resolveEntityRestaurantId(entity) === String(restaurantId);
}

function readRestaurantIdParam(req, url) {
  return (
    url.searchParams.get('restaurant_id') ||
    url.searchParams.get('restaurantId') ||
    req.headers['x-restaurant-id'] ||
    null
  );
}

/**
 * Resolves restaurant scope for authenticated report/analytics endpoints.
 * Super admins must pass restaurant_id (query) or X-Restaurant-Id (header).
 */
function resolveReportRestaurantId(req, url, auth) {
  if (!auth) return null;

  if (auth.restaurantId && !isSuperAdmin(auth)) {
    return String(auth.restaurantId);
  }

  if (isSuperAdmin(auth)) {
    const explicit = readRestaurantIdParam(req, url);
    return explicit ? String(explicit) : null;
  }

  const explicit = readRestaurantIdParam(req, url);
  return explicit ? String(explicit) : null;
}

module.exports = {
  resolveEntityRestaurantId,
  entityMatchesRestaurant,
  readRestaurantIdParam,
  resolveReportRestaurantId,
};
