import 'package:flutter/widgets.dart';

import 'package:almenupro/l10n/app_strings.dart';

/// When false, POS must collect customer name + phone (delivery-like flows).
bool posCustomerContactRequired({
  required bool isDineIn,
  required String orderMode,
  required bool isExternalPlatform,
}) {
  if (isDineIn) return false;
  if (orderMode == 'delivery' || orderMode == 'scheduled') return true;
  // Platform orders (Talabat, Keeta, …): contact lives on the platform, not POS.
  if (orderMode == 'platforms' && isExternalPlatform) return false;
  return false;
}

String posDefaultCustomerPhone(String raw) {
  final value = raw.trim();
  final digits = value.replaceAll(RegExp(r'\D'), '');
  if (digits.length >= 8) return value;
  return '00000000';
}

String posDefaultCustomerName({
  required BuildContext context,
  required String raw,
  required bool isDineIn,
  String? tableDisplayName,
  required bool contactOptional,
  bool isExternalPlatform = false,
}) {
  final trimmed = raw.trim();
  if (trimmed.isNotEmpty) return trimmed;
  if (!contactOptional) return trimmed;
  if (isDineIn) {
    return (tableDisplayName?.trim().isNotEmpty ?? false)
        ? tableDisplayName!.trim()
        : 'طاولة';
  }
  if (isExternalPlatform) {
    return AppStrings.read(context).tr('طلب منصة', 'Platform order');
  }
  return AppStrings.read(context).tr('استلام من المحل', 'Walk-in pickup');
}

bool posShouldPersistCustomerProfile({
  required bool contactOptional,
  required String phone,
  required String name,
}) {
  if (contactOptional) {
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    return digits.length >= 8 && name.trim().isNotEmpty;
  }
  return true;
}