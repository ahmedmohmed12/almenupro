import 'package:flutter/material.dart';

import '../../../services/inventory_api_service.dart';
import '../../../services/super_admin_scope_service.dart';
import 'inventory_theme.dart';

/// Per-addon (modifier) recipe editor — Foodics modifier BOM.
class AdminModifierRecipesPanel extends StatefulWidget {
  const AdminModifierRecipesPanel({
    super.key,
    required this.addonOptions,
  });

  final List<Map<String, dynamic>> addonOptions;

  @override
  State<AdminModifierRecipesPanel> createState() => _AdminModifierRecipesPanelState();
}

class _ModifierIngredientLine {
  _ModifierIngredientLine({required this.itemId, required this.qtyController});

  String itemId;
  final TextEditingController qtyController;
}

class _AdminModifierRecipesPanelState extends State<AdminModifierRecipesPanel> {
  List<Map<String, dynamic>> _stockItems = const [];
  List<Map<String, dynamic>> _recipes = const [];
  var _loading = true;

  String get _restaurantId => SuperAdminScopeService.instance.effectiveRestaurantId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final items = await InventoryApiService.instance.fetchItems(restaurantId: _restaurantId);
      final recipes = await InventoryApiService.instance.fetchRecipes(restaurantId: _restaurantId);
      if (!mounted) return;
      setState(() {
        _stockItems = items;
        _recipes = recipes;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Map<String, dynamic>? _recipeForModifier(String modifierId) {
    for (final row in _recipes) {
      if (row['modifierId']?.toString() == modifierId) return row;
    }
    return null;
  }

  Future<void> _saveModifier(
    String modifierId,
  String modifierName,
    List<_ModifierIngredientLine> lines,
  ) async {
    final ingredients = <Map<String, dynamic>>[];
    for (final line in lines) {
      if (line.itemId.isEmpty) continue;
      final qty = double.tryParse(line.qtyController.text.trim()) ?? 0;
      if (qty <= 0) continue;
      ingredients.add({
        'itemId': line.itemId,
        'qtyInRecipeUom': qty,
        'applicableOrderTypes': 'ALL',
      });
    }
    await InventoryApiService.instance.saveRecipe(
      {
        'modifierId': modifierId,
        'ingredients': ingredients,
      },
      restaurantId: _restaurantId,
    );
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('تم حفظ وصفة الإضافة: $modifierName')),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: LinearProgressIndicator(color: InventoryTheme.burgundy),
      );
    }
    final options = widget.addonOptions
        .where((o) => (o['name']?.toString().trim().isNotEmpty ?? false))
        .toList();
    if (options.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: Text(
          'أضف إضافات في تبويب بيانات الصنف ثم عُد لوصفات الإضافات هنا.',
          style: TextStyle(fontSize: 13, color: Colors.black54),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(),
        Text(
          'وصفات الإضافات (Modifiers)',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: InventoryTheme.burgundy,
              ),
        ),
        const SizedBox(height: 8),
        ...options.map((opt) {
          final modId = opt['id']?.toString() ?? '';
          final name = opt['name']?.toString() ?? modId;
          return _ModifierRecipeCard(
            key: ValueKey(modId),
            modifierId: modId,
            modifierName: name,
            stockItems: _stockItems,
            existing: _recipeForModifier(modId),
            onSave: _saveModifier,
          );
        }),
      ],
    );
  }
}

class _ModifierRecipeCard extends StatefulWidget {
  const _ModifierRecipeCard({
    super.key,
    required this.modifierId,
    required this.modifierName,
    required this.stockItems,
    required this.existing,
    required this.onSave,
  });

  final String modifierId;
  final String modifierName;
  final List<Map<String, dynamic>> stockItems;
  final Map<String, dynamic>? existing;
  final Future<void> Function(String id, String name, List<_ModifierIngredientLine> lines) onSave;

  @override
  State<_ModifierRecipeCard> createState() => _ModifierRecipeCardState();
}

class _ModifierRecipeCardState extends State<_ModifierRecipeCard> {
  final List<_ModifierIngredientLine> _lines = [];
  var _expanded = false;

  @override
  void initState() {
    super.initState();
    final ings = widget.existing?['ingredients'];
    if (ings is List && ings.isNotEmpty) {
      for (final row in ings) {
        if (row is! Map) continue;
        _lines.add(
          _ModifierIngredientLine(
            itemId: row['itemId']?.toString() ?? '',
            qtyController: TextEditingController(
              text: '${row['qtyInRecipeUom'] ?? ''}',
            ),
          ),
        );
      }
    }
    if (_lines.isEmpty) {
      _lines.add(_ModifierIngredientLine(itemId: '', qtyController: TextEditingController(text: '1')));
    }
  }

  @override
  void dispose() {
    for (final l in _lines) {
      l.qtyController.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        initiallyExpanded: _expanded,
        onExpansionChanged: (v) => setState(() => _expanded = v),
        title: Text(widget.modifierName, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text('معرّف: ${widget.modifierId}', style: const TextStyle(fontSize: 11)),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Column(
              children: [
                ...List.generate(_lines.length, (i) {
                  final line = _lines[i];
                  return Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: DropdownButtonFormField<String>(
                          initialValue: line.itemId.isEmpty ? null : line.itemId,
                          decoration: const InputDecoration(
                            labelText: 'مادة',
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                          items: widget.stockItems
                              .map(
                                (row) => DropdownMenuItem(
                                  value: row['id']?.toString(),
                                  child: Text(row['name']?.toString() ?? '', overflow: TextOverflow.ellipsis),
                                ),
                              )
                              .toList(),
                          onChanged: (v) => setState(() => line.itemId = v ?? ''),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: line.qtyController,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(
                            labelText: 'كمية',
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: _lines.length <= 1
                            ? null
                            : () => setState(() {
                                  _lines[i].qtyController.dispose();
                                  _lines.removeAt(i);
                                }),
                        icon: const Icon(Icons.remove_circle_outline, color: Colors.red, size: 20),
                      ),
                    ],
                  );
                }),
                TextButton.icon(
                  onPressed: () => setState(
                    () => _lines.add(
                      _ModifierIngredientLine(itemId: '', qtyController: TextEditingController(text: '1')),
                    ),
                  ),
                  icon: const Icon(Icons.add),
                  label: const Text('سطر مكوّن'),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: InventoryTheme.burgundy),
                    onPressed: () => widget.onSave(widget.modifierId, widget.modifierName, _lines),
                    child: const Text('حفظ وصفة الإضافة'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}