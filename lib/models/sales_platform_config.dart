import 'package:flutter/material.dart';

/// Configurable sales channel (POS local or delivery platform).
class SalesPlatformConfig {
  const SalesPlatformConfig({
    required this.id,
    required this.name,
    this.commissionPercent = 0,
    this.colorArgb = 0xFF475569,
    this.isBuiltIn = false,
  });

  final String id;
  final String name;
  final double commissionPercent;
  final int colorArgb;
  final bool isBuiltIn;

  bool get isLocal => id == 'pos';
  bool get isExternal => !isLocal;

  Color get color => Color(colorArgb);

  IconData get icon {
    switch (id) {
      case 'pos':
        return Icons.storefront_rounded;
      case 'talabat':
        return Icons.delivery_dining_rounded;
      case 'keeta':
        return Icons.two_wheeler_rounded;
      case 'jahez':
        return Icons.moped_rounded;
      default:
        return Icons.hub_rounded;
    }
  }

  String get storageKey => id;

  SalesPlatformConfig copyWith({
    String? id,
    String? name,
    double? commissionPercent,
    int? colorArgb,
    bool? isBuiltIn,
  }) {
    return SalesPlatformConfig(
      id: id ?? this.id,
      name: name ?? this.name,
      commissionPercent: commissionPercent ?? this.commissionPercent,
      colorArgb: colorArgb ?? this.colorArgb,
      isBuiltIn: isBuiltIn ?? this.isBuiltIn,
    );
  }

  factory SalesPlatformConfig.fromJson(Map<String, dynamic> json) {
    return SalesPlatformConfig(
      id: (json['id'] ?? json['key'] ?? '').toString().trim(),
      name: (json['name'] ?? json['label'] ?? '').toString().trim(),
      commissionPercent:
          (json['commissionPercent'] as num?)?.toDouble() ??
              (json['commission_percent'] as num?)?.toDouble() ??
              0,
      colorArgb: _parseColor(json['color'] ?? json['colorArgb'] ?? json['color_argb']),
      isBuiltIn: json['isBuiltIn'] == true || json['is_built_in'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'commissionPercent': commissionPercent,
        'color': '#${colorArgb.toRadixString(16).padLeft(8, '0').substring(2)}',
        'isBuiltIn': isBuiltIn,
      };

  static List<SalesPlatformConfig> defaults() => const [
        SalesPlatformConfig(
          id: 'pos',
          name: 'محلي / POS',
          commissionPercent: 0,
          colorArgb: 0xFF6B1124,
          isBuiltIn: true,
        ),
        SalesPlatformConfig(
          id: 'talabat',
          name: 'Talabat',
          commissionPercent: 15,
          colorArgb: 0xFFFF5A00,
          isBuiltIn: true,
        ),
        SalesPlatformConfig(
          id: 'keeta',
          name: 'Keeta',
          commissionPercent: 12,
          colorArgb: 0xFF00A651,
          isBuiltIn: true,
        ),
        SalesPlatformConfig(
          id: 'jahez',
          name: 'Jahez',
          commissionPercent: 12,
          colorArgb: 0xFFE4002B,
          isBuiltIn: true,
        ),
      ];

  static int _parseColor(dynamic raw) {
    if (raw is int) return raw;
    final text = raw?.toString().trim() ?? '';
    if (text.startsWith('#')) {
      final hex = text.substring(1);
      if (hex.length == 6) {
        return int.parse('FF$hex', radix: 16);
      }
      if (hex.length == 8) {
        return int.parse(hex, radix: 16);
      }
    }
    final parsed = int.tryParse(text);
    if (parsed != null) return parsed;
    return 0xFF475569;
  }
}

class PlatformCatalog {
  PlatformCatalog._();

  static List<SalesPlatformConfig> mergeWithDefaults(List<SalesPlatformConfig>? raw) {
    if (raw == null || raw.isEmpty) return SalesPlatformConfig.defaults();
    final byId = {for (final p in SalesPlatformConfig.defaults()) p.id: p};
    for (final platform in raw) {
      if (platform.id.isEmpty) continue;
      byId[platform.id] = platform;
    }
    final defaults = SalesPlatformConfig.defaults();
    final ordered = <SalesPlatformConfig>[];
    for (final builtin in defaults) {
      ordered.add(byId.remove(builtin.id) ?? builtin);
    }
    ordered.addAll(byId.values);
    return ordered;
  }

  static SalesPlatformConfig resolve(String? source, List<SalesPlatformConfig> platforms) {
    final key = (source ?? 'pos').trim().toLowerCase();
    for (final platform in platforms) {
      if (platform.id.toLowerCase() == key) return platform;
    }
    if (key.contains('talabat')) {
      return platforms.firstWhere((p) => p.id == 'talabat', orElse: () => _fallback(key));
    }
    if (key.contains('keeta')) {
      return platforms.firstWhere((p) => p.id == 'keeta', orElse: () => _fallback(key));
    }
    if (key.contains('jahez')) {
      return platforms.firstWhere((p) => p.id == 'jahez', orElse: () => _fallback(key));
    }
    if (key == 'other_platform' || key == 'other') {
      return platforms.firstWhere(
        (p) => p.id == 'other' || p.id == 'other_platform',
        orElse: () => SalesPlatformConfig(
          id: key,
          name: 'منصة أخرى',
          commissionPercent: 10,
          colorArgb: 0xFF475569,
        ),
      );
    }
    return platforms.firstWhere((p) => p.isLocal, orElse: () => SalesPlatformConfig.defaults().first);
  }

  static SalesPlatformConfig _fallback(String id) => SalesPlatformConfig(
        id: id,
        name: id,
        commissionPercent: 10,
        colorArgb: 0xFF475569,
      );

  static List<SalesPlatformConfig> posSelectable(List<SalesPlatformConfig> platforms) =>
      platforms;

  static List<SalesPlatformConfig> externalOnly(List<SalesPlatformConfig> platforms) =>
      platforms.where((p) => p.isExternal).toList();
}
