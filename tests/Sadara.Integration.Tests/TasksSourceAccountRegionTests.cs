using System.Security.Claims;
using System.Text.Json;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging.Abstractions;
using Sadara.API.Controllers;
using Sadara.Application.Interfaces;
using Sadara.Domain.Entities;
using Sadara.Domain.Enums;
using Sadara.Infrastructure.Data;
using Sadara.Infrastructure.Repositories;
using Sadara.Integration.Tests.Support;
using Xunit;
using static Sadara.Integration.Tests.Support.SummaryTestHarness;

namespace Sadara.Integration.Tests;

/// <summary>
/// اختبارات تكامل للمرحلة 1 من ميزة «ربط المهام بحساب مصدر ومنطقة»
/// (الفرع <c>feature/tasks-source-account-region</c>) — تُشغَّل على الكونترولر الحقيقي
/// <see cref="ServiceRequestsController"/> فوق Postgres حقيقي (Testcontainers) عبر
/// وحدة عمل حقيقية (<see cref="UnitOfWork"/>) على نفس السياق.
///
/// لماذا Postgres حقيقي؟ منطق وسم المهمة يقرأ/يكتب أعمدةً مطبّعة ويطبّق تحقّق ملكية عبر
/// <c>_db</c> + <see cref="IUnitOfWork"/> مع قيود FK فعلية (Service/OperationType/Company/
/// ChangedBy/OwnerUser). InMemory لا يفرض هذه القيود فلا يكشف تسرّب الوسم. عند غياب Docker
/// تُتخطّى كل الاختبارات بوضوح (Skipped) — لا إخفاق ولا نجاح زائف. لا تمسّ الإنتاج إطلاقاً.
///
/// الأولوية (الأمن أولاً):
///  1) عزل عبر الشركات: حساب/منطقة شركة أخرى عند إنشاء/تعديل المهمة ⇒ يُرفض (400) ولا يُكتب صف.
///  2) عدم تسرّب كلمة المرور: استجابة source-pool لا تحوي أي PasswordEncrypted/قيمة سرّية.
///  3) ختم اللقطة خادمياً: SourceAccountLabel/RegionName يُشتقّان من الصف المُتحقَّق لا من العميل.
///  4) التوافق الخلفي: إنشاء مهمة بلا حقول مصدر ⇒ ينجح بـ SourceAccountType=None.
///  5) عزل source-pool نفسه: مستخدم شركة أ لا يرى حسابات/مناطق شركة ب.
/// </summary>
[Collection("Postgres")]
public class TasksSourceAccountRegionTests
{
    private readonly PostgresFixture _fx;

    public TasksSourceAccountRegionTests(PostgresFixture fx) => _fx = fx;

    // ══════════════════════════════════════════════════════════════════════
    // أدوات مساعدة
    // ══════════════════════════════════════════════════════════════════════

    /// <summary>
    /// يبني الكونترولر الحقيقي لمسارات المهام بوحدة عمل حقيقية على <paramref name="db"/> نفسه
    /// (كتابة/قراءة متّسقة) + مُسجِّل صامت. التبعيات غير المستعملة في create/update بلا تغيير حالة
    /// (fcm/taskHubNotifier/configuration) تبقى null! ولا تُمسّ: taskHubNotifier يُستدعى فقط عند
    /// وجود مطالبة "company_id" (نتركها غائبة)، وfcm فقط عند تعيين فني تلقائي (لا نضبط Technician).
    /// </summary>
    private static ServiceRequestsController BuildTaskController(
        SadaraDbContext db, ICurrentTenant tenant, Guid userId)
    {
        var controller = new ServiceRequestsController(
            unitOfWork: new UnitOfWork(db),
            logger: NullLogger<ServiceRequestsController>.Instance,
            fcmService: null!,
            taskHubNotifier: null!,
            db: db,
            tenant: tenant,
            configuration: null!);

        var claims = new List<Claim> { new(ClaimTypes.NameIdentifier, userId.ToString()) };
        var principal = new ClaimsPrincipal(new ClaimsIdentity(claims, "TestAuth"));
        controller.ControllerContext = new ControllerContext
        {
            HttpContext = new DefaultHttpContext { User = principal }
        };
        return controller;
    }

    /// <summary>تنظيف الجداول بين الاختبارات بترتيب آمن للمفاتيح الأجنبية (الأبناء أولاً).</summary>
    private void ResetAll()
    {
        using var ctx = _fx.CreateContext(PostgresFixture.SystemTenant);
        ctx.Database.ExecuteSqlRaw(
            "DELETE FROM \"ServiceRequestStatusHistories\";" +
            "DELETE FROM \"ServiceRequests\";" +
            "DELETE FROM \"SubscriptionLogs\";" +
            "DELETE FROM \"FtthAccounts\";" +
            "DELETE FROM \"SasAccounts\";" +
            "DELETE FROM \"SasRegions\";" +
            "DELETE FROM \"Users\";" +
            "DELETE FROM \"Companies\";");
    }

