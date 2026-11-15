import 'order.dart';
import 'shift_session.dart';
import 'manager_report_period.dart';
import '../utils/order_channel_utils.dart';

class ManagerTopItem {
  const ManagerTopItem({
    required this.name,
    required this.quantity,
    required this.revenue,
  });

  final String name;
  final int quantity;
  final double revenue;
}

class ManagerAlert {
  const ManagerAlert({
    required this.id,
    required this.title,
    required this.body,
    required this.kind,
  });

  final String id;
  final String title;
  final String body;
  final ManagerAlertKind kind;
}

enum ManagerAlertKind { voidOrder, discount, shiftClosed, newOrder }

class ManagerRecentOrder {
  const ManagerRecentOrder({
    required this.id,
    required this.title,
    required this.channel,
    required this.total,
    required this.createdAt,
  });

  final String id;
  final String title;
  final String channel;
  final double total;
  final DateTime createdAt;
}

class ManagerChannelSlice {
  const ManagerChannelSlice({
    required this.id,
    required this.label,
    required this.value,
    required this.color,
  });

  final String id;
  final String label;
  final double value;
  final int color;
}

class ManagerReportSnapshot {
  const ManagerReportSnapshot({
    required this.netSales,
    required this.cashSales,
    required this.knetSales,
    required this.orderCount,
    required this.weekDeltaPercent,
    required this.avgTicket,
    required this.voidedAmount,
    required this.voidCount,
    required this.hourlySales,
    required this.channels,
    required this.topItems,
    required this.openShifts,
    required this.alerts,
    required this.recentOrders,
    required this.updatedAt,
    required this.live,
    required this.period,
    required this.salesTitle,
    required this.comparisonLabel,
    required this.chartTitle,
    required this.chartLabels,
  });

  final double netSales;
  final double cashSales;
  final double knetSales;
  final int orderCount;
  final double weekDeltaPercent;
  final double avgTicket;
  final double voidedAmount;
  final int voidCount;
  final List<double> hourlySales;
  final List<ManagerChannelSlice> channels;
  final List<ManagerTopItem> topItems;
  final List<ShiftSession> openShifts;
  final List<ManagerAlert> alerts;
  final List<ManagerRecentOrder> recentOrders;
  final DateTime updatedAt;
  final bool live;
  final ManagerReportPeriod period;
  final String salesTitle;
  final String comparisonLabel;
  final String chartTitle;
  final List<String> chartLabels;

  factory ManagerReportSnapshot.empty() => ManagerReportSnapshot(
    netSales: 0,
    cashSales: 0,
    knetSales: 0,
    orderCount: 0,
    weekDeltaPercent: 0,
    avgTicket: 0,
    voidedAmount: 0,
    voidCount: 0,
    hourlySales: List<double>.filled(24, 0),
    channels: const [],
    topItems: const [],
    openShifts: const [],
    alerts: const [],
    recentOrders: const [],
    updatedAt: DateTime.fromMillisecondsSinceEpoch(0),
    live: false,
    period: ManagerReportPeriod.live,
    salesTitle: 'صافي المبيعات الآن',
    comparisonLabel: 'مقابل نفس اليوم الأسبوع الماضي',
    chartTitle: 'المبيعات بالساعة',
    chartLabels: const [],
  );
}

