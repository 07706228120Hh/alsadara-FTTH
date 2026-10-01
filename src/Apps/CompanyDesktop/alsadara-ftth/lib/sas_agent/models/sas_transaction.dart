/// نموذج حركة سجلّ العمليات المفوترة لوحدة «وكيل الساس».
///
/// يمثّل صفّاً من `GET /accounts/{id}/transactions` — كلّ حركة ناتجة عن تفعيل/
/// تمديد/تغيير باقة مفوتر خُتم بقيد في دفتر الصدارة الموحّد (Source=sas).
///
/// `fromJson` **متساهل**: يقبل camelCase وsnake_case ويحوّل الحقول العددية التي
/// قد يعيدها الخادم كنصوص، فلا تنكسر الشاشة لو اختلفت التسمية قليلاً.
library;

/// تحويل آمن لرقم — الخادم قد يعيد المبالغ كنصوص أحياناً.
num? _asNum(dynamic v) =>
    v is num ? v : (v == null ? null : num.tryParse(v.toString()));

/// حركة واحدة في سجلّ العمليات المفوترة.
class SasTransaction {
  final String id;
  final String createdAt;

  /// الإجراء الخام: `activate` · `extend` · `changeProfile`.
  final String action;

  final String subscriberUid;
  final String subscriberUsername;
  final String planName;
  final num? basePrice;
  final num? collectedAmount;
  final String currency;

  /// نوع التحصيل الخام: `cash` · `credit` · `agent`.
  final String collectionType;

  /// حالة الحركة الخام (مثل `ok`/`success`/`failed`) — تُترجَم عند العرض.
  final String status;

  final String? journalEntryId;

  const SasTransaction({
    required this.id,
    required this.createdAt,
    required this.action,
    required this.subscriberUid,
    required this.subscriberUsername,
    required this.planName,
    required this.currency,
    required this.collectionType,
    required this.status,
    this.basePrice,
    this.collectedAmount,
    this.journalEntryId,
  });

  /// الإجراء بالعربية للعرض.
  String get actionAr {
    switch (action) {
      case 'activate':
        return 'تفعيل';
      case 'extend':
        return 'تمديد';
      case 'changeProfile':
        return 'تغيير باقة';
      default:
        return action.isEmpty ? '—' : action;
    }
  }

  /// نوع التحصيل بالعربية للعرض.
  String get collectionTypeAr {
    switch (collectionType) {
      case 'cash':
        return 'نقد';
      case 'credit':
        return 'أجل';
      case 'agent':
        return 'وكيل';
      default:
        return collectionType.isEmpty ? '—' : collectionType;
    }
  }

  /// هل الحركة ناجحة؟ (يقبل عدّة صيغ).
  bool get isSuccess {
    final s = status.toLowerCase();
    return s == 'ok' ||
        s == 'success' ||
        s == 'succeeded' ||
        s == 'true' ||
        s == 'done';
  }

  /// الحالة بالعربية للعرض.
  String get statusAr => isSuccess ? 'ناجحة' : (status.isEmpty ? '—' : 'فاشلة');

  factory SasTransaction.fromJson(Map<String, dynamic> json) {
    return SasTransaction(
      id: (json['id'] ?? json['Id'] ?? json['_id'] ?? '').toString(),
      createdAt:
          (json['createdAt'] ?? json['created_at'] ?? json['date'] ?? '')
              .toString(),
      action: (json['action'] ?? json['Action'] ?? json['type'] ?? '')
          .toString(),
      subscriberUid: (json['subscriberUid'] ??
              json['subscriber_uid'] ??
              json['uid'] ??
              json['userId'] ??
              '')
          .toString(),
      subscriberUsername: (json['subscriberUsername'] ??
              json['subscriber_username'] ??
              json['username'] ??
              '')
          .toString(),
      planName: (json['planName'] ??
              json['plan_name'] ??
              json['profileName'] ??
              json['profile_name'] ??
              '')
          .toString(),
      basePrice: _asNum(json['basePrice'] ?? json['base_price']),
      collectedAmount:
          _asNum(json['collectedAmount'] ?? json['collected_amount']),
      currency:
          (json['currency'] ?? json['Currency'] ?? 'IQD').toString(),
      collectionType: (json['collectionType'] ??
              json['collection_type'] ??
              '')
          .toString(),
      status: (json['status'] ?? json['Status'] ?? '').toString(),
      journalEntryId: (json['journalEntryId'] ??
              json['journal_entry_id'] ??
              json['journalId'])
          ?.toString(),
    );
  }
}

/// صفحة حركات مُرقّمة من `GET /accounts/{id}/transactions`.
class SasTransactionsPage {
  final int total;
  final List<SasTransaction> data;

  const SasTransactionsPage({required this.total, required this.data});

  factory SasTransactionsPage.fromJson(Map<String, dynamic> json) {
    final rawList = json['data'] ?? json['rows'] ?? json['items'] ?? json['results'];
    final list = (rawList is List)
        ? rawList
            .whereType<Map>()
            .map((e) => SasTransaction.fromJson(e.cast<String, dynamic>()))
            .toList()
        : <SasTransaction>[];
    final total = _asNum(json['total'])?.toInt() ?? list.length;
    return SasTransactionsPage(total: total, data: list);
  }
}
