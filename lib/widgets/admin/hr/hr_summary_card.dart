import 'package:flutter/material.dart';

import '../../../models/hr_models.dart';
import '../../../services/hr_controller.dart';

const _burgundy = Color(0xFF800020);
const _lightOrange = Color(0xFFFF9F43);
const _darkOrange = Color(0xFFE67E22);

class HrSummaryCard extends StatefulWidget {
  const HrSummaryCard({super.key, this.onOpen});

  final VoidCallback? onOpen;

  @override
  State<HrSummaryCard> createState() => _HrSummaryCardState();
}

class _HrSummaryCardState extends State<HrSummaryCard> {
  final _hr = HrController.instance;

  @override
  void initState() {
    super.initState();
    _hr.addListener(_rebuild);
    if (!_hr.ready) {
      _hr.load();
    }
  }

  @override
  void dispose() {
    _hr.removeListener(_rebuild);
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final critical = _hr.alertCount(DocAlertLevel.critical, now);
    final urgent = _hr.alertCount(DocAlertLevel.urgent, now);
    final warning = _hr.alertCount(DocAlertLevel.warning, now);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: widget.onOpen,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _lightOrange),
            ),
            child: Row(
              children: [
                const Icon(Icons.badge_outlined, color: _burgundy),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'شؤون الموظفين',
                    style: TextStyle(fontWeight: FontWeight.w800, color: _burgundy),
                  ),
                ),
                _Pill(label: '$critical حرج', color: const Color(0xFFB91C1C)),
                const SizedBox(width: 6),
                _Pill(label: '$urgent عاجل', color: _darkOrange),
                const SizedBox(width: 6),
                _Pill(label: '$warning تنبيه', color: const Color(0xFFCA8A04)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 12),
      ),
    );
  }
}
