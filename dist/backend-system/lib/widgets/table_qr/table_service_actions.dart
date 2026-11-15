import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/dining_table.dart';
import '../../services/dining_tables_service.dart';
import '../../services/table_floor_live_service.dart';
import '../../theme/app_theme.dart';

class TableServiceActions extends StatefulWidget {
  const TableServiceActions({
    super.key,
    required this.branchId,
    required this.tableId,
    required this.restaurantId,
    this.onTableChanged,
  });

  final String branchId;
  final String tableId;
  final String restaurantId;
  final ValueChanged<DiningTable>? onTableChanged;

  @override
  State<TableServiceActions> createState() => _TableServiceActionsState();
}

class _TableServiceActionsState extends State<TableServiceActions> {
  var _busy = false;

  Future<void> _run(Future<DiningTable> Function() operation) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final table = await operation();
      widget.onTableChanged?.call(table);
      unawaited(
        TableFloorLiveService.instance.publish(table, widget.restaurantId),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم إرسال الطلب إلى الكاشير'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _requestCheck() async {
    final payment = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'طريقة الدفع',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () => Navigator.pop(context, 'cash'),
                icon: const Icon(Icons.payments_outlined),
                label: const Text('كاش'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => Navigator.pop(context, 'knet'),
                icon: const Icon(Icons.credit_card_rounded),
                label: const Text('K-Net'),
              ),
            ],
          ),
        ),
      ),
    );
    if (payment == null || !mounted) return;
    await _run(
      () => DiningTablesService.instance.requestCheckPublic(
        branchId: widget.branchId,
        tableId: widget.tableId,
        tipAmount: 0,
        paymentMethod: payment,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.branchId.trim().isEmpty || widget.tableId.trim().isEmpty) {
      return const SizedBox.shrink();
    }
    return Material(
      color: Colors.white,
      elevation: 8,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: _busy
          ? const SizedBox(
              width: 108,
              height: 48,
              child: Center(
                child: SizedBox.square(
                  dimension: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
              ),
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _Action(
                  icon: Icons.notifications_active_outlined,
                  label: 'ويتر',
                  onTap: () => _run(
                    () => DiningTablesService.instance.callWaiterPublic(
                      branchId: widget.branchId,
                      tableId: widget.tableId,
                    ),
                  ),
                ),
                Container(width: 1, height: 34, color: const Color(0xFFE5E7EB)),
                _Action(
                  icon: Icons.receipt_long_outlined,
                  label: 'الحساب',
                  onTap: _requestCheck,
                ),
              ],
            ),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: AppTheme.brandMaroon, size: 20),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
    );
  }
}
