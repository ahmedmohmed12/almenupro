import 'package:flutter/material.dart';

import 'api_service.dart';

bool isWebUrl(String input) {
  final trimmed = input.trim().toLowerCase();
  return trimmed.startsWith('http://') || trimmed.startsWith('https://');
}

bool isTalabatMenuUrl(String input) {
  return isWebUrl(input) && input.trim().toLowerCase().contains('talabat');
}

Future<bool> processAndSaveTalabatMenu({
  required String url,
  required void Function(String message) onProgress,
  required void Function(int added, int skipped, int updated) onComplete,
  String? restaurantId,
  String? talabatCookie,
  String? nextData,
}) async {
  final normalizedUrl = url.trim();

  if (normalizedUrl.isEmpty) {
    onProgress('يرجى إدخال رابط صحيح أولاً');
    return false;
  }

  if (!isTalabatMenuUrl(normalizedUrl)) {
    onProgress('استخدم رابط Talabat (طلبات) الصحيح');
    return false;
  }

  final targetRestaurantId = restaurantId ?? ApiService.defaultRestaurantId;

  try {
    onProgress('جاري سحب الأصناف والأسعار والصور من Talabat على السيرفر...');

    final result = await ApiService.instance.importTalabatMenu(
      url: normalizedUrl,
      restaurantId: targetRestaurantId,
      talabatCookie: talabatCookie,
      nextData: nextData,
    );

    if (result.synced == 0 && result.added == 0 && result.updated == 0) {
      onProgress('لم يتم العثور على أصناف في هذا الرابط');
      return false;
    }

    onProgress(
      'تم الاستيراد: ${result.added} جديد، ${result.updated} محدّث '
      '(${result.total} صنف في المنيو)',
    );
    onComplete(result.added, result.skipped, result.updated);
    return true;
  } catch (error) {
    debugPrint('Talabat import error: $error');
    onProgress(error.toString().replaceFirst('Exception: ', ''));
    return false;
  }
}
