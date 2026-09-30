using System.Net.Http.Json;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;
using Sadara.Application.Interfaces;

namespace Sadara.Infrastructure.Services.Sas;

/// <summary>
/// تنفيذ <see cref="ISasServiceClient"/> عبر typed HttpClient يخاطب خدمة الساس الداخلية
/// (Python sidecar) المحصورة على 127.0.0.1.
///
/// الإعداد:
///  - العنوان الأساس من <c>SasService:BaseUrl</c> (افتراضي <c>http://127.0.0.1:8100</c>).
///  - السرّ الداخلي من <c>SasService:InternalSecret</c> أو متغيّر البيئة <c>SADARA_SAS_INTERNAL_SECRET</c>.
///    fail-closed: خارج بيئة Development، إن لم يُضبط السرّ يُرفض الطلب قبل إرسال أي اعتماد
///    (لا تُرسَل كلمة مرور صريحة بلا مصادقة داخلية). في Development فقط يُسمح بالإرسال بلا رأس مع تحذير.
///
/// ⚠️ أمن: الاعتماد يُرسَل في جسم الطلب إلى localhost فقط ولا يُسجَّل في أي log.
/// </summary>
public class SasServiceClient : ISasServiceClient
{
    private const string InternalSecretHeader = "X-Internal-Secret";
    private const string DefaultBaseUrl = "http://127.0.0.1:8100";

    private readonly HttpClient _httpClient;
    private readonly ILogger<SasServiceClient> _logger;
    private readonly string _internalSecret;
    private readonly bool _isDevelopment;

    public SasServiceClient(
        HttpClient httpClient,
        IConfiguration configuration,
        ILogger<SasServiceClient> logger)
    {
        _httpClient = httpClient;
        _logger = logger;

        // اسم البيئة يُقرأ من الإعداد (يوفّره WebApplicationBuilder عبر متغيّرات البيئة القياسية).
        // نتجنّب حقن IHostEnvironment لعدم إضافة تبعية حزمة جديدة لهذا المشروع.
        var environmentName = configuration["ASPNETCORE_ENVIRONMENT"]
                              ?? configuration["DOTNET_ENVIRONMENT"]
                              ?? "Production";
        _isDevelopment = string.Equals(environmentName, "Development", StringComparison.OrdinalIgnoreCase);

        var baseUrl = configuration["SasService:BaseUrl"] ?? DefaultBaseUrl;
        if (_httpClient.BaseAddress is null)
            _httpClient.BaseAddress = new Uri(baseUrl);
        if (_httpClient.Timeout == default || _httpClient.Timeout == TimeSpan.FromSeconds(100))
            _httpClient.Timeout = TimeSpan.FromSeconds(20);

        _internalSecret = configuration["SasService:InternalSecret"]
                          ?? Environment.GetEnvironmentVariable("SADARA_SAS_INTERNAL_SECRET")
                          ?? string.Empty;
    }

    public async Task<SasLoginResult> LoginAsync(
        string serverUrl,
        string username,
        string password,
        CancellationToken cancellationToken = default)
    {
        try
        {
            var payload = new { serverUrl, username, password };
            using var request = BuildRequest(HttpMethod.Post, "/login", payload);
            using var response = await _httpClient.SendAsync(request, cancellationToken);

            var body = await response.Content.ReadAsStringAsync(cancellationToken);
            if (!response.IsSuccessStatusCode)
            {
                _logger.LogWarning("فشل تسجيل الدخول لخدمة الساس (الحالة {Status})", (int)response.StatusCode);
                return new SasLoginResult(false, null, "تعذّر تسجيل الدخول لنظام الساس");
            }

            // العقد المبدئي: نعيد نجاحاً والجسم الخام كمقبض جلسة (يُنقّح في المرحلة 3).
            return new SasLoginResult(true, body, "تم تسجيل الدخول");
        }
        catch (SasServiceUnavailableException)
        {
            // fail-closed (سرّ داخلي غير مضبوط خارج Development) — تُترجمها البوّابة إلى 503.
            throw;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ أثناء الاتصال بخدمة الساس لتسجيل الدخول");
            return new SasLoginResult(false, null, "خدمة الساس غير متاحة حالياً");
        }
    }

