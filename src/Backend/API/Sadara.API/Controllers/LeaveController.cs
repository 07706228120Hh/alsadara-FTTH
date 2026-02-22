using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Sadara.Domain.Entities;
using Sadara.Domain.Interfaces;
using System.Security.Claims;

namespace Sadara.API.Controllers;

[ApiController]
[Route("api/[controller]")]
[Authorize(Policy = "Admin")]
public class LeaveController(IUnitOfWork unitOfWork, ILogger<LeaveController> logger) : ControllerBase
{
    private readonly IUnitOfWork _unitOfWork = unitOfWork;
    private readonly ILogger<LeaveController> _logger = logger;

    private Guid? GetAuthenticatedUserId()
    {
        var claim = User.FindFirst(ClaimTypes.NameIdentifier)?.Value
                 ?? User.FindFirst("sub")?.Value;
        return Guid.TryParse(claim, out var id) ? id : null;
    }

    // ============================================================
    //  طلبات الإجازة - CRUD
    // ============================================================

    /// <summary>تقديم طلب إجازة</summary>
    [HttpPost("requests")]
    public async Task<IActionResult> SubmitLeaveRequest([FromBody] SubmitLeaveRequest request)
    {
        var tokenUserId = GetAuthenticatedUserId();
        Guid userId = tokenUserId ?? request.UserId;

        var user = await _unitOfWork.Users.FirstOrDefaultAsync(u => u.Id == userId);
        if (user == null) return NotFound(new { message = "المستخدم غير موجود" });

        // حساب عدد الأيام
        var startDate = DateOnly.Parse(request.StartDate);
        var endDate = DateOnly.Parse(request.EndDate);
        if (endDate < startDate)
            return BadRequest(new { message = "تاريخ النهاية يجب أن يكون بعد تاريخ البداية" });

        var totalDays = endDate.DayNumber - startDate.DayNumber + 1;

        // التحقق من عدم وجود تداخل مع إجازة أخرى
        var overlap = await _unitOfWork.LeaveRequests.AnyAsync(lr =>
            lr.UserId == userId &&
            lr.Status != LeaveRequestStatus.Rejected &&
            lr.Status != LeaveRequestStatus.Cancelled &&
            lr.StartDate <= endDate && lr.EndDate >= startDate);

        if (overlap)
            return BadRequest(new { message = "يوجد تداخل مع إجازة أخرى في نفس الفترة" });

        // التحقق من الرصيد
        var leaveType = (LeaveType)request.LeaveType;
        if (leaveType != LeaveType.Unpaid && leaveType != LeaveType.Official)
        {
            var balance = await _unitOfWork.LeaveBalances.FirstOrDefaultAsync(b =>
                b.UserId == userId && b.Year == startDate.Year && b.LeaveType == leaveType);

            if (balance != null && balance.RemainingDays < totalDays)
            {
                return BadRequest(new
                {
                    message = $"رصيد الإجازات غير كافٍ. المتبقي: {balance.RemainingDays} أيام، المطلوب: {totalDays} أيام",
                    remainingDays = balance.RemainingDays,
                    requestedDays = totalDays
                });
            }
        }

        var leaveRequest = new LeaveRequest
        {
            UserId = userId,
            UserName = user.FullName,
            CompanyId = user.CompanyId,
            LeaveType = leaveType,
            StartDate = startDate,
            EndDate = endDate,
            TotalDays = totalDays,
            Reason = request.Reason,
            AttachmentUrl = request.AttachmentUrl,
            Status = LeaveRequestStatus.Pending,
        };

        await _unitOfWork.LeaveRequests.AddAsync(leaveRequest);
        await _unitOfWork.SaveChangesAsync();

        _logger.LogInformation("📋 طلب إجازة جديد: {UserName} من {Start} إلى {End} ({Type})",
            user.FullName, startDate, endDate, leaveType);

        return Ok(new { message = "تم تقديم طلب الإجازة بنجاح", leaveRequest });
    }

