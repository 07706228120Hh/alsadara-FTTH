using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Sadara.Domain.Entities;
using Sadara.Domain.Enums;
using Sadara.Domain.Interfaces;
using Sadara.Infrastructure.Data;
using System.Security.Claims;

namespace Sadara.API.Controllers;

/// <summary>
/// نظام المواطن - لوحة تحكم الشركة المرتبطة (CompanyDesktop App)
/// هذه APIs خاصة بالشركة المرتبطة بنظام المواطن فقط
/// </summary>
[ApiController]
[Route("api/citizen-portal")]
[Tags("Citizen Portal Management")]
[Authorize]
public class CitizenPortalController : ControllerBase
{
    private readonly SadaraDbContext _context;
    private readonly IUnitOfWork _unitOfWork;
    private readonly ILogger<CitizenPortalController> _logger;

    public CitizenPortalController(
        SadaraDbContext context,
        IUnitOfWork unitOfWork,
        ILogger<CitizenPortalController> logger)
    {
        _context = context;
        _unitOfWork = unitOfWork;
        _logger = logger;
    }

    #region Dashboard Statistics

    /// <summary>
    /// إحصائيات لوحة التحكم الرئيسية
    /// </summary>
    [HttpGet("dashboard/stats")]
    public async Task<IActionResult> GetDashboardStats()
    {
        try
        {
            var companyId = await GetLinkedCompanyId();
            if (companyId == null)
                return Forbid("هذه الشركة غير مرتبطة بنظام المواطن");

            var today = DateTime.UtcNow.AddHours(3).Date;
            var thisMonth = new DateTime(today.Year, today.Month, 1);

            // إحصائيات المواطنين
            var totalCitizens = await _context.Citizens.CountAsync(c => c.CompanyId == companyId && !c.IsDeleted);
            var activeCitizens = await _context.Citizens.CountAsync(c => c.CompanyId == companyId && c.IsActive && !c.IsDeleted);
            var newCitizensToday = await _context.Citizens.CountAsync(c => c.CompanyId == companyId && c.CreatedAt >= today && !c.IsDeleted);
            var newCitizensThisMonth = await _context.Citizens.CountAsync(c => c.CompanyId == companyId && c.CreatedAt >= thisMonth && !c.IsDeleted);

            // إحصائيات الاشتراكات
            var totalSubscriptions = await _context.CitizenSubscriptions.CountAsync(s => s.CompanyId == companyId);
            var activeSubscriptions = await _context.CitizenSubscriptions.CountAsync(s => s.CompanyId == companyId && s.Status == CitizenSubscriptionStatus.Active);
            var pendingSubscriptions = await _context.CitizenSubscriptions.CountAsync(s => s.CompanyId == companyId && s.Status == CitizenSubscriptionStatus.AwaitingInstallation);
            var expiredSubscriptions = await _context.CitizenSubscriptions.CountAsync(s => s.CompanyId == companyId && s.Status == CitizenSubscriptionStatus.Expired);

            // إحصائيات المدفوعات
            var totalPaidThisMonth = await _context.CitizenPayments
                .Where(p => p.CompanyId == companyId && p.Status == PaymentStatus.Success && p.CreatedAt >= thisMonth)
                .SumAsync(p => p.Amount);
            
            var pendingPayments = await _context.CitizenPayments
                .Where(p => p.CompanyId == companyId && p.Status == PaymentStatus.Pending)
                .SumAsync(p => p.Amount);

            // إحصائيات تذاكر الدعم
            var openTickets = await _context.SupportTickets.CountAsync(t => t.CompanyId == companyId && t.Status == TicketStatus.Open);
            var inProgressTickets = await _context.SupportTickets.CountAsync(t => t.CompanyId == companyId && t.Status == TicketStatus.InProgress);

            // طلبات الخدمات
            var pendingRequests = await _context.ServiceRequests
                .CountAsync(r => r.CompanyId == companyId && r.Status == ServiceRequestStatus.Pending);

            return Ok(new
            {
                success = true,
                data = new
                {
                    citizens = new
                    {
                        total = totalCitizens,
                        active = activeCitizens,
                        inactive = totalCitizens - activeCitizens,
                        newToday = newCitizensToday,
                        newThisMonth = newCitizensThisMonth
                    },
                    subscriptions = new
                    {
                        total = totalSubscriptions,
                        active = activeSubscriptions,
                        pending = pendingSubscriptions,
                        expired = expiredSubscriptions
                    },
                    payments = new
                    {
                        totalThisMonth = totalPaidThisMonth,
                        pendingAmount = pendingPayments
                    },
                    support = new
                    {
                        openTickets,
                        inProgressTickets
                    },
                    serviceRequests = new
                    {
                        pending = pendingRequests
                    }
                }
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting dashboard stats");
            return StatusCode(500, new { success = false, message = "حدث خطأ في النظام" });
        }
    }

    #endregion

    #region Citizens Management

    /// <summary>
    /// قائمة المواطنين مع فلترة وبحث
    /// </summary>
    [HttpGet("citizens")]
    public async Task<IActionResult> GetCitizens(
        [FromQuery] string? search = null,
        [FromQuery] string? city = null,
        [FromQuery] bool? isActive = null,
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 20)
    {
        try
        {
            var companyId = await GetLinkedCompanyId();
            if (companyId == null)
                return Forbid("هذه الشركة غير مرتبطة بنظام المواطن");

            var query = _context.Citizens
                .Where(c => c.CompanyId == companyId && !c.IsDeleted)
                .AsQueryable();

            // البحث
            if (!string.IsNullOrEmpty(search))
            {
                query = query.Where(c => 
                    c.FullName.Contains(search) || 
                    c.PhoneNumber.Contains(search) ||
                    (c.Email != null && c.Email.Contains(search)));
            }

            // فلترة بالمدينة
            if (!string.IsNullOrEmpty(city))
            {
                query = query.Where(c => c.City == city);
            }

            // فلترة بالحالة
            if (isActive.HasValue)
            {
                query = query.Where(c => c.IsActive == isActive.Value);
            }

            var total = await query.CountAsync();

            var citizens = await query
                .OrderByDescending(c => c.CreatedAt)
                .Skip((page - 1) * pageSize)
                .Take(pageSize)
                .Select(c => new
                {
                    c.Id,
                    c.FullName,
                    c.PhoneNumber,
                    c.Email,
                    c.City,
                    c.District,
                    c.IsActive,
                    c.TotalPaid,
                    c.CreatedAt,
                    activeSubscription = c.Subscriptions
                        .Where(s => s.Status == CitizenSubscriptionStatus.Active)
                        .Select(s => new { s.Plan!.NameAr, s.Plan.SpeedMbps })
                        .FirstOrDefault()
                })
                .ToListAsync();

            return Ok(new
            {
                success = true,
                total,
                page,
                pageSize,
                totalPages = (int)Math.Ceiling((double)total / pageSize),
                citizens
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting citizens list");
            return StatusCode(500, new { success = false, message = "حدث خطأ في النظام" });
        }
    }

    /// <summary>
    /// تفاصيل مواطن معين
    /// </summary>
    [HttpGet("citizens/{id:guid}")]
    public async Task<IActionResult> GetCitizenDetails(Guid id)
    {
        try
        {
            var companyId = await GetLinkedCompanyId();
            if (companyId == null)
                return Forbid("هذه الشركة غير مرتبطة بنظام المواطن");

            var citizen = await _context.Citizens
                .Include(c => c.Subscriptions)
                    .ThenInclude(s => s.Plan)
                .Include(c => c.SupportTickets)
                .Include(c => c.Payments)
                .Where(c => c.Id == id && c.CompanyId == companyId && !c.IsDeleted)
                .FirstOrDefaultAsync();

            if (citizen == null)
                return NotFound(new { success = false, message = "المواطن غير موجود" });

            return Ok(new
            {
                success = true,
                citizen = new
                {
                    citizen.Id,
                    citizen.FullName,
                    citizen.PhoneNumber,
                    citizen.Email,
                    citizen.City,
                    citizen.District,
                    citizen.FullAddress,
                    citizen.IsActive,
                    citizen.TotalPaid,
                    citizen.CreatedAt,
                    citizen.LanguagePreference,
                    subscriptions = citizen.Subscriptions.Select(s => new
                    {
                        s.Id,
                        s.SubscriptionNumber,
                        PlanName = s.Plan?.NameAr,
                        Speed = s.Plan?.SpeedMbps,
                        s.Status,
                        s.StartDate,
                        s.EndDate,
                        s.AgreedPrice,
                        s.TotalPaid,
                        s.OutstandingBalance
                    }),
                    ticketsCount = citizen.SupportTickets.Count,
                    openTickets = citizen.SupportTickets.Count(t => t.Status == TicketStatus.Open),
                    totalPayments = citizen.Payments.Where(p => p.Status == PaymentStatus.Success).Sum(p => p.Amount),
                    lastPaymentDate = citizen.Payments.Where(p => p.Status == PaymentStatus.Success).OrderByDescending(p => p.CreatedAt).FirstOrDefault()?.CreatedAt
                }
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting citizen details");
            return StatusCode(500, new { success = false, message = "حدث خطأ في النظام" });
        }
    }

    /// <summary>
    /// إضافة مواطن جديد
    /// </summary>
    [HttpPost("citizens")]
    public async Task<IActionResult> CreateCitizen([FromBody] CreateCitizenRequest request)
    {
        try
        {
            var companyId = await GetLinkedCompanyId();
            if (companyId == null)
                return Forbid("هذه الشركة غير مرتبطة بنظام المواطن");

            // التحقق من عدم تكرار رقم الهاتف
            var existingCitizen = await _context.Citizens
                .FirstOrDefaultAsync(c => c.PhoneNumber == request.PhoneNumber && !c.IsDeleted);

            if (existingCitizen != null)
                return BadRequest(new { success = false, message = "رقم الهاتف مسجل مسبقاً" });

            var citizen = new Citizen
            {
                FullName = request.FullName,
                PhoneNumber = request.PhoneNumber,
                Email = request.Email,
                City = request.City,
                District = request.District,
                FullAddress = request.FullAddress,
                CompanyId = companyId.Value,
                IsActive = true,
                LanguagePreference = "ar",
                AssignedById = GetCurrentUserId(),
                CreatedAt = DateTime.UtcNow
            };

            await _context.Citizens.AddAsync(citizen);
            await _context.SaveChangesAsync();

            _logger.LogInformation("تم إنشاء مواطن جديد: {CitizenId} من قبل: {UserId}", citizen.Id, GetCurrentUserId());

            return Ok(new
            {
                success = true,
                message = "تم إضافة المواطن بنجاح",
                citizenId = citizen.Id
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error creating citizen");
            return StatusCode(500, new { success = false, message = "حدث خطأ في النظام" });
        }
    }

    /// <summary>
    /// تحديث بيانات مواطن
    /// </summary>
    [HttpPut("citizens/{id:guid}")]
    public async Task<IActionResult> UpdateCitizen(Guid id, [FromBody] UpdateCitizenRequest request)
    {
        try
        {
            var companyId = await GetLinkedCompanyId();
            if (companyId == null)
                return Forbid("هذه الشركة غير مرتبطة بنظام المواطن");

            var citizen = await _context.Citizens
                .FirstOrDefaultAsync(c => c.Id == id && c.CompanyId == companyId && !c.IsDeleted);

            if (citizen == null)
                return NotFound(new { success = false, message = "المواطن غير موجود" });

            citizen.FullName = request.FullName ?? citizen.FullName;
            citizen.Email = request.Email ?? citizen.Email;
            citizen.City = request.City ?? citizen.City;
            citizen.District = request.District ?? citizen.District;
            citizen.FullAddress = request.FullAddress ?? citizen.FullAddress;
            citizen.IsActive = request.IsActive ?? citizen.IsActive;
            citizen.UpdatedAt = DateTime.UtcNow;

            await _context.SaveChangesAsync();

            return Ok(new { success = true, message = "تم تحديث البيانات بنجاح" });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error updating citizen");
            return StatusCode(500, new { success = false, message = "حدث خطأ في النظام" });
        }
    }

    #endregion

    #region Subscriptions Management

    /// <summary>
    /// قائمة الاشتراكات
    /// </summary>
    [HttpGet("subscriptions")]
    public async Task<IActionResult> GetSubscriptions(
        [FromQuery] CitizenSubscriptionStatus? status = null,
        [FromQuery] Guid? planId = null,
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 20)
    {
        try
        {
            var companyId = await GetLinkedCompanyId();
            if (companyId == null)
                return Forbid("هذه الشركة غير مرتبطة بنظام المواطن");

            var query = _context.CitizenSubscriptions
                .Include(s => s.Citizen)
                .Include(s => s.Plan)
                .Where(s => s.CompanyId == companyId)
                .AsQueryable();

            if (status.HasValue)
                query = query.Where(s => s.Status == status.Value);

            if (planId.HasValue)
                query = query.Where(s => s.InternetPlanId == planId.Value);

            var total = await query.CountAsync();

            var subscriptions = await query
                .OrderByDescending(s => s.CreatedAt)
                .Skip((page - 1) * pageSize)
                .Take(pageSize)
                .Select(s => new
                {
                    s.Id,
                    s.SubscriptionNumber,
                    CitizenName = s.Citizen!.FullName,
                    CitizenPhone = s.Citizen.PhoneNumber,
                    PlanName = s.Plan!.NameAr,
                    PlanSpeed = s.Plan.SpeedMbps,
                    s.Status,
                    StatusAr = GetStatusArabic(s.Status),
                    s.StartDate,
                    s.EndDate,
                    s.AgreedPrice,
                    s.TotalPaid,
                    s.OutstandingBalance,
                    s.InstallationAddress,
                    s.AutoRenew,
                    s.CreatedAt
                })
                .ToListAsync();

            return Ok(new
            {
                success = true,
                total,
                page,
                pageSize,
                subscriptions
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting subscriptions");
            return StatusCode(500, new { success = false, message = "حدث خطأ في النظام" });
        }
    }

    /// <summary>
    /// إنشاء اشتراك جديد لمواطن
    /// </summary>
    [HttpPost("subscriptions")]
    public async Task<IActionResult> CreateSubscription([FromBody] CreateSubscriptionRequest request)
    {
        try
        {
            var companyId = await GetLinkedCompanyId();
            if (companyId == null)
                return Forbid("هذه الشركة غير مرتبطة بنظام المواطن");

            // التحقق من المواطن
            var citizen = await _context.Citizens
                .FirstOrDefaultAsync(c => c.Id == request.CitizenId && c.CompanyId == companyId && !c.IsDeleted);

            if (citizen == null)
                return NotFound(new { success = false, message = "المواطن غير موجود" });

            // التحقق من الباقة
            var plan = await _context.InternetPlans
                .FirstOrDefaultAsync(p => p.Id == request.PlanId && p.CompanyId == companyId && p.IsActive);

            if (plan == null)
                return NotFound(new { success = false, message = "الباقة غير موجودة" });

            // إنشاء رقم الاشتراك
            var subscriptionNumber = $"SUB-{DateTime.UtcNow:yyyyMMdd}-{new Random().Next(1000, 9999)}";

            var subscription = new CitizenSubscription
            {
                SubscriptionNumber = subscriptionNumber,
                CitizenId = request.CitizenId,
                InternetPlanId = request.PlanId,
                CompanyId = companyId.Value,
                Status = CitizenSubscriptionStatus.AwaitingInstallation,
                InstallationAddress = request.InstallationAddress,
                AgreedPrice = request.CustomPrice ?? plan.MonthlyPrice,
                InstallationFee = plan.InstallationFee,
                AutoRenew = request.AutoRenew,
                Notes = request.Notes,
                CreatedAt = DateTime.UtcNow
            };

            await _context.CitizenSubscriptions.AddAsync(subscription);
            await _context.SaveChangesAsync();

            _logger.LogInformation("تم إنشاء اشتراك جديد: {SubscriptionNumber} للمواطن: {CitizenId}", subscriptionNumber, request.CitizenId);

            return Ok(new
            {
                success = true,
                message = "تم إنشاء الاشتراك بنجاح",
                subscriptionId = subscription.Id,
                subscriptionNumber
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error creating subscription");
            return StatusCode(500, new { success = false, message = "حدث خطأ في النظام" });
        }
    }

    /// <summary>
    /// تفعيل الاشتراك (بعد التركيب)
    /// </summary>
    [HttpPost("subscriptions/{id:guid}/activate")]
    public async Task<IActionResult> ActivateSubscription(Guid id, [FromBody] ActivateSubscriptionRequest request)
    {
        try
        {
            var companyId = await GetLinkedCompanyId();
            if (companyId == null)
                return Forbid("هذه الشركة غير مرتبطة بنظام المواطن");

            var subscription = await _context.CitizenSubscriptions
                .Include(s => s.Plan)
                .FirstOrDefaultAsync(s => s.Id == id && s.CompanyId == companyId);

            if (subscription == null)
                return NotFound(new { success = false, message = "الاشتراك غير موجود" });

            if (subscription.Status != CitizenSubscriptionStatus.AwaitingInstallation)
                return BadRequest(new { success = false, message = "لا يمكن تفعيل هذا الاشتراك" });

            var now = DateTime.UtcNow;
            subscription.Status = CitizenSubscriptionStatus.Active;
            subscription.StartDate = now;
            subscription.EndDate = now.AddMonths(1);
            subscription.NextRenewalDate = subscription.EndDate;
            subscription.InstalledAt = now;
            subscription.InstalledById = GetCurrentUserId();
            subscription.RouterSerialNumber = request.RouterSerialNumber;
            subscription.RouterModel = request.RouterModel;
            subscription.ONUSerialNumber = request.ONUSerialNumber;
            subscription.UpdatedAt = now;

            await _context.SaveChangesAsync();

            return Ok(new { success = true, message = "تم تفعيل الاشتراك بنجاح" });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error activating subscription");
            return StatusCode(500, new { success = false, message = "حدث خطأ في النظام" });
        }
    }

    /// <summary>
    /// إلغاء اشتراك
    /// </summary>
    [HttpPost("subscriptions/{id:guid}/cancel")]
    public async Task<IActionResult> CancelSubscription(Guid id, [FromBody] CancelSubscriptionRequest request)
    {
        try
        {
            var companyId = await GetLinkedCompanyId();
            if (companyId == null)
                return Forbid("هذه الشركة غير مرتبطة بنظام المواطن");

            var subscription = await _context.CitizenSubscriptions
                .FirstOrDefaultAsync(s => s.Id == id && s.CompanyId == companyId);

            if (subscription == null)
                return NotFound(new { success = false, message = "الاشتراك غير موجود" });

            subscription.Status = CitizenSubscriptionStatus.Cancelled;
            subscription.CancelledAt = DateTime.UtcNow;
            subscription.CancelledById = GetCurrentUserId();
            subscription.CancellationReason = request.Reason;
            subscription.UpdatedAt = DateTime.UtcNow;

            await _context.SaveChangesAsync();

            return Ok(new { success = true, message = "تم إلغاء الاشتراك" });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error cancelling subscription");
            return StatusCode(500, new { success = false, message = "حدث خطأ في النظام" });
        }
    }

    #endregion

    #region Payments

    /// <summary>
    /// قائمة المدفوعات
    /// </summary>
    [HttpGet("payments")]
    public async Task<IActionResult> GetPayments(
        [FromQuery] PaymentStatus? status = null,
        [FromQuery] DateTime? fromDate = null,
        [FromQuery] DateTime? toDate = null,
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 20)
    {
        try
        {
            var companyId = await GetLinkedCompanyId();
            if (companyId == null)
                return Forbid("هذه الشركة غير مرتبطة بنظام المواطن");

            var query = _context.CitizenPayments
                .Include(p => p.Citizen)
                .Include(p => p.Subscription)
                .Where(p => p.CompanyId == companyId)
                .AsQueryable();

            if (status.HasValue)
                query = query.Where(p => p.Status == status.Value);

            if (fromDate.HasValue)
                query = query.Where(p => p.CreatedAt >= DateTime.SpecifyKind(fromDate.Value.AddHours(-3), DateTimeKind.Utc));

            if (toDate.HasValue)
                query = query.Where(p => p.CreatedAt <= DateTime.SpecifyKind(toDate.Value.AddHours(-3), DateTimeKind.Utc));

            var total = await query.CountAsync();

            var payments = await query
                .OrderByDescending(p => p.CreatedAt)
                .Skip((page - 1) * pageSize)
                .Take(pageSize)
                .Select(p => new
                {
                    p.Id,
                    p.TransactionNumber,
                    CitizenName = p.Citizen!.FullName,
                    CitizenPhone = p.Citizen.PhoneNumber,
                    SubscriptionNumber = p.Subscription != null ? p.Subscription.SubscriptionNumber : null,
                    p.Amount,
                    PaymentMethod = p.Method,
                    p.Status,
                    p.Notes,
                    p.CreatedAt
                })
                .ToListAsync();

            // إحصائيات سريعة
            var stats = new
            {
                totalAmount = await query.Where(p => p.Status == PaymentStatus.Success).SumAsync(p => p.Amount),
                pendingAmount = await query.Where(p => p.Status == PaymentStatus.Pending).SumAsync(p => p.Amount),
                count = total
            };

            return Ok(new
            {
                success = true,
                total,
                page,
                pageSize,
                stats,
                payments
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting payments");
            return StatusCode(500, new { success = false, message = "حدث خطأ في النظام" });
        }
    }

    /// <summary>
    /// تسجيل دفعة جديدة
    /// </summary>
    [HttpPost("payments")]
    public async Task<IActionResult> RecordPayment([FromBody] RecordPaymentRequest request)
    {
        try
        {
            var companyId = await GetLinkedCompanyId();
            if (companyId == null)
                return Forbid("هذه الشركة غير مرتبطة بنظام المواطن");

            // التحقق من المواطن
            var citizen = await _context.Citizens
                .FirstOrDefaultAsync(c => c.Id == request.CitizenId && c.CompanyId == companyId && !c.IsDeleted);

            if (citizen == null)
                return NotFound(new { success = false, message = "المواطن غير موجود" });

            var transactionNumber = $"PAY-{DateTime.UtcNow:yyyyMMddHHmmss}-{new Random().Next(1000, 9999)}";

            var payment = new CitizenPayment
            {
                TransactionNumber = transactionNumber,
                CitizenId = request.CitizenId,
                CitizenSubscriptionId = request.SubscriptionId,
                CompanyId = companyId.Value,
                Amount = request.Amount,
                Method = request.PaymentMethod,
                Status = PaymentStatus.Success,
                Notes = request.Notes,
                RecordedById = GetCurrentUserId(),
                CreatedAt = DateTime.UtcNow
            };

            await _context.CitizenPayments.AddAsync(payment);

            // تحديث مجموع المدفوعات للمواطن
            citizen.TotalPaid += request.Amount;

            // تحديث الاشتراك إن وجد
            if (request.SubscriptionId.HasValue)
            {
                var subscription = await _context.CitizenSubscriptions.FindAsync(request.SubscriptionId.Value);
                if (subscription != null)
                {
                    subscription.TotalPaid += request.Amount;
                    subscription.OutstandingBalance = Math.Max(0, subscription.AgreedPrice - subscription.TotalPaid);
                }
            }

            await _context.SaveChangesAsync();

            return Ok(new
            {
                success = true,
                message = "تم تسجيل الدفعة بنجاح",
                paymentId = payment.Id,
                transactionNumber
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error recording payment");
            return StatusCode(500, new { success = false, message = "حدث خطأ في النظام" });
        }
    }

    #endregion

    #region Internet Plans

    /// <summary>
    /// قائمة باقات الاشتراك
    /// </summary>
    [HttpGet("plans")]
    public async Task<IActionResult> GetPlans()
    {
        try
        {
            var companyId = await GetLinkedCompanyId();
            if (companyId == null)
                return Forbid("هذه الشركة غير مرتبطة بنظام المواطن");

            var plans = await _context.InternetPlans
                .Where(p => p.CompanyId == companyId)
                .OrderBy(p => p.SortOrder)
                .Select(p => new
                {
                    p.Id,
                    p.Name,
                    p.NameAr,
                    p.Description,
                    p.SpeedMbps,
                    p.MonthlyPrice,
                    p.YearlyPrice,
                    p.InstallationFee,
                    p.IsActive,
                    p.IsFeatured,
                    SubscribersCount = _context.CitizenSubscriptions.Count(s => s.InternetPlanId == p.Id && s.Status == CitizenSubscriptionStatus.Active)
                })
                .ToListAsync();

            return Ok(new { success = true, plans });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting plans");
            return StatusCode(500, new { success = false, message = "حدث خطأ في النظام" });
        }
    }

    /// <summary>
    /// إضافة باقة جديدة
    /// </summary>
    [HttpPost("plans")]
    public async Task<IActionResult> CreatePlan([FromBody] CreatePlanRequest request)
    {
        try
        {
            var companyId = await GetLinkedCompanyId();
            if (companyId == null)
                return Forbid("هذه الشركة غير مرتبطة بنظام المواطن");

            var plan = new InternetPlan
            {
                Name = request.Name,
                NameAr = request.NameAr,
                Description = request.Description,
                SpeedMbps = request.SpeedMbps,
                MonthlyPrice = request.MonthlyPrice,
                YearlyPrice = request.YearlyPrice ?? request.MonthlyPrice * 10, // سنوي = 10 أشهر
                InstallationFee = request.InstallationFee,
                CompanyId = companyId.Value,
                IsActive = true,
                SortOrder = request.DisplayOrder,
                CreatedAt = DateTime.UtcNow
            };

            await _context.InternetPlans.AddAsync(plan);
            await _context.SaveChangesAsync();

            return Ok(new
            {
                success = true,
                message = "تم إضافة الباقة بنجاح",
                planId = plan.Id
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error creating plan");
            return StatusCode(500, new { success = false, message = "حدث خطأ في النظام" });
        }
    }

    /// <summary>
    /// تحديث باقة
    /// </summary>
    [HttpPut("plans/{id:guid}")]
    public async Task<IActionResult> UpdatePlan(Guid id, [FromBody] UpdatePlanRequest request)
    {
        try
        {
            var companyId = await GetLinkedCompanyId();
            if (companyId == null)
                return Forbid("هذه الشركة غير مرتبطة بنظام المواطن");

            var plan = await _context.InternetPlans
                .FirstOrDefaultAsync(p => p.Id == id && p.CompanyId == companyId);

            if (plan == null)
                return NotFound(new { success = false, message = "الباقة غير موجودة" });

            plan.Name = request.Name ?? plan.Name;
            plan.NameAr = request.NameAr ?? plan.NameAr;
            plan.Description = request.Description ?? plan.Description;
            plan.SpeedMbps = request.SpeedMbps ?? plan.SpeedMbps;
            plan.MonthlyPrice = request.MonthlyPrice ?? plan.MonthlyPrice;
            plan.YearlyPrice = request.YearlyPrice ?? plan.YearlyPrice;
            plan.InstallationFee = request.InstallationFee ?? plan.InstallationFee;
            plan.IsActive = request.IsActive ?? plan.IsActive;
            plan.IsFeatured = request.IsFeatured ?? plan.IsFeatured;
            plan.UpdatedAt = DateTime.UtcNow;

            await _context.SaveChangesAsync();

            return Ok(new { success = true, message = "تم تحديث الباقة بنجاح" });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error updating plan");
            return StatusCode(500, new { success = false, message = "حدث خطأ في النظام" });
        }
    }

    #endregion

    #region Support Tickets

    /// <summary>
    /// قائمة تذاكر الدعم
    /// </summary>
    [HttpGet("tickets")]
    public async Task<IActionResult> GetTickets(
        [FromQuery] TicketStatus? status = null,
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 20)
    {
        try
        {
            var companyId = await GetLinkedCompanyId();
            if (companyId == null)
                return Forbid("هذه الشركة غير مرتبطة بنظام المواطن");

            var query = _context.SupportTickets
                .Include(t => t.Citizen)
                .Where(t => t.CompanyId == companyId)
                .AsQueryable();

            if (status.HasValue)
                query = query.Where(t => t.Status == status.Value);

            var total = await query.CountAsync();

            var tickets = await query
                .OrderByDescending(t => t.CreatedAt)
                .Skip((page - 1) * pageSize)
                .Take(pageSize)
                .Select(t => new
                {
                    t.Id,
                    t.TicketNumber,
                    CitizenName = t.Citizen!.FullName,
                    CitizenPhone = t.Citizen.PhoneNumber,
                    t.Subject,
                    t.Category,
                    t.Priority,
                    t.Status,
                    t.CreatedAt,
                    t.ResolvedAt,
                    MessagesCount = t.Messages.Count
                })
                .ToListAsync();

            return Ok(new
            {
                success = true,
                total,
                page,
                pageSize,
                tickets
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting tickets");
            return StatusCode(500, new { success = false, message = "حدث خطأ في النظام" });
        }
    }

    /// <summary>
    /// الرد على تذكرة
    /// </summary>
    [HttpPost("tickets/{id:guid}/reply")]
    public async Task<IActionResult> ReplyToTicket(Guid id, [FromBody] TicketReplyRequest request)
    {
        try
        {
            var companyId = await GetLinkedCompanyId();
            if (companyId == null)
                return Forbid("هذه الشركة غير مرتبطة بنظام المواطن");

            var ticket = await _context.SupportTickets
                .FirstOrDefaultAsync(t => t.Id == id && t.CompanyId == companyId);

            if (ticket == null)
                return NotFound(new { success = false, message = "التذكرة غير موجودة" });

            var message = new TicketMessage
            {
                TicketId = id,
                UserId = GetCurrentUserId(),
                CitizenId = null, // الرسالة من الموظف وليس المواطن
                Content = request.Message,
                CreatedAt = DateTime.UtcNow
            };

            await _context.TicketMessages.AddAsync(message);

            // تحديث حالة التذكرة
            if (ticket.Status == TicketStatus.Open)
                ticket.Status = TicketStatus.InProgress;

            ticket.UpdatedAt = DateTime.UtcNow;

            await _context.SaveChangesAsync();

            return Ok(new { success = true, message = "تم إرسال الرد بنجاح" });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error replying to ticket");
            return StatusCode(500, new { success = false, message = "حدث خطأ في النظام" });
        }
    }

    /// <summary>
    /// إغلاق تذكرة
    /// </summary>
    [HttpPost("tickets/{id:guid}/close")]
    public async Task<IActionResult> CloseTicket(Guid id, [FromBody] CloseTicketRequest request)
    {
        try
        {
            var companyId = await GetLinkedCompanyId();
            if (companyId == null)
                return Forbid("هذه الشركة غير مرتبطة بنظام المواطن");

            var ticket = await _context.SupportTickets
                .FirstOrDefaultAsync(t => t.Id == id && t.CompanyId == companyId);

            if (ticket == null)
                return NotFound(new { success = false, message = "التذكرة غير موجودة" });

            ticket.Status = TicketStatus.Resolved;
            ticket.ResolvedAt = DateTime.UtcNow;
            ticket.ResolutionNotes = request.ResolutionNotes;
            ticket.UpdatedAt = DateTime.UtcNow;

            await _context.SaveChangesAsync();

            return Ok(new { success = true, message = "تم إغلاق التذكرة" });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error closing ticket");
            return StatusCode(500, new { success = false, message = "حدث خطأ في النظام" });
        }
    }

    #endregion

    #region Helper Methods

    /// <summary>
    /// الحصول على ID الشركة المرتبطة بنظام المواطن
    /// </summary>
    private async Task<Guid?> GetLinkedCompanyId()
    {
        var userId = GetCurrentUserId();
        if (userId == null) return null;

        var user = await _context.Users
            .Include(u => u.Company)
            .FirstOrDefaultAsync(u => u.Id == userId);

        if (user == null || user.CompanyId == null)
        {
            // للسوبر أدمن، نرجع الشركة المرتبطة بنظام المواطن
            if (user?.Role == UserRole.SuperAdmin)
            {
                var linkedCompany = await _context.Companies
                    .Where(c => c.IsLinkedToCitizenPortal && !c.IsDeleted)
                    .Select(c => c.Id)
                    .FirstOrDefaultAsync();
                return linkedCompany != Guid.Empty ? linkedCompany : null;
            }
            return null;
        }

        // التحقق من أن الشركة مرتبطة بنظام المواطن
        if (user.Company?.IsLinkedToCitizenPortal != true)
            return null;

        return user.CompanyId;
    }

    private Guid? GetCurrentUserId()
    {
        var userIdClaim = User.FindFirst(ClaimTypes.NameIdentifier)?.Value;
        return Guid.TryParse(userIdClaim, out var userId) ? userId : null;
    }

    private static string GetStatusArabic(CitizenSubscriptionStatus status) => status switch
    {
        CitizenSubscriptionStatus.Active => "نشط",
        CitizenSubscriptionStatus.AwaitingInstallation => "بانتظار التركيب",
        CitizenSubscriptionStatus.Suspended => "موقف",
        CitizenSubscriptionStatus.Cancelled => "ملغي",
        CitizenSubscriptionStatus.Expired => "منتهي",
        CitizenSubscriptionStatus.Pending => "بانتظار الموافقة",
        _ => status.ToString()
    };

    #endregion
}

#region Request/Response Models

public class CreateCitizenRequest
{
    public required string FullName { get; set; }
    public required string PhoneNumber { get; set; }
    public string? Email { get; set; }
    public string? City { get; set; }
    public string? District { get; set; }
    public string? FullAddress { get; set; }
}

public class UpdateCitizenRequest
{
    public string? FullName { get; set; }
    public string? Email { get; set; }
    public string? City { get; set; }
    public string? District { get; set; }
    public string? FullAddress { get; set; }
    public bool? IsActive { get; set; }
}

public class CreateSubscriptionRequest
{
    public Guid CitizenId { get; set; }
    public Guid PlanId { get; set; }
    public string? InstallationAddress { get; set; }
    public decimal? CustomPrice { get; set; }
    public bool AutoRenew { get; set; } = true;
    public string? Notes { get; set; }
}

public class ActivateSubscriptionRequest
{
    public string? RouterSerialNumber { get; set; }
    public string? RouterModel { get; set; }
    public string? ONUSerialNumber { get; set; }
}

public class CancelSubscriptionRequest
{
    public string? Reason { get; set; }
}

public class RecordPaymentRequest
{
    public Guid CitizenId { get; set; }
    public Guid? SubscriptionId { get; set; }
    public decimal Amount { get; set; }
    public PaymentMethod PaymentMethod { get; set; }
    public string? Notes { get; set; }
}

public class CreatePlanRequest
{
    public required string Name { get; set; }
    public required string NameAr { get; set; }
    public string? Description { get; set; }
    public int SpeedMbps { get; set; }
    public decimal MonthlyPrice { get; set; }
    public decimal? YearlyPrice { get; set; }
    public decimal InstallationFee { get; set; }
    public int DisplayOrder { get; set; }
}

public class UpdatePlanRequest
{
    public string? Name { get; set; }
    public string? NameAr { get; set; }
    public string? Description { get; set; }
    public int? SpeedMbps { get; set; }
    public decimal? MonthlyPrice { get; set; }
    public decimal? YearlyPrice { get; set; }
    public decimal? InstallationFee { get; set; }
    public bool? IsActive { get; set; }
    public bool? IsFeatured { get; set; }
}

public class TicketReplyRequest
{
    public required string Message { get; set; }
}

public class CloseTicketRequest
{
    public string? ResolutionNotes { get; set; }
}

#endregion