    private Guid SeedFtthAccount(Guid companyId, Guid ownerUserId, string label, string username, string passwordEncrypted)
    {
        var id = Guid.NewGuid();
        using var ctx = _fx.CreateContext(PostgresFixture.SystemTenant);
        ctx.Set<FtthAccount>().Add(new FtthAccount
        {
            Id = id,
            CompanyId = companyId,
            OwnerUserId = ownerUserId,
            Label = label,
            Username = username,
            ServerUrl = "https://admin.ftth.iq",
            PasswordEncrypted = passwordEncrypted,
        });
        ctx.SaveChanges();
        return id;
    }

    private Guid SeedSasAccount(Guid companyId, Guid ownerUserId, string label, string username, string passwordEncrypted)
    {
        var id = Guid.NewGuid();
        using var ctx = _fx.CreateContext(PostgresFixture.SystemTenant);
        ctx.Set<SasAccount>().Add(new SasAccount
        {
            Id = id,
            CompanyId = companyId,
            OwnerUserId = ownerUserId,
            Label = label,
            Username = username,
            ServerUrl = "https://sas.example.test",
            PasswordEncrypted = passwordEncrypted,
            AccountType = SasAccountType.SasManager,
        });
        ctx.SaveChanges();
        return id;
    }

    private Guid SeedSasRegion(Guid companyId, string name)
    {
        var id = Guid.NewGuid();
        using var ctx = _fx.CreateContext(PostgresFixture.SystemTenant);
        ctx.Set<SasRegion>().Add(new SasRegion
        {
            Id = id,
            CompanyId = companyId,
            Name = name,
            Code = "R-" + name,
        });
        ctx.SaveChanges();
        return id;
    }

    private Guid SeedTask(Guid companyId, int serviceId, int operationTypeId, string phone)
    {
        var id = Guid.NewGuid();
        using var ctx = _fx.CreateContext(PostgresFixture.SystemTenant);
        ctx.Set<ServiceRequest>().Add(new ServiceRequest
        {
            Id = id,
            RequestNumber = "SR-SEED-" + id.ToString("N").Substring(0, 10),
            ServiceId = serviceId,
            OperationTypeId = operationTypeId,
            CompanyId = companyId,
            Status = ServiceRequestStatus.Pending,
            ContactPhone = phone,
            SourceAccountType = TaskSourceAccountType.None,
            RequestedAt = DateTime.UtcNow,
            CreatedAt = DateTime.UtcNow,
        });
        ctx.SaveChanges();
        return id;
    }

    /// <summary>
    /// يزرع مهمة «موسومة» مسبقاً (حساب ساس + منطقة مختومة) لاختبارات المسح/التصفير عند التعديل.
    /// يُكتَب الوسم مباشرةً عبر سياق النظام لعزل سيناريو التعديل عن منطق الإنشاء.
    /// </summary>
    private Guid SeedStampedTask(
        Guid companyId, int serviceId, int operationTypeId, string phone,
        Guid? sasAccountId, string? sasLabel, string? regionRef, string? regionName)
    {
        var id = Guid.NewGuid();
        using var ctx = _fx.CreateContext(PostgresFixture.SystemTenant);
        ctx.Set<ServiceRequest>().Add(new ServiceRequest
        {
            Id = id,
            RequestNumber = "SR-SEED-" + id.ToString("N").Substring(0, 10),
            ServiceId = serviceId,
            OperationTypeId = operationTypeId,
            CompanyId = companyId,
            Status = ServiceRequestStatus.Pending,
            ContactPhone = phone,
            SourceAccountType = sasAccountId.HasValue ? TaskSourceAccountType.Sas : TaskSourceAccountType.None,
            SourceAccountId = sasAccountId,
            SourceAccountLabel = sasLabel,
            RegionRef = regionRef,
            RegionName = regionName,
            RequestedAt = DateTime.UtcNow,
            CreatedAt = DateTime.UtcNow,
        });
        ctx.SaveChanges();
        return id;
    }

    private ServiceRequest? FindTaskByPhone(string phone)
    {
        using var ctx = _fx.CreateContext(PostgresFixture.SystemTenant);
        return ctx.Set<ServiceRequest>().AsNoTracking()
            .FirstOrDefault(r => r.ContactPhone == phone);
    }

