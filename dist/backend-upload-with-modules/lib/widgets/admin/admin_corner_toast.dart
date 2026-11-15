import 'dart:async';

import 'package:flutter/material.dart';

/// Compact toast anchored to the physical bottom-right corner.
class AdminCornerToast {
  AdminCornerToast._();

  static OverlayEntry? _currentEntry;
  static Timer? _hideTimer;

  static void show(
    BuildContext context,
    String message, {
    Color backgroundColor = const Color(0xFF2C353F),
    Color textColor = Colors.white,
    Duration duration = const Duration(seconds: 2),
    double maxWidth = 200,
  }) {
    _hideTimer?.cancel();
    _currentEntry?.remove();
    _currentEntry = null;

    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;

    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (context) => Positioned(
        right: 16,
        bottom: 16,
        child: Material(
          color: Colors.transparent,
          child: Container(
            constraints: BoxConstraints(maxWidth: maxWidth, minWidth: 120),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: backgroundColor,
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.18),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Text(
              message,
              style: TextStyle(
                color: textColor,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                height: 1.25,
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );

    _currentEntry = entry;
    overlay.insert(entry);

    _hideTimer = Timer(duration, () {
      entry.remove();
      if (_currentEntry == entry) {
        _currentEntry = null;
      }
    });
  }

  static void success(BuildContext context, String message) {
    show(
      context,
      message,
      backgroundColor: const Color(0xFF2E7D32),
    );
  }

  static void error(BuildContext context, String message) {
    show(
      context,
      message,
      backgroundColor: const Color(0xFFC62828),
    );
  }
}
