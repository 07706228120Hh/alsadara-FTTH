using Sadara.Application.Inventory;
using Sadara.Domain.Entities;
using Xunit;

namespace Sadara.Integration.Tests;

/// <summary>
/// اختبارات وحدة لـ <see cref="PricingCalculator"/> — منطق اشتقاق أسعار الشرائح من الكلفة والهامش.
/// نقية بالكامل (لا قاعدة بيانات، لا Docker). تغطّي: الهامش الفارغ، الكلفة غير الموجبة،
/// التقريب نصف-لأعلى للعملة، الهامش السالب المفرط، وعدم مسّ الأسعار اليدوية في RecomputeTierPrices.
/// </summary>
public class PricingCalculatorTests
{
    // ── TierPrice ──────────────────────────────────────────────────────────

    [Fact]
    public void TierPrice_NullMargin_Returns_Null()
    {
        Assert.Null(PricingCalculator.TierPrice(cost: 100m, marginPercent: null));
    }

    [Theory]
    [InlineData(0)]
    [InlineData(-5)]
    public void TierPrice_NonPositiveCost_Returns_Null(decimal cost)
    {
        // حتى مع هامش صريح، لا اشتقاق بلا كلفة موجبة
        Assert.Null(PricingCalculator.TierPrice(cost, marginPercent: 25m));
    }

    [Theory]
    [InlineData(100, 0, 100)]       // هامش صفري ⇒ السعر = الكلفة
    [InlineData(100, 25, 125)]      // هامش 25%
    [InlineData(10, 50, 15)]        // هامش 50%
    [InlineData(80, 12.5, 90)]      // هامش كسري
    public void TierPrice_ComputesCostPlusMargin(decimal cost, decimal margin, decimal expected)
    {
        Assert.Equal(expected, PricingCalculator.TierPrice(cost, margin));
    }

    [Fact]
    public void TierPrice_RoundsHalfAwayFromZero_NotBankers()
    {
        // cost=1.005، margin=0 ⇒ 1.005 ⇒ نصف-لأعلى = 1.01 (التقريب البنكي يعطي 1.00)
        Assert.Equal(1.01m, PricingCalculator.TierPrice(1.005m, 0m));
    }

    [Fact]
    public void TierPrice_RoundsToTwoDecimals()
    {
        // cost=33.33، margin=10 ⇒ 36.663 ⇒ 36.66
        Assert.Equal(36.66m, PricingCalculator.TierPrice(33.33m, 10m));
    }

    [Theory]
    [InlineData(-100)]   // الكلفة × 0 = 0 ⇒ سعر صفري ⇒ مرفوض
    [InlineData(-150)]   // سعر سالب ⇒ مرفوض
    public void TierPrice_ExcessiveNegativeMargin_Returns_Null(decimal margin)
    {
        Assert.Null(PricingCalculator.TierPrice(100m, margin));
    }

    // ── RecomputeTierPrices ────────────────────────────────────────────────

    [Fact]
    public void RecomputeTierPrices_SetsAllThreeTiers_WhenMarginsPresent()
    {
        var item = new InventoryItem
        {
            CostPrice = 100m,
            RetailMarginPercent = 30m,
            WholesaleMarginPercent = 20m,
            BulkWholesaleMarginPercent = 10m,
            // أسعار قديمة يجب أن تُستبدل
            SellingPrice = 1m,
            WholesalePrice = 1m,
            BulkWholesalePrice = 1m,
        };

        PricingCalculator.RecomputeTierPrices(item);

        Assert.Equal(130m, item.SellingPrice);
        Assert.Equal(120m, item.WholesalePrice);
        Assert.Equal(110m, item.BulkWholesalePrice);
    }

    [Fact]
    public void RecomputeTierPrices_LeavesManualPrices_WhenMarginNull()
    {
        var item = new InventoryItem
        {
            CostPrice = 100m,
            RetailMarginPercent = 30m,   // مشتقّ
            WholesaleMarginPercent = null, // يدوي — يُترك كما هو
            BulkWholesaleMarginPercent = null, // يدوي — يُترك كما هو
            SellingPrice = 999m,
            WholesalePrice = 77m,
            BulkWholesalePrice = 55m,
        };

        PricingCalculator.RecomputeTierPrices(item);

        Assert.Equal(130m, item.SellingPrice);   // أُعيد حسابه
        Assert.Equal(77m, item.WholesalePrice);   // لم يُمسّ
        Assert.Equal(55m, item.BulkWholesalePrice); // لم يُمسّ
    }

    [Fact]
    public void RecomputeTierPrices_DoesNotOverwrite_WhenCostNonPositive()
    {
        var item = new InventoryItem
        {
            CostPrice = 0m,              // بلا كلفة ⇒ لا اشتقاق
            RetailMarginPercent = 30m,
            SellingPrice = 42m,          // يجب أن يبقى
        };

        PricingCalculator.RecomputeTierPrices(item);

        Assert.Equal(42m, item.SellingPrice);
    }
}
