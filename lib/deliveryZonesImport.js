const XLSX = require('xlsx');

const KUWAIT_GOVERNORATES = [
  'العاصمة',
  'حولي',
  'الفروانية',
  'الجهراء',
  'مبارك الكبير',
  'الأحمدي',
];

const GOVERNORATE_ALIASES = {
  احمد: 'الأحمدي',
  أحمد: 'الأحمدي',
  احمدي: 'الأحمدي',
  أحمدي: 'الأحمدي',
  العاصمه: 'العاصمة',
  capital: 'العاصمة',
  hawalli: 'حولي',
  farwaniya: 'الفروانية',
  jahra: 'الجهراء',
  ahmadi: 'الأحمدي',
};

/** Canonical field → accepted header tokens (normalized matching applied separately). */
const FIELD_ALIASES = {
  governorate: [
    'governorate',
    'governorate name',
    'governorate_name',
    'gov',
    'province',
    'state',
    'المحافظة',
    'محافظة',
    'محافظه',
  ],
  areaName: [
    'areaname',
    'area_name',
    'area name',
    'area',
    'arean',
    'region',
    'district',
    'zone',
    'block',
    'المنطقة',
    'منطقة',
    'منطقه',
    'حي',
  ],
  deliveryFee: [
    'deliveryfee',
    'deliveryfe',
    'delivery_fee',
    'delivery fee',
    'deliveryfees',
    'delivery',
    'fee',
    'fees',
    'price',
    'cost',
    'amount',
    'charge',
    'رسوم',
    'رسوم_التوصيل',
    'رسوم التوصيل',
    'سعر',
    'سعر التوصيل',
  ],
  isActive: [
    'isactive',
    'isact',
    'is_active',
    'active',
    'enabled',
    'status',
    'نشط',
    'فعال',
  ],
};

const CSV_TEMPLATE = [
  'governorate,areaName,deliveryFee,isActive',
  'حولي,السالمية,1.000,true',
  'الفروانية,جليب الشيوخ,1.500,true',
  'الأحمدي,الفحيحيل,2.000,true',
].join('\n');

const LOG_PREFIX = '[delivery-zones-import]';

function log(message, extra) {
  if (extra !== undefined) {
    console.log(LOG_PREFIX, message, extra);
  } else {
    console.log(LOG_PREFIX, message);
  }
}

function normalizeGovernorate(value) {
  const raw = String(value ?? '').trim();
  if (!raw) return '';
  const alias = GOVERNORATE_ALIASES[raw] || GOVERNORATE_ALIASES[raw.toLowerCase()];
  if (alias) return alias;
  const match = KUWAIT_GOVERNORATES.find(
    (entry) => entry.toLowerCase() === raw.toLowerCase(),
  );
  return match || raw;
}

function parseBoolean(value, fallback = true) {
  if (value == null || value === '') return fallback;
  const normalized = String(value).trim().toLowerCase();
  if (['false', '0', 'no', 'off', 'inactive', 'لا', 'غير نشط', 'disabled'].includes(normalized)) {
    return false;
  }
  if (['true', '1', 'yes', 'on', 'active', 'نعم', 'نشط', 'enabled'].includes(normalized)) {
    return true;
  }
  return fallback;
}

function parseCsvLine(line) {
  const cells = [];
  let current = '';
  let inQuotes = false;

  for (let i = 0; i < line.length; i += 1) {
    const char = line[i];
    if (char === '"') {
      if (inQuotes && line[i + 1] === '"') {
        current += '"';
        i += 1;
      } else {
        inQuotes = !inQuotes;
      }
      continue;
    }
    if (char === ',' && !inQuotes) {
      cells.push(current.trim());
      current = '';
      continue;
    }
    current += char;
  }
  cells.push(current.trim());
  return cells;
}

function normalizeHeader(value) {
  return String(value ?? '')
    .trim()
    .replace(/^\uFEFF/, '')
    .replace(/[\u200f\u200e\u202a\u202c]/g, '')
    .replace(/\s+/g, ' ')
    .toLowerCase();
}

function compactHeader(value) {
  return normalizeHeader(value).replace(/[\s_\-./\\]+/g, '');
}

