# AlMenuPro

Restaurant menu + admin/POS Flutter app with a Node API (`apiServer.js`) deployed on Vercel.

## Cursor Cloud specific instructions

- API entry is repo-root `apiServer.js` (`npm start`). Vercel rewrites `/api/*` and `/og/*` to this file.
- CORS preflight (`OPTIONS`) is answered with **HTTP 200** in `handleCorsPreflight` **before** datastore/Mongo init. Do not add work before that branch or browsers will fail Flutter Web (`ClientException` / blocked `https://almenupro-backend.vercel.app/api/items`).
- Flutter Web sends `Content-Type: application/json` on GETs and may send `Authorization` + `X-Restaurant-Id`, so preflight is required. Allowed headers live in `lib/adminAuth.js` and `vercel.json`.
- If `MONGODB_URI` is missing or Mongo auth fails, `lib/dataStore.js` falls back to bundled JSON under `data/` (in-memory on Vercel). `GET /api/health` should still return `{ ok: true }` rather than 503.
- Local API smoke: `node scripts/cors-smoke.js` (OPTIONS 200 + `GET /api/items` array). Standard Flutter commands remain `flutter analyze`, `flutter test`, and `flutter run -d web-server` / `flutter build web`.
