import 'dart:math';

String generateOfflineTxId() {
  final now = DateTime.now().millisecondsSinceEpoch;
  final rand = Random().nextInt(0xFFFFFF).toRadixString(36).padLeft(5, '0');
  return 'offline_tx_${now}_$rand';
}
