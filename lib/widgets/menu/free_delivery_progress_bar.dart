import 'package:flutter/material.dart';

import '../../l10n/app_strings.dart';
import '../../theme/app_theme.dart';

class FreeDeliveryProgressBar extends StatelessWidget {
  const FreeDeliveryProgressBar({
    super.key,
    required this.subtotal,
    required this.threshold,
    required this.baseDeliveryFee,
    required this.strings,
  });

  final double subtotal;
  final double threshold;
  final double baseDeliveryFee;
  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    if (threshold <= 0 || baseDeliveryFee <= 0) {
      return const SizedBox.shrink();
    }

    final reached = subtotal >= threshold;
    final progress = (subtotal / threshold).clamp(0.0, 1.0);
    final remaining = (threshold - subtotal).clamp(0.0, double.infinity);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: reached
              ? [
                  Colors.green.shade50,
                  Colors.green.shade100.withValues(alpha: 0.5),
                ]
              : [
                  AppTheme.brandOrange.withValues(alpha: 0.08),
                  AppTheme.brandMaroon.withValues(alpha: 0.06),
                ],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: reached
              ? Colors.green.shade300
              : AppTheme.brandOrange.withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                reached ? Icons.check_circle : Icons.local_shipping_outlined,
                color: reached ? Colors.green.shade700 : AppTheme.brandMaroon,
                size: 22,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  reached
                      ? strings.freeDeliveryUnlocked
                      : strings.freeDeliveryRemaining(remaining.toStringAsFixed(3)),
                  style: TextStyle(
                    color: reached ? Colors.green.shade900 : AppTheme.brandMaroon,
                    fontWeight: FontWeight.w700,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: progress),
              duration: const Duration(milliseconds: 450),
              curve: Curves.easeOutCubic,
              builder: (context, value, _) {
                return LinearProgressIndicator(
                  value: value,
                  minHeight: 8,
                  backgroundColor: Colors.white.withValues(alpha: 0.8),
                  color: reached ? Colors.green.shade600 : AppTheme.brandOrange,
                );
              },
            ),
          ),
          const SizedBox(height: 6),
          Text(
            strings.freeDeliveryProgressHint(
              subtotal.toStringAsFixed(3),
              threshold.toStringAsFixed(3),
            ),
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade700,
            ),
          ),
        ],
      ),
    );
  }
}
