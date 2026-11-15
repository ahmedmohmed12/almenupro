import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../models/order.dart';
import '../../../models/sales_platform_config.dart';
import '../../../services/pos_print_helper.dart';
import '../../../services/pos_print_settings_service.dart';
import '../../../utils/pos_receipt_html.dart';
import 'pos_theme.dart';

/// Shows thermal receipt preview and triggers browser print on Proceed.
Future<void> showPosPrintPreviewDialog(
  BuildContext context, {
  required Order order,
  String restaurantName = 'المطعم',
  required PosReceiptKind kind,
  String? restaurantPhone,
  String? restaurantAddress,
  List<SalesPlatformConfig>? platforms,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => PosPrintPreviewDialog(
      order: order,
      restaurantName: restaurantName,
      kind: kind,
      restaurantPhone: restaurantPhone,
      restaurantAddress: restaurantAddress,
    ),
  );
}

class PosPrintPreviewDialog extends StatefulWidget {
  const PosPrintPreviewDialog({
    super.key,
    required this.order,
    required this.restaurantName,
    required this.kind,
    this.restaurantPhone,
    this.restaurantAddress,
  });

  final Order order;
  final String restaurantName;
  final PosReceiptKind kind;
  final String? restaurantPhone;
  final String? restaurantAddress;

  @override
  State<PosPrintPreviewDialog> createState() => _PosPrintPreviewDialogState();
}

