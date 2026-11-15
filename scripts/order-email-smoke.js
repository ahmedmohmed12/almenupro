'use strict';

/**
 * Smoke-test super-admin new-order email without creating a DB order.
 *
 * Usage (from repo root):
 *   set SUPER_ADMIN_EMAIL=you@example.com
 *   set RESEND_API_KEY=re_...
 *   node scripts/order-email-smoke.js
 */

const { notifySuperAdminNewOrder } = require('../lib/orderNotify');

async function main() {
  const sample = {
    id: `smoke_${Date.now()}`,
    invoiceNumber: `SMOKE-${Date.now()}`,
    restaurantId: 'rest_smoke',
    restaurantName: 'مطعم تجريبي — Smoke',
    customerName: 'عميل اختبار',
    phone: '50000000',
    totalPrice: 12.5,
    orderSource: 'smoke-script',
    items: [
      { name: 'برجر', quantity: 2, unitPrice: 4, lineTotal: 8 },
      { name: 'عصير', quantity: 1, unitPrice: 1.5, lineTotal: 1.5 },
    ],
  };

  console.log('[order-email-smoke] sending sample…');
  console.log(
    '  SUPER_ADMIN_EMAIL=',
    process.env.SUPER_ADMIN_EMAIL || '(missing)',
  );
  console.log(
    '  RESEND_API_KEY=',
    process.env.RESEND_API_KEY ? '(set)' : '(missing)',
  );

  const result = await notifySuperAdminNewOrder(sample);
  console.log('[order-email-smoke] result:', result);
  if (!result?.sent) {
    process.exitCode = 1;
  }
}

main().catch((error) => {
  console.error('[order-email-smoke] failed:', error);
  process.exitCode = 1;
});
