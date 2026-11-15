'use strict';

const crypto = require('crypto');

const CHANNEL_ID = 'driver_incoming_jobs_v2';
const PROJECT_FALLBACK = 'almenupro';

function isDriverAvailable(driver) {
  if (!driver) return false;
  const until = Date.parse(driver.suspended_until || '');
  if (Number.isFinite(until) && until > Date.now()) return false;
  const online = driver.is_online === true || driver.isOnline === true;
  const busy = driver.is_busy === true || driver.isBusy === true;
  return online && !busy;
}

function jobCopy(request) {
  const fee = String(request?.driver_fee ?? request?.driverFee ?? '').trim();
  const region = String(request?.region_name || request?.regionName || '').trim();
  const title = 'طلب توصيل جديد';
  const body = [fee ? `ربحك ${fee} د.ك` : 'طلب جديد بانتظارك', region]
    .filter(Boolean)
    .join(' — ');
  return { title, body: body || 'افتح التطبيق لاستلام الطلب' };
}

function jobData(request, extra = {}) {
  return {
    type: extra.type || 'driver_job',
    request_id: String(request?.id || request?.request_id || ''),
    order_id: String(request?.order_id || request?.orderId || ''),
    driver_fee: String(request?.driver_fee ?? request?.driverFee ?? ''),
    region_name: String(request?.region_name || request?.regionName || ''),
    destination_region_id: String(
      request?.destination_region_id || request?.region_id || request?.regionId || '',
    ),
    restaurantName: String(request?.restaurantName || request?.restaurant_name || ''),
    click_action: 'FLUTTER_NOTIFICATION_CLICK',
  };
}

async function notifyDriverJob(driver, request) {
  if (!isDriverAvailable(driver)) return;
  const token = String(driver?.fcm_token || driver?.fcmToken || '').trim();
  if (!token) return;
  const copy = jobCopy(request);
  await sendPush(token, {
    title: copy.title,
    body: copy.body,
    data: jobData(request),
  });
}

async function notifyDriverJobTaken(drivers, request, winnerId) {
  const others = (drivers || []).filter((row) => String(row.id) !== String(winnerId));
  await Promise.all(
    others.map((driver) => {
      const token = String(driver?.fcm_token || driver?.fcmToken || '').trim();
      if (!token) return Promise.resolve();
      return sendPush(token, {
        title: 'تم أخذ الطلب',
        body: 'سائق آخر قبل هذا الطلب',
        data: jobData(request, { type: 'driver_job_taken' }),
        silent: true,
      });
    }),
  );
}

function readServiceAccount() {
  const raw =
    process.env.FIREBASE_SERVICE_ACCOUNT ||
    process.env.GOOGLE_APPLICATION_CREDENTIALS_JSON ||
    '';
  if (!raw.trim()) return null;
  try {
    return JSON.parse(raw);
  } catch (_) {
    return null;
  }
}

let cachedToken = { value: '', exp: 0 };

async function googleAccessToken(sa) {
  const now = Math.floor(Date.now() / 1000);
  if (cachedToken.value && cachedToken.exp - 60 > now) return cachedToken.value;
  const header = Buffer.from(JSON.stringify({ alg: 'RS256', typ: 'JWT' })).toString('base64url');
  const claim = Buffer.from(
    JSON.stringify({
      iss: sa.client_email,
      scope: 'https://www.googleapis.com/auth/firebase.messaging',
      aud: 'https://oauth2.googleapis.com/token',
      iat: now,
      exp: now + 3600,
    }),
  ).toString('base64url');
  const signer = crypto.createSign('RSA-SHA256');
  signer.update(`${header}.${claim}`);
  const jwt = `${header}.${claim}.${signer.sign(sa.private_key, 'base64url')}`;
  const res = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: `grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=${jwt}`,
  });
  const json = await res.json();
  if (!json.access_token) return '';
  cachedToken = { value: json.access_token, exp: now + 3500 };
  return json.access_token;
}

async function sendFcmV1(sa, token, { title, body, data, silent }) {
  const access = await googleAccessToken(sa);
  if (!access) return false;
  const projectId = String(sa.project_id || process.env.FIREBASE_PROJECT_ID || PROJECT_FALLBACK);
  const message = {
    token,
    data,
    android: {
      priority: 'high',
      ttl: '45s',
    },
    apns: {
      headers: { 'apns-priority': silent ? '5' : '10', 'apns-push-type': silent ? 'background' : 'alert' },
      payload: {
        aps: silent
          ? { 'content-available': 1 }
          : {
              alert: { title, body },
              sound: 'driver_ringtone.wav',
              'content-available': 1,
            },
      },
    },
  };
  if (!silent) {
    message.notification = { title, body };
    message.android.notification = {
      channelId: CHANNEL_ID,
      sound: 'driver_ringtone',
      notificationCount: 1,
      defaultVibrateTimings: true,
      visibility: 'PUBLIC',
      priority: 'max',
    };
  }
  const res = await fetch(`https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${access}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ message }),
  });
  return res.ok;
}

async function sendLegacyFcm(key, token, { title, body, data, silent }) {
  const payload = {
    to: token,
    priority: 'high',
    content_available: true,
    data,
    android: { priority: 'high' },
  };
  if (!silent) {
    payload.notification = {
      title,
      body,
      sound: 'driver_ringtone',
      android_channel_id: CHANNEL_ID,
      channel_id: CHANNEL_ID,
      click_action: 'FLUTTER_NOTIFICATION_CLICK',
    };
  }
  const res = await fetch('https://fcm.googleapis.com/fcm/send', {
    method: 'POST',
    headers: {
      Authorization: `key=${key}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(payload),
  });
  return res.ok;
}

async function sendPush(token, payload) {
  try {
    const sa = readServiceAccount();
    if (sa) {
      const ok = await sendFcmV1(sa, token, payload);
      if (ok) return;
    }
    const key = String(process.env.FCM_SERVER_KEY || '').trim();
    if (key) await sendLegacyFcm(key, token, payload);
  } catch (_) {}
}

module.exports = { notifyDriverJob, notifyDriverJobTaken, CHANNEL_ID };
