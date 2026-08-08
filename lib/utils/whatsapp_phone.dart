class WhatsAppPhone {
  WhatsAppPhone._();

  static const defaultCountryCode = '965';

  static const countryCodes = [
    ('965', '🇰🇼 +965'),
    ('966', '🇸🇦 +966'),
    ('971', '🇦🇪 +971'),
    ('973', '🇧🇭 +973'),
    ('974', '🇶🇦 +974'),
    ('968', '🇴🇲 +968'),
    ('962', '🇯🇴 +962'),
    ('961', '🇱🇧 +961'),
    ('963', '🇸🇾 +963'),
    ('964', '🇮🇶 +964'),
    ('967', '🇾🇪 +967'),
    ('970', '🇵🇸 +970'),
    ('20', '🇪🇬 +20'),
    ('212', '🇲🇦 +212'),
    ('213', '🇩🇿 +213'),
    ('216', '🇹🇳 +216'),
    ('218', '🇱🇾 +218'),
    ('249', '🇸🇩 +249'),
    ('1', '🇺🇸 +1'),
    ('44', '🇬🇧 +44'),
    ('33', '🇫🇷 +33'),
    ('49', '🇩🇪 +49'),
    ('90', '🇹🇷 +90'),
    ('91', '🇮🇳 +91'),
    ('92', '🇵🇰 +92'),
  ];

  static String digitsOnly(String raw) => raw.replaceAll(RegExp(r'\D'), '');

  static String combine(String countryCode, String phone) {
    final cc = digitsOnly(countryCode);
    var local = digitsOnly(phone);
    if (cc.isEmpty || local.isEmpty) return '';
    if (local.startsWith('0')) {
      local = local.substring(1);
    }
    return '$cc$local';
  }

  static ({String countryCode, String phone}) split(String full) {
    final digits = digitsOnly(full);
    if (digits.isEmpty) {
      return (countryCode: defaultCountryCode, phone: '');
    }

    final codes = countryCodes.map((entry) => entry.$1).toList()
      ..sort((a, b) => b.length.compareTo(a.length));

    for (final code in codes) {
      if (digits.startsWith(code) && digits.length > code.length + 4) {
        return (countryCode: code, phone: digits.substring(code.length));
      }
    }

    if (digits.startsWith('965') && digits.length > 7) {
      return (countryCode: '965', phone: digits.substring(3));
    }

    return (countryCode: defaultCountryCode, phone: digits);
  }

  static String formatDisplay(String countryCode, String phone) {
    final full = combine(countryCode, phone);
    if (full.isEmpty) return '';
    return '+$full';
  }
}
