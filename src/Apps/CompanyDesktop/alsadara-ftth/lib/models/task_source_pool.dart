/// نماذج «مجمّع مصدر المهام» — مخرجات `GET /api/tasks/source-pool`.
///
/// تعريفات فقط (id/label/username/serverUrl) — لا تحمل أي كلمة مرور.
/// تُستخدم في المنسدلات المتتالية بحوار إنشاء/تعديل المهمة.
library;

/// خيار حساب مصدر (FTTH أو ساس).
class SourceAccountOption {
  final String id; // Guid الحساب
  final String label; // التسمية المعروضة
  final String username;
  final String serverUrl;
  final int? accountType; // لحسابات الساس فقط (int)

  const SourceAccountOption({
    required this.id,
    required this.label,
    required this.username,
    this.serverUrl = '',
    this.accountType,
  });

  factory SourceAccountOption.fromJson(Map<String, dynamic> j) {
    return SourceAccountOption(
      id: (j['id'] ?? j['Id'])?.toString() ?? '',
      label: (j['label'] ?? j['Label'])?.toString() ?? '',
      username: (j['username'] ?? j['Username'])?.toString() ?? '',
      serverUrl: (j['serverUrl'] ?? j['ServerUrl'])?.toString() ?? '',
      accountType: _asInt(j['accountType'] ?? j['AccountType']),
    );
  }

  /// نص العرض المدمج: التسمية + اسم المستخدم.
  String get display =>
      username.isNotEmpty && username != label ? '$label ($username)' : label;
}

/// خيار شريك رئيسي (FTTH).
class PartnerOption {
  final String partnerId;
  final String partnerName;

  const PartnerOption({required this.partnerId, required this.partnerName});

  factory PartnerOption.fromJson(Map<String, dynamic> j) {
    return PartnerOption(
      partnerId: (j['partnerId'] ?? j['PartnerId'])?.toString() ?? '',
      partnerName: (j['partnerName'] ?? j['PartnerName'])?.toString() ?? '',
    );
  }
}

/// خيار منطقة ساس.
class SasRegionOption {
  final String id; // Guid المنطقة (يُرسل كـ RegionRef)
  final String name;
  final String code;

  const SasRegionOption({required this.id, required this.name, this.code = ''});

  factory SasRegionOption.fromJson(Map<String, dynamic> j) {
    return SasRegionOption(
      id: (j['id'] ?? j['Id'])?.toString() ?? '',
      name: (j['name'] ?? j['Name'])?.toString() ?? '',
      code: (j['code'] ?? j['Code'])?.toString() ?? '',
    );
  }
}

/// المجمّع الكامل.
class TaskSourcePool {
  final List<SourceAccountOption> ftthAccounts;
  final List<SourceAccountOption> sasAccounts;
  final List<PartnerOption> partners;
  final List<SasRegionOption> sasRegions;

  const TaskSourcePool({
    this.ftthAccounts = const [],
    this.sasAccounts = const [],
    this.partners = const [],
    this.sasRegions = const [],
  });

  factory TaskSourcePool.fromJson(Map<String, dynamic> data) {
    return TaskSourcePool(
      ftthAccounts: _list(data['ftthAccounts'] ?? data['FtthAccounts'])
          .map(SourceAccountOption.fromJson)
          .toList(),
      sasAccounts: _list(data['sasAccounts'] ?? data['SasAccounts'])
          .map(SourceAccountOption.fromJson)
          .toList(),
      partners: _list(data['partners'] ?? data['Partners'])
          .map(PartnerOption.fromJson)
          .toList(),
      sasRegions: _list(data['sasRegions'] ?? data['SasRegions'])
          .map(SasRegionOption.fromJson)
          .toList(),
    );
  }
}

List<Map<String, dynamic>> _list(dynamic raw) {
  if (raw is List) {
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }
  return const [];
}

int? _asInt(dynamic raw) {
  if (raw == null) return null;
  if (raw is int) return raw;
  if (raw is num) return raw.toInt();
  return int.tryParse(raw.toString());
}
