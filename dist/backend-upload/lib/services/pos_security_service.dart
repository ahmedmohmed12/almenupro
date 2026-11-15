import 'dart:async';

import 'package:flutter/foundation.dart';

typedef PosActivityCallback = void Function();

class PosSecurityService {
  PosSecurityService._();

  static final PosSecurityService instance = PosSecurityService._();

  Timer? _idleTimer;
  var _locked = false;
  var _autoLockMinutes = 5;
  PosActivityCallback? _onLockChanged;

  bool get isLocked => _locked;
  int get autoLockMinutes => _autoLockMinutes;

  void configure({
    required int autoLockMinutes,
    PosActivityCallback? onLockChanged,
  }) {
    _autoLockMinutes = autoLockMinutes.clamp(1, 120);
    _onLockChanged = onLockChanged;
    resetIdleTimer();
  }

  void resetIdleTimer() {
    _idleTimer?.cancel();
    if (_autoLockMinutes <= 0) return;
    _idleTimer = Timer(Duration(minutes: _autoLockMinutes), lock);
  }

  void registerActivity() {
    if (!_locked) {
      resetIdleTimer();
    }
  }

  void lock() {
    if (_locked) return;
    _locked = true;
    _idleTimer?.cancel();
    _onLockChanged?.call();
    if (kDebugMode) {
      debugPrint('POS locked after inactivity');
    }
  }

  void unlock() {
    _locked = false;
    resetIdleTimer();
    _onLockChanged?.call();
  }

  void dispose() {
    _idleTimer?.cancel();
    _onLockChanged = null;
  }
}
