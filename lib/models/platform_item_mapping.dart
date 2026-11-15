class PlatformItemMapping {
  const PlatformItemMapping({
    required this.id,
    required this.posItemId,
    required this.platformName,
    required this.platformItemName,
    this.platformItemId = '',
    this.sku = '',
    this.parentMappingId = '',
    this.posOptionId = '',
    this.entityType = 'item',
  });

  final String id;
  final String posItemId;
  final String platformName;
  final String platformItemId;
  final String platformItemName;
  final String sku;
  final String parentMappingId;
  final String posOptionId;
  final String entityType;

  factory PlatformItemMapping.fromMap(Map<String, dynamic> map) {
    String value(String snake, [String? camel]) =>
        (map[snake] ?? (camel == null ? null : map[camel]) ?? '').toString();
    return PlatformItemMapping(
      id: value('id'),
      posItemId: value('pos_item_id', 'posItemId'),
      platformName: value('platform_name', 'platformName'),
      platformItemId: value('platform_item_id', 'platformItemId'),
      platformItemName: value('platform_item_name', 'platformItemName'),
      sku: value('sku'),
      parentMappingId: value('parent_mapping_id', 'parentMappingId'),
      posOptionId: value('pos_option_id', 'posOptionId'),
      entityType: value('entity_type', 'entityType').isEmpty
          ? 'item'
          : value('entity_type', 'entityType'),
    );
  }

  Map<String, dynamic> toMap({String? unmappedId}) => {
    if (id.isNotEmpty) 'id': id,
    'pos_item_id': posItemId,
    'platform_name': platformName,
    'platform_item_id': platformItemId,
    'platform_item_name': platformItemName,
    'sku': sku,
    'parent_mapping_id': parentMappingId,
    'pos_option_id': posOptionId,
    'entity_type': entityType,
    if (unmappedId != null && unmappedId.isNotEmpty) 'unmapped_id': unmappedId,
  };
}

class UnmappedPlatformItem {
  const UnmappedPlatformItem({
    required this.id,
    required this.platformName,
    required this.platformItemName,
    this.platformItemId = '',
    this.sku = '',
    this.entityType = 'item',
    this.parentPlatformItemId = '',
    this.occurrences = 1,
  });

  final String id;
  final String platformName;
  final String platformItemId;
  final String platformItemName;
  final String sku;
  final String entityType;
  final String parentPlatformItemId;
  final int occurrences;

  factory UnmappedPlatformItem.fromMap(
    Map<String, dynamic> map,
  ) => UnmappedPlatformItem(
    id: map['id']?.toString() ?? '',
    platformName: (map['platform_name'] ?? map['platformName'] ?? '')
        .toString(),
    platformItemId: (map['platform_item_id'] ?? map['platformItemId'] ?? '')
        .toString(),
    platformItemName:
        (map['platform_item_name'] ?? map['platformItemName'] ?? '').toString(),
    sku: map['sku']?.toString() ?? '',
    entityType: (map['entity_type'] ?? map['entityType'] ?? 'item').toString(),
    parentPlatformItemId:
        (map['parent_platform_item_id'] ?? map['parentPlatformItemId'] ?? '')
            .toString(),
    occurrences: int.tryParse(map['occurrences']?.toString() ?? '') ?? 1,
  );
}
