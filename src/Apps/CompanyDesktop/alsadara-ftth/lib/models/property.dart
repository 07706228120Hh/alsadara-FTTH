/// نماذج سجل العقارات المستقل — مطابقة لمخرجات بوّابة الصدارة `/api/properties`.
///
/// عرض/بيانات فقط — لا استدعاءات API ولا منطق أعمال هنا. القيم الوصفية بالإنجليزية
/// (كما يُرجعها الـAPI) تُترجَم للعرض عبر خرائط التسميات أدناه.
library;

/// مواطن مربوط بعقار (ساكن/مالك/مستأجر).
class PropertyResident {
  final String id;
  final String citizenId;
  final String name;
  final String phone;
  final String relationship; // Owner / Tenant / Resident
  final bool isPrimary;

  const PropertyResident({
    required this.id,
    required this.citizenId,
    required this.name,
    required this.phone,
    required this.relationship,
    required this.isPrimary,
  });

  factory PropertyResident.fromJson(Map<String, dynamic> j) => PropertyResident(
        id: _str(_pick(j, ['id', 'Id'])),
        citizenId: _str(_pick(j, ['citizenId', 'CitizenId', 'citizen_id'])),
        name: _str(_pick(j, ['name', 'Name'])),
        phone: _str(_pick(j, ['phone', 'Phone'])),
        relationship:
            _str(_pick(j, ['relationship', 'Relationship'])),
        isPrimary: _pick(j, ['isPrimary', 'IsPrimary', 'is_primary']) == true,
      );

  String get relationshipLabel => relationshipLabelOf(relationship);
}

/// خدمة مرتبطة بعقار (إنترنت/ماستر/IPTV/أخرى).
class PropertyService {
  final String id;
  final String serviceType; // Internet / Master / Iptv / Other
  final String providerType; // Sas / Ftth / External
  final String providerRefId;
  final String subscriberRef;
  final String status; // Active / Suspended / Ended
  final String startDate;
  final String endDate;
  final String notes;

  /// اسم الوكيل (لخدمة الإنترنت).
  final String? agentName;

  /// رقم الحساب (لخدمة الماستر).
  final String? accountNumber;

  /// اسم ملف صورة الماستر (حسّاس — يُعرض عبر imageBytes المُصرّح فقط).
  final String? masterPhotoPath;

  /// اسم ملف صورة هوية الأحوال المدنية (حسّاس — عبر imageBytes).
  final String? civilIdPhotoPath;

  /// مؤشّرات توافر الصور في الاستجابة (دون كشف المسار للعرض العام).
  final bool hasMasterPhoto;
  final bool hasCivilIdPhoto;

  const PropertyService({
    required this.id,
    required this.serviceType,
    required this.providerType,
    required this.providerRefId,
    required this.subscriberRef,
    required this.status,
    required this.startDate,
    required this.endDate,
    required this.notes,
    this.agentName,
    this.accountNumber,
    this.masterPhotoPath,
    this.civilIdPhotoPath,
    this.hasMasterPhoto = false,
    this.hasCivilIdPhoto = false,
  });

  factory PropertyService.fromJson(Map<String, dynamic> j) => PropertyService(
        id: _str(_pick(j, ['id', 'Id'])),
        serviceType:
            _str(_pick(j, ['serviceType', 'ServiceType', 'service_type'])),
        providerType:
            _str(_pick(j, ['providerType', 'ProviderType', 'provider_type'])),
        providerRefId: _str(
            _pick(j, ['providerRefId', 'ProviderRefId', 'provider_ref_id'])),
        subscriberRef: _str(
            _pick(j, ['subscriberRef', 'SubscriberRef', 'subscriber_ref'])),
        status: _str(_pick(j, ['status', 'Status'])),
        startDate: _str(_pick(j, ['startDate', 'StartDate', 'start_date'])),
        endDate: _str(_pick(j, ['endDate', 'EndDate', 'end_date'])),
        notes: _str(_pick(j, ['notes', 'Notes'])),
        agentName:
            _pickOrNull(j, ['agentName', 'AgentName', 'agent_name']),
        accountNumber: _pickOrNull(
            j, ['accountNumber', 'AccountNumber', 'account_number']),
        masterPhotoPath: _pickOrNull(
            j, ['masterPhotoPath', 'MasterPhotoPath', 'master_photo_path']),
        civilIdPhotoPath: _pickOrNull(j,
            ['civilIdPhotoPath', 'CivilIdPhotoPath', 'civil_id_photo_path']),
        hasMasterPhoto:
            _pick(j, ['hasMasterPhoto', 'HasMasterPhoto', 'has_master_photo']) ==
                true,
        hasCivilIdPhoto: _pick(j, [
              'hasCivilIdPhoto',
              'HasCivilIdPhoto',
              'has_civil_id_photo'
            ]) ==
            true,
      );

