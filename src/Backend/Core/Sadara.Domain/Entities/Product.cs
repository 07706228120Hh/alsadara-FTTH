namespace Sadara.Domain.Entities;

public class Product : BaseEntity<Guid>
{
    public Guid MerchantId { get; set; }
    public Guid? CategoryId { get; set; }
    public string Name { get; set; } = string.Empty;
    public string? NameAr { get; set; }
    public string? Description { get; set; }
    public string? DescriptionAr { get; set; }
    public string SKU { get; set; } = string.Empty;
    public decimal Price { get; set; }
    public decimal? DiscountPrice { get; set; }
    public decimal CostPrice { get; set; }
    public int StockQuantity { get; set; }
    public int LowStockThreshold { get; set; } = 10;
    public string? ImageUrl { get; set; }
    public string? Images { get; set; }
    public bool IsActive { get; set; } = true;
    public bool IsAvailable { get; set; } = true;
    public bool IsFeatured { get; set; } = false;
    public int SortOrder { get; set; } = 0;
    public int ViewCount { get; set; } = 0;
    public int SoldCount { get; set; } = 0;
    public decimal AverageRating { get; set; } = 0;
    public int ReviewCount { get; set; } = 0;

    public virtual Merchant? Merchant { get; set; }
    public virtual Category? Category { get; set; }
    public virtual ICollection<ProductVariant> Variants { get; set; } = new List<ProductVariant>();
    public virtual ICollection<OrderItem> OrderItems { get; set; } = new List<OrderItem>();
    public virtual ICollection<Review> Reviews { get; set; } = new List<Review>();
}

public class ProductVariant : BaseEntity<Guid>
{
    public Guid ProductId { get; set; }
    public string Name { get; set; } = string.Empty;
    public string? NameAr { get; set; }
    public string? Value { get; set; }
    public decimal? PriceAdjustment { get; set; }
    public int StockQuantity { get; set; }
    public string? SKU { get; set; }
    public bool IsAvailable { get; set; } = true;

    public virtual Product? Product { get; set; }
}
