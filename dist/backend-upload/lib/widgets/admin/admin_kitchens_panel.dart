import 'package:flutter/material.dart';

import '../../models/kitchen.dart';
import '../../services/api_service.dart';

class AdminKitchensPanel extends StatefulWidget {
  const AdminKitchensPanel({
    super.key,
    required this.restaurantId,
    this.canManage = true,
    this.onChanged,
  });

  final String restaurantId;
  final bool canManage;
  final VoidCallback? onChanged;

  @override
  State<AdminKitchensPanel> createState() => _AdminKitchensPanelState();
}

class _AdminKitchensPanelState extends State<AdminKitchensPanel> {
  static const _burgundy = Color(0xFF6B1124);
  var _loading = true;
  var _saving = false;
  List<Kitchen> _kitchens = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant AdminKitchensPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.restaurantId != widget.restaurantId) {
      _load();
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final kitchens = await ApiService.instance.fetchKitchens(
        restaurantId: widget.restaurantId,
        includeInactive: true,
      );
      if (!mounted) return;
      setState(() {
        _kitchens = kitchens;
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

  Future<void> _showEditor({Kitchen? existing}) async {
    final nameAr = TextEditingController(
      text: existing?.nameAr.isNotEmpty == true
          ? existing!.nameAr
          : (existing?.name ?? ''),
    );
    final nameEn = TextEditingController(text: existing?.nameEn ?? '');
    final code = TextEditingController(text: existing?.code ?? '');
    final loginName = TextEditingController(text: existing?.loginName ?? '');
    final password = TextEditingController();
    var isDefault = existing?.isDefault ?? _kitchens.isEmpty;

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text(existing == null ? 'إضافة مطبخ' : 'تعديل المطبخ'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameAr,
                  decoration: const InputDecoration(
                    labelText: 'اسم المطبخ (عربي) *',
                    border: OutlineInputBorder(),
                    hintText: 'مثال: مطبخ العارضية',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: nameEn,
                  decoration: const InputDecoration(
                    labelText: 'الاسم بالإنجليزي',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: code,
                  decoration: const InputDecoration(
                    labelText: 'الرمز',
                    border: OutlineInputBorder(),
                    hintText: 'ARD',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: loginName,
                  decoration: const InputDecoration(
                    labelText: 'اسم المستخدم لشاشة المطبخ',
                    hintText: 'مثال: مطبخ_العارضية',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.badge_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: password,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: existing?.hasPassword == true
                        ? 'كلمة المرور (اتركها فارغة للإبقاء عليها)'
                        : 'كلمة المرور *',
                    hintText: 'نفس صفحة دخول الكاشير',
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.lock_outline),
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('المطبخ الافتراضي'),
                  value: isDefault,
                  onChanged: (value) => setLocal(() => isDefault = value),
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
                if (nameAr.text.trim().isEmpty) return;
                Navigator.pop(context, true);
              },
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );

    final ar = nameAr.text.trim();
    final en = nameEn.text.trim();
    final kitchenCode = code.text.trim().toUpperCase();
    final username = loginName.text.trim();
    final pin = password.text.trim();
    nameAr.dispose();
    nameEn.dispose();
    code.dispose();
    loginName.dispose();
    password.dispose();
    if (saved != true || !mounted) return;

    if (username.isNotEmpty &&
        pin.isEmpty &&
        existing?.hasPassword != true) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('أدخل كلمة مرور لشاشة المطبخ مع اسم المستخدم'),
        ),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      await ApiService.instance.saveKitchen(
        kitchen: Kitchen(
          id: existing?.id ?? '',
          name: ar,
          nameAr: ar,
          nameEn: en,
          code: kitchenCode,
          isDefault: isDefault,
          restaurantId: widget.restaurantId,
          sortOrder: existing?.sortOrder ?? _kitchens.length + 1,
          loginName: username,
          hasPassword: existing?.hasPassword == true || pin.isNotEmpty,
        ),
        restaurantId: widget.restaurantId,
        pin: pin.isEmpty ? null : pin,
      );
      widget.onChanged?.call();
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر حفظ المطبخ: $error')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete(Kitchen kitchen) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('حذف المطبخ'),
        content: Text('هل تريد حذف ${kitchen.displayName}؟'),
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
    try {
      await ApiService.instance.deleteKitchen(kitchen.id);
      widget.onChanged?.call();
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر حذف المطبخ: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'المطابخ',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 16,
            color: _burgundy,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'اربط كل مطبخ بمناطق التوصيل. العميل يطلب، الكاشير يقبل (تتحسب في الورديّة)، ثم يظهر الطلب في شاشة ذلك المطبخ فقط.',
          style: TextStyle(height: 1.4),
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
              onPressed: _saving ? null : () => _showEditor(),
              icon: const Icon(Icons.add),
              label: const Text('إضافة مطبخ جديد'),
            ),
          ),
        ],
        const SizedBox(height: 12),
        if (_loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator(color: _burgundy)),
          )
        else if (_error != null)
          Text('تعذر تحميل المطابخ: $_error')
        else if (_kitchens.isEmpty)
          const Text('لا توجد مطابخ بعد. أضف مطبخ العارضية ومطبخ صباح السالم.')
        else
          ..._kitchens.map(
            (kitchen) => Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: _burgundy.withValues(alpha: 0.1),
                  child: const Icon(Icons.soup_kitchen_outlined, color: _burgundy),
                ),
                title: Text(kitchen.displayName),
                subtitle: Text(
                  [
                    if (kitchen.code.isNotEmpty) kitchen.code,
                    if (kitchen.isDefault) 'افتراضي',
                    if (kitchen.loginName.isNotEmpty)
                      'دخول: ${kitchen.loginName}',
                    if (kitchen.loginName.isNotEmpty && !kitchen.hasPassword)
                      'بدون كلمة مرور',
                  ].join(' • '),
                ),
                trailing: widget.canManage
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            onPressed: () => _showEditor(existing: kitchen),
                            icon: const Icon(Icons.edit_outlined),
                          ),
                          IconButton(
                            onPressed: () => _delete(kitchen),
                            icon: const Icon(Icons.delete_outline),
                          ),
                        ],
                      )
                    : null,
              ),
            ),
          ),
      ],
    );
  }
}
