import '../models/hr_models.dart';

const hrStandardDayMinutes = 8 * 60;

double hrRoundMoney(double value) => double.parse(value.toStringAsFixed(3));

DateTime hrDateOnly(DateTime value) => DateTime(value.year, value.month, value.day);

int hrDaysUntil(DateTime expiry, DateTime now) {
  return hrDateOnly(expiry).difference(hrDateOnly(now)).inDays;
}

/// Yellow 31–60, orange 7–30, red under 7 or already expired.
DocAlertLevel docAlertLevel(DateTime? expiry, DateTime now) {
  if (expiry == null) return DocAlertLevel.ok;
  final days = hrDaysUntil(expiry, now);
  if (days < 7) return DocAlertLevel.critical;
  if (days <= 30) return DocAlertLevel.urgent;
  if (days <= 60) return DocAlertLevel.warning;
  return DocAlertLevel.ok;
}

List<HrDocumentAlert> collectDocumentAlerts(
  Iterable<EmployeeModel> employees,
  DateTime now, {
  bool activeOnly = true,
}) {
  final alerts = <HrDocumentAlert>[];
  for (final employee in employees) {
    if (activeOnly && employee.status != EmployeeStatus.active) continue;
    for (final kind in HrDocumentKind.values) {
      final expiry = employee.expiryFor(kind);
      if (expiry == null) continue;
      final level = docAlertLevel(expiry, now);
      if (level == DocAlertLevel.ok) continue;
      alerts.add(
        HrDocumentAlert(
          employee: employee,
          kind: kind,
          expiry: expiry,
          daysLeft: hrDaysUntil(expiry, now),
          level: level,
        ),
      );
    }
  }
  alerts.sort((a, b) => a.daysLeft.compareTo(b.daysLeft));
  return alerts;
}

List<HrDocumentAlert> filterDocumentAlerts(
  List<HrDocumentAlert> alerts,
  DocAlertFilter filter,
) {
  return switch (filter) {
    DocAlertFilter.all => alerts,
    DocAlertFilter.expiring => alerts
        .where(
          (alert) =>
              alert.level == DocAlertLevel.warning ||
              alert.level == DocAlertLevel.urgent,
        )
        .toList(),
    DocAlertFilter.expired =>
      alerts.where((alert) => alert.level == DocAlertLevel.critical).toList(),
  };
}

enum DocAlertFilter { all, expiring, expired }

String hrDocumentLabel(HrDocumentKind kind) => switch (kind) {
      HrDocumentKind.iqama => 'الإقامة / الهوية',
      HrDocumentKind.healthCard => 'الكارت الصحي',
      HrDocumentKind.passport => 'جواز السفر',
    };

String hrRenewalMessage(HrDocumentAlert alert) {
  final when = _clockDate(alert.expiry.toLocal());
  final remaining = alert.daysLeft < 0
      ? 'منتهية منذ ${alert.daysLeft.abs()} يوماً'
      : 'المتبقي ${alert.daysLeft} يوماً';
  return 'تنبيه تجديد من AlMenuPro: ${hrDocumentLabel(alert.kind)} للموظف ${alert.employee.name} تنتهي في $when. $remaining. يرجى التجديد.';
}

bool employeeWorksOn(EmployeeModel employee, DateTime date) {
  if (employee.offDaysType == OffDaysType.monthly) {
    return !employee.monthlyOffDates.contains(date.day);
  }
  return !employee.offWeekdays.contains(date.weekday);
}

int pinLateMinutes(DateTime checkIn, int shiftStartMinutes) {
  final minuteOfDay = checkIn.hour * 60 + checkIn.minute;
  final late = minuteOfDay - shiftStartMinutes;
  return late > 0 ? late : 0;
}

class ResolvedAttendanceDay {
  const ResolvedAttendanceDay({
    required this.date,
    required this.status,
    required this.source,
    required this.lateMinutes,
    required this.overtimeMinutes,
  });

  final DateTime date;
  final AttendanceStatus status;
  final AttendanceSource source;
  final int lateMinutes;
  final int overtimeMinutes;

  bool get isAutoPresent => source == AttendanceSource.autoPresent;
}

