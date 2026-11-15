import 'package:almenupro/models/restaurant.dart';
import 'package:almenupro/services/restaurant_login_search.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const sample = [
    Restaurant(id: 'rest_a', slug: 'beit-wadha', name: 'Beit Wadha'),
    Restaurant(id: 'rest_b', slug: 'molton-cookies', name: 'Molton Cookies'),
  ];

  test('filters restaurants by slug, name, or id', () {
    expect(
      filterRestaurantsForLogin(sample, 'molton').single.slug,
      'molton-cookies',
    );
    expect(
      filterRestaurantsForLogin(sample, 'wadha').single.slug,
      'beit-wadha',
    );
    expect(filterRestaurantsForLogin(sample, 'rest_a').single.id, 'rest_a');
    expect(filterRestaurantsForLogin(sample, ''), isEmpty);
  });
}