import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/order.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import 'admin_corner_toast.dart';

Future<void> showSendRatingReminderSheet(
  BuildContext context, {
  required Order order,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => SendRatingReminderSheet(order: order),
  );
}

class SendRatingReminderSheet extends StatefulWidget {
  const SendRatingReminderSheet({super.key, required this.order});

  final Order order;

  @override
  State<SendRatingReminderSheet> createState() => _SendRatingReminderSheetState();
}

class _SendRatingReminderSheetState extends State<SendRatingReminderSheet> {
  var _loading = true;
  String? _error;
  String? _ratingUrl;
  String? _whatsappUrl;
  var _alreadyRated = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final payload = await ApiService.instance.createOrderRatingLink(widget.order.id);
      if (!mounted) return;
      setState(() {
        _ratingUrl = payload['ratingUrl']?.toString();
        _whatsappUrl = payload['whatsappUrl']?.toString();
        _alreadyRated = payload['alreadyRated'] == true;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  Future<void> _copyLink() async {
    final url = _ratingUrl;
    if (url == null || url.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: url));
    if (!mounted) return;
    AdminCornerToast.success(context, 'تم نسخ رابط التقييم');
  }

  Future<void> _openWhatsApp() async {
    final raw = _whatsappUrl;
    if (raw == null || raw.isEmpty) {
      AdminCornerToast.error(context, 'لا يوجد رقم واتساب للعميل');
      return;
    }
    final uri = Uri.parse(raw);
    final ok = await launchUrl(uri, webOnlyWindowName: '_blank');
    if (!ok && mounted) {
      AdminCornerToast.error(context, 'تعذر فتح واتساب');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        8,
        20,
        20 + MediaQuery.paddingOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'إرسال طلب تقييم',
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 18,
              color: AppTheme.brandMaroon,
            ),
          ),
          const SizedBox(height: 8),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(
                child: CircularProgressIndicator(color: AppTheme.brandMaroon),
              ),
            )
          else if (_error != null)
            Text(_error!, style: const TextStyle(color: Colors.red))
          else ...[
            if (_alreadyRated)
              const Text(
                'هذا الطلب مُقيَّم مسبقاً. يمكنك إعادة إرسال الرابط للعميل.',
                style: TextStyle(height: 1.4),
              )
            else
              const Text(
                'أرسل تذكيراً للعميل عبر واتساب أو انسخ رابط التقييم.',
                style: TextStyle(height: 1.4),
              ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _openWhatsApp,
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFF25D366)),
              icon: const Icon(Icons.chat),
              label: const Text('إرسال عبر WhatsApp'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _copyLink,
              icon: const Icon(Icons.copy),
              label: const Text('نسخ رابط التقييم'),
            ),
          ],
        ],
      ),
    );
  }
}
