import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../data/molton_menu_data.dart';
import 'menu_storage_service.dart';

class MoltonUploadService {
  MoltonUploadService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  static const String categoriesCollection = 'categories';
  static const String itemsCollection = 'items';
  static const String metaCollection = 'app_meta';
  static const String moltonSeedDocId = 'molton_talabat_seed';

  Future<void> uploadMoltonDataIfEmpty() async {
    try {
      if (MenuStorageService.instance.hasItems) {
        return;
      }

      final seedDoc =
          await _firestore.collection(metaCollection).doc(moltonSeedDocId).get();

      if (seedDoc.exists) {
        return;
      }

      await uploadMoltonData();
      await _markUploaded();
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint('Molton upload skipped: $error');
        debugPrint('$stackTrace');
      }
    }
  }

  Future<void> uploadMoltonData() async {
    final firestore = _firestore;

    for (final category in moltonMenuCategories) {
      final categoryName = category['categoryName'] as String;

      final catRef = await firestore.collection(categoriesCollection).add({
        'name': categoryName,
        'createdAt': FieldValue.serverTimestamp(),
      });

      final items = category['items'] as List<dynamic>;
      for (final rawItem in items) {
        final item = rawItem as Map<String, dynamic>;
        await firestore.collection(itemsCollection).add({
          'categoryId': catRef.id,
          'categoryName': categoryName,
          'name': item['name'],
          'description': item['description'],
          'price': item['price'],
          'imageUrl': item['imageUrl'] as String? ?? '',
          'isAvailable': item['isAvailable'],
          'options': item['options'] ?? [],
        });
      }
    }

    if (kDebugMode) {
      debugPrint('تم رفع قائمة Molton Cookies بنجاح!');
    }
  }

  Future<void> _markUploaded() async {
    await _firestore.collection(metaCollection).doc(moltonSeedDocId).set({
      'seededAt': FieldValue.serverTimestamp(),
      'version': 1,
    });
  }
}
