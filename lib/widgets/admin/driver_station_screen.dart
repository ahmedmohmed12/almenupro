import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../driver/driver_brand.dart';
import '../../driver/driver_mobile.dart';
import '../../l10n/app_strings.dart';
import '../../models/delivery_dispatch.dart';
import '../../services/admin_auth_service.dart';
import '../../services/api_service.dart';
import '../../services/delivery_dispatch_service.dart';
import '../../utils/maps_launcher.dart';
import '../language_toggle_button.dart';
import 'driver_handshake_banners.dart';
import 'scheduled_orders_page.dart';

String _driverStatusLabel(AppStrings strings, DeliveryDispatchRequest request) {
  switch (request.status) {
    case 'accepted':
      final name = request.assignedDriverName;
      return name == null || name.isEmpty
          ? strings.tr('تم القبول', 'Accepted')
          : strings.tr('قبله $name', 'Accepted by $name');
    case 'picked_up':
      return strings.tr('تم الاستلام', 'Picked up');
    case 'on_the_way':
      return strings.tr('في الطريق للعميل', 'On the way to customer');
    case 'delivered':
      return strings.tr('تم التوصيل', 'Delivered');
    case 'rejected_by_all':
      return strings.tr('لا يوجد سائق', 'No driver available');
    case 'cancelled':
      return strings.tr('ملغى', 'Cancelled');
    default:
      return strings.tr('جاري البحث عن سائق', 'Searching for a driver');
  }
}

class DriverStationScreen extends StatefulWidget {
  const DriverStationScreen({super.key, this.onLogout});

  final VoidCallback? onLogout;

  @override
  State<DriverStationScreen> createState() => _DriverStationScreenState();
}

class _DriverStationScreenState extends State<DriverStationScreen> {
  late final DriverSessionController _session;
  Timer? _clock;
  var _tracking = false;
  var _tab = 1;

  @override
  void initState() {
    super.initState();
    _session = DriverSessionController();
    _session.addListener(_onSession);
    _session.start();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_session.incoming.isNotEmpty) setState(() {});
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    _session.removeListener(_onSession);
    _session.dispose();
    super.dispose();
  }

  void _onSession() {
    if (!mounted) return;
    if (_session.consumeBeep()) {
      SystemSound.play(SystemSoundType.alert);
      if (_tab != 1) setState(() => _tab = 1);
      final offer = _session.incoming.isNotEmpty
          ? _session.incoming.first
          : null;
      if (offer != null) {
        unawaited(playDriverIncomingAlert());
        unawaited(
          alertIncomingDriverJob({
            'type': 'driver_job',
            'request_id': offer.id,
            'driver_fee': offer.driverFee.toStringAsFixed(3),
            'region_name': offer.regionName,
            'restaurantName': offer.restaurantName,
          }),
        );
      }
    } else if (_session.incoming.isEmpty) {
      unawaited(stopDriverIncomingAlert());
    }
    unawaited(_syncTracking());
    setState(() {});
  }

  Future<void> _syncTracking() async {
    final driver = _session.driver;
    final token = AdminAuthService.instance.token;
    if (_session.online &&
        driver != null &&
        token != null &&
        token.isNotEmpty) {
      unawaited(registerDriverFcmToken(driver.id));
      await startDriverLocationTracking(
        driverId: driver.id,
        authToken: token,
        apiBaseUrl: ApiService.baseUrl,
        assignedRegions: driver.assignedRegions,
      );
      _tracking = true;
      return;
    }
    if (!_tracking) return;
    _tracking = false;
    await stopDriverLocationTracking();
  }

  int _secondsLeft(DeliveryDispatchRequest request) {
    final expires = request.offerExpiresAt;
    if (expires == null) return 45;
    final left = expires.difference(DateTime.now()).inSeconds;
    return left < 0 ? 0 : left;
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final offer = _session.incoming.isNotEmpty ? _session.incoming.first : null;
    final ordersBadge =
        (_session.active != null ? 1 : 0) + _session.incoming.length;

    return Scaffold(
      backgroundColor: DriverBrand.canvas,
      body: Column(
        children: [
          _DriverHeroHeader(
            driver: _session.driver,
            online: _session.online,
            onLogout: widget.onLogout,
          ),
          const ScheduledDriverBanner(),
          Expanded(
            child: _session.loading
                ? const Center(
                    child: CircularProgressIndicator(color: DriverBrand.orange),
                  )
                : _session.error != null
                ? _DriverErrorState(
                    message: _session.error!,
                    onRetry: _session.refresh,
                  )
                : IndexedStack(
                    index: _tab,
                    children: [
                      _AreasTab(
                        driver: _session.driver,
                        online: _session.online,
                        regionLabel: _session.regionLabel,
                        onToggleOnline: (value) => _session.setOnline(value),
                      ),
                      _OrdersTab(
                        offer: offer,
                        active: _session.active,
                        online: _session.online,
                        secondsLeft: offer == null ? 0 : _secondsLeft(offer),
                        regionLabel: _session.regionLabel,
                        onAccept: () => _session.act('accept'),
                        onDecline: () => _session.act('decline'),
                        onPickup: () => _session.act('pickup'),
                        onEnRoute: () => _session.act('on_the_way'),
                        onDeliver: () => _session.act('deliver'),
                        onCancel: () => _session.act('cancel'),
                        onGoOnline: () => _session.setOnline(true),
                      ),
                      _ProfileTab(
                        driver: _session.driver,
                        online: _session.online,
                        onLogout: widget.onLogout,
                      ),
                      _HistoryTab(
                        history: _session.history,
                        regionLabel: _session.regionLabel,
                      ),
                    ],
                  ),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (index) => setState(() => _tab = index),
        backgroundColor: Colors.white,
        indicatorColor: DriverBrand.orange.withValues(alpha: 0.16),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.map_outlined),
            selectedIcon: const Icon(Icons.map, color: DriverBrand.orange),
            label: strings.tr('المناطق', 'Areas'),
          ),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: ordersBadge > 0,
              label: Text('$ordersBadge'),
              child: const Icon(Icons.delivery_dining_outlined),
            ),
            selectedIcon: Badge(
              isLabelVisible: ordersBadge > 0,
              label: Text('$ordersBadge'),
              child: const Icon(
                Icons.delivery_dining,
                color: DriverBrand.orange,
              ),
            ),
            label: strings.tr('الاستلام', 'Orders'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.person_outline),
            selectedIcon: const Icon(Icons.person, color: DriverBrand.orange),
            label: strings.tr('بياناتي', 'Profile'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.history),
            selectedIcon: const Icon(Icons.history, color: DriverBrand.orange),
            label: strings.tr('السابقة', 'History'),
          ),
        ],
      ),
    );
  }
}

