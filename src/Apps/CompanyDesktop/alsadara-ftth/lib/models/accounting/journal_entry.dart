/// حالة القيد المحاسبي
enum JournalEntryStatus {
  draft,
  posted,
  voided;

  static JournalEntryStatus fromString(String? v) {
    switch (v) {
      case 'Posted':
        return posted;
      case 'Voided':
        return voided;
      default:
        return draft;
    }
  }

  String get displayName {
    switch (this) {
      case draft:
        return 'مسودة';
      case posted:
        return 'مرحّل';
      case voided:
        return 'ملغي';
    }
  }
}

/// نوع المرجع
enum ReferenceType {
  manual,
  cashTransaction,
  salary,
  technicianCollection,
  expense;

  static ReferenceType fromString(String? v) {
    switch (v) {
      case 'CashTransaction':
        return cashTransaction;
      case 'Salary':
        return salary;
      case 'TechnicianCollection':
        return technicianCollection;
      case 'Expense':
        return expense;
      default:
        return manual;
    }
  }

  String get displayName {
    switch (this) {
      case manual:
        return 'يدوي';
      case cashTransaction:
        return 'حركة صندوق';
      case salary:
        return 'رواتب';
      case technicianCollection:
        return 'تحصيل';
      case expense:
        return 'مصروف';
    }
  }
}

/// سطر في القيد المحاسبي
class JournalEntryLine {
  final String? id;
  final String accountId;
  final String? accountName;
  final double debitAmount;
  final double creditAmount;

  const JournalEntryLine({
    this.id,
    required this.accountId,
    this.accountName,
    this.debitAmount = 0,
    this.creditAmount = 0,
  });

  factory JournalEntryLine.fromJson(Map<String, dynamic> j) =>
      JournalEntryLine(
        id: j['Id']?.toString(),
        accountId: j['AccountId']?.toString() ?? '',
        accountName: j['AccountName']?.toString(),
        debitAmount: _toDouble(j['DebitAmount']),
        creditAmount: _toDouble(j['CreditAmount']),
      );

  Map<String, dynamic> toJson() => {
        'AccountId': accountId,
        'DebitAmount': debitAmount,
        'CreditAmount': creditAmount,
      };

  static double _toDouble(dynamic v) =>
      v == null ? 0 : (v is num ? v.toDouble() : double.tryParse('$v') ?? 0);
}

/// القيد المحاسبي
class JournalEntry {
  final String id;
  final int? entryNumber;
  final String description;
  final String? notes;
  final JournalEntryStatus status;
  final ReferenceType? referenceType;
  final DateTime? entryDate;
  final DateTime? createdAt;
  final String? createdById;
  final String? approvedById;
  final String companyId;
  final List<JournalEntryLine> lines;

  const JournalEntry({
    required this.id,
    this.entryNumber,
    required this.description,
    this.notes,
    this.status = JournalEntryStatus.draft,
    this.referenceType,
    this.entryDate,
    this.createdAt,
    this.createdById,
    this.approvedById,
    required this.companyId,
    this.lines = const [],
  });

  double get totalDebit => lines.fold(0, (s, l) => s + l.debitAmount);
  double get totalCredit => lines.fold(0, (s, l) => s + l.creditAmount);
  bool get isBalanced => (totalDebit - totalCredit).abs() < 0.01;

  factory JournalEntry.fromJson(Map<String, dynamic> j) => JournalEntry(
        id: j['Id']?.toString() ?? '',
        entryNumber: j['EntryNumber'] is int ? j['EntryNumber'] : null,
        description: j['Description']?.toString() ?? '',
        notes: j['Notes']?.toString(),
        status: JournalEntryStatus.fromString(j['Status']?.toString()),
        referenceType:
            ReferenceType.fromString(j['ReferenceType']?.toString()),
        entryDate: _parseDate(j['EntryDate']),
        createdAt: _parseDate(j['CreatedAt']),
        createdById: j['CreatedById']?.toString(),
        approvedById: j['ApprovedById']?.toString(),
        companyId: j['CompanyId']?.toString() ?? '',
        lines: j['Lines'] is List
            ? (j['Lines'] as List)
                .map(
                    (l) => JournalEntryLine.fromJson(l as Map<String, dynamic>))
                .toList()
            : const [],
      );

  static DateTime? _parseDate(dynamic v) =>
      v == null ? null : DateTime.tryParse(v.toString());
}