  String get serviceTypeLabel => serviceTypeLabelOf(serviceType);
  String get providerTypeLabel => providerTypeLabelOf(providerType);
  String get statusLabel => serviceStatusLabelOf(status);
}

/// مهمة (طلب) مرتبطة بعقار — من نظام المهام عبر `/properties/{id}/tasks`.
class PropertyTaskHit {
  final String id;
  final String requestNumber;
  final String status; // Pending / Assigned / Completed …
  final String department;
  final String technicianName;
  final int priority; // 1..5 (0 = غير محدّد)
  final String address;
  final String area;
  final String contactPhone;
  final String requestedAt;

  const PropertyTaskHit({
    required this.id,
    required this.requestNumber,
    required this.status,
    required this.department,
    required this.technicianName,
    required this.priority,
    required this.address,
    required this.area,
    required this.contactPhone,
    required this.requestedAt,
  });

  factory PropertyTaskHit.fromJson(Map<String, dynamic> j) => PropertyTaskHit(
        id: _str(_pick(j, ['id', 'Id'])),
        requestNumber:
            _str(_pick(j, ['requestNumber', 'RequestNumber', 'request_number'])),
        status: _str(_pick(j, ['status', 'Status'])),
        department: _str(_pick(j, ['department', 'Department'])),
        technicianName: _str(
            _pick(j, ['technicianName', 'TechnicianName', 'technician_name'])),
        priority: _asInt(_pick(j, ['priority', 'Priority'])),
        address: _str(_pick(j, ['address', 'Address'])),
        area: _str(_pick(j, ['area', 'Area'])),
        contactPhone: _str(
            _pick(j, ['contactPhone', 'ContactPhone', 'contact_phone'])),
        requestedAt: _str(_pick(
            j, ['requestedAt', 'RequestedAt', 'requested_at', 'createdAt',
                'CreatedAt', 'created_at'])),
      );

  String get statusLabel => taskStatusLabelOf(status);
}

/// عملية ضمن خدمة — لمنتقي إنشاء المهمة.
class OperationLookup {
  final int id;
  final String nameAr;
  final bool requiresTechnician;

  const OperationLookup({
    required this.id,
    required this.nameAr,
    required this.requiresTechnician,
  });

  factory OperationLookup.fromJson(Map<String, dynamic> j) => OperationLookup(
        id: _asInt(_pick(j, ['id', 'Id'])),
        nameAr: _str(_pick(j, ['nameAr', 'NameAr', 'name_ar'])),
        requiresTechnician: _pick(j, [
              'requiresTechnician',
              'RequiresTechnician',
              'requires_technician'
            ]) ==
            true,
      );
}

/// خدمة + عملياتها — لمنتقي إنشاء المهمة (`/properties/service-lookups`).
class ServiceLookup {
  final int id;
  final String nameAr;
  final List<OperationLookup> operations;

  const ServiceLookup({
    required this.id,
    required this.nameAr,
    required this.operations,
  });

  factory ServiceLookup.fromJson(Map<String, dynamic> j) {
    final opsRaw = (_pick(j, ['operations', 'Operations']) as List?) ?? const [];
    return ServiceLookup(
      id: _asInt(_pick(j, ['id', 'Id'])),
      nameAr: _str(_pick(j, ['nameAr', 'NameAr', 'name_ar'])),
      operations: opsRaw
          .whereType<Map>()
          .map((e) => OperationLookup.fromJson(e.cast<String, dynamic>()))
          .toList(),
    );
  }
}

