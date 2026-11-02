namespace Sadara.Application.Interfaces;

/// <summary>
/// نتيجة تسجيل الدخول الخادمي إلى نظام FTTH. لا تحوي أي سرّ قابل للتسجيل عدا رموز الوصول/التحديث
/// التي تبقى في الذاكرة فقط ولا تُسجَّل (log) ولا تُعاد في أي استجابة عرض.
/// </summary>
public record FtthLoginResult(bool Ok, string? AccessToken, string? RefreshToken, string? Error);

/// <summary>نتيجة تنفيذ تحويل العمولة لدى FTTH: نجاح + رمز HTTP الوارد + رسالة خطأ (عند الفشل).</summary>
public record FtthTransferResult(bool Ok, int StatusCode, string? Error);

/// <summary>
/// تجريد نداءات نظام FTTH الخاصة بحارس «تحويل العمولة» (تسجيل الدخول/جلب partnerId/رصيد العمولة/التحويل).
///
/// الغرض: فصل منطق الشبكة الخارجي عن منطق الحارس المالي/العزل/الـ idempotency في
/// <c>LinkedAccountsController</c> ليصبح الحارس قابلاً للاختبار بتزييف هذه الواجهة — دون أي تغيير سلوكي.
///
/// ⚠️ أمن: التنفيذ يفرض قائمة سماح المضيفات (إغلاق SSRF) ويعطّل إعادة التوجيه التلقائية ولا يُسجّل أي اعتماد.
/// </summary>
public interface IFtthCommissionClient
{
    /// <summary>تسجيل دخول خادمي إلى FTTH بالاعتماد المخزّن (مفكوك في الذاكرة فقط).</summary>
    Task<FtthLoginResult> LoginAsync(string serverUrl, string username, string password, CancellationToken ct);

    /// <summary>يجلب partnerId الحيّ من FTTH عبر current-user. يعيد null عند الفشل.</summary>
    Task<string?> GetPartnerIdAsync(string serverUrl, string accessToken, CancellationToken ct);

    /// <summary>يجلب رصيد العمولة الحيّ من FTTH. يعيد null عند الفشل.</summary>
    Task<decimal?> GetCommissionBalanceAsync(string serverUrl, string accessToken, string partnerId, CancellationToken ct);

    /// <summary>ينفّذ تحويل العمولة لدى FTTH مع تمرير Idempotency-Key/requestId.</summary>
    Task<FtthTransferResult> TransferAsync(string serverUrl, string accessToken, string partnerId, long amount, string requestId, CancellationToken ct);
}
