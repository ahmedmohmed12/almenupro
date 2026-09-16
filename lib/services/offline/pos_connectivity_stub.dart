class PosBrowserLink {
  void attach(void Function(bool online) onChanged) {}
  void detach() {}
  bool get navigatorOnline => true;
  bool get websocketOnline => true;
}

PosBrowserLink createPosBrowserLink() => PosBrowserLink();
