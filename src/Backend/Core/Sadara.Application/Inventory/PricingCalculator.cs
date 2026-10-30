using Sadara.Domain.Entities;

namespace Sadara.Application.Inventory;

/// <summary>
/// منطق اشتقاق أسعار البيع من الكلفة وهامش الربح لكل شريحة.
/// القاعدة: إن وُجد هامش لشريحة ⇒ سعرها = round(الكلفة × (1 + الهامش/100), 2) ويُعاد حسابه
/// عند تغيّر الكلفة. إن لم يوجد هامش ⇒ السعر يدوي ولا يُمسّ.
/// </summary>
public static class PricingCalculator
{
    /// <summary>سعر شريحة من الكلفة والهامش، أو null إن لا هامش.</summary>
    public static decimal? TierPrice(decimal cost, decimal? marginPercent)
    {
        if (marginPercent == null) return null;
        if (cost <= 0) return null; // لا اشتقاق بلا كلفة موجبة
        // تقريب نصف-لأعلى مناسب للعملة (بدل البنكي الافتراضي ToEven)
        var price = decimal.Round(
            cost * (1 + marginPercent.Value / 100m), 2, MidpointRounding.AwayFromZero);
        // هامش سالب مفرط (≤ -100%) قد يُنتج سعراً صفرياً/سالباً ⇒ لا نكتبه
        return price > 0 ? price : null;
    }

    /// <summary>
    /// يُعيد حساب الأسعار الثلاثة على المادة من <see cref="InventoryItem.CostPrice"/>
    /// لكل شريحة لها هامش غير فارغ فقط (يترك الأسعار اليدوية كما هي).
    /// </summary>
    public static void RecomputeTierPrices(InventoryItem item)
    {
        var retail = TierPrice(item.CostPrice, item.RetailMarginPercent);
        if (retail != null) item.SellingPrice = retail;

        var wholesale = TierPrice(item.CostPrice, item.WholesaleMarginPercent);
        if (wholesale != null) item.WholesalePrice = wholesale;

        var bulk = TierPrice(item.CostPrice, item.BulkWholesaleMarginPercent);
        if (bulk != null) item.BulkWholesalePrice = bulk;
    }
}
