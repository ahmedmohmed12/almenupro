import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:intl/intl.dart';

import '../../models/delivery_dispatch.dart';
import '../../services/admin_auth_service.dart';
import '../../services/api_service.dart';
import '../../services/driver_firestore_sync.dart';
import '../../utils/maps_launcher.dart';
import '../../utils/pick_local_image.dart';
import 'admin_responsive_layout.dart';

class AdminDriversPanel extends StatefulWidget {
  const AdminDriversPanel({super.key});

  @override
  State<AdminDriversPanel> createState() => _AdminDriversPanelState();
}

class _AdminDriversPanelState extends State<AdminDriversPanel> {
  static const _burgundy = Color(0xFF6B1124);

  var _loading = true;
  FleetOpsSnapshot _ops = const FleetOpsSnapshot();
  String? _error;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _load(showSpinner: true);
    _poll = Timer.periodic(const Duration(seconds: 10), (_) => _load());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _load({bool showSpinner = false}) async {
    if (!AdminAuthService.instance.isSuperAdmin) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _ops = const FleetOpsSnapshot();
        _error = null;
      });
      return;
    }
    if (showSpinner && mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final ops = await ApiService.instance.fetchFleetOps();
      if (!mounted) return;
      setState(() {
        _ops = ops;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (_ops.drivers.isEmpty) {
          _error = error.toString().replaceFirst('Exception: ', '');
        }
      });
    }
  }

  Future<void> _openAddDriver() async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => const _AddDriverDialog(),
    );
    if (saved == true) await _load(showSpinner: true);
  }

  Future<void> _openRegions(DeliveryDriver driver) async {
    await showDialog<void>(
      context: context,
      builder: (context) => _DeliveryRegionsDialog(
        driver: driver,
        onUpdated: (_) {},
      ),
    );
    await _load();
  }

  Future<void> _delete(DeliveryDriver driver) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('حذف السائق'),
        content: Text('حذف ${driver.name} من الأسطول المشترك؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('حذف')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ApiService.instance.deleteDriver(driver.id);
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  Future<void> _openActiveOrders(FleetOpsDriver row) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _DriverOpsSheet(
        row: row,
        allDrivers: _ops.drivers,
        onChanged: () async {
          await _load();
          if (!context.mounted) return;
          Navigator.pop(context);
          final refreshed = _ops.drivers.where((entry) => entry.id == row.id).firstOrNull;
          if (refreshed != null && mounted) {
            await _openActiveOrders(refreshed);
          }
        },
      ),
    );
    await _load();
  }

  Future<void> _controlDriver(String driverId, {required String action, int? minutes, String? status}) async {
    try {
      final updated = await ApiService.instance.controlDriver(
        driverId,
        action: action,
        minutes: minutes,
        status: status,
      );
      await syncDriverProfileToFirestore(updated);
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  Future<void> _suspendMenu(FleetOpsDriver row) async {
    final minutes = await showDialog<int>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('حظر مؤقت / إيقاف'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 15),
            child: const Text('15 دقيقة'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 60),
            child: const Text('ساعة واحدة'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 24 * 60),
            child: const Text('24 ساعة'),
          ),
        ],
      ),
    );
    if (minutes == null) return;
    await _controlDriver(row.id, action: 'suspend', minutes: minutes);
  }

  Future<void> _statusOverride(FleetOpsDriver row) async {
    final status = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('تغيير الحالة يدوياً'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'available'),
            child: const Text('متاح'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'busy'),
            child: const Text('مشغول'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'offline'),
            child: const Text('غير متصل'),
          ),
        ],
      ),
    );
    if (status == null) return;
    await _controlDriver(row.id, action: 'status', status: status);
  }

  Future<void> _assignWaitingOrder(DeliveryDispatchRequest request) async {
    final candidates = _ops.drivers
        .where((row) => row.opsStatus != 'suspended')
        .toList()
      ..sort((a, b) {
        final av = a.opsStatus == 'available' ? 0 : 1;
        final bv = b.opsStatus == 'available' ? 0 : 1;
        return av.compareTo(bv);
      });
    if (candidates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا يوجد سائق متاح للتعيين')),
      );
      return;
    }
    final driverId = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('تعيين سائق للتوصيل'),
        children: [
          for (final row in candidates)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, row.id),
              child: Text(
                '${row.driver.name}'
                '${row.opsStatus == 'available' ? ' — متاح' : ' — ${row.opsStatus}'}'
                '${row.driver.phone.isEmpty ? '' : ' · ${row.driver.phone}'}',
              ),
            ),
        ],
      ),
    );
    if (driverId == null || driverId.isEmpty) return;
    try {
      await ApiService.instance.assignDeliveryDriver(
        requestId: request.id,
        driverId: driverId,
      );
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم تعيين السائق للطلب')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  Future<void> _reassignMenu(FleetOpsDriver row) async {
    if (row.activeOrders.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا توجد طلبات نشطة لسحبها')),
      );
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _DriverActiveOrdersSheet(
        row: row,
        allDrivers: _ops.drivers,
        onChanged: () async {
          await _load();
        },
        showReassign: true,
      ),
    );
    await _load();
  }

  String _avgIdleLabel() {
    final idle = _ops.drivers.where((row) => row.opsStatus == 'available').toList();
    if (idle.isEmpty) return 'لا يوجد سائق متاح';
    final avg = idle.fold<int>(0, (sum, row) => sum + row.idleMinutes) ~/ idle.length;
    return 'متوسط الانتظار $avg د';
  }

  Future<void> _openFleetBucket(_FleetBucket bucket) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _FleetBucketSheet(
        bucket: bucket,
        initial: _ops,
        refresh: () async {
          await _load();
          return _ops;
        },
        onOpenDriver: (row) async {
          Navigator.pop(context);
          await _openActiveOrders(row);
        },
      ),
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final summary = _ops.summary;
    return AdminResponsivePage(
      scrollable: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AdminSectionHeader(
            icon: Icons.sensors,
            title: 'مركز عمليات الأسطول',
            subtitle:
                'مراقبة مباشرة لحالة كل سائق، الطلبات النشطة، والتدخل اليدوي دون إعادة تحميل الصفحة.',
            actions: [
              FilledButton.icon(
                onPressed: _openAddDriver,
                style: FilledButton.styleFrom(backgroundColor: _burgundy),
                icon: const Icon(Icons.person_add),
                label: const Text('إضافة سائق'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 900;
              final cards = [
                _FleetSummaryCard(
                  color: const Color(0xFF1B7A4A),
                  icon: Icons.check_circle_outline,
                  title: 'إجمالي السائقين المتاحين',
                  value: '${summary.available}',
                  hint: _avgIdleLabel(),
                  onTap: () => _openFleetBucket(_FleetBucket.available),
                ),
                _FleetSummaryCard(
                  color: const Color(0xFFC45C26),
                  icon: Icons.storefront_outlined,
                  title: 'طلبات جاري استلامها من المطعم',
                  value: '${summary.pickingUp}',
                  hint: 'مقبول ولم يُستلم بعد',
                  onTap: () => _openFleetBucket(_FleetBucket.pickingUp),
                ),
                _FleetSummaryCard(
                  color: const Color(0xFF1E5F99),
                  icon: Icons.local_shipping_outlined,
                  title: 'طلبات في الطريق للعميل',
                  value: '${summary.delivering}',
                  hint: 'تم الاستلام / جاري التوصيل',
                  onTap: () => _openFleetBucket(_FleetBucket.delivering),
                ),
                _FleetSummaryCard(
                  color: const Color(0xFFB42318),
                  icon: Icons.warning_amber_rounded,
                  title: 'تنبيهات التأخير',
                  value: '${summary.delayed}',
                  hint: 'تجاوز الوقت التقديري',
                  onTap: () => _openFleetBucket(_FleetBucket.delayed),
                ),
                _FleetSummaryCard(
                  color: const Color(0xFF6B1124),
                  icon: Icons.person_search_outlined,
                  title: 'طلبات تحتاج سائق',
                  value: '${summary.needsDriver}',
                  hint: 'بانتظار تعيين أو قبول',
                  onTap: () => _openFleetBucket(_FleetBucket.needsDriver),
                ),
              ];
              if (wide) {
                return Row(
                  children: [
                    for (var i = 0; i < cards.length; i++) ...[
                      if (i > 0) const SizedBox(width: 10),
                      Expanded(child: cards[i]),
                    ],
                  ],
                );
              }
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final card in cards)
                    SizedBox(
                      width: constraints.maxWidth >= 520
                          ? (constraints.maxWidth - 10) / 2
                          : constraints.maxWidth,
                      child: card,
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          _NeedsDriverQueue(
            requests: _ops.needsDriver,
            drivers: _ops.drivers,
            onAssign: _assignWaitingOrder,
          ),
          const SizedBox(height: 16),
          if (_loading && _ops.drivers.isEmpty)
            const Center(child: CircularProgressIndicator(color: _burgundy))
          else if (_error != null)
            Text(_error!, style: const TextStyle(color: Color(0xFFC62828)))
          else if (_ops.drivers.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('لا يوجد سائقون في الأسطول المشترك بعد.'),
              ),
            )
          else
            Card(
              clipBehavior: Clip.antiAlias,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  headingRowColor: WidgetStateProperty.all(const Color(0xFFF7F1EE)),
                  columns: const [
                    DataColumn(label: Text('اسم السائق')),
                    DataColumn(label: Text('الهاتف')),
                    DataColumn(label: Text('الحالة المباشرة')),
                    DataColumn(label: Text('طلبات نشطة')),
                    DataColumn(label: Text('المناطق')),
                    DataColumn(label: Text('إجراءات التحكم')),
                  ],
                  rows: [
                    for (final row in _ops.drivers)
                      DataRow(
                        color: WidgetStateProperty.all(
                          row.delayed ? const Color(0xFFFFEBEE) : Colors.transparent,
                        ),
                        cells: [
                          DataCell(
                            InkWell(
                              onTap: () => _openActiveOrders(row),
                              child: Text(
                                row.driver.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  decoration: TextDecoration.underline,
                                ),
                              ),
                            ),
                          ),
                          DataCell(Text(row.driver.phone.isEmpty ? '—' : row.driver.phone)),
                          DataCell(_OpsStatusBadge(row: row)),
                          DataCell(
                            InkWell(
                              onTap: () => _openActiveOrders(row),
                              child: Text(
                                '${row.activeOrders.length}',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: row.activeOrders.isEmpty
                                      ? const Color(0xFF666666)
                                      : _burgundy,
                                  decoration: row.activeOrders.isEmpty
                                      ? TextDecoration.none
                                      : TextDecoration.underline,
                                ),
                              ),
                            ),
                          ),
                          DataCell(Text(
                            row.driver.allowedDeliveryRegions.isEmpty
                                ? 'لا توجد'
                                : '${row.driver.allowedDeliveryRegions.length}',
                          )),
                          DataCell(
                            Wrap(
                              spacing: 4,
                              children: [
                                PopupMenuButton<String>(
                                  tooltip: 'إجراءات التحكم',
                                  onSelected: (value) async {
                                    switch (value) {
                                      case 'reassign':
                                        await _reassignMenu(row);
                                      case 'suspend':
                                        await _suspendMenu(row);
                                      case 'unsuspend':
                                        await _controlDriver(row.id, action: 'unsuspend');
                                      case 'status':
                                        await _statusOverride(row);
                                      case 'regions':
                                        await _openRegions(row.driver);
                                      case 'map':
                                        await navigateToPoint(row.driver.location);
                                      case 'delete':
                                        await _delete(row.driver);
                                    }
                                  },
                                  itemBuilder: (context) => [
                                    const PopupMenuItem(
                                      value: 'reassign',
                                      child: Text('سحب الطلب وإعادة إسناده'),
                                    ),
                                    const PopupMenuItem(
                                      value: 'suspend',
                                      child: Text('حظر مؤقت / إيقاف'),
                                    ),
                                    if (row.opsStatus == 'suspended')
                                      const PopupMenuItem(
                                        value: 'unsuspend',
                                        child: Text('رفع الحظر'),
                                      ),
                                    const PopupMenuItem(
                                      value: 'status',
                                      child: Text('تغيير الحالة يدوياً'),
                                    ),
                                    const PopupMenuDivider(),
                                    const PopupMenuItem(
                                      value: 'regions',
                                      child: Text('مناطق التوصيل'),
                                    ),
                                    if (row.driver.location != null)
                                      const PopupMenuItem(
                                        value: 'map',
                                        child: Text('فتح الموقع'),
                                      ),
                                    const PopupMenuItem(
                                      value: 'delete',
                                      child: Text('حذف السائق'),
                                    ),
                                  ],
                                  child: const Padding(
                                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                    child: Row(
                                      children: [
                                        Icon(Icons.tune, size: 18, color: _burgundy),
                                        SizedBox(width: 4),
                                        Text('تحكم', style: TextStyle(color: _burgundy)),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _NeedsDriverQueue extends StatelessWidget {
  const _NeedsDriverQueue({
    required this.requests,
    required this.drivers,
    required this.onAssign,
  });

  final List<DeliveryDispatchRequest> requests;
  final List<FleetOpsDriver> drivers;
  final Future<void> Function(DeliveryDispatchRequest request) onAssign;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.person_search_outlined, color: Color(0xFF6B1124)),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'طلبات تحتاج سائق توصيل',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                      color: Color(0xFF6B1124),
                    ),
                  ),
                ),
                Text(
                  '${requests.length}',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'الطلبات المفتوحة بدون سائق. عيّن سائقاً يدوياً لإرسال الطلب إليه.',
              style: TextStyle(color: Color(0xFF666666), height: 1.35),
            ),
            const SizedBox(height: 12),
            if (requests.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('لا توجد طلبات بانتظار سائق حالياً.'),
              )
            else
              ...requests.map((request) {
                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF8E1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFFFE082)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        '${request.isExpress ? '🚀 ' : ''}${request.restaurantName.isEmpty ? 'مطعم' : request.restaurantName}'
                        ' · ${request.regionName.isEmpty ? 'بدون منطقة' : request.regionName}',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 4),
                      Text(request.statusLabelAr),
                      Text(
                        [
                          if ((request.orderId ?? '').trim().isNotEmpty)
                            'طلب ${request.orderId}',
                          if (request.customerPhone.isNotEmpty) request.customerPhone,
                          if (request.customerAddress.isNotEmpty) request.customerAddress,
                        ].join(' — '),
                        style: const TextStyle(fontSize: 13, color: Color(0xFF444444)),
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: FilledButton.icon(
                          onPressed: drivers.isEmpty
                              ? null
                              : () => onAssign(request),
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF6B1124),
                          ),
                          icon: const Icon(Icons.person_add_alt_1, size: 18),
                          label: const Text('إضافة سائق للتوصيل'),
                        ),
                      ),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}

class _FleetSummaryCard extends StatelessWidget {
  const _FleetSummaryCard({
    required this.color,
    required this.icon,
    required this.title,
    required this.value,
    required this.hint,
    this.onTap,
  });

  final Color color;
  final IconData icon;
  final String title;
  final String value;
  final String hint;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: color.withValues(alpha: 0.08),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, color: color),
                  const Spacer(),
                  Icon(Icons.touch_app_outlined, size: 16, color: color.withValues(alpha: 0.7)),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                value,
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: color),
              ),
              const SizedBox(height: 4),
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
              const SizedBox(height: 2),
              Text(hint, style: const TextStyle(fontSize: 12, color: Color(0xFF666666))),
              const SizedBox(height: 6),
              Text(
                'اضغط لعرض التفاصيل',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _FleetBucket { available, pickingUp, delivering, delayed, needsDriver }

class _FleetBucketSheet extends StatefulWidget {
  const _FleetBucketSheet({
    required this.bucket,
    required this.initial,
    required this.refresh,
    required this.onOpenDriver,
  });

  final _FleetBucket bucket;
  final FleetOpsSnapshot initial;
  final Future<FleetOpsSnapshot> Function() refresh;
  final Future<void> Function(FleetOpsDriver row) onOpenDriver;

  @override
  State<_FleetBucketSheet> createState() => _FleetBucketSheetState();
}

class _FleetBucketSheetState extends State<_FleetBucketSheet> {
  static const _burgundy = Color(0xFF6B1124);

  late FleetOpsSnapshot _ops;
  String? _busyId;

  @override
  void initState() {
    super.initState();
    _ops = widget.initial;
  }

  String get _title => switch (widget.bucket) {
        _FleetBucket.available => 'السائقون المتاحون',
        _FleetBucket.pickingUp => 'طلبات جاري استلامها من المطعم',
        _FleetBucket.delivering => 'طلبات في الطريق للعميل',
        _FleetBucket.delayed => 'تنبيهات التأخير',
        _FleetBucket.needsDriver => 'طلبات تحتاج سائق',
      };

  List<DeliveryDispatchRequest> get _orders {
    final live = _ops.drivers.expand((row) => row.activeOrders).toList();
    return switch (widget.bucket) {
      _FleetBucket.pickingUp =>
        live.where((row) => row.status == 'accepted').toList(),
      _FleetBucket.delivering => live
          .where((row) => row.status == 'picked_up' || row.status == 'on_the_way')
          .toList(),
      _FleetBucket.delayed => live.where((row) => row.delayed).toList(),
      _FleetBucket.needsDriver => _ops.needsDriver,
      _FleetBucket.available => const [],
    };
  }

  List<FleetOpsDriver> get _availableDrivers =>
      _ops.drivers.where((row) => row.opsStatus == 'available').toList();

  String _fmt(DateTime? value) {
    if (value == null) return '—';
    final local = value.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${local.year}/${two(local.month)}/${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
  }

  Future<void> _run(String id, Future<void> Function() work) async {
    setState(() => _busyId = id);
    try {
      await work();
      final next = await widget.refresh();
      if (!mounted) return;
      setState(() => _ops = next);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _changeDriver(DeliveryDispatchRequest order) async {
    final currentId = (order.assignedDriverId ?? '').trim();
    final candidates = _ops.drivers
        .where((row) => row.opsStatus != 'suspended' && row.id != currentId)
        .toList()
      ..sort((a, b) {
        final av = a.opsStatus == 'available' ? 0 : 1;
        final bv = b.opsStatus == 'available' ? 0 : 1;
        return av.compareTo(bv);
      });
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('تغيير / تعيين السائق'),
        children: [
          if (currentId.isNotEmpty)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, 'pool'),
              child: const Text('إزالة السائق وإعادة الطلب للتجمع'),
            ),
          if (candidates.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('لا يوجد سائق آخر للتعيين'),
            )
          else
            for (final row in candidates)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(context, row.id),
                child: Text(
                  '${row.driver.name}'
                  '${row.opsStatus == 'available' ? ' — متاح' : ''}'
                  '${row.driver.phone.isEmpty ? '' : ' · ${row.driver.phone}'}',
                ),
              ),
        ],
      ),
    );
    if (choice == null) return;
    await _run(order.id, () async {
      if (choice == 'pool') {
        await ApiService.instance.postDeliveryAction(order.id, 'unassign');
      } else {
        await ApiService.instance.assignDeliveryDriver(
          requestId: order.id,
          driverId: choice,
        );
      }
    });
  }

  Future<void> _markDelivered(DeliveryDispatchRequest order) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تم التوصيل'),
        content: Text(
          'تأكيد تسليم الطلب ${order.orderId ?? order.id} يدوياً من لوحة السوبر أدمن؟',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('تم التوصيل')),
        ],
      ),
    );
    if (ok != true) return;
    await _run(order.id, () async {
      await ApiService.instance.postDeliveryAction(order.id, 'admin-deliver');
    });
  }

  @override
  Widget build(BuildContext context) {
    final orders = _orders;
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 8,
        bottom: 16 + MediaQuery.paddingOf(context).bottom,
      ),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.82,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _title,
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 18,
                color: _burgundy,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              widget.bucket == _FleetBucket.available
                  ? 'عرض السائقين المتاحين الآن. اضغط اسماً لفتح طلباته.'
                  : 'كل بيانات الطلب. يمكنك تغيير السائق أو تسجيل تم التوصيل من أي مرحلة.',
              style: const TextStyle(color: Color(0xFF666666)),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: widget.bucket == _FleetBucket.available
                  ? (_availableDrivers.isEmpty
                      ? const Center(child: Text('لا يوجد سائق متاح حالياً.'))
                      : ListView.separated(
                          itemCount: _availableDrivers.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final row = _availableDrivers[index];
                            return Card(
                              child: ListTile(
                                leading: const Icon(Icons.check_circle, color: Color(0xFF1B7A4A)),
                                title: Text(
                                  row.driver.name,
                                  style: const TextStyle(fontWeight: FontWeight.w800),
                                ),
                                subtitle: Text(
                                  [
                                    if (row.driver.phone.isNotEmpty) row.driver.phone,
                                    'متاح منذ ${row.idleMinutes} د',
                                  ].join(' · '),
                                ),
                                trailing: const Icon(Icons.chevron_left),
                                onTap: () => widget.onOpenDriver(row),
                              ),
                            );
                          },
                        ))
                  : (orders.isEmpty
                      ? const Center(child: Text('لا توجد طلبات في هذه القائمة حالياً.'))
                      : ListView.separated(
                          itemCount: orders.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final order = orders[index];
                            final busy = _busyId == order.id;
                            return Card(
                              color: order.delayed ? const Color(0xFFFFEBEE) : null,
                              child: Padding(
                                padding: const EdgeInsets.all(14),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    Text(
                                      '${order.isExpress ? '🚀 ' : ''}طلب #${order.orderId ?? order.id}',
                                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                                    ),
                                    const SizedBox(height: 8),
                                    Text('الحالة: ${order.statusLabelAr}${order.delayed ? ' · متأخر' : ''}'),
                                    Text('المطعم: ${order.restaurantName.isEmpty ? '—' : order.restaurantName}'),
                                    Text('المنطقة: ${order.regionName.isEmpty ? '—' : order.regionName}'),
                                    Text('السائق: ${(order.assignedDriverName ?? '').trim().isEmpty ? 'غير معيّن' : order.assignedDriverName}'
                                        '${(order.assignedDriverPhone ?? '').trim().isEmpty ? '' : ' · ${order.assignedDriverPhone}'}'),
                                    Text('هاتف العميل: ${order.customerPhone.isEmpty ? '—' : order.customerPhone}'),
                                    Text('العنوان: ${order.customerAddress.isEmpty ? '—' : order.customerAddress}'),
                                    Text('رسوم السائق: ${order.driverFee.toStringAsFixed(3)} د.ك · تحصيل: ${order.cashToCollect.toStringAsFixed(3)} د.ك'),
                                    Text('ETA: ${order.etaMinutes ?? '—'} د'),
                                    Text('القبول: ${_fmt(order.acceptedAt)}'),
                                    Text('الاستلام: ${_fmt(order.pickedUpAt)}'),
                                    Text('آخر تحديث: ${_fmt(order.updatedAt)}'),
                                    const SizedBox(height: 12),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: [
                                        FilledButton.icon(
                                          onPressed: busy ? null : () => _changeDriver(order),
                                          style: FilledButton.styleFrom(backgroundColor: _burgundy),
                                          icon: const Icon(Icons.swap_horiz, size: 18),
                                          label: Text(
                                            (order.assignedDriverId ?? '').trim().isEmpty
                                                ? 'تعيين سائق'
                                                : 'تغيير السائق',
                                          ),
                                        ),
                                        FilledButton.icon(
                                          onPressed: busy ? null : () => _markDelivered(order),
                                          style: FilledButton.styleFrom(
                                            backgroundColor: const Color(0xFF1B7A4A),
                                          ),
                                          icon: busy
                                              ? const SizedBox(
                                                  width: 16,
                                                  height: 16,
                                                  child: CircularProgressIndicator(
                                                    strokeWidth: 2,
                                                    color: Colors.white,
                                                  ),
                                                )
                                              : const Icon(Icons.done_all, size: 18),
                                          label: const Text('تم التوصيل'),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        )),
            ),
          ],
        ),
      ),
    );
  }
}

