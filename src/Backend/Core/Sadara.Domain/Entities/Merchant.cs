using Sadara.Domain.Enums;

namespace Sadara.Domain.Entities;

public class Merchant : BaseEntity<Guid>
{
    public Guid UserId { get; set; }
    public string BusinessName { get; set; } = string.Empty;
    public string? BusinessNameAr { get; set; }
    public string? Description { get; set; }
    public string? DescriptionAr { get; set; }
    public string? LogoUrl { get; set; }
    public string? CoverImageUrl { get; set; }
    public string City { get; set; } = string.Empty;
    public string? Area { get; set; }
    public string? Address { get; set; }
    public string? FullAddress { get; set; }
    public string PhoneNumber { get; set; } = string.Empty;
    public string? Email { get; set; }
    public string? Website { get; set; }
    public SubscriptionPlan SubscriptionPlan { get; set; } = SubscriptionPlan.Free;
    public int MaxCustomers { get; set; } = 100;
    public decimal CommissionRate { get; set; } = 5m;
    public decimal WalletBalance { get; set; } = 0;
    public double Rating { get; set; } = 0;
    public int TotalRatings { get; set; } = 0;
    public bool IsVerified { get; set; } = false;
    public DateTime? VerifiedAt { get; set; }
    public bool IsActive { get; set; } = true;
    public DateTime? SubscriptionExpiresAt { get; set; }
    
    public virtual User? User { get; set; }
    public virtual ICollection<Customer> Customers { get; set; } = new List<Customer>();
    public virtual ICollection<Product> Products { get; set; } = new List<Product>();
    public virtual ICollection<Order> Orders { get; set; } = new List<Order>();
}
