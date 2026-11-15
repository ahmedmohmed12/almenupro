# Shared hosting — u-menus.com

Production hosts:

- Frontend: `https://u-menus.com/`
- Backend API: `https://backend.u-menus.com/`

The API uses **MySQL** (`platform_docs` JSON documents), not MongoDB.

## 1. DNS

| Host | Type | Points to |
|------|------|-----------|
| `u-menus.com` | A | shared-host IP |
| `www.u-menus.com` | CNAME or A | `u-menus.com` or same IP |
| `backend.u-menus.com` | A or CNAME | same server / Node app |

SSL: enable AutoSSL / Let's Encrypt on both hosts.

## 2. MySQL (phpMyAdmin)

1. cPanel → MySQL Databases → create database + user, grant ALL.
2. phpMyAdmin → select that database → Import.
3. Upload `data/almenupro.sql` (utf8mb4).
4. Confirm table `platform_docs` has rows (`restaurants`, `menu_items`, `orders`, …).

CLI:

```bash
mysql -u DB_USER -p DB_NAME < data/almenupro.sql
```

Regenerate the dump from bundled JSON:

```bash
node scripts/export-mysql-dump.js
```

## 3. Backend Node app (`backend.u-menus.com`)

Startup file: `apiServer.js`  
Node: 22.x if available, else 18/20.

Environment (cPanel Node / `.env` on the API app — **do not put these on the Flutter site**):

```text
MYSQL_HOST=localhost
MYSQL_PORT=3306
MYSQL_USER=cpanel_db_user
MYSQL_PASSWORD=...
MYSQL_DATABASE=cpanel_db_name
ADMIN_AUTH_SECRET=long-random-string
SUPER_ADMIN_USER=superadmin
SUPER_ADMIN_PASSWORD=strong-password
PORT=               # value assigned by the host / Passenger
```

Do **not** set `MONGODB_URI` on this host.

CORS already reflects any `http:`/`https:` Origin, so `https://u-menus.com` can call `https://backend.u-menus.com`.

Health check: `https://backend.u-menus.com/api/health`  
Expect `"storage":"mysql"` and `"persistent":true`.

## 4. Frontend (`u-menus.com`)

Build **only** with the shared-host API (not Vercel/Render):

```bash
flutter build web --release --dart-define=API_BASE_URL=https://backend.u-menus.com/api
```

Upload **contents** of `build/web` into `public_html` for `u-menus.com`.

Place this as `public_html/.htaccess` (Apache):

```apache
<IfModule mod_rewrite.c>
  RewriteEngine On
  RewriteBase /
  RewriteRule ^index\.html$ - [L]
  RewriteCond %{REQUEST_FILENAME} !-f
  RewriteCond %{REQUEST_FILENAME} !-d
  RewriteRule . /index.html [L]
</IfModule>
```

This keeps `/admin`, `/r/...`, `/menu/...` on the Flutter app.

## 5. Local test before upload

```bash
docker compose -f docker-compose.mysql.yml up -d
copy env.mysql.example .env
npm install
npm run test:mysql
npm start
```

Then `flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:3000/api`
