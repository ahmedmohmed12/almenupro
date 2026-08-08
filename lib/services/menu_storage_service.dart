import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/menu_item.dart';
import '../utils/firebase_config.dart';
import '../utils/image_url.dart';
import 'api_service.dart';

class MenuItemRecord {
  const MenuItemRecord({
    required this.id,
    required this.data,
  });

  final String id;
  final Map<String, dynamic> data;

  Map<String, dynamic> toJson() => {'id': id, 'data': data};

  factory MenuItemRecord.fromJson(Map<String, dynamic> json) {
    return MenuItemRecord(
      id: json['id'] as String,
      data: Map<String, dynamic>.from(json['data'] as Map),
    );
  }
}

/// Persists menu items to Firestore and a local cache so data survives restarts.
class MenuStorageService {
  MenuStorageService._();

  static final MenuStorageService instance = MenuStorageService._();

  static const _cacheKey = 'menu_items_v1';
  static const _metaKey = 'menu_meta_v1';
  static const _itemsCollection = 'items';

  FirebaseFirestore? get _firestore =>
      isFirebaseConfigured ? FirebaseFirestore.instance : null;

  final StreamController<List<MenuItemRecord>> _controller =
      StreamController<List<MenuItemRecord>>.broadcast();

  SharedPreferences? _prefs;
  List<MenuItemRecord> _items = [];
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _firestoreSub;
  var _initialized = false;
  Future<void>? _initFuture;
  Stream<List<MenuItemRecord>>? _watchStream;

  Stream<List<MenuItemRecord>> watchItems() {
    _watchStream ??= _createWatchStream();
    return _watchStream!;
  }

  Stream<List<MenuItemRecord>> _createWatchStream() {
    return Stream<List<MenuItemRecord>>.multi((controller) async {
      await initialize();
      controller.add(List.unmodifiable(_items));

      final subscription = _controller.stream.listen(
        controller.add,
        onError: controller.addError,
        cancelOnError: false,
      );

      controller.onCancel = () => subscription.cancel();
    }).asBroadcastStream();
  }

  List<MenuItemRecord> get currentItems => List.unmodifiable(_items);

  bool get hasItems => _items.isNotEmpty;

  Future<void> initialize() async {
    if (_initialized) return;
    _initFuture ??= _performInitialize();
    await _initFuture;
  }

  Future<void> _performInitialize() async {
    _prefs = await SharedPreferences.getInstance();
    _items = await _loadFromPrefs();

    if (_items.isNotEmpty) {
      _emit();
    }

    if (_firestore != null) {
      _startFirestoreListener();
    }
    unawaited(_refreshFromRemote());

    _initialized = true;
    _emit();
  }

  Future<void> _refreshFromRemote() async {
    try {
      final apiItems = await ApiService.instance.fetchMenuItems();
      if (apiItems.isNotEmpty) {
        _items = apiItems.map(_recordFromMenuItem).toList();
        await _saveToPrefs(_items);
        _emit();
        return;
      }
    } catch (error) {
      debugPrint('MenuStorageService API init failed: $error');
    }

    if (_items.isNotEmpty) return;

    final firestore = _firestore;
    if (firestore == null) return;

    try {
      final snapshot = await firestore
          .collection(_itemsCollection)
          .get()
          .timeout(const Duration(seconds: 8));
      if (snapshot.docs.isNotEmpty) {
        _items = snapshot.docs
            .map(
              (doc) => MenuItemRecord(
                id: doc.id,
                data: Map<String, dynamic>.from(doc.data()),
              ),
            )
            .toList();
        await _saveToPrefs(_items);
        _emit();
      } else if (_items.isNotEmpty) {
        unawaited(_pushAllToFirestore());
      }
    } catch (error) {
      debugPrint('MenuStorageService Firestore init failed: $error');
    }
  }

