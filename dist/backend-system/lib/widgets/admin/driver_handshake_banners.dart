import 'package:flutter/material.dart';

import '../../l10n/app_strings.dart';
import '../../models/delivery_dispatch.dart';
import '../../models/order.dart';
import '../../utils/order_channel_utils.dart';

String _kwd(double value) => '${value.toStringAsFixed(3)} د.ك';
String _driverKwd(AppStrings strings, double value) =>
    '${value.toStringAsFixed(3)} ${strings.tr('د.ك', 'KWD')}';

class HandshakeMoney {
  const HandshakeMoney({
    required this.isCash,
    required this.orderTotal,
    required this.driverFee,
    required this.netToCashier,
    required this.cashierPaysDriver,
    required this.collectFromCustomer,
  });

  final bool isCash;
  final double orderTotal;
  final double driverFee;
  final double netToCashier;
  final double cashierPaysDriver;
  final double collectFromCustomer;

  factory HandshakeMoney.fromOrder(Order order) {
    final cash = isCashPaymentMethod(order.paymentMethod);
    final fee = order.driverFee ?? 0;
    final total = order.totalPrice;
    return HandshakeMoney(
      isCash: cash,
      orderTotal: order.handshakeCollectFromCustomer != null && cash
          ? order.handshakeCollectFromCustomer!
          : total,
      driverFee: fee,
      netToCashier:
          order.handshakeNetToCashier ??
          (cash ? (total - fee).clamp(0, double.infinity) : 0),
      cashierPaysDriver: order.handshakeCashierPaysDriver ?? (cash ? 0 : fee),
      collectFromCustomer:
          order.handshakeCollectFromCustomer ?? (cash ? total : 0),
    );
  }

  factory HandshakeMoney.fromRequest(DeliveryDispatchRequest request) {
    final kind = (request.handshakePaymentKind ?? '').toLowerCase();
    final cash =
        kind == 'cash' ||
        (kind.isEmpty && isCashPaymentMethod(request.paymentMethod));
    final fee = request.handshakeDriverFee ?? request.driverFee;
    final total =
        request.handshakeOrderTotal ??
        (request.cashToCollect > 0 ? request.cashToCollect : fee);
    return HandshakeMoney(
      isCash:
          cash ||
          (kind.isEmpty &&
              request.cashToCollect > 0 &&
              request.paymentMethod.isEmpty),
      orderTotal: total,
      driverFee: fee,
      netToCashier:
          request.handshakeNetToCashier ??
          (cash ? (total - fee).clamp(0, double.infinity) : 0),
      cashierPaysDriver: request.handshakeCashierPaysDriver ?? (cash ? 0 : fee),
      collectFromCustomer:
          request.handshakeCollectFromCustomer ?? (cash ? total : 0),
    );
  }
}

class HandshakeBanner extends StatelessWidget {
  const HandshakeBanner({
    super.key,
    required this.text,
    this.tone = HandshakeTone.cashIn,
  });

  final String text;
  final HandshakeTone tone;

  @override
  Widget build(BuildContext context) {
    final bg = switch (tone) {
      HandshakeTone.cashIn => const Color(0xFFE8F5E9),
      HandshakeTone.cashOut => const Color(0xFFFFF3E0),
      HandshakeTone.paid => const Color(0xFFE3F2FD),
      HandshakeTone.wait => const Color(0xFFFFF8E1),
    };
    final fg = switch (tone) {
      HandshakeTone.cashIn => const Color(0xFF1B5E20),
      HandshakeTone.cashOut => const Color(0xFFBF360C),
      HandshakeTone.paid => const Color(0xFF0D47A1),
      HandshakeTone.wait => const Color(0xFF8A5A00),
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: fg.withValues(alpha: 0.25)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontWeight: FontWeight.w900,
          fontSize: 14,
          color: fg,
          height: 1.35,
        ),
      ),
    );
  }
}

enum HandshakeTone { cashIn, cashOut, paid, wait }

