import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_strings.dart';
import '../../providers/cart_provider.dart';
import '../../theme/app_theme.dart';

Future<String?> showTableQrOrderSummarySheet({
  required BuildContext context,
  required String tableLabel,
  required Future<void> Function(String kitchenNotes) onSendToKitchen,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (_) => TableQrOrderSummarySheet(
      tableLabel: tableLabel,
      onSendToKitchen: onSendToKitchen,
    ),
  );
}

class TableQrOrderSummarySheet extends StatefulWidget {
  const TableQrOrderSummarySheet({
    super.key,
    required this.tableLabel,
    required this.onSendToKitchen,
  });

  final String tableLabel;
  final Future<void> Function(String kitchenNotes) onSendToKitchen;

  @override
  State<TableQrOrderSummarySheet> createState() =>
      _TableQrOrderSummarySheetState();
}

class _TableQrOrderSummarySheetState extends State<TableQrOrderSummarySheet> {
  final _notesController = TextEditingController();
  var _submitting = false;

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    setState(() => _submitting = true);
    try {
      await widget.onSendToKitchen(_notesController.text.trim());
      if (!mounted) return;
      Navigator.of(context).pop('sent');
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
        ),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.read(context);
    final cart = context.watch<CartProvider>();
    final bottom = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
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
          const SizedBox(height: 12),
          Text(
            strings.tr('ملخص الطلب', 'Order summary'),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            widget.tableLabel,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppTheme.brandMaroon,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 14),
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.38,
            ),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: cart.items.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final item = cart.items[index];
                final extras = item.selectedOptions
                    .map((option) => option.name)
                    .where((name) => name.trim().isNotEmpty)
                    .join(' · ');
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    item.menuItem.localizedName(strings.localeCode),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(
                    [
                      'x${item.quantity}',
                      if (extras.isNotEmpty) extras,
                      if ((item.specialNotes ?? '').trim().isNotEmpty)
                        item.specialNotes!,
                    ].join(' · '),
                  ),
                  trailing: Text(
                    '${item.totalPrice.toStringAsFixed(2)} ${strings.currency}',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  leading: IconButton(
                    onPressed: () => cart.removeItem(item.id),
                    icon: const Icon(Icons.delete_outline),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _notesController,
            maxLines: 2,
            decoration: InputDecoration(
              labelText: strings.tr('ملاحظات للمطبخ', 'Kitchen notes'),
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Text(
                strings.tr('الإجمالي', 'Total'),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              Text(
                '${cart.totalPrice.toStringAsFixed(2)} ${strings.currency}',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.brandOrange,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: cart.isEmpty || _submitting ? null : _submit,
            icon: _submitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.soup_kitchen_outlined),
            label: Text(
              strings.tr('إرسال الطلب للمطبخ', 'Send order to kitchen'),
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          TextButton(
            onPressed: _submitting ? null : () => Navigator.pop(context),
            child: Text(strings.tr('متابعة الطلب', 'Keep ordering')),
          ),
        ],
      ),
    );
  }
}
