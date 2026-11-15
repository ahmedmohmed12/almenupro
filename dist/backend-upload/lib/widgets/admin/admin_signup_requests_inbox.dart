import 'package:flutter/material.dart';

import '../../models/signup_request.dart';
import '../../services/api_service.dart';
import '../../utils/signup_browser_mail.dart';
import 'admin_corner_toast.dart';

class AdminSignupRequestsInbox extends StatefulWidget {
  const AdminSignupRequestsInbox({
    super.key,
    this.onUseForRestaurant,
  });

  final void Function(SignupRequest request)? onUseForRestaurant;

  @override
  State<AdminSignupRequestsInbox> createState() =>
      _AdminSignupRequestsInboxState();
}

class _AdminSignupRequestsInboxState extends State<AdminSignupRequestsInbox> {
  static const burgundy = Color(0xFF6B1124);

  final _emailController = TextEditingController();
  List<SignupRequest> _requests = [];
  var _pendingCount = 0;
  var _loading = true;
  var _savingEmail = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final email = await ApiService.instance.fetchSignupNotificationEmail();
      final result = await ApiService.instance.fetchSignupRequests();
      if (!mounted) return;
      setState(() {
        _emailController.text = email;
        _requests = result.requests;
        _pendingCount = result.pendingCount;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _saveEmail() async {
    final email = _emailController.text.trim();
    if (email.isNotEmpty && !email.contains('@')) {
      AdminCornerToast.error(context, 'أدخل بريداً إلكترونياً صالحاً');
      return;
    }
    setState(() => _savingEmail = true);
    try {
      final saved = await ApiService.instance.saveSignupNotificationEmail(email);
      if (!mounted) return;
      _emailController.text = saved;
      AdminCornerToast.success(
        context,
        email.isEmpty
            ? 'تم تعطيل إيميل طلبات الاشتراك'
            : 'سيتم إرسال إشعار الطلبات إلى $saved',
      );
    } catch (_) {
      if (!mounted) return;
      AdminCornerToast.error(context, 'تعذر حفظ بريد الإشعارات');
    } finally {
      if (mounted) setState(() => _savingEmail = false);
    }
  }

  Future<void> _resendEmail(SignupRequest request) async {
    final to = _emailController.text.trim();
    if (to.isEmpty || !to.contains('@')) {
      AdminCornerToast.error(context, 'أضف بريد الإشعارات أولاً ثم احفظه');
      return;
    }
    try {
      final browserSent = await sendSignupBrowserMail(to: to, request: request);
      if (browserSent) {
        await ApiService.instance.markSignupEmailSent(request.id);
        if (!mounted) return;
        AdminCornerToast.success(
          context,
          'تم إرسال الإيميل. إن كانت أول مرة، افتح البريد واضغط رابط التفعيل ثم أعد الإرسال.',
        );
        await _load();
        return;
      }
      final updated =
          await ApiService.instance.resendSignupRequestEmail(request.id);
      if (!mounted) return;
      if (updated.emailSent) {
        AdminCornerToast.success(context, 'تم إرسال الإيميل');
      } else {
        AdminCornerToast.error(
          context,
          updated.emailError.isNotEmpty
              ? updated.emailError
              : 'تعذر إرسال الإيميل. تحقق من البريد أو مجلد الرسائل غير المرغوبة.',
        );
      }
      await _load();
    } catch (_) {
      if (!mounted) return;
      AdminCornerToast.error(context, 'تعذر إعادة إرسال الإيميل');
    }
  }

  Future<void> _setStatus(SignupRequest request, String status) async {
    try {
      await ApiService.instance.updateSignupRequestStatus(
        id: request.id,
        status: status,
      );
      await _load();
    } catch (_) {
      if (!mounted) return;
      AdminCornerToast.error(context, 'تعذر تحديث حالة الطلب');
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'إشعار الإيميل عند طلب اشتراك جديد',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: burgundy,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'أضف بريد الإشعارات ثم اضغط «إعادة إرسال الإيميل». أول رسالة قد تكون رابط تفعيل — افتح البريد (أو Spam) واضغط التأكيد مرة واحدة.',
                  style: TextStyle(color: Color(0xFF666666), height: 1.4),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _emailController,
                  enabled: !_savingEmail,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'بريد إشعارات الاشتراك',
                    hintText: 'you@almenupro.com',
                    prefixIcon: Icon(Icons.alternate_email),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: FilledButton.icon(
                    onPressed: _savingEmail ? null : _saveEmail,
                    style: FilledButton.styleFrom(
                      backgroundColor: burgundy,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 22,
                        vertical: 14,
                      ),
                    ),
                    icon: _savingEmail
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.add),
                    label: const Text('إضافة الإيميل'),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (_pendingCount > 0)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              '$_pendingCount طلب جديد بانتظار المراجعة',
              style: const TextStyle(
                color: burgundy,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        if (_loading)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator(color: burgundy)),
          )
        else if (_error != null)
          Text(_error!)
        else if (_requests.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text('لا توجد طلبات اشتراك حتى الآن.'),
            ),
          )
        else
          ..._requests.map(_buildTile),
      ],
    );
  }

  Widget _buildTile(SignupRequest request) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      color: request.isNew ? const Color(0xFFFFF8E8) : null,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    request.restaurantName,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: burgundy,
                    ),
                  ),
                ),
                _chip(request.statusLabelAr),
                const SizedBox(width: 6),
                if (request.emailSent)
                  _chip('تم الإيميل', const Color(0xFF2E7D32))
                else
                  _chip('لم يُرسل الإيميل', const Color(0xFFC62828)),
              ],
            ),
            const SizedBox(height: 8),
            Text('الاسم: ${request.ownerName}'),
            Text('البريد: ${request.email}'),
            Text('الموبايل: ${request.phone}'),
            Text('الدليل: ${request.slug}'),
            if (request.instagram.isNotEmpty)
              Text('إنستغرام: @${request.instagram}'),
            if (request.createdAt != null)
              Text(
                'التاريخ: ${request.createdAt!.toLocal()}',
                style: const TextStyle(fontSize: 12, color: Color(0xFF888888)),
              ),
            if (!request.emailSent && request.emailError.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  request.emailError,
                  style: const TextStyle(color: Color(0xFFC62828), fontSize: 13),
                ),
              ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (!request.emailSent)
                  OutlinedButton.icon(
                    onPressed: () => _resendEmail(request),
                    icon: const Icon(Icons.outgoing_mail, size: 18),
                    label: const Text('إعادة إرسال الإيميل'),
                  )
                else
                  OutlinedButton.icon(
                    onPressed: () => _resendEmail(request),
                    icon: const Icon(Icons.outgoing_mail, size: 18),
                    label: const Text('إرسال الإيميل مرة أخرى'),
                  ),
                if (widget.onUseForRestaurant != null)
                  FilledButton.icon(
                    onPressed: () {
                      widget.onUseForRestaurant!(request);
                      if (request.isNew) {
                        _setStatus(request, 'read');
                      }
                    },
                    icon: const Icon(Icons.add_business, size: 18),
                    label: const Text('إنشاء مطعم من الطلب'),
                  ),
                if (request.isNew)
                  OutlinedButton(
                    onPressed: () => _setStatus(request, 'read'),
                    child: const Text('تعليم كمقروء'),
                  ),
                OutlinedButton(
                  onPressed: () => _setStatus(request, 'accepted'),
                  child: const Text('قبول'),
                ),
                OutlinedButton(
                  onPressed: () => _setStatus(request, 'rejected'),
                  child: const Text('رفض'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(String label, [Color color = burgundy]) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w700),
      ),
    );
  }
}
