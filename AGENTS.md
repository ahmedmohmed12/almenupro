# AlMenuPro

Restaurant menu + admin/POS Flutter app with a Node API (`apiServer.js`). Configure Flutter web via `--dart-define=API_BASE_URL=…/api` (build: `npm run build:frontend`). Legacy default in Dart: `https://backend.u-menus.com/api`.

**Deploy targets:** API on **Railway** (`npm start`, `HOST=0.0.0.0`, `railway.toml` / `Procfile`); static site on **Cloudflare Pages** (`frontend/dist`, `_redirects`, `wrangler pages deploy`).

## Cursor Cloud specific instructions

- API entry is repo-root `apiServer.js` (`npm start` / Render / Vercel `@vercel/node`). Export is `vercelHandler`, which answers **OPTIONS with HTTP 200** via `writeHead` **before** any route or Mongo work.
- `GET /` and `GET /api` return `{ ok, message, service, version }` from `package.json` without touching Mongo (use for Render health checks).
- CORS (`lib/adminAuth.js`) always allows `*.pages.dev`; also `FRONTEND_URL`, `FRONTEND_ORIGIN`, and `ALLOWED_ORIGINS`. Unless `STRICT_CORS=1`, other `http:`/`https:` Origins are still reflected (Bearer auth, no credentials). Missing Origin → `Access-Control-Allow-Origin: *`.
- Allowed methods: `GET, POST, PUT, PATCH, DELETE, OPTIONS`. Allowed headers: `Content-Type, Authorization, X-Restaurant-Id, X-Requested-With`.
- Flutter Web sends `Content-Type: application/json` on GETs plus `Authorization` / `X-Restaurant-Id`, so preflight is required. Do not add work before the OPTIONS short-circuit.
- If `MONGODB_URI` is missing or Mongo auth fails, `lib/dataStore.js` falls back to bundled JSON under `data/` (in-memory on Vercel). Do not return 503 from init for API routes.
- Local API smoke: `node scripts/cors-smoke.js`.
- **Vercel Node runtime:** pin **22.x** via root `package.json` `engines` and `.nvmrc`. In Vercel → Project → Settings → General → Node.js Version, choose **22.x** (not 24.x) to clear runtime warnings on `@vercel/node`.
