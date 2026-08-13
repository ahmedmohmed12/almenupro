import 'package:flutter/material.dart';

import '../../../services/api_service.dart';
import '../../../models/menu_item.dart';

class PosMenuPage extends StatefulWidget {
  const PosMenuPage({super.key});

  @override
  State<PosMenuPage> createState() => _PosMenuPageState();
}

class _PosMenuPageState extends State<PosMenuPage> {
  var _loading = true;
  String? _error;
  List<MenuItem> _items = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await ApiService.instance.fetchMenuItems();
      if (!mounted) return;
      setState(() {
        _items = items;
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

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'إدارة المنيو والأصناف',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ),
              IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'عرض سريع للأصناف — التعديل الكامل متاح من لوحة المدير.',
            style: TextStyle(color: Color(0xFF666666), fontSize: 13),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF6B1124)))
                : _error != null
                    ? Center(child: Text(_error!, style: const TextStyle(color: Colors.red)))
                    : _items.isEmpty
                        ? const Center(child: Text('لا توجد أصناف'))
                        : ListView.separated(
                            itemCount: _items.length,
                            separatorBuilder: (_, __) => const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final item = _items[index];
                              return ListTile(
                                title: Text(item.nameAr.isNotEmpty ? item.nameAr : item.name),
                                subtitle: Text(
                                  '${item.categoryName} • ${item.price.toStringAsFixed(3)} د.ك',
                                ),
                                trailing: item.isAvailable
                                    ? const Icon(Icons.check_circle, color: Colors.green, size: 20)
                                    : const Icon(Icons.remove_circle_outline, color: Colors.grey, size: 20),
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }
}
