import 'package:flutter/material.dart';

import '../../../services/offline/pos_sync_service.dart';

class PosSyncStatusBadge extends StatelessWidget {
  const PosSyncStatusBadge({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: PosSyncService.instance,
      builder: (context, _) {
        final sync = PosSyncService.instance;
        final color = switch (sync.tone) {
          PosSyncTone.green => const Color(0xFF16A34A),
          PosSyncTone.amber => const Color(0xFFD97706),
          PosSyncTone.red => const Color(0xFFDC2626),
        };
        return Container(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 7 : 10,
            vertical: compact ? 3 : 5,
          ),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: color.withValues(alpha: 0.9)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: compact ? 6 : 8,
                height: compact ? 6 : 8,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              SizedBox(width: compact ? 4 : 6),
              Flexible(
                child: Text(
                  sync.statusLabelAr,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: compact ? 10 : 12,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