    /// <summary>جلب طلبات الإجازة (مع فلترة)</summary>
    [HttpGet("requests")]
    public async Task<IActionResult> GetLeaveRequests(
        [FromQuery] Guid? userId,
        [FromQuery] int? status,
        [FromQuery] Guid? companyId,
        [FromQuery] int? year,
        [FromQuery] int? month,
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 50)
    {
        var query = _unitOfWork.LeaveRequests.AsQueryable();

        if (userId.HasValue)
            query = query.Where(lr => lr.UserId == userId.Value);

        if (companyId.HasValue)
            query = query.Where(lr => lr.CompanyId == companyId.Value);

        if (status.HasValue)
            query = query.Where(lr => (int)lr.Status == status.Value);

        if (year.HasValue)
            query = query.Where(lr => lr.StartDate.Year == year.Value || lr.EndDate.Year == year.Value);

        if (month.HasValue)
            query = query.Where(lr => lr.StartDate.Month == month.Value || lr.EndDate.Month == month.Value);

        var total = await query.CountAsync();
        var requests = await query
            .OrderByDescending(lr => lr.CreatedAt)
            .Skip((page - 1) * pageSize)
            .Take(pageSize)
            .ToListAsync();

        return Ok(new
        {
            total,
            page,
            pageSize,
            requests = requests.Select(r => new
            {
                r.Id,
                r.UserId,
                r.UserName,
                r.CompanyId,
                leaveType = r.LeaveType.ToString(),
                leaveTypeValue = (int)r.LeaveType,
                startDate = r.StartDate.ToString("yyyy-MM-dd"),
                endDate = r.EndDate.ToString("yyyy-MM-dd"),
                r.TotalDays,
                r.Reason,
                status = r.Status.ToString(),
                statusValue = (int)r.Status,
                r.ReviewedByUserName,
                reviewedAt = r.ReviewedAt?.ToString("yyyy-MM-dd HH:mm"),
                r.ReviewNotes,
                r.AttachmentUrl,
                createdAt = r.CreatedAt.ToString("yyyy-MM-dd HH:mm"),
            })
        });
    }

    /// <summary>جلب طلب إجازة واحد</summary>
    [HttpGet("requests/{id}")]
    public async Task<IActionResult> GetLeaveRequest(long id)
    {
        var lr = await _unitOfWork.LeaveRequests.GetByIdAsync(id);
        if (lr == null) return NotFound(new { message = "طلب الإجازة غير موجود" });
        return Ok(lr);
    }

    /// <summary>إلغاء طلب إجازة (بواسطة الموظف)</summary>
    [HttpPost("requests/{id}/cancel")]
    public async Task<IActionResult> CancelLeaveRequest(long id)
    {
        var lr = await _unitOfWork.LeaveRequests.GetByIdAsync(id);
        if (lr == null) return NotFound(new { message = "طلب الإجازة غير موجود" });

        if (lr.Status != LeaveRequestStatus.Pending)
            return BadRequest(new { message = "لا يمكن إلغاء طلب تمت مراجعته مسبقاً" });

        lr.Status = LeaveRequestStatus.Cancelled;
        lr.UpdatedAt = DateTime.UtcNow;
        _unitOfWork.LeaveRequests.Update(lr);
        await _unitOfWork.SaveChangesAsync();

        return Ok(new { message = "تم إلغاء طلب الإجازة" });
    }

    // ============================================================
    //  سير عمل الموافقة (المدير)
    // ============================================================

    /// <summary>الموافقة على طلب إجازة</summary>
    [HttpPost("requests/{id}/approve")]
    public async Task<IActionResult> ApproveLeaveRequest(long id, [FromBody] ReviewLeaveDto? review = null)
    {
        var lr = await _unitOfWork.LeaveRequests.GetByIdAsync(id);
        if (lr == null) return NotFound(new { message = "طلب الإجازة غير موجود" });

        if (lr.Status != LeaveRequestStatus.Pending)
            return BadRequest(new { message = "تمت مراجعة هذا الطلب مسبقاً" });

        // تحديد المراجع
        var reviewerId = GetAuthenticatedUserId();
        var reviewer = reviewerId.HasValue
            ? await _unitOfWork.Users.FirstOrDefaultAsync(u => u.Id == reviewerId.Value)
            : null;

        lr.Status = LeaveRequestStatus.Approved;
        lr.ReviewedByUserId = reviewerId;
        lr.ReviewedByUserName = reviewer?.FullName ?? "مدير";
        lr.ReviewedAt = DateTime.UtcNow;
        lr.ReviewNotes = review?.Notes;
        lr.UpdatedAt = DateTime.UtcNow;

        // خصم من رصيد الإجازات
        if (lr.LeaveType != LeaveType.Unpaid && lr.LeaveType != LeaveType.Official)
        {
            var balance = await _unitOfWork.LeaveBalances.FirstOrDefaultAsync(b =>
                b.UserId == lr.UserId && b.Year == lr.StartDate.Year && b.LeaveType == lr.LeaveType);

            if (balance != null)
            {
                balance.UsedDays += lr.TotalDays;
                balance.UpdatedAt = DateTime.UtcNow;
                _unitOfWork.LeaveBalances.Update(balance);
            }
        }

        _unitOfWork.LeaveRequests.Update(lr);
        await _unitOfWork.SaveChangesAsync();

        _logger.LogInformation("✅ تمت الموافقة على إجازة {UserName} ({Start} - {End}) بواسطة {Reviewer}",
            lr.UserName, lr.StartDate, lr.EndDate, lr.ReviewedByUserName);

        return Ok(new { message = "تمت الموافقة على طلب الإجازة", leaveRequest = lr });
    }

