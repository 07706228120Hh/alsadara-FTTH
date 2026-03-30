namespace Sadara.Domain.Entities;

/// <summary>
/// تقرير التسديدات اليومي للمشغل
/// كل مشغل يرسل تقرير واحد يومياً يحتوي على بنود (ملاحظة + مبلغ)
/// </summary>
public class DailySettlementReport : BaseEntity<long>
{
    /// <summary>تاريخ التقرير (UTC, بدون وقت)</summary>
    public DateTime ReportDate { get; set; }

    /// <summary>اسم المشغل</summary>
    public string OperatorName { get; set; } = "";

    /// <summary>معرف المشغل (اختياري)</summary>
    public string? OperatorId { get; set; }

    /// <summary>معرف الشركة</summary>
    public Guid? CompanyId { get; set; }

    /// <summary>ملاحظات عامة</summary>
    public string? Notes { get; set; }

    /// <summary>بنود التقرير كـ JSON array: [{note, amount}]</summary>
    public string ItemsJson { get; set; } = "[]";

    /// <summary>مجموع المبالغ (محسوب من البنود)</summary>
    public decimal TotalAmount { get; set; }

    /// <summary>معرف الموظف المستلم</summary>
    public string? DeliveredToId { get; set; }

    /// <summary>اسم الموظف المستلم</summary>
    public string? DeliveredToName { get; set; }

    /// <summary>معرف القيد المحاسبي المرتبط</summary>
    public Guid? JournalEntryId { get; set; }

    // ═══ تفاصيل اشتراكات النظام ═══
    /// <summary>إجمالي كل العمليات</summary>
    public decimal SystemTotal { get; set; }
    /// <summary>إجمالي النقد</summary>
    public decimal SystemCashTotal { get; set; }
    /// <summary>إجمالي الآجل</summary>
    public decimal SystemCreditTotal { get; set; }
    /// <summary>إجمالي الماستر</summary>
    public decimal SystemMasterTotal { get; set; }
    /// <summary>إجمالي الفني</summary>
    public decimal SystemTechTotal { get; set; }
    /// <summary>إجمالي الوكيل</summary>
    public decimal SystemAgentTotal { get; set; }
    /// <summary>إجمالي المصاريف (من البنود)</summary>
    public decimal TotalExpenses { get; set; }
    /// <summary>النقد الصافي = نقد النظام − المصاريف</summary>
    public decimal NetCashAmount { get; set; }

    /// <summary>المبلغ المستلم فعلياً من المحاسب</summary>
    public decimal ReceivedAmount { get; set; }
}
