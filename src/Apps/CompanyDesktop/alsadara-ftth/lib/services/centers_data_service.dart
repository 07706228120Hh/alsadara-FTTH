/// خدمة جلب مراكز الشركة من API
/// تُستخدم في جميع الأماكن التي تحتاج قائمة المراكز (نماذج الموظفين، الحضور، إلخ)
library;

import 'package:flutter/foundation.dart';
import 'sadara_api_service.dart';
import 'vps_auth_service.dart';

class CentersDataService {
  // Singleton
  static CentersDataService? _instance;
  static CentersDataService get instance =>
      _instance ??= CentersDataService._internal();
  CentersDataService._internal();

  // البيانات المخزنة مؤقتاً
  List<String> _centerNames = [];
  List<Map<String, dynamic>> _centers = [];
  DateTime? _lastFetch;

  /// مدة صلاحية الكاش (5 دقائق)
  static const _cacheDuration = Duration(minutes: 5);

  /// أسماء المراكز (للاستخدام في dropdowns)
  List<String> get centerNames => List.unmodifiable(_centerNames);

  /// بيانات المراكز الكاملة
  List<Map<String, dynamic>> get centers => List.unmodifiable(_centers);

  /// هل البيانات محملة؟
  bool get isLoaded => _centerNames.isNotEmpty;

  /// جلب المراكز من API (مع كاش)
  Future<List<String>> fetchCenters({bool forceRefresh = false}) async {
    // إرجاع الكاش إذا كان صالحاً
    if (!forceRefresh &&
        _centerNames.isNotEmpty &&
        _lastFetch != null &&
        DateTime.now().difference(_lastFetch!) < _cacheDuration) {
      return _centerNames;
    }

    final companyId = VpsAuthService.instance.currentCompanyId;
    if (companyId == null || companyId.isEmpty) {
      debugPrint('⚠️ CentersDataService: لا يوجد companyId');
      return _centerNames;
    }

    try {
      final response =
          await SadaraApiService.instance.get('/companies/$companyId/centers');

      if (response['success'] == true && response['data'] != null) {
        final data = response['data'] as List;
        _centers =
            data.map((d) => Map<String, dynamic>.from(d as Map)).toList();
        _centerNames = _centers
            .where((c) => (c['IsActive'] ?? c['isActive']) == true)
            .map((c) => (c['Name'] ?? c['name'])?.toString() ?? '')
            .where((n) => n.isNotEmpty)
            .toList();

        _lastFetch = DateTime.now();
        debugPrint('✅ CentersDataService: تم جلب ${_centerNames.length} مركز');
      }
    } catch (e) {
      debugPrint('❌ CentersDataService: خطأ في جلب المراكز: $e');
    }

    return _centerNames;
  }

  /// جلب بيانات مركز معين بالاسم
  Map<String, dynamic>? getCenterByName(String name) {
    try {
      return _centers.firstWhere(
        (c) => (c['Name'] ?? c['name'])?.toString() == name,
      );
    } catch (_) {
      return null;
    }
  }

  /// مسح الكاش (عند تغيير المراكز)
  void clearCache() {
    _centerNames = [];
    _centers = [];
    _lastFetch = null;
  }
}
