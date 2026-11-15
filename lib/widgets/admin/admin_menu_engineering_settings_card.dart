import 'package:flutter/material.dart';

import '../../models/restaurant_settings.dart';
import '../../services/restaurant_settings_service.dart';
import '../../services/super_admin_scope_service.dart';
import '../../utils/dynamic_menu_sort.dart';
import 'admin_corner_toast.dart';
import 'admin_responsive_layout.dart';

class AdminMenuEngineeringSettingsCard extends StatefulWidget {
  const AdminMenuEngineeringSettingsCard({super.key});

  @override
  State<AdminMenuEngineeringSettingsCard> createState() =>
      _AdminMenuEngineeringSettingsCardState();
}

class _AdminMenuEngineeringSettingsCardState
    extends State<AdminMenuEngineeringSettingsCard> {
  static const burgundy = Color(0xFF6B1124);

  var _loading = true;
  var _saving = false;
  var _enabled = false;
  var _paydayStartDay = 1;

  @override
  void initState() {
    super.initState();
    _load();
    SuperAdminScopeService.instance.addListener(_onScopeChanged);
  }

  @override
  void dispose() {
    SuperAdminScopeService.instance.removeListener(_onScopeChanged);
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
        _enabled = settings.dynamicMenuSortingEnabled;
        _paydayStartDay = clampPaydayStartDay(settings.paydayStartDay);
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await RestaurantSettingsService.instance.saveDynamicMenuSettings(
        dynamicMenuSortingEnabled: _enabled,
        paydayStartDay: _paydayStartDay,
        restaurantId: SuperAdminScopeService.instance.effectiveRestaurantId,
      );
      if (!mounted) return;
      AdminCornerToast.success(context, 'تم حفظ إعدادات ترتيب المنيو');
    } catch (error) {
      if (!mounted) return;
      AdminCornerToast.error(
        context,
        error.toString().replaceFirst('Exception: ', ''),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: CircularProgressIndicator(color: burgundy),
        ),
      );
    }

    final cycle = paydayCycleInfo(paydayStartDay: _paydayStartDay);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const AdminSectionHeader(
              icon: Icons.auto_awesome,
              title: 'الترتيب الديناميكي الذكي للمنيو',
              subtitle:
                  'دورة 30 يوماً تبدأ من يوم نزول الراتب. أوقف المفتاح للرجوع للترتيب اليدوي.',
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'تفعيل الترتيب الديناميكي الذكي للمنيو',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: const Text(
                'عند التفعيل يتغيّر ترتيب المنيو للعميل والأدمن حسب المبيعات. عند الإيقاف يعمل الترتيب اليدوي من تبويب الأصناف والأقسام في إدارة المنيو.',
              ),
              value: _enabled,
              onChanged: (value) => setState(() => _enabled = value),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              value: _paydayStartDay,
              decoration: const InputDecoration(
                labelText: 'تاريخ بداية نزول الرواتب في الشهر',
                border: OutlineInputBorder(),
              ),
              items: [
                for (var day = 1; day <= 31; day++)
                  DropdownMenuItem(
                    value: day,
                    child: Text('يوم $day من كل شهر'),
                  ),
              ],
              onChanged: (value) {
                if (value == null) return;
                setState(() => _paydayStartDay = value);
              },
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF7F1EE),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _enabled
                        ? 'الدورة الحالية: اليوم ${cycle.cycleDay} من ${cycle.cycleLength} — ${cycle.phaseLabelAr}'
                        : 'الترتيب اليدوي مفعّل. المنيو الرقمي لن يعيد ترتيب الأصناف تلقائياً.',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'اليوم 1–10: نجوم BCG (ربح مرتفع + مبيعات مرتفعة) ثم الألغاز (ربح مرتفع).\n'
                    'اليوم 11–20: خيل العمل (مبيعات مرتفعة) والوجبات العائلية والكومبو.\n'
                    'اليوم 21 حتى الراتب التالي: الأصناف التوفيرية والسعر الأقل أولاً.',
                    style: TextStyle(height: 1.45, color: Color(0xFF555555)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                style: FilledButton.styleFrom(backgroundColor: burgundy),
                child: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('حفظ'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