/// العقار — عنوان وطني (QR + NPN + IqPin) + موقع + تصنيف.
class Property {
  final String id;
  final String qrToken;
  final String qrPayload;
  final String npn;
  final String npnDisplay;
  final String iqPin;
  final String iqPinDisplay;
  final int govCode;
  final String governorate;
  final String area;
  final String district;
  final String landmark;
  final String addressDetails;

  /// حقول العنوان/المالك الجديدة (اختيارية).
  final String? ownerName;
  final String? ownerPhone;
  final String? address2;
  final String? address3;
  final double? latitude;
  final double? longitude;
  final String propertyType; // Residential / Commercial
  final String ownership; // Owned / Rent
  final bool hasPhoto;
  final String notes;
  final String createdAt;

  /// عدد الخدمات المرتبطة (من قائمة الفهرس أو من التفاصيل).
  final int serviceCount;

  /// تُملأ فقط في استجابة التفاصيل / حلّ الـQR.
  final List<PropertyResident> residents;
  final List<PropertyService> services;

  const Property({
    required this.id,
    required this.qrToken,
    required this.qrPayload,
    required this.npn,
    required this.npnDisplay,
    required this.iqPin,
    required this.iqPinDisplay,
    required this.govCode,
    required this.governorate,
    required this.area,
    required this.district,
    required this.landmark,
    required this.addressDetails,
    this.ownerName,
    this.ownerPhone,
    this.address2,
    this.address3,
    this.latitude,
    this.longitude,
    required this.propertyType,
    required this.ownership,
    required this.hasPhoto,
    required this.notes,
    required this.createdAt,
    this.serviceCount = 0,
    this.residents = const [],
    this.services = const [],
  });

  factory Property.fromJson(
    Map<String, dynamic> j, {
    List<PropertyResident> residents = const [],
    List<PropertyService> services = const [],
  }) {
    final svc = services;
    final explicitCount =
        _pick(j, ['serviceCount', 'ServiceCount', 'service_count']);
    return Property(
      id: _str(_pick(j, ['id', 'Id'])),
      qrToken: _str(_pick(j, ['qrToken', 'QrToken', 'qr_token'])),
      qrPayload: _str(_pick(j, ['qrPayload', 'QrPayload', 'qr_payload'])),
      npn: _str(_pick(j, ['npn', 'Npn'])),
      npnDisplay: _str(_pick(j, ['npnDisplay', 'NpnDisplay', 'npn_display'])),
      iqPin: _str(_pick(j, ['iqPin', 'IqPin', 'iq_pin'])),
      iqPinDisplay:
          _str(_pick(j, ['iqPinDisplay', 'IqPinDisplay', 'iq_pin_display'])),
      govCode: _asInt(_pick(j, ['govCode', 'GovCode', 'gov_code'])),
      governorate: _str(_pick(j, ['governorate', 'Governorate'])),
      area: _str(_pick(j, ['area', 'Area'])),
      district: _str(_pick(j, ['district', 'District'])),
      landmark: _str(_pick(j, ['landmark', 'Landmark'])),
      addressDetails: _str(
          _pick(j, ['addressDetails', 'AddressDetails', 'address_details'])),
      ownerName: _pickOrNull(j, ['ownerName', 'OwnerName', 'owner_name']),
      ownerPhone:
          _pickOrNull(j, ['ownerPhone', 'OwnerPhone', 'owner_phone']),
      address2: _pickOrNull(j, ['address2', 'Address2', 'address_2']),
      address3: _pickOrNull(j, ['address3', 'Address3', 'address_3']),
      latitude: _asDouble(_pick(j, ['latitude', 'Latitude', 'lat', 'Lat'])),
      longitude: _asDouble(_pick(j, ['longitude', 'Longitude', 'lon', 'Lon'])),
      propertyType:
          _str(_pick(j, ['propertyType', 'PropertyType', 'property_type'])),
      ownership: _str(_pick(j, ['ownership', 'Ownership'])),
      hasPhoto: _pick(j, ['hasPhoto', 'HasPhoto', 'has_photo']) == true,
      notes: _str(_pick(j, ['notes', 'Notes'])),
      createdAt: _str(_pick(j, ['createdAt', 'CreatedAt', 'created_at'])),
      serviceCount: explicitCount != null ? _asInt(explicitCount) : svc.length,
      residents: residents,
      services: svc,
    );
  }