/// Scheduled work days default to present. A manager absence or leave replaces
/// that day. A PIN punch adds real lateness and overtime. A missing punch does not.
List<ResolvedAttendanceDay> resolveScheduledAttendance({
  required EmployeeModel employee,
  required Iterable<AttendanceModel> attendance,
  required int year,
  required int month,
}) {
  final byDay = <DateTime, List<AttendanceModel>>{};
  for (final row in attendance) {
    if (row.employeeId != employee.id) continue;
    if (row.date.year != year || row.date.month != month) continue;
    byDay.putIfAbsent(hrDateOnly(row.date), () => []).add(row);
  }

  final lastDay = DateTime(year, month + 1, 0).day;
  final resolved = <ResolvedAttendanceDay>[];
  for (var day = 1; day <= lastDay; day++) {
    final date = DateTime(year, month, day);
    if (!employeeWorksOn(employee, date)) continue;
    final rows = byDay[date] ?? const <AttendanceModel>[];
    final exception = _firstWhere(
      rows,
      (row) => row.status == AttendanceStatus.absent || row.status == AttendanceStatus.leave,
    );
    if (exception != null) {
      resolved.add(
        ResolvedAttendanceDay(
          date: date,
          status: exception.status,
          source: AttendanceSource.manual,
          lateMinutes: 0,
          overtimeMinutes: 0,
        ),
      );
      continue;
    }
    final punch = _firstWhere(
      rows,
      (row) => row.source == AttendanceSource.pin || row.checkInTime != null,
    );
    if (punch != null) {
      final late = _lateMinutes(punch, employee.shiftStartMinutes);
      resolved.add(
        ResolvedAttendanceDay(
          date: date,
          status: late > 0 ? AttendanceStatus.late : AttendanceStatus.present,
          source: punch.source == AttendanceSource.pin
              ? AttendanceSource.pin
              : AttendanceSource.manual,
          lateMinutes: late,
          overtimeMinutes: overtimeAgainstEnd(punch, employee),
        ),
      );
      continue;
    }
    resolved.add(
      ResolvedAttendanceDay(
        date: date,
        status: AttendanceStatus.present,
        source: AttendanceSource.autoPresent,
        lateMinutes: 0,
        overtimeMinutes: 0,
      ),
    );
  }
  return resolved;
}

AttendanceModel? _firstWhere(
  List<AttendanceModel> rows,
  bool Function(AttendanceModel row) test,
) {
  for (final row in rows) {
    if (test(row)) return row;
  }
  return null;
}

int _lateMinutes(AttendanceModel row, int shiftStartMinutes) {
  final checkIn = row.checkInTime;
  if (checkIn != null) return pinLateMinutes(checkIn, shiftStartMinutes);
  return row.lateMinutes < 0 ? 0 : row.lateMinutes;
}

/// Minutes worked after the employee's own end time.
int overtimeAgainstEnd(AttendanceModel row, EmployeeModel employee) {
  final checkOut = row.checkOutTime;
  if (checkOut == null) return 0;
  var minute = checkOut.hour * 60 + checkOut.minute;
  final day = hrDateOnly(row.date);
  final outDay = hrDateOnly(checkOut);
  if (outDay.isAfter(day)) {
    minute += outDay.difference(day).inDays * 24 * 60;
  }
  var end = employee.shiftEndMinutes;
  if (end <= employee.shiftStartMinutes) end += 24 * 60;
  final extra = minute - end;
  return extra > 0 ? extra : 0;
}

class PayrollBreakdown {
  const PayrollBreakdown({
    required this.basicSalary,
    required this.totalAllowances,
    required this.overtimeAmount,
    required this.absenceDeduction,
    required this.lateDeduction,
    required this.penalties,
    required this.loanDeduction,
    this.kitchenVoidDeduction = 0,
  });

  final double basicSalary;
  final double totalAllowances;
  final double overtimeAmount;
  final double absenceDeduction;
  final double lateDeduction;
  final double penalties;
  final double loanDeduction;
  final double kitchenVoidDeduction;

  /// Attendance/HR penalties only (excludes kitchen void debt and loans).
  double get operationalDeductions => absenceDeduction + lateDeduction + penalties;

