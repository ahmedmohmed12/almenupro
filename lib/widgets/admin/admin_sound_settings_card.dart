import 'package:flutter/material.dart';

import '../../models/order_alert_sound.dart';
import '../../services/order_alert_sound_service.dart';

class AdminSoundSettingsCard extends StatefulWidget {
  const AdminSoundSettingsCard({super.key});

  @override
  State<AdminSoundSettingsCard> createState() => _AdminSoundSettingsCardState();
}

class _AdminSoundSettingsCardState extends State<AdminSoundSettingsCard> {
  final _soundService = OrderAlertSoundService.instance;
  var _isPreviewing = false;
  var _isSaving = false;

  @override
  void initState() {
    super.initState();
    _ensureInitialized();
  }

  Future<void> _ensureInitialized() async {
    if (!_soundService.isInitialized) {
      await _soundService.initialize();
    }
    if (mounted) setState(() {});
  }

  Future<void> _saveType(OrderAlertSoundType type) async {
    setState(() => _isSaving = true);
    await _soundService.setSelectedType(type);
    if (!mounted) return;
    setState(() => _isSaving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('تم حفظ نغمة التنبيه: ${type.label}')),
    );
  }

  Future<void> _toggleEnabled(bool value) async {
    await _soundService.setEnabled(value);
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _testSound() async {
    setState(() => _isPreviewing = true);
    await _soundService.previewSound();
    if (!mounted) return;
    setState(() => _isPreviewing = false);

    if (!_soundService.audioUnlocked && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'اضغط "تجربة الصوت" مرة أخرى إذا لم تسمع شيئاً — المتصفح يتطلب تفاعلاً أولاً.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedType = _soundService.selectedType;
    final enabled = _soundService.enabled;
    final unlocked = _soundService.audioUnlocked;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  backgroundColor: null,
                  decoration: BoxDecoration(
                    color: const Color(0xFF6B1124).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.notifications_active_outlined,
                    color: Color(0xFF6B1124),
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'إعدادات التنبيه الصوتي للطلبات',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF6B1124),
                    ),
                  ),
                ),
                Switch(
                  value: enabled,
                  activeThumbColor: const Color(0xFF6B1124),
                  onChanged: _toggleEnabled,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              enabled
                  ? 'اختر نغمة التنبيه التي تُشغَّل تلقائياً عند وصول طلب جديد.'
                  : 'التنبيه الصوتي متوقف حالياً.',
              style: TextStyle(color: Colors.grey.shade700),
            ),
            if (!unlocked) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.amber.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.amber.shade800),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'اضغط "تجربة الصوت" أو أي زر في الصفحة لتفعيل الصوت — '
                        'المتصفحات الحديثة تمنع التشغيل التلقائي قبل أول تفاعل.',
                        style: TextStyle(
                          color: Colors.amber.shade900,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 20),
            ...OrderAlertSoundType.values.map((type) {
              final isSelected = selectedType == type;
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Material(
                  color: isSelected
                      ? const Color(0xFF6B1124).withValues(alpha: 0.08)
                      : Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: _isSaving ? null : () => _saveType(type),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _iconForType(type),
                            color: isSelected
                                ? const Color(0xFF6B1124)
                                : Colors.grey.shade600,
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  type.label,
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: isSelected
                                        ? const Color(0xFF6B1124)
                                        : Colors.black87,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  type.description,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Radio<OrderAlertSoundType>(
                            value: type,
                            groupValue: selectedType,
                            activeColor: const Color(0xFF6B1124),
                            onChanged: _isSaving
                                ? null
                                : (value) {
                                    if (value != null) _saveType(value);
                                  },
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }),
            const SizedBox(height: 8),
            SizedBox(
              height: 48,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF6B1124),
                  side: const BorderSide(color: Color(0xFF6B1124)),
                ),
                onPressed: _isPreviewing || !enabled ? null : _testSound,
                icon: _isPreviewing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.volume_up),
                label: Text(_isPreviewing ? 'جاري التشغيل...' : 'تجربة الصوت'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _iconForType(OrderAlertSoundType type) {
    switch (type) {
      case OrderAlertSoundType.bell:
        return Icons.notifications_outlined;
      case OrderAlertSoundType.soft:
        return Icons.volume_down_outlined;
      case OrderAlertSoundType.alarm:
        return Icons.campaign_outlined;
    }
  }
}
