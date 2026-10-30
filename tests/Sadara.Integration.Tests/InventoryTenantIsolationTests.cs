using System.Security.Claims;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Storage;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging.Abstractions;
using Sadara.API.Controllers;
using Sadara.Application.Interfaces;
using Sadara.Domain.Entities;
using Sadara.Domain.Enums;
using Sadara.Infrastructure.Data;
using Sadara.Infrastructure.Repositories;
using Xunit;

namespace Sadara.Integration.Tests;

/// <summary>
/// اختبار عزل المستأجرين على مستوى <see cref="InventoryController"/> (لا على مستوى الفلتر المركزي).
///
/// السبب الجوهري لوجود هذا الملف: مستودع <c>Repository.GetByIdAsync</c> يستخدم EF
/// <c>FindAsync</c>، وهو **يتجاوز الـGlobal Query Filter** دائماً — فلا يحمي علَم
/// <c>Tenancy:EnforceIsolation</c> نقاطَ «التحميل بالـId». الحماية الفعلية = حُرّاس الكونترولر
/// (OwnedByTenant / DenyIfForeignCompany) التي تقرأ <c>company_id</c> من توكن المستخدم.
///
/// لذلك نبني الكونترولر فعلياً بـ <see cref="UnitOfWork"/> فوق سياق InMemory، ونضبط
/// <see cref="ClaimsPrincipal"/> لشركة A، ثم نطلب معرّفات شركة B ونتوقّع 404/403.
/// السياق هنا بـ EnforceIsolation=false عمداً (يحاكي الإنتاج) كي لا يحجب الفلتر المركزي
/// صفوف B في الزرع/القراءة — فيبقى حارس الكونترولر وحده هو المُختبَر.
/// </summary>
public class InventoryTenantIsolationTests
{
    private static readonly Guid CompanyA = Guid.Parse("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa");
    private static readonly Guid CompanyB = Guid.Parse("bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb");

    // مستأجر محايد للسياق: لا يُفعّل الفلتر المركزي ولا يطمس CompanyId الصريح عند الزرع.
    private sealed class NeutralTenant : ICurrentTenant
    {
        public Guid? CompanyId => null;
        public bool IsSuperAdmin => false;
        public bool BypassTenantFilter => true;   // رؤية كل الشركات في الزرع/التحقّق المحايد
        public Guid? DefaultCompanyId => null;
        public bool EnforceIsolation => false;     // يحاكي الإنتاج؛ يُبقي حارس الكونترولر هو المُختبَر
    }

    // مُزوّد خدمات EF داخلي خاص بهذا الملف (نموذج EF بلا فلتر عزل) + جذر InMemory مشترك.
    private static readonly InMemoryDatabaseRoot DbRoot = new();
    private static readonly IServiceProvider EfServiceProvider =
        new ServiceCollection().AddEntityFrameworkInMemoryDatabase().BuildServiceProvider();

    private static SadaraDbContext NewContext(string dbName) =>
        new(new DbContextOptionsBuilder<SadaraDbContext>()
                .UseInMemoryDatabase(dbName, DbRoot)
                .UseInternalServiceProvider(EfServiceProvider)
                .Options,
            new NeutralTenant());

    // كونترولر بتوكن مستخدم: company_id + دور (غير SuperAdmin افتراضياً).
    private static InventoryController NewController(SadaraDbContext ctx, Guid companyId, bool superAdmin = false)
    {
        var uow = new UnitOfWork(ctx);
        var controller = new InventoryController(uow, NullLogger<InventoryController>.Instance);
        var claims = new List<Claim>
        {
            new("company_id", companyId.ToString()),
            new(ClaimTypes.NameIdentifier, Guid.NewGuid().ToString()),
            new(ClaimTypes.Role, superAdmin ? ((int)UserRole.SuperAdmin).ToString()
                                            : ((int)UserRole.CompanyAdmin).ToString()),
        };
        controller.ControllerContext = new ControllerContext
        {
            HttpContext = new DefaultHttpContext
            {
                User = new ClaimsPrincipal(new ClaimsIdentity(claims, "TestAuth")),
            },
        };
        return controller;
    }

