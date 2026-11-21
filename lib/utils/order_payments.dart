import '../models/order.dart';
import '../models/order_payment_line.dart';
import 'order_channel_utils.dart';

const _kwdEpsilon = 0.0005;

double money3(double value) => double.parse(value.toStringAsFixed(3));

List<OrderPaymentLine> orderPaymentLines(Order order) {
  if (order.payments != null && order.payments!.isNotEmpty) {
    return order.payments!;
  }
  final total = order.totalPrice;
  if (total <= 0) return const [];
  final method = order.paymentMethod ?? '';
  if (isCashPaymentMethod(method)) {
    return [OrderPaymentLine(method: 'cash', amount: money3(total))];
  }
  if (isKnetPaymentMethod(method)) {
    return [OrderPaymentLine(method: 'knet', amount: money3(total))];
  }
  return const [];
}

bool isSplitCashKnetOrder(Order order) {
  final lines = orderPaymentLines(order);
  final cash =
      lines.where((line) => line.isCash).fold<double>(0, (s, l) => s + l.amount);
  final knet =
      lines.where((line) => line.isKnet).fold<double>(0, (s, l) => s + l.amount);
  return cash > 0 && knet > 0;
}

({double cash, double knet}) shiftPaymentBreakdown(Order order) {
  final lines = orderPaymentLines(order);
  var cash = 0.0;
  var knet = 0.0;
  for (final line in lines) {
    if (line.isCash) cash += line.amount;
    if (line.isKnet) knet += line.amount;
  }
  if (cash > 0 || knet > 0) {
    return (cash: money3(cash), knet: money3(knet));
  }
  final total = order.totalPrice;
  if (isCashPaymentMethod(order.paymentMethod)) {
    return (cash: money3(total), knet: 0);
  }
  if (isKnetPaymentMethod(order.paymentMethod)) {
    return (cash: 0, knet: money3(total));
  }
  return (cash: 0, knet: 0);
}

String formatOrderPaymentSummary(Order order) {
  final lines = orderPaymentLines(order);
  if (lines.length >= 2 && isSplitCashKnetOrder(order)) {
    final cash = shiftPaymentBreakdown(order).cash;
    final knet = shiftPaymentBreakdown(order).knet;
    return 'كاش ${cash.toStringAsFixed(3)} + كي نت ${knet.toStringAsFixed(3)} د.ك';
  }
  final method = order.paymentMethod?.trim();
  if (method != null && method.isNotEmpty) return method;
  return 'كاش';
}

String? validateSplitPayments({
  required List<OrderPaymentLine> payments,
  required double orderTotal,
}) {
  if (payments.isEmpty) {
    return 'تفاصيل الدفع مطلوبة';
  }
  var cash = 0.0;
  var knet = 0.0;
  for (final line in payments) {
    if (line.amount <= 0) {
      return 'مبالغ الدفع يجب أن تكون أكبر من صفر';
    }
    if (line.isCash) {
      cash += line.amount;
    } else if (line.isKnet) {
      knet += line.amount;
    } else {
      return 'تقسيم الدفع مسموح بين كاش وكي نت فقط';
    }
  }
  final sum = money3(cash + knet);
  final total = money3(orderTotal);
  if ((sum - total).abs() > _kwdEpsilon) {
    return 'مجموع كاش + كي نت يجب أن يساوي إجمالي الفاتورة';
  }
  if (cash <= 0 || knet <= 0) {
    return 'أدخل مبلغاً لكل من كاش وكي نت';
  }
  return null;
}

List<OrderPaymentLine> buildSplitPayments({
  required double cashAmount,
  required double knetAmount,
}) {
  return [
    OrderPaymentLine(method: 'cash', amount: money3(cashAmount)),
    OrderPaymentLine(method: 'knet', amount: money3(knetAmount)),
  ];
}