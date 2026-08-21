import 'package:flutter/material.dart';

import '../../services/restaurant_settings_service.dart';
import '../../services/super_admin_scope_service.dart';
import '../../utils/image_url.dart';
import '../network_menu_image.dart';
import 'admin_corner_toast.dart';
import 'admin_responsive_layout.dart';

class AdminStoreProfileCard extends StatefulWidget {
  const AdminStoreProfileCard({super.key});

  @override
  State<AdminStoreProfileCard> createState() => _AdminStoreProfileCardState();
}

class _AdminStoreProfileCardState extends State<AdminStoreProfileCard> {
  static const burgundy = Color(0xFF6B1124);

  final _logoUrlController = TextEditingController();
  final _descriptionController = TextEditingController();

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
    _logoUrlController.dispose();
    _descriptionController.dispose();
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
        _logoUrlController.text = settings.logoUrl;
        _descriptionController.text = settings.restaurantDescription;
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
      await RestaurantSettingsService.instance.saveStoreProfile(
        logoUrl: _logoUrlController.text,
        restaurantDescription: _descriptionController.text,
        restaurantId: SuperAdminScopeService.instance.effectiveRestaurantId,
      );
      if (!mounted) return;
      AdminCornerToast.success(context, 'تم حفظ بيانات المحل');
    } catch (_) {
      if (!mounted) return;
      AdminCornerToast.error(context, 'تعذر حفظ بيانات المحل');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String? _previewImageUrl() {
    final raw = _logoUrlController.text.trim();
    if (raw.isEmpty) return null;
    final resolved = resolveImageUrl(raw);
    return resolved.isEmpty ? null : resolved;
  }

  @override
  Widget build(BuildContext context) {
    final scope = SuperAdminScopeService.instance;
    final disabled = scope.isSuperAdmin && !scope.hasSelection;
    final previewUrl = _previewImageUrl();

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
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
                    icon: Icons.storefront,
                    title: 'بيانات المحل للمعاينة',
                    subtitle:
                        'يُستخدم الشعار والوصف في معاينة رابط المنيو على واتساب ووسائل التواصل',
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _logoUrlController,
                    enabled: !disabled,
                    onChanged: (_) => setState(() {}),
                    minLines: 1,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'رابط شعار المطعم',
                      hintText: 'https://example.com/logo.png',
                      isDense: true,
                      prefixIcon: Icon(Icons.image_outlined, color: burgundy),
                      border: OutlineInputBorder(),
                      helperText:
                          'روابط إنستجرام/فيسبوك وطلبات تُحمَّل عبر السيرفر لتظهر في المعاينة والمشاركة',
                    ),
                  ),
                  if (previewUrl != null) ...[
                    const SizedBox(height: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        color: Colors.grey.shade100,
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 72,
                              height: 72,
                              child: NetworkMenuImage(
                                imageUrl: previewUrl,
                                width: 72,
                                height: 72,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Container(
                                  width: 72,
                                  height: 72,
                                  color: Colors.grey.shade200,
                                  child: const Icon(Icons.broken_image_outlined),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'معاينة الشعار',
                                style: TextStyle(
                                  color: Colors.grey.shade700,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  TextField(
                    controller: _descriptionController,
                    enabled: !disabled,
                    minLines: 3,
                    maxLines: 5,
                    decoration: const InputDecoration(
                      labelText: 'وصف المطعم',
                      hintText: 'مثال: أفضل كوكيز في الكويت — طازج يومياً مع توصيل سريع',
                      alignLabelWithHint: true,
                      prefixIcon: Icon(Icons.description_outlined, color: burgundy),
                      border: OutlineInputBorder(),
                      helperText:
                          'يظهر هذا الوصف في og:description عند مشاركة رابط المنيو',
                    ),
                  ),
                  const SizedBox(height: 16),
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: FilledButton.icon(
                      onPressed: (_saving || disabled) ? null : _save,
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
                      label: const Text('حفظ بيانات المحل'),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
