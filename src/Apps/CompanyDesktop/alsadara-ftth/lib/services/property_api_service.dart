/// طبقة اتصال سجل العقارات المستقل — تنادي بوّابة الصدارة `/api/properties/*`
/// عبر [SadaraApiService] (يُضاف Bearer token تلقائياً من مصادر التطبيق).
///
/// نظام أساسي (core) — ليس وحدة الساس. لا tokens ثابتة ولا منطق عرض هنا.
library;

import '../models/property.dart';
import 'sadara_api_service.dart';

/// صفحة نتائج العقارات (بيانات + ترقيم).
class PropertyPage {
  final List<Property> items;
  final int total;
  final int page;
  final int pageSize;

  const PropertyPage({
    required this.items,
    required this.total,
    required this.page,
    required this.pageSize,
  });

  bool get hasMore => page * pageSize < total;
}

/// تفاصيل العقار الكاملة (عقار + مواطنون + خدمات).
class PropertyDetails {
  final Property property;
  final List<PropertyResident> residents;
  final List<PropertyService> services;

  const PropertyDetails({
    required this.property,
    required this.residents,
    required this.services,
  });
}

/// نتيجة بحث منتقي المواطن.
class CitizenHit {
  final String id;
  final String name;
  final String phone;
  final String district;

  const CitizenHit({
    required this.id,
    required this.name,
    required this.phone,
    required this.district,
  });

  factory CitizenHit.fromJson(Map<String, dynamic> j) => CitizenHit(
        id: (j['id'] ?? j['Id'] ?? '').toString(),
        name: (j['name'] ?? j['Name'] ?? '').toString(),
        phone: (j['phone'] ?? j['Phone'] ?? '').toString(),
        district: (j['district'] ?? j['District'] ?? '').toString(),
      );
}

class PropertyApiService {
  PropertyApiService._();
  static final PropertyApiService instance = PropertyApiService._();

  SadaraApiService get _api => SadaraApiService.instance;

  // ─────────────────────────── العقارات ───────────────────────────

