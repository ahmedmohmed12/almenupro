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
        final bannerHeight = desktop ? 176.0 : compact ? 108.0 : 136.0;
        final logoSize = desktop ? 72.0 : compact ? 52.0 : 58.0;
        final titleSize = desktop ? 24.0 : compact ? 16.0 : 18.0;
        final horizontal = desktop ? 28.0 : 16.0;

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
                      padding: EdgeInsets.fromLTRB(horizontal, 16, 16, 0),
                      child: Icon(
                        Icons.cookie,
                        color: Colors.white24,
                        size: desktop ? 96 : 64,
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    horizontal,
                    bannerHeight - (compact ? 36 : 48),
                    horizontal,
                    0,
                  ),
                  child: Material(
                    color: Colors.white,
                    elevation: 6,
                    shadowColor: Colors.black26,
                    borderRadius: BorderRadius.circular(18),
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        compact ? 12 : 14,
                        compact ? 12 : 14,
                        compact ? 12 : 14,
                        compact ? 10 : 12,
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
                                const SizedBox(height: 10),
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
                                      const SizedBox(height: 8),
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
              padding: EdgeInsets.fromLTRB(horizontal, 12, horizontal, 0),
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
        const SizedBox(height: 4),
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
      padding: EdgeInsets.all(compact ? 12 : 14),
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
  });

  final MenuItem item;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 180;
        final imageHeight = (constraints.maxHeight * 0.56).clamp(96.0, 240.0);

        return Material(
          color: Colors.white,
          elevation: 2,
          shadowColor: Colors.black12,
          borderRadius: BorderRadius.circular(18),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: imageHeight,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    item.imageUrl.trim().isEmpty
                        ? const ColoredBox(
                            color: Color(0xFFFFF4E5),
                            child: Icon(Icons.cookie_outlined, size: 42),
                          )
                        : NetworkMenuImage(
                            imageUrl: item.imageUrl,
                            fit: BoxFit.cover,
                          ),
                    Positioned(
                      bottom: 8,
                      left: 8,
                      child: Material(
                        color: AppTheme.brandMaroon,
                        shape: const CircleBorder(),
                        elevation: 3,
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: onAdd,
                          child: Padding(
                            padding: EdgeInsets.all(compact ? 6 : 8),
                            child: Icon(
                              Icons.add,
                              color: Colors.white,
                              size: compact ? 18 : 22,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    compact ? 8 : 12,
                    8,
                    compact ? 8 : 12,
                    compact ? 8 : 12,
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
                          fontSize: compact ? 13 : 14,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Expanded(
                        child: Text(
                          item.description.isEmpty
                              ? 'اختيار شهي من المنيو'
                              : item.description,
                          maxLines: compact ? 2 : 3,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF64748B),
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: AlignmentDirectional.centerStart,
                        child: Text(
                          '${item.price.toStringAsFixed(3)} د.ك',
                          style: const TextStyle(
                            color: AppTheme.brandMaroon,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
