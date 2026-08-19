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
      path: '/api/items?restaurant_id=rest_molton&limit=40&lite=1',
      headers: {
        Origin: DASHBOARD_ORIGIN,
        'Content-Type': 'application/json',
        'X-Restaurant-Id': 'rest_molton',
      },
    });
    assert(items.status === 200, `GET /api/items expected 200, got ${items.status} ${items.body}`);
    const parsedRaw = JSON.parse(items.body);
    const parsed = Array.isArray(parsedRaw) ? parsedRaw : parsedRaw.items;
    assert(Array.isArray(parsed), 'GET /api/items should return a JSON array or {items}');
    assert(parsed.length > 0, 'GET /api/items should return seeded menu items');
    assert(
      !JSON.stringify(parsed).includes('data:image'),
      'Items payload must not include base64 images',
    );
    assert(
      items.headers['access-control-allow-origin'] === '*' ||
        items.headers['access-control-allow-origin'] === DASHBOARD_ORIGIN,
      'GET /api/items missing CORS origin header',
    );

    const health = await request(port, {
      method: 'GET',
      path: '/api/health',
      headers: { Origin: DASHBOARD_ORIGIN },
    });
    assert(health.status === 200, `GET /api/health expected 200, got ${health.status}`);
    const healthBody = JSON.parse(health.body);
    assert(healthBody.ok === true, 'health.ok should be true');

    const root = await request(port, {
      method: 'GET',
      path: '/',
      headers: { Origin: 'https://external-client.example.com' },
    });
    assert(root.status === 200, `GET / expected 200, got ${root.status} ${root.body}`);
    const rootBody = JSON.parse(root.body);
    assert(rootBody.ok === true, 'root.ok should be true');
    assert(rootBody.version, 'root.version should be set');
    assert(
      root.headers['access-control-allow-origin'] === 'https://external-client.example.com',
      `GET / should reflect external Origin, got ${root.headers['access-control-allow-origin']}`,
    );

    const apiRoot = await request(port, {
      method: 'GET',
      path: '/api',
      headers: { Origin: DASHBOARD_ORIGIN },
    });
    assert(apiRoot.status === 200, `GET /api expected 200, got ${apiRoot.status} ${apiRoot.body}`);
    const apiRootBody = JSON.parse(apiRoot.body);
    assert(apiRootBody.ok === true, 'GET /api ok should be true');
    assert(apiRootBody.version, 'GET /api version should be set');

    const externalPreflight = await request(port, {
      method: 'OPTIONS',
      path: '/api/health',
      headers: {
        Origin: 'https://app.onrender.com',
        'Access-Control-Request-Method': 'GET',
        'Access-Control-Request-Headers': 'content-type,authorization',
      },
    });
    assert(externalPreflight.status === 200, `external OPTIONS expected 200, got ${externalPreflight.status}`);
    assert(
      externalPreflight.headers['access-control-allow-origin'] === 'https://app.onrender.com',
      `external OPTIONS should reflect Origin, got ${externalPreflight.headers['access-control-allow-origin']}`,
    );

    const login = await request(port, {
      method: 'POST',
      path: '/api/auth/login',
      headers: { 'Content-Type': 'application/json', Origin: DASHBOARD_ORIGIN },
      body: JSON.stringify({ username: 'superadmin', password: 'almenupro2026' }),
    });
    assert(login.status === 200, `login expected 200, got ${login.status} ${login.body}`);
    const session = JSON.parse(login.body);
    assert(session.token && session.role === 'super_admin', 'login should return super_admin token');

    const invoiceNumber = `test_${Date.now()}`;
    const createOrder = await request(port, {
      method: 'POST',
      path: '/api/orders',
      headers: {
        'Content-Type': 'application/json',
        Origin: 'https://almenupro.vercel.app',
      },
      body: JSON.stringify({
        restaurantId: 'rest_molton',
        restaurant_id: 'rest_molton',
        customerName: 'اختبار السلة',
        phone: '96550000000',
        address: 'حولي، قطعة 1، شارع 2، منزل 3',
        paymentMethod: 'كاش',
        invoiceNumber,
        orderType: 'delivery',
        status: 'pending',
        orderSource: 'customer_web',
        totalPrice: 7.5,
        items: [
          {
            menuItemId: '1',
            name: 'كوكيز اختبار',
            unitPrice: 7.5,
            quantity: 1,
            selectedOptions: [],
          },
        ],
      }),
    });
    assert(
      createOrder.status === 201,
      `POST /api/orders expected 201, got ${createOrder.status} ${createOrder.body}`,
    );
    const created = JSON.parse(createOrder.body);
    assert(created.id, 'created order should have an id');
    assert(created.status === 'pending', 'created order should be pending');
    assert(
      created.restaurantId === 'rest_molton' || created.restaurant_id === 'rest_molton',
      'created order should be scoped to rest_molton',
    );
    assert(Array.isArray(created.items) && created.items.length === 1, 'created order should keep items');

    const listed = await request(port, {
      method: 'GET',
      path: '/api/orders?restaurant_id=rest_molton',
      headers: {
        Origin: 'https://almenupro.vercel.app',
        'Content-Type': 'application/json',
        Authorization: `Bearer ${session.token}`,
        'X-Restaurant-Id': 'rest_molton',
      },
    });
    assert(
      listed.status === 200,
      `GET /api/orders expected 200, got ${listed.status} ${listed.body}`,
    );
    const orders = JSON.parse(listed.body);
    assert(Array.isArray(orders), 'GET /api/orders should return an array');
    const found = orders.find((order) => String(order.id) === String(created.id));
    assert(found, 'admin GET /api/orders should include the newly created order');
    assert(found.customerName === 'اختبار السلة', 'admin order should keep customer name');

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
          createdOrderId: created.id,
          adminSawOrder: true,
          root: rootBody,
          apiRoot: apiRootBody,
          externalAllowOrigin: externalPreflight.headers['access-control-allow-origin'],
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
