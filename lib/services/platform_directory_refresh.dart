import 'package:flutter/foundation.dart';

/// Tells the customer directory to reload after a platform sync.
class PlatformDirectoryRefresh {
  PlatformDirectoryRefresh._();

  static final tick = ValueNotifier<int>(0);

  static void notify() {
    tick.value += 1;
  }
}