class CashierHandshakePanel extends StatelessWidget {
  const CashierHandshakePanel({
    super.key,
    required this.order,
    this.onConfirm,
    this.processing = false,
  });

  final Order order;
  final VoidCallback? onConfirm;
  final bool processing;

  @override
  Widget build(BuildContext context) {
    if (!order.isHeldByDriver && !order.isAwaitingHandoff) {
      return const SizedBox.shrink();
    }
    final money = HandshakeMoney.fromOrder(order);
    final picked =
        order.deliveryStatus == 'picked_up' ||
        order.deliveryStatus == 'on_the_way' ||
        order.statusTimeline.pickedUpAt != null;
    final cashierDone = order.cashierHandoffDone;
    final driverDone = order.driverHandoffDone;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HandshakeBanner(
          tone: money.isCash ? HandshakeTone.cashIn : HandshakeTone.cashOut,
          text: money.isCash
              ? 'استلم من السائق صافي الطعام: ${_kwd(money.netToCashier)}'
              : 'ادفع رسوم التوصيل للسائق: ${_kwd(money.cashierPaysDriver)}',
        ),
        if (!picked) ...[
          const SizedBox(height: 8),
          if (cashierDone && !driverDone)
            const HandshakeBanner(
              tone: HandshakeTone.wait,
              text: 'تم تأكيدك — بانتظار تأكيد السائق لاستلام الطلب',
            )
          else if (!cashierDone && onConfirm != null)
            FilledButton.icon(
              onPressed: processing ? null : onConfirm,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF6B1124),
                minimumSize: const Size.fromHeight(46),
              ),
              icon: processing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.handshake_outlined),
              label: Text(
                money.isCash
                    ? 'أكدت استلام صافي الطعام'
                    : 'أكدت دفع رسوم التوصيل',
              ),
            ),
        ],
      ],
    );
  }
}

class DriverPickupHandshake extends StatelessWidget {
  const DriverPickupHandshake({super.key, required this.request});

  final DeliveryDispatchRequest request;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final money = HandshakeMoney.fromRequest(request);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HandshakeBanner(
          tone: money.isCash ? HandshakeTone.cashOut : HandshakeTone.cashIn,
          text: money.isCash
              ? strings.tr(
                  'ادفع للكاشير صافي الطعام: ${_driverKwd(strings, money.netToCashier)}',
                  'Pay the cashier the food net: ${_driverKwd(strings, money.netToCashier)}',
                )
              : strings.tr(
                  'استلم رسوم التوصيل من الكاشير: ${_driverKwd(strings, money.cashierPaysDriver)}',
                  'Collect the delivery fee from the cashier: ${_driverKwd(strings, money.cashierPaysDriver)}',
                ),
        ),
        if (request.driverHandoffConfirmedAt != null &&
            request.cashierHandoffConfirmedAt == null) ...[
          const SizedBox(height: 8),
          HandshakeBanner(
            tone: HandshakeTone.wait,
            text: strings.tr(
              'بانتظار تأكيد الكاشير لإتمام الاستلام',
              'Waiting for the cashier to confirm the handoff',
            ),
          ),
        ],
      ],
    );
  }
}

class DriverCustomerHandshake extends StatelessWidget {
  const DriverCustomerHandshake({super.key, required this.request});

  final DeliveryDispatchRequest request;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final money = HandshakeMoney.fromRequest(request);
    if (money.isCash) {
      return HandshakeBanner(
        tone: HandshakeTone.cashIn,
        text: strings.tr(
          'حصّل من العميل المبلغ كاملاً: ${_driverKwd(strings, money.collectFromCustomer)}',
          'Collect the full amount from the customer: ${_driverKwd(strings, money.collectFromCustomer)}',
        ),
      );
    }
    return HandshakeBanner(
      tone: HandshakeTone.paid,
      text: strings.tr(
        'الطلب مدفوع أونلاين (Knet) - سلم الطلب فقط بدون تحصيل أي مبالغ',
        'The order was paid online (Knet). Deliver it without collecting any money.',
      ),
    );
  }
}
