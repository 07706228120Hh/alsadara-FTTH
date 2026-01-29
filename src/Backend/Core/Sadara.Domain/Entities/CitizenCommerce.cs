using Sadara.Domain.Enums;

namespace Sadara.Domain.Entities;

/// <summary>
/// مدفوعات المواطن
/// </summary>
public class CitizenPayment : BaseEntity<Guid>
{
    /// <summary>رقم العملية</summary>
    public string TransactionNumber { get; set; } = string.Empty;
    
    /// <summary>المواطن</summary>
    public Guid CitizenId { get; set; }
    
    /// <summary>الشركة</summary>
    public Guid CompanyId { get; set; }
    
    /// <summary>الاشتراك (إن وجد)</summary>
    public Guid? CitizenSubscriptionId { get; set; }
    
    /// <summary>طلب الخدمة (إن وجد)</summary>
    public Guid? ServiceRequestId { get; set; }
    
    /// <summary>نوع الدفعة</summary>
    public CitizenPaymentType PaymentType { get; set; }
    
    /// <summary>المبلغ</summary>
    public decimal Amount { get; set; }
    
    /// <summary>طريقة الدفع</summary>
    public PaymentMethod Method { get; set; }
    
    /// <summary>حالة الدفع</summary>
    public PaymentStatus Status { get; set; } = PaymentStatus.Pending;
    
    /// <summary>معرف العملية الخارجي (ZainCash, etc)</summary>
    public string? ExternalTransactionId { get; set; }
    
    /// <summary>بيانات الاستجابة من البوابة</summary>
    public string? GatewayResponse { get; set; }
    
    /// <summary>تاريخ الدفع</summary>
    public DateTime? PaidAt { get; set; }
    
    /// <summary>ملاحظات</summary>
    public string? Notes { get; set; }
    
    /// <summary>من سجل الدفعة (للدفع اليدوي)</summary>
    public Guid? RecordedById { get; set; }
    
    // Navigation
    public virtual Citizen? Citizen { get; set; }
    public virtual Company? Company { get; set; }
    public virtual CitizenSubscription? Subscription { get; set; }
    public virtual ServiceRequest? ServiceRequest { get; set; }
    public virtual User? RecordedBy { get; set; }
}

/// <summary>
/// نوع الدفعة
/// </summary>
public enum CitizenPaymentType
{
    /// <summary>رسوم تركيب</summary>
    Installation = 0,
    
    /// <summary>اشتراك شهري</summary>
    MonthlySubscription = 1,
    
    /// <summary>رسوم صيانة</summary>
    Maintenance = 2,
    
    /// <summary>شراء منتج</summary>
    ProductPurchase = 3,
    
    /// <summary>رسوم ترقية</summary>
    Upgrade = 4,
    
    /// <summary>غرامة تأخير</summary>
    LateFee = 5,
    
    /// <summary>أخرى</summary>
    Other = 99
}

/// <summary>
/// منتج في متجر الشركة
/// </summary>
public class StoreProduct : BaseEntity<Guid>
{
    /// <summary>الشركة</summary>
    public Guid CompanyId { get; set; }
    
    /// <summary>التصنيف</summary>
    public Guid? CategoryId { get; set; }
    
    /// <summary>اسم المنتج</summary>
    public string Name { get; set; } = string.Empty;
    
    /// <summary>اسم المنتج بالعربي</summary>
    public string NameAr { get; set; } = string.Empty;
    
    /// <summary>الوصف</summary>
    public string? Description { get; set; }
    
    /// <summary>رمز المنتج SKU</summary>
    public string? SKU { get; set; }
    
    /// <summary>السعر</summary>
    public decimal Price { get; set; }
    
    /// <summary>سعر الخصم</summary>
    public decimal? DiscountPrice { get; set; }
    
    /// <summary>الكمية المتوفرة</summary>
    public int StockQuantity { get; set; } = 0;
    
    /// <summary>الصورة الرئيسية</summary>
    public string? ImageUrl { get; set; }
    
    /// <summary>صور إضافية (JSON)</summary>
    public string? AdditionalImages { get; set; }
    
    /// <summary>هل نشط؟</summary>
    public bool IsActive { get; set; } = true;
    
    /// <summary>هل متوفر؟</summary>
    public bool IsAvailable { get; set; } = true;
    
    /// <summary>هل مميز؟</summary>
    public bool IsFeatured { get; set; } = false;
    
    /// <summary>الترتيب</summary>
    public int SortOrder { get; set; } = 0;
    
    /// <summary>متوسط التقييم</summary>
    public decimal AverageRating { get; set; } = 0;
    
    /// <summary>عدد التقييمات</summary>
    public int ReviewCount { get; set; } = 0;
    
    /// <summary>عدد المبيعات</summary>
    public int SoldCount { get; set; } = 0;
    
