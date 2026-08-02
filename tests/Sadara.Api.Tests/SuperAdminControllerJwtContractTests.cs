using System.IdentityModel.Tokens.Jwt;
using System.Reflection;
using System.Security.Claims;
using System.Text;
using FluentAssertions;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.IdentityModel.Tokens;
using Sadara.API.Controllers;
using Sadara.Api.Tests.Fakes;
using Sadara.Domain.Entities;
using Sadara.Domain.Enums;
using Sadara.Infrastructure.Identity;
using Xunit;

namespace Sadara.Api.Tests;

/// <summary>
/// إثبات عقد التوكن للموضع C بعد توحيده على المُوقّع المشترك IJwtTokenSigner
/// (نفس ما فُعِل بالمواضع A/B/D). الموضع C هو:
///   SuperAdminController.GenerateJwtToken(User) — private، توكن مدير النظام العابر للشركات، مدّته 24 ساعة.
///
/// يُستدعى مباشرة عبر reflection على نسخة حقيقية من الكنترولر، بحقن تبعيات وهمية،
/// ومُوقّع JwtTokenSigner حقيقي عند flag OFF (HS256؛ Jwt:Algorithm=HS256 صراحةً هنا).
///
/// معزول تماماً عن قاعدة البيانات والـ web host:
/// - IUnitOfWork = FakeUnitOfWork (لا يُلمَس من GenerateJwtToken).
/// - ILogger = NullLogger.
/// - HttpClient = نسخة عادية (لا يُلمَس من GenerateJwtToken).
/// - IConfiguration = InMemory (Jwt:Secret ثابت + Issuer/Audience + Jwt:Algorithm=HS256).
/// - IJwtTokenSigner = new JwtTokenSigner(config) الحقيقي بنفس الإعداد.
///
/// الحارس الأمني الأهم: توكن مدير النظام **بلا أي claim باسم company_*** (مدير النظام عابر للشركات، بلا مستأجر).
///
/// السرّ أدناه قيمة اختبار محلية غير مرتبطة بأي سرّ إنتاجي.
/// </summary>
public class SuperAdminControllerJwtContractTests
{
    private const string TestSecret = "unit-test-only-hs256-secret-key-do-not-use-in-prod-0123456789";
    private const string Issuer = "sadara-test-issuer";
    private const string Audience = "sadara-test-audience";

    // القيم الاحتياطية المضمّنة في الكنترولر عند غياب Jwt:Issuer/Jwt:Audience.
    private const string FallbackIssuer = "SadaraPlatform";
    private const string FallbackAudience = "SadaraClients";

    // الست claims التي يبنيها الموضع C بالضبط — لا أكثر ولا أقل، ولا أي company_*.
    // ملاحظة: C غير شرطي على Email (يكتب user.Email ?? "" ⇒ claim موجود دائماً).
    private static readonly string[] SuperAdminClaimTypesC =
    {
        ClaimTypes.NameIdentifier, ClaimTypes.Name, ClaimTypes.Email,
        ClaimTypes.MobilePhone, ClaimTypes.Role, "role_id"
    };

    // حارس التسريب: أي claim باسم يطابق إحدى هذه الكلمات يُعدّ حسّاساً غير متوقّع.
    private static readonly string[] SensitiveTokens =
    {
        "password", "secret", "hash", "apikey", "api_key", "refresh", "otp", "pin", "credential"
    };

    // ============ بناء الإعداد والمُوقّع الحقيقي ============

    private static IConfiguration BuildConfig(
        string? secret = TestSecret,
        string? issuer = Issuer,
        string? audience = Audience)
    {
        var settings = new Dictionary<string, string?>();
        if (secret is not null) settings["Jwt:Secret"] = secret;
        if (issuer is not null) settings["Jwt:Issuer"] = issuer;
        if (audience is not null) settings["Jwt:Audience"] = audience;
        // flag OFF صراحةً ⇒ HS256.
        settings["Jwt:Algorithm"] = "HS256";
        return new ConfigurationBuilder().AddInMemoryCollection(settings).Build();
    }

    private static JwtTokenSigner BuildSigner(IConfiguration config) => new(config);

    // ============ بناء الكنترولر مباشرة (بلا web host) ============

    private static SuperAdminController BuildController(IConfiguration config)
        => new(
            new FakeUnitOfWork(new FakeCompanyRepository()),
            config,
            NullLogger<SuperAdminController>.Instance,
            new HttpClient(),
            BuildSigner(config));

    /// <summary>يستدعي private GenerateJwtToken(User) عبر reflection ويعيد التوكن المُسلسل.</summary>
    private static string InvokeGenerate(SuperAdminController controller, User user)
    {
        var method = controller.GetType().GetMethod(
            "GenerateJwtToken",
            BindingFlags.NonPublic | BindingFlags.Instance,
            binder: null,
            types: new[] { typeof(User) },
            modifiers: null);
        method.Should().NotBeNull("GenerateJwtToken(User) يجب أن يوجد كدالة نسخة خاصّة بمعامل واحد");

        var token = method!.Invoke(controller, new object?[] { user });
        token.Should().BeOfType<string>();
        return (string)token!;
    }

