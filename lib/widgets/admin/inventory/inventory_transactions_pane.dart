import 'package:flutter/material.dart';

import '../../../services/api_service.dart';
import '../../../services/inventory_api_service.dart';
import 'inventory_theme.dart';

enum _WasteLineKind { item, menu }

class _PurchaseLine {
  _PurchaseLine()
      : qtyController = TextEditingController(text: '1'),
        costController = TextEditingController(text: '0');
  String? itemId;
  final TextEditingController qtyController;
  final TextEditingController costController;
}

class _WasteLine {
  _WasteLine()
      : qtyController = TextEditingController(text: '1'),
        kind = _WasteLineKind.item,
        reason = InventoryApiService.wasteReasons.first,
        channel = 'TAKEAWAY';
  _WasteLineKind kind;
  String? itemId;
  String? menuItemId;
  final TextEditingController qtyController;
  String reason;
  String channel;
}

class _CountLine {
  _CountLine() : qtyController = TextEditingController();
  String? itemId;
  final TextEditingController qtyController;
}

class _TransferLine {
  _TransferLine() : qtyController = TextEditingController(text: '1');
  String? itemId;
  final TextEditingController qtyController;
}

class _ProductionLine {
  _ProductionLine() : qtyController = TextEditingController(text: '1');
  String? prepItemId;
  final TextEditingController qtyController;
}

/// Foodics daily moves: purchases, transfers, production, waste, count (draft → close).
class InventoryTransactionsPane extends StatefulWidget {
  const InventoryTransactionsPane({
    super.key,
    required this.restaurantId,
    required this.stockItems,
    required this.onRefresh,
  });

  final String restaurantId;
  final List<Map<String, dynamic>> stockItems;
  final Future<void> Function() onRefresh;

  @override
  State<InventoryTransactionsPane> createState() => _InventoryTransactionsPaneState();
}

