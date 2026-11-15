import 'dart:async';
import 'dart:html' as html;

StreamSubscription<html.Event>? _visibilitySub;
StreamSubscription<html.Event>? _focusSub;
StreamSubscription<html.Event>? _pageShowSub;

void attachAdminRuntimeKeepAlive(void Function() onResume) {
  detachAdminRuntimeKeepAlive();

  void handleResume(html.Event _) {
    if (html.document.hidden == true) return;
    onResume();
  }

  _visibilitySub = html.document.onVisibilityChange.listen(handleResume);
  _focusSub = html.window.onFocus.listen(handleResume);
  _pageShowSub = html.window.on['pageshow'].listen(handleResume);
}

void detachAdminRuntimeKeepAlive() {
  _visibilitySub?.cancel();
  _focusSub?.cancel();
  _pageShowSub?.cancel();
  _visibilitySub = null;
  _focusSub = null;
  _pageShowSub = null;
}
