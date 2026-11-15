import 'pos_offline_store_stub.dart'
    if (dart.library.html) 'pos_offline_store_web.dart'
    if (dart.library.io) 'pos_offline_store_io.dart';

export 'pos_offline_store.dart';

final posOfflineStore = createPosOfflineStore();
