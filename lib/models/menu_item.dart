import '../utils/image_url.dart';

class MenuOption {
  const MenuOption({
    required this.id,
    required this.name,
    required this.group,
    this.nameAr = '',
    this.nameEn = '',
    this.price = 0,
    this.isRequired = false,
    this.groupRequired = false,
    this.allowMultiple = false,
    this.isAvailable = true,
    this.linkedMenuItemId,
  });

  final String id;
  final String name;
  final String nameAr;
  final String nameEn;
  final String group;
  final double price;
  /// Legacy alias — prefer [groupRequired].
  final bool isRequired;
  final bool groupRequired;
  final bool allowMultiple;
  final bool isAvailable;
  /// When set, this modifier references another menu item (advanced side item).
  final int? linkedMenuItemId;

  bool get isGroupRequired => groupRequired || isRequired;

  String localizedName(String localeCode) {
    if (localeCode.startsWith('en')) {
      if (nameEn.trim().isNotEmpty) return nameEn.trim();
      if (nameAr.trim().isNotEmpty) return nameAr.trim();
      return name;
    }
    if (nameAr.trim().isNotEmpty) return nameAr.trim();
    if (nameEn.trim().isNotEmpty) return nameEn.trim();
    return name;
  }

  factory MenuOption.fromMap(Map<String, dynamic> map) {
    final groupRequired = map['groupRequired'] == true ||
        map['group_required'] == true ||
        map['isRequired'] == true;
    final isAvailable = !(map['is_available'] == 0 ||
        map['is_available'] == false ||
        map['isAvailable'] == false);

    return MenuOption(
      id: map['id']?.toString() ?? '',
      name: map['name']?.toString() ?? '',
      nameAr: map['name_ar']?.toString() ?? map['nameAr']?.toString() ?? '',
      nameEn: map['name_en']?.toString() ?? map['nameEn']?.toString() ?? '',
      group: map['group']?.toString() ?? 'إضافات',
      price: (map['price'] as num?)?.toDouble() ?? 0,
      isRequired: groupRequired,
      groupRequired: groupRequired,
      allowMultiple:
          map['allowMultiple'] == true || map['allow_multiple'] == true,
      isAvailable: isAvailable,
      linkedMenuItemId: _parseLinkedMenuItemId(map),
    );
  }

  static int? _parseLinkedMenuItemId(Map<String, dynamic> map) {
    final raw = map['linkedMenuItemId'] ??
        map['linked_menu_item_id'] ??
        map['linkedItemId'] ??
        map['linked_item_id'];
    if (raw == null || raw == '') return null;
    if (raw is int) return raw > 0 ? raw : null;
    return int.tryParse(raw.toString());
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': nameAr.isNotEmpty ? nameAr : name,
      if (nameAr.isNotEmpty) 'name_ar': nameAr,
      if (nameEn.isNotEmpty) 'name_en': nameEn,
      'group': group,
      'price': price,
      'groupRequired': isGroupRequired,
      'group_required': isGroupRequired,
      'allowMultiple': allowMultiple,
      'allow_multiple': allowMultiple,
      'isAvailable': isAvailable,
      'is_available': isAvailable ? 1 : 0,
      if (linkedMenuItemId != null) ...{
        'linkedMenuItemId': linkedMenuItemId,
        'linked_menu_item_id': linkedMenuItemId,
      },
    };
  }
}

class MenuItem {
  final int id;
  final int categoryId;
  final String categoryName;
  final String categoryNameEn;
  final String name;
  final String description;
  final String nameAr;
  final String nameEn;
  final String descriptionAr;
  final String descriptionEn;
  final double price;
  final String imageUrl;
  final int? talabatId;
  final bool isAvailable;
  final int displayOrder;
  final List<MenuOption> options;
  final List<int> linkedItemIds;

  MenuItem({
    required this.id,
    required this.categoryId,
    required this.categoryName,
    this.categoryNameEn = '',
    required this.name,
    required this.description,
    this.nameAr = '',
    this.nameEn = '',
    this.descriptionAr = '',
    this.descriptionEn = '',
    required this.price,
    required this.imageUrl,
    this.talabatId,
    required this.isAvailable,
    this.displayOrder = 0,
    this.options = const [],
    this.linkedItemIds = const [],
  });

