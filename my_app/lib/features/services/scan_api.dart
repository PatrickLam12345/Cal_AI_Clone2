// lib/features/services/scan_api.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'api_base.dart';

class ScanApi {
  const ScanApi();

  Future<List<Map<String, dynamic>>> analyzePhoto(File photo) async {
    final base = await apiBaseUrl();
    final uri  = Uri.parse('$base/scan/analyze');
    final b64  = base64Encode(await photo.readAsBytes());

    try {
      final r = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'image_base64': b64}),
          )
          .timeout(const Duration(seconds: 20)); // ⏳ timeout

      if (r.statusCode != 200) {
        throw HttpException('Server responded ${r.statusCode}');
      }

      final data = jsonDecode(r.body) as Map<String, dynamic>;
      return (data['items'] as List).cast<Map<String, dynamic>>();
    } on TimeoutException {
      throw Exception('Request timed out. Check your connection.');
    } on SocketException {
      throw Exception('Can’t reach the server. Are you on the same Wi-Fi?');
    }
  }
}