    /// <summary>رفض طلب إجازة</summary>
    [HttpPost("requests/{id}/reject")]
    public async Task<IActionResult> RejectLeaveRequest(long id, [FromBody] ReviewLeaveDto? review = null)
    {
        var lr = await _unitOfWork.LeaveRequests.GetByIdAsync(id);
        if (lr == null) return NotFound(new { message = "طلب الإجازة غير موجود" });

        if (lr.Status != LeaveRequestStatus.Pending)
            return BadRequest(new { message = "تمت مراجعة هذا الطلب مسبقاً" });

        var reviewerId = GetAuthenticatedUserId();
        var reviewer = reviewerId.HasValue
            ? await _unitOfWork.Users.FirstOrDefaultAsync(u => u.Id == reviewerId.Value)
            : null;

        lr.Status = LeaveRequestStatus.Rejected;
        lr.ReviewedByUserId = reviewerId;
        lr.ReviewedByUserName = reviewer?.FullName ?? "مدير";
        lr.ReviewedAt = DateTime.UtcNow;
        lr.ReviewNotes = review?.Notes;
        lr.UpdatedAt = DateTime.UtcNow;

        _unitOfWork.LeaveRequests.Update(lr);
        await _unitOfWork.SaveChangesAsync();

        _logger.LogInformation("❌ تم رفض إجازة {UserName} ({Start} - {End}) بواسطة {Reviewer}. السبب: {Notes}",
            lr.UserName, lr.StartDate, lr.EndDate, lr.ReviewedByUserName, review?.Notes);

        return Ok(new { message = "تم رفض طلب الإجازة", leaveRequest = lr });
    }

    // ============================================================
    //  رصيد الإجازات
    // ============================================================

    /// <summary>جلب رصيد إجازات موظف</summary>
    [HttpGet("balances/{userId}")]
    public async Task<IActionResult> GetLeaveBalances(Guid userId, [FromQuery] int? year)
    {
        var targetYear = year ?? DateTime.UtcNow.Year;
        var balances = await _unitOfWork.LeaveBalances.AsQueryable()
            .Where(b => b.UserId == userId && b.Year == targetYear)
            .ToListAsync();

        return Ok(new
        {
            userId,
            year = targetYear,
            balances = balances.Select(b => new
            {
                b.Id,
                leaveType = b.LeaveType.ToString(),
                leaveTypeValue = (int)b.LeaveType,
                b.TotalAllowance,
                b.UsedDays,
                remainingDays = b.RemainingDays,
            })
        });
    }

    /// <summary>تعيين أو تحديث رصيد إجازات</summary>
    [HttpPost("balances")]
    public async Task<IActionResult> SetLeaveBalance([FromBody] SetLeaveBalanceRequest request)
    {
        var existing = await _unitOfWork.LeaveBalances.FirstOrDefaultAsync(b =>
            b.UserId == request.UserId &&
            b.Year == request.Year &&
            b.LeaveType == (LeaveType)request.LeaveType);

        if (existing != null)
        {
            existing.TotalAllowance = request.TotalAllowance;
            existing.UpdatedAt = DateTime.UtcNow;
            _unitOfWork.LeaveBalances.Update(existing);
        }
        else
        {
            var user = await _unitOfWork.Users.FirstOrDefaultAsync(u => u.Id == request.UserId);
            var balance = new LeaveBalance
            {
                UserId = request.UserId,
                CompanyId = user?.CompanyId,
                Year = request.Year,
                LeaveType = (LeaveType)request.LeaveType,
                TotalAllowance = request.TotalAllowance,
                UsedDays = 0,
            };
            await _unitOfWork.LeaveBalances.AddAsync(balance);
        }

        await _unitOfWork.SaveChangesAsync();
        return Ok(new { message = "تم تحديث رصيد الإجازات" });
    }

