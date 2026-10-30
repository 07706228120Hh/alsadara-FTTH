namespace Sadara.Application.Inventory;

/// <summary>
/// حساب كلفة المخزون المرجّحة (Weighted Moving Average) — أساس COGS / CostAtSale.
/// مستقلّ عن اشتقاق أسعار البيع في <see cref="PricingCalculator"/> (الذي يعتمد آخر سعر شراء).
/// </summary>
public static class InventoryCosting
{
    /// <summary>
    /// المتوسط المرجّح الجديد بعد إدخال كمية بسعر وحدة معيّن:
    /// <c>(oldQty·oldAvg + incomingQty·unitPrice) / (oldQty + incomingQty)</c>.
    /// إن كانت الكمية الكلّية ≤ 0 (حالة حدّية) تُرجَع كلفة الوحدة الواردة كقيمة آمنة.
    /// </summary>
    /// <param name="oldQuantity">الكمية الحالية قبل الإدخال.</param>
    /// <param name="oldAverageCost">متوسط الكلفة الحالي.</param>
    /// <param name="incomingQuantity">الكمية الواردة.</param>
    /// <param name="incomingUnitPrice">سعر وحدة الكمية الواردة.</param>
    public static decimal WeightedAverageCost(
        decimal oldQuantity, decimal oldAverageCost, decimal incomingQuantity, decimal incomingUnitPrice)
    {
        var newQuantity = oldQuantity + incomingQuantity;
        return newQuantity > 0
            ? ((oldQuantity * oldAverageCost) + (incomingQuantity * incomingUnitPrice)) / newQuantity
            : incomingUnitPrice;
    }
}
