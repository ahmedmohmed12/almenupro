import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/kuwait_governorates.dart';
import '../../models/delivery_zone.dart';
import '../../services/admin_auth_service.dart';
import '../../services/api_service.dart';
import '../../services/super_admin_scope_service.dart';
import 'admin_responsive_layout.dart';

/// Admin UI for managing per-restaurant delivery zones and fees.
class AdminDeliveryZonesPanel extends StatefulWidget {
  const AdminDeliveryZonesPanel({
    super.key,
    this.restaurantId,
    this.canManage = true,
  });

  final String? restaurantId;
  final bool canManage;

  @override
  State<AdminDeliveryZonesPanel> createState() => _AdminDeliveryZonesPanelState();
}

class _AdminDeliveryZonesPanelState extends State<AdminDeliveryZonesPanel> {
  var _loading = true;
  var _saving = false;
  List<DeliveryZone> _zones = [];
  String? _error;

  static const _burgundy = Color(0xFF6B1124);

  @override
  void initState() {
    super.initState();
    SuperAdminScopeService.instance.addListener(_onScopeChanged);
    _loadZones();
  }

  @override
  void dispose() {
    SuperAdminScopeService.instance.removeListener(_onScopeChanged);
    super.dispose();
  }

  void _onScopeChanged() {
    if (!mounted) return;
    _loadZones();
  }

