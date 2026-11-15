/// Link-in-bio hub configuration stored inside [RestaurantSettings].
class LinkHubConfig {
  const LinkHubConfig({
    this.displayName = '',
    this.tagline = '',
    this.accentColor = '#FF6B00',
    this.backgroundColor = '#0F0F10',
    this.surfaceColor = '#1A1A1C',
    this.textColor = '#FFFFFF',
    this.showMenuCta = true,
    this.showWhatsapp = true,
    this.showCall = true,
    this.showAppStore = false,
    this.showPlayStore = false,
    this.appStoreUrl = '',
    this.playStoreUrl = '',
    this.phoneOverride = '',
    this.customLinks = const [],
    this.branches = const [],
    this.social = const LinkHubSocial(),
  });

  /// Optional title on the hub page (falls back to restaurant.name).
  final String displayName;
  final String tagline;
  final String accentColor;
  final String backgroundColor;
  final String surfaceColor;
  /// Primary text color for titles, bios, and button labels.
  final String textColor;
  final bool showMenuCta;
  final bool showWhatsapp;
  final bool showCall;
  final bool showAppStore;
  final bool showPlayStore;
  final String appStoreUrl;
  final String playStoreUrl;
  /// Optional phone for Call Us (falls back to restaurant / WhatsApp).
  final String phoneOverride;
  final List<LinkHubCustomLink> customLinks;
  final List<LinkHubBranch> branches;
  final LinkHubSocial social;

  factory LinkHubConfig.defaults() => const LinkHubConfig();

  factory LinkHubConfig.fromJson(Map<String, dynamic>? json) {
    if (json == null || json.isEmpty) return LinkHubConfig.defaults();
    final linksRaw = json['customLinks'] ?? json['custom_links'];
    final branchesRaw = json['branches'];
    final socialRaw = json['social'];
    return LinkHubConfig(
      displayName: json['displayName']?.toString() ??
          json['display_name']?.toString() ??
          json['title']?.toString() ??
          '',
      tagline: json['tagline']?.toString() ??
          json['bio']?.toString() ??
          '',
      accentColor: _hexOr(
        json['accentColor'] ?? json['accent_color'],
        '#FF6B00',
      ),
      backgroundColor: _hexOr(
        json['backgroundColor'] ?? json['background_color'],
        '#0F0F10',
      ),
      surfaceColor: _hexOr(
        json['surfaceColor'] ?? json['surface_color'],
        '#1A1A1C',
      ),
      textColor: _hexOr(
        json['textColor'] ?? json['text_color'],
        '#FFFFFF',
      ),
      showMenuCta: json['showMenuCta'] != false && json['show_menu_cta'] != false,
      showWhatsapp:
          json['showWhatsapp'] != false && json['show_whatsapp'] != false,
      showCall: json['showCall'] != false && json['show_call'] != false,
      showAppStore:
          json['showAppStore'] == true || json['show_app_store'] == true,
      showPlayStore:
          json['showPlayStore'] == true || json['show_play_store'] == true,
      appStoreUrl: json['appStoreUrl']?.toString() ??
          json['app_store_url']?.toString() ??
          '',
      playStoreUrl: json['playStoreUrl']?.toString() ??
          json['play_store_url']?.toString() ??
          '',
      phoneOverride: json['phoneOverride']?.toString() ??
          json['phone_override']?.toString() ??
          json['phone']?.toString() ??
          '',
      customLinks: _parseLinks(linksRaw),
      branches: _parseBranches(branchesRaw),
      social: LinkHubSocial.fromJson(
        socialRaw is Map ? Map<String, dynamic>.from(socialRaw) : null,
      ),
    );
  }

  LinkHubConfig copyWith({
    String? displayName,
    String? tagline,
    String? accentColor,
    String? backgroundColor,
    String? surfaceColor,
    String? textColor,
    bool? showMenuCta,
    bool? showWhatsapp,
    bool? showCall,
    bool? showAppStore,
    bool? showPlayStore,
    String? appStoreUrl,
    String? playStoreUrl,
    String? phoneOverride,
    List<LinkHubCustomLink>? customLinks,
    List<LinkHubBranch>? branches,
    LinkHubSocial? social,
  }) {
    return LinkHubConfig(
      displayName: displayName ?? this.displayName,
      tagline: tagline ?? this.tagline,
      accentColor: accentColor ?? this.accentColor,
      backgroundColor: backgroundColor ?? this.backgroundColor,
      surfaceColor: surfaceColor ?? this.surfaceColor,
      textColor: textColor ?? this.textColor,
      showMenuCta: showMenuCta ?? this.showMenuCta,
      showWhatsapp: showWhatsapp ?? this.showWhatsapp,
      showCall: showCall ?? this.showCall,
      showAppStore: showAppStore ?? this.showAppStore,
      showPlayStore: showPlayStore ?? this.showPlayStore,
      appStoreUrl: appStoreUrl ?? this.appStoreUrl,
      playStoreUrl: playStoreUrl ?? this.playStoreUrl,
      phoneOverride: phoneOverride ?? this.phoneOverride,
      customLinks: customLinks ?? this.customLinks,
      branches: branches ?? this.branches,
      social: social ?? this.social,
    );
  }

