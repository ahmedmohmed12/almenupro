import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/admin_auth_service.dart';
import '../../services/api_service.dart';
import '../../services/orders_demo_service.dart';
import '../../services/super_admin_scope_service.dart';
import '../../services/whatsapp_broadcast.dart';
import '../../utils/whatsapp_launcher.dart';

/// Admin marketing broadcast. Each client opens in WhatsApp via wa.me.
class AdminWhatsappBroadcastPage extends StatefulWidget {
  const AdminWhatsappBroadcastPage({super.key});

  @override
  State<AdminWhatsappBroadcastPage> createState() =>
      _AdminWhatsappBroadcastPageState();
}

class _AdminWhatsappBroadcastPageState
    extends State<AdminWhatsappBroadcastPage> {
  static const burgundy = Color(0xFF800020);
  static const lightOrange = Color(0xFFFF9F43);
  static const whatsappGreen = Color(0xFF25D366);

  final _controller = WhatsappBroadcastController();
  final _searchController = TextEditingController();
  final _templateController = TextEditingController(
    text: defaultBroadcastTemplate,
  );
  var _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onController);
    _load();
  }

  @override
  void dispose() {
    _controller.removeListener(_onController);
    _controller.dispose();
    _searchController.dispose();
    _templateController.dispose();
    super.dispose();
  }

  void _onController() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final restaurantId = AdminAuthService.instance.isRestaurantAdmin
          ? (AdminAuthService.instance.restaurantId ??
                ApiService.defaultRestaurantId)
          : SuperAdminScopeService.instance.effectiveRestaurantId;
      final customers = await ApiService.instance.fetchCustomers(
        restaurantId: restaurantId,
      );
      final restaurantName =
          AdminAuthService.instance.restaurantName?.trim().isNotEmpty == true
          ? AdminAuthService.instance.restaurantName!.trim()
          : 'AlMenuPro';
      _controller.replaceAudience(
        buildBroadcastAudience(
          customers: customers,
          orders: OrdersDemoService.loadedOrders,
          restaurantName: restaurantName,
        ),
      );
    } catch (error) {
      _error = error.toString().replaceFirst('Exception: ', '');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _startBroadcast() async {
    if (_controller.targets.isEmpty || _controller.isRunning) return;
    _controller.setTemplate(_templateController.text);
    unawaited(_controller.run(_openWhatsApp));
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => _BroadcastProgressDialog(
        controller: _controller,
        onClose: () => Navigator.of(dialogContext).pop(),
      ),
    );
  }

  Future<bool> _openWhatsApp(
    BroadcastRecipient recipient,
    String message,
  ) async {
    final uri = Uri.parse(
      'https://wa.me/${recipient.phone}?text=${Uri.encodeComponent(message)}',
    );
    try {
      final opened = await launchUrl(
        uri,
        mode: kIsWeb
            ? LaunchMode.platformDefault
            : LaunchMode.externalApplication,
        webOnlyWindowName: '_blank',
      );
      if (opened) return true;
    } catch (error) {
      debugPrint('wa.me failed for ${recipient.phone}: $error');
    }
    return openWhatsAppChat(phone: recipient.phone, message: message);
  }

  Future<void> _pickRange({required bool isEnd}) async {
    final now = DateTime.now();
    final current = isEnd ? _controller.rangeTo : _controller.rangeFrom;
    final date = await showDatePicker(
      context: context,
      initialDate: current ?? now,
      firstDate: DateTime(now.year - 3),
      lastDate: DateTime(now.year + 1),
      helpText: isEnd ? 'إلى تاريخ' : 'من تاريخ',
      builder: _datePickerTheme,
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current ?? now),
      helpText: isEnd ? 'إلى وقت' : 'من وقت',
      builder: _datePickerTheme,
    );
    if (!mounted) return;
    final picked = time == null
        ? (isEnd ? broadcastEndOfDay(date) : broadcastStartOfDay(date))
        : DateTime(date.year, date.month, date.day, time.hour, time.minute);
    if (isEnd) {
      _controller.setDateRange(_controller.rangeFrom, picked);
    } else {
      _controller.setDateRange(picked, _controller.rangeTo);
    }
  }

  Widget _datePickerTheme(BuildContext context, Widget? child) {
    return Theme(
      data: Theme.of(context).copyWith(
        colorScheme: const ColorScheme.light(
          primary: burgundy,
          onPrimary: Colors.white,
          secondary: lightOrange,
        ),
      ),
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: child ?? const SizedBox.shrink(),
      ),
    );
  }

  void _insertPlaceholder(String token) {
    final value = _templateController.value;
    final offset = value.selection.baseOffset < 0
        ? value.text.length
        : value.selection.baseOffset;
    final next = insertBroadcastPlaceholder(value.text, offset, token);
    _templateController.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: offset + token.length),
    );
    _controller.setTemplate(next);
  }

  @override
  Widget build(BuildContext context) {
    if (!canUseWhatsappBroadcast) {
      return const Center(child: Text('هذه الصفحة متاحة لمدير المطعم فقط.'));
    }

    return ColoredBox(
      color: const Color(0xFFF8F4F5),
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _Header(
            selected: _controller.audienceCount,
            visible: _controller.visible.length,
          ),
          const SizedBox(height: 16),
          if (_loading)
            const LinearProgressIndicator(color: burgundy)
          else if (_error != null)
            Text(_error!, style: const TextStyle(color: Colors.red))
          else ...[
            _Filters(
              searchController: _searchController,
              platform: _controller.platform,
              onQuery: _controller.setQuery,
              onPlatform: _controller.setPlatform,
              onSelectAll: _controller.selectAllVisible,
              onDeselectAll: _controller.deselectAllVisible,
              onInvert: _controller.invertVisible,
              onRefresh: _load,
            ),
            const SizedBox(height: 12),
            _DateRangeFilter(
              from: _controller.rangeFrom,
              to: _controller.rangeTo,
              activePreset: _controller.activePreset,
              onPickFrom: () => _pickRange(isEnd: false),
              onPickTo: () => _pickRange(isEnd: true),
              onPreset: _controller.applyDatePreset,
              onClear: _controller.clearDateRange,
            ),
            const SizedBox(height: 12),
            _AudienceList(
              recipients: _controller.visible,
              isSelected: _controller.isSelected,
              onToggle: _controller.toggle,
            ),
            const SizedBox(height: 16),
            _TemplateCard(
              controller: _templateController,
              onInsert: _insertPlaceholder,
              onChanged: _controller.setTemplate,
            ),
            const SizedBox(height: 16),
            _ThrottleCard(
              delaySeconds: _controller.delaySeconds,
              onChanged: _controller.setDelay,
              enabled: !_controller.isRunning,
              onSend: _startBroadcast,
              canSend: _controller.targets.isNotEmpty && !_controller.isRunning,
            ),
            const SizedBox(height: 16),
            _LogCard(logs: _controller.logs),
          ],
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.selected, required this.visible});

  final int selected;
  final int visible;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'حملة واتساب',
          style: TextStyle(
            color: _AdminWhatsappBroadcastPageState.burgundy,
            fontSize: 22,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'رسائل تسويقية للعملاء المسجّلين، مع فاصل زمني يمنع الحظر.',
          style: TextStyle(color: Color(0xFF64748B)),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            const _Badge(
              label: 'Admin Panel',
              color: _AdminWhatsappBroadcastPageState.burgundy,
            ),
            _Badge(
              label: '$visible عميل',
              color: _AdminWhatsappBroadcastPageState.lightOrange,
              foreground: const Color(0xFF3F2A12),
            ),
            _Badge(
              label: '$selected محدد للإرسال',
              color: _AdminWhatsappBroadcastPageState.whatsappGreen,
              foreground: const Color(0xFF08301A),
            ),
          ],
        ),
      ],
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({
    required this.label,
    required this.color,
    this.foreground = Colors.white,
  });

  final String label;
  final Color color;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(color: foreground, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _Filters extends StatelessWidget {
  const _Filters({
    required this.searchController,
    required this.platform,
    required this.onQuery,
    required this.onPlatform,
    required this.onSelectAll,
    required this.onDeselectAll,
    required this.onInvert,
    required this.onRefresh,
  });

  final TextEditingController searchController;
  final BroadcastPlatform platform;
  final ValueChanged<String> onQuery;
  final ValueChanged<BroadcastPlatform> onPlatform;
  final VoidCallback onSelectAll;
  final VoidCallback onDeselectAll;
  final VoidCallback onInvert;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: searchController,
              onChanged: onQuery,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'بحث بالاسم أو المطعم أو رقم الهاتف',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final item in BroadcastPlatform.values)
                  ChoiceChip(
                    label: Text(broadcastPlatformLabel(item)),
                    selected: platform == item,
                    selectedColor: _AdminWhatsappBroadcastPageState.lightOrange,
                    onSelected: (_) => onPlatform(item),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton(
                  onPressed: onSelectAll,
                  child: const Text('تحديد الكل'),
                ),
                OutlinedButton(
                  onPressed: onDeselectAll,
                  child: const Text('إلغاء التحديد'),
                ),
                OutlinedButton(
                  onPressed: onInvert,
                  child: const Text('عكس التحديد'),
                ),
                IconButton(
                  tooltip: 'تحديث',
                  onPressed: onRefresh,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DateRangeFilter extends StatelessWidget {
  const _DateRangeFilter({
    required this.from,
    required this.to,
    required this.activePreset,
    required this.onPickFrom,
    required this.onPickTo,
    required this.onPreset,
    required this.onClear,
  });

  final DateTime? from;
  final DateTime? to;
  final BroadcastRangePreset? activePreset;
  final VoidCallback onPickFrom;
  final VoidCallback onPickTo;
  final ValueChanged<BroadcastRangePreset> onPreset;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'نطاق تاريخ ووقت الطلب',
                style: TextStyle(
                  color: _AdminWhatsappBroadcastPageState.burgundy,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'يظهر العميل إذا كان وقت إنشاء أحد طلباته داخل النطاق.',
                style: TextStyle(color: Color(0xFF64748B), fontSize: 12),
              ),
              const SizedBox(height: 12),
              LayoutBuilder(
                builder: (context, constraints) {
                  final stacked = constraints.maxWidth < 700;
                  final fromField = _DateTimeField(
                    label: 'من تاريخ ووقت',
                    value: from,
                    onTap: onPickFrom,
                  );
                  final toField = _DateTimeField(
                    label: 'إلى تاريخ ووقت',
                    value: to,
                    onTap: onPickTo,
                  );
                  if (stacked) {
                    return Column(
                      children: [fromField, const SizedBox(height: 8), toField],
                    );
                  }
                  return Row(
                    children: [
                      Expanded(child: fromField),
                      const SizedBox(width: 12),
                      Expanded(child: toField),
                    ],
                  );
                },
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final preset in BroadcastRangePreset.values)
                    ChoiceChip(
                      label: Text(_presetLabel(preset)),
                      selected: activePreset == preset,
                      selectedColor:
                          _AdminWhatsappBroadcastPageState.lightOrange,
                      onSelected: (_) => onPreset(preset),
                    ),
                  if (from != null || to != null)
                    ActionChip(
                      label: const Text('مسح النطاق'),
                      onPressed: onClear,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _presetLabel(BroadcastRangePreset preset) {
  switch (preset) {
    case BroadcastRangePreset.today:
      return 'اليوم';
    case BroadcastRangePreset.yesterday:
      return 'أمس';
    case BroadcastRangePreset.last7Days:
      return 'آخر 7 أيام';
    case BroadcastRangePreset.thisMonth:
      return 'هذا الشهر';
  }
}

String _formatDateTime(DateTime? value) {
  if (value == null) return 'غير محدد';
  final local = value.toLocal();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${local.year}/${two(local.month)}/${two(local.day)}  ${two(local.hour)}:${two(local.minute)}';
}

class _DateTimeField extends StatelessWidget {
  const _DateTimeField({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final DateTime? value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          suffixIcon: const Icon(
            Icons.event,
            color: _AdminWhatsappBroadcastPageState.burgundy,
          ),
        ),
        child: Text(
          _formatDateTime(value),
          textAlign: TextAlign.right,
          style: TextStyle(
            color: value == null
                ? const Color(0xFF94A3B8)
                : const Color(0xFF1F2937),
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _AudienceList extends StatelessWidget {
  const _AudienceList({
    required this.recipients,
    required this.isSelected,
    required this.onToggle,
  });

  final List<BroadcastRecipient> recipients;
  final bool Function(String id) isSelected;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) {
    final title = Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
      child: Text(
        'العملاء (${recipients.length})',
        style: const TextStyle(
          color: _AdminWhatsappBroadcastPageState.burgundy,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
    if (recipients.isEmpty) {
      return Card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            title,
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: Text('لا يوجد عملاء مطابقون لهذا الفلتر.'),
            ),
          ],
        ),
      );
    }
    return Card(
      child: Column(
        children: [
          title,
          for (final recipient in recipients)
            CheckboxListTile(
              value: isSelected(recipient.id),
              activeColor: _AdminWhatsappBroadcastPageState.burgundy,
              onChanged: (_) => onToggle(recipient.id),
              title: Text(recipient.name),
              subtitle: Text(
                '${recipient.phone} · ${recipient.platformLabel} · ${recipient.restaurantName}',
              ),
            ),
        ],
      ),
    );
  }
}

class _TemplateCard extends StatelessWidget {
  const _TemplateCard({
    required this.controller,
    required this.onInsert,
    required this.onChanged,
  });

  final TextEditingController controller;
  final ValueChanged<String> onInsert;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'نص الرسالة',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final token in broadcastPlaceholders)
                  ChoiceChip(
                    label: Text(token),
                    selected: false,
                    onSelected: (_) => onInsert(token),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: controller,
              minLines: 6,
              maxLines: 10,
              onChanged: onChanged,
              decoration: const InputDecoration(border: OutlineInputBorder()),
            ),
          ],
        ),
      ),
    );
  }
}

