/// Normalizes a restaurant slug to match backend rules (a-z, 0-9, hyphens).
String normalizeRestaurantSlug(String input, {String fallbackName = ''}) {
  String normalize(String value) {
    return value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), '-')
        .replaceAll(RegExp(r'[^a-z0-9-]'), '')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
  }

  final fromInput = normalize(input);
  if (fromInput.isNotEmpty) return fromInput;

  final fromName = normalize(fallbackName);
  return fromName;
}
