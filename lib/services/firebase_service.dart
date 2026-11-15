import 'package:cloud_firestore/cloud_firestore.dart' hide Order;

import '../models/menu_item.dart';
import '../models/order.dart';
import '../utils/firebase_config.dart';
import 'admin_auth_service.dart';

class FirebaseService {
  FirebaseService({FirebaseFirestore? firestore})
      : _firestore = firestore ??
            (isFirebaseConfigured ? FirebaseFirestore.instance : null);

  final FirebaseFirestore? _firestore;

  bool get isAvailable => _firestore != null;

  static const String menuItemsCollection = 'menu_items';
  static const String itemsCollection = 'items';
  static const String ordersCollection = 'orders';

  CollectionReference<Map<String, dynamic>> get _menuItemsRef {
    final firestore = _firestore;
    if (firestore == null) {
      throw StateError('Firebase is not configured');
    }
    return firestore.collection(menuItemsCollection);
  }

  CollectionReference<Map<String, dynamic>> get _itemsRef {
    final firestore = _firestore;
    if (firestore == null) {
      throw StateError('Firebase is not configured');
    }
    return firestore.collection(itemsCollection);
  }

  CollectionReference<Map<String, dynamic>> get _ordersRef {
    final firestore = _firestore;
    if (firestore == null) {
      throw StateError('Firebase is not configured');
    }
    return firestore.collection(ordersCollection);
  }

  Stream<List<MenuItem>> watchMenuItems({bool availableOnly = true}) {
    if (_firestore == null) return Stream.value(const []);
    return _itemsRef.orderBy('categoryName').snapshots().asyncMap(
      (itemsSnapshot) async {
        if (itemsSnapshot.docs.isNotEmpty) {
          return _mapItemDocs(itemsSnapshot.docs, availableOnly);
        }

        Query<Map<String, dynamic>> query =
            _menuItemsRef.orderBy('category');

        if (availableOnly) {
          query = query.where('isAvailable', isEqualTo: true);
        }

        final legacySnapshot = await query.get();
        return legacySnapshot.docs
            .map((doc) => MenuItem.fromMap(doc.id, doc.data()))
            .where((item) => !availableOnly || item.showOnWebsite)
            .toList();
      },
    );
  }

  List<MenuItem> _mapItemDocs(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    bool availableOnly,
  ) {
    return docs
        .where((doc) {
          if (!availableOnly) {
            return true;
          }
          final data = doc.data();
          if (data['isAvailable'] == false) return false;
          final show = data['showOnWebsite'] ?? data['show_on_website'];
          if (show == false || show == 0) return false;
          return true;
        })
        .map(
          (doc) => MenuItem.fromMap(
            doc.id,
            {
              ...doc.data(),
              'category': doc.data()['categoryName'] ?? '',
            },
          ),
        )
        .toList();
  }

  Future<String> addOrder(Order order, {String? restaurantId}) async {
    final data = Map<String, dynamic>.from(order.toMap());
    if (restaurantId != null && restaurantId.isNotEmpty) {
      data['restaurantId'] = restaurantId;
      data['restaurant_id'] = restaurantId;
    }
    final id = order.id.trim().isNotEmpty ? order.id : _ordersRef.doc().id;
    await _ordersRef.doc(id).set(data, SetOptions(merge: true));
    return id;
  }

  Stream<List<Order>> watchOrders({String? restaurantId}) {
    if (_firestore == null) return Stream.value(const []);
    Query<Map<String, dynamic>> query = _ordersRef;
    if (restaurantId != null && restaurantId.isNotEmpty) {
      query = query.where('restaurantId', isEqualTo: restaurantId);
    } else {
      query = query.orderBy('createdAt', descending: true);
    }
    return query.snapshots().map((snapshot) {
      final orders = snapshot.docs
          .map((doc) => Order.fromMap(doc.id, doc.data()))
          .toList();
      orders.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return orders;
    });
  }

  Future<void> updateOrderStatus(
    String orderId,
    OrderStatus status, {
    String? shiftId,
    String? cashierId,
    String? cashierName,
    bool autoAccepted = false,
    String? acceptedBy,
    String? acceptedByName,
  }) async {
    final snapshot = await _ordersRef.doc(orderId).get();
    final current = snapshot.data();
    final parsed = current == null ? null : Order.fromMap(orderId, current);
    if (parsed != null &&
        parsed.isHeldByDriver &&
        status != parsed.status &&
        !AdminAuthService.instance.isSuperAdmin) {
      throw Exception(Order.driverCustodyLockMessage);
    }
    final timeline = (parsed?.statusTimeline ?? const OrderStatusTimeline())
        .stampForOrderStatus(status, createdAt: parsed?.createdAt);
    await _ordersRef.doc(orderId).update({
      'status': status.storageValue,
      if (autoAccepted) 'autoAccepted': true,
      if (acceptedBy != null && acceptedBy.isNotEmpty) 'acceptedBy': acceptedBy,
      if (acceptedByName != null && acceptedByName.isNotEmpty)
        'acceptedByName': acceptedByName,
      if (shiftId != null && shiftId.isNotEmpty) 'shiftId': shiftId,
      if (cashierId != null && cashierId.isNotEmpty) 'cashierId': cashierId,
      if (cashierName != null && cashierName.isNotEmpty) 'cashierName': cashierName,
      'status_timeline': timeline.toMap(),
      if (timeline.createdAt != null)
        'created_at': timeline.createdAt!.toUtc().toIso8601String(),
      if (timeline.acceptedAt != null)
        'accepted_at': timeline.acceptedAt!.toUtc().toIso8601String(),
      if (timeline.deliveredAt != null)
        'delivered_at': timeline.deliveredAt!.toUtc().toIso8601String(),
    });
  }

  Future<void> refreshOrders() async {
    // Orders are delivered via [watchOrders]; this exists for API compatibility.
  }
}
