import 'package:flutter/material.dart';

import '../../models/order.dart';
import '../../models/scheduled_order.dart';
import '../../services/orders_demo_service.dart';
import '../../services/orders_service.dart';
import '../../services/scheduled_orders_controller.dart';
import '../../services/scheduled_release_engine.dart';
import '../../utils/order_channel_utils.dart';
import 'scheduled_invoice_list.dart';

const _burgundy = Color(0xFF800020);
const _lightOrange = Color(0xFFFF9F43);
const _green = Color(0xFF25D366);

/// Timeline of table reservations and scheduled deliveries.
class ScheduledOrdersPage extends StatefulWidget {
  const ScheduledOrdersPage({super.key});

  @override
  State<ScheduledOrdersPage> createState() => _ScheduledOrdersPageState();
}

class _ScheduledOrdersPageState extends State<ScheduledOrdersPage> {
  final _desk = ScheduledOrdersController.instance;
  ScheduledHoldStatus? _filter;

  @override
  void initState() {
    super.initState();
    _desk.addListener(_rebuild);
    if (!_desk.ready) {
      _desk.load();
    }
  }

  @override
  void dispose() {
    _desk.removeListener(_rebuild);
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  List<ScheduledOrder> get _visible {
    final rows = [..._desk.orders]
      ..sort((a, b) => a.targetAt.compareTo(b.targetAt));
    return rows.where((order) {
      if (order.kind == ScheduledKind.delivery &&
          order.status == ScheduledHoldStatus.scheduled) {
        return false;
      }
      final filter = _filter;
      if (filter == null) return true;
      return order.status == filter;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final rows = _visible;
    final upcoming = upcomingScheduledCount(_desk.orders, DateTime.now());
    return Directionality(
      textDirection: TextDirection.rtl,
      child: ColoredBox(
        color: const Color(0xFFF8F4F5),
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'الحجوزات والطلبات المجدولة',
                    style: TextStyle(color: _burgundy, fontSize: 22, fontWeight: FontWeight.w800),
                  ),
                ),
                _CountBadge(label: '$upcoming خلال ساعتين'),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'الفواتير المجدولة تبقى هنا حتى وقت الإطلاق، ثم تنتقل وحدها إلى الطلبات الحالية.',
              style: TextStyle(color: Color(0xFF64748B)),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 420,
              child: StreamBuilder<List<Order>>(
                stream: OrdersService.instance.watchOrders(),
                initialData: OrdersDemoService.loadedOrders,
                builder: (context, snapshot) {
                  final rows = scheduledHoldOrders(snapshot.data ?? const []);
                  return ScheduledInvoiceList(orders: rows);
                },
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'حجوزات الطاولات والسجلات المحلية',
              style: TextStyle(color: _burgundy, fontSize: 16, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilterChip(
                  label: const Text('الكل'),
                  selected: _filter == null,
                  selectedColor: _lightOrange,
                  onSelected: (_) => setState(() => _filter = null),
                ),
                for (final status in ScheduledHoldStatus.values)
                  FilterChip(
                    label: Text(scheduledStatusLabel(status)),
                    selected: _filter == status,
                    selectedColor: _lightOrange,
                    onSelected: (_) => setState(() => _filter = status),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: _burgundy, foregroundColor: Colors.white),
                onPressed: () => _openForm(context),
                icon: const Icon(Icons.add),
                label: const Text('حجز أو طلب مجدول'),
              ),
            ),
            const SizedBox(height: 12),
            if (rows.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: Text('لا توجد حجوزات في هذا التصفية.'),
                ),
              )
            else
              for (final order in rows) _OrderCard(order: order, desk: _desk),
          ],
        ),
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: _lightOrange, borderRadius: BorderRadius.circular(999)),
      child: Text(label, style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF3F2A12))),
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({required this.order, required this.desk});

  final ScheduledOrder order;
  final ScheduledOrdersController desk;

  @override
  Widget build(BuildContext context) {
    final release = _formatDateTime(order.releaseAt);
    final target = _formatDateTime(order.targetAt);
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
                    order.customerName.isEmpty ? 'بدون اسم' : order.customerName,
                    style: const TextStyle(fontWeight: FontWeight.w800, color: _burgundy),
                  ),
                ),
                Text(scheduledStatusLabel(order.status), style: const TextStyle(fontWeight: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: 6),
            Text('${scheduledKindLabel(order.kind)} • ${order.phone}'),
            if (order.kind == ScheduledKind.dineIn)
              Text('طاولة ${order.tableNumber} • ${order.partySize} أفراد'
                  '${order.depositAmount > 0 ? ' • عربون ${order.depositAmount.toStringAsFixed(3)}' : ''}'),
            Text('الموعد $target'),
            Text('وقت الطباعة $release'),
            if (order.kind == ScheduledKind.delivery)
              Text('تجهيز ${order.preparationMinutes} د • طريق ${order.routeMinutes} د • هامش الكاشير ${order.cashierBufferMinutes} د'),
            if (order.notes.isNotEmpty) Text(order.notes),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                if (order.status == ScheduledHoldStatus.scheduled)
                  FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: _green, foregroundColor: Colors.white),
                    onPressed: () => desk.releaseNow(order.id, DateTime.now()),
                    child: const Text('إطلاق الآن'),
                  ),
                if (order.status == ScheduledHoldStatus.scheduled)
                  OutlinedButton(
                    onPressed: () => desk.cancel(order.id),
                    child: const Text('إلغاء'),
                  ),
                if (order.status == ScheduledHoldStatus.inKitchen)
                  OutlinedButton(
                    onPressed: () => desk.markDelivered(order.id),
                    child: const Text('تم التسليم'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _openForm(BuildContext context) async {
  final created = await showDialog<ScheduledOrder>(
    context: context,
    builder: (context) => const _ScheduledOrderDialog(),
  );
  if (created == null) return;
  await ScheduledOrdersController.instance.add(created);
}

class _ScheduledOrderDialog extends StatefulWidget {
  const _ScheduledOrderDialog();

  @override
  State<_ScheduledOrderDialog> createState() => _ScheduledOrderDialogState();
}

class _ScheduledOrderDialogState extends State<_ScheduledOrderDialog> {
  var _kind = ScheduledKind.dineIn;
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _table = TextEditingController();
  final _party = TextEditingController(text: '2');
  final _deposit = TextEditingController(text: '0');
  final _prep = TextEditingController(text: '25');
  final _route = TextEditingController(text: '0');
  final _buffer = TextEditingController(text: '0');
  final _notes = TextEditingController();
  DateTime? _target;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _table.dispose();
    _party.dispose();
    _deposit.dispose();
    _prep.dispose();
    _route.dispose();
    _buffer.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickTarget() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _target ?? now,
      firstDate: now,
      lastDate: DateTime(now.year + 1),
      helpText: 'تاريخ الموعد',
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_target ?? now.add(const Duration(hours: 2))),
      helpText: 'ساعة الموعد',
    );
    if (!mounted) return;
    final clock = time ?? const TimeOfDay(hour: 19, minute: 0);
    setState(() {
      _target = DateTime(date.year, date.month, date.day, clock.hour, clock.minute);
    });
  }

  void _save() {
    final target = _target;
    if (target == null) return;
    if (_kind == ScheduledKind.dineIn && _table.text.trim().isEmpty) return;
    final route = _kind == ScheduledKind.delivery ? _minutes(_route.text, 15) : 0;
    final buffer = _kind == ScheduledKind.delivery ? _minutes(_buffer.text, 0) : 0;
    Navigator.of(context).pop(
      ScheduledOrder(
        id: 'sch_${DateTime.now().microsecondsSinceEpoch}',
        kind: _kind,
        customerName: _name.text.trim(),
        phone: _phone.text.trim(),
        tableNumber: _table.text.trim(),
        partySize: int.tryParse(_party.text.trim()) ?? 2,
        depositAmount: double.tryParse(_deposit.text.trim()) ?? 0,
        preparationMinutes: _minutes(_prep.text, _kind == ScheduledKind.delivery ? 20 : 25),
        routeMinutes: route,
        cashierBufferMinutes: buffer,
        notes: _notes.text.trim(),
        targetAt: target,
        createdAt: DateTime.now(),
      ),
    );
  }

  int _minutes(String raw, int fallback) {
    final parsed = int.tryParse(raw.trim());
    if (parsed == null || parsed < 0) return fallback;
    return parsed;
  }

  DateTime? get _printAt {
    final target = _target;
    if (target == null) return null;
    final prep = _minutes(_prep.text, _kind == ScheduledKind.delivery ? 20 : 25);
    final route = _kind == ScheduledKind.delivery ? _minutes(_route.text, 15) : 0;
    final buffer = _kind == ScheduledKind.delivery ? _minutes(_buffer.text, 0) : 0;
    return target.subtract(Duration(minutes: prep + route + buffer));
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: const Text('حجز أو طلب مجدول', style: TextStyle(color: _burgundy)),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('حجز طاولة'),
                      selected: _kind == ScheduledKind.dineIn,
                      selectedColor: _lightOrange,
                      onSelected: (_) => setState(() {
                        _kind = ScheduledKind.dineIn;
                        _route.text = '0';
                        _buffer.text = '0';
                      }),
                    ),
                    ChoiceChip(
                      label: const Text('توصيل مجدول'),
                      selected: _kind == ScheduledKind.delivery,
                      selectedColor: _lightOrange,
                      onSelected: (_) => setState(() {
                        _kind = ScheduledKind.delivery;
                        _prep.text = '20';
                        _route.text = '15';
                        _buffer.text = '0';
                      }),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(controller: _name, decoration: const InputDecoration(labelText: 'اسم العميل', border: OutlineInputBorder())),
                const SizedBox(height: 8),
                TextField(controller: _phone, decoration: const InputDecoration(labelText: 'الهاتف', border: OutlineInputBorder())),
                if (_kind == ScheduledKind.dineIn) ...[
                  const SizedBox(height: 8),
                  TextField(controller: _table, decoration: const InputDecoration(labelText: 'رقم الطاولة', border: OutlineInputBorder())),
                  const SizedBox(height: 8),
                  TextField(controller: _party, decoration: const InputDecoration(labelText: 'عدد الأفراد', border: OutlineInputBorder())),
                  const SizedBox(height: 8),
                  TextField(controller: _deposit, decoration: const InputDecoration(labelText: 'عربون (اختياري)', border: OutlineInputBorder())),
                ],
                const SizedBox(height: 8),
                InkWell(
                  onTap: _pickTarget,
                  child: InputDecorator(
                    decoration: InputDecoration(
                      labelText: _kind == ScheduledKind.delivery
                          ? 'تاريخ ووقت التوصيل المستهدف'
                          : 'تاريخ ووقت الموعد',
                      border: const OutlineInputBorder(),
                    ),
                    child: Text(_target == null ? 'اختر الموعد' : _formatDateTime(_target!)),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _prep,
                  keyboardType: TextInputType.number,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: _kind == ScheduledKind.delivery ? 'زمن التحضير (دقيقة)' : 'دقائق التجهيز',
                    border: const OutlineInputBorder(),
                  ),
                ),
                if (_kind == ScheduledKind.delivery) ...[
                  const SizedBox(height: 8),
                  TextField(
                    controller: _route,
                    keyboardType: TextInputType.number,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      labelText: 'زمن الطريق (دقيقة)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _buffer,
                    keyboardType: TextInputType.number,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      labelText: 'هامش الكاشير للطباعة (دقيقة)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'وقت الطباعة التلقائي',
                      border: OutlineInputBorder(),
                      filled: true,
                      fillColor: Color(0xFFFFF6EE),
                    ),
                    child: Text(
                      _printAt == null ? 'اختر تاريخ ووقت التوصيل أولاً' : _formatDateTime(_printAt!),
                      style: const TextStyle(fontWeight: FontWeight.w800, color: _burgundy),
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                TextField(controller: _notes, decoration: const InputDecoration(labelText: 'ملاحظة', border: OutlineInputBorder())),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('إغلاق')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _burgundy),
            onPressed: _target == null ? null : _save,
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
  }
}

