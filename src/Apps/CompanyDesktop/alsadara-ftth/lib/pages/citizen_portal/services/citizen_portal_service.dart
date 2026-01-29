/// خدمة نظام المواطن
/// تتصل بـ VPS API لجلب وإدارة بيانات المواطنين
library;

import '../../../services/api/api_client.dart';
import '../../../services/api/api_response.dart';
import '../models/citizen_portal_models.dart';

class CitizenPortalService {
  static CitizenPortalService? _instance;
  static CitizenPortalService get instance =>
      _instance ??= CitizenPortalService._internal();
  CitizenPortalService._internal();

  final ApiClient _apiClient = ApiClient.instance;

  // ============================================
  // إحصائيات
  // ============================================

  /// جلب إحصائيات نظام المواطن
  Future<ApiResponse<CitizenPortalStats>> getStats() async {
    return _apiClient.get(
      '/citizen-portal/stats',
      (data) => CitizenPortalStats.fromJson(data),
    );
  }

  // ============================================
  // المواطنين
  // ============================================

  /// جلب قائمة المواطنين
  Future<ApiResponse<List<CitizenModel>>> getCitizens({
    int page = 1,
    int pageSize = 20,
    String? search,
    bool? isActive,
  }) async {
    var endpoint = '/citizen-portal/citizens?page=$page&pageSize=$pageSize';
    if (search != null && search.isNotEmpty) {
      endpoint += '&search=$search';
    }
    if (isActive != null) {
      endpoint += '&isActive=$isActive';
    }

    return _apiClient.get(
      endpoint,
      (data) => (data as List).map((e) => CitizenModel.fromJson(e)).toList(),
    );
  }

  /// جلب تفاصيل مواطن
  Future<ApiResponse<CitizenModel>> getCitizenById(String id) async {
    return _apiClient.get(
      '/citizen-portal/citizens/$id',
      (data) => CitizenModel.fromJson(data),
    );
  }

  /// إنشاء مواطن جديد
  Future<ApiResponse<CitizenModel>> createCitizen(
      Map<String, dynamic> data) async {
    return _apiClient.post(
      '/citizen-portal/citizens',
      data,
      (data) => CitizenModel.fromJson(data),
    );
  }

  /// تحديث بيانات مواطن
  Future<ApiResponse<CitizenModel>> updateCitizen(
      String id, Map<String, dynamic> data) async {
    return _apiClient.put(
      '/citizen-portal/citizens/$id',
      data,
      (data) => CitizenModel.fromJson(data),
    );
  }

  /// حظر/إلغاء حظر مواطن
  Future<ApiResponse<bool>> toggleCitizenBan(String id,
      {String? reason}) async {
    return _apiClient.post(
      '/citizen-portal/citizens/$id/toggle-ban',
      {'reason': reason},
      (data) => true,
    );
  }

  // ============================================
  // طلبات الخدمة
  // ============================================

  /// جلب طلبات المواطنين
  Future<ApiResponse<List<ServiceRequestModel>>> getRequests({
    int page = 1,
    int pageSize = 20,
    int? status,
    String? citizenId,
    String? assignedToId,
  }) async {
    var endpoint = '/citizen-portal/requests?page=$page&pageSize=$pageSize';
    if (status != null) {
      endpoint += '&status=$status';
    }
    if (citizenId != null) {
      endpoint += '&citizenId=$citizenId';
    }
    if (assignedToId != null) {
      endpoint += '&assignedToId=$assignedToId';
    }

    return _apiClient.get(
      endpoint,
      (data) =>
          (data as List).map((e) => ServiceRequestModel.fromJson(e)).toList(),
    );
  }

  /// جلب تفاصيل طلب
  Future<ApiResponse<ServiceRequestModel>> getRequestById(String id) async {
    return _apiClient.get(
      '/citizen-portal/requests/$id',
      (data) => ServiceRequestModel.fromJson(data),
    );
  }

