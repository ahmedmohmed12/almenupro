const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { onDocumentCreated } = require('firebase-functions/v2/firestore');
const { scrapeTalabatMenu } = require('./talabatScraper');
const { dispatchSharedFleet } = require('./dispatchFleet');

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

exports.dispatchSharedFleet = onCall(async (request) => {
  try {
    return await dispatchSharedFleet(request.data || {});
  } catch (error) {
    throw new HttpsError('internal', error.message || 'تعذر توزيع الطلب على الأسطول');
  }
});

exports.onDeliveryRequestCreated = onDocumentCreated(
  'delivery_requests/{requestId}',
  async (event) => {
    const data = event.data?.data() || {};
    await dispatchSharedFleet({ ...data, id: event.params.requestId });
  },
);