class _DriverHeroHeader extends StatelessWidget {
  const _DriverHeroHeader({
    required this.driver,
    required this.online,
    this.onLogout,
  });

  final DeliveryDriver? driver;
  final bool online;
  final VoidCallback? onLogout;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        16,
        MediaQuery.paddingOf(context).top + 8,
        8,
        18,
      ),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [DriverBrand.orange, DriverBrand.orangeDeep],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const MenuProLogo(height: 36),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  driver?.name.isNotEmpty == true
                      ? driver!.name
                      : strings.tr('سائق المنيو برو', 'AlMenuPro Driver'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  online
                      ? strings.tr(
                          'متصل — جاهز للطلبات',
                          'Online — ready for orders',
                        )
                      : strings.tr('غير متصل', 'Offline'),
                  style: TextStyle(
                    color: online ? const Color(0xFFFFF3C4) : Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const LanguageToggleButton(
            compact: true,
            foregroundColor: Colors.white,
          ),
          if (onLogout != null)
            IconButton(
              onPressed: onLogout,
              icon: const Icon(Icons.logout, color: Colors.white),
            ),
        ],
      ),
    );
  }
}

class _DriverErrorState extends StatelessWidget {
  const _DriverErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: DriverBrand.orange,
              ),
              onPressed: onRetry,
              child: Text(strings.tr('إعادة المحاولة', 'Try again')),
            ),
          ],
        ),
      ),
    );
  }
}

class _AreasTab extends StatelessWidget {
  const _AreasTab({
    required this.driver,
    required this.online,
    required this.regionLabel,
    required this.onToggleOnline,
  });

  final DeliveryDriver? driver;
  final bool online;
  final String Function(String id, [String fallback]) regionLabel;
  final ValueChanged<bool> onToggleOnline;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final regions = driver?.activeRegionIds ?? const <String>[];
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        _OnlineToggleCard(online: online, onToggleOnline: onToggleOnline),
        const SizedBox(height: 18),
        Text(
          strings.tr('مناطق التوصيل المفعّلة', 'Active delivery areas'),
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 6),
        Text(
          strings.tr(
            'يصلك الطلب فقط داخل هذه المناطق. التعديل من لوحة الأدمن.',
            'You only receive orders in these areas. The admin manages them.',
          ),
          style: const TextStyle(color: DriverBrand.muted, height: 1.4),
        ),
        const SizedBox(height: 14),
        if (regions.isEmpty)
          _EmptyHint(
            icon: Icons.location_off_outlined,
            text: strings.tr(
              'لا توجد مناطق مفعّلة. لن تصلك طلبات حتى يفعّلها الأدمن.',
              'No active areas. You will not receive orders until the admin enables one.',
            ),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final region in regions)
                Chip(
                  avatar: const Icon(
                    Icons.place,
                    size: 16,
                    color: DriverBrand.orange,
                  ),
                  label: Text(regionLabel(region)),
                  backgroundColor: Colors.white,
                  side: const BorderSide(color: Color(0xFFFFD8B8)),
                ),
            ],
          ),
      ],
    );
  }
}

