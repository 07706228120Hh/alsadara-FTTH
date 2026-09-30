/// نماذج تذاكر «وكيل الساس» — قراءة مرنة لمفاتيح الخادم.
///
/// نظام تذاكر أصلي تحت `/api/sas-agent/tickets` (user-scoped). كل النماذج
/// تقرأ بمرونة (camelCase أو snake_case) حتى لا يكسرها تغيّر شكل الرد.
/// عرض فقط — لا استدعاءات API هنا.
library;

/// تحويل آمن لعدد صحيح من أي شكل (int/num/String).
int _int(dynamic v, [int d = 0]) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse('${v ?? ''}') ?? d;
}

/// نص آمن (يقبل null).
String _str(dynamic v, [String d = '']) => (v == null) ? d : '$v';

/// تاريخ آمن من نص ISO.
DateTime? _dt(dynamic v) =>
    (v is String && v.isNotEmpty) ? DateTime.tryParse(v) : null;

/// أوّل مفتاح غير فارغ من قائمة أسماء بديلة.
dynamic _pick(Map<String, dynamic> j, List<String> keys) {
  for (final k in keys) {
    final v = j[k];
    if (v != null) return v;
  }
  return null;
}

/// إحصاءات التذاكر — من `GET tickets/stats`.
class SasTicketStats {
  final int total;
  final int open;
  final int inProgress;
  final int resolved;
  final int closed;

  const SasTicketStats({
    this.total = 0,
    this.open = 0,
    this.inProgress = 0,
    this.resolved = 0,
    this.closed = 0,
  });

  static const empty = SasTicketStats();

  factory SasTicketStats.fromJson(Map<String, dynamic> j) => SasTicketStats(
        total: _int(_pick(j, ['total', 'all', 'count'])),
        open: _int(_pick(j, ['open', 'openTotal', 'open_total'])),
        inProgress: _int(_pick(j, ['in_progress', 'inProgress', 'progress'])),
        resolved: _int(_pick(j, ['resolved'])),
        closed: _int(_pick(j, ['closed'])),
      );
}

/// ردّ ضمن تذكرة — من `replies[]` في `GET tickets/{id}`.
class SasTicketReply {
  final String id;
  final String author;
  final String authorKind;
  final String body;
  final bool isInternal;
  final DateTime? createdAt;

  const SasTicketReply({
    required this.id,
    required this.author,
    required this.authorKind,
    required this.body,
    required this.isInternal,
    this.createdAt,
  });

  factory SasTicketReply.fromJson(Map<String, dynamic> j) => SasTicketReply(
        id: _str(_pick(j, ['id', '_id', 'replyId'])),
        author: _str(_pick(j, ['author', 'authorName', 'author_name', 'by'])),
        authorKind:
            _str(_pick(j, ['authorKind', 'author_kind', 'kind', 'role'])),
        body: _str(_pick(j, ['body', 'text', 'message', 'content'])),
        isInternal:
            _pick(j, ['isInternal', 'is_internal', 'internal']) == true,
        createdAt: _dt(_pick(j, ['createdAt', 'created_at', 'ts', 'date'])),
      );
}

/// تذكرة كاملة — من `GET tickets` (بلا ردود) و`GET tickets/{id}` (+ ردود).
class SasTicket {
  final String id;
  final String subject;
  final String body;
  final String status;
  final String priority;
  final String category;
  final String subscriberRef;
  final String createdBy;
  final String createdByKind;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final int repliesCount;
  final List<SasTicketReply> replies;

  const SasTicket({
    required this.id,
    required this.subject,
    required this.body,
    required this.status,
    required this.priority,
    required this.category,
    required this.subscriberRef,
    required this.createdBy,
    required this.createdByKind,
    this.createdAt,
    this.updatedAt,
    this.repliesCount = 0,
    this.replies = const [],
  });

  bool get isOpen => status == 'open' || status == 'in_progress';

