import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/order.dart';
import '../utils/order_channel_utils.dart';
import '../utils/pos_receipt_html.dart';
import 'admin_auth_service.dart';
import 'order_alert_sound_service.dart';
import 'orders_service.dart';
import 'pos_operations_service.dart';
import 'pos_print_helper.dart';

/// 10-second incoming-order countdown with auto-accept + hidden thermal print.
class IncomingOrderAutoAcceptService extends ChangeNotifier {
  IncomingOrderAutoAcceptService._();

  static final IncomingOrderAutoAcceptService instance =
      IncomingOrderAutoAcceptService._();

  static const countdownDuration = Duration(seconds: 10);

  final Map<String, _TrackedIncomingOrder> _tracked = {};
  final Set<String> _inFlight = {};
  final Set<String> _printed = {};
  final Set<String> _warnedNoShift = {};
  final ValueNotifier<String?> shiftReadinessWarning = ValueNotifier(null);
  Timer? _ticker;

  bool get hasActiveCountdowns => _tracked.isNotEmpty;

  int? remainingSeconds(String orderId) {
    final tracked = _tracked[orderId];
    if (tracked == null) return null;
    final left = tracked.deadline.difference(DateTime.now()).inSeconds;
    return left < 0 ? 0 : left;
  }

  void syncPendingIds(Set<String> pendingIds) {
    final removed = _tracked.keys
        .where((id) => !pendingIds.contains(id))
        .toList(growable: false);
    for (final id in removed) {
      _tracked.remove(id);
      _warnedNoShift.remove(id);
    }
    if (removed.isNotEmpty) notifyListeners();
    _ensureTicker();
  }

  bool _heldForCashierEdit(Order order) =>
      isTalabatOrder(order) || isKeetaOrder(order) || isJahezOrder(order);

  void trackNewOrder(Order order) {
    if (AdminAuthService.instance.isKitchen) return;
    if (order.status != OrderStatus.pending) return;
    if (_heldForCashierEdit(order)) return;
    if (!isOnlineMenuOrder(order)) return;
    if (_tracked.containsKey(order.id) || _inFlight.contains(order.id)) return;

    _tracked[order.id] = _TrackedIncomingOrder(
      order: order,
      deadline: DateTime.now().add(countdownDuration),
    );
    if (!_hasOpenCashierShift()) {
      _publishNoOpenShiftWarning(order);
    }
    _ensureTicker();
    notifyListeners();
  }

  /// Resume the 10s window from [Order.createdAt], or auto-accept if it already expired.
  void focusDeepLinkedOrder(Order order) {
    if (AdminAuthService.instance.isKitchen) return;
    if (order.status != OrderStatus.pending) return;
    if (_heldForCashierEdit(order)) return;
    if (!isOnlineMenuOrder(order)) return;
    if (_inFlight.contains(order.id)) return;

    final existing = _tracked[order.id];
    final deadline =
        existing?.deadline ?? order.createdAt.add(countdownDuration);
    _tracked[order.id] = _TrackedIncomingOrder(
      order: order,
      deadline: deadline,
    );
    if (!_hasOpenCashierShift()) {
      _publishNoOpenShiftWarning(order);
    }
    _ensureTicker();
    notifyListeners();

    if (!DateTime.now().isBefore(deadline)) {
      unawaited(_accept(order, autoFallback: true));
    }
  }

  void cancel(String orderId) {
    if (_tracked.remove(orderId) != null) {
      notifyListeners();
    }
    _ensureTicker();
  }

  Future<void> acceptManually(Order order) {
    return _accept(order, autoFallback: false);
  }

  void _ensureTicker() {
    if (_tracked.isEmpty) {
      _ticker?.cancel();
      _ticker = null;
      return;
    }
    _ticker ??= Timer.periodic(const Duration(seconds: 1), (_) {
      _onTick();
    });
  }

  void resumeFromBackground() {
    _ensureTicker();
    _onTick();
  }

  String _countdownFingerprint = '';

  void _onTick() {
    if (_tracked.isEmpty) {
      _ensureTicker();
      if (_countdownFingerprint.isNotEmpty) {
        _countdownFingerprint = '';
        notifyListeners();
      }
      return;
    }

    final now = DateTime.now();
    final fingerprint = _tracked.entries
        .map((entry) {
          final left = entry.value.deadline.difference(now).inSeconds;
          return '${entry.key}:${left < 0 ? 0 : left}';
        })
        .join('|');
    if (fingerprint != _countdownFingerprint) {
      _countdownFingerprint = fingerprint;
      notifyListeners();
    }
    final expired = _tracked.values
        .where((entry) => !now.isBefore(entry.deadline))
        .map((entry) => entry.order)
        .toList(growable: false);
    for (final order in expired) {
      unawaited(_accept(order, autoFallback: true));
    }
  }

