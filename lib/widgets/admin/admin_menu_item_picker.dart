import 'package:flutter/material.dart';

import '../../models/menu_item.dart';
import '../../services/api_service.dart';
import '../../services/super_admin_scope_service.dart';

class AdminMenuItemPicker extends StatefulWidget {
  const AdminMenuItemPicker({
    super.key,
    required this.selectedIds,
    required this.onChanged,
    this.excludeIds = const {},
    this.label = 'اختر أصناف',
    this.maxSelections,
  });

  final List<int> selectedIds;
  final ValueChanged<List<int>> onChanged;
  final Set<int> excludeIds;
  final String label;
  final int? maxSelections;

  static const burgundy = Color(0xFF6B1124);

  @override
  State<AdminMenuItemPicker> createState() => _AdminMenuItemPickerState();
}

class _AdminMenuItemPickerState extends State<AdminMenuItemPicker> {
  var _loading = true;
  List<MenuItem> _items = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final restaurantId =
          SuperAdminScopeService.instance.effectiveRestaurantId;
      final items = await ApiService.instance.fetchItems(
        restaurantId: restaurantId,
      );
      if (!mounted) return;
      setState(() {
        _items = items.where((item) => item.isAvailable).toList()
          ..sort((a, b) => a.localizedName('ar').compareTo(b.localizedName('ar')));
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _items = const [];
        _loading = false;
      });
    }
  }

  void _toggle(int id) {
    final selected = List<int>.from(widget.selectedIds);
    if (selected.contains(id)) {
      selected.remove(id);
    } else {
      if (widget.maxSelections == 1) {
        selected
          ..clear()
          ..add(id);
      } else if (widget.maxSelections == null ||
          selected.length < widget.maxSelections!) {
        selected.add(id);
      }
    }
    widget.onChanged(selected);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: LinearProgressIndicator(color: AdminMenuItemPicker.burgundy),
      );
    }

    final candidates = _items
        .where((item) => !widget.excludeIds.contains(item.id))
        .toList();

    if (candidates.isEmpty) {
      return Text(
        'لا توجد أصناف متاحة للربط.',
        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          widget.label,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            color: AdminMenuItemPicker.burgundy,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: candidates.map((item) {
            final selected = widget.selectedIds.contains(item.id);
            return FilterChip(
              label: Text(
                '${item.localizedName('ar')} (${item.price.toStringAsFixed(3)} د.ك)',
                style: TextStyle(
                  fontSize: 12,
                  color: selected ? Colors.white : AdminMenuItemPicker.burgundy,
                ),
              ),
              selected: selected,
              selectedColor: AdminMenuItemPicker.burgundy,
              checkmarkColor: Colors.white,
              onSelected: (_) => _toggle(item.id),
            );
          }).toList(),
        ),
      ],
    );
  }
}

/// Single-select dropdown for linking a modifier to a menu item.
class AdminLinkedMenuItemDropdown extends StatefulWidget {
  const AdminLinkedMenuItemDropdown({
    super.key,
    required this.value,
    required this.onChanged,
    this.excludeId,
  });

  final int? value;
  final ValueChanged<int?> onChanged;
  final int? excludeId;

  @override
  State<AdminLinkedMenuItemDropdown> createState() =>
      _AdminLinkedMenuItemDropdownState();
}

class _AdminLinkedMenuItemDropdownState
    extends State<AdminLinkedMenuItemDropdown> {
  var _loading = true;
  List<MenuItem> _items = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final items = await ApiService.instance.fetchItems(
        restaurantId: SuperAdminScopeService.instance.effectiveRestaurantId,
      );
      if (!mounted) return;
      setState(() {
        _items = items.where((item) => item.isAvailable).toList();
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const LinearProgressIndicator(color: AdminMenuItemPicker.burgundy);
    }

    final candidates = _items
        .where((item) => widget.excludeId == null || item.id != widget.excludeId)
        .toList();

    return DropdownButtonFormField<int?>(
      value: widget.value,
      decoration: const InputDecoration(
        labelText: 'ربط بصنف من المنيو (اختياري)',
        helperText: 'يُقترح تلقائياً كسايد إيتم مع هذا الخيار',
        border: OutlineInputBorder(),
        isDense: true,
      ),
      items: [
        const DropdownMenuItem<int?>(
          value: null,
          child: Text('بدون ربط — خيار نصي فقط'),
        ),
        ...candidates.map(
          (item) => DropdownMenuItem<int?>(
            value: item.id,
            child: Text(
              '${item.localizedName('ar')} (${item.price.toStringAsFixed(3)} د.ك)',
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ],
      onChanged: widget.onChanged,
    );
  }
}
