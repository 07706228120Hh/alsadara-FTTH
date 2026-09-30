/// نماذج وحدة العقارات (Flutter) — مطابقة لمخرجات راوتر الباكند المعزول.
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
        id: (j['id'] ?? 0) as int,
        username: (j['username'] ?? '') as String,
        name: (j['name'] ?? '') as String,
        profile: (j['profile'] ?? '') as String,
        status: (j['status'] ?? '') as String,
        expiration: (j['expiration'] ?? '') as String,
        phone: (j['phone'] ?? '') as String,
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
        id: (j['id'] ?? 0) as int,
        npn: (j['npn'] ?? '') as String,
        npnDisplay: (j['npn_display'] ?? '') as String,
        iqpin: (j['iqpin'] ?? '') as String,
        iqpinDisplay: (j['iqpin_display'] ?? '') as String,
        qrPayload: (j['qr_payload'] ?? '') as String,
        govCode: (j['gov_code'] ?? 0) as int,
        lat: (j['lat'] as num?)?.toDouble(),
        lon: (j['lon'] as num?)?.toDouble(),
        governorate: (j['governorate'] ?? '') as String,
        district: (j['district'] ?? '') as String,
        landmark: (j['landmark'] ?? '') as String,
        addressDetails: (j['address_details'] ?? '') as String,
        phone: (j['phone'] ?? '') as String,
        ownership: (j['ownership'] ?? '') as String,
        propertyType: (j['property_type'] ?? '') as String,
        ownerName: (j['owner_name'] ?? '') as String,
        notes: (j['notes'] ?? '') as String,
        hasPhoto: j['has_photo'] == true,
        subscriberCount: (j['subscriber_count'] ?? 0) as int,
        subscribers: ((j['subscribers'] as List?) ?? [])
            .map((e) => PremisesSub.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  /// عنوان مقروء مختصر (منطقة/أقرب نقطة).
  String get shortAddress {
    final parts = [governorate, district, landmark].where((s) => s.trim().isNotEmpty);
    return parts.join(' · ');
  }
}

/// تسميات عربية للتصنيفات.
const kOwnershipLabels = {'owned': 'ملك', 'rent': 'إيجار'};
const kPropertyLabels = {'residential': 'دار سكني', 'commercial': 'محل'};

String ownershipLabel(String v) => kOwnershipLabels[v] ?? '—';
String propertyLabel(String v) => kPropertyLabels[v] ?? '—';
