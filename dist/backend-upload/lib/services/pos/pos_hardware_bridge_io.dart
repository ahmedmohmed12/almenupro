import 'dart:async';

import 'package:flutter/foundation.dart';

import 'pos_hardware_bridge.dart';

/// Native desktop hardware bridge.
///
/// Ready for Hive/Isar-adjacent device drivers and USB/serial scanner plugins.
/// Keyboard-wedge scanners already work through [PosBarcodeListener].
class _IoHardwareBridge implements PosHardwareBridge {
  final _controller = StreamController<String>.broadcast();

  @override
  Future<void> initialize() async {
    debugPrint(
      'POS native hardware bridge ready '
      '(USB/serial hooks can attach to externalBarcodeCodes)',
    );
  }

  @override
  Stream<String> get externalBarcodeCodes => _controller.stream;

  /// Inject a code from a future native scanner plugin.
  void debugEmitBarcode(String code) {
    final trimmed = code.trim();
    if (trimmed.isNotEmpty) _controller.add(trimmed);
  }

  @override
  Future<void> openCashDrawer() async {
    // Hook point for ESC/POS cash-drawer pulse on Windows/macOS later.
    debugPrint('POS cash drawer pulse requested (native hook)');
  }

  @override
  bool get supportsDirectUsbPrinter => true;
}

PosHardwareBridge createPosHardwareBridge() => _IoHardwareBridge();
