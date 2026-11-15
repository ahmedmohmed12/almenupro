import 'dart:async';

import 'package:flutter/services.dart';

import '../models/order_alert_sound.dart';

Timer? _loopTimer;
var _looping = false;

Future<void> unlockOrderAlertAudio() async {}

Future<void> playOrderAlertSound(OrderAlertSoundType type) async {
  await _playOnce(type);
}

Future<void> startLoopingOrderAlert(OrderAlertSoundType type) async {
  if (_looping) return;
  _looping = true;
  await _playOnce(type);
  _loopTimer?.cancel();
  _loopTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
    if (!_looping) return;
    await _playOnce(type);
  });
}

Future<void> stopOrderAlertLoop() async {
  _looping = false;
  _loopTimer?.cancel();
  _loopTimer = null;
}

Future<void> _playOnce(OrderAlertSoundType type) async {
  switch (type) {
    case OrderAlertSoundType.bell:
      await SystemSound.play(SystemSoundType.alert);
    case OrderAlertSoundType.soft:
      await SystemSound.play(SystemSoundType.click);
    case OrderAlertSoundType.alarm:
      await SystemSound.play(SystemSoundType.alert);
      await Future<void>.delayed(const Duration(milliseconds: 180));
      await SystemSound.play(SystemSoundType.alert);
  }
}

bool get isOrderAlertLoopActive => _looping;
