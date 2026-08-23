import 'package:flutter/material.dart';

import '../../services/incoming_order_auto_accept_service.dart';

class IncomingOrderCountdownBadge extends StatelessWidget {
  const IncomingOrderCountdownBadge({super.key, required this.orderId});

  final String orderId;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: IncomingOrderAutoAcceptService.instance,
      builder: (context, _) {
        final seconds =
            IncomingOrderAutoAcceptService.instance.remainingSeconds(orderId);
        if (seconds == null) return const SizedBox.shrink();

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: seconds <= 3 ? const Color(0xFFB3261E) : const Color(0xFF6B1124),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.timer, size: 16, color: Colors.white),
              const SizedBox(width: 4),
              Text(
                '$seconds',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
