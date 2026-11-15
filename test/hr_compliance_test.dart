import 'package:almenupro/models/hr_models.dart';
import 'package:almenupro/services/hr_compliance.dart';
import 'package:almenupro/services/hr_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 10, 18);

  EmployeeModel employee({
    DateTime? iqama,
    double basic = 300,
    double housing = 50,
    double other = 20,
    double overtimeRate = 2,
  }) {
    return EmployeeModel(
      id: 'e1',
      name: 'سالم',
      phone: '96550001122',
      jobTitle: 'طباخ',
      branchId: 'main',
      basicSalary: basic,
      housingAllowance: housing,
      otherAllowances: other,
      hourlyOvertimeRate: overtimeRate,
      iqamaExpiryDate: iqama,
    );
  }

  test('document colors follow 60, 30, and 7 day bands', () {
    expect(docAlertLevel(now.add(const Duration(days: 61)), now), DocAlertLevel.ok);
    expect(docAlertLevel(now.add(const Duration(days: 60)), now), DocAlertLevel.warning);
    expect(docAlertLevel(now.add(const Duration(days: 31)), now), DocAlertLevel.warning);
    expect(docAlertLevel(now.add(const Duration(days: 30)), now), DocAlertLevel.urgent);
    expect(docAlertLevel(now.add(const Duration(days: 7)), now), DocAlertLevel.urgent);
    expect(docAlertLevel(now.add(const Duration(days: 6)), now), DocAlertLevel.critical);
    expect(docAlertLevel(now.subtract(const Duration(days: 1)), now), DocAlertLevel.critical);
    expect(docAlertLevel(null, now), DocAlertLevel.ok);
  });

  test('filters separate expiring documents from expired ones', () {
    final alerts = collectDocumentAlerts([
      employee(iqama: now.add(const Duration(days: 40))),
      employee(iqama: now.subtract(const Duration(days: 2))),
    ], now);
    expect(filterDocumentAlerts(alerts, DocAlertFilter.expiring), hasLength(1));
    expect(filterDocumentAlerts(alerts, DocAlertFilter.expired).single.daysLeft, -2);
    expect(hrRenewalMessage(alerts.first), contains('سالم'));
  });

  test('net salary subtracts absence, lateness, penalties, and the loan installment', () {
    final person = employee();
    final day = DateTime(2026, 10, 5);
    final breakdown = calculatePayroll(
      employee: person,
      attendance: [
        AttendanceModel(
          id: 'a1',
          employeeId: 'e1',
          date: day,
          status: AttendanceStatus.present,
          lateMinutes: 60,
          checkInTime: DateTime(2026, 10, 5, 9),
          checkOutTime: DateTime(2026, 10, 5, 18),
        ),
        AttendanceModel(
          id: 'a2',
          employeeId: 'e1',
          date: DateTime(2026, 10, 6),
          status: AttendanceStatus.absent,
        ),
      ],
      records: const [
        LoanAndLeaveModel(
          id: 'l1',
          employeeId: 'e1',
          type: LoanLeaveType.loan,
          amount: 100,
          monthlyDeduction: 20,
        ),
      ],
      month: 10,
      year: 2026,
      penalties: 5,
    );

    expect(breakdown.overtimeAmount, 4);
    expect(breakdown.absenceDeduction, 10);
    expect(breakdown.lateDeduction, closeTo(1.25, 0.001));
    expect(breakdown.loanDeduction, 20);
    expect(breakdown.netSalary, closeTo(337.75, 0.001));
  });

  test('the desk stores a payroll draft and keeps it after reload', () async {
    final store = MemoryHrStore();
    final desk = HrController(store: store);
    await desk.saveEmployee(employee());
    final rows = await desk.calculateMonth(DateTime(2026, 10, 18));
    expect(rows.single.status, PayrollStatus.draft);
    expect(rows.single.netSalary, 370);

    final restored = HrController(store: store);
    await restored.load();
    expect(restored.employees.single.name, 'سالم');
    expect(restored.payroll.single.netSalary, 370);
  });

  test('a month without PIN punches stays fully paid', () {
    final person = employee();
    final days = resolveScheduledAttendance(
      employee: person,
      attendance: const [],
      year: 2026,
      month: 10,
    );
    expect(days.every((day) => day.isAutoPresent), isTrue);
    final breakdown = calculatePayroll(
      employee: person,
      attendance: const [],
      records: const [],
      month: 10,
      year: 2026,
    );
    expect(breakdown.absenceDeduction, 0);
    expect(breakdown.lateDeduction, 0);
    expect(breakdown.netSalary, 370);
  });

  test('only a manager absence deducts; the other scheduled days stay auto-present', () {
    final person = employee();
    final absent = AttendanceModel(
      id: 'a2',
      employeeId: 'e1',
      date: DateTime(2026, 10, 6),
      status: AttendanceStatus.absent,
      source: AttendanceSource.manual,
    );
    final days = resolveScheduledAttendance(
      employee: person,
      attendance: [absent],
      year: 2026,
      month: 10,
    );
    expect(days.where((day) => day.status == AttendanceStatus.absent), hasLength(1));
    expect(days.where((day) => day.isAutoPresent).length, days.length - 1);
    final breakdown = calculatePayroll(
      employee: person,
      attendance: [absent],
      records: const [],
      month: 10,
      year: 2026,
    );
    expect(breakdown.absenceDeduction, 10);
    expect(breakdown.lateDeduction, 0);
    expect(breakdown.netSalary, 360);
  });

  test('an absence on a weekly day off does not reduce pay', () {
    final person = employee().copyWith(offWeekdays: const [DateTime.friday]);
    var friday = DateTime(2026, 10, 1);
    while (friday.weekday != DateTime.friday) {
      friday = friday.add(const Duration(days: 1));
    }
    final breakdown = calculatePayroll(
      employee: person,
      attendance: [
        AttendanceModel(
          id: 'off',
          employeeId: 'e1',
          date: friday,
          status: AttendanceStatus.absent,
          source: AttendanceSource.manual,
        ),
      ],
      records: const [],
      month: 10,
      year: 2026,
    );
    expect(breakdown.absenceDeduction, 0);
    expect(breakdown.netSalary, 370);
  });

  test('a penalty exception deducts and annual leave does not', () {
    final person = employee();
    final breakdown = calculatePayroll(
      employee: person,
      attendance: [
        AttendanceModel(
          id: 'leave',
          employeeId: 'e1',
          date: DateTime(2026, 10, 8),
          status: AttendanceStatus.leave,
          source: AttendanceSource.manual,
        ),
      ],
      records: [
        LoanAndLeaveModel(
          id: 'annual',
          employeeId: 'e1',
          type: LoanLeaveType.leave,
          leaveType: LeaveKind.annual,
          startDate: DateTime(2026, 10, 8),
          endDate: DateTime(2026, 10, 8),
        ),
        LoanAndLeaveModel(
          id: 'fine',
          employeeId: 'e1',
          type: LoanLeaveType.penalty,
          amount: 5,
          startDate: DateTime(2026, 10, 1),
          endDate: DateTime(2026, 10, 31),
        ),
      ],
      month: 10,
      year: 2026,
    );
    expect(breakdown.absenceDeduction, 0);
    expect(breakdown.penalties, 5);
    expect(breakdown.netSalary, 365);
  });

  test('PIN check-in records lateness and overtime without deducting unpunched days', () async {
    final desk = HrController(store: MemoryHrStore());
    await desk.saveEmployee(employee().copyWith(pinCode: '1234'));
    await desk.recordPinCheckIn('1234', DateTime(2026, 10, 5, 9));
    await desk.recordPinCheckOut(DateTime(2026, 10, 5, 18));
    final rows = await desk.calculateMonth(DateTime(2026, 10, 18));
    expect(desk.attendance.single.source, AttendanceSource.pin);
    expect(rows.single.lateDeduction, closeTo(1.25, 0.001));
    expect(rows.single.overtimeAmount, 4);
    expect(rows.single.absenceDeduction, 0);
    expect(rows.single.netSalary, closeTo(372.75, 0.001));
  });

  test('absence on a monthly off date does not reduce pay', () {
    final person = employee().copyWith(
      offDaysType: OffDaysType.monthly,
      monthlyOffDates: const [15],
    );
    final breakdown = calculatePayroll(
      employee: person,
      attendance: [
        AttendanceModel(
          id: 'off',
          employeeId: 'e1',
          date: DateTime(2026, 10, 15),
          status: AttendanceStatus.absent,
          source: AttendanceSource.manual,
        ),
      ],
      records: const [],
      month: 10,
      year: 2026,
    );
    expect(employeeWorksOn(person, DateTime(2026, 10, 15)), isFalse);
    expect(breakdown.absenceDeduction, 0);
    expect(breakdown.netSalary, 370);
  });

  test('a monthly off-day count forgives that many recorded absences', () {
    final person = employee().copyWith(
      offDaysType: OffDaysType.monthly,
      monthlyOffDayCount: 1,
    );
    final breakdown = calculatePayroll(
      employee: person,
      attendance: [
        AttendanceModel(
          id: 'a1',
          employeeId: 'e1',
          date: DateTime(2026, 10, 3),
          status: AttendanceStatus.absent,
        ),
        AttendanceModel(
          id: 'a2',
          employeeId: 'e1',
          date: DateTime(2026, 10, 4),
          status: AttendanceStatus.absent,
        ),
      ],
      records: const [],
      month: 10,
      year: 2026,
    );
    expect(breakdown.absenceDeduction, 10);
    expect(breakdown.netSalary, 360);
  });

  test('overtime is the time after the employee end hour', () {
    final person = employee().copyWith(shiftEndMinutes: 16 * 60);
    final breakdown = calculatePayroll(
      employee: person,
      attendance: [
        AttendanceModel(
          id: 'pin',
          employeeId: 'e1',
          date: DateTime(2026, 10, 5),
          status: AttendanceStatus.present,
          source: AttendanceSource.pin,
          checkInTime: DateTime(2026, 10, 5, 8),
          checkOutTime: DateTime(2026, 10, 5, 17),
        ),
      ],
      records: const [],
      month: 10,
      year: 2026,
    );
    expect(breakdown.lateDeduction, 0);
    expect(breakdown.overtimeAmount, 2);
    expect(breakdown.netSalary, 372);
  });
}
