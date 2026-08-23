import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/foundation.dart';

/// Silent thermal print via a connected QZ Tray client.
///
/// Returns `true` when QZ accepted the job. Returns `false` when QZ is
/// missing, disconnected, or the print call fails so callers can fall back
/// to the browser print path.
Future<bool> printReceiptSilently(Map<String, dynamic> orderData) async {
  try {
    if (!globalContext.has('AlMenuProQz')) {
      throw StateError('QZ Tray bridge is not loaded');
    }

    final bridge = globalContext.getProperty('AlMenuProQz'.toJS);
    if (bridge == null || bridge.isUndefined) {
      throw StateError('QZ Tray is not installed');
    }

    final jsObject = bridge as JSObject;
    final result = jsObject.callMethod(
      'printReceiptSilently'.toJS,
      orderData.jsify(),
    );
    if (result == null || result.isUndefined) {
      return false;
    }

    await (result as JSPromise).toDart;
    return true;
  } catch (error, stackTrace) {
    if (kDebugMode) {
      debugPrint('QZ Tray silent print failed: $error\n$stackTrace');
    }
    return false;
  }
}
