using System.Text.Json;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;
using Sadara.Application.Interfaces;

namespace Sadara.Infrastructure.Services.Ftth;

/// <summary>
/// تنفيذ <see cref="IFtthCommissionClient"/> — نداءات نظام FTTH (admin.ftth.iq) لحارس «تحويل العمولة».
///
/// نُقِل هذا المنطق حرفياً من <c>LinkedAccountsController</c> (نفس الترويسات/قائمة السماح/تعطيل إعادة التوجيه/
/// التحقق من مقطع المسار) دون أي تغيير سلوكي؛ الغرض جعل نداءات FTTH قابلة للحقن لتغطية الحارس المالي بالاختبار.
///
/// ⚠️ أمن:
///  - قائمة سماح المضيفات (<c>Ftth:AllowedHosts</c>، افتراضي admin.ftth.iq) تُفرَض قبل أي نداء شبكة (إغلاق SSRF).
///  - <c>AllowAutoRedirect=false</c> لمنع التفاف SSRF عبر 3xx نحو عناوين داخلية.
///  - لا يُسجَّل أي اعتماد ولا رمز وصول في أي log.
/// </summary>
public class FtthCommissionClient : IFtthCommissionClient
{
    /// <summary>المضيف الافتراضي لنظام FTTH عند غياب ServerUrl.</summary>
    private const string DefaultFtthBaseUrl = "https://admin.ftth.iq";

    private readonly IConfiguration _configuration;
    private readonly ILogger<FtthCommissionClient> _logger;

    public FtthCommissionClient(IConfiguration configuration, ILogger<FtthCommissionClient> logger)
    {
        _configuration = configuration;
        _logger = logger;
    }

    // ==================== أمان: قائمة سماح مضيفات FTTH (إغلاق SSRF) ====================

    /// <summary>
    /// يتحقّق أنّ عنوان خادم FTTH مسموح به لإغلاق SSRF:
    ///  - يُحلّل كـ Uri مطلق صحيح.
    ///  - المخطّط https حصراً (رفض http وأي مخطّط آخر).
    ///  - المضيف (Host وحده) ضمن قائمة السماح (Ftth:AllowedHosts، افتراضي admin.ftth.iq) — غير حسّاس لحالة الأحرف.
    ///  - بلا UserInfo (رفض "user:pass@host").
    /// </summary>
    private bool IsAllowedFtthServerUrl(string? serverUrl)
    {
        if (string.IsNullOrWhiteSpace(serverUrl))
            return false;

        if (!Uri.TryCreate(serverUrl.Trim(), UriKind.Absolute, out var uri))
            return false;

        if (!string.Equals(uri.Scheme, Uri.UriSchemeHttps, StringComparison.OrdinalIgnoreCase))
            return false;

        if (!string.IsNullOrEmpty(uri.UserInfo))
            return false;

        var allowedHosts = _configuration.GetSection("Ftth:AllowedHosts").Get<string[]>();
        if (allowedHosts == null || allowedHosts.Length == 0)
            allowedHosts = new[] { "admin.ftth.iq" };

        return allowedHosts.Any(h => string.Equals(h, uri.Host, StringComparison.OrdinalIgnoreCase));
    }

    /// <summary>يتحقّق أنّ مقطع المسار (partnerId) آمن للاستخدام في URL: أحرف/أرقام/شرطة فقط، ≤64.</summary>
    private static bool IsSafePathSegment(string? s)
        => !string.IsNullOrWhiteSpace(s) && s.Length <= 64 && s.All(ch => char.IsLetterOrDigit(ch) || ch == '-');

    /// <summary>
    /// يبني <see cref="HttpClient"/> مُصادَقاً لنظام FTTH بنفس ترويسات WAF المطلوبة + Bearer.
    /// تعطيل إعادة التوجيه التلقائية (إغلاق التفاف SSRF عبر 3xx). المستدعي يتولّى التخلّص (using).
    /// </summary>
    private static HttpClient BuildFtthAuthedClient(string accessToken)
    {
        var handler = new HttpClientHandler { AllowAutoRedirect = false };
        var client = new HttpClient(handler) { Timeout = TimeSpan.FromSeconds(20) };
        client.DefaultRequestHeaders.Add("Authorization", $"Bearer {accessToken}");
        client.DefaultRequestHeaders.Add("Origin", "https://admin.ftth.iq");
        client.DefaultRequestHeaders.Add("Referer", "https://admin.ftth.iq/");
        client.DefaultRequestHeaders.Add("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64)");
        client.DefaultRequestHeaders.Add("x-client-app", "53d57a7f-3f89-4e9d-873b-3d071bc6dd9f");
        client.DefaultRequestHeaders.Add("x-user-role", "0");
        return client;
    }

