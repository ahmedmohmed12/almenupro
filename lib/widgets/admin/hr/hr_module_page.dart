import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../models/hr_models.dart';
import '../../../services/hr_compliance.dart';
import '../../../services/hr_controller.dart';
import '../../../services/hr_job_roles.dart';
import '../../../services/hr_pos_cashier_sync.dart';
import '../../../utils/whatsapp_launcher.dart';
import '../settings/link_hub_qr_download.dart';
import '../../../models/staff_user.dart';
import '../../../services/pos_operations_service.dart';
import 'hr_provision_pos_cashier_dialog.dart';

const _burgundy = Color(0xFF800020);
const _lightOrange = Color(0xFFFF9F43);
const _darkOrange = Color(0xFFE67E22);

class HrModulePage extends StatefulWidget {
  const HrModulePage({super.key});

  @override
  State<HrModulePage> createState() => _HrModulePageState();
}

class _HrModulePageState extends State<HrModulePage>
    with SingleTickerProviderStateMixin {
  final _hr = HrController.instance;
  late final TabController _tabs = TabController(length: 4, vsync: this);

  @override
  void initState() {
    super.initState();
    _hr.addListener(_rebuild);
    if (!_hr.ready) _hr.load();
  }

  @override
  void dispose() {
    _hr.removeListener(_rebuild);
    _tabs.dispose();
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: ColoredBox(
        color: const Color(0xFFF8F4F5),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 4),
              child: Text(
                'شؤون الموظفين والرواتب والالتزام',
                style: TextStyle(
                  color: _burgundy,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            TabBar(
              controller: _tabs,
              labelColor: _burgundy,
              unselectedLabelColor: const Color(0xFF64748B),
              indicatorColor: _lightOrange,
              isScrollable: true,
              tabs: const [
                Tab(text: 'الوثائق'),
                Tab(text: 'الموظفون'),
                Tab(text: 'الحضور والسلف'),
                Tab(text: 'مسير الرواتب'),
              ],
            ),
            Expanded(
              child: TabBarView(
                controller: _tabs,
                children: [
                  _DocsTab(hr: _hr),
                  _EmployeesTab(hr: _hr),
                  _AttendanceTab(hr: _hr),
                  _PayrollTab(hr: _hr),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DocsTab extends StatefulWidget {
  const _DocsTab({required this.hr});

  final HrController hr;

  @override
  State<_DocsTab> createState() => _DocsTabState();
}

class _DocsTabState extends State<_DocsTab> {
  var _filter = DocAlertFilter.all;
  late final _phone = TextEditingController(text: widget.hr.compliancePhone);

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final alerts = filterDocumentAlerts(widget.hr.alertsAt(DateTime.now()), _filter);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        TextField(
          controller: _phone,
          decoration: const InputDecoration(
            labelText: 'واتساب مندوب المعاملات أو صاحب العمل',
            border: OutlineInputBorder(),
          ),
          onSubmitted: widget.hr.setCompliancePhone,
        ),
        const SizedBox(height: 8),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _burgundy),
            onPressed: () => widget.hr.setCompliancePhone(_phone.text),
            child: const Text('حفظ رقم التنبيه'),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          children: [
            for (final filter in DocAlertFilter.values)
              FilterChip(
                label: Text(_filterLabel(filter)),
                selected: _filter == filter,
                selectedColor: _lightOrange,
                onSelected: (_) => setState(() => _filter = filter),
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (alerts.isEmpty)
          const Text('لا توجد وثائق ضمن هذا التصفية.')
        else
          for (final alert in alerts) _DocCard(alert: alert, phone: widget.hr.compliancePhone),
      ],
    );
  }
}

class _DocCard extends StatelessWidget {
  const _DocCard({required this.alert, required this.phone});

  final HrDocumentAlert alert;
  final String phone;

  @override
  Widget build(BuildContext context) {
    final color = switch (alert.level) {
      DocAlertLevel.warning => const Color(0xFFCA8A04),
      DocAlertLevel.urgent => _darkOrange,
      DocAlertLevel.critical => const Color(0xFFB91C1C),
      DocAlertLevel.ok => const Color(0xFF15803D),
    };
    return Card(
      child: ListTile(
        title: Text('${alert.employee.name} • ${hrDocumentLabel(alert.kind)}'),
        subtitle: Text(
          alert.daysLeft < 0
              ? 'منتهية منذ ${alert.daysLeft.abs()} يوماً'
              : 'المتبقي ${alert.daysLeft} يوماً',
        ),
        leading: Icon(Icons.circle, color: color, size: 14),
        trailing: IconButton(
          tooltip: 'واتساب',
          onPressed: phone.trim().isEmpty
              ? null
              : () => openWhatsAppChat(phone: phone, message: hrRenewalMessage(alert)),
          icon: const Icon(Icons.chat, color: Color(0xFF25D366)),
        ),
      ),
    );
  }
}

class _EmployeesTab extends StatefulWidget {
  const _EmployeesTab({required this.hr});

  final HrController hr;

  @override
  State<_EmployeesTab> createState() => _EmployeesTabState();
}

class _EmployeesTabState extends State<_EmployeesTab> {
  var _loadingStaff = true;
  List<StaffUser> _posStaff = const [];

  HrController get hr => widget.hr;

  @override
  void initState() {
    super.initState();
    hr.addListener(_onHrChanged);
    unawaited(_loadPosStaff());
  }

  @override
  void dispose() {
    hr.removeListener(_onHrChanged);
    super.dispose();
  }

  void _onHrChanged() {
    if (mounted) setState(() {});
  }

  StaffUser? _linkedCashier(String employeeId) {
    for (final row in _posStaff) {
      if (row.employeeId == employeeId && row.isActive) return row;
    }
    return null;
  }

  Future<void> _loadPosStaff() async {
    setState(() => _loadingStaff = true);
    try {
      final rows = await PosOperationsService.instance.fetchStaffUsers();
      if (!mounted) return;
      setState(() {
        _posStaff = rows;
        _loadingStaff = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _posStaff = const [];
        _loadingStaff = false;
      });
    }
  }

  Future<void> _assignCashier(EmployeeModel employee) async {
    final created = await showHrProvisionPosCashierDialog(
      context,
      employee: employee,
    );
    if (created != null) await _loadPosStaff();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'إنشاء وتعيين الكاشير يتم حصرياً من هنا — اربط موظف HR برمز PIN لدخول POS (دور كاشير فقط).',
          style: TextStyle(fontSize: 12, color: Color(0xFF64748B), height: 1.35),
        ),
        const SizedBox(height: 10),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: _burgundy),
            onPressed: () async {
              await _editEmployee(context, hr, null);
              if (context.mounted) {
                await (context.findAncestorStateOfType<_EmployeesTabState>())?._loadPosStaff();
              }
            },
            icon: const Icon(Icons.person_add_alt),
            label: const Text('موظف جديد'),
          ),
        ),
        const SizedBox(height: 12),
        if (hr.employees.isEmpty)
          const Text('لا يوجد موظفون بعد.')
        else
          for (final employee in hr.employees)
            Card(
              child: ListTile(
                title: Text(employee.name),
                subtitle: Text(
                  [
                    employee.jobTitle,
                    '${_formatShift(employee.shiftStartMinutes)}–${_formatShift(employee.shiftEndMinutes)}',
                    employee.status == EmployeeStatus.active ? 'نشط' : 'متوقف',
                    if (_loadingStaff) '… جاري تحميل ربط POS'
                    else if (_linkedCashier(employee.id) != null)
                      'كاشير POS: ${_linkedCashier(employee.id)!.maskedPin}'
                    else if (employee.status == EmployeeStatus.active)
                      'بدون حساب كاشير POS',
                  ].join(' • '),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!_loadingStaff &&
                        employee.status == EmployeeStatus.active &&
                        _linkedCashier(employee.id) == null)
                      IconButton(
                        tooltip: 'تعيين كاشير POS',
                        icon: const Icon(Icons.point_of_sale_outlined, color: _burgundy),
                        onPressed: () => _assignCashier(employee),
                      ),
                    IconButton(
                      icon: const Icon(Icons.edit_outlined),
                      onPressed: () async {
                        await _editEmployee(context, hr, employee);
                        await _loadPosStaff();
                      },
                    ),
                  ],
                ),
              ),
            ),
      ],
    );
  }
}

