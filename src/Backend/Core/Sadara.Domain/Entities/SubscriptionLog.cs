namespace Sadara.Domain.Entities;

/// <summary>
/// سجل عمليات الاشتراكات (بديل Google Sheets)
/// يُسجل كل عملية تجديد/شراء/تفعيل اشتراك
/// </summary>
public class SubscriptionLog : BaseEntity<long>
{
    // معلومات العميل
    public string? CustomerId { get; set; }
    public string? CustomerName { get; set; }
    public string? PhoneNumber { get; set; }

    // معلومات الاشتراك
    public string? SubscriptionId { get; set; }
    public string? PlanName { get; set; }
    public decimal? PlanPrice { get; set; }
    public int? CommitmentPeriod { get; set; }
    public string? BundleId { get; set; }
    public string? CurrentStatus { get; set; }
    public string? DeviceUsername { get; set; }

    // معلومات العملية
    public string? OperationType { get; set; }  // purchase, renewal, change
    public string? ActivatedBy { get; set; }
    public DateTime? ActivationDate { get; set; }
    public string? ActivationTime { get; set; }
    public string? SessionId { get; set; }
    public DateTime? LastUpdateDate { get; set; }

    // معلومات الموقع
    public string? ZoneId { get; set; }
    public string? ZoneName { get; set; }
    public string? FbgInfo { get; set; }
    public string? FatInfo { get; set; }
    public string? FdtInfo { get; set; }

    // معلومات المحفظة
    public decimal? WalletBalanceBefore { get; set; }
    public decimal? WalletBalanceAfter { get; set; }
    public decimal? PartnerWalletBalanceBefore { get; set; }
    public decimal? CustomerWalletBalanceBefore { get; set; }
    public string? Currency { get; set; }
    public string? PaymentMethod { get; set; }

    // معلومات الشريك/الموظف
    public string? PartnerName { get; set; }
    public string? PartnerId { get; set; }
    public Guid? UserId { get; set; }  // FK to User table
    public Guid? CompanyId { get; set; }  // FK to Company table

    // حالة العملية
    public bool IsPrinted { get; set; } = false;
    public bool IsWhatsAppSent { get; set; } = false;
    public string? SubscriptionNotes { get; set; }

    // معلومات إضافية
    public string? StartDate { get; set; }
    public string? EndDate { get; set; }
    public string? ApiResponse { get; set; }  // لتخزين response كامل إذا لزم

    // معلومات التوصيل والدفع
    public string? TechnicianName { get; set; }  // اسم الفني المنفذ
    public string? PaymentStatus { get; set; }   // حالة الدفع (مسدد / غير مسدد)
}
