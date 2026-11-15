import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'driver/driver_app.dart';
import 'driver/driver_mobile.dart';
import 'firebase_options.dart';
import 'providers/locale_provider.dart';
import 'utils/firebase_config.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (isFirebaseConfigured) {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  } else {
    debugPrint(
      'Skipping Firebase init: replace YOUR_* values in lib/firebase_options.dart.',
    );
  }
  runApp(
    ChangeNotifierProvider(
      create: (_) => LocaleProvider()..load(),
      child: const DriverApp(),
    ),
  );
}
