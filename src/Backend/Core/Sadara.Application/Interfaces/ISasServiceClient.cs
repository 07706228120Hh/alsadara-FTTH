namespace Sadara.Application.Interfaces;

/// <summary>
/// نتيجة محاولة تسجيل الدخول لخدمة الساس الداخلية.
/// </summary>
/// <param name="Success">هل نجح الدخول؟</param>
/// <param name="SessionHandle">مقبض جلسة معتم (opaque) يعيده الوسيط عند النجاح — قد يكون null.</param>
/// <param name="Message">رسالة وصفية (للنجاح أو الفشل) — لا تحوي أسراراً أبداً.</param>
public record SasLoginResult(bool Success, string? SessionHandle, string? Message);

/// <summary>
/// تجريد للاتصال بخدمة الساس الداخلية (Python sidecar على 127.0.0.1) خلف الصدارة.
///
/// ⚠️ قواعد أمنية:
///  - الاعتماد (username/password) يُمرَّر من الصدارة بعد فكّ التشفير في الذاكرة فقط، ولا يُسجَّل.
///  - الخدمة غير مكشوفة للإنترنت؛ المصادقة بينها وبين الصدارة عبر سرّ داخلي (X-Internal-Secret).
///  - العقد مبدئي وقابل للتوسيع؛ يكتمل في المرحلة 3 عند بناء خدمة Python.
///
/// جميع الدوال تعيد JSON خاماً (string) كما تُعيده خدمة الساس؛ الصدارة تمرّره للواجهة دون تخزين.
/// </summary>
public interface ISasServiceClient
{
    /// <summary>تسجيل دخول صامت لنظام الساس باعتماد الحساب؛ يعيد نجاحاً + مقبض جلسة اختياري.</summary>
    Task<SasLoginResult> LoginAsync(
        string serverUrl,
        string username,
        string password,
        CancellationToken cancellationToken = default);

    /// <summary>جلب بيانات لوحة الوكيل (Dashboard) خاماً كـ JSON.</summary>
    Task<string> GetDashboardAsync(
        string serverUrl,
        string username,
        string password,
        CancellationToken cancellationToken = default);

    /// <summary>جلب قائمة مشتركي الوكيل خاماً كـ JSON مع وسائط استعلام اختيارية (بحث/صفحة/حجم…).</summary>
    Task<string> GetSubscribersAsync(
        string serverUrl,
        string username,
        string password,
        IDictionary<string, string?>? query = null,
        CancellationToken cancellationToken = default);

    /// <summary>جلب تقرير الوكيل (التصريح/البلنك) خاماً كـ JSON مع وسائط استعلام اختيارية (فترة…).</summary>
    Task<string> GetReportAsync(
        string serverUrl,
        string username,
        string password,
        IDictionary<string, string?>? query = null,
        CancellationToken cancellationToken = default);

    /// <summary>جلب باقات/بروفايلات الساس المتاحة للوكيل خاماً كـ JSON (تبويب الباقات).</summary>
    Task<string> GetPackagesAsync(
        string serverUrl,
        string username,
        string password,
        CancellationToken cancellationToken = default);

    /// <summary>جلب ملخّص/تفاصيل المالية (الرصيد/الحركات) للوكيل خاماً كـ JSON (تبويب المالية).</summary>
    Task<string> GetFinanceAsync(
        string serverUrl,
        string username,
        string password,
        CancellationToken cancellationToken = default);

    /// <summary>جلب حالة صحّة الاتصال/الحساب مع نظام الساس خاماً كـ JSON (تبويب الصحّة/الحالة).</summary>
    Task<string> GetHealthAsync(
        string serverUrl,
        string username,
        string password,
        CancellationToken cancellationToken = default);

    /// <summary>
    /// جلب مرشّحي التجديد (المشتركون المنتهون/الأوشك على الانتهاء) خاماً كـ JSON.
    /// </summary>
    /// <param name="days">نافذة الأيام قبل/بعد الانتهاء لاعتبار المشترك مرشّحاً (اختياري).</param>
    /// <param name="query">نص بحث اختياري لتصفية المرشّحين.</param>
    Task<string> GetRenewalCandidatesAsync(
        string serverUrl,
        string username,
        string password,
        int? days = null,
        string? query = null,
        CancellationToken cancellationToken = default);

    /// <summary>
    /// تجديد جماعي لمشتركين محدّدين — عملية كتابية. تعيد نتيجة الخدمة خاماً كـ JSON.
    /// </summary>
    /// <param name="subscriberIds">معرّفات المشتركين المراد تجديدهم.</param>
    /// <param name="months">عدد الأشهر للتجديد.</param>
    /// <param name="profileId">معرّف البروفايل/الباقة الاختياري للتجديد.</param>
    /// <param name="dryRun">إن true تُحاكى العملية بلا تنفيذ فعلي (معاينة).</param>
    Task<string> BulkRenewAsync(
        string serverUrl,
        string username,
        string password,
        IEnumerable<string> subscriberIds,
        int months,
        string? profileId = null,
        bool dryRun = false,
        CancellationToken cancellationToken = default);

