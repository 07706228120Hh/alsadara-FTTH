using Sadara.Domain.Enums;

namespace Sadara.Domain.Entities;

// ==================== نظام المحاسبة - Accounting System ====================

/// <summary>
/// شجرة الحسابات - Chart of Accounts
/// الحساب المحاسبي الأساسي (أصول، خصوم، إيرادات، مصروفات، حقوق ملكية)
/// يدعم التسلسل الهرمي عبر ParentAccountId
/// </summary>
public class Account : BaseEntity<Guid>
{
    /// <summary>كود الحساب (مثل 1000, 1100, 1110)</summary>
    public string Code { get; set; } = string.Empty;

    /// <summary>اسم الحساب بالعربية</summary>
    public string Name { get; set; } = string.Empty;

    /// <summary>اسم الحساب بالإنجليزية (اختياري)</summary>
    public string? NameEn { get; set; }

    /// <summary>نوع الحساب (أصول، خصوم، إيرادات، مصروفات، حقوق ملكية)</summary>
    public AccountType AccountType { get; set; }

    /// <summary>الحساب الأب (للتسلسل الهرمي)</summary>
    public Guid? ParentAccountId { get; set; }
    public Account? ParentAccount { get; set; }

    /// <summary>الحسابات الفرعية</summary>
    public List<Account> SubAccounts { get; set; } = new();

    /// <summary>الرصيد الافتتاحي</summary>
    public decimal OpeningBalance { get; set; } = 0;

    /// <summary>الرصيد الحالي (يتحدث مع كل قيد)</summary>
    public decimal CurrentBalance { get; set; } = 0;

    /// <summary>حساب نظامي (لا يمكن حذفه)</summary>
    public bool IsSystemAccount { get; set; } = false;

    /// <summary>مستوى الحساب في الشجرة (1 = رئيسي)</summary>
    public int Level { get; set; } = 1;

    /// <summary>هل هو حساب فرعي نهائي (يمكن الترحيل إليه)</summary>
    public bool IsLeaf { get; set; } = true;

    /// <summary>نشط أم لا</summary>
    public bool IsActive { get; set; } = true;

    /// <summary>وصف الحساب</summary>
    public string? Description { get; set; }

    /// <summary>الشركة المالكة</summary>
    public Guid CompanyId { get; set; }
    public Company? Company { get; set; }

    /// <summary>سطور القيود المرتبطة</summary>
    public List<JournalEntryLine> JournalEntryLines { get; set; } = new();
}

/// <summary>
/// القيد المحاسبي - Journal Entry
/// يحتوي على سطور (مدين ودائن) يجب أن يتساوى مجموعها
/// </summary>
public class JournalEntry : BaseEntity<Guid>
{
    /// <summary>رقم القيد التسلسلي (JE-2025-0001)</summary>
    public string EntryNumber { get; set; } = string.Empty;

    /// <summary>تاريخ القيد</summary>
    public DateTime EntryDate { get; set; } = DateTime.UtcNow;

    /// <summary>وصف القيد</summary>
    public string Description { get; set; } = string.Empty;

    /// <summary>إجمالي المدين</summary>
    public decimal TotalDebit { get; set; }

    /// <summary>إجمالي الدائن</summary>
    public decimal TotalCredit { get; set; }

    /// <summary>نوع المرجع (تحصيل، راتب، صندوق، يدوي)</summary>
    public JournalReferenceType ReferenceType { get; set; } = JournalReferenceType.Manual;

    /// <summary>معرّف المرجع (مثل Id التحصيل أو الراتب)</summary>
    public string? ReferenceId { get; set; }

    /// <summary>حالة القيد</summary>
    public JournalEntryStatus Status { get; set; } = JournalEntryStatus.Draft;

    /// <summary>ملاحظات إضافية</summary>
    public string? Notes { get; set; }

    /// <summary>الشركة</summary>
    public Guid CompanyId { get; set; }
    public Company? Company { get; set; }

    /// <summary>المستخدم الذي أنشأ القيد</summary>
    public Guid CreatedById { get; set; }
    public User? CreatedBy { get; set; }

    /// <summary>المستخدم الذي اعتمد القيد</summary>
    public Guid? ApprovedById { get; set; }
    public User? ApprovedBy { get; set; }

    /// <summary>تاريخ الاعتماد</summary>
    public DateTime? ApprovedAt { get; set; }