class _AttendanceTab extends StatelessWidget {
  const _AttendanceTab({required this.hr});

  final HrController hr;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'الحضور افتراضي لكل يوم عمل. الخصم يتم فقط من غياب أو إجازة بدون راتب أو جزاء يسجّله المدير. نسيان رمز الدخول لا يخصم الراتب، ودخول الـ PIN يسجل وقت التأخير والإضافي فقط.',
          style: TextStyle(color: _burgundy, height: 1.4),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          children: [
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: _burgundy),
              onPressed: hr.employees.isEmpty ? null : () => _addAttendance(context, hr),
              child: const Text('تسجيل استثناء'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: _darkOrange),
              onPressed: hr.employees.isEmpty ? null : () => _addLoan(context, hr),
              child: const Text('سلفة أو جزاء'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        for (final employee in hr.employees)
          if (employee.status == EmployeeStatus.active)
            _AutoPresentLine(hr: hr, employee: employee),
        const Text('البصمة والاستثناءات', style: TextStyle(fontWeight: FontWeight.w800, color: _burgundy)),
        if (hr.attendance.isEmpty) const Text('لا توجد استثناءات. الأيام غير المسجلة تُحسب حضوراً كاملاً.'),
        for (final row in hr.attendance.reversed.take(20))
          ListTile(
            dense: true,
            title: Text(_name(hr, row.employeeId)),
            subtitle: Text(_attendanceLine(row)),
          ),
        const Divider(),
        const Text('السلف والإجازات', style: TextStyle(fontWeight: FontWeight.w800, color: _burgundy)),
        if (hr.records.isEmpty) const Text('لا توجد سلف أو إجازات.'),
        for (final row in hr.records.reversed)
          ListTile(
            dense: true,
            title: Text(_name(hr, row.employeeId)),
            subtitle: Text(_recordLine(row)),
          ),
      ],
    );
  }
}

