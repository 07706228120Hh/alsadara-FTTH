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

/// أوّل قيمة غير-null من قائمة أسماء مفاتيح بديلة.
///
/// ضروري لأن بوّابة الصدارة .NET تُسلسِل DTOs بـ**PascalCase**
/// (`Program.cs`: `PropertyNamingPolicy = null`) بينما بيانات Python/SAS4 تصل
/// snake_case/lower. نمرّر كل الصيغ (camel ثم snake ثم Pascal) فيصمد التحليل
/// مهما كانت سياسة التسمية في المصدر.
dynamic _pick(Map<String, dynamic> j, List<String> keys) {
  for (final k in keys) {
    final v = j[k];
    if (v != null) return v;
  }
  return null;
}

// ════════════════════════ تسعير الباقات ════════════════════════

/// سعر باقة واحد — من `GET accounts/{id}/package-prices`.
///
/// النموذج الجديد: الوكيل يحدّد **سعر البيع فقط**. السعر الأساسي (`cost`)
/// ديناميكي يُجلب وقت التجديد من الساس؛ لم يَعُد يُدخَل يدوياً ولا يُعرَض، والربح
/// يُحسب خادمياً (سعر البيع + أجور الصيانة − الأساسي). يبقى `cost` في الموديل
/// لتوافق القراءة لكن لا يُحرَّر ولا يُعتمَد عليه في العرض.
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

  /// الربح التقديري = سعر البيع − الكلفة (غير مستخدم في العرض؛ الربح الفعلي
  /// يُحسب خادمياً وقت التجديد بالأساسي الديناميكي + أجور الصيانة).
  num get profit => sellingPrice - cost;

  factory SasPackagePrice.fromJson(Map<String, dynamic> json) {
    return SasPackagePrice(
      profileId: _asStr(_pick(json,
          ['profileId', 'profile_id', 'ProfileId', 'id', 'Id'])),
      profileName: _asStr(_pick(json, [
        'profileName',
        'profile_name',
        'ProfileName',
        'name',
        'Name',
      ])),
      cost: _asNum(_pick(json, ['cost', 'Cost'])) ?? 0,
      sellingPrice: _asNum(_pick(json, [
            'sellingPrice',
            'selling_price',
            'SellingPrice',
            'price',
            'Price',
          ])) ??
          0,
      isActive:
          (_pick(json, ['isActive', 'is_active', 'IsActive']) ?? true) == true,
    );
  }

  /// الحمولة المرسَلة في `PUT package-prices`. نرسل سعر البيع + التعريف +
  /// التفعيل. `cost` يُرسَل 0 لأن الباكند صار يتجاهله (الأساسي ديناميكي وقت
  /// التجديد)؛ الربح يُحسب خادمياً.
  Map<String, dynamic> toSaveJson() => {
        'profileId': profileId,
        'profileName': profileName,
        'cost': 0,
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

  /// معرّف المنطقة المرتبطة (GUID) — فارغ إن لم تُربط. أساس أجور الصيانة التلقائية.
  final String regionId;

  /// اسم المنطقة المرتبطة (عرضي فقط — يأتي من الخادم).
  final String regionName;

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
    this.regionId = '',
    this.regionName = '',
  });

  factory SasSubscriberProfile.fromJson(Map<String, dynamic> json) {
    return SasSubscriberProfile(
      nationalId:
          _asStr(_pick(json, ['nationalId', 'national_id', 'NationalId'])),
      fullNameQuad: _asStr(
          _pick(json, ['fullNameQuad', 'full_name_quad', 'FullNameQuad'])),
      birthDate:
          _asStr(_pick(json, ['birthDate', 'birth_date', 'BirthDate'])),
      gender: _asStr(_pick(json, ['gender', 'Gender'])),
      altPhone: _asStr(_pick(json, ['altPhone', 'alt_phone', 'AltPhone'])),
      whatsappNumber: _asStr(_pick(
          json, ['whatsappNumber', 'whatsapp_number', 'WhatsappNumber'])),
      email: _asStr(_pick(json, ['email', 'Email'])),
      addressDetail: _asStr(
          _pick(json, ['addressDetail', 'address_detail', 'AddressDetail'])),
      latitude: _asStr(_pick(json, ['latitude', 'Latitude'])),
      longitude: _asStr(_pick(json, ['longitude', 'Longitude'])),
      propertyType: _asStr(
          _pick(json, ['propertyType', 'property_type', 'PropertyType'])),
      landmark: _asStr(_pick(json, ['landmark', 'Landmark'])),
      regionId: _asStr(_pick(json, ['regionId', 'region_id', 'RegionId'])),
      regionName:
          _asStr(_pick(json, ['regionName', 'region_name', 'RegionName'])),
    );
  }

  SasSubscriberProfile copyWith({String? regionId, String? regionName}) =>
      SasSubscriberProfile(
        nationalId: nationalId,
        fullNameQuad: fullNameQuad,
        birthDate: birthDate,
        gender: gender,
        altPhone: altPhone,
        whatsappNumber: whatsappNumber,
        email: email,
        addressDetail: addressDetail,
        latitude: latitude,
        longitude: longitude,
        propertyType: propertyType,
        landmark: landmark,
        regionId: regionId ?? this.regionId,
        regionName: regionName ?? this.regionName,
      );

  /// الحمولة المرسَلة في `PUT profile` (بأسماء camelCase كما يتوقّعها العقد).
  /// regionId يُرسَل null عند الفراغ (إلغاء الربط).
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
        'regionId': regionId.isEmpty ? null : regionId,
      };
}

