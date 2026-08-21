import 'package:flutter/material.dart';

import '../pos/pos_printer_settings_dialog.dart';

class AdminPrinterSettingsCard extends StatelessWidget {
  const AdminPrinterSettingsCard({super.key});

  @override
  Widget build(BuildContext context) {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(20),
        child: PosPrinterSettingsForm(),
      ),
    );
  }
}
