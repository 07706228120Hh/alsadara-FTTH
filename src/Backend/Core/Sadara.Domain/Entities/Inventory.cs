using Sadara.Domain.Enums;

namespace Sadara.Domain.Entities;

// ==================== نظام المخازن والمواد - Inventory Management System ====================

/// <summary>
/// المستودع - يمثل موقع تخزين فعلي
/// </summary>
public class Warehouse : BaseEntity<Guid>
{
    /// <summary>اسم المستودع</summary>
    public string Name { get; set; } = string.Empty;

    /// <summary>رمز المستودع (WH-001)</summary>
    public string? Code { get; set; }

    /// <summary>العنوان</summary>
    public string? Address { get; set; }

    /// <summary>وصف المستودع</summary>
    public string? Description { get; set; }

    /// <summary>نشط أم لا</summary>
    public bool IsActive { get; set; } = true;

    /// <summary>المستودع الافتراضي</summary>
    public bool IsDefault { get; set; } = false;

    /// <summary>مسؤول المستودع</summary>
    public Guid? ManagerUserId { get; set; }
    public User? ManagerUser { get; set; }

    /// <summary>الشركة</summary>
    public Guid CompanyId { get; set; }
    public Company? Company { get; set; }

    /// <summary>أرصدة المخزون في هذا المستودع</summary>
    public List<WarehouseStock> Stocks { get; set; } = new();
}

/// <summary>
/// تصنيف المواد - هرمي (كابلات، سبليترات، ONT، إلخ)
/// </summary>
public class InventoryCategory : BaseEntity<int>
{
    /// <summary>اسم التصنيف بالعربية</summary>
    public string Name { get; set; } = string.Empty;

    /// <summary>اسم التصنيف بالإنجليزية</summary>
    public string? NameEn { get; set; }

    /// <summary>التصنيف الأب (للتسلسل الهرمي)</summary>
    public int? ParentCategoryId { get; set; }
    public InventoryCategory? ParentCategory { get; set; }
    public List<InventoryCategory> SubCategories { get; set; } = new();

    /// <summary>ترتيب العرض</summary>
    public int SortOrder { get; set; } = 0;

    /// <summary>نشط أم لا</summary>
    public bool IsActive { get; set; } = true;

    /// <summary>الشركة</summary>
    public Guid CompanyId { get; set; }
    public Company? Company { get; set; }
}

/// <summary>
/// المادة المخزنية - كابل فايبر، سبليتر، ONT، راوتر، موصل، أداة، إلخ
/// </summary>
public class InventoryItem : BaseEntity<Guid>
{
    /// <summary>اسم المادة بالعربية</summary>
    public string Name { get; set; } = string.Empty;

    /// <summary>اسم المادة بالإنجليزية</summary>
    public string? NameEn { get; set; }

    /// <summary>رمز المادة (SKU)</summary>
    public string SKU { get; set; } = string.Empty;

    /// <summary>الباركود</summary>
    public string? Barcode { get; set; }

    /// <summary>وصف المادة</summary>
    public string? Description { get; set; }

    /// <summary>التصنيف</summary>
    public int? CategoryId { get; set; }
    public InventoryCategory? Category { get; set; }

    /// <summary>وحدة القياس</summary>
    public InventoryUnitType Unit { get; set; } = InventoryUnitType.Piece;

    /// <summary>سعر التكلفة</summary>
    public decimal CostPrice { get; set; }

    /// <summary>سعر البيع</summary>
    public decimal? SellingPrice { get; set; }

    /// <summary>سعر الجملة</summary>
    public decimal? WholesalePrice { get; set; }

    /// <summary>حد أدنى للتنبيه</summary>
    public int MinStockLevel { get; set; } = 0;

    /// <summary>حد أقصى</summary>
    public int MaxStockLevel { get; set; } = 0;

    /// <summary>صورة المادة</summary>
    public string? ImageUrl { get; set; }

    /// <summary>نشط أم لا</summary>
    public bool IsActive { get; set; } = true;

