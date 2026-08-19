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
```

Redeploy both projects after setting variables.
