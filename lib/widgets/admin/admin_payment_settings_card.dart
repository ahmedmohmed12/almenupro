import 'package:flutter/material.dart';

import '../../models/payment_method_config.dart';
import '../../services/restaurant_settings_service.dart';
import '../../services/super_admin_scope_service.dart';
import 'admin_corner_toast.dart';
import 'admin_responsive_layout.dart';

class AdminPaymentSettingsCard extends StatefulWidget {
  const AdminPaymentSettingsCard({super.key});

  @override
  State<AdminPaymentSettingsCard> createState() =>
      _AdminPaymentSettingsCardState();
}

class _AdminPaymentSettingsCardState extends State<AdminPaymentSettingsCard> {
  static const burgundy = Color(0xFF6B1124);

  var _loading = true;
  var _saving = false;
  List<PaymentMethodConfig> _methods = PaymentMethodConfig.defaults();

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
        _methods = settings.configuredPaymentMethods;
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
      await RestaurantSettingsService.instance.savePaymentMethods(
        paymentMethods: _methods,
        restaurantId: SuperAdminScopeService.instance.effectiveRestaurantId,
      );
      if (!mounted) return;
      AdminCornerToast.success(context, 'تم حفظ طرق الدفع');
    } catch (_) {
      if (!mounted) return;
      AdminCornerToast.error(context, 'تعذر حفظ طرق الدفع');
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
                    icon: Icons.payment,
                    title: 'طرق الدفع',
                    subtitle:
                        'فعّل طرق الدفع المتاحة للعملاء في صفحة إتمام الطلب',
                  ),
                  const SizedBox(height: 12),
                  ..._methods.map((method) {
                    return SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(method.nameAr),
                      subtitle: Text(method.nameEn),
                      value: method.enabled,
                      activeThumbColor: burgundy,
                      onChanged: (enabled) {
                        setState(() {
                          final index = _methods.indexWhere((m) => m.id == method.id);
                          if (index == -1) return;
                          _methods[index] = method.copyWith(enabled: enabled);
                        });
                      },
                    );
                  }),
                  const SizedBox(height: 12),
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
                      label: const Text('حفظ طرق الدفع'),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
