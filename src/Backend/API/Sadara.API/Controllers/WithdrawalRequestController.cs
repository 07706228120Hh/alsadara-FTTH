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
public class WithdrawalRequestController(IUnitOfWork unitOfWork, ILogger<WithdrawalRequestController> logger) : ControllerBase
{
    private readonly IUnitOfWork _unitOfWork = unitOfWork;
    private readonly ILogger<WithdrawalRequestController> _logger = logger;

    private Guid? GetAuthenticatedUserId()
    {
        var claim = User.FindFirst(ClaimTypes.NameIdentifier)?.Value
                 ?? User.FindFirst("sub")?.Value;
        return Guid.TryParse(claim, out var id) ? id : null;
    }

    // ============================================================
    //  تقديم طلب سحب أموال
    // ============================================================

    /// <summary>تقديم طلب سحب أموال</summary>
    [HttpPost("requests")]
    public async Task<IActionResult> SubmitWithdrawalRequest([FromBody] SubmitWithdrawalDto request)
    {
        var tokenUserId = GetAuthenticatedUserId();
        Guid userId = tokenUserId ?? request.UserId;

        var user = await _unitOfWork.Users.FirstOrDefaultAsync(u => u.Id == userId);
        if (user == null) return NotFound(new { message = "المستخدم غير موجود" });

        if (request.Amount <= 0)
            return BadRequest(new { message = "المبلغ يجب أن يكون أكبر من صفر" });

        var withdrawalRequest = new WithdrawalRequest
        {
            UserId = userId,
            UserName = user.FullName,
            CompanyId = user.CompanyId,
            Amount = request.Amount,
            Reason = request.Reason,
            Notes = request.Notes,
            Status = WithdrawalRequestStatus.Pending,
        };

        await _unitOfWork.WithdrawalRequests.AddAsync(withdrawalRequest);
        await _unitOfWork.SaveChangesAsync();

        _logger.LogInformation("💰 طلب سحب أموال جديد: {UserName} - {Amount} د.ع",
            user.FullName, request.Amount);

        return Ok(new { message = "تم تقديم طلب سحب الأموال بنجاح", withdrawalRequest });
    }

    // ============================================================
    //  جلب الطلبات
    // ============================================================

    /// <summary>جلب طلبات سحب الأموال (مع فلترة)</summary>
    [HttpGet("requests")]
    public async Task<IActionResult> GetWithdrawalRequests(
        [FromQuery] string? userId = null,
        [FromQuery] int? status = null,
        [FromQuery] string? companyId = null,
        [FromQuery] int? year = null,
        [FromQuery] int? month = null,
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 50)
    {
        var query = _unitOfWork.WithdrawalRequests.AsQueryable();

        // فلترة حسب المستخدم
        if (!string.IsNullOrEmpty(userId) && Guid.TryParse(userId, out var uid))
            query = query.Where(r => r.UserId == uid);

        // فلترة حسب الشركة
        if (!string.IsNullOrEmpty(companyId) && Guid.TryParse(companyId, out var cid))
            query = query.Where(r => r.CompanyId == cid);

        // فلترة حسب الحالة
        if (status.HasValue)
            query = query.Where(r => r.Status == (WithdrawalRequestStatus)status.Value);

        // فلترة حسب السنة والشهر
        if (year.HasValue)
            query = query.Where(r => r.CreatedAt.Year == year.Value);
        if (month.HasValue)
            query = query.Where(r => r.CreatedAt.Month == month.Value);

        var total = await query.CountAsync();

        var requests = await query.OrderByDescending(r => r.CreatedAt)
            .Skip((page - 1) * pageSize)
            .Take(pageSize)
            .Select(r => new
            {
                r.Id,
                r.UserId,
                r.UserName,
                r.CompanyId,
                r.Amount,
                r.Reason,
                r.Notes,
                Status = (int)r.Status,
                StatusName = r.Status.ToString(),
                r.ReviewedByUserId,
                r.ReviewedByUserName,
                r.ReviewedAt,
                r.ReviewNotes,
                r.CreatedAt,
            })
            .ToListAsync();

        return Ok(new
        {
            requests,
            total,
            page,
            pageSize,
            totalPages = (int)Math.Ceiling((double)total / pageSize),
        });
    }

    // ============================================================
    //  طلبات الموظف الحالية
    // ============================================================

