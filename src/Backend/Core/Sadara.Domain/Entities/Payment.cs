using Sadara.Domain.Enums;

namespace Sadara.Domain.Entities;

public class Payment : BaseEntity<Guid>
{
    public Guid OrderId { get; set; }
    public Guid? UserId { get; set; }

    public decimal Amount { get; set; }
    public PaymentMethod Method { get; set; }
    public PaymentStatus Status { get; set; } = PaymentStatus.Pending;

    public string? TransactionId { get; set; }
    public string? GatewayTransactionId { get; set; }
    public string? GatewayResponse { get; set; }
    public string? CardLast4 { get; set; }
    public string? PayerPhone { get; set; }
    public string? PayerName { get; set; }

    public DateTime? PaidAt { get; set; }
    public DateTime? RefundedAt { get; set; }
    public decimal? RefundAmount { get; set; }
    public string? RefundReason { get; set; }

    public string? Notes { get; set; }

    public virtual Order Order { get; set; } = null!;
    public virtual User? User { get; set; }
}

public class Wallet : BaseEntity<Guid>
{
    public Guid UserId { get; set; }
    public decimal Balance { get; set; } = 0;
    public string Currency { get; set; } = "IQD";
    public bool IsActive { get; set; } = true;
    public DateTime? LastTransactionAt { get; set; }

    public virtual User User { get; set; } = null!;
    public virtual ICollection<WalletTransaction> Transactions { get; set; } = new List<WalletTransaction>();
}

public class WalletTransaction : BaseEntity<Guid>
{
    public Guid WalletId { get; set; }
    public Guid? OrderId { get; set; }

    public string Type { get; set; } = string.Empty;
    public decimal Amount { get; set; }
    public decimal BalanceAfter { get; set; }
    public string? Description { get; set; }
    public string? Reference { get; set; }

    public virtual Wallet Wallet { get; set; } = null!;
}
