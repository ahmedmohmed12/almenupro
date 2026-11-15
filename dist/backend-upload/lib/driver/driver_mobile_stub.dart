import '../models/delivery_dispatch.dart';

Future<void> firebaseMessagingBackgroundHandler(dynamic message) async {}

Future<void> initDriverMobileServices() async {}

Future<void> startDriverLocationTracking({
  required String driverId,
  required String authToken,
  required String apiBaseUrl,
  Map<String, bool> assignedRegions = const {},
}) async {}

Future<void> stopDriverLocationTracking() async {}

Future<void> registerDriverFcmToken(String driverId) async {}

Future<void> playDriverIncomingAlert() async {}

Future<void> stopDriverIncomingAlert() async {}

Future<void> alertIncomingDriverJob(Map<String, dynamic> data) async {}

Future<DeliveryDispatchRequest?> consumeIncomingJobPayload() async => null;
