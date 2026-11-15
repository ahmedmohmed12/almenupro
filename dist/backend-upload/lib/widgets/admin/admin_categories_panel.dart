import 'package:flutter/material.dart';

import '../../models/menu_category.dart';
import '../../services/api_service.dart';
import '../../services/restaurant_settings_service.dart';
import '../../services/super_admin_scope_service.dart';
import 'admin_corner_toast.dart';

class AdminCategoriesPanel extends StatefulWidget {
  const AdminCategoriesPanel({
    super.key,
    this.restaurantId,
    this.canManage = true,
  });

  final String? restaurantId;
  final bool canManage;

  @override
  State<AdminCategoriesPanel> createState() => _AdminCategoriesPanelState();
}

class _AdminCategoriesPanelState extends State<AdminCategoriesPanel>
    with AutomaticKeepAliveClientMixin {
  static const burgundy = Color(0xFF6B1124);

  var _loading = true;
  var _saving = false;
  var _dynamicSort = false;
  List<MenuCategory> _categories = [];
  String? _error;

  @override
  bool get wantKeepAlive => true;

  String get _restaurantId =>
      widget.restaurantId ??
      SuperAdminScopeService.instance.effectiveRestaurantId;

  @override
  void initState() {
    super.initState();
    SuperAdminScopeService.instance.addListener(_onScope);
    _load();
  }

  @override
  void dispose() {
    SuperAdminScopeService.instance.removeListener(_onScope);
    super.dispose();
  }

  void _onScope() {
    if (mounted) _load();
  }

  Future<void> _load() async {
    if (_restaurantId.isEmpty) {
      setState(() {
        _loading = false;
        _categories = [];
        _error = 'اختر مطعماً أولاً';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final settings = await RestaurantSettingsService.instance.load(
        restaurantId: _restaurantId,
      );
      final categories = await ApiService.instance.fetchMenuCategories(
        restaurantId: _restaurantId,
      );
      if (!mounted) return;
      setState(() {
        _dynamicSort = settings.dynamicMenuSortingEnabled;
        _categories = categories;
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

  Future<void> _addOrEdit({MenuCategory? existing}) async {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final nameEnCtrl = TextEditingController(text: existing?.nameEn ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(existing == null ? 'إضافة قسم' : 'تعديل قسم'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(
                labelText: 'اسم القسم (عربي)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: nameEnCtrl,
              decoration: const InputDecoration(
                labelText: 'الاسم الإنجليزي (اختياري)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: burgundy),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('حفظ', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final name = nameCtrl.text.trim();
    if (name.isEmpty) {
      AdminCornerToast.error(context, 'اسم القسم مطلوب');
      return;
    }
    setState(() => _saving = true);
    try {
      if (existing == null) {
        await ApiService.instance.createMenuCategory(
          restaurantId: _restaurantId,
          name: name,
          nameEn: nameEnCtrl.text.trim(),
        );
      } else {
        await ApiService.instance.updateMenuCategory(
          existing.id,
          restaurantId: _restaurantId,
          name: name,
          nameEn: nameEnCtrl.text.trim(),
        );
      }
      await _load();
      if (mounted) AdminCornerToast.success(context, 'تم حفظ القسم');
    } catch (error) {
      if (mounted) {
        AdminCornerToast.error(
          context,
          error.toString().replaceFirst('Exception: ', ''),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete(MenuCategory category) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف القسم'),
        content: Text('حذف «${category.name}»؟ الأصناف المرتبطة تبقى كما هي.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('حذف', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ApiService.instance.deleteMenuCategory(category.id);
      await _load();
      if (mounted) AdminCornerToast.success(context, 'تم حذف القسم');
    } catch (error) {
      if (mounted) {
        AdminCornerToast.error(
          context,
          error.toString().replaceFirst('Exception: ', ''),
        );
      }
    }
  }

  Future<void> _onReorder(int oldIndex, int newIndex) async {
    if (_dynamicSort || !widget.canManage) return;
    setState(() {
      if (newIndex > oldIndex) newIndex -= 1;
      final item = _categories.removeAt(oldIndex);
      _categories.insert(newIndex, item);
      _saving = true;
    });
    try {
      await ApiService.instance.reorderMenuCategories(
        restaurantId: _restaurantId,
        orderedIds: _categories.map((e) => e.id).toList(),
      );
      if (mounted) AdminCornerToast.success(context, 'تم حفظ ترتيب الأقسام');
    } catch (error) {
      await _load();
      if (mounted) {
        AdminCornerToast.error(
          context,
          error.toString().replaceFirst('Exception: ', ''),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: burgundy));
    }
    if (_error != null && _categories.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: _load, child: const Text('إعادة المحاولة')),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'أقسام المنيو',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: burgundy,
                  ),
                ),
              ),
              if (_saving)
                const Padding(
                  padding: EdgeInsets.only(left: 8),
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              if (widget.canManage)
                FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: burgundy),
                  onPressed: _saving ? null : () => _addOrEdit(),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('إضافة قسم'),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            _dynamicSort
                ? 'الترتيب الديناميكي مفعّل — ترتيب الأقسام اليدوي متوقف حتى تعطيل الإعداد.'
                : 'اسحب الأقسام لإعادة ترتيبها. هذا الترتيب يظهر للعميل والأدمن عند إيقاف الترتيب الديناميكي.',
            style: TextStyle(
              color: _dynamicSort ? Colors.orange.shade800 : Colors.black54,
              fontSize: 12,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: _categories.isEmpty
              ? const Center(child: Text('لا توجد أقسام بعد — أضف قسماً أو استورد منيو طلبات'))
              : ReorderableListView.builder(
                  buildDefaultDragHandles: false,
                  itemCount: _categories.length,
                  onReorder: _onReorder,
                  itemBuilder: (context, index) {
                    final category = _categories[index];
                    return Card(
                      key: ValueKey(category.id),
                      margin: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      child: ListTile(
                        leading: widget.canManage && !_dynamicSort
                            ? ReorderableDragStartListener(
                                index: index,
                                child: const Icon(Icons.drag_handle),
                              )
                            : CircleAvatar(
                                backgroundColor: burgundy.withValues(alpha: 0.1),
                                child: Text(
                                  '${index + 1}',
                                  style: const TextStyle(
                                    color: burgundy,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                        title: Text(
                          category.name,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: category.nameEn.isEmpty
                            ? null
                            : Text(category.nameEn),
                        trailing: widget.canManage
                            ? Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    tooltip: 'تعديل',
                                    onPressed: () => _addOrEdit(existing: category),
                                    icon: const Icon(Icons.edit_outlined),
                                  ),
                                  IconButton(
                                    tooltip: 'حذف',
                                    onPressed: () => _delete(category),
                                    icon: const Icon(
                                      Icons.delete_outline,
                                      color: Colors.red,
                                    ),
                                  ),
                                ],
                              )
                            : null,
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
