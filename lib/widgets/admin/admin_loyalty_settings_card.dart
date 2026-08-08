import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/loyalty_cashback.dart';
import '../../services/api_service.dart';
import '../../services/restaurant_settings_service.dart';
import '../../services/super_admin_scope_service.dart';
import 'admin_corner_toast.dart';
import 'admin_responsive_layout.dart';

class AdminLoyaltySettingsCard extends StatefulWidget {
  const AdminLoyaltySettingsCard({super.key});

  @override
  State<AdminLoyaltySettingsCard> createState() =>
      _AdminLoyaltySettingsCardState();
}

class _AdminLoyaltySettingsCardState extends State<AdminLoyaltySettingsCard> {
  static const burgundy = Color(0xFF6B1124);

  final _cashbackController = TextEditingController();
  final _minOrderController = TextEditingController();
  final _previewController = TextEditingController(text: '10');

  CashbackType _cashbackType = CashbackType.percentage;
  var _loading = true;
  var _saving = false;
  var _previewLoading = false;
  LoyaltyCashbackPreview? _preview;

  @override
  void initState() {
    super.initState();
    _load();
    SuperAdminScopeService.instance.addListener(_onScopeChanged);
  }

  @override
  void dispose() {
    SuperAdminScopeService.instance.removeListener(_onScopeChanged);
    _cashbackController.dispose();
    _minOrderController.dispose();
    _previewController.dispose();
    super.dispose();
  }

  void _onScopeChanged() => _load();

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final settings = await RestaurantSettingsService.instance.load(
        restaurantId: SuperAdminScopeService.instance.effectiveRestaurantId,
      );
      if (!mounted) return;
      setState(() {
        _cashbackType = settings.cashbackType;
        _cashbackController.text = settings.cashbackValue > 0
            ? _formatValue(settings.cashbackValue)
            : '';
        _minOrderController.text = settings.minOrderForLoyalty > 0
            ? _formatValue(settings.minOrderForLoyalty)
            : '';
        _loading = false;
      });
      await _refreshPreview();
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  String _formatValue(double value) {
    if (_cashbackType == CashbackType.percentage) {
      return value % 1 == 0 ? value.toStringAsFixed(0) : value.toStringAsFixed(1);
    }
    return value.toStringAsFixed(3);
  }

  double? _parseCashbackValue() {
    final raw = _cashbackController.text.trim().replaceAll(',', '.');
    if (raw.isEmpty) return 0;
    final parsed = double.tryParse(raw);
    if (parsed == null || parsed < 0) return null;
    if (_cashbackType == CashbackType.percentage && parsed > 100) return null;
    if (_cashbackType == CashbackType.fixedAmount && parsed > 100) return null;
    return parsed;
  }

  double? _parseMinOrder() {
    final raw = _minOrderController.text.trim().replaceAll(',', '.');
    if (raw.isEmpty) return 0;
    final parsed = double.tryParse(raw);
    if (parsed == null || parsed < 0) return null;
    return parsed;
  }

  String? _validate() {
    final cashback = _parseCashbackValue();
    if (cashback == null) {
      return _cashbackType == CashbackType.percentage
          ? 'أدخل نسبة صحيحة بين 0 و 100'
          : 'أدخل مبلغاً ثابتاً صحيحاً';
    }
    final minOrder = _parseMinOrder();
    if (minOrder == null) return 'أدخل حد أدنى صحيح للطلب';
    return null;
  }

