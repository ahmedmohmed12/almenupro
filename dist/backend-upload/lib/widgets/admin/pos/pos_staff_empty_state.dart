import 'package:flutter/material.dart';

import '../../../models/staff_user.dart';
import '../../../services/pos_operations_service.dart';
import 'pos_add_staff_dialog.dart';

/// Empty-state panel shown on POS login when no cashiers exist yet.
class PosStaffEmptyState extends StatefulWidget {
  const PosStaffEmptyState({
    super.key,
    required this.onStaffAdded,
    this.compact = false,
  });

  final VoidCallback onStaffAdded;
  final bool compact;

  @override
  State<PosStaffEmptyState> createState() => _PosStaffEmptyStateState();
}

class _PosStaffEmptyStateState extends State<PosStaffEmptyState> {
  var _seeding = false;
  String? _error;

  Future<void> _quickSeed() async {
    setState(() {
      _seeding = true;
      _error = null;
    });
    try {
      await seedDefaultPosStaff();
      widget.onStaffAdded();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) setState(() => _seeding = false);
    }
  }

  Future<void> _openAddDialog() async {
    final created = await showPosAddStaffDialog(context);
    if (created != null) {
      widget.onStaffAdded();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(widget.compact ? 12 : 16),
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
                  'لا يوجد موظفون كاشير بعد',
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
            'أضف كاشيراً برمز PIN للبدء، أو استخدم الإعداد السريع (Admin / 1234).',
            style: TextStyle(color: Colors.orange.shade900, fontSize: 13),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(color: Colors.red.shade700, fontSize: 13)),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: _openAddDialog,
                icon: const Icon(Icons.person_add),
                label: const Text('إضافة موظف / كاشير جديد'),
              ),
              OutlinedButton.icon(
                onPressed: _seeding ? null : _quickSeed,
                icon: _seeding
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.bolt),
                label: const Text('إضافة كاشير افتراضي سريع (Admin / 1234)'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Toolbar button for managing cashiers from POS shift banner area.
class PosManageStaffButton extends StatelessWidget {
  const PosManageStaffButton({
    super.key,
    required this.onChanged,
  });

  final VoidCallback onChanged;

  Future<void> _open(BuildContext context) async {
    final created = await showPosAddStaffDialog(context);
    if (created != null) {
      onChanged();
    }
  }

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white,
        side: const BorderSide(color: Colors.white70),
      ),
      onPressed: () => _open(context),
      icon: const Icon(Icons.group_add, size: 18),
      label: const Text('إضافة كاشير'),
    );
  }
}

/// Loads staff list helper for POS screens.
Future<List<StaffUser>> loadPosStaffUsers() {
  return PosOperationsService.instance.fetchStaffUsers();
}
