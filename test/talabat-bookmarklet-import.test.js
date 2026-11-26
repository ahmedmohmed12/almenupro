const { describe, it } = require('node:test');
const assert = require('node:assert/strict');
const {
  parseAnyManualMenuJson,
  parseStructuredMenuText,
} = require('../lib/talabatScraper');

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

  it('parses plain-text pipe menu', () => {
    const text = [
      'قسم: مشروبات',
      'عصير برتقال | 1.5 | طازج | https://images.deliveryhero.io/x.jpg',
      'قسم: رئيسي',
      'برجر لحم | 2.75',
    ].join('\n');
    const result = parseStructuredMenuText(text);
    assert.equal(result.items.length, 2);
    assert.equal(result.items[0].name, 'عصير برتقال');
    assert.equal(result.items[0].categoryName, 'مشروبات');
    assert.equal(result.items[1].price, 2.75);
  });

  it('parseAnyManualMenuJson accepts structured text string', () => {
    const text = 'برجر | 3.5 | وصف قصير';
    const result = parseAnyManualMenuJson(text);
    assert.equal(result.items.length, 1);
    assert.equal(result.items[0].name, 'برجر');
  });
});