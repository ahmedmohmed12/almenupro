import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/menu_item.dart';
import '../../models/offer.dart';
import '../../services/admin_auth_service.dart';
import '../../services/api_service.dart';
import '../../services/super_admin_scope_service.dart';
import 'admin_responsive_layout.dart';

class AdminOffersPanel extends StatefulWidget {
  const AdminOffersPanel({
    super.key,
    this.restaurantId,
    this.canManage = true,
  });

  final String? restaurantId;
  final bool canManage;

  @override
  State<AdminOffersPanel> createState() => _AdminOffersPanelState();
}

class _AdminOffersPanelState extends State<AdminOffersPanel> {
  var _loading = true;
  var _saving = false;
  List<Offer> _offers = [];
  List<MenuItem> _menuItems = [];
  String? _error;

  static const _burgundy = Color(0xFF6B1124);

  @override
  void initState() {
    super.initState();
    SuperAdminScopeService.instance.addListener(_onScopeChanged);
    _load();
  }

  @override
  void dispose() {
    SuperAdminScopeService.instance.removeListener(_onScopeChanged);
    super.dispose();
  }

  void _onScopeChanged() {
    if (!mounted) return;
    _load();
  }

  @override
  void didUpdateWidget(covariant AdminOffersPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.restaurantId != widget.restaurantId ||
        oldWidget.canManage != widget.canManage) {
      _load();
    }
  }

  String get _restaurantId =>
      widget.restaurantId ??
      SuperAdminScopeService.instance.effectiveRestaurantId;

  String get _restaurantLabel {
    if (AdminAuthService.instance.isSuperAdmin) {
      return SuperAdminScopeService.instance.selectedRestaurantName ??
          _restaurantId;
    }
    return AdminAuthService.instance.restaurantName ?? _restaurantId;
  }

  Future<void> _load() async {
    if (!widget.canManage) {
      setState(() {
        _loading = false;
        _offers = [];
        _error = null;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final offers = await ApiService.instance.fetchAdminOffers(
        restaurantId: _restaurantId,
      );
      List<MenuItem> items = const [];
      try {
        final page = await ApiService.instance.fetchItemsPage(
          restaurantId: _restaurantId,
          lite: true,
          limit: 80,
        );
        items = page.items;
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _offers = offers;
        _menuItems = items;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _showOfferDialog({Offer? existing}) async {
    final titleController = TextEditingController(text: existing?.title ?? '');
    final descController =
        TextEditingController(text: existing?.description ?? '');
    final valueController = TextEditingController(
      text: existing == null || existing.discountValue == 0
          ? ''
          : existing.discountValue.toString(),
    );
    final originalController = TextEditingController(
      text: existing == null || existing.originalPrice == 0
          ? ''
          : existing.originalPrice.toString(),
    );
    final offerPriceController = TextEditingController(
      text: existing == null || existing.offerPrice == 0
          ? ''
          : existing.offerPrice.toString(),
    );
    final startController = TextEditingController(
      text: existing?.startsAt?.toIso8601String().split('T').first ?? '',
    );
    final endController = TextEditingController(
      text: existing?.endsAt?.toIso8601String().split('T').first ?? '',
    );
    var type = existing?.type ?? OfferType.percentage;
    var isActive = existing?.isActive ?? true;
    var selectedIds = {...?existing?.itemIds};

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(existing == null ? 'إضافة عرض' : 'تعديل العرض'),
              content: SizedBox(
                width: 460,
                child: Form(
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextFormField(
                          controller: titleController,
                          decoration: const InputDecoration(
                            labelText: 'عنوان العرض',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: descController,
                          maxLines: 2,
                          decoration: const InputDecoration(
                            labelText: 'الوصف',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        SegmentedButton<OfferType>(
                          segments: [
                            for (final entry in OfferType.values)
                              ButtonSegment(
                                value: entry,
                                label: Text(entry.arabicLabel, style: const TextStyle(fontSize: 11)),
                              ),
                          ],
                          selected: {type},
                          onSelectionChanged: (value) {
                            setDialogState(() => type = value.first);
                          },
                        ),
                        const SizedBox(height: 12),
                        if (type != OfferType.combo)
                          TextFormField(
                            controller: valueController,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                            ],
                            decoration: InputDecoration(
                              labelText: type == OfferType.percentage
                                  ? 'نسبة الخصم %'
                                  : 'قيمة الخصم (د.ك)',
                              border: const OutlineInputBorder(),
                            ),
                          ),
                        if (type == OfferType.combo) ...[
                          TextFormField(
                            controller: originalController,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: const InputDecoration(
                              labelText: 'السعر قبل العرض (د.ك)',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: offerPriceController,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: const InputDecoration(
                              labelText: 'سعر الكومبو (د.ك)',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ],
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: startController,
                                decoration: const InputDecoration(
                                  labelText: 'تاريخ البداية YYYY-MM-DD',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextFormField(
                                controller: endController,
                                decoration: const InputDecoration(
                                  labelText: 'تاريخ النهاية YYYY-MM-DD',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('العرض مفعّل'),
                          value: isActive,
                          onChanged: (value) => setDialogState(() => isActive = value),
                        ),
                        if (_menuItems.isNotEmpty) ...[
                          const Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: Text(
                              'أصناف العرض (اختياري)',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              for (final item in _menuItems.take(24))
                                FilterChip(
                                  label: Text(item.name, overflow: TextOverflow.ellipsis),
                                  selected: selectedIds.contains(item.id),
                                  onSelected: (selected) {
                                    setDialogState(() {
                                      if (selected) {
                                        selectedIds.add(item.id);
                                      } else {
                                        selectedIds.remove(item.id);
                                      }
                                    });
                                  },
                                ),
                            ],
                          ),
                        ],
                      ],
                    ),
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
                    if (titleController.text.trim().isEmpty) return;
                    Navigator.pop(context, true);
                  },
                  child: const Text('حفظ'),
                ),
              ],
            );
          },
        );
      },
    );

    final title = titleController.text.trim();
    final description = descController.text.trim();
    final discountValue = double.tryParse(valueController.text.trim()) ?? 0;
    final originalPrice = double.tryParse(originalController.text.trim()) ?? 0;
    final offerPrice = double.tryParse(offerPriceController.text.trim()) ?? 0;
    final startsAt = DateTime.tryParse(startController.text.trim());
    final endsAt = DateTime.tryParse(endController.text.trim());
    titleController.dispose();
    descController.dispose();
    valueController.dispose();
    originalController.dispose();
    offerPriceController.dispose();
    startController.dispose();
    endController.dispose();

    if (saved != true || !mounted) return;

    setState(() => _saving = true);
    try {
      final offer = Offer(
        id: existing?.id ?? '',
        title: title,
        description: description,
        type: type,
        discountValue: discountValue,
        originalPrice: originalPrice,
        offerPrice: offerPrice,
        itemIds: selectedIds.toList(),
        startsAt: startsAt,
        endsAt: endsAt,
        isActive: isActive,
        restaurantId: _restaurantId,
        badgeText: existing?.badgeText ?? '',
        imageUrl: existing?.imageUrl ?? '',
      );
      await ApiService.instance.saveOffer(offer, isUpdate: existing != null);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(existing == null ? 'تمت إضافة العرض' : 'تم تحديث العرض')),
      );
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر حفظ العرض: $error')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _deleteOffer(Offer offer) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('حذف العرض'),
        content: Text('هل تريد حذف "${offer.title}"؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _saving = true);
    try {
      await ApiService.instance.deleteOffer(offer.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم حذف العرض')),
      );
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر حذف العرض: $error')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AdminResponsivePage(
      scrollable: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AdminSectionHeader(
            icon: Icons.local_offer_outlined,
            title: 'العروض والخصومات',
            subtitle: 'إنشاء خصومات نسبية أو مبلغ ثابت أو أسعار كومبو مع تاريخ بداية ونهاية.',
          ),
          if (widget.canManage) ...[
            const SizedBox(height: 12),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: _burgundy),
                onPressed: _saving ? null : () => _showOfferDialog(),
                icon: const Icon(Icons.add),
                label: const Text('إضافة عرض جديد'),
              ),
            ),
          ],
          const SizedBox(height: 16),
          if (!widget.canManage)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('اختر مطعماً من القائمة أعلاه لإدارة عروضه.'),
              ),
            )
          else if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 48),
              child: Center(child: CircularProgressIndicator(color: _burgundy)),
            )
          else if (_error != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    Text('تعذر تحميل العروض:\n$_error', textAlign: TextAlign.center),
                    TextButton(onPressed: _load, child: const Text('إعادة المحاولة')),
                  ],
                ),
              ),
            )
          else if (_offers.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    Text('لا توجد عروض بعد لمطعم $_restaurantLabel.'),
                    const SizedBox(height: 12),
                    FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: _burgundy),
                      onPressed: () => _showOfferDialog(),
                      child: const Text('إضافة أول عرض'),
                    ),
                  ],
                ),
              ),
            )
          else
            Column(
              children: [
                for (final offer in _offers) ...[
                  _OfferAdminCard(
                    offer: offer,
                    saving: _saving,
                    onEdit: () => _showOfferDialog(existing: offer),
                    onDelete: () => _deleteOffer(offer),
                  ),
                  const SizedBox(height: 10),
                ],
              ],
            ),
        ],
      ),
    );
  }
}

class _OfferAdminCard extends StatelessWidget {
  const _OfferAdminCard({
    required this.offer,
    required this.saving,
    required this.onEdit,
    required this.onDelete,
  });

  final Offer offer;
  final bool saving;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  static const _burgundy = Color(0xFF6B1124);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: _burgundy.withValues(alpha: 0.1),
                  child: const Icon(Icons.local_offer_outlined, color: _burgundy),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        offer.title,
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                      ),
                      Text(
                        '${offer.type.arabicLabel} • ${offer.isLive ? 'ساري' : 'غير ساري'}',
                        style: TextStyle(color: Colors.grey.shade700),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (offer.description.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(offer.description),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: _burgundy),
                  onPressed: saving ? null : onEdit,
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('تعديل العرض'),
                ),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.red.shade700),
                  onPressed: saving ? null : onDelete,
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('حذف'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
