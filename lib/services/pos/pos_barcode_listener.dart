import 'dart:async';

import 'package:flutter/services.dart';

import '../../models/menu_item.dart';
import 'pos_hardware_bridge.dart';
import 'pos_catalog_match.dart';

/// Always-on barcode + keyboard-wedge listener for Web and Native Desktop.
///
/// Hardware wedges emit rapid key events ending with Enter. Native plugins can
/// also push codes through [PosHardwareBridge.externalBarcodeCodes].
class PosBarcodeListener {
  PosBarcodeListener({
    required this.resolveCatalog,
    required this.onItemMatched,
    required this.isEditingText,
    required this.isRouteCurrent,
  });

  final List<MenuItem> Function() resolveCatalog;
  final ValueChanged<MenuItem> onItemMatched;
  final bool Function() isEditingText;
  final bool Function() isRouteCurrent;

  String _buffer = '';
  DateTime? _lastAt;
  StreamSubscription<String>? _externalSub;
  var _attached = false;

  void attach() {
    if (_attached) return;
    _attached = true;
    HardwareKeyboard.instance.addHandler(_onKey);
    _externalSub = posHardwareBridge.externalBarcodeCodes.listen(_emitCode);
  }

  void detach() {
    if (!_attached) return;
    _attached = false;
    HardwareKeyboard.instance.removeHandler(_onKey);
    unawaited(_externalSub?.cancel());
    _externalSub = null;
    _buffer = '';
  }

  bool _onKey(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    if (isEditingText()) {
      _buffer = '';
      return false;
    }
    if (!isRouteCurrent()) {
      _buffer = '';
      return false;
    }

    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      final code = _buffer.trim();
      _buffer = '';
      if (code.length >= 3) {
        return _emitCode(code);
      }
      return false;
    }

    final character = event.character;
    if (character == null || character.isEmpty || character.length != 1) {
      return false;
    }
    if (!RegExp(r'[0-9A-Za-z\-]').hasMatch(character)) return false;

    final now = DateTime.now();
    final last = _lastAt;
    if (last != null &&
        now.difference(last) > const Duration(milliseconds: 120)) {
      _buffer = '';
    }
    _lastAt = now;
    _buffer += character;
    return false;
  }

  bool _emitCode(String code) {
    final match = posFindBarcodeMatch(resolveCatalog(), code.trim());
    if (match == null) return false;
    onItemMatched(match);
    return true;
  }
}