class _OnlineToggleCard extends StatelessWidget {
  const _OnlineToggleCard({required this.online, required this.onToggleOnline});

  final bool online;
  final ValueChanged<bool> onToggleOnline;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return Material(
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: online ? const Color(0xFFBBF7D0) : const Color(0xFFFFE0C2),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              online
                  ? strings.tr(
                      'أنت ظاهر للطلبات الآن',
                      'You are available for orders',
                    )
                  : strings.tr('أنت غير متصل', 'You are offline'),
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
            const SizedBox(height: 12),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: online
                    ? const Color(0xFF16A34A)
                    : DriverBrand.orange,
                minimumSize: const Size.fromHeight(52),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              onPressed: () => onToggleOnline(!online),
              child: Text(
                online
                    ? strings.tr(
                        'متصل — اضغط لإيقاف الاستقبال',
                        'Online — tap to stop receiving orders',
                      )
                    : strings.tr(
                        'اضغط للاتصال واستقبال الطلبات',
                        'Tap to go online and receive orders',
                      ),
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OrdersTab extends StatelessWidget {
  const _OrdersTab({
    required this.offer,
    required this.active,
    required this.online,
    required this.secondsLeft,
    required this.regionLabel,
    required this.onAccept,
    required this.onDecline,
    required this.onPickup,
    required this.onEnRoute,
    required this.onDeliver,
    required this.onCancel,
    required this.onGoOnline,
  });

  final DeliveryDispatchRequest? offer;
  final DeliveryDispatchRequest? active;
  final bool online;
  final int secondsLeft;
  final String Function(String id, [String fallback]) regionLabel;
  final VoidCallback onAccept;
  final VoidCallback onDecline;
  final VoidCallback onPickup;
  final VoidCallback onEnRoute;
  final VoidCallback onDeliver;
  final VoidCallback onCancel;
  final VoidCallback onGoOnline;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    if (offer != null && active == null) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _IncomingCard(
            request: offer!,
            seconds: secondsLeft,
            regionLabel: regionLabel,
            onAccept: onAccept,
            onDecline: onDecline,
          ),
        ],
      );
    }
    if (active != null) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _ActiveTripCard(
            request: active!,
            regionLabel: regionLabel,
            onPickup: onPickup,
            onEnRoute: onEnRoute,
            onDeliver: onDeliver,
            onCancel: onCancel,
          ),
        ],
      );
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 28, 20, 28),
            child: Column(
              children: [
                Icon(
                  online ? Icons.hourglass_top_rounded : Icons.wifi_off_rounded,
                  size: 48,
                  color: DriverBrand.orange,
                ),
                const SizedBox(height: 12),
                Text(
                  online
                      ? strings.tr(
                          'بانتظار طلبات التوصيل',
                          'Waiting for delivery orders',
                        )
                      : strings.tr(
                          'فعّل الاتصال لاستلام الطلبات',
                          'Go online to receive orders',
                        ),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  online
                      ? strings.tr(
                          'سيظهر هنا أي طلب جديد في مناطقك المفعّلة.',
                          'New orders in your active areas will appear here.',
                        )
                      : strings.tr(
                          'لن يصلك أي طلب وأنت غير متصل.',
                          'You will not receive orders while offline.',
                        ),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: DriverBrand.muted, height: 1.4),
                ),
                if (!online) ...[
                  const SizedBox(height: 16),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: DriverBrand.orange,
                    ),
                    onPressed: onGoOnline,
                    child: Text(strings.tr('الاتصال الآن', 'Go online now')),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _IncomingCard extends StatelessWidget {
  const _IncomingCard({
    required this.request,
    required this.seconds,
    required this.regionLabel,
    required this.onAccept,
    required this.onDecline,
  });

  final DeliveryDispatchRequest request;
  final int seconds;
  final String Function(String id, [String fallback]) regionLabel;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return Material(
      color: Colors.white,
      elevation: 1,
      shadowColor: Colors.black12,
      borderRadius: BorderRadius.circular(22),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: DriverBrand.orange.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                strings.tr(
                  'طلب جديد — متبقي $seconds ث',
                  'New order — $seconds sec remaining',
                ),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: DriverBrand.orange,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              request.restaurantName.isEmpty
                  ? strings.tr('طلب توصيل', 'Delivery order')
                  : request.restaurantName,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            Text(
              strings.tr(
                'المنطقة: ${regionLabel(request.regionId, request.regionName)}',
                'Area: ${regionLabel(request.regionId, request.regionName)}',
              ),
            ),
            if (request.customerAddress.isNotEmpty)
              Text(request.customerAddress),
            const SizedBox(height: 8),
            Text(
              strings.tr(
                'ربحك: ${request.driverFee.toStringAsFixed(3)} د.ك',
                'Your earnings: ${request.driverFee.toStringAsFixed(3)} KWD',
              ),
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w900,
                color: Color(0xFF15803D),
              ),
            ),
            const SizedBox(height: 20),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF16A34A),
                minimumSize: const Size.fromHeight(56),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              onPressed: onAccept,
              child: Text(
                strings.tr('قبول الطلب', 'Accept order'),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                foregroundColor: const Color(0xFFC62828),
              ),
              onPressed: onDecline,
              child: Text(strings.tr('رفض', 'Decline')),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActiveTripCard extends StatelessWidget {
  const _ActiveTripCard({
    required this.request,
    required this.regionLabel,
    required this.onPickup,
    required this.onEnRoute,
    required this.onDeliver,
    required this.onCancel,
  });

  final DeliveryDispatchRequest request;
  final String Function(String id, [String fallback]) regionLabel;
  final VoidCallback onPickup;
  final VoidCallback onEnRoute;
  final VoidCallback onDeliver;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final goingToRestaurant = request.isAccepted;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _driverStatusLabel(strings, request),
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            Text(
              request.restaurantName.isEmpty
                  ? strings.tr('المطعم', 'Restaurant')
                  : request.restaurantName,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            Text(
              strings.tr(
                'هاتف العميل: ${request.customerPhone}',
                'Customer phone: ${request.customerPhone}',
              ),
            ),
            Text(
              strings.tr(
                'المنطقة: ${regionLabel(request.regionId, request.regionName)}',
                'Area: ${regionLabel(request.regionId, request.regionName)}',
              ),
            ),
            if (request.customerAddress.isNotEmpty)
              Text(request.customerAddress),
            const SizedBox(height: 12),
            if (goingToRestaurant)
              DriverPickupHandshake(request: request)
            else
              DriverCustomerHandshake(request: request),
            const SizedBox(height: 16),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: DriverBrand.orange,
                minimumSize: const Size.fromHeight(54),
              ),
              onPressed: () => navigateToPoint(
                goingToRestaurant
                    ? request.restaurantLocation
                    : request.customerLocation,
              ),
              icon: const Icon(Icons.navigation),
              label: Text(
                goingToRestaurant
                    ? strings.tr('ملاحة إلى المطعم', 'Navigate to restaurant')
                    : strings.tr('ملاحة إلى العميل', 'Navigate to customer'),
              ),
            ),
            const SizedBox(height: 8),
            if (goingToRestaurant)
              FilledButton(
                onPressed: onPickup,
                child: Text(
                  request.driverHandoffConfirmedAt != null &&
                          request.cashierHandoffConfirmedAt == null
                      ? strings.tr(
                          'بانتظار تأكيد الكاشير',
                          'Waiting for cashier confirmation',
                        )
                      : strings.tr(
                          'أكدت التسليم المالي واستلام الطلب',
                          'Confirm payment handoff and order pickup',
                        ),
                ),
              )
            else if (request.isPickedUp)
              FilledButton(
                onPressed: onEnRoute,
                child: Text(
                  strings.tr('في الطريق للعميل', 'On the way to customer'),
                ),
              )
            else
              FilledButton(
                onPressed: onDeliver,
                child: Text(strings.tr('تم التوصيل', 'Delivered')),
              ),
            TextButton(
              onPressed: onCancel,
              child: Text(
                strings.tr('إلغاء وإعادة البحث', 'Cancel and search again'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileTab extends StatelessWidget {
  const _ProfileTab({
    required this.driver,
    required this.online,
    this.onLogout,
  });

  final DeliveryDriver? driver;
  final bool online;
  final VoidCallback? onLogout;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final current = driver;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                const MenuProLogo(height: 72),
                const SizedBox(height: 10),
                Text(
                  current?.name.isNotEmpty == true
                      ? current!.name
                      : strings.tr('سائق المنيو برو', 'AlMenuPro Driver'),
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  online
                      ? strings.tr('الحساب متصل', 'Account online')
                      : strings.tr('الحساب غير متصل', 'Account offline'),
                  style: TextStyle(
                    color: online ? const Color(0xFF15803D) : DriverBrand.muted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        _InfoTile(
          icon: Icons.phone_android,
          label: strings.tr('الهاتف', 'Phone'),
          value: current?.phone ?? '—',
        ),
        _InfoTile(
          icon: Icons.badge_outlined,
          label: strings.tr('الرقم المدني', 'Civil ID'),
          value: current?.civilId ?? '—',
        ),
        _InfoTile(
          icon: Icons.tag,
          label: strings.tr('رقم السائق', 'Driver ID'),
          value: current?.id ?? '—',
        ),
        if ((current?.civilIdPhotoUrl ?? '').isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            strings.tr('صورة البطاقة', 'ID photo'),
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Image.network(
              current!.civilIdPhotoUrl,
              height: 140,
              fit: BoxFit.cover,
            ),
          ),
        ],
        if ((current?.licensePhotoUrl ?? '').isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            strings.tr('رخصة القيادة', 'Driving license'),
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Image.network(
              current!.licensePhotoUrl,
              height: 140,
              fit: BoxFit.cover,
            ),
          ),
        ],
        if (onLogout != null) ...[
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: onLogout,
            icon: const Icon(Icons.logout),
            label: Text(strings.tr('تسجيل الخروج', 'Sign out')),
          ),
        ],
      ],
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: ListTile(
          leading: Icon(icon, color: DriverBrand.orange),
          title: Text(
            label,
            style: const TextStyle(fontSize: 12, color: DriverBrand.muted),
          ),
          subtitle: Text(
            value.isEmpty ? '—' : value,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              color: DriverBrand.ink,
            ),
          ),
        ),
      ),
    );
  }
}