    private ServiceRequest LoadTask(Guid id)
    {
        using var ctx = _fx.CreateContext(PostgresFixture.SystemTenant);
        return ctx.Set<ServiceRequest>().AsNoTracking().Single(r => r.Id == id);
    }

    private int CountTasks()
    {
        using var ctx = _fx.CreateContext(PostgresFixture.SystemTenant);
        return ctx.Set<ServiceRequest>().AsNoTracking().Count();
    }

    private static CreateTaskDto BaseCreateDto(int serviceId, int operationTypeId, string phone) => new()
    {
        TaskType = "صيانة",
        Department = "الصيانة",
        CustomerName = "عميل اختبار",
        CustomerPhone = phone,
        Priority = "متوسط",
        ServiceId = serviceId,
        OperationTypeId = operationTypeId,
    };

    // ══════════════════════════════════════════════════════════════════════
    // 1) عزل عبر الشركات — حساب مصدر من شركة أخرى عند الإنشاء ⇒ يُرفض ولا يُكتب صف
    // ══════════════════════════════════════════════════════════════════════

    [SkippableFact]
    public async Task CreateTask_With_Ftth_SourceAccount_From_Another_Company_Is_Rejected()
    {
        _fx.SkipIfUnavailable();
        ResetAll();
        SeedCompanies(_fx);
        var (svc, op) = SeedServiceAndOperation(_fx);
        var creatorA = SeedUser(_fx, CompanyA, UserRole.Employee, null);
        var ownerB = SeedUser(_fx, CompanyB, UserRole.Employee, null);

        // حساب FTTH يخصّ الشركة ب فقط.
        var ftthB = SeedFtthAccount(CompanyB, ownerB, "حساب الشركة ب", "userB", "SECRET-B");

        await using var db = _fx.CreateContext(new TestTenant { CompanyId = CompanyA });
        var controller = BuildTaskController(db, new TestTenant { CompanyId = CompanyA }, creatorA);

        var dto = BaseCreateDto(svc, op, "07700000001");
        dto.SourceAccountType = TaskSourceAccountType.Ftth;
        dto.SourceAccountId = ftthB;                 // حساب شركة أخرى (محاولة IDOR)
        dto.PartnerName = "مكتب مزيّف";

        var result = await controller.CreateTask(dto);

        Assert.IsType<BadRequestObjectResult>(result);
        // لا يُكتب أي صف (التحقّق قبل AddAsync) — لا تسرّب وسم.
        Assert.Equal(0, CountTasks());
    }

    [SkippableFact]
    public async Task CreateTask_With_Sas_SourceAccount_From_Another_Company_Is_Rejected()
    {
        _fx.SkipIfUnavailable();
        ResetAll();
        SeedCompanies(_fx);
        var (svc, op) = SeedServiceAndOperation(_fx);
        var creatorA = SeedUser(_fx, CompanyA, UserRole.Employee, null);
        var ownerB = SeedUser(_fx, CompanyB, UserRole.Employee, null);

        var sasB = SeedSasAccount(CompanyB, ownerB, "ساس الشركة ب", "sasB", "SECRET-SAS-B");

        await using var db = _fx.CreateContext(new TestTenant { CompanyId = CompanyA });
        var controller = BuildTaskController(db, new TestTenant { CompanyId = CompanyA }, creatorA);

        var dto = BaseCreateDto(svc, op, "07700000002");
        dto.SourceAccountType = TaskSourceAccountType.Sas;
        dto.SourceAccountId = sasB;

        var result = await controller.CreateTask(dto);

        Assert.IsType<BadRequestObjectResult>(result);
        Assert.Equal(0, CountTasks());
    }

    // ══════════════════════════════════════════════════════════════════════
    // 1ب) عزل عبر الشركات — منطقة ساس من شركة أخرى عند الإنشاء ⇒ يُرفض ولا يُكتب صف
    // ══════════════════════════════════════════════════════════════════════

    [SkippableFact]
    public async Task CreateTask_With_SasRegion_From_Another_Company_Is_Rejected()
    {
        _fx.SkipIfUnavailable();
        ResetAll();
        SeedCompanies(_fx);
        var (svc, op) = SeedServiceAndOperation(_fx);
        var creatorA = SeedUser(_fx, CompanyA, UserRole.Employee, null);

        // منطقة ساس تخصّ الشركة ب فقط.
        var regionB = SeedSasRegion(CompanyB, "منطقة الشركة ب");

        await using var db = _fx.CreateContext(new TestTenant { CompanyId = CompanyA });
        var controller = BuildTaskController(db, new TestTenant { CompanyId = CompanyA }, creatorA);

        var dto = BaseCreateDto(svc, op, "07700000003");
        dto.RegionRef = regionB.ToString();          // Guid منطقة شركة أخرى

        var result = await controller.CreateTask(dto);

        Assert.IsType<BadRequestObjectResult>(result);
        Assert.Equal(0, CountTasks());
    }

