# Vercel environment setup — AlMenuPro

## Backend project (`almenupro-backend`)

**Node.js:** use **22.x** (see root `package.json` `engines` and `.nvmrc`). In Vercel → Settings → General → Node.js Version, select **22.x** — avoid 24.x unless you have tested `@vercel/node` on that runtime.

Add these in **Vercel → Project → Settings → Environment Variables**:

| Variable | Production value | Notes |
|---|---|---|
| `MONGODB_URI` | `mongodb+srv://...` | **Required** for persistent data on Vercel |
| `MONGODB_DB` | `almenupro` | Database name |
| `ADMIN_AUTH_SECRET` | long random string | Signs admin JWT tokens |
| `SUPER_ADMIN_USER` | `superadmin` | Platform login username |
| `SUPER_ADMIN_PASSWORD` | strong password | Platform login password |
| `SUPER_ADMIN_EMAIL` | `you@example.com` | Receives HTML alerts for every new order (any restaurant) |
| `RESEND_API_KEY` | `re_...` | Resend API key (same mail stack as signup alerts) |
| `MAIL_FROM` | `Almenupro <noreply@yourdomain.com>` | Verified sender in Resend (optional; defaults to Resend onboarding address) |

After adding `MONGODB_URI`, redeploy the backend. Check persistence:

```text
GET https://almenupro-backend-1.onrender.com/api/health
```

Expected: `"storage": "mongodb"`

## Frontend project (`almenupro-frontend`)

**Node.js:** use **22.x** (`frontend/package.json` `engines`, `frontend/.nvmrc`). Match the setting in Vercel → Settings → General → Node.js Version.

| Variable | Value | Notes |
|---|---|---|
| `API_BASE_URL` | `https://almenupro-backend-1.onrender.com/api` | Build-time only |
| `SUPER_ADMIN_USER` | `superadmin` | Optional login label default |

**Do not** add `ADMIN_AUTH_SECRET` or `SUPER_ADMIN_PASSWORD` to the frontend project — they would be exposed in the web bundle.

## MongoDB Atlas (free tier)

1. Create cluster at [mongodb.com/atlas](https://www.mongodb.com/atlas)
2. Database Access → create user with read/write
3. Network Access → allow `0.0.0.0/0` (or Vercel IP ranges)
4. Connect → Drivers → copy connection string into `MONGODB_URI`

On first deploy with MongoDB, seed data is copied automatically from bundled JSON files.

## CLI (optional)

```bash
cd backend
npx vercel env add MONGODB_URI production
npx vercel env add ADMIN_AUTH_SECRET production
npx vercel env add SUPER_ADMIN_USER production
npx vercel env add SUPER_ADMIN_PASSWORD production
npx vercel env add SUPER_ADMIN_EMAIL production
npx vercel env add RESEND_API_KEY production
npx vercel env add MAIL_FROM production
```

Redeploy both projects after setting variables.

## Super-admin new-order email

Triggered automatically in the API when an order is persisted via `dataStore.prependOrder` (guest/web/QR `POST /api/orders`) or new table POS orders (`send-kitchen` / `checkout` when not a duplicate). Uses `lib/orderNotify.js` → `lib/mailer.js` (Resend). No Firebase Cloud Function and no extra npm package.

Local dry-run (does not hit the DB):

```bash
node scripts/order-email-smoke.js
```

Requires `SUPER_ADMIN_EMAIL` and `RESEND_API_KEY` in the environment (or a local `.env` loaded by your process manager).