  Map<String, dynamic> toJson() => {
        'displayName': displayName,
        'tagline': tagline,
        'accentColor': accentColor,
        'backgroundColor': backgroundColor,
        'surfaceColor': surfaceColor,
        'textColor': textColor,
        'showMenuCta': showMenuCta,
        'showWhatsapp': showWhatsapp,
        'showCall': showCall,
        'showAppStore': showAppStore,
        'showPlayStore': showPlayStore,
        'appStoreUrl': appStoreUrl,
        'playStoreUrl': playStoreUrl,
        'phoneOverride': phoneOverride,
        'customLinks': customLinks.map((e) => e.toJson()).toList(),
        'branches': branches.map((e) => e.toJson()).toList(),
        'social': social.toJson(),
      };

  static String _hexOr(dynamic raw, String fallback) {
    final value = raw?.toString().trim() ?? '';
    if (value.isEmpty) return fallback;
    if (RegExp(r'^#?[0-9A-Fa-f]{6}$').hasMatch(value)) {
      return value.startsWith('#') ? value : '#$value';
    }
    return fallback;
  }

  static List<LinkHubCustomLink> _parseLinks(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => LinkHubCustomLink.fromJson(Map<String, dynamic>.from(e)))
        .where((e) => e.id.isNotEmpty)
        .toList();
  }

  static List<LinkHubBranch> _parseBranches(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => LinkHubBranch.fromJson(Map<String, dynamic>.from(e)))
        .where((e) => e.id.isNotEmpty)
        .toList();
  }
}

class LinkHubCustomLink {
  const LinkHubCustomLink({
    required this.id,
    required this.title,
    required this.url,
    this.visible = true,
    this.icon = 'link',
  });

  final String id;
  final String title;
  final String url;
  final bool visible;
  final String icon;

  factory LinkHubCustomLink.fromJson(Map<String, dynamic> json) {
    return LinkHubCustomLink(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? json['label']?.toString() ?? '',
      url: json['url']?.toString() ?? '',
      visible: json['visible'] != false,
      icon: json['icon']?.toString() ?? 'link',
    );
  }

  LinkHubCustomLink copyWith({
    String? id,
    String? title,
    String? url,
    bool? visible,
    String? icon,
  }) {
    return LinkHubCustomLink(
      id: id ?? this.id,
      title: title ?? this.title,
      url: url ?? this.url,
      visible: visible ?? this.visible,
      icon: icon ?? this.icon,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'url': url,
        'visible': visible,
        'icon': icon,
      };
}

class LinkHubBranch {
  const LinkHubBranch({
    required this.id,
    required this.name,
    this.address = '',
    this.mapsUrl = '',
    this.phone = '',
    this.visible = true,
  });

  final String id;
  final String name;
  final String address;
  final String mapsUrl;
  final String phone;
  final bool visible;

  factory LinkHubBranch.fromJson(Map<String, dynamic> json) {
    return LinkHubBranch(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      address: json['address']?.toString() ?? '',
      mapsUrl: json['mapsUrl']?.toString() ??
          json['maps_url']?.toString() ??
          '',
      phone: json['phone']?.toString() ?? '',
      visible: json['visible'] != false,
    );
  }

  LinkHubBranch copyWith({
    String? id,
    String? name,
    String? address,
    String? mapsUrl,
    String? phone,
    bool? visible,
  }) {
    return LinkHubBranch(
      id: id ?? this.id,
      name: name ?? this.name,
      address: address ?? this.address,
      mapsUrl: mapsUrl ?? this.mapsUrl,
      phone: phone ?? this.phone,
      visible: visible ?? this.visible,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'address': address,
        'mapsUrl': mapsUrl,
        'phone': phone,
        'visible': visible,
      };
}

class LinkHubSocial {
  const LinkHubSocial({
    this.instagram = '',
    this.tiktok = '',
    this.snapchat = '',
    this.facebook = '',
    this.website = '',
  });

  final String instagram;
  final String tiktok;
  final String snapchat;
  final String facebook;
  final String website;

  bool get hasAny =>
      instagram.trim().isNotEmpty ||
      tiktok.trim().isNotEmpty ||
      snapchat.trim().isNotEmpty ||
      facebook.trim().isNotEmpty ||
      website.trim().isNotEmpty;

  factory LinkHubSocial.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const LinkHubSocial();
    return LinkHubSocial(
      instagram: json['instagram']?.toString() ?? '',
      tiktok: json['tiktok']?.toString() ?? '',
      snapchat: json['snapchat']?.toString() ?? '',
      facebook: json['facebook']?.toString() ?? '',
      website: json['website']?.toString() ??
          json['web']?.toString() ??
          '',
    );
  }

  LinkHubSocial copyWith({
    String? instagram,
    String? tiktok,
    String? snapchat,
    String? facebook,
    String? website,
  }) {
    return LinkHubSocial(
      instagram: instagram ?? this.instagram,
      tiktok: tiktok ?? this.tiktok,
      snapchat: snapchat ?? this.snapchat,
      facebook: facebook ?? this.facebook,
      website: website ?? this.website,
    );
  }

  Map<String, dynamic> toJson() => {
        'instagram': instagram,
        'tiktok': tiktok,
        'snapchat': snapchat,
        'facebook': facebook,
        'website': website,
      };
}
