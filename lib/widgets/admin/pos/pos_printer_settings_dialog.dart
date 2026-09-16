import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../l10n/app_strings.dart';
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
    final s = AppStrings.of(context);
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
          Expanded(
            child: Text(
              s.tr('إعدادات الطابعة الحرارية', 'Thermal Printer Settings'),
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                color: burgundy,
              ),
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
  final _qzPrinterController = TextEditingController();

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
      _qzPrinterController.text = _draft.qzPrinterName;
      _loading = false;
    });
  }

  @override
  void dispose() {
    _widthController.dispose();
    _qzPrinterController.dispose();
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
    final next = _draft.copyWith(
      customWidthMm: _effectiveWidth,
      qzPrinterName: _qzPrinterController.text.trim(),
    );
    await PosPrintSettingsService.instance.save(next);
    await RestaurantSettingsService.instance.saveInvoiceLanguage(
      invoiceLanguage: _invoiceLanguage,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          AppStrings.read(
            context,
          ).tr('تم حفظ إعدادات الطابعة', 'Printer settings saved'),
        ),
      ),
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
    final s = AppStrings.of(context);
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
          s.tr(
            'لغة الطباعة تُحفظ للمطعم. مقاس الورق والنسخ تُحفظ على هذا الجهاز.',
            'Receipt language is saved for the restaurant. Paper size and copies are saved on this device.',
          ),
          style: TextStyle(color: Colors.grey.shade700, height: 1.35),
        ),
        const SizedBox(height: 16),
        Text(
          s.tr('لغة الفاتورة', 'Invoice language'),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        SegmentedButton<InvoiceLanguage>(
          segments: [
            ButtonSegment(
              value: InvoiceLanguage.arabic,
              label: Text(s.tr('العربية', 'Arabic')),
              icon: const Icon(Icons.language),
            ),
            ButtonSegment(
              value: InvoiceLanguage.english,
              label: Text(s.tr('الإنجليزية', 'English')),
              icon: const Icon(Icons.translate),
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
              ? s.tr(
                  'فواتير الكاشير والمطبخ ستُطبع بالعربية.',
                  'Cashier and kitchen receipts will print in Arabic.',
                )
              : s.tr(
                  'فواتير الكاشير والمطبخ ستُطبع بالإنجليزية.',
                  'Cashier and kitchen receipts will print in English.',
                ),
          style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
        ),
        const SizedBox(height: 16),
        Text(
          s.tr('مقاس الورق', 'Paper size'),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        SegmentedButton<PosPrintPaperPreset>(
          segments: [
            const ButtonSegment(
              value: PosPrintPaperPreset.mm58,
              label: Text('58mm'),
            ),
            const ButtonSegment(
              value: PosPrintPaperPreset.mm80,
              label: Text('80mm'),
            ),
            ButtonSegment(
              value: PosPrintPaperPreset.custom,
              label: Text(s.tr('مخصص', 'Custom')),
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
            decoration: InputDecoration(
              labelText: s.tr('العرض بالمليمتر', 'Width in millimeters'),
              hintText: '80',
              border: const OutlineInputBorder(),
              suffixText: 'mm',
            ),
            onChanged: (_) => setState(() {}),
          ),
        ],
        const SizedBox(height: 16),
        Text(
          s.tr('عدد النسخ', 'Number of copies'),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
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
        Text(
          s.tr('حجم الخط', 'Font size'),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        SegmentedButton<PosPrintFontSize>(
          segments: [
            for (final size in PosPrintFontSize.values)
              ButtonSegment(
                value: size,
                label: Text(
                  s.tr(size.labelAr, switch (size) {
                    PosPrintFontSize.small => 'Small',
                    PosPrintFontSize.medium => 'Medium',
                    PosPrintFontSize.large => 'Large',
                  }),
                ),
              ),
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
          title: Text(
            s.tr(
              'طباعة فاتورة العميل تلقائياً بعد الدفع',
              'Automatically print customer receipt after payment',
            ),
          ),
          value: _draft.autoPrintCustomer,
          activeThumbColor: _burgundy,
          onChanged: (value) {
            setState(() => _draft = _draft.copyWith(autoPrintCustomer: value));
          },
        ),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: Text(
            s.tr(
              'طباعة تذكرة المطبخ تلقائياً',
              'Automatically print kitchen ticket',
            ),
          ),
          value: _draft.autoPrintKitchen,
          activeThumbColor: _burgundy,
          onChanged: (value) {
            setState(() => _draft = _draft.copyWith(autoPrintKitchen: value));
          },
        ),
        const SizedBox(height: 8),
        Text(
          s.tr('طابعة QZ Tray (طباعة صامتة)', 'QZ Tray (silent printing)'),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _qzPrinterController,
          decoration: InputDecoration(
            hintText: s.tr(
              'اسم الطابعة — اتركه فارغاً للافتراضي',
              'Printer name — leave blank for default',
            ),
            border: const OutlineInputBorder(),
            isDense: true,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          s.tr(
            'إن كان QZ Tray شغال على الجهاز تُطبع الفاتورة صامتة. وإلا تُستخدم طباعة المتصفح 80مم تلقائياً.',
            'When QZ Tray is running, receipts print silently. Otherwise, 80mm browser printing is used.',
          ),
          style: TextStyle(
            color: Colors.grey.shade700,
            fontSize: 12,
            height: 1.35,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '${s.tr('العرض الفعّال', 'Effective width')}: ${_effectiveWidth.toStringAsFixed(2)} mm',
          style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _printTest,
                icon: const Icon(Icons.receipt_long),
                label: Text(s.tr('تجربة طباعة', 'Test print')),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton(
                style: FilledButton.styleFrom(backgroundColor: _burgundy),
                onPressed: _save,
                child: Text(s.tr('حفظ', 'Save')),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
