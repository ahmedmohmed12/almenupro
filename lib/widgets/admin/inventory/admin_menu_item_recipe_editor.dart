import 'package:flutter/material.dart';

import '../../../services/inventory_api_service.dart';
import '../../../services/super_admin_scope_service.dart';
import '../../../utils/food_cost_utils.dart';
import 'admin_modifier_recipes_panel.dart';
import 'inventory_theme.dart';

/// Foodics-style «المكونات» tab: raw/prep lines, channel packaging, live AVCO cost.
class AdminMenuItemRecipeEditor extends StatefulWidget {
  const AdminMenuItemRecipeEditor({
    super.key,
    required this.menuItemId,
    required this.sellingPrice,
    this.addonOptions = const [],
    this.onCostSynced,
  });

  final String menuItemId;
  final double sellingPrice;
  final List<Map<String, dynamic>> addonOptions;
  final ValueChanged<double>? onCostSynced;

  @override
  State<AdminMenuItemRecipeEditor> createState() => _AdminMenuItemRecipeEditorState();
}

class _RecipeIngredientLine {
  _RecipeIngredientLine({
    required this.itemId,
    required this.qtyController,
    this.channels = const ['ALL'],
  });

  String itemId;
  final TextEditingController qtyController;
  List<String> channels;
}

class _AdminMenuItemRecipeEditorState extends State<AdminMenuItemRecipeEditor> {
  var _loading = true;
  var _saving = false;
  String? _error;
  String _previewChannel = 'TAKEAWAY';
  Map<String, dynamic>? _estimate;
  List<Map<String, dynamic>> _stockItems = const [];
  final List<_RecipeIngredientLine> _lines = [];

  String get _restaurantId => SuperAdminScopeService.instance.effectiveRestaurantId;

