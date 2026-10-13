/// طبقة اتصال سجل العقارات المستقل — تنادي بوّابة الصدارة `/api/properties/*`
/// عبر [SadaraApiService] (يُضاف Bearer token تلقائياً من مصادر التطبيق).
///
/// نظام أساسي (core) — ليس وحدة الساس. لا tokens ثابتة ولا منطق عرض هنا.
library;

import 'dart:io';

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

/// دفعة رموز QR فارغة مُولَّدة مسبقاً (مخزون) — للطباعة الشبكية ثم الملء بالمسح.
class PropertyQrBatch {
  final String batchId;
  final int count;
  final int usedCount;
  final String note;
  final String createdAt;

  const PropertyQrBatch({
    required this.batchId,
    required this.count,
    required this.usedCount,
    required this.note,
    required this.createdAt,
  });

  int get remaining => (count - usedCount) < 0 ? 0 : (count - usedCount);

  factory PropertyQrBatch.fromJson(Map<String, dynamic> j) => PropertyQrBatch(
        batchId: (j['batchId'] ?? j['BatchId'] ?? j['id'] ?? j['Id'] ?? '')
            .toString(),
        count: _toInt(j['count'] ?? j['Count']),
        usedCount: _toInt(j['usedCount'] ?? j['UsedCount'] ?? j['used_count']),
        note: (j['note'] ?? j['Note'] ?? '').toString(),
        createdAt:
            (j['createdAt'] ?? j['CreatedAt'] ?? j['created_at'] ?? '').toString(),
      );

  static int _toInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse('${v ?? ''}') ?? 0;
  }
}

/// رمز QR ضمن دفعة مخزون — تسلسل + الرمز + حالته (مُستخدم/فارغ).
class PropertyQrToken {
  final int serial;
  final String qrToken;
  final String status; // Unused / Used (كما يردّها الخادم)
  final String? propertyId; // العقار المرتبط (عند الاستخدام)
  final String npn; // رقم العقار الوطني للعرض (فارغ إن لم يُربط بعد)

  const PropertyQrToken({
    required this.serial,
    required this.qrToken,
    required this.status,
    this.propertyId,
    this.npn = '',
  });

  /// حمولة الـQR المطبوعة (نفس صيغة لصاقة العقار).
  String get payload => 'SADARA|P:$qrToken';
  bool get isUsed => status.toLowerCase() == 'used';

  factory PropertyQrToken.fromJson(Map<String, dynamic> j) => PropertyQrToken(
        serial: PropertyQrBatch._toInt(j['serial'] ?? j['Serial']),
        qrToken: (j['qrToken'] ?? j['QrToken'] ?? j['qr_token'] ?? '').toString(),
        status: (j['status'] ?? j['Status'] ?? '').toString(),
        propertyId: (j['propertyId'] ?? j['PropertyId'])?.toString(),
        npn: (j['npn'] ?? j['Npn'] ?? j['npnDisplay'] ?? '').toString(),
      );
}

/// نتيجة حلّ رمز QR من [PropertyApiService.getByQr]:
/// إمّا عقار موجود [details]، وإمّا رمز مخزون فارغ ([blank] == true).
class PropertyQrResolveResult {
  /// تفاصيل العقار إن كان الرمز مربوطاً بعقار.
  final PropertyDetails? details;

  /// صحيح إن كان الرمز موجوداً في المخزون لكنه غير مُستخدَم بعد.
  final bool blank;

  /// رمز الـQR (يُعاد في حالة الفراغ لتمريره لنموذج الإنشاء).
  final String qrToken;

  /// الرقم التسلسلي ومعرّف الدفعة (للعرض فقط — في حالة الفراغ).
  final int serial;
  final String batchId;

  const PropertyQrResolveResult._({
    this.details,
    this.blank = false,
    this.qrToken = '',
    this.serial = 0,
    this.batchId = '',
  });

  bool get isProperty => details != null;

  factory PropertyQrResolveResult.property(PropertyDetails d) =>
      PropertyQrResolveResult._(details: d);

  factory PropertyQrResolveResult.blankToken({
    required String qrToken,
    int serial = 0,
    String batchId = '',
  }) =>
      PropertyQrResolveResult._(
        blank: true,
        qrToken: qrToken,
        serial: serial,
        batchId: batchId,
      );
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

  /// حلّ عقار من رمز الـQR الدائم (استخدام مباشر إن كان الرمز مربوطاً بعقار).
  ///
  /// مُبقاة للتوافق — ترمي إن كان الرمز فارغاً (مخزون غير مُستخدم). للتفريق بين
  /// «عقار» و«رمز فارغ» استخدم [resolveQr].
  Future<PropertyDetails> getByQr(String token) async {
    final res =
        await _api.get('/properties/by-qr/${Uri.encodeComponent(token)}');
    if (_isBlankTokenResponse(res)) {
      throw Exception('رمز فارغ — لا عقار مربوط بهذا الرمز بعد');
    }
    return _parseDetails(res);
  }

