import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/hr_models.dart';
import 'hr_compliance.dart';

abstract class HrStore {
  Future<Map<String, dynamic>?> load();
  Future<void> save(Map<String, dynamic> json);
}

class MemoryHrStore implements HrStore {
  Map<String, dynamic>? saved;

  @override
  Future<Map<String, dynamic>?> load() async => saved;

  @override
  Future<void> save(Map<String, dynamic> json) async {
    saved = json;
  }
}

class SharedPrefsHrStore implements HrStore {
  static const key = 'hr_compliance_v1';

  @override
  Future<Map<String, dynamic>?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    if (raw == null || raw.isEmpty) return null;
    final decoded = jsonDecode(raw);
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
    return null;
  }

  @override
  Future<void> save(Map<String, dynamic> json) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, jsonEncode(json));
  }
}

/// Local HR desk. The admin app keeps employees, attendance, loans, and payroll.
class HrController extends ChangeNotifier {
  HrController({HrStore? store}) : store = store ?? SharedPrefsHrStore();

  static final HrController instance = HrController();

  final HrStore store;
  var ready = false;
  List<EmployeeModel> employees = const [];
  List<AttendanceModel> attendance = const [];
  List<LoanAndLeaveModel> records = const [];
  List<PayrollModel> payroll = const [];
  String compliancePhone = '';
  String? openPinAttendanceId;

  Future<void> load() async {
    final json = await store.load();
    if (json != null) {
      employees = _list(json['employees'], EmployeeModel.fromJson);
      attendance = _list(json['attendance'], AttendanceModel.fromJson);
      records = _list(json['records'], LoanAndLeaveModel.fromJson);
      payroll = _list(json['payroll'], PayrollModel.fromJson);
      compliancePhone = json['compliancePhone']?.toString() ?? '';
      final openPin = json['openPinAttendanceId']?.toString() ?? '';
      openPinAttendanceId = openPin.isEmpty ? null : openPin;
    }
    ready = true;
    notifyListeners();
  }

  Future<void> ensureLoaded() async {
    if (!ready) await load();
  }

  List<HrDocumentAlert> alertsAt(DateTime now) =>
      collectDocumentAlerts(employees, now);

  int alertCount(DocAlertLevel level, DateTime now) =>
      alertsAt(now).where((alert) => alert.level == level).length;

  Future<void> setCompliancePhone(String phone) async {
    compliancePhone = phone.trim();
    notifyListeners();
    await _save();
  }

  Future<void> saveEmployee(EmployeeModel employee) async {
    await ensureLoaded();
    final index = employees.indexWhere((row) => row.id == employee.id);
    if (index < 0) {
      employees = [...employees, employee];
    } else {
      final next = List<EmployeeModel>.of(employees);
      next[index] = employee;
      employees = next;
    }
    notifyListeners();
    await _save();
  }

  /// POS PIN login. Records the real check-in once per scheduled day.
  /// A missing punch is left as auto-present and is not written here.
  Future<AttendanceModel?> recordPinCheckIn(String pin, DateTime at) async {
    await ensureLoaded();
    final code = pin.trim();
    if (code.isEmpty) return null;
    EmployeeModel? employee;
    for (final row in employees) {
      if (row.status == EmployeeStatus.active && row.pinCode == code) {
        employee = row;
        break;
      }
    }
    if (employee == null || !employeeWorksOn(employee, at)) return null;
    final day = hrDateOnly(at);
    if (_hasException(employee.id, day)) return null;
    for (final row in attendance) {
      if (row.employeeId == employee.id &&
          row.source == AttendanceSource.pin &&
          hrDateOnly(row.date) == day) {
        openPinAttendanceId = row.id;
        if (row.checkOutTime != null) {
          await addAttendance(row.copyWith(clearCheckOut: true));
        } else {
          await _save();
        }
        return row.checkOutTime == null ? row : row.copyWith(clearCheckOut: true);
      }
    }
    await _closeOpenPin(at);
    final late = pinLateMinutes(at, employee.shiftStartMinutes);
    final punch = AttendanceModel(
      id: 'pin_${employee.id}_${day.year}_${day.month}_${day.day}',
      employeeId: employee.id,
      date: day,
      checkInTime: at,
      lateMinutes: late,
      status: late > 0 ? AttendanceStatus.late : AttendanceStatus.present,
      source: AttendanceSource.pin,
    );
    openPinAttendanceId = punch.id;
    await addAttendance(punch);
    return punch;
  }

