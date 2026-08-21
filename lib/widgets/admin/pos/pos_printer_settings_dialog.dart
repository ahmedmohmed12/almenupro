import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../models/invoice_language.dart';
import '../../../services/pos_print_helper.dart';
import '../../../services/pos_print_settings_service.dart';
import '../../../services/restaurant_settings_service.dart';
import '../../../utils/pos_receipt_html.dart';

Future<void> showPosPrinterSettingsDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => const PosPrinterSettingsDialog(),
  );
}

class PosPrinterSettingsDialog extends StatelessWidget {
  const PosPrinterSettingsDialog({super.key});

  static const burgundy = Color(0xFF6B1124);

  @override
  Widget build(BuildContext context) {
    final maxH = MediaQuery.sizeOf(context).height * 0.88;
    final maxW = MediaQuery.sizeOf(context).width;

    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(20, 16, 12, 0),
      contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      actionsPadding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      title: Row(
        children: [
          const Icon(Icons.print_outlined, color: burgundy),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'إعدادات الطابعة الحرارية',
              style: TextStyle(fontWeight: FontWeight.w800, color: burgundy),
            ),
          ),
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
      content: SizedBox(
        width: maxW < 560 ? maxW - 40 : 520,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxH - 140),
          child: const SingleChildScrollView(
            child: PosPrinterSettingsForm(embedded: true),
          ),
        ),
      ),
    );
  }
}

class PosPrinterSettingsForm extends StatefulWidget {
  const PosPrinterSettingsForm({super.key, this.embedded = false});

  final bool embedded;

  @override
  State<PosPrinterSettingsForm> createState() => _PosPrinterSettingsFormState();
}

class _PosPrinterSettingsFormState extends State<PosPrinterSettingsForm> {
  static const _burgundy = Color(0xFF6B1124);

