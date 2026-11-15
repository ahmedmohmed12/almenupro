import 'package:flutter/material.dart';

import '../../models/restaurant.dart';
import '../../services/super_admin_scope_service.dart';

class AdminRestaurantSelector extends StatelessWidget {
  const AdminRestaurantSelector({super.key});

  static const burgundy = Color(0xFF6B1124);

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: SuperAdminScopeService.instance,
      builder: (context, _) {
        final scope = SuperAdminScopeService.instance;
        final restaurants = scope.restaurants;

        if (scope.loadingRestaurants && restaurants.isEmpty) {
          return const SizedBox(
            width: 220,
            child: LinearProgressIndicator(color: burgundy),
          );
        }

        if (restaurants.isEmpty) {
          return OutlinedButton.icon(
            onPressed: scope.refreshRestaurants,
            icon: const Icon(Icons.refresh),
            label: const Text('تحميل المطاعم'),
          );
        }

        return ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: DropdownButtonFormField<String>(
            value: scope.selectedRestaurantId,
            decoration: InputDecoration(
              labelText: 'المطعم النشط',
              prefixIcon: const Icon(Icons.store, color: burgundy),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              isDense: true,
            ),
            items: restaurants
                .map(
                  (restaurant) => DropdownMenuItem<String>(
                    value: restaurant.id,
                    child: Text(
                      restaurant.name,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                )
                .toList(),
            onChanged: (value) {
              if (value == null) return;
              final restaurant = restaurants.firstWhere((entry) => entry.id == value);
              scope.selectRestaurant(restaurant);
            },
          ),
        );
      },
    );
  }
}