  /// قائمة العقارات مع بحث/تصفية/ترقيم.
  Future<PropertyPage> list({
    String? q,
    String? propertyType,
    String? ownership,
    int page = 1,
    int pageSize = 30,
  }) async {
    final params = <String, String>{
      if (q != null && q.trim().isNotEmpty) 'q': q.trim(),
      if (propertyType != null && propertyType.isNotEmpty)
        'propertyType': propertyType,
      if (ownership != null && ownership.isNotEmpty) 'ownership': ownership,
      'page': '$page',
      'pageSize': '$pageSize',
    };
    final query = params.entries
        .map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}')
        .join('&');
    final res = await _api.get('/properties?$query');
    final data = (res['data'] as List?) ?? const [];
    final items = data
        .whereType<Map>()
        .map((e) => Property.fromJson(e.cast<String, dynamic>()))
        .toList();
    return PropertyPage(
      items: items,
      total: _asInt(res['total']) == 0 && items.isNotEmpty
          ? items.length
          : _asInt(res['total']),
      page: _asInt(res['page']) == 0 ? page : _asInt(res['page']),
      pageSize:
          _asInt(res['pageSize']) == 0 ? pageSize : _asInt(res['pageSize']),
    );
  }

  /// تفاصيل عقار بالمعرّف.
  Future<PropertyDetails> getById(String id) async {
    final res = await _api.get('/properties/$id');
    return _parseDetails(res);
  }

  /// حلّ عقار من رمز الـQR الدائم.
  Future<PropertyDetails> getByQr(String token) async {
    final res = await _api.get('/properties/by-qr/${Uri.encodeComponent(token)}');
    return _parseDetails(res);
  }

  /// إنشاء عقار جديد — يُرجع معرّف العقار المُنشأ (إن توفّر).
  Future<String?> create({
    required int govCode,
    required String governorate,
    required String area,
    required String district,
    required String landmark,
    required String addressDetails,
    double? latitude,
    double? longitude,
    required String propertyType,
    required String ownership,
    String notes = '',
  }) async {
    final res = await _api.post('/properties', body: {
      'govCode': govCode,
      'governorate': governorate,
      'area': area,
      'district': district,
      'landmark': landmark,
      'addressDetails': addressDetails,
      'latitude': latitude,
      'longitude': longitude,
      'propertyType': propertyType,
      'ownership': ownership,
      'notes': notes,
    });
    final data = res['data'];
    if (data is Map) {
      return (data['id'] ?? data['Id'])?.toString();
    }
    return (res['id'] ?? res['Id'])?.toString();
  }

  /// تعديل جزئي لعقار (يُرسل فقط الحقول المُمرَّرة).
  Future<void> update(String id, Map<String, dynamic> patch) async {
    await _api.put('/properties/$id', body: patch);
  }

  /// حذف عقار.
  Future<void> delete(String id) async {
    await _api.delete('/properties/$id');
  }

  // ─────────────────────────── المواطنون ───────────────────────────

  /// منتقي المواطن — بحث بالاسم/الهاتف.
  Future<List<CitizenHit>> searchCitizens(String q) async {
    final query = q.trim().isEmpty ? '' : '?q=${Uri.encodeQueryComponent(q.trim())}';
    final res = await _api.get('/properties/citizens$query');
    final data = (res['data'] as List?) ?? const [];
    return data
        .whereType<Map>()
        .map((e) => CitizenHit.fromJson(e.cast<String, dynamic>()))
        .toList();
  }

  /// ربط مواطن بعقار.
  Future<void> addResident(
    String propertyId, {
    required String citizenId,
    required String relationship, // Owner / Tenant / Resident
    bool isPrimary = false,
  }) async {
    await _api.post('/properties/$propertyId/residents', body: {
      'citizenId': citizenId,
      'relationship': relationship,
      'isPrimary': isPrimary,
    });
  }

  /// فكّ ربط مواطن عن عقار.
  Future<void> removeResident(String propertyId, String residentId) async {
    await _api.delete('/properties/$propertyId/residents/$residentId');
  }

  // ─────────────────────────── الخدمات ───────────────────────────

  /// إضافة خدمة لعقار.
  Future<void> addService(
    String propertyId, {
    required String serviceType, // Internet / Master / Iptv / Other
    required String providerType, // Sas / Ftth / External
    String providerRefId = '',
    String subscriberRef = '',
    required String status, // Active / Suspended / Ended
    String? startDate,
    String? endDate,
    String notes = '',
  }) async {
    await _api.post('/properties/$propertyId/services', body: {
      'serviceType': serviceType,
      'providerType': providerType,
      'providerRefId': providerRefId,
      'subscriberRef': subscriberRef,
      'status': status,
      'startDate': startDate,
      'endDate': endDate,
      'notes': notes,
    });
  }

  /// تعديل خدمة (جزئي).
  Future<void> updateService(
      String propertyId, String serviceId, Map<String, dynamic> patch) async {
    await _api.put('/properties/$propertyId/services/$serviceId', body: patch);
  }

  /// حذف خدمة.
  Future<void> deleteService(String propertyId, String serviceId) async {
    await _api.delete('/properties/$propertyId/services/$serviceId');
  }

  // ─────────────────────────── داخلي ───────────────────────────

  PropertyDetails _parseDetails(Map<String, dynamic> res) {
    // الاستجابة: {success,data:{عقار}, residents:[...], services:[...]}
    // residents/services قد تأتي داخل data أو في الجذر.
    final data = (res['data'] as Map?)?.cast<String, dynamic>() ?? res;

    final residentsRaw =
        (res['residents'] ?? data['residents'] ?? data['Residents']) as List? ??
            const [];
    final servicesRaw =
        (res['services'] ?? data['services'] ?? data['Services']) as List? ??
            const [];

    final residents = residentsRaw
        .whereType<Map>()
        .map((e) => PropertyResident.fromJson(e.cast<String, dynamic>()))
        .toList();
    final services = servicesRaw
        .whereType<Map>()
        .map((e) => PropertyService.fromJson(e.cast<String, dynamic>()))
        .toList();

    final property = Property.fromJson(
      data,
      residents: residents,
      services: services,
    );
    return PropertyDetails(
      property: property,
      residents: residents,
      services: services,
    );
  }

  int _asInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse('${v ?? ''}') ?? 0;
  }
}
