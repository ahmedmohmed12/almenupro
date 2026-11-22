class HrRestaurantJobs {
  HrRestaurantJobs._();

  static const cashier = 'كاشير';

  static const presetJobs = <String>[
    cashier,
    'نادل',
    'طباخ',
    'مساعد مطبخ',
    'مدير فرع',
    'محاسب',
    'عامل توصيل',
    'عامل نظافة',
    'أخرى',
  ];

  static bool isCashierJob(String jobTitle) {
    final normalized = jobTitle.trim().toLowerCase();
    return normalized == cashier ||
        normalized == 'cashier' ||
        normalized.contains('كاشير');
  }
}