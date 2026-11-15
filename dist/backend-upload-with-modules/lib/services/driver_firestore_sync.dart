import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/delivery_dispatch.dart';
import '../utils/firebase_config.dart';

Future<void> syncDriverProfileToFirestore(DeliveryDriver driver) async {
  if (!isFirebaseConfigured || driver.id.isEmpty) return;
  try {
    await FirebaseFirestore.instance.collection('drivers').doc(driver.id).set(
      {
        'name': driver.name,
        'phone': driver.phone,
        'civil_id': driver.civilId,
        'civil_id_photo_url': driver.civilIdPhotoUrl,
        'license_photo_url': driver.licensePhotoUrl,
        'assigned_regions': driver.assignedRegions,
        'allowed_delivery_regions': driver.allowedDeliveryRegions,
        'is_online': driver.isOnline,
        'is_busy': driver.isBusy,
        if (driver.availableSince != null)
          'available_since': Timestamp.fromDate(driver.availableSince!.toUtc()),
        if (driver.suspendedUntil != null)
          'suspended_until': Timestamp.fromDate(driver.suspendedUntil!.toUtc()),
        if (driver.suspendedUntil == null) 'suspended_until': null,
        if (driver.location != null)
          'last_location': GeoPoint(driver.location!.lat, driver.location!.lng),
        if (driver.location != null)
          'current_location': GeoPoint(driver.location!.lat, driver.location!.lng),
        'last_updated': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  } catch (_) {}
}
