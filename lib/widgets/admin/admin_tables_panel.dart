import 'package:flutter/material.dart';

import '../../models/dining_table.dart';
import '../../services/dining_tables_service.dart';

class AdminTablesPanel extends StatefulWidget {
  const AdminTablesPanel({super.key});

  @override
  State<AdminTablesPanel> createState() => _AdminTablesPanelState();
}

class _AdminTablesPanelState extends State<AdminTablesPanel> {
  static const burgundy = Color(0xFF6B1124);

  var _loading = true;
  String? _error;
  List<DiningTable> _tables = const [];

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
      setState(() {
        _tables = tables;
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

  Future<void> _showEditor({DiningTable? table}) async {
    final numberController = TextEditingController(text: table?.number ?? '');
    final nameController = TextEditingController(text: table?.name ?? '');
    final zoneController =
        TextEditingController(text: table?.zone ?? 'الصالة الرئيسية');
    final capacityController =
        TextEditingController(text: '${table?.capacity ?? 4}');
    final nextOrder = _tables.isEmpty
        ? 1
        : (_tables.map((entry) => entry.sortOrder).reduce((a, b) => a > b ? a : b) +
            1);
    final sortOrderController = TextEditingController(
      text: '${table?.sortOrder ?? nextOrder}',
    );

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(table == null ? 'إضافة طاولة' : 'تعديل طاولة ${table.number}'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: numberController,
                    decoration: const InputDecoration(
                      labelText: 'رقم الطاولة *',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: 'الاسم (اختياري)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: zoneController,
                    decoration: const InputDecoration(
                      labelText: 'المنطقة / القسم',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: capacityController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'عدد المقاعد',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: sortOrderController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'ترتيب العرض',
                      helperText: 'الرقم الأصغر يظهر أولاً داخل نفس المنطقة',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('حفظ'),
            ),
          ],
        );
      },
    );

    if (saved != true) return;
    final number = numberController.text.trim();
    if (number.isEmpty) {
      _toast('رقم الطاولة مطلوب');
      return;
    }
    final sortOrder = int.tryParse(sortOrderController.text.trim()) ??
        (table?.sortOrder ?? nextOrder);
    try {
      if (table == null) {
        await DiningTablesService.instance.createTable(
          number: number,
          name: nameController.text.trim(),
          zone: zoneController.text.trim().isEmpty
              ? 'الصالة الرئيسية'
              : zoneController.text.trim(),
          capacity: int.tryParse(capacityController.text.trim()) ?? 4,
          sortOrder: sortOrder,
        );
      } else {
        await DiningTablesService.instance.updateTable(
          DiningTable(
            id: table.id,
            number: number,
            name: nameController.text.trim(),
            zone: zoneController.text.trim().isEmpty
                ? table.zone
                : zoneController.text.trim(),
            capacity: int.tryParse(capacityController.text.trim()) ?? table.capacity,
            status: table.status,
            sortOrder: sortOrder,
            activeSession: table.activeSession,
          ),
        );
      }
      await _load();
    } catch (error) {
      _toast(error.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _delete(DiningTable table) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('حذف الطاولة'),
        content: Text('هل تريد حذف طاولة ${table.number}؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await DiningTablesService.instance.deleteTable(table.id);
      await _load();
    } catch (error) {
      _toast(error.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _release(DiningTable table) async {
    try {
      await DiningTablesService.instance.release(table.id);
      await _load();
    } catch (error) {
      _toast(error.toString().replaceFirst('Exception: ', ''));
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final grouped = <String, List<DiningTable>>{};
    for (final table in _tables) {
      grouped.putIfAbsent(table.zone, () => []).add(table);
    }
    for (final list in grouped.values) {
      list.sort((a, b) {
        final byOrder = a.sortOrder.compareTo(b.sortOrder);
        if (byOrder != 0) return byOrder;
        return a.number.compareTo(b.number);
      });
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: burgundy,
        foregroundColor: Colors.white,
        onPressed: _showEditor,
        icon: const Icon(Icons.add),
        label: const Text('إضافة طاولة'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                const Text(
                  'إدارة الطاولات',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: burgundy,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                      onPressed: _showEditor,
                      icon: const Icon(Icons.add),
                      label: const Text('إضافة طاولة'),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'أضف الطاولات حسب الصالة أو الشرفة. الكاشير يفتح جلسة على الطاولة من شاشة الصالة.',
              style: TextStyle(color: Colors.grey.shade700),
            ),
            const SizedBox(height: 16),
            Expanded(child: _buildBody(grouped)),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(Map<String, List<DiningTable>> grouped) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: burgundy));
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
              const SizedBox(height: 12),
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: burgundy),
                onPressed: _showEditor,
                icon: const Icon(Icons.add),
                label: const Text('إضافة طاولة'),
              ),
            ],
          ),
        ),
      );
    }
    if (_tables.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('لا توجد طاولات بعد. أضف أول طاولة.'),
            const SizedBox(height: 16),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: burgundy),
              onPressed: _showEditor,
              icon: const Icon(Icons.add),
              label: const Text('إضافة طاولة'),
            ),
          ],
        ),
      );
    }
    return ListView(
      children: [
        for (final entry in grouped.entries) ...[
          Text(
            entry.key,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final table in entry.value)
                SizedBox(
                  width: 260,
                  child: _TableCard(
                    table: table,
                    onEdit: () => _showEditor(table: table),
                    onDelete: () => _delete(table),
                    onRelease: table.activeSession == null
                        ? null
                        : () => _release(table),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 20),
        ],
      ],
    );
  }
}

class _TableCard extends StatelessWidget {
  const _TableCard({
    required this.table,
    required this.onEdit,
    required this.onDelete,
    this.onRelease,
  });

  final DiningTable table;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback? onRelease;

  @override
  Widget build(BuildContext context) {
    final occupied = table.isOccupied;
    return Card(
      color: occupied ? const Color(0xFFFFF3E0) : Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.table_restaurant,
                  color: occupied ? Colors.orange.shade800 : const Color(0xFF2E7D32),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    table.displayName,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                Text(
                  table.status.labelAr,
                  style: TextStyle(
                    color: occupied ? Colors.orange.shade800 : const Color(0xFF2E7D32),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text('رقم ${table.number} • ${table.capacity} مقاعد • ترتيب ${table.sortOrder}'),
            if (table.activeSession != null)
              Text(
                'جلسة: ${table.activeSession!.openedByName ?? 'كاشير'} • ${table.activeSession!.cartItems.length} أصناف',
                style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
              ),
            const SizedBox(height: 8),
            Row(
              children: [
                TextButton(onPressed: onEdit, child: const Text('تعديل')),
                if (onRelease != null)
                  TextButton(onPressed: onRelease, child: const Text('تفريغ')),
                TextButton(
                  onPressed: onDelete,
                  child: const Text('حذف', style: TextStyle(color: Colors.red)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
