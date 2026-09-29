/// تذكرة (شكوى/طلب) كما يُعيدها الباكند — مشتركة بين كل التطبيقات.
class Ticket {
  final int id;
  final int companyId;
  final String company;
  final String agent;
  final String subscriber;
  final String subscriberName;
  final String subscriberPhone;
  final String category;
  final String categoryAr;
  final String subject;
  final String body;
  final String status;
  final String statusAr;
  final String priority;
  final bool escalated;
  final String createdBy;
  final String createdByKind;
  final String assignedTo;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? resolvedAt;
  final List<TicketReply> replies;

  const Ticket({
    required this.id,
    required this.companyId,
    required this.company,
    required this.agent,
    required this.subscriber,
    required this.subscriberName,
    required this.subscriberPhone,
    required this.category,
    required this.categoryAr,
    required this.subject,
    required this.body,
    required this.status,
    required this.statusAr,
    required this.priority,
    required this.escalated,
    required this.createdBy,
    required this.createdByKind,
    required this.assignedTo,
    this.createdAt,
    this.updatedAt,
    this.resolvedAt,
    this.replies = const [],
  });

  bool get isOpen => status == 'open' || status == 'in_progress';

  factory Ticket.fromJson(Map<String, dynamic> j) => Ticket(
        id: j['id'] as int,
        companyId: (j['company_id'] ?? 0) as int,
        company: (j['company'] ?? '') as String,
        agent: (j['agent'] ?? '') as String,
        subscriber: (j['subscriber'] ?? '') as String,
        subscriberName: (j['subscriber_name'] ?? '') as String,
        subscriberPhone: (j['subscriber_phone'] ?? '') as String,
        category: (j['category'] ?? 'other') as String,
        categoryAr: (j['category_ar'] ?? '') as String,
        subject: (j['subject'] ?? '') as String,
        body: (j['body'] ?? '') as String,
        status: (j['status'] ?? 'open') as String,
        statusAr: (j['status_ar'] ?? '') as String,
        priority: (j['priority'] ?? 'normal') as String,
        escalated: j['escalated'] == true,
        createdBy: (j['created_by'] ?? '') as String,
        createdByKind: (j['created_by_kind'] ?? '') as String,
        assignedTo: (j['assigned_to'] ?? '') as String,
        createdAt: _dt(j['created_at']),
        updatedAt: _dt(j['updated_at']),
        resolvedAt: _dt(j['resolved_at']),
        replies: ((j['replies'] as List?) ?? const [])
            .map((e) => TicketReply.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class TicketReply {
  final int id;
  final String author;
  final String authorKind;
  final String body;
  final bool internal;
  final DateTime? ts;
  const TicketReply({
    required this.id,
    required this.author,
    required this.authorKind,
    required this.body,
    required this.internal,
    this.ts,
  });
  factory TicketReply.fromJson(Map<String, dynamic> j) => TicketReply(
        id: j['id'] as int,
        author: (j['author'] ?? '') as String,
        authorKind: (j['author_kind'] ?? '') as String,
        body: (j['body'] ?? '') as String,
        internal: j['internal'] == true,
        ts: _dt(j['ts']),
      );
}

/// إحصاءات التذاكر (/api/tickets/stats أو ضمن /api/portal/summary).
class TicketStats {
  final int total;
  final int openTotal;
  final int escalated;
  final Map<String, int> byStatus;
  final Map<String, int> byCategory;
  const TicketStats({
    required this.total,
    required this.openTotal,
    required this.escalated,
    required this.byStatus,
    required this.byCategory,
  });
  factory TicketStats.fromJson(Map<String, dynamic> j) => TicketStats(
        total: (j['total'] ?? 0) as int,
        openTotal: (j['open_total'] ?? 0) as int,
        escalated: (j['escalated'] ?? 0) as int,
        byStatus: _intMap(j['by_status']),
        byCategory: _intMap(j['by_category']),
      );
  static const empty = TicketStats(total: 0, openTotal: 0, escalated: 0, byStatus: {}, byCategory: {});
}

Map<String, int> _intMap(dynamic m) =>
    (m is Map) ? m.map((k, v) => MapEntry('$k', (v as num).toInt())) : const {};

DateTime? _dt(dynamic v) => v is String && v.isNotEmpty ? DateTime.tryParse(v) : null;

/// تسميات ثابتة — تطابق الباكند (services/tickets.py).
const ticketCategories = {
  'complaint': 'شكوى',
  'outage': 'انقطاع',
  'billing': 'فوترة/رصيد',
  'speed': 'بطء السرعة',
  'other': 'أخرى',
};
const ticketStatuses = {
  'open': 'مفتوحة',
  'in_progress': 'قيد المعالجة',
  'resolved': 'محلولة',
  'closed': 'مغلقة',
};
const ticketPriorities = {
  'low': 'منخفضة',
  'normal': 'عادية',
  'high': 'عالية',
  'urgent': 'عاجلة',
};
const authorKindAr = {
  'subscriber': 'المشترك',
  'agent': 'الوكيل',
  'company': 'الشركة',
  'regulator': 'الجهة الرقابية',
};