/// منطقة مشتركي الساس — بيانات رئيسية على مستوى الشركة. أجور صيانة ثابتة تُطبَّق تلقائياً.
class SasRegion {
  final String id;
  final String name;
  final String code;
  final String governorate;
  final String city;
  final num maintenanceFee;
  final bool isActive;
  final String notes;
  final int subscribersCount;

  const SasRegion({
    required this.id,
    required this.name,
    this.code = '',
    this.governorate = '',
    this.city = '',
    this.maintenanceFee = 0,
    this.isActive = true,
    this.notes = '',
    this.subscribersCount = 0,
  });

  factory SasRegion.fromJson(Map<String, dynamic> json) => SasRegion(
        id: _asStr(_pick(json, ['id', 'Id'])),
        name: _asStr(_pick(json, ['name', 'Name'])),
        code: _asStr(_pick(json, ['code', 'Code'])),
        governorate:
            _asStr(_pick(json, ['governorate', 'Governorate'])),
        city: _asStr(_pick(json, ['city', 'City'])),
        maintenanceFee: _asNum(_pick(
                json, ['maintenanceFee', 'maintenance_fee', 'MaintenanceFee'])) ??
            0,
        isActive:
            (_pick(json, ['isActive', 'is_active', 'IsActive']) ?? true) == true,
        notes: _asStr(_pick(json, ['notes', 'Notes'])),
        subscribersCount: (_asNum(_pick(json, [
                  'subscribersCount',
                  'subscribers_count',
                  'SubscribersCount',
                ])) ??
                0)
            .toInt(),
      );

  Map<String, dynamic> toSaveJson() => {
        'name': name,
        'code': code,
        'governorate': governorate,
        'city': city,
        'maintenanceFee': maintenanceFee,
        'isActive': isActive,
        'notes': notes,
      };
}

/// صفّ في تقرير الأرباح (منطقة/باقة/إجمالي). الربح = المحصّل − الكلفة.
class SasProfitRow {
  final String label;
  final int count;
  final num cost;
  final num profit;
  final num revenue;

  const SasProfitRow({
    required this.label,
    this.count = 0,
    this.cost = 0,
    this.profit = 0,
    this.revenue = 0,
  });

