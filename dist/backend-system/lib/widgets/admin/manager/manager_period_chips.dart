import 'package:flutter/material.dart';

import '../../../l10n/app_strings.dart';
import '../../../models/manager_report_period.dart';

class ManagerPeriodChips extends StatelessWidget {
  const ManagerPeriodChips({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  final ManagerReportPeriod selected;
  final ValueChanged<ManagerReportPeriod> onSelected;

  static const burgundy = Color(0xFF6B1124);

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final period in ManagerReportPeriod.values)
          ChoiceChip(
            selected: selected == period,
            label: Text(
              s.tr(period.label, switch (period) {
                ManagerReportPeriod.live => 'Live',
                ManagerReportPeriod.lastHour => 'Last hour',
                ManagerReportPeriod.today => 'Today',
                ManagerReportPeriod.yesterday => 'Yesterday',
                ManagerReportPeriod.last7Days => 'Last 7 days',
                ManagerReportPeriod.last30Days => 'Last 30 days',
              }),
            ),
            labelStyle: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 12,
              color: selected == period ? Colors.white : burgundy,
            ),
            selectedColor: burgundy,
            showCheckmark: false,
            backgroundColor: Colors.white,
            side: BorderSide(
              color: selected == period ? burgundy : const Color(0xFFD6D3D1),
            ),
            visualDensity: VisualDensity.compact,
            onSelected: (_) => onSelected(period),
          ),
      ],
    );
  }
}
