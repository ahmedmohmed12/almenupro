import 'pos_hardware_bridge_stub.dart'
    if (dart.library.html) 'pos_hardware_bridge_web.dart'
    if (dart.library.io) 'pos_hardware_bridge_io.dart';

/// Platform hardware hooks for POS (barcode wedges, cash drawer, USB printers).
abstract class PosHardwareBridge {
  Future<void> initialize();

  /// Optional stream of scanner codes from a native HID/serial path.
  /// Web wedges still arrive as keyboard events via [PosBarcodeListener].
  Stream<String> get externalBarcodeCodes;

  Future<void> openCashDrawer();

  bool get supportsDirectUsbPrinter;
}

final PosHardwareBridge posHardwareBridge = createPosHardwareBridge();
