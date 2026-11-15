import 'dart:io' show Platform;

import '../models/delivery_dispatch.dart';
import 'driver_mobile_io.dart' as mobile;
import 'driver_mobile_stub.dart' as stub;

bool get _useMobile => Platform.isAndroid || Platform.isIOS;

Future<void> firebaseMessagingBackgroundHandler(dynamic message) {
  if (_useMobile) {
    return mobile.firebaseMessagingBackgroundHandler(message);
  }
  return stub.firebaseMessagingBackgroundHandler(message);
}

Future<void> initDriverMobileServices() {
  if (_useMobile) return mobile.initDriverMobileServices();
  return stub.initDriverMobileServices();
}

Future<void> startDriverLocationTracking({
  required String driverId,
  required String authToken,
  required String apiBaseUrl,
  Map<String, bool> assignedRegions = const {},
}) {
  if (_useMobile) {
    return mobile.startDriverLocationTracking(
      driverId: driverId,
      authToken: authToken,
      apiBaseUrl: apiBaseUrl,
      assignedRegions: assignedRegions,
    );
  }
  return stub.startDriverLocationTracking(
    driverId: driverId,
    authToken: authToken,
    apiBaseUrl: apiBaseUrl,
    assignedRegions: assignedRegions,
  );
}

Future<void> stopDriverLocationTracking() {
  if (_useMobile) return mobile.stopDriverLocationTracking();
  return stub.stopDriverLocationTracking();
}

Future<void> registerDriverFcmToken(String driverId) {
  if (_useMobile) return mobile.registerDriverFcmToken(driverId);
  return stub.registerDriverFcmToken(driverId);
}

Future<void> playDriverIncomingAlert() {
  if (_useMobile) return mobile.playDriverIncomingAlert();
  return stub.playDriverIncomingAlert();
}

Future<void> stopDriverIncomingAlert() {
  if (_useMobile) return mobile.stopDriverIncomingAlert();
  return stub.stopDriverIncomingAlert();
}

Future<void> alertIncomingDriverJob(Map<String, dynamic> data) {
  if (_useMobile) return mobile.alertIncomingDriverJob(data);
  return stub.alertIncomingDriverJob(data);
}

Future<DeliveryDispatchRequest?> consumeIncomingJobPayload() {
  if (_useMobile) return mobile.consumeIncomingJobPayload();
  return stub.consumeIncomingJobPayload();
}
