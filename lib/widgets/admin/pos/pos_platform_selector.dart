import 'package:flutter/material.dart';

import '../../../models/order_platform.dart';
import '../../../models/sales_platform_config.dart';
import 'pos_theme.dart';

class PosPlatformSelection {
  const PosPlatformSelection({
    required this.platform,
    this.externalOrderId,
    this.trackCommission = false,
    this.commissionPercent,
    this.manualNetRevenue,
  });

  final SalesPlatformConfig platform;
  final String? externalOrderId;
  final bool trackCommission;
  final double? commissionPercent;
  final double? manualNetRevenue;

  bool get isExternal => platform.isExternal;

  PlatformOrderMeta? metaForTotal(double orderTotal) {
    if (!platform.isExternal) return null;
    if (!trackCommission) {
      return PlatformOrderMeta(externalOrderId: externalOrderId);
    }

    if (manualNetRevenue != null && manualNetRevenue! > 0) {
      return PlatformOrderMeta(
        externalOrderId: externalOrderId,
        platformGrossTotal: manualNetRevenue,
      );
    }

    final percent = commissionPercent ?? platform.commissionPercent;
    if (percent <= 0) {
      return PlatformOrderMeta(externalOrderId: externalOrderId);
    }

    final commission = orderTotal * percent / 100;
    return PlatformOrderMeta(
      externalOrderId: externalOrderId,
      platformCommission: commission,
      platformCommissionPercent: percent,
    );
  }

  double? estimatedNet(double orderTotal) =>
      metaForTotal(orderTotal)?.netRevenue(orderTotal);

  double? estimatedCommission(double orderTotal) =>
      metaForTotal(orderTotal)?.platformCommission;
}

class PosPlatformSelector extends StatelessWidget {
  const PosPlatformSelector({
    super.key,
    required this.platforms,
    required this.selection,
    required this.orderTotal,
    required this.onChanged,
    this.externalOrderIdController,
  });

  final List<SalesPlatformConfig> platforms;
  final PosPlatformSelection selection;
  final double orderTotal;
  final ValueChanged<PosPlatformSelection> onChanged;
  final TextEditingController? externalOrderIdController;

  void _update(PosPlatformSelection next) => onChanged(next);

  @override
  Widget build(BuildContext context) {
    final isExternal = selection.isExternal;
    final estimatedNet = selection.estimatedNet(orderTotal);
    final estimatedCommission = selection.estimatedCommission(orderTotal);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(Icons.hub_outlined, size: 18, color: PosTheme.textMuted),
            const SizedBox(width: 6),
            const Text(
              'مصدر الطلب',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            ),
            const Spacer(),
            if (isExternal)
              SalesPlatformBadge(platform: selection.platform, compact: true),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 40,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: platforms.length,
            separatorBuilder: (_, __) => const SizedBox(width: 6),
            itemBuilder: (context, index) {
              final platform = platforms[index];
              final selected = selection.platform.id == platform.id;
              return ChoiceChip(
                visualDensity: VisualDensity.compact,
                avatar: Icon(
                  platform.icon,
                  size: 16,
                  color: selected ? Colors.white : platform.color,
                ),
                label: Text(
                  platform.name,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: selected ? Colors.white : AppThemeCompat.text,
                  ),
                ),
                selected: selected,
                selectedColor: platform.color,
                backgroundColor: platform.color.withValues(alpha: 0.08),
                side: BorderSide(
                  color: selected
                      ? platform.color
                      : platform.color.withValues(alpha: 0.35),
                ),
                onSelected: (_) {
                  _update(
                    PosPlatformSelection(
                      platform: platform,
                      externalOrderId: selection.externalOrderId,
                      trackCommission:
                          platform.isExternal && selection.trackCommission,
                      commissionPercent: platform.isExternal
                          ? (selection.commissionPercent ??
                              platform.commissionPercent)
                          : null,
                      manualNetRevenue: selection.manualNetRevenue,
                    ),
                  );
                },
              );
            },
          ),
        ),
        if (isExternal) ...[
          const SizedBox(height: 10),
          TextFormField(
            controller: externalOrderIdController,
            decoration: InputDecoration(
              labelText: 'رقم الطلب / الهاشتاج على المنصة (اختياري)',
              isDense: true,
              prefixIcon: const Icon(Icons.tag, size: 18),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onChanged: (value) => _update(
              PosPlatformSelection(
                platform: selection.platform,
                externalOrderId: value.trim().isEmpty ? null : value.trim(),
                trackCommission: selection.trackCommission,
                commissionPercent: selection.commissionPercent,
                manualNetRevenue: selection.manualNetRevenue,
              ),
            ),
          ),
          const SizedBox(height: 8),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: const Text(
              'احتساب عمولة المنصة',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              'تطبيق ${selection.platform.commissionPercent.toStringAsFixed(1)}% من الإعدادات',
              style: const TextStyle(fontSize: 11),
            ),
            value: selection.trackCommission,
            activeTrackColor: selection.platform.color.withValues(alpha: 0.45),
            thumbColor: WidgetStateProperty.resolveWith(
              (states) => selection.platform.color,
            ),
            onChanged: (value) => _update(
              PosPlatformSelection(
                platform: selection.platform,
                externalOrderId: selection.externalOrderId,
                trackCommission: value,
                commissionPercent: value
                    ? (selection.commissionPercent ??
                        selection.platform.commissionPercent)
                    : null,
                manualNetRevenue: selection.manualNetRevenue,
              ),
            ),
          ),
          if (selection.trackCommission && estimatedNet != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: PosTheme.card(
                color: selection.platform.color.withValues(alpha: 0.08),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _CommissionRow(
                    label: 'إجمالي الطلب',
                    value: '${orderTotal.toStringAsFixed(3)} د.ك',
                  ),
                  if (estimatedCommission != null && estimatedCommission > 0)
                    _CommissionRow(
                      label:
                          'العمولة (${(selection.commissionPercent ?? selection.platform.commissionPercent).toStringAsFixed(1)}%)',
                      value: '- ${estimatedCommission.toStringAsFixed(3)} د.ك',
                      muted: true,
                    ),
                  _CommissionRow(
                    label: 'صافي المطعم',
                    value: '${estimatedNet.toStringAsFixed(3)} د.ك',
                    bold: true,
                  ),
                ],
              ),
            ),
          ],
        ],
      ],
    );
  }
}

class _CommissionRow extends StatelessWidget {
  const _CommissionRow({
    required this.label,
    required this.value,
    this.bold = false,
    this.muted = false,
  });

  final String label;
  final String value;
  final bool bold;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: muted ? PosTheme.textMuted : null,
                fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: bold ? FontWeight.bold : FontWeight.w600,
              color: muted ? PosTheme.textMuted : PosTheme.accent,
            ),
          ),
        ],
      ),
    );
  }
}

class AppThemeCompat {
  static const text = Color(0xFF1A1A1A);
}
