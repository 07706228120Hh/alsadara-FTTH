import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../config/api_config.dart';
import '../models/citizen.dart';

class ApiService {
  final _storage = const FlutterSecureStorage();
  String? _token;

  // Create a custom http client
  http.Client _createClient() {
    return http.Client();
  }

  Future<String?> getToken() async {
    _token ??= await _storage.read(key: 'auth_token');
    return _token;
  }

  Future<void> saveToken(String token) async {
    _token = token;
    await _storage.write(key: 'auth_token', value: token);
  }

  Future<void> clearToken() async {
    _token = null;
    await _storage.delete(key: 'auth_token');
  }

  /// حفظ حالة "تذكرني"
  Future<void> setRememberMe(bool value) async {
    await _storage.write(
      key: 'citizen_remember_me',
      value: value ? 'true' : 'false',
    );
  }

  /// قراءة حالة "تذكرني"
  Future<bool> getRememberMe() async {
    final value = await _storage.read(key: 'citizen_remember_me');
    return value == 'true';
  }

  // Authentication APIs
  Future<Map<String, dynamic>> register({
    required String fullName,
    required String phoneNumber,
    required String password,
    String? email,
    String? city,
    String? district,
    String? address,
  }) async {
    final client = _createClient();

    try {
      final response = await client.post(
        Uri.parse('${ApiConfig.baseUrl}${ApiConfig.citizenRegister}'),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
        body: json.encode({
          'fullName': fullName,
          'phoneNumber': phoneNumber,
          'password': password,
          'email': email,
          'city': city,
          'district': district,
          'address': address,
          'language': 'ar',
        }),
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return json.decode(utf8.decode(response.bodyBytes));
      }

      final error = json.decode(utf8.decode(response.bodyBytes));
      throw Exception(error['messageAr'] ?? error['message'] ?? 'حدث خطأ');
    } finally {
      client.close();
    }
  }

  Future<Map<String, dynamic>> login({
    required String phoneNumber,
    required String password,
    String? deviceId,
    String? fcmToken,
  }) async {
    final client = _createClient();

    try {
      final response = await client.post(
        Uri.parse('${ApiConfig.baseUrl}${ApiConfig.citizenLogin}'),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
        body: json.encode({
          'phoneNumber': phoneNumber,
          'password': password,
          'deviceId': deviceId,
          'fcmToken': fcmToken,
          'platform': 'web',
        }),
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final data = json.decode(utf8.decode(response.bodyBytes));
        if (data['token'] != null) {
          await saveToken(data['token']);
        }
        return data;
      }

      final error = json.decode(utf8.decode(response.bodyBytes));
      throw Exception(error['messageAr'] ?? error['message'] ?? 'حدث خطأ');
    } finally {
      client.close();
    }
  }

  Future<Map<String, dynamic>> verifyPhone({
    required String citizenId,
    required String code,
  }) async {
    final client = _createClient();

    try {
      final response = await client.post(
        Uri.parse('${ApiConfig.baseUrl}${ApiConfig.citizenVerifyPhone}'),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
        body: json.encode({'citizenId': citizenId, 'code': code}),
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final data = json.decode(utf8.decode(response.bodyBytes));
        if (data['token'] != null) {
          await saveToken(data['token']);
        }
        return data;
      }

      final error = json.decode(utf8.decode(response.bodyBytes));
      throw Exception(error['messageAr'] ?? error['message'] ?? 'حدث خطأ');
    } finally {
      client.close();
    }
  }

  Future<Citizen> getProfile() async {
    final token = await getToken();
    if (token == null) {
      throw Exception('Not authenticated');
    }

    final client = _createClient();

    try {
      final response = await client.get(
        Uri.parse('${ApiConfig.baseUrl}${ApiConfig.citizenProfile}'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json; charset=utf-8',
        },
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final data = json.decode(utf8.decode(response.bodyBytes));
        return Citizen.fromJson(data['citizen']);
      }

      final error = json.decode(utf8.decode(response.bodyBytes));
      throw Exception(error['messageAr'] ?? error['message'] ?? 'حدث خطأ');
    } finally {
      client.close();
    }
  }

  // Plans APIs
  Future<List<dynamic>> getInternetPlans() async {
    final client = _createClient();

    try {
      final response = await client.get(
        Uri.parse('${ApiConfig.baseUrl}${ApiConfig.internetPlans}'),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final data = json.decode(utf8.decode(response.bodyBytes));
        return data['plans'] ?? [];
      }

      final error = json.decode(utf8.decode(response.bodyBytes));
      throw Exception(error['messageAr'] ?? error['message'] ?? 'حدث خطأ');
    } finally {
      client.close();
    }
  }

  // Subscriptions APIs
  Future<List<dynamic>> getMySubscriptions() async {
    final token = await getToken();
    if (token == null) {
      throw Exception('Not authenticated');
    }

    final client = _createClient();

    try {
      final response = await client.get(
        Uri.parse('${ApiConfig.baseUrl}${ApiConfig.subscriptions}'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json; charset=utf-8',
        },
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final data = json.decode(utf8.decode(response.bodyBytes));
        return data['subscriptions'] ?? [];
      }

      final error = json.decode(utf8.decode(response.bodyBytes));
      throw Exception(error['messageAr'] ?? error['message'] ?? 'حدث خطأ');
    } finally {
      client.close();
    }
  }
}
