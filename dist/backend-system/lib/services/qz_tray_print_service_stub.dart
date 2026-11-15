/// Non-web: QZ Tray is unavailable, so silent print always fails.
Future<bool> printReceiptSilently(Map<String, dynamic> orderData) async {
  return false;
}
