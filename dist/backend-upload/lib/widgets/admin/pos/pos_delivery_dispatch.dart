import 'package:flutter/material.dart';

import '../../../models/delivery_dispatch.dart';
import '../../../models/delivery_zone.dart';
import '../../../services/api_service.dart';
import '../../../services/delivery_dispatch_service.dart';

class PosExpressDriverButton extends StatelessWidget {
  const PosExpressDriverButton({
    super.key,
    required this.zones,
    this.restaurantId,
    this.initialPhone = '',
    this.onCreated,
  });

  final List<DeliveryZone> zones;
  final String? restaurantId;
  final String initialPhone;
  final ValueChanged<DeliveryDispatchRequest>? onCreated;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: () async {
        final created = await showDialog<DeliveryDispatchRequest>(
          context: context,
          builder: (context) => _ExpressDriverDialog(
            zones: zones,
            restaurantId: restaurantId,
            initialPhone: initialPhone,
          ),
        );
        if (created != null) onCreated?.call(created);
      },
      icon: const Icon(Icons.rocket_launch, size: 18),
      label: const Text('طلب سائق سريع'),
    );
  }
}

class _ExpressDriverDialog extends StatefulWidget {
  const _ExpressDriverDialog({
    required this.zones,
    this.restaurantId,
    this.initialPhone = '',
  });

  final List<DeliveryZone> zones;
  final String? restaurantId;
  final String initialPhone;

  @override
  State<_ExpressDriverDialog> createState() => _ExpressDriverDialogState();
}

class _ExpressDriverDialogState extends State<_ExpressDriverDialog> {
  late final TextEditingController _phone;
  late final TextEditingController _cash;
  String? _zoneId;
  var _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _phone = TextEditingController(text: widget.initialPhone);
    _cash = TextEditingController(text: '0');
    _zoneId = widget.zones.isNotEmpty ? widget.zones.first.id : null;
  }

  @override
  void dispose() {
    _phone.dispose();
    _cash.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final phone = _phone.text.trim();
    if (phone.length < 8) {
      setState(() => _error = 'أدخل رقم هاتف العميل');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final zone = widget.zones.where((row) => row.id == _zoneId).firstOrNull;
      final created = await ApiService.instance.createDeliveryRequest(
        customerPhone: phone,
        regionId: zone?.id,
        regionName: zone?.displayName,
        isExpress: true,
        cashToCollect: double.tryParse(_cash.text.trim()) ?? 0,
        restaurantId: widget.restaurantId,
      );
      if (!mounted) return;
      Navigator.pop(context, created);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('طلب سائق سريع'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              initialValue: _zoneId,
              decoration: const InputDecoration(labelText: 'المنطقة'),
              items: widget.zones
                  .map(
                    (zone) => DropdownMenuItem(
                      value: zone.id,
                      child: Text('${zone.displayName} — ${zone.deliveryFee.toStringAsFixed(3)} د.ك'),
                    ),
                  )
                  .toList(),
              onChanged: (value) => setState(() => _zoneId = value),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'هاتف العميل'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _cash,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'المبلغ للتحصيل (د.ك)'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: const TextStyle(color: Color(0xFFC62828))),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context), child: const Text('إلغاء')),
        FilledButton(
          onPressed: _saving ? null : _submit,
          child: _saving
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('إرسال'),
        ),
      ],
    );
  }
}

class PosDeliveryTracker extends StatefulWidget {
  const PosDeliveryTracker({super.key, this.restaurantId});

  final String? restaurantId;

  @override
  State<PosDeliveryTracker> createState() => _PosDeliveryTrackerState();
}

class _PosDeliveryTrackerState extends State<PosDeliveryTracker> {
  DeliveryBoardController get _board => DeliveryBoardController.instance;

  @override
  void initState() {
    super.initState();
    _board.ensureStarted(restaurantId: widget.restaurantId);
    _board.addListener(_onBoard);
  }

  @override
  void dispose() {
    _board.removeListener(_onBoard);
    super.dispose();
  }

  void _onBoard() {
    if (mounted) setState(() {});
  }

  Color _colorFor(DeliveryDispatchRequest request) {
    if (request.isRejectedByAll) return const Color(0xFFC62828);
    if (request.isAccepted || request.isPickedUp) return const Color(0xFF2E7D32);
    return const Color(0xFFF9A825);
  }

  @override
  Widget build(BuildContext context) {
    if (_board.loading && _board.live.isEmpty) {
      return const Padding(
        padding: EdgeInsets.only(bottom: 8),
        child: LinearProgressIndicator(minHeight: 2),
      );
    }
    if (_board.error != null && _board.live.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          _board.error!,
          style: const TextStyle(color: Color(0xFFC62828), fontSize: 12),
        ),
      );
    }
    if (_board.live.isEmpty) return const SizedBox.shrink();
    return Column(
      children: _board.live.map((request) {
        final color = _colorFor(request);
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withValues(alpha: 0.4)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '${request.isExpress ? '🚀 ' : ''}${request.statusLabelAr}',
                style: TextStyle(color: color, fontWeight: FontWeight.w800),
              ),
              Text(
                '${request.regionName} — ${request.customerPhone}',
                style: const TextStyle(fontSize: 12),
              ),
              if (request.isPending || request.isRejectedByAll)
                Wrap(
                  spacing: 6,
                  children: _board.onlineDrivers
                      .map(
                        (driver) => ActionChip(
                          label: Text('تعيين ${driver.name}'),
                          onPressed: () => _board.assign(request.id, driver.id),
                        ),
                      )
                      .toList(),
                ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