  /// POS session end. Closes the open PIN punch so overtime can be calculated.
  Future<void> recordPinCheckOut(DateTime at) async {
    await ensureLoaded();
    await _closeOpenPin(at);
  }

  bool _hasException(String employeeId, DateTime day) {
    for (final row in attendance) {
      if (row.employeeId != employeeId || hrDateOnly(row.date) != day) continue;
      if (row.status == AttendanceStatus.absent || row.status == AttendanceStatus.leave) {
        return true;
      }
    }
    return false;
  }

  Future<void> _closeOpenPin(DateTime at) async {
    final id = openPinAttendanceId;
    if (id == null) return;
    AttendanceModel? open;
    for (final row in attendance) {
      if (row.id == id) open = row;
    }
    openPinAttendanceId = null;
    if (open == null || open.checkOutTime != null) {
      await _save();
      return;
    }
    await addAttendance(open.copyWith(checkOutTime: at));
  }

  Future<void> addAttendance(AttendanceModel row) async {
    await ensureLoaded();
    attendance = [...attendance.where((item) => item.id != row.id), row];
    notifyListeners();
    await _save();
  }

  Future<void> addRecord(LoanAndLeaveModel row) async {
    await ensureLoaded();
    records = [...records.where((item) => item.id != row.id), row];
    notifyListeners();
    await _save();
  }

  Future<List<PayrollModel>> calculateMonth(DateTime month, {double penalties = 0}) async {
    await ensureLoaded();
    final kept = {
      for (final row in payroll)
        if (row.month == month.month && row.year == month.year && row.status == PayrollStatus.paid)
          row.id: PayrollStatus.paid,
    };
    final fresh = buildMonthlyPayroll(
      employees: employees,
      attendance: attendance,
      records: records,
      month: month.month,
      year: month.year,
      penalties: penalties,
      existingStatus: kept,
    );
    payroll = [
      ...payroll.where((row) => row.month != month.month || row.year != month.year),
      ...fresh,
    ];
    notifyListeners();
    await _save();
    return fresh;
  }

  Future<void> markPayrollPaid(String id) async {
    await ensureLoaded();
    PayrollModel? slip;
    payroll = [
      for (final row in payroll)
        if (row.id == id) (slip = row.copyWith(status: PayrollStatus.paid)) else row,
    ];
    final paid = slip;
    if (paid != null && paid.loanDeduction > 0) {
      records = [
        for (final row in records)
          if (row.employeeId == paid.employeeId &&
              row.type == LoanLeaveType.loan &&
              row.status == LoanLeaveStatus.approved &&
              row.amount > 0)
            row.copyWith(
              amount: (row.amount - row.monthlyDeduction).clamp(0, row.amount).toDouble(),
              status: row.amount - row.monthlyDeduction <= 0
                  ? LoanLeaveStatus.closed
                  : row.status,
            )
          else
            row,
      ];
    }
    notifyListeners();
    await _save();
  }

  Map<String, EmployeeModel> get employeesById => {
        for (final employee in employees) employee.id: employee,
      };

  Future<void> _save() async {
    await store.save({
      'compliancePhone': compliancePhone,
      if (openPinAttendanceId != null) 'openPinAttendanceId': openPinAttendanceId,
      'employees': employees.map((row) => row.toJson()).toList(),
      'attendance': attendance.map((row) => row.toJson()).toList(),
      'records': records.map((row) => row.toJson()).toList(),
      'payroll': payroll.map((row) => row.toJson()).toList(),
    });
  }
}

List<T> _list<T>(Object? raw, T Function(Map<String, dynamic>) parse) {
  if (raw is! List) return const [];
  return raw
      .whereType<Map>()
      .map((entry) => parse(Map<String, dynamic>.from(entry)))
      .toList();
}
