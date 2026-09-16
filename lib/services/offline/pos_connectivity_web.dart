import 'dart:async';
import 'dart:html' as html;

class PosBrowserLink {
  StreamSubscription<html.Event>? _online;
  StreamSubscription<html.Event>? _offline;

  void attach(void Function(bool online) onChanged) {
    onChanged(navigatorOnline);
    _online = html.window.onOnline.listen((_) => onChanged(true));
    _offline = html.window.onOffline.listen((_) => onChanged(false));
  }

  void detach() {
    _online?.cancel();
    _offline?.cancel();
    _online = null;
    _offline = null;
  }

  bool get navigatorOnline => html.window.navigator.onLine ?? true;

  /// Printer QZ socket is optional; cloud sync uses navigator + HTTP poll.
  bool get websocketOnline => navigatorOnline;
}

PosBrowserLink createPosBrowserLink() => PosBrowserLink();