class _OpsStatusBadge extends StatelessWidget {
  const _OpsStatusBadge({required this.row});

  final FleetOpsDriver row;

  @override
  Widget build(BuildContext context) {
    late final Color bg;
    late final Color fg;
    late final String label;
    switch (row.opsStatus) {
      case 'available':
        bg = const Color(0xFFE8F5E9);
        fg = const Color(0xFF1B7A4A);
        label = 'متاح منذ ${row.idleMinutes} دقيقة';
      case 'en_route_restaurant':
        bg = const Color(0xFFFFF3E0);
        fg = const Color(0xFFC45C26);
        label = 'في الطريق للمطعم';
      case 'en_route_customer':
        bg = const Color(0xFFE3F2FD);
        fg = const Color(0xFF1E5F99);
        final order = row.activeOrders
            .where((entry) => entry.status == 'picked_up' || entry.status == 'on_the_way')
            .map((entry) => entry.orderId)
            .whereType<String>()
            .where((id) => id.isNotEmpty)
            .firstOrNull;
        label = order == null || order.isEmpty ? 'جاري التوصيل' : 'جاري التوصيل · #$order';
      case 'delayed':
        bg = const Color(0xFFFFEBEE);
        fg = const Color(0xFFB42318);
        label = 'مُتأخر';
      case 'suspended':
        bg = const Color(0xFFFFF8E1);
        fg = const Color(0xFF8A5A00);
        label = 'مشغول / محظور';
      case 'busy':
        bg = const Color(0xFFFFF8E1);
        fg = const Color(0xFF8A5A00);
        label = 'مشغول / محظور';
      default:
        bg = const Color(0xFFEEEEEE);
        fg = const Color(0xFF555555);
        label = 'غير متصل';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label, style: TextStyle(color: fg, fontWeight: FontWeight.w700, fontSize: 12)),
    );
  }
}

