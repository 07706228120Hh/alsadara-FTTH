namespace Sadara.Domain.Entities;

/// <summary>
/// سجلّ تدقيق دائم لكل عملية «إخراج إجباري لكل موظفي الشركة» (زر إعدادات الشركة).
/// حدث حسّاس على مستوى الشركة لا يكفيه <c>ILogger</c> وحده، فيُخزَّن في قاعدة البيانات للمراجعة الأمنية.
///
/// معزول بمستأجرين عبر <see cref="CompanyId"/> (يوسم <see cref="ITenantScoped"/>) فيأخذ الفلتر
/// المركزي في <c>SadaraDbContext</c> تلقائياً عند تفعيل العزل.
/// </summary>
public class ForceLogoutAudit : BaseEntity<Guid>, ITenantScoped
{
    /// <summary>معرف الشركة التي طُبّق عليها الإخراج (مفتاح العزل بين المستأجرين)</summary>
    public Guid CompanyId { get; set; }

    /// <summary>معرف المدير الذي نفّذ الإخراج (مرجع تدقيق، بلا مفتاح أجنبي)</summary>
    public Guid RequestedByUserId { get; set; }

    /// <summary>عدد الجلسات/المستخدمين المتأثّرين (عدا الضاغط)</summary>
    public int AffectedCount { get; set; }

    /// <summary>توقيت التنفيذ (UTC)</summary>
    public DateTime ExecutedAtUtc { get; set; }

    // ============ العلاقات ============

    /// <summary>الشركة المالكة</summary>
    public virtual Company Company { get; set; } = null!;
}