    // Navigation
    public virtual Company? Company { get; set; }
    public virtual ProductCategory? Category { get; set; }
    public virtual ICollection<StoreOrderItem> OrderItems { get; set; } = new List<StoreOrderItem>();
}

/// <summary>
/// تصنيف المنتجات
/// </summary>
public class ProductCategory : BaseEntity<Guid>
{
    /// <summary>الشركة</summary>
    public Guid? CompanyId { get; set; }
    
    /// <summary>الاسم</summary>
    public string Name { get; set; } = string.Empty;
    
    /// <summary>الاسم بالعربي</summary>
    public string NameAr { get; set; } = string.Empty;
    
    /// <summary>الوصف</summary>
    public string? Description { get; set; }
    
    /// <summary>الأيقونة</summary>
    public string? IconUrl { get; set; }
    
    /// <summary>الترتيب</summary>
    public int SortOrder { get; set; } = 0;
    
    /// <summary>هل نشط؟</summary>
    public bool IsActive { get; set; } = true;
    
    // Navigation
    public virtual Company? Company { get; set; }
    public virtual ICollection<StoreProduct> Products { get; set; } = new List<StoreProduct>();
}

/// <summary>
/// طلب من المتجر
/// </summary>
public class StoreOrder : BaseEntity<Guid>
{
    /// <summary>رقم الطلب</summary>
    public string OrderNumber { get; set; } = string.Empty;
    
    /// <summary>المواطن</summary>
    public Guid CitizenId { get; set; }
    
    /// <summary>الشركة</summary>
    public Guid CompanyId { get; set; }
    
    /// <summary>حالة الطلب</summary>
    public StoreOrderStatus Status { get; set; } = StoreOrderStatus.Pending;
    
    /// <summary>المجموع الفرعي</summary>
    public decimal SubTotal { get; set; }
    
    /// <summary>رسوم التوصيل</summary>
    public decimal DeliveryFee { get; set; } = 0;
    
    /// <summary>الخصم</summary>
    public decimal DiscountAmount { get; set; } = 0;
    
    /// <summary>المجموع الكلي</summary>
    public decimal TotalAmount { get; set; }
    
    /// <summary>حالة الدفع</summary>
    public PaymentStatus PaymentStatus { get; set; } = PaymentStatus.Pending;
    
    /// <summary>طريقة الدفع</summary>
    public PaymentMethod PaymentMethod { get; set; }
    
    // ============ التوصيل ============
    
    /// <summary>عنوان التوصيل</summary>
    public string? DeliveryAddress { get; set; }
    
    /// <summary>المدينة</summary>
    public string? DeliveryCity { get; set; }
    
    /// <summary>رقم الهاتف للتواصل</summary>
    public string? ContactPhone { get; set; }
    
    /// <summary>ملاحظات التوصيل</summary>
    public string? DeliveryNotes { get; set; }
    
    /// <summary>تاريخ التوصيل المتوقع</summary>
    public DateTime? EstimatedDeliveryDate { get; set; }
    
    /// <summary>تاريخ التوصيل الفعلي</summary>
    public DateTime? ActualDeliveryDate { get; set; }
    
    /// <summary>موظف التوصيل</summary>
    public Guid? DeliveredById { get; set; }
    
    // ============ الإلغاء ============
    
    /// <summary>سبب الإلغاء</summary>
    public string? CancellationReason { get; set; }
    
    /// <summary>تاريخ الإلغاء</summary>
    public DateTime? CancelledAt { get; set; }
    
    /// <summary>ملاحظات</summary>
    public string? Notes { get; set; }
    
    // Navigation
    public virtual Citizen? Citizen { get; set; }
    public virtual Company? Company { get; set; }
    public virtual User? DeliveredBy { get; set; }
    public virtual ICollection<StoreOrderItem> Items { get; set; } = new List<StoreOrderItem>();
}

/// <summary>
/// عنصر في طلب المتجر
/// </summary>
public class StoreOrderItem : BaseEntity<Guid>
{
    public Guid StoreOrderId { get; set; }
    public Guid ProductId { get; set; }
    
    /// <summary>اسم المنتج (snapshot)</summary>
    public string ProductName { get; set; } = string.Empty;
    
    /// <summary>سعر الوحدة</summary>
    public decimal UnitPrice { get; set; }
    
    /// <summary>الكمية</summary>
    public int Quantity { get; set; }
    
    /// <summary>الإجمالي</summary>
    public decimal TotalPrice { get; set; }
    
    // Navigation
    public virtual StoreOrder? Order { get; set; }
    public virtual StoreProduct? Product { get; set; }
}

/// <summary>
/// حالة طلب المتجر
/// </summary>
public enum StoreOrderStatus
{
    Pending = 0,
    Confirmed = 1,
    Processing = 2,
    Shipped = 3,
    Delivered = 4,
    Cancelled = 5,
    Returned = 6
}
