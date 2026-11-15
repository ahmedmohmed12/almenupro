'use strict';

const fs = require('node:fs');
const path = require('node:path');

const PROVIDERS = new Set(['talabat', 'jahez', 'keeta']);

function validateProvider(value) {
  const provider = String(value || '').trim().toLowerCase();
  if (!PROVIDERS.has(provider)) throw new Error('Unsupported vendor provider');
  return provider;
}

function validateVendorId(value) {
  const vendorId = String(value || '').trim();
  if (!/^[A-Za-z0-9_.:-]{1,100}$/.test(vendorId)) {
    throw new Error('Vendor ID contains unsupported characters');
  }
  return vendorId;
}

class VendorCredentialStore {
  constructor({ filePath, safeStorage }) {
    if (!filePath || !safeStorage) {
      throw new TypeError('filePath and safeStorage are required');
    }
    this.filePath = filePath;
    this.safeStorage = safeStorage;
  }

  readFile() {
    try {
      const parsed = JSON.parse(fs.readFileSync(this.filePath, 'utf8'));
      return parsed && typeof parsed === 'object' ? parsed : {};
    } catch {
      return {};
    }
  }

  writeFile(value) {
    fs.mkdirSync(path.dirname(this.filePath), { recursive: true });
    const temporary = `${this.filePath}.${process.pid}.tmp`;
    fs.writeFileSync(temporary, JSON.stringify(value, null, 2), {
      encoding: 'utf8',
      mode: 0o600,
    });
    fs.renameSync(temporary, this.filePath);
  }

  save(providerValue, { vendorId: rawVendorId, authToken: rawToken }) {
    const provider = validateProvider(providerValue);
    const vendorId = validateVendorId(rawVendorId);
    const authToken = String(rawToken || '').trim().replace(/^Bearer\s+/i, '');
    if (authToken.length < 20 || authToken.length > 16_384) {
      throw new Error('Vendor auth token length is invalid');
    }
    if (!this.safeStorage.isEncryptionAvailable()) {
      throw new Error('OS credential encryption is unavailable');
    }
    const rows = this.readFile();
    rows[provider] = {
      vendorId,
      encryptedToken: this.safeStorage
        .encryptString(authToken)
        .toString('base64'),
      updatedAt: new Date().toISOString(),
    };
    this.writeFile(rows);
    return this.status(provider);
  }

  get(providerValue) {
    const provider = validateProvider(providerValue);
    const row = this.readFile()[provider];
    if (!row?.encryptedToken || !row?.vendorId) return null;
    if (!this.safeStorage.isEncryptionAvailable()) {
      throw new Error('OS credential encryption is unavailable');
    }
    const authToken = this.safeStorage.decryptString(
      Buffer.from(row.encryptedToken, 'base64'),
    );
    if (!authToken) return null;
    return {
      vendorId: validateVendorId(row.vendorId),
      authToken,
      updatedAt: String(row.updatedAt || ''),
    };
  }

  status(providerValue) {
    const provider = validateProvider(providerValue);
    const row = this.readFile()[provider];
    return {
      provider,
      configured: Boolean(row?.vendorId && row?.encryptedToken),
      vendorId: row?.vendorId ? validateVendorId(row.vendorId) : '',
      updatedAt: String(row?.updatedAt || ''),
    };
  }

  clear(providerValue) {
    const provider = validateProvider(providerValue);
    const rows = this.readFile();
    const existed = Boolean(rows[provider]);
    delete rows[provider];
    this.writeFile(rows);
    return { provider, cleared: existed };
  }
}

module.exports = {
  VendorCredentialStore,
  validateProvider,
  validateVendorId,
};