  /// Total withheld before loan: operational + kitchen void (مديونية مطبخ).
  double get totalDeductionsBeforeLoan =>
      operationalDeductions + kitchenVoidDeduction;

  double get gross => basicSalary + totalAllowances + overtimeAmount;

  /// Net = gross − operational − kitchen void debt − loan installment.
  double get netSalary =>
      gross - operationalDeductions - kitchenVoidDeduction - loanDeduction;
}

PayrollBreakdown calculatePayroll({
  required EmployeeModel employee,
  required Iterable<AttendanceModel> attendance,
  required Iterable<LoanAndLeaveModel> records,
  required int month,
  required int year,
  double penalties = 0,
  double kitchenVoidDeduction = 0,
}) {
  final monthDays = resolveScheduledAttendance(
    employee: employee,
    attendance: attendance,
    year: year,
    month: month,
  );
  var absenceDays = 0;
  var lateMinutes = 0;
  var overtimeMinutes = 0;
  for (final day in monthDays) {
    if (day.status == AttendanceStatus.absent) absenceDays += 1;
    if (day.isAutoPresent) continue;
    lateMinutes += day.lateMinutes;
    overtimeMinutes += day.overtimeMinutes;
  }
  if (employee.offDaysType == OffDaysType.monthly &&
      employee.monthlyOffDates.isEmpty &&
      employee.monthlyOffDayCount > 0 &&
      absenceDays > 0) {
    final forgiven = absenceDays < employee.monthlyOffDayCount
        ? absenceDays
        : employee.monthlyOffDayCount;
    absenceDays -= forgiven;
  }

  final unpaidDays = records.where((row) {
    final start = row.startDate;
    return row.employeeId == employee.id &&
        row.type == LoanLeaveType.leave &&
        row.leaveType == LeaveKind.unpaid &&
        row.status == LoanLeaveStatus.approved &&
        _overlapsMonth(row, year, month) &&
        (start == null || employeeWorksOn(employee, start));
  }).length;

  final dailyRate = employee.basicSalary / 30;
  final minuteRate = employee.basicSalary / (30 * hrStandardDayMinutes);
  final absenceDeduction = (absenceDays + unpaidDays) * dailyRate;
  final lateDeduction = lateMinutes * minuteRate;
  final overtimeAmount = (overtimeMinutes / 60) * employee.hourlyOvertimeRate;

  var penaltyTotal = penalties < 0 ? 0.0 : penalties;
  for (final row in records) {
    if (row.employeeId != employee.id || row.type != LoanLeaveType.penalty) continue;
    if (row.status != LoanLeaveStatus.approved || row.amount <= 0) continue;
    if (!_overlapsMonth(row, year, month)) continue;
    penaltyTotal += row.amount;
  }

  var loanDeduction = 0.0;
  for (final loan in records) {
    if (loan.employeeId != employee.id || loan.type != LoanLeaveType.loan) continue;
    if (loan.status != LoanLeaveStatus.approved) continue;
    if (loan.amount <= 0 || loan.monthlyDeduction <= 0) continue;
    loanDeduction += loan.monthlyDeduction < loan.amount
        ? loan.monthlyDeduction
        : loan.amount;
  }

  final kitchenDebt =
      hrRoundMoney(kitchenVoidDeduction < 0 ? 0.0 : kitchenVoidDeduction);
  return PayrollBreakdown(
    basicSalary: hrRoundMoney(employee.basicSalary),
    totalAllowances: hrRoundMoney(employee.totalAllowances),
    overtimeAmount: hrRoundMoney(overtimeAmount),
    absenceDeduction: hrRoundMoney(absenceDeduction),
    lateDeduction: hrRoundMoney(lateDeduction),
    penalties: hrRoundMoney(penaltyTotal),
    loanDeduction: hrRoundMoney(loanDeduction),
    kitchenVoidDeduction: kitchenDebt,
  );
}

