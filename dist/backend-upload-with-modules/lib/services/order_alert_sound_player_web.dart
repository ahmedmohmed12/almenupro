import 'dart:async';
import 'dart:html' as html;

import '../models/order_alert_sound.dart';

final _players = <OrderAlertSoundType, html.AudioElement>{};
Timer? _keepAliveTimer;
var _keepAliveAttached = false;
var _audioUnlocked = false;
var _looping = false;
OrderAlertSoundType? _loopingType;

String _assetPath(OrderAlertSoundType type) {
  switch (type) {
    case OrderAlertSoundType.bell:
      return 'assets/assets/sounds/order_bell.wav';
    case OrderAlertSoundType.soft:
      return 'assets/assets/sounds/order_soft.wav';
    case OrderAlertSoundType.alarm:
      return 'assets/assets/sounds/order_alarm.wav';
  }
}

html.AudioElement _playerFor(OrderAlertSoundType type) {
  return _players.putIfAbsent(
    type,
    () => html.AudioElement(_assetPath(type))..preload = 'auto',
  );
}

void _attachBackgroundKeepAlive() {
  if (_keepAliveAttached) return;
  _keepAliveAttached = true;

  html.document.onVisibilityChange.listen((_) {
    if (_looping) {
      unawaited(_resumeLoopIfNeeded());
    }
  });

  _keepAliveTimer ??= Timer.periodic(const Duration(seconds: 2), (_) {
    if (!_looping || _loopingType == null) return;
    unawaited(_resumeLoopIfNeeded());
  });
}

Future<void> _resumeLoopIfNeeded() async {
  if (!_looping || _loopingType == null) return;

  final player = _playerFor(_loopingType!);
  player.loop = true;

  if (player.paused || player.ended) {
    player.currentTime = 0;
    try {
      await player.play();
    } catch (_) {
      _audioUnlocked = false;
    }
  }
}

Future<void> unlockOrderAlertAudio() async {
  _attachBackgroundKeepAlive();

  for (final type in OrderAlertSoundType.values) {
    _playerFor(type);
  }

  try {
    final probe = _playerFor(OrderAlertSoundType.soft);
    probe.loop = false;
    probe.volume = 0.01;
    await probe.play();
    probe.pause();
    probe.currentTime = 0;
    probe.volume = 1;
    _audioUnlocked = true;
  } catch (_) {
    _audioUnlocked = false;
  }
}

Future<void> playOrderAlertSound(OrderAlertSoundType type) async {
  final player = _playerFor(type);
  player.loop = false;
  player.currentTime = 0;

  try {
    await player.play();
  } catch (_) {
    _audioUnlocked = false;
  }
}

Future<void> startLoopingOrderAlert(OrderAlertSoundType type) async {
  _attachBackgroundKeepAlive();

  if (_looping && _loopingType == type) {
    await _resumeLoopIfNeeded();
    return;
  }

  await stopOrderAlertLoop();

  final player = _playerFor(type);
  player.loop = true;
  player.currentTime = 0;
  _looping = true;
  _loopingType = type;

  try {
    await player.play();
  } catch (_) {
    _looping = false;
    _loopingType = null;
    _audioUnlocked = false;
  }
}

Future<void> stopOrderAlertLoop() async {
  _looping = false;
  _loopingType = null;

  for (final player in _players.values) {
    player.loop = false;
    player.pause();
    player.currentTime = 0;
  }
}

bool get isOrderAlertAudioUnlocked => _audioUnlocked;
bool get isOrderAlertLoopActive => _looping;