    /// <summary>
    /// تسجيل دخول خادمي إلى نظام FTTH (admin.ftth.iq) بنفس ترويسات WAF المطلوبة.
    /// يعيد (نجاح، access_token، refresh_token، رسالة خطأ). لا يُسجَّل أي سرّ هنا.
    /// </summary>
    public async Task<FtthLoginResult> LoginAsync(
        string serverUrl, string username, string password, CancellationToken ct)
    {
        var baseUrl = string.IsNullOrWhiteSpace(serverUrl) ? DefaultFtthBaseUrl : serverUrl.TrimEnd('/');

        // دفاع بالعمق (إغلاق SSRF): لا نُجري أي نداء شبكة إن لم يمرّ العنوان قائمة السماح.
        if (!IsAllowedFtthServerUrl(baseUrl))
            return new FtthLoginResult(false, null, null, "عنوان خادم FTTH غير مسموح");

        try
        {
            // تعطيل إعادة التوجيه التلقائية لمنع التفاف SSRF عبر 3xx نحو عناوين داخلية.
            using var handler = new HttpClientHandler { AllowAutoRedirect = false };
            using var client = new HttpClient(handler) { Timeout = TimeSpan.FromSeconds(20) };

            // FTTH WAF يتطلب هذه الترويسات — بدونها يرفض الطلب.
            client.DefaultRequestHeaders.Add("Origin", "https://admin.ftth.iq");
            client.DefaultRequestHeaders.Add("Referer", "https://admin.ftth.iq/");
            client.DefaultRequestHeaders.Add("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64)");
            client.DefaultRequestHeaders.Add("x-client-app", "53d57a7f-3f89-4e9d-873b-3d071bc6dd9f");
            client.DefaultRequestHeaders.Add("x-user-role", "0");

            var content = new FormUrlEncodedContent(new[]
            {
                new KeyValuePair<string, string>("username", username),
                new KeyValuePair<string, string>("password", password),
                new KeyValuePair<string, string>("grant_type", "password"),
                new KeyValuePair<string, string>("scope", "openid profile"),
            });

            var response = await client.PostAsync($"{baseUrl}/api/auth/Contractor/token", content, ct);
            if (!response.IsSuccessStatusCode)
                return new FtthLoginResult(false, null, null, $"فشل الاتصال بنظام FTTH: {(int)response.StatusCode}");

            var json = await response.Content.ReadAsStringAsync(ct);
            using var doc = JsonDocument.Parse(json);
            var root = doc.RootElement;

            string? access = root.TryGetProperty("access_token", out var at) && at.ValueKind == JsonValueKind.String
                ? at.GetString() : null;
            string? refresh = root.TryGetProperty("refresh_token", out var rt) && rt.ValueKind == JsonValueKind.String
                ? rt.GetString() : null;

            if (string.IsNullOrEmpty(access))
                return new FtthLoginResult(false, null, null, "لم يُعِد خادم FTTH رمز وصول صالحاً");

            return new FtthLoginResult(true, access, refresh, null);
        }
        catch (OperationCanceledException)
        {
            throw;
        }
        catch (Exception ex)
        {
            // لا نسجّل الاعتماد — رسالة الاستثناء فقط.
            _logger.LogWarning(ex, "تعذّر الاتصال بنظام FTTH أثناء تسجيل الدخول/التحقق");
            return new FtthLoginResult(false, null, null, "تعذّر الاتصال بنظام FTTH");
        }
    }

