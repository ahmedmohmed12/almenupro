class StaffUser {
  const StaffUser({
    required this.id,
    required this.name,
    required this.roleId,
    this.isActive = true,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String name;
  final String roleId;
  final bool isActive;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory StaffUser.fromJson(Map<String, dynamic> json) {
    return StaffUser(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      roleId: json['roleId']?.toString() ?? json['role_id']?.toString() ?? 'cashier',
      isActive: json['isActive'] != false && json['is_active'] != false,
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? ''),
      updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? ''),
    );
  }

  Map<String, dynamic> toJson({String? pin}) => {
        'id': id,
        'name': name,
        'roleId': roleId,
        'isActive': isActive,
        if (pin != null && pin.isNotEmpty) 'pin': pin,
      };
}

class PosCashierSession {
  const PosCashierSession({
    required this.staff,
    required this.permissions,
    this.roleId = '',
  });

  final StaffUser staff;
  final Map<String, bool> permissions;
  final String roleId;

  bool allows(String permission) => permissions[permission] == true;

  factory PosCashierSession.fromJson(Map<String, dynamic> json) {
    final rawPermissions = json['permissions'];
    final permissions = <String, bool>{};
    if (rawPermissions is Map) {
      rawPermissions.forEach((key, value) {
        permissions[key.toString()] = value == true;
      });
    }
    return PosCashierSession(
      staff: StaffUser.fromJson(Map<String, dynamic>.from(json['staff'] as Map? ?? {})),
      permissions: permissions,
      roleId: json['role'] is Map
          ? (json['role'] as Map)['id']?.toString() ?? ''
          : json['roleId']?.toString() ?? '',
    );
  }
}

class ManagerOverrideResult {
  const ManagerOverrideResult({
    required this.authorized,
    this.authorizedById,
    this.authorizedByName,
  });

  final bool authorized;
  final String? authorizedById;
  final String? authorizedByName;

  factory ManagerOverrideResult.fromJson(Map<String, dynamic> json) {
    return ManagerOverrideResult(
      authorized: json['authorized'] == true,
      authorizedById: json['authorizedById']?.toString(),
      authorizedByName: json['authorizedByName']?.toString(),
    );
  }
}
