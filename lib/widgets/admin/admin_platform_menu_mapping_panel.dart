import 'package:flutter/material.dart';

import '../../models/menu_item.dart';
import '../../models/platform_item_mapping.dart';
import '../../services/api_service.dart';
import '../../services/super_admin_scope_service.dart';
import 'admin_responsive_layout.dart';

class AdminPlatformMenuMappingPanel extends StatefulWidget {
  const AdminPlatformMenuMappingPanel({
    super.key,
    this.restaurantId,
    this.canManage = true,
  });

  final String? restaurantId;
  final bool canManage;

  @override
  State<AdminPlatformMenuMappingPanel> createState() =>
      _AdminPlatformMenuMappingPanelState();
}

class _AdminPlatformMenuMappingPanelState
    extends State<AdminPlatformMenuMappingPanel> {
  static const _platforms = ['talabat', 'jahez', 'keeta'];
  String _platform = 'talabat';
  bool _loading = true;
  String? _error;
  List<MenuItem> _menuItems = const [];
  List<PlatformItemMapping> _mappings = const [];
  List<UnmappedPlatformItem> _unmapped = const [];
  final Map<String, int> _selectedItems = {};
  final Map<String, String> _selectedOptions = {};
  final Set<String> _saving = {};

  String get _restaurantId =>
      widget.restaurantId ??
      SuperAdminScopeService.instance.effectiveRestaurantId;

  @override
  void initState() {
    super.initState();
    SuperAdminScopeService.instance.addListener(_scopeChanged);
    _load();
  }

  @override
  void dispose() {
    SuperAdminScopeService.instance.removeListener(_scopeChanged);
    super.dispose();
  }

  void _scopeChanged() {
    if (mounted) _load();
  }

  @override
  void didUpdateWidget(covariant AdminPlatformMenuMappingPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.restaurantId != widget.restaurantId ||
        oldWidget.canManage != widget.canManage) {
      _load();
    }
  }

  Future<void> _load() async {
    if (!widget.canManage || _restaurantId.isEmpty) {
      setState(() {
        _loading = false;
        _error = null;
        _menuItems = const [];
        _mappings = const [];
        _unmapped = const [];
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        ApiService.instance.fetchItemsPage(
          restaurantId: _restaurantId,
          lite: true,
          limit: 1000,
        ),
        ApiService.instance.fetchPlatformItemMappings(
          restaurantId: _restaurantId,
          platform: _platform,
        ),
        ApiService.instance.fetchUnmappedPlatformItems(
          restaurantId: _restaurantId,
          platform: _platform,
        ),
      ]);
      if (!mounted) return;
      final page = results[0] as ({List<MenuItem> items, int total});
      setState(() {
        _menuItems = page.items;
        _mappings = results[1] as List<PlatformItemMapping>;
        _unmapped = results[2] as List<UnmappedPlatformItem>;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _map(UnmappedPlatformItem external) async {
    final posItemId = _selectedItems[external.id];
    if (posItemId == null || _saving.contains(external.id)) return;
    final posItem = _menuItems.where((item) => item.id == posItemId).first;
    final posOptionId = external.entityType == 'item'
        ? ''
        : (_selectedOptions[external.id] ??
              (posItem.options.length == 1 ? posItem.options.first.id : ''));
    if (external.entityType != 'item' && posOptionId.isEmpty) return;
    var parentMappingId = '';
    if (external.parentPlatformItemId.isNotEmpty) {
      for (final mapping in _mappings) {
        if (mapping.platformItemId == external.parentPlatformItemId) {
          parentMappingId = mapping.id;
          break;
        }
      }
    }
    setState(() => _saving.add(external.id));
    try {
      await ApiService.instance.savePlatformItemMapping(
        PlatformItemMapping(
          id: '',
          posItemId: posItemId.toString(),
          platformName: external.platformName,
          platformItemId: external.platformItemId,
          platformItemName: external.platformItemName,
          sku: external.sku,
          parentMappingId: parentMappingId,
          posOptionId: posOptionId,
          entityType: external.entityType,
        ),
        restaurantId: _restaurantId,
        unmappedId: external.id,
      );
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('تعذر حفظ الربط: $error')));
    } finally {
      if (mounted) setState(() => _saving.remove(external.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.canManage) {
      return const Center(
        child: Text('اختر مطعمًا أولًا لإدارة ربط أصناف المنصات'),
      );
    }
    return AdminResponsivePage(
      scrollable: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AdminSectionHeader(
            icon: Icons.hub_outlined,
            title: 'ربط أصناف المنصات',
            subtitle:
                'اربط أصناف Talabat وJahez وKeeta بأصناف AlMenuPro لتوحيد تقارير المبيعات.',
            actions: [
              IconButton(
                tooltip: 'تحديث',
                onPressed: _loading ? null : _load,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            children: _platforms
                .map(
                  (platform) => ChoiceChip(
                    label: Text(platform.toUpperCase()),
                    selected: _platform == platform,
                    onSelected: (_) {
                      setState(() => _platform = platform);
                      _load();
                    },
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 16),
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else if (_error != null)
            Card(
              color: Colors.red.shade50,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  _error!,
                  style: TextStyle(color: Colors.red.shade800),
                ),
              ),
            )
          else ...[
            Text(
              'أصناف تحتاج مراجعة (${_unmapped.length})',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            if (_unmapped.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: Text('كل الأصناف المكتشفة مربوطة حاليًا.'),
                ),
              )
            else
              ..._unmapped.map(_unmappedCard),
            const SizedBox(height: 20),
            Text(
              'الروابط المحفوظة (${_mappings.length})',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Card(
              child: Column(
                children: _mappings
                    .map(
                      (mapping) => ListTile(
                        leading: const Icon(
                          Icons.link,
                          color: Color(0xFF6B1124),
                        ),
                        title: Text(
                          mapping.platformItemName.isEmpty
                              ? mapping.platformItemId
                              : mapping.platformItemName,
                        ),
                        subtitle: Text(
                          '${mapping.entityType} → POS #${mapping.posItemId}'
                          '${mapping.posOptionId.isEmpty ? '' : ' / ${mapping.posOptionId}'}',
                        ),
                        trailing: IconButton(
                          tooltip: 'حذف الربط',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () async {
                            await ApiService.instance.deletePlatformItemMapping(
                              mapping.id,
                              restaurantId: _restaurantId,
                            );
                            await _load();
                          },
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _unmappedCard(UnmappedPlatformItem external) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    external.platformItemName.isEmpty
                        ? external.platformItemId
                        : external.platformItemName,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                Chip(label: Text(external.entityType)),
                const SizedBox(width: 8),
                Text('×${external.occurrences}'),
              ],
            ),
            if (external.platformItemId.isNotEmpty || external.sku.isNotEmpty)
              Text(
                [
                  if (external.platformItemId.isNotEmpty)
                    'ID: ${external.platformItemId}',
                  if (external.sku.isNotEmpty) 'SKU: ${external.sku}',
                ].join('  •  '),
                style: const TextStyle(color: Colors.black54),
              ),
            const SizedBox(height: 10),
            DropdownButtonFormField<int>(
              initialValue: _selectedItems[external.id],
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'اختر صنف AlMenuPro',
                border: OutlineInputBorder(),
              ),
              items: _menuItems
                  .map(
                    (item) => DropdownMenuItem(
                      value: item.id,
                      child: Text(
                        item.nameAr.isNotEmpty ? item.nameAr : item.name,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (value) => setState(() {
                _selectedItems[external.id] = value!;
                _selectedOptions.remove(external.id);
              }),
            ),
            if (external.entityType != 'item' &&
                _selectedItems[external.id] != null) ...[
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: _selectedOptions[external.id],
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'اختر الإضافة أو الحجم',
                  border: OutlineInputBorder(),
                ),
                items: _menuItems
                    .firstWhere(
                      (item) => item.id == _selectedItems[external.id],
                    )
                    .options
                    .map(
                      (option) => DropdownMenuItem(
                        value: option.id,
                        child: Text(
                          option.nameAr.isNotEmpty
                              ? option.nameAr
                              : option.name,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (value) =>
                    setState(() => _selectedOptions[external.id] = value!),
              ),
            ],
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed:
                  _selectedItems[external.id] == null ||
                      (external.entityType != 'item' &&
                          (_selectedOptions[external.id]?.isEmpty ?? true) &&
                          _menuItems
                                  .firstWhere(
                                    (item) =>
                                        item.id == _selectedItems[external.id],
                                  )
                                  .options
                                  .length !=
                              1) ||
                      _saving.contains(external.id)
                  ? null
                  : () => _map(external),
              icon: _saving.contains(external.id)
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.link),
              label: const Text('ربط بنقرة واحدة'),
            ),
          ],
        ),
      ),
    );
  }
}
