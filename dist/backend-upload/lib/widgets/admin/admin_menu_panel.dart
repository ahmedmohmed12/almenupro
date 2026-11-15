import 'package:flutter/material.dart';

import '../../models/menu_item.dart';
import '../../services/api_service.dart';
import '../../services/menu_storage_service.dart';
import '../../services/restaurant_settings_service.dart';
import '../../services/super_admin_scope_service.dart';
import '../network_menu_image.dart';
import 'admin_breakpoints.dart';
import 'admin_categories_panel.dart';
import 'admin_corner_toast.dart';
import 'admin_menu_panel_status.dart';

class AdminMenuPanel extends StatefulWidget {
  const AdminMenuPanel({
    super.key,
    required this.onAddItem,
    required this.onEditItem,
    required this.onDeleteItem,
    this.onAutofillTalabat,
    this.canImportTalabat = false,
    this.canManageItems = true,
    this.onStatusChanged,
    this.restaurantId,
  });

  final Future<void> Function() onAddItem;
  final Future<void> Function(MenuItemRecord record) onEditItem;
  final Future<void> Function(String id) onDeleteItem;
  final VoidCallback? onAutofillTalabat;
  final bool canImportTalabat;
  final bool canManageItems;
  final ValueChanged<AdminMenuPanelStatus>? onStatusChanged;
  final String? restaurantId;

  @override
  State<AdminMenuPanel> createState() => _AdminMenuPanelState();
}

class _AdminMenuPanelState extends State<AdminMenuPanel> {
  static const burgundy = Color(0xFF6B1124);
  static const _pageSize = 40;

