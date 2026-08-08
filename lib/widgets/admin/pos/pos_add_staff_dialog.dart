import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../models/pos_role.dart';
import '../../../models/staff_user.dart';
import '../../../services/pos_operations_service.dart';

/// Simplified staff roles shown in the add-cashier form.
enum PosStaffFormRole {
  cashier('cashier', 'كاشير عادي'),
  branchManager('shift_supervisor', 'مدير فرع');

  const PosStaffFormRole(this.roleId, this.labelAr);

  final String roleId;
  final String labelAr;
}

class PosAddStaffDialog extends StatefulWidget {
  const PosAddStaffDialog({
    super.key,
    this.initialName = '',
    this.initialPin = '',
    this.initialRole = PosStaffFormRole.cashier,
  });

  final String initialName;
  final String initialPin;
  final PosStaffFormRole initialRole;

  @override
  State<PosAddStaffDialog> createState() => _PosAddStaffDialogState();
}

class _PosAddStaffDialogState extends State<PosAddStaffDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _pinController;
  late PosStaffFormRole _role;
  var _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName);
    _pinController = TextEditingController(text: widget.initialPin);
    _role = widget.initialRole;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _nameController.text.trim();
    final pin = _pinController.text.trim();

    if (name.isEmpty) {
      setState(() => _error = 'أدخل اسم الكاشير');
      return;
    }
    if (pin.length != 4) {
      setState(() => _error = 'رمز PIN يجب أن يكون 4 أرقام');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final created = await PosOperationsService.instance.createStaffUser(
        name: name,
        roleId: _role.roleId,
        pin: pin,
      );
      if (!mounted) return;
      Navigator.of(context).pop(created);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString().replaceFirst('Exception: ', '');
        _submitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('إضافة موظف / كاشير جديد'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _nameController,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'اسم الكاشير',
                hintText: 'مثال: أحمد',
                prefixIcon: Icon(Icons.person_outline),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _pinController,
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: 4,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: 'رمز PIN (4 أرقام)',
                hintText: '1234',
                prefixIcon: Icon(Icons.pin_outlined),
                border: OutlineInputBorder(),
                counterText: '',
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<PosStaffFormRole>(
              initialValue: _role,
              decoration: const InputDecoration(
                labelText: 'الصلاحية',
                prefixIcon: Icon(Icons.badge_outlined),
                border: OutlineInputBorder(),
              ),
              items: PosStaffFormRole.values
                  .map(
                    (entry) => DropdownMenuItem(
                      value: entry,
                      child: Text(entry.labelAr),
                    ),
                  )
                  .toList(),
              onChanged: _submitting
                  ? null
                  : (value) {
                      if (value == null) return;
                      setState(() => _role = value);
                    },
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: TextStyle(color: Colors.red.shade700, fontSize: 13),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
          child: const Text('إلغاء'),
        ),
        FilledButton.icon(
          onPressed: _submitting ? null : _submit,
          icon: _submitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.person_add),
          label: const Text('حفظ الموظف'),
        ),
      ],
    );
  }
}

/// Opens the add-staff dialog. Returns the created [StaffUser] or null.
Future<StaffUser?> showPosAddStaffDialog(
  BuildContext context, {
  String initialName = '',
  String initialPin = '',
  PosStaffFormRole initialRole = PosStaffFormRole.cashier,
}) {
  return showDialog<StaffUser>(
    context: context,
    builder: (context) => PosAddStaffDialog(
      initialName: initialName,
      initialPin: initialPin,
      initialRole: initialRole,
    ),
  );
}

/// Creates a default Admin cashier (PIN 1234) for quick setup.
Future<StaffUser> seedDefaultPosStaff() {
  return PosOperationsService.instance.createStaffUser(
    name: 'Admin',
    roleId: PosStaffFormRole.branchManager.roleId,
    pin: '1234',
  );
}

String roleLabelForStaff(StaffUser member, {List<PosRole>? roles}) {
  final formRole = PosStaffFormRole.values
      .where((entry) => entry.roleId == member.roleId)
      .map((entry) => entry.labelAr)
      .firstOrNull;
  if (formRole != null) return formRole;

  final resolved = roles
      ?.where((role) => role.id == member.roleId)
      .map((role) => role.nameAr)
      .firstOrNull;
  return resolved ?? member.roleId;
}
