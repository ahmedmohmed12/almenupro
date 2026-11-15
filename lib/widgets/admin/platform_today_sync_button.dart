import 'package:flutter/material.dart';

import '../../services/orders_service.dart';
import '../../services/platform_directory_refresh.dart';
import '../../services/platform_today_sync.dart';
import 'admin_corner_toast.dart';

class PlatformTodaySyncButton extends StatefulWidget {
  const PlatformTodaySyncButton({super.key});

  @override
  State<PlatformTodaySyncButton> createState() => _PlatformTodaySyncButtonState();
}

class _PlatformTodaySyncButtonState extends State<PlatformTodaySyncButton> {
  static const burgundy = Color(0xFF6B1124);
  var _syncing = false;

  Future<void> _sync() async {
    if (_syncing) return;
    setState(() => _syncing = true);
    var lastToast = '';
    String platformName(String provider) {
      return switch (provider) {
        'keeta' => 'كيتا',
        'talabat' => 'طلبات',
        'jahez' => 'جاهز',
        _ => provider,
      };
    }

    final stopProgress = listenPlatformSyncProgress((checked, synced) {
      if (!mounted) return;
      final message = 'تم فحص $checked طلب.. جلب $synced طلبات جديدة...';
      if (message == lastToast) return;
      lastToast = message;
      AdminCornerToast.show(
        context,
        message,
        backgroundColor: burgundy,
        maxWidth: 420,
        duration: const Duration(seconds: 4),
      );
    });
    String failureMessage(PlatformSyncDetail detail) {
      final name = platformName(detail.provider);
      final orderId = detail.orderId.replaceFirst(RegExp(r'^#'), '');
      if (detail.alert == 'invoice_network') {
        return 'خطأ شبكة/اتصال أثناء جلب تفاصيل الفاتورة رقم #${orderId.isEmpty ? '—' : orderId}';
      }
      if (detail.alert == 'table_missing') {
        return 'خطأ في مزامنة $name: يتعذر العثور على جدول الطلبات (تأكد من فتح صفحة Order History)';
      }
      if (detail.alert == 'no_order_ids' || (detail.unread && detail.checked == 0)) {
        return 'فشل السحب: لم يتم العثور على أي رقم طلب داخل الصفحة';
      }
      return '$name: متعذر القراءة (يرجى فتح صفحة الطلبات السابقة)';
    }

    Future<void> showPlatform(PlatformSyncDetail detail) async {
      await OrdersService.instance.refreshOrders();
      PlatformDirectoryRefresh.notify();
      if (!mounted || detail.provider.isEmpty) return;
      final name = platformName(detail.provider);
      final failed = detail.unread || detail.alert.isNotEmpty;
      final message = switch (detail.provider) {
        'talabat' => failed
            ? 'طلبات: تعذر استخراج أرقام الطلبات من الجدول (تحقق من صفحة الطلبات السابقة)'
            : 'طلبات: تم جلب ${detail.synced} طلبات جديدة، وحذف ${detail.purged} طلبات زائدة',
        'keeta' => failed
            ? 'كيتا: تعذر استخراج أرقام الطلبات (تحقق من صفحة الطلبات السابقة)'
            : 'كيتا: تم جلب ${detail.synced} طلبات جديدة، وحذف ${detail.purged} طلبات زائدة وتحديث العملاء',
        _ => failed
            ? failureMessage(detail)
            : '$name: تمت المزامنة بنجاح (سحب ${detail.synced} طلبات جديدة، حذف ${detail.purged} زائدة)',
      };
      AdminCornerToast.show(
        context,
        message,
        backgroundColor: failed ? Colors.red.shade800 : const Color(0xFF166534),
        maxWidth: 560,
        duration: const Duration(seconds: 8),
      );
    }

    final stopPlatform = listenPlatformSyncResult(showPlatform);
    final stopAlert = listenPlatformSyncAlert(showPlatform);
    AdminCornerToast.show(
      context,
      'جاري إعادة جلب ومزامنة طلبات اليوم لكافة المنصات...',
      backgroundColor: burgundy,
      maxWidth: 420,
      duration: const Duration(seconds: 8),
    );
    try {
      final report = await syncTodayPlatformSales();
      await OrdersService.instance.refreshOrders();
      PlatformDirectoryRefresh.notify();
      if (!mounted) return;
      if (!report.available) {
        AdminCornerToast.show(
          context,
          'المزامنة تعمل من برنامج سطح المكتب بعد فتح صفحات المنصات.',
          backgroundColor: Colors.orange.shade800,
          maxWidth: 420,
          duration: const Duration(seconds: 4),
        );
      }
    } catch (error) {
      if (!mounted) return;
      AdminCornerToast.show(
        context,
        'تعذرت مزامنة طلبات اليوم',
        backgroundColor: Colors.red.shade800,
        maxWidth: 420,
      );
    } finally {
      stopProgress();
      stopPlatform();
      stopAlert();
      if (mounted) setState(() => _syncing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: _syncing ? null : _sync,
      style: FilledButton.styleFrom(
        backgroundColor: burgundy,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
      icon: _syncing
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : const Icon(Icons.sync, size: 18),
      label: Text(_syncing ? 'جاري المزامنة...' : 'مزامنة مبيعات اليوم لكل المنصات'),
    );
  }
}