    /// <summary>سطور القيد</summary>
    public List<JournalEntryLine> Lines { get; set; } = new();
}

/// <summary>
/// سطر القيد المحاسبي - Journal Entry Line
/// كل سطر إما مدين أو دائن
/// </summary>
public class JournalEntryLine : BaseEntity<long>
{
    /// <summary>القيد الأب</summary>
    public Guid JournalEntryId { get; set; }
    public JournalEntry? JournalEntry { get; set; }

    /// <summary>الحساب</summary>
    public Guid AccountId { get; set; }
    public Account? Account { get; set; }

    /// <summary>المبلغ المدين</summary>
    public decimal DebitAmount { get; set; } = 0;

    /// <summary>المبلغ الدائن</summary>
    public decimal CreditAmount { get; set; } = 0;

    /// <summary>وصف السطر</summary>
    public string? Description { get; set; }

    /// <summary>نوع الكيان المرتبط (فني، وكيل، مواطن)</summary>
    public string? EntityType { get; set; }

    /// <summary>معرّف الكيان المرتبط</summary>
    public string? EntityId { get; set; }
}

/// <summary>
/// الصندوق / القاصة - Cash Box
/// يتتبع النقد الفعلي (صندوق رئيسي، قاصة فرعية)
/// </summary>
public class CashBox : BaseEntity<Guid>
{
    /// <summary>اسم الصندوق</summary>
    public string Name { get; set; } = string.Empty;

    /// <summary>نوع الصندوق</summary>
    public CashBoxType CashBoxType { get; set; } = CashBoxType.Main;

    /// <summary>الرصيد الحالي</summary>
    public decimal CurrentBalance { get; set; } = 0;

    /// <summary>نشط أم لا</summary>
    public bool IsActive { get; set; } = true;

    /// <summary>المسؤول عن الصندوق</summary>
    public Guid? ResponsibleUserId { get; set; }
    public User? ResponsibleUser { get; set; }

    /// <summary>الشركة</summary>
    public Guid CompanyId { get; set; }
    public Company? Company { get; set; }

    /// <summary>الحساب المحاسبي المرتبط</summary>
    public Guid? LinkedAccountId { get; set; }
    public Account? LinkedAccount { get; set; }

    /// <summary>الملاحظات</summary>
    public string? Notes { get; set; }

    /// <summary>حركات الصندوق</summary>
    public List<CashTransaction> Transactions { get; set; } = new();
}

/// <summary>
/// حركة صندوق - Cash Transaction
/// كل إدخال أو إخراج من الصندوق/القاصة
/// </summary>
public class CashTransaction : BaseEntity<long>
{
    /// <summary>الصندوق</summary>
    public Guid CashBoxId { get; set; }
    public CashBox? CashBox { get; set; }

    /// <summary>نوع الحركة (إدخال / إخراج)</summary>
    public CashTransactionType TransactionType { get; set; }

    /// <summary>المبلغ</summary>
    public decimal Amount { get; set; }

    /// <summary>الرصيد بعد الحركة</summary>
    public decimal BalanceAfter { get; set; }

    /// <summary>الوصف</summary>
    public string Description { get; set; } = string.Empty;

    /// <summary>القيد المحاسبي المرتبط (اختياري)</summary>
    public Guid? JournalEntryId { get; set; }
    public JournalEntry? JournalEntry { get; set; }

    /// <summary>نوع المرجع (تحصيل، راتب، مصروف، إيداع)</summary>
    public JournalReferenceType ReferenceType { get; set; }

    /// <summary>معرّف المرجع</summary>
    public string? ReferenceId { get; set; }

    /// <summary>المستخدم الذي أجرى الحركة</summary>
    public Guid CreatedById { get; set; }
    public User? CreatedBy { get; set; }
}

/// <summary>
/// راتب الموظف - Employee Salary
/// سجل شهري لراتب كل موظف
/// </summary>
public class EmployeeSalary : BaseEntity<long>
{
    /// <summary>الموظف</summary>
    public Guid UserId { get; set; }
    public User? User { get; set; }

    /// <summary>الشهر (1-12)</summary>
    public int Month { get; set; }

    /// <summary>السنة</summary>
    public int Year { get; set; }

    /// <summary>الراتب الأساسي</summary>
    public decimal BaseSalary { get; set; }

