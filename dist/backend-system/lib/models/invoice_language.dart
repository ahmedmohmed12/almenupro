/// Preferred language for customer invoices and thermal receipts.
enum InvoiceLanguage {
  arabic('ar'),
  english('en');

  const InvoiceLanguage(this.code);

  final String code;

  bool get isArabic => this == InvoiceLanguage.arabic;
  bool get isEnglish => this == InvoiceLanguage.english;

  static InvoiceLanguage fromStorage(String? raw) {
    final normalized = (raw ?? '').trim().toLowerCase();
    if (normalized == 'en' ||
        normalized == 'english' ||
        normalized == 'eng') {
      return InvoiceLanguage.english;
    }
    return InvoiceLanguage.arabic;
  }
}
