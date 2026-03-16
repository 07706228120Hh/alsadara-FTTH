/// تصنيف المصروف الثابت
enum FixedExpenseCategory {
  officeRent,
  generator,
  internet,
  electricity,
  water,
  other;

  static FixedExpenseCategory fromInt(int? v) {
    switch (v) {
      case 0:
        return officeRent;
      case 1:
        return generator;
      case 2:
        return internet;
      case 3:
        return electricity;
      case 4:
        return water;
      default:
        return other;
    }
  }

  int get intValue {
    switch (this) {
      case officeRent:
        return 0;
      case generator:
        return 1;
      case internet:
        return 2;
      case electricity:
        return 3;
      case water:
        return 4;
      case other:
        return 99;
    }
  }

  String get displayName {
    switch (this) {
      case officeRent:
        return 'إيجار مكتب';
      case generator:
        return 'مولدة';
      case internet:
        return 'إنترنت';
      case electricity:
        return 'كهرباء';
      case water:
        return 'ماء';
      case other:
        return 'أخرى';
    }
  }
}

/// موديل المصروف الثابت
class FixedExpense {
  final int id;
  final String name;
  final FixedExpenseCategory category;
  final double monthlyAmount;
  final String? description;
  final String companyId;
  final bool isActive;
  final DateTime? createdAt;

  const FixedExpense({
    required this.id,
    required this.name,
    this.category = FixedExpenseCategory.other,
    required this.monthlyAmount,
    this.description,
    required this.companyId,
    this.isActive = true,
    this.createdAt,
  });

  factory FixedExpense.fromJson(Map<String, dynamic> j) => FixedExpense(
        id: j['Id'] is int ? j['Id'] : int.tryParse('${j['Id']}') ?? 0,
        name: j['Name']?.toString() ?? '',
        category: FixedExpenseCategory.fromInt(j['Category'] is int
            ? j['Category']
            : int.tryParse('${j['Category']}') ?? 99),
        monthlyAmount: _toDouble(j['MonthlyAmount']),
        description: j['Description']?.toString(),
        companyId: j['CompanyId']?.toString() ?? '',
        isActive: j['IsActive'] != false,
        createdAt: _parseDate(j['CreatedAt']),
      );

  Map<String, dynamic> toJson() => {
        'Name': name,
        'Category': category.intValue,
        'MonthlyAmount': monthlyAmount,
        if (description != null) 'Description': description,
        'CompanyId': companyId,
      };

  static double _toDouble(dynamic v) =>
      v == null ? 0 : (v is num ? v.toDouble() : double.tryParse('$v') ?? 0);

  static DateTime? _parseDate(dynamic v) =>
      v == null ? null : DateTime.tryParse(v.toString());
}

/// موديل دفعة المصروف الثابت
class FixedExpensePayment {
  final int id;
  final int fixedExpenseId;
  final int month;
  final int year;
  final double amount;
  final String? notes;
  final DateTime? paidAt;

  const FixedExpensePayment({
    required this.id,
    required this.fixedExpenseId,
    required this.month,
    required this.year,
    required this.amount,
    this.notes,
    this.paidAt,
  });

  factory FixedExpensePayment.fromJson(Map<String, dynamic> j) =>
      FixedExpensePayment(
        id: j['Id'] is int ? j['Id'] : int.tryParse('${j['Id']}') ?? 0,
        fixedExpenseId: j['FixedExpenseId'] is int
            ? j['FixedExpenseId']
            : int.tryParse('${j['FixedExpenseId']}') ?? 0,
        month: j['Month'] is int ? j['Month'] : 1,
        year: j['Year'] is int ? j['Year'] : DateTime.now().year,
        amount: _toDouble(j['Amount']),
        notes: j['Notes']?.toString(),
        paidAt: _parseDate(j['PaidAt']),
      );

  static double _toDouble(dynamic v) =>
      v == null ? 0 : (v is num ? v.toDouble() : double.tryParse('$v') ?? 0);

  static DateTime? _parseDate(dynamic v) =>
      v == null ? null : DateTime.tryParse(v.toString());
}
