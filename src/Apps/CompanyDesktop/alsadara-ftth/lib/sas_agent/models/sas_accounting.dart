/// نماذج النظام المحاسبي لوحدة «وكيل الساس» (المرحلة 5).
///
/// تغطّي: تسعير الباقات (كلفة/بيع/ربح) · معلومات المواطن الموسّعة (11 حقلاً) ·
/// كشف حساب المواطن (شحنات + تسديدات + رصيد) · المدينون.
///
/// كل `fromJson` **متساهل**: يقبل camelCase وsnake_case ويحوّل الحقول العددية
/// التي قد يعيدها الخادم كنصوص، فلا تنكسر الشاشة لو اختلفت التسمية قليلاً.
library;

/// تحويل آمن لرقم — الخادم قد يعيد المبالغ كنصوص أحياناً.
num? _asNum(dynamic v) =>
    v is num ? v : (v == null ? null : num.tryParse(v.toString()));

String _asStr(dynamic v) => (v ?? '').toString();

// ════════════════════════ تسعير الباقات ════════════════════════

/// سعر باقة واحد — من `GET accounts/{id}/package-prices`.
///
/// الربح محسوب للعرض فقط (`sellingPrice − cost`)؛ يُرسَل للخادم الكلفة/البيع فقط.
/// نموذج **قابل للتعديل** (كلفة/بيع/مفعّل) لذا حقوله غير ثابتة ويحمل `copyWith`.
class SasPackagePrice {
  final String profileId;
  final String profileName;
  num cost;
  num sellingPrice;
  bool isActive;

  SasPackagePrice({
    required this.profileId,
    required this.profileName,
    this.cost = 0,
    this.sellingPrice = 0,
    this.isActive = true,
  });

  /// الربح = سعر البيع − الكلفة (محسوب، للعرض فقط).
  num get profit => sellingPrice - cost;

  factory SasPackagePrice.fromJson(Map<String, dynamic> json) {
    return SasPackagePrice(
      profileId:
          (json['profileId'] ?? json['profile_id'] ?? json['id'] ?? '')
              .toString(),
      profileName: (json['profileName'] ??
              json['profile_name'] ??
              json['name'] ??
              '')
          .toString(),
      cost: _asNum(json['cost'] ?? json['Cost']) ?? 0,
      sellingPrice: _asNum(json['sellingPrice'] ??
              json['selling_price'] ??
              json['price']) ??
          0,
      isActive: (json['isActive'] ?? json['is_active'] ?? true) == true,
    );
  }

  /// الحمولة المرسَلة في `PUT package-prices` (بلا الربح — يُحسب خادمياً).
  Map<String, dynamic> toSaveJson() => {
        'profileId': profileId,
        'profileName': profileName,
        'cost': cost,
        'sellingPrice': sellingPrice,
        'isActive': isActive,
      };
}

// ════════════════════════ معلومات المواطن الموسّعة ════════════════════════

/// الحقول الـ11 الموسّعة للمواطن — من `GET accounts/{id}/users/{uid}/profile`.
///
/// منفصلة عن تفاصيل الساس (تبقى عبر المزامنة؛ بيانات أدخلها الوكيل). كل الحقول
/// نصّية اختيارية ليسهل ربطها بحقول إدخال نموذج.
class SasSubscriberProfile {
  final String nationalId;
  final String fullNameQuad;
  final String birthDate;
  final String gender;
  final String altPhone;
  final String whatsappNumber;
  final String email;
  final String addressDetail;
  final String latitude;
  final String longitude;
  final String propertyType;
  final String landmark;

  const SasSubscriberProfile({
    this.nationalId = '',
    this.fullNameQuad = '',
    this.birthDate = '',
    this.gender = '',
    this.altPhone = '',
    this.whatsappNumber = '',
    this.email = '',
    this.addressDetail = '',
    this.latitude = '',
    this.longitude = '',
    this.propertyType = '',
    this.landmark = '',
  });

  factory SasSubscriberProfile.fromJson(Map<String, dynamic> json) {
    return SasSubscriberProfile(
      nationalId: _asStr(json['nationalId'] ?? json['national_id']),
      fullNameQuad: _asStr(json['fullNameQuad'] ?? json['full_name_quad']),
      birthDate: _asStr(json['birthDate'] ?? json['birth_date']),
      gender: _asStr(json['gender']),
      altPhone: _asStr(json['altPhone'] ?? json['alt_phone']),
      whatsappNumber:
          _asStr(json['whatsappNumber'] ?? json['whatsapp_number']),
      email: _asStr(json['email']),
      addressDetail: _asStr(json['addressDetail'] ?? json['address_detail']),
      latitude: _asStr(json['latitude']),
      longitude: _asStr(json['longitude']),
      propertyType: _asStr(json['propertyType'] ?? json['property_type']),
      landmark: _asStr(json['landmark']),
    );
  }

  /// الحمولة المرسَلة في `PUT profile` (بأسماء camelCase كما يتوقّعها العقد).
  Map<String, dynamic> toSaveJson() => {
        'nationalId': nationalId,
        'fullNameQuad': fullNameQuad,
        'birthDate': birthDate,
        'gender': gender,
        'altPhone': altPhone,
        'whatsappNumber': whatsappNumber,
        'email': email,
        'addressDetail': addressDetail,
        'latitude': latitude,
        'longitude': longitude,
        'propertyType': propertyType,
        'landmark': landmark,
      };
}

