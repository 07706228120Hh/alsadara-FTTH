namespace Sadara.Domain.Entities;

/// <summary>
/// تسديد مواطن/مشترك لذمّة آجلة (دفتر ذمم المواطنين لنظام الساس).
/// كل صفّ = حركة تسديد واحدة تُقيّد: مدين حساب التحصيل (نقد 1110x / إلكتروني 1170) + دائن ذمة المشترك (1180x).
/// يُقرَن بالقيد المحاسبي عبر <see cref="JournalEntryId"/> ويخدم كشف الحساب (شحنات − تسديدات = الرصيد المستحق).
///
/// معزول بمستأجرين عبر <see cref="CompanyId"/> (يوسم <see cref="ITenantScoped"/>) — يطبَّق عليه فلتر المستأجر المركزي.
/// مفتاح المشترك المنطقي: (CompanyId + SasAccountId + SubscriberUid) — نفس مفتاح ذمّة المشترك.
/// </summary>
public class SasCitizenPayment : BaseEntity<Guid>, ITenantScoped
{
    /// <summary>معرف الشركة المالكة (مفتاح العزل بين المستأجرين)</summary>
    public Guid CompanyId { get; set; }

    /// <summary>معرّف حساب الساس الذي يخصّه هذا التسديد (SasAccount.Id)</summary>
    public Guid SasAccountId { get; set; }

    /// <summary>معرّف المشترك في نظام الساس (uid) — مفتاح ذمّة المشترك</summary>
    public string SubscriberUid { get; set; } = string.Empty;

    /// <summary>مبلغ التسديد (موجب)</summary>
    public decimal Amount { get; set; }

    /// <summary>وسيلة التسديد: cash (نقد) | master (دفع إلكتروني)</summary>
    public string Method { get; set; } = "cash";

    /// <summary>ملاحظة اختيارية على التسديد</summary>
    public string? Note { get; set; }

    /// <summary>معرّف القيد المحاسبي المُنشأ لهذا التسديد (إن أُنشئ)</summary>
    public Guid? JournalEntryId { get; set; }
}