ManagerReportSnapshot buildManagerReport({
  required List<Order> orders,
  required List<ShiftSession> shifts,
  required DateTime now,
  List<ManagerAlert> alerts = const [],
  bool live = false,
  ManagerReportPeriod period = ManagerReportPeriod.live,
}) {
  final window = managerPeriodWindow(period, now);

  bool inRange(Order order, DateTime from, DateTime to) {
    final t = order.createdAt.toLocal();
    return !t.isBefore(from) && t.isBefore(to);
  }

  final scoped = orders
      .where((o) => inRange(o, window.from, window.to))
      .toList();
  final compare = orders
      .where((o) => inRange(o, window.compareFrom, window.compareTo))
      .toList();

  double netOf(List<Order> list) => list
      .where((o) => o.status != OrderStatus.cancelled)
      .fold(0.0, (sum, o) => sum + o.totalPrice);

  final net = netOf(scoped);
  final lastNet = netOf(compare);
  final weekDelta = lastNet <= 0
      ? (net > 0 ? 100.0 : 0.0)
      : ((net - lastNet) / lastNet) * 100;

  var cash = 0.0;
  var knet = 0.0;
  var voids = 0.0;
  var voidCount = 0;
  var dineIn = 0.0;
  var takeaway = 0.0;
  var delivery = 0.0;
  var website = 0.0;
  var pos = 0.0;
  final hourly = List<double>.filled(window.bucketCount, 0);
  final itemQty = <String, int>{};
  final itemRev = <String, double>{};

  final counted = scoped.where((o) => o.status != OrderStatus.cancelled);
  for (final order in counted) {
    final bucket = managerBucketIndex(order.createdAt, window);
    hourly[bucket] += order.totalPrice;
    if (_isCash(order.paymentMethod)) {
      cash += order.totalPrice;
    } else {
      knet += order.totalPrice;
    }
    if (isHallTableOrder(order)) {
      dineIn += order.totalPrice;
    } else if (_isWebsite(order)) {
      website += order.totalPrice;
    } else if (order.createdFromPos || isPosOrderSource(order.orderSource)) {
      pos += order.totalPrice;
    } else {
      switch (order.orderType) {
        case OrderType.dineIn:
          dineIn += order.totalPrice;
        case OrderType.pickup:
          takeaway += order.totalPrice;
        case OrderType.delivery:
          delivery += order.totalPrice;
      }
    }
    for (final line in order.items) {
      final name = line.name.trim().isEmpty ? 'صنف' : line.name.trim();
      itemQty[name] = (itemQty[name] ?? 0) + line.quantity;
      itemRev[name] = (itemRev[name] ?? 0) + line.lineTotal;
    }
  }

  for (final order in scoped.where((o) => o.status == OrderStatus.cancelled)) {
    voidCount += 1;
    voids += order.totalPrice;
  }

  final orderCount = counted.length;
  final avg = orderCount == 0 ? 0.0 : net / orderCount;

  final top = itemRev.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  final topItems = top
      .take(5)
      .map(
        (e) => ManagerTopItem(
          name: e.key,
          quantity: itemQty[e.key] ?? 0,
          revenue: e.value,
        ),
      )
      .toList();

  final recent = List<Order>.from(scoped)
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  final recentOrders = recent
      .take(12)
      .map(
        (order) => ManagerRecentOrder(
          id: order.id,
          title: order.invoiceNumber?.trim().isNotEmpty == true
              ? '#${order.invoiceNumber}'
              : order.customerName,
          channel: _channelLabel(order),
          total: order.totalPrice,
          createdAt: order.createdAt,
        ),
      )
      .toList();

  return ManagerReportSnapshot(
    netSales: net,
    cashSales: cash,
    knetSales: knet,
    orderCount: orderCount,
    weekDeltaPercent: weekDelta,
    avgTicket: avg,
    voidedAmount: voids,
    voidCount: voidCount,
    hourlySales: hourly,
    channels: [
      ManagerChannelSlice(
        id: 'dineIn',
        label: 'صالة',
        value: dineIn,
        color: 0xFF6B1124,
      ),
      ManagerChannelSlice(
        id: 'takeaway',
        label: 'سفري',
        value: takeaway,
        color: 0xFFD49A00,
      ),
      ManagerChannelSlice(
        id: 'delivery',
        label: 'توصيل',
        value: delivery,
        color: 0xFF2563EB,
      ),
      ManagerChannelSlice(
        id: 'pos',
        label: 'كاشير',
        value: pos,
        color: 0xFF7C3AED,
      ),
      ManagerChannelSlice(
        id: 'website',
        label: 'الموقع',
        value: website,
        color: 0xFF059669,
      ),
    ],
    topItems: topItems,
    openShifts: shifts.where((s) => s.isOpen).toList(),
    alerts: alerts,
    recentOrders: recentOrders,
    updatedAt: now,
    live: live && period.isLive,
    period: period,
    salesTitle: period.salesTitle,
    comparisonLabel: managerComparisonLabel(period),
    chartTitle: period.chartTitle,
    chartLabels: [
      for (var i = 0; i < window.bucketCount; i++)
        managerBucketLabel(i, window),
    ],
  );
}

