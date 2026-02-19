import 'package:flutter/foundation.dart';
import '../services/agent_api_service.dart';

/// مزود المصادقة للوكيل
class AgentAuthProvider with ChangeNotifier {
  final AgentApiService _apiService = AgentApiService.instance;

  /// الوصول لخدمة API الخاصة بالوكيل
  AgentApiService get agentApi => _apiService;

  bool _isLoading = false;
  bool _isInitialized = false;
  String? _error;

  AgentData? get agent => _apiService.currentAgent;
  bool get isLoading => _isLoading;
  bool get isInitialized => _isInitialized;
  String? get error => _error;
  bool get isAuthenticated => _apiService.isAuthenticated;

  /// تهيئة مصادقة الوكيل - يتحقق من "تذكرني" ويستعيد الجلسة
  Future<void> initialize() async {
    try {
      final rememberMe = await _apiService.getRememberMe();
      if (rememberMe) {
        await tryRestoreSession();
      } else {
        await _apiService.clearToken();
      }
    } catch (_) {
      // فشل التهيئة - متابعة بدون مصادقة
    }
    _isInitialized = true;
    notifyListeners();
  }

  /// محاولة استعادة الجلسة السابقة
  Future<bool> tryRestoreSession() async {
    try {
      return await _apiService.tryRestoreSession();
    } catch (_) {
      return false;
    }
  }

  /// تسجيل دخول الوكيل
  Future<bool> login(
    String agentCode,
    String password, {
    bool rememberMe = false,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await _apiService.login(
        agentCode: agentCode,
        password: password,
      );

      if (response['token'] != null) {
        // حفظ حالة "تذكرني"
        await _apiService.setRememberMe(rememberMe);
        _isLoading = false;
        notifyListeners();
        return true;
      }

      _error = response['messageAr'] ?? 'فشل تسجيل الدخول';
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

  /// تحديث الملف الشخصي
  Future<void> refreshProfile() async {
    try {
      await _apiService.getProfile();
      notifyListeners();
    } catch (e) {
      _error = e.toString().replaceAll('Exception: ', '');
      notifyListeners();
    }
  }

  /// جلب ملخص الحسابات
  Future<AgentAccountingSummaryData?> getAccountingSummary() async {
    try {
      return await _apiService.getAccountingSummary();
    } catch (e) {
      _error = e.toString().replaceAll('Exception: ', '');
      notifyListeners();
      return null;
    }
  }

  /// جلب العمليات
  Future<List<AgentTransactionData>> getTransactions({
    int page = 1,
    int pageSize = 20,
    int? type,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      return await _apiService.getTransactions(
        page: page,
        pageSize: pageSize,
        type: type,
        startDate: startDate,
        endDate: endDate,
      );
    } catch (e) {
      _error = e.toString().replaceAll('Exception: ', '');
      notifyListeners();
      return [];
    }
  }

  /// طلب شحن رصيد
  Future<bool> requestCharge({
    required double amount,
    required String description,
    required int category,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      await _apiService.requestCharge(
        amount: amount,
        description: description,
        category: category,
      );
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString().replaceAll('Exception: ', '');
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// تسجيل تسديد
  Future<bool> recordPayment({
    required double amount,
    required String description,
    required int category,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      await _apiService.recordPayment(
        amount: amount,
        description: description,
        category: category,
      );
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString().replaceAll('Exception: ', '');
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// تسجيل خروج
  Future<void> logout() async {
    await _apiService.logout();
    await _apiService.setRememberMe(false);
    _error = null;
    notifyListeners();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}
