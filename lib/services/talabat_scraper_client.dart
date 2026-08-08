import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class TalabatScraperClient {
  TalabatScraperClient({
    FirebaseFunctions? functions,
    http.Client? httpClient,
    this.localProxyUrl = 'http://127.0.0.1:3001/scrape',
  })  : _functions = functions ?? FirebaseFunctions.instance,
        _httpClient = httpClient ?? http.Client();

  final FirebaseFunctions _functions;
  final http.Client _httpClient;
  final String localProxyUrl;

  Future<TalabatScrapeResult> scrapeMenu(String url) async {
    final normalizedUrl = url.trim();

    if (kIsWeb) {
      try {
        return await _scrapeViaLocalProxy(normalizedUrl);
      } catch (localError) {
        debugPrint('Local Talabat proxy failed: $localError');
      }
    }

    try {
      return await _scrapeViaCloudFunction(normalizedUrl);
    } on TalabatScrapeException {
      rethrow;
    } catch (cloudError) {
      debugPrint('Cloud Function scrape failed: $cloudError');
    }

    if (!kIsWeb) {
      try {
        return await _scrapeViaLocalProxy(normalizedUrl);
      } catch (localError) {
        debugPrint('Local Talabat proxy failed: $localError');
      }
    }

    throw TalabatScrapeException(
      kIsWeb
          ? 'تعذر سحب المنيو. شغّل خادم السحب المحلي: node functions/localScraperServer.js'
          : 'تعذر الاتصال بخدمة سحب المنيو. تأكد من نشر Cloud Functions أو تشغيل الخادم المحلي.',
    );
  }

  Future<TalabatScrapeResult> _scrapeViaCloudFunction(String url) async {
    final callable = _functions.httpsCallable(
      'scrapeTalabatMenu',
      options: HttpsCallableOptions(
        timeout: const Duration(seconds: 60),
      ),
    );

    final response = await callable.call<Map<Object?, Object?>>(
      {'url': url},
    );

    return _parseScrapePayload(
      Map<String, dynamic>.from(response.data),
      fallbackUrl: url,
    );
  }

  Future<TalabatScrapeResult> _scrapeViaLocalProxy(String url) async {
    final response = await _httpClient
        .post(
          Uri.parse(localProxyUrl),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode({'url': url}),
        )
        .timeout(const Duration(seconds: 60));

    final body = jsonDecode(response.body);
    if (response.statusCode != 200) {
      final message = body is Map && body['error'] != null
          ? body['error'].toString()
          : 'تعذر سحب المنيو من الخادم المحلي (${response.statusCode})';
      throw TalabatScrapeException(message);
    }

    if (body is! Map) {
      throw TalabatScrapeException('استجابة غير صالحة من خادم السحب المحلي');
    }

    return _parseScrapePayload(
      Map<String, dynamic>.from(body),
      fallbackUrl: url,
    );
  }

  TalabatScrapeResult _parseScrapePayload(
    Map<String, dynamic> data, {
    required String fallbackUrl,
  }) {
    final rawItems = data['items'];
    if (rawItems is! List) {
      throw TalabatScrapeException('استجابة غير صالحة من خادم السحب');
    }

    final items = rawItems
        .whereType<Map>()
        .map((entry) => Map<String, dynamic>.from(entry))
        .where((item) => (item['name'] ?? '').toString().trim().isNotEmpty)
        .map(
          (item) => {
            'talabatId': item['talabatId'],
            'name': item['name'].toString().trim(),
            'description': item['description'] ?? '',
            'price': _toDouble(item['price']),
            'categoryName': item['categoryName'] ?? 'عام',
            'imageUrl': item['imageUrl'] ?? '',
            'isAvailable': item['isAvailable'] ?? true,
            'source': item['source'] ?? 'Talabat',
          },
        )
        .toList();

    return TalabatScrapeResult(
      menuUrl: data['menuUrl']?.toString() ?? fallbackUrl,
      items: items,
    );
  }

  double _toDouble(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }
}

class TalabatScrapeResult {
  const TalabatScrapeResult({
    required this.menuUrl,
    required this.items,
  });

  final String menuUrl;
  final List<Map<String, dynamic>> items;
}

class TalabatScrapeException implements Exception {
  TalabatScrapeException(this.message);

  final String message;

  @override
  String toString() => message;
}