class _ThrottleCard extends StatelessWidget {
  const _ThrottleCard({
    required this.delaySeconds,
    required this.onChanged,
    required this.enabled,
    required this.onSend,
    required this.canSend,
  });

  final double delaySeconds;
  final ValueChanged<double> onChanged;
  final bool enabled;
  final VoidCallback onSend;
  final bool canSend;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'الفاصل بين الرسائل: ${delaySeconds.toStringAsFixed(1)} ثانية',
            ),
            Slider(
              min: WhatsappBroadcastController.minDelaySeconds,
              max: WhatsappBroadcastController.maxDelaySeconds,
              divisions: 7,
              activeColor: _AdminWhatsappBroadcastPageState.burgundy,
              value: delaySeconds,
              label: '${delaySeconds.toStringAsFixed(1)}s',
              onChanged: enabled ? onChanged : null,
            ),
            const Text(
              'الحد الأدنى 1.5 ثانية والحد الأعلى 5 ثوانٍ حتى لا تُغلق واتساب الحملة.',
              style: TextStyle(color: Color(0xFF64748B), fontSize: 12),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: _AdminWhatsappBroadcastPageState.whatsappGreen,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed: canSend ? onSend : null,
              icon: const Icon(Icons.send),
              label: const Text('بدء الحملة'),
            ),
          ],
        ),
      ),
    );
  }
}

