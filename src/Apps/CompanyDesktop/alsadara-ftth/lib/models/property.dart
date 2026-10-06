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
      );

  String get serviceTypeLabel => serviceTypeLabelOf(serviceType);
  String get providerTypeLabel => providerTypeLabelOf(providerType);
  String get statusLabel => serviceStatusLabelOf(status);
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
