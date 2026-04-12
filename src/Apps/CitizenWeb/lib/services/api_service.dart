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

  /// حفظ بيانات تسجيل الدخول
  Future<void> saveLoginCredentials(String phone, String password) async {
    await _storage.write(key: 'citizen_saved_phone', value: phone);
    await _storage.write(key: 'citizen_saved_password', value: password);
  }

  /// استرجاع بيانات تسجيل الدخول المحفوظة
  Future<({String? phone, String? password})> getSavedCredentials() async {
    final phone = await _storage.read(key: 'citizen_saved_phone');
    final password = await _storage.read(key: 'citizen_saved_password');
    return (phone: phone, password: password);
  }

  /// مسح بيانات تسجيل الدخول المحفوظة
  Future<void> clearSavedCredentials() async {
    await _storage.delete(key: 'citizen_saved_phone');
    await _storage.delete(key: 'citizen_saved_password');
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

  /// تحديث الملف الشخصي
  Future<void> updateProfile({
    String? fullName,
    String? email,
    String? city,
    String? district,
    String? fullAddress,
  }) async {
    final token = await getToken();
    if (token == null) throw Exception('Not authenticated');

    final client = _createClient();
    try {
      final body = <String, dynamic>{};
      if (fullName != null && fullName.isNotEmpty) body['FullName'] = fullName;
      if (email != null && email.isNotEmpty) body['Email'] = email;
      if (city != null && city.isNotEmpty) body['City'] = city;
      if (district != null && district.isNotEmpty) body['District'] = district;
      if (fullAddress != null && fullAddress.isNotEmpty) body['FullAddress'] = fullAddress;

      final response = await client.put(
        Uri.parse('${ApiConfig.baseUrl}${ApiConfig.citizenProfile}'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json; charset=utf-8',
        },
        body: json.encode(body),
      );

      if (response.statusCode >= 200 && response.statusCode < 300) return;

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

  /// إنشاء طلب سحب ديلفري
  Future<Map<String, dynamic>> createDeliveryWithdrawal({
    required String citizenId,
    required double amount,
    required String phone,
    required String address,
    required double latitude,
    required double longitude,
    String? notes,
  }) async {
    final token = await getToken();
    if (token == null) throw Exception('Not authenticated');

    final client = _createClient();
    try {
      final response = await client.post(
        Uri.parse('${ApiConfig.baseUrl}${ApiConfig.citizenDeliveryWithdrawal}'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json; charset=utf-8',
        },
        body: json.encode({
          'amount': amount,
          'contactPhone': phone,
          'address': address,
          'latitude': latitude,
          'longitude': longitude,
          'notes': notes,
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
}