  void _startFirestoreListener() {
    final firestore = _firestore;
    if (firestore == null) return;

    _firestoreSub?.cancel();
    _firestoreSub = firestore
        .collection(_itemsCollection)
        .snapshots()
        .listen(
      (snapshot) {
        if (snapshot.docs.isEmpty) return;

        _items = snapshot.docs
            .map(
              (doc) => MenuItemRecord(
                id: doc.id,
                data: Map<String, dynamic>.from(doc.data()),
              ),
            )
            .toList();
        unawaited(_saveToPrefs(_items));
        _emit();
      },
      onError: (Object error) {
        debugPrint('MenuStorageService Firestore watch failed: $error');
      },
    );
  }

  Future<String> addItem(Map<String, dynamic> data) async {
    await initialize();

    final normalized = _normalizeItemData(data);
    normalized.putIfAbsent(
      'createdAt',
      () => DateTime.now().toIso8601String(),
    );
    final id = _generateId();

    final firestore = _firestore;
    try {
      if (firestore == null) throw StateError('Firebase not configured');
      final docRef =
          await firestore.collection(_itemsCollection).add(normalized);
      final record = MenuItemRecord(id: docRef.id, data: normalized);
      _upsertInMemory(record);
      await _saveToPrefs(_items);
      _emit();
      return docRef.id;
    } catch (error) {
      debugPrint('MenuStorageService addItem Firestore failed: $error');
      final record = MenuItemRecord(id: id, data: normalized);
      _upsertInMemory(record);
      await _saveToPrefs(_items);
      _emit();
      return id;
    }
  }

  Future<void> updateItem(String id, Map<String, dynamic> data) async {
    await initialize();

    final normalized = _normalizeItemData(data, preserveFrom: _findById(id)?.data);
    normalized['updatedAt'] = DateTime.now().toIso8601String();

    final firestore = _firestore;
    try {
      if (firestore == null) throw StateError('Firebase not configured');
      await firestore.collection(_itemsCollection).doc(id).update(normalized);
    } catch (error) {
      debugPrint('MenuStorageService updateItem Firestore failed: $error');
      try {
        if (firestore == null) throw StateError('Firebase not configured');
        await firestore
            .collection(_itemsCollection)
            .doc(id)
            .set(normalized, SetOptions(merge: true));
      } catch (setError) {
        debugPrint('MenuStorageService updateItem set failed: $setError');
      }
    }

    _upsertInMemory(MenuItemRecord(id: id, data: normalized));
    await _saveToPrefs(_items);
    _emit();
  }

  Future<void> deleteItem(String id) async {
    await initialize();

    final firestore = _firestore;
    try {
      if (firestore == null) throw StateError('Firebase not configured');
      await firestore.collection(_itemsCollection).doc(id).delete();
    } catch (error) {
      debugPrint('MenuStorageService deleteItem Firestore failed: $error');
    }

    _items.removeWhere((item) => item.id == id);
    await _saveToPrefs(_items);
    _emit();
  }

