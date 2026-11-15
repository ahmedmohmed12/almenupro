enum EmployeeStatus { active, inactive }

enum AttendanceStatus { present, absent, leave, late }

/// How a day was decided. Missing punches stay [autoPresent] and are not stored.
enum AttendanceSource { autoPresent, pin, manual }

enum LoanLeaveType { loan, leave, penalty }

enum LeaveKind { annual, sick, unpaid }

enum LoanLeaveStatus { pending, approved, rejected, closed }

enum PayrollStatus { draft, paid }

enum OffDaysType { weekly, monthly }

enum HrDocumentKind { iqama, healthCard, passport }

enum DocAlertLevel { ok, warning, urgent, critical }

class EmployeeModel {
  const EmployeeModel({
    required this.id,
    required this.name,
    required this.phone,
    required this.jobTitle,
    required this.branchId,
    this.status = EmployeeStatus.active,
    this.pinCode = '',
    this.basicSalary = 0,
    this.housingAllowance = 0,
    this.otherAllowances = 0,
    this.hourlyOvertimeRate = 0,
    this.shiftStartMinutes = 8 * 60,
    this.shiftEndMinutes = 16 * 60,
    this.offDaysType = OffDaysType.weekly,
    this.offWeekdays = const [],
    this.monthlyOffDates = const [],
    this.monthlyOffDayCount = 0,
    this.iqamaExpiryDate,
    this.healthCardExpiryDate,
    this.passportExpiryDate,
  });

  final String id;
  final String name;
  final String phone;
  final String jobTitle;
  final String branchId;
  final EmployeeStatus status;
  final String pinCode;
  final double basicSalary;
  final double housingAllowance;
  final double otherAllowances;
  final double hourlyOvertimeRate;

  /// Minutes from midnight. Lateness is measured against this start.
  final int shiftStartMinutes;

  /// Minutes from midnight. Overtime starts after this end.
  final int shiftEndMinutes;

  final OffDaysType offDaysType;

  /// DateTime weekday numbers. Used when [offDaysType] is weekly.
  final List<int> offWeekdays;

  /// Days of the month (1–31). Used when [offDaysType] is monthly.
  final List<int> monthlyOffDates;

  /// Monthly absence days that stay unpaid-free when no dates are chosen.
  final int monthlyOffDayCount;
  final DateTime? iqamaExpiryDate;
  final DateTime? healthCardExpiryDate;
  final DateTime? passportExpiryDate;

  double get totalAllowances => housingAllowance + otherAllowances;

  DateTime? expiryFor(HrDocumentKind kind) => switch (kind) {
        HrDocumentKind.iqama => iqamaExpiryDate,
        HrDocumentKind.healthCard => healthCardExpiryDate,
        HrDocumentKind.passport => passportExpiryDate,
      };

