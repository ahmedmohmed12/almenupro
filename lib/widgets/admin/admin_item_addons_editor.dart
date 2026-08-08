import 'package:flutter/material.dart';

class AdminItemAddonsEditor extends StatelessWidget {
  const AdminItemAddonsEditor({
    super.key,
    required this.options,
    required this.onChanged,
  });

  final List<Map<String, dynamic>> options;
  final ValueChanged<List<Map<String, dynamic>>> onChanged;

  static const burgundy = Color(0xFF6B1124);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'الإضافات والسايد إيتْمز',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: burgundy,
                ),
              ),
            ),
            TextButton.icon(
              onPressed: () {
                final next = List<Map<String, dynamic>>.from(options);
                next.add(_emptyOption());
                onChanged(next);
              },
              icon: const Icon(Icons.add, size: 18),
              label: const Text('إضافة خيار'),
            ),
          ],
        ),
        const Text(
          'أضف مجموعات مثل «الحجم» أو «صوصات إضافية» مع السعر والحالة لكل خيار.',
          style: TextStyle(fontSize: 12, color: Color(0xFF666666)),
        ),
        const SizedBox(height: 8),
        if (options.isEmpty)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: const Text(
              'لا توجد إضافات لهذا الصنف. اضغط «إضافة خيار» لإنشاء أول مجموعة.',
              style: TextStyle(fontSize: 13),
            ),
          )
        else
          ...List.generate(options.length, (index) {
            return _OptionEditorCard(
              key: ValueKey(options[index]['id'] ?? index),
              data: options[index],
              onChanged: (updated) {
                final next = List<Map<String, dynamic>>.from(options);
                next[index] = updated;
                onChanged(next);
              },
              onDelete: () {
                final next = List<Map<String, dynamic>>.from(options)..removeAt(index);
                onChanged(next);
              },
            );
          }),
      ],
    );
  }

  static Map<String, dynamic> _emptyOption() {
    final id = 'addon_${DateTime.now().microsecondsSinceEpoch}';
    return {
      'id': id,
      'name': '',
      'group': 'إضافات',
      'price': 0.0,
      'groupRequired': false,
      'allowMultiple': false,
      'isAvailable': true,
    };
  }
}

class _OptionEditorCard extends StatefulWidget {
  const _OptionEditorCard({
    super.key,
    required this.data,
    required this.onChanged,
    required this.onDelete,
  });

  final Map<String, dynamic> data;
  final ValueChanged<Map<String, dynamic>> onChanged;
  final VoidCallback onDelete;

  @override
  State<_OptionEditorCard> createState() => _OptionEditorCardState();
}

class _OptionEditorCardState extends State<_OptionEditorCard> {
  late final TextEditingController _groupController;
  late final TextEditingController _nameController;
  late final TextEditingController _priceController;

  @override
  void initState() {
    super.initState();
    _groupController = TextEditingController(
      text: widget.data['group']?.toString() ?? 'إضافات',
    );
    _nameController = TextEditingController(
      text: widget.data['name']?.toString() ?? '',
    );
    _priceController = TextEditingController(
      text: (widget.data['price'] ?? 0).toString(),
    );
  }

  @override
  void dispose() {
    _groupController.dispose();
    _nameController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  void _emit() {
    widget.onChanged({
      ...widget.data,
      'group': _groupController.text.trim().isEmpty
          ? 'إضافات'
          : _groupController.text.trim(),
      'name': _nameController.text.trim(),
      'price': double.tryParse(_priceController.text.trim()) ?? 0,
      'groupRequired': widget.data['groupRequired'] == true,
      'allowMultiple': widget.data['allowMultiple'] == true,
      'isAvailable': widget.data['isAvailable'] != false,
    });
  }

  void _toggle(String key) {
    widget.onChanged({
      ...widget.data,
      key: !(widget.data[key] == true),
    });
  }

  @override
  Widget build(BuildContext context) {
    final groupRequired = widget.data['groupRequired'] == true;
    final allowMultiple = widget.data['allowMultiple'] == true;
    final isAvailable = widget.data['isAvailable'] != false;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'خيار / إضافة',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                IconButton(
                  tooltip: 'حذف',
                  onPressed: widget.onDelete,
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                ),
              ],
            ),
            TextField(
              controller: _groupController,
              decoration: const InputDecoration(
                labelText: 'اسم المجموعة (مثال: الحجم، صوصات)',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (_) => _emit(),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'اسم الخيار (مثال: جبن إضافي)',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (_) => _emit(),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _priceController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'السعر الإضافي (د.ك) — 0 = مجاني',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (_) => _emit(),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('مجموعة إجبارية'),
              subtitle: const Text('يجب على العميل اختيار خيار من هذه المجموعة'),
              value: groupRequired,
              onChanged: (_) {
                _toggle('groupRequired');
              },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('اختيار متعدد'),
              subtitle: const Text('يسمح للعميل باختيار أكثر من خيار في المجموعة'),
              value: allowMultiple,
              onChanged: (_) {
                _toggle('allowMultiple');
              },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('متوفر'),
              value: isAvailable,
              onChanged: (_) {
                _toggle('isAvailable');
              },
            ),
          ],
        ),
      ),
    );
  }
}
