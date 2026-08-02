using System.Reflection;
using FluentAssertions;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging.Abstractions;
using Sadara.API.Controllers;
using Sadara.Api.Tests.Fakes;
using Sadara.Domain.Entities;
using Sadara.Infrastructure.Identity;
using Xunit;

namespace Sadara.Api.Tests;

/// <summary>
/// اختبار وحدة يثبّت "عقد استجابة" endpoint الجديد GetNodeConfig(Guid id)
/// في SuperAdminController — معزول تماماً عن قاعدة البيانات والـ web host.
///
/// الغرض الأمني: ضمان أن الـ endpoint لا يعيد سوى الحقول الخمسة المصرّح بها،
/// وأن أي حقل حسّاس يُضاف مستقبلاً (password/secret/key/token/hash/apikey)
/// سيكسر الاختبار فوراً (حارس التسريب).
/// </summary>
public class SuperAdminControllerNodeConfigTests
{
    // الحقول الخمسة المتوقّعة — بالضبط، لا أكثر ولا أقل.
    private static readonly string[] ExpectedKeys =
    {
        "company_id", "company_name", "node_id", "gateway_url", "jwks_url"
    };

    // كلمات حسّاسة يجب ألّا يطابقها أي اسم خاصية في data.
    private static readonly string[] SensitiveTokens =
    {
        "password", "secret", "key", "token", "hash", "apikey"
    };

    private const string GatewayUrl = "https://gateway.test.local";

    private static SuperAdminController BuildController(FakeCompanyRepository repo, string? gatewayUrl = GatewayUrl)
    {
        var settings = new Dictionary<string, string?>();
        if (gatewayUrl is not null)
            settings["Distributed:GatewayUrl"] = gatewayUrl;
        // Jwt:Secret مطلوب فقط لبناء JwtTokenSigner (HS256 الافتراضي)؛ GetNodeConfig لا يستعمل المُوقّع.
        settings["Jwt:Secret"] = "unit-test-only-hs256-secret-key-do-not-use-in-prod-0123456789";

        var configuration = new ConfigurationBuilder()
            .AddInMemoryCollection(settings)
            .Build();

        var uow = new FakeUnitOfWork(repo);

        return new SuperAdminController(
            uow,
            configuration,
            NullLogger<SuperAdminController>.Instance,
            new HttpClient(),
            new JwtTokenSigner(configuration));
    }

    /// <summary>يستخرج كائن data من غلاف الاستجابة { success, data } عبر reflection.</summary>
    private static object ExtractData(object? responseValue)
    {
        responseValue.Should().NotBeNull("الاستجابة يجب أن تحمل جسماً");
        var dataProp = responseValue!.GetType().GetProperty("data", BindingFlags.Public | BindingFlags.Instance);
        dataProp.Should().NotBeNull("الغلاف يجب أن يحتوي على خاصية data");
        var data = dataProp!.GetValue(responseValue);
        data.Should().NotBeNull("data يجب ألّا تكون null في حالة النجاح");
        return data!;
    }

    private static IReadOnlyDictionary<string, object?> DataProperties(object data)
    {
        return data.GetType()
            .GetProperties(BindingFlags.Public | BindingFlags.Instance)
            .ToDictionary(p => p.Name, p => p.GetValue(data));
    }

    // ============================================================
    // 1) حالة النجاح: OkObjectResult + بالضبط المفاتيح الخمسة
    // ============================================================
    [Fact]
    public async Task GetNodeConfig_ExistingCompany_Returns_Ok_With_Exactly_Five_Fields()
    {
        var id = Guid.NewGuid();
        var repo = new FakeCompanyRepository().Seed(new Company
        {
            Id = id,
            Name = "شركة الاختبار",
            Code = "TST",
            IsDeleted = false
        });

        var controller = BuildController(repo);

        var result = await controller.GetNodeConfig(id);

        var ok = result.Should().BeOfType<OkObjectResult>().Subject;
        var data = ExtractData(ok.Value);
        var props = DataProperties(data);

        props.Keys.Should().BeEquivalentTo(ExpectedKeys,
            "يجب أن يعيد الحقول الخمسة المصرّح بها بالضبط — لا أقل ولا أكثر");
        props.Should().HaveCount(5, "أي حقل إضافي قد يكون تسريباً للبيانات");
    }