  EmployeeModel copyWith({
    String? name,
    String? phone,
    String? jobTitle,
    String? branchId,
    EmployeeStatus? status,
    String? pinCode,
    double? basicSalary,
    double? housingAllowance,
    double? otherAllowances,
    double? hourlyOvertimeRate,
    int? shiftStartMinutes,
    int? shiftEndMinutes,
    OffDaysType? offDaysType,
    List<int>? offWeekdays,
    List<int>? monthlyOffDates,
    int? monthlyOffDayCount,
    DateTime? iqamaExpiryDate,
    DateTime? healthCardExpiryDate,
    DateTime? passportExpiryDate,
    bool clearIqama = false,
    bool clearHealth = false,
    bool clearPassport = false,
  }) {
    return EmployeeModel(
      id: id,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      jobTitle: jobTitle ?? this.jobTitle,
      branchId: branchId ?? this.branchId,
      status: status ?? this.status,
      pinCode: pinCode ?? this.pinCode,
      basicSalary: basicSalary ?? this.basicSalary,
      housingAllowance: housingAllowance ?? this.housingAllowance,
      otherAllowances: otherAllowances ?? this.otherAllowances,
      hourlyOvertimeRate: hourlyOvertimeRate ?? this.hourlyOvertimeRate,
      shiftStartMinutes: shiftStartMinutes ?? this.shiftStartMinutes,
      shiftEndMinutes: shiftEndMinutes ?? this.shiftEndMinutes,
      offDaysType: offDaysType ?? this.offDaysType,
      offWeekdays: offWeekdays ?? this.offWeekdays,
      monthlyOffDates: monthlyOffDates ?? this.monthlyOffDates,
      monthlyOffDayCount: monthlyOffDayCount ?? this.monthlyOffDayCount,
      iqamaExpiryDate: clearIqama ? null : (iqamaExpiryDate ?? this.iqamaExpiryDate),
      healthCardExpiryDate:
          clearHealth ? null : (healthCardExpiryDate ?? this.healthCardExpiryDate),
      passportExpiryDate:
          clearPassport ? null : (passportExpiryDate ?? this.passportExpiryDate),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'phone': phone,
        'jobTitle': jobTitle,
        'branchId': branchId,
        'status': status.name,
        'pinCode': pinCode,
        'basicSalary': basicSalary,
        'housingAllowance': housingAllowance,
        'otherAllowances': otherAllowances,
        'hourlyOvertimeRate': hourlyOvertimeRate,
        'shiftStartMinutes': shiftStartMinutes,
        'shiftEndMinutes': shiftEndMinutes,
        'offDaysType': offDaysType.name,
        'offWeekdays': offWeekdays,
        'monthlyOffDates': monthlyOffDates,
        'monthlyOffDayCount': monthlyOffDayCount,
        if (iqamaExpiryDate != null) 'iqamaExpiryDate': iqamaExpiryDate!.toUtc().toIso8601String(),
        if (healthCardExpiryDate != null)
          'healthCardExpiryDate': healthCardExpiryDate!.toUtc().toIso8601String(),
        if (passportExpiryDate != null)
          'passportExpiryDate': passportExpiryDate!.toUtc().toIso8601String(),
      };

  factory EmployeeModel.fromJson(Map<String, dynamic> json) {
    return EmployeeModel(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      phone: json['phone']?.toString() ?? '',
      jobTitle: json['jobTitle']?.toString() ?? '',
      branchId: json['branchId']?.toString() ?? '',
      status: _enum(EmployeeStatus.values, json['status'], EmployeeStatus.active),
      pinCode: json['pinCode']?.toString() ?? '',
      basicSalary: _num(json['basicSalary']),
      housingAllowance: _num(json['housingAllowance']),
      otherAllowances: _num(json['otherAllowances']),
      hourlyOvertimeRate: _num(json['hourlyOvertimeRate']),
      shiftStartMinutes: json['shiftStartMinutes'] == null
          ? 8 * 60
          : _num(json['shiftStartMinutes']).round(),
      shiftEndMinutes: json['shiftEndMinutes'] == null
          ? 16 * 60
          : _num(json['shiftEndMinutes']).round(),
      offDaysType: _enum(OffDaysType.values, json['offDaysType'], OffDaysType.weekly),
      offWeekdays: _weekdays(json['offWeekdays']),
      monthlyOffDates: _monthDates(json['monthlyOffDates']),
      monthlyOffDayCount: _num(json['monthlyOffDayCount']).round(),
      iqamaExpiryDate: _date(json['iqamaExpiryDate']),
      healthCardExpiryDate: _date(json['healthCardExpiryDate']),
      passportExpiryDate: _date(json['passportExpiryDate']),
    );
  }
}

class AttendanceModel {
  const AttendanceModel({
    required this.id,
    required this.employeeId,
    required this.date,
    this.checkInTime,
    this.checkOutTime,
    this.lateMinutes = 0,
    this.status = AttendanceStatus.present,
    this.source = AttendanceSource.manual,
  });

  final String id;
  final String employeeId;
  final DateTime date;
  final DateTime? checkInTime;
  final DateTime? checkOutTime;
  final int lateMinutes;
  final AttendanceStatus status;
  final AttendanceSource source;

