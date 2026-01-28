using Sadara.Domain.Enums;

namespace Sadara.Domain.Entities;

// Category entity for product categories
public class Category : BaseEntity<Guid>
{
    public string Name { get; set; } = string.Empty;
    public string NameAr { get; set; } = string.Empty;
    public string? Description { get; set; }
    public string? DescriptionAr { get; set; }
    public string? ImageUrl { get; set; }
    public Guid? ParentCategoryId { get; set; }
    public int DisplayOrder { get; set; }
    public bool IsActive { get; set; } = true;

    public virtual Category? ParentCategory { get; set; }
    public virtual ICollection<Category> SubCategories { get; set; } = new List<Category>();
    public virtual ICollection<Product> Products { get; set; } = new List<Product>();
}

// City entity
public class City : BaseEntity<Guid>
{
    public string Name { get; set; } = string.Empty;
    public string NameAr { get; set; } = string.Empty;
    public string? GovernorateCode { get; set; }
    public int DisplayOrder { get; set; }
    public decimal DeliveryFee { get; set; }
    public bool IsActive { get; set; } = true;

    public virtual ICollection<Area> Areas { get; set; } = new List<Area>();
}

// Area entity (nested in City)
public class Area : BaseEntity<Guid>
{
    public string Name { get; set; } = string.Empty;
    public string NameAr { get; set; } = string.Empty;
    public Guid CityId { get; set; }
    public decimal DeliveryFee { get; set; }
    public bool IsActive { get; set; } = true;

    public virtual City City { get; set; } = null!;
}

// Review entity
public class Review : BaseEntity<Guid>
{
    public Guid ProductId { get; set; }
    public long CustomerId { get; set; }
    public int Rating { get; set; }
    public string? Comment { get; set; }
    public bool IsApproved { get; set; }

    public virtual Product Product { get; set; } = null!;
    public virtual Customer Customer { get; set; } = null!;
}

// Wishlist item
public class WishlistItem : BaseEntity<Guid>
{
    public long CustomerId { get; set; }
    public Guid ProductId { get; set; }

    public virtual Customer Customer { get; set; } = null!;
    public virtual Product Product { get; set; } = null!;
}

// Cart item
public class CartItem : BaseEntity<Guid>
{
    public long CustomerId { get; set; }
    public Guid ProductId { get; set; }
    public int Quantity { get; set; }

    public virtual Customer Customer { get; set; } = null!;
    public virtual Product Product { get; set; } = null!;
}

// Address entity
public class Address : BaseEntity<Guid>
{
    public long CustomerId { get; set; }
    public string Label { get; set; } = string.Empty;
    public string FullAddress { get; set; } = string.Empty;
    public string? Street { get; set; }
    public string? Building { get; set; }
    public string? Floor { get; set; }
    public string? Apartment { get; set; }
    public string? AdditionalInfo { get; set; }
    public Guid CityId { get; set; }
    public Guid? AreaId { get; set; }
    public double? Latitude { get; set; }
    public double? Longitude { get; set; }
    public bool IsDefault { get; set; }

    public virtual Customer Customer { get; set; } = null!;
    public virtual City City { get; set; } = null!;
    public virtual Area? Area { get; set; }
}

// Coupon entity
public class Coupon : BaseEntity<Guid>
{
    public string Code { get; set; } = string.Empty;
    public string? Description { get; set; }
    public string? DescriptionAr { get; set; }
    public DiscountType DiscountType { get; set; }
    public decimal DiscountValue { get; set; }
    public decimal? MinimumOrderAmount { get; set; }
    public decimal? MaximumDiscountAmount { get; set; }
    public int? UsageLimit { get; set; }
    public int UsedCount { get; set; }
    public DateTime StartDate { get; set; }
    public DateTime EndDate { get; set; }
    public bool IsActive { get; set; } = true;
    public Guid? MerchantId { get; set; }
    public Guid? CategoryId { get; set; }

    public virtual Merchant? Merchant { get; set; }
    public virtual Category? Category { get; set; }
}
