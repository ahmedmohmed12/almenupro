import 'package:flutter/material.dart';

import '../models/restaurant.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../utils/restaurant_route.dart';

class RestaurantDirectoryScreen extends StatefulWidget {
  const RestaurantDirectoryScreen({super.key});

  @override
  State<RestaurantDirectoryScreen> createState() =>
      _RestaurantDirectoryScreenState();
}

class _RestaurantDirectoryScreenState extends State<RestaurantDirectoryScreen> {
  var _loading = true;
  String? _error;
  List<Restaurant> _restaurants = const [];

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
      final restaurants = await ApiService.instance.fetchPublicRestaurants();
      if (!mounted) return;
      setState(() {
        _restaurants = restaurants;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  void _open(Restaurant restaurant) {
    Navigator.of(context).pushNamed(
      RestaurantRoute.menuPathForSlug(restaurant.slug),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppTheme.brandBackground,
        appBar: AppBar(
          backgroundColor: AppTheme.brandMaroon,
          foregroundColor: Colors.white,
          title: const Text('اختر المطعم'),
        ),
        body: _loading
            ? const Center(
                child: CircularProgressIndicator(color: AppTheme.brandOrange),
              )
            : _error != null
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!),
                        TextButton(onPressed: _load, child: const Text('إعادة المحاولة')),
                      ],
                    ),
                  )
                : _restaurants.isEmpty
                    ? const Center(child: Text('لا توجد مطاعم متاحة حالياً'))
                    : ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: _restaurants.length,
                        separatorBuilder: (context, index) =>
                            const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final restaurant = _restaurants[index];
                          return Card(
                            child: ListTile(
                              leading: const Icon(
                                Icons.storefront,
                                color: AppTheme.brandMaroon,
                              ),
                              title: Text(
                                restaurant.name,
                                style: const TextStyle(fontWeight: FontWeight.w700),
                              ),
                              subtitle: Text('/menu/${restaurant.slug}'),
                              trailing: const Icon(Icons.chevron_left),
                              onTap: () => _open(restaurant),
                            ),
                          );
                        },
                      ),
      ),
    );
  }
}
