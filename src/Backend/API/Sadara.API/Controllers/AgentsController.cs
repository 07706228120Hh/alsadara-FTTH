using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Microsoft.IdentityModel.Tokens;
using Sadara.Domain.Entities;
using Sadara.Domain.Enums;
using Sadara.Domain.Interfaces;
using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace Sadara.API.Controllers;

/// <summary>
/// إدارة الوكلاء - CRUD + المحاسبة + تسجيل الدخول
/// الوكيل يدخل بوابة المواطن ويجري عمليات
/// تظهر في شاشة الشركة + مدير النظام
/// </summary>
[ApiController]
[Route("api/[controller]")]
[Tags("Agents")]
public class AgentsController : ControllerBase
{
    private readonly IUnitOfWork _unitOfWork;
    private readonly IConfiguration _configuration;
    private readonly ILogger<AgentsController> _logger;

    public AgentsController(
        IUnitOfWork unitOfWork,
        IConfiguration configuration,
        ILogger<AgentsController> logger)
    {
        _unitOfWork = unitOfWork;
        _configuration = configuration;
        _logger = logger;
    }

    // ==================== مصادقة الوكيل ====================

    /// <summary>
    /// تسجيل دخول الوكيل (يدخل بوابة المواطن)
    /// </summary>
    [HttpPost("login")]
    [AllowAnonymous]
    public async Task<IActionResult> Login([FromBody] AgentLoginRequest request)
    {
        try
        {
            if (string.IsNullOrWhiteSpace(request.Password))
                return BadRequest(new { success = false, message = "كلمة المرور مطلوبة", messageAr = "كلمة المرور مطلوبة" });

            if (string.IsNullOrWhiteSpace(request.PhoneNumber) && string.IsNullOrWhiteSpace(request.AgentCode))
                return BadRequest(new { success = false, message = "رقم الهاتف أو كود الوكيل مطلوب", messageAr = "رقم الهاتف أو كود الوكيل مطلوب" });

            // البحث بكود الوكيل أو رقم الهاتف أو الاسم
            Agent? agent = null;
            if (!string.IsNullOrWhiteSpace(request.AgentCode))
            {
                agent = await _unitOfWork.Agents.FirstOrDefaultAsync(a => a.AgentCode == request.AgentCode);
                // محاولة البحث بالاسم أو رقم الهاتف إذا لم يُعثر عليه بالكود
                agent ??= await _unitOfWork.Agents.FirstOrDefaultAsync(a => a.Name == request.AgentCode);
                agent ??= await _unitOfWork.Agents.FirstOrDefaultAsync(a => a.PhoneNumber == request.AgentCode);
            }
            else if (!string.IsNullOrWhiteSpace(request.PhoneNumber))
            {
                agent = await _unitOfWork.Agents.FirstOrDefaultAsync(a => a.PhoneNumber == request.PhoneNumber);
                agent ??= await _unitOfWork.Agents.FirstOrDefaultAsync(a => a.AgentCode == request.PhoneNumber);
            }

            if (agent == null)
                return Unauthorized(new { success = false, message = "بيانات الدخول غير صحيحة", messageAr = "بيانات الدخول غير صحيحة" });

            // تحميل الشركة بشكل منفصل
            if (agent.CompanyId != Guid.Empty)
                agent.Company = await _unitOfWork.Companies.FirstOrDefaultAsync(c => c.Id == agent.CompanyId);

            if (agent.Status != AgentStatus.Active)
                return Unauthorized(new { success = false, message = "حساب الوكيل معلق أو محظور", messageAr = "حساب الوكيل معلق أو محظور" });

            // التحقق من كلمة المرور
            if (!VerifyPassword(request.Password, agent.PasswordHash))
                return Unauthorized(new { success = false, message = "بيانات الدخول غير صحيحة", messageAr = "بيانات الدخول غير صحيحة" });

            // تحديث آخر تسجيل دخول
            agent.LastLoginAt = DateTime.UtcNow;
            _unitOfWork.Agents.Update(agent);
            await _unitOfWork.SaveChangesAsync();

            // إنشاء JWT token
            var token = GenerateAgentToken(agent);

            _logger.LogInformation("Agent {AgentCode} ({Name}) logged in successfully", agent.AgentCode, agent.Name);

            return Ok(new
            {
                success = true,
                message = "تم تسجيل الدخول بنجاح",
                data = new
                {
                    token,
                    agent = MapAgentToDto(agent)
                }
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error during agent login");
            return StatusCode(500, new { success = false, message = "حدث خطأ أثناء تسجيل الدخول" });
        }
    }

    // ==================== إدارة الوكلاء (CRUD) ====================

    /// <summary>
    /// جلب جميع الوكلاء (للشركة أو مدير النظام)
    /// </summary>
    [HttpGet]
    [Authorize(Policy = "CompanyAdminOrAbove")]
    public async Task<IActionResult> GetAll([FromQuery] Guid? companyId, [FromQuery] AgentStatus? status)
    {
        try
        {
            IQueryable<Agent> query = _unitOfWork.Agents.AsQueryable();

            if (companyId.HasValue)
                query = query.Where(a => a.CompanyId == companyId.Value);

            if (status.HasValue)
                query = query.Where(a => a.Status == status.Value);

            var agents = await query.OrderByDescending(a => a.CreatedAt).ToListAsync();

            // تحميل بيانات الشركات بشكل منفصل لتجنب مشاكل Include مع InMemory
            var companyIds = agents.Select(a => a.CompanyId).Where(id => id != Guid.Empty).Distinct().ToList();
            var companies = companyIds.Any()
                ? await _unitOfWork.Companies.AsQueryable().Where(c => companyIds.Contains(c.Id)).ToDictionaryAsync(c => c.Id)
                : new Dictionary<Guid, Company>();

            foreach (var agent in agents)
            {
                if (companies.TryGetValue(agent.CompanyId, out var company))
                    agent.Company = company;
            }

            // === مزامنة أرصدة الوكلاء من جدول المعاملات (المصدر الموحّد) ===
            var agentIds = agents.Select(a => a.Id).ToList();
            if (agentIds.Any())
            {
                var balances = await _unitOfWork.AgentTransactions.AsQueryable()
                    .Where(t => agentIds.Contains(t.AgentId) && !t.IsDeleted)
                    .GroupBy(t => t.AgentId)
                    .Select(g => new
                    {
                        AgentId = g.Key,
                        Charges = g.Where(t => t.Type == TransactionType.Charge).Sum(t => (decimal?)t.Amount) ?? 0,
                        Payments = g.Where(t => t.Type == TransactionType.Payment).Sum(t => (decimal?)t.Amount) ?? 0,
                    })
                    .ToListAsync();

                var balanceDict = balances.ToDictionary(b => b.AgentId);
                bool needsSave = false;

                foreach (var agent in agents)
                {
                    if (balanceDict.TryGetValue(agent.Id, out var bal))
                    {
                        if (agent.TotalCharges != bal.Charges || agent.TotalPayments != bal.Payments)
                        {
                            agent.TotalCharges = bal.Charges;
                            agent.TotalPayments = bal.Payments;
                            agent.NetBalance = bal.Payments - bal.Charges;
                            _unitOfWork.Agents.Update(agent);
                            needsSave = true;
                        }
                    }
                }
                if (needsSave) await _unitOfWork.SaveChangesAsync();
            }

            return Ok(new
            {
                success = true,
                data = agents.Select(MapAgentToDto),
                total = agents.Count
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting agents");
            return StatusCode(500, new { success = false, message = "حدث خطأ أثناء جلب الوكلاء" });
        }
    }

    /// <summary>
    /// جلب وكيل بالمعرف
    /// </summary>
    [HttpGet("{id:guid}")]
    [Authorize(Policy = "CompanyAdminOrAbove")]
    public async Task<IActionResult> GetById(Guid id)
    {
        try
        {
            var agent = await _unitOfWork.Agents.FirstOrDefaultAsync(a => a.Id == id);

            if (agent == null)
                return NotFound(new { success = false, message = "الوكيل غير موجود" });

            // تحميل الشركة بشكل منفصل
            if (agent.CompanyId != Guid.Empty)
                agent.Company = await _unitOfWork.Companies.FirstOrDefaultAsync(c => c.Id == agent.CompanyId);

            return Ok(new { success = true, data = MapAgentToDto(agent) });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting agent {Id}", id);
            return StatusCode(500, new { success = false, message = "حدث خطأ" });
        }
    }

    /// <summary>
    /// إنشاء وكيل جديد
    /// </summary>
    [HttpPost]
    [Authorize(Policy = "CompanyAdminOrAbove")]
    public async Task<IActionResult> Create([FromBody] CreateAgentRequest request)
    {
        try
        {
            // التحقق من البيانات
            if (string.IsNullOrWhiteSpace(request.Name) || string.IsNullOrWhiteSpace(request.PhoneNumber) || string.IsNullOrWhiteSpace(request.Password))
                return BadRequest(new { success = false, message = "الاسم ورقم الهاتف وكلمة المرور مطلوبان" });

            // التحقق من عدم تكرار رقم الهاتف
            var existingAgent = await _unitOfWork.Agents.FirstOrDefaultAsync(a => a.PhoneNumber == request.PhoneNumber);
            if (existingAgent != null)
                return BadRequest(new { success = false, message = "رقم الهاتف مستخدم بالفعل" });

            // توليد كود الوكيل
            var agentCode = await GenerateAgentCode();

            var agent = new Agent
            {
                Id = Guid.NewGuid(),
                AgentCode = agentCode,
                Name = request.Name,
                Type = request.Type,
                PhoneNumber = request.PhoneNumber,
                PasswordHash = HashPassword(request.Password),
                PlainPassword = request.Password,
                Email = request.Email,
                City = request.City,
                Area = request.Area,
                FullAddress = request.FullAddress,
                Latitude = request.Latitude,
                Longitude = request.Longitude,
                PageId = request.PageId,
                CompanyId = request.CompanyId,
                Status = AgentStatus.Active,
                Notes = request.Notes,
                TotalCharges = 0,
                TotalPayments = 0,
                NetBalance = 0
            };

            await _unitOfWork.Agents.AddAsync(agent);
            await _unitOfWork.SaveChangesAsync();

            _logger.LogInformation("Agent created: {AgentCode} - {Name} for company {CompanyId}", agent.AgentCode, agent.Name, agent.CompanyId);

            return CreatedAtAction(nameof(GetById), new { id = agent.Id }, new
            {
                success = true,
                message = "تم إنشاء الوكيل بنجاح",
                data = MapAgentToDto(agent)
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error creating agent");
            return StatusCode(500, new { success = false, message = "حدث خطأ أثناء إنشاء الوكيل" });
        }
    }

    /// <summary>
    /// تعديل بيانات وكيل
    /// </summary>
    [HttpPut("{id:guid}")]
    [Authorize(Policy = "CompanyAdminOrAbove")]
    public async Task<IActionResult> Update(Guid id, [FromBody] UpdateAgentRequest request)
    {
        try
        {
            var agent = await _unitOfWork.Agents.GetByIdAsync(id);
            if (agent == null)
                return NotFound(new { success = false, message = "الوكيل غير موجود" });

            // تحديث الحقول المرسلة فقط
            if (!string.IsNullOrWhiteSpace(request.Name)) agent.Name = request.Name;
            if (request.Type.HasValue) agent.Type = request.Type.Value;
            if (!string.IsNullOrWhiteSpace(request.Email)) agent.Email = request.Email;
            if (!string.IsNullOrWhiteSpace(request.City)) agent.City = request.City;
            if (!string.IsNullOrWhiteSpace(request.Area)) agent.Area = request.Area;
            if (!string.IsNullOrWhiteSpace(request.FullAddress)) agent.FullAddress = request.FullAddress;
            if (request.Latitude.HasValue) agent.Latitude = request.Latitude;
            if (request.Longitude.HasValue) agent.Longitude = request.Longitude;
            if (!string.IsNullOrWhiteSpace(request.PageId)) agent.PageId = request.PageId;
            if (request.Status.HasValue) agent.Status = request.Status.Value;
            if (request.Notes != null) agent.Notes = request.Notes;
            if (!string.IsNullOrWhiteSpace(request.ProfileImageUrl)) agent.ProfileImageUrl = request.ProfileImageUrl;

            // تغيير كلمة المرور
            if (!string.IsNullOrWhiteSpace(request.NewPassword))
            {
                agent.PasswordHash = HashPassword(request.NewPassword);
                agent.PlainPassword = request.NewPassword;
            }

            // تغيير رقم الهاتف (مع التحقق من عدم التكرار)
            if (!string.IsNullOrWhiteSpace(request.PhoneNumber) && request.PhoneNumber != agent.PhoneNumber)
            {
                var exists = await _unitOfWork.Agents.AnyAsync(a => a.PhoneNumber == request.PhoneNumber && a.Id != id);
                if (exists)
                    return BadRequest(new { success = false, message = "رقم الهاتف مستخدم بالفعل" });
                agent.PhoneNumber = request.PhoneNumber;
            }

            agent.UpdatedAt = DateTime.UtcNow;
            _unitOfWork.Agents.Update(agent);
            await _unitOfWork.SaveChangesAsync();

            _logger.LogInformation("Agent updated: {AgentCode}", agent.AgentCode);

            return Ok(new { success = true, message = "تم تعديل الوكيل بنجاح", data = MapAgentToDto(agent) });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error updating agent {Id}", id);
            return StatusCode(500, new { success = false, message = "حدث خطأ أثناء تعديل الوكيل" });
        }
    }

    /// <summary>
    /// حذف وكيل (حذف ناعم)
    /// </summary>
    [HttpDelete("{id:guid}")]
    [Authorize(Policy = "SuperAdmin")]
    public async Task<IActionResult> Delete(Guid id)
    {
        try
        {
            var agent = await _unitOfWork.Agents.GetByIdAsync(id);
            if (agent == null)
                return NotFound(new { success = false, message = "الوكيل غير موجود" });

            agent.IsDeleted = true;
            agent.DeletedAt = DateTime.UtcNow;
            agent.Status = AgentStatus.Inactive;
            _unitOfWork.Agents.Update(agent);
            await _unitOfWork.SaveChangesAsync();

            _logger.LogInformation("Agent deleted (soft): {AgentCode}", agent.AgentCode);

            return Ok(new { success = true, message = "تم حذف الوكيل بنجاح" });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error deleting agent {Id}", id);
            return StatusCode(500, new { success = false, message = "حدث خطأ أثناء حذف الوكيل" });
        }
    }

    // ==================== المحاسبة (أجور + تسديد + صافي) ====================

    /// <summary>
    /// جلب جميع معاملات الوكلاء لشركة معينة
    /// </summary>
    [HttpGet("transactions/all")]
    [Authorize(Policy = "CompanyAdminOrAbove")]
    public async Task<IActionResult> GetAllTransactions(
        [FromQuery] string? companyId,
        [FromQuery] TransactionType? type,
        [FromQuery] DateTime? from,
        [FromQuery] DateTime? to,
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 50)
    {
        try
        {
            // جلب وكلاء الشركة
            var agentsQuery = _unitOfWork.Agents.AsQueryable();
            if (!string.IsNullOrEmpty(companyId) && Guid.TryParse(companyId, out var cId))
                agentsQuery = agentsQuery.Where(a => a.CompanyId == cId);

            var agentIds = await agentsQuery.Select(a => a.Id).ToListAsync();
            var agentNames = await agentsQuery.ToDictionaryAsync(a => a.Id, a => new { a.Name, a.AgentCode });

            var query = _unitOfWork.AgentTransactions.AsQueryable()
                .Where(t => agentIds.Contains(t.AgentId));

            if (type.HasValue)
                query = query.Where(t => t.Type == type.Value);
            if (from.HasValue)
            {
                var fromUtc = DateTime.SpecifyKind(from.Value.AddHours(-3), DateTimeKind.Utc);
                query = query.Where(t => t.CreatedAt >= fromUtc);
            }
            if (to.HasValue)
            {
                var toUtc = DateTime.SpecifyKind(to.Value.AddHours(-3), DateTimeKind.Utc);
                query = query.Where(t => t.CreatedAt <= toUtc);
            }

            var total = await query.CountAsync();
            var transactions = await query
                .OrderByDescending(t => t.CreatedAt)
                .Skip((page - 1) * pageSize)
                .Take(pageSize)
                .ToListAsync();

            // حساب الإجماليات
            var totalCharges = await _unitOfWork.AgentTransactions.AsQueryable()
                .Where(t => agentIds.Contains(t.AgentId) && t.Type == TransactionType.Charge)
                .SumAsync(t => t.Amount);
            var totalPayments = await _unitOfWork.AgentTransactions.AsQueryable()
                .Where(t => agentIds.Contains(t.AgentId) && t.Type == TransactionType.Payment)
                .SumAsync(t => t.Amount);

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

            return Ok(new
            {
                success = true,
                data = transactions.Select(tx => new
                {
                    id = tx.Id,
                    agentId = tx.AgentId,
                    agentName = agentNames.ContainsKey(tx.AgentId) ? agentNames[tx.AgentId].Name : "",
                    agentCode = agentNames.ContainsKey(tx.AgentId) ? agentNames[tx.AgentId].AgentCode : "",
                    type = tx.Type.ToString(),
                    typeValue = (int)tx.Type,
                    category = tx.Category.ToString(),
                    categoryValue = (int)tx.Category,
                    amount = tx.Amount,
                    balanceAfter = tx.BalanceAfter,
                    description = tx.Description,
                    referenceNumber = tx.ReferenceNumber,
                    serviceRequestId = tx.ServiceRequestId,
                    citizenId = tx.CitizenId,
                    createdById = tx.CreatedById,
                    journalEntryId = tx.JournalEntryId,
                    journalEntryNumber = tx.JournalEntryId.HasValue && jeDict.ContainsKey(tx.JournalEntryId.Value)
                        ? jeDict[tx.JournalEntryId.Value] : null,
                    notes = tx.Notes,
                    createdAt = tx.CreatedAt
                }),
                total,
                page,
                pageSize,
                totalPages = (int)Math.Ceiling((double)total / pageSize),
                summary = new
                {
                    totalCharges,
                    totalPayments,
                    netBalance = totalPayments - totalCharges,
                    agentCount = agentIds.Count
                }
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting all agent transactions");
            return StatusCode(500, new { success = false, message = "حدث خطأ أثناء جلب المعاملات" });
        }
    }

    /// <summary>
    /// جلب معاملات وكيل معين
    /// </summary>
    [HttpGet("{id:guid}/transactions")]
    [Authorize(Policy = "CompanyAdminOrAbove")]
    public async Task<IActionResult> GetTransactions(
        Guid id,
        [FromQuery] TransactionType? type,
        [FromQuery] DateTime? from,
        [FromQuery] DateTime? to,
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 20)
    {
        try
        {
            var agent = await _unitOfWork.Agents.GetByIdAsync(id);
            if (agent == null)
                return NotFound(new { success = false, message = "الوكيل غير موجود" });

            var query = _unitOfWork.AgentTransactions.AsQueryable()
                .Where(t => t.AgentId == id);

            if (type.HasValue)
                query = query.Where(t => t.Type == type.Value);

            if (from.HasValue)
            {
                var fromUtc = DateTime.SpecifyKind(from.Value.AddHours(-3), DateTimeKind.Utc);
                query = query.Where(t => t.CreatedAt >= fromUtc);
            }

            if (to.HasValue)
            {
                var toUtc = DateTime.SpecifyKind(to.Value.AddHours(-3), DateTimeKind.Utc);
                query = query.Where(t => t.CreatedAt <= toUtc);
            }

            var total = await query.CountAsync();
            var transactions = await query
                .OrderByDescending(t => t.CreatedAt)
                .Skip((page - 1) * pageSize)
                .Take(pageSize)
                .ToListAsync();

            return Ok(new
            {
                success = true,
                data = transactions.Select(MapTransactionToDto),
                total,
                page,
                pageSize,
                totalPages = (int)Math.Ceiling((double)total / pageSize),
                summary = new
                {
                    totalCharges = agent.TotalCharges,
                    totalPayments = agent.TotalPayments,
                    netBalance = agent.NetBalance
                }
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting transactions for agent {Id}", id);
            return StatusCode(500, new { success = false, message = "حدث خطأ أثناء جلب المعاملات" });
        }
    }

    /// <summary>
    /// إضافة أجور على الوكيل (Charge)
    /// </summary>
    [HttpPost("{id:guid}/charge")]
    [Authorize(Policy = "CompanyAdminOrAbove")]
    public async Task<IActionResult> AddCharge(Guid id, [FromBody] CreateTransactionRequest request)
    {
        try
        {
            var agent = await _unitOfWork.Agents.GetByIdAsync(id);
            if (agent == null)
                return NotFound(new { success = false, message = "الوكيل غير موجود" });

            if (request.Amount <= 0)
                return BadRequest(new { success = false, message = "المبلغ يجب أن يكون أكبر من صفر" });

            // تحديث أرصدة الوكيل
            agent.TotalCharges += request.Amount;
            agent.NetBalance = agent.TotalPayments - agent.TotalCharges;
            _unitOfWork.Agents.Update(agent);

            // إنشاء المعاملة
            var transaction = new AgentTransaction
            {
                AgentId = id,
                Type = TransactionType.Charge,
                Category = request.Category,
                Amount = request.Amount,
                BalanceAfter = agent.NetBalance,
                Description = request.Description ?? "أجور",
                ReferenceNumber = request.ReferenceNumber,
                ServiceRequestId = request.ServiceRequestId,
                CitizenId = request.CitizenId,
                CreatedById = GetCurrentUserId(),
                Notes = request.Notes
            };

            await _unitOfWork.AgentTransactions.AddAsync(transaction);

            // === قيد محاسبي تلقائي: أجور الوكيل ===
            // مدين: 1150-sub ذمم الوكيل (زاد دينه)
            // دائن: 4100 إيرادات (سجّلنا إيراد)
            if (agent.CompanyId != Guid.Empty)
            {
                try
                {
                    var revenueAcct = await ServiceRequestAccountingHelper.FindAccountByCode(
                        _unitOfWork, "4100", agent.CompanyId);
                    var agentSubAcct = await ServiceRequestAccountingHelper.FindOrCreateSubAccount(
                        _unitOfWork, "1150", agent.Id, agent.Name, agent.CompanyId);

                    if (revenueAcct != null)
                    {
                        await _unitOfWork.SaveChangesAsync();

                        var journalLines = new List<(Guid AccountId, decimal DebitAmount, decimal CreditAmount, string? LineDescription)>
                        {
                            (agentSubAcct.Id, request.Amount, 0, $"أجور وكيل {agent.Name} - {request.Description ?? "أجور"}"),
                            (revenueAcct.Id, 0, request.Amount, $"إيراد أجور وكيل {agent.Name}")
                        };
                        await ServiceRequestAccountingHelper.CreateAndPostJournalEntry(
                            _unitOfWork, agent.CompanyId, GetCurrentUserId() ?? Guid.Empty,
                            $"أجور وكيل {agent.Name} - {request.Amount:N0} دينار",
                            JournalReferenceType.AgentTransaction, agent.Id.ToString(),
                            journalLines);

                        // ربط القيد بالمعاملة
                        var je = await _unitOfWork.JournalEntries.AsQueryable()
                            .Where(j => j.ReferenceType == JournalReferenceType.AgentTransaction
                                && j.ReferenceId == agent.Id.ToString()
                                && j.CompanyId == agent.CompanyId)
                            .OrderByDescending(j => j.CreatedAt)
                            .FirstOrDefaultAsync();
                        if (je != null)
                        {
                            transaction.JournalEntryId = je.Id;
                            _unitOfWork.AgentTransactions.Update(transaction);
                        }
                    }
                }
                catch (Exception ex)
                {
                    _logger.LogWarning(ex, "فشل إنشاء القيد المحاسبي لأجور الوكيل {AgentCode}", agent.AgentCode);
                }
            }

            await _unitOfWork.SaveChangesAsync();

            _logger.LogInformation("Charge added to agent {AgentCode}: {Amount} IQD", agent.AgentCode, request.Amount);

            return Ok(new
            {
                success = true,
                message = $"تم إضافة أجور بمبلغ {request.Amount:N0} دينار",
                data = new
                {
                    transaction = MapTransactionToDto(transaction),
                    agentBalance = new
                    {
                        totalCharges = agent.TotalCharges,
                        totalPayments = agent.TotalPayments,
                        netBalance = agent.NetBalance
                    }
                }
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error adding charge to agent {Id}", id);
            return StatusCode(500, new { success = false, message = "حدث خطأ أثناء إضافة الأجور" });
        }
    }

    /// <summary>
    /// تسجيل تسديد من الوكيل (Payment)
    /// </summary>
    [HttpPost("{id:guid}/payment")]
    [Authorize(Policy = "CompanyAdminOrAbove")]
    public async Task<IActionResult> AddPayment(Guid id, [FromBody] CreateTransactionRequest request)
    {
        try
        {
            var agent = await _unitOfWork.Agents.GetByIdAsync(id);
            if (agent == null)
                return NotFound(new { success = false, message = "الوكيل غير موجود" });

            if (request.Amount <= 0)
                return BadRequest(new { success = false, message = "المبلغ يجب أن يكون أكبر من صفر" });

            // تحديث أرصدة الوكيل
            agent.TotalPayments += request.Amount;
            agent.NetBalance = agent.TotalPayments - agent.TotalCharges;
            _unitOfWork.Agents.Update(agent);

            // إنشاء المعاملة
            var transaction = new AgentTransaction
            {
                AgentId = id,
                Type = TransactionType.Payment,
                Category = request.Category,
                Amount = request.Amount,
                BalanceAfter = agent.NetBalance,
                Description = request.Description ?? "تسديد",
                ReferenceNumber = request.ReferenceNumber,
                ServiceRequestId = request.ServiceRequestId,
                CitizenId = request.CitizenId,
                CreatedById = GetCurrentUserId(),
                Notes = request.Notes
            };

            await _unitOfWork.AgentTransactions.AddAsync(transaction);

            // === قيد محاسبي تلقائي: تسديد الوكيل ===
            // مدين: 1110 النقدية (استلمنا كاش)
            // دائن: 1150 ذمم الوكلاء (انخفض دين الوكيل)
            if (agent.CompanyId != Guid.Empty)
            {
                try
                {
                    var cashAcct = await ServiceRequestAccountingHelper.FindAccountByCode(
                        _unitOfWork, "1110", agent.CompanyId);
                    var agentSubAcct = await ServiceRequestAccountingHelper.FindOrCreateSubAccount(
                        _unitOfWork, "1150", agent.Id, agent.Name, agent.CompanyId);

                    if (cashAcct != null)
                    {
                        // حفظ الحساب الفرعي أولاً إذا كان جديداً (لتجنب خطأ FK)
                        await _unitOfWork.SaveChangesAsync();

                        var journalLines = new List<(Guid AccountId, decimal DebitAmount, decimal CreditAmount, string? LineDescription)>
                        {
                            (cashAcct.Id, request.Amount, 0, $"تسديد وكيل {agent.Name} - {request.Description ?? "تسديد"}"),
                            (agentSubAcct.Id, 0, request.Amount, $"تخفيض ذمم وكيل {agent.Name}")
                        };
                        await ServiceRequestAccountingHelper.CreateAndPostJournalEntry(
                            _unitOfWork, agent.CompanyId, GetCurrentUserId() ?? Guid.Empty,
                            $"تسديد وكيل {agent.Name} - {request.Amount:N0} دينار",
                            JournalReferenceType.Manual, agent.Id.ToString(),
                            journalLines);

                        // ربط القيد بالمعاملة
                        var payJe = await _unitOfWork.JournalEntries.AsQueryable()
                            .Where(j => j.ReferenceId == agent.Id.ToString()
                                && j.CompanyId == agent.CompanyId)
                            .OrderByDescending(j => j.CreatedAt)
                            .FirstOrDefaultAsync();
                        if (payJe != null)
                        {
                            transaction.JournalEntryId = payJe.Id;
                            _unitOfWork.AgentTransactions.Update(transaction);
                        }
                    }
                }
                catch (Exception ex)
                {
                    _logger.LogWarning(ex, "فشل إنشاء القيد المحاسبي لتسديد الوكيل {AgentCode}", agent.AgentCode);
                }
            }

            await _unitOfWork.SaveChangesAsync();

            _logger.LogInformation("Payment received from agent {AgentCode}: {Amount} IQD", agent.AgentCode, request.Amount);

            return Ok(new
            {
                success = true,
                message = $"تم تسجيل تسديد بمبلغ {request.Amount:N0} دينار",
                data = new
                {
                    transaction = MapTransactionToDto(transaction),
                    agentBalance = new
                    {
                        totalCharges = agent.TotalCharges,
                        totalPayments = agent.TotalPayments,
                        netBalance = agent.NetBalance
                    }
                }
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error adding payment for agent {Id}", id);
            return StatusCode(500, new { success = false, message = "حدث خطأ أثناء تسجيل التسديد" });
        }
    }

    /// <summary>
    /// ملخص محاسبة جميع الوكلاء (للمدير)
    /// </summary>
    [HttpGet("accounting/summary")]
    [Authorize(Policy = "CompanyAdminOrAbove")]
    public async Task<IActionResult> GetAccountingSummary([FromQuery] Guid? companyId)
    {
        try
        {
            var query = _unitOfWork.Agents.AsQueryable();
            if (companyId.HasValue)
                query = query.Where(a => a.CompanyId == companyId.Value);

            var agents = await query.ToListAsync();

            var summary = new
            {
                totalAgents = agents.Count,
                activeAgents = agents.Count(a => a.Status == AgentStatus.Active),
                totalCharges = agents.Sum(a => a.TotalCharges),
                totalPayments = agents.Sum(a => a.TotalPayments),
                totalNetBalance = agents.Sum(a => a.NetBalance),
                agentsWithDebt = agents.Count(a => a.NetBalance > 0),
                agentsWithCredit = agents.Count(a => a.NetBalance < 0),
                agentsSummary = agents.Select(a => new
                {
                    id = a.Id,
                    agentCode = a.AgentCode,
                    name = a.Name,
                    status = a.Status.ToString(),
                    totalCharges = a.TotalCharges,
                    totalPayments = a.TotalPayments,
                    netBalance = a.NetBalance
                }).OrderByDescending(a => a.netBalance)
            };

            return Ok(new { success = true, data = summary });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting accounting summary");
            return StatusCode(500, new { success = false, message = "حدث خطأ أثناء جلب ملخص المحاسبة" });
        }
    }

    // ==================== تعديل وحذف المعاملات (مدير النظام فقط) ====================

    /// <summary>
    /// تعديل معاملة مالية - مدير النظام فقط
    /// </summary>
    [HttpPut("transactions/{transactionId:long}")]
    [Authorize(Policy = "SuperAdmin")]
    public async Task<IActionResult> UpdateTransaction(long transactionId, [FromBody] UpdateTransactionRequest request)
    {
        try
        {
            var transaction = await _unitOfWork.AgentTransactions
                .FirstOrDefaultAsync(t => t.Id == transactionId);
            if (transaction == null)
                return NotFound(new { success = false, message = "المعاملة غير موجودة" });

            var agent = await _unitOfWork.Agents.GetByIdAsync(transaction.AgentId);
            if (agent == null)
                return NotFound(new { success = false, message = "الوكيل غير موجود" });

            // حفظ القيم القديمة لإعادة حساب الرصيد
            var oldAmount = transaction.Amount;
            var oldType = transaction.Type;

            // عكس تأثير المعاملة القديمة
            if (oldType == TransactionType.Charge)
                agent.TotalCharges -= oldAmount;
            else if (oldType == TransactionType.Payment)
                agent.TotalPayments -= oldAmount;

            // تحديث الحقول
            if (request.Amount.HasValue && request.Amount.Value > 0)
                transaction.Amount = request.Amount.Value;
            if (request.Description != null)
                transaction.Description = request.Description;
            if (request.Notes != null)
                transaction.Notes = request.Notes;
            if (request.Category.HasValue)
                transaction.Category = request.Category.Value;
            
            transaction.UpdatedAt = DateTime.UtcNow;

            // إعادة تطبيق المعاملة بالقيم الجديدة
            if (transaction.Type == TransactionType.Charge)
                agent.TotalCharges += transaction.Amount;
            else if (transaction.Type == TransactionType.Payment)
                agent.TotalPayments += transaction.Amount;

            agent.NetBalance = agent.TotalPayments - agent.TotalCharges;
            transaction.BalanceAfter = agent.NetBalance;

            _unitOfWork.Agents.Update(agent);
            await _unitOfWork.SaveChangesAsync();

            // إعادة حساب BalanceAfter لجميع المعاملات اللاحقة
            await RecalculateBalancesAfter(agent);

            _logger.LogInformation("SuperAdmin updated transaction {Id} for agent {AgentCode}", transactionId, agent.AgentCode);

            return Ok(new
            {
                success = true,
                message = "تم تعديل المعاملة بنجاح",
                data = new
                {
                    transaction = MapTransactionToDto(transaction),
                    agentBalance = new
                    {
                        totalCharges = agent.TotalCharges,
                        totalPayments = agent.TotalPayments,
                        netBalance = agent.NetBalance
                    }
                }
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error updating transaction {Id}", transactionId);
            return StatusCode(500, new { success = false, message = "حدث خطأ أثناء تعديل المعاملة" });
        }
    }

    /// <summary>
    /// حذف معاملة مالية - مدير النظام فقط
    /// </summary>
    [HttpDelete("transactions/{transactionId:long}")]
    [Authorize(Policy = "SuperAdmin")]
    public async Task<IActionResult> DeleteTransaction(long transactionId)
    {
        try
        {
            var transaction = await _unitOfWork.AgentTransactions
                .FirstOrDefaultAsync(t => t.Id == transactionId);
            if (transaction == null)
                return NotFound(new { success = false, message = "المعاملة غير موجودة" });

            var agent = await _unitOfWork.Agents.GetByIdAsync(transaction.AgentId);
            if (agent == null)
                return NotFound(new { success = false, message = "الوكيل غير موجود" });

            // عكس تأثير المعاملة على رصيد الوكيل
            if (transaction.Type == TransactionType.Charge)
                agent.TotalCharges -= transaction.Amount;
            else if (transaction.Type == TransactionType.Payment)
                agent.TotalPayments -= transaction.Amount;

            agent.NetBalance = agent.TotalPayments - agent.TotalCharges;
            _unitOfWork.Agents.Update(agent);

            // حذف طلب الخدمة المرتبط وسجلاته بشكل كامل من قاعدة البيانات
            if (transaction.ServiceRequestId.HasValue)
            {
                var serviceRequest = await _unitOfWork.ServiceRequests
                    .FirstOrDefaultAsync(sr => sr.Id == transaction.ServiceRequestId.Value);
                if (serviceRequest != null)
                {
                    // حذف السجلات المرتبطة
                    var statusHistories = await _unitOfWork.ServiceRequestStatusHistories.AsQueryable()
                        .Where(h => h.ServiceRequestId == serviceRequest.Id).ToListAsync();
                    foreach (var h in statusHistories)
                        _unitOfWork.ServiceRequestStatusHistories.Delete(h);

                    var comments = await _unitOfWork.ServiceRequestComments.AsQueryable()
                        .Where(c => c.ServiceRequestId == serviceRequest.Id).ToListAsync();
                    foreach (var c in comments)
                        _unitOfWork.ServiceRequestComments.Delete(c);

                    var attachments = await _unitOfWork.ServiceRequestAttachments.AsQueryable()
                        .Where(a => a.ServiceRequestId == serviceRequest.Id).ToListAsync();
                    foreach (var a in attachments)
                        _unitOfWork.ServiceRequestAttachments.Delete(a);

                    _unitOfWork.ServiceRequests.Delete(serviceRequest);
                    _logger.LogInformation("Hard-deleted linked ServiceRequest {SrId}", serviceRequest.Id);
                }
            }

            // حذف المعاملة بشكل كامل
            _unitOfWork.AgentTransactions.Delete(transaction);

            await _unitOfWork.SaveChangesAsync();

            // إعادة حساب BalanceAfter لجميع المعاملات المتبقية
            await RecalculateBalancesAfter(agent);

            _logger.LogInformation("SuperAdmin deleted transaction {Id} for agent {AgentCode}", transactionId, agent.AgentCode);

            return Ok(new
            {
                success = true,
                message = "تم حذف المعاملة بنجاح",
                data = new
                {
                    agentBalance = new
                    {
                        totalCharges = agent.TotalCharges,
                        totalPayments = agent.TotalPayments,
                        netBalance = agent.NetBalance
                    }
                }
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error deleting transaction {Id}", transactionId);
            return StatusCode(500, new { success = false, message = "حدث خطأ أثناء حذف المعاملة" });
        }
    }

    /// <summary>
    /// إعادة حساب BalanceAfter لجميع معاملات الوكيل بالترتيب
    /// </summary>
    private async Task RecalculateBalancesAfter(Agent agent)
    {
        var allTransactions = await _unitOfWork.AgentTransactions
            .AsQueryable()
            .Where(t => t.AgentId == agent.Id)
            .OrderBy(t => t.CreatedAt)
            .ThenBy(t => t.Id)
            .ToListAsync();

        decimal runningCharges = 0;
        decimal runningPayments = 0;
        foreach (var tx in allTransactions)
        {
            if (tx.Type == TransactionType.Charge)
                runningCharges += tx.Amount;
            else if (tx.Type == TransactionType.Payment)
                runningPayments += tx.Amount;

            tx.BalanceAfter = runningPayments - runningCharges;
        }
        await _unitOfWork.SaveChangesAsync();
    }

    /// <summary>
    /// جلب الملف الشخصي للوكيل الحالي (يستخدمها الوكيل بعد تسجيل الدخول)
    /// </summary>
    [HttpGet("me")]
    [Authorize]
    public async Task<IActionResult> GetMyProfile()
    {
        try
        {
            var agentId = GetCurrentAgentId();
            if (agentId == null)
                return Unauthorized(new { success = false, message = "غير مصرح" });

            var agent = await _unitOfWork.Agents.FirstOrDefaultAsync(a => a.Id == agentId);

            if (agent == null)
                return NotFound(new { success = false, message = "الوكيل غير موجود" });

            // تحميل الشركة بشكل منفصل
            if (agent.CompanyId != Guid.Empty)
                agent.Company = await _unitOfWork.Companies.FirstOrDefaultAsync(c => c.Id == agent.CompanyId);

            return Ok(new { success = true, data = MapAgentToDto(agent) });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting agent profile");
            return StatusCode(500, new { success = false, message = "حدث خطأ" });
        }
    }

    /// <summary>
    /// تغيير كلمة المرور للوكيل الحالي
    /// </summary>
    [HttpPost("me/change-password")]
    [Authorize]
    public async Task<IActionResult> ChangeMyPassword([FromBody] AgentChangePasswordRequest request)
    {
        try
        {
            var agentId = GetCurrentAgentId();
            if (agentId == null)
                return Unauthorized(new { success = false, message = "غير مصرح" });

            var agent = await _unitOfWork.Agents.FirstOrDefaultAsync(a => a.Id == agentId);
            if (agent == null)
                return NotFound(new { success = false, message = "الوكيل غير موجود" });

            if (string.IsNullOrWhiteSpace(request.CurrentPassword) || string.IsNullOrWhiteSpace(request.NewPassword))
                return BadRequest(new { success = false, message = "كلمة المرور الحالية والجديدة مطلوبتان" });

            if (request.NewPassword.Length < 6)
                return BadRequest(new { success = false, message = "كلمة المرور يجب أن تكون 6 أحرف على الأقل" });

            // التحقق من كلمة المرور الحالية
            if (!VerifyPassword(request.CurrentPassword, agent.PasswordHash))
                return BadRequest(new { success = false, message = "كلمة المرور الحالية غير صحيحة" });

            agent.PasswordHash = HashPassword(request.NewPassword);
            agent.UpdatedAt = DateTime.UtcNow;
            _unitOfWork.Agents.Update(agent);
            await _unitOfWork.SaveChangesAsync();

            _logger.LogInformation("Agent {AgentCode} changed password", agent.AgentCode);

            return Ok(new { success = true, message = "تم تغيير كلمة المرور بنجاح" });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error changing agent password");
            return StatusCode(500, new { success = false, message = "حدث خطأ أثناء تغيير كلمة المرور" });
        }
    }

    /// <summary>
    /// ملخص حسابات الوكيل الحالي (مع إحصائيات اليوم)
    /// </summary>
    [HttpGet("me/accounting")]
    [Authorize]
    public async Task<IActionResult> GetMyAccountingSummary()
    {
        try
        {
            var agentId = GetCurrentAgentId();
            if (agentId == null)
                return Unauthorized(new { success = false, message = "غير مصرح" });

            var agent = await _unitOfWork.Agents.FirstOrDefaultAsync(a => a.Id == agentId);
            if (agent == null)
                return NotFound(new { success = false, message = "الوكيل غير موجود" });

            var todayStart = DateTime.UtcNow.AddHours(3).Date;
            var transactions = await _unitOfWork.AgentTransactions.AsQueryable()
                .Where(t => t.AgentId == agentId.Value)
                .ToListAsync();

            var todayTransactions = transactions.Where(t => t.CreatedAt >= todayStart).ToList();

            return Ok(new
            {
                success = true,
                data = new
                {
                    totalCharges = agent.TotalCharges,
                    totalPayments = agent.TotalPayments,
                    netBalance = agent.NetBalance,
                    transactionsCount = transactions.Count,
                    todayCharges = todayTransactions.Where(t => t.Type == TransactionType.Charge).Sum(t => t.Amount),
                    todayPayments = todayTransactions.Where(t => t.Type == TransactionType.Payment).Sum(t => t.Amount),
                    todayTransactionsCount = todayTransactions.Count
                }
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting agent accounting summary");
            return StatusCode(500, new { success = false, message = "حدث خطأ أثناء جلب ملخص الحسابات" });
        }
    }

    /// <summary>
    /// جلب معاملات الوكيل الحالي (يستخدمها الوكيل نفسه)
    /// </summary>
    [HttpGet("me/transactions")]
    [Authorize]
    public async Task<IActionResult> GetMyTransactions(
        [FromQuery] TransactionType? type,
        [FromQuery] DateTime? from,
        [FromQuery] DateTime? to,
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 20)
    {
        try
        {
            var agentId = GetCurrentAgentId();
            if (agentId == null)
                return Unauthorized(new { success = false, message = "غير مصرح" });

            var agent = await _unitOfWork.Agents.FirstOrDefaultAsync(a => a.Id == agentId);
            if (agent == null)
                return NotFound(new { success = false, message = "الوكيل غير موجود" });

            var query = _unitOfWork.AgentTransactions.AsQueryable()
                .Where(t => t.AgentId == agentId);

            if (type.HasValue)
                query = query.Where(t => t.Type == type.Value);

            if (from.HasValue)
            {
                var fromUtc = DateTime.SpecifyKind(from.Value.AddHours(-3), DateTimeKind.Utc);
                query = query.Where(t => t.CreatedAt >= fromUtc);
            }

            if (to.HasValue)
            {
                var toUtc = DateTime.SpecifyKind(to.Value.AddHours(-3), DateTimeKind.Utc);
                query = query.Where(t => t.CreatedAt <= toUtc);
            }

            var total = await query.CountAsync();
            var transactions = await query
                .OrderByDescending(t => t.CreatedAt)
                .Skip((page - 1) * pageSize)
                .Take(pageSize)
                .ToListAsync();

            return Ok(new
            {
                success = true,
                data = transactions.Select(MapTransactionToDto),
                total,
                page,
                pageSize,
                totalPages = (int)Math.Ceiling((double)total / pageSize),
                summary = new
                {
                    totalCharges = agent.TotalCharges,
                    totalPayments = agent.TotalPayments,
                    netBalance = agent.NetBalance
                }
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting my transactions");
            return StatusCode(500, new { success = false, message = "حدث خطأ أثناء جلب المعاملات" });
        }
    }

    // ==================== تسديد مديونية (Agent Self-Payment) ====================

    /// <summary>
    /// تسجيل تسديد مديونية - الوكيل يُسدد جزء من رصيده المستحق
    /// </summary>
    [HttpPost("me/payment")]
    [Authorize]
    public async Task<IActionResult> AddMyPayment([FromBody] CreateTransactionRequest request)
    {
        try
        {
            var agentId = GetCurrentAgentId();
            if (agentId == null)
                return Unauthorized(new { success = false, message = "غير مصرح" });

            var agent = await _unitOfWork.Agents.FirstOrDefaultAsync(a => a.Id == agentId);
            if (agent == null)
                return NotFound(new { success = false, message = "الوكيل غير موجود" });

            if (request.Amount <= 0)
                return BadRequest(new { success = false, message = "المبلغ يجب أن يكون أكبر من صفر" });

            // إنشاء رقم طلب تسلسلي بسيط
            var maxNumber = await _unitOfWork.ServiceRequests.AsQueryable()
                .IgnoreQueryFilters()
                .Select(s => s.RequestNumber)
                .Where(n => n != null)
                .ToListAsync();
            var nextNum = maxNumber
                .Select(n => int.TryParse(n, out var num) ? num : 0)
                .DefaultIfEmpty(1000)
                .Max() + 1;
            var requestNumber = nextNum.ToString();

            // إنشاء طلب خدمة ليظهر في شاشة الشركة
            var details = new Dictionary<string, object>
            {
                { "customerName", agent.Name },
                { "customerPhone", agent.PhoneNumber ?? "" },
                { "agentCode", agent.AgentCode },
                { "agentName", agent.Name },
                { "agentType", agent.Type == AgentType.Private ? "وكيل خاص" : "وكيل عام" },
                { "pageId", agent.PageId ?? "" },
                { "source", "agent_portal" },
                { "type", "debt_payment" },
                { "amount", request.Amount },
                { "description", request.Description ?? "تسديد حساب" }
            };

            var serviceRequest = new ServiceRequest
            {
                Id = Guid.NewGuid(),
                RequestNumber = requestNumber,
                ServiceId = 10, // عمليات الوكلاء
                OperationTypeId = 11, // دفع مديونية
                CitizenId = null,
                AgentId = agentId.Value,
                CompanyId = agent.CompanyId != Guid.Empty ? agent.CompanyId : null,
                Details = JsonSerializer.Serialize(details),
                ContactPhone = agent.PhoneNumber,
                Status = ServiceRequestStatus.Pending,
                Priority = 3,
                EstimatedCost = request.Amount,
                RequestedAt = DateTime.UtcNow,
                CreatedAt = DateTime.UtcNow
            };
            await _unitOfWork.ServiceRequests.AddAsync(serviceRequest);

            // تحديث أرصدة الوكيل
            agent.TotalPayments += request.Amount;
            agent.NetBalance = agent.TotalPayments - agent.TotalCharges;
            _unitOfWork.Agents.Update(agent);

            // إنشاء المعاملة
            var transaction = new AgentTransaction
            {
                AgentId = agentId.Value,
                Type = TransactionType.Payment,
                Category = request.Category,
                Amount = request.Amount,
                BalanceAfter = agent.NetBalance,
                Description = request.Description ?? "تسديد حساب",
                ReferenceNumber = requestNumber,
                ServiceRequestId = serviceRequest.Id,
                CitizenId = request.CitizenId,
                CreatedById = agentId,
                Notes = request.Notes
            };

            await _unitOfWork.AgentTransactions.AddAsync(transaction);
            await _unitOfWork.SaveChangesAsync();

            _logger.LogInformation("Agent {AgentCode} self-payment: {Amount} IQD", agent.AgentCode, request.Amount);

            return Ok(new
            {
                success = true,
                message = $"تم تسجيل تسديد بمبلغ {request.Amount:N0} دينار",
                data = new
                {
                    transaction = MapTransactionToDto(transaction),
                    agentBalance = new
                    {
                        totalCharges = agent.TotalCharges,
                        totalPayments = agent.TotalPayments,
                        netBalance = agent.NetBalance
                    }
                }
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error adding self-payment");
            return StatusCode(500, new { success = false, message = "حدث خطأ أثناء تسجيل التسديد" });
        }
    }

    // ==================== طلب رصيد (Balance Request) ====================

    /// <summary>
    /// طلب رصيد من الشركة (الوكيل يطلب شحن رصيد)
    /// يُنشئ طلب خدمة من نوع "طلب رصيد" + عملية مالية معلقة
    /// </summary>
    [HttpPost("me/balance-request")]
    [Authorize]
    public async Task<IActionResult> RequestBalance([FromBody] BalanceRequestDto dto)
    {
        try
        {
            var agentId = GetCurrentAgentId();
            if (agentId == null)
                return Unauthorized(new { success = false, message = "غير مصرح" });

            var agent = await _unitOfWork.Agents.FirstOrDefaultAsync(a => a.Id == agentId);
            if (agent == null)
                return NotFound(new { success = false, message = "الوكيل غير موجود" });

            if (dto.Amount <= 0)
                return BadRequest(new { success = false, message = "المبلغ يجب أن يكون أكبر من صفر" });

            // إنشاء رقم طلب تسلسلي بسيط
            var allNums2 = await _unitOfWork.ServiceRequests.AsQueryable()
                .IgnoreQueryFilters()
                .Select(s => s.RequestNumber)
                .Where(n => n != null)
                .ToListAsync();
            var nextN2 = allNums2
                .Select(n => int.TryParse(n, out var num) ? num : 0)
                .DefaultIfEmpty(1000)
                .Max() + 1;
            var requestNumber = nextN2.ToString();

            var methodText = dto.Category == 7 ? "تحويل بنكي" : "نقدي";

            // إنشاء طلب خدمة ليظهر في شاشة الشركة
            var details = new Dictionary<string, object>
            {
                { "customerName", agent.Name },
                { "customerPhone", agent.PhoneNumber ?? "" },
                { "agentCode", agent.AgentCode },
                { "agentName", agent.Name },
                { "agentType", agent.Type == AgentType.Private ? "وكيل خاص" : "وكيل عام" },
                { "pageId", agent.PageId ?? "" },
                { "source", "agent_portal" },
                { "type", "balance_request" },
                { "amount", dto.Amount },
                { "method", methodText }
            };

            var serviceRequest = new ServiceRequest
            {
                Id = Guid.NewGuid(),
                RequestNumber = requestNumber,
                ServiceId = 10, // عمليات الوكلاء
                OperationTypeId = 10, // طلب رصيد
                CitizenId = null,
                AgentId = agentId.Value,
                CompanyId = agent.CompanyId != Guid.Empty ? agent.CompanyId : null,
                Details = JsonSerializer.Serialize(details),
                ContactPhone = agent.PhoneNumber,
                Status = ServiceRequestStatus.Pending,
                Priority = 3,
                EstimatedCost = dto.Amount,
                RequestedAt = DateTime.UtcNow,
                CreatedAt = DateTime.UtcNow
            };
            await _unitOfWork.ServiceRequests.AddAsync(serviceRequest);

            // تسجيل العملية كـ Charge (دين على الوكيل)
            var transaction = new AgentTransaction
            {
                AgentId = agentId.Value,
                Type = TransactionType.Charge,
                Category = dto.Category == 7 ? TransactionCategory.BankTransfer : TransactionCategory.CashPayment,
                Amount = dto.Amount,
                Description = dto.Description ?? $"طلب رصيد ({methodText})",
                ReferenceNumber = requestNumber,
                ServiceRequestId = serviceRequest.Id,
                CreatedById = agentId,
                CreatedAt = DateTime.UtcNow
            };

            // تحديث أرصدة الوكيل - طلب رصيد = دين على الوكيل
            agent.TotalCharges += dto.Amount;
            agent.NetBalance = agent.TotalPayments - agent.TotalCharges;
            transaction.BalanceAfter = agent.NetBalance;

            _unitOfWork.Agents.Update(agent);
            await _unitOfWork.AgentTransactions.AddAsync(transaction);

            // === قيد محاسبي تلقائي: طلب رصيد (سلفة للوكيل) ===
            // مدين: 1150 ذمم الوكلاء (زاد دين الوكيل)
            // دائن: 1110 النقدية (أعطيناه كاش/رصيد)
            if (agent.CompanyId != Guid.Empty)
            {
                try
                {
                    var agentSubAcct = await ServiceRequestAccountingHelper.FindOrCreateSubAccount(
                        _unitOfWork, "1150", agent.Id, agent.Name, agent.CompanyId);
                    var cashAcct = await ServiceRequestAccountingHelper.FindAccountByCode(
                        _unitOfWork, "1110", agent.CompanyId);

                    if (cashAcct != null)
                    {
                        // حفظ الحساب الفرعي أولاً إذا كان جديداً (لتجنب خطأ FK)
                        await _unitOfWork.SaveChangesAsync();

                        var journalLines = new List<(Guid AccountId, decimal DebitAmount, decimal CreditAmount, string? LineDescription)>
                        {
                            (agentSubAcct.Id, dto.Amount, 0, $"طلب رصيد وكيل {agent.Name} ({methodText})"),
                            (cashAcct.Id, 0, dto.Amount, $"صرف رصيد لوكيل {agent.Name})")
                        };
                        await ServiceRequestAccountingHelper.CreateAndPostJournalEntry(
                            _unitOfWork, agent.CompanyId, agentId ?? Guid.Empty,
                            $"طلب رصيد وكيل {agent.Name} - {dto.Amount:N0} دينار ({methodText})",
                            JournalReferenceType.Manual, serviceRequest.Id.ToString(),
                            journalLines);
                    }
                }
                catch (Exception ex)
                {
                    _logger.LogWarning(ex, "فشل إنشاء القيد المحاسبي لطلب رصيد الوكيل {AgentCode}", agent.AgentCode);
                }
            }

            await _unitOfWork.SaveChangesAsync();

            _logger.LogInformation("Agent {AgentCode} requested balance: {Amount} IQD via {Method}", 
                agent.AgentCode, dto.Amount, methodText);

            return Ok(new
            {
                success = true,
                message = "تم تقديم طلب الرصيد بنجاح",
                data = new
                {
                    referenceNumber = requestNumber,
                    amount = dto.Amount,
                    method = methodText,
                    transaction = MapTransactionToDto(transaction),
                    agentBalance = new
                    {
                        totalCharges = agent.TotalCharges,
                        totalPayments = agent.TotalPayments,
                        netBalance = agent.NetBalance
                    }
                }
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error creating balance request");
            return StatusCode(500, new { success = false, message = "حدث خطأ أثناء تقديم الطلب" });
        }
    }

    // ==================== طلبات الخدمة (Service Requests) ====================

    /// <summary>
    /// إنشاء طلب خدمة جديد (تفعيل اشتراك) - للوكيل
    /// </summary>
    [HttpPost("me/service-request")]
    [Authorize]
    public async Task<IActionResult> CreateServiceRequest([FromBody] AgentServiceRequestDto dto)
    {
        try
        {
            var agentId = GetCurrentAgentId();
            if (agentId == null)
                return Unauthorized(new { success = false, message = "غير مصرح" });

            var agent = await _unitOfWork.Agents.FirstOrDefaultAsync(a => a.Id == agentId);
            if (agent == null)
                return NotFound(new { success = false, message = "الوكيل غير موجود" });

            // التحقق من الباقة (إن وجدت)
            InternetPlan? plan = null;
            if (dto.InternetPlanId.HasValue)
            {
                plan = await _unitOfWork.InternetPlans.GetByIdAsync(dto.InternetPlanId.Value);
                if (plan == null || !plan.IsActive)
                    return BadRequest(new { success = false, message = "الباقة غير متوفرة" });
            }

            // التحقق من الخدمة
            var service = await _unitOfWork.Services.GetByIdAsync(dto.ServiceId);
            if (service == null || !service.IsActive)
                return BadRequest(new { success = false, message = "الخدمة غير متوفرة" });

            // التحقق من نوع العملية
            var opType = await _unitOfWork.OperationTypes.GetByIdAsync(dto.OperationTypeId);
            if (opType == null)
                return BadRequest(new { success = false, message = "نوع العملية غير صالح" });

            // إنشاء رقم طلب تسلسلي بسيط
            var allNums3 = await _unitOfWork.ServiceRequests.AsQueryable()
                .IgnoreQueryFilters()
                .Select(s => s.RequestNumber)
                .Where(n => n != null)
                .ToListAsync();
            var nextN3 = allNums3
                .Select(n => int.TryParse(n, out var num) ? num : 0)
                .DefaultIfEmpty(1000)
                .Max() + 1;
            var requestNumber = nextN3.ToString();

            // تحضير التفاصيل
            var details = new Dictionary<string, object>
            {
                { "customerName", dto.CustomerName ?? "" },
                { "customerPhone", dto.CustomerPhone ?? "" },
                { "agentCode", agent.AgentCode },
                { "agentName", agent.Name },
                { "agentType", agent.Type == AgentType.Private ? "وكيل خاص" : "وكيل عام" },
                { "pageId", agent.PageId ?? "" },
                { "source", "agent_portal" }
            };

            if (plan != null)
            {
                details["planId"] = plan.Id.ToString();
                details["planName"] = plan.NameAr;
                details["planSpeed"] = plan.SpeedMbps?.ToString() ?? "";
                details["monthlyPrice"] = plan.MonthlyPrice.ToString("F0");
                details["installationFee"] = plan.InstallationFee.ToString("F0");
            }

            // مدة الاشتراك
            if (dto.SubscriptionDuration.HasValue && dto.SubscriptionDuration.Value > 0)
            {
                details["subscriptionDuration"] = dto.SubscriptionDuration.Value;
            }

            // حساب التكلفة
            var estimatedCost = plan != null ? plan.MonthlyPrice + plan.InstallationFee : 0m;

            var serviceRequest = new ServiceRequest
            {
                Id = Guid.NewGuid(),
                RequestNumber = requestNumber,
                ServiceId = dto.ServiceId,
                OperationTypeId = dto.OperationTypeId,
                CitizenId = null, // سيتم ربطه لاحقاً إذا وجد المواطن
                AgentId = agentId.Value, // ربط الطلب بالوكيل مباشرة
                CompanyId = agent.CompanyId != Guid.Empty ? agent.CompanyId : null,
                Details = JsonSerializer.Serialize(details),
                Address = dto.Address,
                City = dto.City,
                Area = dto.Area,
                ContactPhone = dto.CustomerPhone,
                Status = ServiceRequestStatus.Pending,
                Priority = dto.Priority,
                EstimatedCost = estimatedCost,
                RequestedAt = DateTime.UtcNow,
                CreatedAt = DateTime.UtcNow
            };

            await _unitOfWork.ServiceRequests.AddAsync(serviceRequest);

            // إضافة سجل الحالة
            var statusHistory = new ServiceRequestStatusHistory
            {
                ServiceRequestId = serviceRequest.Id,
                FromStatus = ServiceRequestStatus.Pending,
                ToStatus = ServiceRequestStatus.Pending,
                Note = $"تم إنشاء الطلب بواسطة الوكيل {agent.AgentCode} - {agent.Name}",
                ChangedById = null, // Agent ID is not in Users table
                CreatedAt = DateTime.UtcNow
            };
            await _unitOfWork.ServiceRequestStatusHistories.AddAsync(statusHistory);

            // ملاحظة: لا يتم خصم الرصيد عند إنشاء الطلب
            // يتم الخصم فقط عند اكتمال الطلب (في ServiceRequestsController.UpdateStatus)

            await _unitOfWork.SaveChangesAsync();

            // ═══════ إشعار المدراء بطلب وكيل جديد ═══════
            try
            {
                var adminRoles = new[] { UserRole.CompanyAdmin, UserRole.Manager, UserRole.SuperAdmin };
                var adminIds = await _unitOfWork.Users.AsQueryable()
                    .Where(u => adminRoles.Contains(u.Role) && !u.IsDeleted)
                    .Select(u => u.Id)
                    .ToListAsync();

                foreach (var adminId in adminIds)
                {
                    await _unitOfWork.Notifications.AddAsync(new Notification
                    {
                        UserId = adminId,
                        Title = "طلب وكيل جديد",
                        TitleAr = "طلب وكيل جديد",
                        Body = $"طلب جديد من الوكيل {agent.AgentCode} ({agent.Name}): {requestNumber} - {dto.CustomerName}",
                        BodyAr = $"طلب جديد من الوكيل {agent.AgentCode} ({agent.Name}): {requestNumber} - {dto.CustomerName}",
                        Type = NotificationType.AgentRequest,
                        ReferenceId = serviceRequest.Id,
                        ReferenceType = "ServiceRequest",
                        CreatedAt = DateTime.UtcNow
                    });
                }
                if (adminIds.Count > 0)
                    await _unitOfWork.SaveChangesAsync();
            }
            catch (Exception notifEx)
            {
                _logger.LogWarning(notifEx, "فشل إرسال إشعارات طلب الوكيل - الطلب نفسه تم إنشاؤه بنجاح");
            }

            _logger.LogInformation("Agent {AgentCode} created service request {RequestNumber}", agent.AgentCode, requestNumber);

            return Ok(new
            {
                success = true,
                message = "تم إنشاء طلب الخدمة بنجاح",
                data = new
                {
                    serviceRequest.Id,
                    serviceRequest.RequestNumber,
                    Status = serviceRequest.Status.ToString(),
                    statusValue = (int)serviceRequest.Status,
                    serviceRequest.EstimatedCost,
                    serviceName = service.NameAr,
                    operationType = opType.NameAr,
                    customerName = dto.CustomerName,
                    customerPhone = dto.CustomerPhone,
                    agentBalance = agent.NetBalance,
                    serviceRequest.CreatedAt
                }
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error creating service request");
            return StatusCode(500, new { success = false, message = "حدث خطأ أثناء إنشاء الطلب" });
        }
    }

    /// <summary>
    /// جلب طلبات الخدمة للوكيل
    /// </summary>
    [HttpGet("me/service-requests")]
    [Authorize]
    public async Task<IActionResult> GetMyServiceRequests(
        [FromQuery] string? status,
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 20)
    {
        try
        {
            var agentId = GetCurrentAgentId();
            if (agentId == null)
                return Unauthorized(new { success = false, message = "غير مصرح" });

            var agent = await _unitOfWork.Agents.FirstOrDefaultAsync(a => a.Id == agentId);
            if (agent == null)
                return NotFound(new { success = false, message = "الوكيل غير موجود" });

            // الطلبات التي أنشأها الوكيل (عبر AgentId مباشرة)
            var query = _unitOfWork.ServiceRequests.AsQueryable()
                .Where(r => r.AgentId == agentId.Value);

            if (!string.IsNullOrEmpty(status) && Enum.TryParse<ServiceRequestStatus>(status, true, out var filterStatus))
                query = query.Where(r => r.Status == filterStatus);

            var total = await query.CountAsync();
            var requests = await query
                .Include(r => r.Service)
                .OrderByDescending(r => r.CreatedAt)
                .Skip((page - 1) * pageSize)
                .Take(pageSize)
                .Select(r => new
                {
                    r.Id,
                    r.RequestNumber,
                    ServiceName = r.Service != null ? r.Service.NameAr : "",
                    Status = r.Status.ToString(),
                    StatusValue = (int)r.Status,
                    r.Details,
                    r.ContactPhone,
                    r.Address,
                    r.City,
                    r.Area,
                    r.EstimatedCost,
                    r.Priority,
                    r.CreatedAt,
                    r.CompletedAt
                })
                .ToListAsync();

            return Ok(new
            {
                success = true,
                data = requests,
                total,
                page,
                pageSize,
                totalPages = (int)Math.Ceiling((double)total / pageSize)
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting agent service requests");
            return StatusCode(500, new { success = false, message = "حدث خطأ أثناء جلب الطلبات" });
        }
    }

    // ==================== دوال مساعدة ====================

    private async Task<string> GenerateAgentCode()
    {
        var lastAgent = await _unitOfWork.Agents.AsQueryable()
            .OrderByDescending(a => a.AgentCode)
            .FirstOrDefaultAsync();

        int nextNumber = 1001;
        if (lastAgent != null)
        {
            if (int.TryParse(lastAgent.AgentCode, out int lastNumber))
                nextNumber = lastNumber + 1;
            else if (lastAgent.AgentCode.StartsWith("AGT-"))
            {
                if (int.TryParse(lastAgent.AgentCode.Replace("AGT-", ""), out int agentNum))
                    nextNumber = 1000 + agentNum + 1;
            }
        }

        return nextNumber.ToString();
    }

    private string HashPassword(string password)
    {
        using var sha256 = SHA256.Create();
        var hashedBytes = sha256.ComputeHash(Encoding.UTF8.GetBytes(password + "SadaraSalt2024"));
        return Convert.ToBase64String(hashedBytes);
    }

    private bool VerifyPassword(string password, string hash)
    {
        return HashPassword(password) == hash;
    }

    private string GenerateAgentToken(Agent agent)
    {
        var jwtSecret = _configuration["Jwt:Secret"] ?? "YourSuperSecretKeyThatIsAtLeast32CharactersLong!";
        var key = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(jwtSecret));
        var credentials = new SigningCredentials(key, SecurityAlgorithms.HmacSha256);

        var claims = new[]
        {
            new Claim(ClaimTypes.NameIdentifier, agent.Id.ToString()),
            new Claim(ClaimTypes.Name, agent.Name),
            new Claim(ClaimTypes.MobilePhone, agent.PhoneNumber),
            new Claim("agent_code", agent.AgentCode),
            new Claim("company_id", agent.CompanyId.ToString()),
            new Claim("role", "Agent"),
            new Claim("user_type", "agent")
        };

        var token = new JwtSecurityToken(
            issuer: _configuration["Jwt:Issuer"] ?? "SadaraPlatform",
            audience: _configuration["Jwt:Audience"] ?? "SadaraClients",
            claims: claims,
            expires: DateTime.UtcNow.AddDays(30),
            signingCredentials: credentials
        );

        return new JwtSecurityTokenHandler().WriteToken(token);
    }

    private Guid? GetCurrentUserId()
    {
        var userIdClaim = User.FindFirst(ClaimTypes.NameIdentifier)?.Value;
        return Guid.TryParse(userIdClaim, out var userId) ? userId : null;
    }

    private Guid? GetCurrentAgentId()
    {
        var userType = User.FindFirst("user_type")?.Value;
        if (userType != "agent") return null;
        var idClaim = User.FindFirst(ClaimTypes.NameIdentifier)?.Value;
        return Guid.TryParse(idClaim, out var agentId) ? agentId : null;
    }

    private static object MapAgentToDto(Agent agent)
    {
        return new
        {
            id = agent.Id,
            agentCode = agent.AgentCode,
            name = agent.Name,
            type = agent.Type.ToString(),
            typeValue = (int)agent.Type,
            phoneNumber = agent.PhoneNumber,
            email = agent.Email,
            city = agent.City,
            area = agent.Area,
            fullAddress = agent.FullAddress,
            latitude = agent.Latitude,
            longitude = agent.Longitude,
            pageId = agent.PageId,
            companyId = agent.CompanyId,
            companyName = agent.Company?.Name,
            status = agent.Status.ToString(),
            statusValue = (int)agent.Status,
            profileImageUrl = agent.ProfileImageUrl,
            notes = agent.Notes,
            lastLoginAt = agent.LastLoginAt,
            totalCharges = agent.TotalCharges,
            totalPayments = agent.TotalPayments,
            netBalance = agent.NetBalance,
            plainPassword = agent.PlainPassword,
            createdAt = agent.CreatedAt,
            updatedAt = agent.UpdatedAt
        };
    }

    private static object MapTransactionToDto(AgentTransaction tx)
    {
        return new
        {
            id = tx.Id,
            agentId = tx.AgentId,
            type = tx.Type.ToString(),
            typeValue = (int)tx.Type,
            category = tx.Category.ToString(),
            categoryValue = (int)tx.Category,
            amount = tx.Amount,
            balanceAfter = tx.BalanceAfter,
            description = tx.Description,
            referenceNumber = tx.ReferenceNumber,
            serviceRequestId = tx.ServiceRequestId,
            citizenId = tx.CitizenId,
            createdById = tx.CreatedById,
            notes = tx.Notes,
            journalEntryId = tx.JournalEntryId,
            createdAt = tx.CreatedAt
        };
    }
}

// ==================== DTOs ====================

public record AgentLoginRequest(string? PhoneNumber, string Password, string? AgentCode = null);

public record CreateAgentRequest(
    string Name,
    AgentType Type,
    string PhoneNumber,
    string Password,
    string? Email,
    string? City,
    string? Area,
    string? FullAddress,
    double? Latitude,
    double? Longitude,
    string? PageId,
    Guid CompanyId,
    string? Notes
);

public record UpdateAgentRequest(
    string? Name,
    AgentType? Type,
    string? PhoneNumber,
    string? NewPassword,
    string? Email,
    string? City,
    string? Area,
    string? FullAddress,
    double? Latitude,
    double? Longitude,
    string? PageId,
    AgentStatus? Status,
    string? Notes,
    string? ProfileImageUrl
);

public record CreateTransactionRequest(
    decimal Amount,
    TransactionCategory Category,
    string? Description,
    string? ReferenceNumber,
    Guid? ServiceRequestId,
    Guid? CitizenId,
    string? Notes
);

/// <summary>
/// طلب إنشاء خدمة بواسطة الوكيل
/// </summary>
public class AgentServiceRequestDto
{
    /// <summary>معرف الخدمة (9 = Internet FTTH)</summary>
    public int ServiceId { get; set; }
    
    /// <summary>نوع العملية (8 = تفعيل اشتراك جديد)</summary>
    public int OperationTypeId { get; set; }
    
    /// <summary>معرف باقة الإنترنت (اختياري)</summary>
    public Guid? InternetPlanId { get; set; }
    
    /// <summary>اسم الزبون</summary>
    public string? CustomerName { get; set; }
    
    /// <summary>هاتف الزبون</summary>
    public string? CustomerPhone { get; set; }
    
    /// <summary>العنوان</summary>
    public string? Address { get; set; }
    
    /// <summary>المدينة</summary>
    public string? City { get; set; }
    
    /// <summary>المنطقة</summary>
    public string? Area { get; set; }
    
    /// <summary>الأولوية (1=عاجل, 5=عادي)</summary>
    public int Priority { get; set; } = 3;
    
    /// <summary>مدة الاشتراك بالأشهر (اختياري)</summary>
    public int? SubscriptionDuration { get; set; }
    
    /// <summary>ملاحظات إضافية</summary>
    public string? Notes { get; set; }
}

/// <summary>
/// طلب رصيد من الوكيل
/// </summary>
public class BalanceRequestDto
{
    /// <summary>المبلغ المطلوب</summary>
    public decimal Amount { get; set; }
    
    /// <summary>الوصف</summary>
    public string? Description { get; set; }
    
    /// <summary>طريقة الدفع (6=نقدي, 7=تحويل بنكي)</summary>
    public int Category { get; set; } = 7;
}

/// <summary>
/// طلب تغيير كلمة المرور (للوكيل)
/// </summary>
public record AgentChangePasswordRequest(string CurrentPassword, string NewPassword);

/// <summary>
/// طلب تعديل معاملة مالية (مدير النظام فقط)
/// </summary>
public class UpdateTransactionRequest
{
    /// <summary>المبلغ الجديد (اختياري)</summary>
    public decimal? Amount { get; set; }
    
    /// <summary>الوصف الجديد (اختياري)</summary>
    public string? Description { get; set; }
    
    /// <summary>الفئة الجديدة (اختياري)</summary>
    public TransactionCategory? Category { get; set; }
    
    /// <summary>ملاحظات (اختياري)</summary>
    public string? Notes { get; set; }
}
