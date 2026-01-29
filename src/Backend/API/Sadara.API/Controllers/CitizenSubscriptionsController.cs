using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Sadara.Domain.Entities;
using Sadara.Domain.Enums;
using Sadara.Infrastructure.Data;
using System.Security.Claims;

namespace Sadara.API.Controllers;

/// <summary>
/// اشتراكات المواطن - عرض وإدارة الاشتراكات
/// </summary>
[ApiController]
[Route("api/citizen/subscriptions")]
[Tags("Citizen Subscriptions")]
[Authorize(AuthenticationSchemes = "CitizenJwt")]
public class CitizenSubscriptionsController : ControllerBase
{
    private readonly SadaraDbContext _context;
    private readonly ILogger<CitizenSubscriptionsController> _logger;

    public CitizenSubscriptionsController(SadaraDbContext context, ILogger<CitizenSubscriptionsController> logger)
    {
        _context = context;
        _logger = logger;
    }

    /// <summary>
    /// الحصول على جميع اشتراكاتي
    /// </summary>
    [HttpGet]
    public async Task<IActionResult> GetMySubscriptions()
    {
        try
        {
            var citizenId = GetCurrentCitizenId();
            if (citizenId == null)
                return Unauthorized();

            var subscriptions = await _context.CitizenSubscriptions
                .Include(s => s.Plan)
                .Include(s => s.Company)
                .Where(s => s.CitizenId == citizenId)
                .OrderByDescending(s => s.CreatedAt)
                .Select(s => new SubscriptionResponse
                {
                    Id = s.Id,
                    SubscriptionNumber = s.SubscriptionNumber,
                    PlanId = s.InternetPlanId,
                    PlanName = s.Plan!.NameAr,
                    PlanSpeed = s.Plan.SpeedMbps,
                    CompanyName = s.Company!.NameAr,
                    CompanyLogo = s.Company.LogoUrl,
                    Status = s.Status.ToString(),
                    StatusAr = GetStatusArabic(s.Status),
                    StartDate = s.StartDate,
                    EndDate = s.EndDate,
                    NextRenewalDate = s.NextRenewalDate,
                    AutoRenew = s.AutoRenew,
                    AgreedPrice = s.AgreedPrice,
                    TotalPaid = s.TotalPaid,
                    OutstandingBalance = s.OutstandingBalance,
                    InstallationAddress = s.InstallationAddress,
                    InstalledAt = s.InstalledAt,
                    RouterSerialNumber = s.RouterSerialNumber,
                    IsExpired = s.EndDate.HasValue && DateTime.UtcNow > s.EndDate.Value,
                    DaysRemaining = s.EndDate.HasValue ? Math.Max(0, (s.EndDate.Value - DateTime.UtcNow).Days) : 0,
                    CreatedAt = s.CreatedAt
                })
                .ToListAsync();

            return Ok(new
            {
                success = true,
                count = subscriptions.Count,
                subscriptions
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting subscriptions");
            return StatusCode(500, new { success = false, messageAr = "حدث خطأ", message = "Error occurred" });
        }
    }

    /// <summary>
    /// الحصول على الاشتراك النشط
    /// </summary>
    [HttpGet("active")]
    public async Task<IActionResult> GetActiveSubscription()
    {
        try
        {
            var citizenId = GetCurrentCitizenId();
            if (citizenId == null)
                return Unauthorized();

            var subscription = await _context.CitizenSubscriptions
                .Include(s => s.Plan)
                .Include(s => s.Company)
                .Where(s => s.CitizenId == citizenId && s.Status == CitizenSubscriptionStatus.Active)
                .OrderByDescending(s => s.StartDate)
                .Select(s => new SubscriptionDetailResponse
                {
                    Id = s.Id,
                    SubscriptionNumber = s.SubscriptionNumber,
                    PlanId = s.InternetPlanId,
                    PlanName = s.Plan!.NameAr,
                    PlanSpeed = s.Plan.SpeedMbps,
                    PlanDataLimit = s.Plan.DataLimitGB,
                    PlanFeatures = s.Plan.Features,
                    CompanyId = s.CompanyId,
                    CompanyName = s.Company!.NameAr,
                    CompanyLogo = s.Company.LogoUrl,
                    CompanyPhone = s.Company.Phone,
                    Status = s.Status.ToString(),
                    StatusAr = GetStatusArabic(s.Status),
                    StartDate = s.StartDate,
                    EndDate = s.EndDate,
                    NextRenewalDate = s.NextRenewalDate,
                    AutoRenew = s.AutoRenew,
                    AgreedPrice = s.AgreedPrice,
                    TotalPaid = s.TotalPaid,
                    OutstandingBalance = s.OutstandingBalance,
                    InstallationAddress = s.InstallationAddress,
                    InstallationLatitude = s.InstallationLatitude,
                    InstallationLongitude = s.InstallationLongitude,
                    InstalledAt = s.InstalledAt,
                    RouterSerialNumber = s.RouterSerialNumber,
                    RouterModel = s.RouterModel,
                    ONUSerialNumber = s.ONUSerialNumber,
                    IsExpired = s.EndDate.HasValue && DateTime.UtcNow > s.EndDate.Value,
                    DaysRemaining = s.EndDate.HasValue ? Math.Max(0, (s.EndDate.Value - DateTime.UtcNow).Days) : 0
                })
                .FirstOrDefaultAsync();

            if (subscription == null)
                return NotFound(new { success = false, messageAr = "لا يوجد اشتراك نشط", message = "No active subscription" });

            return Ok(new { success = true, subscription });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting active subscription");
            return StatusCode(500, new { success = false, messageAr = "حدث خطأ", message = "Error occurred" });
        }
    }

    /// <summary>
    /// الحصول على تفاصيل اشتراك معين
    /// </summary>
    [HttpGet("{id}")]
    public async Task<IActionResult> GetSubscription(Guid id)
    {
        try
        {
            var citizenId = GetCurrentCitizenId();
            if (citizenId == null)
                return Unauthorized();

            var subscription = await _context.CitizenSubscriptions
                .Include(s => s.Plan)
                .Include(s => s.Company)
                .Include(s => s.InstalledBy)
                .Where(s => s.Id == id && s.CitizenId == citizenId)
                .Select(s => new SubscriptionDetailResponse
                {
                    Id = s.Id,
                    SubscriptionNumber = s.SubscriptionNumber,
                    PlanId = s.InternetPlanId,
                    PlanName = s.Plan!.NameAr,
                    PlanSpeed = s.Plan.SpeedMbps,
                    PlanDataLimit = s.Plan.DataLimitGB,
                    PlanFeatures = s.Plan.Features,
                    CompanyId = s.CompanyId,
                    CompanyName = s.Company!.NameAr,
                    CompanyLogo = s.Company.LogoUrl,
                    CompanyPhone = s.Company.Phone,
                    Status = s.Status.ToString(),
                    StatusAr = GetStatusArabic(s.Status),
                    StartDate = s.StartDate,
                    EndDate = s.EndDate,
                    NextRenewalDate = s.NextRenewalDate,
                    AutoRenew = s.AutoRenew,
                    AgreedPrice = s.AgreedPrice,
                    InstallationFee = s.InstallationFee,
                    TotalPaid = s.TotalPaid,
                    OutstandingBalance = s.OutstandingBalance,
                    InstallationAddress = s.InstallationAddress,
                    InstallationLatitude = s.InstallationLatitude,
                    InstallationLongitude = s.InstallationLongitude,
                    InstalledAt = s.InstalledAt,
                    InstalledByName = s.InstalledBy != null ? s.InstalledBy.FullName : null,
                    RouterSerialNumber = s.RouterSerialNumber,
                    RouterModel = s.RouterModel,
                    ONUSerialNumber = s.ONUSerialNumber,
                    CancellationReason = s.CancellationReason,
                    CancelledAt = s.CancelledAt,
                    SuspensionReason = s.SuspensionReason,
                    SuspendedAt = s.SuspendedAt,
                    Notes = s.Notes,
                    IsExpired = s.EndDate.HasValue && DateTime.UtcNow > s.EndDate.Value,
                    DaysRemaining = s.EndDate.HasValue ? Math.Max(0, (s.EndDate.Value - DateTime.UtcNow).Days) : 0,
                    CreatedAt = s.CreatedAt
                })
                .FirstOrDefaultAsync();

            if (subscription == null)
                return NotFound(new { success = false, messageAr = "الاشتراك غير موجود", message = "Subscription not found" });

            return Ok(new { success = true, subscription });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting subscription");
            return StatusCode(500, new { success = false, messageAr = "حدث خطأ", message = "Error occurred" });
        }
    }

    /// <summary>
    /// الحصول على مدفوعات اشتراك
    /// </summary>
    [HttpGet("{id}/payments")]
    public async Task<IActionResult> GetSubscriptionPayments(Guid id)
    {
        try
        {
            var citizenId = GetCurrentCitizenId();
            if (citizenId == null)
                return Unauthorized();

            var subscription = await _context.CitizenSubscriptions
                .FirstOrDefaultAsync(s => s.Id == id && s.CitizenId == citizenId);

            if (subscription == null)
                return NotFound(new { success = false, messageAr = "الاشتراك غير موجود", message = "Subscription not found" });

            var payments = await _context.CitizenPayments
                .Where(p => p.CitizenSubscriptionId == id)
                .OrderByDescending(p => p.CreatedAt)
                .Select(p => new PaymentResponse
                {
                    Id = p.Id,
                    PaymentNumber = p.TransactionNumber,
                    Amount = p.Amount,
                    PaymentType = p.PaymentType.ToString(),
                    PaymentTypeAr = GetPaymentTypeArabic(p.PaymentType),
                    Status = p.Status.ToString(),
                    StatusAr = GetPaymentStatusArabic(p.Status),
                    PaidAt = p.PaidAt,
                    Notes = p.Notes,
                    CreatedAt = p.CreatedAt
                })
                .ToListAsync();

            return Ok(new
            {
                success = true,
                count = payments.Count,
                totalPaid = payments.Where(p => p.Status == "Success").Sum(p => p.Amount),
                payments
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting payments");
            return StatusCode(500, new { success = false, messageAr = "حدث خطأ", message = "Error occurred" });
        }
    }

    /// <summary>
    /// تفعيل/إلغاء التجديد التلقائي
    /// </summary>
    [HttpPost("{id}/auto-renew")]
    public async Task<IActionResult> ToggleAutoRenew(Guid id, [FromBody] ToggleAutoRenewRequest request)
    {
        try
        {
            var citizenId = GetCurrentCitizenId();
            if (citizenId == null)
                return Unauthorized();

            var subscription = await _context.CitizenSubscriptions
                .FirstOrDefaultAsync(s => s.Id == id && s.CitizenId == citizenId);

            if (subscription == null)
                return NotFound(new { success = false, messageAr = "الاشتراك غير موجود", message = "Subscription not found" });

            subscription.AutoRenew = request.AutoRenew;
            subscription.UpdatedAt = DateTime.UtcNow;

            await _context.SaveChangesAsync();

            return Ok(new
            {
                success = true,
                messageAr = request.AutoRenew ? "تم تفعيل التجديد التلقائي" : "تم إلغاء التجديد التلقائي",
                message = request.AutoRenew ? "Auto-renew enabled" : "Auto-renew disabled",
                autoRenew = subscription.AutoRenew
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error toggling auto-renew");
            return StatusCode(500, new { success = false, messageAr = "حدث خطأ", message = "Error occurred" });
        }
    }

    /// <summary>
    /// طلب إلغاء اشتراك
    /// </summary>
    [HttpPost("{id}/cancel")]
    public async Task<IActionResult> RequestCancellation(Guid id, [FromBody] CancellationRequest request)
    {
        try
        {
            var citizenId = GetCurrentCitizenId();
            if (citizenId == null)
                return Unauthorized();

            var subscription = await _context.CitizenSubscriptions
                .FirstOrDefaultAsync(s => s.Id == id && s.CitizenId == citizenId);

            if (subscription == null)
                return NotFound(new { success = false, messageAr = "الاشتراك غير موجود", message = "Subscription not found" });

            if (subscription.Status == CitizenSubscriptionStatus.Cancelled)
                return BadRequest(new { success = false, messageAr = "الاشتراك ملغي مسبقاً", message = "Subscription already cancelled" });

            subscription.CancellationReason = request.Reason;
            // لا نلغيه مباشرة، نترك الشركة تقوم بذلك
            subscription.Notes = $"[طلب إلغاء من المواطن]: {request.Reason}";
            subscription.UpdatedAt = DateTime.UtcNow;

            await _context.SaveChangesAsync();

            _logger.LogInformation("Cancellation requested for subscription: {SubscriptionNumber}", subscription.SubscriptionNumber);

            return Ok(new
            {
                success = true,
                messageAr = "تم تقديم طلب الإلغاء. سيتم مراجعته من قبل الشركة",
                message = "Cancellation request submitted"
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error requesting cancellation");
            return StatusCode(500, new { success = false, messageAr = "حدث خطأ", message = "Error occurred" });
        }
    }

    /// <summary>
    /// طلب ترقية الباقة
    /// </summary>
    [HttpPost("{id}/upgrade")]
    public async Task<IActionResult> RequestUpgrade(Guid id, [FromBody] UpgradeRequest request)
    {
        try
        {
            var citizenId = GetCurrentCitizenId();
            if (citizenId == null)
                return Unauthorized();

            var subscription = await _context.CitizenSubscriptions
                .Include(s => s.Plan)
                .FirstOrDefaultAsync(s => s.Id == id && s.CitizenId == citizenId);

            if (subscription == null)
                return NotFound(new { success = false, messageAr = "الاشتراك غير موجود", message = "Subscription not found" });

            if (subscription.Status != CitizenSubscriptionStatus.Active)
                return BadRequest(new { success = false, messageAr = "يجب أن يكون الاشتراك نشطاً للترقية", message = "Subscription must be active to upgrade" });

            var newPlan = await _context.InternetPlans.FindAsync(request.NewPlanId);
            if (newPlan == null || !newPlan.IsActive)
                return NotFound(new { success = false, messageAr = "الباقة الجديدة غير موجودة", message = "New plan not found" });

            if (newPlan.MonthlyPrice <= subscription.Plan!.MonthlyPrice)
                return BadRequest(new { success = false, messageAr = "اختر باقة أعلى للترقية", message = "Select a higher plan for upgrade" });

            // إنشاء طلب خدمة للترقية
            // TODO: إنشاء ServiceRequest للترقية

            subscription.Notes = $"[طلب ترقية]: من {subscription.Plan.NameAr} إلى {newPlan.NameAr}";
            subscription.UpdatedAt = DateTime.UtcNow;

            await _context.SaveChangesAsync();

            return Ok(new
            {
                success = true,
                messageAr = "تم تقديم طلب الترقية. سيتم مراجعته من قبل الشركة",
                message = "Upgrade request submitted",
                currentPlan = subscription.Plan.NameAr,
                newPlan = newPlan.NameAr,
                priceDifference = newPlan.MonthlyPrice - subscription.AgreedPrice
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error requesting upgrade");
            return StatusCode(500, new { success = false, messageAr = "حدث خطأ", message = "Error occurred" });
        }
    }

    // ==================== Helper Methods ====================

    private Guid? GetCurrentCitizenId()
    {
        var claim = User.FindFirst(ClaimTypes.NameIdentifier);
        if (claim == null || !Guid.TryParse(claim.Value, out var id))
            return null;
        return id;
    }

    private static string GetStatusArabic(CitizenSubscriptionStatus status) => status switch
    {
        CitizenSubscriptionStatus.Pending => "قيد المراجعة",
        CitizenSubscriptionStatus.AwaitingInstallation => "بانتظار التركيب",
        CitizenSubscriptionStatus.Active => "نشط",
        CitizenSubscriptionStatus.Suspended => "موقوف مؤقتاً",
        CitizenSubscriptionStatus.Expired => "منتهي",
        CitizenSubscriptionStatus.Cancelled => "ملغي",
        _ => status.ToString()
    };

    private static string GetPaymentTypeArabic(CitizenPaymentType type) => type switch
    {
        CitizenPaymentType.Installation => "رسوم تركيب",
        CitizenPaymentType.MonthlySubscription => "اشتراك شهري",
        CitizenPaymentType.Maintenance => "صيانة",
        CitizenPaymentType.ProductPurchase => "شراء منتج",
        CitizenPaymentType.Upgrade => "رسوم ترقية",
        CitizenPaymentType.LateFee => "غرامة تأخير",
        CitizenPaymentType.Other => "أخرى",
        _ => type.ToString()
    };

    private static string GetPaymentStatusArabic(PaymentStatus status) => status switch
    {
        PaymentStatus.Pending => "قيد الانتظار",
        PaymentStatus.Success => "مدفوع",
        PaymentStatus.Failed => "فشل",
        PaymentStatus.Refunded => "مسترد",
        PaymentStatus.Cancelled => "ملغي",
        _ => status.ToString()
    };
}

// ==================== DTOs ====================

public class SubscriptionResponse
{
    public Guid Id { get; set; }
    public string SubscriptionNumber { get; set; } = string.Empty;
    public Guid PlanId { get; set; }
    public string PlanName { get; set; } = string.Empty;
    public int? PlanSpeed { get; set; }
    public string CompanyName { get; set; } = string.Empty;
    public string? CompanyLogo { get; set; }
    public string Status { get; set; } = string.Empty;
    public string StatusAr { get; set; } = string.Empty;
    public DateTime? StartDate { get; set; }
    public DateTime? EndDate { get; set; }
    public DateTime? NextRenewalDate { get; set; }
    public bool AutoRenew { get; set; }
    public decimal AgreedPrice { get; set; }
    public decimal TotalPaid { get; set; }
    public decimal OutstandingBalance { get; set; }
    public string? InstallationAddress { get; set; }
    public DateTime? InstalledAt { get; set; }
    public string? RouterSerialNumber { get; set; }
    public bool IsExpired { get; set; }
    public int DaysRemaining { get; set; }
    public DateTime CreatedAt { get; set; }
}

public class SubscriptionDetailResponse : SubscriptionResponse
{
    public int? PlanDataLimit { get; set; }
    public string? PlanFeatures { get; set; }
    public Guid CompanyId { get; set; }
    public string? CompanyPhone { get; set; }
    public decimal InstallationFee { get; set; }
    public double? InstallationLatitude { get; set; }
    public double? InstallationLongitude { get; set; }
    public string? InstalledByName { get; set; }
    public string? RouterModel { get; set; }
    public string? ONUSerialNumber { get; set; }
    public string? CancellationReason { get; set; }
    public DateTime? CancelledAt { get; set; }
    public string? SuspensionReason { get; set; }
    public DateTime? SuspendedAt { get; set; }
    public string? Notes { get; set; }
}

public class PaymentResponse
{
    public Guid Id { get; set; }
    public string PaymentNumber { get; set; } = string.Empty;
    public decimal Amount { get; set; }
    public string PaymentType { get; set; } = string.Empty;
    public string PaymentTypeAr { get; set; } = string.Empty;
    public string Status { get; set; } = string.Empty;
    public string StatusAr { get; set; } = string.Empty;
    public DateTime? PaidAt { get; set; }
    public string? Notes { get; set; }
    public DateTime CreatedAt { get; set; }
}

public class ToggleAutoRenewRequest
{
    public bool AutoRenew { get; set; }
}

public class CancellationRequest
{
    public string? Reason { get; set; }
}

public class UpgradeRequest
{
    public Guid NewPlanId { get; set; }
}
