import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/admin_auth_service.dart';
import '../../services/orders_demo_service.dart';
import '../../services/smart_whatsapp_hub.dart';
import '../../services/super_admin_scope_service.dart';
import '../../services/whatsapp_broadcast.dart';
import '../../utils/whatsapp_launcher.dart';
import 'admin_whatsapp_broadcast_page.dart';

/// Four-stage WhatsApp desk: edit the message, then open one customer at a time.
class SmartWhatsappHubPage extends StatefulWidget {
  const SmartWhatsappHubPage({super.key});

  @override
  State<SmartWhatsappHubPage> createState() => _SmartWhatsappHubPageState();
}

class _SmartWhatsappHubPageState extends State<SmartWhatsappHubPage> {
  static const burgundy = Color(0xFF800020);
  static const lightOrange = Color(0xFFFF9F43);
  static const whatsappGreen = Color(0xFF25D366);

  final _hub = SmartWhatsappHubController();
  final _discount = TextEditingController(text: 'ALMENU10');
  var _tab = 0;
  var _discountSynced = false;

  @override
  void initState() {
    super.initState();
    _hub.addListener(_rebuild);
    _reload();
  }

  @override
  void dispose() {
    _hub.removeListener(_rebuild);
    _hub.dispose();
    _discount.dispose();
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  Future<void> _reload() async {
    final restaurantName =
        AdminAuthService.instance.restaurantName?.trim().isNotEmpty == true
        ? AdminAuthService.instance.restaurantName!.trim()
        : (SuperAdminScopeService.instance.effectiveRestaurantId.isEmpty
              ? 'AlMenuPro'
              : 'AlMenuPro');
    await _hub.load(
      OrdersDemoService.loadedOrders,
      restaurantName: restaurantName,
    );
    if (!_discountSynced && mounted) {
      _discount.text = _hub.discountCode;
      _discountSynced = true;
    }
  }

  Future<void> _dispatch(WhatsappTask task) async {
    if (_hub.isSent(task)) return;
    final message = _hub.messageFor(task);
    final uri = Uri.parse(
      'https://wa.me/${task.phone}?text=${Uri.encodeComponent(message)}',
    );
    var opened = false;
    try {
      opened = await launchUrl(
        uri,
        mode: kIsWeb
            ? LaunchMode.platformDefault
            : LaunchMode.externalApplication,
        webOnlyWindowName: '_blank',
      );
    } catch (error) {
      debugPrint('wa.me failed for ${task.phone}: $error');
    }
    if (!opened) {
      opened = await openWhatsAppChat(phone: task.phone, message: message);
    }
    if (!opened) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر فتح واتساب لهذا الرقم.')),
      );
      return;
    }
    await _hub.markSent(task);
  }

  @override
  Widget build(BuildContext context) {
    if (!canUseWhatsappBroadcast) {
      return const Center(child: Text('هذه الصفحة متاحة لمدير المطعم فقط.'));
    }
    return ColoredBox(
      color: const Color(0xFFF8F4F5),
      child: DefaultTabController(
        length: 2,
        child: Column(
          children: [
            Material(
              color: Colors.white,
              child: TabBar(
                labelColor: burgundy,
                indicatorColor: burgundy,
                onTap: (index) => setState(() => _tab = index),
                tabs: const [
                  Tab(text: 'طوابير الإرسال'),
                  Tab(text: 'إدارة القوالب'),
                ],
              ),
            ),
            Expanded(child: _tab == 0 ? _queueTab() : _templateTab()),
          ],
        ),
      ),
    );
  }

  Widget _queueTab() {
    final visible = _hub.tasksFor(_hub.stage);
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 900;
        return Directionality(
          textDirection: TextDirection.rtl,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: wide ? 28 : 12,
              vertical: 16,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _QueueBadges(hub: _hub, onSelect: _hub.selectStage),
                const SizedBox(height: 8),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton.icon(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const AdminWhatsappBroadcastPage(),
                        ),
                      );
                    },
                    icon: const Icon(Icons.campaign_outlined),
                    label: const Text('حملة جماعية'),
                  ),
                ),
                const SizedBox(height: 8),
                if (!_hub.ready)
                  const LinearProgressIndicator(color: burgundy)
                else
                  Expanded(
                    child: _QueueTable(
                      stage: _hub.stage,
                      tasks: visible,
                      isSent: _hub.isSent,
                      onSend: _dispatch,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _templateTab() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 900;
        final editors = [
          for (final stage in WhatsappStage.values)
            _TemplateEditor(
              stage: stage,
              initialText: _hub.templates[stage] ?? '',
              preview: _hub.previewFor(stage),
              wide: wide,
              onChanged: (text) => _hub.updateTemplate(stage, text),
            ),
        ];
        return ListView(
          padding: EdgeInsets.symmetric(
            horizontal: wide ? 28 : 12,
            vertical: 16,
          ),
          children: [
            TextField(
              decoration: const InputDecoration(
                labelText: 'كود الخصم {discount_code}',
                border: OutlineInputBorder(),
              ),
              controller: _discount,
              onChanged: _hub.updateDiscount,
            ),
            const SizedBox(height: 12),
            if (wide)
              for (var i = 0; i < editors.length; i += 2)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: editors[i]),
                      const SizedBox(width: 12),
                      Expanded(
                        child: i + 1 < editors.length
                            ? editors[i + 1]
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ),
                )
            else
              ...editors.map(
                (editor) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: editor,
                ),
              ),
          ],
        );
      },
    );
  }
}