// ════════════════════════ كشف حساب المواطن ════════════════════════

/// شحنة واحدة في كشف حساب المواطن (عملية أدانت ذمّته).
class SasCitizenCharge {
  final String id;
  final String createdAt;
  final String planName;
  final String operationType;
  final num? amount;
  final String currency;
  final String? journalEntryId;

  const SasCitizenCharge({
    required this.id,
    required this.createdAt,
    required this.planName,
    required this.operationType,
    required this.currency,
    this.amount,
    this.journalEntryId,
  });

  factory SasCitizenCharge.fromJson(Map<String, dynamic> json) {
    return SasCitizenCharge(
      id: _asStr(json['id'] ?? json['Id']),
      createdAt: _asStr(json['createdAt'] ?? json['created_at']),
      planName: _asStr(json['planName'] ?? json['plan_name']),
      operationType: _asStr(json['operationType'] ?? json['operation_type']),
      amount: _asNum(json['amount']),
      currency: (json['currency'] ?? 'IQD').toString(),
      journalEntryId:
          (json['journalEntryId'] ?? json['journal_entry_id'])?.toString(),
    );
  }
}

/// تسديد واحد في كشف حساب المواطن (دفعة سدّت جزءاً من الذمّة).
class SasCitizenPayment {
  final String id;
  final String createdAt;
  final num? amount;
  final String method; // cash | master
  final String note;
  final String? journalEntryId;

  const SasCitizenPayment({
    required this.id,
    required this.createdAt,
    required this.method,
    required this.note,
    this.amount,
    this.journalEntryId,
  });

  /// طريقة التسديد بالعربية.
  String get methodAr {
    switch (method) {
      case 'cash':
        return 'نقد';
      case 'master':
        return 'ماستر';
      default:
        return method.isEmpty ? '—' : method;
    }
  }

  factory SasCitizenPayment.fromJson(Map<String, dynamic> json) {
    return SasCitizenPayment(
      id: _asStr(json['id'] ?? json['Id']),
      createdAt: _asStr(json['createdAt'] ?? json['created_at']),
      amount: _asNum(json['amount']),
      method: _asStr(json['method']),
      note: _asStr(json['note']),
      journalEntryId:
          (json['journalEntryId'] ?? json['journal_entry_id'])?.toString(),
    );
  }
}

/// كشف حساب مواطن كامل — من `GET accounts/{id}/users/{uid}/statement`.
class SasCitizenStatement {
  final List<SasCitizenCharge> charges;
  final List<SasCitizenPayment> payments;

  /// الرصيد المستحق (موجب = مدين على المواطن).
  final num balance;

  const SasCitizenStatement({
    required this.charges,
    required this.payments,
    required this.balance,
  });

  factory SasCitizenStatement.fromJson(Map<String, dynamic> raw) {
    // يُفكّ غلاف `data` إن وُجد.
    final json = (raw['data'] is Map)
        ? (raw['data'] as Map).cast<String, dynamic>()
        : raw;
    final rawCharges = json['charges'];
    final rawPayments = json['payments'];
    return SasCitizenStatement(
      charges: (rawCharges is List)
          ? rawCharges
              .whereType<Map>()
              .map((e) => SasCitizenCharge.fromJson(e.cast<String, dynamic>()))
              .toList()
          : const [],
      payments: (rawPayments is List)
          ? rawPayments
              .whereType<Map>()
              .map(
                  (e) => SasCitizenPayment.fromJson(e.cast<String, dynamic>()))
              .toList()
          : const [],
      balance: _asNum(json['balance']) ?? 0,
    );
  }
}

/// نتيجة تسجيل تسديد — من `POST citizen payment`.
class SasPaymentResult {
  final String paymentId;
  final String? journalEntryId;
  final num balance;

  const SasPaymentResult({
    required this.paymentId,
    required this.balance,
    this.journalEntryId,
  });

  factory SasPaymentResult.fromJson(Map<String, dynamic> raw) {
    final json = (raw['data'] is Map)
        ? (raw['data'] as Map).cast<String, dynamic>()
        : raw;
    return SasPaymentResult(
      paymentId: _asStr(json['paymentId'] ?? json['payment_id']),
      journalEntryId:
          (json['journalEntryId'] ?? json['journal_entry_id'])?.toString(),
      balance: _asNum(json['balance']) ?? 0,
    );
  }
}

// ════════════════════════ المدينون ════════════════════════

/// مشترك مدين — من `GET accounts/{id}/debtors`.
class SasDebtor {
  final String subscriberUid;
  final String name;
  final num balance;

  const SasDebtor({
    required this.subscriberUid,
    required this.name,
    required this.balance,
  });

  factory SasDebtor.fromJson(Map<String, dynamic> json) {
    return SasDebtor(
      subscriberUid:
          _asStr(json['subscriberUid'] ?? json['subscriber_uid'] ?? json['uid']),
      name: _asStr(json['name'] ?? json['username']),
      balance: _asNum(json['balance']) ?? 0,
    );
  }
}