    public Task<string> GetDashboardAsync(
        string serverUrl,
        string username,
        string password,
        CancellationToken cancellationToken = default)
        => PostForRawAsync("/dashboard", serverUrl, username, password, null, cancellationToken);

    public Task<string> GetSubscribersAsync(
        string serverUrl,
        string username,
        string password,
        IDictionary<string, string?>? query = null,
        CancellationToken cancellationToken = default)
        => PostForRawAsync("/subscribers", serverUrl, username, password, query, cancellationToken);

    public Task<string> GetReportAsync(
        string serverUrl,
        string username,
        string password,
        IDictionary<string, string?>? query = null,
        CancellationToken cancellationToken = default)
        => PostForRawAsync("/report", serverUrl, username, password, query, cancellationToken);

    public Task<string> GetPackagesAsync(
        string serverUrl,
        string username,
        string password,
        CancellationToken cancellationToken = default)
        => PostForRawAsync("/packages", serverUrl, username, password, null, cancellationToken);

    public Task<string> GetFinanceAsync(
        string serverUrl,
        string username,
        string password,
        CancellationToken cancellationToken = default)
        => PostForRawAsync("/finance", serverUrl, username, password, null, cancellationToken);

    public Task<string> GetHealthAsync(
        string serverUrl,
        string username,
        string password,
        CancellationToken cancellationToken = default)
        // ملاحظة: مسار Python هو /system-health (لأن /health محجوز لفحص الحياة بلا مصادقة)
        => PostForRawAsync("/system-health", serverUrl, username, password, null, cancellationToken);

    public Task<string> GetRenewalCandidatesAsync(
        string serverUrl,
        string username,
        string password,
        int? days = null,
        string? query = null,
        CancellationToken cancellationToken = default)
        => PostBodyForRawAsync(
            "/renewal/candidates",
            new
            {
                serverUrl,
                username,
                password,
                days,
                query
            },
            cancellationToken);

    public Task<string> BulkRenewAsync(
        string serverUrl,
        string username,
        string password,
        IEnumerable<string> subscriberIds,
        int months,
        string? profileId = null,
        bool dryRun = false,
        CancellationToken cancellationToken = default)
        => PostBodyForRawAsync(
            "/renewal/bulk",
            new
            {
                serverUrl,
                username,
                password,
                subscriberIds = subscriberIds?.ToArray() ?? Array.Empty<string>(),
                months,
                profileId,
                dryRun
            },
            cancellationToken);

    // ==================== العقد الموحّد الكامل لعمليات الساس ====================
    // جميع الدوال أدناه تنادي نقاط خدمة Python المقابلة عبر PostBodyForRawAsync
    // (تمرّر الاعتماد + الوسائط في الجسم، وتعيد JSON خاماً). لا تُسجَّل الأسرار.

    // ---------- المشتركون: قراءات ----------

    public Task<string> GetUserDetailAsync(
        string serverUrl, string username, string password,
        string uid, CancellationToken cancellationToken = default)
        => PostBodyForRawAsync("/users/detail",
            new { serverUrl, username, password, uid }, cancellationToken);

    public Task<string> GetUsersOverviewAsync(
        string serverUrl, string username, string password,
        CancellationToken cancellationToken = default)
        => PostBodyForRawAsync("/users/overview",
            new { serverUrl, username, password }, cancellationToken);

    public Task<string> GetUserHistoryAsync(
        string serverUrl, string username, string password,
        string uid, CancellationToken cancellationToken = default)
        => PostBodyForRawAsync("/users/history",
            new { serverUrl, username, password, uid }, cancellationToken);

    public Task<string> GetUserExtendDataAsync(
        string serverUrl, string username, string password,
        string uid, CancellationToken cancellationToken = default)
        => PostBodyForRawAsync("/users/extend-data",
            new { serverUrl, username, password, uid }, cancellationToken);

    // ---------- المشتركون: كتابات ----------

