const { describe, it } = require('node:test');
const assert = require('node:assert/strict');
const { parseAnyManualMenuJson } = require('../lib/talabatScraper');

describe('bookmarklet manual JSON import', () => {
  it('parses almenupro bookmarklet payload', () => {
    const payload = {
      source: 'almenupro-talabat-bookmarklet',
      menuUrl: 'https://www.talabat.com/kuwait/restaurant/1/x',
      items: [
        {
          talabatId: 99,
          name: 'شاورما',
          price: 2.5,
          categoryName: 'سندويشات',
          imageUrl: 'https://images.deliveryhero.io/x.jpg',
          description: 'وصف',
        },
      ],
    };
    const result = parseAnyManualMenuJson(payload);
    assert.equal(result.items.length, 1);
    assert.equal(result.items[0].name, 'شاورما');
    assert.equal(result.items[0].categoryName, 'سندويشات');
    assert.equal(result.menuUrl, payload.menuUrl);
  });
});