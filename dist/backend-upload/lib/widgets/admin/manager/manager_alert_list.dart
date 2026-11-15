import 'package:flutter/material.dart';

import '../../../models/manager_report_snapshot.dart';

class ManagerAlertList extends StatelessWidget {
  const ManagerAlertList({
    super.key,
    required this.alerts,
    required this.onDismiss,
  });

  final List<ManagerAlert> alerts;
  final ValueChanged<String> onDismiss;

  @override
  Widget build(BuildContext context) {
    if (alerts.isEmpty) return const SizedBox.shrink();
    return Column(
      children: [
        for (final alert in alerts)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
            decoration: BoxDecoration(
              color: _bg(alert.kind),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _fg(alert.kind).withValues(alpha: 0.25)),
            ),
            child: Row(
              children: [
                Icon(_icon(alert.kind), color: _fg(alert.kind), size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        alert.title,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: _fg(alert.kind),
                          fontSize: 13,
                        ),
                      ),
                      Text(
                        alert.body,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: () => onDismiss(alert.id),
                  icon: const Icon(Icons.close, size: 18),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Color _bg(ManagerAlertKind kind) => switch (kind) {
        ManagerAlertKind.voidOrder => const Color(0xFFFEF2F2),
        ManagerAlertKind.discount => const Color(0xFFFFF7ED),
        ManagerAlertKind.shiftClosed => const Color(0xFFEFF6FF),
        ManagerAlertKind.newOrder => const Color(0xFFECFDF5),
      };

  Color _fg(ManagerAlertKind kind) => switch (kind) {
        ManagerAlertKind.voidOrder => const Color(0xFFB91C1C),
        ManagerAlertKind.discount => const Color(0xFFC2410C),
        ManagerAlertKind.shiftClosed => const Color(0xFF1D4ED8),
        ManagerAlertKind.newOrder => const Color(0xFF047857),
      };

  IconData _icon(ManagerAlertKind kind) => switch (kind) {
        ManagerAlertKind.voidOrder => Icons.block,
        ManagerAlertKind.discount => Icons.percent,
        ManagerAlertKind.shiftClosed => Icons.lock_clock,
        ManagerAlertKind.newOrder => Icons.notifications_active,
      };
}
