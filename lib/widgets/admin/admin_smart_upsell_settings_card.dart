import 'package:flutter/material.dart';

import '../../services/restaurant_settings_service.dart';
import '../../services/super_admin_scope_service.dart';
import 'admin_menu_item_picker.dart';

class AdminSmartUpsellSettingsCard extends StatefulWidget {
  const AdminSmartUpsellSettingsCard({super.key});

  @override
  State<AdminSmartUpsellSettingsCard> createState() =>
      _AdminSmartUpsellSettingsCardState();
}

class _AdminSmartUpsellSettingsCardState
    extends State<AdminSmartUpsellSettingsCard> {
  static const burgundy = Color(0xFF6B1124);

  final _thresholdController = TextEditingController();
  final _maxPriceController = TextEditingController();
  var _enabled = true;
  var _smartRecommendationsEnabled = true;
  var _loading = true;
  var _saving = false;
  List<int> _impulseBumpItemIds = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _thresholdController.dispose();
    _maxPriceController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final settings = await RestaurantSettingsService.instance.load(
        restaurantId: SuperAdminScopeService.instance.effectiveRestaurantId,
      );
      _enabled = settings.smartUpsellEnabled;
      _smartRecommendationsEnabled = settings.smartRecommendationsEnabled;
      _impulseBumpItemIds = List<int>.from(settings.impulseBumpItemIds);
      _thresholdController.text = settings.freeDeliveryThreshold > 0
          ? settings.freeDeliveryThreshold.toStringAsFixed(3)
          : '';
      _maxPriceController.text = settings.impulseBumpMaxPrice.toStringAsFixed(3);
    } catch (_) {
      _enabled = true;
      _smartRecommendationsEnabled = true;
      _impulseBumpItemIds = const [];
      _thresholdController.clear();
      _maxPriceController.text = '2.000';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final threshold = double.tryParse(_thresholdController.text.trim()) ?? 0;
      final maxPrice = double.tryParse(_maxPriceController.text.trim()) ?? 2;

      await RestaurantSettingsService.instance.saveUpsellSettings(
        smartUpsellEnabled: _enabled,
        freeDeliveryThreshold: threshold,
        impulseBumpMaxPrice: maxPrice,
        impulseBumpItemIds: _impulseBumpItemIds,
        smartRecommendationsEnabled: _smartRecommendationsEnabled,
        restaurantId: SuperAdminScopeService.instance.effectiveRestaurantId,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم حفظ إعدادات البياع الشاطر')),
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
            ? const Center(child: CircularProgressIndicator(color: burgundy))
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'البياع الشاطر — المرحلة 2',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: burgundy,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'اقتراحات ذكية حسب السلة، سايد إيتمز مربوطة، وإضافات سريعة محسّنة في الدفع.',
                    style: TextStyle(fontSize: 13, color: Color(0xFF666666)),
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('تفعيل البياع الشاطر'),
                    value: _enabled,
                    onChanged: (value) => setState(() => _enabled = value),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('الاقتراحات الذكية حسب السلة'),
                    subtitle: const Text(
                      'يعرض «يناسب طلبك» بناءً على محتويات السلة وتاريخ الطلبات',
                    ),
                    value: _smartRecommendationsEnabled,
                    onChanged: _enabled
                        ? (value) =>
                            setState(() => _smartRecommendationsEnabled = value)
                        : null,
                  ),
                  TextField(
                    controller: _thresholdController,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'حد التوصيل المجاني (د.ك)',
                      helperText: 'اتركه فارغاً أو 0 لتعطيل شريط التقدم',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _maxPriceController,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'أقصى سعر لاقتراحات الدفع السريع (د.ك)',
                      helperText:
                          'يُستخدم للاختيار التلقائي إذا لم تُحدد أصنافاً أدناه',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 8),
                  AdminMenuItemPicker(
                    selectedIds: _impulseBumpItemIds,
                    onChanged: (ids) =>
                        setState(() => _impulseBumpItemIds = ids),
                    label: 'أصناف الإضافات السريعة (Impulse Bumps)',
                  ),
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
                        : const Text('حفظ إعدادات البياع الشاطر'),
                  ),
                ],
              ),
      ),
    );
  }
}
