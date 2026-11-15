# AlMenuPro Desktop

Standalone Electron shell for the Flutter POS web app and the Talabat, Jahez,
and Keeta merchant portals. It scrapes normalized orders from provider views
and submits them to AlMenuPro's existing external-order endpoint through a
persistent main-process queue.

## Setup

Requires Node.js 22 or newer.

```powershell
cd desktop
Copy-Item .env.example .env
npm install
npm start
```

Set `DESKTOP_API_TOKEN` to a cashier or administrator bearer token authorized
for `DESKTOP_RESTAURANT_ID`. Provider logins happen inside their own embedded
views; credentials are never exposed to the toolbar renderer.

## Configuration

- `DESKTOP_POS_URL`: Flutter web POS URL.
- `DESKTOP_API_URL`: API base ending in `/api`.
- `DESKTOP_RESTAURANT_ID`: restaurant scope used by partitions and API calls.
- `DESKTOP_API_TOKEN`: bearer token used only by the main-process queue.
- `DESKTOP_ENABLE_MOCK_ORDERS`: enables the localhost-only simulation endpoint.
- `DESKTOP_MOCK_PORT`, `DESKTOP_MOCK_SECRET`: protected local simulation port
  and secret. Never enable this endpoint in production.
- `DESKTOP_TALABAT_URL`, `DESKTOP_JAHEZ_URL`, `DESKTOP_KEETA_URL`: merchant
  portal entry URLs.
- `DESKTOP_*_ALLOWED_ORIGINS`: comma-separated portal and authentication
  origins allowed to navigate and emit scraper events. Add a provider's login
  origin here if its sign-in redirects to another domain.
- `DESKTOP_*_ORDER_URLS`: comma-separated, allowlisted order screens used as
  authenticated navigation fallbacks. Put the live-orders URL first and the
  order-history URL second when both exist.

Each provider uses a persistent Electron partition named from both provider and
restaurant. Changing restaurant ID creates a separate login/session store.

## Production selector maintenance

Obtain provider approval before inspecting or automating a merchant portal.
Use a test order and remove customer names, phones, addresses, cookies, tokens,
and credentials from every saved fixture.

1. Log in to the real merchant portal and keep one complete order card/detail
   visible.
2. In browser developer tools, inspect stable semantic attributes such as
   `data-testid`, `data-test`, `aria-label`, or durable element structure.
   Avoid generated class names and positional selectors such as `:nth-child`.
3. Update the corresponding file in `src/selectors/`:
   - `observationModes.live`: live-order root/card selectors when available.
   - `observationModes.history`: order-history table and row selectors. Keep
     `maxRows` small so only recent top rows are scanned.
   - `observerRoot` and `order`: backward-compatible fallback selectors.
   - `id`, `customerName`, `phone`, `address`, `subtotal`, `total`,
     `paymentMethod`, `deliveryType`, and `createdAt`: queried inside `order`.
   - `item`: repeated line item queried inside `order`.
   - `itemName`, `itemQuantity`, `itemPrice`, and `itemOptions`: queried inside
     each `item`.
4. If sign-in redirects to another trusted origin, add that exact origin to
   `DESKTOP_<PROVIDER>_ALLOWED_ORIGINS`; never use a wildcard.
   Set `DESKTOP_<PROVIDER>_ORDER_URLS` to the authenticated live/recent-order
   routes. Navigation fallback runs only after an authenticated dashboard shell
   is detected and no configured order surface exists.
5. Add a sanitized DOM-shaped fixture to `test/provider-adapters.test.js`.
   If a portal needs provider-specific parsing, override `parseOrder` or
   `parseItem` in its adapter rather than adding conditions to `BaseAdapter`.
6. Run `npm run smoke`, rebuild with `npm run dist:win`, and submit one test
   order. Confirm its external ID, items/options, total, duplicate handling,
   pending alert, acceptance, and single kitchen print.

The scraper only reads data currently rendered in the portal DOM. If a portal
loads required fields only after opening a detail drawer, obtain a permitted
stable detail view or API integration; do not add credential capture or
unrestricted page automation.

## Architecture and security

- The `BrowserWindow` renders only the local toolbar.
- A `WebContentsView` hosts the primary Flutter POS, and one isolated
  `WebContentsView` exists per provider.
