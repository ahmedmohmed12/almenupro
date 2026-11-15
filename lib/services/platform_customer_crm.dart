import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/customer.dart';
import '../models/order.dart';
import '../models/platform_customer_profile.dart';

/// Saves Talabat/Keeta (and Jahez) customers into the local AlMenuPro store.
class PlatformCustomerCrm {
  PlatformCustomerCrm._();

  static const missingName = 'عميل منصات';

  static List<PlatformCustomerProfile> upsertPayload(
    List<PlatformCustomerProfile> customers,
    Map<String, dynamic> payload,
  ) {
    if (!isPlatformPayload(payload)) return customers;
    final phone = extractPhone(payload);
    final digits = phoneDigits(phone);
    if (digits.length < 8) return customers;

    final incomingName = extractName(payload);
    final address = extractAddress(payload);
    final invoice = extractInvoice(payload, address);
    final now = DateTime.now();
    final index = customers.indexWhere((customer) => phonesMatch(customer.phoneNumber, digits));

    if (index == -1) {
      final created = PlatformCustomerProfile(
        id: 'plat_$digits',
        phoneNumber: digits,
        customerName: resolveName(incomingName, null),
        address: address,
        addresses: address.isEmpty ? const [] : [address],
        invoices: invoice == null ? const [] : [invoice],
        createdAt: now,
        updatedAt: now,
      );
      return [created, ...customers];
    }

    final existing = customers[index];
    final storedDigits = phoneDigits(existing.phoneNumber);
    final nextPhone = digits.length >= storedDigits.length ? digits : storedDigits;
    final addresses = rememberAddress(existing.addresses, existing.address, address);
    final invoices = rememberInvoice(existing.invoices, invoice);
    final next = PlatformCustomerProfile(
      id: existing.id,
      phoneNumber: nextPhone,
      customerName: resolveName(incomingName, existing.customerName),
      address: address.isNotEmpty ? address : existing.address,
      addresses: addresses,
      invoices: invoices,
      createdAt: existing.createdAt,
      updatedAt: now,
    );
    if (_sameProfile(existing, next)) return customers;
    final copy = [...customers];
    copy[index] = next;
    return copy;
  }

  static List<PlatformCustomerProfile> upsertOrder(
    List<PlatformCustomerProfile> customers,
    Order order,
  ) {
    return upsertPayload(customers, payloadFromOrder(order));
  }

  static Map<String, dynamic> payloadFromOrder(Order order) {
    return {
      'id': order.id,
      'phone_number': order.phone,
      'customerName': order.customerName,
      'address': order.address,
      'orderSource': order.orderSource,
      'invoiceNumber': order.invoiceNumber,
      'externalOrderId': order.externalOrderId,
      'totalPrice': order.customerPayable,
      'createdAt': order.createdAt.toIso8601String(),
    };
  }

  static bool isPlatformPayload(Map<String, dynamic> payload) {
    final source = _firstText([
      payload['orderSource'],
      payload['order_source'],
      payload['platform'],
      payload['salesPlatform'],
    ]).toLowerCase();
    return source.contains('talabat') ||
        source.contains('keeta') ||
        source.contains('keta') ||
        source.contains('jahez');
  }

  static String extractPhone(Map<String, dynamic> payload) {
    final customer = _nested(payload['customer']);
    return _firstText([
      payload['phone_number'],
      payload['phone'],
      payload['customer_phone'],
      payload['customerPhone'],
      customer['phone_number'],
      customer['phone'],
      customer['mobile'],
    ]);
  }

  static String extractName(Map<String, dynamic> payload) {
    final customer = _nested(payload['customer']);
    return _firstText([
      payload['customerName'],
      payload['customer_name'],
      payload['name'],
      customer['name'],
      customer['customerName'],
      customer['customer_name'],
    ]);
  }

  static String extractAddress(Map<String, dynamic> payload) {
    final customer = _nested(payload['customer']);
    return _firstText([
      payload['address'],
      payload['delivery_address'],
      payload['deliveryAddress'],
      customer['address'],
      customer['delivery_address'],
    ]);
  }

