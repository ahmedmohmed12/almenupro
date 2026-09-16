import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../models/order_platform.dart';
import '../../../models/sales_platform_config.dart';
import 'pos_theme.dart';
import 'pos_ui_components.dart';

class PosPlatformSelection {
  const PosPlatformSelection({
    required this.platform,
    this.externalOrderId,
    this.deliveryFee = 0,
    this.trackCommission = false,
    this.commissionPercent,
    this.manualNetRevenue,
  });

  final SalesPlatformConfig platform;
  final String? externalOrderId;
  /// Platform delivery fee entered by cashier (KWD).
  final double deliveryFee;
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
    this.deliveryFeeController,
    this.showSourceToggle = true,
    this.compactHeader = false,
  });

  final List<SalesPlatformConfig> platforms;
  final PosPlatformSelection selection;
  final double orderTotal;
  final ValueChanged<PosPlatformSelection> onChanged;
  final TextEditingController? externalOrderIdController;
  final TextEditingController? deliveryFeeController;
  final bool showSourceToggle;
  final bool compactHeader;

  SalesPlatformConfig get _localPlatform => platforms.firstWhere(
        (p) => p.isLocal,
        orElse: () => SalesPlatformConfig.defaults().first,
      );

  List<SalesPlatformConfig> get _externalPlatforms =>
      platforms.where((p) => p.isExternal).toList(growable: false);

  void _update(PosPlatformSelection next) => onChanged(next);

  static const Object _unset = Object();

  PosPlatformSelection _copySelection({
    SalesPlatformConfig? platform,
    Object? externalOrderId = _unset,
    double? deliveryFee,
    bool? trackCommission,
    Object? commissionPercent = _unset,
    Object? manualNetRevenue = _unset,
  }) {
    return PosPlatformSelection(
      platform: platform ?? selection.platform,
      externalOrderId: identical(externalOrderId, _unset)
          ? selection.externalOrderId
          : externalOrderId as String?,
      deliveryFee: deliveryFee ?? selection.deliveryFee,
      trackCommission: trackCommission ?? selection.trackCommission,
      commissionPercent: identical(commissionPercent, _unset)
          ? selection.commissionPercent
          : commissionPercent as double?,
      manualNetRevenue: identical(manualNetRevenue, _unset)
          ? selection.manualNetRevenue
          : manualNetRevenue as double?,
    );
  }

  void _selectLocal() {
    deliveryFeeController?.clear();
    _update(
      PosPlatformSelection(
        platform: _localPlatform,
        externalOrderId: selection.externalOrderId,
      ),
    );
  }

  void _onDeliveryFeeChanged(String value) {
    final parsed = double.tryParse(value.trim()) ?? 0;
    _update(_copySelection(deliveryFee: parsed < 0 ? 0 : parsed));
  }

  Future<void> _openPlatformPicker(BuildContext context) async {
    final externals = _externalPlatforms;
    if (externals.isEmpty) return;

    final picked = await showDialog<SalesPlatformConfig>(
      context: context,
      builder: (dialogContext) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 18,
            vertical: 24,
          ),
          child: SizedBox(
            width: 440,
            height: MediaQuery.sizeOf(dialogContext).height * 0.62,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 4, 8),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'منصات التوصيل',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(dialogContext),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
                    itemCount: externals.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final platform = externals[index];
                      final selected = selection.platform.id == platform.id;
                      return Material(
                        color: selected
                            ? platform.color.withValues(alpha: 0.1)
                            : PosTheme.surfaceAlt,
                        borderRadius: BorderRadius.circular(14),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: () => Navigator.pop(dialogContext, platform),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: selected
                                    ? platform.color
                                    : platform.color.withValues(alpha: 0.28),
                                width: selected ? 1.5 : 1,
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: platform.color.withValues(
                                      alpha: 0.14,
                                    ),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Icon(
                                    platform.icon,
                                    color: platform.color,
                                    size: 20,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        platform.name,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 15,
                                        ),
                                      ),
                                      if (platform.commissionPercent > 0)
                                        Text(
                                          'عمولة ${platform.commissionPercent.toStringAsFixed(1)}%',
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: PosTheme.textMuted,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                if (selected)
                                  Icon(
                                    Icons.check_circle,
                                    color: platform.color,
                                  )
                                else
                                  Icon(
                                    Icons.chevron_left,
                                    color: platform.color.withValues(
                                      alpha: 0.7,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (picked == null) return;
    _update(
      _copySelection(
        platform: picked,
        commissionPercent:
            selection.commissionPercent ?? picked.commissionPercent,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isExternal = selection.isExternal;
    final estimatedNet = selection.estimatedNet(orderTotal);
    final estimatedCommission = selection.estimatedCommission(orderTotal);
    final selected = selection.platform;
    final hasExternal = _externalPlatforms.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showSourceToggle) ...[
          const Text(
            'مصدر الطلب',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              PosStyleChip(
                label: 'محلي',
                icon: Icons.storefront,
                color: const Color(0xFF6B1124),
                selected: !isExternal,
                onSelected: _selectLocal,
              ),
              if (hasExternal)
                PosStyleChip(
                  label: 'منصات التوصيل',
                  icon: Icons.delivery_dining,
                  color: isExternal ? selected.color : const Color(0xFF0EA5E9),
                  selected: isExternal,
                  onSelected: () => _openPlatformPicker(context),
                ),
            ],
          ),
        ],
        if (isExternal) ...[
          if (showSourceToggle) const SizedBox(height: 8),
          Material(
            color: selected.color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => _openPlatformPicker(context),
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: compactHeader ? 12 : 10,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: selected.color.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(selected.icon, color: selected.color, size: 20),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            selected.name,
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              color: selected.color,
                              fontSize: compactHeader ? 15 : 14,
                            ),
                          ),
                          Text(
                            selected.commissionPercent > 0
                                ? 'عمولة ${selected.commissionPercent.toStringAsFixed(1)}% — اضغط لتغيير المنصة'
                                : 'اضغط لتغيير المنصة',
                            style: const TextStyle(
                              fontSize: 11.5,
                              color: Color(0xFF475569),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.edit_outlined, size: 18, color: selected.color),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 80),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 6,
                  child: TextFormField(
                    controller: externalOrderIdController,
                    decoration: InputDecoration(
                      labelText: 'رقم الطلب / الهاشتاج',
                      isDense: true,
                      filled: true,
                      fillColor: PosTheme.surfaceAlt,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 10,
                      ),
                      prefixIcon: Icon(Icons.tag, size: 18, color: selected.color),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onChanged: (value) => _update(
                      _copySelection(
                        externalOrderId:
                            value.trim().isEmpty ? null : value.trim(),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 4,
                  child: TextFormField(
                    controller: deliveryFeeController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                        RegExp(r'^\d*\.?\d{0,3}'),
                      ),
                    ],
                    decoration: InputDecoration(
                      labelText: 'رسوم التوصيل',
                      hintText: '0.000',
                      isDense: true,
                      filled: true,
                      fillColor: PosTheme.surfaceAlt,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 10,
                      ),
                      suffixText: 'د.ك',
                      prefixIcon: Icon(
                        Icons.local_shipping_outlined,
                        size: 18,
                        color: selected.color,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onChanged: _onDeliveryFeeChanged,
                  ),
                ),
              ],
            ),
          ),
          if (!compactHeader) ...[
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text(
                'احتساب عمولة المنصة',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                '${selection.platform.commissionPercent.toStringAsFixed(1)}% من الإعدادات',
                style: const TextStyle(fontSize: 11),
              ),
              value: selection.trackCommission,
              activeTrackColor: selected.color.withValues(alpha: 0.45),
              thumbColor: WidgetStateProperty.resolveWith(
                (states) => selected.color,
              ),
              onChanged: (value) => _update(
                _copySelection(
                  trackCommission: value,
                  commissionPercent: value
                      ? (selection.commissionPercent ??
                          selection.platform.commissionPercent)
                      : null,
                ),
              ),
            ),
            if (selection.trackCommission && estimatedNet != null)
              Container(
                padding: const EdgeInsets.all(10),
                decoration: PosTheme.card(
                  color: selected.color.withValues(alpha: 0.08),
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
