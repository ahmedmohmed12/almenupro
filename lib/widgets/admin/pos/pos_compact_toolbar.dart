import 'dart:async';

import 'package:flutter/material.dart';

import '../../../models/order.dart';
import '../../../services/admin_order_monitor_service.dart';
import '../../../services/dining_tables_service.dart';
import '../../../services/orders_service.dart';
import 'pos_sync_status_badge.dart';
import 'pos_theme.dart';

/// Single thin POS header (≤45px): search/barcode + order modes + ops + shift.
class PosCompactToolbar extends StatefulWidget {
  const PosCompactToolbar({
    super.key,
    required this.orderMode,
    required this.onSelectOrderMode,
    required this.onOpenSearch,
    required this.onOpenBarcode,
    this.onOpenTables,
    this.onOpenDriverHandoff,
    this.onOpenOnlineOrders,
    this.tableManagementEnabled = false,
    this.showOrderModes = true,
    this.shiftLabel,
  });

  final String orderMode;
  final ValueChanged<String> onSelectOrderMode;
  final VoidCallback onOpenSearch;
  final VoidCallback onOpenBarcode;
  final VoidCallback? onOpenTables;
  final VoidCallback? onOpenDriverHandoff;
  final VoidCallback? onOpenOnlineOrders;
  final bool tableManagementEnabled;
  final bool showOrderModes;
  /// Optional short shift caption (e.g. cashier name) shown on the maroon bar.
  final String? shiftLabel;

  @override
  State<PosCompactToolbar> createState() => _PosCompactToolbarState();
}

class _PosCompactToolbarState extends State<PosCompactToolbar> {
  Timer? _tablesTimer;
  var _tableBadge = 0;
  var _tableTone = _OpsTone.ready;

  @override
  void initState() {
    super.initState();
    if (widget.tableManagementEnabled) {
      unawaited(_refreshTables());
      _tablesTimer = Timer.periodic(
        const Duration(seconds: 12),
        (_) => unawaited(_refreshTables()),
      );
    }
  }

