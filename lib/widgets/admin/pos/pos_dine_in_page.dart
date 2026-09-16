import 'dart:async';

import 'package:flutter/material.dart';

import '../../../models/dining_table.dart';
import '../../../services/admin_auth_service.dart';
import '../../../services/dining_tables_service.dart';
import '../../../services/table_floor_live_service.dart';
import '../admin_pos_panel.dart';
import 'pos_action_hub.dart';
import 'pos_sync_status_badge.dart';
import 'pos_table_floor_map.dart';

class PosDineInPage extends StatefulWidget {
  const PosDineInPage({super.key, this.restaurantId, this.onOrderSubmitted});

  final String? restaurantId;
  final VoidCallback? onOrderSubmitted;

  @override
  State<PosDineInPage> createState() => _PosDineInPageState();
}

class _PosDineInPageState extends State<PosDineInPage> {
  var _loading = true;
  String? _error;
  List<DiningTable> _tables = const [];
  DiningTable? _activeTable;
  Timer? _elapsedTimer;
  Timer? _pollTimer;
  StreamSubscription<List<Map<String, dynamic>>>? _liveSub;
  var _requestingCheck = false;
  List<Map<String, dynamic>> _liveOverlays = const [];

  String get _restaurantId =>
      widget.restaurantId ?? AdminAuthService.instance.restaurantId ?? '';

