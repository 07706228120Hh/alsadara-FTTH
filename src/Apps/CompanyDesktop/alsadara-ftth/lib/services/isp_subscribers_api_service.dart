import 'api_service.dart';

/// خدمة بيانات مشتركي الإنترنت عبر VPS API
class ISPSubscribersApiService {
  static ISPSubscribersApiService? _instance;
  static ISPSubscribersApiService get instance =>
      _instance ??= ISPSubscribersApiService._internal();
  ISPSubscribersApiService._internal();

  final ApiService _api = ApiService.instance;

  /// جلب جميع المشتركين مع التصفية
  Future<Map<String, dynamic>> getAll({
    String? region,
    String? search,
    int page = 1,
    int pageSize = 50,
  }) async {
    String url = '/ispsubscribers?page=$page&pageSize=$pageSize';
    if (region != null && region.isNotEmpty) url += '&region=$region';
    if (search != null && search.isNotEmpty) url += '&search=$search';

    return await _api.get(url);
  }

  /// جلب قائمة المناطق
  Future<List<String>> getRegions() async {
    final response = await _api.get('/ispsubscribers/regions');
    final data = response['data'];
    if (data is List) {
      return data.map((r) => r.toString()).toList();
    }
    return [];
  }

  /// بحث القرابة (يدعم البحث الغامض)
  Future<List<Map<String, dynamic>>> kinshipSearch({
    String? name,
    String? motherName,
    String? region,
  }) async {
    String url = '/ispsubscribers/kinship-search';
    List<String> params = [];
    if (name != null && name.isNotEmpty) params.add('name=$name');
    if (motherName != null && motherName.isNotEmpty) {
      params.add('motherName=$motherName');
    }
    if (region != null && region.isNotEmpty) params.add('region=$region');
    if (params.isNotEmpty) url += '?${params.join('&')}';

    final response = await _api.get(url);
    final data = response['data'];
    if (data is List) {
      return List<Map<String, dynamic>>.from(data);
    }
    return [];
  }

  /// جلب مشتركين حسب المنطقة
  Future<List<Map<String, dynamic>>> getByRegion(String region) async {
    final response = await _api.get('/ispsubscribers/by-region/$region');
    final data = response['data'];
    if (data is List) {
      return List<Map<String, dynamic>>.from(data);
    }
    return [];
  }

  /// إضافة مشترك جديد
  Future<Map<String, dynamic>> create({
    required String name,
    String? region,
    String? agent,
    String? dash,
    String? motherName,
    String? phoneNumber,
    String? companyId,
  }) async {
    return await _api.post('/ispsubscribers', body: {
      'Name': name,
      'Region': region,
      'Agent': agent,
      'Dash': dash,
      'MotherName': motherName,
      'PhoneNumber': phoneNumber,
      'CompanyId': companyId,
    });
  }

  /// إضافة مشتركين بالجملة (استيراد)
  Future<Map<String, dynamic>> bulkCreate(
      List<Map<String, dynamic>> subscribers) async {
    return await _api.post('/ispsubscribers/bulk', body: subscribers);
  }

  /// حذف مشترك
  Future<void> delete(int id) async {
    await _api.delete('/ispsubscribers/$id');
  }
}