    /// <summary>البدلات</summary>
    public decimal Allowances { get; set; } = 0;

    /// <summary>الخصومات</summary>
    public decimal Deductions { get; set; } = 0;

    /// <summary>المكافآت</summary>
    public decimal Bonuses { get; set; } = 0;

    /// <summary>صافي الراتب المحسوب</summary>
    public decimal NetSalary { get; set; }

    /// <summary>حالة الراتب</summary>
    public SalaryStatus Status { get; set; } = SalaryStatus.Pending;

    /// <summary>تاريخ الصرف</summary>
    public DateTime? PaidAt { get; set; }

    /// <summary>القيد المحاسبي المرتبط</summary>
    public Guid? JournalEntryId { get; set; }
    public JournalEntry? JournalEntry { get; set; }

    /// <summary>ملاحظات</summary>
    public string? Notes { get; set; }

    /// <summary>الشركة</summary>
    public Guid CompanyId { get; set; }
    public Company? Company { get; set; }

    // ========== تفاصيل الحضور (تُحسب تلقائياً) ==========

    /// <summary>إجمالي أيام الحضور</summary>
    public int AttendanceDays { get; set; }

    /// <summary>إجمالي أيام الغياب</summary>
    public int AbsentDays { get; set; }

    /// <summary>إجمالي دقائق التأخير</summary>
    public int TotalLateMinutes { get; set; }

    /// <summary>إجمالي دقائق الساعات الإضافية</summary>
    public int TotalOvertimeMinutes { get; set; }

    /// <summary>إجمالي دقائق المغادرة المبكرة</summary>
    public int TotalEarlyDepartureMinutes { get; set; }

    /// <summary>أيام الإجازات بدون راتب</summary>
    public int UnpaidLeaveDays { get; set; }

    /// <summary>أيام الإجازات المدفوعة</summary>
    public int PaidLeaveDays { get; set; }

    /// <summary>خصم التأخير</summary>
    public decimal LateDeduction { get; set; }

    /// <summary>خصم الغياب</summary>
    public decimal AbsentDeduction { get; set; }

    /// <summary>خصم المغادرة المبكرة</summary>
    public decimal EarlyDepartureDeduction { get; set; }

    /// <summary>خصم الإجازات بدون راتب</summary>
    public decimal UnpaidLeaveDeduction { get; set; }

    /// <summary>مكافأة الساعات الإضافية</summary>
    public decimal OvertimeBonus { get; set; }

    /// <summary>أيام العمل المتوقعة في الشهر</summary>
    public int ExpectedWorkDays { get; set; }

    /// <summary>خصومات يدوية (من صفحة الخصومات والمكافآت)</summary>
    public decimal ManualDeductions { get; set; } = 0;

    /// <summary>مكافآت يدوية (من صفحة الخصومات والمكافآت)</summary>
    public decimal ManualBonuses { get; set; } = 0;
}

/// <summary>
/// سياسة الرواتب - تحدد قواعد الخصم والمكافأة لكل شركة
/// </summary>
public class SalaryPolicy : BaseEntity<int>
{
    /// <summary>الشركة</summary>
    public Guid CompanyId { get; set; }
    public Company? Company { get; set; }

    /// <summary>اسم السياسة</summary>
    public string Name { get; set; } = "سياسة افتراضية";

    /// <summary>هل هي السياسة الافتراضية</summary>
    public bool IsDefault { get; set; } = true;

    // ========== قواعد خصم التأخير ==========

    /// <summary>خصم لكل دقيقة تأخير (بالعملة)</summary>
    public decimal DeductionPerLateMinute { get; set; } = 0;

    /// <summary>حد أقصى لخصم التأخير شهرياً (%)</summary>
    public decimal MaxLateDeductionPercent { get; set; } = 25;

    // ========== قواعد خصم الغياب ==========

    /// <summary>خصم يوم غياب = راتب يومي × هذا المعامل</summary>
    public decimal AbsentDayMultiplier { get; set; } = 1;

    // ========== قواعد المغادرة المبكرة ==========

    /// <summary>خصم لكل دقيقة مغادرة مبكرة</summary>
    public decimal DeductionPerEarlyDepartureMinute { get; set; } = 0;

    // ========== قواعد الساعات الإضافية ==========

