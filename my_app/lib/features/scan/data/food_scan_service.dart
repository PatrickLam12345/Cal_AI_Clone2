// lib/features/scan/data/food_scan_service.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

import '../../services/api_base.dart';
import '../../services/scan_api.dart';
// import '../../services/usda_api.dart'; // temporarily not used

class FoodScanService {
  FoodScanService._();
  static final instance = FoodScanService._();

  final _scanApi = const ScanApi();
  // final _usdaApi = const UsdaApi();

  /// DEV MODE: skip USDA resolve so the UI always shows results fast
  static const bool _kSkipResolve = true;

  Future<List<Map<String, dynamic>>> analyzeAndResolve(File photo) async {
    try {
      // 1) Detect items (dummy backend should return immediately)
      final guesses = await _scanApi.analyzePhoto(photo);
      if (guesses.isEmpty) return [];

      if (_kSkipResolve) {
        // Map guesses into the UI shape so your list renders
        return guesses.map((g) => {
          'name': g['name'],
          'portion_desc': g['portion_desc'],
          'portion_grams': g['portion_grams'],
          'data_type': 'Scan (dev)',
          'nutrients': {'calories': 0},
        }).toList();
      }

      // 2) If you want to re-enable resolve later:
      // final base = await apiBaseUrl();
      // final uri  = Uri.parse('$base/usda/resolve');
      // final r = await http.post(uri,
      //   headers: {'Content-Type': 'application/json'},
      //   body: jsonEncode({'items': guesses}),
      // ).timeout(const Duration(seconds: 10));
      // if (r.statusCode != 200) return [];
      // final data = jsonDecode(r.body) as Map<String, dynamic>;
      // return (data['items'] as List?)?.cast<Map<String, dynamic>>() ?? [];

      return []; // unreachable with _kSkipResolve=true
    } on TimeoutException {
      return [];
    } on SocketException {
      return [];
    } catch (_) {
      return [];
    }
  }
}
