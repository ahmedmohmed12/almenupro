import 'web_initial_route_stub.dart'
    if (dart.library.html) 'web_initial_route_web.dart';

String currentWebPath() => readWebPath();