class _DriverOpsSheet extends StatelessWidget {
  const _DriverOpsSheet({
    required this.row,
    required this.allDrivers,
    required this.onChanged,
    this.showReassign = false,
  });

  final FleetOpsDriver row;
  final List<FleetOpsDriver> allDrivers;
  final Future<void> Function() onChanged;
  final bool showReassign;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 8,
          bottom: 16 + MediaQuery.paddingOf(context).bottom,
        ),
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.78,
          child: Column(
            children: [
              Text(
                row.driver.name,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                  color: Color(0xFF6B1124),
                ),
              ),
              const TabBar(
                labelColor: Color(0xFF6B1124),
                tabs: [
                  Tab(text: 'طلبات نشطة'),
                  Tab(text: 'السجل المالي'),
                ],
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    _DriverActiveOrdersSheet(
                      row: row,
                      allDrivers: allDrivers,
                      onChanged: onChanged,
                      showReassign: showReassign,
                      embedded: true,
                    ),
                    _DriverLedgerTab(driverId: row.id, driverName: row.driver.name),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DriverLedgerTab extends StatefulWidget {
  const _DriverLedgerTab({required this.driverId, required this.driverName});

  final String driverId;
  final String driverName;

  @override
  State<_DriverLedgerTab> createState() => _DriverLedgerTabState();
}

class _DriverLedgerTabState extends State<_DriverLedgerTab> {
  final _orderId = TextEditingController();
  final _restaurant = TextEditingController();
  DateTime? _from;
  DateTime? _to;
  var _loading = true;
  String? _error;
  List<DriverLedgerEntry> _entries = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _orderId.dispose();
    _restaurant.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final entries = await ApiService.instance.fetchDriverLedger(
        widget.driverId,
        from: _from?.toUtc().toIso8601String(),
        to: _to?.toUtc().toIso8601String(),
        restaurant: _restaurant.text.trim(),
        orderId: _orderId.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        _entries = entries;
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

  Future<void> _pickDate({required bool from}) async {
    final initial = from ? _from : _to;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial ?? DateTime.now(),
      firstDate: DateTime(2024),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked == null) return;
    setState(() {
      if (from) {
        _from = picked;
      } else {
        _to = picked;
      }
    });
    await _load();
  }

  String _stamp(DateTime? value) {
    if (value == null) return '—';
    return DateFormat('yyyy/MM/dd HH:mm:ss').format(value.toLocal());
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            SizedBox(
              width: 160,
              child: TextField(
                controller: _orderId,
                decoration: const InputDecoration(
                  isDense: true,
                  labelText: 'رقم الطلب',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => _load(),
              ),
            ),
            SizedBox(
              width: 160,
              child: TextField(
                controller: _restaurant,
                decoration: const InputDecoration(
                  isDense: true,
                  labelText: 'اسم المطعم',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => _load(),
              ),
            ),
            OutlinedButton(
              onPressed: () => _pickDate(from: true),
              child: Text(_from == null ? 'من تاريخ' : DateFormat('yyyy/MM/dd').format(_from!)),
            ),
            OutlinedButton(
              onPressed: () => _pickDate(from: false),
              child: Text(_to == null ? 'إلى تاريخ' : DateFormat('yyyy/MM/dd').format(_to!)),
            ),
            FilledButton(onPressed: _load, child: const Text('بحث')),
          ],
        ),
        const SizedBox(height: 8),
        if (_loading)
          const Expanded(child: Center(child: CircularProgressIndicator()))
        else if (_error != null)
          Expanded(child: Center(child: Text(_error!)))
        else if (_entries.isEmpty)
          const Expanded(child: Center(child: Text('لا توجد حركات مالية بعد.')))
        else
          Expanded(
            child: ListView.separated(
              itemCount: _entries.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final row = _entries[index];
                final pay = row.paymentKind == 'cash' ? 'كاش' : 'كينت';
                final dual = row.dualStatus == 'confirmed' ? 'مؤكد من الطرفين' : 'بانتظار التأكيد';
                return ListTile(
                  dense: true,
                  title: Text(
                    'طلب #${row.invoiceNumber.isEmpty ? row.orderId : row.invoiceNumber}',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: Text(
                    '${_stamp(row.createdAt)}\n'
                    '${row.restaurantName} · كاشير: ${row.cashierName.isEmpty ? '—' : row.cashierName} (${row.cashierId.isEmpty ? '—' : row.cashierId})\n'
                    '$pay · صافي للكاشير ${row.netToCashier.toStringAsFixed(3)} · رسوم السائق ${row.driverFee.toStringAsFixed(3)}\n'
                    '$dual',
                  ),
                  isThreeLine: true,
                );
              },
            ),
          ),
      ],
    );
  }
}