  var _loading = true;
  late PosPrintSettings _draft;
  var _invoiceLanguage = InvoiceLanguage.arabic;
  final _widthController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await PosPrintSettingsService.instance.initialize();
    final restaurant = await RestaurantSettingsService.instance.load();
    if (!mounted) return;
    setState(() {
      _draft = PosPrintSettingsService.instance.settings;
      _invoiceLanguage = restaurant.invoiceLanguage;
      _widthController.text = _draft.customWidthMm.toStringAsFixed(
        _draft.customWidthMm == _draft.customWidthMm.roundToDouble() ? 0 : 2,
      );
      _loading = false;
    });
  }

  @override
  void dispose() {
    _widthController.dispose();
    super.dispose();
  }

  double get _effectiveWidth {
    if (_draft.paperPreset != PosPrintPaperPreset.custom) {
      return _draft.widthMm;
    }
    return (double.tryParse(_widthController.text.trim()) ??
            _draft.customWidthMm)
        .clamp(40, 120);
  }

  Future<void> _save() async {
    final next = _draft.copyWith(customWidthMm: _effectiveWidth);
    await PosPrintSettingsService.instance.save(next);
    await RestaurantSettingsService.instance.saveInvoiceLanguage(
      invoiceLanguage: _invoiceLanguage,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم حفظ إعدادات الطابعة')),
    );
    if (widget.embedded) Navigator.pop(context);
  }

  Future<void> _printTest() async {
    final preview = _draft.copyWith(customWidthMm: _effectiveWidth);
    final order = PosPrintHelper.buildTestOrder(language: _invoiceLanguage);
    await PosPrintHelper.printOrder(
      order: order,
      kind: PosReceiptKind.customer,
      overrideSettings: preview,
      language: _invoiceLanguage,
      ignorePermission: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SizedBox(
        height: 160,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'لغة الطباعة تُحفظ للمطعم. مقاس الورق والنسخ تُحفظ على هذا الجهاز.',
          style: TextStyle(color: Colors.grey.shade700, height: 1.35),
        ),
        const SizedBox(height: 16),
        const Text('لغة الفاتورة', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        SegmentedButton<InvoiceLanguage>(
          segments: const [
            ButtonSegment(
              value: InvoiceLanguage.arabic,
              label: Text('العربية'),
              icon: Icon(Icons.language),
            ),
            ButtonSegment(
              value: InvoiceLanguage.english,
              label: Text('English'),
              icon: Icon(Icons.translate),
            ),
          ],
          selected: {_invoiceLanguage},
          onSelectionChanged: (value) {
            if (value.isEmpty) return;
            setState(() => _invoiceLanguage = value.first);
          },
        ),
        const SizedBox(height: 8),
        Text(
          _invoiceLanguage.isArabic
              ? 'فواتير الكاشير والمطبخ ستُطبع بالعربية.'
              : 'Cashier and kitchen receipts will print in English.',
          style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
        ),
        const SizedBox(height: 16),
        const Text('مقاس الورق', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        SegmentedButton<PosPrintPaperPreset>(
          segments: const [
            ButtonSegment(
              value: PosPrintPaperPreset.mm58,
              label: Text('58mm'),
            ),
            ButtonSegment(
              value: PosPrintPaperPreset.mm80,
              label: Text('80mm'),
            ),
            ButtonSegment(
              value: PosPrintPaperPreset.custom,
              label: Text('مخصص'),
            ),
          ],
          selected: {_draft.paperPreset},
          onSelectionChanged: (value) {
            if (value.isEmpty) return;
            setState(() => _draft = _draft.copyWith(paperPreset: value.first));
          },
        ),
        if (_draft.paperPreset == PosPrintPaperPreset.custom) ...[
          const SizedBox(height: 12),
          TextField(
            controller: _widthController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
            ],
            decoration: const InputDecoration(
              labelText: 'العرض بالمليمتر',
              hintText: '80',
              border: OutlineInputBorder(),
              suffixText: 'mm',
            ),
            onChanged: (_) => setState(() {}),
          ),
        ],
        const SizedBox(height: 16),
        const Text('عدد النسخ', style: TextStyle(fontWeight: FontWeight.w700)),
        Row(
          children: [
            Expanded(
              child: Slider(
                value: _draft.copies.toDouble(),
                min: 1,
                max: 5,
                divisions: 4,
                label: '${_draft.copies}',
                activeColor: _burgundy,
                onChanged: (value) {
                  setState(
                    () => _draft = _draft.copyWith(copies: value.round()),
                  );
                },
              ),
            ),
            SizedBox(
              width: 36,
              child: Text(
                '${_draft.copies}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        const Text('حجم الخط', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        SegmentedButton<PosPrintFontSize>(
          segments: [
            for (final size in PosPrintFontSize.values)
              ButtonSegment(value: size, label: Text(size.labelAr)),
          ],
          selected: {_draft.fontSize},
          onSelectionChanged: (value) {
            if (value.isEmpty) return;
            setState(() => _draft = _draft.copyWith(fontSize: value.first));
          },
        ),
        const SizedBox(height: 12),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: const Text('طباعة فاتورة العميل تلقائياً بعد الدفع'),
          value: _draft.autoPrintCustomer,
          activeThumbColor: _burgundy,
          onChanged: (value) {
            setState(
              () => _draft = _draft.copyWith(autoPrintCustomer: value),
            );
          },
        ),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: const Text('طباعة تذكرة المطبخ تلقائياً'),
          value: _draft.autoPrintKitchen,
          activeThumbColor: _burgundy,
          onChanged: (value) {
            setState(
              () => _draft = _draft.copyWith(autoPrintKitchen: value),
            );
          },
        ),
        const SizedBox(height: 8),
        Text(
          'العرض الفعّال: ${_effectiveWidth.toStringAsFixed(2)} mm',
          style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _printTest,
                icon: const Icon(Icons.receipt_long),
                label: const Text('تجربة طباعة'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton(
                style: FilledButton.styleFrom(backgroundColor: _burgundy),
                onPressed: _save,
                child: const Text('حفظ'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
