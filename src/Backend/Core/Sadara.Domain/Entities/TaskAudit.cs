namespace Sadara.Domain.Entities;

/// <summary>
/// تدقيق المهام - يسجل حالة التدقيق والتقييم لكل مهمة
/// </summary>
public class TaskAudit : BaseEntity<long>
{
    /// <summary>
    /// معرف طلب الخدمة (ServiceRequest)
    /// </summary>
    public Guid ServiceRequestId { get; set; }

    /// <summary>
    /// رقم الطلب (RequestNumber) - للربط السريع
    /// </summary>
    public string? RequestNumber { get; set; }

    /// <summary>
    /// حالة التدقيق: لم يتم، تم التدقيق، مشكلة
    /// </summary>
    public string AuditStatus { get; set; } = "لم يتم";

    /// <summary>
    /// التقييم (1-5 نجوم)
    /// </summary>
    public int Rating { get; set; } = 0;

    /// <summary>
    /// ملاحظات التدقيق (تفاصيل المشكلة مثلاً)
    /// </summary>
    public string? Notes { get; set; }

    /// <summary>
    /// اسم المستخدم الذي أجرى التدقيق
    /// </summary>
    public string? AuditedBy { get; set; }

    /// <summary>
    /// تاريخ آخر تدقيق
    /// </summary>
    public DateTime? AuditedAt { get; set; }

    /// <summary>
    /// معرف الشركة (multi-tenant)
    /// </summary>
    public Guid? CompanyId { get; set; }
}
