using System.Security.Claims;
using System.Text.Json;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging.Abstractions;
using Sadara.API.Controllers;
using Sadara.Domain.Entities;
using Sadara.Domain.Enums;
using Sadara.Infrastructure.Data;
using Sadara.Integration.Tests.Support;
using Xunit;

namespace Sadara.Integration.Tests;

/// <summary>
/// جولة معالجة المرحلة 0-أ (مراجعة الكود + الأمن) على مسار JWT في <see cref="InternalDataController"/>:
///   B1  سقف الدور غير هرمي تحت المدير (موظف موارد بشرية يدير الفنيين، لا المدراء).
///   C2  لا كلمة مرور نصية؛ كلمة مرور FTTH/كود البصمة لصاحبها؛ الراتب والصلاحيات خارج قائمة الزملاء.
///   C3  موظف جديد بصلاحيات "{}" وكلمة مرور عشوائية تُعاد مرة واحدة.
///   S2  401 عربية لتوكن منتهٍ.
///   S9  إنشاء سجل تفعيل يتطلب إضافة الاشتراكات؛ غير المحاسب يرى سجلاته فقط.
///   S10 تقرير التسديد لصاحبه أو للمحاسب فقط.
/// </summary>
[Collection("Postgres")]
public sealed class InternalDataRemediationTests
{
    private readonly PostgresFixture _fx;
    private static readonly string TestApiKey = "test-" + Guid.NewGuid().ToString("N");

    private const string HrEmployeesPerms =
        "{\"hr.employees\":{\"view\":true,\"add\":true,\"edit\":true,\"delete\":true}}";
    private const string SubsAddPerms = "{\"subscriptions\":{\"view\":true,\"add\":true}}";

    public InternalDataRemediationTests(PostgresFixture fx) => _fx = fx;

    // ═══════ بنية تحتية ═══════

    private Guid NewCompany()
    {
        using var ctx = _fx.CreateContext(PostgresFixture.SystemTenant);
        var suffix = Guid.NewGuid().ToString("N")[..8];
        var c = new Company
        {
            Id = Guid.NewGuid(), Name = "شركة " + suffix, Code = "RM-" + suffix, MaxUsers = 100,
        };
        ctx.Set<Company>().Add(c);
        ctx.SaveChanges();
        return c.Id;
    }

    private Guid NewUser(Guid companyId, UserRole role, string? firstV2 = null, string? secondV2 = null,
        string? ftthPassword = null, string? securityCode = null, decimal? salary = null, string? fullName = null)
    {
        using var ctx = _fx.CreateContext(PostgresFixture.SystemTenant);
        var id = Guid.NewGuid();
        var tag = id.ToString("N")[..8];
        ctx.Set<User>().Add(new User
        {
            Id = id,
            Username = "u-" + tag,
            FullName = fullName ?? "مستخدم " + tag,
            FtthUsername = "ftth-" + tag,
            PhoneNumber = $"07{Random.Shared.Next(100000000, 999999999)}",
            CompanyId = companyId,
            Role = role,
            IsActive = true,
            FirstSystemPermissionsV2 = firstV2,
            SecondSystemPermissionsV2 = secondV2,
            FtthPasswordEncrypted = ftthPassword,
            AttendanceSecurityCode = securityCode,
            Salary = salary,
            PlainPassword = "legacy-plain",
            PasswordHash = BCrypt.Net.BCrypt.HashPassword("old-pass-1"),
        });
        ctx.SaveChanges();
        return id;
    }

    private User ReadUser(Guid id)
    {
        using var ctx = _fx.CreateContext(PostgresFixture.SystemTenant);
        return ctx.Set<User>().AsNoTracking().IgnoreQueryFilters().First(u => u.Id == id);
    }

