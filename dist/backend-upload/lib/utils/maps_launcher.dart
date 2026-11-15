import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/delivery_dispatch.dart';

Uri googleMapsHttpsUri(GeoPointLite point) {
  return Uri.parse(
    'https://www.google.com/maps/dir/?api=1&destination=${point.lat},${point.lng}&travelmode=driving',
  );
}

Future<bool> launchGoogleNavigation(GeoPointLite point) {
  if (kIsWeb) return launchMapsHttps(point);
  final uri = defaultTargetPlatform == TargetPlatform.iOS
      ? Uri.parse(
          'comgooglemaps://?daddr=${point.lat},${point.lng}&directionsmode=driving',
        )
      : Uri.parse(
          'google.navigation:q=${point.lat},${point.lng}&mode=d',
        );
  return launchUrl(uri, mode: LaunchMode.externalApplication);
}

Future<bool> launchMapsHttps(GeoPointLite point) {
  return launchUrl(
    googleMapsHttpsUri(point),
    mode: LaunchMode.externalApplication,
    webOnlyWindowName: '_blank',
  );
}

Future<bool> launchMapsFallback(GeoPointLite point) => launchMapsHttps(point);

Future<void> navigateToPoint(GeoPointLite? point) async {
  if (point == null) return;
  if (kIsWeb) {
    await launchMapsHttps(point);
    return;
  }
  final opened = await launchGoogleNavigation(point);
  if (!opened) {
    await launchMapsHttps(point);
  }
}