  bool _hasOpenCashierShift() {
    final shift = PosOperationsService.instance.activeShift;
    return shift != null && shift.isOpen;
  }

  void _publishNoOpenShiftWarning(Order order) {
    if (!_warnedNoShift.add(order.id)) return;
    debugPrint(
      'Incoming order ${order.id} is waiting: no cashier shift is open.',
    );
    shiftReadinessWarning.value = order.id;
  }

  ({String cashierId, String cashierName, String shiftId}) _receivingIdentity(
    Order order,
  ) {
    final shift = PosOperationsService.instance.activeShift;
    final cashier = PosOperationsService.instance.cashierSession;
    final staffId = cashier?.staff.id.trim() ?? '';
    final staffName = cashier?.staff.name.trim() ?? '';
    final shiftCashierId = shift?.cashierId.trim() ?? '';
    final shiftCashierName = shift?.cashierName.trim() ?? '';
    final sessionName =
        AdminAuthService.instance.session?.staffName?.trim() ?? '';
    final sessionId = AdminAuthService.instance.session?.staffId?.trim() ?? '';
    final cashierId = [
      staffId,
      shiftCashierId,
      sessionId,
      order.cashierId ?? '',
    ].firstWhere((value) => value.trim().isNotEmpty, orElse: () => '');
    final cashierName = [
      staffName,
      shiftCashierName,
      sessionName,
      order.cashierName ?? '',
    ].firstWhere((value) => value.trim().isNotEmpty, orElse: () => 'كاشير');
    return (
      cashierId: cashierId,
      cashierName: cashierName,
      shiftId: shift?.id.trim() ?? order.shiftId ?? '',
    );
  }

  Future<void> _accept(Order order, {required bool autoFallback}) async {
    if (_inFlight.contains(order.id)) return;
    final unassignedConfirmed =
        order.status == OrderStatus.confirmed &&
        (order.cashierId ?? '').trim().isEmpty &&
        (order.shiftId ?? '').trim().isEmpty &&
        order.receivedByCashierLabel.trim().isEmpty;
    if (order.status != OrderStatus.pending &&
        _tracked[order.id] == null &&
        !unassignedConfirmed) {
      return;
    }

    if (autoFallback && !_hasOpenCashierShift()) {
      _publishNoOpenShiftWarning(order);
      return;
    }

    _inFlight.add(order.id);
    _tracked.remove(order.id);
    notifyListeners();
    _ensureTicker();

    await OrderAlertSoundService.instance.acknowledgeOrder(order.id);

    try {
      final identity = _receivingIdentity(order);
      await OrdersService.instance.updateOrderStatus(
        order.id,
        OrderStatus.confirmed,
        shiftId: identity.shiftId.isNotEmpty ? identity.shiftId : null,
        cashierId: identity.cashierId.isNotEmpty ? identity.cashierId : null,
        cashierName: identity.cashierName.isNotEmpty
            ? identity.cashierName
            : null,
        autoAccepted: autoFallback,
        acceptedBy: AdminAuthService.instance.auditUserId,
        acceptedByName: AdminAuthService.instance.auditUserName,
      );

      await _printOnce(order.copyWith(status: OrderStatus.confirmed));
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint('Incoming order accept failed: $error\n$stackTrace');
      }
      if (autoFallback) {
        _tracked[order.id] = _TrackedIncomingOrder(
          order: order,
          deadline: DateTime.now().add(const Duration(seconds: 3)),
        );
        _ensureTicker();
        notifyListeners();
        return;
      }
      rethrow;
    } finally {
      _inFlight.remove(order.id);
    }
  }

  Future<void> _printOnce(Order order) async {
    if (!_printed.add(order.id)) return;
    try {
      final printed = await PosPrintHelper.printIncomingAcceptance(
        order: order,
        kind: PosReceiptKind.kitchen,
      );
      if (!printed) {
        _printed.remove(order.id);
        _publishNoOpenShiftWarning(order);
      }
    } catch (error, stackTrace) {
      _printed.remove(order.id);
      if (kDebugMode) {
        debugPrint('Incoming order auto-print failed: $error\n$stackTrace');
      }
    }
  }
}

class _TrackedIncomingOrder {
  const _TrackedIncomingOrder({required this.order, required this.deadline});

  final Order order;
  final DateTime deadline;
}
