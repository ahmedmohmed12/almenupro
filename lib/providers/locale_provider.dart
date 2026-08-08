import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocaleProvider extends ChangeNotifier {
  LocaleProvider();

  static const _prefKey = 'customer_locale';

  String _localeCode = 'ar';

  String get localeCode => _localeCode;

  bool get isArabic => _localeCode.startsWith('ar');

  TextDirection get textDirection =>
      isArabic ? TextDirection.rtl : TextDirection.ltr;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_prefKey);
    if (saved == 'ar' || saved == 'en') {
      _localeCode = saved!;
      notifyListeners();
    }
  }

  Future<void> setLocale(String code) async {
    final normalized = code.startsWith('en') ? 'en' : 'ar';
    if (_localeCode == normalized) return;
    _localeCode = normalized;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, normalized);
  }

  Future<void> toggle() => setLocale(isArabic ? 'en' : 'ar');
}
