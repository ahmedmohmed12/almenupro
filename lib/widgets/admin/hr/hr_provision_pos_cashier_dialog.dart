import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../models/hr_models.dart';
import '../../../models/staff_user.dart';
import '../../../services/pos_operations_service.dart';

const _burgundy = Color(0xFF800020);

/// Assign a POS cashier login linked to an HR employee (role: cashier only).
Future<StaffUser?> showHrProvisionPosCashierDialog(
  BuildContext context, {
  required EmployeeModel employee,
}) {
  return showDialog<StaffUser>(
    context: context,
    builder: (context) => _HrProvisionPosCashierDialog(employee: employee),
  );
}

class _HrProvisionPosCashierDialog extends StatefulWidget {
  const _HrProvisionPosCashierDialog({required this.employee});

  final EmployeeModel employee;

  @override
  State<_HrProvisionPosCashierDialog> createState() =>
      _HrProvisionPosCashierDialogState();
}

class _HrProvisionPosCashierDialogState extends State<_HrProvisionPosCashierDialog> {
  late final TextEditingController _pinController;
  var _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final hrPin = widget.employee.pinCode.trim();
    _pinController = TextEditingController(
      text: hrPin.length == 4 ? hrPin : '',
    );
  }

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final pin = _pinController.text.trim();
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
        name: widget.employee.name,
        roleId: 'cashier',
        pin: pin,
        employeeId: widget.employee.id,
        hrProvision: true,
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
      title: const Text('تعيين كاشير POS'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.employee.name,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
            const SizedBox(height: 4),
            Text(
              widget.employee.jobTitle,
              style: const TextStyle(color: Color(0xFF64748B)),
            ),
            const SizedBox(height: 12),
            const Text(
              'يُنشأ حساب كاشير برقم PIN ويرتبط بملف الموظف في شؤون الموظفين. '
              'الدور: كاشير عادي فقط — لا موافقة ذاتية على إلغاء المطبخ.',
              style: TextStyle(fontSize: 12, color: Color(0xFF64748B), height: 1.35),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _pinController,
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: 4,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: 'رمز PIN للكاشير (4 أرقام)',
                border: const OutlineInputBorder(),
                errorText: _error,
                counterText: '',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: _burgundy),
          onPressed: _submitting ? null : _submit,
          child: _submitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Text('حفظ وتعيين كاشير'),
        ),
      ],
    );
  }
}