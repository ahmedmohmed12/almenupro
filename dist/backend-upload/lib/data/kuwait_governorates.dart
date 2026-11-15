/// Kuwait governorates supported for delivery zone configuration.
const List<String> kuwaitGovernorates = [
  'العاصمة',
  'حولي',
  'الفروانية',
  'الجهراء',
  'مبارك الكبير',
  'الأحمدي',
];

String normalizeGovernorate(String? value) {
  final trimmed = (value ?? '').trim();
  if (trimmed.isEmpty) return '';
  if (trimmed.contains('احمد') || trimmed.contains('أحمد')) {
    return 'الأحمدي';
  }
  return trimmed;
}
