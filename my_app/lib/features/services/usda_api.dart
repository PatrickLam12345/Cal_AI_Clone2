// lib/services/usda_api.dart
import 'dart:convert';
import 'package:http/http.dart' as http;

class UsdaSearchResponse {
  final List<Map<String, dynamic>> foods;
  final int page;
  final int pageSize;
  final int totalHits;

  UsdaSearchResponse({
    required this.foods,
    required this.page,
    required this.pageSize,
    required this.totalHits,
  });
}

class UsdaApi {
  final String base; // change to http://localhost:3000 for desktop
  const UsdaApi({this.base = 'http://10.0.2.2:3000'});

  static const _timeout = Duration(seconds: 12);

  Future<UsdaSearchResponse> search(String q, {int page = 1}) async {
    final uri = Uri.parse('$base/usda/search')
        .replace(queryParameters: {'q': q, 'page': '$page'});

    final resp = await http.get(uri, headers: {'Accept': 'application/json'}).timeout(_timeout);
    if (resp.statusCode != 200) {
      throw Exception('Search failed (${resp.statusCode}): ${resp.body}');
    }

    final decoded = json.decode(resp.body);

    final foods = (decoded is Map && decoded['foods'] is List)
        ? (decoded['foods'] as List).whereType<Map<String, dynamic>>().toList()
        : <Map<String, dynamic>>[];

    final p  = (decoded is Map && decoded['page'] is int)      ? decoded['page'] as int      : page;
    final ps = (decoded is Map && decoded['pageSize'] is int)  ? decoded['pageSize'] as int  : 25;
    final th = (decoded is Map && decoded['totalHits'] is int) ? decoded['totalHits'] as int : foods.length;

    return UsdaSearchResponse(foods: foods, page: p, pageSize: ps, totalHits: th);
  }

  Future<Map<String, dynamic>> detail(int fdcId) async {
    final uri = Uri.parse('$base/usda/detail/$fdcId');
    final resp = await http.get(uri, headers: {'Accept': 'application/json'}).timeout(_timeout);
    if (resp.statusCode != 200) {
      throw Exception('Detail failed (${resp.statusCode}): ${resp.body}');
    }
    final decoded = json.decode(resp.body);
    if (decoded is Map<String, dynamic>) return decoded;
    throw Exception('Invalid detail response');
  }

  Future<List<Map<String, dynamic>>> normalize(Map<String, dynamic> detail) async {
    final uri = Uri.parse('$base/usda/normalize');
    final resp = await http
        .post(uri,
            headers: {
              'Accept': 'application/json',
              'Content-Type': 'application/json',
            },
            body: json.encode({'detail': detail}))
        .timeout(_timeout);
    if (resp.statusCode != 200) {
      throw Exception('Normalize failed (${resp.statusCode}): ${resp.body}');
    }
    final decoded = json.decode(resp.body);
    final nutrients = (decoded is Map && decoded['nutrients'] is List)
        ? decoded['nutrients'] as List
        : const <dynamic>[];
    return nutrients.whereType<Map<String, dynamic>>().toList();
  }
}
