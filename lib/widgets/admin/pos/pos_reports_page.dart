import 'package:flutter/material.dart';

import '../admin_shift_reports_card.dart';

class PosReportsPage extends StatelessWidget {
  const PosReportsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const SingleChildScrollView(
      padding: EdgeInsets.all(16),
      child: AdminShiftReportsCard(),
    );
  }
}