  @override
  void didUpdateWidget(covariant AdminDeliveryZonesPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.restaurantId != widget.restaurantId ||
        oldWidget.canManage != widget.canManage) {
      _loadZones();
    }
  }

  String get _restaurantId =>
      widget.restaurantId ??
      SuperAdminScopeService.instance.effectiveRestaurantId;

  String get _restaurantLabel {
    if (AdminAuthService.instance.isSuperAdmin) {
      return SuperAdminScopeService.instance.selectedRestaurantName ??
          _restaurantId;
    }
    return AdminAuthService.instance.restaurantName ?? _restaurantId;
  }

  Map<String, List<DeliveryZone>> get _groupedZones {
    final grouped = <String, List<DeliveryZone>>{};
    for (final zone in _zones) {
      final key = zone.governorate.trim().isEmpty ? 'بدون محافظة' : zone.governorate;
      grouped.putIfAbsent(key, () => []).add(zone);
    }
    final keys = grouped.keys.toList()..sort();
    return {for (final key in keys) key: grouped[key]!};
  }

  Future<void> _loadZones() async {
    if (!widget.canManage) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _zones = [];
        _error = null;
      });
      return;
    }

    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final zones = await ApiService.instance.fetchDeliveryZones(
        restaurantId: _restaurantId,
        activeOnly: false,
      );
      if (!mounted) return;
      setState(() {
        _zones = zones
          ..sort((a, b) {
            final gov = a.governorate.compareTo(b.governorate);
            if (gov != 0) return gov;
            return a.areaName.compareTo(b.areaName);
          });
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  Future<void> _showZoneDialog({DeliveryZone? existing}) async {
    if (!widget.canManage) return;

    var selectedGovernorate = existing?.governorate.isNotEmpty == true
        ? existing!.governorate
        : kuwaitGovernorates.first;
    final areaController = TextEditingController(text: existing?.areaName ?? '');
    final feeController = TextEditingController(
      text: existing != null ? existing.deliveryFee.toStringAsFixed(3) : '',
    );
    final formKey = GlobalKey<FormState>();

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(existing == null ? 'إضافة منطقة توصيل' : 'تعديل منطقة التوصيل'),
        content: SizedBox(
          width: 420,
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: kuwaitGovernorates.contains(selectedGovernorate)
                      ? selectedGovernorate
                      : kuwaitGovernorates.first,
                  decoration: const InputDecoration(
                    labelText: 'المحافظة',
                    border: OutlineInputBorder(),
                  ),
                  items: kuwaitGovernorates
                      .map((gov) => DropdownMenuItem(value: gov, child: Text(gov)))
                      .toList(),
                  onChanged: (value) {
                    if (value != null) selectedGovernorate = value;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: areaController,
                  decoration: const InputDecoration(
                    labelText: 'اسم المنطقة',
                    border: OutlineInputBorder(),
                    hintText: 'مثال: السالمية',
                  ),
                  validator: (value) =>
                      value == null || value.trim().isEmpty ? 'مطلوب' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: feeController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,3}')),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'رسوم التوصيل (د.ك)',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) return 'مطلوب';
                    final parsed = double.tryParse(value.trim());
                    if (parsed == null || parsed < 0) return 'قيمة غير صالحة';
                    return null;
                  },
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _burgundy),
            onPressed: () {
              if (formKey.currentState?.validate() != true) return;
              Navigator.pop(context, true);
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    );

    if (saved != true || !mounted) {
      areaController.dispose();
      feeController.dispose();
      return;
    }

    final areaName = areaController.text.trim();
    final deliveryFee = double.parse(feeController.text.trim());
    areaController.dispose();
    feeController.dispose();

    setState(() => _saving = true);
    try {
      final zone = DeliveryZone(
        id: existing?.id ?? '',
        governorate: selectedGovernorate,
        areaName: areaName,
        deliveryFee: deliveryFee,
        restaurantId: _restaurantId,
      );

      if (existing == null) {
        await ApiService.instance.createDeliveryZone(zone);
      } else {
        await ApiService.instance.updateDeliveryZone(zone);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(existing == null ? 'تمت إضافة المنطقة' : 'تم تحديث المنطقة'),
        ),
      );
      await _loadZones();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر حفظ المنطقة: $error')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _deleteZone(DeliveryZone zone) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('حذف منطقة التوصيل'),
        content: Text(
          'هل تريد حذف "${zone.displayName}" (${zone.displayGovernorate})؟',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _saving = true);
    try {
      await ApiService.instance.deleteDeliveryZone(zone.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم حذف المنطقة')),
      );
      await _loadZones();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر حذف المنطقة: $error')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AdminResponsivePage(
      scrollable: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AdminSectionHeader(
            icon: Icons.local_shipping_outlined,
            title: 'مناطق التوصيل ورسومها',
            subtitle: widget.canManage
                ? 'إدارة مناطق ورسوم التوصيل للمطعم: $_restaurantLabel'
                : 'اختر مطعماً من القائمة أعلاه لإدارة مناطقه.',
          ),
          if (widget.canManage) ...[
            const SizedBox(height: 12),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: _burgundy,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
                onPressed: _saving ? null : () => _showZoneDialog(),
                icon: const Icon(Icons.add_location_alt_outlined),
                label: const Text('إضافة منطقة جديدة'),
              ),
            ),
          ],
          const SizedBox(height: 16),
          if (!widget.canManage)
            _messageCard(
              color: Colors.orange.shade50,
              icon: Icons.store_outlined,
              message: 'اختر مطعماً من القائمة أعلاه لإدارة مناطق التوصيل الخاصة به.',
            )
          else
            _buildZonesSection(),
        ],
      ),
    );
  }

  Widget _buildZonesSection() {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 48),
        child: Center(child: CircularProgressIndicator(color: _burgundy)),
      );
    }

    if (_error != null) {
      return _messageCard(
        icon: Icons.error_outline,
        message: 'تعذر تحميل مناطق التوصيل:\n$_error',
        action: OutlinedButton.icon(
          onPressed: _loadZones,
          icon: const Icon(Icons.refresh),
          label: const Text('إعادة المحاولة'),
        ),
      );
    }

    if (_zones.isEmpty) {
      return _messageCard(
        icon: Icons.map_outlined,
        message: 'لا توجد مناطق توصيل بعد لهذا المطعم.\nاضغط "إضافة منطقة" لبدء الإعداد.',
        action: FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: _burgundy),
          onPressed: _saving ? null : () => _showZoneDialog(),
          icon: const Icon(Icons.add),
          label: const Text('إضافة أول منطقة'),
        ),
      );
    }

    final grouped = _groupedZones;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final entry in grouped.entries) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 8, top: 4),
            child: Text(
              entry.key,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 15,
                color: _burgundy,
              ),
            ),
          ),
          for (final zone in entry.value) ...[
            _ZoneCard(
              zone: zone,
              saving: _saving,
              onEdit: () => _showZoneDialog(existing: zone),
              onDelete: () => _deleteZone(zone),
            ),
            const SizedBox(height: 10),
          ],
          const SizedBox(height: 8),
        ],
      ],
    );
  }

  Widget _messageCard({
    Color? color,
    required IconData icon,
    required String message,
    Widget? action,
  }) {
    return Card(
      color: color,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(icon, size: 48, color: Colors.grey.shade600),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            if (action != null) ...[
              const SizedBox(height: 16),
              action,
            ],
          ],
        ),
      ),
    );
  }
}

class _ZoneCard extends StatelessWidget {
  const _ZoneCard({
    required this.zone,
    required this.saving,
    required this.onEdit,
    required this.onDelete,
  });

  final DeliveryZone zone;
  final bool saving;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  static const _burgundy = Color(0xFF6B1124);

  @override
  Widget build(BuildContext context) {
    final name = zone.displayName;
    final governorate = zone.displayGovernorate;
    final fee = '${zone.deliveryFee.toStringAsFixed(3)} د.ك';

    return Material(
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  backgroundColor: _burgundy.withValues(alpha: 0.1),
                  child: const Icon(Icons.location_on_outlined, color: _burgundy),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        governorate,
                        style: TextStyle(
                          color: Colors.grey.shade700,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF4E5),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            fee,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              color: _burgundy,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: _burgundy),
                  onPressed: saving ? null : onEdit,
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('تعديل المنطقة'),
                ),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red.shade700,
                  ),
                  onPressed: saving ? null : onDelete,
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('حذف'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
