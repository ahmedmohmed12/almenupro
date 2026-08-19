import 'package:flutter/material.dart';

import '../../models/menu_item.dart';
import '../../services/api_service.dart';
import '../../services/menu_storage_service.dart';
import '../network_menu_image.dart';
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
  });

  final Future<void> Function() onAddItem;
  final Future<void> Function(MenuItemRecord record) onEditItem;
  final Future<void> Function(String id) onDeleteItem;
  final VoidCallback? onAutofillTalabat;
  final bool canImportTalabat;
  final bool canManageItems;
  final ValueChanged<AdminMenuPanelStatus>? onStatusChanged;

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
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadFromApi();
  }

  MenuItemRecord _toRecord(MenuItem item) {
    return MenuItemRecord(id: item.id.toString(), data: item.toMap());
  }

  Future<void> _loadFromApi({bool reset = true}) async {
    if (reset) {
      setState(() {
        _loading = true;
        _errorMessage = null;
      });
    } else {
      setState(() => _loadingMore = true);
    }

    try {
      final page = await ApiService.instance.fetchItemsPage(
        lite: true,
        limit: _pageSize,
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
          savingOrder: false,
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
    return ColoredBox(
      color: const Color(0xFFF4F6F8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildToolbar(),
          if (_errorMessage != null) _retryBanner(),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: _buildContent(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolbar() {
    return Material(
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 820;
            final title = Text(
              _apiOnline
                  ? 'قائمة الأصناف (${_apiItems.length}${_totalItems > _apiItems.length ? '/$_totalItems' : ''})'
                  : 'قائمة الأصناف الحالية',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            );

            final actions = Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.end,
              children: [
                OutlinedButton.icon(
                  onPressed: _loading ? null : () => _loadFromApi(),
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('تحديث'),
                ),
                if (widget.canImportTalabat)
                  OutlinedButton.icon(
                    onPressed: widget.onAutofillTalabat,
                    icon: const Icon(Icons.cloud_download, size: 18),
                    label: const Text('تعبئة Talabat'),
                  ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: burgundy),
                  onPressed: widget.canManageItems
                      ? () async {
                          await widget.onAddItem();
                          if (mounted) await _loadFromApi();
                        }
                      : null,
                  icon: const Icon(Icons.add, color: Colors.white, size: 18),
                  label: const Text(
                    'إضافة صنف',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ],
            );

            if (compact) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  title,
                  const SizedBox(height: 10),
                  actions,
                ],
              );
            }

            return Row(
              children: [
                Expanded(child: title),
                actions,
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
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: _buildItemList(_apiItems)),
          if (_apiItems.length < _totalItems)
            Align(
              alignment: Alignment.center,
              child: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: OutlinedButton(
                  onPressed:
                      _loadingMore ? null : () => _loadFromApi(reset: false),
                  child: _loadingMore
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(
                          'تحميل المزيد (${_apiItems.length}/$_totalItems)',
                        ),
                ),
              ),
            ),
        ],
      );
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

  Widget _buildItemList(List<MenuItem> items) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 900;
        return Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              if (wide) _buildWideHeader(),
              Expanded(
                child: ListView.separated(
                  padding: EdgeInsets.zero,
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final item = items[index];
                    return wide
                        ? _buildWideRow(item)
                        : _buildCompactRow(item);
                  },
                ),
              ),
            ],
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
                child: Text(
                  item.name,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    decoration: hidden ? TextDecoration.lineThrough : null,
                  ),
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
                    '${item.categoryName} • ${item.price.toStringAsFixed(3)} د.ك',
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
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'تعديل',
          onPressed: widget.canManageItems ? () => _editItem(item) : null,
          icon: const Icon(Icons.edit_outlined, color: Colors.blue),
        ),
        IconButton(
          tooltip: item.isAvailable ? 'إخفاء من المنيو' : 'إظهار في المنيو',
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
