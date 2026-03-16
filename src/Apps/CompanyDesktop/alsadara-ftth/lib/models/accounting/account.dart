/// موديل الحساب المحاسبي
class Account {
  final String id;
  final String code;
  final String name;
  final String? nameEn;
  final String accountType;
  final String? parentAccountId;
  final String? description;
  final double openingBalance;
  final double balance;
  final bool isActive;
  final bool isLeaf;
  final String companyId;
  final DateTime? createdAt;
  final List<Account> children;

  const Account({
    required this.id,
    required this.code,
    required this.name,
    this.nameEn,
    required this.accountType,
    this.parentAccountId,
    this.description,
    this.openingBalance = 0,
    this.balance = 0,
    this.isActive = true,
    this.isLeaf = true,
    required this.companyId,
    this.createdAt,
    this.children = const [],
  });

  factory Account.fromJson(Map<String, dynamic> j) => Account(
        id: j['Id']?.toString() ?? '',
        code: j['Code']?.toString() ?? '',
        name: j['Name']?.toString() ?? '',
        nameEn: j['NameEn']?.toString(),
        accountType:
            j['AccountType']?.toString() ?? j['Type']?.toString() ?? '',
        parentAccountId: j['ParentAccountId']?.toString(),
        description: j['Description']?.toString(),
        openingBalance: _toDouble(j['OpeningBalance']),
        balance: _toDouble(j['CurrentBalance'] ?? j['Balance']),
        isActive: j['IsActive'] != false,
        isLeaf: j['IsLeaf'] == true,
        companyId: j['CompanyId']?.toString() ?? '',
        createdAt: _parseDate(j['CreatedAt']),
        children: j['Children'] is List
            ? (j['Children'] as List)
                .map((c) => Account.fromJson(c as Map<String, dynamic>))
                .toList()
            : const [],
      );

  Map<String, dynamic> toJson() => {
        'Id': id,
        'Code': code,
        'Name': name,
        if (nameEn != null) 'NameEn': nameEn,
        'AccountType': accountType,
        if (parentAccountId != null) 'ParentAccountId': parentAccountId,
        if (description != null) 'Description': description,
        'OpeningBalance': openingBalance,
        'IsActive': isActive,
        'CompanyId': companyId,
      };

  static double _toDouble(dynamic v) =>
      v == null ? 0 : (v is num ? v.toDouble() : double.tryParse('$v') ?? 0);

  static DateTime? _parseDate(dynamic v) =>
      v == null ? null : DateTime.tryParse(v.toString());
}