    private (InternalDataController Controller, SadaraDbContext Db) Build(
        Guid? jwtUserId = null, Guid? tokenCompanyId = null, string role = "Employee", string? bearerHeader = null)
    {
        var db = _fx.CreateContext(PostgresFixture.SystemTenant);
        var uow = new Sadara.Infrastructure.Repositories.UnitOfWork(db);
        var config = new ConfigurationBuilder()
            .AddInMemoryCollection(new Dictionary<string, string?> { ["Security:InternalApiKey"] = TestApiKey })
            .Build();
        var controller = new InternalDataController(uow, config, db, NullLogger<InternalDataController>.Instance);

        ClaimsPrincipal principal = jwtUserId.HasValue
            ? new ClaimsPrincipal(new ClaimsIdentity(new List<Claim>
                {
                    new(ClaimTypes.NameIdentifier, jwtUserId.Value.ToString()),
                    new(ClaimTypes.Role, role),
                    new("company_id", (tokenCompanyId ?? Guid.Empty).ToString()),
                }, authenticationType: "Bearer"))
            : new ClaimsPrincipal(new ClaimsIdentity());

        var http = new DefaultHttpContext { User = principal };
        if (bearerHeader != null) http.Request.Headers.Authorization = bearerHeader;
        controller.ControllerContext = new ControllerContext { HttpContext = http };
        return (controller, db);
    }

    private static int StatusOf(IActionResult r) => r switch
    {
        ObjectResult o => o.StatusCode ?? 200,
        StatusCodeResult s => s.StatusCode,
        _ => throw new Xunit.Sdk.XunitException("نتيجة غير متوقعة: " + r.GetType().Name),
    };

    private static JsonElement Json(IActionResult r) =>
        JsonDocument.Parse(JsonSerializer.Serialize(((ObjectResult)r).Value)).RootElement.Clone();

    private static JsonElement Body(object o) =>
        JsonDocument.Parse(JsonSerializer.Serialize(o)).RootElement.Clone();

    // ═══════ B1: سقف الدور ═══════

    [SkippableFact]
    public async Task B1_HrEmployee_CanManageTechnician()
    {
        _fx.SkipIfUnavailable();
        var co = NewCompany();
        var hr = NewUser(co, UserRole.Employee, firstV2: HrEmployeesPerms);
        var tech = NewUser(co, UserRole.Technician);
        var tech2 = NewUser(co, UserRole.Technician);
        var (c, db) = Build(hr, co);
        await using var _ = db;

        Assert.Equal(200, StatusOf(await c.UpdateEmployeePassword(co, tech,
            new InternalUpdatePasswordRequest { NewPassword = "newpass123" })));
        Assert.True(BCrypt.Net.BCrypt.Verify("newpass123", ReadUser(tech).PasswordHash));

        Assert.Equal(200, StatusOf(await c.UpdateCompanyEmployee(co, tech,
            new InternalUpdateEmployeeRequest { Center = "مركز-1", Role = "technician" })));
        Assert.Equal(200, StatusOf(await c.GetCompanyEmployeeById(co, tech)));

        var created = await c.CreateCompanyEmployee(co, new InternalCreateEmployeeRequest
        {
            FullName = "فني جديد", PhoneNumber = $"07{Random.Shared.Next(100000000, 999999999)}",
            Role = "technician", Password = "secret123",
        });
        Assert.Equal(200, StatusOf(created));

        Assert.Equal(200, StatusOf(await c.DeleteCompanyEmployee(co, tech2)));
    }

