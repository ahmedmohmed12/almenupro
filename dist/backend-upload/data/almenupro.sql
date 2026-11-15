-- AlMenuPro MySQL dump for shared hosting (utf8mb4)
-- Generated 2026-10-03T15:09:51.098Z
-- Import with phpMyAdmin or: mysql -u USER -p DATABASE < data/almenupro.sql
SET NAMES utf8mb4;
SET FOREIGN_KEY_CHECKS=0;

CREATE TABLE IF NOT EXISTS platform_docs (
  id VARCHAR(64) NOT NULL,
  payload LONGTEXT NOT NULL,
  updated_at VARCHAR(40) NOT NULL,
  PRIMARY KEY (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

REPLACE INTO platform_docs (id, payload, updated_at) VALUES ('menu_items', '[{"id":1,"restaurant_id":"rest_molton","category_id":1,"category_name":"كوكيز","category_name_en":"Cookies","name":"مولتن نوتيلا","name_ar":"مولتن نوتيلا","name_en":"Molten Nutella","description":"6 قطع","description_ar":"6 قطع","description_en":"6 pieces","price":1.5,"image_url":"","is_available":1,"display_order":1,"options":[],"linkedItemIds":[]},{"id":2,"restaurant_id":"rest_molton","category_id":1,"category_name":"كوكيز","category_name_en":"Cookies","name":"كوكيز شوكولاتة","name_ar":"كوكيز شوكولاتة","name_en":"Chocolate Cookies","description":"16 قطعة مع صوص الشوكولاتة","description_ar":"16 قطعة مع صوص الشوكولاتة","description_en":"16 pieces, served with chocolate sauce","price":2,"image_url":"","is_available":1,"display_order":2,"options":[],"linkedItemIds":[]},{"id":3,"restaurant_id":"rest_molton","category_id":2,"category_name":"ميني بايتس","category_name_en":"Mini Bites","name":"ميني بايتس نوتيلا","name_ar":"ميني بايتس نوتيلا","name_en":"Nutella Mini Bites","description":"40 قطعة في العلبة","description_ar":"40 قطعة في العلبة","description_en":"40 pieces in the box","price":3.5,"image_url":"","is_available":1,"display_order":3,"options":[],"linkedItemIds":[]}]', '2026-10-03T15:09:51.098Z');

REPLACE INTO platform_docs (id, payload, updated_at) VALUES ('orders', '[{"restaurantId":"rest_molton","restaurant_id":"rest_molton","customerName":"اختبار السلة","phone":"96550000000","address":"حولي، قطعة 1، شارع 2، منزل 3","paymentMethod":"كاش","invoiceNumber":"test_1787140313203","orderType":"delivery","status":"pending","orderSource":"customer_web","totalPrice":7.5,"items":[{"menuItemId":"1","name":"كوكيز اختبار","unitPrice":7.5,"quantity":1,"selectedOptions":[]}],"id":"ord_1787140313209_newk","createdAt":"2026-08-19T11:51:53.209Z"},{"restaurantId":"rest_molton","restaurant_id":"rest_molton","customerName":"اختبار السلة","phone":"96550000000","address":"حولي، قطعة 1، شارع 2، منزل 3","paymentMethod":"كاش","invoiceNumber":"test_1787139328110","orderType":"delivery","status":"pending","orderSource":"customer_web","totalPrice":7.5,"items":[{"menuItemId":"1","name":"كوكيز اختبار","unitPrice":7.5,"quantity":1,"selectedOptions":[]}],"id":"ord_1787139328115_c0fo","createdAt":"2026-08-19T11:35:28.115Z"},{"restaurantId":"rest_molton","restaurant_id":"rest_molton","customerName":"اختبار السلة","phone":"96550000000","address":"حولي، قطعة 1، شارع 2، منزل 3","paymentMethod":"كاش","invoiceNumber":"test_1787138637007","orderType":"delivery","status":"pending","orderSource":"customer_web","totalPrice":7.5,"items":[{"menuItemId":"1","name":"كوكيز اختبار","unitPrice":7.5,"quantity":1,"selectedOptions":[]}],"id":"ord_1787138637009_wa46","createdAt":"2026-08-19T11:23:57.009Z"},{"restaurantId":"rest_molton","restaurant_id":"rest_molton","customerName":"اختبار السلة","phone":"96550000000","address":"حولي، قطعة 1، شارع 2، منزل 3","paymentMethod":"كاش","invoiceNumber":"test_1787136617052","orderType":"delivery","status":"pending","orderSource":"customer_web","totalPrice":7.5,"items":[{"menuItemId":"1","name":"كوكيز اختبار","unitPrice":7.5,"quantity":1,"selectedOptions":[]}],"id":"ord_1787136617055_qzd3","createdAt":"2026-08-19T10:50:17.055Z"}]', '2026-10-03T15:09:51.098Z');

REPLACE INTO platform_docs (id, payload, updated_at) VALUES ('restaurants', '[{"id":"rest_molton","slug":"molton-cookies","name":"Molton Cookies","adminPassword":"123456","status":"active","createdAt":"2026-07-24T00:00:00.000Z"}]', '2026-10-03T15:09:51.098Z');

REPLACE INTO platform_docs (id, payload, updated_at) VALUES ('delivery_zones', '[{"id":"zone_molton_salmiya","restaurant_id":"rest_molton","governorate":"حولي","areaName":"السالمية","deliveryFee":1,"isActive":true,"createdAt":"2026-07-25T00:00:00.000Z","updatedAt":"2026-07-25T00:00:00.000Z"},{"id":"zone_molton_hawally","restaurant_id":"rest_molton","governorate":"حولي","areaName":"حولي","deliveryFee":1.25,"isActive":true,"createdAt":"2026-07-25T00:00:00.000Z","updatedAt":"2026-07-25T00:00:00.000Z"},{"id":"zone_molton_jabriya","restaurant_id":"rest_molton","governorate":"حولي","areaName":"الجابرية","deliveryFee":1.5,"isActive":true,"createdAt":"2026-07-25T00:00:00.000Z","updatedAt":"2026-07-25T00:00:00.000Z"},{"id":"zone_molton_fintas","restaurant_id":"rest_molton","governorate":"الأحمدي","areaName":"الفنطاس","deliveryFee":2,"isActive":true,"createdAt":"2026-07-25T00:00:00.000Z","updatedAt":"2026-07-25T00:00:00.000Z"}]', '2026-10-03T15:09:51.098Z');

REPLACE INTO platform_docs (id, payload, updated_at) VALUES ('kitchens', '[{"id":"kitchen_ardiya","restaurant_id":"rest_molton","name":"مطبخ العارضية","name_ar":"مطبخ العارضية","name_en":"Al-Ardiya Kitchen","code":"ARD","status":"active","is_default":true,"sort_order":1,"kds_enabled":true},{"id":"kitchen_sabah","restaurant_id":"rest_molton","name":"مطبخ صباح السالم","name_ar":"مطبخ صباح السالم","name_en":"Sabah Al-Salem Kitchen","code":"SBH","status":"active","is_default":false,"sort_order":2,"kds_enabled":true}]', '2026-10-03T15:09:51.098Z');

REPLACE INTO platform_docs (id, payload, updated_at) VALUES ('menu_categories', '[]', '2026-10-03T15:09:51.098Z');

REPLACE INTO platform_docs (id, payload, updated_at) VALUES ('reviews', '[]', '2026-10-03T15:09:51.098Z');

REPLACE INTO platform_docs (id, payload, updated_at) VALUES ('expenses', '[]', '2026-10-03T15:09:51.098Z');

REPLACE INTO platform_docs (id, payload, updated_at) VALUES ('offers', '[{"id":"offer_molton_family20","restaurantId":"rest_molton","restaurant_id":"rest_molton","title":"خصم 20% على الكوكيز","description":"خصم 20% على أصناف الكوكيز المختارة طوال فترة العرض.","type":"percentage","discountValue":20,"originalPrice":0,"offerPrice":0,"itemIds":[],"badgeText":"20%","isActive":true,"minSubtotal":0,"startsAt":"2026-01-01T00:00:00.000Z","endsAt":"2027-12-31T23:59:59.000Z"},{"id":"offer_molton_combo","restaurantId":"rest_molton","restaurant_id":"rest_molton","title":"وجبة الكوكيز مع المشروب بسعر مميز","description":"اختر العرض بضغطة واحدة وأضف الباقة إلى السلة بالسعر المخفض.","type":"combo","discountValue":0,"originalPrice":3.5,"offerPrice":2.75,"itemIds":[],"badgeText":"عرض","isActive":true,"minSubtotal":0,"startsAt":"2026-01-01T00:00:00.000Z","endsAt":"2027-12-31T23:59:59.000Z"}]', '2026-10-03T15:09:51.098Z');

REPLACE INTO platform_docs (id, payload, updated_at) VALUES ('staff_users', '[]', '2026-10-03T15:09:51.098Z');

REPLACE INTO platform_docs (id, payload, updated_at) VALUES ('dining_tables', '[]', '2026-10-03T15:09:51.098Z');

REPLACE INTO platform_docs (id, payload, updated_at) VALUES ('shift_sessions', '[]', '2026-10-03T15:09:51.098Z');

REPLACE INTO platform_docs (id, payload, updated_at) VALUES ('signup_requests', '[]', '2026-10-03T15:09:51.098Z');

REPLACE INTO platform_docs (id, payload, updated_at) VALUES ('drivers', '[]', '2026-10-03T15:09:51.098Z');

REPLACE INTO platform_docs (id, payload, updated_at) VALUES ('delivery_requests', '[]', '2026-10-03T15:09:51.098Z');

REPLACE INTO platform_docs (id, payload, updated_at) VALUES ('settings', '{"byRestaurant":{"rest_molton":{"whatsappNumber":"96594774950","workingHours":[{"weekday":6,"isOpen":true,"open":"10:00","close":"22:00"},{"weekday":7,"isOpen":true,"open":"10:00","close":"22:00"},{"weekday":1,"isOpen":true,"open":"10:00","close":"22:00"},{"weekday":2,"isOpen":true,"open":"10:00","close":"22:00"},{"weekday":3,"isOpen":true,"open":"10:00","close":"22:00"},{"weekday":4,"isOpen":true,"open":"10:00","close":"22:00"},{"weekday":5,"isOpen":true,"open":"10:00","close":"23:00"}],"updatedAt":"2026-07-24T00:00:00.000Z"}}}', '2026-10-03T15:09:51.098Z');

REPLACE INTO platform_docs (id, payload, updated_at) VALUES ('customers', '[{"id":"cust_1787136617056_nvjhfi","phone":"96550000000","customerName":"اختبار السلة","address":"حولي، قطعة 1، شارع 2، منزل 3","governorate":"","areaName":"","deliveryZoneId":null,"addressDetails":{"block":"","street":"","avenue":"","houseNumber":"","floorApartment":""},"paymentMethod":"كاش","totalOrders":4,"createdAt":"2026-08-19T10:50:17.056Z","updatedAt":"2026-08-19T11:51:53.213Z","restaurant_id":"rest_molton"}]', '2026-10-03T15:09:51.098Z');

REPLACE INTO platform_docs (id, payload, updated_at) VALUES ('audit_events', '[]', '2026-10-03T15:09:51.098Z');

REPLACE INTO platform_docs (id, payload, updated_at) VALUES ('upsell_events', '[]', '2026-10-03T15:09:51.098Z');

REPLACE INTO platform_docs (id, payload, updated_at) VALUES ('store_assets', '{}', '2026-10-03T15:09:51.098Z');

SET FOREIGN_KEY_CHECKS=1;