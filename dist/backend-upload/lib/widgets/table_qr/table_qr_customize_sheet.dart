import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_strings.dart';
import '../../models/cart_item.dart';
import '../../models/menu_item.dart';
import '../../providers/cart_provider.dart';
import '../../providers/locale_provider.dart';
import '../../theme/app_theme.dart';
import '../network_menu_image.dart';

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

bool tableQrHasMandatoryOptions(MenuItem item) {
  return item.availableOptions.any((option) => option.isGroupRequired);
}

Future<void> showTableQrCustomizeSheet(
  BuildContext context,
  MenuItem item,
) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (_) => TableQrCustomizeSheet(item: item),
  );
}

class TableQrCustomizeSheet extends StatefulWidget {
  const TableQrCustomizeSheet({super.key, required this.item});

  final MenuItem item;

  @override
  State<TableQrCustomizeSheet> createState() => _TableQrCustomizeSheetState();
}

class _TableQrCustomizeSheetState extends State<TableQrCustomizeSheet> {
  final _notesController = TextEditingController();
  var _quantity = 1;
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
    final locale = context.read<LocaleProvider>().localeCode;
    final selected = <SelectedOption>[];
    for (final group in _groups) {
      if (group.allowMultiple) {
        for (final id in _multiSelections[group.name] ?? {}) {
          final option = group.options.firstWhere((entry) => entry.id == id);
          selected.add(
            SelectedOption(
              group: group.name,
              name: option.localizedName(locale),
              price: option.price,
            ),
          );
        }
      } else {
        final id = _singleSelections[group.name];
        if (id == null) continue;
        final option = group.options.firstWhere((entry) => entry.id == id);
        selected.add(
          SelectedOption(
            group: group.name,
            name: option.localizedName(locale),
            price: option.price,
          ),
        );
      }
    }
    return selected;
  }

  bool get _valid {
    for (final group in _groups) {
      if (!group.groupRequired) continue;
      if (group.allowMultiple) {
        if ((_multiSelections[group.name] ?? {}).isEmpty) return false;
      } else if (_singleSelections[group.name] == null) {
        return false;
      }
    }
    return true;
  }

  double get _unitPrice {
    final extras = _selectedOptions.fold<double>(
      0,
      (sum, option) => sum + option.price,
    );
    return widget.item.price + extras;
  }

  void _add() {
    if (!_valid) return;
    context.read<CartProvider>().addItem(
      menuItem: widget.item,
      selectedOptions: _selectedOptions,
      quantity: _quantity,
      specialNotes: _notesController.text.trim().isEmpty
          ? null
          : _notesController.text.trim(),
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.read(context);
    final locale = strings.localeCode;
    final bottom = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + bottom),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    width: 72,
                    height: 72,
                    child: widget.item.imageUrl.trim().isEmpty
                        ? Container(
                            color: AppTheme.brandSurface,
                            child: const Icon(Icons.restaurant),
                          )
                        : NetworkMenuImage(
                            imageUrl: widget.item.imageUrl,
                            fit: BoxFit.cover,
                          ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.item.localizedName(locale),
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${_unitPrice.toStringAsFixed(2)} ${strings.currency}',
                        style: const TextStyle(
                          color: AppTheme.brandOrange,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            for (final group in _groups) ...[
              Text(
                group.groupRequired ? '${group.name} *' : group.name,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final option in group.options)
                    FilterChip(
                      selected: group.allowMultiple
                          ? (_multiSelections[group.name] ?? {}).contains(
                              option.id,
                            )
                          : _singleSelections[group.name] == option.id,
                      label: Text(
                        option.price > 0
                            ? '${option.localizedName(locale)} (+${option.price.toStringAsFixed(2)})'
                            : option.localizedName(locale),
                      ),
                      onSelected: (selected) {
                        setState(() {
                          if (group.allowMultiple) {
                            final set = _multiSelections[group.name] ?? {};
                            if (selected) {
                              set.add(option.id);
                            } else {
                              set.remove(option.id);
                            }
                            _multiSelections[group.name] = set;
                          } else {
                            _singleSelections[group.name] =
                                selected ? option.id : null;
                          }
                        });
                      },
                    ),
                ],
              ),
              const SizedBox(height: 14),
            ],
            TextField(
              controller: _notesController,
              maxLines: 2,
              decoration: InputDecoration(
                labelText: strings.tr('ملاحظات خاصة', 'Special instructions'),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                IconButton.filledTonal(
                  onPressed: _quantity > 1
                      ? () => setState(() => _quantity -= 1)
                      : null,
                  icon: const Icon(Icons.remove),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(
                    '$_quantity',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                IconButton.filledTonal(
                  onPressed: () => setState(() => _quantity += 1),
                  icon: const Icon(Icons.add),
                ),
                const Spacer(),
                FilledButton(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 44),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: _valid ? _add : null,
                  child: Text(
                    strings.tr(
                      'أضف ${(_unitPrice * _quantity).toStringAsFixed(2)} ${strings.currency}',
                      'Add ${(_unitPrice * _quantity).toStringAsFixed(2)} ${strings.currency}',
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
