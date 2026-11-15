import 'dart:async';

import 'pos_hardware_bridge.dart';

/// Web hardware bridge: keyboard-wedge scanners only (no USB host APIs).
class _WebHardwareBridge implements PosHardwareBridge {
  final _controller = StreamController<String>.broadcast();

  @override
  Future<void> initialize() async {}

  @override
  Stream<String> get externalBarcodeCodes => _controller.stream;

  @override
  Future<void> openCashDrawer() async {}

  @override
  bool get supportsDirectUsbPrinter => false;
}

PosHardwareBridge createPosHardwareBridge() => _WebHardwareBridge();