    public Task<string> UserActionAsync(
        string serverUrl, string username, string password,
        string uid, string action, object? parameters = null,
        CancellationToken cancellationToken = default)
        => PostBodyForRawAsync("/users/action",
            new { serverUrl, username, password, uid, action, @params = parameters }, cancellationToken);

    public Task<string> UsersBulkActionAsync(
        string serverUrl, string username, string password,
        IEnumerable<string> uids, string action, object? parameters = null,
        CancellationToken cancellationToken = default)
        => PostBodyForRawAsync("/users/bulk-action",
            new { serverUrl, username, password, uids = uids?.ToArray() ?? Array.Empty<string>(), action, @params = parameters }, cancellationToken);

    public Task<string> CreateUserAsync(
        string serverUrl, string username, string password,
        object payload, CancellationToken cancellationToken = default)
        => PostBodyForRawAsync("/users/create",
            new { serverUrl, username, password, payload }, cancellationToken);

    public Task<string> UpdateUserAsync(
        string serverUrl, string username, string password,
        string uid, object payload, CancellationToken cancellationToken = default)
        => PostBodyForRawAsync("/users/update",
            new { serverUrl, username, password, uid, payload }, cancellationToken);

    public Task<string> DeleteUserAsync(
        string serverUrl, string username, string password,
        string uid, CancellationToken cancellationToken = default)
        => PostBodyForRawAsync("/users/delete",
            new { serverUrl, username, password, uid }, cancellationToken);

    public Task<string> GetUserRefundDataAsync(
        string serverUrl, string username, string password,
        string uid, CancellationToken cancellationToken = default)
        => PostBodyForRawAsync("/users/refund-data",
            new { serverUrl, username, password, uid }, cancellationToken);

    public Task<string> RefundUserAsync(
        string serverUrl, string username, string password,
        string uid, CancellationToken cancellationToken = default)
        => PostBodyForRawAsync("/users/refund",
            new { serverUrl, username, password, uid }, cancellationToken);

    // ---------- المتصلون ----------

    public Task<string> GetOnlineAsync(
        string serverUrl, string username, string password,
        CancellationToken cancellationToken = default)
        => PostBodyForRawAsync("/online",
            new { serverUrl, username, password }, cancellationToken);

    // ---------- الوكلاء/المدراء ----------

    public Task<string> GetManagersAsync(
        string serverUrl, string username, string password,
        CancellationToken cancellationToken = default)
        => PostBodyForRawAsync("/managers",
            new { serverUrl, username, password }, cancellationToken);

    public Task<string> ManagerActionAsync(
        string serverUrl, string username, string password,
        string mid, string action, object? parameters = null,
        CancellationToken cancellationToken = default)
        => PostBodyForRawAsync("/managers/action",
            new { serverUrl, username, password, mid, action, @params = parameters }, cancellationToken);

    public Task<string> DeleteManagerAsync(
        string serverUrl, string username, string password,
        string mid, CancellationToken cancellationToken = default)
        => PostBodyForRawAsync("/managers/delete",
            new { serverUrl, username, password, mid }, cancellationToken);

    // ---------- البروكسي العام لـ SAS ----------

    public Task<string> SasGetAsync(
        string serverUrl, string username, string password,
        string path, CancellationToken cancellationToken = default)
        => PostBodyForRawAsync("/sas/get",
            new { serverUrl, username, password, path }, cancellationToken);

    public Task<string> SasPostAsync(
        string serverUrl, string username, string password,
        string path, object? payload = null, CancellationToken cancellationToken = default)
        => PostBodyForRawAsync("/sas/post",
            new { serverUrl, username, password, path, payload }, cancellationToken);

