/// نماذج وحدة العقارات — مطابقة لمخرجات بوّابة الصدارة `/api/sas-agent/premises`.
///
/// عرض/بيانات فقط — لا استدعاءات API ولا منطق أعمال هنا.
library;

/// اشتراك مرتبط بعقار (عرض مختصر).
class PremisesSub {
  final int id;
  final String username, name, profile, status, expiration, phone;
  final bool online;

  const PremisesSub({
    required this.id,
    required this.username,
    required this.name,
    required this.profile,
    required this.status,
    required this.expiration,
    required this.phone,
    required this.online,
  });

  factory PremisesSub.fromJson(Map<String, dynamic> j) => PremisesSub(
        id: _asInt(_pick(j, ['id', 'Id'])),
        username: _str(_pick(j, ['username', 'Username'])),
        name: _str(_pick(j, ['name', 'Name'])),
        profile: _str(_pick(j, ['profile', 'Profile'])),
        status: _str(_pick(j, ['status', 'Status'])),
        expiration: _str(_pick(j, ['expiration', 'Expiration'])),
        phone: _str(_pick(j, ['phone', 'Phone'])),
        online: _pick(j, ['online', 'Online']) == true,
      );
}

/// عقار/موقع فعلي — عنوان وطني مولَّد + وسائط + تصنيف.
class Premises {
  final int id;
  final String npn, npnDisplay, iqpin, iqpinDisplay, qrPayload;
  final int govCode;
  final double? lat, lon;
  final String governorate, district, landmark, addressDetails;
  final String phone, ownership, propertyType, ownerName, notes;
  final bool hasPhoto;
  final int subscriberCount;
  final List<PremisesSub> subscribers;

  const Premises({
    required this.id,
    required this.npn,
    required this.npnDisplay,
    required this.iqpin,
    required this.iqpinDisplay,
    required this.qrPayload,
    required this.govCode,
    this.lat,
    this.lon,
    required this.governorate,
    required this.district,
    required this.landmark,
    required this.addressDetails,
    required this.phone,
    required this.ownership,
    required this.propertyType,
    required this.ownerName,
    required this.notes,
    required this.hasPhoto,
    required this.subscriberCount,
    this.subscribers = const [],
  });

  factory Premises.fromJson(Map<String, dynamic> j) => Premises(
        id: _asInt(_pick(j, ['id', 'Id'])),
        npn: _str(_pick(j, ['npn', 'Npn'])),
        npnDisplay:
            _str(_pick(j, ['npn_display', 'npnDisplay', 'NpnDisplay'])),
        iqpin: _str(_pick(j, ['iqpin', 'Iqpin'])),
        iqpinDisplay: _str(
            _pick(j, ['iqpin_display', 'iqpinDisplay', 'IqpinDisplay'])),
        qrPayload:
            _str(_pick(j, ['qr_payload', 'qrPayload', 'QrPayload'])),
        govCode: _asInt(_pick(j, ['gov_code', 'govCode', 'GovCode'])),
        lat: _asDouble(_pick(j, ['lat', 'Lat'])),
        lon: _asDouble(_pick(j, ['lon', 'Lon'])),
        governorate: _str(_pick(j, ['governorate', 'Governorate'])),
        district: _str(_pick(j, ['district', 'District'])),
        landmark: _str(_pick(j, ['landmark', 'Landmark'])),
        addressDetails: _str(
            _pick(j, ['address_details', 'addressDetails', 'AddressDetails'])),
        phone: _str(_pick(j, ['phone', 'Phone'])),
        ownership: _str(_pick(j, ['ownership', 'Ownership'])),
        propertyType: _str(
            _pick(j, ['property_type', 'propertyType', 'PropertyType'])),
        ownerName:
            _str(_pick(j, ['owner_name', 'ownerName', 'OwnerName'])),
        notes: _str(_pick(j, ['notes', 'Notes'])),
        hasPhoto:
            _pick(j, ['has_photo', 'hasPhoto', 'HasPhoto']) == true,
        subscriberCount: _asInt(
            _pick(j, ['subscriber_count', 'subscriberCount', 'SubscriberCount'])),
        subscribers: ((_pick(j, ['subscribers', 'Subscribers']) as List?) ??
                const [])
            .whereType<Map>()
            .map((e) => PremisesSub.fromJson(e.cast<String, dynamic>()))
            .toList(),
      );

  /// عنوان مقروء مختصر (محافظة/منطقة/أقرب نقطة).
  String get shortAddress {
    final parts =
        [governorate, district, landmark].where((s) => s.trim().isNotEmpty);
    return parts.join(' · ');
  }
}

/// تسميات عربية للتصنيفات.
const kOwnershipLabels = {'owned': 'ملك', 'rent': 'إيجار'};
const kPropertyLabels = {'residential': 'دار سكني', 'commercial': 'محل'};

String ownershipLabel(String v) => kOwnershipLabels[v] ?? '—';
String propertyLabel(String v) => kPropertyLabels[v] ?? '—';

// ─────────────────────────── محوّلات آمنة ───────────────────────────

/// أوّل قيمة غير-null من قائمة أسماء مفاتيح بديلة.
///
/// بوّابة الصدارة .NET تُسلسِل DTOs بـ**PascalCase** (`Program.cs`:
/// `PropertyNamingPolicy = null`)، لذا نمرّر camel/snake/Pascal معاً.
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
