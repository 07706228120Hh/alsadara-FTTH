namespace Sadara.Domain.Entities;

/// <summary>
/// إعدادات التذكير التلقائي
/// </summary>
public class ReminderSettings : BaseEntity<long>
{
    public string TenantId { get; set; } = string.Empty;
    public bool IsEnabled { get; set; } = false;

    /// <summary>وجبات الإرسال بصيغة JSON</summary>
    public string BatchesJson { get; set; } = "[]";
}

/// <summary>
/// سجل تنفيذ التذكيرات
/// </summary>
public class ReminderExecutionLog : BaseEntity<long>
{
    public string TenantId { get; set; } = string.Empty;
    public string? BatchId { get; set; }
    public int Days { get; set; }
    public int Total { get; set; }
    public int Sent { get; set; }
    public int Failed { get; set; }
    public DateTime ExecutedAt { get; set; } = DateTime.UtcNow;
    public bool IsManual { get; set; } = false;
    public string? TriggeredBy { get; set; }
}