  bool get hasCustomizations =>
      options.any((option) => option.isAvailable);

  List<MenuOption> get availableOptions =>
      options.where((option) => option.isAvailable).toList();

  String localizedName(String localeCode) {
    if (localeCode.startsWith('en')) {
      if (nameEn.trim().isNotEmpty) return nameEn.trim();
      if (nameAr.trim().isNotEmpty) return nameAr.trim();
      return name;
    }
    if (nameAr.trim().isNotEmpty) return nameAr.trim();
    if (nameEn.trim().isNotEmpty) return nameEn.trim();
    return name;
  }

  String localizedCategoryName(String localeCode) {
    if (localeCode.startsWith('en')) {
      if (categoryNameEn.trim().isNotEmpty) return categoryNameEn.trim();
      return categoryName;
    }
    return categoryName;
  }

  String localizedDescription(String localeCode) {
    if (localeCode.startsWith('en')) {
      if (descriptionEn.trim().isNotEmpty) return descriptionEn.trim();
      if (descriptionAr.trim().isNotEmpty) return descriptionAr.trim();
      return description;
    }
    if (descriptionAr.trim().isNotEmpty) return descriptionAr.trim();
    if (descriptionEn.trim().isNotEmpty) return descriptionEn.trim();
    return description;
  }

  /// Backward-compatible alias used by older screens.
  String get category => categoryName;

  /// Local Almenupro image path or absolute URL (`image_url` in API JSON).
  String get image_url => imageUrl;

  factory MenuItem.fromJson(Map<String, dynamic> json) {
    final nameAr =
        json['name_ar']?.toString() ?? json['nameAr']?.toString() ?? json['name']?.toString() ?? '';
    final nameEn = json['name_en']?.toString() ?? json['nameEn']?.toString() ?? '';
    final descriptionAr = json['description_ar']?.toString() ??
        json['descriptionAr']?.toString() ??
        json['description']?.toString() ??
        '';
    final descriptionEn =
        json['description_en']?.toString() ?? json['descriptionEn']?.toString() ?? '';

    return MenuItem(
      id: json['id'] is int ? json['id'] as int : int.parse(json['id'].toString()),
      categoryId: json['category_id'] is int
          ? json['category_id'] as int
          : int.parse(json['category_id']?.toString() ?? '0'),
      categoryName: json['category_name']?.toString() ?? '',
      categoryNameEn: json['category_name_en']?.toString() ??
          json['categoryNameEn']?.toString() ??
          '',
      name: json['name']?.toString() ?? nameAr,
      description: json['description']?.toString() ?? descriptionAr,
      nameAr: nameAr,
      nameEn: nameEn,
      descriptionAr: descriptionAr,
      descriptionEn: descriptionEn,
      price: double.parse(json['price'].toString()),
      imageUrl: normalizeMenuImageUrl(json['image_url'] ?? json['imageUrl']),
      talabatId: json['talabat_id'] is int
          ? json['talabat_id'] as int
          : int.tryParse(json['talabat_id']?.toString() ?? ''),
      isAvailable: json['is_available'] == 1 || json['is_available'] == true,
      displayOrder: (json['display_order'] as num?)?.toInt() ??
          (json['displayOrder'] as num?)?.toInt() ??
          0,
      options: (json['options'] as List<dynamic>? ?? [])
          .whereType<Map>()
          .map((option) => MenuOption.fromMap(Map<String, dynamic>.from(option)))
          .toList(),
      linkedItemIds: _parseLinkedItemIds(json),
    );
  }

  static List<int> _parseLinkedItemIds(Map<String, dynamic> json) {
    final raw = json['linkedItemIds'] as List<dynamic>? ??
        json['linked_item_ids'] as List<dynamic>? ??
        [];
    return raw
        .map((id) => int.tryParse(id.toString()))
        .whereType<int>()
        .where((id) => id > 0)
        .toList();
  }