String _formatDateTime(DateTime value) {
  final local = value.toLocal();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${local.year}/${two(local.month)}/${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
}

/// Shown on the kitchen screen when a held order has just been released.
class ScheduledKitchenBanner extends StatelessWidget {
  const ScheduledKitchenBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ScheduledOrdersController.instance,
      builder: (context, _) {
        final now = DateTime.now();
        final fresh = ScheduledOrdersController.instance.orders.where((order) {
          final released = order.releasedAt;
          return order.status == ScheduledHoldStatus.inKitchen &&
              released != null &&
              now.difference(released) < const Duration(minutes: 20);
        }).toList();
        if (fresh.isEmpty) return const SizedBox.shrink();
        return Material(
          color: const Color(0xFFFFF6EE),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Text(
              'دخل المطبخ ${fresh.length} طلب مجدول',
              style: const TextStyle(color: _burgundy, fontWeight: FontWeight.w800),
            ),
          ),
        );
      },
    );
  }
}

/// Deliveries that the desk already flagged for the driver, still waiting to leave.
class ScheduledDriverBanner extends StatelessWidget {
  const ScheduledDriverBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ScheduledOrdersController.instance,
      builder: (context, _) {
        final rows = ScheduledOrdersController.instance.orders.where((order) {
          return order.kind == ScheduledKind.delivery &&
              order.status == ScheduledHoldStatus.scheduled &&
              order.driverNotifiedAt != null;
        }).toList();
        if (rows.isEmpty) return const SizedBox.shrink();
        return Material(
          color: const Color(0xFFFFF6EE),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Text(
              'مُجدول: ${rows.length} طلب توصيل يحتاج تأكيد التعيين',
              style: const TextStyle(color: _burgundy, fontWeight: FontWeight.w800),
            ),
          ),
        );
      },
    );
  }
}
