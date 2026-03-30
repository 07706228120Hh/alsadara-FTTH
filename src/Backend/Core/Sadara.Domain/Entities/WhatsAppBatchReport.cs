namespace Sadara.Domain.Entities;

/// <summary>
/// تقرير إرسال جماعي عبر واتساب
/// </summary>
public class WhatsAppBatchReport : BaseEntity<long>
{
    /// <summary>معرف الدُفعة</summary>
    public string BatchId { get; set; } = string.Empty;

    /// <summary>نوع القالب (sadara_reminder, sadara_renewed, sadara_expired)</summary>
    public string? TemplateType { get; set; }

    /// <summary>العدد الكلي</summary>
    public int Total { get; set; }

    /// <summary>عدد المرسل بنجاح</summary>
    public int Sent { get; set; }

    /// <summary>عدد الفاشل</summary>
    public int Failed { get; set; }

    /// <summary>نسبة النجاح</summary>
    public string? Rate { get; set; }

    /// <summary>وقت الإتمام</summary>
    public DateTime? CompletedAt { get; set; }

    /// <summary>تحذيرات</summary>
    public string? Warning { get; set; }

    /// <summary>ملخص الأخطاء</summary>
    public string? FailedSummary { get; set; }

    /// <summary>هل تم إيقاف مبكر</summary>
    public bool EarlyStop { get; set; } = false;

    /// <summary>سبب الإيقاف المبكر</summary>
    public string? EarlyStopReason { get; set; }

    /// <summary>الحالة (processing, completed, stopped)</summary>
    public string Status { get; set; } = "completed";
}