    /// <summary>
    /// ينادي مسار خدمة الساس ممرِّراً الاعتماد + وسائط الاستعلام في الجسم، ويعيد JSON خاماً.
    /// عند فشل الاتصال يرمي <see cref="SasServiceUnavailableException"/> لتترجمها البوّابة إلى 502/503.
    /// </summary>
    private async Task<string> PostForRawAsync(
        string path,
        string serverUrl,
        string username,
        string password,
        IDictionary<string, string?>? query,
        CancellationToken cancellationToken)
    {
        try
        {
            var payload = new
            {
                serverUrl,
                username,
                password,
                query = query ?? new Dictionary<string, string?>()
            };
            using var request = BuildRequest(HttpMethod.Post, path, payload);
            using var response = await _httpClient.SendAsync(request, cancellationToken);

            var body = await response.Content.ReadAsStringAsync(cancellationToken);
            if (!response.IsSuccessStatusCode)
            {
                _logger.LogWarning("فشل نداء خدمة الساس {Path} (الحالة {Status})", path, (int)response.StatusCode);
                throw new SasServiceUnavailableException("تعذّر جلب البيانات من خدمة الساس");
            }

            return body;
        }
        catch (SasServiceUnavailableException)
        {
            throw;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ أثناء الاتصال بخدمة الساس {Path}", path);
            throw new SasServiceUnavailableException("خدمة الساس غير متاحة حالياً");
        }
    }

    /// <summary>
    /// ينادي مسار خدمة الساس بجسم JSON مُخصّص (يتضمّن الاعتماد + وسائط العملية) ويعيد JSON خاماً.
    /// يُستخدم للعمليات ذات الجسم غير النمطي (مرشّحو التجديد/التجديد الجماعي).
    /// عند فشل الاتصال يرمي <see cref="SasServiceUnavailableException"/> لتترجمها البوّابة إلى 502/503.
    /// ⚠️ أمن: الاعتماد ضمن الجسم يُرسَل إلى localhost فقط ولا يُسجَّل في أي log.
    /// </summary>
    private async Task<string> PostBodyForRawAsync(
        string path,
        object payload,
        CancellationToken cancellationToken)
    {
        try
        {
            using var request = BuildRequest(HttpMethod.Post, path, payload);
            using var response = await _httpClient.SendAsync(request, cancellationToken);

            var body = await response.Content.ReadAsStringAsync(cancellationToken);
            if (!response.IsSuccessStatusCode)
            {
                _logger.LogWarning("فشل نداء خدمة الساس {Path} (الحالة {Status})", path, (int)response.StatusCode);
                throw new SasServiceUnavailableException("تعذّر تنفيذ العملية عبر خدمة الساس");
            }

            return body;
        }
        catch (SasServiceUnavailableException)
        {
            throw;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ أثناء الاتصال بخدمة الساس {Path}", path);
            throw new SasServiceUnavailableException("خدمة الساس غير متاحة حالياً");
        }
    }

    /// <summary>يبني طلباً مع رأس السرّ الداخلي (إن وُجد) وجسم JSON.</summary>
    /// <remarks>
    /// fail-closed: إن كان السرّ الداخلي فارغاً وخارج بيئة Development نرمي
    /// <see cref="SasServiceUnavailableException"/> قبل تكوين أي طلب يحمل اعتماداً،
    /// حتى لا تُرسَل كلمة مرور صريحة بلا مصادقة داخلية. في Development فقط يُسمح بالإرسال
    /// بلا رأس مع تحذير log (بلا كشف السرّ أو الاعتماد).
    /// </remarks>
    private HttpRequestMessage BuildRequest(HttpMethod method, string path, object payload)
    {
        if (string.IsNullOrEmpty(_internalSecret))
        {
            if (!_isDevelopment)
                throw new SasServiceUnavailableException(
                    "خدمة الساس غير مُهيّأة بأمان (السرّ الداخلي غير مضبوط) — تعذّر إرسال الطلب.");

            _logger.LogWarning(
                "السرّ الداخلي لخدمة الساس غير مضبوط — يُرسَل الطلب بلا رأس مصادقة (مسموح في Development فقط).");
        }

        var request = new HttpRequestMessage(method, path)
        {
            Content = JsonContent.Create(payload)
        };
        if (!string.IsNullOrEmpty(_internalSecret))
            request.Headers.Add(InternalSecretHeader, _internalSecret);
        return request;
    }
}

/// <summary>
/// استثناء يشير إلى تعذّر الوصول لخدمة الساس الداخلية — تترجمه البوّابة إلى 502/503.
/// </summary>
public class SasServiceUnavailableException : Exception
{
    public SasServiceUnavailableException(string message) : base(message) { }
}
