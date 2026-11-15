import 'package:flutter/foundation.dart';

/// Parses table QR ordering identity from path + query.
///
/// Supported:
/// - `/menu?table=5&rest=101`
/// - `/menu?table_id=5&restaurant_id=101`
/// - `/table/{branchId}/{tableId}` / `/table/{branchId}/{tableId}/order`
class TableQrRouteParams {
  const TableQrRouteParams({
    required this.tableId,
    required this.restaurantId,
    this.branchId = '',
    this.slug = '',
  });

  final String tableId;
  final String restaurantId;
  final String branchId;
  final String slug;

  bool get isValid => tableId.isNotEmpty && restaurantId.isNotEmpty;

  static TableQrRouteParams? fromUri(Uri uri) {
    final query = uri.queryParameters;
    final table =
        (query['table'] ??
                query['table_id'] ??
                query['tableId'] ??
                '')
            .trim();
    final rest =
        (query['rest'] ??
                query['restaurant_id'] ??
                query['restaurantId'] ??
                query['branch'] ??
                '')
            .trim();

    final segments =
        uri.path.split('/').where((segment) => segment.isNotEmpty).toList();
    if (segments.length >= 3 && segments.first.toLowerCase() == 'table') {
      final branchId = Uri.decodeComponent(segments[1]);
      final tableId = Uri.decodeComponent(segments[2]);
      return TableQrRouteParams(
        tableId: table.isNotEmpty ? table : tableId,
        restaurantId: rest.isNotEmpty ? rest : branchId,
        branchId: branchId,
      );
    }

    if (table.isEmpty) return null;
    return TableQrRouteParams(
      tableId: table,
      restaurantId: rest,
      slug: (query['slug'] ?? '').trim(),
    );
  }

  static TableQrRouteParams? fromBrowser() {
    if (!kIsWeb) return null;
    return fromUri(Uri.base);
  }
}
