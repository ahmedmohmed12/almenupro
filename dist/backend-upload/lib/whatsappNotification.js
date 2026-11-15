'use strict';

async function sendWhatsAppNotification({ to, messageBody, order } = {}) {
  const frontendUrl = process.env.FRONTEND_URL || 'https://frontend-six-lime-13.vercel.app';
  const orderLink = `${frontendUrl}/admin/orders/${order._id || order.id}`;
  const fullMessage = messageBody + `\n\n🔗 رابط قبول الأوردر الفوري:\n` + orderLink;

  const digits = String(to || '').replace(/\D/g, '');
  if (!digits) {
    return { ok: false, skipped: true, fullMessage, orderLink };
  }

  const token = process.env.WHATSAPP_TOKEN || process.env.WHATSAPP_ACCESS_TOKEN;
  const phoneNumberId = process.env.WHATSAPP_PHONE_NUMBER_ID;
  const webhookUrl = process.env.WHATSAPP_WEBHOOK_URL;

  if (token && phoneNumberId) {
    const response = await fetch(
      `https://graph.facebook.com/v21.0/${phoneNumberId}/messages`,
      {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${token}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          messaging_product: 'whatsapp',
          to: digits,
          type: 'text',
          text: { body: fullMessage, preview_url: true },
        }),
      },
    );
    if (!response.ok) {
      const detail = await response.text();
      throw new Error(`WhatsApp API ${response.status}: ${detail}`);
    }
    return { ok: true, fullMessage, orderLink };
  }

  if (webhookUrl) {
    const response = await fetch(webhookUrl, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        to: digits,
        message: fullMessage,
        text: fullMessage,
      }),
    });
    if (!response.ok) {
      const detail = await response.text();
      throw new Error(`WhatsApp webhook ${response.status}: ${detail}`);
    }
    return { ok: true, fullMessage, orderLink };
  }

  return { ok: false, skipped: true, fullMessage, orderLink };
}

module.exports = {
  sendWhatsAppNotification,
};
