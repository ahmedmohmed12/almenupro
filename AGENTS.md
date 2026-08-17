# AlMenuPro

Restaurant menu + admin/POS Flutter app with a Node API (`apiServer.js`). Production API host: `https://almenupro-backend-1.onrender.com` (Flutter default `API_BASE_URL` appends `/api`).

## Cursor Cloud specific instructions

- API entry is repo-root `apiServer.js` (`npm start` / Render / Vercel `@vercel/node`). Export is `vercelHandler`, which answers **OPTIONS with HTTP 200** via `writeHead` **before** any route or Mongo work.
- `GET /` and `GET /api` return `{ ok, message, service, version }` from `package.json` without touching Mongo (use for Render health checks).
- CORS (`lib/adminAuth.js`) reflects any `http:`/`https:` `Origin` (Bearer auth, no credentials). Missing Origin → `Access-Control-Allow-Origin: *`.
- Allowed methods: `GET, POST, PUT, PATCH, DELETE, OPTIONS`. Allowed headers: `Content-Type, Authorization, X-Restaurant-Id, X-Requested-With`.
- Flutter Web sends `Content-Type: application/json` on GETs plus `Authorization` / `X-Restaurant-Id`, so preflight is required. Do not add work before the OPTIONS short-circuit.
- If `MONGODB_URI` is missing or Mongo auth fails, `lib/dataStore.js` falls back to bundled JSON under `data/` (in-memory on Vercel). Do not return 503 from init for API routes.
- Local API smoke: `node scripts/cors-smoke.js`.
