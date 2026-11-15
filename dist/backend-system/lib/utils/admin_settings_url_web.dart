import 'dart:html' as html;

import '../widgets/admin/settings/admin_settings_tab.dart';

AdminSettingsTab readSettingsTabFromUrl() {
  final uri = Uri.parse(html.window.location.href);
  final fromPath = AdminSettingsTab.fromRoutePath(uri.path);
  if (fromPath != null) return fromPath;

  // Legacy query param support: ?tab=store
  final legacy = AdminSettingsTab.fromId(uri.queryParameters['tab']);
  if (uri.queryParameters.containsKey('tab')) return legacy;

  return AdminSettingsTab.whatsapp;
}

void writeSettingsTabToUrl(AdminSettingsTab tab) {
  final uri = Uri.parse(html.window.location.href);
  final nextPath = tab.routePath;
  final next = uri.replace(
    path: nextPath,
    queryParameters: Map.from(uri.queryParameters)..remove('tab'),
  );
  html.window.history.pushState(null, '', next.toString());
}
