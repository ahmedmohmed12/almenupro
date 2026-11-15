'use strict';

function isValidEmail(value) {
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(String(value || '').trim());
}

function escapeHtml(value) {
  return String(value || '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

function signupEmailText(request) {
  return [
    'طلب اشتراك جديد — المنيو برو',
    '',
    `الاسم: ${request.ownerName || ''}`,
    `البريد: ${request.email || ''}`,
    `الموبايل: ${request.phone || ''}`,
    `اسم المطعم: ${request.restaurantName || ''}`,
    `دليل المتجر: ${request.slug || ''}`,
    `إنستغرام: ${request.instagram || '—'}`,
  ].join('\n');
}

function signupEmailHtml(request) {
  const rows = [
    ['الاسم', request.ownerName],
    ['البريد', request.email],
    ['الموبايل', request.phone],
    ['اسم المطعم', request.restaurantName],
    ['دليل المتجر (slug)', request.slug],
    ['إنستغرام', request.instagram || '—'],
  ];
  const body = rows
    .map(
      ([label, value]) =>
        `<tr><td style="padding:8px 12px;border:1px solid #eadfd6;font-weight:700;color:#6B1124">${escapeHtml(label)}</td><td style="padding:8px 12px;border:1px solid #eadfd6">${escapeHtml(value)}</td></tr>`,
    )
    .join('');
  return `
    <div dir="rtl" style="font-family:Tahoma,Arial,sans-serif;background:#F7F4F1;padding:24px">
      <div style="max-width:560px;margin:0 auto;background:#fff;border-radius:16px;overflow:hidden;border:1px solid #eadfd6">
        <div style="background:#6B1124;color:#fff;padding:18px 22px;font-size:18px;font-weight:800">طلب اشتراك جديد — المنيو برو</div>
        <p style="padding:16px 22px 0;color:#444;line-height:1.8">وصل طلب من مطعم يريد الاشتراك في المنصة.</p>
        <table style="margin:12px 22px 22px;border-collapse:collapse;width:calc(100% - 44px)">${body}</table>
      </div>
    </div>
  `;
}

function formatMoney(value) {
  const n = Number(value);
  if (!Number.isFinite(n)) return '0.000';
  return n.toFixed(3);
}

function orderItemsLines(order) {
  const items = Array.isArray(order?.items) ? order.items : [];
  return items.map((item) => {
    const name =
      item?.name || item?.menuItem?.name || item?.title || 'صنف';
    const qty = Number(item?.quantity ?? item?.qty ?? 1) || 1;
    const lineTotal =
      item?.totalPrice ??
      item?.lineTotal ??
      item?.price ??
      (Number(item?.unitPrice) || 0) * qty;
    return { name: String(name), qty, lineTotal: formatMoney(lineTotal) };
  });
}

function newOrderEmailText(payload) {
  const items = orderItemsLines(payload.order)
    .map((row) => `- ${row.name} x${row.qty} = ${row.lineTotal} د.ك`)
    .join('\n');
  return [
    'طلب جديد على المنصة — المنيو برو',
    '',
    `المطعم: ${payload.restaurantName || ''}`,
    `رقم الطلب: ${payload.orderId || ''}`,
    `العميل: ${payload.customerName || ''}`,
    `الهاتف: ${payload.customerPhone || ''}`,
    `الإجمالي: ${payload.totalAmount || '0.000'} د.ك`,
    '',
    'الأصناف:',
    items || '- لا توجد أصناف',
  ].join('\n');
}

function newOrderEmailHtml(payload) {
  const metaRows = [
    ['المطعم', payload.restaurantName],
    ['رقم الطلب', payload.orderId],
    ['العميل', payload.customerName],
    ['الهاتف', payload.customerPhone],
    ['الإجمالي', `${payload.totalAmount || '0.000'} د.ك`],
    ['المصدر', payload.orderSource || '—'],
  ];
  const meta = metaRows
    .map(
      ([label, value]) =>
        `<tr><td style="padding:8px 12px;border:1px solid #eadfd6;font-weight:700;color:#6B1124;width:34%">${escapeHtml(label)}</td><td style="padding:8px 12px;border:1px solid #eadfd6">${escapeHtml(value)}</td></tr>`,
    )
    .join('');
  const itemRows = orderItemsLines(payload.order)
    .map(
      (row) =>
        `<tr><td style="padding:8px 12px;border:1px solid #eadfd6">${escapeHtml(row.name)}</td><td style="padding:8px 12px;border:1px solid #eadfd6;text-align:center">${row.qty}</td><td style="padding:8px 12px;border:1px solid #eadfd6;text-align:left">${escapeHtml(row.lineTotal)} د.ك</td></tr>`,
    )
    .join('');
  return `
    <div dir="rtl" style="font-family:Tahoma,Arial,sans-serif;background:#F7F4F1;padding:24px">
      <div style="max-width:640px;margin:0 auto;background:#fff;border-radius:16px;overflow:hidden;border:1px solid #eadfd6">
        <div style="background:#6B1124;color:#fff;padding:18px 22px;font-size:18px;font-weight:800">طلب جديد على المنصة</div>
        <p style="padding:16px 22px 0;color:#444;line-height:1.8">
          وصل طلب جديد من مطعم <strong style="color:#6B1124">${escapeHtml(payload.restaurantName || '—')}</strong>.
        </p>
        <table style="margin:12px 22px 8px;border-collapse:collapse;width:calc(100% - 44px)">${meta}</table>
        <h3 style="margin:8px 22px 0;color:#6B1124;font-size:15px">الأصناف</h3>
        <table style="margin:8px 22px 22px;border-collapse:collapse;width:calc(100% - 44px)">
          <thead>
            <tr style="background:#F7F4F1">
              <th style="padding:8px 12px;border:1px solid #eadfd6;text-align:right">الصنف</th>
              <th style="padding:8px 12px;border:1px solid #eadfd6">الكمية</th>
              <th style="padding:8px 12px;border:1px solid #eadfd6;text-align:left">السعر</th>
            </tr>
          </thead>
          <tbody>
            ${
              itemRows ||
              `<tr><td colspan="3" style="padding:10px 12px;border:1px solid #eadfd6;color:#777">لا توجد أصناف</td></tr>`
            }
          </tbody>
        </table>
      </div>
    </div>
  `;
}

function reasonAr(reason) {
  switch (String(reason || '')) {
    case 'no_recipient':
      return 'لا يوجد إيميل سوبر أدمن (SUPER_ADMIN_EMAIL)';
    case 'no_resend_key':
    case 'no_smtp':
      return 'تعذر الإرسال: عيّن RESEND_API_KEY على السيرفر';
    default:
      return reason || 'تعذر إرسال الإيميل';
  }
}

async function sendViaResend({ to, subject, html, text }) {
  const apiKey = process.env.RESEND_API_KEY || '';
  if (!apiKey) return { sent: false, reason: 'no_resend_key' };
  const from = process.env.MAIL_FROM || 'Almenupro <onboarding@resend.dev>';
  const response = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${apiKey}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ from, to: [to], subject, html, text }),
  });
  if (!response.ok) {
    const detail = (await response.text()).slice(0, 300);
    return { sent: false, reason: `resend_${response.status}`, detail };
  }
  return { sent: true, provider: 'resend' };
}