  /// حلّ رمز QR ويُميّز بين عقار موجود ورمز مخزون **فارغ** (blank==true).
  ///
  /// - عقار → [PropertyQrResolveResult.isProperty] صحيح مع [details].
  /// - رمز فارغ → [PropertyQrResolveResult.blank] صحيح مع [qrToken]/[serial].
  /// - رمز غير معروف (404) → ترمي استثناءً (يعالجه المستدعي كـ«رمز غير معروف»).
  Future<PropertyQrResolveResult> resolveQr(String token) async {
    final res =
        await _api.get('/properties/by-qr/${Uri.encodeComponent(token)}');
    if (_isBlankTokenResponse(res)) {
      final data = (res['data'] as Map?)?.cast<String, dynamic>() ?? res;
      return PropertyQrResolveResult.blankToken(
        qrToken: (data['qrToken'] ??
                data['QrToken'] ??
                data['qr_token'] ??
                res['qrToken'] ??
                token)
            .toString(),
        serial: _asInt(
            data['serial'] ?? data['Serial'] ?? res['serial'] ?? res['Serial']),
        batchId: (data['batchId'] ??
                data['BatchId'] ??
                res['batchId'] ??
                res['BatchId'] ??
                '')
            .toString(),
      );
    }
    return PropertyQrResolveResult.property(_parseDetails(res));
  }

  /// صحيح إن كانت الاستجابة تمثّل رمزاً فارغاً (blank==true) بدل عقار.
  bool _isBlankTokenResponse(Map<String, dynamic> res) {
    bool flag(dynamic v) => v == true || '$v'.toLowerCase() == 'true';
    if (flag(res['blank']) || flag(res['Blank'])) return true;
    final data = res['data'];
    if (data is Map) {
      return flag(data['blank']) || flag(data['Blank']);
    }
    return false;
  }

  // ─────────────────── دفعات رموز QR الفارغة (المخزون) ───────────────────

  /// توليد دفعة رموز QR فارغة مسبقاً بعدد [count] (+ملاحظة اختيارية).
  /// يُرجع الدفعة المُنشأة. الخادم يفرض العزل/الحدود.
  Future<PropertyQrBatch> generateQrBatch(int count, {String? note}) async {
    final res = await _api.post('/properties/qr-batches', body: {
      'count': count,
      if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
    });
    final data = (res['data'] as Map?)?.cast<String, dynamic>() ?? res;
    return PropertyQrBatch.fromJson(data);
  }

  /// قائمة دفعات رموز QR (معزولة بالشركة في الخادم).
  Future<List<PropertyQrBatch>> listQrBatches() async {
    final res = await _api.get('/properties/qr-batches');
    final data = (res['data'] as List?) ?? const [];
    return data
        .whereType<Map>()
        .map((e) => PropertyQrBatch.fromJson(e.cast<String, dynamic>()))
        .toList();
  }