  factory SasTicket.fromJson(Map<String, dynamic> j) {
    final rawReplies = _pick(j, ['replies', 'messages', 'thread']);
    final replies = (rawReplies is List)
        ? rawReplies
            .whereType<Map>()
            .map((e) => SasTicketReply.fromJson(e.cast<String, dynamic>()))
            .toList()
        : const <SasTicketReply>[];
    return SasTicket(
      id: _str(_pick(j, ['id', '_id', 'ticketId', 'ticket_id'])),
      subject: _str(_pick(j, ['subject', 'title'])),
      body: _str(_pick(j, ['body', 'description', 'text', 'message'])),
      status: _str(_pick(j, ['status']), 'open'),
      priority: _str(_pick(j, ['priority']), 'normal'),
      category: _str(_pick(j, ['category']), 'other'),
      subscriberRef: _str(
          _pick(j, ['subscriberRef', 'subscriber_ref', 'subscriber'])),
      createdBy: _str(_pick(j, ['createdBy', 'created_by', 'author'])),
      createdByKind: _str(
          _pick(j, ['createdByKind', 'created_by_kind', 'authorKind'])),
      createdAt: _dt(_pick(j, ['createdAt', 'created_at'])),
      updatedAt: _dt(_pick(j, ['updatedAt', 'updated_at'])),
      repliesCount: _int(
          _pick(j, ['repliesCount', 'replies_count', 'messagesCount']),
          replies.length),
      replies: replies,
    );
  }
}

/// صفحة تذاكر مُرقّمة — من `GET tickets?page=&count=`.
class SasTicketsPage {
  final List<SasTicket> rows;
  final int total;
  final int page;
  final int count;

  const SasTicketsPage({
    this.rows = const [],
    this.total = 0,
    this.page = 1,
    this.count = 20,
  });

  bool get hasMore => page * count < total;

  factory SasTicketsPage.fromJson(Map<String, dynamic> j) {
    // القائمة قد تكون تحت data/rows/items/tickets أو الجذر مباشرةً.
    dynamic list = _pick(j, ['data', 'rows', 'items', 'tickets']);
    if (list is Map) {
      list = _pick(list.cast<String, dynamic>(), ['data', 'rows', 'items']);
    }
    final rows = (list is List)
        ? list
            .whereType<Map>()
            .map((e) => SasTicket.fromJson(e.cast<String, dynamic>()))
            .toList()
        : const <SasTicket>[];
    return SasTicketsPage(
      rows: rows,
      total: _int(_pick(j, ['total', 'count', 'totalCount']), rows.length),
      page: _int(_pick(j, ['page', 'currentPage']), 1),
      count: _int(_pick(j, ['count', 'pageSize', 'perPage']), 20),
    );
  }
}

// ─────────────────────────── تسميات ثابتة ───────────────────────────

/// تصنيفات التذاكر (قيمة API → عربي).
const sasTicketCategories = <String, String>{
  'complaint': 'شكوى',
  'outage': 'انقطاع',
  'billing': 'فوترة/رصيد',
  'speed': 'بطء السرعة',
  'technical': 'فنّي',
  'other': 'أخرى',
};

/// حالات التذكرة.
const sasTicketStatuses = <String, String>{
  'open': 'مفتوحة',
  'in_progress': 'قيد المعالجة',
  'resolved': 'محلولة',
  'closed': 'مغلقة',
};

/// أولويات التذكرة.
const sasTicketPriorities = <String, String>{
  'low': 'منخفضة',
  'normal': 'عادية',
  'high': 'عالية',
  'urgent': 'عاجلة',
};

/// نوع كاتب الرد (عربي).
const sasAuthorKindAr = <String, String>{
  'subscriber': 'المشترك',
  'agent': 'الوكيل',
  'company': 'الشركة',
  'staff': 'الموظّف',
  'operator': 'المشغّل',
  'regulator': 'الجهة الرقابية',
};

String sasCategoryAr(String c) => sasTicketCategories[c] ?? c;
String sasStatusAr(String s) => sasTicketStatuses[s] ?? s;
String sasPriorityAr(String p) => sasTicketPriorities[p] ?? p;
String sasAuthorAr(String k) => sasAuthorKindAr[k] ?? k;
