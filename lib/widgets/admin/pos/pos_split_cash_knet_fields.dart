import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../l10n/app_strings.dart';
import '../../../utils/order_payments.dart';
import 'pos_theme.dart';

enum PosPayMode { cash, knet, split }

class PosSplitCashKnetFields extends StatelessWidget {
  const PosSplitCashKnetFields({
    super.key,
    required this.total,
    required this.cashController,
    required this.knetController,
    this.onChanged,
  });

  final double total;
  final TextEditingController cashController;
  final TextEditingController knetController;
  final VoidCallback? onChanged;

  double get _cash =>
      double.tryParse(cashController.text.trim().replaceAll(',', '')) ?? 0;
  double get _knet =>
      double.tryParse(knetController.text.trim().replaceAll(',', '')) ?? 0;

  double get remaining => money3((total - _cash - _knet).clamp(-99999, 99999));

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final balanced = remaining.abs() <= 0.0005 && _cash > 0 && _knet > 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: cashController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
          ],
          decoration: InputDecoration(
            labelText: s.tr('المبلغ كاش', 'Cash amount'),
            prefixIcon: const Icon(Icons.payments_outlined),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            isDense: true,
          ),
          onChanged: (value) {
            final cash = double.tryParse(value.trim()) ?? 0;
            final nextKnet = money3((total - cash).clamp(0, 999999));
            if (knetController.text.trim().isEmpty ||
                (double.tryParse(knetController.text.trim()) ?? 0) <= 0) {
              knetController.text = nextKnet.toStringAsFixed(3);
            }
            onChanged?.call();
          },
        ),
        const SizedBox(height: 8),
        TextField(
          controller: knetController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
          ],
          decoration: InputDecoration(
            labelText: s.tr('المبلغ كي نت', 'K-Net amount'),
            prefixIcon: const Icon(Icons.credit_card),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            isDense: true,
          ),
          onChanged: (_) => onChanged?.call(),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () {
                  knetController.text = money3(total - _cash).toStringAsFixed(3);
                  onChanged?.call();
                },
                child: Text(
                  s.tr(
                    'الباقي لكي نت (${money3(total - _cash).toStringAsFixed(3)})',
                    'Use K-Net remainder (${money3(total - _cash).toStringAsFixed(3)})',
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          s.tr(
            'المتبقي: ${remaining.toStringAsFixed(3)} د.ك',
            'Remaining: ${remaining.toStringAsFixed(3)} KWD',
          ),
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: balanced ? PosTheme.green : PosTheme.orange,
          ),
        ),
      ],
    );
  }
}