class _DriverActiveOrdersSheet extends StatefulWidget {
  const _DriverActiveOrdersSheet({
    required this.row,
    required this.allDrivers,
    required this.onChanged,
    this.showReassign = false,
    this.embedded = false,
  });

  final FleetOpsDriver row;
  final List<FleetOpsDriver> allDrivers;
  final Future<void> Function() onChanged;
  final bool showReassign;
  final bool embedded;

  @override
  State<_DriverActiveOrdersSheet> createState() => _DriverActiveOrdersSheetState();
}

class _DriverActiveOrdersSheetState extends State<_DriverActiveOrdersSheet> {
  static const _burgundy = Color(0xFF6B1124);
  String? _busyId;

  String _fmt(DateTime? value) {
    if (value == null) return '—';
    final local = value.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(local.hour)}:${two(local.minute)}';
  }

  Future<void> _run(String id, Future<void> Function() work) async {
    setState(() => _busyId = id);
    try {
      await work();
      await widget.onChanged();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _adminDeliver(DeliveryDispatchRequest order) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تسليم للعميل (أدمن)'),
        content: Text('تأكيد تسليم الطلب ${order.orderId ?? order.id} يدوياً؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('تسليم')),
        ],
      ),
    );
    if (ok != true) return;
    await _run(order.id, () async {
      await ApiService.instance.postDeliveryAction(order.id, 'admin-deliver');
    });
  }

  Future<void> _unassign(DeliveryDispatchRequest order) async {
    final available = widget.allDrivers
        .where((entry) => entry.opsStatus == 'available' && entry.id != widget.row.id)
        .toList();
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('سحب الطلب وإعادة إسناده'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'pool'),
            child: const Text('إعادة إلى التجمع المفتوح'),
          ),
          for (final driver in available)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, driver.id),
              child: Text('تعيين إلى ${driver.driver.name}'),
            ),
        ],
      ),
    );
    if (choice == null) return;
    await _run(order.id, () async {
      if (choice == 'pool') {
        await ApiService.instance.postDeliveryAction(order.id, 'unassign');
      } else {
        await ApiService.instance.assignDeliveryDriver(requestId: order.id, driverId: choice);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final orders = widget.row.activeOrders;
    final body = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!widget.embedded) ...[
              Text(
                'طلبات ${widget.row.driver.name} النشطة',
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: _burgundy),
              ),
              const SizedBox(height: 12),
            ],
            if (orders.isEmpty)
              const Expanded(child: Center(child: Text('لا توجد طلبات معيّنة حالياً.')))
            else
              Expanded(
                child: ListView.separated(
                  itemCount: orders.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final order = orders[index];
                    final busy = _busyId == order.id;
                    return Card(
                      color: order.delayed ? const Color(0xFFFFEBEE) : null,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'طلب #${order.orderId ?? order.id}',
                              style: const TextStyle(fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 4),
                            Text('المطعم: ${order.restaurantName.isEmpty ? '—' : order.restaurantName}'),
                            Text(
                              'العنوان: ${order.customerAddress.isEmpty ? '—' : order.customerAddress}',
                            ),
                            Text('الحالة: ${order.statusLabelAr}${order.delayed ? ' · مُتأخر' : ''}'),
                            Text('الاستلام: ${_fmt(order.pickedUpAt)} · التوصيل المتوقع: ${order.etaMinutes ?? '—'} د'),
                            Text('القَبول: ${_fmt(order.acceptedAt)} · التحديث: ${_fmt(order.updatedAt)}'),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                FilledButton(
                                  onPressed: busy ? null : () => _adminDeliver(order),
                                  style: FilledButton.styleFrom(backgroundColor: _burgundy),
                                  child: busy
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white,
                                          ),
                                        )
                                      : const Text('تسليم للعميل (أدمن)'),
                                ),
                                OutlinedButton(
                                    onPressed: busy ? null : () => _unassign(order),
                                    child: const Text('سحب / إعادة إسناد'),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        );
    if (widget.embedded) return body;
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 8,
        bottom: 16 + MediaQuery.paddingOf(context).bottom,
      ),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.72,
        child: body,
      ),
    );
  }
}


