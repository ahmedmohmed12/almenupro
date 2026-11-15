import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/link_hub_config.dart';
import '../../utils/image_url.dart';
import '../../utils/restaurant_route.dart';
import '../../utils/whatsapp_phone.dart';
import '../network_menu_image.dart';

Color linkHubParseColor(String hex, {Color fallback = const Color(0xFF0F0F10)}) {
  final raw = hex.trim().replaceFirst('#', '');
  if (raw.length != 6) return fallback;
  final value = int.tryParse(raw, radix: 16);
  if (value == null) return fallback;
  return Color(0xFF000000 | value);
}

/// Shared customer + admin-preview link-in-bio layout.
class LinkHubView extends StatelessWidget {
  const LinkHubView({
    super.key,
    required this.restaurantName,
    required this.slug,
    required this.logoUrl,
    required this.description,
    required this.hub,
    required this.whatsappNumber,
    this.restaurantPhone = '',
    this.compact = false,
    this.onOpenMenu,
  });

  final String restaurantName;
  final String slug;
  final String logoUrl;
  final String description;
  final LinkHubConfig hub;
  final String whatsappNumber;
  final String restaurantPhone;
  final bool compact;
  final VoidCallback? onOpenMenu;

  String get _title {
    final custom = hub.displayName.trim();
    if (custom.isNotEmpty) return custom;
    return restaurantName.trim().isNotEmpty ? restaurantName.trim() : 'المطعم';
  }

  String get _bio {
    final tag = hub.tagline.trim();
    if (tag.isNotEmpty) return tag;
    return description.trim();
  }

  String get _phoneDigits {
    final override = WhatsAppPhone.digitsOnly(hub.phoneOverride);
    if (override.isNotEmpty) return override;
    final rest = WhatsAppPhone.digitsOnly(restaurantPhone);
    if (rest.isNotEmpty) return rest;
    return WhatsAppPhone.digitsOnly(whatsappNumber);
  }

