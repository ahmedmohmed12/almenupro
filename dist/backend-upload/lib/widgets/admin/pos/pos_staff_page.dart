import 'package:flutter/material.dart';

import '../../../models/staff_user.dart';
import '../../../services/pos_operations_service.dart';
import 'pos_add_staff_dialog.dart';
import 'pos_staff_empty_state.dart';

class PosStaffPage extends StatefulWidget {
  const PosStaffPage({super.key});

  @override
  State<PosStaffPage> createState() => _PosStaffPageState();
}

class _PosStaffPageState extends State<PosStaffPage> {
  var _loading = true;
  List<StaffUser> _staff = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _staff = await PosOperationsService.instance.fetchStaffUsers();
    } catch (_) {
      _staff = const [];
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addStaff() async {
    final created = await showPosAddStaffDialog(context);
    if (created != null) await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'إدارة الموظفين / الكاشير',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ),
              FilledButton.icon(
                onPressed: _addStaff,
                icon: const Icon(Icons.person_add),
                label: const Text('إضافة كاشير'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF6B1124)))
                : _staff.isEmpty
                    ? PosStaffEmptyState(onStaffAdded: _load)
                    : ListView.separated(
                        itemCount: _staff.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final member = _staff[index];
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: const Color(0xFF6B1124).withValues(alpha: 0.12),
                              child: Text(member.name.isNotEmpty ? member.name[0] : '?'),
                            ),
                            title: Text(member.name),
                            subtitle: Text('الدور: ${member.roleId} • PIN: ${member.maskedPin}'),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