function mapHeaderToField(header) {
  const key = normalizeHeader(header);
  if (!key) return null;

  const compact = compactHeader(header);

  for (const [field, aliases] of Object.entries(FIELD_ALIASES)) {
    for (const alias of aliases) {
      const aliasKey = normalizeHeader(alias);
      const aliasCompact = compactHeader(alias);
      if (key === aliasKey || compact === aliasCompact) {
        return field;
      }
    }
  }

  if (compact.startsWith('governor') || compact.startsWith('gov') || key.includes('محافظ')) {
    return 'governorate';
  }
  if (
    compact.startsWith('areaname') ||
    compact.startsWith('arean') ||
    compact === 'area' ||
    compact.startsWith('region') ||
    compact.startsWith('district') ||
    key.includes('منطق') ||
    key.includes('حي')
  ) {
    return 'areaName';
  }
  if (
    compact.startsWith('deliveryfe') ||
    compact.startsWith('deliveryfee') ||
    compact.startsWith('delivery') ||
    compact === 'fee' ||
    compact === 'fees' ||
    compact === 'price' ||
    compact === 'cost' ||
    key.includes('رسوم') ||
    key.includes('سعر')
  ) {
    return 'deliveryFee';
  }
  if (
    compact.startsWith('isact') ||
    compact.startsWith('isactive') ||
    compact.startsWith('active') ||
    compact.startsWith('enabled') ||
    compact === 'status' ||
    key.includes('نشط') ||
    key.includes('فعال')
  ) {
    return 'isActive';
  }

  return null;
}

function isExcelBuffer(buffer) {
  if (!buffer || buffer.length < 4) return false;
  const isZipXlsx =
    buffer[0] === 0x50 &&
    buffer[1] === 0x4b &&
    (buffer[2] === 0x03 || buffer[2] === 0x05 || buffer[2] === 0x07);
  const isOleXls =
    buffer[0] === 0xd0 &&
    buffer[1] === 0xcf &&
    buffer[2] === 0x11 &&
    buffer[3] === 0xe0;
  return isZipXlsx || isOleXls;
}

function isExcelFileName(fileName) {
  const lower = String(fileName || '').trim().toLowerCase();
  return lower.endsWith('.xlsx') || lower.endsWith('.xls') || lower.endsWith('.xlsm');
}

function csvTextToMatrix(csvText) {
  const text = String(csvText || '').replace(/^\uFEFF/, '').trim();
  if (!text) return [];

  return text
    .split(/\r?\n/)
    .map((line) => parseCsvLine(line))
    .filter((row) => row.some((cell) => String(cell ?? '').trim().length > 0));
}

function excelBufferToMatrix(buffer) {
  const workbook = XLSX.read(buffer, { type: 'buffer', cellDates: false });
  const sheetName = workbook.SheetNames[0];
  if (!sheetName) {
    throw new Error('Excel file has no worksheets');
  }

  log('Using Excel sheet', { sheetName, sheets: workbook.SheetNames.length });
  const sheet = workbook.Sheets[sheetName];
  const matrix = XLSX.utils.sheet_to_json(sheet, {
    header: 1,
    defval: '',
    raw: false,
    blankrows: false,
  });

  return matrix.filter((row) =>
    Array.isArray(row) ? row.some((cell) => String(cell ?? '').trim().length > 0) : false,
  );
}

function cellToString(value) {
  if (value == null) return '';
  if (typeof value === 'number' && Number.isFinite(value)) return String(value);
  return String(value).trim();
}

function scoreHeaderRow(cells) {
  const fields = cells.map((cell) => mapHeaderToField(cell));
  let score = 0;
  if (fields.includes('governorate')) score += 3;
  if (fields.includes('areaName')) score += 3;
  if (fields.includes('deliveryFee')) score += 1;
  if (fields.includes('isActive')) score += 1;
  return score;
}

function findHeaderRowIndex(matrix) {
  const maxScan = Math.min(matrix.length, 20);
  let bestIndex = 0;
  let bestScore = 0;

  for (let i = 0; i < maxScan; i += 1) {
    const cells = (matrix[i] || []).map(cellToString);
    if (cells.every((cell) => !cell)) continue;
    const score = scoreHeaderRow(cells);
    if (score > bestScore) {
      bestScore = score;
      bestIndex = i;
    }
  }

  return { index: bestIndex, score: bestScore };
}

function buildFieldMapping(headerCells, maxColumns) {
  const mapped = headerCells.map((header) => mapHeaderToField(header));
  const hasGovernorate = mapped.includes('governorate');
  const hasArea = mapped.includes('areaName');

  if (hasGovernorate && hasArea) {
    return { fieldIndexes: mapped, mode: 'header-map' };
  }

  const colCount = Math.max(headerCells.length, maxColumns, 2);
  const positional = [];
  for (let i = 0; i < colCount; i += 1) {
    if (i === 0) positional.push('governorate');
    else if (i === 1) positional.push('areaName');
    else if (i === 2) positional.push('deliveryFee');
    else if (i === 3) positional.push('isActive');
    else positional.push(null);
  }

  log('Header mapping fallback → positional columns', {
    rawHeaders: headerCells,
    attemptedMap: mapped,
    positional,
  });

  return { fieldIndexes: positional, mode: 'positional-fallback' };
}