async function sendSignupNotification({ to, request }) {
  const recipient = String(to || '').trim();
  if (!isValidEmail(recipient)) {
    return {
      sent: false,
      reason: 'no_recipient',
      reasonAr: reasonAr('no_recipient'),
    };
  }
  const subject = `طلب اشتراك جديد: ${request.restaurantName || request.ownerName || 'مطعم'}`;
  const html = signupEmailHtml(request);
  const text = signupEmailText(request);
  try {
    const resend = await sendViaResend({ to: recipient, subject, html, text });
    if (resend.sent) return { ...resend, reasonAr: '' };
    return { ...resend, reasonAr: reasonAr(resend.reason) };
  } catch (error) {
    return {
      sent: false,
      reason: 'resend_failed',
      reasonAr: reasonAr('no_resend_key'),
      detail: String(error?.message || error),
    };
  }
}

/** Email the platform super-admin about any new order from any restaurant. */
async function sendNewOrderSuperAdminNotification({ to, restaurantName, order }) {
  const recipient = String(to || process.env.SUPER_ADMIN_EMAIL || '').trim();
  if (!isValidEmail(recipient)) {
    return {
      sent: false,
      reason: 'no_recipient',
      reasonAr: reasonAr('no_recipient'),
    };
  }

  const orderId =
    order?.invoiceNumber || order?.invoice_number || order?.id || '';
  const totalAmount = formatMoney(
    order?.totalPrice ?? order?.total_price ?? order?.grandTotal ?? 0,
  );
  const customerName = order?.customerName || order?.customer_name || 'عميل';
  const customerPhone = order?.phone || order?.customerPhone || '—';
  const orderSource =
    order?.orderSource || order?.order_source || order?.source || '';

  const payload = {
    restaurantName: restaurantName || order?.restaurantName || 'مطعم',
    orderId: String(orderId),
    totalAmount,
    customerName: String(customerName),
    customerPhone: String(customerPhone),
    orderSource: String(orderSource),
    order: order || {},
  };

  const subject = `طلب جديد — ${payload.restaurantName} (#${payload.orderId})`;
  const html = newOrderEmailHtml(payload);
  const text = newOrderEmailText(payload);

  try {
    const resend = await sendViaResend({ to: recipient, subject, html, text });
    if (resend.sent) {
      console.log(
        `[mailer] super-admin order email sent → ${recipient} order=${payload.orderId} restaurant=${payload.restaurantName}`,
      );
      return { ...resend, reasonAr: '', recipient };
    }
    console.warn(
      `[mailer] super-admin order email failed reason=${resend.reason} order=${payload.orderId}`,
      resend.detail || '',
    );
    return { ...resend, reasonAr: reasonAr(resend.reason), recipient };
  } catch (error) {
    console.error('[mailer] super-admin order email exception:', error);
    return {
      sent: false,
      reason: 'resend_failed',
      reasonAr: reasonAr('no_resend_key'),
      detail: String(error?.message || error),
      recipient,
    };
  }
}

module.exports = {
  isValidEmail,
  sendSignupNotification,
  sendNewOrderSuperAdminNotification,
  reasonAr,
  formatMoney,
  orderItemsLines,
};
