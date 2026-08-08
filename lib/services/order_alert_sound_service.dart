import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/order_alert_sound.dart';
import 'order_alert_sound_player_stub.dart'
    if (dart.library.html) 'order_alert_sound_player_web.dart';

const _soundTypeKey = 'order_alert_sound_type';
const _soundEnabledKey = 'order_alert_sound_enabled';

class OrderAlertSoundService {
  OrderAlertSoundService._();

  static final OrderAlertSoundService instance = OrderAlertSoundService._();

  OrderAlertSoundType _selectedType = OrderAlertSoundType.bell;
  var _enabled = true;
  var _initialized = false;
  var _audioUnlocked = false;
  var _isLoopPlaying = false;
  final Set<String> _ringingOrderIds = <String>{};

  OrderAlertSoundType get selectedType => _selectedType;
  bool get enabled => _enabled;
  bool get audioUnlocked => _audioUnlocked;
  bool get isInitialized => _initialized;
  bool get isAlertLoopActive => _isLoopPlaying;
  int get alertingOrderCount => _ringingOrderIds.length;

  Future<void> initialize() async {
    if (_initialized) return;

    final prefs = await SharedPreferences.getInstance();
    _selectedType = OrderAlertSoundType.fromStorageKey(
      prefs.getString(_soundTypeKey),
    );
    _enabled = prefs.getBool(_soundEnabledKey) ?? true;
    _initialized = true;
  }

  Future<void> setSelectedType(OrderAlertSoundType type) async {
    _selectedType = type;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_soundTypeKey, type.storageKey);

    if (_isLoopPlaying) {
      await stopAlertLoop();
      await startAlertLoop();
    }
  }

  Future<void> setEnabled(bool value) async {
    _enabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_soundEnabledKey, value);
    if (!value) {
      await stopAllAlerts();
    }
  }

  Future<void> unlockFromUserGesture() async {
    await unlockOrderAlertAudio();
    _audioUnlocked = true;
  }

  Future<void> previewSound([OrderAlertSoundType? type]) async {
    await unlockFromUserGesture();
    await playOrderAlertSound(type ?? _selectedType);
  }

  /// Keeps looping alert active while [pendingOrderIds] contains ringing orders.
  Future<void> syncPendingAlerts(
    Set<String> pendingOrderIds, {
    Set<String>? newlyDetected,
  }) async {
    if (!_enabled) return;

    _ringingOrderIds.removeWhere((id) => !pendingOrderIds.contains(id));

    if (newlyDetected != null) {
      for (final id in newlyDetected) {
        if (pendingOrderIds.contains(id)) {
          _ringingOrderIds.add(id);
        }
      }
    }

    if (_ringingOrderIds.isEmpty) {
      await stopAlertLoop();
    } else {
      await startAlertLoop();
    }
  }

  /// Stops alert for one order immediately (accept / archive / status change).
  Future<void> acknowledgeOrder(String orderId) async {
    _ringingOrderIds.remove(orderId);
    if (_ringingOrderIds.isEmpty) {
      await stopAlertLoop();
    }
  }

  /// Temporary mute: stop sound now without accepting orders.
  Future<void> stopAllAlerts() async {
    _ringingOrderIds.clear();
    await stopAlertLoop();
  }

  Future<void> startAlertLoop() async {
    if (!_enabled || _ringingOrderIds.isEmpty) return;

    await unlockFromUserGesture();
    _isLoopPlaying = true;

    try {
      await startLoopingOrderAlert(_selectedType);
    } catch (error, stackTrace) {
      _isLoopPlaying = false;
      if (kDebugMode) {
        debugPrint('Order alert loop failed: $error\n$stackTrace');
      }
    }
  }

  Future<void> stopAlertLoop() async {
    if (!_isLoopPlaying) {
      await stopOrderAlertLoop();
      return;
    }

    _isLoopPlaying = false;
    await stopOrderAlertLoop();
  }

  @Deprecated('Use syncPendingAlerts for looping alerts')
  Future<void> playNewOrderAlert() async {
    if (!_enabled) return;
    await startAlertLoop();
  }
}

Future<void> playNewOrderSound() =>
    OrderAlertSoundService.instance.playNewOrderAlert();
