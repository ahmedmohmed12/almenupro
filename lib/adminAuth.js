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

const CORS_ALLOW_METHODS = 'GET, POST, PUT, PATCH, DELETE, OPTIONS';
const CORS_ALLOW_HEADERS =
  'Content-Type, Authorization, X-Restaurant-Id, X-Requested-With';

const PRODUCTION_DASHBOARD_ORIGIN =
  'https://almenupro-dashboard-2026-gfwn0j6x9-almenupro.vercel.app';

const STATIC_ALLOWED_ORIGINS = new Set([
  PRODUCTION_DASHBOARD_ORIGIN,
  'https://almenupro-dashboard-2026.vercel.app',
  'https://almenupro-frontend-three.vercel.app',
  'https://almenupro.vercel.app',
  'http://localhost:3000',
  'http://localhost:8080',
  'http://localhost:8088',
  'http://127.0.0.1:3000',
  'http://127.0.0.1:8080',
  'http://127.0.0.1:8088',
]);

function extraAllowedOrigins() {
  return String(process.env.CORS_ALLOWED_ORIGINS || '')
    .split(',')
    .map((value) => value.trim())
    .filter(Boolean);
}

function isAllowedOrigin(origin) {
  if (!origin) return false;
  if (STATIC_ALLOWED_ORIGINS.has(origin)) return true;
  if (extraAllowedOrigins().includes(origin)) return true;
  try {
    const { protocol, hostname } = new URL(origin);
    if (protocol !== 'https:') return false;
    // Vercel preview URLs for this team, e.g. almenupro-dashboard-2026-*-almenupro.vercel.app
    if (hostname.endsWith('-almenupro.vercel.app')) return true;
    if (hostname === 'almenupro-backend.vercel.app') return true;
  } catch {
    return false;
  }
  return false;
}

function requestOrigin(req) {
  return String(req?.headers?.origin || req?.headers?.Origin || '').trim();
}

function corsHeaders(req) {
  const origin = requestOrigin(req);
  const requested = String(req?.headers?.['access-control-request-headers'] || '').trim();
  const headers = {
    'Access-Control-Allow-Methods': CORS_ALLOW_METHODS,
    'Access-Control-Allow-Headers': requested || CORS_ALLOW_HEADERS,
    'Access-Control-Max-Age': '86400',
    Vary: 'Origin, Access-Control-Request-Headers',
  };
  // Bearer-token API: do not enable credentials, so a reflected origin is sufficient.
  // Never use '*' together with credentials (none are set here).
  if (origin && isAllowedOrigin(origin)) {
    headers['Access-Control-Allow-Origin'] = origin;
  } else if (!origin) {
    headers['Access-Control-Allow-Origin'] = PRODUCTION_DASHBOARD_ORIGIN;
  }
  return headers;
}

function applyCorsHeaders(req, res) {
  const source = req && req.headers ? req : res?.req;
  const headers = corsHeaders(source);
  for (const [key, value] of Object.entries(headers)) {
    if (!res.headersSent) {
      res.setHeader(key, value);
    }
  }
  return headers;
}

/**
 * Always answer CORS preflight with HTTP 200 before any route/datastore work.
 * Browsers reject non-2xx OPTIONS even when Allow-* headers are present.
 * Use writeHead so Vercel/@vercel/node commits status+headers in one shot.
 */
function handleCorsPreflight(req, res) {
  if (String(req.method || '').toUpperCase() !== 'OPTIONS') {
    applyCorsHeaders(req, res);
    return false;
  }
  if (res.headersSent || res.writableEnded) {
    return true;
  }
  res.writeHead(200, {
    ...corsHeaders(req),
    'Content-Length': '0',
  });
  res.end();
  return true;
}

function authError(res, statusCode, message) {
  const headers = corsHeaders(res.req || { headers: {} });
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
