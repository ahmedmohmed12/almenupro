import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_strings.dart';
import '../../models/cart_item.dart';
import '../../models/menu_item.dart';
import '../../providers/cart_provider.dart';
import '../../providers/locale_provider.dart';
import '../../theme/app_theme.dart';

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

Future<void> showCustomizationDialog(
  BuildContext context,
  MenuItem item, {
  void Function(CartItem cartItem)? onAdd,
}) async {
  await showDialog<void>(
    context: context,
    builder: (context) => _CustomizationDialog(item: item, onAdd: onAdd),
  );
}

class _CustomizationDialog extends StatefulWidget {
  const _CustomizationDialog({
    required this.item,
    this.onAdd,
  });

  final MenuItem item;
  final void Function(CartItem cartItem)? onAdd;

  @override
  State<_CustomizationDialog> createState() => _CustomizationDialogState();
}

class _CustomizationDialogState extends State<_CustomizationDialog> {
  final _notesController = TextEditingController();
  int _quantity = 1;
  final Map<String, String?> _singleSelections = {};
  final Map<String, Set<String>> _multiSelections = {};

  List<_OptionGroupView> get _groups {
    final grouped = <String, List<MenuOption>>{};
    for (final option in widget.item.availableOptions) {
      final groupName =
          option.group.trim().isEmpty ? 'إضافات' : option.group.trim();
      grouped.putIfAbsent(groupName, () => []).add(option);
    }

    return grouped.entries
        .map(
          (entry) => _OptionGroupView(
            name: entry.key,
            groupRequired: entry.value.any((option) => option.isGroupRequired),
            allowMultiple: entry.value.any((option) => option.allowMultiple),
            options: entry.value,
          ),
        )
        .toList();
  }

