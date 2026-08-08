import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

String normalizeWhatsAppNumber(String raw) {
  return raw.replaceAll(RegExp(r'\D'), '');
}

Future<bool> openWhatsAppChat({
  required String phone,
  required String message,
}) async {
  final normalizedPhone = normalizeWhatsAppNumber(phone);
  if (normalizedPhone.isEmpty) {
    return false;
  }

  final uri = Uri.parse(
    'https://api.whatsapp.com/send?phone=$normalizedPhone&text=${Uri.encodeComponent(message)}',
  );

  if (kIsWeb) {
    return launchUrl(
      uri,
      webOnlyWindowName: '_blank',
      webViewConfiguration: const WebViewConfiguration(
        enableJavaScript: true,
      ),
    );
  }

  try {
    if (await canLaunchUrl(uri)) {
      return launchUrl(uri, mode: LaunchMode.externalApplication);
    }
    return launchUrl(uri, mode: LaunchMode.platformDefault);
  } catch (_) {
    return false;
  }
}