  bool get isCommercial =>
      propertyType.toLowerCase() == 'commercial';
  bool get isRent => ownership.toLowerCase() == 'rent';

  String get propertyTypeLabel => propertyTypeLabelOf(propertyType);
  String get ownershipLabel => ownershipLabelOf(ownership);

  /// عنوان مقروء مختصر (محافظة · منطقة · أقرب نقطة).
  String get shortAddress {
    final parts = [governorate, area, district, landmark]
        .where((s) => s.trim().isNotEmpty);
    return parts.take(3).join(' · ');
  }

  String get displayTitle =>
      npnDisplay.trim().isNotEmpty ? npnDisplay : 'عقار #$id';
}

// ─────────────────────────── تسميات العرض ───────────────────────────

/// قيم الـAPI (PascalCase إنجليزية) → تسمية عربية للعرض.
const Map<String, String> kPropertyTypeLabels = {
  'Residential': 'دار سكني',
  'Commercial': 'محل تجاري',
};
const Map<String, String> kOwnershipLabels = {
  'Owned': 'ملك',
  'Rent': 'إيجار',
};
const Map<String, String> kRelationshipLabels = {
  'Owner': 'مالك',
  'Tenant': 'مستأجر',
  'Resident': 'ساكن',
};
const Map<String, String> kServiceTypeLabels = {
  'Internet': 'إنترنت',
  'Master': 'ماستر',
  'Iptv': 'IPTV',
  'Other': 'أخرى',
};
const Map<String, String> kProviderTypeLabels = {
  'Sas': 'ساس',
  'Ftth': 'FTTH',
  'External': 'خارجي',
};
const Map<String, String> kServiceStatusLabels = {
  'Active': 'نشط',
  'Suspended': 'موقوف',
  'Ended': 'منتهٍ',
};
const Map<String, String> kTaskStatusLabels = {
  'Pending': 'قيد الانتظار',
  'Reviewing': 'قيد المراجعة',
  'Approved': 'موافَق',
  'Assigned': 'مُسندة',
  'InProgress': 'قيد التنفيذ',
  'Completed': 'مكتملة',
  'Cancelled': 'ملغاة',
  'Rejected': 'مرفوضة',
  'OnHold': 'معلّقة',
};

String _label(Map<String, String> map, String v) {
  if (map.containsKey(v)) return map[v]!;
  // تطابق غير حسّاس لحالة الأحرف (في حال اختلاف التهيئة من الـAPI)
  for (final e in map.entries) {
    if (e.key.toLowerCase() == v.toLowerCase()) return e.value;
  }
  return v.isEmpty ? '—' : v;
}

String propertyTypeLabelOf(String v) => _label(kPropertyTypeLabels, v);
String ownershipLabelOf(String v) => _label(kOwnershipLabels, v);
String relationshipLabelOf(String v) => _label(kRelationshipLabels, v);
String serviceTypeLabelOf(String v) => _label(kServiceTypeLabels, v);
String providerTypeLabelOf(String v) => _label(kProviderTypeLabels, v);
String serviceStatusLabelOf(String v) => _label(kServiceStatusLabels, v);
String taskStatusLabelOf(String v) => _label(kTaskStatusLabels, v);

// ─────────────────────────── محوّلات آمنة ───────────────────────────

/// أوّل قيمة غير-null من قائمة أسماء مفاتيح بديلة.
///
/// بوّابة الصدارة .NET قد تُسلسِل DTOs بـPascalCase، لذا نمرّر
/// camel/snake/Pascal معاً للأمان.
dynamic _pick(Map<String, dynamic> j, List<String> keys) {
  for (final k in keys) {
    final v = j[k];
    if (v != null) return v;
  }
  return null;
}

/// مثل [_pick] لكن يُرجع نصاً اختيارياً (null إن غاب أو كان فارغاً).
String? _pickOrNull(Map<String, dynamic> j, List<String> keys) {
  final v = _pick(j, keys);
  if (v == null) return null;
  final s = v.toString();
  return s.trim().isEmpty ? null : s;
}

String _str(dynamic v) => (v ?? '').toString();

int _asInt(dynamic v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse('${v ?? ''}') ?? 0;
}

double? _asDouble(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString());
}
