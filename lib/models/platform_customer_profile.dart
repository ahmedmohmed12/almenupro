import 'customer.dart';

class PlatformCustomerInvoice {
  const PlatformCustomerInvoice({
    required this.orderId,
    required this.invoiceNumber,
    required this.platform,
    required this.total,
    this.address = '',
    this.createdAt,
  });

  final String orderId;
  final String invoiceNumber;
  final String platform;
  final double total;
  final String address;
  final DateTime? createdAt;

  Map<String, dynamic> toMap() {
    return {
      'orderId': orderId,
      'invoiceNumber': invoiceNumber,
      'platform': platform,
      'total': total,
      'address': address,
      if (createdAt != null) 'createdAt': createdAt!.toIso8601String(),
    };
  }

  factory PlatformCustomerInvoice.fromMap(Map<String, dynamic> map) {
    return PlatformCustomerInvoice(
      orderId: map['orderId']?.toString() ?? map['order_id']?.toString() ?? '',
      invoiceNumber:
          map['invoiceNumber']?.toString() ?? map['invoice_number']?.toString() ?? '',
      platform: map['platform']?.toString() ?? map['orderSource']?.toString() ?? '',
      total: (map['total'] as num?)?.toDouble() ??
          (map['totalPrice'] as num?)?.toDouble() ??
          0,
      address: map['address']?.toString() ?? '',
      createdAt: DateTime.tryParse(map['createdAt']?.toString() ?? ''),
    );
  }
}

class PlatformCustomerProfile {
  const PlatformCustomerProfile({
    required this.id,
    required this.phoneNumber,
    required this.customerName,
    required this.address,
    this.addresses = const [],
    this.invoices = const [],
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String phoneNumber;
  final String customerName;
  final String address;
  final List<String> addresses;
  final List<PlatformCustomerInvoice> invoices;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'phone_number': phoneNumber,
      'phone': phoneNumber,
      'customerName': customerName,
      'address': address,
      'addresses': addresses,
      'invoices': invoices.map((invoice) => invoice.toMap()).toList(),
      if (createdAt != null) 'createdAt': createdAt!.toIso8601String(),
      if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
    };
  }

  factory PlatformCustomerProfile.fromMap(Map<String, dynamic> map) {
    final invoicesRaw = map['invoices'];
    final addressesRaw = map['addresses'];
    return PlatformCustomerProfile(
      id: map['id']?.toString() ?? '',
      phoneNumber: map['phone_number']?.toString() ?? map['phone']?.toString() ?? '',
      customerName: map['customerName']?.toString() ?? map['customer_name']?.toString() ?? '',
      address: map['address']?.toString() ?? '',
      addresses: addressesRaw is List
          ? addressesRaw.map((row) => row.toString().trim()).where((row) => row.isNotEmpty).toList()
          : const [],
      invoices: invoicesRaw is List
          ? invoicesRaw
              .whereType<Map>()
              .map((row) => PlatformCustomerInvoice.fromMap(Map<String, dynamic>.from(row)))
              .where((invoice) => invoice.orderId.isNotEmpty)
              .toList()
          : const [],
      createdAt: DateTime.tryParse(map['createdAt']?.toString() ?? ''),
      updatedAt: DateTime.tryParse(map['updatedAt']?.toString() ?? ''),
    );
  }

  Customer toCustomer() {
    final savedAddresses = addresses.isNotEmpty
        ? addresses
        : (address.trim().isEmpty ? const <String>[] : [address.trim()]);
    return Customer(
      id: id,
      phone: phoneNumber,
      customerName: customerName,
      formattedAddress: address,
      addresses: savedAddresses,
      totalOrders: invoices.length,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  CustomerDetailData toDetail() {
    final rawOrders = invoices.map((invoice) {
      return <String, dynamic>{
        'id': invoice.orderId,
        'customerName': customerName,
        'phone': phoneNumber,
        'address': invoice.address.isNotEmpty ? invoice.address : address,
        'items': const <Map<String, dynamic>>[],
        'totalPrice': invoice.total,
        'invoiceNumber': invoice.invoiceNumber,
        'orderSource': invoice.platform,
        'status': 'delivered',
        'createdAt': (invoice.createdAt ?? createdAt ?? DateTime.now()).toIso8601String(),
      };
    }).toList();
    return CustomerDetailData(
      customer: toCustomer(),
      rawOrders: rawOrders,
    );
  }
}