  AttendanceModel copyWith({
    DateTime? checkInTime,
    DateTime? checkOutTime,
    int? lateMinutes,
    AttendanceStatus? status,
    AttendanceSource? source,
    bool clearCheckOut = false,
  }) {
    return AttendanceModel(
      id: id,
      employeeId: employeeId,
      date: date,
      checkInTime: checkInTime ?? this.checkInTime,
      checkOutTime: clearCheckOut ? null : (checkOutTime ?? this.checkOutTime),
      lateMinutes: lateMinutes ?? this.lateMinutes,
      status: status ?? this.status,
      source: source ?? this.source,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'employeeId': employeeId,
        'date': date.toUtc().toIso8601String(),
        if (checkInTime != null) 'checkInTime': checkInTime!.toUtc().toIso8601String(),
        if (checkOutTime != null) 'checkOutTime': checkOutTime!.toUtc().toIso8601String(),
        'lateMinutes': lateMinutes,
        'status': status.name,
        'source': source.name,
      };

  factory AttendanceModel.fromJson(Map<String, dynamic> json) {
    return AttendanceModel(
      id: json['id']?.toString() ?? '',
      employeeId: json['employeeId']?.toString() ?? '',
      date: _date(json['date']) ?? DateTime.fromMillisecondsSinceEpoch(0),
      checkInTime: _date(json['checkInTime']),
      checkOutTime: _date(json['checkOutTime']),
      lateMinutes: _num(json['lateMinutes']).round(),
      status: _enum(AttendanceStatus.values, json['status'], AttendanceStatus.present),
      source: _enum(AttendanceSource.values, json['source'], AttendanceSource.manual),
    );
  }
}

class LoanAndLeaveModel {
  const LoanAndLeaveModel({
    required this.id,
    required this.employeeId,
    required this.type,
    this.amount = 0,
    this.monthlyDeduction = 0,
    this.leaveType,
    this.status = LoanLeaveStatus.approved,
    this.startDate,
    this.endDate,
  });

  final String id;
  final String employeeId;
  final LoanLeaveType type;
  final double amount;
  final double monthlyDeduction;
  final LeaveKind? leaveType;
  final LoanLeaveStatus status;
  final DateTime? startDate;
  final DateTime? endDate;

  Map<String, dynamic> toJson() => {
        'id': id,
        'employeeId': employeeId,
        'type': type.name,
        'amount': amount,
        'monthlyDeduction': monthlyDeduction,
        if (leaveType != null) 'leaveType': leaveType!.name,
        'status': status.name,
        if (startDate != null) 'startDate': startDate!.toUtc().toIso8601String(),
        if (endDate != null) 'endDate': endDate!.toUtc().toIso8601String(),
      };

  factory LoanAndLeaveModel.fromJson(Map<String, dynamic> json) {
    return LoanAndLeaveModel(
      id: json['id']?.toString() ?? '',
      employeeId: json['employeeId']?.toString() ?? '',
      type: _enum(LoanLeaveType.values, json['type'], LoanLeaveType.loan),
      amount: _num(json['amount']),
      monthlyDeduction: _num(json['monthlyDeduction']),
      leaveType: json['leaveType'] == null
          ? null
          : _enum(LeaveKind.values, json['leaveType'], LeaveKind.annual),
      status: _enum(LoanLeaveStatus.values, json['status'], LoanLeaveStatus.approved),
      startDate: _date(json['startDate']),
      endDate: _date(json['endDate']),
    );
  }

  LoanAndLeaveModel copyWith({double? amount, LoanLeaveStatus? status}) {
    return LoanAndLeaveModel(
      id: id,
      employeeId: employeeId,
      type: type,
      amount: amount ?? this.amount,
      monthlyDeduction: monthlyDeduction,
      leaveType: leaveType,
      status: status ?? this.status,
      startDate: startDate,
      endDate: endDate,
    );
  }
}

class PayrollModel {
  const PayrollModel({
    required this.id,
    required this.employeeId,
    required this.month,
    required this.year,
    required this.basicSalary,
    required this.totalAllowances,
    required this.overtimeAmount,
    required this.deductions,
    required this.loanDeduction,
    required this.netSalary,
    this.status = PayrollStatus.draft,
    this.absenceDeduction = 0,
    this.lateDeduction = 0,
    this.penalties = 0,
  });