    [SkippableFact]
    public async Task B1_HrEmployee_CannotTouchManagementRoles()
    {
        _fx.SkipIfUnavailable();
        var co = NewCompany();
        var hr = NewUser(co, UserRole.Employee, firstV2: HrEmployeesPerms);
        var manager = NewUser(co, UserRole.Manager);
        var admin = NewUser(co, UserRole.CompanyAdmin);
        var tech = NewUser(co, UserRole.Technician);
        var (c, db) = Build(hr, co);
        await using var _ = db;

        Assert.Equal(403, StatusOf(await c.UpdateEmployeePassword(co, manager,
            new InternalUpdatePasswordRequest { NewPassword = "hacked123" })));
        Assert.Equal(403, StatusOf(await c.UpdateEmployeePassword(co, admin,
            new InternalUpdatePasswordRequest { NewPassword = "hacked123" })));
        Assert.Equal(403, StatusOf(await c.GetCompanyEmployeeById(co, admin)));
        Assert.Equal(403, StatusOf(await c.DeleteCompanyEmployee(co, manager)));
        // لا ترقية فني إلى دور إداري، ولا إنشاء مدير
        Assert.Equal(403, StatusOf(await c.UpdateCompanyEmployee(co, tech,
            new InternalUpdateEmployeeRequest { Role = "manager" })));
        Assert.Equal(403, StatusOf(await c.CreateCompanyEmployee(co, new InternalCreateEmployeeRequest
        {
            FullName = "x", PhoneNumber = $"07{Random.Shared.Next(100000000, 999999999)}", Role = "admin",
        })));
        Assert.Equal(UserRole.Technician, ReadUser(tech).Role);
    }

    [SkippableFact]
    public async Task B1_Manager_CannotTouchCompanyAdmin_ButCanManageManagerPeer()
    {
        _fx.SkipIfUnavailable();
        var co = NewCompany();
        var mgr = NewUser(co, UserRole.Manager);
        var peer = NewUser(co, UserRole.Manager);
        var admin = NewUser(co, UserRole.CompanyAdmin);
        var (c, db) = Build(mgr, co, role: "Manager");
        await using var _ = db;

        Assert.Equal(403, StatusOf(await c.UpdateEmployeePassword(co, admin,
            new InternalUpdatePasswordRequest { NewPassword = "hacked123" })));
        Assert.Equal(200, StatusOf(await c.UpdateEmployeePassword(co, peer,
            new InternalUpdatePasswordRequest { NewPassword = "peerpass1" })));
    }

    // ═══════ C2: الحقول الحسّاسة ═══════

    [SkippableFact]
    public async Task C2_GetEmployee_NeverReturnsPlainPassword_AndHidesCredentialsFromNonOwner()
    {
        _fx.SkipIfUnavailable();
        var co = NewCompany();
        var mgr = NewUser(co, UserRole.Manager);
        var tech = NewUser(co, UserRole.Technician, ftthPassword: "ftth-secret", securityCode: "4321");

        var (c, db) = Build(mgr, co, role: "Manager");
        await using var _ = db;
        var data = Json(await c.GetCompanyEmployeeById(co, tech)).GetProperty("data");
        Assert.False(data.TryGetProperty("PlainPassword", out var plain1), plain1.ToString());
        Assert.Equal(JsonValueKind.Null, data.GetProperty("FtthPasswordEncrypted").ValueKind);
        Assert.Equal(JsonValueKind.Null, data.GetProperty("AttendanceSecurityCode").ValueKind);
        Assert.True(data.GetProperty("CredentialsHidden").GetBoolean());
        Assert.True(data.GetProperty("SecurityCodeHidden").GetBoolean());

        // صاحب الحساب يرى اعتماداته
        var (own, db2) = Build(tech, co, role: "Technician");
        await using var __ = db2;
        var mine = Json(await own.GetCompanyEmployeeById(co, tech)).GetProperty("data");
        Assert.False(mine.TryGetProperty("PlainPassword", out var plain2), plain2.ToString());
        Assert.Equal("ftth-secret", mine.GetProperty("FtthPasswordEncrypted").GetString());
        Assert.Equal("4321", mine.GetProperty("AttendanceSecurityCode").GetString());
    }

