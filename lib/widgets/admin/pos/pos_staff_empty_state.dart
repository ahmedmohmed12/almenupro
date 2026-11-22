import 'package:flutter/material.dart';

import '../../../models/staff_user.dart';
import '../../../services/pos_operations_service.dart';

/// Shown on POS login when no cashiers exist — directs to HR only.
class PosStaffEmptyState extends StatelessWidget {
  const PosStaffEmptyState({
    super.key,
    required this.onStaffAdded,
    this.compact = false,
  });

  final VoidCallback onStaffAdded;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(compact ? 12 : 16),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline, color: Colors.orange.shade800),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'لا يوجد كاشير POS بعد',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.orange.shade900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'أنشئ الموظف في لوحة الإدارة → شؤون الموظفين → تبويب «الموظفون»، ثم اضغط أيقونة POS لتعيين رمز PIN للكاشير.',
            style: TextStyle(color: Colors.orange.shade900, fontSize: 13),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: OutlinedButton.icon(
              onPressed: onStaffAdded,
              icon: const Icon(Icons.refresh),
              label: const Text('إعادة تحميل القائمة'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Loads staff list helper for POS screens.
Future<List<StaffUser>> loadPosStaffUsers() {
  return PosOperationsService.instance.fetchStaffUsers();
}