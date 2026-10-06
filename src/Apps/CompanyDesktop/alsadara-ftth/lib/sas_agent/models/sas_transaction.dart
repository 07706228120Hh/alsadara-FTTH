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

  /// نوع التحصيل الخام: `cash` · `credit` · `agent` · `citizen` · `technician`.
  final String collectionType;

  /// حالة الحركة الخام (مثل `ok`/`success`/`failed`) — تُترجَم عند العرض.
  final String status;

  final String? journalEntryId;

  /// اسم مُنفِّذ العملية (المستخدم الذي ختم الحركة).
  final String activatedBy;

  /// اسم الفنّي المُسنَدة إليه العملية (عند collectionType == technician).
  final String technicianName;

  /// اسم الوكيل المُسنَدة إليه العملية (عند collectionType == agent).
  final String agentName;

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
    this.activatedBy = '',
    this.technicianName = '',
    this.agentName = '',
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
      case 'citizen':
        return 'ذمة المواطن';
      case 'technician':
        return 'فني';
      default:
        return collectionType.isEmpty ? '—' : collectionType;
    }
  }

  /// اسم المُسنَدة إليه العملية «على مَن» حسب نوع التحصيل:
  /// فنّي → اسم الفنّي · وكيل → اسم الوكيل · ذمة المواطن → «المواطن» ·
  /// غير ذلك → فارغ (لا إسناد).
  String get assigneeAr {
    switch (collectionType) {
      case 'technician':
        return technicianName.isEmpty ? '—' : technicianName;
      case 'agent':
        return agentName.isEmpty ? '—' : agentName;
      case 'citizen':
        return 'المواطن';
      default:
        return '';
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
      activatedBy: (json['activatedBy'] ??
              json['activated_by'] ??
              json['activatedByName'] ??
              json['activated_by_name'] ??
              '')
          .toString(),
      technicianName: (json['technicianName'] ??
              json['technician_name'] ??
              json['linkedTechnicianName'] ??
              json['linked_technician_name'] ??
              '')
          .toString(),
      agentName: (json['agentName'] ??
              json['agent_name'] ??
              json['linkedAgentName'] ??
              json['linked_agent_name'] ??
              '')
          .toString(),
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
