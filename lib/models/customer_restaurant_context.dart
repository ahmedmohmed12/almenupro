import 'restaurant.dart';
import 'restaurant_settings.dart';

/// Loaded restaurant context for the public customer menu page.
class CustomerRestaurantContext {
  const CustomerRestaurantContext({
    required this.restaurant,
    required this.settings,
  });

  final Restaurant restaurant;
  final RestaurantSettings settings;

  String get slug => restaurant.slug;
  String get name => restaurant.name;
  String get id => restaurant.id;
  String get whatsappNumber => settings.whatsappNumber;
}