class _AddDriverDialog extends StatefulWidget {
  const _AddDriverDialog();

  @override
  State<_AddDriverDialog> createState() => _AddDriverDialogState();
}

class _AddDriverDialogState extends State<_AddDriverDialog> {
  static const _burgundy = Color(0xFF6B1124);

  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _civilId = TextEditingController();
  final _pin = TextEditingController();
  PickedStoreImage? _civilPhoto;
  PickedStoreImage? _licensePhoto;
  var _saving = false;
  String? _nameError;
  String? _pinError;
  String? _civilIdError;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _civilId.dispose();
    _pin.dispose();
    super.dispose();
  }

  Future<void> _pick(void Function(PickedStoreImage image) apply) async {
    final picked = await pickLocalStoreImage();
    if (picked == null || !mounted) return;
    setState(() => apply(picked));
  }

  String _digitsOnly(String raw) =>
      raw.replaceAll(RegExp(r'\D'), '');

  bool _validate() {
    final name = _name.text.trim();
    final pin = _digitsOnly(_pin.text.trim());
    if (pin != _pin.text) {
      _pin.value = TextEditingValue(
        text: pin,
        selection: TextSelection.collapsed(offset: pin.length),
      );
    }
    final civilId = _digitsOnly(_civilId.text.trim());
    if (civilId != _civilId.text.trim() && _civilId.text.trim().isNotEmpty) {
      _civilId.value = TextEditingValue(
        text: civilId,
        selection: TextSelection.collapsed(offset: civilId.length),
      );
    }

    final nameError = name.length < 2 ? 'اسم السائق مطلوب' : null;
    final pinError = pin.length == 4
        ? null
        : 'رمز PIN المكون من 4 أرقام مطلوب لتطبيق السائق';
    final civilIdError = civilId.isEmpty || civilId.length == 12
        ? null
        : 'الرقم المدني اختياري، وإن وُجد يجب أن يكون 12 رقماً';

    setState(() {
      _nameError = nameError;
      _pinError = pinError;
      _civilIdError = civilIdError;
    });
    return nameError == null && pinError == null && civilIdError == null;
  }

  Future<void> _save() async {
    if (!_validate()) return;
    final name = _name.text.trim();
    final pin = _digitsOnly(_pin.text.trim());
    final civilId = _digitsOnly(_civilId.text.trim());
    setState(() => _saving = true);
    try {
      var driver = await ApiService.instance.createDriver(
        name: name,
        phone: _phone.text.trim(),
        civilId: civilId,
        pin: pin,
      );
      var civilUrl = '';
      var licenseUrl = '';
      if (_civilPhoto != null) {
        civilUrl = await ApiService.instance.uploadDriverDocument(
          driverId: driver.id,
          kind: 'civil_id',
          contentType: _civilPhoto!.contentType,
          base64: _civilPhoto!.base64,
        );
      }
      if (_licensePhoto != null) {
        licenseUrl = await ApiService.instance.uploadDriverDocument(
          driverId: driver.id,
          kind: 'license',
          contentType: _licensePhoto!.contentType,
          base64: _licensePhoto!.base64,
        );
      }
      if (civilUrl.isNotEmpty || licenseUrl.isNotEmpty) {
        driver = await ApiService.instance.patchDriver(
          driver.id,
          civilIdPhotoUrl: civilUrl.isEmpty ? null : civilUrl,
          licensePhotoUrl: licenseUrl.isEmpty ? null : licenseUrl,
        );
      }
      await syncDriverProfileToFirestore(driver);
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      final message = error.toString().replaceFirst('Exception: ', '');
      setState(() {
        if (message.contains('PIN') || message.contains('pin')) {
          _pinError = message;
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('إضافة سائق جديد'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _name,
                enabled: !_saving,
                onChanged: (_) {
                  if (_nameError != null) setState(() => _nameError = null);
                },
                decoration: InputDecoration(
                  labelText: 'اسم السائق',
                  border: const OutlineInputBorder(),
                  errorText: _nameError,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _phone,
                enabled: !_saving,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'رقم الهاتف',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _pin,
                enabled: !_saving,
                maxLength: 4,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onChanged: (value) {
                  final pin = value.trim();
                  if (_pinError != null && pin.length == 4) {
                    setState(() => _pinError = null);
                  }
                },
                decoration: InputDecoration(
                  labelText: 'رمز PIN لتطبيق السائق *',
                  hintText: 'مثال: 1234',
                  helperText: '4 أرقام — يستخدمها السائق لتسجيل الدخول',
                  border: const OutlineInputBorder(),
                  errorBorder: const OutlineInputBorder(
                    borderSide: BorderSide(color: Color(0xFFC62828), width: 1.5),
                  ),
                  focusedErrorBorder: const OutlineInputBorder(
                    borderSide: BorderSide(color: Color(0xFFC62828), width: 2),
                  ),
                  counterText: '',
                  prefixIcon: const Icon(Icons.lock_outline),
                  errorText: _pinError,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _civilId,
                enabled: !_saving,
                keyboardType: TextInputType.number,
                maxLength: 12,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onChanged: (value) {
                  final civilId = value.trim();
                  if (_civilIdError != null &&
                      (civilId.isEmpty || civilId.length == 12)) {
                    setState(() => _civilIdError = null);
                  }
                },
                decoration: InputDecoration(
                  labelText: 'الرقم المدني (اختياري)',
                  helperText: '12 رقماً إذا تم إدخاله',
                  counterText: '',
                  border: const OutlineInputBorder(),
                  errorBorder: const OutlineInputBorder(
                    borderSide: BorderSide(color: Color(0xFFC62828), width: 1.5),
                  ),
                  focusedErrorBorder: const OutlineInputBorder(
                    borderSide: BorderSide(color: Color(0xFFC62828), width: 2),
                  ),
                  errorText: _civilIdError,
                ),
              ),
              const SizedBox(height: 16),
              _PhotoPickerTile(
                label: 'صورة البطاقة المدنية',
                picked: _civilPhoto,
                onPick: _saving ? null : () => _pick((image) => _civilPhoto = image),
              ),
              const SizedBox(height: 12),
              _PhotoPickerTile(
                label: 'صورة رخصة القيادة',
                picked: _licensePhoto,
                onPick: _saving ? null : () => _pick((image) => _licensePhoto = image),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          style: FilledButton.styleFrom(backgroundColor: _burgundy),
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Text('حفظ'),
        ),
      ],
    );
  }
}

class _PhotoPickerTile extends StatelessWidget {
  const _PhotoPickerTile({
    required this.label,
    required this.picked,
    required this.onPick,
  });

  final String label;
  final PickedStoreImage? picked;
  final VoidCallback? onPick;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPick,
      icon: Icon(picked == null ? Icons.upload_file : Icons.check_circle_outline),
      label: Text(picked == null ? label : '$label — تم الاختيار'),
    );
  }
}

class _DeliveryRegionsDialog extends StatefulWidget {
  const _DeliveryRegionsDialog({
    required this.driver,
    required this.onUpdated,
  });

  final DeliveryDriver driver;
  final ValueChanged<DeliveryDriver> onUpdated;

  @override
  State<_DeliveryRegionsDialog> createState() => _DeliveryRegionsDialogState();
}

class _DeliveryRegionsDialogState extends State<_DeliveryRegionsDialog> {
  static const _burgundy = Color(0xFF6B1124);

  var _loading = true;
  String? _error;
  List<MasterDeliveryRegion> _regions = [];
  late Map<String, bool> _assigned;
  String? _busyKey;

  @override
  void initState() {
    super.initState();
    _assigned = Map<String, bool>.from(widget.driver.assignedRegions);
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final regions = await ApiService.instance.fetchMasterRegions();
      if (!mounted) return;
      final next = Map<String, bool>.from(_assigned);
      for (final region in regions) {
        next.putIfAbsent(region.id, () => false);
      }
      setState(() {
        _regions = regions;
        _assigned = next;
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

  Future<void> _persist(Map<String, bool> next) async {
    final previous = Map<String, bool>.from(_assigned);
    setState(() => _assigned = next);
    try {
      final updated = await ApiService.instance.patchDriver(
        widget.driver.id,
        assignedRegions: next,
      );
      await syncDriverProfileToFirestore(updated);
      widget.onUpdated(updated);
    } catch (error) {
      if (!mounted) return;
      setState(() => _assigned = previous);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  Future<void> _setAll(bool value) async {
    final next = <String, bool>{
      for (final entry in _assigned.entries) entry.key: value,
      for (final region in _regions) region.id: value,
    };
    setState(() => _busyKey = '*');
    await _persist(next);
    if (mounted) setState(() => _busyKey = null);
  }

  Future<void> _toggle(MasterDeliveryRegion region, bool value) async {
    setState(() => _busyKey = region.id);
    final next = Map<String, bool>.from(_assigned)..[region.id] = value;
    await _persist(next);
    if (mounted) setState(() => _busyKey = null);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('مناطق التوصيل — ${widget.driver.name}'),
      content: SizedBox(
        width: 460,
        height: 480,
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: _burgundy))
            : _error != null
                ? Text(_error!, style: const TextStyle(color: Color(0xFFC62828)))
                : _regions.isEmpty
                    ? const Text('لا توجد مناطق رئيسية بعد. أضف مناطق التوصيل من إعدادات المطاعم.')
                    : Column(
                        children: [
                          Row(
                            children: [
                              OutlinedButton(
                                onPressed: _busyKey != null ? null : () => _setAll(true),
                                child: const Text('تحديد الكل'),
                              ),
                              const SizedBox(width: 8),
                              OutlinedButton(
                                onPressed: _busyKey != null ? null : () => _setAll(false),
                                child: const Text('إلغاء الكل'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Expanded(
                            child: ListView.separated(
                              itemCount: _regions.length,
                              separatorBuilder: (_, __) => const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final region = _regions[index];
                                final on = _assigned[region.id] == true;
                                return SwitchListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: Text(region.name),
                                  subtitle: region.governorate.isEmpty
                                      ? null
                                      : Text(region.governorate),
                                  value: on,
                                  activeThumbColor: _burgundy,
                                  onChanged: _busyKey != null
                                      ? null
                                      : (value) => _toggle(region, value),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('إغلاق')),
      ],
    );
  }
}
