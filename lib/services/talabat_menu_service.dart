import 'package:flutter/material.dart';

import '../utils/talabat_manual_menu_json.dart';
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
  String? menuJson,
}) async {
  final manual = (menuJson ?? nextData ?? '').trim();
  var normalizedUrl = url.trim();
  if (normalizedUrl.isEmpty && manual.isNotEmpty) {
    normalizedUrl = menuUrlFromManualTalabatJson(manual) ?? '';
  }
  if (normalizedUrl.isEmpty && looksLikeTalabatMenuPaste(manual)) {
    normalizedUrl = 'https://www.talabat.com/';
  }

  if (normalizedUrl.isEmpty) {
    onProgress('ألصق بيانات المنيو من Talabat أو أدخل رابط صفحة المطعم');
    return false;
  }

  final hasPaste = manual.isNotEmpty && looksLikeTalabatMenuPaste(manual);
  if (!hasPaste && !isTalabatMenuUrl(normalizedUrl)) {
    onProgress('استخدم رابط صفحة المطعم على Talabat أو الصق البيانات المنسوخة');
    return false;
  }

  final targetRestaurantId = restaurantId ?? ApiService.defaultRestaurantId;

  try {
    onProgress(
      hasPaste
          ? 'جاري إضافة الأصناف وحفظ الصور على السيرفر…'
          : 'جاري سحب المنيو من Talabat (قد يفشل إن كان الموقع محجوباً)…',
    );

    final result = await ApiService.instance.importTalabatMenu(
      url: normalizedUrl,
      restaurantId: targetRestaurantId,
      talabatCookie: talabatCookie,
      nextData: nextData,
      menuJson: menuJson ?? nextData,
    );

    if (result.synced == 0 && result.added == 0 && result.updated == 0) {
      onProgress('لم يتم العثور على أصناف — تأكد من لصق البيانات كاملة');
      return false;
    }

    onComplete(result.added, result.skipped, result.updated);
    return true;
  } catch (error) {
    debugPrint('Talabat import error: $error');
    onProgress(error.toString().replaceFirst('Exception: ', ''));
    return false;
  }
}