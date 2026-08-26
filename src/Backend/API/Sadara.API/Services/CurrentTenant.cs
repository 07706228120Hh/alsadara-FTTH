using System.Security.Claims;
using Sadara.Application.Interfaces;

namespace Sadara.API.Services;

/// <summary>
/// تنفيذ <see cref="ICurrentTenant"/> عبر IHttpContextAccessor.
///
/// يقرأ هوية المستأجر من التوكن الحالي:
///  - الشركة: يدعم اسمَي الـ claim الموجودين في النظام ("company_id" و "companyId") لضمان التوافق.
///  - الدور: من ClaimTypes.Role أو "role"؛ إذا كان "SuperAdmin" => تجاوز كامل للعزل.
///
/// ملاحظة انتقالية: التوكنات القديمة الصادرة قبل إضافة claim الشركة (خصوصاً من تسجيل الدخول الرئيسي)
/// قد لا تحمل الشركة؛ يتم إثراؤها بـ company_id عبر حدث OnTokenValidated في Program.cs (استعلام واحد
/// عن شركة المستخدم من قاعدة البيانات) حتى لا تنكسر جلسات المستخدمين الحاليين أثناء الانتقال.
///
/// نموذج التجاوز (BypassTenantFilter): الفلتر المركزي إنما يعزل مستخدماً *مُصادَقاً* عن شركات غيره.
/// لا يمكن — منطقياً — عزل طلب لا يحمل هوية شركة أصلاً (لا يوجد مستأجر نُقيّده به). لذلك نتجاوز الفلتر في:
///   (1) غياب HttpContext كلياً — سياق نظام (خدمات خلفية/هجرات/seed).
///   (2) SuperAdmin — يصل لكل الشركات بالتصميم.
///   (3) مفتاح API داخلي صحيح (X-Api-Key) — تكامل موثوق (n8n) لشركة واحدة؛ الحماية على مستوى المفتاح.
///   (4) طلب غير مُصادَق (قبل تسجيل الدخول / anonymous) — لا يوجد توكن يشتق منه شركة؛ استعلامات الدخول
///       تُقيّد الشركة صراحةً (كود الشركة + بيانات الاعتماد)، فالتجاوز هنا لا يسرّب شيئاً بل يمنع «إخفاء
///       كل الصفوف» الذي كان يكسر تسجيل الدخول.
/// أما نقاط النهاية المحمية بـ [Authorize] فتُرفض بـ 401 قبل أن تصل إلى DbContext إن لم تحمل توكناً،
/// فلا يفتح البند (4) أي مسار مُصادَق.
/// </summary>
public class CurrentTenant : ICurrentTenant
{
    private readonly IHttpContextAccessor _httpContextAccessor;
    private readonly IConfiguration _configuration;

    private const string ApiKeyHeader = "X-Api-Key";

    public CurrentTenant(IHttpContextAccessor httpContextAccessor, IConfiguration configuration)
    {
        _httpContextAccessor = httpContextAccessor;
        _configuration = configuration;
    }

    private HttpContext? Http => _httpContextAccessor.HttpContext;
    private ClaimsPrincipal? User => Http?.User;

    public bool IsSuperAdmin
    {
        get
        {
            var role = User?.FindFirst(ClaimTypes.Role)?.Value
                    ?? User?.FindFirst("role")?.Value;
            return string.Equals(role, "SuperAdmin", StringComparison.OrdinalIgnoreCase);
        }
    }

    /// <summary>هل الطلب يحمل هوية مُصادَقة (توكن صالح)؟</summary>
    private bool IsAuthenticated => User?.Identity?.IsAuthenticated == true;

    /// <summary>
    /// هل يحمل الطلب مفتاح API داخلياً صحيحاً؟ (ترويسة X-Api-Key مطابقة لـ Security:InternalApiKey
    /// أو متغيّر البيئة SADARA_INTERNAL_API_KEY). يجب أن يكون المفتاح المُهيّأ غير فارغ حتى لا يُقبل مفتاح فارغ.
    /// </summary>
    private bool HasValidInternalApiKey
    {
        get
        {
            var http = Http;
            if (http is null) return false;

            var provided = http.Request.Headers[ApiKeyHeader].FirstOrDefault();
            if (string.IsNullOrEmpty(provided)) return false;

            var configured = _configuration["Security:InternalApiKey"]
                          ?? Environment.GetEnvironmentVariable("SADARA_INTERNAL_API_KEY");
            if (string.IsNullOrEmpty(configured)) return false;

            return string.Equals(provided, configured, StringComparison.Ordinal);
        }
    }

    /// <summary>
    /// تجاوز الفلتر المركزي. انظر توثيق الصنف أعلاه لتفصيل الحالات الأربع.
    /// </summary>
    public bool BypassTenantFilter =>
        Http is null
        || IsSuperAdmin
        || HasValidInternalApiKey
        || !IsAuthenticated;

    public Guid? CompanyId
    {
        get
        {
            var raw = User?.FindFirst("company_id")?.Value
                   ?? User?.FindFirst("companyId")?.Value;
            return Guid.TryParse(raw, out var id) ? id : (Guid?)null;
        }
    }

    /// <summary>
    /// الشركة الافتراضية للمنصّة من الإعداد <c>Tenancy:DefaultCompanyId</c>.
    /// إذا لم تُضبط (أو قيمة غير صالحة) تُرجع null ⇒ لا يجري أي خَتم (سلوك محايد).
    /// </summary>
    public Guid? DefaultCompanyId
    {
        get
        {
            var raw = _configuration["Tenancy:DefaultCompanyId"];
            return Guid.TryParse(raw, out var id) ? id : (Guid?)null;
        }
    }

    /// <summary>
    /// علَم تفعيل العزل — يُقرأ من <c>Tenancy:EnforceIsolation</c> أو متغيّر البيئة
    /// <c>SADARA_ENFORCE_ISOLATION</c>. الافتراضي false (معطّل) ⇒ نشر الثنائي محايد.
    /// </summary>
    public bool EnforceIsolation
    {
        get
        {
            var raw = _configuration["Tenancy:EnforceIsolation"]
                   ?? Environment.GetEnvironmentVariable("SADARA_ENFORCE_ISOLATION");
            return bool.TryParse(raw, out var on) && on;
        }
    }
}
