import 'api_service.dart';

/// خدمة الحضور والانصراف عبر VPS API
class AttendanceApiService {
  static AttendanceApiService? _instance;
  static AttendanceApiService get instance =>
      _instance ??= AttendanceApiService._internal();
  AttendanceApiService._internal();

  final ApiService _api = ApiService.instance;

  /// تسجيل حضور
  Future<Map<String, dynamic>> checkIn({
    required String userId,
    required String userName,
    String? companyId,
    String? centerName,
    double? latitude,
    double? longitude,
    String? securityCode,
  }) async {
    return await _api.post('/attendance/checkin', body: {
      'UserId': userId,
      'UserName': userName,
      'CompanyId': companyId,
      'CenterName': centerName,
      'Latitude': latitude,
      'Longitude': longitude,
      'SecurityCode': securityCode,
    });
  }

  /// تسجيل انصراف
  Future<Map<String, dynamic>> checkOut({
    required String userId,
    double? latitude,
    double? longitude,
    String? notes,
  }) async {
    return await _api.post('/attendance/checkout', body: {
      'UserId': userId,
      'Latitude': latitude,
      'Longitude': longitude,
      'Notes': notes,
    });
  }

  /// جلب سجل الحضور الشهري لموظف
  Future<Map<String, dynamic>> getMonthlyAttendance({
    required String userId,
    int? year,
    int? month,
  }) async {
    String url = '/attendance/$userId/monthly';
    List<String> params = [];
    if (year != null) params.add('year=$year');
    if (month != null) params.add('month=$month');
    if (params.isNotEmpty) url += '?${params.join('&')}';

    final response = await _api.get(url);
    final data = response['data'];
    if (data is Map<String, dynamic>) return data;
    return response;
  }

  /// جلب حضور جميع الموظفين لتاريخ معين
  Future<List<Map<String, dynamic>>> getDailyAttendance({
    String? date,
    String? companyId,
  }) async {
    String url = '/attendance/daily';
    List<String> params = [];
    if (date != null) params.add('date=$date');
    if (companyId != null) params.add('companyId=$companyId');
    if (params.isNotEmpty) url += '?${params.join('&')}';

    final response = await _api.get(url);
    final data = response['data'];
    if (data is List) return List<Map<String, dynamic>>.from(data);
    return [];
  }

  /// جلب مراكز العمل
  Future<List<Map<String, dynamic>>> getCenters({String? companyId}) async {
    String url = '/attendance/centers';
    if (companyId != null) url += '?companyId=$companyId';

    final response = await _api.get(url);
    final data = response['data'];
    if (data is List) return List<Map<String, dynamic>>.from(data);
    return [];
  }

  /// إضافة مركز عمل
  Future<Map<String, dynamic>> addCenter({
    required String name,
    required double latitude,
    required double longitude,
    double? radiusMeters,
    String? companyId,
  }) async {
    return await _api.post('/attendance/centers', body: {
      'Name': name,
      'Latitude': latitude,
      'Longitude': longitude,
      'RadiusMeters': radiusMeters ?? 200,
      'CompanyId': companyId,
    });
  }
}
