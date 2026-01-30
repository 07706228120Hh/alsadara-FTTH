import '../models/company_model.dart';
import '../services/company_api_service.dart';

/// خدمة مساعدة للتحقق من الشركة المرتبطة بنظام المواطن
class CitizenPortalHelper {
  static CompanyModel? _cachedLinkedCompany;
  static DateTime? _lastFetchTime;
  static const Duration cacheExpiration = Duration(minutes: 5);

  /// التحقق من أن الشركة الحالية هي المرتبطة بنظام المواطن
  /// يستخدم Cache لتقليل استدعاءات API
  static Future<bool> isLinkedCompany(String companyId) async {
    try {
      final linkedId = await CompanyApiService.getLocalLinkedCompanyId();
      return linkedId == companyId;
    } catch (e) {
      print('خطأ في التحقق من الشركة المرتبطة: $e');
      return false;
    }
  }

  /// الحصول على الشركة المرتبطة (مع Cache)
  static Future<CompanyModel?> getLinkedCompany() async {
    try {
      final linkedId = await CompanyApiService.getLocalLinkedCompanyId();
      if (linkedId == null) return null;

      // إرجاع نموذج بسيط بالمعرف فقط
      return CompanyModel(
        id: linkedId,
        name: '',
        code: '',
        isActive: true,
        subscriptionStartDate: DateTime.now(),
        subscriptionEndDate: DateTime.now().add(const Duration(days: 365)),
        subscriptionPlan: 'basic',
        maxUsers: 10,
        daysRemaining: 365,
        isExpired: false,
        isLinkedToCitizenPortal: true,
        createdAt: DateTime.now(),
      );
    } catch (e) {
      print('خطأ في جلب الشركة المرتبطة: $e');
      return null;
    }
  }

  /// الحصول على معرف الشركة المرتبطة
  static Future<String?> getLinkedCompanyId() async {
    return await CompanyApiService.getLocalLinkedCompanyId();
  }

  /// مسح الـ Cache (عند تحديث الربط)
  static void clearCache() {
    _cachedLinkedCompany = null;
    _lastFetchTime = null;
  }
}
