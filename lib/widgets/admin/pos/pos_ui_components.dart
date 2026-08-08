import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../models/cart_item.dart';
import '../../../models/menu_item.dart';
import '../../../theme/app_theme.dart';
import '../../network_menu_image.dart';
import 'pos_theme.dart';

class PosMenuItemCard extends StatefulWidget {
  const PosMenuItemCard({
    super.key,
    required this.item,
    required this.onTap,
    this.compact = false,
  });

  final MenuItem item;
  final VoidCallback onTap;
  final bool compact;

  @override
  State<PosMenuItemCard> createState() => _PosMenuItemCardState();
}

class _PosMenuItemCardState extends State<PosMenuItemCard> {
  var _pressed = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.96 : 1,
        duration: const Duration(milliseconds: 90),
        child: Container(
          decoration: PosTheme.card(),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    NetworkMenuImage(imageUrl: item.imageUrl, fit: BoxFit.cover),
                    if (item.hasCustomizations)
                      Positioned(
                        top: 6,
                        left: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Icon(
                            Icons.tune,
                            size: 12,
                            color: Colors.white,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Container(
                color: PosTheme.surfaceAlt,
                padding: EdgeInsets.all(widget.compact ? 6 : 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: widget.compact ? 11 : 13,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${item.price.toStringAsFixed(3)} د.ك',
                      style: const TextStyle(
                        color: PosTheme.accent,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class PosQuickItemChip extends StatefulWidget {
  const PosQuickItemChip({
    super.key,
    required this.item,
    required this.onTap,
  });

  final MenuItem item;
  final VoidCallback onTap;

  @override
  State<PosQuickItemChip> createState() => _PosQuickItemChipState();
}

class _PosQuickItemChipState extends State<PosQuickItemChip> {
  var _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.95 : 1,
        duration: const Duration(milliseconds: 80),
        child: Container(
          width: 108,
          decoration: PosTheme.card(color: PosTheme.quickStrip),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 56,
                child: NetworkMenuImage(
                  imageUrl: widget.item.imageUrl,
                  fit: BoxFit.cover,
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.item.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      widget.item.price.toStringAsFixed(3),
                      style: const TextStyle(
                        fontSize: 10,
                        color: PosTheme.accent,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class PosCategoryTile extends StatelessWidget {
  const PosCategoryTile({
    super.key,
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: selected ? PosTheme.accentSoft : PosTheme.surface,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected ? PosTheme.accent : PosTheme.border,
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 18,
                  color: selected ? PosTheme.accent : PosTheme.textMuted,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: selected ? FontWeight.bold : FontWeight.w600,
                      color: selected ? PosTheme.accent : AppTheme.brandBlack,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

IconData posCategoryIcon(String category) {
  final value = category.toLowerCase();
  if (value.contains('الكل')) return Icons.grid_view_rounded;
  if (value.contains('مبيع') || value.contains('🔥')) {
    return Icons.local_fire_department_rounded;
  }
  if (value.contains('مشرو') || value.contains('drink')) {
    return Icons.local_cafe_rounded;
  }
  if (value.contains('حلو') || value.contains('dessert')) {
    return Icons.cake_rounded;
  }
  if (value.contains('برجر') || value.contains('burger')) {
    return Icons.lunch_dining_rounded;
  }
  if (value.contains('بيت') || value.contains('pizza')) {
    return Icons.local_pizza_rounded;
  }
  return Icons.restaurant_menu_rounded;
}

class PosCartLine extends StatelessWidget {
  const PosCartLine({
    super.key,
    required this.item,
    required this.onIncrease,
    required this.onDecrease,
  });

  final CartItem item;
  final VoidCallback onIncrease;
  final VoidCallback onDecrease;

  @override
  Widget build(BuildContext context) {
    final addons = item.selectedOptions
        .map((o) => '${o.name} (+${o.price.toStringAsFixed(3)})')
        .join(' · ');

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: PosTheme.card(color: PosTheme.surfaceAlt),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.menuItem.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                if (addons.isNotEmpty)
                  Text(
                    addons,
                    style: const TextStyle(
                      fontSize: 11,
                      color: PosTheme.textMuted,
                    ),
                  ),
                if (item.specialNotes?.trim().isNotEmpty ?? false)
                  Text(
                    'ملاحظة: ${item.specialNotes!.trim()}',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.orange.shade800,
                    ),
                  ),
                const SizedBox(height: 4),
                Text(
                  '${item.unitPrice.toStringAsFixed(3)} × ${item.quantity}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: PosTheme.accent,
                  ),
                ),
              ],
            ),
          ),
          PosQuantityControl(
            quantity: item.quantity,
            onIncrease: onIncrease,
            onDecrease: onDecrease,
          ),
        ],
      ),
    );
  }
}

class PosQuantityControl extends StatefulWidget {
  const PosQuantityControl({
    super.key,
    required this.quantity,
    required this.onIncrease,
    required this.onDecrease,
  });

  final int quantity;
  final VoidCallback onIncrease;
  final VoidCallback onDecrease;

  @override
  State<PosQuantityControl> createState() => _PosQuantityControlState();
}

class _PosQuantityControlState extends State<PosQuantityControl> {
  var _incPressed = false;
  var _decPressed = false;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _QtyCircle(
          icon: Icons.remove,
          pressed: _decPressed,
          onTap: widget.onDecrease,
          onPressChange: (v) => setState(() => _decPressed = v),
        ),
        Container(
          width: 36,
          alignment: Alignment.center,
          child: Text(
            '${widget.quantity}',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
        ),
        _QtyCircle(
          icon: Icons.add,
          pressed: _incPressed,
          onTap: widget.onIncrease,
          onPressChange: (v) => setState(() => _incPressed = v),
          filled: true,
        ),
      ],
    );
  }
}

class _QtyCircle extends StatelessWidget {
  const _QtyCircle({
    required this.icon,
    required this.pressed,
    required this.onTap,
    required this.onPressChange,
    this.filled = false,
  });

  final IconData icon;
  final bool pressed;
  final VoidCallback onTap;
  final ValueChanged<bool> onPressChange;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => onPressChange(true),
      onTapUp: (_) {
        onPressChange(false);
        onTap();
      },
      onTapCancel: () => onPressChange(false),
      child: AnimatedScale(
        scale: pressed ? 0.88 : 1,
        duration: const Duration(milliseconds: 80),
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: filled ? PosTheme.accent : PosTheme.surface,
            shape: BoxShape.circle,
            border: Border.all(
              color: filled ? PosTheme.accent : PosTheme.border,
              width: 1.5,
            ),
          ),
          child: Icon(
            icon,
            size: 20,
            color: filled ? Colors.white : PosTheme.accent,
          ),
        ),
      ),
    );
  }
}

