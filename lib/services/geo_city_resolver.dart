import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/services.dart' show rootBundle;

// GeoNames attribution and dataset limits: assets/geo/geoCities.LICENSE.md.
// Port of poputki-front/src/utils/geoCityResolver.js.

class _GeoCity {
  final double lat;
  final double lon;
  final String country;
  final List<String> names;
  _GeoCity(this.lat, this.lon, this.country, this.names);
}

class _Candidate {
  final String name;
  final String? country;
  _Candidate(this.name, this.country);
}

final RegExp _suffix = RegExp(r'\s*\((?:[A-Z]{2}|РФ)\)\s*$', caseSensitive: false);
final RegExp _suffixCode = RegExp(r'\(([A-Z]{2}|РФ)\)\s*$', caseSensitive: false);
final RegExp _separators = RegExp(r"[\s\-’']");

String _normalize(String value) =>
    value.replaceAll(_suffix, '').toLowerCase().replaceAll('ё', 'е').replaceAll(_separators, '');

double _radians(double v) => v * math.pi / 180;

double distanceKm(double lat1, double lon1, double lat2, double lon2) {
  final a = math.pow(math.sin(_radians(lat2 - lat1) / 2), 2) +
      math.cos(_radians(lat1)) *
          math.cos(_radians(lat2)) *
          math.pow(math.sin(_radians(lon2 - lon1) / 2), 2);
  return 6371 * 2 * math.atan2(math.sqrt(a), math.sqrt(math.max(0, 1 - a)));
}

class GeoCityResolver {
  final List<_GeoCity> _cities;
  GeoCityResolver._(this._cities);

  static GeoCityResolver? _instance;

  static Future<GeoCityResolver> load() async {
    if (_instance != null) return _instance!;
    final raw = await rootBundle.loadString('assets/geo/geoCities.json');
    final data = jsonDecode(raw) as List<dynamic>;
    _instance = GeoCityResolver._(data.map((e) {
      final row = e as List<dynamic>;
      return _GeoCity((row[0] as num).toDouble(), (row[1] as num).toDouble(),
          row[2] as String, (row[3] as List<dynamic>).cast<String>());
    }).toList());
    return _instance!;
  }

  /// Only suggests a service city within 25 km and in the nearest city's
  /// country, so a distant supported departure never replaces the real one.
  String? resolve(double latitude, double longitude, List<String> availableCities,
      {double accuracy = 0}) {
    if (!latitude.isFinite || latitude.abs() > 90 || !longitude.isFinite ||
        longitude.abs() > 180 || (accuracy.isFinite && accuracy > 10000)) {
      return null;
    }
    final available = <String, List<_Candidate>>{};
    for (final name in availableCities) {
      final code = _suffixCode.firstMatch(name)?.group(1)?.toUpperCase();
      final country = code == 'РФ' ? 'RU' : code;
      available.putIfAbsent(_normalize(name), () => []).add(_Candidate(name, country));
    }

    String? nearestCountry;
    var nearestDistance = double.infinity;
    final supported = <({String city, String country, double distance})>[];
    for (final c in _cities) {
      final d = distanceKm(latitude, longitude, c.lat, c.lon);
      if (d < nearestDistance) {
        nearestDistance = d;
        nearestCountry = c.country;
      }
      if (d > 25) continue;
      String? match;
      for (final n in c.names) {
        for (final item in available[_normalize(n)] ?? const <_Candidate>[]) {
          if (item.country == null || item.country == c.country) {
            match = item.name;
            break;
          }
        }
        if (match != null) break;
      }
      if (match != null) supported.add((city: match, country: c.country, distance: d));
    }
    final inCountry = supported.where((s) => s.country == nearestCountry).toList()
      ..sort((a, b) => a.distance.compareTo(b.distance));
    return inCountry.isEmpty ? null : inCountry.first.city;
  }
}
