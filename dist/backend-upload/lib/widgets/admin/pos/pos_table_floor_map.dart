import 'package:flutter/material.dart';

import '../../../l10n/app_strings.dart';
import '../../../models/dining_table.dart';
import 'pos_action_hub.dart';
import 'pos_theme.dart';

class PosTableFloorMap extends StatelessWidget {
  const PosTableFloorMap({
    super.key,
    required this.tables,
    required this.onOpenTable,
    this.onRefresh,
  });

  final List<DiningTable> tables;
  final ValueChanged<DiningTable> onOpenTable;
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final width = MediaQuery.sizeOf(context).width;
    final desktop = width >= PosTheme.desktopMin;
    final tablet =
        width >= PosTheme.mobileBreakpoint && width < PosTheme.desktopMin;
    final mobile = width < PosTheme.mobileBreakpoint;

    final grouped = <String, List<DiningTable>>{};
    for (final table in tables) {
      grouped.putIfAbsent(table.zone, () => []).add(table);
    }

    final waiterCalls = tables.where((table) => table.isWaiterCall).toList();
    final checks = tables.where((table) => table.isAwaitingCheck).toList();

    final floor = RefreshIndicator(
      onRefresh: onRefresh ?? () async {},
      child: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'طاولات الصالة',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'اختر طاولة لفتح الجلسة وتسجيل الطلب.',
                    style: TextStyle(color: Colors.grey.shade700),
                  ),
                  const SizedBox(height: 12),
                  const Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      _StatusLegend(color: PosOpsColors.ready, label: 'متاحة'),
                      _StatusLegend(color: PosOpsColors.busy, label: 'مشغولة'),
                      _StatusLegend(
                        color: PosOpsColors.waiter,
                        label: 'طلب ويتر',
                      ),
                      _StatusLegend(
                        color: PosOpsColors.alert,
                        label: 'طلب حساب',
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (tables.isEmpty)
            const SliverFillRemaining(
              child: Center(
                child: Text('لا توجد طاولات. أضفها من إدارة الطاولات.'),
              ),
            )
          else if (mobile)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              sliver: SliverList.builder(
                itemCount: grouped.length,
                itemBuilder: (context, index) {
                  final entry = grouped.entries.elementAt(index);
                  return _MobileZoneCard(
                    zone: entry.key,
                    tables: entry.value,
                    onOpenTable: onOpenTable,
                  );
                },
              ),
            )
          else
            for (final entry in grouped.entries) ...[
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                sliver: SliverToBoxAdapter(
                  child: Text(
                    entry.key,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                sliver: SliverGrid(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: tablet ? 3 : (width >= 1600 ? 6 : 4),
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 1.1,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => _FloorTableTile(
                      table: entry.value[index],
                      onTap: () => onOpenTable(entry.value[index]),
                    ),
                    childCount: entry.value.length,
                  ),
                ),
              ),
            ],
        ],
      ),
    );

    if (!desktop) return floor;

    return Row(
      children: [
        Expanded(child: floor),
        Material(
          color: Colors.white,
          elevation: 8,
          child: SizedBox(
            width: 280,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text(
                  'تنبيهات الصالة',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                ),
                const SizedBox(height: 12),
                if (waiterCalls.isEmpty && checks.isEmpty)
                  Text(
                    'لا توجد إشارات من الزبائن حالياً.',
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                for (final table in waiterCalls)
                  _AlertTile(
                    table: table,
                    color: PosOpsColors.waiter,
                    label: table.waiterNote.isEmpty
                        ? 'طلب ويتر'
                        : table.waiterNote,
                    onTap: () => onOpenTable(table),
                  ),
                for (final table in checks)
                  _AlertTile(
                    table: table,
                    color: PosOpsColors.alert,
                    label: _billRequestLabel(table, s),
                    onTap: () => onOpenTable(table),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _AlertTile extends StatelessWidget {
  const _AlertTile({
    required this.table,
    required this.color,
    required this.label,
    required this.onTap,
  });

  final DiningTable table;
  final Color color;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: onTap,
        tileColor: Color.lerp(color, Colors.white, 0.86),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text(
          table.displayName,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Text(label),
        leading: CircleAvatar(backgroundColor: color, radius: 8),
      ),
    );
  }
}

class _MobileZoneCard extends StatelessWidget {
  const _MobileZoneCard({
    required this.zone,
    required this.tables,
    required this.onOpenTable,
  });

  final String zone;
  final List<DiningTable> tables;
  final ValueChanged<DiningTable> onOpenTable;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ExpansionTile(
        initiallyExpanded: true,
        title: Text(zone, style: const TextStyle(fontWeight: FontWeight.w800)),
        children: [
          for (final table in tables)
            ListTile(
              onTap: () => onOpenTable(table),
              leading: CircleAvatar(
                backgroundColor: _floorColor(table),
                child: const Icon(
                  Icons.table_restaurant,
                  color: Colors.white,
                  size: 18,
                ),
              ),
              title: Text(table.displayName),
              subtitle: Text(
                [
                  s.isArabic ? table.status.labelAr : table.status.labelEn,
                  if (table.currentOrderNumber.isNotEmpty)
                    s.tr(
                      'طلب #${table.currentOrderNumber}',
                      'Order #${table.currentOrderNumber}',
                    ),
                  if (table.isOccupied && table.elapsedLabel.isNotEmpty)
                    table.elapsedLabelFor(s.isArabic),
                  if (table.isOccupied)
                    '${table.sessionAmount.toStringAsFixed(3)} ${s.currency}',
                  if (table.isAwaitingCheck) _billRequestLabel(table, s),
                ].join(' • '),
              ),
              trailing: const Icon(Icons.chevron_left),
            ),
        ],
      ),
    );
  }
}

class _StatusLegend extends StatelessWidget {
  const _StatusLegend({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
      ],
    );
  }
}

Color _floorColor(DiningTable table) {
  if (table.isAwaitingCheck) return PosOpsColors.alert;
  if (table.isWaiterCall) return PosOpsColors.waiter;
  if (table.isOccupied) return PosOpsColors.busy;
  return PosOpsColors.ready;
}

String _billRequestLabel(DiningTable table, AppStrings s) {
  final payment = table.requestedPaymentMethod == 'knet'
      ? 'Knet'
      : s.tr('كاش', 'Cash');
  return s.tr(
    'طلب حساب • ${table.requestedBillTotal.toStringAsFixed(3)} ${s.currency} • $payment',
    'Bill request • ${table.requestedBillTotal.toStringAsFixed(3)} ${s.currency} • $payment',
  );
}

class _FloorTableTile extends StatefulWidget {
  const _FloorTableTile({required this.table, required this.onTap});

  final DiningTable table;
  final VoidCallback onTap;

  @override
  State<_FloorTableTile> createState() => _FloorTableTileState();
}

class _FloorTableTileState extends State<_FloorTableTile>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    if (widget.table.isAwaitingCheck) _pulse.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant _FloorTableTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.table.isAwaitingCheck) {
      if (!_pulse.isAnimating) _pulse.repeat(reverse: true);
    } else {
      _pulse.stop();
      _pulse.value = 0;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final table = widget.table;
    final color = _floorColor(table);
    final s = AppStrings.of(context);
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, child) {
        final glow = table.isAwaitingCheck ? _pulse.value : 0.0;
        return Material(
          color: Color.lerp(color, Colors.white, 0.12 + glow * 0.2) ?? color,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: widget.onTap,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: color, width: 3),
              ),
              padding: const EdgeInsets.all(12),
              child: child,
            ),
          ),
        );
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            table.displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 16,
              color: Colors.white,
            ),
          ),
          Text(
            '${table.capacity} مقاعد',
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
          const Spacer(),
          if (table.isOccupied) ...[
            if (table.currentOrderNumber.isNotEmpty)
              Text(
                s.tr(
                  'رقم الطلب: #${table.currentOrderNumber}',
                  'Order: #${table.currentOrderNumber}',
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
              ),
            Text(
              s.tr(
                '${table.sessionItemCount} أصناف • ${table.elapsedLabelFor(true)}',
                '${table.sessionItemCount} items • ${table.elapsedLabelFor(false)}',
              ),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
            Text(
              s.tr(
                'المبلغ الحالي: ${table.sessionAmount.toStringAsFixed(3)} ${s.currency}',
                'Current amount: ${table.sessionAmount.toStringAsFixed(3)} ${s.currency}',
              ),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
            ),
            if (table.isAwaitingCheck)
              Text(
                _billRequestLabel(table, s),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 11,
                ),
              ),
            const SizedBox(height: 3),
          ],
          Text(
            s.isArabic ? table.status.labelAr : table.status.labelEn,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
