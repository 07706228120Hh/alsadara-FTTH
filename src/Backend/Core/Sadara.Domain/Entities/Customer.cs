using Sadara.Domain.Enums;

namespace Sadara.Domain.Entities;

public class Customer : BaseEntity<long>
{
    public Guid MerchantId { get; set; }
    public Guid? UserId { get; set; }
    public string CustomerCode { get; set; } = string.Empty;
    public string FullName { get; set; } = string.Empty;
    public string PhoneNumber { get; set; } = string.Empty;
    public string? Email { get; set; }
    public string City { get; set; } = string.Empty;
    public string? Area { get; set; }
    public string? Address { get; set; }
    public Gender? Gender { get; set; }
    public CustomerType Type { get; set; } = CustomerType.Regular;
    public int TotalOrders { get; set; } = 0;
    public decimal TotalSpent { get; set; } = 0;
    public DateTime? LastOrderDate { get; set; }
    public int Points { get; set; } = 0;
    public decimal WalletBalance { get; set; } = 0;
    public string? Tags { get; set; }
    public string? Notes { get; set; }
    public bool IsActive { get; set; } = true;
    
    public virtual Merchant? Merchant { get; set; }
    public virtual User? User { get; set; }
    public virtual ICollection<Order> Orders { get; set; } = new List<Order>();
}