class _InventoryTransactionsPaneState extends State<InventoryTransactionsPane>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  var _loading = true;
  List<Map<String, dynamic>> _purchases = const [];
  List<Map<String, dynamic>> _transfers = const [];
  List<Map<String, dynamic>> _productions = const [];
  List<Map<String, dynamic>> _wasteDocs = const [];
  List<Map<String, dynamic>> _counts = const [];
  List<Map<String, String>> _menuItems = const [];

  List<Map<String, dynamic>> get _prepItems => widget.stockItems
      .where((row) => row['itemType']?.toString() == 'PREP')
      .toList();

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 5, vsync: this);
    _reload();
    _loadMenuItems();
  }

  Future<void> _loadMenuItems() async {
    try {
      final items = await ApiService.instance.fetchMenuItems(
        restaurantId: widget.restaurantId,
      );
      if (!mounted) return;
      setState(() {
        _menuItems = items
            .map((m) => {'id': '${m.id}', 'name': m.name})
            .toList();
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        InventoryApiService.instance.fetchPurchases(restaurantId: widget.restaurantId),
        InventoryApiService.instance.fetchTransfers(restaurantId: widget.restaurantId),
        InventoryApiService.instance.fetchProductions(restaurantId: widget.restaurantId),
        InventoryApiService.instance.fetchWasteDocuments(restaurantId: widget.restaurantId),
        InventoryApiService.instance.fetchCounts(restaurantId: widget.restaurantId),
      ]);
      if (!mounted) return;
      setState(() {
        _purchases = results[0];
        _transfers = results[1];
        _productions = results[2];
        _wasteDocs = results[3];
        _counts = results[4];
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));
    }
  }

  Future<void> _afterMutation() async {
    await _reload();
    await widget.onRefresh();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Material(
          color: Colors.white,
          child: TabBar(
            controller: _tabs,
            labelColor: InventoryTheme.burgundy,
            indicatorColor: InventoryTheme.accent,
            isScrollable: true,
            tabs: const [
              Tab(text: 'مشتريات'),
              Tab(text: 'تحويلات'),
              Tab(text: 'إنتاج'),
              Tab(text: 'هالك'),
              Tab(text: 'جرد'),
            ],
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: InventoryTheme.burgundy))
              : TabBarView(
                  controller: _tabs,
                  children: [
                    _purchasesTab(),
                    _transfersTab(),
                    _productionTab(),
                    _wasteTab(),
                    _countTab(),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _purchasesTab() {
    return _docList(
      docs: _purchases,
      title: (p) => p['vendorName']?.toString() ?? 'مشتريات',
      subtitle: (p) => 'الإجمالي: ${p['totalWithTax'] ?? p['subtotal'] ?? '—'}',
      onClose: (p) => InventoryApiService.instance.closePurchase(
        p['id'].toString(),
        restaurantId: widget.restaurantId,
      ),
      onEdit: (p) => () => _showPurchaseSheet(existing: p),
      onAdd: () => _showPurchaseSheet(),
    );
  }

  Widget _transfersTab() {
    return _docList(
      docs: _transfers,
      title: (t) => 'تحويل ${t['id']}',
      subtitle: (t) =>
          '${t['foodicsStage'] ?? t['stage']} • ${t['fromBranchId']} → ${t['toBranchId']}',
      status: (t) => t['status']?.toString() ?? 'DRAFT',
      onClose: null,
      trailingAction: (t) {
        final stage = (t['foodicsStage'] ?? t['stage'] ?? '').toString().toUpperCase();
        if (t['status']?.toString().toUpperCase() == 'DRAFT' ||
            stage == 'REQUEST' ||
            stage == 'REQUESTED') {
          return TextButton(
            child: const Text('إرسال'),
            onPressed: () async {
              await InventoryApiService.instance.sendTransfer(
                t['id'].toString(),
                restaurantId: widget.restaurantId,
              );
              await _afterMutation();
            },
          );
        }
        if (stage == 'SENT' || stage == 'IN_TRANSIT') {
          return TextButton(
            child: const Text('استلام'),
            onPressed: () async {
              await InventoryApiService.instance.receiveTransfer(
                t['id'].toString(),
                restaurantId: widget.restaurantId,
              );
              await _afterMutation();
            },
          );
        }
        return null;
      },
      onEdit: (t) {
        final stage = (t['foodicsStage'] ?? t['stage'] ?? '').toString().toUpperCase();
        if (stage != 'REQUEST' && stage != 'REQUESTED' && t['status']?.toString().toUpperCase() != 'DRAFT') {
          return null;
        }
        return () => _showTransferSheet(existing: t);
      },
      onAdd: () => _showTransferSheet(),
    );
  }

  int _productionLineCount(Map<String, dynamic> p) {
    final raw = p['lines'];
    if (raw is List && raw.isNotEmpty) return raw.length;
    if (p['prepItemId'] != null) return 1;
    return 0;
  }

  Widget _productionTab() {
    return _docList(
      docs: _productions,
      title: (p) {
        final n = _productionLineCount(p);
        if (n > 1) return 'إنتاج — $n أصناف PREP';
        return 'إنتاج ${p['prepItemId'] ?? p['lines']?.first?['prepItemId'] ?? ''}';
      },
      subtitle: (p) {
        final n = _productionLineCount(p);
        if (n > 1) return 'بنود: $n';
        return 'كمية: ${p['outputQtyInRecipeUom'] ?? p['lines']?.first?['outputQtyInRecipeUom'] ?? '—'}';
      },
      onClose: (p) => InventoryApiService.instance.closeProduction(
        p['id'].toString(),
        restaurantId: widget.restaurantId,
      ),
      onEdit: (p) => () => _showProductionSheet(existing: p),
      onAdd: () => _showProductionSheet(),
    );
  }

  Widget _wasteTab() {
    return _docList(
      docs: _wasteDocs,
      title: (_) => 'وثيقة هالك',
      subtitle: (w) => 'أسطر: ${(w['lines'] as List?)?.length ?? 0}',
      onClose: (w) => InventoryApiService.instance.closeWasteDocument(
        w['id'].toString(),
        restaurantId: widget.restaurantId,
      ),
      onEdit: (w) => () => _showWasteSheet(existing: w),
      onAdd: () => _showWasteSheet(),
    );
  }

  Widget _countTab() {
    return _docList(
      docs: _counts,
      title: (c) => 'جرد ${c['categoryFilter']?.toString().isNotEmpty == true ? c['categoryFilter'] : 'عام'}',
      subtitle: (c) => 'جلسات: ${(c['lines'] as List?)?.length ?? 0}${c['blindCount'] == true ? ' • أعمى' : ''}',
      onClose: (c) => InventoryApiService.instance.closeCount(
        c['id'].toString(),
        restaurantId: widget.restaurantId,
      ),
      onEdit: (c) => () => _showCountSheet(existing: c),
      onAdd: () => _showCountSheet(),
    );
  }

  Widget _docList({
    required List<Map<String, dynamic>> docs,
    required String Function(Map<String, dynamic>) title,
    required String Function(Map<String, dynamic>) subtitle,
    String Function(Map<String, dynamic>)? status,
    Future<Map<String, dynamic>> Function(Map<String, dynamic>)? onClose,
    Widget? Function(Map<String, dynamic>)? trailingAction,
    VoidCallback? Function(Map<String, dynamic>)? onEdit,
    required VoidCallback onAdd,
  }) {
    return Stack(
      children: [
        ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
          itemCount: docs.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final doc = docs[index];
            final st = status?.call(doc) ?? doc['status']?.toString() ?? 'DRAFT';
            final isDraft = st.toUpperCase() == 'DRAFT';
            return Card(
              child: ListTile(
                title: Text(title(doc)),
                subtitle: Text(subtitle(doc)),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (trailingAction != null) trailingAction(doc) ?? const SizedBox.shrink(),
                    InventoryDocStatusChip(status: st),
                    if (isDraft && onEdit != null) ...[
                      Builder(
                        builder: (context) {
                          final edit = onEdit(doc);
                          if (edit == null) return const SizedBox.shrink();
                          return IconButton(
                            tooltip: 'تعديل المسودة',
                            icon: const Icon(Icons.edit_outlined),
                            onPressed: edit,
                          );
                        },
                      ),
                    ],
                    if (isDraft && onClose != null)
                      IconButton(
                        tooltip: 'إغلاق',
                        icon: const Icon(Icons.lock_outline),
                        onPressed: () async {
                          await onClose(doc);
                          await _afterMutation();
                        },
                      ),
                  ],
                ),
              ),
            );
          },
        ),
        Positioned(
          left: 16,
          right: 16,
          bottom: 16,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: InventoryTheme.accent,
              foregroundColor: Colors.black87,
            ),
            onPressed: onAdd,
            icon: const Icon(Icons.add),
            label: const Text('مسودة جديدة'),
          ),
        ),
      ],
    );
  }

  void _showPurchaseSheet({Map<String, dynamic>? existing}) {
    final editing = existing != null;
    final docId = existing?['id']?.toString();
    final vendorCtrl = TextEditingController(text: existing?['vendorName']?.toString() ?? '');
    final taxCtrl = TextEditingController(text: '${existing?['taxAmount'] ?? '0'}');
    final invoiceCtrl = TextEditingController(text: existing?['invoiceRef']?.toString() ?? '');
    final lines = <_PurchaseLine>[];
    final rawLines = existing?['lines'];
    if (rawLines is List && rawLines.isNotEmpty) {
      for (final row in rawLines) {
        if (row is! Map) continue;
        final line = _PurchaseLine();
        line.itemId = row['itemId']?.toString();
        line.qtyController.text = '${row['qtyInPurchaseUom'] ?? row['qty'] ?? '1'}';
        line.costController.text = '${row['unitCostInPurchaseUom'] ?? row['unitCost'] ?? '0'}';
        lines.add(line);
      }
    }
    if (lines.isEmpty) {
      lines.add(_PurchaseLine());
      if (widget.stockItems.isNotEmpty) {
        lines.first.itemId = widget.stockItems.first['id']?.toString();
      }
    }
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
            child: DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.85,
              maxChildSize: 0.95,
              builder: (_, scroll) => _scrollableSheet(
                scroll: scroll,
                title: editing ? 'تعديل مسودة شراء' : 'مشتريات — عدة بنود (مسودة)',
                saveLabel: editing ? 'حفظ التعديل' : 'حفظ مسودة',
                children: [
                  TextField(
                    controller: vendorCtrl,
                    decoration: const InputDecoration(labelText: 'المورد', border: OutlineInputBorder()),
                  ),
                  TextField(
                    controller: invoiceCtrl,
                    decoration: const InputDecoration(labelText: 'رقم الفاتورة', border: OutlineInputBorder()),
                  ),
                  TextField(
                    controller: taxCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'الضريبة', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 8),
                  ..._buildPurchaseLineEditors(lines, setLocal),
                  TextButton.icon(
                    onPressed: () => setLocal(() {
                      final line = _PurchaseLine();
                      if (widget.stockItems.isNotEmpty) {
                        line.itemId = widget.stockItems.first['id']?.toString();
                      }
                      lines.add(line);
                    }),
                    icon: const Icon(Icons.add),
                    label: const Text('إضافة بند شراء'),
                  ),
                ],
                onSave: () async {
                  final bodyLines = <Map<String, dynamic>>[];
                  for (final line in lines) {
                    if (line.itemId == null) continue;
                    bodyLines.add({
                      'itemId': line.itemId,
                      'qtyInPurchaseUom': double.tryParse(line.qtyController.text) ?? 0,
                      'unitCostInPurchaseUom': double.tryParse(line.costController.text) ?? 0,
                    });
                  }
                  final payload = {
                    'vendorName': vendorCtrl.text.trim(),
                    'invoiceRef': invoiceCtrl.text.trim(),
                    'lines': bodyLines,
                  };
                  if (editing && docId != null) {
                    await InventoryApiService.instance.patchPurchase(
                      docId,
                      payload,
                      restaurantId: widget.restaurantId,
                    );
                  } else {
                    await InventoryApiService.instance.createPurchase(
                      {
                        ...payload,
                        'taxAmount': double.tryParse(taxCtrl.text) ?? 0,
                      },
                      restaurantId: widget.restaurantId,
                    );
                  }
                  if (ctx.mounted) Navigator.pop(ctx);
                  await _afterMutation();
                },
              ),
            ),
          );
        },
      ),
    );
  }

  List<Widget> _buildPurchaseLineEditors(List<_PurchaseLine> lines, void Function(void Function()) setLocal) {
    return List.generate(lines.length, (i) {
      final line = lines[i];
      return Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            children: [
              _itemDropdown(line.itemId, (v) => setLocal(() => line.itemId = v)),
              TextField(
                controller: line.qtyController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'كمية الشراء', border: OutlineInputBorder()),
              ),
              TextField(
                controller: line.costController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'سعر الوحدة', border: OutlineInputBorder()),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                  onPressed: lines.length <= 1
                      ? null
                      : () => setLocal(() {
                            lines[i].qtyController.dispose();
                            lines[i].costController.dispose();
                            lines.removeAt(i);
                          }),
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                ),
              ),
            ],
          ),
        ),
      );
    });
  }

  void _showTransferSheet({Map<String, dynamic>? existing}) {
    final editing = existing != null;
    final docId = existing?['id']?.toString();
    final notesCtrl = TextEditingController(text: existing?['notes']?.toString() ?? '');
    final lines = <_TransferLine>[];
    final rawLines = existing?['lines'];
    if (rawLines is List && rawLines.isNotEmpty) {
      for (final row in rawLines) {
        if (row is! Map) continue;
        final line = _TransferLine();
        line.itemId = row['itemId']?.toString();
        line.qtyController.text = '${row['qtyInRecipeUom'] ?? row['qty'] ?? '1'}';
        lines.add(line);
      }
    }
    if (lines.isEmpty) {
      lines.add(_TransferLine());
      if (widget.stockItems.isNotEmpty) {
        lines.first.itemId = widget.stockItems.first['id']?.toString();
      }
    }
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
          child: DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.85,
            builder: (_, scroll) => _scrollableSheet(
              scroll: scroll,
              title: editing ? 'تعديل مسودة تحويل' : 'تحويل — عدة بنود (طلب)',
              saveLabel: editing ? 'حفظ التعديل' : 'حفظ مسودة',
              children: [
                TextField(
                  controller: notesCtrl,
                  decoration: const InputDecoration(
                    labelText: 'ملاحظات (اختياري)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                ..._buildTransferLineEditors(lines, setLocal),
                TextButton.icon(
                  onPressed: () => setLocal(() {
                    final line = _TransferLine();
                    if (widget.stockItems.isNotEmpty) {
                      line.itemId = widget.stockItems.first['id']?.toString();
                    }
                    lines.add(line);
                  }),
                  icon: const Icon(Icons.add),
                  label: const Text('إضافة بند تحويل'),
                ),
              ],
              onSave: () async {
                final bodyLines = <Map<String, dynamic>>[];
                for (final line in lines) {
                  if (line.itemId == null) continue;
                  bodyLines.add({
                    'itemId': line.itemId,
                    'qtyInRecipeUom': double.tryParse(line.qtyController.text) ?? 0,
                  });
                }
                final payload = {
                  'fromBranchId': existing?['fromBranchId'] ?? widget.restaurantId,
                  'toBranchId': existing?['toBranchId'] ?? widget.restaurantId,
                  'notes': notesCtrl.text.trim(),
                  'lines': bodyLines,
                };
                if (editing && docId != null) {
                  await InventoryApiService.instance.patchTransfer(
                    docId,
                    payload,
                    restaurantId: widget.restaurantId,
                  );
                } else {
                  await InventoryApiService.instance.createTransfer(
                    payload,
                    restaurantId: widget.restaurantId,
                  );
                }
                if (ctx.mounted) Navigator.pop(ctx);
                await _afterMutation();
              },
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildTransferLineEditors(List<_TransferLine> lines, void Function(void Function()) setLocal) {
    return List.generate(lines.length, (i) {
      final line = lines[i];
      return Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            children: [
              _itemDropdown(line.itemId, (v) => setLocal(() => line.itemId = v)),
              TextField(
                controller: line.qtyController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'الكمية (وحدة وصفة)',
                  border: OutlineInputBorder(),
                ),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                  onPressed: lines.length <= 1
                      ? null
                      : () => setLocal(() {
                            lines[i].qtyController.dispose();
                            lines.removeAt(i);
                          }),
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                ),
              ),
            ],
          ),
        ),
      );
    });
  }

  void _showProductionSheet({Map<String, dynamic>? existing}) {
    if (_prepItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('أنشئ صنف PREP في المخزون أولاً')),
      );
      return;
    }
    final editing = existing != null;
    final docId = existing?['id']?.toString();
    final notesCtrl = TextEditingController(text: existing?['notes']?.toString() ?? '');
    final lines = <_ProductionLine>[];
    final rawLines = existing?['lines'];
    if (rawLines is List && rawLines.isNotEmpty) {
      for (final row in rawLines) {
        if (row is! Map) continue;
        final line = _ProductionLine();
        line.prepItemId = row['prepItemId']?.toString();
        line.qtyController.text =
            '${row['outputQtyInRecipeUom'] ?? row['outputQty'] ?? '1'}';
        lines.add(line);
      }
    } else if (editing && existing != null && existing['prepItemId'] != null) {
      final line = _ProductionLine();
      line.prepItemId = existing['prepItemId']?.toString();
      line.qtyController.text =
          '${existing['outputQtyInRecipeUom'] ?? existing['outputQty'] ?? '1'}';
      lines.add(line);
    }
    if (lines.isEmpty) {
      lines.add(_ProductionLine()..prepItemId = _prepItems.first['id']?.toString());
    }
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
          child: DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.85,
            builder: (_, scroll) => _scrollableSheet(
              scroll: scroll,
              title: editing ? 'تعديل مسودة إنتاج' : 'إنتاج — مسودة واحدة بعدة PREP',
              saveLabel: editing ? 'حفظ التعديل' : 'حفظ مسودة',
              children: [
                TextField(
                  controller: notesCtrl,
                  decoration: const InputDecoration(
                    labelText: 'ملاحظات (اختياري)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                ..._buildProductionLineEditors(lines, setLocal),
                TextButton.icon(
                  onPressed: () => setLocal(() {
                    lines.add(_ProductionLine()..prepItemId = _prepItems.first['id']?.toString());
                  }),
                  icon: const Icon(Icons.add),
                  label: const Text('إضافة صنف PREP'),
                ),
              ],
              onSave: () async {
                final bodyLines = <Map<String, dynamic>>[];
                for (final line in lines) {
                  if (line.prepItemId == null) continue;
                  final qty = double.tryParse(line.qtyController.text) ?? 0;
                  if (qty <= 0) continue;
                  bodyLines.add({
                    'prepItemId': line.prepItemId,
                    'outputQtyInRecipeUom': qty,
                  });
                }
                if (bodyLines.isEmpty) return;
                final payload = {
                  'lines': bodyLines,
                  if (notesCtrl.text.trim().isNotEmpty) 'notes': notesCtrl.text.trim(),
                };
                if (editing && docId != null) {
                  await InventoryApiService.instance.patchProduction(
                    docId,
                    payload,
                    restaurantId: widget.restaurantId,
                  );
                } else {
                  await InventoryApiService.instance.createProduction(
                    payload,
                    restaurantId: widget.restaurantId,
                  );
                }
                if (ctx.mounted) Navigator.pop(ctx);
                await _afterMutation();
              },
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildProductionLineEditors(
    List<_ProductionLine> lines,
    void Function(void Function()) setLocal,
  ) {
    return List.generate(lines.length, (i) {
      final line = lines[i];
      return Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            children: [
              DropdownButtonFormField<String>(
                value: line.prepItemId,
                decoration: const InputDecoration(labelText: 'صنف PREP', border: OutlineInputBorder()),
                items: _prepItems
                    .map(
                      (row) => DropdownMenuItem(
                        value: row['id']?.toString(),
                        child: Text(row['name']?.toString() ?? ''),
                      ),
                    )
                    .toList(),
                onChanged: (v) => setLocal(() => line.prepItemId = v),
              ),
              TextField(
                controller: line.qtyController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'كمية الإنتاج',
                  border: OutlineInputBorder(),
                ),
              ),
              if (lines.length > 1)
                Align(
                  alignment: Alignment.centerLeft,
                  child: IconButton(
                    onPressed: () => setLocal(() {
                      lines[i].qtyController.dispose();
                      lines.removeAt(i);
                    }),
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                  ),
                ),
            ],
          ),
        ),
      );
    });
  }

  void _showWasteSheet({Map<String, dynamic>? existing}) {
    final editing = existing != null;
    final docId = existing?['id']?.toString();
    final lines = <_WasteLine>[];
    final rawLines = existing?['lines'];
    if (rawLines is List && rawLines.isNotEmpty) {
      for (final row in rawLines) {
        if (row is! Map) continue;
        final line = _WasteLine();
        if (row['menuItemId'] != null) {
          line.kind = _WasteLineKind.menu;
          line.menuItemId = row['menuItemId']?.toString();
          line.channel = row['channel']?.toString() ?? 'TAKEAWAY';
        } else {
          line.itemId = row['itemId']?.toString();
        }
        line.qtyController.text = '${row['qty'] ?? row['qtyInRecipeUom'] ?? '1'}';
        line.reason = row['wasteReason']?.toString() ?? InventoryApiService.wasteReasons.first;
        lines.add(line);
      }
    }
    if (lines.isEmpty) {
      lines.add(_WasteLine());
      if (widget.stockItems.isNotEmpty) {
        lines.first.itemId = widget.stockItems.first['id']?.toString();
      }
      if (_menuItems.isNotEmpty) {
        lines.first.menuItemId = _menuItems.first['id'];
      }
    }
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.85,
          builder: (_, scroll) => _scrollableSheet(
            scroll: scroll,
            title: editing ? 'تعديل مسودة هالك' : 'هالك — مواد أو أصناف منيو',
            saveLabel: editing ? 'حفظ التعديل' : 'حفظ مسودة',
            children: [
              ..._buildWasteLineEditors(lines, setLocal),
              TextButton.icon(
                onPressed: () => setLocal(() {
                  final line = _WasteLine();
                  if (widget.stockItems.isNotEmpty) {
                    line.itemId = widget.stockItems.first['id']?.toString();
                  }
                  if (_menuItems.isNotEmpty) line.menuItemId = _menuItems.first['id'];
                  lines.add(line);
                }),
                icon: const Icon(Icons.add),
                label: const Text('إضافة سطر هالك'),
              ),
            ],
            onSave: () async {
              final payload = <Map<String, dynamic>>[];
              for (final line in lines) {
                final qty = double.tryParse(line.qtyController.text) ?? 0;
                if (qty <= 0) continue;
                if (line.kind == _WasteLineKind.menu && line.menuItemId != null) {
                  payload.add({
                    'menuItemId': line.menuItemId,
                    'qty': qty,
                    'wasteReason': line.reason,
                    'channel': line.channel,
                  });
                } else if (line.itemId != null) {
                  payload.add({
                    'itemId': line.itemId,
                    'qty': qty,
                    'wasteReason': line.reason,
                  });
                }
              }
              if (editing && docId != null) {
                await InventoryApiService.instance.patchWasteDocument(
                  docId,
                  {'lines': payload},
                  restaurantId: widget.restaurantId,
                );
              } else {
                await InventoryApiService.instance.createWasteDocument(
                  {'lines': payload},
                  restaurantId: widget.restaurantId,
                );
              }
              if (ctx.mounted) Navigator.pop(ctx);
              await _afterMutation();
            },
          ),
        ),
      ),
    );
  }

  List<Widget> _buildWasteLineEditors(List<_WasteLine> lines, void Function(void Function()) setLocal) {
    return List.generate(lines.length, (i) {
      final line = lines[i];
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            children: [
              SegmentedButton<_WasteLineKind>(
                segments: const [
                  ButtonSegment(value: _WasteLineKind.item, label: Text('مادة مخزون')),
                  ButtonSegment(value: _WasteLineKind.menu, label: Text('صنف منيو')),
                ],
                selected: {line.kind},
                onSelectionChanged: (s) => setLocal(() => line.kind = s.first),
              ),
              if (line.kind == _WasteLineKind.item)
                _itemDropdown(line.itemId, (v) => setLocal(() => line.itemId = v))
              else
                DropdownButtonFormField<String>(
                  initialValue: line.menuItemId,
                  decoration: const InputDecoration(labelText: 'صنف المنيو', border: OutlineInputBorder()),
                  items: _menuItems
                      .map(
                        (m) => DropdownMenuItem(
                          value: m['id'],
                          child: Text(m['name'] ?? '', overflow: TextOverflow.ellipsis),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setLocal(() => line.menuItemId = v),
                ),
              TextField(
                controller: line.qtyController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'الكمية', border: OutlineInputBorder()),
              ),
              if (line.kind == _WasteLineKind.menu)
                DropdownButtonFormField<String>(
                  initialValue: line.channel,
                  decoration: const InputDecoration(labelText: 'قناة (لتفجيك الوصفة)', border: OutlineInputBorder()),
                  items: InventoryApiService.inventoryChannels
                      .where((c) => c != 'ALL')
                      .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                      .toList(),
                  onChanged: (v) => setLocal(() => line.channel = v ?? line.channel),
                ),
              DropdownButtonFormField<String>(
                initialValue: line.reason,
                decoration: const InputDecoration(labelText: 'سبب الهالك', border: OutlineInputBorder()),
                items: InventoryApiService.wasteReasons
                    .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                    .toList(),
                onChanged: (v) => setLocal(() => line.reason = v ?? line.reason),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                  onPressed: lines.length <= 1
                      ? null
                      : () => setLocal(() {
                            lines[i].qtyController.dispose();
                            lines.removeAt(i);
                          }),
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                ),
              ),
            ],
          ),
        ),
      );
    });
  }

  void _showCountSheet({Map<String, dynamic>? existing}) {
    final editing = existing != null;
    final docId = existing?['id']?.toString();
    final lines = <_CountLine>[];
    final rawLines = existing?['lines'];
    if (rawLines is List && rawLines.isNotEmpty) {
      for (final row in rawLines) {
        if (row is! Map) continue;
        final line = _CountLine();
        line.itemId = row['itemId']?.toString();
        line.qtyController.text = '${row['countedQty'] ?? row['qty'] ?? ''}';
        lines.add(line);
      }
    }
    if (lines.isEmpty) {
      lines.add(_CountLine());
      if (widget.stockItems.isNotEmpty) {
        lines.first.itemId = widget.stockItems.first['id']?.toString();
      }
    }
    var blind = existing?['blindCount'] == true;
    final catCtrl = TextEditingController(text: existing?['categoryFilter']?.toString() ?? '');
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.85,
          builder: (_, scroll) => _scrollableSheet(
            scroll: scroll,
            title: editing ? 'تعديل مسودة جرد' : 'جرد — عدة أصناف',
            saveLabel: editing ? 'حفظ التعديل' : 'حفظ مسودة',
            children: [
              TextField(
                controller: catCtrl,
                decoration: const InputDecoration(
                  labelText: 'تصنيف (اختياري)',
                  border: OutlineInputBorder(),
                ),
              ),
              SwitchListTile(
                title: const Text('جرد أعمى'),
                value: blind,
                onChanged: (v) => setLocal(() => blind = v),
              ),
              ..._buildCountLineEditors(lines, setLocal),
              TextButton.icon(
                onPressed: () => setLocal(() {
                  final line = _CountLine();
                  if (widget.stockItems.isNotEmpty) {
                    line.itemId = widget.stockItems.first['id']?.toString();
                  }
                  lines.add(line);
                }),
                icon: const Icon(Icons.add),
                label: const Text('إضافة صنف للجرد'),
              ),
            ],
            onSave: () async {
              final payload = <Map<String, dynamic>>[];
              for (final line in lines) {
                if (line.itemId == null) continue;
                payload.add({
                  'itemId': line.itemId,
                  'countedQty': double.tryParse(line.qtyController.text) ?? 0,
                });
              }
              final body = {
                'blindCount': blind,
                if (catCtrl.text.trim().isNotEmpty) 'categoryFilter': catCtrl.text.trim(),
                'lines': payload,
              };
              if (editing && docId != null) {
                await InventoryApiService.instance.patchCount(
                  docId,
                  body,
                  restaurantId: widget.restaurantId,
                );
              } else {
                await InventoryApiService.instance.createCount(
                  body,
                  restaurantId: widget.restaurantId,
                );
              }
              if (ctx.mounted) Navigator.pop(ctx);
              await _afterMutation();
            },
          ),
        ),
      ),
    );
  }

  List<Widget> _buildCountLineEditors(List<_CountLine> lines, void Function(void Function()) setLocal) {
    return List.generate(lines.length, (i) {
      final line = lines[i];
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            children: [
              _itemDropdown(line.itemId, (v) => setLocal(() => line.itemId = v)),
              TextField(
                controller: line.qtyController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'كمية معدّة',
                  border: OutlineInputBorder(),
                ),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                  onPressed: lines.length <= 1
                      ? null
                      : () => setLocal(() {
                            lines[i].qtyController.dispose();
                            lines.removeAt(i);
                          }),
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                ),
              ),
            ],
          ),
        ),
      );
    });
  }

  Widget _scrollableSheet({
    required ScrollController scroll,
    required String title,
    required List<Widget> children,
    required Future<void> Function() onSave,
    String saveLabel = 'حفظ مسودة',
  }) {
    return SingleChildScrollView(
      controller: scroll,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
          const SizedBox(height: 12),
          ...children,
          const SizedBox(height: 16),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: InventoryTheme.burgundy),
            onPressed: () async => onSave(),
            child: Text(saveLabel),
          ),
        ],
      ),
    );
  }

  Widget _itemDropdown(String? value, ValueChanged<String?> onChanged) {
    return DropdownButtonFormField<String>(
      value: value,
      decoration: const InputDecoration(labelText: 'صنف مخزون'),
      items: widget.stockItems
          .map(
            (row) => DropdownMenuItem(
              value: row['id']?.toString(),
              child: Text(row['name']?.toString() ?? ''),
            ),
          )
          .toList(),
      onChanged: onChanged,
    );
  }

}