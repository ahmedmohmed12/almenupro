import 'package:flutter/material.dart';

import '../../models/menu_item.dart';
import '../../providers/customer_session_provider.dart';
import '../../theme/app_theme.dart';
import '../network_menu_image.dart';

class StorefrontHero extends StatelessWidget {
  const StorefrontHero({
    super.key,
    required this.restaurantName,
    required this.description,
    required this.logoUrl,
    required this.deliveryFee,
    required this.session,
  });

  final String restaurantName;
  final String description;
  final String logoUrl;
  final double deliveryFee;
  final CustomerSessionProvider session;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final compact = width < 520;
        final desktop = width >= 900;
        final bannerHeight = desktop ? 148.0 : compact ? 84.0 : 112.0;
        final logoSize = desktop ? 64.0 : compact ? 44.0 : 52.0;
        final titleSize = desktop ? 22.0 : compact ? 15.0 : 17.0;
        final horizontal = desktop ? 20.0 : 10.0;

        return Column(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  height: bannerHeight,
                  width: double.infinity,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFF6B1124), Color(0xFFB45309)],
                      begin: Alignment.topRight,
                      end: Alignment.bottomLeft,
                    ),
                  ),
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(horizontal, 10, 12, 0),
                      child: Icon(
                        Icons.cookie,
                        color: Colors.white24,
                        size: desktop ? 80 : 52,
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    horizontal,
                    bannerHeight - (compact ? 28 : 38),
                    horizontal,
                    0,
                  ),
                  child: Material(
                    color: Colors.white,
                    elevation: 6,
                    shadowColor: Colors.black26,
                    borderRadius: BorderRadius.circular(14),
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        compact ? 10 : 12,
                        compact ? 8 : 10,
                        compact ? 10 : 12,
                        compact ? 8 : 10,
                      ),
                      child: compact
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    _Logo(url: logoUrl, size: logoSize),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: _Identity(
                                        restaurantName: restaurantName,
                                        description: description,
                                        titleSize: titleSize,
                                        maxDescriptionLines: 2,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                _MetaRow(deliveryFee: deliveryFee),
                              ],
                            )
                          : Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _Logo(url: logoUrl, size: logoSize),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      _Identity(
                                        restaurantName: restaurantName,
                                        description: description,
                                        titleSize: titleSize,
                                        maxDescriptionLines: desktop ? 2 : 1,
                                      ),
                                      const SizedBox(height: 6),
                                      _MetaRow(deliveryFee: deliveryFee),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                ),
              ],
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(horizontal, 8, horizontal, 0),
              child: _PromoBanner(session: session, compact: compact),
            ),
          ],
        );
      },
    );
  }
}

class _Logo extends StatelessWidget {
  const _Logo({required this.url, required this.size});

  final String url;
  final double size;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        width: size,
        height: size,
        child: url.trim().isEmpty
            ? const ColoredBox(
                color: Color(0xFFFFF4E5),
                child: Icon(Icons.storefront, color: AppTheme.brandMaroon),
              )
            : NetworkMenuImage(imageUrl: url, fit: BoxFit.cover),
      ),
    );
  }
}

class _Identity extends StatelessWidget {
  const _Identity({
    required this.restaurantName,
    required this.description,
    required this.titleSize,
    required this.maxDescriptionLines,
  });

  final String restaurantName;
  final String description;
  final double titleSize;
  final int maxDescriptionLines;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          restaurantName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: titleSize,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          description.isEmpty ? 'كوكيز طازج وتوصيل سريع' : description,
          maxLines: maxDescriptionLines,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
        ),
      ],
    );
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.deliveryFee});

  final double deliveryFee;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 6,
      children: [
        const _MetaChip(icon: Icons.star_rounded, label: '4.8'),
        const _MetaChip(icon: Icons.timer_outlined, label: '25-35 د'),
        _MetaChip(
          icon: Icons.delivery_dining_outlined,
          label: deliveryFee <= 0
              ? 'توصيل مجاني'
              : '${deliveryFee.toStringAsFixed(3)} د.ك',
        ),
      ],
    );
  }
}

class _PromoBanner extends StatelessWidget {
  const _PromoBanner({required this.session, required this.compact});

  final CustomerSessionProvider session;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 10 : 12,
        vertical: compact ? 8 : 10,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFDBA74)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.card_giftcard, color: AppTheme.brandOrange),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  session.identified && session.isReturning
                      ? 'مرحباً بعودتك، ${session.welcomeName}'
                      : 'عرض الكاش باك',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: AppTheme.brandMaroon,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  session.identified && session.walletBalance > 0
                      ? 'رصيد محفظتك ${session.walletBalance.toStringAsFixed(3)} د.ك — ${session.cashbackOfferLabel}'
                      : session.cashbackOfferLabel,
                  maxLines: compact ? 3 : 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF9A3412),
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: AppTheme.brandOrange),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

class StorefrontItemCard extends StatelessWidget {
  const StorefrontItemCard({
    super.key,
    required this.item,
    required this.onAdd,
    this.dense = false,
  });

  final MenuItem item;
  final VoidCallback onAdd;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = dense || constraints.maxWidth < 200;
        final showDescription = !compact && item.description.trim().isNotEmpty;

        return Material(
          color: Colors.white,
          elevation: 1,
          shadowColor: Colors.black12,
          borderRadius: BorderRadius.circular(14),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: compact ? 13 : 12,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    item.imageUrl.trim().isEmpty
                        ? const ColoredBox(
                            color: Color(0xFFFFF4E5),
                            child: Icon(Icons.cookie_outlined, size: 36),
                          )
                        : NetworkMenuImage(
                            imageUrl: item.imageUrl,
                            fit: BoxFit.cover,
                          ),
                    Positioned(
                      bottom: 6,
                      left: 6,
                      child: Material(
                        color: AppTheme.brandMaroon,
                        shape: const CircleBorder(),
                        elevation: 2,
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: onAdd,
                          child: Padding(
                            padding: EdgeInsets.all(compact ? 5 : 7),
                            child: Icon(
                              Icons.add,
                              color: Colors.white,
                              size: compact ? 16 : 20,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  compact ? 8 : 10,
                  compact ? 6 : 8,
                  compact ? 8 : 10,
                  compact ? 7 : 9,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        height: 1.2,
                        fontSize: compact ? 12 : 13.5,
                      ),
                    ),
                    if (showDescription) ...[
                      const SizedBox(height: 3),
                      Text(
                        item.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF64748B),
                          height: 1.25,
                        ),
                      ),
                    ],
                    const SizedBox(height: 4),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(
                        '${item.price.toStringAsFixed(3)} د.ك',
                        maxLines: 1,
                        style: TextStyle(
                          color: AppTheme.brandMaroon,
                          fontWeight: FontWeight.w800,
                          fontSize: compact ? 12.5 : 14,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