    /// <summary>الشركة</summary>
    public Guid CompanyId { get; set; }
    public Company? Company { get; set; }

    /// <summary>أرصدة المخزون</summary>
    public List<WarehouseStock> Stocks { get; set; } = new();

    /// <summary>حركات المخزون</summary>
    public List<StockMovement> Movements { get; set; } = new();
}

// ==================== عملاء المخازن ====================

/// <summary>
/// عميل المخازن - للمبيعات النقدية والآجلة
/// </summary>
public class InventoryCustomer : BaseEntity<Guid>
{
    /// <summary>كود العميل (CU-0001)</summary>
    public string CustomerCode { get; set; } = string.Empty;

    /// <summary>الاسم الكامل</summary>
    public string FullName { get; set; } = string.Empty;

    /// <summary>رقم الهاتف</summary>
    public string? Phone { get; set; }

    /// <summary>رقم هاتف ثاني</summary>
    public string? Phone2 { get; set; }

    /// <summary>البريد الإلكتروني</summary>
    public string? Email { get; set; }

    /// <summary>المدينة</summary>
    public string? City { get; set; }

    /// <summary>المنطقة</summary>
    public string? Area { get; set; }

    /// <summary>العنوان</summary>
    public string? Address { get; set; }

    /// <summary>نوع العميل (نقدي / آجل / VIP)</summary>
    public InventoryCustomerType CustomerType { get; set; } = InventoryCustomerType.Cash;

    /// <summary>سقف الائتمان (للآجل)</summary>
    public decimal CreditLimit { get; set; } = 0;

    /// <summary>إجمالي المبيعات</summary>
    public decimal TotalSales { get; set; } = 0;

    /// <summary>إجمالي المدفوعات</summary>
    public decimal TotalPayments { get; set; } = 0;

    /// <summary>الرصيد (موجب = مدين لنا، سالب = له رصيد)</summary>
    public decimal Balance { get; set; } = 0;

    /// <summary>الرقم الضريبي</summary>
    public string? TaxNumber { get; set; }

    /// <summary>ملاحظات</summary>
    public string? Notes { get; set; }

    /// <summary>نشط أم لا</summary>
    public bool IsActive { get; set; } = true;

    /// <summary>الشركة</summary>
    public Guid CompanyId { get; set; }
    public Company? Company { get; set; }

    /// <summary>حساب العميل في شجرة الحسابات</summary>
    public Guid? AccountId { get; set; }
    public Account? Account { get; set; }

    /// <summary>الفواتير</summary>
    public List<Invoice> Invoices { get; set; } = new();
}

// ==================== الموردين (مطوّر) ====================

/// <summary>
/// المورد - مزود المواد
/// </summary>
public class Supplier : BaseEntity<Guid>
{
    /// <summary>اسم المورد</summary>
    public string Name { get; set; } = string.Empty;

    /// <summary>الشخص المسؤول</summary>
    public string? ContactPerson { get; set; }

    /// <summary>رقم الهاتف</summary>
    public string? Phone { get; set; }

    /// <summary>البريد الإلكتروني</summary>
    public string? Email { get; set; }

    /// <summary>العنوان</summary>
    public string? Address { get; set; }

    /// <summary>الرقم الضريبي</summary>
    public string? TaxNumber { get; set; }

    /// <summary>ملاحظات</summary>
    public string? Notes { get; set; }

    /// <summary>نشط أم لا</summary>
    public bool IsActive { get; set; } = true;

    /// <summary>نوع المورد (نقدي / آجل)</summary>
    public SupplierType SupplierType { get; set; } = SupplierType.Cash;

    /// <summary>سقف الائتمان</summary>
    public decimal CreditLimit { get; set; } = 0;

    /// <summary>إجمالي المشتريات</summary>
    public decimal TotalPurchases { get; set; } = 0;

    /// <summary>إجمالي المدفوعات</summary>
    public decimal TotalPayments { get; set; } = 0;