    /// <summary>يجلب partnerId الحيّ من FTTH عبر current-user (model.self.id). يعيد null عند الفشل.</summary>
    public async Task<string?> GetPartnerIdAsync(string serverUrl, string accessToken, CancellationToken ct)
    {
        var baseUrl = string.IsNullOrWhiteSpace(serverUrl) ? DefaultFtthBaseUrl : serverUrl.TrimEnd('/');
        if (!IsAllowedFtthServerUrl(baseUrl)) return null; // دفاع بالعمق (إغلاق SSRF)

        try
        {
            using var client = BuildFtthAuthedClient(accessToken);
            var resp = await client.GetAsync($"{baseUrl}/api/current-user", ct);
            if (!resp.IsSuccessStatusCode) return null;

            var json = await resp.Content.ReadAsStringAsync(ct);
            using var doc = JsonDocument.Parse(json);
            if (doc.RootElement.TryGetProperty("model", out var model)
                && model.TryGetProperty("self", out var self)
                && self.TryGetProperty("id", out var idEl))
            {
                return idEl.ValueKind switch
                {
                    JsonValueKind.String => idEl.GetString(),
                    JsonValueKind.Number => idEl.GetRawText(),
                    _ => null
                };
            }
            return null;
        }
        catch (OperationCanceledException) { throw; }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "تعذّر جلب partnerId من نظام FTTH");
            return null;
        }
    }

    /// <summary>يجلب رصيد العمولة الحيّ من FTTH (model.commission). يعيد null عند الفشل.</summary>
    public async Task<decimal?> GetCommissionBalanceAsync(string serverUrl, string accessToken, string partnerId, CancellationToken ct)
    {
        var baseUrl = string.IsNullOrWhiteSpace(serverUrl) ? DefaultFtthBaseUrl : serverUrl.TrimEnd('/');
        if (!IsAllowedFtthServerUrl(baseUrl)) return null;
        if (!IsSafePathSegment(partnerId)) return null; // partnerId جزء من المسار — نقبل معرّفات بسيطة فقط

        try
        {
            using var client = BuildFtthAuthedClient(accessToken);
            var resp = await client.GetAsync($"{baseUrl}/api/partners/{partnerId}/wallets/balance", ct);
            if (!resp.IsSuccessStatusCode) return null;

            var json = await resp.Content.ReadAsStringAsync(ct);
            using var doc = JsonDocument.Parse(json);
            if (doc.RootElement.TryGetProperty("model", out var model)
                && model.TryGetProperty("commission", out var c))
            {
                if (c.ValueKind == JsonValueKind.Number && c.TryGetDecimal(out var dn)) return dn;
                if (c.ValueKind == JsonValueKind.String && decimal.TryParse(c.GetString(), out var ds)) return ds;
            }
            return null;
        }
        catch (OperationCanceledException) { throw; }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "تعذّر جلب رصيد العمولة من نظام FTTH");
            return null;
        }
    }

    /// <summary>
    /// ينفّذ تحويل العمولة لدى FTTH (partners/{partnerId}/wallets/transfer-commission) مع تمرير Idempotency-Key/requestId.
    /// يعيد (نجاح، رمز HTTP، رسالة خطأ). لا يُسجَّل أي سرّ هنا.
    /// </summary>
    public async Task<FtthTransferResult> TransferAsync(
        string serverUrl, string accessToken, string partnerId, long amount, string requestId, CancellationToken ct)
    {
        var baseUrl = string.IsNullOrWhiteSpace(serverUrl) ? DefaultFtthBaseUrl : serverUrl.TrimEnd('/');
        if (!IsAllowedFtthServerUrl(baseUrl)) return new FtthTransferResult(false, 0, "عنوان خادم FTTH غير مسموح");
        if (!IsSafePathSegment(partnerId)) return new FtthTransferResult(false, 0, "معرّف الشريك غير صالح");

        try
        {
            using var client = BuildFtthAuthedClient(accessToken);
            client.DefaultRequestHeaders.Add("Idempotency-Key", requestId);

            var payload = JsonSerializer.Serialize(new { amount = amount.ToString(), requestId });
            using var content = new StringContent(payload, System.Text.Encoding.UTF8, "application/json");

            var resp = await client.PostAsync($"{baseUrl}/api/partners/{partnerId}/wallets/transfer-commission", content, ct);
            var code = (int)resp.StatusCode;
            if (resp.IsSuccessStatusCode) return new FtthTransferResult(true, code, null);
            return new FtthTransferResult(false, code, $"فشل تحويل العمولة لدى نظام FTTH: {code}");
        }
        catch (OperationCanceledException) { throw; }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "تعذّر الاتصال بنظام FTTH أثناء تحويل العمولة");
            return new FtthTransferResult(false, 0, "تعذّر الاتصال بنظام FTTH");
        }
    }
}