    [SkippableFact]
    public async Task UpdateTask_With_Ftth_SourceAccount_From_Another_Company_Is_Rejected_And_Row_Unchanged()
    {
        _fx.SkipIfUnavailable();
        ResetAll();
        SeedCompanies(_fx);
        var (svc, op) = SeedServiceAndOperation(_fx);
        var editorA = SeedUser(_fx, CompanyA, UserRole.Employee, null);
        var ownerB = SeedUser(_fx, CompanyB, UserRole.Employee, null);

        // مهمة قائمة ضمن الشركة أ (بلا وسم)، وحساب FTTH يخصّ الشركة ب.
        var taskId = SeedTask(CompanyA, svc, op, "07700000004");
        var ftthB = SeedFtthAccount(CompanyB, ownerB, "حساب ب", "ub", "SECRET-B2");

        await using var db = _fx.CreateContext(new TestTenant { CompanyId = CompanyA });
        var controller = BuildTaskController(db, new TestTenant { CompanyId = CompanyA }, editorA);

        var dto = new UpdateTaskDto
        {
            SourceAccountType = TaskSourceAccountType.Ftth,
            SourceAccountId = ftthB,
        };

        var result = await controller.UpdateTask(taskId, dto);

        Assert.IsType<BadRequestObjectResult>(result);
        // الصف يبقى بلا وسم (لم تُحفظ التغييرات).
        var row = LoadTask(taskId);
        Assert.Equal(TaskSourceAccountType.None, row.SourceAccountType);
        Assert.Null(row.SourceAccountId);
        Assert.Null(row.SourceAccountLabel);
    }

    // ══════════════════════════════════════════════════════════════════════
    // 3) ختم اللقطة خادمياً — Label/RegionName من الصف المُتحقَّق لا من العميل
    // ══════════════════════════════════════════════════════════════════════

    [SkippableFact]
    public async Task CreateTask_With_Valid_Ftth_Account_Stamps_Label_From_Server()
    {
        _fx.SkipIfUnavailable();
        ResetAll();
        SeedCompanies(_fx);
        var (svc, op) = SeedServiceAndOperation(_fx);
        var creatorA = SeedUser(_fx, CompanyA, UserRole.Employee, null);

        // اللقطة الرسمية للحساب على الخادم — لا يملك العميل حقلاً لتزييفها (CreateTaskDto بلا Label عمداً).
        const string serverLabel = "الحساب الرسمي للشركة أ";
        var ftthA = SeedFtthAccount(CompanyA, creatorA, serverLabel, "userA", "SECRET-A");

        await using var db = _fx.CreateContext(new TestTenant { CompanyId = CompanyA });
        var controller = BuildTaskController(db, new TestTenant { CompanyId = CompanyA }, creatorA);

        var dto = BaseCreateDto(svc, op, "07700000005");
        dto.SourceAccountType = TaskSourceAccountType.Ftth;
        dto.SourceAccountId = ftthA;
        dto.PartnerId = "2261175";
        dto.PartnerName = "مدينة الصدر";

        var result = await controller.CreateTask(dto);
        Assert.IsType<CreatedAtActionResult>(result);

        var row = FindTaskByPhone("07700000005")!;
        Assert.Equal(TaskSourceAccountType.Ftth, row.SourceAccountType);
        Assert.Equal(ftthA, row.SourceAccountId);
        // اللقطة مختومة من صف الحساب المُتحقَّق — لا من العميل.
        Assert.Equal(serverLabel, row.SourceAccountLabel);
        Assert.Equal("2261175", row.PartnerId);
        Assert.Equal("مدينة الصدر", row.PartnerName);
    }

    [SkippableFact]
    public async Task CreateTask_With_Valid_SasRegion_Stamps_RegionName_From_Server()
    {
        _fx.SkipIfUnavailable();
        ResetAll();
        SeedCompanies(_fx);
        var (svc, op) = SeedServiceAndOperation(_fx);
        var creatorA = SeedUser(_fx, CompanyA, UserRole.Employee, null);

        const string regionName = "منطقة النسيم";
        var regionA = SeedSasRegion(CompanyA, regionName);

        await using var db = _fx.CreateContext(new TestTenant { CompanyId = CompanyA });
        var controller = BuildTaskController(db, new TestTenant { CompanyId = CompanyA }, creatorA);

        var dto = BaseCreateDto(svc, op, "07700000006");
        dto.RegionRef = regionA.ToString();

        var result = await controller.CreateTask(dto);
        Assert.IsType<CreatedAtActionResult>(result);

        var row = FindTaskByPhone("07700000006")!;
        Assert.Equal(regionA.ToString(), row.RegionRef);
        // اسم المنطقة مختوم من صف المنطقة المُتحقَّق.
        Assert.Equal(regionName, row.RegionName);
    }