    /// <summary>الرصيد (موجب = ندين له، سالب = له رصيد عندنا)</summary>
    public decimal Balance { get; set; } = 0;

    /// <summary>حساب المورد في شجرة الحسابات</summary>
    public Guid? AccountId { get; set; }
    public Account? Account { get; set; }

    /// <summary>الشركة</summary>
    public Guid CompanyId { get; set; }
    public Company? Company { get; set; }

    /// <summary>أوامر الشراء</summary>
    public List<PurchaseOrder> PurchaseOrders { get; set; } = new();

    /// <summary>الفواتير</summary>
    public List<Invoice> Invoices { get; set; } = new();
}

/// <summary>
/// أمر الشراء - طلب شراء مواد من مورد (وارد)
/// </summary>
public class PurchaseOrder : BaseEntity<Guid>
{
    /// <summary>رقم الأمر (PO-2026-0001)</summary>
    public string OrderNumber { get; set; } = string.Empty;

    /// <summary>المورد</summary>
    public Guid SupplierId { get; set; }
    public Supplier? Supplier { get; set; }

    /// <summary>المستودع المستلم</summary>
    public Guid WarehouseId { get; set; }
    public Warehouse? Warehouse { get; set; }

    /// <summary>تاريخ الأمر</summary>
    public DateTime OrderDate { get; set; } = DateTime.UtcNow;

    /// <summary>تاريخ التسليم المتوقع</summary>
    public DateTime? ExpectedDeliveryDate { get; set; }

    /// <summary>تاريخ الاستلام الفعلي</summary>
    public DateTime? ReceivedDate { get; set; }

    /// <summary>حالة أمر الشراء</summary>
    public PurchaseOrderStatus Status { get; set; } = PurchaseOrderStatus.Draft;

    /// <summary>المبلغ الإجمالي</summary>
    public decimal TotalAmount { get; set; }

    /// <summary>مبلغ الخصم</summary>
    public decimal? DiscountAmount { get; set; }

    /// <summary>مبلغ الضريبة</summary>
    public decimal? TaxAmount { get; set; }

    /// <summary>المبلغ الصافي</summary>
    public decimal NetAmount { get; set; }

    /// <summary>ملاحظات</summary>
    public string? Notes { get; set; }

    /// <summary>رابط المرفق</summary>
    public string? AttachmentUrl { get; set; }

    /// <summary>المستخدم الذي أنشأ الأمر</summary>
    public Guid CreatedById { get; set; }
    public User? CreatedBy { get; set; }

    /// <summary>المستخدم الذي اعتمد الأمر</summary>
    public Guid? ApprovedById { get; set; }
    public User? ApprovedBy { get; set; }

    /// <summary>قيد المحاسبة المرتبط</summary>
    public Guid? JournalEntryId { get; set; }
    public JournalEntry? JournalEntry { get; set; }

    /// <summary>الشركة</summary>
    public Guid CompanyId { get; set; }
    public Company? Company { get; set; }

    /// <summary>بنود الشراء</summary>
    public List<PurchaseOrderItem> Items { get; set; } = new();
}

/// <summary>
/// بند شراء - سطر في أمر الشراء
/// </summary>
public class PurchaseOrderItem : BaseEntity<long>
{
    /// <summary>أمر الشراء</summary>
    public Guid PurchaseOrderId { get; set; }
    public PurchaseOrder? PurchaseOrder { get; set; }

    /// <summary>المادة</summary>
    public Guid InventoryItemId { get; set; }
    public InventoryItem? InventoryItem { get; set; }

    /// <summary>الكمية المطلوبة</summary>
    public int Quantity { get; set; }

    /// <summary>الكمية المستلمة</summary>
    public int ReceivedQuantity { get; set; } = 0;

    /// <summary>سعر الوحدة</summary>
    public decimal UnitPrice { get; set; }

    /// <summary>المبلغ الإجمالي</summary>
    public decimal TotalPrice { get; set; }

