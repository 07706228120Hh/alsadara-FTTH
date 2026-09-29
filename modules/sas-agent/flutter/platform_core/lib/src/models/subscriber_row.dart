/// صف مشترك من /api/companies/subscribers (قائمة الموظّفين) أو حساب من /api/subscriber/me.
class SubscriberRow {
  final int id;
  final int companyId;
  final String company, username, name, agent, agentName, profile, status;
  final bool online, enabled;
  final String expiration, city, governorate, phone;
  const SubscriberRow({
    required this.id,
    required this.companyId,
    required this.company,
    required this.username,
    required this.name,
    required this.agent,
    required this.agentName,
    required this.profile,
    required this.status,
    required this.online,
    required this.enabled,
    required this.expiration,
    required this.city,
    required this.governorate,
    required this.phone,
  });
  bool get active => status == 'active';

  /// تاريخ الانتهاء كما يرسله SAS (نصّ) — نحاول تحليله للعرض/التنبيه.
  DateTime? get expiresAt => DateTime.tryParse(expiration.replaceFirst(' ', 'T'));
  int? get daysLeft {
    final e = expiresAt;
    return e?.difference(DateTime.now()).inDays;
  }

  factory SubscriberRow.fromJson(Map<String, dynamic> j) => SubscriberRow(
        id: (j['id'] ?? 0) as int,
        companyId: (j['company_id'] ?? 0) as int,
        company: (j['company'] ?? '') as String,
        username: (j['username'] ?? '') as String,
        name: (j['name'] ?? '') as String,
        agent: (j['agent'] ?? '') as String,
        agentName: (j['agent_name'] ?? '') as String,
        profile: (j['profile'] ?? '') as String,
        status: (j['status'] ?? '') as String,
        online: j['online'] == true,
        enabled: j['enabled'] != false,
        expiration: (j['expiration'] ?? '') as String,
        city: (j['city'] ?? '') as String,
        governorate: (j['governorate'] ?? '') as String,
        phone: (j['phone'] ?? '') as String,
      );
}

/// صف وكيل من /api/companies/agents/all.
class AgentRow {
  final int id, companyId, managerId, usersCount;
  final String company, username, name, parentUsername;
  final double balance;
  final bool enabled;
  const AgentRow({
    required this.id,
    required this.companyId,
    required this.managerId,
    required this.usersCount,
    required this.company,
    required this.username,
    required this.name,
    required this.parentUsername,
    required this.balance,
    required this.enabled,
  });
  factory AgentRow.fromJson(Map<String, dynamic> j) => AgentRow(
        id: (j['id'] ?? 0) as int,
        companyId: (j['company_id'] ?? 0) as int,
        managerId: (j['manager_id'] ?? 0) as int,
        usersCount: (j['users_count'] ?? 0) as int,
        company: (j['company'] ?? '') as String,
        username: (j['username'] ?? '') as String,
        name: (j['name'] ?? '') as String,
        parentUsername: (j['parent_username'] ?? '') as String,
        balance: ((j['balance'] ?? 0) as num).toDouble(),
        enabled: j['enabled'] != false,
      );
}

/// صف البلنك الموحّد (/api/companies/reconciliation).
class ReconRow {
  final int companyId, agentId, sasAttributed, agentDeclared, declaredActive, diff;
  final String company, agentUsername, agentName, verdict;
  final DateTime? lastReportTs;
  const ReconRow({
    required this.companyId,
    required this.agentId,
    required this.sasAttributed,
    required this.agentDeclared,
    required this.declaredActive,
    required this.diff,
    required this.company,
    required this.agentUsername,
    required this.agentName,
    required this.verdict,
    this.lastReportTs,
  });
  factory ReconRow.fromJson(Map<String, dynamic> j) => ReconRow(
        companyId: (j['company_id'] ?? 0) as int,
        agentId: (j['agent_id'] ?? 0) as int,
        sasAttributed: (j['sas_attributed'] ?? 0) as int,
        agentDeclared: (j['agent_declared'] ?? 0) as int,
        declaredActive: (j['declared_active'] ?? 0) as int,
        diff: (j['diff'] ?? 0) as int,
        company: (j['company'] ?? '') as String,
        agentUsername: (j['agent_username'] ?? '') as String,
        agentName: (j['agent_name'] ?? '') as String,
        verdict: (j['verdict'] ?? 'no_report') as String,
        lastReportTs: j['last_report_ts'] is String ? DateTime.tryParse(j['last_report_ts']) : null,
      );
}

const verdictAr = {
  'matched': 'مطابق',
  'company_suspicious': 'فارق لصالح الوكيل',
  'agent_suspicious': 'فارق لصالح الشركة',
  'no_report': 'بلا تصريح',
};
