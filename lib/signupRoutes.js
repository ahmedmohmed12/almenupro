'use strict';

const { validateSignupPayload, normalizeSignupRequest } = require('./signupStore');
const { isValidEmail, sendSignupNotification } = require('./mailer');

const recentByIp = new Map();

function clientIp(req) {
  const forwarded = String(req.headers['x-forwarded-for'] || '')
    .split(',')[0]
    .trim();
  return forwarded || req.socket?.remoteAddress || 'unknown';
}

function rateLimited(ip) {
  const now = Date.now();
  const windowMs = 10 * 60 * 1000;
  const stamps = (recentByIp.get(ip) || []).filter((t) => now - t < windowMs);
  if (stamps.length >= 5) {
    recentByIp.set(ip, stamps);
    return true;
  }
  stamps.push(now);
  recentByIp.set(ip, stamps);
  return false;
}

function platformFromSettings(settings) {
  const platform = settings && typeof settings.platform === 'object' ? settings.platform : {};
  return {
    signupNotificationEmail: String(platform.signupNotificationEmail || '').trim(),
  };
}

async function handleSignupRoutes(req, res, url, deps) {
  const {
    readBody,
    sendJson,
    requireAuth,
    isSuperAdmin,
    authError,
    parseJson,
    readSignupRequests,
    writeSignupRequests,
    readSettingsMap,
    writeSettingsMap,
  } = deps;

  if (
    (url.pathname === '/api/public/signup-requests' || url.pathname === '/api/signup-requests') &&
    req.method === 'POST'
  ) {
    if (rateLimited(clientIp(req))) {
      sendJson(res, 429, { error: 'محاولة كثيرة. حاول بعد قليل.' });
      return true;
    }
    try {
      const body = parseJson(await readBody(req));
      const record = validateSignupPayload(body);
      const list = await readSignupRequests();
      const duplicate = list.some(
        (row) =>
          String(row.email).toLowerCase() === record.email &&
          Date.now() - new Date(row.createdAt).getTime() < 24 * 60 * 60 * 1000,
      );
      if (duplicate) {
        sendJson(res, 409, { error: 'تم إرسال طلب بهذا البريد خلال 24 ساعة' });
        return true;
      }
      const settings = await readSettingsMap();
      const platform = platformFromSettings(settings);
      const mail = await sendSignupNotification({
        to: platform.signupNotificationEmail,
        request: record,
      });
      record.emailSent = Boolean(mail.sent);
      record.emailError = mail.sent ? '' : (mail.reasonAr || mail.reason || '');
      list.unshift(record);
      await writeSignupRequests(list.slice(0, 500));
      sendJson(res, 201, {
        ok: true,
        id: record.id,
        emailSent: record.emailSent,
        emailError: record.emailError,
        message: 'تم إرسال الطلب. سنتواصل معك قريباً.',
      });
    } catch (error) {
      sendJson(res, error.code || 400, { error: error.message || 'تعذر إرسال الطلب' });
    }
    return true;
  }

  if (!url.pathname.startsWith('/api/signup-requests') && url.pathname !== '/api/platform-settings') {
    return false;
  }

  if (url.pathname === '/api/platform-settings' && req.method === 'GET') {
    const auth = requireAuth(req, res);
    if (!auth) return true;
    if (!isSuperAdmin(auth)) {
      authError(res, 403, 'Super admin required');
      return true;
    }
    const platform = platformFromSettings(await readSettingsMap());
    sendJson(res, 200, platform);
    return true;
  }

  if (url.pathname === '/api/platform-settings' && req.method === 'PATCH') {
    const auth = requireAuth(req, res);
    if (!auth) return true;
    if (!isSuperAdmin(auth)) {
      authError(res, 403, 'Super admin required');
      return true;
    }
    try {
      const body = parseJson(await readBody(req));
      const email = String(body.signupNotificationEmail || '').trim();
      if (email && !isValidEmail(email)) {
        sendJson(res, 400, { error: 'بريد الإشعارات غير صالح' });
        return true;
      }
      const settings = await readSettingsMap();
      const next = {
        ...settings,
        platform: {
          ...(settings.platform && typeof settings.platform === 'object' ? settings.platform : {}),
          signupNotificationEmail: email,
          updatedAt: new Date().toISOString(),
        },
      };
      await writeSettingsMap(next);
      sendJson(res, 200, platformFromSettings(next));
    } catch (error) {
      sendJson(res, 400, { error: error.message || 'تعذر حفظ إعدادات المنصة' });
    }
    return true;
  }

  if (url.pathname === '/api/signup-requests' && req.method === 'GET') {
    const auth = requireAuth(req, res);
    if (!auth) return true;
    if (!isSuperAdmin(auth)) {
      authError(res, 403, 'Super admin required');
      return true;
    }
    const list = await readSignupRequests();
    sendJson(res, 200, {
      requests: list,
      pendingCount: list.filter((row) => row.status === 'new').length,
    });
    return true;
  }

  const match = url.pathname.match(/^\/api\/signup-requests\/([^/]+)$/);
  if (match && req.method === 'PATCH') {
    const auth = requireAuth(req, res);
    if (!auth) return true;
    if (!isSuperAdmin(auth)) {
      authError(res, 403, 'Super admin required');
      return true;
    }
    const id = decodeURIComponent(match[1]);
    try {
      const body = parseJson(await readBody(req));
      const list = await readSignupRequests();
      const index = list.findIndex((row) => String(row.id) === id);
      if (index < 0) {
        sendJson(res, 404, { error: 'الطلب غير موجود' });
        return true;
      }
      if (body.markEmailSent === true) {
        list[index] = normalizeSignupRequest({
          ...list[index],
          emailSent: true,
          emailError: '',
          updatedAt: new Date().toISOString(),
        });
        await writeSignupRequests(list);
        sendJson(res, 200, list[index]);
        return true;
      }
      if (body.resendEmail === true) {
        const settings = await readSettingsMap();
        const platform = platformFromSettings(settings);
        const mail = await sendSignupNotification({
          to: platform.signupNotificationEmail,
          request: list[index],
        });
        list[index] = normalizeSignupRequest({
          ...list[index],
          emailSent: Boolean(mail.sent),
          emailError: mail.sent ? '' : (mail.reasonAr || mail.reason || ''),
          updatedAt: new Date().toISOString(),
        });
        await writeSignupRequests(list);
        sendJson(res, 200, list[index]);
        return true;
      }
      const nextStatus = String(body.status || list[index].status).toLowerCase();
      list[index] = normalizeSignupRequest({
        ...list[index],
        status: nextStatus,
        updatedAt: new Date().toISOString(),
      });
      await writeSignupRequests(list);
      sendJson(res, 200, list[index]);
    } catch (error) {
      sendJson(res, 400, { error: error.message || 'تعذر تحديث الطلب' });
    }
    return true;
  }

  return false;
}

module.exports = { handleSignupRoutes };