    /// <summary>ملاحظات</summary>
    public string? Notes { get; set; }
}

/// <summary>
/// عملية بيع مواد (صادر)
/// </summary>
public class SalesOrder : BaseEntity<Guid>
{
    /// <summary>رقم العملية (SO-2026-0001)</summary>
    public string OrderNumber { get; set; } = string.Empty;

    /// <summary>اسم العميل (نص حر)</summary>
    public string? CustomerName { get; set; }

    /// <summary>هاتف العميل</summary>
    public string? CustomerPhone { get; set; }

    /// <summary>المستودع</summary>
    public Guid WarehouseId { get; set; }
    public Warehouse? Warehouse { get; set; }

    /// <summary>تاريخ العملية</summary>
    public DateTime OrderDate { get; set; } = DateTime.UtcNow;

    /// <summary>حالة البيع</summary>
    public SalesOrderStatus Status { get; set; } = SalesOrderStatus.Draft;

    /// <summary>المبلغ الإجمالي</summary>
    public decimal TotalAmount { get; set; }

    /// <summary>مبلغ الخصم</summary>
    public decimal? DiscountAmount { get; set; }

    /// <summary>مبلغ الضريبة</summary>
    public decimal? TaxAmount { get; set; }

    /// <summary>المبلغ الصافي</summary>
    public decimal NetAmount { get; set; }

    /// <summary>طريقة الدفع</summary>
    public PaymentMethod PaymentMethod { get; set; } = PaymentMethod.CashOnDelivery;

    /// <summary>ملاحظات</summary>
    public string? Notes { get; set; }

    /// <summary>المستخدم الذي أنشأ العملية</summary>
    public Guid CreatedById { get; set; }
    public User? CreatedBy { get; set; }

    /// <summary>قيد المحاسبة المرتبط</summary>
    public Guid? JournalEntryId { get; set; }
    public JournalEntry? JournalEntry { get; set; }

    /// <summary>الشركة</summary>
    public Guid CompanyId { get; set; }
    public Company? Company { get; set; }

    /// <summary>بنود البيع</summary>
    public List<SalesOrderItem> Items { get; set; } = new();
}

/// <summary>
/// بند بيع - سطر في عملية البيع
/// </summary>
public class SalesOrderItem : BaseEntity<long>
{
    /// <summary>عملية البيع</summary>
    public Guid SalesOrderId { get; set; }
    public SalesOrder? SalesOrder { get; set; }

    /// <summary>المادة</summary>
    public Guid InventoryItemId { get; set; }
    public InventoryItem? InventoryItem { get; set; }

    /// <summary>الكمية</summary>
    public int Quantity { get; set; }

    /// <summary>سعر الوحدة</summary>
    public decimal UnitPrice { get; set; }

    /// <summary>المبلغ الإجمالي</summary>
    public decimal TotalPrice { get; set; }
}

/// <summary>
/// صرف مواد للفنيين - للتنصيب أو الصيانة
/// </summary>
public class TechnicianDispensing : BaseEntity<Guid>
{
    /// <summary>رقم السند (TD-2026-0001)</summary>
    public string VoucherNumber { get; set; } = string.Empty;

    /// <summary>الفني المستلم</summary>
    public Guid TechnicianId { get; set; }
    public User? Technician { get; set; }

    /// <summary>المستودع</summary>
    public Guid WarehouseId { get; set; }
    public Warehouse? Warehouse { get; set; }

    /// <summary>ربط بطلب الخدمة (اختياري)</summary>
    public Guid? ServiceRequestId { get; set; }
    public ServiceRequest? ServiceRequest { get; set; }

    /// <summary>تاريخ الصرف</summary>
    public DateTime DispensingDate { get; set; } = DateTime.UtcNow;

    /// <summary>حالة الصرف</summary>
    public DispensingStatus Status { get; set; } = DispensingStatus.Pending;

    /// <summary>نوع العملية (صرف أو إرجاع)</summary>
    public DispensingType Type { get; set; } = DispensingType.Dispensing;

