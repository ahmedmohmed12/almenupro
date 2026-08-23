class ExpenseRecord {
  const ExpenseRecord({
    required this.id,
    required this.title,
    required this.category,
    required this.amount,
    required this.date,
    this.notes = '',
  });

  final String id;
  final String title;
  final String category;
  final double amount;
  final String date;
  final String notes;

  factory ExpenseRecord.fromJson(Map<String, dynamic> json) {
    return ExpenseRecord(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      category: json['category']?.toString() ?? 'other',
      amount: (json['amount'] as num?)?.toDouble() ?? 0,
      date: json['date']?.toString() ?? '',
      notes: json['notes']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'title': title,
        'category': category,
        'amount': amount,
        'date': date,
        if (notes.trim().isNotEmpty) 'notes': notes.trim(),
      };
}

const expenseCategoryKeys = [
  'suppliers',
  'salaries',
  'rent',
  'utilities',
  'maintenance',
  'other',
];

String expenseCategoryLabel(String key) {
  switch (key) {
    case 'suppliers':
      return 'الموردون';
    case 'salaries':
      return 'الرواتب';
    case 'rent':
      return 'الإيجار';
    case 'utilities':
      return 'الخدمات';
    case 'maintenance':
      return 'الصيانة';
    default:
      return 'أخرى';
  }
}

class PnlCategoryShare {
  const PnlCategoryShare({
    required this.category,
    required this.amount,
    required this.sharePercent,
  });

  final String category;
  final double amount;
  final double sharePercent;

  factory PnlCategoryShare.fromJson(Map<String, dynamic> json) {
    return PnlCategoryShare(
      category: json['category']?.toString() ?? 'other',
      amount: (json['amount'] as num?)?.toDouble() ?? 0,
      sharePercent: (json['sharePercent'] as num?)?.toDouble() ?? 0,
    );
  }
}

class PnlDayPoint {
  const PnlDayPoint({
    required this.date,
    required this.revenue,
    required this.expenses,
    required this.net,
    this.orders = 0,
  });

  final String date;
  final double revenue;
  final double expenses;
  final double net;
  final int orders;

  factory PnlDayPoint.fromJson(Map<String, dynamic> json) {
    return PnlDayPoint(
      date: json['date']?.toString() ?? '',
      revenue: (json['revenue'] as num?)?.toDouble() ?? 0,
      expenses: (json['expenses'] as num?)?.toDouble() ?? 0,
      net: (json['net'] as num?)?.toDouble() ?? 0,
      orders: (json['orders'] as num?)?.toInt() ?? 0,
    );
  }
}

class PnlReport {
  const PnlReport({
    this.days = 30,
    this.orders = 0,
    this.grossRevenue = 0,
    this.netRevenue = 0,
    this.commission = 0,
    this.totalExpenses = 0,
    this.netProfit = 0,
    this.marginPercent = 0,
    this.expenseRatio = 0,
    this.health = 'no_data',
    this.categories = const [],
    this.series = const [],
  });

  final int days;
  final int orders;
  final double grossRevenue;
  final double netRevenue;
  final double commission;
  final double totalExpenses;
  final double netProfit;
  final double marginPercent;
  final double expenseRatio;
  final String health;
  final List<PnlCategoryShare> categories;
  final List<PnlDayPoint> series;

  factory PnlReport.fromJson(Map<String, dynamic> json) {
    final summary = json['summary'] is Map
        ? Map<String, dynamic>.from(json['summary'] as Map)
        : <String, dynamic>{};
    return PnlReport(
      days: (json['days'] as num?)?.toInt() ?? 30,
      orders: (summary['orders'] as num?)?.toInt() ?? 0,
      grossRevenue: (summary['grossRevenue'] as num?)?.toDouble() ?? 0,
      netRevenue: (summary['netRevenue'] as num?)?.toDouble() ?? 0,
      commission: (summary['commission'] as num?)?.toDouble() ?? 0,
      totalExpenses: (summary['totalExpenses'] as num?)?.toDouble() ?? 0,
      netProfit: (summary['netProfit'] as num?)?.toDouble() ?? 0,
      marginPercent: (summary['marginPercent'] as num?)?.toDouble() ?? 0,
      expenseRatio: (summary['expenseRatio'] as num?)?.toDouble() ?? 0,
      health: summary['health']?.toString() ?? 'no_data',
      categories: (json['categories'] as List? ?? const [])
          .whereType<Map>()
          .map((row) => PnlCategoryShare.fromJson(Map<String, dynamic>.from(row)))
          .toList(),
      series: (json['series'] as List? ?? const [])
          .whereType<Map>()
          .map((row) => PnlDayPoint.fromJson(Map<String, dynamic>.from(row)))
          .toList(),
    );
  }
}