    /// <summary>جلب طلبات سحب الأموال للموظف الحالي</summary>
    [HttpGet("my-requests")]
    public async Task<IActionResult> GetMyWithdrawalRequests(
        [FromQuery] int? status = null,
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 20)
    {
        var tokenUserId = GetAuthenticatedUserId();
        if (tokenUserId == null)
            return Unauthorized(new { message = "غير مصرح" });

        var query = _unitOfWork.WithdrawalRequests.AsQueryable()
            .Where(r => r.UserId == tokenUserId.Value);

        if (status.HasValue)
            query = query.Where(r => r.Status == (WithdrawalRequestStatus)status.Value);

        var total = await query.CountAsync();

        var requests = await query.OrderByDescending(r => r.CreatedAt)
            .Skip((page - 1) * pageSize)
            .Take(pageSize)
            .Select(r => new
            {
                r.Id,
                r.UserId,
                r.UserName,
                r.Amount,
                r.Reason,
                r.Notes,
                Status = (int)r.Status,
                StatusName = r.Status.ToString(),
                r.ReviewedByUserName,
                r.ReviewedAt,
                r.ReviewNotes,
                r.CreatedAt,
            })
            .ToListAsync();

        return Ok(new
        {
            requests,
            total,
            page,
            pageSize,
            totalPages = (int)Math.Ceiling((double)total / pageSize),
        });
    }

    // ============================================================
    //  الموافقة والرفض
    // ============================================================

    /// <summary>الموافقة على طلب سحب أموال (موافقة فقط بدون صرف)</summary>
    [HttpPost("requests/{id}/approve")]
    public async Task<IActionResult> ApproveWithdrawalRequest(long id, [FromBody] ReviewWithdrawalDto? review = null)
    {
        var req = await _unitOfWork.WithdrawalRequests.FirstOrDefaultAsync(r => r.Id == id);
        if (req == null) return NotFound(new { message = "الطلب غير موجود" });

        if (req.Status != WithdrawalRequestStatus.Pending)
            return BadRequest(new { message = "لا يمكن تغيير حالة طلب غير معلق" });

        var reviewer = GetAuthenticatedUserId();
        var reviewerUser = reviewer.HasValue
            ? await _unitOfWork.Users.FirstOrDefaultAsync(u => u.Id == reviewer.Value)
            : null;

        req.Status = WithdrawalRequestStatus.Approved;
        req.ReviewedByUserId = reviewer;
        req.ReviewedByUserName = reviewerUser?.FullName;
        req.ReviewedAt = DateTime.UtcNow;
        req.ReviewNotes = review?.Notes;
        req.UpdatedAt = DateTime.UtcNow;

        _unitOfWork.WithdrawalRequests.Update(req);
        await _unitOfWork.SaveChangesAsync();

        _logger.LogInformation("✅ تمت الموافقة على طلب سحب أموال #{Id} - {Amount} د.ع للموظف {UserName}",
            id, req.Amount, req.UserName);

        return Ok(new { message = "تمت الموافقة على الطلب", request = req });
    }

