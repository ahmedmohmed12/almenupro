const DEFAULT_COUNTRY_CODE = '965';

const COUNTRY_CODES = [
  '965',
  '966',
  '971',
  '973',
  '974',
  '968',
  '962',
  '961',
  '963',
  '964',
  '967',
  '970',
  '20',
  '212',
  '213',
  '216',
  '218',
  '249',
  '1',
  '44',
  '33',
  '49',
  '90',
  '91',
  '92',
];

function digitsOnly(raw) {
  return String(raw || '').replace(/\D/g, '');
}

function combineWhatsappNumber(countryCode, phone) {
  const cc = digitsOnly(countryCode);
  let local = digitsOnly(phone);
  if (!cc || !local) return '';
  if (local.startsWith('0')) {
    local = local.slice(1);
  }
  return `${cc}${local}`;
}

function splitWhatsappNumber(full) {
  const digits = digitsOnly(full);
  if (!digits) {
    return { whatsappCountryCode: DEFAULT_COUNTRY_CODE, whatsappPhone: '' };
  }

  const sortedCodes = [...COUNTRY_CODES].sort((a, b) => b.length - a.length);
  for (const code of sortedCodes) {
    if (digits.startsWith(code) && digits.length > code.length + 4) {
      return {
        whatsappCountryCode: code,
        whatsappPhone: digits.slice(code.length),
      };
    }
  }

  if (digits.startsWith('965')) {
    return {
      whatsappCountryCode: '965',
      whatsappPhone: digits.slice(3),
    };
  }

  return {
    whatsappCountryCode: DEFAULT_COUNTRY_CODE,
    whatsappPhone: digits,
  };
}

function normalizeWhatsappSettings(source = {}) {
  const explicitCountry = digitsOnly(
    source.whatsappCountryCode || source.whatsapp_country_code || '',
  );
  const explicitPhone = digitsOnly(source.whatsappPhone || source.whatsapp_phone || '');
  const legacyFull = digitsOnly(source.whatsappNumber || source.whatsapp_number || '');

  let whatsappCountryCode = explicitCountry || DEFAULT_COUNTRY_CODE;
  let whatsappPhone = explicitPhone;
  let whatsappNumber = legacyFull;

  if (whatsappPhone && whatsappCountryCode) {
    whatsappNumber = combineWhatsappNumber(whatsappCountryCode, whatsappPhone);
  } else if (whatsappNumber) {
    const split = splitWhatsappNumber(whatsappNumber);
    whatsappCountryCode = split.whatsappCountryCode;
    whatsappPhone = split.whatsappPhone;
  } else {
    whatsappNumber = '';
    whatsappPhone = '';
    whatsappCountryCode = DEFAULT_COUNTRY_CODE;
  }

  return {
    whatsappCountryCode,
    whatsappPhone,
    whatsappNumber,
  };
}

module.exports = {
  DEFAULT_COUNTRY_CODE,
  COUNTRY_CODES,
  digitsOnly,
  combineWhatsappNumber,
  splitWhatsappNumber,
  normalizeWhatsappSettings,
};
