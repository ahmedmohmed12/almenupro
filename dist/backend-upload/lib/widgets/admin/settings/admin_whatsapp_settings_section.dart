import 'package:flutter/material.dart';

import '../../../services/admin_auth_service.dart';
import '../../../services/restaurant_settings_service.dart';
import '../../../services/super_admin_scope_service.dart';
import '../../../utils/whatsapp_phone.dart';
import '../admin_breakpoints.dart';
import '../admin_corner_toast.dart';
import '../admin_responsive_layout.dart';

class AdminWhatsappSettingsSection extends StatefulWidget {
  const AdminWhatsappSettingsSection({super.key});

  @override
  State<AdminWhatsappSettingsSection> createState() =>
      _AdminWhatsappSettingsSectionState();
}

class _AdminWhatsappSettingsSectionState extends State<AdminWhatsappSettingsSection> {
  static const burgundy = Color(0xFF6B1124);

  final _phoneController = TextEditingController();
  var _countryCode = WhatsAppPhone.defaultCountryCode;
  var _loading = true;
  var _saving = false;
  var _configured = false;
  String? _savedDisplay;

  @override
  void initState() {
    super.initState();
    _load();
    SuperAdminScopeService.instance.addListener(_onScopeChanged);
  }

  @override
  void dispose() {
    SuperAdminScopeService.instance.removeListener(_onScopeChanged);
    _phoneController.dispose();
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
        _countryCode = settings.whatsappCountryCode;
        _phoneController.text = settings.whatsappPhone;
        _configured = settings.hasWhatsappNumber;
        _savedDisplay = _configured
            ? WhatsAppPhone.formatDisplay(
                settings.whatsappCountryCode,
                settings.whatsappPhone,
              )
            : null;
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
    if (_phoneController.text.trim().isEmpty) {
      AdminCornerToast.error(context, 'يرجى إدخال رقم الواتساب');
      return;
    }

    setState(() => _saving = true);
    try {
      await RestaurantSettingsService.instance.saveWhatsappNumber(
        countryCode: _countryCode,
        phone: _phoneController.text.trim(),
        restaurantId: SuperAdminScopeService.instance.effectiveRestaurantId,
      );
      if (!mounted) return;
      AdminCornerToast.success(context, 'تم حفظ رقم الواتساب');
      await _load();
    } catch (error) {
      if (!mounted) return;
      AdminCornerToast.error(context, 'تعذر حفظ رقم الواتساب: $error');
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildStatusCard(),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const AdminSectionHeader(
                  icon: Icons.chat,
                  title: 'تعديل رقم الواتساب',
                  subtitle:
                      'يُستخدم هذا الرقم لاستقبال طلبات العملاء عبر واتساب',
                ),
                const SizedBox(height: 16),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final stackFields =
                        constraints.maxWidth < AdminBreakpoints.compact;
                    final countryField = SizedBox(
                      width: stackFields ? double.infinity : 150,
                      child: DropdownButtonFormField<String>(
                        initialValue: _countryCode,
                        decoration: const InputDecoration(
                          labelText: 'مفتاح الدولة',
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 14,
                          ),
                        ),
                        items: WhatsAppPhone.countryCodes
                            .map(
                              (entry) => DropdownMenuItem(
                                value: entry.$1,
                                child: Text(entry.$2),
                              ),
                            )
                            .toList(),
                        onChanged: _disabled
                            ? null
                            : (value) {
                                if (value == null) return;
                                setState(() => _countryCode = value);
                              },
                      ),
                    );
                    final phoneField = TextField(
                      controller: _phoneController,
                      enabled: !_disabled,
                      keyboardType: TextInputType.phone,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        labelText: 'رقم الواتساب',
                        hintText: 'مثال: 94774950',
                        prefixIcon: Icon(Icons.phone, color: Colors.green),
                        border: OutlineInputBorder(),
                      ),
                    );

                    if (stackFields) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          countryField,
                          const SizedBox(height: 12),
                          phoneField,
                        ],
                      );
                    }

                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        countryField,
                        const SizedBox(width: 12),
                        Expanded(child: phoneField),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 8),
                Text(
                  'سيُستخدم الرقم: ${WhatsAppPhone.formatDisplay(_countryCode, _phoneController.text)}',
                  style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
                ),
                const SizedBox(height: 16),
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: burgundy,
                      minimumSize: const Size(0, 48),
                    ),
                    onPressed: (_saving || _disabled) ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
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
        ),
      ],
    );
  }

  Widget _buildStatusCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _configured ? Colors.green.shade50 : Colors.red.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _configured ? Colors.green.shade400 : Colors.red.shade300,
          width: 1.5,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            _configured ? Icons.check_circle : Icons.error_outline,
            color: _configured ? Colors.green.shade700 : Colors.red.shade700,
            size: 34,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _configured ? 'رقم الواتساب مُفعَّل' : 'لم يُعيَّن رقم واتساب بعد',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 17,
                    color: _configured
                        ? Colors.green.shade900
                        : Colors.red.shade900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _configured
                      ? 'الرقم المحفوظ حالياً:\n$_savedDisplay'
                      : 'الطلبات لن تُرسل للعملاء حتى تحفظ رقم واتساب المطعم.',
                  style: const TextStyle(fontSize: 14, height: 1.45),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
