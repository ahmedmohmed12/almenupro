'use strict';

const { randomUUID } = require('crypto');

function slugify(value) {
  return String(value || '')
    .trim()
    .toLowerCase()
    .replace(/\s+/g, '-')
    .replace(/[^a-z0-9-]/g, '')
    .replace(/-+/g, '-')
    .replace(/^-|-$/g, '')
    .slice(0, 48);
}

function normalizePhone(raw, countryCode = '965') {
  const digits = String(raw || '').replace(/\D/g, '');
  const code = String(countryCode || '965').replace(/\D/g, '') || '965';
  if (!digits) return '';
  if (digits.startsWith(code)) return `+${digits}`;
  return `+${code}${digits}`;
}

function normalizeSignupRequest(raw = {}) {
  const createdAt = raw.createdAt || raw.created_at || new Date().toISOString();
  const statusRaw = String(raw.status || 'new').toLowerCase();
  const status = ['new', 'read', 'accepted', 'rejected'].includes(statusRaw)
    ? statusRaw
    : 'new';
  return {
    id: String(raw.id || `sig_${randomUUID()}`),
    ownerName: String(raw.ownerName || raw.name || '').trim().slice(0, 120),
    email: String(raw.email || '').trim().toLowerCase().slice(0, 160),
    phone: normalizePhone(raw.phone || raw.mobile, raw.countryCode || raw.country_code),
    restaurantName: String(raw.restaurantName || raw.storeName || '').trim().slice(0, 120),
    slug: slugify(raw.slug || raw.storeDirectory || raw.restaurantName),
    instagram: String(raw.instagram || '').trim().replace(/^@/, '').slice(0, 80),
    status,
    createdAt,
    updatedAt: raw.updatedAt || raw.updated_at || createdAt,
    emailSent: Boolean(raw.emailSent),
    emailError: String(raw.emailError || '').trim().slice(0, 240),
  };
}

function validateSignupPayload(body = {}) {
  const record = normalizeSignupRequest(body);
  if (record.ownerName.length < 2) throw Object.assign(new Error('الاسم مطلوب'), { code: 400 });
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(record.email)) {
    throw Object.assign(new Error('البريد الإلكتروني غير صالح'), { code: 400 });
  }
  if (record.phone.replace(/\D/g, '').length < 8) {
    throw Object.assign(new Error('رقم الموبايل غير صالح'), { code: 400 });
  }
  if (record.restaurantName.length < 2) {
    throw Object.assign(new Error('اسم المطعم مطلوب'), { code: 400 });
  }
  if (record.slug.length < 2) {
    throw Object.assign(new Error('دليل المتجر (بالإنجليزية) مطلوب'), { code: 400 });
  }
  if (body.terms !== true && body.acceptedTerms !== true && body.agree !== true) {
    throw Object.assign(new Error('يجب الموافقة على الشروط والأحكام'), { code: 400 });
  }
  return record;
}

module.exports = {
  slugify,
  normalizeSignupRequest,
  validateSignupPayload,
};