  factory MenuItem.fromMap(String documentId, Map<String, dynamic> map) {
    final rawOptions = map['options'] as List<dynamic>? ?? [];
    final nameAr = map['name_ar']?.toString() ??
        map['nameAr']?.toString() ??
        map['name']?.toString() ??
        '';
    final nameEn = map['name_en']?.toString() ?? map['nameEn']?.toString() ?? '';
    final descriptionAr = map['description_ar']?.toString() ??
        map['descriptionAr']?.toString() ??
        map['description']?.toString() ??
        '';
    final descriptionEn =
        map['description_en']?.toString() ?? map['descriptionEn']?.toString() ?? '';

    return MenuItem(
      id: int.tryParse(documentId) ?? documentId.hashCode,
      categoryId: map['categoryId'] is int
          ? map['categoryId'] as int
          : int.tryParse(map['categoryId']?.toString() ?? '') ??
              int.tryParse(map['category_id']?.toString() ?? '') ??
              0,
      categoryName:
          (map['categoryName'] ?? map['category_name'] ?? map['category'] ?? '')
              .toString(),
      categoryNameEn: map['category_name_en']?.toString() ??
          map['categoryNameEn']?.toString() ??
          '',
      name: map['name']?.toString() ?? nameAr,
      description: map['description']?.toString() ?? descriptionAr,
      nameAr: nameAr,
      nameEn: nameEn,
      descriptionAr: descriptionAr,
      descriptionEn: descriptionEn,
      price: (map['price'] as num?)?.toDouble() ??
          double.tryParse(map['price']?.toString() ?? '') ??
          0,
      imageUrl: normalizeMenuImageUrl(map['imageUrl'] ?? map['image_url']),
      talabatId: map['talabat_id'] is int
          ? map['talabat_id'] as int
          : int.tryParse(map['talabat_id']?.toString() ?? ''),
      isAvailable: map['is_available'] == 1 ||
          map['is_available'] == true ||
          map['isAvailable'] == true ||
          map['isAvailable'] == 1,
      displayOrder: (map['display_order'] as num?)?.toInt() ??
          (map['displayOrder'] as num?)?.toInt() ??
          0,
      options: rawOptions
          .whereType<Map>()
          .map((option) => MenuOption.fromMap(Map<String, dynamic>.from(option)))
          .toList(),
      linkedItemIds: _parseLinkedItemIds(map),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'category_id': categoryId,
      'category_name': categoryName,
      if (categoryNameEn.isNotEmpty) 'category_name_en': categoryNameEn,
      'name': nameAr.isNotEmpty ? nameAr : name,
      'description': descriptionAr.isNotEmpty ? descriptionAr : description,
      'name_ar': nameAr.isNotEmpty ? nameAr : name,
      'name_en': nameEn,
      'description_ar': descriptionAr.isNotEmpty ? descriptionAr : description,
      'description_en': descriptionEn,
      'price': price,
      'image_url': imageUrl,
      if (talabatId != null) 'talabat_id': talabatId,
      'is_available': isAvailable ? 1 : 0,
      'display_order': displayOrder,
      if (options.isNotEmpty)
        'options': options.map((option) => option.toMap()).toList(),
      if (linkedItemIds.isNotEmpty) 'linkedItemIds': linkedItemIds,
      if (linkedItemIds.isNotEmpty) 'linked_item_ids': linkedItemIds,
    };
  }

  Map<String, dynamic> toMap() {
    return {
      'name': nameAr.isNotEmpty ? nameAr : name,
      'description': descriptionAr.isNotEmpty ? descriptionAr : description,
      'nameAr': nameAr.isNotEmpty ? nameAr : name,
      'nameEn': nameEn,
      'descriptionAr': descriptionAr.isNotEmpty ? descriptionAr : description,
      'descriptionEn': descriptionEn,
      'price': price,
      'imageUrl': imageUrl,
      'categoryName': categoryName,
      if (categoryNameEn.isNotEmpty) 'categoryNameEn': categoryNameEn,
      'categoryId': categoryId,
      'options': options.map((option) => option.toMap()).toList(),
      'isAvailable': isAvailable,
      'displayOrder': displayOrder,
      if (linkedItemIds.isNotEmpty) 'linkedItemIds': linkedItemIds,
    };
  }
}