class _LogCard extends StatelessWidget {
  const _LogCard({required this.logs});

  final List<BroadcastLogEntry> logs;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'سجل التنفيذ (${logs.length})',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            if (logs.isEmpty)
              const Text('لم تُرسل أي رسالة في هذه الجلسة.')
            else
              for (final entry in logs.take(30))
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text('${entry.recipientName} · ${entry.phone}'),
                  subtitle: Text(entry.detail),
                  trailing: Text(_statusLabel(entry.status)),
                ),
          ],
        ),
      ),
    );
  }

  String _statusLabel(BroadcastLogStatus status) {
    switch (status) {
      case BroadcastLogStatus.sent:
        return 'تم';
      case BroadcastLogStatus.failed:
        return 'فشل';
      case BroadcastLogStatus.skipped:
        return 'تخطّي';
    }
  }
}

class _BroadcastProgressDialog extends StatelessWidget {
  const _BroadcastProgressDialog({
    required this.controller,
    required this.onClose,
  });

  final WhatsappBroadcastController controller;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final done =
            controller.runState == BroadcastRunState.done ||
            controller.runState == BroadcastRunState.cancelled;
        final paused = controller.runState == BroadcastRunState.paused;
        final progress = controller.runTotal == 0
            ? 0.0
            : controller.sentCount / controller.runTotal;
        return AlertDialog(
          title: const Text('تنفيذ الحملة'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LinearProgressIndicator(
                value: controller.runState == BroadcastRunState.idle
                    ? null
                    : progress,
                color: _AdminWhatsappBroadcastPageState.whatsappGreen,
              ),
              const SizedBox(height: 12),
              Text(
                controller.runTotal == 0
                    ? 'جارٍ التحضير...'
                    : 'Sending ${controller.sentCount}/${controller.runTotal} to ${controller.currentName.isEmpty ? '...' : controller.currentName}',
              ),
            ],
          ),
          actions: [
            if (!done && paused)
              TextButton(
                onPressed: controller.resume,
                child: const Text('متابعة'),
              ),
            if (!done && !paused)
              TextButton(
                onPressed: controller.pause,
                child: const Text('إيقاف مؤقت'),
              ),
            TextButton(
              onPressed: () {
                if (!done) controller.cancel();
                onClose();
              },
              child: Text(done ? 'إغلاق' : 'إلغاء الحملة'),
            ),
          ],
        );
      },
    );
  }
}