class _PayrollTab extends StatelessWidget {
  const _PayrollTab({required this.hr});

  final HrController hr;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final rows = hr.payroll
        .where((row) => row.month == now.month && row.year == now.year)
        .toList();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: _burgundy),
              onPressed: () => hr.calculateMonth(now),
              icon: const Icon(Icons.calculate_outlined),
              label: const Text('احتساب الرواتب للشهر الحالي'),
            ),
            OutlinedButton(
              onPressed: rows.isEmpty
                  ? null
                  : () => downloadBytesAsFile(
                        Uint8List.fromList(utf8.encode(payrollCsv(rows, hr.employeesById))),
                        filename: 'payroll-${now.year}-${now.month}.csv',
                        mime: 'text/csv;charset=utf-8',
                      ),
              child: const Text('Excel'),
            ),
            OutlinedButton(
              onPressed: rows.isEmpty
                  ? null
                  : () => openReportPrintView(payrollPrintHtml(rows, hr.employeesById)),
              child: const Text('PDF / طباعة'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        const Text(
          'الأيام بلا بصمة تبقى براتب اليوم الكامل. الغياب في يوم العطلة لا يُخصم. التأخير من ساعة البداية، والإضافي بعد ساعة النهاية في بطاقة الموظف.',
        ),
        const SizedBox(height: 12),
        if (rows.isEmpty)
          const Text('اضغط احتساب الرواتب ليظهر مسير هذا الشهر.')
        else
          for (final row in rows)
            Card(
              child: ListTile(
                title: Text(_name(hr, row.employeeId)),
                subtitle: Text(
                  'الصافي ${row.netSalary.toStringAsFixed(3)} • استقطاع ${row.deductions.toStringAsFixed(3)}'
                  '${row.kitchenVoidDeduction > 0 ? ' • مديونية مطبخ ${row.kitchenVoidDeduction.toStringAsFixed(3)}' : ''}'
                  ' • سلفة ${row.loanDeduction.toStringAsFixed(3)}',
                ),
                trailing: row.status == PayrollStatus.paid
                    ? const Text('مدفوع', style: TextStyle(color: Color(0xFF15803D)))
                    : TextButton(
                        onPressed: () => hr.markPayrollPaid(row.id),
                        child: const Text('اعتماد الدفع'),
                      ),
              ),
            ),
      ],
    );
  }
}

