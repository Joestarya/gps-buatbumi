import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/tomtom_config.dart';

class OsmPlace {
  final String name;
  final double lat;
  final double lon;
  final String? displayAddress;

  OsmPlace({
    required this.name,
    required this.lat,
    required this.lon,
    this.displayAddress,
  });
}

class OsmSearchService {
  // Now backed by TomTom Search API
  static const _baseUrl = 'https://api.tomtom.com/search/2/search';

  Future<List<OsmPlace>> search(String query, {String countryCodes = '', int limit = 10}) async {
    if (query.trim().isEmpty) return [];
    final path = '$_baseUrl/${Uri.encodeComponent(query)}.json';
    final params = {
      'key': TomTomConfig.apiKey,
      'limit': '$limit',
      if (countryCodes.isNotEmpty) 'countrySet': countryCodes.toUpperCase(),
    };
    final uri = Uri.parse(path).replace(queryParameters: params);

    final res = await http.get(uri, headers: {
      'Accept': 'application/json',
    });
    if (res.statusCode != 200) return [];
    final data = json.decode(res.body) as Map<String, dynamic>;
    final results = (data['results'] as List?) ?? [];
    return results.map<OsmPlace>((e) {
      final poi = (e['poi'] as Map?) ?? {};
      final name = (poi['name']?.toString() ?? 'Unknown');
      final position = (e['position'] as Map?) ?? {};
      final lat = (position['lat'] ?? 0).toDouble();
      final lon = (position['lon'] ?? 0).toDouble();
      final address = ((e['address'] as Map?)?['freeformAddress']?.toString()) ?? name;
      return OsmPlace(
        name: name,
        lat: lat,
        lon: lon,
        displayAddress: address,
      );
    }).toList();
  }
}
