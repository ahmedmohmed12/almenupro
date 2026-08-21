import 'admin_role.dart';

enum RestaurantStatus {
  active,
  inactive,
  suspended;

  static RestaurantStatus fromValue(String? raw) {
    switch (raw?.trim().toLowerCase()) {
      case 'inactive':
        return RestaurantStatus.inactive;
      case 'suspended':
        return RestaurantStatus.suspended;
      default:
        return RestaurantStatus.active;
    }
  }

  String get apiValue {
    switch (this) {
      case RestaurantStatus.inactive:
        return 'inactive';
      case RestaurantStatus.suspended:
        return 'suspended';
      case RestaurantStatus.active:
        return 'active';
    }
  }

  String get labelAr {
    switch (this) {
      case RestaurantStatus.inactive:
        return 'موقوف';
      case RestaurantStatus.suspended:
        return 'معلّق';
      case RestaurantStatus.active:
        return 'نشط';
    }
  }
}

enum SubscriptionPlan {
  free,
  basic,
  pro,
  enterprise;

  static SubscriptionPlan fromValue(String? raw) {
    switch (raw?.trim().toLowerCase()) {
      case 'basic':
        return SubscriptionPlan.basic;
      case 'pro':
        return SubscriptionPlan.pro;
      case 'enterprise':
        return SubscriptionPlan.enterprise;
      default:
        return SubscriptionPlan.free;
    }
  }

  String get apiValue {
    switch (this) {
      case SubscriptionPlan.basic:
        return 'basic';
      case SubscriptionPlan.pro:
        return 'pro';
      case SubscriptionPlan.enterprise:
        return 'enterprise';
      case SubscriptionPlan.free:
        return 'free';
    }
  }

  String get labelAr {
    switch (this) {
      case SubscriptionPlan.basic:
        return 'أساسي';
      case SubscriptionPlan.pro:
        return 'احترافي';
      case SubscriptionPlan.enterprise:
        return 'مؤسسات';
      case SubscriptionPlan.free:
        return 'مجاني';
    }
  }
}

enum SubscriptionStatus {
  active,
  trial,
  expired,
  cancelled;

  static SubscriptionStatus fromValue(String? raw) {
    switch (raw?.trim().toLowerCase()) {
      case 'trial':
        return SubscriptionStatus.trial;
      case 'expired':
        return SubscriptionStatus.expired;
      case 'cancelled':
        return SubscriptionStatus.cancelled;
      default:
        return SubscriptionStatus.active;
    }
  }

  String get apiValue {
    switch (this) {
      case SubscriptionStatus.trial:
        return 'trial';
      case SubscriptionStatus.expired:
        return 'expired';
      case SubscriptionStatus.cancelled:
        return 'cancelled';
      case SubscriptionStatus.active:
        return 'active';
    }
  }

  String get labelAr {
    switch (this) {
      case SubscriptionStatus.trial:
        return 'تجريبي';
      case SubscriptionStatus.expired:
        return 'منتهي';
      case SubscriptionStatus.cancelled:
        return 'ملغى';
      case SubscriptionStatus.active:
        return 'ساري';
    }
  }
}