    /// <summary>ملاحظات</summary>
    public string? Notes { get; set; }

    /// <summary>المستخدم الذي أنشأ العملية</summary>
    public Guid CreatedById { get; set; }
    public User? CreatedBy { get; set; }

    /// <summary>المستخدم الذي وافق</summary>
    public Guid? ApprovedById { get; set; }
    public User? ApprovedBy { get; set; }

    /// <summary>الشركة</summary>
    public Guid CompanyId { get; set; }
    public Company? Company { get; set; }

    /// <summary>بنود الصرف</summary>
    public List<TechnicianDispensingItem> Items { get; set; } = new();
}

/// <summary>
/// بند صرف فني - سطر في عملية الصرف
/// </summary>
public class TechnicianDispensingItem : BaseEntity<long>
{
    /// <summary>عملية الصرف</summary>
    public Guid TechnicianDispensingId { get; set; }
    public TechnicianDispensing? TechnicianDispensing { get; set; }

    /// <summary>المادة</summary>
    public Guid InventoryItemId { get; set; }
    public InventoryItem? InventoryItem { get; set; }

    /// <summary>الكمية المصروفة</summary>
    public int Quantity { get; set; }

    /// <summary>الكمية المرجعة</summary>
    public int ReturnedQuantity { get; set; } = 0;

    /// <summary>ملاحظات</summary>
    public string? Notes { get; set; }
}

/// <summary>
/// حركة مخزنية - سجل تدقيق غير قابل للتعديل لكل حركة وارد/صادر
/// </summary>
public class StockMovement : BaseEntity<long>
{
    /// <summary>المادة</summary>
    public Guid InventoryItemId { get; set; }
    public InventoryItem? InventoryItem { get; set; }

    /// <summary>المستودع</summary>
    public Guid WarehouseId { get; set; }
    public Warehouse? Warehouse { get; set; }

    /// <summary>نوع الحركة</summary>
    public StockMovementType MovementType { get; set; }

    /// <summary>الكمية (دائماً موجبة)</summary>
    public int Quantity { get; set; }

    /// <summary>الرصيد قبل الحركة</summary>
    public int StockBefore { get; set; }

    /// <summary>الرصيد بعد الحركة</summary>
    public int StockAfter { get; set; }

    /// <summary>تكلفة الوحدة وقت الحركة</summary>
    public decimal? UnitCost { get; set; }

    /// <summary>نوع المستند المرجعي (PurchaseOrder, SalesOrder, TechnicianDispensing)</summary>
    public string? ReferenceType { get; set; }

    /// <summary>معرف المستند المرجعي</summary>
    public string? ReferenceId { get; set; }

    /// <summary>رقم المستند المرجعي (PO-2026-0001)</summary>
    public string? ReferenceNumber { get; set; }

    /// <summary>وصف الحركة</summary>
    public string? Description { get; set; }

    /// <summary>المستخدم الذي نفذ الحركة</summary>
    public Guid CreatedById { get; set; }
    public User? CreatedBy { get; set; }

    /// <summary>الشركة</summary>
    public Guid CompanyId { get; set; }
    public Company? Company { get; set; }
}

/// <summary>
/// رصيد المخزون الحالي - جدول denormalized يحتفظ بالرصيد الحالي لكل مادة في كل مستودع
/// يُحدَّث تلقائياً مع كل StockMovement
/// </summary>
public class WarehouseStock : BaseEntity<long>
{
    /// <summary>المستودع</summary>
    public Guid WarehouseId { get; set; }
    public Warehouse? Warehouse { get; set; }

    /// <summary>المادة</summary>
    public Guid InventoryItemId { get; set; }
    public InventoryItem? InventoryItem { get; set; }

    /// <summary>الكمية الحالية</summary>
    public int CurrentQuantity { get; set; } = 0;

    /// <summary>الكمية المحجوزة (لطلبات قيد التنفيذ)</summary>
    public int ReservedQuantity { get; set; } = 0;

