import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../models/cart_item.dart';
import '../../../models/menu_item.dart';
import '../../../theme/app_theme.dart';
import 'pos_theme.dart';

/// Lightweight POS modifier popup — fewer clicks than the full customer dialog.
Future<CartItem?> showPosFastModifiersDialog(
  BuildContext context,
  MenuItem item,
) async {
  return showDialog<CartItem>(
    context: context,
    barrierDismissible: true,
    builder: (context) => _PosFastModifiersDialog(item: item),
  );
}

class _OptionGroupView {
  const _OptionGroupView({
    required this.name,
    required this.groupRequired,
    required this.allowMultiple,
    required this.options,
  });

  final String name;
  final bool groupRequired;
  final bool allowMultiple;
  final List<MenuOption> options;
}

class _PosFastModifiersDialog extends StatefulWidget {
  const _PosFastModifiersDialog({required this.item});

  final MenuItem item;

  @override
  State<_PosFastModifiersDialog> createState() =>
      _PosFastModifiersDialogState();
}

class _PosFastModifiersDialogState extends State<_PosFastModifiersDialog> {
  final _notesController = TextEditingController();
  var _quantity = 1;
  final Map<String, String> _singleSelections = {};
  final Map<String, Set<String>> _multiSelections = {};

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  List<_OptionGroupView> get _groups {
    final grouped = <String, List<MenuOption>>{};
    for (final option in widget.item.options.where((o) => o.isAvailable)) {
      grouped.putIfAbsent(option.group, () => []).add(option);
    }
    return grouped.entries
        .map(
          (entry) => _OptionGroupView(
            name: entry.key,
            groupRequired: entry.value.any((o) => o.isGroupRequired),
            allowMultiple: entry.value.any((o) => o.allowMultiple),
            options: entry.value,
          ),
        )
        .toList();
  }

  List<SelectedOption> get _selectedOptions {
    final result = <SelectedOption>[];
    for (final group in _groups) {
      if (group.allowMultiple) {
        final ids = _multiSelections[group.name] ?? {};
        for (final option in group.options) {
          if (ids.contains(option.id)) {
            result.add(
              SelectedOption(
                group: group.name,
                name: option.name,
                price: option.price,
              ),
            );
          }
        }
      } else {
        final selectedId = _singleSelections[group.name];
        if (selectedId == null) continue;
        final option = group.options.firstWhere((o) => o.id == selectedId);
        result.add(
          SelectedOption(
            group: group.name,
            name: option.name,
            price: option.price,
          ),
        );
      }
    }
    return result;
  }

  double get _unitPrice {
    final mods =
        _selectedOptions.fold<double>(0, (sum, o) => sum + o.price);
    return widget.item.price + mods;
  }

  bool _validate() {
    for (final group in _groups) {
      if (!group.groupRequired) continue;
      if (group.allowMultiple) {
        if ((_multiSelections[group.name] ?? {}).isEmpty) {
          _toast('اختر: ${group.name}');
          return false;
        }
      } else if (!_singleSelections.containsKey(group.name)) {
        _toast('اختر: ${group.name}');
        return false;
      }
    }
    return true;
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
  }

  void _confirm() {
    if (!_validate()) return;
    final cartItem = CartItem(
      id: '${widget.item.id}_${DateTime.now().microsecondsSinceEpoch}',
      menuItem: widget.item,
      selectedOptions: _selectedOptions,
      quantity: _quantity,
      specialNotes: _notesController.text.trim().isEmpty
          ? null
          : _notesController.text.trim(),
    );
    Navigator.of(context).pop(cartItem);
  }

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: {
        const SingleActivator(LogicalKeyboardKey.enter): const _ConfirmIntent(),
        const SingleActivator(LogicalKeyboardKey.numpadEnter):
            const _ConfirmIntent(),
        const SingleActivator(LogicalKeyboardKey.escape): const _CloseIntent(),
      },
      child: Actions(
        actions: {
          _ConfirmIntent: CallbackAction<_ConfirmIntent>(
            onInvoke: (_) {
              _confirm();
              return null;
            },
          ),
          _CloseIntent: CallbackAction<_CloseIntent>(
            onInvoke: (_) {
              Navigator.of(context).pop();
              return null;
            },
          ),
        },
        child: Focus(
          autofocus: true,
          child: Dialog(
            insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480, maxHeight: 560),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.item.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 17,
                                ),
                              ),
                              Text(
                                '${widget.item.price.toStringAsFixed(3)} د.ك',
                                style: const TextStyle(
                                  color: PosTheme.accent,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        ..._groups.map(_buildGroup),
                        TextField(
                          controller: _notesController,
                          decoration: InputDecoration(
                            labelText: 'ملاحظة خاصة',
                            hintText: 'مثال: بدون صوص',
                            isDense: true,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          maxLines: 2,
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: PosTheme.surfaceAlt,
                      border: Border(top: BorderSide(color: PosTheme.border)),
                    ),
                    child: Row(
                      children: [
                        _QtyButton(
                          icon: Icons.remove,
                          onTap: _quantity > 1
                              ? () => setState(() => _quantity--)
                              : null,
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Text(
                            '$_quantity',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        _QtyButton(
                          icon: Icons.add,
                          onTap: () => setState(() => _quantity++),
                        ),
                        const Spacer(),
                        Text(
                          '${(_unitPrice * _quantity).toStringAsFixed(3)} د.ك',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: PosTheme.accent,
                          ),
                        ),
                        const SizedBox(width: 12),
                        FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: AppTheme.brandMaroon,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 14,
                            ),
                          ),
                          onPressed: _confirm,
                          child: const Text('إضافة Enter'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGroup(_OptionGroupView group) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                group.name,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              if (group.groupRequired) ...[
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'مطلوب',
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.red.shade700,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: group.options.map((option) {
              final priceLabel = option.price > 0
                  ? ' (+${option.price.toStringAsFixed(3)})'
                  : '';
              if (group.allowMultiple) {
                final selected =
                    _multiSelections[group.name]?.contains(option.id) ?? false;
                return FilterChip(
                  label: Text('${option.name}$priceLabel'),
                  selected: selected,
                  onSelected: (checked) {
                    setState(() {
                      final set =
                          _multiSelections.putIfAbsent(group.name, () => {});
                      if (checked) {
                        set.add(option.id);
                      } else {
                        set.remove(option.id);
                      }
                    });
                  },
                  selectedColor: PosTheme.accentSoft,
                  checkmarkColor: PosTheme.accent,
                );
              }

              final selected = _singleSelections[group.name] == option.id;
              return ChoiceChip(
                label: Text('${option.name}$priceLabel'),
                selected: selected,
                onSelected: (_) {
                  setState(() => _singleSelections[group.name] = option.id);
                },
                selectedColor: PosTheme.accentSoft,
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

class _QtyButton extends StatelessWidget {
  const _QtyButton({required this.icon, this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: onTap == null ? PosTheme.border : PosTheme.accentSoft,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          width: 40,
          height: 40,
          child: Icon(icon, size: 20, color: PosTheme.accent),
        ),
      ),
    );
  }
}

class _ConfirmIntent extends Intent {
  const _ConfirmIntent();
}

class _CloseIntent extends Intent {
  const _CloseIntent();
}
