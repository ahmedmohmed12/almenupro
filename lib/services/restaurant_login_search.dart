import '../models/restaurant.dart';
import 'api_service.dart';

List<Restaurant> filterRestaurantsForLogin(
  List<Restaurant> source,
  String query, {
  int limit = 8,
}) {
  final needle = query.trim().toLowerCase();
  if (needle.isEmpty) return const [];
  final scored = <({Restaurant row, int rank})>[];
  for (final row in source) {
    final slug = row.slug.toLowerCase();
    final name = row.name.toLowerCase();
    final id = row.id.toLowerCase();
    if (!slug.contains(needle) &&
        !name.contains(needle) &&
        !id.contains(needle)) {
      continue;
    }
    var rank = 3;
    if (slug == needle || name == needle) {
      rank = 0;
    } else if (slug.startsWith(needle) || name.startsWith(needle)) {
      rank = 1;
    } else if (slug.contains(needle) || name.contains(needle)) {
      rank = 2;
    }
    scored.add((row: row, rank: rank));
  }
  scored.sort((a, b) {
    final byRank = a.rank.compareTo(b.rank);
    if (byRank != 0) return byRank;
    return a.row.name.compareTo(b.row.name);
  });
  return scored.take(limit).map((entry) => entry.row).toList();
}

Future<List<Restaurant>> loadRestaurantsForLogin() {
  return ApiService.instance.fetchPublicRestaurants();
}