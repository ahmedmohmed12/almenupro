import 'package:firebase_core/firebase_core.dart';

import '../firebase_options.dart';

bool get isFirebaseConfigured {
  try {
    final options = DefaultFirebaseOptions.currentPlatform;
    return options.apiKey.isNotEmpty &&
        !options.apiKey.startsWith('YOUR_') &&
        options.projectId.isNotEmpty &&
        !options.projectId.startsWith('YOUR_');
  } catch (_) {
    return false;
  }
}

/// Call after [WidgetsFlutterBinding.ensureInitialized].
Future<void> initializeFirebaseApp() async {
  if (Firebase.apps.isNotEmpty) return;
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
}