    private sealed class Seeded
    {
        public Guid ItemA, ItemB, CustomerB;
    }

    private static Seeded SeedTwoCompanies(string dbName)
    {
        using var ctx = NewContext(dbName);
        var s = new Seeded
        {
            ItemA = Guid.NewGuid(),
            ItemB = Guid.NewGuid(),
            CustomerB = Guid.NewGuid(),
        };
        ctx.Set<InventoryItem>().AddRange(
            new InventoryItem { Id = s.ItemA, CompanyId = CompanyA, Name = "مادة أ", SKU = "A-1", CostPrice = 10 },
            new InventoryItem { Id = s.ItemB, CompanyId = CompanyB, Name = "مادة ب", SKU = "B-1", CostPrice = 20 });
        ctx.Set<InventoryCustomer>().Add(
            new InventoryCustomer { Id = s.CustomerB, CompanyId = CompanyB, CustomerCode = "CU-B1", FullName = "عميل ب" });
        ctx.SaveChanges();
        return s;
    }

    // ── النوع A: تعديل بالـId عبر شركة أخرى يُحجب (404) ──
    [Fact]
    public async Task UpdateItem_ForeignCompany_Returns_NotFound()
    {
        var dbName = Guid.NewGuid().ToString();
        var s = SeedTwoCompanies(dbName);
        using var ctx = NewContext(dbName);
        var controller = NewController(ctx, CompanyA); // توكن شركة A

        var result = await controller.UpdateItem(s.ItemB, new UpdateItemRequest { Name = "اختراق", CostPrice = 999 });

        Assert.IsType<NotFoundObjectResult>(result);
        // وتأكيد عدم تغيّر مادة شركة B فعلياً
        using var verify = NewContext(dbName);
        var itemB = verify.Set<InventoryItem>().Single(i => i.Id == s.ItemB);
        Assert.Equal("مادة ب", itemB.Name);
        Assert.Equal(20, itemB.CostPrice);
    }

    // ── النوع A: قراءة تفاصيل عميل شركة أخرى تُحجب ──
    [Fact]
    public async Task GetCustomerDetails_ForeignCompany_Returns_NotFound()
    {
        var dbName = Guid.NewGuid().ToString();
        var s = SeedTwoCompanies(dbName);
        using var ctx = NewContext(dbName);
        var controller = NewController(ctx, CompanyA);

        var result = await controller.GetCustomerDetails(s.CustomerB);

        Assert.IsType<NotFoundObjectResult>(result);
    }

    // ── النوع A: حذف مادة شركة أخرى يُحجب ──
    [Fact]
    public async Task DeleteItem_ForeignCompany_Returns_NotFound()
    {
        var dbName = Guid.NewGuid().ToString();
        var s = SeedTwoCompanies(dbName);
        using var ctx = NewContext(dbName);
        var controller = NewController(ctx, CompanyA);

        var result = await controller.DeleteItem(s.ItemB);

        Assert.IsType<NotFoundObjectResult>(result);
    }

    // ── المسار الطبيعي: شركة A تعدّل مادتها بنجاح (الحارس لا يكسر الشرعي) ──
    [Fact]
    public async Task UpdateItem_SameCompany_Succeeds()
    {
        var dbName = Guid.NewGuid().ToString();
        var s = SeedTwoCompanies(dbName);
        using var ctx = NewContext(dbName);
        var controller = NewController(ctx, CompanyA);

        var result = await controller.UpdateItem(s.ItemA, new UpdateItemRequest { Name = "مادة أ محدّثة" });

        Assert.IsType<OkObjectResult>(result);
        using var verify = NewContext(dbName);
        Assert.Equal("مادة أ محدّثة", verify.Set<InventoryItem>().Single(i => i.Id == s.ItemA).Name);
    }