    /// <summary>صرف طلب سحب أموال (موافقة + صرف + إنشاء قيد على الموظف)</summary>
    [HttpPost("requests/{id}/pay")]
    public async Task<IActionResult> PayWithdrawalRequest(long id, [FromBody] ReviewWithdrawalDto? review = null)
    {
        try
        {
            var req = await _unitOfWork.WithdrawalRequests.FirstOrDefaultAsync(r => r.Id == id);
            if (req == null) return NotFound(new { message = "الطلب غير موجود" });

            if (req.Status != WithdrawalRequestStatus.Pending && req.Status != WithdrawalRequestStatus.Approved)
                return BadRequest(new { message = "لا يمكن صرف طلب في هذه الحالة" });

            var reviewer = GetAuthenticatedUserId();
            var reviewerUser = reviewer.HasValue
                ? await _unitOfWork.Users.FirstOrDefaultAsync(u => u.Id == reviewer.Value)
                : null;

            // جلب بيانات الموظف
            var employee = await _unitOfWork.Users.FirstOrDefaultAsync(u => u.Id == req.UserId);
            if (employee == null) return NotFound(new { message = "الموظف غير موجود" });

            // 1. تحديث حالة الطلب إلى مصروف
            req.Status = WithdrawalRequestStatus.Paid;
            req.ReviewedByUserId = reviewer;
            req.ReviewedByUserName = reviewerUser?.FullName;
            req.ReviewedAt = DateTime.UtcNow;
            req.ReviewNotes = review?.Notes;
            req.UpdatedAt = DateTime.UtcNow;
            _unitOfWork.WithdrawalRequests.Update(req);

            // 2. إنشاء قيد حسابي (Charge) على الموظف - سحب من أجور الراتب
            employee.TechTotalCharges += req.Amount;
            employee.TechNetBalance = employee.TechTotalPayments - employee.TechTotalCharges;
            _unitOfWork.Users.Update(employee);

            var tx = new TechnicianTransaction
            {
                TechnicianId = employee.Id,
                Type = TechnicianTransactionType.Charge,
                Category = TechnicianTransactionCategory.Other,
                Amount = req.Amount,
                BalanceAfter = employee.TechNetBalance,
                Description = $"سحب أموال - {req.Reason ?? "طلب سحب"}",
                ReferenceNumber = $"WD-{req.Id}-{DateTime.UtcNow:yyMMddHHmm}",
                Notes = req.Notes,
                CreatedById = reviewer,
                CompanyId = req.CompanyId ?? employee.CompanyId ?? Guid.Empty,
                CreatedAt = DateTime.UtcNow
            };
            await _unitOfWork.TechnicianTransactions.AddAsync(tx);

            // 3. إنشاء خصم على الراتب (التزام) حتى يظهر في كشف الراتب
            var now = DateTime.UtcNow;
            var deduction = new EmployeeDeductionBonus
            {
                UserId = employee.Id,
                CompanyId = req.CompanyId ?? employee.CompanyId ?? Guid.Empty,
                Type = AdjustmentType.Deduction,
                Category = "سلفة",
                Amount = req.Amount,
                Month = now.Month,
                Year = now.Year,
                Description = $"سحب أموال - {req.Reason ?? "طلب سحب"} (طلب #{req.Id})",
                Notes = review?.Notes,
                IsApplied = false,
                CreatedById = reviewer ?? Guid.Empty,
                IsRecurring = false,
                IsActive = true,
                CreatedAt = now
            };
            await _unitOfWork.EmployeeDeductionBonuses.AddAsync(deduction);

            await _unitOfWork.SaveChangesAsync();

            _logger.LogInformation(
                "💸 تم صرف طلب سحب أموال #{Id} - {Amount} د.ع للموظف {UserName}. قيد Charge تم إنشاؤه. الرصيد الجديد: {Balance}",
                id, req.Amount, req.UserName, employee.TechNetBalance);

            return Ok(new
            {
                message = $"تم صرف {req.Amount} د.ع للموظف {req.UserName} وإنشاء قيد محاسبي",
                request = new { req.Id, req.Amount, req.UserName, Status = req.Status.ToString() },
                transaction = new { tx.Id, tx.Amount, tx.BalanceAfter, tx.Description },
                newBalance = employee.TechNetBalance
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في صرف طلب سحب أموال #{Id}", id);
            return StatusCode(500, new { message = "خطأ داخلي في الخادم" });
        }
    }

    /// <summary>رفض طلب سحب أموال</summary>
    [HttpPost("requests/{id}/reject")]
    public async Task<IActionResult> RejectWithdrawalRequest(long id, [FromBody] ReviewWithdrawalDto? review = null)
    {
        var req = await _unitOfWork.WithdrawalRequests.FirstOrDefaultAsync(r => r.Id == id);
        if (req == null) return NotFound(new { message = "الطلب غير موجود" });

        if (req.Status != WithdrawalRequestStatus.Pending)
            return BadRequest(new { message = "لا يمكن تغيير حالة طلب غير معلق" });

        var reviewer = GetAuthenticatedUserId();
        var reviewerUser = reviewer.HasValue
            ? await _unitOfWork.Users.FirstOrDefaultAsync(u => u.Id == reviewer.Value)
            : null;

        req.Status = WithdrawalRequestStatus.Rejected;
        req.ReviewedByUserId = reviewer;
        req.ReviewedByUserName = reviewerUser?.FullName;
        req.ReviewedAt = DateTime.UtcNow;
        req.ReviewNotes = review?.Notes;
        req.UpdatedAt = DateTime.UtcNow;

        _unitOfWork.WithdrawalRequests.Update(req);
        await _unitOfWork.SaveChangesAsync();

        _logger.LogInformation("❌ تم رفض طلب سحب أموال #{Id} للموظف {UserName}", id, req.UserName);

        return Ok(new { message = "تم رفض الطلب", request = req });
    }

    /// <summary>إلغاء طلب سحب أموال (من قبل الموظف)</summary>
    [HttpPost("requests/{id}/cancel")]
    public async Task<IActionResult> CancelWithdrawalRequest(long id)
    {
        var req = await _unitOfWork.WithdrawalRequests.FirstOrDefaultAsync(r => r.Id == id);
        if (req == null) return NotFound(new { message = "الطلب غير موجود" });

        // التحقق من أن المعلقة فقط يمكن إلغاؤها
        if (req.Status != WithdrawalRequestStatus.Pending)
            return BadRequest(new { message = "لا يمكن إلغاء طلب غير معلق" });

        // التحقق من أن الموظف نفسه هو من يلغي
        var tokenUserId = GetAuthenticatedUserId();
        if (tokenUserId.HasValue && req.UserId != tokenUserId.Value)
        {
            // السماح للمدير بالإلغاء أيضاً
        }

        req.Status = WithdrawalRequestStatus.Cancelled;
        req.UpdatedAt = DateTime.UtcNow;

        _unitOfWork.WithdrawalRequests.Update(req);
        await _unitOfWork.SaveChangesAsync();

        return Ok(new { message = "تم إلغاء الطلب" });
    }
}

// DTOs
public record SubmitWithdrawalDto(
    Guid UserId,
    decimal Amount,
    string? Reason,
    string? Notes);

public record ReviewWithdrawalDto(string? Notes);
