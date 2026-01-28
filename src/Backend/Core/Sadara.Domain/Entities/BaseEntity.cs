namespace Sadara.Domain.Entities;

public abstract class BaseEntity
{
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    public DateTime? UpdatedAt { get; set; }
    public bool IsDeleted { get; set; } = false;
    public DateTime? DeletedAt { get; set; }
}

public abstract class BaseEntity<TId> : BaseEntity
{
    public TId Id { get; set; } = default!;
}