    /// <summary>معامل أجر الساعة الإضافية (1.5 = ساعة ونصف)</summary>
    public decimal OvertimeHourlyMultiplier { get; set; } = 1.5m;

    /// <summary>حد أقصى ساعات إضافية شهرياً</summary>
    public int MaxOvertimeHoursPerMonth { get; set; } = 40;

    // ========== قواعد الإجازات بدون راتب ==========

    /// <summary>خصم يوم إجازة بدون راتب = راتب يومي × هذا المعامل</summary>
    public decimal UnpaidLeaveDayMultiplier { get; set; } = 1;

    /// <summary>أيام العمل المتوقعة شهرياً (لحساب الراتب اليومي)</summary>
    public int WorkDaysPerMonth { get; set; } = 26;

    /// <summary>مفعّل</summary>
    public bool IsActive { get; set; } = true;
}

// ==================== خصومات ومكافآت الموظفين - Employee Deductions & Bonuses ====================

/// <summary>
/// نوع التعديل اليدوي على الراتب
/// </summary>
public enum AdjustmentType
{
    /// <summary>خصم</summary>
    Deduction = 0,

    /// <summary>مكافأة</summary>
    Bonus = 1,

    /// <summary>بدل</summary>
    Allowance = 2
}

/// <summary>
/// خصم أو مكافأة يدوية للموظف
/// تُضاف يدوياً وتُحتسب تلقائياً عند إنشاء مسيّر الرواتب
/// </summary>
public class EmployeeDeductionBonus : BaseEntity<long>
{
    /// <summary>الموظف المستهدف</summary>
    public Guid UserId { get; set; }
    public User? User { get; set; }

    /// <summary>الشركة</summary>
    public Guid CompanyId { get; set; }
    public Company? Company { get; set; }

    /// <summary>نوع التعديل (خصم / مكافأة / بدل)</summary>
    public AdjustmentType Type { get; set; }

    /// <summary>الفئة (سلفة، غرامة، مكافأة أداء، بدل نقل...)</summary>
    public string Category { get; set; } = string.Empty;

    /// <summary>المبلغ (دائماً موجب)</summary>
    public decimal Amount { get; set; }

    /// <summary>الشهر الذي تُطبّق فيه (1-12)</summary>
    public int Month { get; set; }

    /// <summary>السنة التي تُطبّق فيها</summary>
    public int Year { get; set; }

    /// <summary>وصف/سبب التعديل</summary>
    public string Description { get; set; } = string.Empty;

    /// <summary>ملاحظات إضافية</summary>
    public string? Notes { get; set; }

    /// <summary>هل تم تطبيقها على الراتب</summary>
    public bool IsApplied { get; set; } = false;

    /// <summary>معرّف سجل الراتب الذي طُبّقت عليه</summary>
    public long? AppliedToSalaryId { get; set; }
    public EmployeeSalary? AppliedToSalary { get; set; }

    /// <summary>المستخدم الذي أنشأ التعديل</summary>
    public Guid CreatedById { get; set; }
    public User? CreatedBy { get; set; }

    /// <summary>هل هو تعديل متكرر شهرياً</summary>
    public bool IsRecurring { get; set; } = false;

    /// <summary>مفعّل</summary>
    public bool IsActive { get; set; } = true;
}

/// <summary>
/// تحصيل الفني - Technician Collection
/// المبالغ التي يجمعها الفني من المواطنين
/// </summary>
public class TechnicianCollection : BaseEntity<long>
{
    /// <summary>الفني الذي حصّل المبلغ</summary>
    public Guid TechnicianId { get; set; }
    public User? Technician { get; set; }

    /// <summary>المواطن (اختياري)</summary>
    public Guid? CitizenId { get; set; }
    public Citizen? Citizen { get; set; }

    /// <summary>طلب الخدمة (اختياري)</summary>
    public Guid? ServiceRequestId { get; set; }
    public ServiceRequest? ServiceRequest { get; set; }

    /// <summary>المبلغ المحصّل</summary>
    public decimal Amount { get; set; }

    /// <summary>تاريخ التحصيل</summary>
    public DateTime CollectionDate { get; set; } = DateTime.UtcNow;

    /// <summary>هل تم تسليم المبلغ للصندوق</summary>
    public bool IsDelivered { get; set; } = false;

    /// <summary>تاريخ التسليم</summary>
    public DateTime? DeliveredAt { get; set; }

