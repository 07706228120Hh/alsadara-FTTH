using Sadara.Domain.Enums;

namespace Sadara.Domain.Entities;

/// <summary>
/// حساب ساس (SAS) مربوط بموظف داخل الشركة.
/// يدعم عدّة حسابات للموظف الواحد (صفحة وكيل + نظام ساس).
/// معزول بمستأجرين عبر <see cref="CompanyId"/> (يوسم <see cref="ITenantScoped"/>)
/// وبمالك عبر <see cref="OwnerUserId"/> (دفاع بالعمق فوق فلتر المستأجر).
/// </summary>
public class SasAccount : BaseEntity<Guid>, ITenantScoped
{
    /// <summary>معرف الشركة المالكة (مفتاح العزل بين المستأجرين)</summary>
    public Guid CompanyId { get; set; }

    /// <summary>معرف الموظف المالك للحساب (User) — يُطابَق مع المستخدم الحالي كدفاع بالعمق</summary>
    public Guid OwnerUserId { get; set; }

    /// <summary>تسمية وصفية للحساب يختارها الموظف (مثل: «حسابي الرئيسي»)</summary>
    public string Label { get; set; } = string.Empty;

    /// <summary>عنوان خادم الساس (SAS4) الخاص بمزوّد الوكيل</summary>
    public string ServerUrl { get; set; } = string.Empty;

    /// <summary>اسم المستخدم على نظام الساس</summary>
    public string Username { get; set; } = string.Empty;

    /// <summary>
    /// كلمة مرور الساس مشفّرة (تُحفظ مشفّرة عبر Data Protection في المرحلة 1.4).
    /// ⚠️ لا يُعاد هذا الحقل أبداً في أي استجابة API — يُفكّ تشفيره داخلياً فقط عند التمرير لخدمة Python.
    /// </summary>
    public string PasswordEncrypted { get; set; } = string.Empty;

    /// <summary>نوع الحساب: صفحة وكيل (SasManager) أو نظام ساس (SasUser)</summary>
    public SasAccountType AccountType { get; set; }

    /// <summary>
    /// مُضاعِف القيم المالية القادمة من نظام SAS4 إلى الدينار الحقيقي.
    /// بعض مزوّدي SAS4 يُرجعون القيم بوحدة الآلاف (16 = 16,000 دينار)؛ هذا المُضاعِف
    /// (افتراضي 1000) يُطبَّق على السعر/الرصيد القادمَين من الساس لتوحيدهما مع محاسبة
    /// الصدارة (الدينار الكامل). اضبطه 1 للمزوّدين الذين يُرجعون الدينار مباشرةً.
    /// </summary>
    public decimal AmountMultiplier { get; set; } = 1000m;

    /// <summary>هل الحساب مفعّل؟</summary>
    public bool IsActive { get; set; } = true;

    /// <summary>آخر وقت مزامنة ناجحة لهذا الحساب</summary>
    public DateTime? LastSyncAt { get; set; }

    /// <summary>حالة آخر مزامنة (نص وصفي مختصر)</summary>
    public string? SyncStatus { get; set; }

    // ============ العلاقات ============

    /// <summary>الشركة المالكة</summary>
    public virtual Company Company { get; set; } = null!;
}
