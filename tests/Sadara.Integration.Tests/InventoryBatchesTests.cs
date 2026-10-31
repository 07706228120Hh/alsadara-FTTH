using System.Security.Claims;
using System.Text.Json;
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
/// اختبارات ميزة الدُّفعات/الصلاحية (StockBatch): تعبئة دُفعة عند الاستلام، خصم FEFO
/// (الأقرب صلاحيةً أولاً + التسامح مع نقص الدُّفعات)، تنبيهات expired/expiringSoon، والعزل.
/// InMemory + NeutralTenant بلا Docker. تُختبَر مسارات بلا معاملات (CreatePurchaseOrder/AdjustStock)
/// لتفادي عدم دعم المعاملات في مزوّد InMemory.
/// </summary>
public class InventoryBatchesTests
{
    private static readonly Guid CompanyA = Guid.Parse("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa");
    private static readonly Guid CompanyB = Guid.Parse("bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb");

    private sealed class NeutralTenant : ICurrentTenant
    {
        public Guid? CompanyId => null;
        public bool IsSuperAdmin => false;
        public bool BypassTenantFilter => true;
        public Guid? DefaultCompanyId => null;
        public bool EnforceIsolation => false;
    }

    private static readonly InMemoryDatabaseRoot DbRoot = new();
    private static readonly IServiceProvider EfServiceProvider =
        new ServiceCollection().AddEntityFrameworkInMemoryDatabase().BuildServiceProvider();

    private static SadaraDbContext NewContext(string dbName) =>
        new(new DbContextOptionsBuilder<SadaraDbContext>()
                .UseInMemoryDatabase(dbName, DbRoot)
                .UseInternalServiceProvider(EfServiceProvider)
                .Options,
            new NeutralTenant());

    private static InventoryController NewController(SadaraDbContext ctx, Guid companyId)
    {
        var controller = new InventoryController(new UnitOfWork(ctx), NullLogger<InventoryController>.Instance);
        var claims = new List<Claim>
        {
            new("company_id", companyId.ToString()),
            new(ClaimTypes.NameIdentifier, Guid.NewGuid().ToString()),
            new(ClaimTypes.Role, ((int)UserRole.CompanyAdmin).ToString()),
        };
        controller.ControllerContext = new ControllerContext
        {
            HttpContext = new DefaultHttpContext
            { User = new ClaimsPrincipal(new ClaimsIdentity(claims, "TestAuth")) },
        };
        return controller;
    }

    private static (Guid itemId, Guid warehouseId) SeedItemWarehouse(SadaraDbContext ctx, Guid company)
    {
        var itemId = Guid.NewGuid();
        var whId = Guid.NewGuid();
        ctx.Set<Warehouse>().Add(new Warehouse
        { Id = whId, CompanyId = company, Name = "مستودع", IsActive = true });
        ctx.Set<InventoryItem>().Add(new InventoryItem
        { Id = itemId, CompanyId = company, Name = "مادة", SKU = "SKU", IsActive = true, CostPrice = 5 });
        return (itemId, whId);
    }

    private static void SeedStock(SadaraDbContext ctx, Guid company, Guid whId, Guid itemId, int qty)
    {
        ctx.Set<WarehouseStock>().Add(new WarehouseStock
        { CompanyId = company, WarehouseId = whId, InventoryItemId = itemId, CurrentQuantity = qty, AverageCost = 5 });
    }

    private static void SeedBatch(SadaraDbContext ctx, Guid company, Guid whId, Guid itemId,
        int qty, DateTime? expiry, string? number = null)
    {
        ctx.Set<StockBatch>().Add(new StockBatch
        {
            CompanyId = company,
            WarehouseId = whId,
            InventoryItemId = itemId,
            Quantity = qty,
            UnitCost = 5,
            ReceivedAt = DateTime.UtcNow,
            ExpiryDate = expiry,
            BatchNumber = number,
        });
    }

    private static List<StockBatch> ReadBatches(SadaraDbContext ctx, Guid itemId) =>
        ctx.Set<StockBatch>().Where(b => b.InventoryItemId == itemId).ToList();

    private static JsonElement DataOf(IActionResult result)
    {
        var ok = Assert.IsType<OkObjectResult>(result);
        using var doc = JsonDocument.Parse(JsonSerializer.Serialize(ok.Value));
        return doc.RootElement.GetProperty("data").Clone();
    }