  factory SasProfitRow.fromJson(Map<String, dynamic> json) {
    final rawCount = _pick(json, ['count', 'Count']) ?? 0;
    return SasProfitRow(
      label: _asStr(_pick(json, ['label', 'Label'])),
      count: rawCount is num
          ? rawCount.toInt()
          : int.tryParse('$rawCount') ?? 0,
      cost: _asNum(_pick(json, ['cost', 'Cost'])) ?? 0,
      profit: _asNum(_pick(json, ['profit', 'Profit'])) ?? 0,
      revenue: _asNum(_pick(json, ['revenue', 'Revenue'])) ?? 0,
    );
  }
}

/// تقرير أرباح الساس (إجمالي + تفصيل حسب المنطقة والباقة).
class SasProfitReport {
  final SasProfitRow totals;
  final List<SasProfitRow> byRegion;
  final List<SasProfitRow> byPackage;

  const SasProfitReport({
    required this.totals,
    this.byRegion = const [],
    this.byPackage = const [],
  });

  factory SasProfitReport.fromJson(Map<String, dynamic> json) {
    List<SasProfitRow> rows(dynamic v) => (v is List)
        ? v
            .whereType<Map>()
            .map((e) => SasProfitRow.fromJson(e.cast<String, dynamic>()))
            .toList()
        : const [];
    final t = _pick(json, ['totals', 'Totals']);
    return SasProfitReport(
      totals: t is Map
          ? SasProfitRow.fromJson(t.cast<String, dynamic>())
          : const SasProfitRow(label: 'الإجمالي'),
      byRegion: rows(_pick(json, ['byRegion', 'by_region', 'ByRegion'])),
      byPackage: rows(_pick(json, ['byPackage', 'by_package', 'ByPackage'])),
    );
  }
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
      id: _asStr(_pick(json, ['id', 'Id'])),
      createdAt:
          _asStr(_pick(json, ['createdAt', 'created_at', 'CreatedAt'])),
      planName: _asStr(_pick(json, ['planName', 'plan_name', 'PlanName'])),
      operationType: _asStr(
          _pick(json, ['operationType', 'operation_type', 'OperationType'])),
      amount: _asNum(_pick(json, ['amount', 'Amount'])),
      currency: _asStr(_pick(json, ['currency', 'Currency']) ?? 'IQD'),
      journalEntryId: _pick(json,
              ['journalEntryId', 'journal_entry_id', 'JournalEntryId'])
          ?.toString(),
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
      id: _asStr(_pick(json, ['id', 'Id'])),
      createdAt:
          _asStr(_pick(json, ['createdAt', 'created_at', 'CreatedAt'])),
      amount: _asNum(_pick(json, ['amount', 'Amount'])),
      method: _asStr(_pick(json, ['method', 'Method'])),
      note: _asStr(_pick(json, ['note', 'Note'])),
      journalEntryId: _pick(json,
              ['journalEntryId', 'journal_entry_id', 'JournalEntryId'])
          ?.toString(),
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
    final rawCharges = _pick(json, ['charges', 'Charges']);
    final rawPayments = _pick(json, ['payments', 'Payments']);
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
      balance: _asNum(_pick(json, ['balance', 'Balance'])) ?? 0,
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
      paymentId:
          _asStr(_pick(json, ['paymentId', 'payment_id', 'PaymentId'])),
      journalEntryId: _pick(json,
              ['journalEntryId', 'journal_entry_id', 'JournalEntryId'])
          ?.toString(),
      balance: _asNum(_pick(json, ['balance', 'Balance'])) ?? 0,
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
      subscriberUid: _asStr(_pick(json, [
        'subscriberUid',
        'subscriber_uid',
        'SubscriberUid',
        'uid',
        'Uid',
      ])),
      name: _asStr(_pick(json, ['name', 'Name', 'username', 'Username'])),
      balance: _asNum(_pick(json, ['balance', 'Balance'])) ?? 0,
    );
  }
}