    // ══════════════════════════════════════════════════════════════════════
    // 4) التوافق الخلفي — إنشاء مهمة بلا حقول مصدر ⇒ ينجح بـ None
    // ══════════════════════════════════════════════════════════════════════

    [SkippableFact]
    public async Task CreateTask_Without_Source_Fields_Succeeds_With_None()
    {
        _fx.SkipIfUnavailable();
        ResetAll();
        SeedCompanies(_fx);
        var (svc, op) = SeedServiceAndOperation(_fx);
        var creatorA = SeedUser(_fx, CompanyA, UserRole.Employee, null);

        await using var db = _fx.CreateContext(new TestTenant { CompanyId = CompanyA });
        var controller = BuildTaskController(db, new TestTenant { CompanyId = CompanyA }, creatorA);

        var dto = BaseCreateDto(svc, op, "07700000007"); // بلا أي حقول مصدر/منطقة

        var result = await controller.CreateTask(dto);
        Assert.IsType<CreatedAtActionResult>(result);

        var row = FindTaskByPhone("07700000007")!;
        Assert.Equal(TaskSourceAccountType.None, row.SourceAccountType);
        Assert.Null(row.SourceAccountId);
        Assert.Null(row.SourceAccountLabel);
        Assert.Null(row.PartnerId);
        Assert.Null(row.PartnerName);
        Assert.Null(row.RegionRef);
        Assert.Null(row.RegionName);
        Assert.Equal(CompanyA, row.CompanyId);       // ختم الشركة من التوكن
    }

    // ══════════════════════════════════════════════════════════════════════
    // 2) عدم تسرّب كلمة المرور — استجابة source-pool بلا PasswordEncrypted/أي سرّ
    // ══════════════════════════════════════════════════════════════════════

    [SkippableFact]
    public async Task SourcePool_Does_Not_Leak_Any_Password()
    {
        _fx.SkipIfUnavailable();
        ResetAll();
        SeedCompanies(_fx);
        SeedServiceAndOperation(_fx);
        var ownerA = SeedUser(_fx, CompanyA, UserRole.Employee, null);

        const string ftthSecret = "FTTH_ENC_SECRET_ZZZ_1";
        const string sasSecret = "SAS_ENC_SECRET_ZZZ_2";
        SeedFtthAccount(CompanyA, ownerA, "حساب FTTH", "ftth_user_a", ftthSecret);
        SeedSasAccount(CompanyA, ownerA, "حساب ساس", "sas_user_a", sasSecret);

        await using var db = _fx.CreateContext(new TestTenant { CompanyId = CompanyA });
        var controller = BuildTaskController(db, new TestTenant { CompanyId = CompanyA }, ownerA);

        var result = await controller.GetSourcePool();
        var ok = Assert.IsType<OkObjectResult>(result);

        var json = JsonSerializer.Serialize(ok.Value);

        // على مستوى JSON: لا مفتاح كلمة مرور ولا أي قيمة سرّية مزروعة.
        Assert.DoesNotContain("assword", json);           // password / Password / PasswordEncrypted
        Assert.DoesNotContain("Encrypted", json);
        Assert.DoesNotContain(ftthSecret, json);
        Assert.DoesNotContain(sasSecret, json);
        // سلامة: الحسابات حاضرة فعلاً (أسماء المستخدمين تظهر) حتى لا يكون الاختبار فارغاً.
        Assert.Contains("ftth_user_a", json);
        Assert.Contains("sas_user_a", json);
    }

    // ══════════════════════════════════════════════════════════════════════
    // 5) عزل source-pool — مستخدم شركة أ لا يرى حسابات/مناطق شركة ب
    // ══════════════════════════════════════════════════════════════════════