    // ───────────────────────── 1) الاستلام يُنشئ دُفعة ─────────────────────────
    [Fact]
    public async Task Receipt_ViaCreatePurchaseOrder_CreatesBatch_WithExpiry()
    {
        var dbName = Guid.NewGuid().ToString();
        Guid itemId, whId;
        using (var seed = NewContext(dbName))
        {
            (itemId, whId) = SeedItemWarehouse(seed, CompanyA);
            seed.SaveChanges();
        }

        var expiry = DateTime.UtcNow.Date.AddDays(90);
        using (var ctx = NewContext(dbName))
        {
            var controller = NewController(ctx, CompanyA);
            var result = await controller.CreatePurchaseOrder(new CreatePurchaseOrderRequest
            {
                CompanyId = CompanyA,
                SupplierId = Guid.NewGuid(),
                WarehouseId = whId,
                Items = new List<PurchaseOrderItemDto>
                {
                    new() { InventoryItemId = itemId, Quantity = 10, UnitPrice = 7, ExpiryDate = expiry, BatchNumber = "B1" },
                },
            });
            Assert.IsType<OkObjectResult>(result);
        }

        using (var verify = NewContext(dbName))
        {
            var batches = ReadBatches(verify, itemId);
            var batch = Assert.Single(batches);
            Assert.Equal(10, batch.Quantity);
            Assert.Equal(7m, batch.UnitCost);
            Assert.Equal("B1", batch.BatchNumber);
            Assert.Equal(expiry, batch.ExpiryDate);
            Assert.Equal(CompanyA, batch.CompanyId);
        }
    }

    // ───────────────────────── 2) خصم FEFO (الأقرب صلاحيةً أولاً) ─────────────────────────
    [Fact]
    public async Task Deduction_IsFefo_NearestExpiryFirst_NullLast()
    {
        var dbName = Guid.NewGuid().ToString();
        Guid itemId, whId;
        var today = DateTime.UtcNow.Date;
        using (var seed = NewContext(dbName))
        {
            (itemId, whId) = SeedItemWarehouse(seed, CompanyA);
            SeedStock(seed, CompanyA, whId, itemId, qty: 90);
            SeedBatch(seed, CompanyA, whId, itemId, qty: 30, expiry: today.AddDays(60), number: "FAR");
            SeedBatch(seed, CompanyA, whId, itemId, qty: 30, expiry: null, number: "NONE");
            SeedBatch(seed, CompanyA, whId, itemId, qty: 30, expiry: today.AddDays(10), number: "NEAR");
            seed.SaveChanges();
        }

        using (var ctx = NewContext(dbName))
        {
            var controller = NewController(ctx, CompanyA);
            // تسوية نقص بمقدار 50 ⇒ خصم FEFO
            var result = await controller.AdjustStock(new AdjustStockRequest
            {
                CompanyId = CompanyA,
                WarehouseId = whId,
                InventoryItemId = itemId,
                NewQuantity = 40,
                Reason = "اختبار",
            });
            Assert.IsType<OkObjectResult>(result);
        }

        using (var verify = NewContext(dbName))
        {
            var batches = ReadBatches(verify, itemId);
            var near = batches.Single(b => b.BatchNumber == "NEAR");
            var far = batches.Single(b => b.BatchNumber == "FAR");
            var none = batches.Single(b => b.BatchNumber == "NONE");

            // 50 مخصومة: NEAR(30)→0، FAR(30)→10، NONE بلا صلاحية يبقى 30.
            Assert.Equal(0, near.Quantity);
            Assert.Equal(10, far.Quantity);
            Assert.Equal(30, none.Quantity);
        }
    }

    // ───────────────────────── 3) التسامح مع نقص الدُّفعات ─────────────────────────
    [Fact]
    public async Task Deduction_IsTolerant_WhenBatchesLessThanRequested()
    {
        var dbName = Guid.NewGuid().ToString();
        Guid itemId, whId;
        using (var seed = NewContext(dbName))
        {
            (itemId, whId) = SeedItemWarehouse(seed, CompanyA);
            SeedStock(seed, CompanyA, whId, itemId, qty: 100);   // مخزون موروث
            SeedBatch(seed, CompanyA, whId, itemId, qty: 40, expiry: null, number: "ONLY"); // دُفعات أقل
            seed.SaveChanges();
        }

        using (var ctx = NewContext(dbName))
        {
            var controller = NewController(ctx, CompanyA);
            // خصم 100 بينما الدُّفعات 40 فقط — يجب ألّا يرمي ولا يمنع
            var result = await controller.AdjustStock(new AdjustStockRequest
            {
                CompanyId = CompanyA,
                WarehouseId = whId,
                InventoryItemId = itemId,
                NewQuantity = 0,
                Reason = "تصفير",
            });
            Assert.IsType<OkObjectResult>(result);
        }

        using (var verify = NewContext(dbName))
        {
            var batch = Assert.Single(ReadBatches(verify, itemId));
            Assert.Equal(0, batch.Quantity); // استُهلك المتاح فقط دون استثناء
        }
    }

