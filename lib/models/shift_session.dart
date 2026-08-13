class ShiftSummary {
  const ShiftSummary({
    this.orderCount = 0,
    this.voidCount = 0,
    this.refundCount = 0,
    this.cashSales = 0,
    this.knetSales = 0,
    this.electronicSales = 0,
    this.grossSales = 0,
    this.discountTotal = 0,
    this.refundTotal = 0,
    this.expectedCash = 0,
    this.actualCash = 0,
    this.discrepancy = 0,
    this.discrepancyType = 'balanced',
  });

  final int orderCount;
  final int voidCount;
  final int refundCount;
  final double cashSales;
  final double knetSales;
  final double electronicSales;
  final double grossSales;
  final double discountTotal;
  final double refundTotal;
  final double expectedCash;
  final double actualCash;
  final double discrepancy;
  final String discrepancyType;

  String get discrepancyLabelAr => switch (discrepancyType) {
        'shortage' => 'عجز',
        'surplus' => 'فائض',
        _ => 'مطابق',
      };

  factory ShiftSummary.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const ShiftSummary();
    return ShiftSummary(
      orderCount: (json['orderCount'] as num?)?.toInt() ??
          (json['order_count'] as num?)?.toInt() ??
          0,
      voidCount: (json['voidCount'] as num?)?.toInt() ??
          (json['void_count'] as num?)?.toInt() ??
          0,
      refundCount: (json['refundCount'] as num?)?.toInt() ??
          (json['refund_count'] as num?)?.toInt() ??
          0,
      cashSales: (json['cashSales'] as num?)?.toDouble() ??
          (json['cash_sales'] as num?)?.toDouble() ??
          0,
      knetSales: (json['knetSales'] as num?)?.toDouble() ??
          (json['knet_sales'] as num?)?.toDouble() ??
          0,
      electronicSales: (json['electronicSales'] as num?)?.toDouble() ??
          (json['electronic_sales'] as num?)?.toDouble() ??
          0,
      grossSales: (json['grossSales'] as num?)?.toDouble() ??
          (json['gross_sales'] as num?)?.toDouble() ??
          0,
      discountTotal: (json['discountTotal'] as num?)?.toDouble() ??
          (json['discount_total'] as num?)?.toDouble() ??
          0,
      refundTotal: (json['refundTotal'] as num?)?.toDouble() ??
          (json['refund_total'] as num?)?.toDouble() ??
          0,
      expectedCash: (json['expectedCash'] as num?)?.toDouble() ??
          (json['expected_cash'] as num?)?.toDouble() ??
          0,
      actualCash: (json['actualCash'] as num?)?.toDouble() ??
          (json['actual_cash'] as num?)?.toDouble() ??
          0,
      discrepancy: (json['discrepancy'] as num?)?.toDouble() ?? 0,
      discrepancyType:
          json['discrepancyType']?.toString() ?? json['discrepancy_type']?.toString() ?? 'balanced',
    );
  }
}

class ShiftSession {
  const ShiftSession({
    required this.id,
    required this.cashierId,
    required this.cashierName,
    required this.status,
    required this.openedAt,
    this.roleId = '',
    this.closedAt,
    this.openingFloat = 0,
    this.closingCashCounted,
    this.notes = '',
    this.summary = const ShiftSummary(),
    this.closedById,
    this.closedByName,
  });

  final String id;
  final String cashierId;
  final String cashierName;
  final String roleId;
  final String status;
  final DateTime openedAt;
  final DateTime? closedAt;
  final double openingFloat;
  final double? closingCashCounted;
  final String notes;
  final ShiftSummary summary;
  final String? closedById;
  final String? closedByName;

  bool get isOpen => status.toLowerCase() == 'open';

  double get cashCollected =>
      closingCashCounted ?? summary.actualCash;

  factory ShiftSession.fromJson(Map<String, dynamic> json) {
    return ShiftSession(
      id: json['id']?.toString() ?? '',
      cashierId: json['cashierId']?.toString() ?? json['cashier_id']?.toString() ?? '',
      cashierName: json['cashierName']?.toString() ?? json['cashier_name']?.toString() ?? '',
      roleId: json['roleId']?.toString() ?? json['role_id']?.toString() ?? '',
      status: json['status']?.toString() ?? 'open',
      openedAt: DateTime.tryParse(json['openedAt']?.toString() ?? '') ?? DateTime.now().toUtc(),
      closedAt: DateTime.tryParse(json['closedAt']?.toString() ?? json['closed_at']?.toString() ?? ''),
      openingFloat: (json['openingFloat'] as num?)?.toDouble() ??
          (json['opening_float'] as num?)?.toDouble() ??
          0,
      closingCashCounted: json['closingCashCounted'] == null && json['closing_cash_counted'] == null
          ? null
          : (json['closingCashCounted'] as num?)?.toDouble() ??
              (json['closing_cash_counted'] as num?)?.toDouble(),
      notes: json['notes']?.toString() ?? '',
      summary: ShiftSummary.fromJson(
        json['summary'] is Map ? Map<String, dynamic>.from(json['summary'] as Map) : null,
      ),
      closedById: json['closedById']?.toString() ?? json['closed_by_id']?.toString(),
      closedByName: json['closedByName']?.toString() ?? json['closed_by_name']?.toString(),
    );
  }
}

class ShiftReportsMeta {
  const ShiftReportsMeta({
    this.totalShifts = 0,
    this.openShifts = 0,
    this.closedShifts = 0,
    this.grossSales = 0,
    this.dataState = '',
    this.openCount = 0,
    this.ordersInRange = 0,
    this.ordersWithoutShift = 0,
  });

  final int totalShifts;
  final int openShifts;
  final int closedShifts;
  final double grossSales;
  final String dataState;
  final int openCount;
  final int ordersInRange;
  final int ordersWithoutShift;

  factory ShiftReportsMeta.fromJson(Map<String, dynamic> json) {
    final openShifts = (json['openShifts'] as num?)?.toInt() ??
        (json['open_shifts'] as num?)?.toInt() ??
        (json['openCount'] as num?)?.toInt() ??
        0;
    return ShiftReportsMeta(
      totalShifts: (json['totalShifts'] as num?)?.toInt() ??
          (json['total_shifts'] as num?)?.toInt() ??
          0,
      openShifts: openShifts,
      closedShifts: (json['closedShifts'] as num?)?.toInt() ??
          (json['closed_shifts'] as num?)?.toInt() ??
          0,
      grossSales: (json['grossSales'] as num?)?.toDouble() ??
          (json['gross_sales'] as num?)?.toDouble() ??
          0,
      dataState: json['dataState']?.toString() ??
          json['data_state']?.toString() ??
          '',
      openCount: (json['openCount'] as num?)?.toInt() ??
          (json['open_count'] as num?)?.toInt() ??
          openShifts,
      ordersInRange: (json['ordersInRange'] as num?)?.toInt() ??
          (json['orders_in_range'] as num?)?.toInt() ??
          0,
      ordersWithoutShift: (json['ordersWithoutShift'] as num?)?.toInt() ??
          (json['orders_without_shift'] as num?)?.toInt() ??
          0,
    );
  }
}

class ShiftReportsResult {
  const ShiftReportsResult({
    this.shifts = const [],
    this.meta = const ShiftReportsMeta(),
  });

  final List<ShiftSession> shifts;
  final ShiftReportsMeta meta;

  List<ShiftSession> get openShifts =>
      shifts.where((shift) => shift.isOpen).toList();

  List<ShiftSession> get closedShifts =>
      shifts.where((shift) => !shift.isOpen).toList();
}
