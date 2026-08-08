import 'package:flutter/material.dart';

import 'api_service.dart';

bool isWebUrl(String input) {
  final trimmed = input.trim().toLowerCase();
  return trimmed.startsWith('http://') || trimmed.startsWith('https://');
}

bool isTalabatMenuUrl(String input) {
  return isWebUrl(input) && input.trim().toLowerCase().contains('talabat');
}

Future<void> processAndSaveTalabatMenu({
  required String url,
  required void Function(String message) onProgress,
  required void Function(int added, int skipped, int updated) onComplete,
  String? restaurantId,
}) async {
  final normalizedUrl = url.trim();

  if (normalizedUrl.isEmpty) {
    onProgress('يرجى إدخال رابط صحيح أولاً');
    onComplete(0, 0, 0);
    return;
  }

  if (!isTalabatMenuUrl(normalizedUrl)) {
    onProgress('استخدم رابط Talabat (طلبات) الصحيح');
    onComplete(0, 0, 0);
    return;
  }

  final targetRestaurantId = restaurantId ?? ApiService.defaultRestaurantId;

  try {
    onProgress('جاري سحب الأصناف والأسعار والصور من Talabat على السيرفر...');

    final result = await ApiService.instance.importTalabatMenu(
      url: normalizedUrl,
      restaurantId: targetRestaurantId,
    );

    if (result.synced == 0) {
      onProgress('لم يتم العثور على أصناف في هذا الرابط');
      onComplete(0, 0, 0);
      return;
    }

    onProgress(
      'تم الاستيراد: ${result.added} جديد، ${result.updated} محدّث '
      '(${result.total} صنف في المنيو)',
    );
    onComplete(result.added, result.skipped, result.updated);
  } catch (error) {
    debugPrint('Talabat import error: $error');
    onProgress(error.toString().replaceFirst('Exception: ', ''));
    onComplete(0, 0, 0);
  }
}
