import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;

import 'package:http/http.dart' as http;

import '../models/signup_request.dart';

Future<bool> sendSignupBrowserMail({
  required String to,
  required SignupRequest request,
}) async {
  final recipient = to.trim();
  if (!recipient.contains('@')) return false;
  final subject = 'طلب اشتراك جديد: ${request.restaurantName}';
  final payload = <String, String>{
    '_subject': subject,
    '_template': 'table',
    '_captcha': 'false',
    'name': request.ownerName,
    'email': request.email,
    'phone': request.phone,
    'restaurant': request.restaurantName,
    'slug': request.slug,
    'instagram': request.instagram,
    'message': [
      'طلب اشتراك جديد — المنيو برو',
      'الاسم: ${request.ownerName}',
      'البريد: ${request.email}',
      'الموبايل: ${request.phone}',
      'المطعم: ${request.restaurantName}',
      'الدليل: ${request.slug}',
      'إنستغرام: ${request.instagram}',
    ].join('\n'),
  };
  try {
    final response = await http
        .post(
          Uri.parse('https://formsubmit.co/ajax/${Uri.encodeComponent(recipient)}'),
          headers: const {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
          body: jsonEncode(payload),
        )
        .timeout(const Duration(seconds: 20));
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return true;
    }
  } catch (_) {}
  return _submitHiddenForm(recipient, payload);
}

Future<bool> _submitHiddenForm(String to, Map<String, String> payload) async {
  final frameName = 'amp_mail_${DateTime.now().millisecondsSinceEpoch}';
  final iframe = html.IFrameElement()
    ..name = frameName
    ..style.display = 'none';
  final form = html.FormElement()
    ..method = 'POST'
    ..action = 'https://formsubmit.co/${Uri.encodeComponent(to)}'
    ..target = frameName
    ..style.display = 'none';
  payload.forEach((key, value) {
    form.append(html.HiddenInputElement()
      ..name = key
      ..value = value);
  });
  html.document.body?.append(iframe);
  html.document.body?.append(form);
  final done = Completer<bool>();
  late StreamSubscription<html.Event> sub;
  sub = iframe.onLoad.listen((_) {
    if (!done.isCompleted) done.complete(true);
  });
  form.submit();
  try {
    return await done.future.timeout(
      const Duration(seconds: 12),
      onTimeout: () => true,
    );
  } finally {
    await sub.cancel();
    form.remove();
    iframe.remove();
  }
}
