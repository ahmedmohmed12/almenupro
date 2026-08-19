# AlMenuPro

Restaurant menu + admin/POS Flutter app with a Node API (`apiServer.js`) deployed on Vercel.

## Cursor Cloud specific instructions

- API entry is repo-root `apiServer.js` (`npm start` / Vercel `@vercel/node`). Export is `vercelHandler`, which answers **OPTIONS with HTTP 200** before any route or Mongo work.
- CORS headers on every response: `Access-Control-Allow-Origin: *`, methods including `GET, POST, PUT, PATCH, DELETE, OPTIONS`, headers including `Content-Type, Authorization, X-Restaurant-Id` / `x-restaurant-id` (`lib/adminAuth.js` + `vercel.json`).
- Flutter Web sends `Content-Type: application/json` on GETs and may send `Authorization` + `X-Restaurant-Id`, so preflight is required. Do not add work before the OPTIONS short-circuit or browsers will block `https://almenupro-backend.vercel.app/api/...`.
- If `MONGODB_URI` is missing or Mongo auth fails, `lib/dataStore.js` falls back to bundled JSON under `data/` (in-memory on Vercel). Do not return 503 from init for API routes; keep `GET /api/health` and `GET /api/items` available.
- Local API smoke: `node scripts/cors-smoke.js` (OPTIONS 200 + `GET /api/items` array).
