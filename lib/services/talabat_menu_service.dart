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

  if (normalizedUrl.isEmpty) {
    onProgress('أدخل رابط Talabat أو الصق JSON من Bookmarklet (فيه menuUrl)');
    return false;
  }

  if (!isTalabatMenuUrl(normalizedUrl) && !looksLikeTalabatBookmarkletJson(manual)) {
    onProgress('استخدم رابط Talabat (طلبات) أو JSON من Bookmarklet');
    return false;
  }

  final targetRestaurantId = restaurantId ?? ApiService.defaultRestaurantId;

  try {
    onProgress(
      manual.isNotEmpty
          ? 'جاري استيراد الأصناف والصور من JSON الملصق...'
          : 'جاري سحب الأصناف من Talabat على السيرفر...',
    );

    final result = await ApiService.instance.importTalabatMenu(
      url: normalizedUrl,
      restaurantId: targetRestaurantId,
      talabatCookie: talabatCookie,
      nextData: nextData,
      menuJson: menuJson ?? nextData,
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