  /// رموز دفعة محدّدة ضمن نطاق تسلسل [fromSerial]..[toSerial] (اختياريان).
  /// يُستخدم للطباعة الشبكية على دفعات/صفحات محدودة (تفادي توليد الآلاف دفعةً).
  Future<List<PropertyQrToken>> getBatchTokens(
    String batchId, {
    int? fromSerial,
    int? toSerial,
  }) async {
    final params = <String, String>{
      if (fromSerial != null) 'fromSerial': '$fromSerial',
      if (toSerial != null) 'toSerial': '$toSerial',
    };
    final query = params.isEmpty
        ? ''
        : '?${params.entries.map((e) => '${e.key}=${e.value}').join('&')}';
    final res = await _api
        .get('/properties/qr-batches/${Uri.encodeComponent(batchId)}/tokens$query');
    final data = (res['data'] as List?) ?? const [];
    return data
        .whereType<Map>()
        .map((e) => PropertyQrToken.fromJson(e.cast<String, dynamic>()))
        .toList();
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
    String ownerName = '',
    String ownerPhone = '',
    String address2 = '',
    String address3 = '',
    String? regionId,
    String? address2Id,
    String? address3Id,
    String? qrToken,
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
      'ownerName': ownerName,
      'ownerPhone': ownerPhone,
      'address2': address2,
      'address3': address3,
      'regionId': regionId,
      'address2Id': address2Id,
      'address3Id': address3Id,
      // رمز مخزون مطبوع مسبقاً (اختياري) — يربط العقار بالرمز عند الملء بالمسح.
      if (qrToken != null && qrToken.trim().isNotEmpty) 'qrToken': qrToken.trim(),
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
    String agentName = '',
    String accountNumber = '',
    String? masterPhotoPath,
    String? civilIdPhotoPath,
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
      'agentName': agentName,
      'accountNumber': accountNumber,
      'masterPhotoPath': masterPhotoPath,
      'civilIdPhotoPath': civilIdPhotoPath,
    });
  }

  // ─────────────────────────── الصور (حسّاسة/مُصرّحة) ───────────────────────────

  /// رفع صورة خدمة (ماستر/هوية) — multipart، الحقل `file`.
  /// يُرجع اسم الملف المحفوظ (data.fileName) ليُخزَّن في مسار الصورة.
  Future<String?> uploadImage(File file) async {
    final res = await _api.uploadFile('/properties/upload-image', file);
    final data = res['data'];
    if (data is Map) {
      return (data['fileName'] ?? data['FileName'] ?? data['file_name'])
          ?.toString();
    }
    return (res['fileName'] ?? res['FileName'])?.toString();
  }

  /// تحميل بايتات صورة مُصرّحة (Bearer يُحقن تلقائياً) — لا URL عام.
  Future<List<int>> imageBytes(String fileName) {
    return _api.getBytes('/properties/image/$fileName');
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

  // ─────────────────────────── المهام المرتبطة ───────────────────────────

  /// مهام (طلبات) العقار المرتبطة من نظام المهام.
  Future<List<PropertyTaskHit>> getTasks(String propertyId) async {
    final res = await _api.get('/properties/$propertyId/tasks');
    final data = (res['data'] as List?) ?? const [];
    return data
        .whereType<Map>()
        .map((e) => PropertyTaskHit.fromJson(e.cast<String, dynamic>()))
        .toList();
  }

  /// الخدمات وعملياتها — لمنتقي إنشاء مهمة مرتبطة بالعقار.
  Future<List<ServiceLookup>> getServiceLookups() async {
    final res = await _api.get('/properties/service-lookups');
    final data = (res['data'] as List?) ?? const [];
    return data
        .whereType<Map>()
        .map((e) => ServiceLookup.fromJson(e.cast<String, dynamic>()))
        .toList();
  }

  /// إنشاء مهمة مرتبطة بعقار — يُرجع رقم الطلب (requestNumber) عند النجاح.
  /// الباكند يملأ العنوان/الهاتف/المواطن من العقار تلقائياً.
  Future<String?> createTask(
    String propertyId, {
    required int serviceId,
    required int operationTypeId,
    int? priority,
    String? department,
    String? technician,
    String? note,
  }) async {
    final res = await _api.post('/properties/$propertyId/tasks', body: {
      'serviceId': serviceId,
      'operationTypeId': operationTypeId,
      if (priority != null) 'priority': priority,
      if (department != null && department.trim().isNotEmpty)
        'department': department.trim(),
      if (technician != null && technician.trim().isNotEmpty)
        'technician': technician.trim(),
      if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
    });
    final data = res['data'];
    if (data is Map) {
      return (data['requestNumber'] ??
              data['RequestNumber'] ??
              data['request_number'])
          ?.toString();
    }
    return null;
  }

  // ─────────────────────────── المناطق ───────────────────────────

  /// قائمة المناطق (المستوى الأعلى) — معزولة بالشركة في الباكند.
  Future<List<PropRegion>> getRegions() async {
    final res = await _api.get('/properties/regions');
    final data = (res['data'] as List?) ?? const [];
    return data
        .whereType<Map>()
        .map((e) => PropRegion.fromJson(e.cast<String, dynamic>()))
        .toList();
  }

  /// إنشاء منطقة — يُرجع معرّفها عند النجاح.
  Future<String?> createRegion({
    required String name,
    String? code,
    String? governorate,
    String? city,
    num maintenanceFee = 0,
    bool isActive = true,
    String? notes,
  }) async {
    final res = await _api.post('/properties/regions', body: {
      'name': name,
      if (code != null) 'code': code,
      if (governorate != null) 'governorate': governorate,
      if (city != null) 'city': city,
      'maintenanceFee': maintenanceFee,
      'isActive': isActive,
      if (notes != null) 'notes': notes,
    });
    return _extractId(res);
  }

  /// تعديل منطقة — يُرسل فقط الحقول المُمرَّرة عبر [patch].
  Future<void> updateRegion(String id, Map<String, dynamic> patch) async {
    await _api.put('/properties/regions/$id', body: patch);
  }

  /// حذف منطقة — قد يرمي الخادم 409 إن كانت مرتبطة (الرسالة تُمرَّر كما هي).
  Future<void> deleteRegion(String id) async {
    await _api.delete('/properties/regions/$id');
  }

  // ─────────────────────────── العنوان 2 ───────────────────────────

  /// عناوين المستوى الثاني تحت منطقة.
  Future<List<AddressNode>> getAddress2(String regionId) async {
    final res = await _api
        .get('/properties/address2?regionId=${Uri.encodeQueryComponent(regionId)}');
    final data = (res['data'] as List?) ?? const [];
    return data
        .whereType<Map>()
        .map((e) =>
            AddressNode.fromJson(e.cast<String, dynamic>(), parentId: regionId))
        .toList();
  }

  /// إنشاء عنوان 2 تحت منطقة — يُرجع معرّفه.
  Future<String?> createAddress2(String regionId, String name,
      {num maintenanceFee = 0, bool isActive = true}) async {
    final res = await _api.post('/properties/address2', body: {
      'parentId': regionId,
      'name': name,
      'maintenanceFee': maintenanceFee,
      'isActive': isActive,
    });
    return _extractId(res);
  }

  /// تعديل عنوان 2 — يُرسل فقط الحقول المُمرَّرة.
  Future<void> updateAddress2(String id,
      {String? name, num? maintenanceFee, bool? isActive}) async {
    await _api.put('/properties/address2/$id', body: {
      if (name != null) 'name': name,
      if (maintenanceFee != null) 'maintenanceFee': maintenanceFee,
      if (isActive != null) 'isActive': isActive,
    });
  }

  /// حذف عنوان 2 — قد يرمي الخادم 409 (الرسالة تُمرَّر كما هي).
  Future<void> deleteAddress2(String id) async {
    await _api.delete('/properties/address2/$id');
  }

  // ─────────────────────────── العنوان 3 ───────────────────────────

  /// عناوين المستوى الثالث تحت عنوان 2.
  Future<List<AddressNode>> getAddress3(String address2Id) async {
    final res = await _api.get(
        '/properties/address3?address2Id=${Uri.encodeQueryComponent(address2Id)}');
    final data = (res['data'] as List?) ?? const [];
    return data
        .whereType<Map>()
        .map((e) => AddressNode.fromJson(e.cast<String, dynamic>(),
            parentId: address2Id))
        .toList();
  }

  /// إنشاء عنوان 3 تحت عنوان 2 — يُرجع معرّفه.
  Future<String?> createAddress3(String address2Id, String name,
      {num maintenanceFee = 0, bool isActive = true}) async {
    final res = await _api.post('/properties/address3', body: {
      'parentId': address2Id,
      'name': name,
      'maintenanceFee': maintenanceFee,
      'isActive': isActive,
    });
    return _extractId(res);
  }

  /// تعديل عنوان 3 — يُرسل فقط الحقول المُمرَّرة.
  Future<void> updateAddress3(String id,
      {String? name, num? maintenanceFee, bool? isActive}) async {
    await _api.put('/properties/address3/$id', body: {
      if (name != null) 'name': name,
      if (maintenanceFee != null) 'maintenanceFee': maintenanceFee,
      if (isActive != null) 'isActive': isActive,
    });
  }

  /// حذف عنوان 3 — قد يرمي الخادم 409 (الرسالة تُمرَّر كما هي).
  Future<void> deleteAddress3(String id) async {
    await _api.delete('/properties/address3/$id');
  }

  // ─────────────────────────── أجر الصيانة التراكمي ───────────────────────────

  /// يحسب أجر الصيانة الإجمالي التراكمي (منطقة + عنوان2 + عنوان3) عبر الخادم.
  ///
  /// كل المعاملات اختيارية؛ المجموع = جمع المستويات المُمرَّرة الموجودة.
  /// يُرجع `data.total` كـ[num] (0 إن لم يُمرَّر أي مستوى أو غابت القيمة).
  Future<num> computeMaintenanceFee({
    String? regionId,
    String? address2Id,
    String? address3Id,
  }) async {
    final params = <String, String>{
      if (regionId != null && regionId.isNotEmpty) 'regionId': regionId,
      if (address2Id != null && address2Id.isNotEmpty) 'address2Id': address2Id,
      if (address3Id != null && address3Id.isNotEmpty) 'address3Id': address3Id,
    };
    if (params.isEmpty) return 0;
    final query = params.entries
        .map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}')
        .join('&');
    final res = await _api.get('/properties/maintenance-fee?$query');
    final data = (res['data'] as Map?)?.cast<String, dynamic>();
    final total = data?['total'] ?? data?['Total'] ?? res['total'] ?? res['Total'];
    if (total is num) return total;
    return num.tryParse('${total ?? ''}') ?? 0;
  }

  // ─────────────────────────── داخلي ───────────────────────────

  /// يستخرج المعرّف المُنشأ من استجابة `{success,id}` أو `{data:{id}}`.
  String? _extractId(Map<String, dynamic> res) {
    final data = res['data'];
    if (data is Map) {
      return (data['id'] ?? data['Id'])?.toString();
    }
    return (res['id'] ?? res['Id'])?.toString();
  }

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