bool _isCash(String? method) {
  final raw = (method ?? '').trim().toLowerCase();
  return raw.contains('cash') || raw.contains('كاش') || raw.contains('نقد');
}

bool _channelLabelForWebsite(Order order) => _isWebsite(order);

String _channelLabel(Order order) {
  if (isHallTableOrder(order)) return 'صالة';
  if (order.createdFromPos || isPosOrderSource(order.orderSource)) {
    return 'كاشير';
  }
  if (_channelLabelForWebsite(order)) return 'الموقع';
  return switch (order.orderType) {
    OrderType.dineIn => 'صالة',
    OrderType.pickup => 'سفري',
    OrderType.delivery => 'توصيل',
  };
}

bool _isWebsite(Order order) {
  if (isHallTableOrder(order)) return false;
  final src = (order.orderSource ?? '').trim().toLowerCase();
  return src.contains('web') ||
      src.contains('site') ||
      src.contains('qr') ||
      src.contains('menu') ||
      src.contains('online');
}

List<ManagerAlert> detectManagerAlerts({
  required List<Order> previous,
  required List<Order> next,
  required List<ShiftSession> previousShifts,
  required List<ShiftSession> nextShifts,
}) {
  if (previous.isEmpty && previousShifts.isEmpty) return const [];
  final alerts = <ManagerAlert>[];
  final prevIds = {for (final o in previous) o.id: o};

  for (final order in next) {
    final before = prevIds[order.id];
    if (before == null &&
        !order.createdFromPos &&
        !isPosOrderSource(order.orderSource)) {
      alerts.add(
        ManagerAlert(
          id: 'new-${order.id}',
          title: isPosOrderSource(order.orderSource)
              ? 'طلب كاشير جديد'
              : 'طلب جديد',
          body:
              '${_channelLabel(order)} — ${order.totalPrice.toStringAsFixed(3)} د.ك'
              '${order.cashierName == null || order.cashierName!.trim().isEmpty ? '' : ' (${order.cashierName})'}',
          kind: ManagerAlertKind.newOrder,
        ),
      );
    }
    final becameVoid =
        order.status == OrderStatus.cancelled &&
        (before == null || before.status != OrderStatus.cancelled);
    if (becameVoid) {
      alerts.add(
        ManagerAlert(
          id: 'void-${order.id}',
          title: 'إلغاء طلب',
          body:
              'تم إلغاء طلب ${order.invoiceNumber ?? order.id} '
              '(${order.totalPrice.toStringAsFixed(3)} د.ك)',
          kind: ManagerAlertKind.voidOrder,
        ),
      );
    }
    final discount = order.discountAmount ?? 0;
    final prevDiscount = before?.discountAmount ?? 0;
    if (discount > 0.001 && discount > prevDiscount + 0.001) {
      alerts.add(
        ManagerAlert(
          id: 'disc-${order.id}-$discount',
          title: 'خصم مخصص',
          body:
              'خصم ${discount.toStringAsFixed(3)} د.ك على طلب '
              '${order.invoiceNumber ?? order.id}',
          kind: ManagerAlertKind.discount,
        ),
      );
    }
  }

  final prevOpen = {
    for (final s in previousShifts.where((s) => s.isOpen)) s.id: s,
  };
  for (final shift in nextShifts.where((s) => !s.isOpen)) {
    if (prevOpen.containsKey(shift.id)) {
      alerts.add(
        ManagerAlert(
          id: 'shift-${shift.id}',
          title: 'إغلاق وردية',
          body: 'أُغلقت وردية ${shift.cashierName}',
          kind: ManagerAlertKind.shiftClosed,
        ),
      );
    }
  }
  return alerts;
}