    [SkippableFact]
    public async Task C2_HrSecurityCodeGrant_SeesAttendanceCode_ButNotFtthPassword()
    {
        _fx.SkipIfUnavailable();
        var co = NewCompany();
        var hr = NewUser(co, UserRole.Employee,
            firstV2: "{\"hr.employees\":{\"view\":true,\"edit\":true},\"hr.security_code\":{\"view\":true}}");
        var tech = NewUser(co, UserRole.Technician, ftthPassword: "ftth-secret", securityCode: "9876");
        var (c, db) = Build(hr, co);
        await using var _ = db;

        var data = Json(await c.GetCompanyEmployeeById(co, tech)).GetProperty("data");
        Assert.Equal("9876", data.GetProperty("AttendanceSecurityCode").GetString());
        Assert.Equal(JsonValueKind.Null, data.GetProperty("FtthPasswordEncrypted").ValueKind);
    }

    [SkippableFact]
    public async Task C2_ColleagueList_HidesSalaryAndPermissions_UnlessManager()
    {
        _fx.SkipIfUnavailable();
        var co = NewCompany();
        var plain = NewUser(co, UserRole.Employee, firstV2: "{}");
        var mgr = NewUser(co, UserRole.Manager);
        NewUser(co, UserRole.Technician, salary: 750000m);

        var (c, db) = Build(plain, co);
        await using var _ = db;
        foreach (var e in Json(await c.GetCompanyEmployees(co)).GetProperty("data").EnumerateArray())
        {
            Assert.Equal(JsonValueKind.Null, e.GetProperty("Salary").ValueKind);
            Assert.Equal(JsonValueKind.Null, e.GetProperty("FirstSystemPermissions").ValueKind);
        }

        var (m, db2) = Build(mgr, co, role: "Manager");
        await using var __ = db2;
        Assert.Contains(Json(await m.GetCompanyEmployees(co)).GetProperty("data").EnumerateArray(),
            e => e.GetProperty("Salary").ValueKind == JsonValueKind.Number);
    }

    [SkippableFact]
    public async Task C2_PasswordChange_ClearsStoredPlaintext()
    {
        _fx.SkipIfUnavailable();
        var co = NewCompany();
        var mgr = NewUser(co, UserRole.Manager);
        var tech = NewUser(co, UserRole.Technician);
        var (c, db) = Build(mgr, co, role: "Manager");
        await using var _ = db;

        Assert.Equal(200, StatusOf(await c.UpdateEmployeePassword(co, tech,
            new InternalUpdatePasswordRequest { NewPassword = "brandnew1" })));
        Assert.Null(ReadUser(tech).PlainPassword);
    }

    // ═══════ C3: موظف جديد ═══════

    [SkippableFact]
    public async Task C3_NewEmployee_GetsExplicitEmptyPermissions_AndGeneratedPassword()
    {
        _fx.SkipIfUnavailable();
        var co = NewCompany();
        var mgr = NewUser(co, UserRole.Manager);
        var (c, db) = Build(mgr, co, role: "Manager");
        await using var _ = db;

        var r = await c.CreateCompanyEmployee(co, new InternalCreateEmployeeRequest
        {
            FullName = "موظف بلا كلمة مرور", PhoneNumber = $"07{Random.Shared.Next(100000000, 999999999)}",
        });
        Assert.Equal(200, StatusOf(r));
        var data = Json(r).GetProperty("data");
        var generated = data.GetProperty("GeneratedPassword").GetString();
        Assert.False(string.IsNullOrEmpty(generated));
        Assert.Equal(10, generated!.Length);

        var created = ReadUser(Guid.Parse(data.GetProperty("Id").GetString()!));
        Assert.Equal("{}", created.FirstSystemPermissionsV2);
        Assert.Equal("{}", created.SecondSystemPermissionsV2);
        Assert.True(BCrypt.Net.BCrypt.Verify(generated, created.PasswordHash));
        Assert.False(BCrypt.Net.BCrypt.Verify("123456", created.PasswordHash));
        Assert.Null(created.PlainPassword);
        // V2 "{}" ⇒ لا صلاحية (لا fail-open)
        Assert.False(Sadara.API.Authorization.RequirePermissionAttribute.HasPermission(
            created.FirstSystemPermissionsV2, "accounting", "view"));
    }

