using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Sadara.Domain.Entities;
using Sadara.Infrastructure.Data;
using System.Security.Claims;

namespace Sadara.API.Controllers;

/// <summary>
/// باقات الإنترنت - عرض وإدارة الباقات المتاحة
/// </summary>
[ApiController]
[Route("api/citizen/plans")]
[Tags("Internet Plans")]
public class InternetPlansController : ControllerBase
{
    private readonly SadaraDbContext _context;
    private readonly ILogger<InternetPlansController> _logger;

    public InternetPlansController(SadaraDbContext context, ILogger<InternetPlansController> logger)
    {
        _context = context;
        _logger = logger;
    }

    /// <summary>
    /// الحصول على جميع الباقات المتاحة
    /// </summary>
    [HttpGet]
    public async Task<IActionResult> GetPlans([FromQuery] Guid? companyId)
    {
        try
        {
            var query = _context.InternetPlans
                .Where(p => p.IsActive)
                .AsQueryable();

            // إذا تم تحديد شركة
            if (companyId.HasValue)
            {
                query = query.Where(p => p.CompanyId == companyId || p.CompanyId == null);
            }

            var plans = await query
                .OrderBy(p => p.SortOrder)
                .ThenBy(p => p.MonthlyPrice)
                .Select(p => new InternetPlanResponse
                {
                    Id = p.Id,
                    Name = p.Name,
                    NameAr = p.NameAr,
                    Description = p.Description,
                    ImageUrl = p.ImageUrl,
                    SpeedMbps = p.SpeedMbps,
                    DataLimitGB = p.DataLimitGB,
                    IsUnlimited = p.DataLimitGB == null,
                    MonthlyPrice = p.MonthlyPrice,
                    YearlyPrice = p.YearlyPrice,
                    InstallationFee = p.InstallationFee,
                    DurationMonths = p.DurationMonths,
                    Features = p.Features,
                    IsFeatured = p.IsFeatured,
                    Color = p.Color,
                    Badge = p.Badge,
                    CompanyId = p.CompanyId
                })
                .ToListAsync();

            return Ok(new
            {
                success = true,
                count = plans.Count,
                plans
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting plans");
            return StatusCode(500, new { success = false, messageAr = "حدث خطأ", message = "Error occurred" });
        }
    }

    /// <summary>
    /// الحصول على تفاصيل باقة معينة
    /// </summary>
    [HttpGet("{id}")]
    public async Task<IActionResult> GetPlan(Guid id)
    {
        try
        {
            var plan = await _context.InternetPlans
                .Where(p => p.Id == id && p.IsActive)
                .Select(p => new InternetPlanResponse
                {
                    Id = p.Id,
                    Name = p.Name,
                    NameAr = p.NameAr,
                    Description = p.Description,
                    ImageUrl = p.ImageUrl,
                    SpeedMbps = p.SpeedMbps,
                    DataLimitGB = p.DataLimitGB,
                    IsUnlimited = p.DataLimitGB == null,
                    MonthlyPrice = p.MonthlyPrice,
                    YearlyPrice = p.YearlyPrice,
                    InstallationFee = p.InstallationFee,
                    DurationMonths = p.DurationMonths,
                    Features = p.Features,
                    IsFeatured = p.IsFeatured,
                    Color = p.Color,
                    Badge = p.Badge,
                    CompanyId = p.CompanyId
                })
                .FirstOrDefaultAsync();

            if (plan == null)
                return NotFound(new { success = false, messageAr = "الباقة غير موجودة", message = "Plan not found" });

            return Ok(new { success = true, plan });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting plan");
            return StatusCode(500, new { success = false, messageAr = "حدث خطأ", message = "Error occurred" });
        }
    }

    /// <summary>
    /// الحصول على الباقات المميزة
    /// </summary>
    [HttpGet("featured")]
    public async Task<IActionResult> GetFeaturedPlans([FromQuery] Guid? companyId)
    {
        try
        {
            var query = _context.InternetPlans
                .Where(p => p.IsActive && p.IsFeatured)
                .AsQueryable();

            if (companyId.HasValue)
            {
                query = query.Where(p => p.CompanyId == companyId || p.CompanyId == null);
            }

            var plans = await query
                .OrderBy(p => p.SortOrder)
                .Take(3)
                .Select(p => new InternetPlanResponse
                {
                    Id = p.Id,
                    Name = p.Name,
                    NameAr = p.NameAr,
                    Description = p.Description,
                    ImageUrl = p.ImageUrl,
                    SpeedMbps = p.SpeedMbps,
                    DataLimitGB = p.DataLimitGB,
                    IsUnlimited = p.DataLimitGB == null,
                    MonthlyPrice = p.MonthlyPrice,
                    YearlyPrice = p.YearlyPrice,
                    InstallationFee = p.InstallationFee,
                    DurationMonths = p.DurationMonths,
                    Features = p.Features,
                    IsFeatured = p.IsFeatured,
                    Color = p.Color,
                    Badge = p.Badge
                })
                .ToListAsync();

            return Ok(new { success = true, plans });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting featured plans");
            return StatusCode(500, new { success = false, messageAr = "حدث خطأ", message = "Error occurred" });
        }
    }

    /// <summary>
    /// مقارنة الباقات
    /// </summary>
    [HttpPost("compare")]
    public async Task<IActionResult> ComparePlans([FromBody] ComparePlansRequest request)
    {
        try
        {
            if (request.PlanIds == null || request.PlanIds.Count < 2)
                return BadRequest(new { success = false, messageAr = "اختر باقتين على الأقل للمقارنة", message = "Select at least 2 plans to compare" });

            var plans = await _context.InternetPlans
                .Where(p => request.PlanIds.Contains(p.Id) && p.IsActive)
                .Select(p => new InternetPlanResponse
                {
                    Id = p.Id,
                    Name = p.Name,
                    NameAr = p.NameAr,
                    Description = p.Description,
                    SpeedMbps = p.SpeedMbps,
                    DataLimitGB = p.DataLimitGB,
                    IsUnlimited = p.DataLimitGB == null,
                    MonthlyPrice = p.MonthlyPrice,
                    YearlyPrice = p.YearlyPrice,
                    InstallationFee = p.InstallationFee,
                    DurationMonths = p.DurationMonths,
                    Features = p.Features
                })
                .ToListAsync();

            return Ok(new { success = true, plans });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error comparing plans");
            return StatusCode(500, new { success = false, messageAr = "حدث خطأ", message = "Error occurred" });
        }
    }

    /// <summary>
    /// طلب اشتراك في باقة
    /// </summary>
    [HttpPost("{id}/subscribe")]
    [Authorize(AuthenticationSchemes = "CitizenJwt")]
    public async Task<IActionResult> SubscribeToPlan(Guid id, [FromBody] SubscribeToPlanRequest request)
    {
        try
        {
            var citizenId = GetCurrentCitizenId();
            if (citizenId == null)
                return Unauthorized();

            var citizen = await _context.Citizens.FindAsync(citizenId);
            if (citizen == null)
                return NotFound(new { success = false, messageAr = "المستخدم غير موجود", message = "User not found" });

            var plan = await _context.InternetPlans.FindAsync(id);
            if (plan == null || !plan.IsActive)
                return NotFound(new { success = false, messageAr = "الباقة غير موجودة", message = "Plan not found" });

            // التحقق من عدم وجود اشتراك نشط
            var existingActive = await _context.CitizenSubscriptions
                .AnyAsync(s => s.CitizenId == citizenId && 
                              (s.Status == CitizenSubscriptionStatus.Active || 
                               s.Status == CitizenSubscriptionStatus.Pending ||
                               s.Status == CitizenSubscriptionStatus.AwaitingInstallation));

            if (existingActive)
                return BadRequest(new { success = false, messageAr = "لديك اشتراك نشط أو قيد الانتظار", message = "You have an active or pending subscription" });

            // إنشاء رقم اشتراك
            var subscriptionNumber = $"SUB-{DateTime.UtcNow:yyyyMMdd}-{Guid.NewGuid().ToString("N").Substring(0, 6).ToUpper()}";

            var subscription = new CitizenSubscription
            {
                Id = Guid.NewGuid(),
                SubscriptionNumber = subscriptionNumber,
                CitizenId = citizenId!.Value,
                InternetPlanId = id,
                CompanyId = citizen.CompanyId ?? Guid.Empty,
                Status = CitizenSubscriptionStatus.Pending,
                InstallationAddress = request.InstallationAddress ?? citizen.FullAddress,
                InstallationLatitude = request.Latitude ?? citizen.Latitude,
                InstallationLongitude = request.Longitude ?? citizen.Longitude,
                AgreedPrice = plan.MonthlyPrice,
                InstallationFee = plan.InstallationFee,
                AutoRenew = request.AutoRenew,
                Notes = request.Notes,
                CreatedAt = DateTime.UtcNow
            };

            _context.CitizenSubscriptions.Add(subscription);
            await _context.SaveChangesAsync();

            _logger.LogInformation("New subscription request: {SubscriptionNumber} for citizen: {CitizenId}", subscriptionNumber, citizenId);

            return Ok(new
            {
                success = true,
                messageAr = "تم تقديم طلب الاشتراك بنجاح. سنتواصل معك قريباً",
                message = "Subscription request submitted successfully",
                subscription = new
                {
                    subscriptionNumber,
                    subscription.Id,
                    planName = plan.NameAr,
                    status = "Pending",
                    statusAr = "قيد المراجعة"
                }
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error subscribing to plan");
            return StatusCode(500, new { success = false, messageAr = "حدث خطأ", message = "Error occurred" });
        }
    }

    private Guid? GetCurrentCitizenId()
    {
        var claim = User.FindFirst(ClaimTypes.NameIdentifier);
        if (claim == null || !Guid.TryParse(claim.Value, out var id))
            return null;
        return id;
    }
}

// ==================== DTOs ====================

public class InternetPlanResponse
{
    public Guid Id { get; set; }
    public string Name { get; set; } = string.Empty;
    public string NameAr { get; set; } = string.Empty;
    public string? Description { get; set; }
    public string? ImageUrl { get; set; }
    public int? SpeedMbps { get; set; }
    public int? DataLimitGB { get; set; }
    public bool IsUnlimited { get; set; }
    public decimal MonthlyPrice { get; set; }
    public decimal? YearlyPrice { get; set; }
    public decimal InstallationFee { get; set; }
    public int DurationMonths { get; set; }
    public string? Features { get; set; }
    public bool IsFeatured { get; set; }
    public string? Color { get; set; }
    public string? Badge { get; set; }
    public Guid? CompanyId { get; set; }
}

public class ComparePlansRequest
{
    public List<Guid> PlanIds { get; set; } = new();
}

public class SubscribeToPlanRequest
{
    public string? InstallationAddress { get; set; }
    public double? Latitude { get; set; }
    public double? Longitude { get; set; }
    public bool AutoRenew { get; set; } = false;
    public string? Notes { get; set; }
}