  /// تحديث حالة طلب
  Future<ApiResponse<bool>> updateRequestStatus(
    String id,
    int status, {
    String? note,
  }) async {
    return _apiClient.patch(
      '/citizen-portal/requests/$id/status',
      {'status': status, 'note': note},
      (data) => true,
    );
  }

  /// تعيين طلب لموظف
  Future<ApiResponse<bool>> assignRequest(
      String requestId, String employeeId) async {
    return _apiClient.post(
      '/citizen-portal/requests/$requestId/assign',
      {'employeeId': employeeId},
      (data) => true,
    );
  }

  // ============================================
  // الاشتراكات
  // ============================================

  /// جلب اشتراكات المواطنين
  Future<ApiResponse<List<CitizenSubscriptionModel>>> getSubscriptions({
    int page = 1,
    int pageSize = 20,
    String? citizenId,
    bool? isActive,
  }) async {
    var endpoint =
        '/citizen-portal/subscriptions?page=$page&pageSize=$pageSize';
    if (citizenId != null) {
      endpoint += '&citizenId=$citizenId';
    }
    if (isActive != null) {
      endpoint += '&isActive=$isActive';
    }

    return _apiClient.get(
      endpoint,
      (data) => (data as List)
          .map((e) => CitizenSubscriptionModel.fromJson(e))
          .toList(),
    );
  }

  /// إنشاء اشتراك جديد
  Future<ApiResponse<CitizenSubscriptionModel>> createSubscription(
      Map<String, dynamic> data) async {
    return _apiClient.post(
      '/citizen-portal/subscriptions',
      data,
      (data) => CitizenSubscriptionModel.fromJson(data),
    );
  }

  /// تجديد اشتراك
  Future<ApiResponse<CitizenSubscriptionModel>> renewSubscription(
      String id) async {
    return _apiClient.post(
      '/citizen-portal/subscriptions/$id/renew',
      {},
      (data) => CitizenSubscriptionModel.fromJson(data),
    );
  }

  /// إلغاء اشتراك
  Future<ApiResponse<bool>> cancelSubscription(String id) async {
    return _apiClient.post(
      '/citizen-portal/subscriptions/$id/cancel',
      {},
      (data) => true,
    );
  }

  // ============================================
  // المدفوعات
  // ============================================

  /// جلب مدفوعات المواطنين
  Future<ApiResponse<List<CitizenPaymentModel>>> getPayments({
    int page = 1,
    int pageSize = 20,
    String? citizenId,
    String? status,
  }) async {
    var endpoint = '/citizen-portal/payments?page=$page&pageSize=$pageSize';
    if (citizenId != null) {
      endpoint += '&citizenId=$citizenId';
    }
    if (status != null) {
      endpoint += '&status=$status';
    }

    return _apiClient.get(
      endpoint,
      (data) =>
          (data as List).map((e) => CitizenPaymentModel.fromJson(e)).toList(),
    );
  }

  // ============================================
  // خطط الاشتراك
  // ============================================

  /// جلب خطط الاشتراك
  Future<ApiResponse<List<SubscriptionPlanModel>>> getPlans() async {
    return _apiClient.get(
      '/citizen-portal/plans',
      (data) =>
          (data as List).map((e) => SubscriptionPlanModel.fromJson(e)).toList(),
    );
  }

  /// إنشاء خطة اشتراك
  Future<ApiResponse<SubscriptionPlanModel>> createPlan(
      Map<String, dynamic> data) async {
    return _apiClient.post(
      '/citizen-portal/plans',
      data,
      (data) => SubscriptionPlanModel.fromJson(data),
    );
  }

  /// تحديث خطة اشتراك
  Future<ApiResponse<SubscriptionPlanModel>> updatePlan(
      String id, Map<String, dynamic> data) async {
    return _apiClient.put(
      '/citizen-portal/plans/$id',
      data,
      (data) => SubscriptionPlanModel.fromJson(data),
    );
  }

  /// حذف خطة اشتراك
  Future<ApiResponse<bool>> deletePlan(String id) async {
    return _apiClient.delete(
      '/citizen-portal/plans/$id',
      (data) => true,
    );
  }
}