  Future<void> _save() async {
    final error = _validate();
    if (error != null) {
      AdminCornerToast.error(context, error);
      return;
    }

    setState(() => _saving = true);
    try {
      await RestaurantSettingsService.instance.saveLoyaltySettings(
        cashbackType: _cashbackType,
        cashbackValue: _parseCashbackValue() ?? 0,
        minOrderForLoyalty: _parseMinOrder() ?? 0,
        restaurantId: SuperAdminScopeService.instance.effectiveRestaurantId,
      );
      if (!mounted) return;
      AdminCornerToast.success(context, 'تم حفظ إعدادات الولاء والكاش باك');
      await _refreshPreview();
    } catch (_) {
      if (!mounted) return;
      AdminCornerToast.error(context, 'تعذر حفظ إعدادات الولاء');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _refreshPreview() async {
    final orderTotal = double.tryParse(
      _previewController.text.trim().replaceAll(',', '.'),
    );
    if (orderTotal == null || orderTotal <= 0) {
      setState(() => _preview = null);
      return;
    }

    setState(() => _previewLoading = true);
    try {
      final preview = await ApiService.instance.calculateLoyaltyCashback(
        orderTotal: orderTotal,
        restaurantId: SuperAdminScopeService.instance.effectiveRestaurantId,
      );
      if (!mounted) return;
      setState(() {
        _preview = preview;
        _previewLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _previewLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: _loading
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(color: burgundy),
                ),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const AdminSectionHeader(
                    icon: Icons.loyalty,
                    title: 'الولاء والكاش باك',
                    subtitle:
                        'اختر نسبة مئوية أو مبلغاً ثابتاً يُضاف لمحفظة العميل عند اكتمال الطلب',
                  ),
                  const SizedBox(height: 16),
                  SegmentedButton<CashbackType>(
                    segments: const [
                      ButtonSegment(
                        value: CashbackType.percentage,
                        label: Text('نسبة مئوية (%)'),
                        icon: Icon(Icons.percent, size: 18),
                      ),
                      ButtonSegment(
                        value: CashbackType.fixedAmount,
                        label: Text('مبلغ ثابت (KWD)'),
                        icon: Icon(Icons.payments_outlined, size: 18),
                      ),
                    ],
                    selected: {_cashbackType},
                    onSelectionChanged: (selection) {
                      setState(() {
                        _cashbackType = selection.first;
                        _cashbackController.clear();
                        _preview = null;
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _cashbackController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                    ],
                    decoration: InputDecoration(
                      labelText: _cashbackType == CashbackType.percentage
                          ? 'نسبة الكاش باك'
                          : 'مبلغ الكاش باك',
                      hintText: _cashbackType == CashbackType.percentage
                          ? 'مثال: 5 أو 10'
                          : 'مثال: 0.500 أو 1.000',
                      border: const OutlineInputBorder(),
                      prefixIcon: Icon(
                        _cashbackType == CashbackType.percentage
                            ? Icons.percent
                            : Icons.currency_exchange,
                      ),
                      suffixText: _cashbackType == CashbackType.percentage
                          ? '%'
                          : 'KWD',
                    ),
                    onChanged: (_) => _refreshPreview(),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _minOrderController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                    ],
                    decoration: const InputDecoration(
                      labelText: 'الحد الأدنى للطلب (اختياري)',
                      hintText: 'مثال: 5.000 — اتركه فارغاً لتعطيل الشرط',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.shopping_cart_outlined),
                      suffixText: 'KWD',
                    ),
                    onChanged: (_) => _refreshPreview(),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: burgundy.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: burgundy.withValues(alpha: 0.15)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'معاينة الكاش باك',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: _previewController,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                  decimal: true,
                                ),
                                decoration: const InputDecoration(
                                  labelText: 'إجمالي الطلب التجريبي',
                                  border: OutlineInputBorder(),
                                  suffixText: 'KWD',
                                  isDense: true,
                                ),
                                onChanged: (_) => _refreshPreview(),
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              tooltip: 'تحديث المعاينة',
                              onPressed:
                                  _previewLoading ? null : _refreshPreview,
                              icon: _previewLoading
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.refresh),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        if (_preview != null)
                          Text(
                            _preview!.qualifies
                                ? 'العميل يستحق: ${_preview!.earnedCashback.toStringAsFixed(3)} KWD'
                                : 'لا يستحق كاش باك (${_preview!.reason ?? 'غير مؤهل'})',
                            style: TextStyle(
                              color: _preview!.qualifies
                                  ? Colors.green.shade700
                                  : Colors.orange.shade800,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: FilledButton.icon(
                      onPressed: _saving ? null : _save,
                      icon: _saving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.save),
                      label: const Text('حفظ إعدادات الولاء'),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
