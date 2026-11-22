import '../models/hr_models.dart';
import 'hr_job_roles.dart';
import 'pos_operations_service.dart';

/// Links HR employees with job «كاشير» to POS staff (role cashier only).
class HrPosCashierSync {
  HrPosCashierSync._();

  static Future<void> syncAfterEmployeeSave(EmployeeModel employee) async {
    final staff = await PosOperationsService.instance.fetchStaffUsers();
    final linked = staff
        .where((row) => row.employeeId == employee.id)
        .toList();

    if (!HrRestaurantJobs.isCashierJob(employee.jobTitle) ||
        employee.status != EmployeeStatus.active) {
      for (final row in linked) {
        await PosOperationsService.instance.updateStaffUser(
          row.id,
          name: employee.name,
          isActive: false,
          hrProvision: true,
        );
      }
      return;
    }

    final pin = employee.pinCode.trim();
    if (pin.length != 4) {
      throw Exception('رمز الدخول يجب أن يكون 4 أرقام لتعيين كاشير POS');
    }

    if (linked.isNotEmpty) {
      final primary = linked.first;
      await PosOperationsService.instance.updateStaffUser(
        primary.id,
        name: employee.name,
        pin: pin,
        roleId: 'cashier',
        isActive: true,
        employeeId: employee.id,
        hrProvision: true,
      );
      for (var i = 1; i < linked.length; i++) {
        await PosOperationsService.instance.updateStaffUser(
          linked[i].id,
          isActive: false,
          hrProvision: true,
        );
      }
      return;
    }

    await PosOperationsService.instance.createStaffUser(
      name: employee.name,
      roleId: 'cashier',
      pin: pin,
      employeeId: employee.id,
      hrProvision: true,
    );
  }
}