    [SkippableFact]
    public async Task C3_ExplicitPassword_NotReturned_AndShortPasswordRejected()
    {
        _fx.SkipIfUnavailable();
        var co = NewCompany();
        var mgr = NewUser(co, UserRole.Manager);
        var (c, db) = Build(mgr, co, role: "Manager");
        await using var _ = db;

        var ok = await c.CreateCompanyEmployee(co, new InternalCreateEmployeeRequest
        {
            FullName = "x", PhoneNumber = $"07{Random.Shared.Next(100000000, 999999999)}", Password = "chosen123",
        });
        Assert.Equal(200, StatusOf(ok));
        Assert.Equal(JsonValueKind.Null, Json(ok).GetProperty("data").GetProperty("GeneratedPassword").ValueKind);

        Assert.Equal(400, StatusOf(await c.CreateCompanyEmployee(co, new InternalCreateEmployeeRequest
        {
            FullName = "y", PhoneNumber = $"07{Random.Shared.Next(100000000, 999999999)}", Password = "123",
        })));
    }

    // ═══════ S2: رسالة 401 ═══════

    [SkippableFact]
    public async Task S2_ExpiredBearer_GetsArabicSessionMessage_LegacyKeepsOldMessage()
    {
        _fx.SkipIfUnavailable();
        var (c, db) = Build(bearerHeader: "Bearer expired.token.value");
        await using var _ = db;
        var r = await c.GetSubscriptionLogs(null, null, null, null, 10);
        Assert.Equal(401, StatusOf(r));
        Assert.Equal("انتهت الجلسة — أعد تسجيل الدخول", Json(r).GetProperty("message").GetString());

        var (k, db2) = Build();
        await using var __ = db2;
        Assert.Equal("Invalid API Key",
            Json(await k.GetSubscriptionLogs(null, null, null, null, 10)).GetProperty("message").GetString());
    }

    // ═══════ S9: سجلات التفعيل ═══════

    [SkippableFact]
    public async Task S9_ViewerWithoutSubscriptionsAdd_CannotCreateLog()
    {
        _fx.SkipIfUnavailable();
        var co = NewCompany();
        var viewer = NewUser(co, UserRole.Viewer); // V2 فارغ ⇒ لا منح صريح
        var tech = NewUser(co, UserRole.Technician);
        var (c, db) = Build(viewer, co, role: "Viewer");
        await using var _ = db;
        var marker = "viewer-" + Guid.NewGuid().ToString("N");

        var r = await c.CreateSubscriptionLog(Body(new
        {
            customerName = marker, linkedTechnicianId = tech.ToString(),
            collectionType = "technician", planPrice = 99999,
        }));
        Assert.Equal(403, StatusOf(r));
        await using var check = _fx.CreateContext(PostgresFixture.SystemTenant);
        Assert.False(await check.Set<SubscriptionLog>().AnyAsync(l => l.CustomerName == marker));
    }

    [SkippableFact]
    public async Task S9_NonAccountingOperator_SeesOnlyOwnLogs()
    {
        _fx.SkipIfUnavailable();
        var co = NewCompany();
        var op = NewUser(co, UserRole.Employee, firstV2: "{}", secondV2: SubsAddPerms);
        var other = NewUser(co, UserRole.Employee, firstV2: "{}", secondV2: SubsAddPerms);
        var acct = NewUser(co, UserRole.Employee, firstV2: "{\"accounting\":{\"view\":true}}");
        using (var ctx = _fx.CreateContext(PostgresFixture.SystemTenant))
        {
            ctx.Set<SubscriptionLog>().AddRange(
                new SubscriptionLog { CustomerName = "mine", CompanyId = co, UserId = op, ActivationDate = DateTime.UtcNow },
                new SubscriptionLog { CustomerName = "theirs", CompanyId = co, UserId = other, ActivationDate = DateTime.UtcNow });
            ctx.SaveChanges();
        }

        var (c, db) = Build(op, co);
        await using var _ = db;
        var mine = Json(await c.GetSubscriptionLogs(null, null, null, null, 1000)).EnumerateArray().ToList();
        Assert.NotEmpty(mine);
        Assert.All(mine, e => Assert.Equal(op.ToString(), e.GetProperty("UserId").GetString()));

        var (a, db2) = Build(acct, co);
        await using var __ = db2;
        var all = Json(await a.GetSubscriptionLogs(null, null, null, null, 1000)).EnumerateArray()
            .Select(e => e.GetProperty("UserId").GetString()).ToHashSet();
        Assert.Contains(op.ToString(), all);
        Assert.Contains(other.ToString(), all);
    }