    // ============================================================
    // 2) حارس التسريب: لا اسم خاصية يطابق كلمة حسّاسة
    // ============================================================
    [Fact]
    public async Task GetNodeConfig_Response_Contains_No_Sensitive_Field_Names()
    {
        var id = Guid.NewGuid();
        var repo = new FakeCompanyRepository().Seed(new Company
        {
            Id = id,
            Name = "شركة الاختبار",
            Code = "TST",
            IsDeleted = false
        });

        var controller = BuildController(repo);

        var result = await controller.GetNodeConfig(id);
        var ok = result.Should().BeOfType<OkObjectResult>().Subject;
        var data = ExtractData(ok.Value);
        var props = DataProperties(data);

        foreach (var name in props.Keys)
        {
            var lower = name.ToLowerInvariant();
            foreach (var token in SensitiveTokens)
            {
                lower.Contains(token).Should().BeFalse(
                    $"اسم الحقل '{name}' يطابق الكلمة الحسّاسة '{token}' — تسريب محتمل");
            }
        }
    }

    // ============================================================
    // 3) حالات NotFound: شركة غير موجودة أو محذوفة
    // ============================================================
    [Fact]
    public async Task GetNodeConfig_MissingCompany_Returns_NotFound()
    {
        var repo = new FakeCompanyRepository(); // فارغ — GetByIdAsync تعيد null
        var controller = BuildController(repo);

        var result = await controller.GetNodeConfig(Guid.NewGuid());

        result.Should().BeOfType<NotFoundObjectResult>();
    }

    [Fact]
    public async Task GetNodeConfig_DeletedCompany_Returns_NotFound()
    {
        var id = Guid.NewGuid();
        var repo = new FakeCompanyRepository().Seed(new Company
        {
            Id = id,
            Name = "شركة محذوفة",
            Code = "DEL",
            IsDeleted = true
        });

        var controller = BuildController(repo);

        var result = await controller.GetNodeConfig(id);

        result.Should().BeOfType<NotFoundObjectResult>();
    }

    // ============================================================
    // 4) القيم المشتقّة: node_id و jwks_url
    // ============================================================
    [Fact]
    public async Task GetNodeConfig_NodeId_Uses_Code_When_Present_And_Jwks_Derived_From_Gateway()
    {
        var id = Guid.NewGuid();
        var repo = new FakeCompanyRepository().Seed(new Company
        {
            Id = id,
            Name = "شركة برمز",
            Code = "ACME",
            IsDeleted = false
        });

        var controller = BuildController(repo, GatewayUrl);

        var result = await controller.GetNodeConfig(id);
        var ok = result.Should().BeOfType<OkObjectResult>().Subject;
        var props = DataProperties(ExtractData(ok.Value));

        props["node_id"].Should().Be("node-ACME");
        props["gateway_url"].Should().Be(GatewayUrl);
        props["jwks_url"].Should().Be(GatewayUrl + "/.well-known/jwks.json");
        props["company_id"].Should().Be(id);
        props["company_name"].Should().Be("شركة برمز");
    }

    [Fact]
    public async Task GetNodeConfig_NodeId_FallsBack_To_Id_When_Code_Is_Blank()
    {
        var id = Guid.NewGuid();
        var repo = new FakeCompanyRepository().Seed(new Company
        {
            Id = id,
            Name = "شركة بلا رمز",
            Code = "   ", // فراغ/مسافات فقط
            IsDeleted = false
        });

        var controller = BuildController(repo);

        var result = await controller.GetNodeConfig(id);
        var ok = result.Should().BeOfType<OkObjectResult>().Subject;
        var props = DataProperties(ExtractData(ok.Value));

        props["node_id"].Should().Be("node-" + id);
    }

    [Fact]
    public async Task GetNodeConfig_Uses_Default_Gateway_When_Config_Missing()
    {
        var id = Guid.NewGuid();
        var repo = new FakeCompanyRepository().Seed(new Company
        {
            Id = id,
            Name = "شركة",
            Code = "X",
            IsDeleted = false
        });

        // gatewayUrl = null → لا مفتاح Distributed:GatewayUrl → يستخدم الافتراضي
        var controller = BuildController(repo, gatewayUrl: null);

        var result = await controller.GetNodeConfig(id);
        var ok = result.Should().BeOfType<OkObjectResult>().Subject;
        var props = DataProperties(ExtractData(ok.Value));

        props["gateway_url"].Should().Be("https://72.61.183.61");
        props["jwks_url"].Should().Be("https://72.61.183.61/.well-known/jwks.json");
    }
}