String _name(HrController hr, String id) =>
    hr.employeesById[id]?.name ?? id;

String _filterLabel(DocAlertFilter filter) => switch (filter) {
      DocAlertFilter.all => 'الكل',
      DocAlertFilter.expiring => 'وشيك الانتهاء',
      DocAlertFilter.expired => 'المنتهي',
    };

Future<void> _editEmployee(
  BuildContext context,
  HrController hr,
  EmployeeModel? current,
) async {
  final name = TextEditingController(text: current?.name ?? '');
  final phone = TextEditingController(text: current?.phone ?? '');
  final jobCustom = TextEditingController(
    text: current != null && !HrRestaurantJobs.presetJobs.contains(current.jobTitle)
        ? current.jobTitle
        : '',
  );
  var jobPreset = (() {
    final title = current?.jobTitle.trim() ?? '';
    if (title.isEmpty) return HrRestaurantJobs.cashier;
    if (HrRestaurantJobs.presetJobs.contains(title)) return title;
    return 'أخرى';
  })();
  final branch = TextEditingController(text: current?.branchId ?? '');
  final pin = TextEditingController(text: current?.pinCode ?? '');
  final basic = TextEditingController(text: '${current?.basicSalary ?? 0}');
  final housing = TextEditingController(text: '${current?.housingAllowance ?? 0}');
  final other = TextEditingController(text: '${current?.otherAllowances ?? 0}');
  final overtime = TextEditingController(text: '${current?.hourlyOvertimeRate ?? 0}');
  var startMinutes = current?.shiftStartMinutes ?? 8 * 60;
  var endMinutes = current?.shiftEndMinutes ?? 16 * 60;
  var offType = current?.offDaysType ?? OffDaysType.weekly;
  final offDays = <int>{...?current?.offWeekdays};
  final monthlyDates = <int>{...?current?.monthlyOffDates};
  final monthlyCount = TextEditingController(text: '${current?.monthlyOffDayCount ?? 0}');
  var iqama = current?.iqamaExpiryDate;
  var health = current?.healthCardExpiryDate;
  var passport = current?.passportExpiryDate;
  var active = current?.status != EmployeeStatus.inactive;

  final saved = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setLocal) {
        Future<DateTime?> pick(DateTime? currentDate) async {
          final now = DateTime.now();
          return showDatePicker(
            context: context,
            initialDate: currentDate ?? now,
            firstDate: DateTime(now.year - 2),
            lastDate: DateTime(now.year + 12),
          );
        }

        return AlertDialog(
          title: Text(current == null ? 'موظف جديد' : 'تعديل موظف'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: name, decoration: const InputDecoration(labelText: 'الاسم')),
                TextField(controller: phone, decoration: const InputDecoration(labelText: 'الهاتف')),
                DropdownButtonFormField<String>(
                  value: jobPreset,
                  decoration: const InputDecoration(
                    labelText: 'مهمة الموظف في المطعم',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final entry in HrRestaurantJobs.presetJobs)
                      DropdownMenuItem(value: entry, child: Text(entry)),
                  ],
                  onChanged: (value) => setLocal(() => jobPreset = value ?? jobPreset),
                ),
                if (jobPreset == 'أخرى')
                  TextField(
                    controller: jobCustom,
                    decoration: const InputDecoration(
                      labelText: 'المسمى / المهمة',
                      border: OutlineInputBorder(),
                    ),
                  ),
                if (HrRestaurantJobs.isCashierJob(
                  jobPreset == 'أخرى' ? jobCustom.text : jobPreset,
                ))
                  const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Text(
                      'عند الحفظ يُربط الموظف تلقائياً ككاشير POS (دور كاشير فقط) برمز الدخول والفرع.',
                      style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                    ),
                  ),
                TextField(controller: branch, decoration: const InputDecoration(labelText: 'الفرع')),
                TextField(
                  controller: pin,
                  keyboardType: TextInputType.number,
                  maxLength: 4,
                  decoration: const InputDecoration(
                    labelText: 'رمز الدخول (4 أرقام)',
                    counterText: '',
                  ),
                ),
                TextField(controller: basic, decoration: const InputDecoration(labelText: 'الراتب الأساسي')),
                TextField(controller: housing, decoration: const InputDecoration(labelText: 'بدل السكن')),
                TextField(controller: other, decoration: const InputDecoration(labelText: 'بدلات أخرى')),
                TextField(controller: overtime, decoration: const InputDecoration(labelText: 'أجر الساعة الإضافية')),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('ساعة بداية العمل'),
                  subtitle: Text(_formatShift(startMinutes)),
                  trailing: const Icon(Icons.schedule, color: _burgundy),
                  onTap: () async {
                    final picked = await showTimePicker(
                      context: context,
                      initialTime: _timeFromMinutes(startMinutes),
                    );
                    if (picked == null) return;
                    setLocal(() => startMinutes = picked.hour * 60 + picked.minute);
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('ساعة نهاية العمل'),
                  subtitle: Text(_formatShift(endMinutes)),
                  trailing: const Icon(Icons.schedule, color: _darkOrange),
                  onTap: () async {
                    final picked = await showTimePicker(
                      context: context,
                      initialTime: _timeFromMinutes(endMinutes),
                    );
                    if (picked == null) return;
                    setLocal(() => endMinutes = picked.hour * 60 + picked.minute);
                  },
                ),
                const SizedBox(height: 8),
                DropdownButton<OffDaysType>(
                  value: offType,
                  isExpanded: true,
                  items: const [
                    DropdownMenuItem(value: OffDaysType.weekly, child: Text('عطلة أسبوعية')),
                    DropdownMenuItem(value: OffDaysType.monthly, child: Text('عطلة شهرية')),
                  ],
                  onChanged: (value) => setLocal(() => offType = value ?? offType),
                ),
                if (offType == OffDaysType.weekly) ...[
                  const Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Text('أيام العطلة الأسبوعية'),
                  ),
                  Wrap(
                    spacing: 6,
                    children: [
                      for (final day in _weekdays)
                        FilterChip(
                          label: Text(_weekdayLabel(day)),
                          selected: offDays.contains(day),
                          selectedColor: _lightOrange,
                          onSelected: (selected) {
                            setLocal(() {
                              if (selected) {
                                offDays.add(day);
                              } else {
                                offDays.remove(day);
                              }
                            });
                          },
                        ),
                    ],
                  ),
                ] else ...[
                  TextField(
                    controller: monthlyCount,
                    decoration: const InputDecoration(labelText: 'عدد أيام العطلة في الشهر'),
                  ),
                  const SizedBox(height: 8),
                  const Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Text('أو اختر تواريخ الشهر'),
                  ),
                  Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: [
                      for (var day = 1; day <= 31; day++)
                        FilterChip(
                          label: Text('$day'),
                          selected: monthlyDates.contains(day),
                          selectedColor: _lightOrange,
                          onSelected: (selected) {
                            setLocal(() {
                              if (selected) {
                                monthlyDates.add(day);
                              } else {
                                monthlyDates.remove(day);
                              }
                            });
                          },
                        ),
                    ],
                  ),
                  const Text(
                    'الغياب أو عدم الحضور في هذه الأيام لا يُخصم. بدون تواريخ، العدد يُسقط أياماً من الغياب المسجّل.',
                    style: TextStyle(fontSize: 12),
                  ),
                ],
                TextButton(
                  onPressed: () async {
                    iqama = await pick(iqama);
                    setLocal(() {});
                  },
                  child: Text('الإقامة: ${iqama == null ? '—' : _day(iqama!)}'),
                ),
                TextButton(
                  onPressed: () async {
                    health = await pick(health);
                    setLocal(() {});
                  },
                  child: Text('الكارت الصحي: ${health == null ? '—' : _day(health!)}'),
                ),
                TextButton(
                  onPressed: () async {
                    passport = await pick(passport);
                    setLocal(() {});
                  },
                  child: Text('الجواز: ${passport == null ? '—' : _day(passport!)}'),
                ),
                SwitchListTile(
                  value: active,
                  title: const Text('نشط'),
                  onChanged: (value) => setLocal(() => active = value),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('رجوع')),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('حفظ'),
            ),
          ],
        );
      },
    ),
  );
  if (saved == true && name.text.trim().isNotEmpty) {
    final resolvedJob =
        jobPreset == 'أخرى' ? jobCustom.text.trim() : jobPreset.trim();
    final employee = EmployeeModel(
        id: current?.id ?? 'emp_${DateTime.now().microsecondsSinceEpoch}',
        name: name.text.trim(),
        phone: phone.text.trim(),
        jobTitle: resolvedJob.isEmpty ? jobPreset : resolvedJob,
        branchId: branch.text.trim(),
        status: active ? EmployeeStatus.active : EmployeeStatus.inactive,
        pinCode: pin.text.trim(),
        basicSalary: double.tryParse(basic.text) ?? 0,
        housingAllowance: double.tryParse(housing.text) ?? 0,
        otherAllowances: double.tryParse(other.text) ?? 0,
        hourlyOvertimeRate: double.tryParse(overtime.text) ?? 0,
        shiftStartMinutes: startMinutes,
        shiftEndMinutes: endMinutes,
        offDaysType: offType,
        offWeekdays: offDays.toList(),
        monthlyOffDates: monthlyDates.toList(),
        monthlyOffDayCount: int.tryParse(monthlyCount.text) ?? 0,
        iqamaExpiryDate: iqama,
        healthCardExpiryDate: health,
        passportExpiryDate: passport,
      );
    await hr.saveEmployee(employee);
    String? syncError;
    try {
      await HrPosCashierSync.syncAfterEmployeeSave(employee);
    } catch (error) {
      syncError = error.toString().replaceFirst('Exception: ', '');
    }
    if (context.mounted) {
      final messenger = ScaffoldMessenger.of(context);
      if (syncError == null && HrRestaurantJobs.isCashierJob(employee.jobTitle)) {
        messenger.showSnackBar(
          const SnackBar(content: Text('تم حفظ الموظف وربط كاشير POS')),
        );
      } else if (syncError != null) {
        messenger.showSnackBar(SnackBar(content: Text(syncError)));
      }
    }
  }
  name.dispose();
  phone.dispose();
  jobCustom.dispose();
  branch.dispose();
  pin.dispose();
  basic.dispose();
  housing.dispose();
  other.dispose();
  overtime.dispose();
  monthlyCount.dispose();
}

