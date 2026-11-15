import 'package:flutter/material.dart';

import '../models/restaurant.dart';
import '../models/restaurant_settings.dart';
import '../services/api_service.dart';
import '../widgets/link_hub/link_hub_view.dart';

/// Public link-in-bio hub at `/r/{slug}/links`.
class RestaurantLinkHubScreen extends StatefulWidget {
  const RestaurantLinkHubScreen({super.key, required this.slug});

  final String slug;

  @override
  State<RestaurantLinkHubScreen> createState() =>
      _RestaurantLinkHubScreenState();
}

class _RestaurantLinkHubScreenState extends State<RestaurantLinkHubScreen> {
  Restaurant? _restaurant;
  RestaurantSettings? _settings;
  Object? _error;
  var _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final restaurant = await ApiService.instance.fetchPublicRestaurant(
        slug: widget.slug,
      );
      final settings = await ApiService.instance.fetchSettings(
        restaurantId: restaurant.id,
      );
      if (!mounted) return;
      setState(() {
        _restaurant = restaurant;
        _settings = settings;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final restaurant = _restaurant;
    final settings = _settings;
    final bg = linkHubParseColor(
      settings?.linkHub.backgroundColor ?? '#0F0F10',
    );

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: bg,
        body: _loading
            ? Center(
                child: CircularProgressIndicator(
                  color: linkHubParseColor(
                    settings?.linkHub.accentColor ?? '#FF6B00',
                    fallback: const Color(0xFFFF6B00),
                  ),
                ),
              )
            : _error != null || restaurant == null || settings == null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.link_off_rounded,
                              color: Colors.white54, size: 40),
                          const SizedBox(height: 12),
                          Text(
                            _error?.toString() ?? 'المطعم غير موجود',
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white70),
                          ),
                          const SizedBox(height: 16),
                          FilledButton(
                            onPressed: _load,
                            child: const Text('إعادة المحاولة'),
                          ),
                        ],
                      ),
                    ),
                  )
                : SafeArea(
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 480),
                        child: LinkHubView(
                          restaurantName: restaurant.name,
                          slug: restaurant.slug.isNotEmpty
                              ? restaurant.slug
                              : widget.slug,
                          logoUrl: settings.logoUrl,
                          description: settings.restaurantDescription,
                          hub: settings.linkHub,
                          whatsappNumber: settings.fullWhatsappNumber,
                          restaurantPhone: restaurant.phone,
                        ),
                      ),
                    ),
                  ),
      ),
    );
  }
}