    [SkippableFact]
    public async Task SourcePool_Isolates_Accounts_And_Regions_By_Company()
    {
        _fx.SkipIfUnavailable();
        ResetAll();
        SeedCompanies(_fx);
        SeedServiceAndOperation(_fx);
        var ownerA = SeedUser(_fx, CompanyA, UserRole.Employee, null);
        var ownerB = SeedUser(_fx, CompanyB, UserRole.Employee, null);

        // الشركة أ
        SeedFtthAccount(CompanyA, ownerA, "FTTH-LABEL-A", "ftth_a", "s1");
        SeedSasAccount(CompanyA, ownerA, "SAS-LABEL-A", "sas_a", "s2");
        SeedSasRegion(CompanyA, "REGION-NAME-A");
        // الشركة ب (يجب ألا تظهر لمستخدم الشركة أ)
        SeedFtthAccount(CompanyB, ownerB, "FTTH-LABEL-B", "ftth_b", "s3");
        SeedSasAccount(CompanyB, ownerB, "SAS-LABEL-B", "sas_b", "s4");
        SeedSasRegion(CompanyB, "REGION-NAME-B");

        await using var db = _fx.CreateContext(new TestTenant { CompanyId = CompanyA });
        var controller = BuildTaskController(db, new TestTenant { CompanyId = CompanyA }, ownerA);

        var result = await controller.GetSourcePool();
        var ok = Assert.IsType<OkObjectResult>(result);
        var json = JsonSerializer.Serialize(ok.Value);

        // حسابات/مناطق الشركة أ حاضرة.
        Assert.Contains("FTTH-LABEL-A", json);
        Assert.Contains("SAS-LABEL-A", json);
        Assert.Contains("REGION-NAME-A", json);
        // ولا شيء من الشركة ب يتسرّب.
        Assert.DoesNotContain("FTTH-LABEL-B", json);
        Assert.DoesNotContain("SAS-LABEL-B", json);
        Assert.DoesNotContain("REGION-NAME-B", json);
    }

    [SkippableFact]
    public async Task SourcePool_Without_Company_In_Token_Is_Forbidden()
    {
        _fx.SkipIfUnavailable();
        ResetAll();

        await using var db = _fx.CreateContext(new TestTenant { CompanyId = null });
        var controller = BuildTaskController(db, new TestTenant { CompanyId = null }, Guid.NewGuid());

        var result = await controller.GetSourcePool();

        // fail-closed: توكن بلا شركة (وليس SuperAdmin) ⇒ 403 بدل كشف مجمّع كل الشركات.
        var obj = Assert.IsType<ObjectResult>(result);
        Assert.Equal(403, obj.StatusCode);
    }

    // ══════════════════════════════════════════════════════════════════════
    // M1) حارس source-pool = (tasks/add OR tasks/edit) — لا سمة RequirePermission واحدة
    //     يغطّي الإصلاح CanAddOrEditTasksAsync: المجمّع يغذّي حواري الإنشاء والتعديل معاً.
    // ══════════════════════════════════════════════════════════════════════

    [SkippableFact]
    public async Task SourcePool_With_Edit_Only_Permission_Is_Allowed()
    {
        _fx.SkipIfUnavailable();
        ResetAll();
        SeedCompanies(_fx);
        SeedServiceAndOperation(_fx);
        // موظف (ليس مديراً) يملك tasks/edit فقط — بلا tasks/add.
        var userA = SeedUser(_fx, CompanyA, UserRole.Employee, "{\"tasks\":{\"edit\":true}}");

        await using var db = _fx.CreateContext(new TestTenant { CompanyId = CompanyA });
        var controller = BuildTaskController(db, new TestTenant { CompanyId = CompanyA }, userA);

        var result = await controller.GetSourcePool();

        // منطق OR: edit وحده كافٍ ⇒ 200.
        Assert.IsType<OkObjectResult>(result);
    }

    [SkippableFact]
    public async Task SourcePool_With_Add_Only_Permission_Is_Allowed()
    {
        _fx.SkipIfUnavailable();
        ResetAll();
        SeedCompanies(_fx);
        SeedServiceAndOperation(_fx);
        var userA = SeedUser(_fx, CompanyA, UserRole.Employee, "{\"tasks\":{\"add\":true}}");

        await using var db = _fx.CreateContext(new TestTenant { CompanyId = CompanyA });
        var controller = BuildTaskController(db, new TestTenant { CompanyId = CompanyA }, userA);

        var result = await controller.GetSourcePool();

        Assert.IsType<OkObjectResult>(result);
    }

    [SkippableFact]
    public async Task SourcePool_With_Neither_Add_Nor_Edit_Permission_Is_Forbidden()
    {
        _fx.SkipIfUnavailable();
        ResetAll();
        SeedCompanies(_fx);
        SeedServiceAndOperation(_fx);
        // صلاحيات V2 حاضرة لكن بلا add/edit (view فقط) — غير فارغة كي لا يتسرّب fail-open.
        var userA = SeedUser(_fx, CompanyA, UserRole.Employee, "{\"tasks\":{\"view\":true}}");

        await using var db = _fx.CreateContext(new TestTenant { CompanyId = CompanyA });
        var controller = BuildTaskController(db, new TestTenant { CompanyId = CompanyA }, userA);

        var result = await controller.GetSourcePool();

        // لا add ولا edit وليس مديراً ⇒ 403.
        var obj = Assert.IsType<ObjectResult>(result);
        Assert.Equal(403, obj.StatusCode);
    }