Future<void> _addAttendance(BuildContext context, HrController hr) async {
  var employeeId = hr.employees.first.id;
  var status = AttendanceStatus.absent;
  var leave = LeaveKind.annual;
  var date = DateTime.now();
  final saved = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setLocal) => AlertDialog(
        title: const Text('استثناء حضور'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButton<String>(
              value: employeeId,
              isExpanded: true,
              items: [
                for (final employee in hr.employees)
                  DropdownMenuItem(value: employee.id, child: Text(employee.name)),
              ],
              onChanged: (value) => setLocal(() => employeeId = value ?? employeeId),
            ),
            DropdownButton<AttendanceStatus>(
              value: status,
              isExpanded: true,
              items: const [
                DropdownMenuItem(value: AttendanceStatus.absent, child: Text('غياب')),
                DropdownMenuItem(value: AttendanceStatus.leave, child: Text('إجازة')),
              ],
              onChanged: (value) => setLocal(() => status = value ?? status),
            ),
            if (status == AttendanceStatus.leave)
              DropdownButton<LeaveKind>(
                value: leave,
                isExpanded: true,
                items: const [
                  DropdownMenuItem(value: LeaveKind.annual, child: Text('سنوية')),
                  DropdownMenuItem(value: LeaveKind.sick, child: Text('مرضية')),
                  DropdownMenuItem(value: LeaveKind.unpaid, child: Text('بدون راتب')),
                ],
                onChanged: (value) => setLocal(() => leave = value ?? leave),
              ),
            TextButton(
              onPressed: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: date,
                  firstDate: DateTime(date.year - 1),
                  lastDate: DateTime(date.year + 1),
                );
                if (picked != null) setLocal(() => date = picked);
              },
              child: Text('التاريخ ${_day(date)}'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('رجوع')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('حفظ')),
        ],
      ),
    ),
  );
  if (saved == true) {
    await hr.addAttendance(
      AttendanceModel(
        id: 'att_${DateTime.now().microsecondsSinceEpoch}',
        employeeId: employeeId,
        date: date,
        status: status,
        source: AttendanceSource.manual,
      ),
    );
    if (status == AttendanceStatus.leave) {
      await hr.addRecord(
        LoanAndLeaveModel(
          id: 'rec_${DateTime.now().microsecondsSinceEpoch}',
          employeeId: employeeId,
          type: LoanLeaveType.leave,
          leaveType: leave,
          status: LoanLeaveStatus.approved,
          startDate: date,
          endDate: date,
        ),
      );
    }
  }
}

