import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:audioplayers/audioplayers.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../firebase_options.dart';
import '../l10n/app_strings.dart';
import '../models/delivery_dispatch.dart';
import '../services/api_service.dart';

const _channelId = 'driver_incoming_jobs_v2';
const _prefsToken = 'driver_bg_token';
const _prefsDriverId = 'driver_bg_id';
const _prefsApi = 'driver_bg_api';
const _prefsIncoming = 'driver_incoming_job';
const _prefsRegions = 'driver_assigned_regions';
const _prefsLastAlert = 'driver_last_alert_id';

final FlutterLocalNotificationsPlugin _localNotifications =
    FlutterLocalNotificationsPlugin();
final AudioPlayer _alertPlayer = AudioPlayer();
var _alertPlaying = false;
var _notificationsReady = false;

Future<AppStrings> _mobileStrings() async {
  final prefs = await SharedPreferences.getInstance();
  return AppStrings(prefs.getString('app_locale') ?? 'ar');
}

bool _firebaseReady() {
  final options = DefaultFirebaseOptions.currentPlatform;
  return !options.apiKey.startsWith('YOUR_') &&
      !options.projectId.startsWith('YOUR_');
}

Future<void> _ensureFirebase() async {
  if (!_firebaseReady()) return;
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  }
}

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await _ensureFirebase();
  await _ensureNotificationPlugin();
  final data = Map<String, dynamic>.from(message.data);
  if (data['type'] == 'driver_job' ||
      (data['request_id'] ?? '').toString().isNotEmpty) {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsIncoming, jsonEncode(data));
  }
  if (message.notification != null && data['type'] != 'driver_job_taken') {
    return;
  }
  await _showIncomingJobNotification(data);
}

Future<void> _ensureNotificationPlugin() async {
  if (_notificationsReady) return;
  final strings = await _mobileStrings();
  await _localNotifications.initialize(
    const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: true,
        requestSoundPermission: true,
        requestBadgePermission: true,
      ),
    ),
  );
  final channel = AndroidNotificationChannel(
    _channelId,
    strings.tr('طلبات التوصيل', 'Delivery orders'),
    description: strings.tr(
      'تنبيه صوتي عند وصول طلب جديد',
      'Sound alert when a new order arrives',
    ),
    importance: Importance.max,
    playSound: true,
    sound: RawResourceAndroidNotificationSound('driver_ringtone'),
    enableVibration: true,
  );
  await _localNotifications
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >()
      ?.createNotificationChannel(channel);
  await _localNotifications
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >()
      ?.createNotificationChannel(
        AndroidNotificationChannel(
          'driver_gps',
          strings.tr('تتبع السائق', 'Driver tracking'),
          description: strings.tr(
            'إشعار الخدمة الأمامية لتتبع الموقع',
            'Foreground service notification for location tracking',
          ),
          importance: Importance.low,
        ),
      );
  _notificationsReady = true;
}

Future<void> playDriverIncomingAlert() async {
  if (_alertPlaying) return;
  _alertPlaying = true;
  try {
    await _alertPlayer.setReleaseMode(ReleaseMode.loop);
    await _alertPlayer.play(AssetSource('sounds/driver_ringtone.wav'));
  } catch (_) {
    _alertPlaying = false;
  }
}

Future<void> stopDriverIncomingAlert() async {
  _alertPlaying = false;
  try {
    await _alertPlayer.stop();
  } catch (_) {}
}

Future<void> alertIncomingDriverJob(Map<String, dynamic> data) {
  return _showIncomingJobNotification(data);
}

Future<void> initDriverMobileServices() async {
  if (!(Platform.isAndroid || Platform.isIOS)) return;

  final strings = await _mobileStrings();
  await _ensureNotificationPlugin();
  await Permission.notification.request();
  await Permission.locationWhenInUse.request();
  await Permission.locationAlways.request();
  if (Platform.isAndroid) {
    await Permission.ignoreBatteryOptimizations.request();
  }

  if (_firebaseReady()) {
    await _ensureFirebase();
    await FirebaseMessaging.instance.requestPermission(
      alert: true,
      sound: true,
      badge: true,
      criticalAlert: true,
      announcement: true,
    );
    await FirebaseMessaging.instance
        .setForegroundNotificationPresentationOptions(
          alert: true,
          badge: true,
          sound: true,
        );
    FirebaseMessaging.onMessage.listen((message) {
      final data = Map<String, dynamic>.from(message.data);
      unawaited(_showIncomingJobNotification(data));
      if (data['type'] != 'driver_job_taken') {
        unawaited(playDriverIncomingAlert());
      }
    });
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      unawaited(_storeIncomingPayload(message.data));
    });
  }

  await FlutterBackgroundService().configure(
    androidConfiguration: AndroidConfiguration(
      onStart: driverLocationOnStart,
      autoStart: false,
      isForegroundMode: true,
      notificationChannelId: 'driver_gps',
      initialNotificationTitle: strings.tr('تتبع التوصيل', 'Delivery tracking'),
      initialNotificationContent: strings.tr(
        'الموقع يعمل أثناء التوصيل',
        'Location is active during delivery',
      ),
      foregroundServiceNotificationId: 1101,
      foregroundServiceTypes: [AndroidForegroundType.location],
    ),
    iosConfiguration: IosConfiguration(
      autoStart: false,
      onForeground: driverLocationOnStart,
      onBackground: onIosBackground,
    ),
  );
}