  final String id;
  final String employeeId;
  final int month;
  final int year;
  final double basicSalary;
  final double totalAllowances;
  final double overtimeAmount;
  final double deductions;
  final double loanDeduction;
  final double netSalary;
  final PayrollStatus status;
  final double absenceDeduction;
  final double lateDeduction;
  final double penalties;

  Map<String, dynamic> toJson() => {
        'id': id,
        'employeeId': employeeId,
        'month': month,
        'year': year,
        'basicSalary': basicSalary,
        'totalAllowances': totalAllowances,
        'overtimeAmount': overtimeAmount,
        'deductions': deductions,
        'loanDeduction': loanDeduction,
        'netSalary': netSalary,
        'status': status.name,
        'absenceDeduction': absenceDeduction,
        'lateDeduction': lateDeduction,
        'penalties': penalties,
      };

  factory PayrollModel.fromJson(Map<String, dynamic> json) {
    return PayrollModel(
      id: json['id']?.toString() ?? '',
      employeeId: json['employeeId']?.toString() ?? '',
      month: _num(json['month']).round(),
      year: _num(json['year']).round(),
      basicSalary: _num(json['basicSalary']),
      totalAllowances: _num(json['totalAllowances']),
      overtimeAmount: _num(json['overtimeAmount']),
      deductions: _num(json['deductions']),
      loanDeduction: _num(json['loanDeduction']),
      netSalary: _num(json['netSalary']),
      status: _enum(PayrollStatus.values, json['status'], PayrollStatus.draft),
      absenceDeduction: _num(json['absenceDeduction']),
      lateDeduction: _num(json['lateDeduction']),
      penalties: _num(json['penalties']),
    );
  }

  PayrollModel copyWith({PayrollStatus? status}) {
    return PayrollModel(
      id: id,
      employeeId: employeeId,
      month: month,
      year: year,
      basicSalary: basicSalary,
      totalAllowances: totalAllowances,
      overtimeAmount: overtimeAmount,
      deductions: deductions,
      loanDeduction: loanDeduction,
      netSalary: netSalary,
      status: status ?? this.status,
      absenceDeduction: absenceDeduction,
      lateDeduction: lateDeduction,
      penalties: penalties,
    );
  }
}

class HrDocumentAlert {
  const HrDocumentAlert({
    required this.employee,
    required this.kind,
    required this.expiry,
    required this.daysLeft,
    required this.level,
  });

  final EmployeeModel employee;
  final HrDocumentKind kind;
  final DateTime expiry;
  final int daysLeft;
  final DocAlertLevel level;
}

T _enum<T extends Enum>(List<T> values, Object? raw, T fallback) {
  final name = raw?.toString() ?? '';
  for (final value in values) {
    if (value.name == name) return value;
  }
  return fallback;
}

List<int> _monthDates(Object? raw) {
  if (raw is! List) return const [];
  final days = <int>[];
  for (final entry in raw) {
    final day = entry is num ? entry.round() : int.tryParse(entry.toString());
    if (day != null && day >= 1 && day <= 31) days.add(day);
  }
  return days;
}

List<int> _weekdays(Object? raw) {
  if (raw is! List) return const [];
  final days = <int>[];
  for (final entry in raw) {
    final day = entry is num ? entry.round() : int.tryParse(entry.toString());
    if (day != null && day >= DateTime.monday && day <= DateTime.sunday) days.add(day);
  }
  return days;
}

double _num(Object? raw) {
  if (raw is num) return raw.toDouble();
  return double.tryParse(raw?.toString() ?? '') ?? 0;
}

DateTime? _date(Object? raw) {
  if (raw == null) return null;
  return DateTime.tryParse(raw.toString());
}
