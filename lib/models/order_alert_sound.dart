enum OrderAlertSoundType {
  bell('bell', 'جرس', 'صوت جرس كلاسيكي'),
  soft('soft', 'تنبيه خفيف', 'نغمة قصيرة وهادئة'),
  alarm('alarm', 'صفارة إنذار', 'تنبيه قوي للطلبات العاجلة');

  const OrderAlertSoundType(this.storageKey, this.label, this.description);

  final String storageKey;
  final String label;
  final String description;

  static OrderAlertSoundType fromStorageKey(String? key) {
    return OrderAlertSoundType.values.firstWhere(
      (type) => type.storageKey == key,
      orElse: () => OrderAlertSoundType.bell,
    );
  }
}
