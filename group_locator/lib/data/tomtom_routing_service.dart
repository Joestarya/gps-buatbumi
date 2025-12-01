import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import '../config/tomtom_config.dart';

class TomTomRouteResult {
  final List<LatLng> points;
  final double lengthMeters;
  final int travelTimeSeconds;
  TomTomRouteResult({
    required this.points,
    required this.lengthMeters,
    required this.travelTimeSeconds,
  });
}

class TomTomRoutingService {
  static const _base = 'https://api.tomtom.com/routing/1/calculateRoute';

  Future<TomTomRouteResult?> fetchRoute(LatLng from, LatLng to) async {
    final url = Uri.parse(
        '$_base/${from.latitude},${from.longitude}:${to.latitude},${to.longitude}/json').replace(queryParameters: {
      'key': TomTomConfig.apiKey,
      'traffic': 'true',
      'routeRepresentation': 'polyline',
      'computeBestOrder': 'false',
    });
    final res = await http.get(url, headers: {
      'Accept': 'application/json',
    });
    if (res.statusCode != 200) return null;
    final data = json.decode(res.body);
    final routes = data['routes'] as List?;
    if (routes == null || routes.isEmpty) return null;
    final route0 = routes.first;
    final summary = route0['summary'] ?? {};
    final lengthMeters = (summary['lengthInMeters'] ?? 0).toDouble();
    final travelTimeSeconds = (summary['travelTimeInSeconds'] ?? 0).toInt();
    final legs = route0['legs'] as List?;
    final List<LatLng> points = [];
    if (legs != null && legs.isNotEmpty) {
      for (final leg in legs) {
        final legPoints = leg['points'] as List?;
        if (legPoints != null) {
          for (final p in legPoints) {
            final lat = (p['latitude'] ?? 0).toDouble();
            final lon = (p['longitude'] ?? 0).toDouble();
            points.add(LatLng(lat, lon));
          }
        }
      }
    }
    return TomTomRouteResult(
      points: points,
      lengthMeters: lengthMeters,
      travelTimeSeconds: travelTimeSeconds,
    );
  }
}