    private static JwtSecurityToken Read(string token)
        => new JwtSecurityTokenHandler().ReadJwtToken(token);

    private static string? ClaimValue(JwtSecurityToken jwt, string type)
        => jwt.Claims.FirstOrDefault(c => c.Type == type)?.Value;

    // الـ claims القياسية التي يضيفها منشئ JwtSecurityToken من issuer/audience/expires.
    // نستثنيها عند مقارنة "المجموعة التي بناها الكنترولر" لأنها ليست جزءاً من عقد الـ payload المخصّص.
    private static readonly string[] RegisteredClaimTypes = { "iss", "aud", "exp", "nbf", "iat", "jti" };

    /// <summary>أنواع الـ claims التي بناها المستهلك فقط (بلا iss/aud/exp القياسية)، مرتّبة.</summary>
    private static IEnumerable<string> ConsumerClaimTypes(JwtSecurityToken jwt)
        => jwt.Claims.Select(c => c.Type)
              .Where(t => !RegisteredClaimTypes.Contains(t))
              .OrderBy(t => t);

    private static User BuildSuperAdmin(
        Guid? id = null,
        string fullName = "مدير النظام",
        string phone = "07700000000",
        string? email = null)
        => new()
        {
            Id = id ?? Guid.NewGuid(),
            FullName = fullName,
            PhoneNumber = phone,
            Email = email,
            Role = UserRole.SuperAdmin
        };

    private static void AssertNoUnexpectedSensitiveClaim(JwtSecurityToken jwt)
    {
        foreach (var c in jwt.Claims)
        {
            var lower = c.Type.ToLowerInvariant();
            foreach (var token in SensitiveTokens)
                lower.Contains(token).Should().BeFalse(
                    $"الـ claim '{c.Type}' يطابق الكلمة الحسّاسة '{token}' — تسريب غير متوقّع في توكن مدير النظام");
        }
    }

    // ==========================================================================
    //  1) الرأس: HS256 بلا kid
    // ==========================================================================

    [Fact]
    public void C_Header_IsHs256_And_NoKid()
    {
        var config = BuildConfig();
        var jwt = Read(InvokeGenerate(BuildController(config), BuildSuperAdmin(email: "root@test.local")));

        jwt.Header.Alg.Should().Be(SecurityAlgorithms.HmacSha256, "flag OFF ⇒ HS256");
        jwt.Header.Kid.Should().BeNull("HS256 لا يضيف kid — مطابقة حرفية للعقد السابق");
    }

    // ==========================================================================
    //  2) المحتوى: بالضبط الست claims بقيمها الصحيحة، وبلا أي company_*
    // ==========================================================================

    [Fact]
    public void C_Contains_Exactly_Six_Claims_With_Correct_Values_And_No_Company()
    {
        var config = BuildConfig();
        var userId = Guid.NewGuid();
        var user = BuildSuperAdmin(userId, "مدير المنصّة", "07799998888", "admin@test.local");

        var jwt = Read(InvokeGenerate(BuildController(config), user));

        ClaimValue(jwt, ClaimTypes.NameIdentifier).Should().Be(userId.ToString());
        ClaimValue(jwt, ClaimTypes.Name).Should().Be("مدير المنصّة");
        ClaimValue(jwt, ClaimTypes.Email).Should().Be("admin@test.local");
        ClaimValue(jwt, ClaimTypes.MobilePhone).Should().Be("07799998888");
        ClaimValue(jwt, ClaimTypes.Role).Should().Be(UserRole.SuperAdmin.ToString());
        ClaimValue(jwt, "role_id").Should().Be(((int)UserRole.SuperAdmin).ToString());

        // بالضبط الست claims (لا user_type، لا company_*) — عدا iss/aud/exp القياسية.
        ConsumerClaimTypes(jwt)
            .Should().Equal(SuperAdminClaimTypesC.OrderBy(t => t),
                "C = ست claims بالضبط لمدير النظام (بلا company_*)");
    }

    [Fact]
    public void C_Email_Claim_Is_Empty_String_When_User_Email_Null()
    {
        // C غير شرطي على Email: يكتب user.Email ?? "" ⇒ claim موجود بقيمة فارغة.
        var config = BuildConfig();
        var user = BuildSuperAdmin(email: null);

        var jwt = Read(InvokeGenerate(BuildController(config), user));

        jwt.Claims.Should().Contain(c => c.Type == ClaimTypes.Email,
            "C يضيف Email دائماً (غير شرطي) بقيمة \"\" عند null");
        ClaimValue(jwt, ClaimTypes.Email).Should().BeEmpty();

        // ما زالت الست claims كاملة (عدا iss/aud/exp القياسية).
        ConsumerClaimTypes(jwt)
            .Should().Equal(SuperAdminClaimTypesC.OrderBy(t => t));
    }