    /// <summary>تعيين رصيد إجازات لجميع موظفي الشركة (دفعة واحدة)</summary>
    [HttpPost("balances/bulk")]
    public async Task<IActionResult> BulkSetLeaveBalances([FromBody] BulkSetBalanceRequest request)
    {
        var companyUsers = await _unitOfWork.Users.AsQueryable()
            .Where(u => u.CompanyId == request.CompanyId && u.IsActive)
            .ToListAsync();

        var targetYear = request.Year ?? DateTime.UtcNow.Year;
        var leaveType = (LeaveType)request.LeaveType;
        int created = 0, updated = 0;

        foreach (var user in companyUsers)
        {
            var existing = await _unitOfWork.LeaveBalances.FirstOrDefaultAsync(b =>
                b.UserId == user.Id && b.Year == targetYear && b.LeaveType == leaveType);

            if (existing != null)
            {
                existing.TotalAllowance = request.TotalAllowance;
                existing.UpdatedAt = DateTime.UtcNow;
                _unitOfWork.LeaveBalances.Update(existing);
                updated++;
            }
            else
            {
                await _unitOfWork.LeaveBalances.AddAsync(new LeaveBalance
                {
                    UserId = user.Id,
                    CompanyId = request.CompanyId,
                    Year = targetYear,
                    LeaveType = leaveType,
                    TotalAllowance = request.TotalAllowance,
                    UsedDays = 0,
                });
                created++;
            }
        }

        await _unitOfWork.SaveChangesAsync();

        _logger.LogInformation("📊 رصيد {Type} لسنة {Year}: أُنشئ {Created}، حُدّث {Updated} لشركة {CompanyId}",
            leaveType, targetYear, created, updated, request.CompanyId);

        return Ok(new { message = $"تم تحديث رصيد {companyUsers.Count} موظف", created, updated });
    }

    /// <summary>ملخص إحصائيات الإجازات (للوحة التحكم)</summary>
    [HttpGet("summary")]
    public async Task<IActionResult> GetLeaveSummary([FromQuery] Guid? companyId, [FromQuery] int? year)
    {
        var targetYear = year ?? DateTime.UtcNow.Year;
        var query = _unitOfWork.LeaveRequests.AsQueryable()
            .Where(lr => lr.StartDate.Year == targetYear || lr.EndDate.Year == targetYear);

        if (companyId.HasValue)
            query = query.Where(lr => lr.CompanyId == companyId.Value);

        var requests = await query.ToListAsync();

        return Ok(new
        {
            year = targetYear,
            totalRequests = requests.Count,
            pending = requests.Count(r => r.Status == LeaveRequestStatus.Pending),
            approved = requests.Count(r => r.Status == LeaveRequestStatus.Approved),
            rejected = requests.Count(r => r.Status == LeaveRequestStatus.Rejected),
            cancelled = requests.Count(r => r.Status == LeaveRequestStatus.Cancelled),
            totalApprovedDays = requests.Where(r => r.Status == LeaveRequestStatus.Approved).Sum(r => r.TotalDays),
            byType = Enum.GetValues<LeaveType>().Select(t => new
            {
                type = t.ToString(),
                typeValue = (int)t,
                count = requests.Count(r => r.LeaveType == t && r.Status == LeaveRequestStatus.Approved),
                totalDays = requests.Where(r => r.LeaveType == t && r.Status == LeaveRequestStatus.Approved).Sum(r => r.TotalDays),
            }).Where(x => x.count > 0)
        });
    }
}

// DTOs
public record SubmitLeaveRequest(
    Guid UserId,
    int LeaveType,
    string StartDate,
    string EndDate,
    string? Reason,
    string? AttachmentUrl);

public record ReviewLeaveDto(string? Notes);

public record SetLeaveBalanceRequest(
    Guid UserId,
    int Year,
    int LeaveType,
    int TotalAllowance);

public record BulkSetBalanceRequest(
    Guid CompanyId,
    int? Year,
    int LeaveType,
    int TotalAllowance);
