namespace Sadara.Domain.Enums;

/// <summary>
/// أدوار المستخدمين في النظام
/// متوافقة مع نظام Flutter الموجود
/// </summary>
public enum UserRole
{
    /// <summary>مواطن/زبون - يستخدم تطبيق المواطن PWA</summary>
    Citizen = 0,
    
    /// <summary>تاجر/مزود خدمة - يملك متجر</summary>
    Merchant = 1,
    
    /// <summary>سائق توصيل</summary>
    Driver = 2,
    
    /// <summary>موظف شركة - صلاحيات محدودة</summary>
    Employee = 10,
    
    /// <summary>مشاهد - عرض فقط</summary>
    Viewer = 11,
    
    /// <summary>فني - صيانة وتركيب</summary>
    Technician = 12,
    
    /// <summary>ليدر فني - يدير الفنيين</summary>
    TechnicalLeader = 13,
    
    /// <summary>مشرف - صلاحيات إدارية جزئية</summary>
    Manager = 14,
    
    /// <summary>مدير شركة - صلاحيات كاملة على شركته</summary>
    CompanyAdmin = 20,
    
    /// <summary>مدير النظام - صلاحيات كاملة على كل الشركات</summary>
    SuperAdmin = 99
}

public enum OrderStatus
{
    Pending = 0,
    Confirmed = 1,
    Processing = 2,
    Shipped = 3,
    Delivered = 4,
    Cancelled = 5,
    Refunded = 6
}

public enum PaymentStatus
{
    Pending = 0,
    Processing = 1,
    Success = 2,
    Failed = 3,
    Refunded = 4,
    Cancelled = 5
}

public enum PaymentMethod
{
    CashOnDelivery = 0,
    ZainCash = 1,
    FastPay = 2,
    Wallet = 3,
    BankTransfer = 4
}

public enum CustomerType
{
    New = 0,
    Regular = 1,
    VIP = 2,
    Blacklisted = 3
}

public enum SubscriptionPlan
{
    Free = 0,
    Basic = 1,
    Pro = 2,
    Enterprise = 3
}

/// <summary>
/// حالة اشتراك الشركة
/// </summary>
public enum CompanySubscriptionStatus
{
    /// <summary>نشط - يعمل بشكل طبيعي</summary>
    Active = 0,
    
    /// <summary>تحذير - ينتهي خلال 30 يوم</summary>
    Warning = 1,
    
    /// <summary>حرج - ينتهي خلال 7 أيام</summary>
    Critical = 2,
    
    /// <summary>منتهي - انتهى الاشتراك</summary>
    Expired = 3,
    
    /// <summary>معلق - موقوف يدوياً</summary>
    Suspended = 4
}

/// <summary>
/// أنواع الإشعارات
/// </summary>
public enum NotificationType
{
    OrderUpdate = 0,
    Payment = 1,
    Promotion = 2,
    System = 3,
    
    /// <summary>طلب خدمة جديد</summary>
    ServiceRequest = 10,
    
    /// <summary>تحديث حالة طلب</summary>
    RequestStatusUpdate = 11,
    
    /// <summary>تم تعيين طلب لموظف</summary>
    RequestAssigned = 12,
    
    /// <summary>تعليق جديد على طلب</summary>
    RequestComment = 13,
    
    /// <summary>طلب وكيل جديد</summary>
    AgentRequest = 20,
    
    /// <summary>اكتمال مهمة</summary>
    TaskCompleted = 21
}

/// <summary>
/// حالات طلب الخدمة
/// </summary>
public enum ServiceRequestStatus
{
    /// <summary>جديد - بانتظار المراجعة</summary>
    Pending = 0,
    
    /// <summary>قيد المراجعة</summary>
    Reviewing = 1,
    
    /// <summary>موافق عليه</summary>
    Approved = 2,
    
    /// <summary>تم التعيين لموظف</summary>
    Assigned = 3,
    
    /// <summary>قيد التنفيذ</summary>
    InProgress = 4,
    
    /// <summary>مكتمل</summary>
    Completed = 5,
    
    /// <summary>ملغي</summary>
    Cancelled = 6,
    
    /// <summary>مرفوض</summary>
    Rejected = 7,
    
    /// <summary>معلق - بانتظار المواطن</summary>
    OnHold = 8
}

/// <summary>
/// أولوية الطلب
/// </summary>
public enum RequestPriority
{
    Low = 0,
    Normal = 1,
    High = 2,
    Urgent = 3
}

public enum Gender
{
    Male = 0,
    Female = 1,
    Other = 2
}

