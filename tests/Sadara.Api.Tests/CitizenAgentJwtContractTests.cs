using System.IdentityModel.Tokens.Jwt;
using System.Reflection;
using System.Security.Claims;
using System.Text;
using FluentAssertions;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.IdentityModel.Tokens;
using Sadara.Api.Tests.Fakes;
using Sadara.API.Controllers;
using Sadara.Domain.Entities;
using Sadara.Domain.Enums;
using Sadara.Infrastructure.Data;
using Sadara.Infrastructure.Identity;
using Xunit;

namespace Sadara.Api.Tests;

/// <summary>
/// إثبات عقد التوكن للموضعين E وF بعد توحيدهما على المُوقّع المشترك IJwtTokenSigner
/// (نفس ما فُعِل بالمواضع A/B/C/D). الموضعان هنا:
///   E: CitizenAuthController.GenerateJwtToken(Citizen) — private، توكن مواطن، مدّته 30 يوماً.
///      claims: NameIdentifier, MobilePhone, Name, type=citizen, companyId (شرطي، بحرف I كبير). بلا sub/jti/role.
///   F: AgentsController.GenerateAgentToken(Agent) — private، توكن وكيل، مدّته 30 يوماً.
///      claims: NameIdentifier, Name, MobilePhone, agent_code, company_id, role=Agent (claim مخصّص باسم "role"),
///      user_type=agent. بلا jti.
///
/// كل موضع يُستدعى مباشرة عبر reflection على نسخة حقيقية من الكنترولر، بحقن تبعيات وهمية،
/// ومُوقّع JwtTokenSigner حقيقي عند flag OFF (HS256؛ Jwt:Algorithm=HS256 صراحةً هنا).
///
/// معزول تماماً عن قاعدة البيانات والـ web host:
/// - E: SadaraDbContext على مزوّد InMemory (مُنشئه يتطلب DbContextOptions + ICurrentTenant)؛
///      دالة GenerateJwtToken(Citizen) لا تستعلم القاعدة إطلاقاً.
/// - F: IUnitOfWork = FakeUnitOfWork (لا يُلمَس من GenerateAgentToken).
/// - ILogger = NullLogger.
/// - IConfiguration = InMemory (Jwt:Secret ثابت + Issuer/Audience + Jwt:Algorithm=HS256).
/// - IJwtTokenSigner = new JwtTokenSigner(config) الحقيقي بنفس الإعداد.
///
/// السرّ أدناه قيمة اختبار محلية غير مرتبطة بأي سرّ إنتاجي.
/// </summary>
public class CitizenAgentJwtContractTests
{
    private const string TestSecret = "unit-test-only-hs256-secret-key-do-not-use-in-prod-0123456789";
    private const string Issuer = "sadara-test-issuer";
    private const string Audience = "sadara-test-audience";

    // القيم الاحتياطية المضمّنة في الكنترولرين عند غياب Jwt:Issuer/Jwt:Audience.
    private const string FallbackIssuer = "SadaraPlatform";
    private const string FallbackAudience = "SadaraClients";

    // ==== عقد E (المواطن) ====
    // الأربع الأساسية دائماً + companyId عند وجوده. لا sub، لا jti، لا role.
    private static readonly string[] CitizenCoreClaimTypesE =
    {
        ClaimTypes.NameIdentifier, ClaimTypes.MobilePhone, ClaimTypes.Name, "type"
    };

