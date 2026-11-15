import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../models/cart_item.dart';
import '../../../models/menu_item.dart';
import 'pos_theme.dart';

/// Foodics-style modifiers sheet for POS item customizations.
Future<CartItem?> showPosFastModifiersDialog(
  BuildContext context,
  MenuItem item,
) async {
  return showGeneralDialog<CartItem>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Dismiss',
    barrierColor: Colors.black54,
    transitionDuration: Duration.zero,
    pageBuilder: (context, animation, secondaryAnimation) {
      return Align(
        alignment: Alignment.bottomCenter,
        child: _PosFastModifiersSheet(item: item),
      );
    },
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

class _PosFastModifiersSheet extends StatefulWidget {
  const _PosFastModifiersSheet({required this.item});

  final MenuItem item;

  @override
  State<_PosFastModifiersSheet> createState() => _PosFastModifiersSheetState();
}

class _PosFastModifiersSheetState extends State<_PosFastModifiersSheet> {
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
    final mods = _selectedOptions.fold<double>(0, (sum, o) => sum + o.price);
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
    final height = MediaQuery.sizeOf(context).height * 0.88;
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
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Material(
              color: PosTheme.surface,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
              clipBehavior: Clip.antiAlias,
              child: SizedBox(
                height: height,
                width: double.infinity,
                child: Column(
                  children: [
                    const SizedBox(height: 10),
                    Container(
                      width: 44,
                      height: 4,
                      decoration: BoxDecoration(
                        color: PosTheme.border,
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 14, 8, 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.item.name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 20,
                                    color: PosTheme.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'السعر الأساسي ${widget.item.price.toStringAsFixed(3)} د.ك',
                                  style: const TextStyle(
                                    color: PosTheme.textMuted,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.of(context).pop(),
                            icon: const Icon(Icons.close_rounded),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                        children: [
                          ..._groups.map(_buildGroup),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _notesController,
                            decoration: InputDecoration(
                              labelText: 'ملاحظة خاصة',
                              hintText: 'مثال: بدون صوص',
                              filled: true,
                              fillColor: PosTheme.surfaceAlt,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide.none,
                              ),
                            ),
                            maxLines: 2,
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                      decoration: const BoxDecoration(
                        color: PosTheme.surface,
                        border: Border(top: BorderSide(color: PosTheme.border)),
                        boxShadow: [
                          BoxShadow(
                            color: Color(0x14000000),
                            blurRadius: 12,
                            offset: Offset(0, -2),
                          ),
                        ],
                      ),
                      child: SafeArea(
                        top: false,
                        child: Row(
                          children: [
                            _QtyButton(
                              icon: Icons.remove,
                              onTap: _quantity > 1
                                  ? () => setState(() => _quantity--)
                                  : null,
                            ),
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 14),
                              child: Text(
                                '$_quantity',
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            _QtyButton(
                              icon: Icons.add,
                              onTap: () => setState(() => _quantity++),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: SizedBox(
                                height: 52,
                                child: FilledButton(
                                  style: FilledButton.styleFrom(
                                    backgroundColor: PosTheme.orange,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                  ),
                                  onPressed: _confirm,
                                  child: Text(
                                    'تأكيد الإضافة  ·  ${(_unitPrice * _quantity).toStringAsFixed(3)} د.ك',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 15,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGroup(_OptionGroupView group) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  group.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: PosTheme.textPrimary,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: group.groupRequired
                      ? const Color(0xFFFEE2E2)
                      : PosTheme.surfaceAlt,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  group.groupRequired
                      ? 'مطلوب'
                      : (group.allowMultiple ? 'متعدد' : 'اختيار واحد'),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: group.groupRequired
                        ? const Color(0xFFB91C1C)
                        : PosTheme.textMuted,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: group.options.map((option) {
              final priceLabel = option.price > 0
                  ? '  +${option.price.toStringAsFixed(3)} د.ك'
                  : '';
              final selected = group.allowMultiple
                  ? (_multiSelections[group.name]?.contains(option.id) ?? false)
                  : _singleSelections[group.name] == option.id;

              return Material(
                color: selected ? PosTheme.orangeSoft : PosTheme.surfaceAlt,
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () {
                    setState(() {
                      if (group.allowMultiple) {
                        final set =
                            _multiSelections.putIfAbsent(group.name, () => {});
                        if (selected) {
                          set.remove(option.id);
                        } else {
                          set.add(option.id);
                        }
                      } else {
                        _singleSelections[group.name] = option.id;
                      }
                    });
                  },
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 48),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: selected ? PosTheme.orange : PosTheme.border,
                        width: selected ? 1.6 : 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          group.allowMultiple
                              ? (selected
                                  ? Icons.check_box_rounded
                                  : Icons.check_box_outline_blank_rounded)
                              : (selected
                                  ? Icons.radio_button_checked
                                  : Icons.radio_button_off),
                          size: 18,
                          color: selected ? PosTheme.orange : PosTheme.textMuted,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${option.name}$priceLabel',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: selected
                                ? PosTheme.orange
                                : PosTheme.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
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
      color: onTap == null ? PosTheme.border : PosTheme.orangeSoft,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: 44,
          height: 44,
          child: Icon(icon, size: 22, color: PosTheme.orange),
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
