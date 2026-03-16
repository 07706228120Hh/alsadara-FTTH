using System.Text.Json.Serialization;

namespace Sadara.Domain.Entities;

/// <summary>مشترك IPTV - بيانات اشتراكات التلفزيون عبر الإنترنت</summary>
public class IptvSubscriber : BaseEntity<long>
{
    [JsonPropertyName("id")]
    public new long Id { get; set; }

    [JsonPropertyName("companyId")]
    public string CompanyId { get; set; } = string.Empty;

    [JsonPropertyName("subscriptionId")]
    public string? SubscriptionId { get; set; }

    [JsonPropertyName("customerName")]
    public string CustomerName { get; set; } = string.Empty;

    [JsonPropertyName("phone")]
    public string? Phone { get; set; }

    [JsonPropertyName("iptvUsername")]
    public string? IptvUsername { get; set; }

    [JsonPropertyName("iptvPassword")]
    public string? IptvPassword { get; set; }

    [JsonPropertyName("iptvCode")]
    public string? IptvCode { get; set; }

    [JsonPropertyName("activationDate")]
    public DateTime? ActivationDate { get; set; }

    [JsonPropertyName("durationMonths")]
    public int DurationMonths { get; set; } = 1;

    [JsonPropertyName("isActive")]
    public bool IsActive { get; set; } = true;

    [JsonPropertyName("location")]
    public string? Location { get; set; }

    [JsonPropertyName("notes")]
    public string? Notes { get; set; }

    [JsonPropertyName("createdAt")]
    public new DateTime CreatedAt { get; set; } = DateTime.UtcNow;

    [JsonPropertyName("updatedAt")]
    public new DateTime? UpdatedAt { get; set; }
}
