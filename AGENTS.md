# AlMenuPro

Restaurant menu + admin/POS Flutter app with a Node API (`apiServer.js`) deployed on Vercel.

## Cursor Cloud specific instructions

- API entry is repo-root `apiServer.js` (`npm start` / Vercel `@vercel/node`). Export is `vercelHandler`, which answers **OPTIONS with HTTP 200** via `writeHead` **before** any route or Mongo work.
- CORS reflects allowed browser origins (no `*` and no `Access-Control-Allow-Credentials`). Production dashboard origin: `https://almenupro-dashboard-2026-gfwn0j6x9-almenupro.vercel.app`. Extra origins: `CORS_ALLOWED_ORIGINS` (comma-separated) or `*-almenupro.vercel.app` previews.
- Allowed methods: `GET, POST, PUT, PATCH, DELETE, OPTIONS`. Allowed headers: `Content-Type, Authorization, X-Restaurant-Id, X-Requested-With`.
- Flutter Web sends `Content-Type: application/json` on GETs plus `Authorization` / `X-Restaurant-Id`, so preflight is required. Do not add work before the OPTIONS short-circuit.
- If `MONGODB_URI` is missing or Mongo auth fails, `lib/dataStore.js` falls back to bundled JSON under `data/` (in-memory on Vercel). Do not return 503 from init for API routes.
- The production alias `https://almenupro-backend.vercel.app` can lag behind a working deployment URL. After CORS changes, confirm the **alias** OPTIONS is 200, not only the `*.vercel.app` deployment URL.
- Local API smoke: `node scripts/cors-smoke.js`.
