const urls = [
  'https://www.talabat.com/nextApi/vendor/20426/areas?countryId=1',
  'https://www.talabat.com/nextApi/vendor/20426/branches?countryId=1',
  'https://www.talabat.com/nextApi/branches?vendorId=20426&countryId=1',
  'https://www.talabat.com/nextApi/brand/molton-cookies/branches?countryId=1',
  'https://www.talabat.com/nextApi/getVendorBranches?vendorId=20426&countryId=1',
  'https://www.talabat.com/nextApi/search/global?countryId=1&q=molton%20cookies',
];

(async () => {
  for (const url of urls) {
    try {
      const res = await fetch(url, {
        headers: {
          'User-Agent': 'Mozilla/5.0',
          Accept: 'application/json',
          Referer: 'https://www.talabat.com/kuwait/molton-cookies',
        },
      });
      const text = await res.text();
      console.log('\nURL:', url);
      console.log('status', res.status, 'len', text.length);
      console.log(text.slice(0, 400));
    } catch (e) {
      console.log('fail', url, e.message);
    }
  }
})();
