# Flutter Web frontend (Vercel)

Deploy this folder as a **separate Vercel project** with Root Directory = `frontend`.

## Environment variables (Vercel Project Settings)

| Variable | Required | Example |
|----------|----------|---------|
| `API_BASE_URL` | Recommended | `https://almenupro-backend.vercel.app/api` |

Passed to Flutter at build time via `--dart-define=API_BASE_URL=...`.

## Backend CORS

The Node backend (`apiServer.js`) already sends `Access-Control-Allow-Origin: *` for all API responses.

## Routes

- `/` — customer menu
- `/admin` — admin dashboard (password: see app code)
