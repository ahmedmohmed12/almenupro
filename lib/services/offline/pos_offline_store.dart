abstract class PosOfflineStore {
  Future<void> putCatalog(String restaurantId, List<Map<String, dynamic>> items);
  Future<List<Map<String, dynamic>>> getCatalog(String restaurantId);

  Future<void> putActiveOrder(Map<String, dynamic> record);
  Future<Map<String, dynamic>?> getActiveOrder(String id);
  Future<List<Map<String, dynamic>>> listActiveOrders(String restaurantId);
  Future<void> deleteActiveOrder(String id);

  Future<void> putQueueItem(Map<String, dynamic> record);
  Future<List<Map<String, dynamic>>> listQueuePending();
  Future<void> deleteQueueItem(String id);

  Future<void> putShiftState(Map<String, dynamic> record);
  Future<Map<String, dynamic>?> getShiftState(String id);
}

class MemoryPosOfflineStore implements PosOfflineStore {
  final _catalog = <String, Map<String, dynamic>>{};
  final _active = <String, Map<String, dynamic>>{};
  final _queue = <String, Map<String, dynamic>>{};
  final _shifts = <String, Map<String, dynamic>>{};

  @override
  Future<void> putCatalog(String restaurantId, List<Map<String, dynamic>> items) async {
    _catalog.removeWhere((_, row) => row['restaurantId'] == restaurantId);
    for (final item in items) {
      final id = '${restaurantId}:${item['id']}';
      _catalog[id] = {...item, 'restaurantId': restaurantId, 'id': id};
    }
  }

  @override
  Future<List<Map<String, dynamic>>> getCatalog(String restaurantId) async {
    return _catalog.values
        .where((row) => row['restaurantId'] == restaurantId)
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  }

  @override
  Future<void> putActiveOrder(Map<String, dynamic> record) async {
    _active[record['id'].toString()] = Map<String, dynamic>.from(record);
  }

  @override
  Future<Map<String, dynamic>?> getActiveOrder(String id) async {
    final row = _active[id];
    return row == null ? null : Map<String, dynamic>.from(row);
  }

  @override
  Future<List<Map<String, dynamic>>> listActiveOrders(String restaurantId) async {
    return _active.values
        .where((row) => row['restaurantId'] == restaurantId)
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  }

  @override
  Future<void> deleteActiveOrder(String id) async {
    _active.remove(id);
  }

  @override
  Future<void> putQueueItem(Map<String, dynamic> record) async {
    _queue[record['id'].toString()] = Map<String, dynamic>.from(record);
  }

  @override
  Future<List<Map<String, dynamic>>> listQueuePending() async {
    final rows = _queue.values
        .where((row) => row['status'] != 'synced')
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
    rows.sort(
      (a, b) => (a['createdAt']?.toString() ?? '').compareTo(b['createdAt']?.toString() ?? ''),
    );
    return rows;
  }

  @override
  Future<void> deleteQueueItem(String id) async {
    _queue.remove(id);
  }

  @override
  Future<void> putShiftState(Map<String, dynamic> record) async {
    _shifts[record['id'].toString()] = Map<String, dynamic>.from(record);
  }

  @override
  Future<Map<String, dynamic>?> getShiftState(String id) async {
    final row = _shifts[id];
    return row == null ? null : Map<String, dynamic>.from(row);
  }
}
