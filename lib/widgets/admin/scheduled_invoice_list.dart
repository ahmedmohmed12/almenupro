import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/order.dart';
import '../../models/scheduled_order.dart';
import '../../services/orders_service.dart';
import '../../services/scheduled_orders_controller.dart';

const _burgundy = Color(0xFF800020);
const _lightOrange = Color(0xFFFF9F43);

/// Invoices that are still waiting for their release time.
class ScheduledInvoiceList extends StatefulWidget {
  const ScheduledInvoiceList({super.key, required this.orders});

  final List<Order> orders;

  @override
  State<ScheduledInvoiceList> createState() => _ScheduledInvoiceListState();
}

class _ScheduledInvoiceListState extends State<ScheduledInvoiceList> {
  Timer? _ticker;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.orders.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'لا توجد طلبات مجدولة.\nتظهر هنا فقط الفواتير ذات الحالة scheduled حتى وقت الإطلاق.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFF64748B), height: 1.4),
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      itemCount: widget.orders.length,
      itemBuilder: (context, index) {
        final order = widget.orders[index];
        return _ScheduledInvoiceCard(
          order: order,
          now: _now,
          onEdit: () => _edit(order),
          onCancel: () => _cancel(order),
        );
      },
    );
  }

  Future<void> _edit(Order order) async {
    final next = await showDialog<Order>(
      context: context,
      builder: (context) => _EditScheduleDialog(order: order),
    );
    if (next == null) return;
    await OrdersService.instance.saveScheduledInvoice(next);
    final target = next.targetDeliveryTime;
    if (target == null) return;
    final desk = ScheduledOrdersController.instance;
    final existing = desk.orders.where((row) => row.id == next.id);
    if (existing.isNotEmpty &&
        existing.first.status != ScheduledHoldStatus.scheduled) {
      return;
    }
    await desk.upsert(
      ScheduledOrder(
        id: next.id,
        kind: ScheduledKind.delivery,
        customerName: next.customerName,
        phone: next.phone,
        targetAt: target,
        createdAt: next.createdAt,
        preparationMinutes: next.prepTimeMinutes ?? 20,
        routeMinutes: next.routeTimeMinutes ?? 15,
        cashierBufferMinutes: next.cashierBufferMinutes ?? 0,
        notes: next.address,
      ),
    );
  }

  Future<void> _cancel(Order order) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('إلغاء الطلب المجدول'),
        content: Text('إلغاء فاتورة ${order.customerName}؟ لن تُرسل للمطبخ.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('رجوع'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('إلغاء الطلب'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await OrdersService.instance.updateOrderStatus(
      order.id,
      OrderStatus.cancelled,
    );
    await ScheduledOrdersController.instance.cancel(order.id);
  }
}

class _ScheduledInvoiceCard extends StatelessWidget {
  const _ScheduledInvoiceCard({
    required this.order,
    required this.now,
    required this.onEdit,
    required this.onCancel,
  });

