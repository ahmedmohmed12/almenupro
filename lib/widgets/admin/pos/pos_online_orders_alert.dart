import 'package:flutter/material.dart';

/// Compact alert shown on POS home when online menu orders are waiting.
class PosOnlineOrdersAlertBar extends StatelessWidget {
  const PosOnlineOrdersAlertBar({
    super.key,
    required this.pendingCount,
    required this.onOpen,
  });

  final int pendingCount;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    if (pendingCount <= 0) return const SizedBox.shrink();

    return Material(
      color: Colors.orange.shade50,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Icon(Icons.notifications_active, color: Colors.orange.shade800),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '$pendingCount طلب منيو إلكتروني بانتظار القبول',
                  style: TextStyle(
                    color: Colors.orange.shade900,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              TextButton(
                onPressed: onOpen,
                child: const Text('عرض'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