    // ═══════ S10: تقارير التسديد ═══════

    [SkippableFact]
    public async Task S10_Operator_CanSubmitOwnReport_NotAnotherOperators()
    {
        _fx.SkipIfUnavailable();
        var co = NewCompany();
        var op = NewUser(co, UserRole.Employee, firstV2: "{}", secondV2: SubsAddPerms);
        var other = NewUser(co, UserRole.Employee, firstV2: "{}", fullName: "مشغل آخر " + Guid.NewGuid().ToString("N")[..6]);
        var opFtth = ReadUser(op).FtthUsername!;
        var otherName = ReadUser(other).FullName;
        var (c, db) = Build(op, co);
        await using var _ = db;

        Assert.Equal(403, StatusOf(await c.CreateSettlementReport(Body(new
        {
            operatorName = otherName, reportDate = "2026-10-01", items = Array.Empty<object>(),
        }))));
        Assert.Equal(403, StatusOf(await c.CreateSettlementReport(Body(new
        {
            operatorName = opFtth, operatorId = other.ToString(), reportDate = "2026-10-01", items = Array.Empty<object>(),
        }))));
        Assert.Equal(200, StatusOf(await c.CreateSettlementReport(Body(new
        {
            operatorName = opFtth, reportDate = "2026-10-01", items = Array.Empty<object>(),
        }))));
    }

    [SkippableFact]
    public async Task S10_Operator_CannotUpdateOrOverwriteAnotherOperatorsReport()
    {
        _fx.SkipIfUnavailable();
        var co = NewCompany();
        var op = NewUser(co, UserRole.Employee, firstV2: "{}");
        var other = NewUser(co, UserRole.Employee, firstV2: "{}");
        var otherFtth = ReadUser(other).FtthUsername!;
        long reportId;
        using (var ctx = _fx.CreateContext(PostgresFixture.SystemTenant))
        {
            var rep = new DailySettlementReport
            {
                ReportDate = DateTime.SpecifyKind(new DateTime(2026, 10, 2).AddHours(-3), DateTimeKind.Utc),
                OperatorName = otherFtth, OperatorId = other.ToString(), CompanyId = co, Notes = "أصلي",
            };
            ctx.Set<DailySettlementReport>().Add(rep);
            ctx.SaveChanges();
            reportId = rep.Id;
        }

        var (c, db) = Build(op, co);
        await using var _ = db;
        Assert.Equal(403, StatusOf(await c.UpdateSettlementReport(reportId, Body(new { notes = "عبث" }))));
        Assert.Equal(403, StatusOf(await c.DeleteSettlementReport(reportId)));

        await using var check = _fx.CreateContext(PostgresFixture.SystemTenant);
        Assert.Equal("أصلي", (await check.Set<DailySettlementReport>().AsNoTracking()
            .FirstAsync(r => r.Id == reportId)).Notes);

        // صاحب التقرير يستطيع التعديل
        var (owner, db2) = Build(other, co);
        await using var __ = db2;
        Assert.Equal(200, StatusOf(await owner.UpdateSettlementReport(reportId, Body(new { notes = "تعديل المالك" }))));
    }
}
