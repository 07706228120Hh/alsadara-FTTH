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
/// إثبات عقد التوكن للموضعين B وD بعد توحيدهما على المُوقّع المشترك IJwtTokenSigner
/// (نفس ما فُعِل بالموضع A). كل موضع كنترولر (private GenerateJwtToken) يُستدعى مباشرة
/// عبر reflection على نسخة حقيقية من الكنترولر، بحقن تبعيات وهمية، ومُوقّع JwtTokenSigner
/// حقيقي عند flag OFF (HS256؛ Jwt:Algorithm غير مضبوط).
///
/// معزول تماماً عن قاعدة البيانات والـ web host:
/// - IUnitOfWork = FakeUnitOfWork (لا يُلمَس من GenerateJwtToken).
/// - ICurrentTenant = FakeCurrentTenant (لا يُلمَس من GenerateJwtToken).
/// - ILogger = NullLogger.
/// - IConfiguration = InMemory (Jwt:Secret ثابت + Issuer/Audience؛ Jwt:Algorithm غير مضبوط ⇒ HS256).
/// - IJwtTokenSigner = new JwtTokenSigner(config) الحقيقي بنفس الإعداد.
///
/// السرّ أدناه قيمة اختبار محلية غير مرتبطة بأي سرّ إنتاجي.
/// </summary>
public class AuthControllersJwtContractTests
{
    private const string TestSecret = "unit-test-only-hs256-secret-key-do-not-use-in-prod-0123456789";
    private const string Issuer = "sadara-test-issuer";
    private const string Audience = "sadara-test-audience";

    // القيم الاحتياطية المضمّنة في الكنترولرين عند غياب Jwt:Issuer/Jwt:Audience.
    private const string FallbackIssuer = "SadaraPlatform";
    private const string FallbackAudience = "SadaraClients";

    // الست claims الأساسية (B) — قبل Email و company_*.
    private static readonly string[] CoreClaimTypesB =
    {
        ClaimTypes.NameIdentifier, ClaimTypes.Name, ClaimTypes.MobilePhone,
        ClaimTypes.Role, "role_id", "user_type"
    };

    // التسع claims (D) — company_* غير شرطية + Email غير شرطي (يُكتب "" عند null).
    private static readonly string[] NineClaimTypesD =
    {
        ClaimTypes.NameIdentifier, ClaimTypes.Name, ClaimTypes.Email, ClaimTypes.MobilePhone,
        ClaimTypes.Role, "role_id", "company_id", "company_code", "company_name"
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
        // Jwt:Algorithm غير مضبوط عمداً ⇒ HS256 الافتراضي (flag OFF).
        return new ConfigurationBuilder().AddInMemoryCollection(settings).Build();
    }

    private static JwtTokenSigner BuildSigner(IConfiguration config) => new(config);

    // ============ بناء الكنترولرين مباشرة (بلا web host) ============

    private static UnifiedAuthController BuildUnifiedController(IConfiguration config)
        => new(
            new FakeUnitOfWork(new FakeCompanyRepository()),
            config,
            NullLogger<UnifiedAuthController>.Instance,
            BuildSigner(config));

    private static CompaniesController BuildCompaniesController(IConfiguration config)
        => new(
            new FakeUnitOfWork(new FakeCompanyRepository()),
            config,
            NullLogger<CompaniesController>.Instance,
            new FakeCurrentTenant(),
            BuildSigner(config));

