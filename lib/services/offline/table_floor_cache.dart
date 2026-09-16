abstract class TableFloorCache {
  Future<void> save(String restaurantId, List<Map<String, dynamic>> tables);
  Future<List<Map<String, dynamic>>> load(String restaurantId);
}

class MemoryTableFloorCache implements TableFloorCache {
  final _rows = <String, List<Map<String, dynamic>>>{};

  @override
  Future<void> save(String restaurantId, List<Map<String, dynamic>> tables) async {
    _rows[restaurantId] = tables.map(Map<String, dynamic>.from).toList();
  }

  @override
  Future<List<Map<String, dynamic>>> load(String restaurantId) async {
    return (_rows[restaurantId] ?? const [])
        .map(Map<String, dynamic>.from)
        .toList();
  }
}
