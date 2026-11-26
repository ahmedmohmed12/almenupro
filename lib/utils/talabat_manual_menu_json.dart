import 'dart:convert';

/// Resolves Talabat URL from bookmarklet / manual JSON when the URL field is empty.
String? menuUrlFromManualTalabatJson(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;
  try {
    final decoded = jsonDecode(trimmed);
    if (decoded is! Map) return null;
    final map = Map<String, dynamic>.from(decoded);
    final url = (map['menuUrl'] ?? map['menu_url'] ?? '').toString().trim();
    return url.isEmpty ? null : url;
  } catch (_) {
    return null;
  }
}

bool looksLikeTalabatBookmarkletJson(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return false;
  try {
    final decoded = jsonDecode(trimmed);
    if (decoded is! Map) return false;
    final map = Map<String, dynamic>.from(decoded);
    if (map['source'] == 'almenupro-talabat-bookmarklet') return true;
    return map['items'] is List && (map['items'] as List).isNotEmpty;
  } catch (_) {
    return false;
  }
}

/// JSON from bookmarklet, array of items, or simple text lines (name | price).
bool looksLikeTalabatMenuPaste(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return false;
  if (looksLikeTalabatBookmarkletJson(trimmed)) return true;
  if (trimmed.startsWith('[')) {
    try {
      final decoded = jsonDecode(trimmed);
      return decoded is List && decoded.isNotEmpty;
    } catch (_) {
      return false;
    }
  }
  if (trimmed.contains('almenupro-talabat-bookmarklet')) return true;
  if (RegExp(r'قسم\s*[:：]', caseSensitive: false).hasMatch(trimmed)) {
    return true;
  }
  final lines = trimmed.split('\n').where((l) => l.trim().isNotEmpty);
  var pipeLines = 0;
  for (final line in lines) {
    if (line.contains('|') && RegExp(r'\d').hasMatch(line)) pipeLines++;
  }
  return pipeLines >= 1;
}