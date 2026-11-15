import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../../models/delivery_dispatch.dart';

final _kuwait = LatLng(29.3759, 47.9774);

class RestaurantLocationPicker extends StatefulWidget {
  const RestaurantLocationPicker({super.key, this.initial});

  final GeoPointLite? initial;

  static Future<GeoPointLite?> show(
    BuildContext context, {
    GeoPointLite? initial,
  }) {
    return showDialog<GeoPointLite>(
      context: context,
      builder: (context) => RestaurantLocationPicker(initial: initial),
    );
  }

  @override
  State<RestaurantLocationPicker> createState() => _RestaurantLocationPickerState();
}

class _RestaurantLocationPickerState extends State<RestaurantLocationPicker> {
  static const _burgundy = Color(0xFF6B1124);

  final _search = TextEditingController();
  final _mapController = MapController();
  late LatLng _center;
  LatLng? _pin;
  var _searching = false;
  List<_PlaceHit> _hits = const [];
  String? _error;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _center = initial == null ? _kuwait : LatLng(initial.lat, initial.lng);
    _pin = initial == null ? null : LatLng(initial.lat, initial.lng);
  }

  @override
  void dispose() {
    _search.dispose();
    _mapController.dispose();
    super.dispose();
  }

  void _dropPin(LatLng point) {
    setState(() {
      _pin = point;
      _center = point;
      _error = null;
    });
    _mapController.move(point, 17);
  }

  Future<void> _runSearch() async {
    final query = _search.text.trim();
    if (query.length < 2) return;
    final fromLink = parseMapLink(query);
    if (fromLink != null) {
      _dropPin(LatLng(fromLink.lat, fromLink.lng));
      return;
    }
    setState(() {
      _searching = true;
      _error = null;
    });
    try {
      final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
        'q': query,
        'format': 'jsonv2',
        'limit': '8',
        'countrycodes': 'kw',
      });
      final response = await http.get(
        uri,
        headers: const {
          'Accept': 'application/json',
          'User-Agent': 'AlMenuPro-admin/1.0',
        },
      );
      if (response.statusCode != 200) {
        throw Exception('تعذر البحث في الخريطة');
      }
      final decoded = jsonDecode(response.body);
      final hits = <_PlaceHit>[];
      if (decoded is List) {
        for (final row in decoded.whereType<Map>()) {
          final lat = double.tryParse('${row['lat']}');
          final lng = double.tryParse('${row['lon']}');
          if (lat == null || lng == null) continue;
          hits.add(
            _PlaceHit(
              label: row['display_name']?.toString() ?? query,
              point: LatLng(lat, lng),
            ),
          );
        }
      }
      if (!mounted) return;
      setState(() {
        _hits = hits;
        _searching = false;
        if (hits.isEmpty) {
          _error = 'لا توجد نتائج. اضغط على الخريطة لتحديد الموقع.';
        } else {
          _dropPin(hits.first.point);
        }
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _searching = false;
        _error = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final pin = _pin;
    return AlertDialog(
      title: const Text('موقع المطعم على الخريطة'),
      content: SizedBox(
        width: 640,
        child: SingleChildScrollView(
          child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                'ابحث أو اضغط على الخريطة لوضع الدبوس. هذا الموقع يظهر للسائق عند استلام الطلب.',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _search,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _runSearch(),
              decoration: InputDecoration(
                labelText: 'بحث أو رابط خرائط جوجل',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  onPressed: _searching ? null : _runSearch,
                  icon: _searching
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.search),
                ),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 6),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(_error!, style: const TextStyle(color: Color(0xFFC62828))),
              ),
            ],
            if (_hits.length > 1)
              SizedBox(
                height: 88,
                child: ListView.builder(
                  itemCount: _hits.length,
                  itemBuilder: (context, index) {
                    final hit = _hits[index];
                    return ListTile(
                      dense: true,
                      leading: const Icon(Icons.place_outlined, size: 18),
                      title: Text(hit.label, maxLines: 1, overflow: TextOverflow.ellipsis),
                      onTap: () => _dropPin(hit.point),
                    );
                  },
                ),
              ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                height: 320,
                child: FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: _center,
                    initialZoom: pin == null ? 11 : 16,
                    onTap: (tap, point) => _dropPin(point),
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.example.almenupro',
                    ),
                    if (pin != null)
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: pin,
                            width: 40,
                            height: 40,
                            child: const Icon(Icons.location_on, color: Color(0xFFC62828), size: 40),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
            if (pin != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '${pin.latitude.toStringAsFixed(6)}, ${pin.longitude.toStringAsFixed(6)}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
          ],
        ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: _burgundy),
          onPressed: pin == null
              ? null
              : () => Navigator.pop(
                    context,
                    GeoPointLite(lat: pin.latitude, lng: pin.longitude),
                  ),
          child: const Text('حفظ الموقع'),
        ),
      ],
    );
  }
}

class _PlaceHit {
  const _PlaceHit({required this.label, required this.point});
  final String label;
  final LatLng point;
}

GeoPointLite? parseMapLink(String raw) {
  if (raw.isEmpty) return null;
  final at = RegExp(r'@(-?\d+(?:\.\d+)?),\s*(-?\d+(?:\.\d+)?)').firstMatch(raw);
  if (at != null) {
    return GeoPointLite(lat: double.parse(at.group(1)!), lng: double.parse(at.group(2)!));
  }
  final bang = RegExp(r'!3d(-?\d+(?:\.\d+)?)!4d(-?\d+(?:\.\d+)?)').firstMatch(raw);
  if (bang != null) {
    return GeoPointLite(lat: double.parse(bang.group(1)!), lng: double.parse(bang.group(2)!));
  }
  final osm = RegExp(r'#map=\d+/(-?\d+(?:\.\d+)?)/(-?\d+(?:\.\d+)?)').firstMatch(raw);
  if (osm != null) {
    return GeoPointLite(lat: double.parse(osm.group(1)!), lng: double.parse(osm.group(2)!));
  }
  final query = RegExp(
    r'[?&](?:q|query|ll)=(-?\d+(?:\.\d+)?),\s*(-?\d+(?:\.\d+)?)',
  ).firstMatch(raw);
  if (query != null) {
    return GeoPointLite(
      lat: double.parse(query.group(1)!),
      lng: double.parse(query.group(2)!),
    );
  }
  return null;
}