- Every renderer uses `contextIsolation: true`, `sandbox: true`, and
  `nodeIntegration: false`.
- Popups, permissions, downloads, and nested webviews are denied.
- The scraper preload is bundled before launch because sandboxed Electron
  preloads cannot load arbitrary local CommonJS modules at runtime.
- Main validates the sender and every scraped field before queueing.
- Dedupe and queue state are atomically persisted under Electron `userData`.

Provider DOMs change over time. Update the external selector maps in
`src/selectors/` without changing parser logic. The adapter registry and
provider-specific adapter classes live in `src/adapters/`.

## Commands

```powershell
npm run build:preload
npm test
npm run smoke
npm run diagnose
npm start
```

## Local end-to-end test

Open three PowerShell terminals from the repository root.

Backend:

```powershell
npm install
npm start
```

Flutter POS:

```powershell
flutter pub get
flutter run -d web-server --web-port 8080 --dart-define=API_BASE_URL=http://localhost:3000/api
```

Desktop shell:

```powershell
cd desktop
Copy-Item .env.example .env
# Set DESKTOP_API_URL=http://localhost:3000/api and add a valid cashier/admin
# bearer token to DESKTOP_API_TOKEN in .env.
npm install
npm run smoke
npm start
```

The shell opens the Flutter POS at `http://localhost:8080`; use the toolbar to
switch to each provider and sign in. For a restaurant-admin token, POST the
restaurant slug and password to `http://localhost:3000/api/auth/login`, then
copy the returned `token` into `.env`. Restart Electron after changing `.env`.

## Mock order integration test

Use development only. In `desktop/.env`, set:

```env
DESKTOP_ENABLE_MOCK_ORDERS=true
DESKTOP_MOCK_PORT=17321
DESKTOP_MOCK_SECRET=replace-with-a-long-local-secret
```

Start the backend, Flutter POS, and Electron, sign into the POS, and open a
cashier shift. In a fourth terminal:

```powershell
cd desktop
npm run diagnose
npm run simulate:talabat
# Or:
npm run simulate:jahez
npm run simulate:keeta
# Full check: waits up to 25 seconds for POS confirmation.
npm run simulate:e2e:talabat
```

The command injects through Electron's localhost server, then follows the same
validator, dedupe store, persistent queue, authenticated external-order API,
and backend persistence path as a scraped order. It prints
`backendPersistence.confirmed: true` only after finding the order through the
API.
The `simulate:e2e:*` commands additionally wait for the open POS session to
auto-accept or manually accept the order and fail if its backend status does
not become `confirmed`.

The current POS does not use a WebSocket for incoming orders. Its existing
`AdminOrderMonitorService` refresh stream detects the new pending order, starts
the audio alert, and starts the 10-second auto-accept countdown. After
acceptance, `PosPrintHelper.printIncomingAcceptance` invokes the configured
kitchen print bridge. To verify the client side:

1. Keep the POS visible and confirm the pending-order badge increases.
2. Confirm the audible alert/browser notification appears.
3. Confirm the order source badge is Talabat, Jahez, or Keeta and the external
   order ID matches the CLI output.
4. Accept manually, or wait 10 seconds with an open cashier shift.
5. Confirm the order changes to `confirmed`.
6. With QZ Tray/thermal printer configured, confirm one kitchen receipt prints.
7. Run the CLI again with an explicit reused ID, for example
   `node scripts/simulate-order.js talabat MOCK-DUPE-1` twice, and confirm the
   second result reports a duplicate and no second receipt/order is created.
8. Close the cashier shift and inject another unique order. Confirm POS shows
   the no-open-shift warning and no print job is sent. Open a shift; the pending
   order can then be accepted and printed.

Example production values are `DESKTOP_POS_URL=https://u-menus.com/admin/pos`
and `DESKTOP_API_URL=https://backend.u-menus.com/api`.

## Windows package

```powershell
npm run pack
npm run dist:win
```

Artifacts are built under `desktop/release-production-current/` and exported to
`desktop/dist/windows/`. Code signing should be configured
before public distribution.

For an installed/portable build, create `.env` either beside
`AlMenuPro POS.exe` or in Electron's AlMenuPro user-data directory under
`%APPDATA%`. The user-data file takes precedence. Restart the app after
configuration changes; `.env` is deliberately not embedded in the installer.

Use scraping only where permitted by provider agreements and applicable law.