public enum DiscountType
{
    Percentage = 0,
    Fixed = 1
}

/// <summary>
/// نوع النظام الذي تنتمي إليه الصلاحية
/// </summary>
public enum SystemType
{
    /// <summary>متاح لجميع الأنظمة</summary>
    All = 0,
    
    /// <summary>النظام الأول (الحضور والانصراف)</summary>
    FirstSystem = 1,
    
    /// <summary>النظام الثاني (إدارة الشركة)</summary>
    SecondSystem = 2,
    
    /// <summary>نظام المواطن (يتطلب شركة مميزة)</summary>
    CitizenPortal = 3
}

/// <summary>
/// نوع مجموعة الصلاحيات
/// </summary>
public enum PermissionGroupType
{
    /// <summary>صلاحيات عامة</summary>
    General = 0,
    
    /// <summary>صلاحيات الموظفين</summary>
    Employees = 1,
    
    /// <summary>صلاحيات المالية</summary>
    Finance = 2,
    
    /// <summary>صلاحيات المخزون</summary>
    Inventory = 3,
    
    /// <summary>صلاحيات التقارير</summary>
    Reports = 4,
    
    /// <summary>صلاحيات الإعدادات</summary>
    Settings = 5,
    
    /// <summary>صلاحيات نظام المواطن</summary>
    CitizenPortal = 10,

    /// <summary>صلاحيات المحاسبة</summary>
    Accounting = 11
}

// ==================== Accounting System Enums (نظام المحاسبة) ====================

/// <summary>
/// نوع الحساب المحاسبي
/// </summary>
public enum AccountType
{
    /// <summary>أصول (مثل: النقدية، البنوك، المدينون)</summary>
    Assets = 1,

    /// <summary>خصوم/التزامات (مثل: الدائنون، قروض)</summary>
    Liabilities = 2,

    /// <summary>حقوق الملكية (رأس المال، أرباح محتجزة)</summary>
    Equity = 3,

    /// <summary>إيرادات (اشتراكات، تركيبات، خدمات)</summary>
    Revenue = 4,

    /// <summary>مصروفات (رواتب، إيجار، مواد)</summary>
    Expenses = 5
}

/// <summary>
/// حالة القيد المحاسبي
/// </summary>
public enum JournalEntryStatus
{
    /// <summary>مسودة - لم يُعتمد بعد</summary>
    Draft = 0,

    /// <summary>معتمد - تم ترحيله للحسابات</summary>
    Posted = 1,

    /// <summary>ملغي</summary>
    Voided = 2
}

/// <summary>
/// نوع المرجع للقيد المحاسبي
/// </summary>
public enum JournalReferenceType
{
    /// <summary>قيد يدوي</summary>
    Manual = 0,

    /// <summary>تحصيل فني</summary>
    TechnicianCollection = 1,

    /// <summary>راتب موظف</summary>
    Salary = 2,

    /// <summary>مصروف</summary>
    Expense = 3,

    /// <summary>إيداع صندوق</summary>
    CashDeposit = 4,

    /// <summary>سحب من صندوق</summary>
    CashWithdrawal = 5,

    /// <summary>معاملة وكيل</summary>
    AgentTransaction = 6,

    /// <summary>دفعة مواطن</summary>
    CitizenPayment = 7,

    /// <summary>طلب خدمة</summary>
    ServiceRequest = 8,

    /// <summary>تحويل بين صناديق</summary>
    CashTransfer = 9
}

/// <summary>
/// نوع الصندوق / القاصة
/// </summary>
public enum CashBoxType
{
    /// <summary>صندوق رئيسي</summary>
    Main = 0,

    /// <summary>قاصة فرعية</summary>
    PettyCash = 1,

    /// <summary>صندوق بنكي</summary>
    Bank = 2
}

/// <summary>
/// نوع حركة الصندوق
/// </summary>
public enum CashTransactionType
{
    /// <summary>إدخال/إيداع</summary>
    Deposit = 0,

    /// <summary>إخراج/سحب</summary>
    Withdrawal = 1,

    /// <summary>تحويل وارد من صندوق آخر</summary>
    TransferIn = 2,

    /// <summary>تحويل صادر لصندوق آخر</summary>
    TransferOut = 3
}

/// <summary>
/// حالة الراتب
/// </summary>
public enum SalaryStatus
{
    /// <summary>بانتظار الصرف</summary>
    Pending = 0,

    /// <summary>تم الصرف</summary>
    Paid = 1,

    /// <summary>صرف جزئي</summary>
    PartiallyPaid = 2,

    /// <summary>ملغي</summary>
    Cancelled = 3
}
