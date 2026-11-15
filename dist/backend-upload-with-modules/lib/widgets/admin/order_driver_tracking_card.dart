import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../models/order.dart';
import '../../services/delivery_dispatch_service.dart';

class OrderDriverTrackingCard extends StatelessWidget {
  const OrderDriverTrackingCard({super.key, required this.order});

  final Order order;

  @override
  Widget build(BuildContext context) {
    if (order.orderType != OrderType.delivery) {
      return const SizedBox.shrink();
    }
    DeliveryBoardController.instance.ensureStarted();
    return ListenableBuilder(
      listenable: DeliveryBoardController.instance,
      builder: (context, _) {
        final board = DeliveryBoardController.instance;
        final request = board.requestForOrder(order.id);
        final driverId = (order.assignedDriverId ?? request?.assignedDriverId ?? '').trim();
        final driver = board.driverFor(
          driverId: driverId,
          driverName: order.assignedDriverName ?? request?.assignedDriverName,
        );
        final name = (order.assignedDriverName ??
                request?.assignedDriverName ??
                driver?.name ??
                '')
            .trim();
        final phone = (order.assignedDriverPhone ??
                request?.assignedDriverPhone ??
                driver?.phone ??
                '')
            .trim();
        final location = board.liveLocationFor(driverId.isEmpty ? driver?.id : driverId) ??
            driver?.location;
        final restaurantPoint = request?.restaurantLocation;
        final waiting = order.isWaitingDriver || (request?.isPending ?? false);
        final showEta = location != null &&
            restaurantPoint != null &&
            (order.deliveryStatus == 'driver_accepted' ||
                request?.isAccepted == true) &&
            order.statusTimeline.pickedUpAt == null;
        final eta = showEta ? location.etaMinutesTo(restaurantPoint) : null;

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'تتبع السائق',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
              if (order.isHeldByDriver ||
                  (request?.isAccepted == true) ||
                  (request?.isPickedUp == true) ||
                  (request?.isOnTheWay == true)) ...[
                const SizedBox(height: 8),
                const DriverCustodyLockBadge(),
              ],
              const SizedBox(height: 8),
              if (waiting && name.isEmpty)
                const Text(
                  'بانتظار قبول السائق — الطلب في قائمة «جديد» لدى السائقين.',
                  style: TextStyle(color: Color(0xFF64748B)),
                )
              else ...[
                Text(
                  name.isEmpty ? 'سائق معيّن' : name,
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                ),
                if (phone.isNotEmpty)
                  Text('📞 $phone', style: const TextStyle(fontSize: 13)),
              ],
              if (eta != null) ...[
                const SizedBox(height: 8),
                Text(
                  'يوصل المطعم خلال $eta دقيقة',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF6B1124),
                  ),
                ),
              ],
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  height: 160,
                  child: location == null
                      ? Container(
                          color: const Color(0xFFEEF2F6),
                          alignment: Alignment.center,
                          child: const Text(
                            'موقع السائق غير متاح بعد',
                            style: TextStyle(color: Color(0xFF64748B)),
                          ),
                        )
                      : FlutterMap(
                          options: MapOptions(
                            initialCenter: LatLng(location.lat, location.lng),
                            initialZoom: 14,
                          ),
                          children: [
                            TileLayer(
                              urlTemplate:
                                  'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                              userAgentPackageName: 'com.example.almenupro',
                            ),
                            MarkerLayer(
                              markers: [
                                if (restaurantPoint != null)
                                  Marker(
                                    point: LatLng(
                                      restaurantPoint.lat,
                                      restaurantPoint.lng,
                                    ),
                                    width: 36,
                                    height: 36,
                                    child: const Icon(
                                      Icons.storefront,
                                      color: Color(0xFF6B1124),
                                    ),
                                  ),
                                Marker(
                                  point: LatLng(location.lat, location.lng),
                                  width: 40,
                                  height: 40,
                                  child: const Icon(
                                    Icons.delivery_dining,
                                    color: Color(0xFF1565C0),
                                    size: 34,
                                  ),
                                ),
                              ],
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

class DriverCustodyLockBadge extends StatelessWidget {
  const DriverCustodyLockBadge({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: Order.driverCustodyLockMessage,
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 8 : 10,
          vertical: compact ? 6 : 8,
        ),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF8E1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFFFE082)),
        ),
        child: Row(
          children: [
            Icon(
              Icons.lock_outline,
              size: compact ? 16 : 18,
              color: const Color(0xFF8A5A00),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                Order.driverCustodyLockMessage,
                style: TextStyle(
                  fontSize: compact ? 11 : 12,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF8A5A00),
                  height: 1.35,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
