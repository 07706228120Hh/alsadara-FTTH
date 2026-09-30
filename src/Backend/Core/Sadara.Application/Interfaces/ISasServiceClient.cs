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

    /// <summary>نظرة عامة على مشترك محدّد (POST /users/overview + uid). قراءة.</summary>
    Task<string> GetUserOverviewAsync(
        string serverUrl, string username, string password,
        string uid, CancellationToken cancellationToken = default);

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

    // ==================== البلنك/التصريح + المزامنة المحلية + المقاطعة + اختبار الاتصال ====================
    // نقاط بوّابة «وكيل الساس» المحلية (خدمة Python 127.0.0.1:8100). على عكس نقاط الساس الخام أعلاه،
    // هذه النقاط تعتمد على تخزين محلي معزول بـ account_id (وبعضها companyId/ownerUserId):
    //  - accountId  = معرّف SasAccount المملوك (لا من إدخال المستخدم) — مفتاح عزل التخزين المحلي.
    //  - companyId  = شركة المستخدم الحالي (عزل المستأجرين).
    //  - ownerUserId= المستخدم المالك للحساب (دفاع بالعمق).
    // ⚠️ أمن: الاعتماد (username/password) يُمرَّر بعد فكّ التشفير في الذاكرة فقط ولا يُسجَّل أبداً.

    /// <summary>
    /// اختبار اتصال الحساب بنظام الساس (POST /account/test باعتماد فقط).
    /// يعيد JSON خاماً <c>{ok, message, subscribers_count?}</c>. قراءة (لا تخزين).
    /// </summary>
    Task<string> TestAccountAsync(
        string serverUrl, string username, string password,
        CancellationToken cancellationToken = default);

    /// <summary>
    /// مزامنة محلية لمشتركي الحساب من الساس إلى التخزين المحلي (POST /sync باعتماد + accountId).
    /// يعيد JSON خاماً <c>{count, expiry, synced_at}</c>. كتابة محلية.
    /// </summary>
    Task<string> SyncAccountAsync(
        string serverUrl, string username, string password,
        string accountId, CancellationToken cancellationToken = default);

    /// <summary>
    /// جلب المشتركين من التخزين المحلي المعزول بـ accountId (POST /subscribers/local) — بلا اعتماد ساس.
    /// يعيد JSON خاماً (قائمة). قراءة محلية.
    /// </summary>
    /// <param name="accountId">معرّف الحساب المملوك (عزل التخزين المحلي).</param>
    /// <param name="search">نص بحث اختياري.</param>
    /// <param name="status">تصفية بالحالة (اختياري).</param>
    /// <param name="expiring">تصفية المنتهين/الأوشك على الانتهاء (اختياري).</param>
    /// <param name="page">رقم الصفحة (اختياري).</param>
    /// <param name="count">حجم الصفحة (اختياري).</param>
    Task<string> GetLocalSubscribersAsync(
        string accountId,
        string? search = null,
        string? status = null,
        bool? expiring = null,
        int? page = null,
        int? count = null,
        CancellationToken cancellationToken = default);

    /// <summary>
    /// تقديم تصريح/بلنك شهري (POST /report/submit) معزول بـ accountId + companyId + ownerUserId.
    /// يعيد JSON خاماً (AgentReport). كتابة محلية.
    /// </summary>
    /// <param name="accountId">معرّف الحساب المملوك.</param>
    /// <param name="companyId">معرّف شركة المستخدم (عزل المستأجرين).</param>
    /// <param name="ownerUserId">معرّف المستخدم المالك.</param>
    /// <param name="declaredTotal">إجمالي المشتركين المُصرَّح به.</param>
    /// <param name="declaredActive">المشتركون الفعّالون المُصرَّح بهم.</param>
    /// <param name="note">ملاحظة اختيارية.</param>
    /// <param name="submittedBy">من قدّم التصريح (اختياري — للتدقيق).</param>
    Task<string> SubmitReportAsync(
        string accountId,
        string companyId,
        string ownerUserId,
        int declaredTotal,
        int declaredActive,
        string? note = null,
        string? submittedBy = null,
        CancellationToken cancellationToken = default);

    /// <summary>
    /// قائمة تصاريح/بلنكات الحساب من التخزين المحلي المعزول بـ accountId (POST /report/list) — بلا اعتماد.
    /// يعيد JSON خاماً (قائمة). قراءة محلية.
    /// </summary>
    Task<string> ListReportsAsync(
        string accountId, CancellationToken cancellationToken = default);

    /// <summary>
    /// المقاطعة/المطابقة بين المُصرَّح والفعلي (POST /reconciliation + accountId + اعتماد اختياري).
    /// يعيد JSON خاماً <c>{declared, actual, diff, verdict}</c>. قراءة (قد تستدعي الساس للفعلي).
    /// </summary>
    Task<string> GetReconciliationAsync(
        string accountId,
        string serverUrl, string username, string password,
        CancellationToken cancellationToken = default);

    // ==================== التذاكر (user-scoped — تخصّ الوكيل لا حساب ساس) ====================
    // كل نقاط التذاكر معزولة بـ (companyId + ownerUserId) من سياق المستخدم المُصادَق مباشرةً،
    // لا من حساب ساس ولا من إدخال المستخدم. لا اعتماد ساس ولا فكّ تشفير هنا إطلاقاً.
    //  - companyId  = شركة المستخدم الحالي (عزل المستأجرين).
    //  - ownerUserId= المستخدم المالك (الوكيل) — مفتاح ملكية التذكرة.
    //  - createdBy/author = هوية المستخدم خادمياً (تدقيق) — لا من العميل.
    // جميع الدوال تنادي نقاط Python عبر PostBodyForRawAsync وتعيد JSON خاماً.

    /// <summary>إحصاءات تذاكر الوكيل (POST /tickets/stats + companyId + ownerUserId). قراءة.</summary>
    Task<string> GetTicketsStatsAsync(
        string companyId,
        string ownerUserId,
        CancellationToken cancellationToken = default);

    /// <summary>
    /// قائمة تذاكر الوكيل (POST /tickets/list + companyId + ownerUserId + مرشّحات). قراءة.
    /// </summary>
    /// <param name="companyId">شركة المستخدم (عزل المستأجرين).</param>
    /// <param name="ownerUserId">المستخدم المالك (الوكيل).</param>
    /// <param name="status">تصفية بالحالة (اختياري).</param>
    /// <param name="category">تصفية بالتصنيف (اختياري).</param>
    /// <param name="search">نص بحث اختياري.</param>
    /// <param name="page">رقم الصفحة (اختياري).</param>
    /// <param name="count">حجم الصفحة (اختياري).</param>
    Task<string> GetTicketsListAsync(
        string companyId,
        string ownerUserId,
        string? status = null,
        string? category = null,
        string? search = null,
        int? page = null,
        int? count = null,
        CancellationToken cancellationToken = default);

    /// <summary>تفاصيل تذكرة محدّدة (POST /tickets/get + companyId + ownerUserId + ticketId). قراءة.</summary>
    Task<string> GetTicketAsync(
        string companyId,
        string ownerUserId,
        string ticketId,
        CancellationToken cancellationToken = default);

    /// <summary>
    /// إنشاء تذكرة جديدة (POST /tickets/create + companyId + ownerUserId + محتوى). كتابة.
    /// </summary>
    /// <param name="companyId">شركة المستخدم (عزل المستأجرين).</param>
    /// <param name="ownerUserId">المستخدم المالك (الوكيل).</param>
    /// <param name="subject">عنوان التذكرة.</param>
    /// <param name="body">نصّ التذكرة.</param>
    /// <param name="category">تصنيف اختياري.</param>
    /// <param name="priority">أولوية اختيارية.</param>
    /// <param name="subscriberRef">مرجع مشترك اختياري.</param>
    /// <param name="createdBy">من أنشأ التذكرة (من هوية المستخدم خادمياً — للتدقيق).</param>
    Task<string> CreateTicketAsync(
        string companyId,
        string ownerUserId,
        string subject,
        string body,
        string? category = null,
        string? priority = null,
        string? subscriberRef = null,
        string? createdBy = null,
        CancellationToken cancellationToken = default);

    /// <summary>
    /// إضافة ردّ على تذكرة (POST /tickets/reply + companyId + ownerUserId + ticketId + body). كتابة.
    /// </summary>
    /// <param name="companyId">شركة المستخدم (عزل المستأجرين).</param>
    /// <param name="ownerUserId">المستخدم المالك (الوكيل).</param>
    /// <param name="ticketId">معرّف التذكرة.</param>
    /// <param name="body">نصّ الردّ.</param>
    /// <param name="isInternal">هل الردّ داخلي (اختياري).</param>
    /// <param name="author">كاتب الردّ (من هوية المستخدم خادمياً — للتدقيق).</param>
    Task<string> ReplyTicketAsync(
        string companyId,
        string ownerUserId,
        string ticketId,
        string body,
        bool? isInternal = null,
        string? author = null,
        CancellationToken cancellationToken = default);

    /// <summary>
    /// تحديث تذكرة (POST /tickets/update + companyId + ownerUserId + ticketId + حقول). كتابة.
    /// </summary>
    /// <param name="companyId">شركة المستخدم (عزل المستأجرين).</param>
    /// <param name="ownerUserId">المستخدم المالك (الوكيل).</param>
    /// <param name="ticketId">معرّف التذكرة.</param>
    /// <param name="status">الحالة الجديدة (اختياري).</param>
    /// <param name="priority">الأولوية الجديدة (اختياري).</param>
    /// <param name="category">التصنيف الجديد (اختياري).</param>
    Task<string> UpdateTicketAsync(
        string companyId,
        string ownerUserId,
        string ticketId,
        string? status = null,
        string? priority = null,
        string? category = null,
        CancellationToken cancellationToken = default);

    // ==================== العقارات (Premises — user-scoped: شركة + مالك) ====================
    // كل نقاط العقارات معزولة بـ (companyId + ownerUserId) من سياق المستخدم المُصادَق مباشرةً،
    // لا من حساب ساس ولا من إدخال المستخدم. لا اعتماد ساس ولا فكّ تشفير هنا إطلاقاً.
    //  - companyId  = شركة المستخدم الحالي (عزل المستأجرين).
    //  - ownerUserId= المستخدم المالك — مفتاح ملكية العقار.
    // جميع الدوال تنادي نقاط Python (/premises/*) عبر PostBodyForRawAsync وتعيد JSON خاماً.

    /// <summary>
    /// قائمة عقارات الوكيل (POST /premises/list + companyId + ownerUserId + مرشّحات). قراءة.
    /// </summary>
    /// <param name="companyId">شركة المستخدم (عزل المستأجرين).</param>
    /// <param name="ownerUserId">المستخدم المالك.</param>
    /// <param name="search">نص بحث اختياري.</param>
    /// <param name="ownership">تصفية بنوع الملكية (اختياري).</param>
    /// <param name="ptype">تصفية بنوع العقار (اختياري).</param>
    /// <param name="page">رقم الصفحة (اختياري).</param>
    /// <param name="count">حجم الصفحة (اختياري).</param>
    Task<string> GetPremisesListAsync(
        string companyId,
        string ownerUserId,
        string? search = null,
        string? ownership = null,
        string? ptype = null,
        int? page = null,
        int? count = null,
        CancellationToken cancellationToken = default);

    /// <summary>تفاصيل عقار محدّد (POST /premises/get + companyId + ownerUserId + premises_id). قراءة.</summary>
    Task<string> GetPremisesAsync(
        string companyId,
        string ownerUserId,
        string premisesId,
        CancellationToken cancellationToken = default);

    /// <summary>مشتركو عقار محدّد (POST /premises/subscribers + companyId + ownerUserId + premises_id). قراءة.</summary>
    Task<string> GetPremisesSubscribersAsync(
        string companyId,
        string ownerUserId,
        string premisesId,
        CancellationToken cancellationToken = default);

    /// <summary>عقار مرتبط بمشترك (POST /premises/by-subscriber + companyId + ownerUserId + subscriber_ref). قراءة.</summary>
    Task<string> GetPremisesBySubscriberAsync(
        string companyId,
        string ownerUserId,
        string subscriberRef,
        CancellationToken cancellationToken = default);

    /// <summary>مرشّحو الربط (مشتركون قابلون للربط بعقار) (POST /premises/link-candidates + companyId + ownerUserId + search?). قراءة.</summary>
    Task<string> GetPremisesLinkCandidatesAsync(
        string companyId,
        string ownerUserId,
        string? search = null,
        CancellationToken cancellationToken = default);

    /// <summary>صورة عقار محدّد (POST /premises/photo/get + companyId + ownerUserId + premises_id). قراءة.</summary>
    Task<string> GetPremisesPhotoAsync(
        string companyId,
        string ownerUserId,
        string premisesId,
        CancellationToken cancellationToken = default);

    /// <summary>
    /// إنشاء عقار جديد (POST /premises/create + companyId + ownerUserId + حقول). كتابة.
    /// </summary>
    /// <param name="companyId">شركة المستخدم (عزل المستأجرين).</param>
    /// <param name="ownerUserId">المستخدم المالك.</param>
    /// <param name="governorate">المحافظة.</param>
    /// <param name="area">المنطقة.</param>
    /// <param name="landmark">أقرب نقطة دالّة.</param>
    /// <param name="lat">خط العرض (اختياري).</param>
    /// <param name="lon">خط الطول (اختياري).</param>
    /// <param name="phone">هاتف اختياري.</param>
    /// <param name="ownership">نوع الملكية (اختياري).</param>
    /// <param name="ptype">نوع العقار (اختياري).</param>
    /// <param name="createdBy">من أنشأ العقار (من هوية المستخدم خادمياً — للتدقيق).</param>
    Task<string> CreatePremisesAsync(
        string companyId,
        string ownerUserId,
        string governorate,
        string area,
        string landmark,
        double? lat = null,
        double? lon = null,
        string? phone = null,
        string? ownership = null,
        string? ptype = null,
        string? createdBy = null,
        CancellationToken cancellationToken = default);

    /// <summary>
    /// تعديل عقار (POST /premises/update + companyId + ownerUserId + premises_id + حقول). كتابة.
    /// كل الحقول اختيارية؛ يُحدَّث ما أُرسل فقط.
    /// </summary>
    Task<string> UpdatePremisesAsync(
        string companyId,
        string ownerUserId,
        string premisesId,
        string? governorate = null,
        string? area = null,
        string? landmark = null,
        double? lat = null,
        double? lon = null,
        string? phone = null,
        string? ownership = null,
        string? ptype = null,
        CancellationToken cancellationToken = default);

    /// <summary>حذف عقار (POST /premises/delete + companyId + ownerUserId + premises_id). كتابة.</summary>
    Task<string> DeletePremisesAsync(
        string companyId,
        string ownerUserId,
        string premisesId,
        CancellationToken cancellationToken = default);

    /// <summary>
    /// رفع صورة عقار (POST /premises/photo/upload + companyId + ownerUserId + premises_id + image_base64 + ext). كتابة.
    /// </summary>
    /// <param name="companyId">شركة المستخدم (عزل المستأجرين).</param>
    /// <param name="ownerUserId">المستخدم المالك.</param>
    /// <param name="premisesId">معرّف العقار.</param>
    /// <param name="imageBase64">الصورة مُرمَّزة base64 (بلا بادئة data:).</param>
    /// <param name="ext">امتداد الصورة (jpg/png/webp…).</param>
    Task<string> UploadPremisesPhotoAsync(
        string companyId,
        string ownerUserId,
        string premisesId,
        string imageBase64,
        string ext,
        CancellationToken cancellationToken = default);

    /// <summary>ربط مشترك بعقار (POST /premises/link + companyId + ownerUserId + premises_id + subscriber_ref). كتابة.</summary>
    Task<string> LinkPremisesSubscriberAsync(
        string companyId,
        string ownerUserId,
        string premisesId,
        string subscriberRef,
        CancellationToken cancellationToken = default);

    /// <summary>فكّ ربط مشترك عن عقار (POST /premises/unlink + companyId + ownerUserId + premises_id + subscriber_ref). كتابة.</summary>
    Task<string> UnlinkPremisesSubscriberAsync(
        string companyId,
        string ownerUserId,
        string premisesId,
        string subscriberRef,
        CancellationToken cancellationToken = default);

    // ==================== إدارة الوكلاء (للأدمن — company-scoped) ====================
    // نقطة أدمن على مستوى الشركة: تجلب المقاطعة/الحكم لكل حسابات ساس الشركة دفعةً واحدة.
    // على عكس نقاط الحساب المفردة، لا اعتماد ساس ولا فكّ تشفير هنا؛ الجسم {companyId, accountIds[]} فقط.
    //  - companyId  = شركة الأدمن الحالي (عزل المستأجرين) — من التوكن حصراً لا من إدخال المستخدم.
    //  - accountIds = كل معرّفات حسابات ساس ضمن الشركة (تُشتق خادمياً من قاعدة البيانات).
    // تعيد JSON خاماً <c>{items:[{account_id, declared_total, declared_active, actual_total, actual_active, diff, verdict, last_sync}]}</c>.

    /// <summary>
    /// ملخّص مقاطعة الوكلاء للأدمن على مستوى الشركة (POST /admin/agents-summary + companyId + accountIds[]).
    /// قراءة (لا تخزين، لا اعتماد ساس). تعيد لكل حساب المُصرَّح/الفعلي/الفرق/الحكم/آخر مزامنة.
    /// </summary>
    /// <param name="companyId">معرّف شركة الأدمن الحالي (عزل المستأجرين).</param>
    /// <param name="accountIds">معرّفات حسابات ساس ضمن الشركة (خادمياً — لا من العميل).</param>
    Task<string> GetAgentsSummaryAsync(
        string companyId,
        IEnumerable<string> accountIds,
        CancellationToken cancellationToken = default);
}
