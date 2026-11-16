import 'dart:html' as html;

String readWebPath() {
  final path = html.window.location.pathname ?? '';
  if (path.isEmpty) return '/';
  return path;
}