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
        id: _asInt(j['id']),
        username: (j['username'] ?? '').toString(),
        name: (j['name'] ?? '').toString(),
        profile: (j['profile'] ?? '').toString(),
        status: (j['status'] ?? '').toString(),
        expiration: (j['expiration'] ?? '').toString(),
        phone: (j['phone'] ?? '').toString(),
        online: j['online'] == true,
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
        id: _asInt(j['id']),
        npn: (j['npn'] ?? '').toString(),
        npnDisplay: (j['npn_display'] ?? j['npnDisplay'] ?? '').toString(),
        iqpin: (j['iqpin'] ?? '').toString(),
        iqpinDisplay:
            (j['iqpin_display'] ?? j['iqpinDisplay'] ?? '').toString(),
        qrPayload: (j['qr_payload'] ?? j['qrPayload'] ?? '').toString(),
        govCode: _asInt(j['gov_code'] ?? j['govCode']),
        lat: _asDouble(j['lat']),
        lon: _asDouble(j['lon']),
        governorate: (j['governorate'] ?? '').toString(),
        district: (j['district'] ?? '').toString(),
        landmark: (j['landmark'] ?? '').toString(),
        addressDetails:
            (j['address_details'] ?? j['addressDetails'] ?? '').toString(),
        phone: (j['phone'] ?? '').toString(),
        ownership: (j['ownership'] ?? '').toString(),
        propertyType:
            (j['property_type'] ?? j['propertyType'] ?? '').toString(),
        ownerName: (j['owner_name'] ?? j['ownerName'] ?? '').toString(),
        notes: (j['notes'] ?? '').toString(),
        hasPhoto: (j['has_photo'] ?? j['hasPhoto']) == true,
        subscriberCount:
            _asInt(j['subscriber_count'] ?? j['subscriberCount']),
        subscribers: ((j['subscribers'] as List?) ?? const [])
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
