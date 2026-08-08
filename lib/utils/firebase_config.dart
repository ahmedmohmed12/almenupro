import 'package:flutter/foundation.dart';

import '../firebase_options.dart';

/// True when real Firebase web credentials are configured (not placeholders).
bool get isFirebaseConfigured {
  if (!kIsWeb) return true;
  final options = DefaultFirebaseOptions.web;
  return !options.apiKey.startsWith('YOUR_') &&
      !options.projectId.startsWith('YOUR_');
}
