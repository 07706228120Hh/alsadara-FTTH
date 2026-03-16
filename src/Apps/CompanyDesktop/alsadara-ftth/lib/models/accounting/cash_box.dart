/// نوع الصندوق
enum CashBoxType {
  main,
  pettyCash,
  bank;

  static CashBoxType fromString(String? v) {
    switch (v) {
      case 'PettyCash':
        return pettyCash;
      case 'Bank':
        return bank;
      default:
        return main;
    }
  }

  String get displayName {
    switch (this) {
      case main:
        return 'صندوق رئيسي';
      case pettyCash:
        return 'صندوق نثرية';
      case bank:
        return 'حساب بنكي';
    }
  }
}

/// موديل الصندوق
class CashBox {
  final String id;
  final String name;
  final CashBoxType cashBoxType;
  final double initialBalance;
  final double currentBalance;
  final String? responsibleUserId;
  final String? linkedAccountId;
  final String? notes;
  final String companyId;
  final bool isActive;
  final DateTime? createdAt;

  const CashBox({
    required this.id,
    required this.name,
    this.cashBoxType = CashBoxType.main,
    this.initialBalance = 0,
    this.currentBalance = 0,
    this.responsibleUserId,
    this.linkedAccountId,
    this.notes,
    required this.companyId,
    this.isActive = true,
    this.createdAt,
  });

  factory CashBox.fromJson(Map<String, dynamic> j) => CashBox(
        id: j['Id']?.toString() ?? '',
        name: j['Name']?.toString() ?? '',
        cashBoxType:
            CashBoxType.fromString(j['CashBoxType']?.toString()),
        initialBalance: _toDouble(j['InitialBalance']),
        currentBalance: _toDouble(j['CurrentBalance'] ?? j['Balance']),
        responsibleUserId: j['ResponsibleUserId']?.toString(),
        linkedAccountId: j['LinkedAccountId']?.toString(),
        notes: j['Notes']?.toString(),
        companyId: j['CompanyId']?.toString() ?? '',
        isActive: j['IsActive'] != false,
        createdAt: _parseDate(j['CreatedAt']),
      );

  Map<String, dynamic> toJson() => {
        'Name': name,
        'CashBoxType': cashBoxType.name,
        'InitialBalance': initialBalance,
        if (responsibleUserId != null) 'ResponsibleUserId': responsibleUserId,
        if (notes != null) 'Notes': notes,
        'CompanyId': companyId,
      };

  static double _toDouble(dynamic v) =>
      v == null ? 0 : (v is num ? v.toDouble() : double.tryParse('$v') ?? 0);

  static DateTime? _parseDate(dynamic v) =>
      v == null ? null : DateTime.tryParse(v.toString());
}
