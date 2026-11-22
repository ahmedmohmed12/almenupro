import '../models/kitchen_void_liability.dart';
import '../models/staff_user.dart';
import 'pos_operations_service.dart';

/// Rejected kitchen void debt mapped to HR [employeeId] for payroll (no duplicates).
class HrKitchenVoidPayroll {
  HrKitchenVoidPayroll._();

  static DateTime? _parseLiabilityMonth(KitchenVoidLiability row) {
  final raw = row.reviewedAt ?? row.voidedAt;
    if (raw == null || raw.isEmpty) return null;
    return DateTime.tryParse(raw);
  }

  static bool _alreadyDeducted(KitchenVoidLiability row) {
    final flag = row.payrollDeductedAt;
    return flag != null && flag.isNotEmpty;
  }

  static Future<Map<String, double>> debtsForMonth({
    required int month,
    required int year,
  }) async {
    final liabilities = await PosOperationsService.instance.fetchKitchenVoidLiabilities(
      status: 'ALL',
    );
    final staff = await PosOperationsService.instance.fetchStaffUsers();
    final employeeByCashier = <String, String>{};
    for (final user in staff) {
      final employeeId = user.employeeId?.trim() ?? '';
      if (employeeId.isNotEmpty) {
        employeeByCashier[user.id] = employeeId;
      }
    }

    final byEmployee = <String, double>{};
    for (final row in liabilities.liabilities) {
      if (!row.isRejected || _alreadyDeducted(row)) continue;
      final when = _parseLiabilityMonth(row);
      if (when == null || when.month != month || when.year != year) continue;

      var employeeId = row.employeeId?.trim() ?? '';
      if (employeeId.isEmpty) {
        employeeId = employeeByCashier[row.cashierId] ?? '';
      }
      if (employeeId.isEmpty) continue;

      byEmployee.update(employeeId, (prev) => prev + row.amount, ifAbsent: () => row.amount);
    }
    return byEmployee;
  }

  static Future<List<String>> liabilityIdsForEmployeeMonth({
    required String employeeId,
    required int month,
    required int year,
    required List<KitchenVoidLiability> liabilities,
    required List<StaffUser> staff,
  }) async {
    final employeeByCashier = <String, String>{
      for (final user in staff)
        if ((user.employeeId ?? '').isNotEmpty) user.id: user.employeeId!,
    };
    final ids = <String>[];
    for (final row in liabilities) {
      if (!row.isRejected || _alreadyDeducted(row)) continue;
      final when = _parseLiabilityMonth(row);
      if (when == null || when.month != month || when.year != year) continue;
      var emp = row.employeeId?.trim() ?? '';
      if (emp.isEmpty) emp = employeeByCashier[row.cashierId] ?? '';
      if (emp != employeeId) continue;
      ids.add(row.id);
    }
    return ids;
  }

  static Future<void> markPayrollDeducted({
    required int month,
    required int year,
    required List<String> liabilityIds,
  }) async {
    if (liabilityIds.isEmpty) return;
    await PosOperationsService.instance.applyKitchenVoidPayrollDeductions(
      month: month,
      year: year,
      liabilityIds: liabilityIds,
    );
  }
}