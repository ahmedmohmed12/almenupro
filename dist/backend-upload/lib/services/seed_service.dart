import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../data/sample_menu_data.dart';
import 'firebase_service.dart';

class SeedService {
  SeedService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  static const String metaCollection = 'app_meta';
  static const String seedDocId = 'menu_seed';

  /// Seeds sample menu items when the menu collection is empty.
  Future<void> seedMenuIfEmpty() async {
    try {
      final seedDoc = await _firestore
          .collection(metaCollection)
          .doc(seedDocId)
          .get();

      if (seedDoc.exists) {
        return;
      }

      final menuSnapshot = await _firestore
          .collection(FirebaseService.menuItemsCollection)
          .limit(1)
          .get();

      if (menuSnapshot.docs.isNotEmpty) {
        await _markSeeded();
        return;
      }

      final batch = _firestore.batch();
      for (final item in sampleMenuItems) {
        final docRef = _firestore
            .collection(FirebaseService.menuItemsCollection)
            .doc(item.id.toString());
        batch.set(docRef, item.toMap());
      }

      await batch.commit();
      await _markSeeded();

      if (kDebugMode) {
        debugPrint(
          'Seeded ${sampleMenuItems.length} menu items to Firestore.',
        );
      }
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint('Menu seed skipped: $error');
        debugPrint('$stackTrace');
      }
    }
  }

  Future<void> _markSeeded() async {
    await _firestore.collection(metaCollection).doc(seedDocId).set({
      'seededAt': FieldValue.serverTimestamp(),
      'version': 1,
    });
  }
}