  @override
  void initState() {
    super.initState();
    unawaited(_hydrateCache());
    _load();
    _elapsedTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted && _activeTable == null) setState(() {});
    });
    _pollTimer = Timer.periodic(const Duration(seconds: 8), (_) {
      if (mounted && _activeTable == null) unawaited(_load(silent: true));
    });
    _liveSub = TableFloorLiveService.instance.watch(_restaurantId).listen((
      overlays,
    ) {
      if (!mounted) return;
      DiningTable? active = _activeTable;
      final currentActive = active;
      if (currentActive != null) {
        for (final overlay in overlays) {
          if (overlay['tableId']?.toString() == currentActive.id) {
            active = TableFloorLiveService.instance.mergeOverlay(
              currentActive,
              overlay,
            );
            break;
          }
        }
      }
      setState(() {
        _liveOverlays = overlays;
        _activeTable = active;
      });
    });
  }

  @override
  void dispose() {
    _elapsedTimer?.cancel();
    _pollTimer?.cancel();
    _liveSub?.cancel();
    super.dispose();
  }

  List<DiningTable> get _visibleTables =>
      TableFloorLiveService.instance.mergeOverlays(_tables, _liveOverlays);

  Future<void> _hydrateCache() async {
    final cached = await TableFloorLiveService.instance.loadCached(
      _restaurantId,
    );
    if (!mounted || cached.isEmpty) return;
    setState(() {
      _tables = cached;
      _loading = false;
    });
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        if (_tables.isEmpty) _loading = true;
        _error = null;
      });
    }
    try {
      final tables = await DiningTablesService.instance.fetchTables();
      if (!mounted) return;
      DiningTable? active;
      if (_activeTable != null) {
        for (final table in tables) {
          if (table.id == _activeTable!.id) {
            active = table;
            break;
          }
        }
      }
      setState(() {
        _tables = tables;
        _activeTable = active;
        _loading = false;
      });
      unawaited(
        TableFloorLiveService.instance.persistCache(_restaurantId, tables),
      );
      unawaited(
        TableFloorLiveService.instance.publishAll(tables, _restaurantId),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _openTable(DiningTable table) async {
    if (table.isWaiterCall) {
      final note = table.waiterNote;
      final ack = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('طلب ويتر — ${table.displayName}'),
          content: Text(note.isEmpty ? 'الزبون طلب الويتر.' : note),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('لاحقاً'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('تم الاطلاع'),
            ),
          ],
        ),
      );
      if (ack == true) {
        try {
          await DiningTablesService.instance.updateSession(
            table.id,
            cartItems: DiningTablesService.cartItemsFromSession(
              table.activeSession?.cartItems ?? const [],
            ),
            waiterRequested: false,
          );
        } catch (_) {}
      }
    }
    try {
      final opened = table.activeSession == null
          ? await DiningTablesService.instance.openSession(table.id)
          : table;
      if (!mounted) return;
      setState(() => _activeTable = opened);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
        ),
      );
    }
  }

  void _onSessionUpdated(DiningTable table) {
    setState(() {
      _activeTable = table;
      _tables = [
        for (final entry in _tables)
          if (entry.id == table.id) table else entry,
      ];
    });
    unawaited(TableFloorLiveService.instance.publish(table, _restaurantId));
  }

  void _onKitchenSent() {
    if (!mounted) return;
    setState(() => _activeTable = null);
  }

  void _onReleased() {
    final releasedId = _activeTable?.id;
    DiningTable? releasedTable;
    setState(() {
      _activeTable = null;
      if (releasedId != null) {
        _tables = [
          for (final table in _tables)
            if (table.id == releasedId)
              releasedTable = table.copyWith(
                status: DiningTableStatus.available,
                clearSession: true,
              )
            else
              table,
        ];
      }
    });
    unawaited(
      TableFloorLiveService.instance.persistCache(_restaurantId, _tables),
    );
    if (releasedTable != null) {
      unawaited(
        TableFloorLiveService.instance.publish(releasedTable!, _restaurantId),
      );
    }
    widget.onOrderSubmitted?.call();
  }

  Future<void> _requestCheck() async {
    final table = _activeTable;
    if (table == null || table.isAwaitingCheck) return;
    setState(() => _requestingCheck = true);
    try {
      final updated = await DiningTablesService.instance.updateSession(
        table.id,
        cartItems: DiningTablesService.cartItemsFromSession(
          table.activeSession?.cartItems ?? const [],
        ),
        customerName: table.activeSession?.customerName,
        phone: table.activeSession?.phone,
        checkRequested: true,
      );
      if (!mounted) return;
      _onSessionUpdated(updated);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
        ),
      );
    } finally {
      if (mounted) setState(() => _requestingCheck = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF6B1124)),
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => _load(),
                child: const Text('إعادة المحاولة'),
              ),
            ],
          ),
        ),
      );
    }

    if (_activeTable != null) {
      final awaiting = _activeTable!.isAwaitingCheck;
      final requestedPayment = _activeTable!.requestedPaymentMethod == 'knet'
          ? 'Knet'
          : 'كاش';
      return Column(
        children: [
          Material(
            color: awaiting ? PosOpsColors.alert : const Color(0xFF2C353F),
            child: ListTile(
              leading: IconButton(
                icon: const Icon(Icons.arrow_forward, color: Colors.white),
                onPressed: () => setState(() => _activeTable = null),
              ),
              title: Text(
                '${_activeTable!.displayName} — ${_activeTable!.zone}',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              subtitle: Text(
                awaiting
                    ? 'طلب حساب — ${_activeTable!.requestedBillTotal.toStringAsFixed(3)} د.ك — $requestedPayment'
                    : 'طلب صالة: أرسل للمطبخ ثم أغلق الحساب عند الدفع',
                style: const TextStyle(color: Colors.white70),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton(
                    onPressed: _requestingCheck || awaiting
                        ? null
                        : _requestCheck,
                    child: Text(
                      awaiting ? 'بانتظار الحساب' : 'طلب الحساب',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const PosSyncStatusBadge(compact: true),
                  IconButton(
                    icon: const Icon(Icons.refresh, color: Colors.white),
                    onPressed: () => _load(),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: AdminPosPanel(
              restaurantId: _restaurantId.isEmpty ? null : _restaurantId,
              dineInTable: _activeTable,
              onDineInSessionUpdated: _onSessionUpdated,
              onDineInKitchenSent: _onKitchenSent,
              onDineInReleased: _onReleased,
              onOrderSubmitted: widget.onOrderSubmitted,
            ),
          ),
        ],
      );
    }

    return PosTableFloorMap(
      tables: _visibleTables,
      onOpenTable: _openTable,
      onRefresh: () => _load(),
    );
  }
}