    /// <summary>متوسط التكلفة المرجح</summary>
    public decimal AverageCost { get; set; } = 0;

    /// <summary>تاريخ آخر وارد</summary>
    public DateTime? LastStockInDate { get; set; }

    /// <summary>تاريخ آخر صادر</summary>
    public DateTime? LastStockOutDate { get; set; }

    /// <summary>الشركة</summary>
    public Guid CompanyId { get; set; }
    public Company? Company { get; set; }
}

// ==================== الفواتير ====================

/// <summary>
/// فاتورة بيع أو شراء
/// </summary>
public class Invoice : BaseEntity<Guid>
{
    /// <summary>رقم الفاتورة (INV-2026-0001 بيع / PINV-2026-0001 شراء)</summary>
    public string InvoiceNumber { get; set; } = string.Empty;

    /// <summary>نوع الفاتورة (بيع / شراء)</summary>
    public InvoiceType InvoiceType { get; set; }

    /// <summary>نوع الدفع (نقد / آجل / جزئي)</summary>
    public InvoicePaymentType PaymentType { get; set; } = InvoicePaymentType.Cash;

    /// <summary>العميل (لفواتير البيع)</summary>
    public Guid? CustomerId { get; set; }
    public InventoryCustomer? Customer { get; set; }

    /// <summary>المورد (لفواتير الشراء)</summary>
    public Guid? SupplierId { get; set; }
    public Supplier? Supplier { get; set; }

    /// <summary>اسم العميل/المورد للعرض</summary>
    public string? EntityName { get; set; }

    /// <summary>المستودع</summary>
    public Guid WarehouseId { get; set; }
    public Warehouse? Warehouse { get; set; }

    /// <summary>تاريخ الفاتورة</summary>
    public DateTime InvoiceDate { get; set; } = DateTime.UtcNow;

    /// <summary>تاريخ الاستحقاق (للآجل)</summary>
    public DateTime? DueDate { get; set; }

    /// <summary>المجموع الفرعي (قبل الخصم والضريبة)</summary>
    public decimal SubTotal { get; set; }

    /// <summary>نوع الخصم العام (نسبة / مبلغ ثابت)</summary>
    public DiscountType DiscountType { get; set; } = DiscountType.Percentage;

    /// <summary>قيمة الخصم المدخلة</summary>
    public decimal DiscountValue { get; set; } = 0;

    /// <summary>مبلغ الخصم الفعلي</summary>
    public decimal DiscountAmount { get; set; } = 0;

    /// <summary>نسبة الضريبة</summary>
    public decimal TaxRate { get; set; } = 0;

    /// <summary>مبلغ الضريبة</summary>
    public decimal TaxAmount { get; set; } = 0;

    /// <summary>المبلغ الصافي النهائي</summary>
    public decimal NetAmount { get; set; }

    /// <summary>المبلغ المدفوع</summary>
    public decimal PaidAmount { get; set; } = 0;

    /// <summary>المبلغ المتبقي</summary>
    public decimal RemainingAmount { get; set; } = 0;

    /// <summary>حالة الفاتورة</summary>
    public InvoiceStatus Status { get; set; } = InvoiceStatus.Draft;

    /// <summary>ملاحظات</summary>
    public string? Notes { get; set; }

    /// <summary>رابط المرفق</summary>
    public string? AttachmentUrl { get; set; }

    /// <summary>القيد المحاسبي</summary>
    public Guid? JournalEntryId { get; set; }
    public JournalEntry? JournalEntry { get; set; }

    /// <summary>الصندوق (للنقد)</summary>
    public Guid? CashBoxId { get; set; }
    public CashBox? CashBox { get; set; }

    /// <summary>المستخدم الذي أنشأ الفاتورة</summary>
    public Guid CreatedById { get; set; }
    public User? CreatedBy { get; set; }

    /// <summary>الشركة</summary>
    public Guid CompanyId { get; set; }
    public Company? Company { get; set; }

