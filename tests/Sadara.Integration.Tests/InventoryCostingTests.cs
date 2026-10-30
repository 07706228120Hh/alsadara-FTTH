using Sadara.Application.Inventory;
using Xunit;

namespace Sadara.Integration.Tests;

/// <summary>
/// اختبارات وحدة لـ <see cref="InventoryCosting.WeightedAverageCost"/> — المتوسط المرجّح
/// المستخرَج من ثلاثة مواضع مكرّرة في InventoryController (استلام شراء/أمر شراء/تأكيد فاتورة شراء).
/// </summary>
public class InventoryCostingTests
{
    [Fact]
    public void FirstReceipt_IntoEmptyStock_UsesIncomingPrice()
    {
        // مخزون فارغ (0 كمية، 0 متوسط) + 10 وحدات بسعر 5 ⇒ المتوسط = 5
        Assert.Equal(5m, InventoryCosting.WeightedAverageCost(0m, 0m, 10m, 5m));
    }

    [Fact]
    public void SubsequentReceipt_BlendsWeightedAverage()
    {
        // 10 @ 5 (قيمة 50) + 10 @ 7 (قيمة 70) = 120 / 20 = 6
        Assert.Equal(6m, InventoryCosting.WeightedAverageCost(10m, 5m, 10m, 7m));
    }

    [Fact]
    public void UnequalQuantities_WeightsByQuantity()
    {
        // 30 @ 10 (300) + 10 @ 20 (200) = 500 / 40 = 12.5
        Assert.Equal(12.5m, InventoryCosting.WeightedAverageCost(30m, 10m, 10m, 20m));
    }

    [Fact]
    public void ZeroTotalQuantity_FallsBackToIncomingPrice()
    {
        // حالة حدّية: كمية قديمة سالبة تُلغي الواردة ⇒ الرجوع لسعر الوحدة الوارد
        Assert.Equal(8m, InventoryCosting.WeightedAverageCost(-10m, 5m, 10m, 8m));
    }

    [Fact]
    public void MatchesLegacyInlineFormula_ForDecimalPrecision()
    {
        // يطابق الصيغة المضمّنة سابقاً بالضبط (33 @ 3.33 + 7 @ 9.99)
        decimal oldQty = 33m, oldAvg = 3.33m, inQty = 7m, inPrice = 9.99m;
        var expected = ((oldQty * oldAvg) + (inQty * inPrice)) / (oldQty + inQty);
        Assert.Equal(expected, InventoryCosting.WeightedAverageCost(oldQty, oldAvg, inQty, inPrice));
    }
}