Future<void> _addLoan(BuildContext context, HrController hr) async {
  var employeeId = hr.employees.first.id;
  var type = LoanLeaveType.loan;
  var leave = LeaveKind.annual;
  final amount = TextEditingController(text: '0');
  final installment = TextEditingController(text: '0');
  final saved = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setLocal) => AlertDialog(
        title: const Text('سلفة أو جزاء'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButton<String>(
              value: employeeId,
              isExpanded: true,
              items: [
                for (final employee in hr.employees)
                  DropdownMenuItem(value: employee.id, child: Text(employee.name)),
              ],
              onChanged: (value) => setLocal(() => employeeId = value ?? employeeId),
            ),
            DropdownButton<LoanLeaveType>(
              value: type,
              isExpanded: true,
              items: const [
                DropdownMenuItem(value: LoanLeaveType.loan, child: Text('سلفة')),
                DropdownMenuItem(value: LoanLeaveType.leave, child: Text('إجازة')),
                DropdownMenuItem(value: LoanLeaveType.penalty, child: Text('جزاء')),
              ],
              onChanged: (value) => setLocal(() => type = value ?? type),
            ),
            if (type == LoanLeaveType.leave)
              DropdownButton<LeaveKind>(
                value: leave,
                isExpanded: true,
                items: const [
                  DropdownMenuItem(value: LeaveKind.annual, child: Text('سنوية')),
                  DropdownMenuItem(value: LeaveKind.sick, child: Text('مرضية')),
                  DropdownMenuItem(value: LeaveKind.unpaid, child: Text('بدون راتب')),
                ],
                onChanged: (value) => setLocal(() => leave = value ?? leave),
              ),
            TextField(
              controller: amount,
              decoration: InputDecoration(
                labelText: type == LoanLeaveType.penalty ? 'مبلغ الجزاء' : 'المبلغ',
              ),
            ),
            if (type == LoanLeaveType.loan)
              TextField(
                controller: installment,
                decoration: const InputDecoration(labelText: 'القسط الشهري'),
              ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('رجوع')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('حفظ')),
        ],
      ),
    ),
  );
  if (saved == true) {
    final now = DateTime.now();
    await hr.addRecord(
      LoanAndLeaveModel(
        id: 'rec_${DateTime.now().microsecondsSinceEpoch}',
        employeeId: employeeId,
        type: type,
        amount: double.tryParse(amount.text) ?? 0,
        monthlyDeduction: double.tryParse(installment.text) ?? 0,
        leaveType: type == LoanLeaveType.leave ? leave : null,
        status: LoanLeaveStatus.approved,
        startDate: DateTime(now.year, now.month),
        endDate: DateTime(now.year, now.month + 1, 0),
      ),
    );
  }
  amount.dispose();
  installment.dispose();
}