    /// <summary>يستدعي private GenerateJwtToken(User, Company?) عبر reflection ويعيد التوكن المُسلسل.</summary>
    private static string InvokeGenerate(object controller, User user, Company? company)
    {
        var method = controller.GetType().GetMethod(
            "GenerateJwtToken",
            BindingFlags.NonPublic | BindingFlags.Instance);
        method.Should().NotBeNull("GenerateJwtToken يجب أن يوجد كدالة نسخة خاصّة");

        var token = method!.Invoke(controller, new object?[] { user, company });
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

    private static User BuildUser(
        Guid? id = null,
        string fullName = "مستخدم اختبار",
        string phone = "07700000000",
        string? email = null,
        UserRole role = UserRole.Employee)
        => new()
        {
            Id = id ?? Guid.NewGuid(),
            FullName = fullName,
            PhoneNumber = phone,
            Email = email,
            Role = role
        };

    private static Company BuildCompany(Guid? id = null, string name = "شركة الاختبار", string code = "TST")
        => new() { Id = id ?? Guid.NewGuid(), Name = name, Code = code };

    private static void AssertNoUnexpectedSensitiveClaim(JwtSecurityToken jwt)
    {
        foreach (var c in jwt.Claims)
        {
            var lower = c.Type.ToLowerInvariant();
            foreach (var token in SensitiveTokens)
                lower.Contains(token).Should().BeFalse(
                    $"الـ claim '{c.Type}' يطابق الكلمة الحسّاسة '{token}' — تسريب غير متوقّع في التوكن");
        }
    }

    private static string UserTypeOf(UserRole role) => role switch
    {
        UserRole.SuperAdmin => "super_admin",
        UserRole.CompanyAdmin => "company_admin",
        UserRole.Manager => "manager",
        UserRole.TechnicalLeader => "technical_leader",
        UserRole.Technician => "technician",
        UserRole.Employee => "employee",
        UserRole.Viewer => "viewer",
        UserRole.Citizen => "citizen",
        UserRole.Merchant => "merchant",
        UserRole.Driver => "driver",
        _ => "unknown"
    };

    // ==========================================================================
    //  الموضع B — UnifiedAuthController.GenerateJwtToken(User, Company?)
    // ==========================================================================

    [Fact]
    public void B_Header_IsHs256_And_NoKid()
    {
        var config = BuildConfig();
        var jwt = Read(InvokeGenerate(BuildUnifiedController(config), BuildUser(), BuildCompany()));

        jwt.Header.Alg.Should().Be(SecurityAlgorithms.HmacSha256, "flag OFF ⇒ HS256");
        jwt.Header.Kid.Should().BeNull("HS256 لا يضيف kid — مطابقة حرفية للعقد السابق");
    }

    [Fact]
    public void B_WithCompany_And_Email_Contains_All_Nine_Claims_With_Correct_Values()
    {
        var config = BuildConfig();
        var userId = Guid.NewGuid();
        var companyId = Guid.NewGuid();
        var user = BuildUser(userId, "أحمد الفني", "07711112222", "ahmed@test.local", UserRole.Technician);
        var company = BuildCompany(companyId, "شركة الصدارة", "SADARA");

        var jwt = Read(InvokeGenerate(BuildUnifiedController(config), user, company));

        // الست الأساسية.
        ClaimValue(jwt, ClaimTypes.NameIdentifier).Should().Be(userId.ToString());
        ClaimValue(jwt, ClaimTypes.Name).Should().Be("أحمد الفني");
        ClaimValue(jwt, ClaimTypes.MobilePhone).Should().Be("07711112222");
        ClaimValue(jwt, ClaimTypes.Role).Should().Be(UserRole.Technician.ToString());
        ClaimValue(jwt, "role_id").Should().Be(((int)UserRole.Technician).ToString());
        ClaimValue(jwt, "user_type").Should().Be(UserTypeOf(UserRole.Technician));

        // Email عند وجوده.
        ClaimValue(jwt, ClaimTypes.Email).Should().Be("ahmed@test.local");

        // company_* عند وجود company.
        ClaimValue(jwt, "company_id").Should().Be(companyId.ToString());
        ClaimValue(jwt, "company_code").Should().Be("SADARA");
        ClaimValue(jwt, "company_name").Should().Be("شركة الصدارة");

        // مجموعة الأنواع بالضبط = الست الأساسية + Email + company_* الثلاثة (لا زيادة/نقص).
        var expected = CoreClaimTypesB
            .Append(ClaimTypes.Email)
            .Concat(new[] { "company_id", "company_code", "company_name" })
            .OrderBy(t => t);
        ConsumerClaimTypes(jwt)
            .Should().Equal(expected, "B مع company+email = تسع claims بالضبط (عدا iss/aud/exp القياسية)");
    }

    [Fact]
    public void B_WithoutCompany_Omits_CompanyClaims()
    {
        var config = BuildConfig();
        var user = BuildUser(email: "citizen@test.local", role: UserRole.Citizen);

        var jwt = Read(InvokeGenerate(BuildUnifiedController(config), user, company: null));

        jwt.Claims.Should().NotContain(c => c.Type == "company_id", "company=null ⇒ لا company_id");
        jwt.Claims.Should().NotContain(c => c.Type == "company_code");
        jwt.Claims.Should().NotContain(c => c.Type == "company_name");

        // الست الأساسية + Email موجودة.
        foreach (var t in CoreClaimTypesB)
            jwt.Claims.Should().Contain(c => c.Type == t, $"claim أساسي '{t}' يجب أن يوجد");
        ClaimValue(jwt, ClaimTypes.Email).Should().Be("citizen@test.local");
    }

    [Fact]
    public void B_WithoutEmail_Omits_EmailClaim()
    {
        var config = BuildConfig();
        var user = BuildUser(email: null, role: UserRole.Employee);

        var jwt = Read(InvokeGenerate(BuildUnifiedController(config), user, company: null));

        jwt.Claims.Should().NotContain(c => c.Type == ClaimTypes.Email,
            "Email=null ⇒ لا claim بريد (مطابق لسلوك B: يُضاف فقط إذا غير فارغ)");
        // فقط الست الأساسية عند غياب Email وcompany (عدا iss/aud/exp القياسية).
        ConsumerClaimTypes(jwt)
            .Should().Equal(CoreClaimTypesB.OrderBy(t => t), "B بلا email/company = الست الأساسية فقط");
    }

    [Fact]
    public void B_Lifetime_Is_24h_From_Generation_And_No_Iat_No_Nbf()
    {
        var config = BuildConfig();
        var before = DateTimeOffset.UtcNow.ToUnixTimeSeconds();
        var jwt = Read(InvokeGenerate(BuildUnifiedController(config), BuildUser(), BuildCompany()));
        var after = DateTimeOffset.UtcNow.ToUnixTimeSeconds();

        const long day = 24 * 3600;
        jwt.Payload.TryGetValue("exp", out var rawExp).Should().BeTrue("exp يجب أن يوجد");
        Convert.ToInt64(rawExp).Should().BeInRange(before + day - 2, after + day + 2,
            "B: exp = وقت التوليد + 24 ساعة (±2s)");

        jwt.Payload.ContainsKey("iat").Should().BeFalse("متسق مع المشروع: لا iat");
        jwt.Payload.ContainsKey("nbf").Should().BeFalse("متسق مع المشروع: لا nbf");
    }

    [Fact]
    public void B_Issuer_Audience_Match_Configured()
    {
        var config = BuildConfig();
        var jwt = Read(InvokeGenerate(BuildUnifiedController(config), BuildUser(), BuildCompany()));

        jwt.Issuer.Should().Be(Issuer);
        jwt.Audiences.Should().ContainSingle().Which.Should().Be(Audience);
    }

    [Fact]
    public void B_Issuer_Audience_Use_Fallbacks_When_Config_Missing()
    {
        // Jwt:Issuer/Audience غير مضبوطين ⇒ القيم الاحتياطية داخل B.
        var config = BuildConfig(issuer: null, audience: null);
        var jwt = Read(InvokeGenerate(BuildUnifiedController(config), BuildUser(), BuildCompany()));

        jwt.Issuer.Should().Be(FallbackIssuer, "غياب Jwt:Issuer ⇒ SadaraPlatform");
        jwt.Audiences.Should().ContainSingle().Which.Should().Be(FallbackAudience, "غياب Jwt:Audience ⇒ SadaraClients");
    }

    [Fact]
    public void B_Token_Validates_RoundTrip_With_Hs256_Parameters()
    {
        var config = BuildConfig();
        var token = InvokeGenerate(BuildUnifiedController(config), BuildUser(email: "e@test.local"), BuildCompany());

        AssertValidatesHs256(token);
    }

    [Fact]
    public void B_No_Unexpected_Sensitive_Claim()
    {
        var config = BuildConfig();
        var jwt = Read(InvokeGenerate(
            BuildUnifiedController(config),
            BuildUser(email: "e@test.local", role: UserRole.CompanyAdmin),
            BuildCompany()));

        AssertNoUnexpectedSensitiveClaim(jwt);
    }

    // ==========================================================================
    //  الموضع D — CompaniesController.GenerateJwtToken(User, Company)
    // ==========================================================================

    [Fact]
    public void D_Header_IsHs256_And_NoKid()
    {
        var config = BuildConfig();
        var jwt = Read(InvokeGenerate(BuildCompaniesController(config), BuildUser(), BuildCompany()));

        jwt.Header.Alg.Should().Be(SecurityAlgorithms.HmacSha256, "flag OFF ⇒ HS256");
        jwt.Header.Kid.Should().BeNull("HS256 لا يضيف kid");
    }

    [Fact]
    public void D_Contains_Exactly_Nine_Claims_With_Correct_Values()
    {
        var config = BuildConfig();
        var userId = Guid.NewGuid();
        var companyId = Guid.NewGuid();
        var user = BuildUser(userId, "سالم المدير", "07733334444", "salem@test.local", UserRole.CompanyAdmin);
        var company = BuildCompany(companyId, "شركة النور", "NOOR");

        var jwt = Read(InvokeGenerate(BuildCompaniesController(config), user, company));

        ClaimValue(jwt, ClaimTypes.NameIdentifier).Should().Be(userId.ToString());
        ClaimValue(jwt, ClaimTypes.Name).Should().Be("سالم المدير");
        ClaimValue(jwt, ClaimTypes.Email).Should().Be("salem@test.local");
        ClaimValue(jwt, ClaimTypes.MobilePhone).Should().Be("07733334444");
        ClaimValue(jwt, ClaimTypes.Role).Should().Be(UserRole.CompanyAdmin.ToString());
        ClaimValue(jwt, "role_id").Should().Be(((int)UserRole.CompanyAdmin).ToString());
        ClaimValue(jwt, "company_id").Should().Be(companyId.ToString());
        ClaimValue(jwt, "company_code").Should().Be("NOOR");
        ClaimValue(jwt, "company_name").Should().Be("شركة النور");

        // بالضبط التسع claims (company_* غير شرطية؛ لا user_type في D) — عدا iss/aud/exp القياسية.
        ConsumerClaimTypes(jwt)
            .Should().Equal(NineClaimTypesD.OrderBy(t => t), "D = تسع claims بالضبط");
    }

    [Fact]
    public void D_Email_Claim_Is_Empty_String_When_User_Email_Null()
    {
        // D غير شرطي على Email: يكتب user.Email ?? "" ⇒ claim موجود بقيمة فارغة.
        var config = BuildConfig();
        var user = BuildUser(email: null);
        var company = BuildCompany();

        var jwt = Read(InvokeGenerate(BuildCompaniesController(config), user, company));

        jwt.Claims.Should().Contain(c => c.Type == ClaimTypes.Email,
            "D يضيف Email دائماً (غير شرطي) بقيمة \"\" عند null");
        ClaimValue(jwt, ClaimTypes.Email).Should().BeEmpty();

        // ما زالت التسع claims كاملة (عدا iss/aud/exp القياسية).
        ConsumerClaimTypes(jwt)
            .Should().Equal(NineClaimTypesD.OrderBy(t => t));
    }

    [Fact]
    public void D_Lifetime_Is_24h_From_Generation_And_No_Iat_No_Nbf()
    {
        var config = BuildConfig();
        var before = DateTimeOffset.UtcNow.ToUnixTimeSeconds();
        var jwt = Read(InvokeGenerate(BuildCompaniesController(config), BuildUser(), BuildCompany()));
        var after = DateTimeOffset.UtcNow.ToUnixTimeSeconds();

        const long day = 24 * 3600;
        jwt.Payload.TryGetValue("exp", out var rawExp).Should().BeTrue("exp يجب أن يوجد");
        Convert.ToInt64(rawExp).Should().BeInRange(before + day - 2, after + day + 2,
            "D: exp = وقت التوليد + 24 ساعة (±2s)");

        jwt.Payload.ContainsKey("iat").Should().BeFalse();
        jwt.Payload.ContainsKey("nbf").Should().BeFalse();
    }

    [Fact]
    public void D_Issuer_Audience_Match_Configured()
    {
        var config = BuildConfig();
        var jwt = Read(InvokeGenerate(BuildCompaniesController(config), BuildUser(), BuildCompany()));

        jwt.Issuer.Should().Be(Issuer);
        jwt.Audiences.Should().ContainSingle().Which.Should().Be(Audience);
    }

    [Fact]
    public void D_Issuer_Audience_Use_Fallbacks_When_Config_Missing()
    {
        var config = BuildConfig(issuer: null, audience: null);
        var jwt = Read(InvokeGenerate(BuildCompaniesController(config), BuildUser(), BuildCompany()));

        jwt.Issuer.Should().Be(FallbackIssuer);
        jwt.Audiences.Should().ContainSingle().Which.Should().Be(FallbackAudience);
    }

    [Fact]
    public void D_Token_Validates_RoundTrip_With_Hs256_Parameters()
    {
        var config = BuildConfig();
        var token = InvokeGenerate(BuildCompaniesController(config), BuildUser(email: "e@test.local"), BuildCompany());

        AssertValidatesHs256(token);
    }

    [Fact]
    public void D_No_Unexpected_Sensitive_Claim()
    {
        var config = BuildConfig();
        var jwt = Read(InvokeGenerate(
            BuildCompaniesController(config),
            BuildUser(email: "e@test.local", role: UserRole.Manager),
            BuildCompany()));

        AssertNoUnexpectedSensitiveClaim(jwt);
    }

    // ============ round-trip HS256 مشترك ============

    private static void AssertValidatesHs256(string token)
    {
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
        act.Should().NotThrow("التوكن المُنتَج صالح للتحقق بمفتاح HS256 عبر TokenValidationParameters");
    }
}