  Future<MenuSyncResult> syncItems({
    required List<Map<String, dynamic>> incomingItems,
    bool updateExisting = false,
    String? sourceUrl,
  }) async {
    await initialize();

    final existingByTalabatId = <String, MenuItemRecord>{};
    final existingByName = <String, MenuItemRecord>{};
    for (final item in _items) {
      final talabatId = item.data['talabatId']?.toString();
      if (talabatId != null && talabatId.isNotEmpty) {
        existingByTalabatId[talabatId] = item;
        continue;
      }

      final name = (item.data['name'] ?? '').toString().trim().toLowerCase();
      if (name.isNotEmpty) {
        existingByName[name] = item;
      }
    }

    var addedCount = 0;
    var skippedCount = 0;
    var updatedCount = 0;
    final pendingWrites = <MenuItemRecord>[];
    final now = DateTime.now().toIso8601String();

    for (final raw in incomingItems) {
      final item = _normalizeItemData(raw);
      final nameKey = (item['name'] ?? '').toString().trim().toLowerCase();
      if (nameKey.isEmpty) continue;

      final talabatKey = item['talabatId']?.toString();
      final hasTalabatId = talabatKey != null && talabatKey.isNotEmpty;
      final existing = hasTalabatId
          ? existingByTalabatId[talabatKey]
          : existingByName[nameKey];

      if (existing != null) {
        if (!updateExisting) {
          skippedCount++;
          continue;
        }

        final merged = _normalizeItemData(item, preserveFrom: existing.data);
        merged['updatedAt'] = now;
        final record = MenuItemRecord(id: existing.id, data: merged);
        pendingWrites.add(record);
        if (hasTalabatId) {
          existingByTalabatId[talabatKey] = record;
        } else {
          existingByName[nameKey] = record;
        }
        updatedCount++;
        continue;
      }

      final normalized = Map<String, dynamic>.from(item);
      normalized.putIfAbsent('createdAt', () => now);
      final id = _firestore?.collection(_itemsCollection).doc().id ?? _generateId();
      final record = MenuItemRecord(id: id, data: normalized);
      pendingWrites.add(record);
      if (hasTalabatId) {
        existingByTalabatId[talabatKey] = record;
      } else {
        existingByName[nameKey] = record;
      }
      addedCount++;
    }

    if (pendingWrites.isNotEmpty) {
      for (final record in pendingWrites) {
        _upsertInMemory(record);
      }
      await _saveToPrefs(_items);
      _emit();
      unawaited(_commitRecordsBatch(pendingWrites));
    }

    if (sourceUrl != null && sourceUrl.trim().isNotEmpty) {
      await _saveImportMeta(sourceUrl.trim(), _items.length);
    }

    return MenuSyncResult(
      addedCount: addedCount,
      skippedCount: skippedCount,
      updatedCount: updatedCount,
      totalCount: _items.length,
    );
  }

  Future<void> _commitRecordsBatch(List<MenuItemRecord> records) async {
    if (records.isEmpty) return;

    const chunkSize = 450;
    for (var start = 0; start < records.length; start += chunkSize) {
      final end = (start + chunkSize < records.length)
          ? start + chunkSize
          : records.length;
      final chunk = records.sublist(start, end);

      final firestore = _firestore;
      if (firestore == null) return;

      try {
        final batch = firestore.batch();
        for (final record in chunk) {
          final ref = firestore.collection(_itemsCollection).doc(record.id);
          batch.set(ref, record.data, SetOptions(merge: true));
        }
        await batch.commit();
      } catch (error) {
        debugPrint('MenuStorageService batch commit failed: $error');
      }
    }
  }

  Future<void> _saveImportMeta(String sourceUrl, int itemCount) async {
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    final meta = {
      'sourceUrl': sourceUrl,
      'importedAt': DateTime.now().toIso8601String(),
      'itemCount': itemCount,
    };
    await prefs.setString(_metaKey, jsonEncode(meta));

    final firestore = _firestore;
    try {
      if (firestore == null) return;
      await firestore.collection('app_meta').doc('menu_import').set({
        'sourceUrl': sourceUrl,
        'importedAt': FieldValue.serverTimestamp(),
        'itemCount': itemCount,
      }, SetOptions(merge: true));
    } catch (error) {
      debugPrint('MenuStorageService import meta save failed: $error');
    }
  }

  Future<void> _pushAllToFirestore() async {
    await _commitRecordsBatch(_items);
  }

  MenuItemRecord _recordFromMenuItem(MenuItem item) {
    return MenuItemRecord(
      id: item.id.toString(),
      data: {
        'name': item.name,
        'description': item.description,
        'price': item.price,
        'categoryName': item.categoryName,
        'categoryId': item.categoryId,
        'imageUrl': item.imageUrl,
        'isAvailable': item.isAvailable,
        'source': 'NodeAPI',
      },
    );
  }

  MenuItemRecord? _findById(String id) {
    for (final item in _items) {
      if (item.id == id) return item;
    }
    return null;
  }

  void _upsertInMemory(MenuItemRecord record) {
    final index = _items.indexWhere((item) => item.id == record.id);
    if (index == -1) {
      _items.add(record);
    } else {
      _items[index] = record;
    }
  }

