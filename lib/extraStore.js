'use strict';

const fs = require('fs');
const path = require('path');

const DATA_DIR = path.join(__dirname, '..', 'data');
const IS_VERCEL = Boolean(process.env.VERCEL);

const FILES = {
  customers: path.join(DATA_DIR, 'customers.json'),
  deliveryZones: path.join(DATA_DIR, 'delivery_zones.json'),
  staffUsers: path.join(DATA_DIR, 'staff_users.json'),
  shiftSessions: path.join(DATA_DIR, 'shift_sessions.json'),
  auditEvents: path.join(DATA_DIR, 'audit_events.json'),
  upsellEvents: path.join(DATA_DIR, 'upsell_events.json'),
};

const memory = {
  customers: [],
  deliveryZones: [],
  staffUsers: [],
  shiftSessions: [],
  auditEvents: [],
  upsellEvents: [],
};

function loadJson(filePath, fallback) {
  try {
    if (!fs.existsSync(filePath)) return fallback;
    const parsed = JSON.parse(fs.readFileSync(filePath, 'utf8'));
    return parsed ?? fallback;
  } catch {
    return fallback;
  }
}

function writeJson(filePath, value) {
  if (IS_VERCEL) return;
  const dir = path.dirname(filePath);
  if (!fs.existsSync(dir)) {
    fs.mkdirSync(dir, { recursive: true });
  }
  fs.writeFileSync(filePath, JSON.stringify(value, null, 2), 'utf8');
}

function seed() {
  memory.customers = loadJson(FILES.customers, []);
  memory.deliveryZones = loadJson(FILES.deliveryZones, []);
  memory.staffUsers = loadJson(FILES.staffUsers, []);
  memory.shiftSessions = loadJson(FILES.shiftSessions, []);
  memory.auditEvents = loadJson(FILES.auditEvents, []);
  memory.upsellEvents = loadJson(FILES.upsellEvents, []);
}

function collection(name) {
  return {
    async read() {
      if (!IS_VERCEL) {
        memory[name] = loadJson(FILES[name], memory[name] || []);
      }
      return Array.isArray(memory[name]) ? memory[name] : [];
    },
    async write(data) {
      memory[name] = Array.isArray(data) ? data : [];
      writeJson(FILES[name], memory[name]);
      return memory[name];
    },
  };
}

seed();

module.exports = {
  seed,
  customers: collection('customers'),
  deliveryZones: collection('deliveryZones'),
  staffUsers: collection('staffUsers'),
  shiftSessions: collection('shiftSessions'),
  auditEvents: collection('auditEvents'),
  upsellEvents: collection('upsellEvents'),
};
