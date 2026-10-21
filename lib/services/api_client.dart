import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ApiClient {
  static String? _resolvedBaseUrl;

  static String get baseUrl {
    if (_resolvedBaseUrl != null) return _resolvedBaseUrl!;
    if (!kIsWeb && Platform.isAndroid) {
      return dotenv.env['BASE_URL'] ?? 'http://10.0.2.2:5242/api/';
    }
    return dotenv.env['LOCAL_URL'] ?? 'http://localhost:5242/api/';
  }

  static Future<Map<String, String>> _getHeaders() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwt_token');
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  static Future<http.Response> _sendWithFallback(
    Future<http.Response> Function(String fullUrl, Map<String, String> headers) call,
    String endpoint,
  ) async {
    final headers = await _getHeaders();
    final currentBase = baseUrl;
    try {
      final res = await call('$currentBase$endpoint', headers).timeout(const Duration(seconds: 4));
      return res;
    } catch (_) {
      // Nếu máy thật không gọi được 10.0.2.2, tự động chuyển sang localhost:5242 (hỗ trợ adb reverse)
      final altBase = currentBase.contains('10.0.2.2')
          ? currentBase.replaceAll('10.0.2.2', 'localhost')
          : currentBase.replaceAll('localhost', '10.0.2.2');
      _resolvedBaseUrl = altBase;
      return await call('$altBase$endpoint', headers);
    }
  }

  static Future<http.Response> get(String endpoint) async {
    return await _sendWithFallback(
      (url, headers) => http.get(Uri.parse(url), headers: headers),
      endpoint,
    );
  }

  static Future<http.Response> post(String endpoint, dynamic data) async {
    return await _sendWithFallback(
      (url, headers) => http.post(Uri.parse(url), headers: headers, body: jsonEncode(data)),
      endpoint,
    );
  }

  static Future<http.Response> put(String endpoint, dynamic data) async {
    return await _sendWithFallback(
      (url, headers) => http.put(Uri.parse(url), headers: headers, body: jsonEncode(data)),
      endpoint,
    );
  }

  static Future<http.Response> delete(String endpoint) async {
    return await _sendWithFallback(
      (url, headers) => http.delete(Uri.parse(url), headers: headers),
      endpoint,
    );
  }
}