    // ───────────────────────── 4) تنبيهات expired / expiringSoon ─────────────────────────
    [Fact]
    public async Task Alerts_IncludeExpired_And_ExpiringSoon()
    {
        var dbName = Guid.NewGuid().ToString();
        Guid itemId, whId;
        var today = DateTime.UtcNow.Date;
        using (var seed = NewContext(dbName))
        {
            (itemId, whId) = SeedItemWarehouse(seed, CompanyA);
            SeedBatch(seed, CompanyA, whId, itemId, qty: 5, expiry: today.AddDays(-1));  // منتهية
            SeedBatch(seed, CompanyA, whId, itemId, qty: 5, expiry: today.AddDays(10));  // قريبة
            SeedBatch(seed, CompanyA, whId, itemId, qty: 5, expiry: today.AddDays(200)); // بعيدة
            SeedBatch(seed, CompanyA, whId, itemId, qty: 0, expiry: today.AddDays(5));   // كمية صفر ⇒ تُتجاهل
            seed.SaveChanges();
        }

        using var ctx = NewContext(dbName);
        var controller = NewController(ctx, CompanyA);
        var data = DataOf(await controller.GetInventoryAlerts(null, 30));

        Assert.Equal(1, data.GetProperty("expiredCount").GetInt32());
        Assert.Equal(1, data.GetProperty("expiringSoonCount").GetInt32());
    }

    // ───────────────────────── 5) العزل: شركة لا ترى دُفعات أخرى ─────────────────────────
    [Fact]
    public async Task Batches_AreIsolated_To_Token_Company()
    {
        var dbName = Guid.NewGuid().ToString();
        Guid itemA, whA, itemB, whB;
        var today = DateTime.UtcNow.Date;
        using (var seed = NewContext(dbName))
        {
            (itemA, whA) = SeedItemWarehouse(seed, CompanyA);
            (itemB, whB) = SeedItemWarehouse(seed, CompanyB);
            SeedBatch(seed, CompanyA, whA, itemA, qty: 5, expiry: today.AddDays(-1));  // منتهية (A)
            // شركة B لديها منتهية + قريبة — يجب ألّا تظهر لتوكن A
            SeedBatch(seed, CompanyB, whB, itemB, qty: 5, expiry: today.AddDays(-1));
            SeedBatch(seed, CompanyB, whB, itemB, qty: 5, expiry: today.AddDays(5));
            seed.SaveChanges();
        }

        using var ctx = NewContext(dbName);
        var controllerA = NewController(ctx, CompanyA);

        // تنبيهات A: منتهية واحدة فقط، لا شيء من B
        var data = DataOf(await controllerA.GetInventoryAlerts(CompanyB, 30));
        Assert.Equal(1, data.GetProperty("expiredCount").GetInt32());
        Assert.Equal(0, data.GetProperty("expiringSoonCount").GetInt32());

        // GetItemBatches على مادة شركة B بتوكن A ⇒ 404 (لا كشف عابر للشركات)
        var cross = await controllerA.GetItemBatches(itemB);
        Assert.IsType<NotFoundObjectResult>(cross);

        // GetItemBatches على مادة A يُرجِع دُفعتها
        var own = await controllerA.GetItemBatches(itemA);
        var ownData = DataOf(own);
        Assert.Equal(1, ownData.GetArrayLength());
    }

    // ───────── 6) الصرف المباشر للفني يخصم الدُّفعات FEFO (انحدار P2) ─────────
    [Fact]
    public async Task DirectTechnicianDispensing_DeductsBatches_Fefo()
    {
        var dbName = Guid.NewGuid().ToString();
        Guid itemId, whId;
        var techId = Guid.NewGuid();
        var today = DateTime.UtcNow.Date;
        using (var seed = NewContext(dbName))
        {
            (itemId, whId) = SeedItemWarehouse(seed, CompanyA);
            SeedStock(seed, CompanyA, whId, itemId, qty: 50);
            SeedBatch(seed, CompanyA, whId, itemId, qty: 20, expiry: today.AddDays(60), number: "FAR");
            SeedBatch(seed, CompanyA, whId, itemId, qty: 20, expiry: today.AddDays(10), number: "NEAR");
            seed.Set<User>().Add(new User { Id = techId, CompanyId = CompanyA });
            seed.SaveChanges();
        }

        using (var ctx = NewContext(dbName))
        {
            var controller = NewController(ctx, CompanyA);
            var result = await controller.CreateTechnicianDispensing(new CreateDispensingRequest
            {
                CompanyId = CompanyA,
                WarehouseId = whId,
                TechnicianId = techId,
                Items = new List<DispensingItemDto> { new() { InventoryItemId = itemId, Quantity = 15 } },
            });
            Assert.IsType<OkObjectResult>(result);
        }

        using (var verify = NewContext(dbName))
        {
            var batches = ReadBatches(verify, itemId);
            // 15 مخصومة FEFO: NEAR(20)→5، FAR يبقى 20.
            Assert.Equal(5, batches.Single(b => b.BatchNumber == "NEAR").Quantity);
            Assert.Equal(20, batches.Single(b => b.BatchNumber == "FAR").Quantity);
        }
    }
}
