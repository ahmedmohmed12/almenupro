import 'package:flutter/material.dart';

const kOfferUsageLimitMessage = 'لقد وصلت للحد الأقصى لاستخدام هذا العرض';

Future<void> showOfferUsageLimitAlert(
  BuildContext context, [
  String? message,
]) {
  final text = (message ?? '').trim().isEmpty
      ? kOfferUsageLimitMessage
      : message!.trim();
  return showDialog<void>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: const Text('تنبيه'),
        content: Text(text),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('حسناً'),
          ),
        ],
      );
    },
  );
}
