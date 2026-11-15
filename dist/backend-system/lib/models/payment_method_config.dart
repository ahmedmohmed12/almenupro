class PaymentMethodConfig {
  const PaymentMethodConfig({
    required this.id,
    required this.storageValue,
    required this.nameAr,
    required this.nameEn,
    this.enabled = true,
    this.isBuiltIn = false,
  });

  final String id;
  final String storageValue;
  final String nameAr;
  final String nameEn;
  final bool enabled;
  final bool isBuiltIn;

  String labelFor(String localeCode) =>
      localeCode.startsWith('ar') ? nameAr : nameEn;

  PaymentMethodConfig copyWith({
    String? id,
    String? storageValue,
    String? nameAr,
    String? nameEn,
    bool? enabled,
    bool? isBuiltIn,
  }) {
    return PaymentMethodConfig(
      id: id ?? this.id,
      storageValue: storageValue ?? this.storageValue,
      nameAr: nameAr ?? this.nameAr,
      nameEn: nameEn ?? this.nameEn,
      enabled: enabled ?? this.enabled,
      isBuiltIn: isBuiltIn ?? this.isBuiltIn,
    );
  }

  factory PaymentMethodConfig.fromJson(Map<String, dynamic> json) {
    return PaymentMethodConfig(
      id: (json['id'] ?? json['key'] ?? '').toString().trim(),
      storageValue: (json['storageValue'] ??
              json['storage_value'] ??
              json['value'] ??
              json['id'] ??
              '')
          .toString()
          .trim(),
      nameAr: (json['nameAr'] ?? json['name_ar'] ?? json['name'] ?? '')
          .toString()
          .trim(),
      nameEn: (json['nameEn'] ?? json['name_en'] ?? json['name'] ?? '')
          .toString()
          .trim(),
      enabled: json['enabled'] != false,
      isBuiltIn: json['isBuiltIn'] == true || json['is_built_in'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'storageValue': storageValue,
        'nameAr': nameAr,
        'nameEn': nameEn,
        'enabled': enabled,
        'isBuiltIn': isBuiltIn,
      };

  static List<PaymentMethodConfig> defaults() => const [
        PaymentMethodConfig(
          id: 'cash',
          storageValue: 'كاش',
          nameAr: 'كاش (Cash)',
          nameEn: 'Cash',
          enabled: true,
          isBuiltIn: true,
        ),
        PaymentMethodConfig(
          id: 'knet',
          storageValue: 'K-Net',
          nameAr: 'K-Net / كي نت',
          nameEn: 'K-Net',
          enabled: true,
          isBuiltIn: true,
        ),
        PaymentMethodConfig(
          id: 'wallet',
          storageValue: 'wallet',
          nameAr: 'محفظة',
          nameEn: 'Wallet',
          enabled: false,
          isBuiltIn: true,
        ),
      ];
}

class PaymentMethodCatalog {
  PaymentMethodCatalog._();

  static List<PaymentMethodConfig> mergeWithDefaults(
    List<PaymentMethodConfig>? raw,
  ) {
    if (raw == null || raw.isEmpty) return enabledOnly(PaymentMethodConfig.defaults());
    final byId = {for (final method in PaymentMethodConfig.defaults()) method.id: method};
    for (final method in raw) {
      if (method.id.isEmpty) continue;
      byId[method.id] = method;
    }
    return enabledOnly([
      for (final builtin in PaymentMethodConfig.defaults())
        byId.remove(builtin.id) ?? builtin,
      ...byId.values,
    ]);
  }

  static List<PaymentMethodConfig> enabledOnly(List<PaymentMethodConfig> methods) =>
      methods.where((method) => method.enabled).toList();

  static String normalizeStorageValue(
    String? raw,
    List<PaymentMethodConfig> methods,
  ) {
    final enabled = enabledOnly(methods);
    if (enabled.isEmpty) return 'كاش';

    final value = (raw ?? '').trim().toLowerCase();
    if (value.isEmpty) return enabled.first.storageValue;

    for (final method in enabled) {
      if (method.storageValue.toLowerCase() == value) {
        return method.storageValue;
      }
      if (method.id.toLowerCase() == value) {
        return method.storageValue;
      }
    }

    if (value.contains('k-net') ||
        value.contains('knet') ||
        value.contains('كي') ||
        value.contains('ك-net')) {
      return _firstById(enabled, 'knet')?.storageValue ?? enabled.first.storageValue;
    }
    if (value.contains('wallet') || value.contains('محفظ')) {
      return _firstById(enabled, 'wallet')?.storageValue ?? enabled.first.storageValue;
    }
    if (value.contains('cash') ||
        value.contains('كاش') ||
        value.contains('نقد') ||
        value.contains('cash')) {
      return _firstById(enabled, 'cash')?.storageValue ?? enabled.first.storageValue;
    }

    return enabled.first.storageValue;
  }

  static PaymentMethodConfig? _firstById(
    List<PaymentMethodConfig> methods,
    String id,
  ) {
    for (final method in methods) {
      if (method.id == id) return method;
    }
    return null;
  }
}