    /// <summary>الموظف الذي استلم المبلغ</summary>
    public Guid? DeliveredToUserId { get; set; }
    public User? DeliveredToUser { get; set; }

    /// <summary>القيد المحاسبي المرتبط</summary>
    public Guid? JournalEntryId { get; set; }
    public JournalEntry? JournalEntry { get; set; }

    /// <summary>الصندوق الذي أُودع فيه المبلغ</summary>
    public Guid? CashBoxId { get; set; }
    public CashBox? CashBox { get; set; }

    /// <summary>ملاحظات</summary>
    public string? Notes { get; set; }

    /// <summary>وصف التحصيل</summary>
    public string? Description { get; set; }

    /// <summary>طريقة الدفع</summary>
    public PaymentMethod PaymentMethod { get; set; } = PaymentMethod.CashOnDelivery;

    /// <summary>رقم الإيصال</summary>
    public string? ReceiptNumber { get; set; }

    /// <summary>المستلم - اسم الشخص الذي استلم المبلغ</summary>
    public string? ReceivedBy { get; set; }

    /// <summary>الشركة</summary>
    public Guid CompanyId { get; set; }
    public Company? Company { get; set; }
}

/// <summary>
/// المصروف - Expense
/// مصروفات الشركة العامة والتشغيلية
/// </summary>
public class Expense : BaseEntity<long>
{
    /// <summary>الحساب المحاسبي (من شجرة الحسابات - مصروفات)</summary>
    public Guid AccountId { get; set; }
    public Account? Account { get; set; }

    /// <summary>المبلغ</summary>
    public decimal Amount { get; set; }

    /// <summary>الوصف</summary>
    public string Description { get; set; } = string.Empty;

    /// <summary>تاريخ المصروف</summary>
    public DateTime ExpenseDate { get; set; } = DateTime.UtcNow;

    /// <summary>الفئة</summary>
    public string? Category { get; set; }

    /// <summary>القيد المحاسبي المرتبط</summary>
    public Guid? JournalEntryId { get; set; }
    public JournalEntry? JournalEntry { get; set; }

    /// <summary>الصندوق الذي دُفع منه</summary>
    public Guid? PaidFromCashBoxId { get; set; }
    public CashBox? PaidFromCashBox { get; set; }

    /// <summary>المستخدم الذي سجّل المصروف</summary>
    public Guid CreatedById { get; set; }
    public User? CreatedBy { get; set; }

    /// <summary>مرفق/إيصال</summary>
    public string? AttachmentUrl { get; set; }

    /// <summary>ملاحظات</summary>
    public string? Notes { get; set; }

    /// <summary>الشركة</summary>
    public Guid CompanyId { get; set; }
    public Company? Company { get; set; }
}

// ==================== معاملات الفنيين المالية - Technician Transactions ====================

/// <summary>
/// نوع معاملة الفني
/// </summary>
public enum TechnicianTransactionType
{
    /// <summary>أجور - مبلغ مترتب على الفني (خصم)</summary>
    Charge = 0,

    /// <summary>تسديد - الفني يدفع من المبلغ المترتب عليه</summary>
    Payment = 1,

    /// <summary>خصم/تنزيل</summary>
    Discount = 2,

    /// <summary>تعديل يدوي من المدير</summary>
    Adjustment = 3
}

/// <summary>
/// فئة معاملة الفني
/// </summary>
public enum TechnicianTransactionCategory
{
    /// <summary>صيانة</summary>
    Maintenance = 0,

    /// <summary>تركيب</summary>
    Installation = 1,

    /// <summary>تحصيل</summary>
    Collection = 2,

    /// <summary>تسديد نقدي</summary>
    CashPayment = 3,

    /// <summary>شراء اشتراك</summary>
    Subscription = 4,

    /// <summary>أخرى</summary>
    Other = 99
}

/// <summary>
/// المعاملة المالية للفني
/// كل مهمة صيانة مكتملة تُنشئ معاملة هنا على الفني المعيّن
/// مشابه لنظام AgentTransaction
/// </summary>
public class TechnicianTransaction : BaseEntity<long>
{
    /// <summary>معرف الفني (User)</summary>
    public Guid TechnicianId { get; set; }

    /// <summary>نوع المعاملة (أجور / تسديد / خصم / تعديل)</summary>
    public TechnicianTransactionType Type { get; set; }

