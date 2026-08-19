import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/restaurant_settings_service.dart';
import '../../services/super_admin_scope_service.dart';
import 'admin_responsive_layout.dart';

class AdminSmartCartUpsellSettingsCard extends StatefulWidget {
  const AdminSmartCartUpsellSettingsCard({super.key});

  @override
  State<AdminSmartCartUpsellSettingsCard> createState() =>
      _AdminSmartCartUpsellSettingsCardState();
}

class _AdminSmartCartUpsellSettingsCardState
    extends State<AdminSmartCartUpsellSettingsCard> {
  static const burgundy = Color(0xFF6B1124);

  final _thresholdController = TextEditingController();
  var _enabled = true;
  var _drinks = true;
  var _sides = true;
  var _desserts = true;
  var _loading = true;
  var _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
    SuperAdminScopeService.instance.addListener(_onScopeChanged);
  }

  @override
  void dispose() {
    SuperAdminScopeService.instance.removeListener(_onScopeChanged);
    _thresholdController.dispose();
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
        _enabled = settings.smartCartUpsellEnabled;
        _drinks = settings.smartUpsellDrinksEnabled;
        _sides = settings.smartUpsellSidesEnabled;
        _desserts = settings.smartUpsellDessertsEnabled;
        _thresholdController.text =
            settings.dessertUpsellThreshold.toStringAsFixed(3);
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _thresholdController.text = '5.000';
        _loading = false;
      });
    }
  }

  Future<void> _save() async {
    final threshold = double.tryParse(
          _thresholdController.text.trim().replaceAll(',', '.'),
        ) ??
        5;
    setState(() => _saving = true);
    try {
      await RestaurantSettingsService.instance.saveStage3UpsellSettings(
        smartCartUpsellEnabled: _enabled,
        smartUpsellDrinksEnabled: _drinks,
        smartUpsellSidesEnabled: _sides,
        smartUpsellDessertsEnabled: _desserts,
        dessertUpsellThreshold: threshold < 0 ? 0 : threshold,
        restaurantId: SuperAdminScopeService.instance.effectiveRestaurantId,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم حفظ إعدادات المرحلة 3')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر الحفظ: $error')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
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
                    icon: Icons.add_shopping_cart_outlined,
                    title: 'البياع الشاطر — المرحلة 3',
                    subtitle:
                        'اقتراحات تكملة السلة بزر إضافة واحدة في الكاشير وشاشة الدفع: مشروبات، مقبلات، وحلويات.',
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'تفعيل المرحلة 3 — البياع في السلة',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: const Text(
                      'عند التفعيل تظهر اقتراحات تكملة الطلب في POS وفي خطوة السلة للعميل',
                    ),
                    value: _enabled,
                    onChanged: (value) => setState(() => _enabled = value),
                  ),
                  if (_enabled) ...[
                    const Divider(height: 24),
                    const Text(
                      'ماذا يقترح البياع؟',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: burgundy,
                      ),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('مشروبات'),
                      subtitle: const Text(
                        'إذا الطلب فيه صنف رئيسي بدون مشروب',
                      ),
                      value: _drinks,
                      onChanged: (value) => setState(() => _drinks = value),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('مقبلات / شوربة / سلطة'),
                      subtitle: const Text(
                        'إذا الطلب فيه صنف رئيسي بدون جانب',
                      ),
                      value: _sides,
                      onChanged: (value) => setState(() => _sides = value),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('حلويات'),
                      subtitle: const Text(
                        'إذا وصلت السلة لحد القيمة ولم يُضف حلى',
                      ),
                      value: _desserts,
                      onChanged: (value) => setState(() => _desserts = value),
                    ),
                    if (_desserts) ...[
                      const SizedBox(height: 8),
                      TextField(
                        controller: _thresholdController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                        ],
                        decoration: const InputDecoration(
                          labelText: 'حد اقتراح الحلويات (د.ك)',
                          helperText:
                              'يظهر اقتراح الحلى عندما يصل إجمالي السلة لهذا المبلغ أو أعلى',
                          border: OutlineInputBorder(),
                          suffixText: 'د.ك',
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: burgundy.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: burgundy.withValues(alpha: 0.15),
                        ),
                      ),
                      child: const Text(
                        'تظهر الاقتراحات بزر «إضافة» في سلة الكاشير وفي الخطوة الأولى من Checkout العميل.',
                        style: TextStyle(height: 1.4, fontSize: 13),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: burgundy),
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('حفظ إعدادات المرحلة 3'),
                  ),
                ],
              ),
      ),
    );
  }
}
