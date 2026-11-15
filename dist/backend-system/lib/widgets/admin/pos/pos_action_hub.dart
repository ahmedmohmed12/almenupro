import 'dart:async';

import 'package:flutter/material.dart';

import '../../../models/order.dart';
import '../../../services/admin_order_monitor_service.dart';
import '../../../services/dining_tables_service.dart';
import '../../../services/orders_service.dart';
import 'pos_theme.dart';

abstract final class PosOpsColors {
  static const ready = Color(0xFF10B981);
  static const busy = Color(0xFFF59E0B);
  static const waiter = Color(0xFF3B82F6);
  static const alert = Color(0xFFEF4444);
}

enum PosOpsTone { ready, busy, waiter, alert }

class PosActionHub extends StatefulWidget {
  const PosActionHub({
    super.key,
    required this.onOpenTables,
    required this.onOpenDriverHandoff,
    required this.onOpenOnlineOrders,
    this.tableManagementEnabled = false,
    this.compact = false,
  });

  final VoidCallback onOpenTables;
  final VoidCallback onOpenDriverHandoff;
  final VoidCallback onOpenOnlineOrders;
  final bool tableManagementEnabled;
  final bool compact;

  @override
  State<PosActionHub> createState() => _PosActionHubState();
}

class _PosActionHubState extends State<PosActionHub> {
  Timer? _tablesTimer;
  var _occupiedTables = 0;
  var _awaitingCheck = 0;
  var _waiterCalls = 0;
  String _awaitingSummary = '';

  @override
  void initState() {
    super.initState();
    if (widget.tableManagementEnabled) {
      unawaited(_refreshTables());
    }
    _tablesTimer = Timer.periodic(const Duration(seconds: 12), (_) {
      if (widget.tableManagementEnabled) {
        unawaited(_refreshTables());
      }
    });
  }

