import 'dart:html' as html;

const _redirectStorageKey = 'almenupro_admin_redirect';

void navigateToAdminPath(String path) {
  html.window.history.pushState(null, '', path);
}

void replaceAdminPath(String path) {
  html.window.history.replaceState(null, '', path);
}

void storeAdminRedirect(String path) {
  html.window.sessionStorage[_redirectStorageKey] = path;
}

String? readStoredAdminRedirect() {
  return html.window.sessionStorage[_redirectStorageKey];
}

void clearStoredAdminRedirect() {
  html.window.sessionStorage.remove(_redirectStorageKey);
}