class PosTotalRow extends StatelessWidget {
  const PosTotalRow({
    super.key,
    required this.label,
    required this.value,
    this.bold = false,
    this.large = false,
  });

  final String label;
  final double value;
  final bool bold;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontWeight: bold ? FontWeight.bold : FontWeight.w500,
      fontSize: large ? 20 : (bold ? 15 : 13),
      color: bold ? PosTheme.accent : AppTheme.brandBlack,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Text(label, style: style),
          const Spacer(),
          Text('${value.toStringAsFixed(3)} د.ك', style: style),
        ],
      ),
    );
  }
}

class PosPaymentChip extends StatelessWidget {
  const PosPaymentChip({
    super.key,
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Material(
        color: selected ? PosTheme.accent : PosTheme.surface,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected ? PosTheme.accent : PosTheme.border,
              ),
            ),
            child: Column(
              children: [
                Icon(icon, color: selected ? Colors.white : PosTheme.textMuted),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: selected ? Colors.white : AppTheme.brandBlack,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class PosShortcutHint extends StatelessWidget {
  const PosShortcutHint({super.key});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: const [
        _HintBadge('F2', 'دفع'),
        _HintBadge('F4', 'بحث'),
        _HintBadge('F8', 'تفريغ'),
        _HintBadge('Esc', 'إلغاء'),
      ],
    );
  }
}

class _HintBadge extends StatelessWidget {
  const _HintBadge(this.keyLabel, this.action);

  final String keyLabel;
  final String action;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: PosTheme.surfaceAlt,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: PosTheme.border),
      ),
      child: Text(
        '$keyLabel $action',
        style: const TextStyle(fontSize: 10, color: PosTheme.textMuted),
      ),
    );
  }
}

/// Keyboard shortcut intents for POS.
class PosFocusSearchIntent extends Intent {
  const PosFocusSearchIntent();
}

class PosSubmitIntent extends Intent {
  const PosSubmitIntent();
}

class PosClearCartIntent extends Intent {
  const PosClearCartIntent();
}

class PosClearSearchIntent extends Intent {
  const PosClearSearchIntent();
}

/// Matches menu item by name prefix, initials, or barcode/id.
bool posMatchesSearch(MenuItem item, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return true;

  if (item.talabatId?.toString() == q || item.id.toString() == q) {
    return true;
  }

  final names = [
    item.name.toLowerCase(),
    item.nameAr.toLowerCase(),
    item.nameEn.toLowerCase(),
  ];

  for (final name in names) {
    if (name.startsWith(q) || name.contains(q)) return true;
    final initials = name
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .map((w) => w.characters.first)
        .join();
    if (initials.startsWith(q)) return true;
  }
  return false;
}

MenuItem? posFindBarcodeMatch(List<MenuItem> items, String query) {
  final q = query.trim();
  if (q.isEmpty) return null;
  for (final item in items) {
    if (item.talabatId?.toString() == q || item.id.toString() == q) {
      return item;
    }
  }
  return null;
}
