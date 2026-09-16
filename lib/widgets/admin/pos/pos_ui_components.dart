import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../models/cart_item.dart';
import '../../../models/menu_item.dart';
import '../../../theme/app_theme.dart';
import '../../network_menu_image.dart';
import '../../menu/product_sale_price.dart';
import 'pos_theme.dart';

export '../../../services/pos/pos_catalog_match.dart';

class PosMenuItemCard extends StatelessWidget {
  const PosMenuItemCard({
    super.key,
    required this.item,
    required this.onTap,
    this.compact = false,
  });

  final MenuItem item;
  final VoidCallback onTap;
  final bool compact;

  bool get _hasRequiredMods =>
      item.options.any((o) => o.isAvailable && o.isGroupRequired);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: RepaintBoundary(
          child: Container(
            decoration: PosTheme.card(radius: 10),
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 58,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      NetworkMenuImage(
                        imageUrl: item.imageUrl,
                        fit: BoxFit.cover,
                      ),
                      if (item.hasDiscount && item.discountPercent != null)
                        Positioned(
                          top: 4,
                          left: 4,
                          child: ProductDiscountBadge(
                            percent: item.discountPercent!,
                            compact: true,
                          ),
                        ),
                      if (item.hasCustomizations)
                        Positioned(
                          top: 4,
                          right: 4,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: _hasRequiredMods
                                  ? PosTheme.orange
                                  : Colors.black54,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Icon(
                              Icons.tune_rounded,
                              size: 11,
                              color: Colors.white,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  flex: 42,
                  child: Container(
                    color: PosTheme.surface,
                    padding: EdgeInsets.fromLTRB(
                      compact ? 5 : 6,
                      compact ? 4 : 5,
                      compact ? 5 : 6,
                      compact ? 4 : 5,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            item.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: compact ? 11 : 12,
                              height: 1.15,
                              color: PosTheme.textPrimary,
                            ),
                          ),
                        ),
                        if (item.hasDiscount)
                          ProductSalePrice(item: item, compact: true)
                        else
                          Text(
                            '${item.price.toStringAsFixed(3)} د.ك',
                            style: TextStyle(
                              color: PosTheme.orange,
                              fontWeight: FontWeight.w800,
                              fontSize: compact ? 11.5 : 12.5,
                            ),
                          ),
                      ],
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

class PosQuickItemChip extends StatelessWidget {
  const PosQuickItemChip({
    super.key,
    required this.item,
    required this.onTap,
  });

  final MenuItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
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
                  imageUrl: item.imageUrl,
                  fit: BoxFit.cover,
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      item.price.toStringAsFixed(3),
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
    this.compact = false,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: compact ? 4 : 6),
      child: Material(
        color: selected ? PosTheme.accentSoft : PosTheme.surface,
        borderRadius: BorderRadius.circular(compact ? 10 : 12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(compact ? 10 : 12),
          child: Container(
            width: double.infinity,
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 8 : 10,
              vertical: compact ? 8 : 12,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(compact ? 10 : 12),
              border: Border.all(
                color: selected ? PosTheme.accent : PosTheme.border,
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: compact ? 16 : 18,
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
    final variant = item.menuItem.categoryName.trim();
    final modifiers = item.selectedOptions;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: PosTheme.card(color: PosTheme.surface, radius: 12),
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
                    fontWeight: FontWeight.w800,
                    fontSize: 14.5,
                    color: PosTheme.textPrimary,
                  ),
                ),
                if (variant.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    variant,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: PosTheme.textMuted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                if (modifiers.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  ...modifiers.map(
                    (option) => Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text(
                        option.price > 0
                            ? '+ ${option.name}  (${option.price.toStringAsFixed(3)})'
                            : '+ ${option.name}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: PosTheme.textMuted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
                if (item.specialNotes?.trim().isNotEmpty ?? false) ...[
                  const SizedBox(height: 4),
                  Text(
                    'ملاحظة: ${item.specialNotes!.trim()}',
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: PosTheme.orange,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                const SizedBox(height: 6),
                Text(
                  '${item.totalPrice.toStringAsFixed(3)} د.ك',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: PosTheme.orange,
                    fontSize: 13.5,
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
      onTap: onTap,
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

class PosStyleChip extends StatelessWidget {
  const PosStyleChip({
    super.key,
    required this.label,
    required this.icon,
    required this.color,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final IconData icon;
  final Color color;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 0),
      avatar: Icon(
        icon,
        size: 16,
        color: selected ? Colors.white : color,
      ),
      label: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: selected ? Colors.white : const Color(0xFF1A1A1A),
        ),
      ),
      selected: selected,
      selectedColor: color,
      backgroundColor: color.withValues(alpha: 0.08),
      side: BorderSide(
        color: selected ? color : color.withValues(alpha: 0.35),
      ),
      onSelected: (_) => onSelected(),
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
    return Material(
      color: selected ? PosTheme.accent : PosTheme.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? PosTheme.accent : PosTheme.border,
            ),
          ),
          child: Column(
            children: [
              Icon(
                icon,
                size: 20,
                color: selected ? Colors.white : PosTheme.textMuted,
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: selected ? Colors.white : AppTheme.brandBlack,
                ),
              ),
            ],
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
        _HintBadge('Enter', 'فاتورة'),
        _HintBadge('Shift+Enter', 'مطبخ'),
        _HintBadge('F2', 'فاتورة'),
        _HintBadge('F4', 'بحث'),
        _HintBadge('F8', 'تفريغ'),
        _HintBadge('Esc', 'تفريغ'),
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

class PosKitchenIntent extends Intent {
  const PosKitchenIntent();
}

class PosClearCartIntent extends Intent {
  const PosClearCartIntent();
}

class PosClearSearchIntent extends Intent {
  const PosClearSearchIntent();
}

/// True when the primary focus is inside a text editing control.
bool posIsEditingText() {
  final primary = FocusManager.instance.primaryFocus;
  if (primary == null) return false;
  final context = primary.context;
  if (context == null) return false;
  return context.findAncestorWidgetOfExactType<EditableText>() != null;
}
