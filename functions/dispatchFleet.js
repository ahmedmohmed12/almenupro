'use strict';

const admin = require('firebase-admin');

const FLEET_NOTIFY_LIMIT = 5;

function toNum(value, fallback = NaN) {
  const n = Number(value);
  return Number.isFinite(n) ? n : fallback;
}

function geoFromDriver(raw) {
  if (!raw) return null;
  if (typeof raw.latitude === 'number' && typeof raw.longitude === 'number') {
    return { lat: raw.latitude, lng: raw.longitude };
  }
  const lat = toNum(raw.lat ?? raw.latitude, NaN);
  const lng = toNum(raw.lng ?? raw.longitude, NaN);
  if (Number.isFinite(lat) && Number.isFinite(lng)) return { lat, lng };
  if (raw.geopoint && typeof raw.geopoint.latitude === 'number') {
    return { lat: raw.geopoint.latitude, lng: raw.geopoint.longitude };
  }
  return null;
}

function haversineKm(a, b) {
  if (!a || !b) return null;
  const R = 6371;
  const dLat = ((b.lat - a.lat) * Math.PI) / 180;
  const dLng = ((b.lng - a.lng) * Math.PI) / 180;
  const s =
    Math.sin(dLat / 2) ** 2 +
    Math.cos((a.lat * Math.PI) / 180) * Math.cos((b.lat * Math.PI) / 180) * Math.sin(dLng / 2) ** 2;
  return 2 * R * Math.asin(Math.min(1, Math.sqrt(s)));
}

function regionKey(value) {
  return String(value || '')
    .trim()
    .toLowerCase()
    .replace(/\s+/g, '_');
}

function driverCoversRegion(data, regionId, regionName) {
  if (!regionId && !regionName) return false;
  const map = data.assigned_regions && typeof data.assigned_regions === 'object' && !Array.isArray(data.assigned_regions)
    ? data.assigned_regions
    : null;
  const aliases = new Set(
    [regionKey(regionId), regionKey(regionName), ...regionKey(regionId).split(/[_\-/]/)].filter(
      (part) => part.length > 1,
    ),
  );
  if (map) {
    return Object.entries(map).some(([key, on]) => {
      if (on !== true) return false;
      const normalized = regionKey(key);
      return aliases.has(normalized) || [...aliases].some((alias) => alias.includes(normalized) || normalized.includes(alias));
    });
  }
  const list = Array.isArray(data.allowed_delivery_regions)
    ? data.allowed_delivery_regions.map(regionKey)
    : [];
  if (!list.length) return false;
  return list.some(
    (entry) => aliases.has(entry) || [...aliases].some((alias) => alias.includes(entry) || entry.includes(alias)),
  );
}

function restaurantOrigin(data) {
  return geoFromDriver(data.restaurant_location || data.restaurantLocation);
}

async function dispatchSharedFleet(payload = {}) {
  if (!admin.apps.length) {
    admin.initializeApp();
  }
  const db = admin.firestore();
  const regionId = String(
    payload.destination_region_id || payload.destinationRegionId || payload.region_id || payload.regionId || '',
  ).trim();
  const regionName = String(payload.region_name || payload.regionName || '').trim();
  const origin = restaurantOrigin(payload);
  const snapshot = await db.collection('drivers').get();
  const ranked = [];
  snapshot.forEach((doc) => {
    const data = doc.data() || {};
    if (data.is_online !== true || data.is_busy === true) return;
    if (!driverCoversRegion(data, regionId, regionName)) return;
    const loc = geoFromDriver(data.current_location);
    ranked.push({
      id: doc.id,
      token: String(data.fcm_token || '').trim(),
      km: haversineKm(origin, loc),
    });
  });
  ranked.sort((a, b) => {
    if (a.km == null && b.km == null) return 0;
    if (a.km == null) return 1;
    if (b.km == null) return -1;
    return a.km - b.km;
  });
  const top = ranked.slice(0, FLEET_NOTIFY_LIMIT);
  const requestId = String(payload.id || payload.request_id || '');
  const fee = String(payload.driver_fee ?? payload.driverFee ?? '');
  const title = 'طلب توصيل جديد';
  const body = [fee ? `ربحك ${fee} د.ك` : 'طلب جديد بانتظارك', regionName]
    .filter(Boolean)
    .join(' — ');
  const messages = top
    .filter((row) => row.token)
    .map((row) => ({
      token: row.token,
      notification: { title, body: body || 'افتح التطبيق لاستلام الطلب' },
      android: {
        priority: 'high',
        ttl: 45000,
        notification: {
          channelId: 'driver_incoming_jobs_v2',
          sound: 'driver_ringtone',
          defaultVibrateTimings: true,
          visibility: 'PUBLIC',
          priority: 'max',
        },
      },
      apns: {
        headers: { 'apns-priority': '10', 'apns-push-type': 'alert' },
        payload: {
          aps: {
            alert: { title, body: body || 'افتح التطبيق لاستلام الطلب' },
            sound: 'driver_ringtone.wav',
            contentAvailable: true,
          },
        },
      },
      data: {
        type: 'driver_job',
        request_id: requestId,
        driver_fee: fee,
        region_name: regionName,
        destination_region_id: regionId,
      },
    }));
  if (messages.length) {
    await admin.messaging().sendEach(messages);
  }
  if (requestId) {
    await db.collection('delivery_requests').doc(requestId).set(
      {
        notified_driver_ids: top.map((row) => row.id),
        destination_region_id: regionId,
        status: payload.status || 'pending',
        updated_at: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
  }
  return { notified: top.map((row) => row.id) };
}

module.exports = { dispatchSharedFleet, FLEET_NOTIFY_LIMIT };
