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
/// اختبارات endpoint «تنبيهات المخزون» (/api/inventory/alerts): تصنيف نفاد/انخفاض/تجاوز
/// + العزل بشركة التوكن. الأنواع المجهولة داخلية فنقرأ القيم عبر تسلسل JSON.
/// </summary>
public class InventoryAlertsTests
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

    private static void AddItemWithStock(SadaraDbContext ctx, Guid company, string name,
        int min, int max, int qty)
    {
        var itemId = Guid.NewGuid();
        var whId = Guid.NewGuid();
        ctx.Set<InventoryItem>().Add(new InventoryItem
        {
            Id = itemId, CompanyId = company, Name = name, SKU = name, IsActive = true,
            MinStockLevel = min, MaxStockLevel = max, CostPrice = 10,
        });
        ctx.Set<WarehouseStock>().Add(new WarehouseStock
        {
            CompanyId = company, WarehouseId = whId,
            InventoryItemId = itemId, CurrentQuantity = qty, AverageCost = 10,
        });
    }

    private static JsonElement DataOf(IActionResult result)
    {
        var ok = Assert.IsType<OkObjectResult>(result);
        using var doc = JsonDocument.Parse(JsonSerializer.Serialize(ok.Value));
        return doc.RootElement.GetProperty("data").Clone();
    }

    [Fact]
    public async Task Alerts_Classifies_Out_Low_And_Over_Stock()
    {
        var dbName = Guid.NewGuid().ToString();
        using (var seed = NewContext(dbName))
        {
            AddItemWithStock(seed, CompanyA, "نافد", min: 5, max: 100, qty: 0);     // نفاد
            AddItemWithStock(seed, CompanyA, "منخفض", min: 10, max: 100, qty: 3);   // انخفاض
            AddItemWithStock(seed, CompanyA, "زائد", min: 1, max: 50, qty: 120);    // تجاوز
            AddItemWithStock(seed, CompanyA, "سليم", min: 5, max: 100, qty: 40);    // لا تنبيه
            seed.SaveChanges();
        }
        using var ctx = NewContext(dbName);
        var controller = NewController(ctx, CompanyA);

        var data = DataOf(await controller.GetInventoryAlerts(null));

        Assert.Equal(1, data.GetProperty("outOfStockCount").GetInt32());
        Assert.Equal(1, data.GetProperty("lowStockCount").GetInt32());
        Assert.Equal(1, data.GetProperty("overStockCount").GetInt32());
        Assert.Equal(3, data.GetProperty("totalAlerts").GetInt32());
    }

    [Fact]
    public async Task Alerts_AreIsolated_To_Token_Company()
    {
        var dbName = Guid.NewGuid().ToString();
        using (var seed = NewContext(dbName))
        {
            AddItemWithStock(seed, CompanyA, "نافد-أ", min: 5, max: 100, qty: 0);
            // شركة B لديها 3 تنبيهات — يجب ألّا تظهر لتوكن A
            AddItemWithStock(seed, CompanyB, "نافد-ب", min: 5, max: 100, qty: 0);
            AddItemWithStock(seed, CompanyB, "منخفض-ب", min: 10, max: 100, qty: 2);
            AddItemWithStock(seed, CompanyB, "زائد-ب", min: 1, max: 50, qty: 999);
            seed.SaveChanges();
        }
        using var ctx = NewContext(dbName);
        var controller = NewController(ctx, CompanyA);

        // حتى لو مرّر العميل companyId شركة B، يُفرض توكن A
        var data = DataOf(await controller.GetInventoryAlerts(CompanyB));

        Assert.Equal(1, data.GetProperty("totalAlerts").GetInt32());
        Assert.Equal(1, data.GetProperty("outOfStockCount").GetInt32());
    }
}
