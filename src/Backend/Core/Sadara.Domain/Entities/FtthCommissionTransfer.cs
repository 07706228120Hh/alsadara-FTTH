namespace Sadara.Domain.Entities;

/// <summary>
/// سجلّ idempotency/تدقيق لعملية «تحويل رصيد العمولة إلى المحفظة الرئيسية» في نظام FTTH،
/// تمرّ عبر بوّابة الصدارة (<c>POST /api/linked-accounts/ftth/{id}/transfer-commission</c>) التي تفرض
/// خادمياً: <c>0 &lt; amount ≤ رصيد العمولة الحيّ</c> + منع التكرار + تدقيق، قبل تمرير التحويل لـ FTTH.
///
/// العزل: معزول بمستأجرين عبر <see cref="CompanyId"/> (يوسم <see cref="ITenantScoped"/>) وبمالك الحساب
/// عبر <see cref="OwnerUserId"/> (دفاع بالعمق). فهرس فريد مُرشّح على (الشركة + الحساب + <see cref="RequestId"/>)
/// يضمن تنفيذ العملية الواحدة مرّة واحدة فقط حتى عند التكرار/السباق.
///
/// ⚠️ بيانات عملية وتدقيق فقط — لا يُخزَّن هنا أي اعتماد/سرّ (كلمة مرور FTTH) إطلاقاً، ولا أي توكن.
/// </summary>
public class FtthCommissionTransfer : BaseEntity<Guid>, ITenantScoped
{
    /// <summary>معرف الشركة المالكة (مفتاح العزل بين المستأجرين) — يُختم من التوكن لا من العميل.</summary>
    public Guid CompanyId { get; set; }

    /// <summary>معرف الموظف مالك حساب FTTH الذي نُفّذ عليه التحويل (مرجع تدقيق + عزل بالعمق).</summary>
    public Guid OwnerUserId { get; set; }

    /// <summary>معرف حساب FTTH المرتبط (<see cref="FtthAccount"/>) الذي نُفّذ عليه التحويل.</summary>
    public Guid FtthAccountId { get; set; }

    /// <summary>معرّف الشريك في نظام FTTH (partnerId) الذي نُفّذ التحويل على محفظته — للتدقيق.</summary>
    public string PartnerId { get; set; } = string.Empty;

    /// <summary>المبلغ المطلوب تحويله من العمولة إلى المحفظة الرئيسية (بالدينار، عدد صحيح موجب).</summary>
    public long Amount { get; set; }

    /// <summary>
    /// مُعرّف الطلب الفريد (idempotency key) المُرسَل من العميل. فريد ضمن (الشركة + الحساب)
    /// لمنع تنفيذ نفس العملية مرّتين. يُمرَّر أيضاً لـ FTTH كـ <c>Idempotency-Key</c>.
    /// </summary>
    public string RequestId { get; set; } = string.Empty;

    /// <summary>حالة العملية: "Pending" / "Succeeded" / "Failed".</summary>
    public string Status { get; set; } = FtthCommissionTransferStatus.Pending;

    /// <summary>رمز استجابة FTTH (HTTP status code) عند اكتمال/فشل النداء — null قبل التنفيذ.</summary>
    public int? FtthResponseCode { get; set; }

    /// <summary>رسالة موجزة عن النتيجة/سبب الفشل (عربية للعرض، أو ملخّص خطأ FTTH) — بلا أي سرّ.</summary>
    public string? FtthMessage { get; set; }

    /// <summary>توقيت اكتمال العملية (نجاح/فشل نهائي) بالـ UTC — null ما دامت Pending.</summary>
    public DateTime? CompletedAtUtc { get; set; }

    // ============ العلاقات ============

    /// <summary>الشركة المالكة</summary>
    public virtual Company Company { get; set; } = null!;
}

/// <summary>حالات عملية تحويل العمولة (ثوابت نصّية لتفادي تحويلات enum في القاعدة).</summary>
public static class FtthCommissionTransferStatus
{
    public const string Pending = "Pending";
    public const string Succeeded = "Succeeded";
    public const string Failed = "Failed";
}
