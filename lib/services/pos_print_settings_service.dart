import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum PosPrintFontSize {
  small,
  medium,
  large;

  String get labelAr => switch (this) {
        PosPrintFontSize.small => 'صغير',
        PosPrintFontSize.medium => 'متوسط',
        PosPrintFontSize.large => 'كبير',
      };

  static PosPrintFontSize fromStorage(String? raw) {
    switch ((raw ?? '').trim().toLowerCase()) {
      case 'small':
        return PosPrintFontSize.small;
      case 'large':
        return PosPrintFontSize.large;
      default:
        return PosPrintFontSize.medium;
    }
  }
}

enum PosPrintPaperPreset {
  mm58,
  mm80,
  custom;

  static PosPrintPaperPreset fromStorage(String? raw) {
    switch ((raw ?? '').trim().toLowerCase()) {
      case 'mm58':
      case '58':
        return PosPrintPaperPreset.mm58;
      case 'custom':
        return PosPrintPaperPreset.custom;
      default:
        return PosPrintPaperPreset.mm80;
    }
  }
}

/// Workstation-local thermal printer preferences for the POS.
class PosPrintSettings {
  const PosPrintSettings({
    this.paperPreset = PosPrintPaperPreset.mm80,
    this.customWidthMm = 80,
    this.copies = 1,
    this.autoPrintCustomer = true,
    this.autoPrintKitchen = true,
    this.fontSize = PosPrintFontSize.medium,
  });

  final PosPrintPaperPreset paperPreset;
  final double customWidthMm;
  final int copies;
  final bool autoPrintCustomer;
  final bool autoPrintKitchen;
  final PosPrintFontSize fontSize;

  double get widthMm => switch (paperPreset) {
        PosPrintPaperPreset.mm58 => 58,
        PosPrintPaperPreset.mm80 => 80,
        PosPrintPaperPreset.custom => customWidthMm.clamp(40, 120),
      };

  PosPrintSettings copyWith({
    PosPrintPaperPreset? paperPreset,
    double? customWidthMm,
    int? copies,
    bool? autoPrintCustomer,
    bool? autoPrintKitchen,
    PosPrintFontSize? fontSize,
  }) {
    return PosPrintSettings(
      paperPreset: paperPreset ?? this.paperPreset,
      customWidthMm: customWidthMm ?? this.customWidthMm,
      copies: copies ?? this.copies,
      autoPrintCustomer: autoPrintCustomer ?? this.autoPrintCustomer,
      autoPrintKitchen: autoPrintKitchen ?? this.autoPrintKitchen,
      fontSize: fontSize ?? this.fontSize,
    );
  }
}

class PosPrintSettingsService extends ChangeNotifier {
  PosPrintSettingsService._();

  static final PosPrintSettingsService instance = PosPrintSettingsService._();

  static const _keyPreset = 'pos_print_paper_preset';
  static const _keyCustomWidth = 'pos_print_custom_width_mm';
  static const _keyCopies = 'pos_print_copies';
  static const _keyAutoCustomer = 'pos_auto_print_customer';
  static const _keyAutoKitchen = 'pos_auto_print_kitchen';
  static const _keyFontSize = 'pos_print_font_size';

  PosPrintSettings _settings = const PosPrintSettings();
  var _initialized = false;

  PosPrintSettings get settings => _settings;
  bool get isInitialized => _initialized;

  Future<void> initialize() async {
    if (_initialized) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      _settings = PosPrintSettings(
        paperPreset: PosPrintPaperPreset.fromStorage(prefs.getString(_keyPreset)),
        customWidthMm: prefs.getDouble(_keyCustomWidth) ?? 80,
        copies: (prefs.getInt(_keyCopies) ?? 1).clamp(1, 5),
        autoPrintCustomer: prefs.getBool(_keyAutoCustomer) ?? true,
        autoPrintKitchen: prefs.getBool(_keyAutoKitchen) ?? true,
        fontSize: PosPrintFontSize.fromStorage(prefs.getString(_keyFontSize)),
      );
    } catch (error) {
      if (kDebugMode) {
        debugPrint('PosPrintSettings load failed: $error');
      }
    }
    _initialized = true;
    notifyListeners();
  }

  Future<void> save(PosPrintSettings next) async {
    _settings = next.copyWith(
      copies: next.copies.clamp(1, 5),
      customWidthMm: next.customWidthMm.clamp(40, 120),
    );
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyPreset, _settings.paperPreset.name);
    await prefs.setDouble(_keyCustomWidth, _settings.customWidthMm);
    await prefs.setInt(_keyCopies, _settings.copies);
    await prefs.setBool(_keyAutoCustomer, _settings.autoPrintCustomer);
    await prefs.setBool(_keyAutoKitchen, _settings.autoPrintKitchen);
    await prefs.setString(_keyFontSize, _settings.fontSize.name);
  }
}