  Future<void> _open(String url) async {
    final uri = Uri.tryParse(url.trim());
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _openMenu(BuildContext context) async {
    if (onOpenMenu != null) {
      onOpenMenu!();
      return;
    }
    final path = RestaurantRoute.menuPathForSlug(slug);
    Navigator.of(context).pushNamed(path);
  }

  @override
  Widget build(BuildContext context) {
    final bg = linkHubParseColor(hub.backgroundColor);
    final surface = linkHubParseColor(
      hub.surfaceColor,
      fallback: const Color(0xFF1A1A1C),
    );
    final accent = linkHubParseColor(
      hub.accentColor,
      fallback: const Color(0xFFFF6B00),
    );
    final text = linkHubParseColor(
      hub.textColor,
      fallback: Colors.white,
    );
    final muted = text.withValues(alpha: 0.72);
    final faint = text.withValues(alpha: 0.38);
    final pad = compact ? 16.0 : 22.0;
    final visibleLinks = hub.customLinks.where((l) => l.visible).toList();
    final visibleBranches = hub.branches.where((b) => b.visible).toList();

    return ColoredBox(
      color: bg,
      child: ListView(
        padding: EdgeInsets.fromLTRB(pad, compact ? 20 : 36, pad, 40),
        children: [
          _Header(
            name: _title,
            bio: _bio,
            logoUrl: logoUrl,
            accent: accent,
            surface: surface,
            text: text,
            muted: muted,
            compact: compact,
          ),
          const SizedBox(height: 22),
          if (hub.showMenuCta) ...[
            _HubButton(
              label: 'المنيو أونلاين / Order Menu',
              icon: Icons.restaurant_menu_rounded,
              filled: true,
              accent: accent,
              surface: surface,
              text: text,
              onTap: () => _openMenu(context),
            ),
            const SizedBox(height: 10),
          ],
          if (hub.showWhatsapp && whatsappNumber.trim().isNotEmpty) ...[
            _HubButton(
              label: 'واتساب / WhatsApp',
              icon: Icons.chat_rounded,
              filled: false,
              accent: accent,
              surface: surface,
              text: text,
              onTap: () => _open('https://wa.me/${WhatsAppPhone.digitsOnly(whatsappNumber)}'),
            ),
            const SizedBox(height: 10),
          ],
          if (hub.showCall && _phoneDigits.isNotEmpty) ...[
            _HubButton(
              label: 'اتصل بنا / Call Us',
              icon: Icons.call_rounded,
              filled: false,
              accent: accent,
              surface: surface,
              text: text,
              onTap: () => _open('tel:$_phoneDigits'),
            ),
            const SizedBox(height: 10),
          ],
          if (hub.showAppStore && hub.appStoreUrl.trim().isNotEmpty) ...[
            _HubButton(
              label: 'App Store',
              icon: Icons.apple,
              filled: false,
              accent: accent,
              surface: surface,
              text: text,
              onTap: () => _open(hub.appStoreUrl),
            ),
            const SizedBox(height: 10),
          ],
          if (hub.showPlayStore && hub.playStoreUrl.trim().isNotEmpty) ...[
            _HubButton(
              label: 'Google Play',
              icon: Icons.shop_rounded,
              filled: false,
              accent: accent,
              surface: surface,
              text: text,
              onTap: () => _open(hub.playStoreUrl),
            ),
            const SizedBox(height: 10),
          ],
          for (final link in visibleLinks) ...[
            _HubButton(
              label: link.title.isEmpty ? link.url : link.title,
              icon: Icons.link_rounded,
              filled: false,
              accent: accent,
              surface: surface,
              text: text,
              onTap: () => _open(link.url),
            ),
            const SizedBox(height: 10),
          ],
          if (visibleBranches.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'الفروع / Branches',
              style: TextStyle(
                color: muted,
                fontWeight: FontWeight.w800,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 8),
            ...visibleBranches.map(
              (branch) => _BranchTile(
                branch: branch,
                surface: surface,
                accent: accent,
                text: text,
                muted: muted,
                onMaps: branch.mapsUrl.trim().isEmpty
                    ? null
                    : () => _open(branch.mapsUrl),
                onCall: branch.phone.trim().isEmpty
                    ? null
                    : () => _open(
                          'tel:${WhatsAppPhone.digitsOnly(branch.phone)}',
                        ),
              ),
            ),
          ],
          if (hub.social.hasAny) ...[
            const SizedBox(height: 22),
            _SocialRow(social: hub.social, accent: accent, onOpen: _open),
          ],
          const SizedBox(height: 28),
          Text(
            'Powered by AlMenuPro',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: faint,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.name,
    required this.bio,
    required this.logoUrl,
    required this.accent,
    required this.surface,
    required this.text,
    required this.muted,
    required this.compact,
  });

  final String name;
  final String bio;
  final String logoUrl;
  final Color accent;
  final Color surface;
  final Color text;
  final Color muted;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final size = compact ? 72.0 : 96.0;
    final resolvedLogo = resolveImageUrl(logoUrl);
    return Column(
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: surface,
            border: Border.all(color: accent.withValues(alpha: 0.85), width: 2.5),
            boxShadow: [
              BoxShadow(
                color: accent.withValues(alpha: 0.28),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: resolvedLogo.isEmpty
              ? Icon(Icons.storefront_rounded, color: accent, size: size * 0.42)
              : NetworkMenuImage(
                  imageUrl: resolvedLogo,
                  width: size,
                  height: size,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Icon(
                    Icons.storefront_rounded,
                    color: accent,
                    size: size * 0.42,
                  ),
                ),
        ),
        const SizedBox(height: 16),
        Text(
          name,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: text,
            fontWeight: FontWeight.w900,
            fontSize: compact ? 22 : 26,
            height: 1.15,
          ),
        ),
        if (bio.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            bio,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: muted,
              fontSize: compact ? 13 : 14.5,
              height: 1.4,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ],
    );
  }
}

class _HubButton extends StatelessWidget {
  const _HubButton({
    required this.label,
    required this.icon,
    required this.filled,
    required this.accent,
    required this.surface,
    required this.text,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool filled;
  final Color accent;
  final Color surface;
  final Color text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = filled ? Colors.white : text;
    return Material(
      color: filled ? accent : surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: 52),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: filled
                ? null
                : Border.all(color: text.withValues(alpha: 0.12)),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                color: filled ? Colors.white : accent,
                size: 22,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: fg.withValues(alpha: filled ? 1 : 0.95),
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
              ),
              Icon(
                Icons.chevron_left_rounded,
                color: fg.withValues(alpha: 0.45),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BranchTile extends StatelessWidget {
  const _BranchTile({
    required this.branch,
    required this.surface,
    required this.accent,
    required this.text,
    required this.muted,
    this.onMaps,
    this.onCall,
  });

  final LinkHubBranch branch;
  final Color surface;
  final Color accent;
  final Color text;
  final Color muted;
  final VoidCallback? onMaps;
  final VoidCallback? onCall;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: text.withValues(alpha: 0.08)),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 14),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
          iconColor: accent,
          collapsedIconColor: muted,
          title: Text(
            branch.name,
            style: TextStyle(
              color: text,
              fontWeight: FontWeight.w800,
              fontSize: 14.5,
            ),
          ),
          subtitle: branch.address.trim().isEmpty
              ? null
              : Text(
                  branch.address,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: muted,
                    fontSize: 12,
                  ),
                ),
          children: [
            if (branch.address.trim().isNotEmpty)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  branch.address,
                  style: TextStyle(
                    color: muted,
                    height: 1.35,
                  ),
                ),
              ),
            const SizedBox(height: 10),
            Row(
              children: [
                if (onMaps != null)
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onMaps,
                      icon: const Icon(Icons.map_rounded, size: 18),
                      label: const Text('Google Maps'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: accent,
                        side: BorderSide(color: accent.withValues(alpha: 0.5)),
                      ),
                    ),
                  ),
                if (onMaps != null && onCall != null) const SizedBox(width: 8),
                if (onCall != null)
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onCall,
                      icon: const Icon(Icons.call_rounded, size: 18),
                      label: const Text('اتصال'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: text,
                        side: BorderSide(
                          color: text.withValues(alpha: 0.25),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SocialRow extends StatelessWidget {
  const _SocialRow({
    required this.social,
    required this.accent,
    required this.onOpen,
  });

  final LinkHubSocial social;
  final Color accent;
  final Future<void> Function(String url) onOpen;

  String? _normalize(String raw, {required String hostHint}) {
    final value = raw.trim();
    if (value.isEmpty) return null;
    if (value.startsWith('http://') || value.startsWith('https://')) {
      return value;
    }
    if (value.startsWith('@')) {
      return 'https://$hostHint/${value.substring(1)}';
    }
    if (value.contains('.')) return 'https://$value';
    return 'https://$hostHint/$value';
  }

  @override
  Widget build(BuildContext context) {
    final items = <({IconData icon, String? url})>[
      (
        icon: Icons.camera_alt_outlined,
        url: _normalize(social.instagram, hostHint: 'instagram.com'),
      ),
      (
        icon: Icons.music_note_rounded,
        url: _normalize(social.tiktok, hostHint: 'www.tiktok.com/@'),
      ),
      (
        icon: Icons.photo_camera_front_outlined,
        url: _normalize(social.snapchat, hostHint: 'www.snapchat.com/add'),
      ),
      (
        icon: Icons.facebook_rounded,
        url: _normalize(social.facebook, hostHint: 'facebook.com'),
      ),
      (
        icon: Icons.language_rounded,
        url: _normalize(social.website, hostHint: ''),
      ),
    ].where((e) => (e.url ?? '').isNotEmpty).toList();

    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final item in items)
          Material(
            color: accent.withValues(alpha: 0.15),
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () => onOpen(item.url!),
              child: SizedBox(
                width: 46,
                height: 46,
                child: Icon(item.icon, color: accent, size: 22),
              ),
            ),
          ),
      ],
    );
  }
}
