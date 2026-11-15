'use strict';

const KUWAIT_TIME_ZONE = 'Asia/Kuwait';

function kuwaitDateKey(value = new Date()) {
  const date = value instanceof Date ? value : new Date(value);
  if (Number.isNaN(date.getTime())) return '';
  const parts = new Intl.DateTimeFormat('en-CA', {
    timeZone: KUWAIT_TIME_ZONE,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).formatToParts(date);
  const pick = (type) => parts.find((part) => part.type === type)?.value || '';
  return `${pick('year')}-${pick('month')}-${pick('day')}`;
}

function orderDateKey(value) {
  const text = String(value ?? '').trim();
  if (/^\d{4}-\d{2}-\d{2}$/.test(text)) return text;
  const dmy = text.match(/^(\d{1,2})[./-](\d{1,2})[./-](\d{4})(?:\s|$)/);
  if (dmy && !text.includes('T')) {
    return `${dmy[3]}-${dmy[2].padStart(2, '0')}-${dmy[1].padStart(2, '0')}`;
  }
  return kuwaitDateKey(value);
}

function isKuwaitToday(value, now = new Date()) {
  const key = orderDateKey(value);
  return Boolean(key && key === orderDateKey(now));
}

module.exports = { isKuwaitToday, kuwaitDateKey, orderDateKey, KUWAIT_TIME_ZONE };