  @override
  void initState() {
    super.initState();
    for (final group in _groups) {
      if (group.allowMultiple) {
        _multiSelections[group.name] = <String>{};
      } else if (group.groupRequired && group.options.isNotEmpty) {
        _singleSelections[group.name] = group.options.first.id;
      } else {
        _singleSelections[group.name] = null;
      }
    }
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  List<SelectedOption> get _selectedOptions {
    final selected = <SelectedOption>[];

    for (final group in _groups) {
      if (group.allowMultiple) {
        final ids = _multiSelections[group.name] ?? {};
        for (final option in group.options) {
          if (ids.contains(option.id)) {
            selected.add(
              SelectedOption(
                group: group.name,
                name: option.localizedName(_localeCode),
                price: option.price,
              ),
            );
          }
        }
      } else {
        final selectedId = _singleSelections[group.name];
        if (selectedId == null) continue;
        final option = group.options.firstWhere(
          (entry) => entry.id == selectedId,
          orElse: () => group.options.first,
        );
        selected.add(
          SelectedOption(
            group: group.name,
            name: option.localizedName(_localeCode),
            price: option.price,
          ),
        );
      }
    }

    return selected;
  }

  String get _localeCode =>
      mounted ? context.read<LocaleProvider>().localeCode : 'ar';

  double get _unitPrice {
    final modifiers =
        _selectedOptions.fold<double>(0, (sum, option) => sum + option.price);
    return widget.item.price + modifiers;
  }

  bool _validateSelections(AppStrings strings) {
    for (final group in _groups) {
      if (!group.groupRequired) continue;

      if (group.allowMultiple) {
        final count = _multiSelections[group.name]?.length ?? 0;
        if (count == 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(strings.requiredAddonGroup(group.name))),
          );
          return false;
        }
      } else if (_singleSelections[group.name] == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(strings.requiredAddonGroup(group.name))),
        );
        return false;
      }
    }
    return true;
  }

  void _addToCart() {
    final strings = AppStrings.of(context);
    if (!_validateSelections(strings)) return;

    final cartItem = CartItem(
      id: '${widget.item.id}_${DateTime.now().microsecondsSinceEpoch}',
      menuItem: widget.item,
      selectedOptions: _selectedOptions,
      quantity: _quantity,
      specialNotes: _notesController.text.trim().isEmpty
          ? null
          : _notesController.text.trim(),
    );

    if (widget.onAdd != null) {
      widget.onAdd!(cartItem);
    } else {
      context.read<CartProvider>().addItem(
            menuItem: widget.item,
            selectedOptions: _selectedOptions,
            quantity: _quantity,
            specialNotes: cartItem.specialNotes,
          );
    }

    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          strings.addedToCart(widget.item.localizedName(_localeCode)),
        ),
      ),
    );
  }

  String _priceLabel(double price, AppStrings strings) {
    if (price <= 0) return strings.freeAddon;
    return '+${price.toStringAsFixed(3)} ${strings.currency}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final strings = AppStrings.of(context);
    final localeCode = context.watch<LocaleProvider>().localeCode;
    final displayName = widget.item.localizedName(localeCode);
    final displayDescription = widget.item.localizedDescription(localeCode);

    return AlertDialog(
      title: Text(displayName),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (displayDescription.isNotEmpty)
                Text(
                  displayDescription,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              if (displayDescription.isNotEmpty) const SizedBox(height: 16),
              Text(
                strings.basePriceLabel(
                  widget.item.price.toStringAsFixed(3),
                ),
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppTheme.brandMaroon,
                ),
              ),
              const SizedBox(height: 16),
              ..._groups.map((group) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              group.name,
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          if (group.groupRequired)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.red.shade50,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                strings.requiredLabel,
                                style: TextStyle(
                                  color: Colors.red.shade700,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (group.allowMultiple)
                        ...group.options.map((option) {
                          final selected =
                              _multiSelections[group.name]?.contains(option.id) ??
                                  false;
                          return CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                            value: selected,
                            title: Text(option.localizedName(localeCode)),
                            subtitle: Text(_priceLabel(option.price, strings)),
                            onChanged: (checked) {
                              setState(() {
                                final current = _multiSelections.putIfAbsent(
                                  group.name,
                                  () => <String>{},
                                );
                                if (checked == true) {
                                  current.add(option.id);
                                } else {
                                  current.remove(option.id);
                                }
                              });
                            },
                          );
                        })
                      else ...[
                        if (!group.groupRequired)
                          RadioListTile<String?>(
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                            title: Text(strings.noAddonSelected),
                            value: null,
                            groupValue: _singleSelections[group.name],
                            onChanged: (value) {
                              setState(() => _singleSelections[group.name] = value);
                            },
                          ),
                        ...group.options.map((option) {
                          return RadioListTile<String?>(
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                            title: Text(option.localizedName(localeCode)),
                            subtitle: Text(_priceLabel(option.price, strings)),
                            value: option.id,
                            groupValue: _singleSelections[group.name],
                            onChanged: (value) {
                              setState(() => _singleSelections[group.name] = value);
                            },
                          );
                        }),
                      ],
                    ],
                  ),
                );
              }),
              TextField(
                controller: _notesController,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: strings.specialNotesLabel,
                  hintText: strings.specialNotesHint,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    onPressed:
                        _quantity > 1 ? () => setState(() => _quantity--) : null,
                    icon: const Icon(Icons.remove_circle_outline),
                  ),
                  Text(
                    '$_quantity',
                    style: theme.textTheme.titleLarge,
                  ),
                  IconButton(
                    onPressed: () => setState(() => _quantity++),
                    icon: const Icon(Icons.add_circle_outline),
                  ),
                ],
              ),
              Text(
                strings.totalWithAddons(
                  (_unitPrice * _quantity).toStringAsFixed(3),
                ),
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: AppTheme.brandPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(strings.cancel),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: AppTheme.brandMaroon,
          ),
          onPressed: _addToCart,
          child: Text(strings.addToCart),
        ),
      ],
    );
  }
}
