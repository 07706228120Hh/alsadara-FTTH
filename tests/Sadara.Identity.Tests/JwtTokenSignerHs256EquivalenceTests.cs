using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using System.Text;
using FluentAssertions;
using Microsoft.IdentityModel.Tokens;
using Sadara.Domain.Entities;
using Sadara.Domain.Enums;
using Sadara.Infrastructure.Identity;
using Xunit;

namespace Sadara.Identity.Tests;

/// <summary>
/// إثبات تكافؤ الموضع A بعد التوحيد على IJwtTokenSigner (ADR-003 خطوة 0).
///
/// الهدف: إثبات أنّ JwtService (الذي يفوّض التوقيع الآن إلى JwtTokenSigner) يُصدر — عند flag OFF (HS256) —
/// توكناً مكافئاً حرفياً لما كان يُصدره قبل التوحيد (بناء يدوي بـ new JwtSecurityToken(...) + HmacSha256).
///
/// «baseline» في كل اختبار = إعادة بناء التوكن بالطريقة القديمة يدوياً داخل الاختبار
/// (نفس claims الثمانية، نفس السرّ، نفس HS256، نفس المدة 60د، نفس issuer/audience، نفس نمط المُنشئ).
///
/// معزول تماماً: لا DB، لا web host. السرّ أدناه قيمة اختبار محلية غير مرتبطة بأي سرّ إنتاجي.
/// </summary>
public class JwtTokenSignerHs256EquivalenceTests
{
    // سرّ اختبار محلي فقط (طوله كافٍ لـ HMAC-SHA256؛ لا علاقة له بأي سرّ إنتاجي).
    private const string TestSecret = "unit-test-only-hs256-secret-key-do-not-use-in-prod-0123456789";
    private const int ExpiryMinutes = 60;

    // claims التي يقرأها/يبنيها JwtService الثمانية — نعيد بناءها بنفس الترتيب والقيم في الـ baseline.
    private static readonly string CompanyIdClaimType = "company_id";
    private static readonly string MerchantIdClaimType = "MerchantId";

    // ============ إعداد الموضع A (النظام قيد الاختبار) ============

    private static JwtService NewUnifiedJwtService()
    {
        // Jwt:Algorithm غير مضبوط ⇒ HS256 الافتراضي (flag OFF).
        var config = TestSupport.BuildConfig(TestSecret, ExpiryMinutes);
        var signer = new JwtTokenSigner(config);
        return new JwtService(signer, TestSecret, TestSupport.Issuer, TestSupport.Audience, ExpiryMinutes);
    }

    // ============ الـ baseline: بناء التوكن بالطريقة القديمة يدوياً (قبل التوحيد) ============

    /// <summary>
    /// يبني توكناً بنفس منطق GenerateAccessToken قبل التوحيد حرفياً:
    /// نفس claims الثمانية بنفس الترتيب، نفس السرّ HS256، نفس المدة، نفس نمط new JwtSecurityToken(...).
    /// نمرّر jti صراحةً للتحكم به في المقارنة (القيمة عشوائية في الإنتاج على أي حال).
    /// </summary>
    private static string BuildLegacyBaselineToken(User user, string jti, DateTime expiresUtc)
    {
        var claims = new[]
        {
            new Claim(JwtRegisteredClaimNames.Sub, user.Id.ToString()),
            new Claim(JwtRegisteredClaimNames.Jti, jti),
            new Claim(ClaimTypes.NameIdentifier, user.Id.ToString()),
            new Claim(ClaimTypes.Name, user.FullName),
            new Claim(ClaimTypes.MobilePhone, user.PhoneNumber),
            new Claim(ClaimTypes.Role, user.Role.ToString()),
            new Claim(MerchantIdClaimType, user.Merchant?.Id.ToString() ?? ""),
            new Claim(CompanyIdClaimType, user.CompanyId?.ToString() ?? "")
        };

        var key = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(TestSecret));
        var credentials = new SigningCredentials(key, SecurityAlgorithms.HmacSha256);

