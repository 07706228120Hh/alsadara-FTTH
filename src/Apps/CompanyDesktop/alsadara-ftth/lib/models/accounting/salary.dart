/// حالة الراتب
enum SalaryStatus {
  pending,
  paid,
  partiallyPaid,
  cancelled;

  static SalaryStatus fromString(String? v) {
    switch (v) {
      case 'Paid':
        return paid;
      case 'PartiallyPaid':
        return partiallyPaid;
      case 'Cancelled':
        return cancelled;
      default:
        return pending;
    }
  }

  String get displayName {
    switch (this) {
      case pending:
        return 'معلق';
      case paid:
        return 'مدفوع';
      case partiallyPaid:
        return 'مدفوع جزئياً';
      case cancelled:
        return 'ملغي';
    }
  }
}

/// موديل الراتب
class Salary {
  final String id;
  final String? employeeId;
  final String? employeeName;
  final int month;
  final int year;
  final double baseSalary;
  final double allowances;
  final double deductions;
  final double bonuses;
  final double netSalary;
  final double lateDeduction;
  final double absentDeduction;
  final double overtimeBonus;
  final int attendanceDays;
  final int expectedWorkDays;
  final int absentDays;
  final SalaryStatus status;
  final String? notes;
  final String companyId;
  final DateTime? paidAt;
  final DateTime? createdAt;

  const Salary({
    required this.id,
    this.employeeId,
    this.employeeName,
    required this.month,
    required this.year,
    this.baseSalary = 0,
    this.allowances = 0,
    this.deductions = 0,
    this.bonuses = 0,
    this.netSalary = 0,
    this.lateDeduction = 0,
    this.absentDeduction = 0,
    this.overtimeBonus = 0,
    this.attendanceDays = 0,
    this.expectedWorkDays = 26,
    this.absentDays = 0,
    this.status = SalaryStatus.pending,
    this.notes,
    required this.companyId,
    this.paidAt,
    this.createdAt,
  });

  factory Salary.fromJson(Map<String, dynamic> j) => Salary(
        id: j['Id']?.toString() ?? '',
        employeeId:
            j['UserId']?.toString() ?? j['EmployeeId']?.toString(),
        employeeName: j['EmployeeName']?.toString() ??
            j['UserName']?.toString(),
        month: j['Month'] is int ? j['Month'] : 1,
        year: j['Year'] is int ? j['Year'] : DateTime.now().year,
        baseSalary: _toDouble(j['BaseSalary']),
        allowances: _toDouble(j['Allowances']),
        deductions: _toDouble(j['Deductions']),
        bonuses: _toDouble(j['Bonuses']),
        netSalary: _toDouble(j['NetSalary']),
        lateDeduction: _toDouble(j['LateDeduction']),
        absentDeduction: _toDouble(j['AbsentDeduction']),
        overtimeBonus: _toDouble(j['OvertimeBonus']),
        attendanceDays:
            j['AttendanceDays'] is int ? j['AttendanceDays'] : 0,
        expectedWorkDays:
            j['ExpectedWorkDays'] is int ? j['ExpectedWorkDays'] : 26,
        absentDays: j['AbsentDays'] is int ? j['AbsentDays'] : 0,
        status: SalaryStatus.fromString(j['Status']?.toString()),
        notes: j['Notes']?.toString(),
        companyId: j['CompanyId']?.toString() ?? '',
        paidAt: _parseDate(j['PaidAt']),
        createdAt: _parseDate(j['CreatedAt']),
      );

  static double _toDouble(dynamic v) =>
      v == null ? 0 : (v is num ? v.toDouble() : double.tryParse('$v') ?? 0);

  static DateTime? _parseDate(dynamic v) =>
      v == null ? null : DateTime.tryParse(v.toString());
}
