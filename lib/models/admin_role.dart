enum AdminRole {
  superAdmin('super_admin'),
  restaurantAdmin('restaurant_admin');

  const AdminRole(this.storageKey);

  final String storageKey;

  static AdminRole? fromStorageKey(String? value) {
    if (value == null) return null;
    for (final role in AdminRole.values) {
      if (role.storageKey == value) return role;
    }
    return null;
  }

  bool get isSuperAdmin => this == AdminRole.superAdmin;
  bool get isRestaurantAdmin => this == AdminRole.restaurantAdmin;
}
