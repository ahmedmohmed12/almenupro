import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/locale_provider.dart';

class LanguageToggleButton extends StatelessWidget {
  const LanguageToggleButton({
    super.key,
    this.compact = false,
    this.foregroundColor,
  });

  final bool compact;
  final Color? foregroundColor;

  @override
  Widget build(BuildContext context) {
    final locale = context.watch<LocaleProvider>();
    final label = locale.isArabic ? 'EN' : 'ع';
    final tooltip = locale.isArabic ? 'English' : 'العربية';

    if (compact) {
      return IconButton(
        tooltip: tooltip,
        onPressed: locale.toggle,
        color: foregroundColor,
        icon: Text(
          label,
          style: TextStyle(color: foregroundColor, fontWeight: FontWeight.w800),
        ),
      );
    }

    return TextButton.icon(
      onPressed: locale.toggle,
      icon: const Icon(Icons.language),
      label: Text(label),
      style: foregroundColor == null
          ? null
          : TextButton.styleFrom(foregroundColor: foregroundColor),
    );
  }
}