function rowToRecord(cells, fieldIndexes) {
  const record = {
    governorate: '',
    areaName: '',
    deliveryFee: '',
    isActive: '',
  };

  for (let col = 0; col < fieldIndexes.length; col += 1) {
    const field = fieldIndexes[col];
    if (!field) continue;
    if (cells[col] != null && String(cells[col]).trim() !== '') {
      record[field] = cells[col];
    }
  }

  return record;
}

function parseDeliveryZonesMatrix(matrix, sourceLabel = 'file') {
  log(`Parsing ${sourceLabel}`, { totalLines: matrix.length });

  if (!Array.isArray(matrix) || matrix.length === 0) {
    throw new Error('File is empty');
  }

  const { index: headerRowIndex, score: headerScore } = findHeaderRowIndex(matrix);
  const headerCells = (matrix[headerRowIndex] || []).map(cellToString);

  let maxColumns = headerCells.length;
  for (let i = headerRowIndex + 1; i < matrix.length; i += 1) {
    const row = matrix[i] || [];
    if (Array.isArray(row)) {
      maxColumns = Math.max(maxColumns, row.length);
    }
  }

  const { fieldIndexes, mode: mappingMode } = buildFieldMapping(headerCells, maxColumns);

  log('=== HEADER ROW DETECTED ===', {
    headerRowNumber: headerRowIndex + 1,
    headerScore,
    mappingMode,
    rawHeaders: headerCells,
    mappedFields: fieldIndexes,
  });

  const rows = [];
  const errors = [];
  let skippedEmpty = 0;
  let firstSampleLogged = false;

  for (let lineIndex = headerRowIndex + 1; lineIndex < matrix.length; lineIndex += 1) {
    const rawRow = matrix[lineIndex] || [];
    const cells = Array.isArray(rawRow) ? rawRow.map(cellToString) : [cellToString(rawRow)];

    if (cells.every((cell) => !cell)) {
      skippedEmpty += 1;
      log(`Row ${lineIndex + 1}: skipped (empty)`);
      continue;
    }

    const record = rowToRecord(cells, fieldIndexes);
    const governorate = normalizeGovernorate(record.governorate);
    const areaName = String(record.areaName || '').trim();
    const deliveryFee =
      Number(String(record.deliveryFee || '0').replace(/,/g, '.').replace(/[^\d.]/g, '')) ||
      0;
    const isActive = parseBoolean(record.isActive, true);
    const rowNumber = lineIndex + 1;

    if (!firstSampleLogged) {
      firstSampleLogged = true;
      log('=== FIRST DATA ROW SAMPLE ===', {
        rowNumber,
        rawCells: cells,
        mappedRecord: record,
        parsed: { governorate, areaName, deliveryFee, isActive },
      });
    }

    if (!governorate || !areaName) {
      const reason = !governorate && !areaName
        ? 'Missing governorate and area name'
        : !governorate
          ? 'Missing governorate'
          : 'Missing area name';
      log(`Row ${rowNumber}: REJECTED — ${reason}`, { raw: cells, mapped: record });
      errors.push({ row: rowNumber, error: reason, raw: cells });
      continue;
    }

    const knownGovernorate = KUWAIT_GOVERNORATES.some(
      (entry) => entry.toLowerCase() === governorate.toLowerCase(),
    );
    if (!knownGovernorate) {
      log(`Row ${rowNumber}: non-standard governorate accepted`, { governorate });
    }

    rows.push({
      governorate: knownGovernorate
        ? KUWAIT_GOVERNORATES.find(
            (entry) => entry.toLowerCase() === governorate.toLowerCase(),
          ) || governorate
        : governorate,
      areaName,
      deliveryFee: Math.max(0, deliveryFee),
      isActive,
      row: rowNumber,
    });
  }

  log('=== PARSE SUMMARY ===', {
    source: sourceLabel,
    headerRowNumber: headerRowIndex + 1,
    mappingMode,
    validRows: rows.length,
    errorRows: errors.length,
    skippedEmpty,
    scannedDataLines: matrix.length - headerRowIndex - 1,
    rejectionSamples: errors.slice(0, 5),
  });

  if (rows.length === 0 && matrix.length > headerRowIndex + 1) {
    throw new Error(
      `No valid rows found. Headers at row ${headerRowIndex + 1}: [${headerCells.join(' | ')}]. ` +
        `Mapping: [${fieldIndexes.join(' | ')}]. Errors: ${errors.length}, empty skipped: ${skippedEmpty}.`,
    );
  }

  if (rows.length === 0) {
    throw new Error('File must include a header row and at least one data row');
  }

  return {
    rows,
    errors,
    meta: {
      skippedEmpty,
      source: sourceLabel,
      headerRowIndex,
      mappingMode,
      rawHeaders: headerCells,
      mappedFields: fieldIndexes,
    },
  };
}