  Map<String, dynamic> _normalizeItemData(
    Map<String, dynamic> data, {
    Map<String, dynamic>? preserveFrom,
  }) {
    final imageUrl = normalizeMenuImageUrl(
      data['imageUrl'] ?? preserveFrom?['imageUrl'] ?? preserveFrom?['image_url'],
    );

    return {
      'name': (data['name'] ?? preserveFrom?['name'] ?? '').toString().trim(),
      'nameAr': (data['nameAr'] ??
              data['name_ar'] ??
              preserveFrom?['nameAr'] ??
              preserveFrom?['name_ar'] ??
              data['name'] ??
              preserveFrom?['name'] ??
              '')
          .toString()
          .trim(),
      'nameEn': (data['nameEn'] ??
              data['name_en'] ??
              preserveFrom?['nameEn'] ??
              preserveFrom?['name_en'] ??
              '')
          .toString()
          .trim(),
      'description':
          (data['description'] ?? preserveFrom?['description'] ?? '')
              .toString(),
      'descriptionAr': (data['descriptionAr'] ??
              data['description_ar'] ??
              preserveFrom?['descriptionAr'] ??
              preserveFrom?['description_ar'] ??
              data['description'] ??
              preserveFrom?['description'] ??
              '')
          .toString(),
      'descriptionEn': (data['descriptionEn'] ??
              data['description_en'] ??
              preserveFrom?['descriptionEn'] ??
              preserveFrom?['description_en'] ??
              '')
          .toString(),
      'price': _toDouble(data['price'] ?? preserveFrom?['price']),
      'categoryName':
          (data['categoryName'] ?? preserveFrom?['categoryName'] ?? 'عام')
              .toString(),
      'categoryNameEn': (data['categoryNameEn'] ??
              data['category_name_en'] ??
              preserveFrom?['categoryNameEn'] ??
              preserveFrom?['category_name_en'] ??
              '')
          .toString(),
      'categoryId':
          (data['categoryId'] ?? preserveFrom?['categoryId'] ?? '').toString(),
      'talabatId': (data['talabatId'] ?? preserveFrom?['talabatId'] ?? '')
          .toString(),
      'imageUrl': imageUrl,
      'options': data['options'] ?? preserveFrom?['options'] ?? <dynamic>[],
      'isAvailable': data['isAvailable'] as bool? ??
          preserveFrom?['isAvailable'] as bool? ??
          true,
      'source': (data['source'] ?? preserveFrom?['source'] ?? 'Manual')
          .toString(),
      if (preserveFrom?['createdAt'] != null)
        'createdAt': preserveFrom!['createdAt'],
    };
  }

  double _toDouble(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  String _generateId() {
    final random = Random().nextInt(999999).toString().padLeft(6, '0');
    return 'local_${DateTime.now().millisecondsSinceEpoch}_$random';
  }

  Future<List<MenuItemRecord>> _loadFromPrefs() async {
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    final raw = prefs.getString(_cacheKey);
    if (raw == null || raw.isEmpty) return [];

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];

      return decoded
          .whereType<Map>()
          .map((entry) => MenuItemRecord.fromJson(Map<String, dynamic>.from(entry)))
          .where((item) => (item.data['name'] ?? '').toString().trim().isNotEmpty)
          .toList();
    } catch (error) {
      debugPrint('MenuStorageService cache load failed: $error');
      return [];
    }
  }

  Future<void> _saveToPrefs(List<MenuItemRecord> items) async {
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    final encoded = jsonEncode(items.map((item) => item.toJson()).toList());
    await prefs.setString(_cacheKey, encoded);
  }

  void _emit() {
    if (!_controller.isClosed) {
      _controller.add(List.unmodifiable(_items));
    }
  }
}

class MenuSyncResult {
  const MenuSyncResult({
    required this.addedCount,
    required this.skippedCount,
    required this.updatedCount,
    required this.totalCount,
  });

  final int addedCount;
  final int skippedCount;
  final int updatedCount;
  final int totalCount;
}