    // ==================== العقد الموحّد الكامل لعمليات الساس (خدمة Python 127.0.0.1:8100) ====================
    // كل الدوال أدناه تمرّر الاعتماد (serverUrl/username/password) + الوسائط في جسم POST وتعيد JSON خاماً.
    // ⚠️ أمن: الاعتماد يُمرَّر بعد فكّ التشفير في الذاكرة فقط، ولا يُسجَّل أبداً.

    // ---------- المشتركون: قراءات ----------

    /// <summary>تفاصيل مشترك محدّد (POST /users/detail + uid). قراءة.</summary>
    Task<string> GetUserDetailAsync(
        string serverUrl, string username, string password,
        string uid, CancellationToken cancellationToken = default);

    /// <summary>نظرة عامة على المشتركين (POST /users/overview). قراءة.</summary>
    Task<string> GetUsersOverviewAsync(
        string serverUrl, string username, string password,
        CancellationToken cancellationToken = default);

    /// <summary>سجل/تاريخ مشترك محدّد (POST /users/history + uid). قراءة.</summary>
    Task<string> GetUserHistoryAsync(
        string serverUrl, string username, string password,
        string uid, CancellationToken cancellationToken = default);

    /// <summary>بيانات تمديد/إضافة رصيد لمشترك (POST /users/extend-data + uid). قراءة.</summary>
    Task<string> GetUserExtendDataAsync(
        string serverUrl, string username, string password,
        string uid, CancellationToken cancellationToken = default);

    // ---------- المشتركون: كتابات ----------

    /// <summary>تنفيذ إجراء على مشترك (POST /users/action + uid + action + params). كتابة.</summary>
    Task<string> UserActionAsync(
        string serverUrl, string username, string password,
        string uid, string action, object? parameters = null,
        CancellationToken cancellationToken = default);

    /// <summary>تنفيذ إجراء جماعي على مشتركين (POST /users/bulk-action + uids[] + action + params). كتابة.</summary>
    Task<string> UsersBulkActionAsync(
        string serverUrl, string username, string password,
        IEnumerable<string> uids, string action, object? parameters = null,
        CancellationToken cancellationToken = default);

    /// <summary>إنشاء مشترك جديد (POST /users/create + payload). كتابة.</summary>
    Task<string> CreateUserAsync(
        string serverUrl, string username, string password,
        object payload, CancellationToken cancellationToken = default);

    /// <summary>تعديل مشترك (POST /users/update + uid + payload). كتابة.</summary>
    Task<string> UpdateUserAsync(
        string serverUrl, string username, string password,
        string uid, object payload, CancellationToken cancellationToken = default);

    /// <summary>حذف مشترك (POST /users/delete + uid). كتابة.</summary>
    Task<string> DeleteUserAsync(
        string serverUrl, string username, string password,
        string uid, CancellationToken cancellationToken = default);

    /// <summary>بيانات استرداد رصيد/داتا لمشترك (POST /users/refund-data + uid). كتابة (تحضير عملية).</summary>
    Task<string> GetUserRefundDataAsync(
        string serverUrl, string username, string password,
        string uid, CancellationToken cancellationToken = default);

    /// <summary>تنفيذ استرداد لمشترك (POST /users/refund + uid). كتابة.</summary>
    Task<string> RefundUserAsync(
        string serverUrl, string username, string password,
        string uid, CancellationToken cancellationToken = default);

    // ---------- المتصلون ----------

    /// <summary>قائمة المتصلين حالياً (POST /online). قراءة.</summary>
    Task<string> GetOnlineAsync(
        string serverUrl, string username, string password,
        CancellationToken cancellationToken = default);

    // ---------- الوكلاء/المدراء ----------

    /// <summary>قائمة الوكلاء/المدراء (POST /managers). قراءة.</summary>
    Task<string> GetManagersAsync(
        string serverUrl, string username, string password,
        CancellationToken cancellationToken = default);

    /// <summary>تنفيذ إجراء على وكيل/مدير (POST /managers/action + mid + action + params). كتابة.</summary>
    Task<string> ManagerActionAsync(
        string serverUrl, string username, string password,
        string mid, string action, object? parameters = null,
        CancellationToken cancellationToken = default);

    /// <summary>حذف وكيل/مدير (POST /managers/delete + mid). كتابة.</summary>
    Task<string> DeleteManagerAsync(
        string serverUrl, string username, string password,
        string mid, CancellationToken cancellationToken = default);

    // ---------- البروكسي العام لـ SAS ----------

    /// <summary>بروكسي عام GET لأي مسار ساس (POST /sas/get + path). قراءة.</summary>
    Task<string> SasGetAsync(
        string serverUrl, string username, string password,
        string path, CancellationToken cancellationToken = default);

    /// <summary>بروكسي عام POST لأي مسار ساس (POST /sas/post + path + payload). كتابة.</summary>
    Task<string> SasPostAsync(
        string serverUrl, string username, string password,
        string path, object? payload = null, CancellationToken cancellationToken = default);
}
