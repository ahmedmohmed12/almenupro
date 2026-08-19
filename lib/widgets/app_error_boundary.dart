import 'package:flutter/material.dart';

/// Shows a recoverable panel instead of Flutter's blank release ErrorWidget.
class AppErrorBoundary extends StatelessWidget {
  const AppErrorBoundary({
    super.key,
    required this.child,
    this.onRetry,
    this.message = 'تعذر عرض هذا القسم. أعد المحاولة.',
  });

  final Widget child;
  final VoidCallback? onRetry;
  final String message;

  static Widget releaseFallback(FlutterErrorDetails details, {VoidCallback? onRetry}) {
    return Material(
      color: Colors.white,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 40, color: Color(0xFF6B1124)),
              const SizedBox(height: 12),
              const Text(
                'تعذر عرض هذا القسم',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                details.exceptionAsString().replaceFirst('Exception: ', ''),
                textAlign: TextAlign.center,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13, color: Colors.black54),
              ),
              if (onRetry != null) ...[
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: onRetry,
                  child: const Text('إعادة المحاولة'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return child;
  }
}
