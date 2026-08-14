'use strict';

const http = require('http');
const handler = require('../apiServer');

const DASHBOARD_ORIGIN =
  'https://almenupro-dashboard-2026-gfwn0j6x9-almenupro.vercel.app';

function request(port, { method, path, headers = {}, body }) {
  return new Promise((resolve, reject) => {
    const req = http.request(
      {
        hostname: '127.0.0.1',
        port,
        method,
        path,
        headers,
      },
      (res) => {
        const chunks = [];
        res.on('data', (chunk) => chunks.push(chunk));
        res.on('end', () => {
          resolve({
            status: res.statusCode,
            headers: res.headers,
            body: Buffer.concat(chunks).toString('utf8'),
          });
        });
      },
    );
    req.on('error', reject);
    if (body) req.write(body);
    req.end();
  });
}

function assert(condition, message) {
  if (!condition) {
    throw new Error(message);
  }
}

async function main() {
  delete process.env.MONGODB_URI;
  process.env.MONGODB_URI = '';

  const server = http.createServer(handler);
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  const { port } = server.address();

  try {
    const preflightStarted = Date.now();
    const preflight = await request(port, {
      method: 'OPTIONS',
      path: '/api/items?restaurant_id=rest_molton',
      headers: {
        Origin: DASHBOARD_ORIGIN,
        'Access-Control-Request-Method': 'GET',
        'Access-Control-Request-Headers':
          'content-type,authorization,x-restaurant-id,x-requested-with',
      },
    });
    const preflightMs = Date.now() - preflightStarted;

    assert(preflight.status === 200, `OPTIONS expected 200, got ${preflight.status}`);
    assert(
      preflight.headers['access-control-allow-origin'] === DASHBOARD_ORIGIN,
      `Allow-Origin should echo dashboard origin, got ${preflight.headers['access-control-allow-origin']}`,
    );
    assert(
      String(preflight.headers['access-control-allow-methods'] || '').includes('GET') &&
        String(preflight.headers['access-control-allow-methods'] || '').includes('DELETE'),
      'Allow-Methods should include GET and DELETE',
    );
    const allowHeaders = String(preflight.headers['access-control-allow-headers'] || '').toLowerCase();
    assert(allowHeaders.includes('authorization'), 'Allow-Headers should include Authorization');
    assert(allowHeaders.includes('x-restaurant-id'), 'Allow-Headers should include X-Restaurant-Id');
    assert(allowHeaders.includes('x-requested-with'), 'Allow-Headers should include X-Requested-With');
    assert(preflightMs < 1500, `OPTIONS should not wait on datastore (${preflightMs}ms)`);

    const items = await request(port, {
      method: 'GET',
      path: '/api/items?restaurant_id=rest_molton',
      headers: {
        Origin: DASHBOARD_ORIGIN,
        'Content-Type': 'application/json',
        'X-Restaurant-Id': 'rest_molton',
      },
    });
    assert(items.status === 200, `GET /api/items expected 200, got ${items.status} ${items.body}`);
    const parsed = JSON.parse(items.body);
    assert(Array.isArray(parsed), 'GET /api/items should return a JSON array');
    assert(parsed.length > 0, 'GET /api/items should return seeded menu items');
    assert(
      items.headers['access-control-allow-origin'] === DASHBOARD_ORIGIN,
      `GET Allow-Origin should echo dashboard origin, got ${items.headers['access-control-allow-origin']}`,
    );

    const health = await request(port, {
      method: 'GET',
      path: '/api/health',
      headers: { Origin: DASHBOARD_ORIGIN },
    });
    assert(health.status === 200, `GET /api/health expected 200, got ${health.status}`);
    const healthBody = JSON.parse(health.body);
    assert(healthBody.ok === true, 'health.ok should be true');

    const login = await request(port, {
      method: 'POST',
      path: '/api/auth/login',
      headers: { 'Content-Type': 'application/json', Origin: DASHBOARD_ORIGIN },
      body: JSON.stringify({ username: 'superadmin', password: 'almenupro2026' }),
    });
    assert(login.status === 200, `login expected 200, got ${login.status} ${login.body}`);
    const session = JSON.parse(login.body);
    assert(session.token && session.role === 'super_admin', 'login should return super_admin token');

    console.log(
      JSON.stringify(
        {
          ok: true,
          optionsStatus: preflight.status,
          optionsMs: preflightMs,
          allowOrigin: preflight.headers['access-control-allow-origin'],
          itemsStatus: items.status,
          itemCount: parsed.length,
          health: healthBody,
        },
        null,
        2,
      ),
    );
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