        var token = new JwtSecurityToken(
            issuer: TestSupport.Issuer,
            audience: TestSupport.Audience,
            claims: claims,
            expires: expiresUtc,
            signingCredentials: credentials);

        return new JwtSecurityTokenHandler().WriteToken(token);
    }

    private static JwtSecurityToken Read(string token)
        => new JwtSecurityTokenHandler().ReadJwtToken(token);

    private static string? ClaimValue(JwtSecurityToken jwt, string type)
        => jwt.Claims.FirstOrDefault(c => c.Type == type)?.Value;

    // ============ 1) الرأس: HS256 وبلا kid في الاثنين ============

    [Fact]
    public void Header_Both_Alg_IsHs256_And_NoKid()
    {
        var svc = NewUnifiedJwtService();
        var user = TestSupport.BuildUser(companyId: Guid.NewGuid());

        var produced = Read(svc.GenerateAccessToken(user));
        var baseline = Read(BuildLegacyBaselineToken(user, Guid.NewGuid().ToString(), DateTime.UtcNow.AddMinutes(ExpiryMinutes)));

        produced.Header.Alg.Should().Be(SecurityAlgorithms.HmacSha256);
        baseline.Header.Alg.Should().Be(SecurityAlgorithms.HmacSha256);

        produced.Header.Kid.Should().BeNull("الموضع A عند HS256 لا يضيف kid — مطابقة حرفية للسابق");
        baseline.Header.Kid.Should().BeNull();

        // typ متطابق أيضاً (JWT).
        produced.Header.Typ.Should().Be(baseline.Header.Typ);
    }

    // ============ 2) مجموعة claims وأسماؤها وقيمها متطابقة (عدا jti) ============

    [Fact]
    public void Claims_Produced_MatchBaseline_ExceptJti_ForCompanyUser()
    {
        var svc = NewUnifiedJwtService();
        var user = TestSupport.BuildUser(
            id: Guid.NewGuid(),
            companyId: Guid.NewGuid(),
            fullName: "أحمد محمد الفني",
            phone: "07711112222",
            role: UserRole.Technician,
            merchantId: Guid.NewGuid());

        var produced = Read(svc.GenerateAccessToken(user));

        // نبني baseline بنفس jti للتوكن المُنتَج كي نقارن كل شيء ما عدا jti بمساواة تامة للمجموعة.
        var producedJti = ClaimValue(produced, JwtRegisteredClaimNames.Jti);
        producedJti.Should().NotBeNullOrWhiteSpace("jti يجب أن يوجد في التوكن المُنتَج");

        var baseline = Read(BuildLegacyBaselineToken(user, producedJti!, produced.ValidTo));

        // مجموعة أنواع الـ claims متطابقة تماماً (نفس الثمانية بلا زيادة ولا نقص).
        var producedTypes = produced.Claims.Select(c => c.Type).OrderBy(t => t).ToArray();
        var baselineTypes = baseline.Claims.Select(c => c.Type).OrderBy(t => t).ToArray();
        producedTypes.Should().Equal(baselineTypes, "نفس مجموعة أنواع الـ claims بلا زيادة/نقص");

        // كل زوج (type,value) متطابق عند تثبيت jti — تكافؤ محتوى حرفي.
        var producedPairs = produced.Claims.Select(c => (c.Type, c.Value)).OrderBy(p => p).ToArray();
        var baselinePairs = baseline.Claims.Select(c => (c.Type, c.Value)).OrderBy(p => p).ToArray();
        producedPairs.Should().Equal(baselinePairs, "قيم كل الـ claims متطابقة عند تثبيت jti");

        // تحقّق صريح من كل claim على حدة (توثيق للسلوك).
        ClaimValue(produced, JwtRegisteredClaimNames.Sub).Should().Be(user.Id.ToString());
        ClaimValue(produced, ClaimTypes.NameIdentifier).Should().Be(user.Id.ToString());
        ClaimValue(produced, ClaimTypes.Name).Should().Be("أحمد محمد الفني");
        ClaimValue(produced, ClaimTypes.MobilePhone).Should().Be("07711112222");
        ClaimValue(produced, ClaimTypes.Role).Should().Be(UserRole.Technician.ToString());
        ClaimValue(produced, MerchantIdClaimType).Should().Be(user.Merchant!.Id.ToString());
        ClaimValue(produced, CompanyIdClaimType).Should().Be(user.CompanyId!.Value.ToString());
    }

    // ============ jti: موجود في الاثنين وعشوائي (لا يُقارَن بالقيمة) ============

    [Fact]
    public void Jti_ExistsInBoth_AndIsRandom_PerGeneration()
    {
        var svc = NewUnifiedJwtService();
        var user = TestSupport.BuildUser(companyId: Guid.NewGuid());

        var t1 = Read(svc.GenerateAccessToken(user));
        var t2 = Read(svc.GenerateAccessToken(user));
        var baseline = Read(BuildLegacyBaselineToken(user, Guid.NewGuid().ToString(), DateTime.UtcNow.AddMinutes(ExpiryMinutes)));

        ClaimValue(t1, JwtRegisteredClaimNames.Jti).Should().NotBeNullOrWhiteSpace();
        ClaimValue(baseline, JwtRegisteredClaimNames.Jti).Should().NotBeNullOrWhiteSpace();

        // عشوائية: توكنان متتاليان يحملان jti مختلفين (لا نقارن القيمة بين المُنتَج والـ baseline).
        ClaimValue(t1, JwtRegisteredClaimNames.Jti)
            .Should().NotBe(ClaimValue(t2, JwtRegisteredClaimNames.Jti), "jti عشوائي لكل توكن");
    }

    // ============ company_id فارغة للـ SuperAdmin — موجودة لا محذوفة، في الاثنين ============

    [Fact]
    public void CompanyId_Empty_ForSuperAdmin_InBoth_AndClaimSetsMatch()
    {
        var svc = NewUnifiedJwtService();
        var user = TestSupport.BuildUser(companyId: null, role: UserRole.SuperAdmin);

        var produced = Read(svc.GenerateAccessToken(user));
        var baseline = Read(BuildLegacyBaselineToken(
            user, ClaimValue(produced, JwtRegisteredClaimNames.Jti)!, produced.ValidTo));

        // company_id موجود (لا يُحذف) وقيمته فارغة في الاثنين.
        produced.Claims.Should().Contain(c => c.Type == CompanyIdClaimType, "الـ claim موجود دائماً");
        ClaimValue(produced, CompanyIdClaimType).Should().BeEmpty("SuperAdmin بلا شركة ⇒ company_id فارغ");
        ClaimValue(baseline, CompanyIdClaimType).Should().BeEmpty();

        // MerchantId فارغ أيضاً (لا Merchant).
        ClaimValue(produced, MerchantIdClaimType).Should().BeEmpty();

        // مجموعة (type,value) متطابقة عند تثبيت jti.
        var producedPairs = produced.Claims.Select(c => (c.Type, c.Value)).OrderBy(p => p).ToArray();
        var baselinePairs = baseline.Claims.Select(c => (c.Type, c.Value)).OrderBy(p => p).ToArray();
        producedPairs.Should().Equal(baselinePairs);
    }

    // ============ 4) المدة ≈ 3600s: exp ≈ (زمن التوليد + 60د) في الاثنين ============
    // ملاحظة موثّقة: new JwtSecurityToken(...) بلا notBefore/issuedAt لا يضيف iat ولا nbf —
    // فالتوكن يحمل exp فقط (لا iat) قبل التوحيد وبعده على حدٍّ سواء. لذا نقيس المدة عبر
    // exp مقابل لحظة التوليد (±2s تسامح)، ونتحقّق صراحةً من غياب iat/nbf في الاثنين (جزء من التكافؤ).

    [Fact]
    public void Lifetime_Exp_IsGenerationTimePlus3600s_InBoth_AndNoIatNoNbf()
    {
        var svc = NewUnifiedJwtService();
        var user = TestSupport.BuildUser(companyId: Guid.NewGuid());

        var beforeProduced = DateTimeOffset.UtcNow.ToUnixTimeSeconds();
        var produced = Read(svc.GenerateAccessToken(user));
        var afterProduced = DateTimeOffset.UtcNow.ToUnixTimeSeconds();

        var baselineExpectedExp = DateTime.UtcNow.AddMinutes(ExpiryMinutes);
        var baseline = Read(BuildLegacyBaselineToken(user, Guid.NewGuid().ToString(), baselineExpectedExp));

        long Exp(JwtSecurityToken t)
        {
            t.Payload.TryGetValue("exp", out var raw).Should().BeTrue("exp يجب أن يوجد");
            return Convert.ToInt64(raw);
        }

        // exp للتوكن المُنتَج ضمن [before+3600-2, after+3600+2] — أي مدة 3600s حول لحظة التوليد.
        Exp(produced).Should().BeInRange(beforeProduced + 3600 - 2, afterProduced + 3600 + 2,
            "الموضع A: exp = UtcNow + 60د (=3600s) بلا انحراف عن السابق");

        // سلوك حتمي مطابق للسابق: لا iat ولا nbf يُضافان (منشئ JwtSecurityToken بلا notBefore).
        foreach (var t in new[] { produced, baseline })
        {
            t.Payload.ContainsKey("iat").Should().BeFalse("المُنشئ بلا issuedAt لا يضيف iat — مطابقة للسابق");
            t.Payload.ContainsKey("nbf").Should().BeFalse("المُنشئ بلا notBefore لا يضيف nbf — مطابقة للسابق");
        }
    }

    [Fact]
    public void Expiry_IsRoughlyNowPlus60Min_ForProducedToken()
    {
        var svc = NewUnifiedJwtService();
        var before = DateTime.UtcNow;

        var produced = Read(svc.GenerateAccessToken(TestSupport.BuildUser(companyId: Guid.NewGuid())));

        var expected = before.AddMinutes(ExpiryMinutes);
        // تسامح ±2s حول UtcNow لحظة التوليد.
        produced.ValidTo.Should().BeCloseTo(expected, TimeSpan.FromSeconds(2),
            "exp ≈ UtcNow + 60min (لا انحراف عن السلوك السابق)");
    }

    // ============ issuer/audience متطابقان ============

    [Fact]
    public void IssuerAndAudience_Match_Baseline()
    {
        var svc = NewUnifiedJwtService();
        var user = TestSupport.BuildUser(companyId: Guid.NewGuid());

        var produced = Read(svc.GenerateAccessToken(user));
        var baseline = Read(BuildLegacyBaselineToken(user, Guid.NewGuid().ToString(), DateTime.UtcNow.AddMinutes(ExpiryMinutes)));

        produced.Issuer.Should().Be(TestSupport.Issuer);
        produced.Issuer.Should().Be(baseline.Issuer);

        produced.Audiences.Should().ContainSingle().Which.Should().Be(TestSupport.Audience);
        produced.Audiences.Should().Equal(baseline.Audiences);
    }

    // ============ 5) round-trip: التوكن المُنتَج يُتحقَّق بنجاح بمفتاح HS256 ============

    [Fact]
    public void ProducedToken_ValidatesSuccessfully_WithHs256Parameters()
    {
        var svc = NewUnifiedJwtService();
        var token = svc.GenerateAccessToken(TestSupport.BuildUser(companyId: Guid.NewGuid()));

        var handler = new JwtSecurityTokenHandler();
        var parameters = new TokenValidationParameters
        {
            ValidateIssuerSigningKey = true,
            IssuerSigningKey = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(TestSecret)),
            ValidAlgorithms = new[] { SecurityAlgorithms.HmacSha256 },
            ValidateIssuer = true,
            ValidIssuer = TestSupport.Issuer,
            ValidateAudience = true,
            ValidAudience = TestSupport.Audience,
            ValidateLifetime = true,
            ClockSkew = TimeSpan.Zero
        };

        var act = () => handler.ValidateToken(token, parameters, out _);
        act.Should().NotThrow("التوكن المُنتَج من الموضع A ما زال صالحاً للمسار الحالي (HS256)");

        // وأيضاً عبر ValidateToken الخاص بالخدمة نفسها.
        svc.ValidateToken(token).Should().BeTrue();
    }

    [Fact]
    public void ProducedAndBaseline_HaveIdenticalHeaderAndPayloadSegments_WhenJtiAndExpFixed()
    {
        // إثبات التكافؤ الحرفي على مستوى البايت للجزأين (header.payload) عند تثبيت المتغيّرين
        // الوحيدين غير الحتميين: jti (عشوائي) و exp/iat (زمن التوليد). التوقيع يُستثنى لأنه دالة الحمولة.
        var svc = NewUnifiedJwtService();
        var user = TestSupport.BuildUser(
            id: Guid.NewGuid(),
            companyId: Guid.NewGuid(),
            fullName: "مستخدم عربي للاختبار",
            phone: "07733334444",
            role: UserRole.Manager,
            merchantId: Guid.NewGuid());

        var producedRaw = svc.GenerateAccessToken(user);
        var produced = Read(producedRaw);

        // نبني baseline بنفس jti ونفس exp بالضبط الملتقطَين من التوكن المُنتَج.
        var jti = ClaimValue(produced, JwtRegisteredClaimNames.Jti)!;
        var baselineRaw = BuildLegacyBaselineToken(user, jti, produced.ValidTo);

        var producedParts = producedRaw.Split('.');
        var baselineParts = baselineRaw.Split('.');

        // header متطابق حرفياً (نفس alg بلا kid، نفس typ).
        producedParts[0].Should().Be(baselineParts[0], "الرأس المُسلسل متطابق بايت-ببايت");
        // payload متطابق حرفياً عند تثبيت jti+exp (نفس الـ claims وترتيبها).
        producedParts[1].Should().Be(baselineParts[1], "الحمولة المُسلسلة متطابقة بايت-ببايت عند تثبيت jti+exp");
        // التوقيع أيضاً متطابق لأنه HMAC حتمي على نفس (header.payload) بنفس السرّ.
        producedParts[2].Should().Be(baselineParts[2], "توقيع HMAC حتمي ⇒ متطابق على نفس الحمولة/السرّ");
    }

    // ============ 6) محارف عربية في claim الاسم ============

    [Fact]
    public void ArabicName_RoundTrips_Intact_AndMatchesBaseline()
    {
        var svc = NewUnifiedJwtService();
        const string arabicName = "عبد الرحمن عبّاس الخفاجي";
        var user = TestSupport.BuildUser(companyId: Guid.NewGuid(), fullName: arabicName, role: UserRole.Manager);

        var produced = Read(svc.GenerateAccessToken(user));
        var baseline = Read(BuildLegacyBaselineToken(
            user, ClaimValue(produced, JwtRegisteredClaimNames.Jti)!, produced.ValidTo));

        // الاسم العربي يُحفظ كما هو (UTF-8) بلا تشويه في الاثنين.
        ClaimValue(produced, ClaimTypes.Name).Should().Be(arabicName);
        ClaimValue(baseline, ClaimTypes.Name).Should().Be(arabicName);
        ClaimValue(produced, ClaimTypes.Name).Should().Be(ClaimValue(baseline, ClaimTypes.Name));
    }
}