class _PosPrintPreviewDialogState extends State<PosPrintPreviewDialog> {
  var _paperWidth = PosReceiptPaperWidth.mm80;
  var _printing = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadPaper());
  }

  Future<void> _loadPaper() async {
    await PosPrintSettingsService.instance.initialize();
    if (!mounted) return;
    final mm = PosPrintSettingsService.instance.settings.widthMm;
    setState(() {
      _paperWidth =
          mm <= 62 ? PosReceiptPaperWidth.mm58 : PosReceiptPaperWidth.mm80;
    });
  }

  bool get _isKitchen => widget.kind == PosReceiptKind.kitchen;

  String get _title =>
      _isKitchen ? 'معاينة تذكرة المطبخ' : 'معاينة فاتورة العميل';

  Future<void> _print() async {
    setState(() => _printing = true);
    try {
      final preset = _paperWidth == PosReceiptPaperWidth.mm58
          ? PosPrintPaperPreset.mm58
          : PosPrintPaperPreset.mm80;
      await PosPrintHelper.printOrder(
        order: widget.order,
        kind: widget.kind,
        overrideSettings: PosPrintHelper.settings.copyWith(paperPreset: preset),
      );
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تعذرت الطباعة: $error'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final previewWidth =
        _paperWidth == PosReceiptPaperWidth.mm58 ? 220.0 : 302.0;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 720),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  const Text(
                    'مقاس الورق:',
                    style: TextStyle(fontSize: 12, color: PosTheme.textMuted),
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('80mm'),
                    selected: _paperWidth == PosReceiptPaperWidth.mm80,
                    onSelected: (_) =>
                        setState(() => _paperWidth = PosReceiptPaperWidth.mm80),
                  ),
                  const SizedBox(width: 6),
                  ChoiceChip(
                    label: const Text('58mm'),
                    selected: _paperWidth == PosReceiptPaperWidth.mm58,
                    onSelected: (_) =>
                        setState(() => _paperWidth = PosReceiptPaperWidth.mm58),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFFE8ECF0),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: PosTheme.border),
                ),
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Container(
                      width: previewWidth,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x33000000),
                            blurRadius: 12,
                            offset: Offset(0, 4),
                          ),
                        ],
                      ),
                      child: PosThermalReceiptPreview(
                        order: widget.order,
                        restaurantName: widget.restaurantName,
                        kind: widget.kind,
                        restaurantPhone: widget.restaurantPhone,
                        restaurantAddress: widget.restaurantAddress,
                        paperWidth: _paperWidth,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            _buildActions(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
      child: Row(
        children: [
          Icon(
            _isKitchen ? Icons.restaurant : Icons.receipt_long,
            color: PosTheme.accent,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                Text(
                  'طلب #${widget.order.invoiceNumber ?? widget.order.id}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: PosTheme.textMuted,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'إغلاق',
            onPressed: _printing ? null : () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }

  Widget _buildActions() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _printing ? null : () => Navigator.of(context).pop(),
              icon: const Icon(Icons.arrow_back),
              label: const Text('رجوع'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: FilledButton.icon(
              onPressed: _printing ? null : _print,
              icon: _printing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.print),
              label: Text(_isKitchen ? 'طباعة المطبخ' : 'طباعة فورية'),
              style: FilledButton.styleFrom(
                backgroundColor: PosTheme.success,
                minimumSize: const Size.fromHeight(48),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Flutter mirror of the thermal HTML receipt for on-screen preview.
class PosThermalReceiptPreview extends StatelessWidget {
  const PosThermalReceiptPreview({
    super.key,
    required this.order,
    required this.restaurantName,
    required this.kind,
    required this.paperWidth,
    this.restaurantPhone,
    this.restaurantAddress,
  });

  final Order order;
  final String restaurantName;
  final PosReceiptKind kind;
  final PosReceiptPaperWidth paperWidth;
  final String? restaurantPhone;
  final String? restaurantAddress;

  @override
  Widget build(BuildContext context) {
    final isKitchen = kind == PosReceiptKind.kitchen;
    final baseSize = paperWidth == PosReceiptPaperWidth.mm58 ? 9.0 : 11.0;
    final time =
        DateFormat('yyyy-MM-dd HH:mm').format(order.createdAt.toLocal());
    final subtotal = order.subtotal ?? order.totalPrice;
    final deliveryFee = order.deliveryFee ?? 0;

    return Padding(
      padding: EdgeInsets.all(paperWidth == PosReceiptPaperWidth.mm58 ? 8 : 12),
      child: DefaultTextStyle(
        style: TextStyle(
          fontFamily: 'Courier',
          fontSize: baseSize,
          color: Colors.black,
          height: 1.35,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              restaurantName,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: baseSize + 4,
              ),
            ),
            if (restaurantPhone?.trim().isNotEmpty ?? false)
              Text('📞 ${restaurantPhone!.trim()}', textAlign: TextAlign.center),
            if (restaurantAddress?.trim().isNotEmpty ?? false)
              Text('📍 ${restaurantAddress!.trim()}', textAlign: TextAlign.center),
            const _DashedDivider(),
            Text(
              isKitchen ? 'تذكرة المطبخ' : 'فاتورة العميل',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: baseSize + 2,
              ),
            ),
            const _DashedDivider(),
            _MetaRow(label: 'طلب #', value: order.invoiceNumber ?? order.id),
            _MetaRow(label: 'الوقت', value: time),
            _MetaRow(label: 'العميل', value: order.customerName),
            _MetaRow(label: 'هاتف', value: order.phone),
            if (!isKitchen) _MetaRow(label: 'العنوان', value: order.address),
            if (!isKitchen)
              _MetaRow(label: 'الدفع', value: order.paymentMethod ?? 'كاش'),
            _MetaRow(
              label: 'النوع',
              value: switch (order.orderType) {
                OrderType.pickup => 'استلام',
                OrderType.dineIn => 'صالة',
                OrderType.delivery => 'توصيل',
              },
            ),
            const _DashedDivider(),
            if (isKitchen)
              ...order.items.map((item) => _KitchenItemRow(item: item))
            else ...[
              Row(
                children: [
                  SizedBox(
                    width: 28,
                    child: Text('كم', style: TextStyle(fontSize: baseSize - 1)),
                  ),
                  Expanded(
                    child: Text('الصنف', style: TextStyle(fontSize: baseSize - 1)),
                  ),
                  Text('د.ك', style: TextStyle(fontSize: baseSize - 1)),
                ],
              ),
              const _DashedDivider(),
              ...order.items.map((item) => _CustomerItemRow(item: item)),
              const _DashedDivider(),
              _TotalLine(label: 'المجموع الفرعي', value: subtotal),
              _TotalLine(label: 'التوصيل', value: deliveryFee),
              _TotalLine(
                label: 'الإجمالي',
                value: order.totalPrice,
                bold: true,
              ),
            ],
            const _DashedDivider(),
            Text(
              isKitchen ? '— المطبخ —' : 'شكراً لزيارتكم',
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            const Text(
              'Almenupro POS',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 8, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}

class _DashedDivider extends StatelessWidget {
  const _DashedDivider();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: LayoutBuilder(
        builder: (context, constraints) {
          const dashWidth = 4.0;
          const dashSpace = 3.0;
          final count =
              (constraints.maxWidth / (dashWidth + dashSpace)).floor();
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(
              count,
              (_) => const SizedBox(
                width: dashWidth,
                height: 1,
                child: ColoredBox(color: Colors.black),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: RichText(
        text: TextSpan(
          style: DefaultTextStyle.of(context).style,
          children: [
            TextSpan(
              text: '$label ',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            TextSpan(text: value),
          ],
        ),
      ),
    );
  }
}

class _KitchenItemRow extends StatelessWidget {
  const _KitchenItemRow({required this.item});

  final OrderLineItem item;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${item.quantity}x',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 20,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                ...item.selectedOptions.map(
                  (o) => Text(
                    '+ ${o.group}: ${o.name}',
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
                if (item.specialNotes?.trim().isNotEmpty ?? false)
                  Container(
                    margin: const EdgeInsets.only(top: 4),
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.black, width: 1.5),
                    ),
                    child: Text(
                      '⚠ ${item.specialNotes!.trim()}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
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

class _CustomerItemRow extends StatelessWidget {
  const _CustomerItemRow({required this.item});

  final OrderLineItem item;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 28,
            child: Text(
              '${item.quantity}x',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.name),
                ...item.selectedOptions.map(
                  (o) => Text(
                    '+ ${o.group}: ${o.name}',
                    style: const TextStyle(fontSize: 9, color: Colors.black54),
                  ),
                ),
                if (item.specialNotes?.trim().isNotEmpty ?? false)
                  Text(
                    'ملاحظة: ${item.specialNotes!.trim()}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 10,
                    ),
                  ),
              ],
            ),
          ),
          Text(item.lineTotal.toStringAsFixed(3)),
        ],
      ),
    );
  }
}

class _TotalLine extends StatelessWidget {
  const _TotalLine({
    required this.label,
    required this.value,
    this.bold = false,
  });

  final String label;
  final double value;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontWeight: bold ? FontWeight.bold : FontWeight.normal,
      fontSize: bold ? 13 : null,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        children: [
          Text(label, style: style),
          const Spacer(),
          Text('${value.toStringAsFixed(3)} د.ك', style: style),
        ],
      ),
    );
  }
}