List<PayrollModel> buildMonthlyPayroll({
  required Iterable<EmployeeModel> employees,
  required Iterable<AttendanceModel> attendance,
  required Iterable<LoanAndLeaveModel> records,
  required int month,
  required int year,
  double penalties = 0,
  Map<String, double> kitchenVoidByEmployee = const {},
  Map<String, PayrollStatus> existingStatus = const {},
}) {
  final rows = <PayrollModel>[];
  for (final employee in employees) {
    if (employee.status != EmployeeStatus.active) continue;
    final breakdown = calculatePayroll(
      employee: employee,
      attendance: attendance,
      records: records,
      month: month,
      year: year,
      penalties: penalties,
      kitchenVoidDeduction: kitchenVoidByEmployee[employee.id] ?? 0,
    );
    final id = 'pay_${employee.id}_${year}_$month';
    rows.add(
      PayrollModel(
        id: id,
        employeeId: employee.id,
        month: month,
        year: year,
        basicSalary: breakdown.basicSalary,
        totalAllowances: breakdown.totalAllowances,
        overtimeAmount: breakdown.overtimeAmount,
        deductions: breakdown.operationalDeductions,
        loanDeduction: breakdown.loanDeduction,
        netSalary: hrRoundMoney(breakdown.netSalary),
        status: existingStatus[id] ?? PayrollStatus.draft,
        absenceDeduction: breakdown.absenceDeduction,
        lateDeduction: breakdown.lateDeduction,
        penalties: breakdown.penalties,
        kitchenVoidDeduction: breakdown.kitchenVoidDeduction,
      ),
    );
  }
  return rows;
}

String payrollCsv(List<PayrollModel> rows, Map<String, EmployeeModel> employees) {
  final buffer = StringBuffer(
    'employee,month,year,basic,allowances,overtime,deductions,loan,net,status\n',
  );
  for (final row in rows) {
    final name = employees[row.employeeId]?.name ?? row.employeeId;
    buffer.writeln(
      '${_csv(name)},${row.month},${row.year},${_money(row.basicSalary)},${_money(row.totalAllowances)},${_money(row.overtimeAmount)},${_money(row.deductions)},${_money(row.loanDeduction)},${_money(row.netSalary)},${row.status.name}',
    );
  }
  return buffer.toString();
}

String payrollPrintHtml(List<PayrollModel> rows, Map<String, EmployeeModel> employees) {
  final body = rows.map((row) {
    final name = employees[row.employeeId]?.name ?? row.employeeId;
    return '<tr><td>${_html(name)}</td><td>${_money(row.basicSalary)}</td><td>${_money(row.totalAllowances)}</td><td>${_money(row.overtimeAmount)}</td><td>${_money(row.deductions)}</td><td>${_money(row.loanDeduction)}</td><td>${_money(row.netSalary)}</td></tr>';
  }).join();
  final title = rows.isEmpty ? 'مسير الرواتب' : 'مسير الرواتب ${rows.first.month}/${rows.first.year}';
  return '''
<!DOCTYPE html><html lang="ar" dir="rtl"><head><meta charset="utf-8"><title>$title</title>
<style>
body{font-family:sans-serif;color:#3f1d28}
h1{color:#800020}
table{width:100%;border-collapse:collapse}
th,td{border:1px solid #f3d7b0;padding:8px;text-align:right}
th{background:#800020;color:#fff}
</style></head><body>
<h1>$title</h1>
<table><thead><tr><th>الموظف</th><th>الأساسي</th><th>البدلات</th><th>الإضافي</th><th>الاستقطاعات</th><th>السلفة</th><th>الصافي</th></tr></thead>
<tbody>$body</tbody></table>
</body></html>
''';
}

bool _overlapsMonth(LoanAndLeaveModel row, int year, int month) {
  final start = row.startDate;
  if (start == null) return true;
  final end = row.endDate ?? start;
  final monthStart = DateTime(year, month);
  final monthEnd = DateTime(year, month + 1);
  return start.isBefore(monthEnd) && end.isAfter(monthStart.subtract(const Duration(days: 1)));
}

String _clockDate(DateTime value) {
  String two(int number) => number.toString().padLeft(2, '0');
  return '${value.year}-${two(value.month)}-${two(value.day)}';
}

String _money(double value) => value.toStringAsFixed(3);

String _csv(String value) {
  final escaped = value.replaceAll('"', '""');
  return '"$escaped"';
}

String _html(String value) => value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;');
