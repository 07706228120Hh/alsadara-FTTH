using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Sadara.Domain.Entities;
using Sadara.Domain.Enums;
using Sadara.Domain.Interfaces;

namespace Sadara.API.Controllers;

/// <summary>
/// معاملات الفنيين المالية
/// </summary>
[ApiController]
[Route("api/[controller]")]
[Authorize]
public class TechnicianTransactionsController(IUnitOfWork unitOfWork, ILogger<TechnicianTransactionsController> logger) : ControllerBase
{
    private readonly IUnitOfWork _unitOfWork = unitOfWork;
    private readonly ILogger<TechnicianTransactionsController> _logger = logger;

    /// <summary>
    /// جلب معاملات الفني الحالي (my-transactions)
    /// </summary>
    [HttpGet("my-transactions")]
    [Authorize(Policy = "TechnicianOrAbove")]
    public async Task<IActionResult> GetMyTransactions(
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 50,
        [FromQuery] DateTime? from = null,
        [FromQuery] DateTime? to = null)
    {
        try
        {
            var userId = GetCurrentUserId();
            if (userId == Guid.Empty)
                return Unauthorized(new { success = false, message = "غير مصادق" });

            var user = await _unitOfWork.Users.GetByIdAsync(userId);
            if (user == null)
                return NotFound(new { success = false, message = "المستخدم غير موجود" });

            var query = _unitOfWork.TechnicianTransactions.AsQueryable()
                .Where(t => t.TechnicianId == userId);

            if (from.HasValue)
            {
                var fromUtc = DateTime.SpecifyKind(from.Value, DateTimeKind.Utc);
                query = query.Where(t => t.CreatedAt >= fromUtc);
            }
            if (to.HasValue)
            {
                var toUtc = DateTime.SpecifyKind(to.Value.AddDays(1), DateTimeKind.Utc);
                query = query.Where(t => t.CreatedAt < toUtc);
            }

            var total = await query.CountAsync();
            var transactions = await query
                .OrderByDescending(t => t.CreatedAt)
                .Skip((page - 1) * pageSize)
                .Take(pageSize)
                .ToListAsync();

            // جلب بيانات طلبات الخدمة المرتبطة بالمعاملات
            var srIds = transactions
                .Where(t => t.ServiceRequestId.HasValue)
                .Select(t => t.ServiceRequestId!.Value)
                .Distinct()
                .ToList();

            var srDict = new Dictionary<Guid, Domain.Entities.ServiceRequest>();
            if (srIds.Any())
            {
                var srs = await _unitOfWork.ServiceRequests.AsQueryable()
                    .Where(sr => srIds.Contains(sr.Id))
                    .ToListAsync();
                foreach (var sr in srs) srDict[sr.Id] = sr;
            }

            // جلب أرقام القيود المحاسبية المرتبطة
            var jeIds = transactions
                .Where(t => t.JournalEntryId.HasValue)
                .Select(t => t.JournalEntryId!.Value)
                .Distinct()
                .ToList();
            var jeDict = new Dictionary<Guid, string>();
            if (jeIds.Any())
            {
                var jes = await _unitOfWork.JournalEntries.AsQueryable()
                    .Where(j => jeIds.Contains(j.Id))
                    .Select(j => new { j.Id, j.EntryNumber })
                    .ToListAsync();
                foreach (var j in jes) jeDict[j.Id] = j.EntryNumber;
            }

            // حساب الإجماليات
            var allTechTxQuery = _unitOfWork.TechnicianTransactions.AsQueryable()
                .Where(t => t.TechnicianId == userId);

            var totalCharges = await allTechTxQuery
                .Where(t => t.Type == TechnicianTransactionType.Charge)
                .SumAsync(t => (decimal?)t.Amount) ?? 0;

            var totalPayments = await allTechTxQuery
                .Where(t => t.Type == TechnicianTransactionType.Payment)
                .SumAsync(t => (decimal?)t.Amount) ?? 0;

            return Ok(new
            {
                transactions = transactions.Select(tx =>
                {
                    // استخراج تفاصيل المهمة
                    string? customerName = null;
                    string? taskType = null;
                    string? area = null;
                    string? address = null;
                    string? contactPhone = null;
                    string? city = null;
                    decimal? finalCost = null;

                    if (tx.ServiceRequestId.HasValue && srDict.TryGetValue(tx.ServiceRequestId.Value, out var sr))
                    {
                        area = sr.Area;
                        address = sr.Address;
                        contactPhone = sr.ContactPhone;
                        city = sr.City;
                        finalCost = sr.FinalCost ?? sr.EstimatedCost;

                        if (!string.IsNullOrEmpty(sr.Details))
                        {
                            try
                            {
                                var details = System.Text.Json.JsonSerializer.Deserialize<Dictionary<string, object>>(
                                    sr.Details,
                                    new System.Text.Json.JsonSerializerOptions { PropertyNameCaseInsensitive = true });
                                if (details != null)
                                {
                                    customerName = details.TryGetValue("customerName", out var cn) ? cn?.ToString() : null;
                                    if (customerName == null)
                                        customerName = details.TryGetValue("subscriberName", out var sn) ? sn?.ToString() : null;
                                    taskType = details.TryGetValue("taskType", out var tt) ? tt?.ToString() : null;
                                }
                            }
                            catch { }
                        }
                    }

                    return new
                    {
                        id = tx.Id,
                        type = tx.Type.ToString(),
                        typeValue = (int)tx.Type,
                        category = tx.Category.ToString(),
                        categoryValue = (int)tx.Category,
                        amount = tx.Amount,
                        balanceAfter = tx.BalanceAfter,
                        description = tx.Description,
                        referenceNumber = tx.ReferenceNumber,
                        serviceRequestId = tx.ServiceRequestId,
                        journalEntryId = tx.JournalEntryId,
                        journalEntryNumber = tx.JournalEntryId.HasValue && jeDict.ContainsKey(tx.JournalEntryId.Value)
                            ? jeDict[tx.JournalEntryId.Value] : null,
                        notes = tx.Notes,
                        receivedBy = tx.ReceivedBy,
                        createdAt = tx.CreatedAt,
                        customerName,
                        taskType,
                        area,
                        address,
                        contactPhone,
                        city,
                        finalCost
                    };
                }),
                total,
                page,
                pageSize,
                totalPages = (int)Math.Ceiling((double)total / pageSize),
                summary = new
                {
                    totalCharges,
                    totalPayments,
                    netBalance = user.TechNetBalance,
                    technicianName = user.FullName
                }
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في جلب معاملات الفني");
            return StatusCode(500, new { success = false, message = "خطأ داخلي في الخادم" });
        }
    }

    /// <summary>
    /// جلب معاملات فني محدد (للإدارة)
    /// </summary>
    [HttpGet("by-technician/{technicianId:guid}")]
    [Authorize(Policy = "CompanyAdminOrAbove")]
    public async Task<IActionResult> GetByTechnician(
        Guid technicianId,
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 50,
        [FromQuery] DateTime? from = null,
        [FromQuery] DateTime? to = null)
    {
        try
        {
            var technician = await _unitOfWork.Users.GetByIdAsync(technicianId);
            if (technician == null)
                return NotFound(new { success = false, message = "الفني غير موجود" });

            var query = _unitOfWork.TechnicianTransactions.AsQueryable()
                .Where(t => t.TechnicianId == technicianId);

            if (from.HasValue)
            {
                var fromUtc = DateTime.SpecifyKind(from.Value, DateTimeKind.Utc);
                query = query.Where(t => t.CreatedAt >= fromUtc);
            }
            if (to.HasValue)
            {
                var toUtc = DateTime.SpecifyKind(to.Value.AddDays(1), DateTimeKind.Utc);
                query = query.Where(t => t.CreatedAt < toUtc);
            }

            var total = await query.CountAsync();
            var transactions = await query
                .OrderByDescending(t => t.CreatedAt)
                .Skip((page - 1) * pageSize)
                .Take(pageSize)
                .ToListAsync();

            // جلب بيانات طلبات الخدمة المرتبطة
            var srIds = transactions
                .Where(t => t.ServiceRequestId.HasValue)
                .Select(t => t.ServiceRequestId!.Value)
                .Distinct()
                .ToList();

            var srDict = new Dictionary<Guid, Domain.Entities.ServiceRequest>();
            if (srIds.Any())
            {
                var srs = await _unitOfWork.ServiceRequests.AsQueryable()
                    .Where(sr => srIds.Contains(sr.Id))
                    .ToListAsync();
                foreach (var sr in srs) srDict[sr.Id] = sr;
            }

            // جلب أرقام القيود المحاسبية المرتبطة
            var jeIds2 = transactions
                .Where(t => t.JournalEntryId.HasValue)
                .Select(t => t.JournalEntryId!.Value)
                .Distinct()
                .ToList();
            var jeDict = new Dictionary<Guid, string>();
            if (jeIds2.Any())
            {
                var jes = await _unitOfWork.JournalEntries.AsQueryable()
                    .Where(j => jeIds2.Contains(j.Id))
                    .Select(j => new { j.Id, j.EntryNumber })
                    .ToListAsync();
                foreach (var j in jes) jeDict[j.Id] = j.EntryNumber;
            }

            var allTechTxQuery = _unitOfWork.TechnicianTransactions.AsQueryable()
                .Where(t => t.TechnicianId == technicianId);

            var totalCharges = await allTechTxQuery
                .Where(t => t.Type == TechnicianTransactionType.Charge)
                .SumAsync(t => (decimal?)t.Amount) ?? 0;

            var totalPayments = await allTechTxQuery
                .Where(t => t.Type == TechnicianTransactionType.Payment)
                .SumAsync(t => (decimal?)t.Amount) ?? 0;

            return Ok(new
            {
                transactions = transactions.Select(tx =>
                {
                    string? customerName = null;
                    string? taskType = null;
                    string? area = null;
                    string? address = null;
                    string? contactPhone = null;
                    string? city = null;
                    decimal? finalCost = null;

                    if (tx.ServiceRequestId.HasValue && srDict.TryGetValue(tx.ServiceRequestId.Value, out var sr))
                    {
                        area = sr.Area;
                        address = sr.Address;
                        contactPhone = sr.ContactPhone;
                        city = sr.City;
                        finalCost = sr.FinalCost ?? sr.EstimatedCost;

                        if (!string.IsNullOrEmpty(sr.Details))
                        {
                            try
                            {
                                var details = System.Text.Json.JsonSerializer.Deserialize<Dictionary<string, object>>(
                                    sr.Details,
                                    new System.Text.Json.JsonSerializerOptions { PropertyNameCaseInsensitive = true });
                                if (details != null)
                                {
                                    customerName = details.TryGetValue("customerName", out var cn) ? cn?.ToString() : null;
                                    if (customerName == null)
                                        customerName = details.TryGetValue("subscriberName", out var sn) ? sn?.ToString() : null;
                                    taskType = details.TryGetValue("taskType", out var tt) ? tt?.ToString() : null;
                                }
                            }
                            catch { }
                        }
                    }

                    return new
                    {
                        id = tx.Id,
                        type = tx.Type.ToString(),
                        typeValue = (int)tx.Type,
                        category = tx.Category.ToString(),
                        categoryValue = (int)tx.Category,
                        amount = tx.Amount,
                        balanceAfter = tx.BalanceAfter,
                        description = tx.Description,
                        referenceNumber = tx.ReferenceNumber,
                        serviceRequestId = tx.ServiceRequestId,
                        journalEntryId = tx.JournalEntryId,
                        journalEntryNumber = tx.JournalEntryId.HasValue && jeDict.ContainsKey(tx.JournalEntryId.Value)
                            ? jeDict[tx.JournalEntryId.Value] : null,
                        notes = tx.Notes,
                        receivedBy = tx.ReceivedBy,
                        createdAt = tx.CreatedAt,
                        customerName,
                        taskType,
                        area,
                        address,
                        contactPhone,
                        city,
                        finalCost
                    };
                }),
                total,
                page,
                pageSize,
                totalPages = (int)Math.Ceiling((double)total / pageSize),
                summary = new
                {
                    totalCharges,
                    totalPayments,
                    netBalance = technician.TechNetBalance,
                    technicianName = technician.FullName
                }
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في جلب معاملات الفني {TechnicianId}", technicianId);
            return StatusCode(500, new { success = false, message = "خطأ داخلي في الخادم" });
        }
    }

    /// <summary>
    /// ملخص مستحقات جميع الفنيين (للإدارة - يظهر في شاشة تحصيلات الفنيين)
    /// </summary>
    [HttpGet("all-dues")]
    [Authorize(Policy = "CompanyAdminOrAbove")]
    public async Task<IActionResult> GetAllTechnicianDues()
    {
        try
        {
            // تحديد شركة المستخدم الحالي لفلترة البيانات
            var currentUserId = GetCurrentUserId();
            var currentUser = await _unitOfWork.Users.GetByIdAsync(currentUserId);
            var userCompanyId = currentUser?.CompanyId;

            // جلب جميع الفنيين الذين لديهم معاملات أو رصيد — مع فلتر الشركة
            var technicians = await _unitOfWork.Users.AsQueryable()
                .Where(u => (u.TechTotalCharges > 0 || u.TechTotalPayments > 0 || u.TechNetBalance != 0)
                    && (userCompanyId == null || u.CompanyId == userCompanyId))
                .Select(u => new
                {
                    u.Id,
                    u.FullName,
                    u.PhoneNumber,
                    u.TechTotalCharges,
                    u.TechTotalPayments,
                    u.TechNetBalance
                })
                .OrderBy(u => u.TechNetBalance) // الأكثر مديونية أولاً
                .ToListAsync();

            // جلب آخر معاملة لكل فني
            var techIds = technicians.Select(t => t.Id).ToList();
            var lastTxDict = new Dictionary<Guid, (DateTime LastDate, int TransactionCount)>();
            
            if (techIds.Any())
            {
                var lastTransactions = await _unitOfWork.TechnicianTransactions.AsQueryable()
                    .Where(t => techIds.Contains(t.TechnicianId))
                    .GroupBy(t => t.TechnicianId)
                    .Select(g => new
                    {
                        TechnicianId = g.Key,
                        LastDate = g.Max(t => t.CreatedAt),
                        TransactionCount = g.Count()
                    })
                    .ToListAsync();
                    
                foreach (var lt in lastTransactions)
                {
                    lastTxDict[lt.TechnicianId] = (lt.LastDate, lt.TransactionCount);
                }
            }

            var totalAllCharges = technicians.Sum(t => t.TechTotalCharges);
            var totalAllPayments = technicians.Sum(t => t.TechTotalPayments);
            var totalNetBalance = technicians.Sum(t => t.TechNetBalance);

            return Ok(new
            {
                technicians = technicians.Select(t =>
                {
                    var hasTx = lastTxDict.TryGetValue(t.Id, out var txInfo);
                    return new
                    {
                        id = t.Id,
                        name = t.FullName,
                        phone = t.PhoneNumber,
                        totalCharges = t.TechTotalCharges,
                        totalPayments = t.TechTotalPayments,
                        netBalance = t.TechNetBalance,
                        transactionCount = hasTx ? txInfo!.TransactionCount : 0,
                        lastTransactionDate = hasTx ? txInfo!.LastDate : (DateTime?)null
                    };
                }),
                summary = new
                {
                    technicianCount = technicians.Count,
                    totalCharges = totalAllCharges,
                    totalPayments = totalAllPayments,
                    totalNetBalance = totalNetBalance,
                    debtorCount = technicians.Count(t => t.TechNetBalance < 0)
                }
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في جلب ملخص مستحقات الفنيين");
            return StatusCode(500, new { success = false, message = "خطأ داخلي في الخادم" });
        }
    }

    /// <summary>
    /// تسجيل تسديد من فني (للإدارة)
    /// </summary>
    [HttpPost("record-payment")]
    [Authorize(Policy = "CompanyAdminOrAbove")]
    public async Task<IActionResult> RecordPayment([FromBody] TechPaymentRequest request)
    {
        try
        {
            if (request.Amount <= 0)
                return BadRequest(new { success = false, message = "المبلغ يجب أن يكون أكبر من صفر" });

            var technician = await _unitOfWork.Users.GetByIdAsync(request.TechnicianId);
            if (technician == null)
                return NotFound(new { success = false, message = "الفني غير موجود" });

            technician.TechTotalPayments += request.Amount;
            technician.TechNetBalance = technician.TechTotalPayments - technician.TechTotalCharges;
            _unitOfWork.Users.Update(technician);

            var tx = new TechnicianTransaction
            {
                TechnicianId = technician.Id,
                Type = TechnicianTransactionType.Payment,
                Category = TechnicianTransactionCategory.CashPayment,
                Amount = request.Amount,
                BalanceAfter = technician.TechNetBalance,
                Description = request.Description ?? "تسديد نقدي",
                ReferenceNumber = $"{DateTime.UtcNow:yyMMddHHmm}{Random.Shared.Next(1000, 9999)}",
                Notes = request.Notes,
                CreatedById = GetCurrentUserId(),
                CompanyId = technician.CompanyId ?? Guid.Empty,
                CreatedAt = DateTime.UtcNow
            };
            await _unitOfWork.TechnicianTransactions.AddAsync(tx);

            // === إنشاء قيد محاسبي تلقائي ===
            var companyId = technician.CompanyId ?? Guid.Empty;
            if (companyId != Guid.Empty)
            {
                try
                {
                    var cashAcct = await ServiceRequestAccountingHelper.FindAccountByCode(
                        _unitOfWork, "1110", companyId);
                    var techSubAcct = await ServiceRequestAccountingHelper.FindOrCreateSubAccount(
                        _unitOfWork, "1140", technician.Id, technician.FullName ?? "فني", companyId);

                    if (cashAcct != null)
                    {
                        await _unitOfWork.SaveChangesAsync();

                        // مدين: ذمة الفني (تخفيض) — دائن: النقدية (خروج كاش)
                        var journalLines = new List<(Guid AccountId, decimal DebitAmount, decimal CreditAmount, string? LineDescription)>
                        {
                            (techSubAcct.Id, request.Amount, 0, $"تسديد ذمة فني {technician.FullName}"),
                            (cashAcct.Id, 0, request.Amount, $"صرف نقدي للفني {technician.FullName}")
                        };
                        await ServiceRequestAccountingHelper.CreateAndPostJournalEntry(
                            _unitOfWork, companyId, GetCurrentUserId(),
                            $"تسديد فني {technician.FullName} - {request.Amount:N0} دينار",
                            JournalReferenceType.TechnicianCollection, technician.Id.ToString(),
                            journalLines);

                        // ربط القيد بالمعاملة
                        var je = await _unitOfWork.JournalEntries.AsQueryable()
                            .Where(j => j.ReferenceId == technician.Id.ToString()
                                && j.CompanyId == companyId)
                            .OrderByDescending(j => j.CreatedAt)
                            .FirstOrDefaultAsync();
                        if (je != null)
                        {
                            tx.JournalEntryId = je.Id;
                            _unitOfWork.TechnicianTransactions.Update(tx);
                        }
                    }
                }
                catch (Exception ex)
                {
                    _logger.LogWarning(ex, "فشل إنشاء القيد المحاسبي لتسديد الفني {TechName}", technician.FullName);
                }
            }

            await _unitOfWork.SaveChangesAsync();

            _logger.LogInformation("تم تسجيل تسديد {Amount} من الفني {TechName}", request.Amount, technician.FullName);

            return Ok(new
            {
                success = true,
                message = $"تم تسجيل تسديد {request.Amount} د.ع من {technician.FullName}",
                newBalance = technician.TechNetBalance
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في تسجيل تسديد الفني");
            return StatusCode(500, new { success = false, message = "خطأ داخلي في الخادم" });
        }
    }

    /// <summary>
    /// تعديل معاملة فني
    /// </summary>
    [HttpPut("{id}")]
    [Authorize(Policy = "CompanyAdminOrAbove")]
    public async Task<IActionResult> UpdateTransaction(long id, [FromBody] UpdateTechTransactionRequest request)
    {
        try
        {
            var tx = await _unitOfWork.TechnicianTransactions.AsQueryable()
                .FirstOrDefaultAsync(t => t.Id == id);
            if (tx == null)
                return NotFound(new { success = false, message = "المعاملة غير موجودة" });

            var technician = await _unitOfWork.Users.GetByIdAsync(tx.TechnicianId);
            if (technician == null)
                return NotFound(new { success = false, message = "الفني غير موجود" });

            // عكس تأثير المعاملة القديمة
            if (tx.Type == TechnicianTransactionType.Charge)
                technician.TechTotalCharges -= tx.Amount;
            else if (tx.Type == TechnicianTransactionType.Payment)
                technician.TechTotalPayments -= tx.Amount;

            // تحديث حقول المعاملة
            if (request.Amount.HasValue) tx.Amount = request.Amount.Value;
            if (request.Description != null) tx.Description = request.Description;
            if (request.Notes != null) tx.Notes = request.Notes;
            if (request.ReceivedBy != null) tx.ReceivedBy = request.ReceivedBy;
            if (request.ReferenceNumber != null) tx.ReferenceNumber = request.ReferenceNumber;
            if (request.Type.HasValue) tx.Type = (TechnicianTransactionType)request.Type.Value;
            if (request.Category.HasValue) tx.Category = (TechnicianTransactionCategory)request.Category.Value;
            tx.UpdatedAt = DateTime.UtcNow;

            // إعادة حساب الرصيد بالقيم الجديدة
            if (tx.Type == TechnicianTransactionType.Charge)
                technician.TechTotalCharges += tx.Amount;
            else if (tx.Type == TechnicianTransactionType.Payment)
                technician.TechTotalPayments += tx.Amount;
            technician.TechNetBalance = technician.TechTotalPayments - technician.TechTotalCharges;
            tx.BalanceAfter = technician.TechNetBalance;

            _unitOfWork.TechnicianTransactions.Update(tx);
            _unitOfWork.Users.Update(technician);
            await _unitOfWork.SaveChangesAsync();

            _logger.LogInformation("تم تعديل المعاملة {TxId} للفني {TechName}", id, technician.FullName);

            return Ok(new { success = true, message = "تم تعديل المعاملة بنجاح" });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في تعديل المعاملة {TxId}", id);
            return StatusCode(500, new { success = false, message = "خطأ داخلي في الخادم" });
        }
    }

    /// <summary>
    /// حذف معاملة فني (حذف ناعم)
    /// </summary>
    [HttpDelete("{id}")]
    [Authorize(Policy = "CompanyAdminOrAbove")]
    public async Task<IActionResult> DeleteTransaction(long id)
    {
        try
        {
            var tx = await _unitOfWork.TechnicianTransactions.AsQueryable()
                .FirstOrDefaultAsync(t => t.Id == id);
            if (tx == null)
                return NotFound(new { success = false, message = "المعاملة غير موجودة" });

            var technician = await _unitOfWork.Users.GetByIdAsync(tx.TechnicianId);
            if (technician == null)
                return NotFound(new { success = false, message = "الفني غير موجود" });

            // عكس تأثير المعاملة على الرصيد
            if (tx.Type == TechnicianTransactionType.Charge)
            {
                technician.TechTotalCharges -= tx.Amount;
            }
            else if (tx.Type == TechnicianTransactionType.Payment)
            {
                technician.TechTotalPayments -= tx.Amount;
            }
            technician.TechNetBalance = technician.TechTotalPayments - technician.TechTotalCharges;
            _unitOfWork.Users.Update(technician);

            // حذف ناعم
            tx.IsDeleted = true;
            tx.DeletedAt = DateTime.UtcNow;
            _unitOfWork.TechnicianTransactions.Update(tx);
            await _unitOfWork.SaveChangesAsync();

            _logger.LogInformation("تم حذف المعاملة {TxId} ({Amount} د.ع) للفني {TechName}", 
                id, tx.Amount, technician.FullName);

            return Ok(new { success = true, message = "تم حذف المعاملة بنجاح" });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في حذف المعاملة {TxId}", id);
            return StatusCode(500, new { success = false, message = "خطأ داخلي في الخادم" });
        }
    }

    private Guid GetCurrentUserId()
    {
        var claim = User.FindFirst("sub") ?? User.FindFirst(System.Security.Claims.ClaimTypes.NameIdentifier);
        return claim != null ? Guid.Parse(claim.Value) : Guid.Empty;
    }
}

public class UpdateTechTransactionRequest
{
    public decimal? Amount { get; set; }
    public string? Description { get; set; }
    public string? Notes { get; set; }
    public string? ReceivedBy { get; set; }
    public int? Type { get; set; }
    public int? Category { get; set; }
    public string? ReferenceNumber { get; set; }
}

public class TechPaymentRequest
{
    public Guid TechnicianId { get; set; }
    public decimal Amount { get; set; }
    public string? Description { get; set; }
    public string? Notes { get; set; }
}
