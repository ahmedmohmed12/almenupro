import 'package:flutter/material.dart';

import '../../models/menu_item.dart';
import '../../services/api_service.dart';
import '../../services/menu_storage_service.dart';

class AdminMenuPanel extends StatefulWidget {
  const AdminMenuPanel({
    super.key,
    required this.onAddItem,
    required this.onEditItem,
    required this.onDeleteItem,
    required this.onAutofillTalabat,
  });

  final VoidCallback onAddItem;
  final void Function(MenuItemRecord record) onEditItem;
  final void Function(String id) onDeleteItem;
  final VoidCallback onAutofillTalabat;

  @override
  State<AdminMenuPanel> createState() => _AdminMenuPanelState();
}

class _AdminMenuPanelState extends State<AdminMenuPanel> {
  static const burgundy = Color(0xFF6B1124);
  static const gold = Color(0xFFD49A00);

  List<MenuItem> _apiItems = [];
  var _loading = true;
  var _apiOnline = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadFromApi();
  }

  Future<void> _loadFromApi() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      _apiItems = await ApiService.instance.fetchMenuItems();
      _apiOnline = true;
      _errorMessage = null;
    } catch (error) {
      _apiItems = [];
      _apiOnline = false;
      _errorMessage = error.toString().replaceFirst('Exception: ', '');
    }

    if (mounted) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildToolbar(),
          const SizedBox(height: 16),
          _buildServerStatus(),
          const SizedBox(height: 16),
          Expanded(child: _buildContent()),
        ],
      ),
    );
  }

  Widget _buildToolbar() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 720;

        if (compact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'قائمة الأصناف الحالية',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _loading ? null : _loadFromApi,
                icon: const Icon(Icons.refresh),
                label: const Text('تحديث من السيرفر'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: widget.onAutofillTalabat,
                icon: const Icon(Icons.cloud_download),
                label: const Text('تعبئة منيو Talabat'),
              ),
              const SizedBox(height: 8),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: burgundy),
                onPressed: widget.onAddItem,
                icon: const Icon(Icons.add, color: Colors.white),
                label: const Text(
                  'إضافة صنف جديد',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ],
          );
        }

        return Row(
          children: [
            const Expanded(
              child: Text(
                'قائمة الأصناف الحالية',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
            ),
            OutlinedButton.icon(
              onPressed: _loading ? null : _loadFromApi,
              icon: const Icon(Icons.refresh),
              label: const Text('تحديث من السيرفر'),
            ),
            const SizedBox(width: 10),
            OutlinedButton.icon(
              onPressed: widget.onAutofillTalabat,
              icon: const Icon(Icons.cloud_download),
              label: const Text('تعبئة Talabat'),
            ),
            const SizedBox(width: 10),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: burgundy),
              onPressed: widget.onAddItem,
              icon: const Icon(Icons.add, color: Colors.white),
              label: const Text(
                'إضافة صنف جديد',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildServerStatus() {
    final apiUrl = ApiService.baseUrl;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: _loading
            ? Colors.blue.shade50
            : _errorMessage != null
                ? Colors.red.shade50
                : _apiOnline
                    ? Colors.green.shade50
                    : Colors.orange.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: _loading
              ? Colors.blue.shade200
              : _errorMessage != null
                  ? Colors.red.shade200
                  : _apiOnline
                      ? Colors.green.shade200
                      : Colors.orange.shade200,
        ),
      ),
      child: Row(
        children: [
          Icon(
            _loading
                ? Icons.sync
                : _errorMessage != null
                    ? Icons.error_outline
                    : _apiOnline
                        ? Icons.cloud_done
                        : Icons.cloud_off,
            color: _loading
                ? Colors.blue.shade700
                : _errorMessage != null
                    ? Colors.red.shade700
                    : _apiOnline
                        ? Colors.green.shade700
                        : Colors.orange.shade800,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _loading
                  ? 'جاري تحميل الأصناف من $apiUrl/items ...'
                  : _errorMessage != null
                      ? 'تعذر تحميل الأصناف: $_errorMessage'
                      : _apiItems.isEmpty
                          ? 'متصل بالسيرفر ($apiUrl) — لا توجد أصناف حالياً'
                          : 'متصل بالسيرفر: $apiUrl/items (${_apiItems.length} صنف)',
              style: TextStyle(
                color: _loading
                    ? Colors.blue.shade900
                    : _errorMessage != null
                        ? Colors.red.shade900
                        : _apiOnline
                            ? Colors.green.shade900
                            : Colors.orange.shade900,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (_loading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: burgundy),
            SizedBox(height: 16),
            Text('جاري جلب الأصناف من السيرفر...'),
          ],
        ),
      );
    }

    if (_errorMessage != null) {
      return _buildErrorState(
        message: _errorMessage!,
        onRetry: _loadFromApi,
      );
    }

    if (_apiItems.isNotEmpty) {
      return _buildApiTable(_apiItems);
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

        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const Center(
            child: CircularProgressIndicator(color: burgundy),
          );
        }

        final records = snapshot.data ?? [];
        if (records.isEmpty) {
          return _buildErrorState(
            message: 'لا توجد أصناف على السيرفر أو في التخزين المحلي.',
            onRetry: _loadFromApi,
            showTalabatButton: true,
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'عرض ${records.length} صنف من التخزين المحلي (السيرفر فارغ)',
                style: TextStyle(color: Colors.orange.shade900, fontSize: 13),
              ),
            ),
            Expanded(child: _buildLocalList(records)),
          ],
        );
      },
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
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.inventory_2_outlined,
              size: 56,
              color: Colors.grey.shade500,
            ),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 15),
            ),
            const SizedBox(height: 20),
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
              const SizedBox(height: 10),
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

  Widget _buildApiTable(List<MenuItem> items) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 800) {
          return ListView.builder(
            itemCount: items.length,
            itemBuilder: (context, index) => _apiItemCard(items[index]),
          );
        }

        return Card(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          clipBehavior: Clip.antiAlias,
          child: SingleChildScrollView(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: constraints.maxWidth - 48),
                child: DataTable(
                  headingRowColor: WidgetStateProperty.all(
                    burgundy.withValues(alpha: 0.08),
                  ),
                  columns: const [
                    DataColumn(label: Text('الصورة')),
                    DataColumn(label: Text('الاسم')),
                    DataColumn(label: Text('القسم')),
                    DataColumn(label: Text('السعر')),
                    DataColumn(label: Text('الحالة')),
                  ],
                  rows: items.map(_apiDataRow).toList(),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  DataRow _apiDataRow(MenuItem item) {
    return DataRow(
      cells: [
        DataCell(_itemThumb(item.imageUrl)),
        DataCell(Text(item.name, style: const TextStyle(fontWeight: FontWeight.w600))),
        DataCell(Text(item.categoryName)),
        DataCell(Text('${item.price.toStringAsFixed(3)} د.ك')),
        DataCell(
          Chip(
            label: Text(item.isAvailable ? 'متوفر' : 'غير متوفر'),
            backgroundColor:
                item.isAvailable ? Colors.green.shade50 : Colors.red.shade50,
            visualDensity: VisualDensity.compact,
          ),
        ),
      ],
    );
  }

  Widget _apiItemCard(MenuItem item) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: SizedBox(
          width: 56,
          height: 56,
          child: _itemThumb(item.imageUrl),
        ),
        title: Text(item.name, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text('${item.categoryName} • ${item.price.toStringAsFixed(3)} د.ك'),
        trailing: Icon(
          item.isAvailable ? Icons.check_circle : Icons.cancel,
          color: item.isAvailable ? Colors.green : Colors.red,
        ),
      ),
    );
  }

  Widget _buildLocalList(List<MenuItemRecord> records) {
    return ListView.builder(
      itemCount: records.length,
      itemBuilder: (context, index) {
        final record = records[index];
        final data = record.data;
        final imageUrl = data['imageUrl'] as String? ?? '';

        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                SizedBox(width: 72, height: 72, child: _itemThumb(imageUrl)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        data['name'] as String? ?? '',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      Text(data['description'] as String? ?? ''),
                      Text('${data['price']} د.ك'),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.edit, color: Colors.blue),
                  onPressed: () => widget.onEditItem(record),
                ),
                IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red),
                  onPressed: () => widget.onDeleteItem(record.id),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _itemThumb(String imageUrl) {
    if (imageUrl.isEmpty) {
      return Container(
        decoration: BoxDecoration(
          color: burgundy.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(Icons.restaurant, color: burgundy),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.network(
        imageUrl,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) =>
            const Icon(Icons.broken_image, color: Colors.grey),
      ),
    );
  }
}
