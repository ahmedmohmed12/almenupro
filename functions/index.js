const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { scrapeTalabatMenu } = require('./talabatScraper');

exports.scrapeTalabatMenu = onCall(async (request) => {
  const url = (request.data?.url || '').trim();

  if (!url) {
    throw new HttpsError('invalid-argument', 'يرجى إدخال رابط Talabat');
  }

  if (!url.toLowerCase().includes('talabat')) {
    throw new HttpsError(
      'invalid-argument',
      'الرابط يجب أن يكون من موقع talabat.com',
    );
  }

  try {
    return await scrapeTalabatMenu(url);
  } catch (error) {
    throw new HttpsError(
      'failed-precondition',
      error.message || 'تعذر سحب المنيو من Talabat',
    );
  }
});