class _QueueBadges extends StatelessWidget {
  const _QueueBadges({required this.hub, required this.onSelect});

  final SmartWhatsappHubController hub;
  final ValueChanged<WhatsappStage> onSelect;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final stage in WhatsappStage.values)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 8),
              child: _QueueTabButton(
                label: whatsappQueueLabel(stage),
                count: hub.pendingCount(stage),
                selected: hub.stage == stage,
                onTap: () => onSelect(stage),
              ),
            ),
        ],
      ),
    );
  }
}

class _QueueTabButton extends StatelessWidget {
  const _QueueTabButton({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final foreground = selected
        ? Colors.white
        : _SmartWhatsappHubPageState.burgundy;
    return Material(
      color: selected ? _SmartWhatsappHubPageState.burgundy : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: selected
              ? _SmartWhatsappHubPageState.burgundy
              : const Color(0xFFE7D6DA),
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: foreground,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: selected
                      ? _SmartWhatsappHubPageState.lightOrange
                      : const Color(0xFFFFF1E4),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  '$count',
                  style: const TextStyle(
                    color: _SmartWhatsappHubPageState.burgundy,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Customer rows for the selected queue. Sent state is read on each rebuild.
class _QueueTable extends StatelessWidget {
  const _QueueTable({
    required this.stage,
    required this.tasks,
    required this.isSent,
    required this.onSend,
  });

  final WhatsappStage stage;
  final List<WhatsappTask> tasks;
  final bool Function(WhatsappTask task) isSent;
  final ValueChanged<WhatsappTask> onSend;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Colors.white,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFFE7D6DA)),
      ),
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 760;
          final tableWidth = compact ? 760.0 : constraints.maxWidth;
          return Scrollbar(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: tableWidth,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (tasks.isEmpty)
                        const Padding(
                          padding: EdgeInsets.fromLTRB(20, 16, 20, 0),
                          child: Text(
                            'لا توجد مهام في هذا الطابور.',
                            style: TextStyle(
                              color: Color(0xFF6B5A5E),
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      Theme(
                        data: Theme.of(context).copyWith(
                          dataTableTheme: const DataTableThemeData(
                            headingTextStyle: TextStyle(
                              color: _SmartWhatsappHubPageState.burgundy,
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        child: PaginatedDataTable(
                          key: ValueKey(stage),
                          header: Text(
                            whatsappQueueLabel(stage),
                            style: const TextStyle(
                              color: _SmartWhatsappHubPageState.burgundy,
                              fontWeight: FontWeight.w800,
                              fontSize: 18,
                            ),
                          ),
                          headingRowColor: const WidgetStatePropertyAll(
                            Color(0xFFFFF6EE),
                          ),
                          dataRowMinHeight: 64,
                          dataRowMaxHeight: 76,
                          columnSpacing: compact ? 18 : 28,
                          horizontalMargin: compact ? 12 : 20,
                          rowsPerPage: tasks.isEmpty
                              ? 1
                              : (tasks.length < 8 ? tasks.length : 8),
                          showCheckboxColumn: false,
                          arrowHeadColor: _SmartWhatsappHubPageState.burgundy,
                          columns: const [
                            DataColumn(label: Text('الاسم')),
                            DataColumn(label: Text('رقم الهاتف')),
                            DataColumn(label: Text('رقم الطلب')),
                            DataColumn(label: Text('حالة الإرسال')),
                            DataColumn(label: Text('الإجراء')),
                          ],
                          source: _WhatsappTaskSource(
                            tasks: tasks,
                            isSent: isSent,
                            onSend: onSend,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _WhatsappTaskSource extends DataTableSource {
  _WhatsappTaskSource({
    required this.tasks,
    required this.isSent,
    required this.onSend,
  });

  final List<WhatsappTask> tasks;
  final bool Function(WhatsappTask task) isSent;
  final ValueChanged<WhatsappTask> onSend;

  @override
  DataRow? getRow(int index) {
    if (index >= tasks.length) return null;
    final task = tasks[index];
    final sent = isSent(task);
    return DataRow.byIndex(
      index: index,
      color: WidgetStatePropertyAll(
        index.isEven ? const Color(0xFFFFFBF8) : Colors.white,
      ),
      cells: [
        DataCell(
          Text(task.name, style: const TextStyle(fontWeight: FontWeight.w700)),
        ),
        DataCell(Text('\u200E${task.phone}')),
        DataCell(
          Text(
            '\u200E${task.orderId}',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        DataCell(sent ? const _SentBadge() : const _PendingBadge()),
        DataCell(
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: _SmartWhatsappHubPageState.whatsappGreen,
              foregroundColor: Colors.white,
              disabledBackgroundColor: const Color(0xFFE7D6DA),
              disabledForegroundColor: const Color(0xFF6B5A5E),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            ),
            onPressed: sent ? null : () => onSend(task),
            icon: const _WhatsAppGlyph(),
            label: const Text('إرسال'),
          ),
        ),
      ],
    );
  }

  @override
  bool get isRowCountApproximate => false;

  @override
  int get rowCount => tasks.length;

  @override
  int get selectedRowCount => 0;
}

class _SentBadge extends StatelessWidget {
  const _SentBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFE8F8EE),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: _SmartWhatsappHubPageState.whatsappGreen),
      ),
      child: const Text(
        'Sent ✅',
        style: TextStyle(color: Color(0xFF128C7E), fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _PendingBadge extends StatelessWidget {
  const _PendingBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF1E4),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: _SmartWhatsappHubPageState.lightOrange),
      ),
      child: const Text(
        'بانتظار',
        style: TextStyle(
          color: _SmartWhatsappHubPageState.burgundy,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _WhatsAppGlyph extends StatelessWidget {
  const _WhatsAppGlyph();

  @override
  Widget build(BuildContext context) {
    final color = IconTheme.of(context).color ?? Colors.white;
    return SizedBox(
      width: 18,
      height: 18,
      child: CustomPaint(painter: _WhatsAppGlyphPainter(color)),
    );
  }
}

class _WhatsAppGlyphPainter extends CustomPainter {
  _WhatsAppGlyphPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final bubble = RRect.fromLTRBR(
      size.width * 0.04,
      size.height * 0.06,
      size.width * 0.96,
      size.height * 0.74,
      Radius.circular(size.width * 0.28),
    );
    canvas.drawRRect(bubble, paint);
    final tail = Path()
      ..moveTo(size.width * 0.22, size.height * 0.66)
      ..lineTo(size.width * 0.16, size.height * 0.98)
      ..lineTo(size.width * 0.46, size.height * 0.70)
      ..close();
    canvas.drawPath(tail, paint);
  }

  @override
  bool shouldRepaint(covariant _WhatsAppGlyphPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _TemplateEditor extends StatefulWidget {
  const _TemplateEditor({
    required this.stage,
    required this.initialText,
    required this.preview,
    required this.wide,
    required this.onChanged,
  });

  final WhatsappStage stage;
  final String initialText;
  final String preview;
  final bool wide;
  final ValueChanged<String> onChanged;

  @override
  State<_TemplateEditor> createState() => _TemplateEditorState();
}

class _TemplateEditorState extends State<_TemplateEditor> {
  late final TextEditingController _text = TextEditingController(
    text: widget.initialText,
  );

  @override
  void didUpdateWidget(_TemplateEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialText != widget.initialText &&
        _text.text != widget.initialText) {
      _text.text = widget.initialText;
    }
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _insert(String token) {
    final value = _text.value;
    final offset = value.selection.baseOffset < 0
        ? value.text.length
        : value.selection.baseOffset;
    final next = insertBroadcastPlaceholder(value.text, offset, token);
    _text.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: offset + token.length),
    );
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final editor = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          whatsappStageLabel(widget.stage),
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            color: _SmartWhatsappHubPageState.burgundy,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          children: [
            for (final token in whatsappStagePlaceholders)
              ChoiceChip(
                label: Text(token),
                selected: false,
                onSelected: (_) => _insert(token),
              ),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _text,
          minLines: 4,
          maxLines: 8,
          onChanged: widget.onChanged,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
      ],
    );
    final preview = Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF6EE),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _SmartWhatsappHubPageState.lightOrange),
      ),
      child: Text(widget.preview),
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: widget.wide
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 3, child: editor),
                  const SizedBox(width: 12),
                  Expanded(flex: 2, child: preview),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [editor, const SizedBox(height: 12), preview],
              ),
      ),
    );
  }
}