    /// <summary>فئة المعاملة (صيانة / تركيب / تحصيل...)</summary>
    public TechnicianTransactionCategory Category { get; set; }

    /// <summary>المبلغ (دائماً موجب)</summary>
    public decimal Amount { get; set; }

    /// <summary>الرصيد بعد المعاملة</summary>
    public decimal BalanceAfter { get; set; }

    /// <summary>وصف المعاملة</summary>
    public string Description { get; set; } = string.Empty;

    /// <summary>رقم المرجع (رقم طلب الخدمة)</summary>
    public string? ReferenceNumber { get; set; }

    /// <summary>معرف طلب الخدمة المرتبط</summary>
    public Guid? ServiceRequestId { get; set; }

    /// <summary>من أنشأ المعاملة</summary>
    public Guid? CreatedById { get; set; }

    /// <summary>ملاحظات إضافية</summary>
    public string? Notes { get; set; }

    /// <summary>المستلم</summary>
    public string? ReceivedBy { get; set; }

    /// <summary>الشركة</summary>
    public Guid CompanyId { get; set; }

    /// <summary>القيد المحاسبي المرتبط</summary>
    public Guid? JournalEntryId { get; set; }

    // ============ Navigation Properties ============

    /// <summary>الفني</summary>
    public virtual User? Technician { get; set; }

    /// <summary>طلب الخدمة</summary>
    public virtual ServiceRequest? ServiceRequest { get; set; }

    /// <summary>الشركة</summary>
    public virtual Company? Company { get; set; }
}

// ==================== المصاريف الثابتة الشهرية - Fixed Monthly Expenses ====================

/// <summary>
/// فئة المصروف الثابت
/// </summary>
public enum FixedExpenseCategory
{
    /// <summary>إيجار مكتب</summary>
    OfficeRent = 0,
    /// <summary>تكلفة مولد كهرباء</summary>
    GeneratorCost = 1,
    /// <summary>إنترنت</summary>
    Internet = 2,
    /// <summary>كهرباء</summary>
    Electricity = 3,
    /// <summary>ماء</summary>
    Water = 4,
    /// <summary>أخرى</summary>
    Other = 99
}

/// <summary>
/// المصاريف الثابتة الشهرية (إيجارات، مولد، خدمات)
/// يتم تسجيلها شهرياً كالتزامات مستحقة وعند الدفع تُخصم
/// </summary>
public class FixedExpense : BaseEntity<long>
{
    /// <summary>اسم المصروف (مثل: إيجار المكتب الرئيسي)</summary>
    public string Name { get; set; } = string.Empty;

    /// <summary>الفئة</summary>
    public FixedExpenseCategory Category { get; set; }

    /// <summary>المبلغ الشهري</summary>
    public decimal MonthlyAmount { get; set; }

    /// <summary>الوصف / ملاحظات</summary>
    public string? Description { get; set; }

    /// <summary>نشط (يُحسب ضمن الالتزامات الشهرية)</summary>
    public bool IsActive { get; set; } = true;

    /// <summary>الشركة</summary>
    public Guid CompanyId { get; set; }
    public Company? Company { get; set; }
}

/// <summary>
/// سجل دفع مصروف ثابت شهري
/// كل شهر يُنشأ سجل لكل مصروف ثابت (مستحق أو مدفوع)
/// </summary>
public class FixedExpensePayment : BaseEntity<long>
{
    /// <summary>المصروف الثابت</summary>
    public long FixedExpenseId { get; set; }
    public FixedExpense? FixedExpense { get; set; }

    /// <summary>الشهر</summary>
    public int Month { get; set; }

    /// <summary>السنة</summary>
    public int Year { get; set; }

    /// <summary>المبلغ المستحق</summary>
    public decimal Amount { get; set; }

    /// <summary>هل تم الدفع</summary>
    public bool IsPaid { get; set; } = false;

    /// <summary>تاريخ الدفع</summary>
    public DateTime? PaidAt { get; set; }

    /// <summary>القيد المحاسبي المرتبط بالدفع</summary>
    public Guid? JournalEntryId { get; set; }
    public JournalEntry? JournalEntry { get; set; }

    /// <summary>ملاحظات</summary>
    public string? Notes { get; set; }

    /// <summary>الشركة</summary>
    public Guid CompanyId { get; set; }
    public Company? Company { get; set; }
}