  @override
  void didUpdateWidget(covariant PosCompactToolbar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.tableManagementEnabled && widget.tableManagementEnabled) {
      unawaited(_refreshTables());
      _tablesTimer?.cancel();
      _tablesTimer = Timer.periodic(
        const Duration(seconds: 12),
        (_) => unawaited(_refreshTables()),
      );
    }
    if (oldWidget.tableManagementEnabled && !widget.tableManagementEnabled) {
      _tablesTimer?.cancel();
      setState(() {
        _tableBadge = 0;
        _tableTone = _OpsTone.ready;
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
      for (final table in tables) {
        if (table.isAwaitingCheck) {
          awaiting += 1;
          occupied += 1;
        } else if (table.isWaiterCall) {
          waiter += 1;
        } else if (table.isOccupied) {
          occupied += 1;
        }
      }
      if (!mounted) return;
      setState(() {
        _tableBadge =
            awaiting > 0 ? awaiting : (waiter > 0 ? waiter : occupied);
        _tableTone = awaiting > 0
            ? _OpsTone.alert
            : (waiter > 0
                ? _OpsTone.waiter
                : (occupied > 0 ? _OpsTone.busy : _OpsTone.ready));
      });
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final shift = (widget.shiftLabel ?? '').trim();
    return Material(
      color: PosTheme.headerMaroon,
      child: SizedBox(
        height: PosTheme.headerHeight,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Row(
            children: [
              _IconBtn(
                tooltip: 'بحث (F4)',
                icon: Icons.search_rounded,
                onTap: widget.onOpenSearch,
              ),
              const SizedBox(width: 2),
              _IconBtn(
                tooltip: 'باركود',
                icon: Icons.qr_code_scanner_rounded,
                onTap: widget.onOpenBarcode,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    if (widget.showOrderModes) ...[
                      _ModeChip(
                        label: 'استلام',
                        icon: Icons.shopping_bag_outlined,
                        selected: widget.orderMode == 'takeaway' ||
                            widget.orderMode == 'local',
                        onSelected: () =>
                            widget.onSelectOrderMode('takeaway'),
                      ),
                      const SizedBox(width: 4),
                      _ModeChip(
                        label: 'توصيل',
                        icon: Icons.delivery_dining_rounded,
                        selected: widget.orderMode == 'delivery',
                        onSelected: () =>
                            widget.onSelectOrderMode('delivery'),
                      ),
                      const SizedBox(width: 4),
                      _ModeChip(
                        label: 'منصات',
                        icon: Icons.hub_outlined,
                        selected: widget.orderMode == 'platforms',
                        onSelected: () =>
                            widget.onSelectOrderMode('platforms'),
                      ),
                    ],
                    if (widget.onOpenTables != null &&
                        widget.tableManagementEnabled) ...[
                      if (widget.showOrderModes) const SizedBox(width: 6),
                      _OpsChip(
                        label: 'طاولات',
                        icon: Icons.table_restaurant_rounded,
                        count: _tableBadge,
                        tone: _tableTone,
                        onTap: widget.onOpenTables!,
                      ),
                    ],
                    if (widget.onOpenDriverHandoff != null) ...[
                      const SizedBox(width: 4),
                      StreamBuilder<List<Order>>(
                        stream: OrdersService.instance.watchOrders(),
                        initialData: const [],
                        builder: (context, snapshot) {
                          final handoff = (snapshot.data ?? [])
                              .where((order) => order.needsCashierHandoff)
                              .length;
                          return _OpsChip(
                            label: 'سائق',
                            icon: Icons.moped_rounded,
                            count: handoff,
                            tone:
                                handoff > 0 ? _OpsTone.busy : _OpsTone.ready,
                            onTap: widget.onOpenDriverHandoff!,
                          );
                        },
                      ),
                    ],
                    if (widget.onOpenOnlineOrders != null) ...[
                      const SizedBox(width: 4),
                      ValueListenableBuilder<int>(
                        valueListenable:
                            AdminOrderMonitorService.instance.pendingCount,
                        builder: (context, onlineCount, _) {
                          return _OpsChip(
                            label: 'موقع',
                            icon: Icons.language_rounded,
                            count: onlineCount,
                            tone: onlineCount > 0
                                ? _OpsTone.alert
                                : _OpsTone.ready,
                            onTap: widget.onOpenOnlineOrders!,
                          );
                        },
                      ),
                    ],
                  ],
                ),
              ),
              if (shift.isNotEmpty) ...[
                const SizedBox(width: 6),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 120),
                  child: Text(
                    shift,
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
              const SizedBox(width: 4),
              const Flexible(
                child: Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: PosSyncStatusBadge(compact: true),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _OpsTone { ready, busy, waiter, alert }

class _IconBtn extends StatelessWidget {
  const _IconBtn({
    required this.tooltip,
    required this.icon,
    required this.onTap,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: 34,
            height: 34,
            child: Icon(icon, size: 18, color: Colors.white),
          ),
        ),
      ),
    );
  }
}

class _ModeChip extends StatelessWidget {
  const _ModeChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? PosTheme.orange
          : Colors.white.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onSelected,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: Colors.white),
              const SizedBox(width: 4),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OpsChip extends StatelessWidget {
  const _OpsChip({
    required this.label,
    required this.icon,
    required this.count,
    required this.tone,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final int count;
  final _OpsTone tone;
  final VoidCallback onTap;

  Color get _color => switch (tone) {
        _OpsTone.ready => const Color(0xFF10B981),
        _OpsTone.busy => const Color(0xFFF59E0B),
        _OpsTone.waiter => const Color(0xFF3B82F6),
        _OpsTone.alert => const Color(0xFFEF4444),
      };

  @override
  Widget build(BuildContext context) {
    final active = count > 0;
    return Material(
      color: active ? _color : Colors.white.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 14,
                color: active ? Colors.white : _color,
              ),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: active ? Colors.white : Colors.white.withValues(alpha: 0.92),
                ),
              ),
              if (active) ...[
                const SizedBox(width: 4),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 0),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '$count',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 10,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
