/// موديل المصروف
class Expense {
  final String id;
  final String accountId;
  final String? accountName;
  final double amount;
  final String description;
  final String? category;
  final String? paidFromCashBoxId;
  final String? attachmentUrl;
  final String? notes;
  final String companyId;
  final String? createdById;
  final DateTime? expenseDate;
  final DateTime? createdAt;

  const Expense({
    required this.id,
    required this.accountId,
    this.accountName,
    required this.amount,
    required this.description,
    this.category,
    this.paidFromCashBoxId,
    this.attachmentUrl,
    this.notes,
    required this.companyId,
    this.createdById,
    this.expenseDate,
    this.createdAt,
  });

  factory Expense.fromJson(Map<String, dynamic> j) => Expense(
        id: j['Id']?.toString() ?? '',
        accountId: j['AccountId']?.toString() ?? '',
        accountName: j['AccountName']?.toString(),
        amount: _toDouble(j['Amount']),
        description: j['Description']?.toString() ?? '',
        category: j['Category']?.toString(),
        paidFromCashBoxId: j['PaidFromCashBoxId']?.toString(),
        attachmentUrl: j['AttachmentUrl']?.toString(),
        notes: j['Notes']?.toString(),
        companyId: j['CompanyId']?.toString() ?? '',
        createdById: j['CreatedById']?.toString(),
        expenseDate: _parseDate(j['ExpenseDate']),
        createdAt: _parseDate(j['CreatedAt']),
      );

  Map<String, dynamic> toJson() => {
        'AccountId': accountId,
        'Amount': amount,
        'Description': description,
        if (category != null) 'Category': category,
        if (notes != null) 'Notes': notes,
        'CompanyId': companyId,
      };

  static double _toDouble(dynamic v) =>
      v == null ? 0 : (v is num ? v.toDouble() : double.tryParse('$v') ?? 0);

  static DateTime? _parseDate(dynamic v) =>
      v == null ? null : DateTime.tryParse(v.toString());
}