class _AutoPresentLine extends StatelessWidget {
  const _AutoPresentLine({required this.hr, required this.employee});

  final HrController hr;
  final EmployeeModel employee;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final days = resolveScheduledAttendance(
      employee: employee,
      attendance: hr.attendance,
      year: now.year,
      month: now.month,
    );
    final auto = days.where((day) => day.isAutoPresent).length;
    final pin = days.where((day) => day.source == AttendanceSource.pin).length;
    final absent = days.where((day) => day.status == AttendanceStatus.absent).length;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text('${employee.name}: حضور تلقائي $auto • بصمة $pin • غياب $absent'),
    );
  }
}

const _weekdays = [
  DateTime.saturday,
  DateTime.sunday,
  DateTime.monday,
  DateTime.tuesday,
  DateTime.wednesday,
  DateTime.thursday,
  DateTime.friday,
];

TimeOfDay _timeFromMinutes(int minutes) {
  final hour = (minutes ~/ 60) % 24;
  final minute = minutes % 60;
  return TimeOfDay(hour: hour, minute: minute);
}

String _formatShift(int minutes) {
  final hour = (minutes ~/ 60) % 24;
  final minute = minutes % 60;
  final period = hour >= 12 ? 'م' : 'ص';
  final hour12 = hour % 12 == 0 ? 12 : hour % 12;
  String two(int number) => number.toString().padLeft(2, '0');
  return '${two(hour12)}:${two(minute)} $period';
}