class Restaurant {
  const Restaurant({
    required this.id,
    required this.slug,
    required this.name,
    this.ownerName = '',
    this.phone = '',
    this.status = RestaurantStatus.active,
    this.subscriptionPlan = SubscriptionPlan.free,
    this.subscriptionStatus = SubscriptionStatus.active,
    this.subscriptionExpiresAt,
    this.subscriptionNotes = '',
    this.tableManagementEnabled = false,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String slug;
  final String name;
  final String ownerName;
  final String phone;
  final RestaurantStatus status;
  final SubscriptionPlan subscriptionPlan;
  final SubscriptionStatus subscriptionStatus;
  final DateTime? subscriptionExpiresAt;
  final String subscriptionNotes;
  final bool tableManagementEnabled;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get isActive => status == RestaurantStatus.active;

  factory Restaurant.fromJson(Map<String, dynamic> json) {
    return Restaurant(
      id: json['id']?.toString() ?? '',
      slug: json['slug']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      ownerName:
          json['ownerName']?.toString() ?? json['owner_name']?.toString() ?? '',
      phone: json['phone']?.toString() ??
          json['ownerPhone']?.toString() ??
          json['owner_phone']?.toString() ??
          '',
      status: RestaurantStatus.fromValue(json['status']?.toString()),
      subscriptionPlan: SubscriptionPlan.fromValue(
        json['subscriptionPlan']?.toString() ?? json['subscription_plan']?.toString(),
      ),
      subscriptionStatus: SubscriptionStatus.fromValue(
        json['subscriptionStatus']?.toString() ??
            json['subscription_status']?.toString(),
      ),
      subscriptionExpiresAt: DateTime.tryParse(
        json['subscriptionExpiresAt']?.toString() ??
            json['subscription_expires_at']?.toString() ??
            '',
      ),
      subscriptionNotes: json['subscriptionNotes']?.toString() ??
          json['subscription_notes']?.toString() ??
          '',
      tableManagementEnabled: json['tableManagementEnabled'] == true ||
          json['tableManagement'] == true ||
          (json['features'] is Map &&
              (json['features']['tableManagement'] == true ||
                  json['features']['table_management'] == true)),
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? ''),
      updatedAt: DateTime.tryParse(
        json['updatedAt']?.toString() ?? json['updated_at']?.toString() ?? '',
      ),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'slug': slug,
        'name': name,
        'ownerName': ownerName,
        'phone': phone,
        'status': status.apiValue,
        'subscriptionPlan': subscriptionPlan.apiValue,
        'subscriptionStatus': subscriptionStatus.apiValue,
        if (subscriptionExpiresAt != null)
          'subscriptionExpiresAt': subscriptionExpiresAt!.toIso8601String(),
        if (subscriptionNotes.isNotEmpty) 'subscriptionNotes': subscriptionNotes,
        'tableManagement': tableManagementEnabled,
        'features': {'tableManagement': tableManagementEnabled},
        if (createdAt != null) 'createdAt': createdAt!.toIso8601String(),
        if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
      };

  Restaurant copyWith({
    String? id,
    String? slug,
    String? name,
    String? ownerName,
    String? phone,
    RestaurantStatus? status,
    SubscriptionPlan? subscriptionPlan,
    SubscriptionStatus? subscriptionStatus,
    DateTime? subscriptionExpiresAt,
    String? subscriptionNotes,
    bool? tableManagementEnabled,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Restaurant(
      id: id ?? this.id,
      slug: slug ?? this.slug,
      name: name ?? this.name,
      ownerName: ownerName ?? this.ownerName,
      phone: phone ?? this.phone,
      status: status ?? this.status,
      subscriptionPlan: subscriptionPlan ?? this.subscriptionPlan,
      subscriptionStatus: subscriptionStatus ?? this.subscriptionStatus,
      subscriptionExpiresAt: subscriptionExpiresAt ?? this.subscriptionExpiresAt,
      subscriptionNotes: subscriptionNotes ?? this.subscriptionNotes,
      tableManagementEnabled:
          tableManagementEnabled ?? this.tableManagementEnabled,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

class AdminSession {
  const AdminSession({
    required this.token,
    required this.role,
    this.restaurantId,
    this.restaurantName,
    this.staffId,
    this.staffName,
  });

  final String token;
  final AdminRole role;
  final String? restaurantId;
  final String? restaurantName;
  final String? staffId;
  final String? staffName;

  bool get isSuperAdmin => role.isSuperAdmin;
  bool get isRestaurantAdmin => role.isRestaurantAdmin;
  bool get isCashier => role.isCashier;

  factory AdminSession.fromJson(Map<String, dynamic> json) {
    return AdminSession(
      token: json['token']?.toString() ?? '',
      role: AdminRole.fromStorageKey(json['role']?.toString()) ??
          AdminRole.restaurantAdmin,
      restaurantId: json['restaurantId']?.toString(),
      restaurantName: json['restaurantName']?.toString(),
      staffId: json['staffId']?.toString() ?? json['staff_id']?.toString(),
      staffName: json['staffName']?.toString() ?? json['staff_name']?.toString(),
    );
  }
}
