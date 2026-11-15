import 'package:flutter/material.dart';

import '../../models/working_hours.dart';
import '../../services/restaurant_settings_service.dart';

class AdminWorkingHoursCard extends StatefulWidget {
  const AdminWorkingHoursCard({super.key});

  @override
  State<AdminWorkingHoursCard> createState() => _AdminWorkingHoursCardState();
}

class _AdminWorkingHoursCardState extends State<AdminWorkingHoursCard> {
  final _settingsService = RestaurantSettingsService.instance;

  var _isLoading = true;
  var _isSaving = false;
  List<WorkingDaySchedule> _days = WorkingDaySchedule.defaultWeek();

  @override
  void initState() {
    super.initState();
    _loadWorkingHours();
  }

  Future<void> _loadWorkingHours() async {
    setState(() => _isLoading = true);
    try {
      final settings = await _settingsService.load();
      if (!mounted) return;
      setState(() {
        _days = List<WorkingDaySchedule>.from(settings.workingHours.days);
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _days = WorkingDaySchedule.defaultWeek();
        _isLoading = false;
      });
    }
  }

  Future<void> _pickTime({
    required int index,
    required bool isOpenTime,
  }) async {
    final day = _days[index];
    final initial = isOpenTime ? day.openTime : day.closeTime;
    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
      helpText: isOpenTime ? 'وقت الفتح' : 'وقت الإغلاق',
      cancelText: 'إلغاء',
      confirmText: 'تم',
    );

    if (picked == null || !mounted) return;

    setState(() {
      _days[index] = day.copyWith(
        openTime: isOpenTime ? picked : day.openTime,
        closeTime: isOpenTime ? day.closeTime : picked,
      );
    });
  }

  Future<void> _saveWorkingHours() async {
    setState(() => _isSaving = true);
    try {
      await _settingsService.saveWorkingHours(WorkingHoursSettings(days: _days));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم حفظ مواعيد العمل بنجاح')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر حفظ مواعيد العمل: $error')),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF6B1124).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.schedule,
                    color: Color(0xFF6B1124),
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'مواعيد العمل',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF6B1124),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'حدد أيام وأوقات فتح وإغلاق المطعم من السبت إلى الجمعة.',
              style: TextStyle(color: Colors.grey.shade700),
            ),
            const SizedBox(height: 16),
            if (_isLoading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(color: Color(0xFF6B1124)),
                ),
              )
            else
              ...List.generate(_days.length, (index) {
                final day = _days[index];
                return _WorkingDayRow(
                  day: day,
                  onOpenChanged: (value) {
                    setState(() {
                      _days[index] = day.copyWith(isOpen: value);
                    });
                  },
                  onPickOpen: () => _pickTime(index: index, isOpenTime: true),
                  onPickClose: () => _pickTime(index: index, isOpenTime: false),
                );
              }),
            const SizedBox(height: 16),
            SizedBox(
              height: 48,
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6B1124),
                ),
                onPressed: _isLoading || _isSaving ? null : _saveWorkingHours,
                icon: _isSaving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Icon(Icons.save, color: Colors.white),
                label: Text(
                  _isSaving ? 'جاري الحفظ...' : 'حفظ مواعيد العمل',
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WorkingDayRow extends StatelessWidget {
  const _WorkingDayRow({
    required this.day,
    required this.onOpenChanged,
    required this.onPickOpen,
    required this.onPickClose,
  });

  final WorkingDaySchedule day;
  final ValueChanged<bool> onOpenChanged;
  final VoidCallback onPickOpen;
  final VoidCallback onPickClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  day.label,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
              Text(
                day.isOpen ? 'مفتوح' : 'مغلق',
                style: TextStyle(
                  color: day.isOpen ? Colors.green.shade700 : Colors.red.shade700,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Switch(
                value: day.isOpen,
                activeThumbColor: const Color(0xFF6B1124),
                onChanged: onOpenChanged,
              ),
            ],
          ),
          if (day.isOpen) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _TimePickerButton(
                    label: 'وقت الفتح',
                    value: formatTimeLabel(day.openTime),
                    onTap: onPickOpen,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _TimePickerButton(
                    label: 'وقت الإغلاق',
                    value: formatTimeLabel(day.closeTime),
                    onTap: onPickClose,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _TimePickerButton extends StatelessWidget {
  const _TimePickerButton({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        alignment: Alignment.centerRight,
      ),
      onPressed: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: Color(0xFF6B1124),
            ),
          ),
        ],
      ),
    );
  }
}
