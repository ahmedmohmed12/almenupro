import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../utils/admin_deep_link.dart';
import '../../utils/admin_route_nav.dart';

void completeAdminLoginNavigation(BuildContext context, {String? redirect}) {
  final safe =
      AdminDeepLink.sanitizeRedirect(redirect) ?? AdminDeepLink.adminHomePath;
  if (kIsWeb) {
    replaceAdminPath(safe);
  }
  Navigator.of(context).pushReplacementNamed(safe);
}