  List<MenuItem> _apiItems = [];
  var _loading = true;
  var _loadingMore = false;
  var _apiOnline = false;
  var _togglingId = '';
  var _totalItems = 0;
  var _dynamicSort = false;
  var _savingOrder = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    SuperAdminScopeService.instance.addListener(_onScopeChanged);
    _loadFromApi();
  }

  @override
  void dispose() {
    SuperAdminScopeService.instance.removeListener(_onScopeChanged);
    super.dispose();
  }

  void _onScopeChanged() {
    if (!mounted) return;
    _loadFromApi();
  }

  String get _restaurantId =>
      widget.restaurantId ??
      SuperAdminScopeService.instance.effectiveRestaurantId;

  MenuItemRecord _toRecord(MenuItem item) {
    return MenuItemRecord(id: item.id.toString(), data: item.toMap());
  }

  Future<void> _loadFromApi({bool reset = true}) async {
    if (reset) {
      setState(() {
        if (_apiItems.isEmpty) _loading = true;
        _errorMessage = null;
      });
    } else {
      setState(() => _loadingMore = true);
    }

    try {
      final settings = await RestaurantSettingsService.instance.load(
        restaurantId: _restaurantId,
      );
      _dynamicSort = settings.dynamicMenuSortingEnabled;
      final page = await ApiService.instance.fetchItemsPage(
        restaurantId: _restaurantId,
        lite: true,
        // Manual reorder needs a full page; dynamic can stay paginated.
        limit: _dynamicSort ? _pageSize : 250,
        offset: reset ? 0 : _apiItems.length,
      );
      _apiOnline = true;
      _errorMessage = null;
      _totalItems = page.total;
      _apiItems = reset ? page.items : [..._apiItems, ...page.items];
    } catch (error) {
      _apiOnline = false;
      _errorMessage = error.toString().replaceFirst('Exception: ', '');
      if (reset && _apiItems.isEmpty) {
        _apiItems = [];
      }
    }

    if (!mounted) return;
    setState(() {
      _loading = false;
      _loadingMore = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.onStatusChanged?.call(
        AdminMenuPanelStatus(
          loading: false,
          apiOnline: _apiOnline,
          errorMessage: _apiItems.isEmpty ? _errorMessage : null,
          savingOrder: _savingOrder,
          itemCount: _apiItems.length,
        ),
      );
    });
  }

  Future<void> _editItem(MenuItem item) async {
    await widget.onEditItem(_toRecord(item));
    if (mounted) await _loadFromApi();
  }

  Future<void> _toggleAvailability(MenuItem item) async {
    if (!widget.canManageItems || _togglingId.isNotEmpty) return;
    final next = !item.isAvailable;
    setState(() {
      _togglingId = item.id.toString();
      _apiItems = [
        for (final entry in _apiItems)
          if (entry.id == item.id) entry.copyWith(isAvailable: next) else entry,
      ];
    });
    try {
      await ApiService.instance.setMenuItemAvailability(
        item.id.toString(),
        next,
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _apiItems = [
          for (final entry in _apiItems)
            if (entry.id == item.id)
              entry.copyWith(isAvailable: item.isAvailable)
            else
              entry,
        ];
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر تحديث الحالة: $error')),
      );
    } finally {
      if (mounted) setState(() => _togglingId = '');
    }
  }

  Future<void> _deleteApiItem(MenuItem item) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تأكيد الحذف'),
        content: Text('هل تريد حذف "${item.name}" من المنيو؟'),
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
    if (confirm != true) return;

    try {
      await ApiService.instance.deleteMenuItem(item.id.toString());
      if (!mounted) return;
      setState(() {
        _apiItems = _apiItems.where((entry) => entry.id != item.id).toList();
        _totalItems = _totalItems > 0 ? _totalItems - 1 : 0;
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر الحذف: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: ColoredBox(
        color: Colors.white,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Material(
              color: Color(0xFFF8F1F3),
              child: TabBar(
                labelColor: Color(0xFF6B1124),
                unselectedLabelColor: Colors.black54,
                indicatorColor: Color(0xFF6B1124),
                tabs: [
                  Tab(text: 'الأصناف'),
                  Tab(text: 'الأقسام'),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  ColoredBox(
                    color: Colors.white,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildToolbar(),
                        if (_errorMessage != null) _retryBanner(),
                        if (!_dynamicSort && widget.canManageItems)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
                            child: Text(
                              _savingOrder
                                  ? 'جاري حفظ ترتيب الأصناف...'
                                  : 'اسحب الأصناف لإعادة ترتيبها يدوياً (الترتيب الديناميكي متوقف).',
                              style: TextStyle(
                                fontSize: 12,
                                color: _savingOrder
                                    ? burgundy
                                    : Colors.black54,
                              ),
                            ),
                          ),
                        if (_dynamicSort)
                          const Padding(
                            padding: EdgeInsets.fromLTRB(12, 0, 12, 6),
                            child: Text(
                              'الترتيب الديناميكي مفعّل — ترتيب الأصناف اليدوي متوقف.',
                              style: TextStyle(
                                fontSize: 12,
                                color: Color(0xFFE65100),
                              ),
                            ),
                          ),
                        Expanded(child: _buildContent()),
                      ],
                    ),
                  ),
                  AdminCategoriesPanel(
                    restaurantId: _restaurantId,
                    canManage: widget.canManageItems,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _onUpdateFromTalabat() {
    print('Updating from Talabat...');
    widget.onAutofillTalabat?.call();
  }

  Widget _addItemButton({required bool expanded}) {
    final button = FilledButton.icon(
      style: FilledButton.styleFrom(
        backgroundColor: burgundy,
        foregroundColor: Colors.white,
        minimumSize: expanded ? const Size.fromHeight(44) : const Size(0, 40),
        padding: EdgeInsets.symmetric(
          horizontal: expanded ? 12 : 14,
          vertical: 10,
        ),
      ),
      onPressed: widget.canManageItems
          ? () async {
              await widget.onAddItem();
              if (mounted) await _loadFromApi();
            }
          : null,
      icon: const Icon(Icons.add, size: 20),
      label: const Text(
        'إضافة صنف جديد',
        style: TextStyle(fontWeight: FontWeight.w800),
      ),
    );
    return expanded ? button : Flexible(child: button);
  }

  Widget _buildToolbar() {
    return ColoredBox(
      color: const Color(0xFFF8F1F3),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final stacked = constraints.maxWidth < 720;
            final title = const Text(
              'إدارة المنيو والأصناف',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: burgundy,
              ),
            );
            final importTalabat = widget.canImportTalabat
                ? OutlinedButton.icon(
                    onPressed: widget.onAutofillTalabat,
                    icon: const Icon(Icons.cloud_download_outlined, size: 18),
                    label: const Text('جلب المنيو من طلبات'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: burgundy,
                      side: const BorderSide(color: burgundy),
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                    ),
                  )
                : null;
            final sync = widget.canImportTalabat
                ? Tooltip(
                    message: 'جلب المنيو من طلبات',
                    child: IconButton(
                      onPressed: _onUpdateFromTalabat,
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.cloud_download_outlined, color: burgundy),
                    ),
                  )
                : const SizedBox.shrink();

            if (stacked) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(child: title),
                      if (widget.canImportTalabat) sync,
                    ],
                  ),
                  if (importTalabat != null) ...[
                    const SizedBox(height: 8),
                    importTalabat,
                  ],
                  const SizedBox(height: 8),
                  _addItemButton(expanded: true),
                ],
              );
            }

            return Row(
              children: [
                Expanded(child: title),
                if (importTalabat != null) ...[
                  importTalabat,
                  const SizedBox(width: 8),
                ],
                _addItemButton(expanded: false),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _retryBanner() {
    return Material(
      color: Colors.orange.shade50,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                'تعذر تحميل بعض البيانات: $_errorMessage',
                style: TextStyle(color: Colors.orange.shade900, fontSize: 13),
              ),
            ),
            TextButton(
              onPressed: _loadFromApi,
              child: const Text('إعادة المحاولة'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    if (_loading && _apiItems.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: burgundy),
      );
    }

    if (_apiItems.isNotEmpty) {
      return _buildItemList(_apiItems);
    }

    if (_errorMessage != null) {
      return _buildErrorState(message: _errorMessage!, onRetry: _loadFromApi);
    }

    return StreamBuilder<List<MenuItemRecord>>(
      stream: MenuStorageService.instance.watchItems(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _buildErrorState(
            message: 'خطأ في التخزين المحلي: ${snapshot.error}',
            onRetry: _loadFromApi,
          );
        }
        final records = snapshot.data ?? [];
        if (records.isEmpty) {
          return _buildErrorState(
            message: 'لا توجد أصناف على السيرفر حالياً.',
            onRetry: _loadFromApi,
            showTalabatButton: widget.canImportTalabat,
          );
        }
        return _buildLocalList(records);
      },
    );
  }

  Future<void> _onReorderItems(int oldIndex, int newIndex) async {
    if (_dynamicSort || !widget.canManageItems) return;
    setState(() {
      if (newIndex > oldIndex) newIndex -= 1;
      final item = _apiItems.removeAt(oldIndex);
      _apiItems.insert(newIndex, item);
      _savingOrder = true;
    });
    try {
      await ApiService.instance.reorderMenuItems(
        restaurantId: _restaurantId,
        orderedIds: _apiItems.map((e) => e.id.toString()).toList(),
      );
      ApiService.instance.invalidateItemsCache();
      if (mounted) {
        AdminCornerToast.success(context, 'تم حفظ ترتيب الأصناف');
      }
    } catch (error) {
      ApiService.instance.invalidateItemsCache();
      await _loadFromApi();
      if (mounted) {
        AdminCornerToast.error(
          context,
          error.toString().replaceFirst('Exception: ', ''),
        );
      }
    } finally {
      if (mounted) setState(() => _savingOrder = false);
    }
  }

  Widget _buildItemList(List<MenuItem> items) {
    final canReorder =
        !_dynamicSort && widget.canManageItems && items.isNotEmpty;
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 900;
        if (!canReorder) {
          return ColoredBox(
            color: Colors.white,
            child: ListView(
              padding: EdgeInsets.zero,
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                if (wide) _buildWideHeader(),
                for (final item in items) ...[
                  wide ? _buildWideRow(item) : _buildCompactRow(item),
                  const Divider(height: 1),
                ],
                if (items.length < _totalItems)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Center(
                      child: OutlinedButton(
                        onPressed: _loadingMore
                            ? null
                            : () => _loadFromApi(reset: false),
                        child: _loadingMore
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Text(
                                'تحميل المزيد (${items.length}/$_totalItems)',
                              ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        }

        return ColoredBox(
          color: Colors.white,
          child: ReorderableListView.builder(
            buildDefaultDragHandles: false,
            itemCount: items.length + (items.length < _totalItems ? 1 : 0),
            onReorder: (oldIndex, newIndex) {
              if (oldIndex >= items.length) return;
              if (newIndex > items.length) newIndex = items.length;
              _onReorderItems(oldIndex, newIndex);
            },
            itemBuilder: (context, index) {
              if (index >= items.length) {
                return Padding(
                  key: const ValueKey('load-more'),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Center(
                    child: OutlinedButton(
                      onPressed: _loadingMore
                          ? null
                          : () => _loadFromApi(reset: false),
                      child: Text(
                        'تحميل المزيد (${items.length}/$_totalItems)',
                      ),
                    ),
                  ),
                );
              }
              final item = items[index];
              return Material(
                key: ValueKey('item-${item.id}'),
                color: Colors.white,
                child: Column(
                  children: [
                    if (index == 0 && wide) _buildWideHeader(),
                    Row(
                      children: [
                        ReorderableDragStartListener(
                          index: index,
                          child: const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 8),
                            child: Icon(Icons.drag_handle),
                          ),
                        ),
                        Expanded(
                          child: wide
                              ? _buildWideRow(item)
                              : _buildCompactRow(item),
                        ),
                      ],
                    ),
                    const Divider(height: 1),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildWideHeader() {
    const style = TextStyle(
      fontWeight: FontWeight.w700,
      color: burgundy,
      fontSize: 13,
    );
    return Container(
      width: double.infinity,
      color: const Color(0xFFF8F1F3),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: const Row(
        children: [
          SizedBox(width: 64, child: Text('الصورة', style: style)),
          Expanded(flex: 3, child: Text('الصنف', style: style)),
          Expanded(flex: 2, child: Text('القسم', style: style)),
          SizedBox(width: 110, child: Text('السعر', style: style)),
          SizedBox(width: 200, child: Text('الإجراءات', style: style)),
        ],
      ),
    );
  }

  Widget _buildWideRow(MenuItem item) {
    final hidden = !item.isAvailable;
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 180),
      opacity: hidden ? 0.55 : 1,
      child: Material(
        color: hidden ? const Color(0xFFF3F3F3) : Colors.white,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              SizedBox(
                width: 64,
                height: 56,
                child: _itemThumb(item.imageUrl),
              ),
                Expanded(
                  flex: 3,
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          item.name,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            decoration: hidden ? TextDecoration.lineThrough : null,
                          ),
                        ),
                      ),
                      if (!item.showOnWebsite)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: Chip(
                            visualDensity: VisualDensity.compact,
                            label: const Text('كاشير فقط'),
                            labelStyle: TextStyle(
                              fontSize: 10,
                              color: Colors.brown.shade800,
                              fontWeight: FontWeight.w700,
                            ),
                            backgroundColor: Colors.orange.shade50,
                            side: BorderSide(color: Colors.orange.shade200),
                            padding: EdgeInsets.zero,
                          ),
                        ),
                    ],
                  ),
                ),
              Expanded(
                flex: 2,
                child: Text(
                  item.categoryName,
                  style: const TextStyle(color: Color(0xFF555555)),
                ),
              ),
              SizedBox(
                width: 110,
                child: Text('${item.price.toStringAsFixed(3)} د.ك'),
              ),
              SizedBox(width: 200, child: _itemActions(item)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCompactRow(MenuItem item) {
    final hidden = !item.isAvailable;
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 180),
      opacity: hidden ? 0.55 : 1,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          children: [
            SizedBox(width: 56, height: 56, child: _itemThumb(item.imageUrl)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      decoration: hidden ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  Text(
                    [
                      item.categoryName,
                      '${item.price.toStringAsFixed(3)} د.ك',
                      if (!item.showOnWebsite) 'كاشير فقط',
                    ].join(' • '),
                    style: const TextStyle(fontSize: 12, color: Color(0xFF666666)),
                  ),
                ],
              ),
            ),
            _itemActions(item),
          ],
        ),
      ),
    );
  }

  Widget _itemActions(MenuItem item) {
    final busy = _togglingId == item.id.toString();
    final compact = AdminBreakpoints.isMobile(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'تعديل',
          visualDensity: VisualDensity.compact,
          constraints: compact
              ? const BoxConstraints(minWidth: 36, minHeight: 36)
              : null,
          onPressed: widget.canManageItems ? () => _editItem(item) : null,
          icon: const Icon(Icons.edit_outlined, color: Colors.blue),
        ),
        IconButton(
          tooltip: item.isAvailable ? 'إخفاء من المنيو' : 'إظهار في المنيو',
          visualDensity: VisualDensity.compact,
          constraints: compact
              ? const BoxConstraints(minWidth: 36, minHeight: 36)
              : null,
          onPressed: widget.canManageItems && !busy
              ? () => _toggleAvailability(item)
              : null,
          icon: busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(
                  item.isAvailable
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  color: item.isAvailable ? Colors.green.shade700 : Colors.grey,
                ),
        ),
        IconButton(
          tooltip: 'حذف',
          visualDensity: VisualDensity.compact,
          constraints: compact
              ? const BoxConstraints(minWidth: 36, minHeight: 36)
              : null,
          onPressed:
              widget.canManageItems ? () => _deleteApiItem(item) : null,
          icon: const Icon(Icons.delete_outline, color: Colors.red),
        ),
      ],
    );
  }

  Widget _buildLocalList(List<MenuItemRecord> records) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: ListView.separated(
        padding: EdgeInsets.zero,
        itemCount: records.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final record = records[index];
          final data = record.data;
          final imageUrl =
              (data['imageUrl'] ?? data['image_url'] ?? '').toString();
          final available = data['isAvailable'] != false;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                SizedBox(width: 56, height: 56, child: _itemThumb(imageUrl)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    data['name']?.toString() ?? '',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  tooltip: 'تعديل',
                  onPressed: () => widget.onEditItem(record),
                  icon: const Icon(Icons.edit_outlined, color: Colors.blue),
                ),
                IconButton(
                  tooltip: available ? 'إخفاء' : 'إظهار',
                  onPressed: () async {
                    await MenuStorageService.instance.updateItem(record.id, {
                      ...data,
                      'isAvailable': !available,
                    });
                  },
                  icon: Icon(
                    available
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    color: available ? Colors.green : Colors.grey,
                  ),
                ),
                IconButton(
                  tooltip: 'حذف',
                  onPressed: () => widget.onDeleteItem(record.id),
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildErrorState({
    required String message,
    required VoidCallback onRetry,
    bool showTalabatButton = false,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inventory_2_outlined, size: 48, color: Colors.grey.shade500),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: burgundy),
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, color: Colors.white),
              label: const Text(
                'إعادة المحاولة',
                style: TextStyle(color: Colors.white),
              ),
            ),
            if (showTalabatButton) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: widget.onAutofillTalabat,
                icon: const Icon(Icons.cloud_download),
                label: const Text('تعبئة منيو Talabat'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _itemThumb(String imageUrl) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: imageUrl.trim().isEmpty
          ? Container(
              color: burgundy.withValues(alpha: 0.08),
              child: const Icon(Icons.restaurant, color: burgundy),
            )
          : NetworkMenuImage(
              imageUrl: imageUrl,
              fit: BoxFit.cover,
              width: 56,
              height: 56,
              errorBuilder: (_, _, _) => const ColoredBox(
                color: Color(0xFFF4ECE9),
                child: Icon(Icons.broken_image, color: Colors.grey),
              ),
            ),
    );
  }
}
