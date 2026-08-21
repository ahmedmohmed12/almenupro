import 'dart:html' as html;

void navigateToAdminPath(String path) {
  html.window.history.pushState(null, '', path);
}