class _HistoryTab extends StatelessWidget {
  const _HistoryTab({required this.history, required this.regionLabel});

  final List<DeliveryDispatchRequest> history;
  final String Function(String id, [String fallback]) regionLabel;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    if (history.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: _EmptyHint(
          icon: Icons.receipt_long_outlined,
          text: strings.tr(
            'لا توجد طلبات سابقة بعد. ستظهر هنا بعد إتمام التوصيل.',
            'No previous orders yet. Completed deliveries will appear here.',
          ),
        ),
      );
    }
    final format = DateFormat('d/M/yyyy • HH:mm');
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      itemCount: history.length + 1,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  strings.tr('الطلبات السابقة', 'Previous orders'),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  strings.tr(
                    'الوقت والتاريخ، المطعم، العميل، وبيانات الطلب',
                    'Date, time, restaurant, customer, and order details',
                  ),
                  style: const TextStyle(color: DriverBrand.muted, height: 1.4),
                ),
              ],
            ),
          );
        }
        final request = history[index - 1];
        final when = request.updatedAt ?? request.createdAt;
        final orderRef = (request.orderId ?? '').trim();
        return Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        request.restaurantName.isEmpty
                            ? strings.tr('مطعم', 'Restaurant')
                            : request.restaurantName,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    Text(
                      _driverStatusLabel(strings, request),
                      style: TextStyle(
                        color: request.status == 'delivered'
                            ? const Color(0xFF15803D)
                            : DriverBrand.muted,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                if (when != null)
                  Text(
                    format.format(when.toLocal()),
                    style: const TextStyle(
                      color: DriverBrand.muted,
                      fontSize: 12,
                    ),
                  ),
                if (orderRef.isNotEmpty)
                  Text(
                    strings.tr(
                      'رقم الطلب: $orderRef',
                      'Order number: $orderRef',
                    ),
                  ),
                Text(
                  strings.tr(
                    'العميل: ${request.customerPhone.isEmpty ? '—' : request.customerPhone}',
                    'Customer: ${request.customerPhone.isEmpty ? '—' : request.customerPhone}',
                  ),
                ),
                if (request.customerAddress.isNotEmpty)
                  Text(request.customerAddress),
                Text(
                  strings.tr(
                    'المنطقة: ${regionLabel(request.regionId, request.regionName)}',
                    'Area: ${regionLabel(request.regionId, request.regionName)}',
                  ),
                ),
                Text(
                  strings.tr(
                    'أجرة السائق: ${request.driverFee.toStringAsFixed(3)} د.ك',
                    'Driver fee: ${request.driverFee.toStringAsFixed(3)} KWD',
                  ),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Icon(icon, color: DriverBrand.orange, size: 36),
            const SizedBox(height: 10),
            Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(height: 1.45),
            ),
          ],
        ),
      ),
    );
  }
}
