import 'package:flutter/material.dart';

/// Weekday uses [DateTime] constants (Saturday = 6 … Friday = 5).
class WorkingDaySchedule {
  const WorkingDaySchedule({
    required this.weekday,
    required this.label,
    this.isOpen = true,
    this.openTime = const TimeOfDay(hour: 10, minute: 0),
    this.closeTime = const TimeOfDay(hour: 22, minute: 0),
  });

  final int weekday;
  final String label;
  final bool isOpen;
  final TimeOfDay openTime;
  final TimeOfDay closeTime;

  static const orderedWeekdays = [
    DateTime.saturday,
    DateTime.sunday,
    DateTime.monday,
    DateTime.tuesday,
    DateTime.wednesday,
    DateTime.thursday,
    DateTime.friday,
  ];

  static const weekdayLabels = {
    DateTime.saturday: 'السبت',
    DateTime.sunday: 'الأحد',
    DateTime.monday: 'الاثنين',
    DateTime.tuesday: 'الثلاثاء',
    DateTime.wednesday: 'الأربعاء',
    DateTime.thursday: 'الخميس',
    DateTime.friday: 'الجمعة',
  };

  static List<WorkingDaySchedule> defaultWeek() {
    return orderedWeekdays
        .map(
          (weekday) => WorkingDaySchedule(
            weekday: weekday,
            label: weekdayLabels[weekday] ?? '',
            closeTime: weekday == DateTime.friday
                ? const TimeOfDay(hour: 23, minute: 0)
                : const TimeOfDay(hour: 22, minute: 0),
          ),
        )
        .toList();
  }

  factory WorkingDaySchedule.fromJson(Map<String, dynamic> json) {
    final weekday = (json['weekday'] as num?)?.toInt() ?? DateTime.saturday;
    return WorkingDaySchedule(
      weekday: weekday,
      label: weekdayLabels[weekday] ?? '',
      isOpen: json['isOpen'] as bool? ?? json['is_open'] as bool? ?? true,
      openTime: parseTimeString(
        json['open']?.toString() ?? json['openTime']?.toString() ?? '10:00',
      ),
      closeTime: parseTimeString(
        json['close']?.toString() ?? json['closeTime']?.toString() ?? '22:00',
      ),
    );
  }

  WorkingDaySchedule copyWith({
    bool? isOpen,
    TimeOfDay? openTime,
    TimeOfDay? closeTime,
  }) {
    return WorkingDaySchedule(
      weekday: weekday,
      label: label,
      isOpen: isOpen ?? this.isOpen,
      openTime: openTime ?? this.openTime,
      closeTime: closeTime ?? this.closeTime,
    );
  }

  Map<String, dynamic> toJson() => {
        'weekday': weekday,
        'isOpen': isOpen,
        'open': formatTimeString(openTime),
        'close': formatTimeString(closeTime),
      };
}

class WorkingHoursSettings {
  const WorkingHoursSettings({required this.days});

  final List<WorkingDaySchedule> days;

  factory WorkingHoursSettings.defaults() =>
      WorkingHoursSettings(days: WorkingDaySchedule.defaultWeek());

  factory WorkingHoursSettings.fromJsonList(List<dynamic>? raw) {
    if (raw == null || raw.isEmpty) {
      return WorkingHoursSettings.defaults();
    }

    final parsed = raw
        .whereType<Map>()
        .map((item) => WorkingDaySchedule.fromJson(Map<String, dynamic>.from(item)))
        .toList();

    if (parsed.isEmpty) {
      return WorkingHoursSettings.defaults();
    }

    final byWeekday = {for (final day in parsed) day.weekday: day};
    final merged = WorkingDaySchedule.orderedWeekdays
        .map((weekday) => byWeekday[weekday] ?? WorkingDaySchedule(weekday: weekday, label: WorkingDaySchedule.weekdayLabels[weekday] ?? ''))
        .toList();

    return WorkingHoursSettings(days: merged);
  }

  List<Map<String, dynamic>> toJsonList() =>
      days.map((day) => day.toJson()).toList();
}

String formatTimeString(TimeOfDay time) {
  final hour = time.hour.toString().padLeft(2, '0');
  final minute = time.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

TimeOfDay parseTimeString(String value) {
  final parts = value.split(':');
  if (parts.length < 2) {
    return const TimeOfDay(hour: 10, minute: 0);
  }
  final hour = int.tryParse(parts[0]) ?? 10;
  final minute = int.tryParse(parts[1]) ?? 0;
  return TimeOfDay(hour: hour.clamp(0, 23), minute: minute.clamp(0, 59));
}

String formatTimeLabel(TimeOfDay time) {
  final hour = time.hourOfPeriod == 0 ? 12 : time.hourOfPeriod;
  final minute = time.minute.toString().padLeft(2, '0');
  final suffix = time.period == DayPeriod.am ? 'ص' : 'م';
  return '$hour:$minute $suffix';
}