    // ══════════════════════════════════════════════════════════════════════
    // P3-a) طول المنطقة اليدوية — نص يدوي >100 حرف ⇒ 400 لا 500، صفر كتابة؛ ≤100 ⇒ ينجح ويُختم
    // ══════════════════════════════════════════════════════════════════════

    [SkippableFact]
    public async Task CreateTask_With_Manual_Region_Exceeding_100_Chars_Is_Rejected_No_Write()
    {
        _fx.SkipIfUnavailable();
        ResetAll();
        SeedCompanies(_fx);
        var (svc, op) = SeedServiceAndOperation(_fx);
        var creatorA = SeedUser(_fx, CompanyA, UserRole.Employee, null);

        await using var db = _fx.CreateContext(new TestTenant { CompanyId = CompanyA });
        var controller = BuildTaskController(db, new TestTenant { CompanyId = CompanyA }, creatorA);

        var dto = BaseCreateDto(svc, op, "07700000010");
        dto.RegionRef = new string('x', 101);        // نص يدوي (ليس Guid) يتجاوز 100 — كان يسبّب 500 (varchar(100))

        var result = await controller.CreateTask(dto);

        // حارس الطول يُرجِع 400 صريحاً قبل أي كتابة — لا انتهاك طول عمود (500).
        Assert.IsType<BadRequestObjectResult>(result);
        Assert.Equal(0, CountTasks());
    }

    [SkippableFact]
    public async Task UpdateTask_With_Manual_Region_Exceeding_100_Chars_Is_Rejected()
    {
        _fx.SkipIfUnavailable();
        ResetAll();
        SeedCompanies(_fx);
        var (svc, op) = SeedServiceAndOperation(_fx);
        var editorA = SeedUser(_fx, CompanyA, UserRole.Employee, null);
        var taskId = SeedTask(CompanyA, svc, op, "07700000011");

        await using var db = _fx.CreateContext(new TestTenant { CompanyId = CompanyA });
        var controller = BuildTaskController(db, new TestTenant { CompanyId = CompanyA }, editorA);

        var dto = new UpdateTaskDto { RegionRef = new string('y', 101) };

        var result = await controller.UpdateTask(taskId, dto);

        Assert.IsType<BadRequestObjectResult>(result);
        // الصف يبقى بلا منطقة (لم تُحفظ).
        var row = LoadTask(taskId);
        Assert.Null(row.RegionRef);
        Assert.Null(row.RegionName);
    }

    [SkippableFact]
    public async Task CreateTask_With_Manual_Region_Within_Limit_Stamps_RegionName()
    {
        _fx.SkipIfUnavailable();
        ResetAll();
        SeedCompanies(_fx);
        var (svc, op) = SeedServiceAndOperation(_fx);
        var creatorA = SeedUser(_fx, CompanyA, UserRole.Employee, null);

        await using var db = _fx.CreateContext(new TestTenant { CompanyId = CompanyA });
        var controller = BuildTaskController(db, new TestTenant { CompanyId = CompanyA }, creatorA);

        var manualRegion = new string('م', 100);     // 100 حرف — عند الحدّ تماماً
        var dto = BaseCreateDto(svc, op, "07700000012");
        dto.RegionRef = manualRegion;

        var result = await controller.CreateTask(dto);
        Assert.IsType<CreatedAtActionResult>(result);

        var row = FindTaskByPhone("07700000012")!;
        // منطقة نصّية يدوية: RegionRef و RegionName يساويان النص نفسه بعد Trim.
        Assert.Equal(manualRegion, row.RegionRef);
        Assert.Equal(manualRegion, row.RegionName);
        Assert.Equal(TaskSourceAccountType.None, row.SourceAccountType);
    }

    // ══════════════════════════════════════════════════════════════════════
    // M2) مسح المنطقة مع None — منطقة ساس مختومة ثم SourceAccountType=None ⇒ تصفير كامل (لا لقطة يتيمة)
    // ══════════════════════════════════════════════════════════════════════

