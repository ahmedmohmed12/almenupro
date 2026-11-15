import 'package:flutter/foundation.dart';

import '../models/order.dart';

class OrderTypeProvider extends ChangeNotifier {
  OrderType _orderType = OrderType.delivery;

  OrderType get orderType => _orderType;

  void setOrderType(OrderType type) {
    if (_orderType == type) {
      return;
    }
    _orderType = type;
    notifyListeners();
  }
}