  static const _channelLabels = <String, String>{
    'ALL': 'كل القنوات',
    'DINE_IN': 'صالة',
    'TAKEAWAY': 'سفري',
    'DELIVERY': 'توصيل',
    'AGGREGATOR': 'منصات',
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final line in _lines) {
      line.qtyController.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await InventoryApiService.instance.fetchItems(
        restaurantId: _restaurantId,
      );
      final recipe = await InventoryApiService.instance.fetchMenuRecipe(
        widget.menuItemId,
        restaurantId: _restaurantId,
      );
      _lines
        ..clear()
        ..addAll(_parseIngredients(recipe?['ingredients']));
      if (_lines.isEmpty) {
        _lines.add(_newLine());
      }
      await _refreshEstimate();
      if (!mounted) return;
      setState(() {
        _stockItems = items;
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

  List<_RecipeIngredientLine> _parseIngredients(dynamic raw) {
    if (raw is! List) return [];
    final out = <_RecipeIngredientLine>[];
    for (final row in raw) {
      if (row is! Map) continue;
      final types = row['applicableOrderTypes'];
      List<String> channels;
      if (types == null || types == 'ALL') {
        channels = ['ALL'];
      } else if (types is List) {
        channels = types.map((e) => e.toString().toUpperCase()).toList();
      } else {
        channels = [types.toString().toUpperCase()];
      }
      out.add(
        _RecipeIngredientLine(
          itemId: row['itemId']?.toString() ?? '',
          qtyController: TextEditingController(
            text: '${row['qtyInRecipeUom'] ?? row['qty'] ?? ''}',
          ),
          channels: channels,
        ),
      );
    }
    return out;
  }

  _RecipeIngredientLine _newLine() {
    return _RecipeIngredientLine(
      itemId: '',
      qtyController: TextEditingController(text: '1'),
      channels: const ['ALL'],
    );
  }

  Future<void> _refreshEstimate() async {
    try {
      final est = await InventoryApiService.instance.estimateMenuCost(
        menuItemId: widget.menuItemId,
        channel: _previewChannel,
        restaurantId: _restaurantId,
      );
      if (!mounted) return;
      setState(() => _estimate = est);
    } catch (_) {
      if (!mounted) return;
      setState(() => _estimate = null);
    }
  }

  Future<void> _save({bool syncCost = true}) async {
    setState(() => _saving = true);
    try {
      final ingredients = <Map<String, dynamic>>[];
      for (final line in _lines) {
        final id = line.itemId.trim();
        if (id.isEmpty) continue;
        final qty = double.tryParse(line.qtyController.text.trim()) ?? 0;
        if (qty <= 0) continue;
        ingredients.add({
          'itemId': id,
          'qtyInRecipeUom': qty,
          'applicableOrderTypes':
              line.channels.length == 1 && line.channels.first == 'ALL'
                  ? 'ALL'
                  : line.channels,
        });
      }
      await InventoryApiService.instance.saveRecipe(
        {
          'menuItemId': widget.menuItemId,
          'ingredients': ingredients,
        },
        restaurantId: _restaurantId,
      );
      await _refreshEstimate();
      final total = (_estimate?['totalCost'] as num?)?.toDouble();
      if (syncCost && total != null && widget.onCostSynced != null) {
        widget.onCostSynced!(total);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم حفظ وصفة المخزون وتثبيت التكلفة من AVCO')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$error')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: InventoryTheme.burgundy),
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: _load,
                style: FilledButton.styleFrom(backgroundColor: InventoryTheme.burgundy),
                child: const Text('إعادة المحاولة'),
              ),
            ],
          ),
        ),
      );
    }

    final totalCost = (_estimate?['totalCost'] as num?)?.toDouble();
    final foodCostPct = widget.sellingPrice > 0 && totalCost != null
        ? (totalCost / widget.sellingPrice) * 100
        : null;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'مكونات الصنف (وحدة الوصفة)',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: InventoryTheme.burgundy,
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 4),
            const Text(
              'اربط مواد RAW/PREP من المخزون. قناة التعبئة تحدد تكلفة السفري/التوصيل مثل Foodics.',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
            const SizedBox(height: 12),
            _liveCostCard(totalCost, foodCostPct),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _previewChannel,
              decoration: const InputDecoration(
                labelText: 'قناة معاينة التكلفة',
                border: OutlineInputBorder(),
              ),
              items: InventoryApiService.inventoryChannels
                  .where((c) => c != 'ALL')
                  .map(
                    (c) => DropdownMenuItem(
                      value: c,
                      child: Text(_channelLabels[c] ?? c),
                    ),
                  )
                  .toList(),
              onChanged: (value) async {
                if (value == null) return;
                setState(() => _previewChannel = value);
                await _refreshEstimate();
              },
            ),
            const SizedBox(height: 16),
            ...List.generate(_lines.length, (index) => _ingredientCard(index)),
            TextButton.icon(
              onPressed: () => setState(() => _lines.add(_newLine())),
              icon: const Icon(Icons.add),
              label: const Text('إضافة مكوّن'),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _saving ? null : () => _save(),
              style: FilledButton.styleFrom(
                backgroundColor: InventoryTheme.burgundy,
              ),
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.save_outlined),
              label: const Text('حفظ الوصفة ومزامنة Food Cost'),
            ),
            AdminModifierRecipesPanel(addonOptions: widget.addonOptions),
          ],
        ),
      ),
    );
  }

  Widget _liveCostCard(double? totalCost, double? foodCostPct) {
    return Card(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: InventoryTheme.accent.withValues(alpha: 0.6)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('تكلفة حية (AVCO)', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text('إجمالي التكلفة: ${totalCost?.toStringAsFixed(5) ?? '—'} د.ك'),
            Text('سعر البيع: ${widget.sellingPrice.toStringAsFixed(3)} د.ك'),
            if (foodCostPct != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: FoodCostBadge(
                  sellingPrice: widget.sellingPrice,
                  costPrice: totalCost,
                  compact: true,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _ingredientCard(int index) {
    final line = _lines[index];
  final stockById = {
      for (final row in _stockItems) row['id']?.toString() ?? '': row,
    };
    final selectedId = line.itemId.isEmpty ? null : line.itemId;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          children: [
            DropdownButtonFormField<String>(
              value: selectedId != null && stockById.containsKey(selectedId)
                  ? selectedId
                  : null,
              decoration: const InputDecoration(
                labelText: 'مادة مخزون',
                border: OutlineInputBorder(),
              ),
              items: _stockItems
                  .map(
                    (row) => DropdownMenuItem(
                      value: row['id']?.toString(),
                      child: Text(
                        '${row['name']} (${row['itemType'] ?? 'RAW'})',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value == null) return;
                setState(() => line.itemId = value);
              },
            ),
            const SizedBox(height: 8),
            TextField(
              controller: line.qtyController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'الكمية (${stockById[selectedId]?['recipeUom'] ?? 'وصفة'})',
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                children: InventoryApiService.inventoryChannels.map((channel) {
                  final selected = line.channels.contains(channel) ||
                      (channel == 'ALL' && line.channels.contains('ALL'));
                  return FilterChip(
                    label: Text(_channelLabels[channel] ?? channel, style: const TextStyle(fontSize: 11)),
                    selected: selected,
                    onSelected: (_) {
                      setState(() {
                        if (channel == 'ALL') {
                          line.channels = ['ALL'];
                        } else {
                          line.channels.remove('ALL');
                          if (selected) {
                            line.channels.remove(channel);
                          } else {
                            line.channels.add(channel);
                          }
                          if (line.channels.isEmpty) line.channels = ['ALL'];
                        }
                      });
                    },
                  );
                }).toList(),
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: IconButton(
                onPressed: _lines.length <= 1
                    ? null
                    : () => setState(() {
                          _lines[index].qtyController.dispose();
                          _lines.removeAt(index);
                        }),
                icon: const Icon(Icons.delete_outline, color: Colors.red),
              ),
            ),
          ],
        ),
      ),
    );
  }
}