    /// <summary>بنود الفاتورة</summary>
    public List<InvoiceItem> Items { get; set; } = new();

    /// <summary>سندات الدفع المرتبطة</summary>
    public List<PaymentVoucher> PaymentVouchers { get; set; } = new();
}

/// <summary>
/// بند فاتورة
/// </summary>
public class InvoiceItem : BaseEntity<long>
{
    /// <summary>الفاتورة</summary>
    public Guid InvoiceId { get; set; }
    public Invoice? Invoice { get; set; }

    /// <summary>المادة</summary>
    public Guid InventoryItemId { get; set; }
    public InventoryItem? InventoryItem { get; set; }

    /// <summary>اسم المادة وقت الفاتورة (snapshot)</summary>
    public string ItemName { get; set; } = string.Empty;

    /// <summary>الكمية</summary>
    public int Quantity { get; set; }

    /// <summary>سعر الوحدة</summary>
    public decimal UnitPrice { get; set; }

    /// <summary>نسبة خصم البند</summary>
    public decimal DiscountPercent { get; set; } = 0;

    /// <summary>مبلغ خصم البند</summary>
    public decimal DiscountAmount { get; set; } = 0;

    /// <summary>مبلغ الضريبة للبند</summary>
    public decimal TaxAmount { get; set; } = 0;

    /// <summary>السعر الإجمالي النهائي للبند</summary>
    public decimal TotalPrice { get; set; }

    /// <summary>تكلفة الوحدة وقت البيع (لحساب الربح)</summary>
    public decimal CostAtSale { get; set; } = 0;

    /// <summary>ملاحظات</summary>
    public string? Notes { get; set; }
}

// ==================== سندات القبض والصرف ====================

/// <summary>
/// سند قبض (من عميل) أو سند صرف (لمورد)
/// </summary>
public class PaymentVoucher : BaseEntity<Guid>
{
    /// <summary>رقم السند (RV-2026-0001 قبض / PV-2026-0001 صرف)</summary>
    public string VoucherNumber { get; set; } = string.Empty;

    /// <summary>نوع السند (قبض / صرف)</summary>
    public VoucherType VoucherType { get; set; }

    /// <summary>نوع الكيان (عميل / مورد)</summary>
    public VoucherEntityType EntityType { get; set; }

    /// <summary>معرف العميل أو المورد</summary>
    public Guid EntityId { get; set; }

    /// <summary>اسم العميل/المورد للعرض</summary>
    public string EntityName { get; set; } = string.Empty;

    /// <summary>المبلغ</summary>
    public decimal Amount { get; set; }

    /// <summary>طريقة الدفع</summary>
    public PaymentMethod PaymentMethod { get; set; } = PaymentMethod.CashOnDelivery;

    /// <summary>الصندوق</summary>
    public Guid? CashBoxId { get; set; }
    public CashBox? CashBox { get; set; }

    /// <summary>تاريخ السند</summary>
    public DateTime VoucherDate { get; set; } = DateTime.UtcNow;

    /// <summary>ربط بفاتورة محددة (اختياري)</summary>
    public Guid? InvoiceId { get; set; }
    public Invoice? Invoice { get; set; }

    /// <summary>ملاحظات</summary>
    public string? Notes { get; set; }

    /// <summary>رابط المرفق</summary>
    public string? AttachmentUrl { get; set; }

    /// <summary>القيد المحاسبي</summary>
    public Guid? JournalEntryId { get; set; }
    public JournalEntry? JournalEntry { get; set; }

    /// <summary>المستخدم الذي أنشأ السند</summary>
    public Guid CreatedById { get; set; }
    public User? CreatedBy { get; set; }

    /// <summary>الشركة</summary>
    public Guid CompanyId { get; set; }
    public Company? Company { get; set; }
}

// ==================== المرتجعات ====================

