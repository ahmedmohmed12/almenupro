import 'package:flutter/material.dart';

import '../../../services/admin_auth_service.dart';
import '../../../services/restaurant_settings_service.dart';
import '../../../services/super_admin_scope_service.dart';
import '../admin_corner_toast.dart';
import '../admin_responsive_layout.dart';

class AdminEmailNotificationsCard extends StatefulWidget {
  const AdminEmailNotificationsCard({super.key});

  @override
  State<AdminEmailNotificationsCard> createState() =>
      _AdminEmailNotificationsCardState();
}

class _AdminEmailNotificationsCardState extends State<AdminEmailNotificationsCard> {
  static const burgundy = Color(0xFF6B1124);

  final _emailController = TextEditingController();
  final _orderAlertsController = TextEditingController(
    text: 'طلب جديد #{orderNumber} — {restaurantName}',
  );

  var _loading = true;
  var _saving = false;
  var _notifyOnNewOrder = true;
  var _notifyOnShiftClose = false;

  @override
  void initState() {
    super.initState();
    _load();
    SuperAdminScopeService.instance.addListener(_onScopeChanged);
  }

  @override
  void dispose() {
    SuperAdminScopeService.instance.removeListener(_onScopeChanged);
    _emailController.dispose();
    _orderAlertsController.dispose();
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
        _emailController.text = settings.notificationEmail;
        _notifyOnNewOrder = settings.notifyOnNewOrderEmail;
        _notifyOnShiftClose = settings.notifyOnShiftCloseEmail;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool get _disabled =>
      AdminAuthService.instance.isSuperAdmin &&
      !SuperAdminScopeService.instance.hasSelection;

  Future<void> _save() async {
    final email = _emailController.text.trim();
    if (email.isNotEmpty && !email.contains('@')) {
      AdminCornerToast.error(context, 'أدخل بريداً إلكترونياً صالحاً');
      return;
    }

    setState(() => _saving = true);
    try {
      await RestaurantSettingsService.instance.saveEmailNotifications(
        notificationEmail: email,
        notifyOnNewOrderEmail: _notifyOnNewOrder,
        notifyOnShiftCloseEmail: _notifyOnShiftClose,
        restaurantId: SuperAdminScopeService.instance.effectiveRestaurantId,
      );
      if (!mounted) return;
      AdminCornerToast.success(context, 'تم حفظ إعدادات الإيميل');
    } catch (_) {
      if (!mounted) return;
      AdminCornerToast.error(context, 'تعذر حفظ إعدادات الإيميل');
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
                    icon: Icons.mail_outline,
                    title: 'إشعارات الإيميل',
                    subtitle:
                        'استقبل تنبيهات الطلبات وإغلاق الورديات على بريدك الإلكتروني',
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _emailController,
                    enabled: !_disabled,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'البريد الإلكتروني للإشعارات',
                      hintText: 'manager@restaurant.com',
                      prefixIcon: Icon(Icons.alternate_email),
                      border: OutlineInputBorder(),
                      helperText: 'اتركه فارغاً لتعطيل إشعارات الإيميل',
                    ),
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('إشعار عند طلب جديد'),
                    subtitle: const Text('إرسال بريد عند وصول طلب جديد'),
                    value: _notifyOnNewOrder,
                    onChanged: _disabled
                        ? null
                        : (value) => setState(() => _notifyOnNewOrder = value),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('إشعار عند إغلاق الوردية'),
                    subtitle: const Text('ملخص مالي عند إغلاق وردية POS'),
                    value: _notifyOnShiftClose,
                    onChanged: _disabled
                        ? null
                        : (value) => setState(() => _notifyOnShiftClose = value),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _orderAlertsController,
                    enabled: false,
                    minLines: 2,
                    maxLines: 3,
                    decoration: InputDecoration(
                      labelText: 'قالب رسالة الطلب (قريباً)',
                      alignLabelWithHint: true,
                      border: const OutlineInputBorder(),
                      filled: true,
                      fillColor: Colors.grey.shade50,
                      helperText: 'قوالب واتساب/إيميل قابلة للتخصيص — قيد التطوير',
                    ),
                  ),
                  const SizedBox(height: 16),
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: FilledButton.icon(
                      onPressed: (_saving || _disabled) ? null : _save,
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
                      label: const Text('حفظ التغييرات'),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
