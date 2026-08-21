import 'package:flutter/material.dart';

import '../../../models/dining_table.dart';
import '../../../services/admin_auth_service.dart';
import '../../../services/dining_tables_service.dart';
import '../admin_pos_panel.dart';

class PosDineInPage extends StatefulWidget {
  const PosDineInPage({
    super.key,
    this.restaurantId,
    this.onOrderSubmitted,
  });

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

  String get _restaurantId =>
      widget.restaurantId ??
      AdminAuthService.instance.restaurantId ??
      '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
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
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _openTable(DiningTable table) async {
    try {
      final opened = table.activeSession == null
          ? await DiningTablesService.instance.openSession(table.id)
          : table;
      if (!mounted) return;
      setState(() => _activeTable = opened);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString().replaceFirst('Exception: ', ''))),
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
  }

  Future<void> _onReleased() async {
    setState(() => _activeTable = null);
    await _load();
    widget.onOrderSubmitted?.call();
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
              FilledButton(onPressed: _load, child: const Text('إعادة المحاولة')),
            ],
          ),
        ),
      );
    }

    if (_activeTable != null) {
      return Column(
        children: [
          Material(
            color: const Color(0xFF2C353F),
            child: ListTile(
              leading: IconButton(
                icon: const Icon(Icons.arrow_forward, color: Colors.white),
                onPressed: () => setState(() => _activeTable = null),
              ),
              title: Text(
                '${_activeTable!.displayName} — ${_activeTable!.zone}',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
              subtitle: const Text(
                'طلب صالة: أرسل للمطبخ ثم أغلق الحساب عند الدفع',
                style: TextStyle(color: Colors.white70),
              ),
              trailing: IconButton(
                icon: const Icon(Icons.refresh, color: Colors.white),
                onPressed: _load,
              ),
            ),
          ),
          Expanded(
            child: AdminPosPanel(
              restaurantId: _restaurantId.isEmpty ? null : _restaurantId,
              dineInTable: _activeTable,
              onDineInSessionUpdated: _onSessionUpdated,
              onDineInReleased: _onReleased,
              onOrderSubmitted: widget.onOrderSubmitted,
            ),
          ),
        ],
      );
    }

    final grouped = <String, List<DiningTable>>{};
    for (final table in _tables) {
      grouped.putIfAbsent(table.zone, () => []).add(table);
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'طاولات الصالة',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          Text(
            'اختر طاولة لفتح الجلسة وتسجيل الطلب.',
            style: TextStyle(color: Colors.grey.shade700),
          ),
          const SizedBox(height: 16),
          if (_tables.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 48),
              child: Center(child: Text('لا توجد طاولات. أضفها من إدارة الطاولات.')),
            )
          else
            for (final entry in grouped.entries) ...[
              Text(
                entry.key,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final table in entry.value)
                    _FloorTableTile(
                      table: table,
                      onTap: () => _openTable(table),
                    ),
                ],
              ),
              const SizedBox(height: 20),
            ],
        ],
      ),
    );
  }
}

class _FloorTableTile extends StatelessWidget {
  const _FloorTableTile({required this.table, required this.onTap});

  final DiningTable table;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final occupied = table.isOccupied;
    return SizedBox(
      width: 150,
      height: 120,
      child: Material(
        color: occupied ? const Color(0xFFFFE0B2) : const Color(0xFFE8F5E9),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  table.displayName,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const Spacer(),
                Text('${table.capacity} مقاعد'),
                Text(
                  table.status.labelAr,
                  style: TextStyle(
                    color: occupied ? Colors.orange.shade900 : Colors.green.shade800,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
