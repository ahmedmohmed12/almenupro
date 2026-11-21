import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/kitchen_void_liability.dart';
import '../../services/pos_operations_service.dart';

class AdminKitchenVoidLiabilitiesCard extends StatefulWidget {
  const AdminKitchenVoidLiabilitiesCard({
    super.key,
    required this.onOpenReview,
  });

  final VoidCallback onOpenReview;

  static const burgundy = Color(0xFF6B1124);

  @override
  State<AdminKitchenVoidLiabilitiesCard> createState() =>
      _AdminKitchenVoidLiabilitiesCardState();
}

class _AdminKitchenVoidLiabilitiesCardState
    extends State<AdminKitchenVoidLiabilitiesCard> {
  Timer? _timer;
  var _loading = true;
  KitchenVoidLiabilitySummary _summary = const KitchenVoidLiabilitySummary();
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
    _timer = Timer.periodic(const Duration(seconds: 20), (_) => unawaited(_refresh()));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final result =
          await PosOperationsService.instance.fetchKitchenVoidLiabilities(
        status: 'PENDING',
      );
      if (!mounted) return;
      setState(() {
        _summary = result.summary;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final pending = _summary.pendingCount;
    final amount = _summary.pendingAmount;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: pending > 0
              ? AdminKitchenVoidLiabilitiesCard.burgundy.withValues(alpha: 0.35)
              : const Color(0xFFE2E8F0),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.rule_folder_outlined,
                  color: AdminKitchenVoidLiabilitiesCard.burgundy,
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'مسؤوليات إلغاء المطبخ',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                ),
                if (_loading)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else if (pending > 0)
                  Badge(
                    label: Text('$pending'),
                    child: const Icon(Icons.pending_actions_outlined),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              pending > 0
                  ? '$pending طلب بانتظار المراجعة — ${amount.toStringAsFixed(3)} د.ك'
                  : 'لا توجد مسؤوليات معلّقة حالياً.',
              style: const TextStyle(color: Color(0xFF475569), fontSize: 13),
            ),
            if (_error != null) ...[
              const SizedBox(height: 6),
              Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 12)),
            ],
            const SizedBox(height: 6),
            const Text(
              'من هنا توافق على الإعفاء أو تسجّل المديونية على الكاشير عند إغلاق الوردية.',
              style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: widget.onOpenReview,
              icon: const Icon(Icons.open_in_new_rounded),
              label: Text(
                pending > 0 ? 'مراجعة المسؤوليات ($pending)' : 'فتح مراجعة المسؤوليات',
              ),
              style: FilledButton.styleFrom(
                backgroundColor: AdminKitchenVoidLiabilitiesCard.burgundy,
              ),
            ),
          ],
        ),
      ),
    );
  }
}