import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/dining_table.dart';
import '../utils/firebase_config.dart';
import 'offline/table_floor_cache_db.dart';

class TableFloorLiveService {
  TableFloorLiveService._();

  static final TableFloorLiveService instance = TableFloorLiveService._();

  static const collection = 'table_floor';

  FirebaseFirestore? get _firestore =>
      isFirebaseConfigured ? FirebaseFirestore.instance : null;

  String docId(String restaurantId, String tableId) =>
      '${restaurantId}_$tableId';

  Map<String, dynamic> _payload(DiningTable table, String restaurantId) {
    return {
      'restaurantId': restaurantId,
      'tableId': table.id,
      'status': table.isAwaitingCheck
          ? DiningTableStatus.awaitingCheck.apiValue
          : table.isWaiterCall
          ? DiningTableStatus.waiterCall.apiValue
          : table.isOccupied
          ? DiningTableStatus.occupied.apiValue
          : table.status.apiValue,
      'waiterNote': table.waiterNote,
      'number': table.number,
      'name': table.displayName,
      'openedAt': table.activeSession?.openedAt?.toIso8601String(),
      'currentOrderNumber': table.currentOrderNumber,
      'currentAmount': table.sessionAmount,
      'itemCount': table.sessionItemCount,
      'tipAmount': table.requestedTip,
      'paymentMethod': table.requestedPaymentMethod,
      'billTotal': table.requestedBillTotal,
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
    };
  }

  Future<List<DiningTable>> loadCached(String restaurantId) async {
    if (restaurantId.isEmpty) return const [];
    final rows = await tableFloorCache.load(restaurantId);
    return rows.map(DiningTable.fromJson).toList();
  }

  Future<void> persistCache(
    String restaurantId,
    List<DiningTable> tables,
  ) async {
    if (restaurantId.isEmpty) return;
    unawaited(
      tableFloorCache.save(
        restaurantId,
        tables
            .map(
              (table) => {
                'id': table.id,
                'number': table.number,
                'name': table.name,
                'zone': table.zone,
                'capacity': table.capacity,
                'status': table.status.apiValue,
                'sortOrder': table.sortOrder,
                if (table.activeSession != null)
                  'activeSession': {
                    'id': table.activeSession!.id,
                    'openedAt': table.activeSession!.openedAt
                        ?.toIso8601String(),
                    'openedByName': table.activeSession!.openedByName,
                    'cartItems': table.activeSession!.cartItems,
                    'kitchenOrderIds': table.activeSession!.kitchenOrderIds,
                    'currentOrderNumber':
                        table.activeSession!.currentOrderNumber,
                    'checkRequested': table.activeSession!.checkRequested,
                    'checkRequestedAt': table.activeSession!.checkRequestedAt
                        ?.toIso8601String(),
                    'tipAmount': table.activeSession!.tipAmount,
                    'paymentMethod': table.activeSession!.paymentMethod,
                    'billTotal': table.activeSession!.billTotal,
                    'waiterRequested': table.activeSession!.waiterRequested,
                    'waiterNote': table.activeSession!.waiterNote,
                    'customerName': table.activeSession!.customerName,
                    'phone': table.activeSession!.phone,
                  },
              },
            )
            .toList(),
      ),
    );
  }

  Future<void> publish(DiningTable table, String restaurantId) async {
    final firestore = _firestore;
    if (firestore == null || restaurantId.isEmpty || table.id.isEmpty) return;
    try {
      await firestore
          .collection(collection)
          .doc(docId(restaurantId, table.id))
          .set(_payload(table, restaurantId), SetOptions(merge: true));
    } catch (error) {
      debugPrint('table_floor publish failed: $error');
    }
  }

  Future<void> publishAll(List<DiningTable> tables, String restaurantId) async {
    for (final table in tables) {
      await publish(table, restaurantId);
    }
  }

  Stream<List<Map<String, dynamic>>> watch(String restaurantId) {
    final firestore = _firestore;
    if (firestore == null || restaurantId.isEmpty) {
      return const Stream.empty();
    }
    return firestore
        .collection(collection)
        .where('restaurantId', isEqualTo: restaurantId)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => Map<String, dynamic>.from(doc.data()))
              .toList(),
        );
  }

  DiningTable mergeOverlay(DiningTable table, Map<String, dynamic>? overlay) {
    if (overlay == null) return table;
    final status = DiningTableStatus.fromValue(overlay['status']?.toString());
    final note = overlay['waiterNote']?.toString() ?? table.waiterNote;
    final session = table.activeSession;
    return table.copyWith(
      status: status,
      activeSession: DiningTableSession(
        id: session?.id ?? 'live',
        openedAt: session?.openedAt,
        openedById: session?.openedById,
        openedByName: session?.openedByName,
        cartItems: session?.cartItems ?? const [],
        notes: session?.notes ?? '',
        customerName: session?.customerName ?? '',
        phone: session?.phone ?? '',
        kitchenOrderIds: session?.kitchenOrderIds ?? const [],
        currentOrderNumber:
            (overlay['currentOrderNumber']?.toString().trim().isNotEmpty ??
                false)
            ? overlay['currentOrderNumber'].toString().trim()
            : (session?.currentOrderNumber ?? ''),
        checkRequested:
            status == DiningTableStatus.awaitingCheck ||
            (session?.checkRequested ?? false),
        checkRequestedAt: session?.checkRequestedAt,
        tipAmount:
            (overlay['tipAmount'] as num?)?.toDouble() ??
            session?.tipAmount ??
            0,
        paymentMethod:
            overlay['paymentMethod']?.toString() ??
            session?.paymentMethod ??
            '',
        billTotal:
            (overlay['billTotal'] as num?)?.toDouble() ??
            session?.billTotal ??
            0,
        waiterRequested:
            status == DiningTableStatus.waiterCall ||
            (session?.waiterRequested ?? false),
        waiterNote: note,
        waiterRequestedAt: session?.waiterRequestedAt,
        updatedAt: DateTime.tryParse(overlay['updatedAt']?.toString() ?? ''),
      ),
    );
  }

  List<DiningTable> mergeOverlays(
    List<DiningTable> tables,
    List<Map<String, dynamic>> overlays,
  ) {
    if (overlays.isEmpty) return tables;
    final byId = <String, Map<String, dynamic>>{};
    for (final overlay in overlays) {
      final id = overlay['tableId']?.toString() ?? '';
      if (id.isNotEmpty) byId[id] = overlay;
    }
    return [for (final table in tables) mergeOverlay(table, byId[table.id])];
  }
}
