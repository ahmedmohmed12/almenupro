const crypto = require('crypto');

const SECRET = process.env.ADMIN_AUTH_SECRET || 'almenupro-dev-secret';
const SUPER_ADMIN_USER = process.env.SUPER_ADMIN_USER || 'superadmin';
const SUPER_ADMIN_PASSWORD = process.env.SUPER_ADMIN_PASSWORD || 'almenupro2026';
const DEFAULT_RESTAURANT_ID = 'rest_molton';

const ROLES = {
  SUPER_ADMIN: 'super_admin',
  RESTAURANT_ADMIN: 'restaurant_admin',
};

function signToken(payload) {
  const data = Buffer.from(JSON.stringify(payload)).toString('base64url');
  const signature = crypto
    .createHmac('sha256', SECRET)
    .update(data)
    .digest('base64url');
  return `${data}.${signature}`;
}

function verifyToken(token) {
  if (!token || typeof token !== 'string') return null;
  const parts = token.split('.');
  if (parts.length !== 2) return null;

  const [data, signature] = parts;
  const expected = crypto
    .createHmac('sha256', SECRET)
    .update(data)
    .digest('base64url');

  if (signature !== expected) return null;

  try {
    const payload = JSON.parse(Buffer.from(data, 'base64url').toString('utf8'));
    if (!payload?.role) return null;
    return payload;
  } catch {
    return null;
  }
}

function issueSession({ role, restaurantId = null, restaurantName = null }) {
  return signToken({
    role,
    restaurantId,
    restaurantName,
    iat: Date.now(),
  });
}

function loginSuperAdmin(username, password) {
  if (
    String(username || '').trim() !== SUPER_ADMIN_USER ||
    String(password || '') !== SUPER_ADMIN_PASSWORD
  ) {
    return null;
  }

  return issueSession({ role: ROLES.SUPER_ADMIN });
}

function loginRestaurantAdmin(restaurantSlug, password, restaurants) {
  const slug = String(restaurantSlug || '').trim().toLowerCase();
  const restaurant = restaurants.find(
    (entry) => String(entry.slug || '').toLowerCase() === slug,
  );

  if (!restaurant) return null;
  if (String(password || '') !== String(restaurant.adminPassword || '')) {
    return null;
  }

  return issueSession({
    role: ROLES.RESTAURANT_ADMIN,
    restaurantId: restaurant.id,
    restaurantName: restaurant.name,
  });
}

function parseAuthHeader(req) {
  const header = req.headers.authorization || req.headers.Authorization || '';
  const match = String(header).match(/^Bearer\s+(.+)$/i);
  if (!match) return null;
  return verifyToken(match[1]);
}

function isSuperAdmin(auth) {
  return auth?.role === ROLES.SUPER_ADMIN;
}

function isRestaurantAdmin(auth) {
  return auth?.role === ROLES.RESTAURANT_ADMIN;
}

function canAccessRestaurant(auth, restaurantId) {
  if (!auth) return false;
  if (isSuperAdmin(auth)) return true;
  return isRestaurantAdmin(auth) && auth.restaurantId === restaurantId;
}

function resolveRestaurantId(auth, requestedRestaurantId, { allowPublicDefault = false } = {}) {
  if (auth && isRestaurantAdmin(auth)) {
    return auth.restaurantId;
  }

  if (auth && isSuperAdmin(auth)) {
    return requestedRestaurantId || DEFAULT_RESTAURANT_ID;
  }

  if (allowPublicDefault) {
    return requestedRestaurantId || DEFAULT_RESTAURANT_ID;
  }

  return null;
}

const CORS_ALLOW_METHODS = 'GET, HEAD, POST, PUT, PATCH, DELETE, OPTIONS';
const CORS_ALLOW_HEADERS =
  'Content-Type, Authorization, X-Restaurant-Id, X-Requested-With, Accept, Origin';

function corsHeaders(req) {
  const requested = String(req?.headers?.['access-control-request-headers'] || '').trim();
  return {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': CORS_ALLOW_METHODS,
    'Access-Control-Allow-Headers': requested || CORS_ALLOW_HEADERS,
    'Access-Control-Max-Age': '86400',
    Vary: 'Origin, Access-Control-Request-Headers',
  };
}

function applyCorsHeaders(req, res) {
  const headers = corsHeaders(req);
  for (const [key, value] of Object.entries(headers)) {
    res.setHeader(key, value);
  }
  return headers;
}

function handleCorsPreflight(req, res) {
  applyCorsHeaders(req, res);
  if (String(req.method || '').toUpperCase() !== 'OPTIONS') {
    return false;
  }
  res.statusCode = 200;
  res.setHeader('Content-Length', '0');
  res.end();
  return true;
}

function authError(res, statusCode, message) {
  const headers = corsHeaders({ headers: {} });
  res.writeHead(statusCode, {
    'Content-Type': 'application/json; charset=utf-8',
    ...headers,
  });
  res.end(JSON.stringify({ error: message }));
}

module.exports = {
  ROLES,
  DEFAULT_RESTAURANT_ID,
  SUPER_ADMIN_USER,
  CORS_ALLOW_METHODS,
  CORS_ALLOW_HEADERS,
  corsHeaders,
  applyCorsHeaders,
  handleCorsPreflight,
  loginSuperAdmin,
  loginRestaurantAdmin,
  parseAuthHeader,
  isSuperAdmin,
  isRestaurantAdmin,
  canAccessRestaurant,
  resolveRestaurantId,
  authError,
};
