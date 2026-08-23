import 'package:flutter/foundation.dart';

/// Holds a pending deep-linked order ref until the authenticated UI can open it.
class AdminOrderFocusService extends ChangeNotifier {
  AdminOrderFocusService._();

  static final AdminOrderFocusService instance = AdminOrderFocusService._();

  String? _pendingOrderRef;
  String? _pendingRedirect;

  String? get pendingOrderRef => _pendingOrderRef;
  String? get pendingRedirect => _pendingRedirect;

  void rememberRedirect(String path) {
    _pendingRedirect = path;
    notifyListeners();
  }

  String? consumeRedirect() {
    final value = _pendingRedirect;
    _pendingRedirect = null;
    return value;
  }

  void requestOrder(String orderRef) {
    final ref = orderRef.trim();
    if (ref.isEmpty) return;
    _pendingOrderRef = ref;
    notifyListeners();
  }

  String? consumeOrder() {
    final value = _pendingOrderRef;
    _pendingOrderRef = null;
    notifyListeners();
    return value;
  }

  void clear() {
    _pendingOrderRef = null;
    _pendingRedirect = null;
    notifyListeners();
  }
}
