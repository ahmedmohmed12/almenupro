import '../models/cart_item.dart';
import '../models/dining_table.dart';
import '../models/menu_item.dart';
import '../models/order.dart';
import 'admin_auth_service.dart';
import 'api_service.dart';

class DiningTablesService {
  DiningTablesService._();

  static final DiningTablesService instance = DiningTablesService._();

  Future<List<DiningTable>> fetchTables() async {
    final decoded = await ApiService.instance.getJson('/tables');
    final raw = decoded['tables'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((entry) => DiningTable.fromJson(Map<String, dynamic>.from(entry)))
        .toList();
  }

  Future<DiningTable> createTable({
    required String number,
    String name = '',
    String zone = 'الصالة الرئيسية',
    int capacity = 2,
    int sortOrder = 0,
  }) async {
    final decoded = await ApiService.instance.postJson('/tables', {
      'number': number,
      'name': name,
      'zone': zone,
      'capacity': capacity,
      'sortOrder': sortOrder,
    });
    return DiningTable.fromJson(decoded);
  }

  Future<DiningTable> updateTable(DiningTable table) async {
    final decoded = await ApiService.instance.patchJson(
      '/tables/${table.id}',
      table.toPayload(),
    );
    return DiningTable.fromJson(decoded);
  }

  Future<void> deleteTable(String tableId) async {
    await ApiService.instance.deleteJson('/tables/$tableId');
  }

  Future<DiningTable> openSession(
    String tableId, {
    List<CartItem> cartItems = const [],
    String notes = '',
  }) async {
    final decoded = await ApiService.instance.postJson(
      '/tables/$tableId/open-session',
      {
        'staffId': AdminAuthService.instance.session?.staffId,
        'staffName': AdminAuthService.instance.session?.staffName ??
            AdminAuthService.instance.restaurantName,
        'cartItems': cartItems.map(cartItemToSessionMap).toList(),
        'notes': notes,
      },
    );
    final tableRaw = decoded['table'];
    if (tableRaw is Map) {
      return DiningTable.fromJson(Map<String, dynamic>.from(tableRaw));
    }
    return DiningTable.fromJson(decoded);
  }

  Future<DiningTable> updateSession(
    String tableId, {
    required List<CartItem> cartItems,
    String? notes,
    String? customerName,
    String? phone,
  }) async {
    final decoded = await ApiService.instance.putJson('/tables/$tableId/session', {
      'cartItems': cartItems.map(cartItemToSessionMap).toList(),
      if (notes != null) 'notes': notes,
      if (customerName != null) 'customerName': customerName,
      if (phone != null) 'phone': phone,
    });
    return DiningTable.fromJson(decoded);
  }

  Future<({Order order, DiningTable table})> sendKitchen(
    String tableId, {
    required List<CartItem> cartItems,
    String? customerName,
    String? phone,
  }) async {
    final decoded = await ApiService.instance.postJson(
      '/tables/$tableId/send-kitchen',
      {
        'cartItems': cartItems.map(cartItemToSessionMap).toList(),
        if (customerName != null) 'customerName': customerName,
        if (phone != null) 'phone': phone,
      },
    );
    return _parseOrderTable(decoded);
  }

  Future<({Order order, DiningTable table})> checkout(
    String tableId, {
    required List<CartItem> cartItems,
    required String paymentMethod,
    String? customerName,
    String? phone,
    String? invoiceNumber,
  }) async {
    final decoded = await ApiService.instance.postJson(
      '/tables/$tableId/checkout',
      {
        'cartItems': cartItems.map(cartItemToSessionMap).toList(),
        'paymentMethod': paymentMethod,
        if (customerName != null) 'customerName': customerName,
        if (phone != null) 'phone': phone,
        if (invoiceNumber != null) 'invoiceNumber': invoiceNumber,
      },
    );
    return _parseOrderTable(decoded);
  }

  Future<DiningTable> release(String tableId) async {
    final decoded = await ApiService.instance.postJson(
      '/tables/$tableId/release',
      const {},
    );
    final tableRaw = decoded['table'];
    if (tableRaw is Map) {
      return DiningTable.fromJson(Map<String, dynamic>.from(tableRaw));
    }
    return DiningTable.fromJson(decoded);
  }

  static Map<String, dynamic> cartItemToSessionMap(CartItem item) {
    return {
      'id': item.id,
      'menuItemId': item.menuItem.id.toString(),
      'name': item.menuItem.name,
      'unitPrice': item.unitPrice,
      'quantity': item.quantity,
      'selectedOptions': item.selectedOptions.map((option) => option.toMap()).toList(),
      if (item.specialNotes != null && item.specialNotes!.isNotEmpty)
        'specialNotes': item.specialNotes,
      if (item.offerId != null && item.offerId!.isNotEmpty) 'offerId': item.offerId,
      'lineTotal': item.totalPrice,
      'menuItem': item.menuItem.toMap(),
    };
  }

  static List<CartItem> cartItemsFromSession(
    List<Map<String, dynamic>> raw, {
    List<MenuItem> catalog = const [],
  }) {
    return raw.map((entry) {
      MenuItem? menuItem;
      final nested = entry['menuItem'] ?? entry['menu_item'];
      if (nested is Map) {
        menuItem = MenuItem.fromJson(Map<String, dynamic>.from(nested));
      } else {
        final id =
            entry['menuItemId']?.toString() ?? entry['menu_item_id']?.toString();
        if (id != null) {
          for (final item in catalog) {
            if (item.id.toString() == id) {
              menuItem = item;
              break;
            }
          }
        }
      }
      menuItem ??= MenuItem.fromJson({
        'id': entry['menuItemId'] ?? DateTime.now().millisecondsSinceEpoch,
        'name': entry['name'] ?? 'صنف',
        'price': entry['unitPrice'] ?? 0,
      });
      final rawOptions = entry['selectedOptions'] as List<dynamic>? ?? [];
      return CartItem(
        id: entry['id']?.toString() ??
            '${menuItem.id}_${DateTime.now().microsecondsSinceEpoch}',
        menuItem: menuItem,
        selectedOptions: rawOptions
            .whereType<Map>()
            .map((option) => SelectedOption.fromMap(Map<String, dynamic>.from(option)))
            .toList(),
        quantity: (entry['quantity'] as num?)?.toInt() ?? 1,
        specialNotes: entry['specialNotes']?.toString(),
        offerId: entry['offerId']?.toString(),
      );
    }).toList();
  }

  ({Order order, DiningTable table}) _parseOrderTable(Map<String, dynamic> decoded) {
    final orderRaw = decoded['order'];
    final tableRaw = decoded['table'];
    if (orderRaw is! Map || tableRaw is! Map) {
      throw Exception('استجابة غير متوقعة من السيرفر');
    }
    final orderMap = Map<String, dynamic>.from(orderRaw);
    return (
      order: Order.fromMap(orderMap['id']?.toString() ?? '', orderMap),
      table: DiningTable.fromJson(Map<String, dynamic>.from(tableRaw)),
    );
  }
}