  static PlatformCustomerInvoice? extractInvoice(
    Map<String, dynamic> payload,
    String address,
  ) {
    final orderId = _firstText([
      payload['id'],
      payload['orderId'],
      payload['order_id'],
    ]);
    if (orderId.isEmpty) return null;
    final invoiceNumber = _firstText([
      payload['invoiceNumber'],
      payload['invoice_number'],
      payload['externalOrderId'],
      payload['external_order_id'],
      orderId,
    ]);
    final platform = _firstText([
      payload['orderSource'],
      payload['order_source'],
      payload['platform'],
    ]).toLowerCase();
    final total = (payload['customerPayableTotal'] as num?)?.toDouble() ??
        (payload['customer_payable_total'] as num?)?.toDouble() ??
        (payload['totalPrice'] as num?)?.toDouble() ??
        (payload['total'] as num?)?.toDouble() ??
        0;
    return PlatformCustomerInvoice(
      orderId: orderId,
      invoiceNumber: invoiceNumber,
      platform: platform,
      total: total,
      address: address,
      createdAt: DateTime.tryParse(payload['createdAt']?.toString() ?? ''),
    );
  }

  static String resolveName(String incoming, String? existing) {
    final cleaned = incoming.trim();
    final saved = existing?.trim() ?? '';
    final incomingMissing = isMissingName(cleaned) || cleaned == missingName;
    final savedMissing = saved.isEmpty || isMissingName(saved) || saved == missingName;
    if (!incomingMissing) return cleaned;
    if (!savedMissing) return saved;
    return missingName;
  }

  static bool isMissingName(String value) {
    final text = value.trim();
    if (text.isEmpty) return true;
    if (RegExp(r'^\*+$').hasMatch(text) || text.contains('**')) return true;
    return RegExp(
      r'^(unknown|customer|n/a|na|null|undefined|عميل|بدون اسم)$',
      caseSensitive: false,
    ).hasMatch(text);
  }

  static String phoneDigits(String raw) => raw.replaceAll(RegExp(r'\D'), '');

  static bool phonesMatch(String stored, String lookup) {
    final left = phoneDigits(stored);
    final right = phoneDigits(lookup);
    if (left.isEmpty || right.isEmpty) return false;
    if (left == right) return true;
    if (left.length >= 8 && right.length >= 8) {
      return left.substring(left.length - 8) == right.substring(right.length - 8);
    }
    return false;
  }

  static List<String> rememberAddress(
    List<String> existing,
    String current,
    String incoming,
  ) {
    final next = <String>[];
    void add(String value) {
      final text = value.trim();
      if (text.isEmpty) return;
      final known = next.any((row) => row.toLowerCase() == text.toLowerCase());
      if (!known) next.add(text);
    }

    add(incoming);
    add(current);
    for (final row in existing) {
      add(row);
    }
    return next;
  }

  static List<PlatformCustomerInvoice> rememberInvoice(
    List<PlatformCustomerInvoice> existing,
    PlatformCustomerInvoice? invoice,
  ) {
    if (invoice == null || invoice.orderId.isEmpty) return existing;
    if (existing.any((row) => row.orderId == invoice.orderId)) return existing;
    return [invoice, ...existing];
  }

  static List<Customer> mergeIntoAdminList(
    List<Customer> apiCustomers,
    List<PlatformCustomerProfile> profiles,
  ) {
    final merged = [...apiCustomers];
    for (final profile in profiles) {
      final index = merged.indexWhere((customer) => phonesMatch(customer.phone, profile.phoneNumber));
      if (index == -1) {
        merged.add(profile.toCustomer());
        continue;
      }
      final existing = merged[index];
      final combined = rememberAddress(
        [...profile.addresses, ...existing.addresses],
        existing.formattedAddress,
        profile.address,
      );
      merged[index] = Customer(
        id: existing.id,
        phone: existing.phone.trim().isNotEmpty ? existing.phone : profile.phoneNumber,
        customerName: resolveName(profile.customerName, existing.customerName),
        formattedAddress: combined.isNotEmpty ? combined.first : existing.formattedAddress,
        governorate: existing.governorate,
        areaName: existing.areaName,
        deliveryZoneId: existing.deliveryZoneId,
        addressDetails: existing.addressDetails,
        paymentMethod: existing.paymentMethod,
        totalOrders: existing.totalOrders >= profile.invoices.length
            ? existing.totalOrders
            : profile.invoices.length,
        addresses: combined,
        createdAt: existing.createdAt,
        updatedAt: profile.updatedAt ?? existing.updatedAt,
      );
    }
    return merged;
  }