  final Order order;
  final DateTime now;
  final VoidCallback onEdit;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final target = order.targetDeliveryTime;
    final release = order.resolvedAutoReleaseTime;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    order.customerName.trim().isEmpty
                        ? 'بدون اسم'
                        : order.customerName,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: _burgundy,
                    ),
                  ),
                ),
                const Text(
                  'مجدول',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(order.phone),
            if (order.items.isNotEmpty)
              Text(
                order.items
                    .take(3)
                    .map((item) => '${item.quantity}× ${item.name}')
                    .join('، '),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            Text('الموعد المستهدف ${target == null ? '—' : _clock(target)}'),
            Text(
              'وقت الإطلاق ${release == null ? '—' : _clock(release)}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              'المتبقي ${release == null ? '—' : _remaining(release, now)}',
              style: const TextStyle(
                color: Color(0xFF9A3412),
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: _lightOrange,
                    foregroundColor: const Color(0xFF3F2A12),
                  ),
                  onPressed: onEdit,
                  child: const Text('تعديل'),
                ),
                OutlinedButton(
                  onPressed: onCancel,
                  child: const Text('إلغاء'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _EditScheduleDialog extends StatefulWidget {
  const _EditScheduleDialog({required this.order});

  final Order order;

  @override
  State<_EditScheduleDialog> createState() => _EditScheduleDialogState();
}

class _EditScheduleDialogState extends State<_EditScheduleDialog> {
  late DateTime? _target = widget.order.targetDeliveryTime;
  late final _prep = TextEditingController(
    text: '${widget.order.prepTimeMinutes ?? 20}',
  );
  late final _route = TextEditingController(
    text: '${widget.order.routeTimeMinutes ?? 15}',
  );
  late final _buffer = TextEditingController(
    text: '${widget.order.cashierBufferMinutes ?? 0}',
  );

  @override
  void dispose() {
    _prep.dispose();
    _route.dispose();
    _buffer.dispose();
    super.dispose();
  }

  int _minutes(TextEditingController controller, int fallback) {
    final parsed = int.tryParse(controller.text.trim());
    if (parsed == null || parsed < 0) return fallback;
    return parsed;
  }

  DateTime? get _release {
    final target = _target;
    if (target == null) return null;
    final lead = _minutes(_prep, 20) + _minutes(_route, 15) + _minutes(_buffer, 0);
    return target.subtract(Duration(minutes: lead));
  }

  Future<void> _pick() async {
    final now = DateTime.now();
    final current = _target ?? now;
    final date = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current),
    );
    if (!mounted) return;
    final clock = time ?? TimeOfDay.fromDateTime(current);
    setState(() {
      _target = DateTime(date.year, date.month, date.day, clock.hour, clock.minute);
    });
  }

  @override
  Widget build(BuildContext context) {
    final release = _release;
    return AlertDialog(
      title: const Text('تعديل الموعد'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            OutlinedButton(
              onPressed: _pick,
              child: Text(_target == null ? 'اختر التاريخ والوقت' : _clock(_target!)),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _prep,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'زمن التحضير (دقائق)'),
              onChanged: (_) => setState(() {}),
            ),
            TextField(
              controller: _route,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'زمن الطريق (دقائق)'),
              onChanged: (_) => setState(() {}),
            ),
            TextField(
              controller: _buffer,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'هامش الكاشير (دقائق)'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                'وقت الإطلاق ${release == null ? '—' : _clock(release)}',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('رجوع'),
        ),
        FilledButton(
          onPressed: _target == null
              ? null
              : () {
                  final target = _target!;
                  final prep = _minutes(_prep, 20);
                  final route = _minutes(_route, 15);
                  final buffer = _minutes(_buffer, 0);
                  Navigator.pop(
                    context,
                    widget.order.copyWith(
                      deliveryDate: target,
                      targetDeliveryTime: target,
                      prepTimeMinutes: prep,
                      routeTimeMinutes: route,
                      cashierBufferMinutes: buffer,
                      autoReleaseTime: target.subtract(
                        Duration(minutes: prep + route + buffer),
                      ),
                    ),
                  );
                },
          child: const Text('حفظ'),
        ),
      ],
    );
  }
}

String _clock(DateTime value) {
  String two(int number) => number.toString().padLeft(2, '0');
  final local = value.toLocal();
  return '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
}

String _remaining(DateTime release, DateTime now) {
  final diff = release.difference(now);
  if (!diff.isNegative && diff.inSeconds == 0) return 'الآن';
  if (diff.isNegative) return 'جارٍ الإطلاق';
  final hours = diff.inHours;
  final minutes = diff.inMinutes.remainder(60);
  final seconds = diff.inSeconds.remainder(60);
  if (hours > 0) return '$hours س $minutes د';
  return '$minutes د ${seconds.toString().padLeft(2, '0')} ث';
}