  @override
  void didUpdateWidget(covariant PosActionHub oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.tableManagementEnabled && widget.tableManagementEnabled) {
      unawaited(_refreshTables());
    }
    if (oldWidget.tableManagementEnabled && !widget.tableManagementEnabled) {
      setState(() {
        _occupiedTables = 0;
        _awaitingCheck = 0;
        _waiterCalls = 0;
        _awaitingSummary = '';
      });
    }
  }

  @override
  void dispose() {
    _tablesTimer?.cancel();
    super.dispose();
  }

  Future<void> _refreshTables() async {
    try {
      final tables = await DiningTablesService.instance.fetchTables();
      var occupied = 0;
      var awaiting = 0;
      var waiter = 0;
      String awaitingSummary = '';
      for (final table in tables) {
        if (table.isAwaitingCheck) {
          awaiting += 1;
          occupied += 1;
          if (awaitingSummary.isEmpty) {
            final payment = table.requestedPaymentMethod == 'knet'
                ? 'Knet'
                : 'كاش';
            awaitingSummary =
                '${table.displayName} • ${table.requestedBillTotal.toStringAsFixed(3)} • $payment';
          }
        } else if (table.isWaiterCall) {
          waiter += 1;
        } else if (table.isOccupied) {
          occupied += 1;
        }
      }
      if (!mounted) return;
      setState(() {
        _occupiedTables = occupied;
        _awaitingCheck = awaiting;
        _waiterCalls = waiter;
        _awaitingSummary = awaitingSummary;
      });
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(10, widget.compact ? 4 : 6, 10, 2),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final viewport = MediaQuery.sizeOf(context).width;
          final mobile = viewport < PosTheme.mobileBreakpoint;
          final tablet =
              !widget.compact &&
              viewport >= PosTheme.mobileBreakpoint &&
              viewport <= PosTheme.tabletMax;
          final hubHeight = widget.compact ? 42.0 : 52.0;
          final cards = [
            if (widget.tableManagementEnabled)
              _PosActionCard(
                icon: Icons.table_restaurant,
                title: 'الطاولات',
                count: _awaitingCheck > 0
                    ? _awaitingCheck
                    : (_waiterCalls > 0 ? _waiterCalls : _occupiedTables),
                readyBadge: 'جاهز',
                pendingSuffix: _awaitingCheck > 0
                    ? (_awaitingSummary.isEmpty
                          ? 'طلب حساب'
                          : 'طلب حساب • $_awaitingSummary')
                    : (_waiterCalls > 0 ? 'طلب ويتر' : 'مشغولة'),
                tone: _awaitingCheck > 0
                    ? PosOpsTone.alert
                    : (_waiterCalls > 0
                          ? PosOpsTone.waiter
                          : (_occupiedTables > 0
                                ? PosOpsTone.busy
                                : PosOpsTone.ready)),
                onTap: widget.onOpenTables,
                enlargeTouch: tablet,
              ),
            StreamBuilder<List<Order>>(
              stream: OrdersService.instance.watchOrders(),
              initialData: const [],
              builder: (context, snapshot) {
                final handoff = (snapshot.data ?? [])
                    .where((order) => order.needsCashierHandoff)
                    .length;
                return _PosActionCard(
                  icon: Icons.moped,
                  title: 'استلام من السائق',
                  count: handoff,
                  readyBadge: 'جاهز',
                  pendingSuffix: 'بانتظار الصندوق',
                  tone: handoff > 0 ? PosOpsTone.busy : PosOpsTone.ready,
                  onTap: widget.onOpenDriverHandoff,
                  enlargeTouch: tablet,
                );
              },
            ),
            ValueListenableBuilder<int>(
              valueListenable: AdminOrderMonitorService.instance.pendingCount,
              builder: (context, onlineCount, _) {
                return _PosActionCard(
                  icon: Icons.language,
                  title: 'طلبات الموقع',
                  count: onlineCount,
                  readyBadge: 'جاهز',
                  pendingSuffix: 'طلبات معلقة',
                  tone: onlineCount > 0 ? PosOpsTone.alert : PosOpsTone.ready,
                  onTap: widget.onOpenOnlineOrders,
                  enlargeTouch: tablet,
                );
              },
            ),
          ];

          if (mobile) {
            return SizedBox(
              height: hubHeight,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: cards.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, index) =>
                    SizedBox(width: 200, child: cards[index]),
              ),
            );
          }

          return SizedBox(
            height: hubHeight,
            child: Row(
              children: [
                for (var i = 0; i < cards.length; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  Expanded(child: cards[i]),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _PosActionCard extends StatefulWidget {
  const _PosActionCard({
    required this.icon,
    required this.title,
    required this.count,
    required this.readyBadge,
    required this.pendingSuffix,
    required this.tone,
    required this.onTap,
    this.enlargeTouch = false,
  });

  final IconData icon;
  final String title;
  final int count;
  final String readyBadge;
  final String pendingSuffix;
  final PosOpsTone tone;
  final VoidCallback onTap;
  final bool enlargeTouch;

  @override
  State<_PosActionCard> createState() => _PosActionCardState();
}

class _PosActionCardState extends State<_PosActionCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _syncPulse();
  }

  @override
  void didUpdateWidget(covariant _PosActionCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tone != widget.tone) _syncPulse();
  }

  void _syncPulse() {
    if (widget.tone == PosOpsTone.ready) {
      _pulse.stop();
      _pulse.value = 0;
    } else {
      _pulse.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  Color get _base => switch (widget.tone) {
    PosOpsTone.ready => PosOpsColors.ready,
    PosOpsTone.busy => PosOpsColors.busy,
    PosOpsTone.waiter => PosOpsColors.waiter,
    PosOpsTone.alert => PosOpsColors.alert,
  };

  @override
  Widget build(BuildContext context) {
    final pending = widget.count > 0;
    final badge = pending
        ? '(${widget.count}) ${widget.pendingSuffix}'
        : widget.readyBadge;

    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, child) {
        final t = widget.tone == PosOpsTone.ready ? 0.0 : _pulse.value;
        final color = Color.lerp(_base, Colors.white, t * 0.16) ?? _base;
        return Material(
          color: color,
          borderRadius: BorderRadius.circular(14),
          elevation: pending ? 2 : 0,
          child: child,
        );
      },
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: widget.enlargeTouch ? 14 : 12,
          ),
          child: Row(
            children: [
              Icon(
                widget.icon,
                color: Colors.white,
                size: widget.enlargeTouch ? 22 : 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.22),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  badge,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