    [SkippableFact]
    public async Task UpdateTask_SetSourceTypeNone_Clears_Region_And_Account_Snapshot()
    {
        _fx.SkipIfUnavailable();
        ResetAll();
        SeedCompanies(_fx);
        var (svc, op) = SeedServiceAndOperation(_fx);
        var editorA = SeedUser(_fx, CompanyA, UserRole.Employee, null);

        // حساب ساس + منطقة ساس ضمن الشركة أ، ومهمة موسومة بهما مسبقاً.
        var sasA = SeedSasAccount(CompanyA, editorA, "ساس أ", "sas_a", "SECRET");
        var regionA = SeedSasRegion(CompanyA, "منطقة الصدر");
        var taskId = SeedStampedTask(
            CompanyA, svc, op, "07700000013",
            sasA, "ساس أ", regionA.ToString(), "منطقة الصدر");

        await using var db = _fx.CreateContext(new TestTenant { CompanyId = CompanyA });
        var controller = BuildTaskController(db, new TestTenant { CompanyId = CompanyA }, editorA);

        var dto = new UpdateTaskDto { SourceAccountType = TaskSourceAccountType.None };

        var result = await controller.UpdateTask(taskId, dto);
        Assert.IsType<OkObjectResult>(result);

        // None تُصفّر الحساب والشريك والمنطقة معاً — لا تبقى لقطة منطقة يتيمة.
        var row = LoadTask(taskId);
        Assert.Equal(TaskSourceAccountType.None, row.SourceAccountType);
        Assert.Null(row.SourceAccountId);
        Assert.Null(row.SourceAccountLabel);
        Assert.Null(row.PartnerId);
        Assert.Null(row.PartnerName);
        Assert.Null(row.RegionRef);
        Assert.Null(row.RegionName);
    }

    // ══════════════════════════════════════════════════════════════════════
    // مسح المنطقة صراحةً ("") مقابل عدم التعديل (null) — العقد مع الواجهة
    // ══════════════════════════════════════════════════════════════════════

    [SkippableFact]
    public async Task UpdateTask_With_Empty_RegionRef_Clears_Region_Only()
    {
        _fx.SkipIfUnavailable();
        ResetAll();
        SeedCompanies(_fx);
        var (svc, op) = SeedServiceAndOperation(_fx);
        var editorA = SeedUser(_fx, CompanyA, UserRole.Employee, null);

        var sasA = SeedSasAccount(CompanyA, editorA, "ساس أ", "sas_a", "SECRET");
        var taskId = SeedStampedTask(
            CompanyA, svc, op, "07700000014",
            sasA, "ساس أ", "منطقة يدوية", "منطقة يدوية");

        await using var db = _fx.CreateContext(new TestTenant { CompanyId = CompanyA });
        var controller = BuildTaskController(db, new TestTenant { CompanyId = CompanyA }, editorA);

        // "" = مسح صريح للمنطقة فقط؛ SourceAccountType غير مُرسَل (null) ⇒ الحساب لا يُمسّ.
        var dto = new UpdateTaskDto { RegionRef = "" };

        var result = await controller.UpdateTask(taskId, dto);
        Assert.IsType<OkObjectResult>(result);

        var row = LoadTask(taskId);
        Assert.Null(row.RegionRef);
        Assert.Null(row.RegionName);
        // الحساب المصدر يبقى كما هو (لم يُرسَل SourceAccountType).
        Assert.Equal(TaskSourceAccountType.Sas, row.SourceAccountType);
        Assert.Equal(sasA, row.SourceAccountId);
    }

    [SkippableFact]
    public async Task UpdateTask_With_Null_RegionRef_Leaves_Region_Unchanged()
    {
        _fx.SkipIfUnavailable();
        ResetAll();
        SeedCompanies(_fx);
        var (svc, op) = SeedServiceAndOperation(_fx);
        var editorA = SeedUser(_fx, CompanyA, UserRole.Employee, null);

        var taskId = SeedStampedTask(
            CompanyA, svc, op, "07700000015",
            null, null, "منطقة باقية", "منطقة باقية");

        await using var db = _fx.CreateContext(new TestTenant { CompanyId = CompanyA });
        var controller = BuildTaskController(db, new TestTenant { CompanyId = CompanyA }, editorA);

        // RegionRef == null ⇒ عدم تعديل المنطقة إطلاقاً (تُخطّى ApplyRegionAsync).
        var dto = new UpdateTaskDto { Notes = "تحديث غير متعلّق بالمنطقة" };

        var result = await controller.UpdateTask(taskId, dto);
        Assert.IsType<OkObjectResult>(result);

        var row = LoadTask(taskId);
        Assert.Equal("منطقة باقية", row.RegionRef);
        Assert.Equal("منطقة باقية", row.RegionName);
    }
}
