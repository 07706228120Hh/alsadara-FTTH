import 'package:flutter/foundation.dart';
import '../models/citizen.dart';
import '../services/api_service.dart';

class AuthProvider with ChangeNotifier {
  final ApiService _apiService = ApiService();

  Citizen? _citizen;
  bool _isLoading = false;
  String? _error;

  Citizen? get citizen => _citizen;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isAuthenticated => _citizen != null;

  Future<bool> login(String phoneNumber, String password) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await _apiService.login(
        phoneNumber: phoneNumber,
        password: password,
      );

      if (response['success'] == true && response['citizen'] != null) {
        _citizen = Citizen.fromJson(response['citizen']);
        _isLoading = false;
        notifyListeners();
        return true;
      }

      _error = response['messageAr'] ?? 'حدث خطأ أثناء تسجيل الدخول';
      _isLoading = false;
      notifyListeners();
      return false;
    } catch (e) {
      _error = e.toString().replaceAll('Exception: ', '');
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<Map<String, dynamic>> register({
    required String fullName,
    required String phoneNumber,
    required String password,
    String? email,
    String? city,
    String? district,
    String? address,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await _apiService.register(
        fullName: fullName,
        phoneNumber: phoneNumber,
        password: password,
        email: email,
        city: city,
        district: district,
        address: address,
      );

      _isLoading = false;
      notifyListeners();
      return response;
    } catch (e) {
      _error = e.toString().replaceAll('Exception: ', '');
      _isLoading = false;
      notifyListeners();
      rethrow;
    }
  }

  Future<bool> verifyPhone(String citizenId, String code) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await _apiService.verifyPhone(
        citizenId: citizenId,
        code: code,
      );

      if (response['success'] == true && response['citizen'] != null) {
        _citizen = Citizen.fromJson(response['citizen']);
        _isLoading = false;
        notifyListeners();
        return true;
      }

      _error = response['messageAr'] ?? 'رمز التحقق غير صحيح';
      _isLoading = false;
      notifyListeners();
      return false;
    } catch (e) {
      _error = e.toString().replaceAll('Exception: ', '');
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<void> loadProfile() async {
    try {
      _citizen = await _apiService.getProfile();
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  Future<void> logout() async {
    await _apiService.clearToken();
    _citizen = null;
    _error = null;
    notifyListeners();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}