String _weekdayLabel(int day) => switch (day) {
      DateTime.saturday => 'السبت',
      DateTime.sunday => 'الأحد',
      DateTime.monday => 'الاثنين',
      DateTime.tuesday => 'الثلاثاء',
      DateTime.wednesday => 'الأربعاء',
      DateTime.thursday => 'الخميس',
      _ => 'الجمعة',
    };

String _attendanceLine(AttendanceModel row) {
  final kind = switch (row.status) {
    AttendanceStatus.present => 'حاضر',
    AttendanceStatus.absent => 'غياب',
    AttendanceStatus.leave => 'إجازة',
    AttendanceStatus.late => 'متأخر',
  };
  final source = switch (row.source) {
    AttendanceSource.pin => 'بصمة',
    AttendanceSource.manual => 'استثناء',
    AttendanceSource.autoPresent => 'تلقائي',
  };
  final clock = row.checkInTime == null ? '' : ' • ${_clock(row.checkInTime!)}';
  return '$source • $kind • تأخر ${row.lateMinutes} د$clock';
}

String _recordLine(LoanAndLeaveModel row) {
  return switch (row.type) {
    LoanLeaveType.loan =>
      'سلفة ${row.amount.toStringAsFixed(3)} • قسط ${row.monthlyDeduction.toStringAsFixed(3)}',
    LoanLeaveType.leave => 'إجازة ${row.leaveType?.name ?? ''} • ${row.status.name}',
    LoanLeaveType.penalty => 'جزاء ${row.amount.toStringAsFixed(3)}',
  };
}

String _clock(DateTime value) {
  String two(int number) => number.toString().padLeft(2, '0');
  return '${two(value.hour)}:${two(value.minute)}';
}

String _day(DateTime value) {
  String two(int number) => number.toString().padLeft(2, '0');
  return '${value.year}-${two(value.month)}-${two(value.day)}';
}
