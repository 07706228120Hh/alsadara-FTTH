import 'ticket.dart';

/// أعداد المشتركين حسب الحالة.
class SubCounts {
  final int total, active, expired, online;
  const SubCounts({this.total = 0, this.active = 0, this.expired = 0, this.online = 0});
  factory SubCounts.fromJson(Map<String, dynamic>? j) => j == null
      ? const SubCounts()
      : SubCounts(
          total: (j['total'] ?? 0) as int,
          active: (j['active'] ?? 0) as int,
          expired: (j['expired'] ?? 0) as int,
          online: (j['online'] ?? 0) as int,
        );
}

/// عدّاد نوافذ الانتهاء (تنبيهات التجديد) — تراكميّ: soon3 يشمل today، soon7 يشمل soon3.
class ExpiryCounts {
  final int overdue, today, soon3, soon7;
  const ExpiryCounts({this.overdue = 0, this.today = 0, this.soon3 = 0, this.soon7 = 0});
  int get total => overdue + today + soon3 + soon7;
  bool get any => overdue > 0 || soon7 > 0;
  factory ExpiryCounts.fromJson(Map<String, dynamic>? j) => j == null
      ? const ExpiryCounts()
      : ExpiryCounts(
          overdue: (j['overdue'] ?? 0) as int,
          today: (j['today'] ?? 0) as int,
          soon3: (j['soon3'] ?? 0) as int,
          soon7: (j['soon7'] ?? 0) as int,
        );
}

/// بطاقة شركة (مع آخر لقطة SAS).
class CompanyBlock {
  final int id;
  final String name, code, color, governorate, accessType;
  final bool lastSyncOk;
  final DateTime? lastSyncAt;
  final int total, active, expired, online, managers;
  const CompanyBlock({
    required this.id,
    required this.name,
    required this.code,
    required this.color,
    required this.governorate,
    required this.accessType,
    required this.lastSyncOk,
    this.lastSyncAt,
    this.total = 0,
    this.active = 0,
    this.expired = 0,
    this.online = 0,
    this.managers = 0,
  });
  factory CompanyBlock.fromJson(Map<String, dynamic> j) {
    final s = (j['snapshot'] as Map?) ?? const {};
    return CompanyBlock(
      id: (j['id'] ?? 0) as int,
      name: (j['name'] ?? '') as String,
      code: (j['code'] ?? '') as String,
      color: (j['color'] ?? '#22D3EE') as String,
      governorate: (j['governorate'] ?? '') as String,
      accessType: (j['access_type'] ?? '') as String,
      lastSyncOk: j['last_sync_ok'] == true,
      lastSyncAt: j['last_sync_at'] is String ? DateTime.tryParse(j['last_sync_at']) : null,
      total: (s['total'] ?? 0) as int,
      active: (s['active'] ?? 0) as int,
      expired: (s['expired'] ?? 0) as int,
      online: (s['online'] ?? 0) as int,
      managers: (s['managers'] ?? 0) as int,
    );
  }
}

/// بطاقة الوكيل (من SAS).
class AgentBlock {
  final int? id;
  final String username, name, parentUsername;
  final int usersCount;
  final double balance, rewardPoints;
  final bool enabled;
  const AgentBlock({
    this.id,
    required this.username,
    required this.name,
    required this.parentUsername,
    required this.usersCount,
    required this.balance,
    required this.rewardPoints,
    required this.enabled,
  });
  factory AgentBlock.fromJson(Map<String, dynamic> j) => AgentBlock(
        id: j['id'] as int?,
        username: (j['username'] ?? '') as String,
        name: (j['name'] ?? '') as String,
        parentUsername: (j['parent_username'] ?? '') as String,
        usersCount: (j['users_count'] ?? 0) as int,
        balance: ((j['balance'] ?? 0) as num).toDouble(),
        rewardPoints: ((j['reward_points'] ?? 0) as num).toDouble(),
        enabled: j['enabled'] != false,
      );
}

/// آخر تصريح للوكيل.
class LastReport {
  final int declaredTotal, declaredActive;
  final String note;
  final DateTime? ts;
  const LastReport({required this.declaredTotal, required this.declaredActive, required this.note, this.ts});
  factory LastReport.fromJson(Map<String, dynamic> j) => LastReport(
        declaredTotal: (j['declared_total'] ?? 0) as int,
        declaredActive: (j['declared_active'] ?? 0) as int,
        note: (j['note'] ?? '') as String,
        ts: j['ts'] is String ? DateTime.tryParse(j['ts']) : null,
      );
}

/// ملخّص /api/portal/summary — يختلف محتواه حسب نوع الحساب.
class PortalSummary {
  final String kind;
  final TicketStats tickets;
  final SubCounts subscribers;
  final ExpiryCounts expiry;        // وكيل — تنبيهات التجديد
  final CompanyBlock? company;      // وكيل/شركة
  final AgentBlock? agent;          // وكيل
  final LastReport? lastReport;     // وكيل
  final int agentsCount;            // شركة
  final List<CompanyBlock> companies; // وزارة
  final SubCounts totals;           // وزارة (من اللقطات)
  const PortalSummary({
    required this.kind,
    required this.tickets,
    required this.subscribers,
    this.expiry = const ExpiryCounts(),
    this.company,
    this.agent,
    this.lastReport,
    this.agentsCount = 0,
    this.companies = const [],
    this.totals = const SubCounts(),
  });
  factory PortalSummary.fromJson(Map<String, dynamic> j) => PortalSummary(
        kind: (j['kind'] ?? 'regulator') as String,
        tickets: TicketStats.fromJson((j['tickets'] as Map<String, dynamic>?) ?? const {}),
        subscribers: SubCounts.fromJson(j['subscribers'] as Map<String, dynamic>?),
        expiry: ExpiryCounts.fromJson(j['expiry'] as Map<String, dynamic>?),
        company: j['company'] is Map ? CompanyBlock.fromJson(j['company'] as Map<String, dynamic>) : null,
        agent: j['agent'] is Map ? AgentBlock.fromJson(j['agent'] as Map<String, dynamic>) : null,
        lastReport: j['last_report'] is Map ? LastReport.fromJson(j['last_report'] as Map<String, dynamic>) : null,
        agentsCount: (j['agents_count'] ?? 0) as int,
        companies: ((j['companies'] as List?) ?? const [])
            .map((e) => CompanyBlock.fromJson(e as Map<String, dynamic>))
            .toList(),
        totals: SubCounts.fromJson(j['totals'] as Map<String, dynamic>?),
      );
}