    // ==========================================================================
    //  3) المدة: 24 ساعة من التوليد، بلا iat/nbf
    // ==========================================================================

    [Fact]
    public void C_Lifetime_Is_24h_From_Generation_And_No_Iat_No_Nbf()
    {
        var config = BuildConfig();
        var before = DateTimeOffset.UtcNow.ToUnixTimeSeconds();
        var jwt = Read(InvokeGenerate(BuildController(config), BuildSuperAdmin()));
        var after = DateTimeOffset.UtcNow.ToUnixTimeSeconds();

        const long day = 24 * 3600;
        jwt.Payload.TryGetValue("exp", out var rawExp).Should().BeTrue("exp يجب أن يوجد");
        Convert.ToInt64(rawExp).Should().BeInRange(before + day - 2, after + day + 2,
            "C: exp = وقت التوليد + 24 ساعة (±2s)");

        jwt.Payload.ContainsKey("iat").Should().BeFalse("متسق مع المشروع: لا iat");
        jwt.Payload.ContainsKey("nbf").Should().BeFalse("متسق مع المشروع: لا nbf");
    }

    // ==========================================================================
    //  4) issuer/audience
    // ==========================================================================

    [Fact]
    public void C_Issuer_Audience_Match_Configured()
    {
        var config = BuildConfig();
        var jwt = Read(InvokeGenerate(BuildController(config), BuildSuperAdmin()));

        jwt.Issuer.Should().Be(Issuer);
        jwt.Audiences.Should().ContainSingle().Which.Should().Be(Audience);
    }

    [Fact]
    public void C_Issuer_Audience_Use_Fallbacks_When_Config_Missing()
    {
        // Jwt:Issuer/Audience غير مضبوطين ⇒ القيم الاحتياطية داخل C.
        var config = BuildConfig(issuer: null, audience: null);
        var jwt = Read(InvokeGenerate(BuildController(config), BuildSuperAdmin()));

        jwt.Issuer.Should().Be(FallbackIssuer, "غياب Jwt:Issuer ⇒ SadaraPlatform");
        jwt.Audiences.Should().ContainSingle().Which.Should().Be(FallbackAudience, "غياب Jwt:Audience ⇒ SadaraClients");
    }

    // ==========================================================================
    //  5) round-trip HS256
    // ==========================================================================

    [Fact]
    public void C_Token_Validates_RoundTrip_With_Hs256_Parameters()
    {
        var config = BuildConfig();
        var token = InvokeGenerate(BuildController(config), BuildSuperAdmin(email: "root@test.local"));

        var handler = new JwtSecurityTokenHandler();
        var parameters = new TokenValidationParameters
        {
            ValidateIssuerSigningKey = true,
            IssuerSigningKey = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(TestSecret)),
            ValidAlgorithms = new[] { SecurityAlgorithms.HmacSha256 },
            ValidateIssuer = true,
            ValidIssuer = Issuer,
            ValidateAudience = true,
            ValidAudience = Audience,
            ValidateLifetime = true,
            ClockSkew = TimeSpan.Zero
        };

        var act = () => handler.ValidateToken(token, parameters, out _);
        act.Should().NotThrow("توكن مدير النظام صالح للتحقق بمفتاح HS256 عبر TokenValidationParameters");
    }

    // ==========================================================================
    //  6) حارس التصعيد: لا claim باسم company_* ولا أي claim حسّاس غير متوقّع
    // ==========================================================================

    [Fact]
    public void C_Token_Contains_No_Company_Claim_And_No_Unexpected_Sensitive_Claim()
    {
        var config = BuildConfig();
        var jwt = Read(InvokeGenerate(BuildController(config), BuildSuperAdmin(email: "root@test.local")));

        // حارس عزل المستأجر: مدير النظام عابر للشركات ⇒ لا يجوز أن يحمل توكنه أي claim باسم يبدأ بـ company_
        jwt.Claims.Should().NotContain(
            c => c.Type.StartsWith("company_", StringComparison.OrdinalIgnoreCase),
            "توكن مدير النظام يجب ألّا يحمل أي claim باسم company_* — لا شركة/مستأجر مرتبط به");
        // تأكيد صريح للأسماء الثلاثة المعروفة من المواضع الأخرى.
        jwt.Claims.Should().NotContain(c => c.Type == "company_id");
        jwt.Claims.Should().NotContain(c => c.Type == "company_code");
        jwt.Claims.Should().NotContain(c => c.Type == "company_name");

        // حارس التسريب العام: لا claim باسم حسّاس.
        AssertNoUnexpectedSensitiveClaim(jwt);
    }
}