Future<void> startDriverLocationTracking({
  required String driverId,
  required String authToken,
  required String apiBaseUrl,
  Map<String, bool> assignedRegions = const {},
}) async {
  if (!(Platform.isAndroid || Platform.isIOS)) return;
  await Geolocator.requestPermission();
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_prefsDriverId, driverId);
  await prefs.setString(_prefsToken, authToken);
  await prefs.setString(_prefsApi, apiBaseUrl);
  await prefs.setString(_prefsRegions, jsonEncode(assignedRegions));
  final service = FlutterBackgroundService();
  final running = await service.isRunning();
  if (!running) {
    await service.startService();
  }
}

Future<void> stopDriverLocationTracking() async {
  if (!(Platform.isAndroid || Platform.isIOS)) return;
  final service = FlutterBackgroundService();
  service.invoke('stop');
}

Future<void> registerDriverFcmToken(String driverId) async {
  if (!(Platform.isAndroid || Platform.isIOS)) return;
  if (!_firebaseReady()) return;
  try {
    await _ensureFirebase();
    if (FirebaseAuth.instance.currentUser == null) {
      await FirebaseAuth.instance.signInAnonymously();
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsDriverId, driverId);
    final token = await FirebaseMessaging.instance.getToken();
    if (token == null || token.isEmpty) return;
    await _persistDriverFcmToken(driverId, token);
    FirebaseMessaging.instance.onTokenRefresh.listen((refreshed) {
      unawaited(_persistDriverFcmToken(driverId, refreshed));
    });
  } catch (_) {}
}

Future<void> _persistDriverFcmToken(String driverId, String token) async {
  try {
    await FirebaseFirestore.instance.collection('drivers').doc(driverId).set({
      'fcm_token': token,
      'fcm_updated_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  } catch (_) {}
  try {
    await ApiService.instance.patchDriver(driverId, fcmToken: token);
  } catch (_) {}
}

Future<DeliveryDispatchRequest?> consumeIncomingJobPayload() async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString(_prefsIncoming);
  if (raw == null || raw.isEmpty) return null;
  await prefs.remove(_prefsIncoming);
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return null;
    return DeliveryDispatchRequest.fromJson(Map<String, dynamic>.from(decoded));
  } catch (_) {
    return null;
  }
}

Future<void> _storeIncomingPayload(Map<String, dynamic> data) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_prefsIncoming, jsonEncode(data));
}

Future<void> _pollInboxForIncomingJob() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_prefsToken) ?? '';
    final api = prefs.getString(_prefsApi) ?? '';
    if (token.isEmpty || api.isEmpty) return;
    final response = await http
        .get(
          Uri.parse('$api/me/driver'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
        )
        .timeout(const Duration(seconds: 12));
    if (response.statusCode != 200) return;
    final decoded = jsonDecode(response.body);
    if (decoded is! Map) return;
    final incomingRaw = decoded['incoming'];
    final incoming = incomingRaw is List
        ? incomingRaw.whereType<Map>().toList()
        : const <Map>[];
    if (incoming.isEmpty) {
      await prefs.remove(_prefsLastAlert);
      await _localNotifications.cancel(4401);
      return;
    }
    final first = Map<String, dynamic>.from(incoming.first);
    final requestId = '${first['id'] ?? first['request_id'] ?? ''}';
    if (requestId.isEmpty) return;
    if (prefs.getString(_prefsLastAlert) == requestId) return;
    await prefs.setString(_prefsLastAlert, requestId);
    await _showIncomingJobNotification({
      'type': 'driver_job',
      'request_id': requestId,
      'driver_fee': '${first['driver_fee'] ?? first['driverFee'] ?? ''}',
      'region_name': '${first['region_name'] ?? first['regionName'] ?? ''}',
      'restaurantName': '${first['restaurantName'] ?? ''}',
    });
  } catch (_) {}
}

