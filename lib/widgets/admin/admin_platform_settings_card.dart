import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/sales_platform_config.dart';
import '../../services/restaurant_settings_service.dart';
import '../../services/super_admin_scope_service.dart';
import 'admin_corner_toast.dart';

class AdminPlatformSettingsCard extends StatefulWidget {
  const AdminPlatformSettingsCard({super.key});

  @override
  State<AdminPlatformSettingsCard> createState() =>
      _AdminPlatformSettingsCardState();
}

class _AdminPlatformSettingsCardState extends State<AdminPlatformSettingsCard> {
  static const burgundy = Color(0xFF6B1124);

  var _loading = true;
  var _saving = false;
  List<SalesPlatformConfig> _platforms = SalesPlatformConfig.defaults();

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
        _platforms = settings.resolvedSalesPlatforms;
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
      await RestaurantSettingsService.instance.saveSalesPlatforms(
        salesPlatforms: _platforms,
        restaurantId: SuperAdminScopeService.instance.effectiveRestaurantId,
      );
      if (!mounted) return;
      AdminCornerToast.success(context, 'تم حفظ إعدادات المنصات');
    } catch (_) {
      if (!mounted) return;
      AdminCornerToast.error(context, 'تعذر حفظ إعدادات المنصات');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _updatePlatform(int index, SalesPlatformConfig next) {
    setState(() => _platforms[index] = next);
  }

  void _removePlatform(int index) {
    final platform = _platforms[index];
    if (platform.isBuiltIn) return;
    setState(() => _platforms.removeAt(index));
  }

  Future<void> _addPlatform() async {
    final result = await showDialog<_PlatformFormResult>(
      context: context,
      builder: (context) => const _PlatformEditorDialog(title: 'إضافة منصة'),
    );
    if (result == null) return;
    if (_platforms.any((p) => p.id == result.id)) {
      if (!mounted) return;
      AdminCornerToast.error(context, 'معرّف المنصة مستخدم مسبقاً');
      return;
    }
    setState(() {
      _platforms.add(
        SalesPlatformConfig(
          id: result.id,
          name: result.name,
          commissionPercent: result.commissionPercent,
          colorArgb: result.colorArgb,
        ),
      );
    });
  }

  Future<void> _editPlatform(int index) async {
    final current = _platforms[index];
    final result = await showDialog<_PlatformFormResult>(
      context: context,
      builder: (context) => _PlatformEditorDialog(
        title: 'تعديل ${current.name}',
        initial: current,
        lockId: current.isBuiltIn,
      ),
    );
    if (result == null) return;
    _updatePlatform(
      index,
      current.copyWith(
        id: result.id,
        name: result.name,
        commissionPercent: result.commissionPercent,
        colorArgb: result.colorArgb,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: burgundy.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.hub_outlined, color: burgundy),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'إعدادات المنصات (Platform Settings)',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: burgundy,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'إدارة منصات التوصيل ونسب العمولة لحساب صافي الدخل.',
                        style: TextStyle(fontSize: 13, color: Color(0xFF666666)),
                      ),
                    ],
                  ),
                ),
                FilledButton.icon(
                  onPressed: _loading || _saving ? null : _addPlatform,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('منصة جديدة'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_loading)
              const Center(child: CircularProgressIndicator(color: burgundy))
            else
              ...List.generate(_platforms.length, (index) {
                final platform = _platforms[index];
                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: platform.color.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: platform.color.withValues(alpha: 0.25)),
                  ),
                  child: Row(
                    children: [
                      SalesPlatformBadge(platform: platform),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              platform.isLocal
                                  ? 'طلبات المحل — بدون عمولة'
                                  : 'عمولة ${platform.commissionPercent.toStringAsFixed(1)}%',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF666666),
                              ),
                            ),
                            if (!platform.isLocal)
                              Text(
                                'ID: ${platform.id}',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Color(0xFF999999),
                                ),
                              ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'تعديل',
                        onPressed: () => _editPlatform(index),
                        icon: const Icon(Icons.edit_outlined),
                      ),
                      if (!platform.isBuiltIn)
                        IconButton(
                          tooltip: 'حذف',
                          onPressed: () => _removePlatform(index),
                          icon: Icon(Icons.delete_outline, color: Colors.red.shade400),
                        ),
                    ],
                  ),
                );
              }),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: burgundy),
                onPressed: _loading || _saving ? null : _save,
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
                label: const Text('حفظ إعدادات المنصات'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlatformFormResult {
  const _PlatformFormResult({
    required this.id,
    required this.name,
    required this.commissionPercent,
    required this.colorArgb,
  });

  final String id;
  final String name;
  final double commissionPercent;
  final int colorArgb;
}

class _PlatformEditorDialog extends StatefulWidget {
  const _PlatformEditorDialog({
    required this.title,
    this.initial,
    this.lockId = false,
  });

  final String title;
  final SalesPlatformConfig? initial;
  final bool lockId;

  @override
  State<_PlatformEditorDialog> createState() => _PlatformEditorDialogState();
}

class _PlatformEditorDialogState extends State<_PlatformEditorDialog> {
  late final TextEditingController _idController;
  late final TextEditingController _nameController;
  late final TextEditingController _commissionController;
  late int _colorArgb;

  static const _colorOptions = [
    0xFFFF5A00,
    0xFF00A651,
    0xFFE4002B,
    0xFF475569,
    0xFF2563EB,
    0xFF9333EA,
    0xFFD49A00,
  ];

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _idController = TextEditingController(text: initial?.id ?? '');
    _nameController = TextEditingController(text: initial?.name ?? '');
    _commissionController = TextEditingController(
      text: (initial?.commissionPercent ?? 10).toStringAsFixed(1),
    );
    _colorArgb = initial?.colorArgb ?? _colorOptions.first;
  }

  @override
  void dispose() {
    _idController.dispose();
    _nameController.dispose();
    _commissionController.dispose();
    super.dispose();
  }

  void _submit() {
    final id = _idController.text.trim().toLowerCase().replaceAll(' ', '_');
    final name = _nameController.text.trim();
    final commission = double.tryParse(_commissionController.text.trim()) ?? 0;
    if (id.isEmpty || name.isEmpty) return;
    Navigator.of(context).pop(
      _PlatformFormResult(
        id: id,
        name: name,
        commissionPercent: commission,
        colorArgb: _colorArgb,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'اسم المنصة',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _idController,
              enabled: !widget.lockId,
              decoration: const InputDecoration(
                labelText: 'المعرّف (ID)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _commissionController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d{0,2}(\.\d{0,2})?')),
              ],
              decoration: const InputDecoration(
                labelText: 'نسبة العمولة %',
                suffixText: '%',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: _colorOptions.map((color) {
                final selected = _colorArgb == color;
                return GestureDetector(
                  onTap: () => setState(() => _colorArgb = color),
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: Color(color),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: selected ? Colors.black : Colors.transparent,
                        width: 2,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('إلغاء'),
        ),
        FilledButton(onPressed: _submit, child: const Text('حفظ')),
      ],
    );
  }
}