    // ==== عقد F (الوكيل) ====
    // السبع claims بالضبط. لا jti. ملاحظة: "role" هنا claim مخصّص باسم "role" وليس ClaimTypes.Role.
    private static readonly string[] AgentClaimTypesF =
    {
        ClaimTypes.NameIdentifier, ClaimTypes.Name, ClaimTypes.MobilePhone,
        "agent_code", "company_id", "role", "user_type"
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

    // ============ بناء الكنترولرين مباشرة (بلا web host) ============

    /// <summary>
    /// SadaraDbContext على مزوّد InMemory. مُنشئه يتطلب (DbContextOptions, ICurrentTenant)؛
    /// دالة GenerateJwtToken(Citizen) قيد الاختبار لا تستعلم القاعدة، فالسياق مجرّد تبعية بنائية.
    /// </summary>
    private static SadaraDbContext BuildInMemoryContext()
    {
        var options = new DbContextOptionsBuilder<SadaraDbContext>()
            .UseInMemoryDatabase($"citizen-jwt-contract-{Guid.NewGuid()}")
            .Options;
        return new SadaraDbContext(options, new FakeCurrentTenant());
    }

    private static CitizenAuthController BuildCitizenController(IConfiguration config)
        => new(
            BuildInMemoryContext(),
            config,
            NullLogger<CitizenAuthController>.Instance,
            BuildSigner(config));

    private static AgentsController BuildAgentsController(IConfiguration config)
        => new(
            new FakeUnitOfWork(new FakeCompanyRepository()),
            config,
            NullLogger<AgentsController>.Instance,
            BuildSigner(config));

    /// <summary>يستدعي private GenerateJwtToken(Citizen) عبر reflection ويعيد التوكن المُسلسل.</summary>
    private static string InvokeGenerateCitizen(CitizenAuthController controller, Citizen citizen)
    {
        var method = controller.GetType().GetMethod(
            "GenerateJwtToken",
            BindingFlags.NonPublic | BindingFlags.Instance,
            binder: null,
            types: new[] { typeof(Citizen) },
            modifiers: null);
        method.Should().NotBeNull("GenerateJwtToken(Citizen) يجب أن يوجد كدالة نسخة خاصّة بمعامل واحد");

        var token = method!.Invoke(controller, new object?[] { citizen });
        token.Should().BeOfType<string>();
        return (string)token!;
    }

    /// <summary>يستدعي private GenerateAgentToken(Agent) عبر reflection ويعيد التوكن المُسلسل.</summary>
    private static string InvokeGenerateAgent(AgentsController controller, Agent agent)
    {
        var method = controller.GetType().GetMethod(
            "GenerateAgentToken",
            BindingFlags.NonPublic | BindingFlags.Instance,
            binder: null,
            types: new[] { typeof(Agent) },
            modifiers: null);
        method.Should().NotBeNull("GenerateAgentToken(Agent) يجب أن يوجد كدالة نسخة خاصّة بمعامل واحد");

        var token = method!.Invoke(controller, new object?[] { agent });
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

    private static Citizen BuildCitizen(
        Guid? id = null,
        string fullName = "مواطن الاختبار",
        string phone = "+9647701112222",
        Guid? companyId = null)
        => new()
        {
            Id = id ?? Guid.NewGuid(),
            FullName = fullName,
            PhoneNumber = phone,
            CompanyId = companyId
        };

    private static Agent BuildAgent(
        Guid? id = null,
        string name = "وكيل الاختبار",
        string phone = "+9647703334444",
        string agentCode = "AG-0001",
        Guid? companyId = null)
        => new()
        {
            Id = id ?? Guid.NewGuid(),
            Name = name,
            PhoneNumber = phone,
            AgentCode = agentCode,
            CompanyId = companyId ?? Guid.NewGuid()
        };

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

    // ==========================================================================
    //  الموضع E — CitizenAuthController.GenerateJwtToken(Citizen)
    // ==========================================================================

    [Fact]
    public void E_Header_IsHs256_And_NoKid()
    {
        var config = BuildConfig();
        var jwt = Read(InvokeGenerateCitizen(BuildCitizenController(config), BuildCitizen(companyId: Guid.NewGuid())));

        jwt.Header.Alg.Should().Be(SecurityAlgorithms.HmacSha256, "flag OFF ⇒ HS256");
        jwt.Header.Kid.Should().BeNull("HS256 لا يضيف kid — مطابقة حرفية للعقد السابق");
    }

    [Fact]
    public void E_WithCompany_Contains_All_Claims_With_Correct_Values()
    {
        var config = BuildConfig();
        var citizenId = Guid.NewGuid();
        var companyId = Guid.NewGuid();
        var citizen = BuildCitizen(citizenId, "علي المواطن", "+9647705556666", companyId);

        var jwt = Read(InvokeGenerateCitizen(BuildCitizenController(config), citizen));

        ClaimValue(jwt, ClaimTypes.NameIdentifier).Should().Be(citizenId.ToString());
        ClaimValue(jwt, ClaimTypes.MobilePhone).Should().Be("+9647705556666");
        ClaimValue(jwt, ClaimTypes.Name).Should().Be("علي المواطن");
        ClaimValue(jwt, "type").Should().Be("citizen");
        // companyId بحرف I كبير (مطابقة حرفية لعقد E).
        ClaimValue(jwt, "companyId").Should().Be(companyId.ToString());

        // بالضبط الأربع الأساسية + companyId — عدا iss/aud/exp القياسية.
        var expected = CitizenCoreClaimTypesE.Append("companyId").OrderBy(t => t);
        ConsumerClaimTypes(jwt)
            .Should().Equal(expected, "E مع company = خمس claims بالضبط");
    }

    [Fact]
    public void E_WithoutCompany_Omits_CompanyId_Claim()
    {
        var config = BuildConfig();
        var citizen = BuildCitizen(companyId: null);

        var jwt = Read(InvokeGenerateCitizen(BuildCitizenController(config), citizen));

        jwt.Claims.Should().NotContain(c => c.Type == "companyId",
            "CompanyId=null ⇒ لا claim companyId (يُضاف فقط عند HasValue)");

        // بالضبط الأربع الأساسية عند غياب الشركة — عدا iss/aud/exp القياسية.
        ConsumerClaimTypes(jwt)
            .Should().Equal(CitizenCoreClaimTypesE.OrderBy(t => t), "E بلا company = الأربع الأساسية فقط");
    }

    [Fact]
    public void E_Guard_No_Jti_No_Sub_No_Role()
    {
        var config = BuildConfig();
        var jwt = Read(InvokeGenerateCitizen(BuildCitizenController(config), BuildCitizen(companyId: Guid.NewGuid())));

        // حارس صريح: عقد المواطن بلا jti، بلا sub، بلا role (لا مخصّص ولا قياسي).
        jwt.Payload.ContainsKey("jti").Should().BeFalse("عقد E بلا jti");
        jwt.Claims.Should().NotContain(c => c.Type == "jti");
        jwt.Claims.Should().NotContain(c => c.Type == "sub", "عقد E بلا sub");
        jwt.Claims.Should().NotContain(c => c.Type == "role", "عقد E بلا role مخصّص");
        jwt.Claims.Should().NotContain(c => c.Type == ClaimTypes.Role, "عقد E بلا role قياسي");
    }

    [Fact]
    public void E_Lifetime_Is_30d_From_Generation_And_No_Iat_No_Nbf()
    {
        var config = BuildConfig();
        var before = DateTimeOffset.UtcNow.ToUnixTimeSeconds();
        var jwt = Read(InvokeGenerateCitizen(BuildCitizenController(config), BuildCitizen(companyId: Guid.NewGuid())));
        var after = DateTimeOffset.UtcNow.ToUnixTimeSeconds();

        const long thirtyDays = 30L * 24 * 3600;
        jwt.Payload.TryGetValue("exp", out var rawExp).Should().BeTrue("exp يجب أن يوجد");
        Convert.ToInt64(rawExp).Should().BeInRange(before + thirtyDays - 5, after + thirtyDays + 5,
            "E: exp = وقت التوليد + 30 يوماً (±5s)");

        jwt.Payload.ContainsKey("iat").Should().BeFalse("متسق مع المشروع: لا iat");
        jwt.Payload.ContainsKey("nbf").Should().BeFalse("متسق مع المشروع: لا nbf");
    }

    [Fact]
    public void E_Issuer_Audience_Match_Configured()
    {
        var config = BuildConfig();
        var jwt = Read(InvokeGenerateCitizen(BuildCitizenController(config), BuildCitizen(companyId: Guid.NewGuid())));

        jwt.Issuer.Should().Be(Issuer);
        jwt.Audiences.Should().ContainSingle().Which.Should().Be(Audience);
    }

    [Fact]
    public void E_Issuer_Audience_Use_Fallbacks_When_Config_Missing()
    {
        var config = BuildConfig(issuer: null, audience: null);
        var jwt = Read(InvokeGenerateCitizen(BuildCitizenController(config), BuildCitizen(companyId: Guid.NewGuid())));

        jwt.Issuer.Should().Be(FallbackIssuer, "غياب Jwt:Issuer ⇒ SadaraPlatform");
        jwt.Audiences.Should().ContainSingle().Which.Should().Be(FallbackAudience, "غياب Jwt:Audience ⇒ SadaraClients");
    }

    [Fact]
    public void E_Token_Validates_RoundTrip_With_Hs256_Parameters()
    {
        var config = BuildConfig();
        var token = InvokeGenerateCitizen(BuildCitizenController(config), BuildCitizen(companyId: Guid.NewGuid()));

        AssertValidatesHs256(token);
    }

    [Fact]
    public void E_No_Unexpected_Sensitive_Claim()
    {
        var config = BuildConfig();
        var jwt = Read(InvokeGenerateCitizen(BuildCitizenController(config), BuildCitizen(companyId: Guid.NewGuid())));

        AssertNoUnexpectedSensitiveClaim(jwt);
    }

    // ==========================================================================
    //  الموضع F — AgentsController.GenerateAgentToken(Agent)
    // ==========================================================================

    [Fact]
    public void F_Header_IsHs256_And_NoKid()
    {
        var config = BuildConfig();
        var jwt = Read(InvokeGenerateAgent(BuildAgentsController(config), BuildAgent()));

        jwt.Header.Alg.Should().Be(SecurityAlgorithms.HmacSha256, "flag OFF ⇒ HS256");
        jwt.Header.Kid.Should().BeNull("HS256 لا يضيف kid");
    }

    [Fact]
    public void F_Contains_Exactly_Seven_Claims_With_Correct_Values()
    {
        var config = BuildConfig();
        var agentId = Guid.NewGuid();
        var companyId = Guid.NewGuid();
        var agent = BuildAgent(agentId, "كريم الوكيل", "+9647707778888", "AG-0042", companyId);

        var jwt = Read(InvokeGenerateAgent(BuildAgentsController(config), agent));

        ClaimValue(jwt, ClaimTypes.NameIdentifier).Should().Be(agentId.ToString());
        ClaimValue(jwt, ClaimTypes.Name).Should().Be("كريم الوكيل");
        ClaimValue(jwt, ClaimTypes.MobilePhone).Should().Be("+9647707778888");
        ClaimValue(jwt, "agent_code").Should().Be("AG-0042");
        ClaimValue(jwt, "company_id").Should().Be(companyId.ToString());
        // "role" claim مخصّص بقيمة ثابتة "Agent" (وليس ClaimTypes.Role).
        ClaimValue(jwt, "role").Should().Be("Agent");
        ClaimValue(jwt, "user_type").Should().Be("agent");

        // بالضبط السبع claims — عدا iss/aud/exp القياسية.
        ConsumerClaimTypes(jwt)
            .Should().Equal(AgentClaimTypesF.OrderBy(t => t), "F = سبع claims بالضبط");
    }

    [Fact]
    public void F_Role_Is_Custom_Claim_Not_StandardClaimType()
    {
        var config = BuildConfig();
        var jwt = Read(InvokeGenerateAgent(BuildAgentsController(config), BuildAgent()));

        // الـ role في F هو claim باسم حرفي "role" — لا يُكتب كـ ClaimTypes.Role القياسي.
        jwt.Claims.Should().Contain(c => c.Type == "role" && c.Value == "Agent");
        jwt.Claims.Should().NotContain(c => c.Type == ClaimTypes.Role,
            "F يستخدم claim مخصّص باسم \"role\" وليس ClaimTypes.Role القياسي");
    }

    [Fact]
    public void F_Guard_No_Jti()
    {
        var config = BuildConfig();
        var jwt = Read(InvokeGenerateAgent(BuildAgentsController(config), BuildAgent()));

        jwt.Payload.ContainsKey("jti").Should().BeFalse("عقد F بلا jti");
        jwt.Claims.Should().NotContain(c => c.Type == "jti");
    }

    [Fact]
    public void F_Lifetime_Is_30d_From_Generation_And_No_Iat_No_Nbf()
    {
        var config = BuildConfig();
        var before = DateTimeOffset.UtcNow.ToUnixTimeSeconds();
        var jwt = Read(InvokeGenerateAgent(BuildAgentsController(config), BuildAgent()));
        var after = DateTimeOffset.UtcNow.ToUnixTimeSeconds();

        const long thirtyDays = 30L * 24 * 3600;
        jwt.Payload.TryGetValue("exp", out var rawExp).Should().BeTrue("exp يجب أن يوجد");
        Convert.ToInt64(rawExp).Should().BeInRange(before + thirtyDays - 5, after + thirtyDays + 5,
            "F: exp = وقت التوليد + 30 يوماً (±5s)");

        jwt.Payload.ContainsKey("iat").Should().BeFalse();
        jwt.Payload.ContainsKey("nbf").Should().BeFalse();
    }

    [Fact]
    public void F_Issuer_Audience_Match_Configured()
    {
        var config = BuildConfig();
        var jwt = Read(InvokeGenerateAgent(BuildAgentsController(config), BuildAgent()));

        jwt.Issuer.Should().Be(Issuer);
        jwt.Audiences.Should().ContainSingle().Which.Should().Be(Audience);
    }

    [Fact]
    public void F_Issuer_Audience_Use_Fallbacks_When_Config_Missing()
    {
        var config = BuildConfig(issuer: null, audience: null);
        var jwt = Read(InvokeGenerateAgent(BuildAgentsController(config), BuildAgent()));

        jwt.Issuer.Should().Be(FallbackIssuer);
        jwt.Audiences.Should().ContainSingle().Which.Should().Be(FallbackAudience);
    }

    [Fact]
    public void F_Token_Validates_RoundTrip_With_Hs256_Parameters()
    {
        var config = BuildConfig();
        var token = InvokeGenerateAgent(BuildAgentsController(config), BuildAgent());

        AssertValidatesHs256(token);
    }

    [Fact]
    public void F_No_Unexpected_Sensitive_Claim()
    {
        var config = BuildConfig();
        var jwt = Read(InvokeGenerateAgent(BuildAgentsController(config), BuildAgent()));

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