function parseDeliveryZonesFile({ buffer, fileName, csvText } = {}) {
  let matrix = [];
  let sourceLabel = 'unknown';

  if (buffer && Buffer.isBuffer(buffer) && buffer.length > 0) {
    const useExcel = isExcelBuffer(buffer) || isExcelFileName(fileName);

    if (useExcel) {
      log('Detected Excel binary upload', {
        fileName: fileName || '(none)',
        bytes: buffer.length,
      });
      matrix = excelBufferToMatrix(buffer);
      sourceLabel = `excel:${fileName || 'upload.xlsx'}`;
    } else {
      const asText = buffer.toString('utf8').replace(/^\uFEFF/, '').trim();
      log('Detected text/CSV buffer upload', {
        fileName: fileName || '(none)',
        bytes: buffer.length,
        preview: asText.slice(0, 160),
      });
      matrix = csvTextToMatrix(asText);
      sourceLabel = `csv-buffer:${fileName || 'upload.csv'}`;
    }
  } else if (csvText) {
    log('Detected CSV text payload', { chars: String(csvText).length });
    matrix = csvTextToMatrix(csvText);
    sourceLabel = 'csv-text';
  } else {
    throw new Error('No file content provided');
  }

  return parseDeliveryZonesMatrix(matrix, sourceLabel);
}

/** @deprecated Use parseDeliveryZonesFile */
function parseDeliveryZonesCsv(csvText) {
  return parseDeliveryZonesFile({ csvText });
}

function zoneIdentityKey(governorate, areaName) {
  return `${String(governorate).trim().toLowerCase()}::${String(areaName).trim().toLowerCase()}`;
}

function importDeliveryZonesForRestaurant({
  existingZones,
  rows,
  restaurantId,
  normalizeDeliveryZone,
}) {
  const scopedId = String(restaurantId);
  const restaurantZones = (existingZones || []).filter(
    (zone) => String(zone.restaurant_id || zone.restaurantId) === scopedId,
  );
  const otherZones = (existingZones || []).filter(
    (zone) => String(zone.restaurant_id || zone.restaurantId) !== scopedId,
  );

  const indexByKey = new Map();
  restaurantZones.forEach((zone, index) => {
    indexByKey.set(
      zoneIdentityKey(zone.governorate, zone.areaName || zone.area_name),
      index,
    );
  });

  let added = 0;
  let updated = 0;
  const now = new Date().toISOString();

  for (const row of rows) {
    const key = zoneIdentityKey(row.governorate, row.areaName);
    const existingIndex = indexByKey.get(key);

    if (existingIndex != null) {
      const zone = restaurantZones[existingIndex];
      zone.governorate = row.governorate;
      zone.areaName = row.areaName;
      zone.deliveryFee = row.deliveryFee;
      zone.isActive = row.isActive;
      zone.updatedAt = now;
      updated += 1;
      continue;
    }

    const id = `zone_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`;
    const created = normalizeDeliveryZone(
      {
        governorate: row.governorate,
        areaName: row.areaName,
        deliveryFee: row.deliveryFee,
        isActive: row.isActive,
        createdAt: now,
        updatedAt: now,
      },
      id,
      scopedId,
    );
    restaurantZones.push(created);
    indexByKey.set(key, restaurantZones.length - 1);
    added += 1;
  }

  return {
    zones: [...otherZones, ...restaurantZones],
    summary: {
      added,
      updated,
      totalRows: rows.length,
    },
  };
}

module.exports = {
  CSV_TEMPLATE,
  KUWAIT_GOVERNORATES,
  normalizeGovernorate,
  parseDeliveryZonesCsv,
  parseDeliveryZonesFile,
  importDeliveryZonesForRestaurant,
  mapHeaderToField,
  buildFieldMapping,
};