  static CustomerDetailData overlayDetail(
    CustomerDetailData detail,
    PlatformCustomerProfile profile,
  ) {
    final addresses = <String>[];
    void add(String value) {
      final text = value.trim();
      if (text.isEmpty) return;
      if (addresses.any((row) => row.toLowerCase() == text.toLowerCase())) return;
      addresses.add(text);
    }

    for (final row in profile.addresses) {
      add(row);
    }
    add(profile.address);
    for (final row in detail.customer.addresses) {
      add(row);
    }
    add(detail.customer.formattedAddress);
    final orders = mergeOrderHistory(detail.rawOrders, profile);
    final customer = Customer(
      id: detail.customer.id,
      phone: detail.customer.phone.trim().isNotEmpty
          ? detail.customer.phone
          : profile.phoneNumber,
      customerName: resolveName(profile.customerName, detail.customer.customerName),
      formattedAddress: addresses.isNotEmpty ? addresses.first : detail.customer.formattedAddress,
      governorate: detail.customer.governorate,
      areaName: detail.customer.areaName,
      deliveryZoneId: detail.customer.deliveryZoneId,
      addressDetails: detail.customer.addressDetails,
      paymentMethod: detail.customer.paymentMethod,
      totalOrders: orders.length,
      addresses: addresses,
      createdAt: detail.customer.createdAt,
      updatedAt: detail.customer.updatedAt,
    );
    return CustomerDetailData(customer: customer, rawOrders: orders);
  }

  static List<Map<String, dynamic>> mergeOrderHistory(
    List<Map<String, dynamic>> apiOrders,
    PlatformCustomerProfile profile,
  ) {
    final seen = <String>{};
    final merged = <Map<String, dynamic>>[];
    void add(Map<String, dynamic> raw) {
      final id = (raw['id'] ?? raw['orderId'] ?? raw['order_id'])?.toString() ?? '';
      if (id.isEmpty || !seen.add(id)) return;
      merged.add(raw);
    }

    for (final raw in apiOrders) {
      add(Map<String, dynamic>.from(raw));
    }
    for (final raw in profile.toDetail().rawOrders) {
      add(raw);
    }
    return merged;
  }

  static bool _sameProfile(PlatformCustomerProfile left, PlatformCustomerProfile right) {
    return left.customerName == right.customerName &&
        left.address == right.address &&
        left.phoneNumber == right.phoneNumber &&
        left.addresses.length == right.addresses.length &&
        left.invoices.length == right.invoices.length;
  }

  static Map<String, dynamic> _nested(Object? raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return const {};
  }

  static String _firstText(List<Object?> values) {
    for (final value in values) {
      final text = value?.toString().trim() ?? '';
      if (text.isNotEmpty) return text;
    }
    return '';
  }
}

class PlatformCustomerCrmStore {
  PlatformCustomerCrmStore._();

  static final PlatformCustomerCrmStore instance = PlatformCustomerCrmStore._();

  static const _keyPrefix = 'platform_customer_crm_';

  String _key(String restaurantId) => '$_keyPrefix${restaurantId.trim()}';

  Future<List<PlatformCustomerProfile>> read(String restaurantId) async {
    final prefs = await SharedPreferences.getInstance();
    return _decode(prefs.getString(_key(restaurantId)));
  }

  Future<List<PlatformCustomerProfile>> ingestOrders({
    required String restaurantId,
    required List<Order> orders,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _key(restaurantId);
    final stored = _decode(prefs.getString(key));
    var customers = stored;
    for (final order in orders) {
      customers = PlatformCustomerCrm.upsertOrder(customers, order);
    }
    if (!identical(customers, stored)) {
      await prefs.setString(
        key,
        jsonEncode(customers.map((customer) => customer.toMap()).toList()),
      );
    }
    return customers;
  }

  Future<PlatformCustomerProfile?> findById(String restaurantId, String customerId) async {
    final customers = await read(restaurantId);
    for (final customer in customers) {
      if (customer.id == customerId) return customer;
    }
    return null;
  }

  Future<PlatformCustomerProfile?> findByPhone(String restaurantId, String phone) async {
    final customers = await read(restaurantId);
    for (final customer in customers) {
      if (PlatformCustomerCrm.phonesMatch(customer.phoneNumber, phone)) return customer;
    }
    return null;
  }

  static List<PlatformCustomerProfile> _decode(String? raw) {
    if (raw == null || raw.trim().isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((row) => PlatformCustomerProfile.fromMap(Map<String, dynamic>.from(row)))
          .where((customer) => customer.phoneNumber.isNotEmpty)
          .toList();
    } catch (_) {
      return const [];
    }
  }
}