Future<void> _showIncomingJobNotification(Map<String, dynamic> data) async {
  await _ensureNotificationPlugin();
  final strings = await _mobileStrings();
  final type = '${data['type'] ?? ''}';
  final requestId = '${data['request_id'] ?? data['id'] ?? ''}';
  if (type == 'driver_job_taken' || type == 'driver_job_cancelled') {
    await _localNotifications.cancel(4401);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsIncoming);
    await stopDriverIncomingAlert();
    return;
  }
  if (type != 'driver_job' && requestId.isEmpty) return;
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_prefsIncoming, jsonEncode(data));
  final android = AndroidNotificationDetails(
    _channelId,
    strings.tr('طلبات التوصيل', 'Delivery orders'),
    channelDescription: strings.tr(
      'تنبيه بطلب توصيل جديد',
      'New delivery order alert',
    ),
    importance: Importance.max,
    priority: Priority.high,
    fullScreenIntent: true,
    playSound: true,
    sound: RawResourceAndroidNotificationSound('driver_ringtone'),
    timeoutAfter: 45000,
    category: AndroidNotificationCategory.call,
    visibility: NotificationVisibility.public,
    enableVibration: true,
    audioAttributesUsage: AudioAttributesUsage.notificationRingtone,
  );
  const ios = DarwinNotificationDetails(
    presentAlert: true,
    presentSound: true,
    sound: 'driver_ringtone.wav',
    interruptionLevel: InterruptionLevel.timeSensitive,
  );
  await _localNotifications.show(
    4401,
    strings.tr('طلب توصيل جديد', 'New delivery order'),
    strings.tr(
      'ربحك ${data['driver_fee'] ?? ''} — ${data['region_name'] ?? ''}',
      'Your earnings ${data['driver_fee'] ?? ''} — ${data['region_name'] ?? ''}',
    ),
    NotificationDetails(android: android, iOS: ios),
    payload: jsonEncode(data),
  );
}

@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();
  return true;
}

@pragma('vm:entry-point')
void driverLocationOnStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();
  await _ensureNotificationPlugin();
  Timer? heartbeat;
  StreamSubscription<Position>? stream;
  Position? lastSent;

  if (service is AndroidServiceInstance) {
    service.on('setAsForeground').listen((_) {
      service.setAsForegroundService();
    });
    service.on('setAsBackground').listen((_) {
      service.setAsBackgroundService();
    });
  }

  service.on('stop').listen((_) async {
    heartbeat?.cancel();
    await stream?.cancel();
    await service.stopSelf();
  });

  Future<void> publish(
    Position position, {
    required bool forceHeartbeat,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final driverId = prefs.getString(_prefsDriverId) ?? '';
      final token = prefs.getString(_prefsToken) ?? '';
      final api = prefs.getString(_prefsApi) ?? '';
      if (driverId.isEmpty || token.isEmpty || api.isEmpty) return;

      final movedMeters = lastSent == null
          ? 999
          : Geolocator.distanceBetween(
              lastSent!.latitude,
              lastSent!.longitude,
              position.latitude,
              position.longitude,
            );
      if (!forceHeartbeat && movedMeters < 15) return;
      lastSent = position;

      await http.patch(
        Uri.parse('$api/drivers/$driverId'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'current_location': {
            'lat': position.latitude,
            'lng': position.longitude,
          },
          'is_online': true,
        }),
      );

      if (_firebaseReady()) {
        await _ensureFirebase();
        await FirebaseFirestore.instance
            .collection('drivers')
            .doc(driverId)
            .set({
              'current_location': GeoPoint(
                position.latitude,
                position.longitude,
              ),
              'last_location': GeoPoint(position.latitude, position.longitude),
              'is_online': true,
              'assigned_regions': _assignedRegionsFromPrefs(prefs),
              'updated_at': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));
      }
    } catch (_) {}
  }

  Future<void> tick({required bool forceHeartbeat}) async {
    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    );
    await publish(position, forceHeartbeat: forceHeartbeat);
  }

  stream =
      Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 15,
        ),
      ).listen((position) {
        unawaited(publish(position, forceHeartbeat: false));
      });

  heartbeat = Timer.periodic(const Duration(seconds: 10), (_) {
    unawaited(tick(forceHeartbeat: true));
    unawaited(_pollInboxForIncomingJob());
  });
  await tick(forceHeartbeat: true);
  await _pollInboxForIncomingJob();
}

Map<String, bool> _assignedRegionsFromPrefs(SharedPreferences prefs) {
  try {
    final raw = prefs.getString(_prefsRegions);
    if (raw == null || raw.isEmpty) return const {};
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return const {};
    return decoded.map((key, value) => MapEntry(key.toString(), value == true));
  } catch (_) {
    return const {};
  }
}