/// <summary>
/// مرتجع مبيعات أو مشتريات
/// </summary>
public class ReturnOrder : BaseEntity<Guid>
{
    /// <summary>رقم المرتجع (SR-2026-0001 / PR-2026-0001)</summary>
    public string ReturnNumber { get; set; } = string.Empty;

    /// <summary>نوع المرتجع (مبيعات / مشتريات)</summary>
    public ReturnType ReturnType { get; set; }

    /// <summary>الفاتورة الأصلية</summary>
    public Guid OriginalInvoiceId { get; set; }
    public Invoice? OriginalInvoice { get; set; }

    /// <summary>العميل (لمرتجع البيع)</summary>
    public Guid? CustomerId { get; set; }
    public InventoryCustomer? Customer { get; set; }

    /// <summary>المورد (لمرتجع الشراء)</summary>
    public Guid? SupplierId { get; set; }
    public Supplier? Supplier { get; set; }

    /// <summary>المستودع</summary>
    public Guid WarehouseId { get; set; }
    public Warehouse? Warehouse { get; set; }

    /// <summary>المبلغ الإجمالي للمرتجع</summary>
    public decimal TotalAmount { get; set; }

    /// <summary>طريقة الاسترداد</summary>
    public RefundMethod RefundMethod { get; set; } = RefundMethod.DeductFromBalance;

    /// <summary>الصندوق (للإرجاع النقدي)</summary>
    public Guid? CashBoxId { get; set; }
    public CashBox? CashBox { get; set; }

    /// <summary>حالة المرتجع</summary>
    public ReturnStatus Status { get; set; } = ReturnStatus.Draft;

    /// <summary>تاريخ المرتجع</summary>
    public DateTime ReturnDate { get; set; } = DateTime.UtcNow;

    /// <summary>السبب العام</summary>
    public string? Reason { get; set; }

    /// <summary>ملاحظات</summary>
    public string? Notes { get; set; }

    /// <summary>القيد المحاسبي</summary>
    public Guid? JournalEntryId { get; set; }
    public JournalEntry? JournalEntry { get; set; }

    /// <summary>المستخدم الذي أنشأ المرتجع</summary>
    public Guid CreatedById { get; set; }
    public User? CreatedBy { get; set; }

    /// <summary>الشركة</summary>
    public Guid CompanyId { get; set; }
    public Company? Company { get; set; }

    /// <summary>بنود المرتجع</summary>
    public List<ReturnOrderItem> Items { get; set; } = new();
}

/// <summary>
/// بند مرتجع
/// </summary>
public class ReturnOrderItem : BaseEntity<long>
{
    /// <summary>المرتجع</summary>
    public Guid ReturnOrderId { get; set; }
    public ReturnOrder? ReturnOrder { get; set; }

    /// <summary>المادة</summary>
    public Guid InventoryItemId { get; set; }
    public InventoryItem? InventoryItem { get; set; }

    /// <summary>الكمية المرتجعة</summary>
    public int Quantity { get; set; }

    /// <summary>سعر الوحدة</summary>
    public decimal UnitPrice { get; set; }

    /// <summary>المبلغ الإجمالي</summary>
    public decimal TotalPrice { get; set; }

    /// <summary>سبب الإرجاع لهذا البند</summary>
    public string? Reason { get; set; }
}

// ==================== ربط حسابات المخزون ====================

/// <summary>
/// ربط الحسابات المحاسبية بنظام المخزون — يحدد أي حساب يُستخدم لكل نوع قيد
/// </summary>
public class InventoryAccountMapping : BaseEntity<int>
{
    /// <summary>الشركة</summary>
    public Guid CompanyId { get; set; }
    public Company? Company { get; set; }

    /// <summary>مفتاح الحساب (inventory, cogs, sales_revenue, accounts_receivable, accounts_payable, sales_returns, purchase_returns, tax_payable)</summary>
    public string AccountKey { get; set; } = string.Empty;

    /// <summary>الحساب المحاسبي المربوط</summary>
    public Guid AccountId { get; set; }
    public Account? Account { get; set; }
}