    // ── SuperAdmin يتجاوز العزل (ضبط موجب) ──
    [Fact]
    public async Task SuperAdmin_Can_Access_Any_Company_Item()
    {
        var dbName = Guid.NewGuid().ToString();
        var s = SeedTwoCompanies(dbName);
        using var ctx = NewContext(dbName);
        var controller = NewController(ctx, CompanyA, superAdmin: true);

        var result = await controller.UpdateItem(s.ItemB, new UpdateItemRequest { Name = "تعديل مشرف" });

        Assert.IsType<OkObjectResult>(result);
    }

    // ── النوع B: إنشاء مادة بـ CompanyId لشركة أخرى يُرفض (403) ──
    [Fact]
    public async Task CreateItem_ForeignCompanyId_Returns_403()
    {
        var dbName = Guid.NewGuid().ToString();
        SeedTwoCompanies(dbName);
        using var ctx = NewContext(dbName);
        var controller = NewController(ctx, CompanyA); // توكن A لكن الجسم يدّعي B

        var result = await controller.CreateItem(new CreateItemRequest
        {
            Name = "حقن", SKU = "X-1", CostPrice = 5, CompanyId = CompanyB,
        });

        var obj = Assert.IsType<ObjectResult>(result);
        Assert.Equal(403, obj.StatusCode);
    }

    // ── بنود السطور: إنشاء أمر شراء ببند مادة شركة أخرى يُرفض (400) — حارس EnsureItemsOwnedAsync ──
    [Fact]
    public async Task CreatePurchaseOrder_ForeignLineItem_Returns_BadRequest()
    {
        var dbName = Guid.NewGuid().ToString();
        var s = SeedTwoCompanies(dbName);
        var warehouseA = Guid.NewGuid();
        using (var seed = NewContext(dbName))
        {
            seed.Set<Warehouse>().Add(new Warehouse
            { Id = warehouseA, CompanyId = CompanyA, Name = "مستودع أ", IsActive = true, IsDefault = true });
            seed.SaveChanges();
        }
        using var ctx = NewContext(dbName);
        var controller = NewController(ctx, CompanyA); // توكن A، طلب A، لكن البند مادة B

        var result = await controller.CreatePurchaseOrder(new CreatePurchaseOrderRequest
        {
            CompanyId = CompanyA,
            WarehouseId = warehouseA,
            SupplierId = Guid.NewGuid(),
            Items = new() { new PurchaseOrderItemDto { InventoryItemId = s.ItemB, Quantity = 1, UnitPrice = 5 } },
        });

        var obj = Assert.IsType<BadRequestObjectResult>(result);
        // ولم تُنشأ أي حركة مخزون شبح
        using var verify = NewContext(dbName);
        Assert.Empty(verify.Set<PurchaseOrder>().ToList());
    }

    // ── بنود السطور: أمر شراء بمادة الشركة نفسها ينجح (الحارس لا يكسر الشرعي) ──
    [Fact]
    public async Task CreatePurchaseOrder_OwnLineItem_Succeeds()
    {
        var dbName = Guid.NewGuid().ToString();
        var s = SeedTwoCompanies(dbName);
        var warehouseA = Guid.NewGuid();
        using (var seed = NewContext(dbName))
        {
            seed.Set<Warehouse>().Add(new Warehouse
            { Id = warehouseA, CompanyId = CompanyA, Name = "مستودع أ", IsActive = true, IsDefault = true });
            seed.SaveChanges();
        }
        using var ctx = NewContext(dbName);
        var controller = NewController(ctx, CompanyA);

        var result = await controller.CreatePurchaseOrder(new CreatePurchaseOrderRequest
        {
            CompanyId = CompanyA,
            WarehouseId = warehouseA,
            SupplierId = Guid.NewGuid(),
            Items = new() { new PurchaseOrderItemDto { InventoryItemId = s.ItemA, Quantity = 1, UnitPrice = 5 } },
        });

        // نجاح (Ok/Created) — لا 400/403/404
        Assert.True(result is OkObjectResult or CreatedResult or CreatedAtActionResult or ObjectResult { StatusCode: 200 or 201 });
        using var verify = NewContext(dbName);
        Assert.Single(verify.Set<PurchaseOrder>().ToList());
    }
}
