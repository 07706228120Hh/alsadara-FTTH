using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Sadara.Domain.Entities;
using Sadara.Domain.Enums;
using Sadara.Domain.Interfaces;

namespace Sadara.API.Controllers;

/// <summary>
/// نظام المحاسبة - شجرة الحسابات، القيود، الصندوق، الرواتب، التحصيلات، المصروفات
/// </summary>
[ApiController]
[Route("api/[controller]")]
[Authorize]
[Tags("Accounting")]
public class AccountingController : ControllerBase
{
    private readonly IUnitOfWork _unitOfWork;
    private readonly ILogger<AccountingController> _logger;

    public AccountingController(IUnitOfWork unitOfWork, ILogger<AccountingController> logger)
    {
        _unitOfWork = unitOfWork;
        _logger = logger;
    }

    // ==================== شجرة الحسابات - Chart of Accounts ====================

    /// <summary>
    /// جلب شجرة الحسابات
    /// </summary>
    [HttpGet("accounts")]
    public async Task<IActionResult> GetAccounts([FromQuery] Guid? companyId = null)
    {
        try
        {
            var query = _unitOfWork.Accounts.AsQueryable();
            if (companyId.HasValue)
                query = query.Where(a => a.CompanyId == companyId);

            var accounts = await query.OrderBy(a => a.Code).Select(a => new
            {
                a.Id,
                a.Code,
                a.Name,
                a.NameEn,
                AccountType = a.AccountType.ToString(),
                a.ParentAccountId,
                a.OpeningBalance,
                a.CurrentBalance,
                a.IsSystemAccount,
                a.Level,
                a.IsLeaf,
                a.IsActive,
                a.Description,
                a.CompanyId
            }).ToListAsync();

            return Ok(new { success = true, data = accounts, total = accounts.Count });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في جلب شجرة الحسابات");
            return StatusCode(500, new { success = false, message = "خطأ داخلي" });
        }
    }

    /// <summary>
    /// جلب شجرة الحسابات بشكل هرمي
    /// </summary>
    [HttpGet("accounts/tree")]
    public async Task<IActionResult> GetAccountsTree([FromQuery] Guid? companyId = null)
    {
        try
        {
            var query = _unitOfWork.Accounts.AsQueryable();
            if (companyId.HasValue)
                query = query.Where(a => a.CompanyId == companyId);

            var allAccounts = await query.OrderBy(a => a.Code).ToListAsync();
            var rootAccounts = allAccounts.Where(a => a.ParentAccountId == null).ToList();

            // حساب الرصيد التراكمي للشجرة الفرعية
            decimal CalculateSubtreeBalance(Account account, List<Account> all)
            {
                var children = all.Where(a => a.ParentAccountId == account.Id).ToList();
                if (!children.Any()) return account.CurrentBalance;
                return children.Sum(c => CalculateSubtreeBalance(c, all));
            }

            object BuildTree(Account account)
            {
                var children = allAccounts.Where(a => a.ParentAccountId == account.Id).ToList();
                var subtreeBalance = children.Any()
                    ? children.Sum(c => CalculateSubtreeBalance(c, allAccounts))
                    : account.CurrentBalance;
                return new
                {
                    account.Id,
                    account.Code,
                    account.Name,
                    account.NameEn,
                    AccountType = account.AccountType.ToString(),
                    account.OpeningBalance,
                    CurrentBalance = subtreeBalance,
                    account.IsLeaf,
                    account.IsActive,
                    account.Level,
                    account.Description,
                    Children = children.Select(c => BuildTree(c)).ToList()
                };
            }

            var tree = rootAccounts.Select(r => BuildTree(r)).ToList();
            return Ok(new { success = true, data = tree });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في جلب شجرة الحسابات الهرمية");
            return StatusCode(500, new { success = false, message = "خطأ داخلي" });
        }
    }

    /// <summary>
    /// إنشاء حساب جديد
    /// </summary>
    [HttpPost("accounts")]
    public async Task<IActionResult> CreateAccount([FromBody] CreateAccountDto dto)
    {
        try
        {
            // التحقق من عدم تكرار الكود
            var exists = await _unitOfWork.Accounts.AnyAsync(a => a.Code == dto.Code && a.CompanyId == dto.CompanyId);
            if (exists)
                return BadRequest(new { success = false, message = "كود الحساب موجود مسبقاً" });

            int level = 1;
            if (dto.ParentAccountId.HasValue)
            {
                var parent = await _unitOfWork.Accounts.GetByIdAsync(dto.ParentAccountId.Value);
                if (parent == null)
                    return BadRequest(new { success = false, message = "الحساب الأب غير موجود" });
                level = parent.Level + 1;

                // تحديث الأب ليصبح غير نهائي
                if (parent.IsLeaf)
                {
                    parent.IsLeaf = false;
                    _unitOfWork.Accounts.Update(parent);
                }
            }

            var account = new Account
            {
                Id = Guid.NewGuid(),
                Code = dto.Code,
                Name = dto.Name,
                NameEn = dto.NameEn,
                AccountType = dto.AccountType,
                ParentAccountId = dto.ParentAccountId,
                OpeningBalance = dto.OpeningBalance,
                CurrentBalance = dto.OpeningBalance,
                IsSystemAccount = false,
                Level = level,
                IsLeaf = true,
                IsActive = true,
                Description = dto.Description,
                CompanyId = dto.CompanyId
            };

            await _unitOfWork.Accounts.AddAsync(account);
            await _unitOfWork.SaveChangesAsync();

            return Ok(new { success = true, data = new { account.Id, account.Code, account.Name }, message = "تم إنشاء الحساب بنجاح" });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في إنشاء حساب");
            return StatusCode(500, new { success = false, message = "خطأ داخلي" });
        }
    }

    /// <summary>
    /// تعديل حساب
    /// </summary>
    [HttpPut("accounts/{id}")]
    public async Task<IActionResult> UpdateAccount(Guid id, [FromBody] UpdateAccountDto dto)
    {
        try
        {
            var account = await _unitOfWork.Accounts.GetByIdAsync(id);
            if (account == null)
                return NotFound(new { success = false, message = "الحساب غير موجود" });

            if (account.IsSystemAccount)
                return BadRequest(new { success = false, message = "لا يمكن تعديل حساب نظامي" });

            account.Name = dto.Name ?? account.Name;
            account.NameEn = dto.NameEn ?? account.NameEn;
            account.Description = dto.Description ?? account.Description;
            account.IsActive = dto.IsActive ?? account.IsActive;

            // تحديث الرصيد الافتتاحي مع تعديل الرصيد الحالي
            if (dto.OpeningBalance.HasValue)
            {
                var diff = dto.OpeningBalance.Value - account.OpeningBalance;
                account.OpeningBalance = dto.OpeningBalance.Value;
                account.CurrentBalance += diff;
            }

            _unitOfWork.Accounts.Update(account);
            await _unitOfWork.SaveChangesAsync();

            return Ok(new { success = true, message = "تم تحديث الحساب" });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في تعديل الحساب");
            return StatusCode(500, new { success = false, message = "خطأ داخلي" });
        }
    }

    /// <summary>
    /// حذف حساب (ناعم)
    /// </summary>
    [HttpDelete("accounts/{id}")]
    public async Task<IActionResult> DeleteAccount(Guid id)
    {
        try
        {
            var account = await _unitOfWork.Accounts.GetByIdAsync(id);
            if (account == null)
                return NotFound(new { success = false, message = "الحساب غير موجود" });

            if (account.IsSystemAccount)
                return BadRequest(new { success = false, message = "لا يمكن حذف حساب نظامي" });

            // التحقق من عدم وجود حسابات فرعية
            var hasChildren = await _unitOfWork.Accounts.AnyAsync(a => a.ParentAccountId == id);
            if (hasChildren)
                return BadRequest(new { success = false, message = "لا يمكن حذف حساب لديه حسابات فرعية" });

            // التحقق من عدم وجود قيود مرتبطة
            var hasEntries = await _unitOfWork.JournalEntryLines.AnyAsync(l => l.AccountId == id);
            if (hasEntries)
                return BadRequest(new { success = false, message = "لا يمكن حذف حساب له قيود محاسبية" });

            account.IsDeleted = true;
            account.DeletedAt = DateTime.UtcNow;
            _unitOfWork.Accounts.Update(account);
            await _unitOfWork.SaveChangesAsync();

            return Ok(new { success = true, message = "تم حذف الحساب" });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في حذف الحساب");
            return StatusCode(500, new { success = false, message = "خطأ داخلي" });
        }
    }

    /// <summary>
    /// تهيئة شجرة الحسابات الافتراضية لشركة
    /// </summary>
    [HttpPost("accounts/seed")]
    public async Task<IActionResult> SeedDefaultAccounts([FromBody] SeedAccountsDto dto)
    {
        try
        {
            var exists = await _unitOfWork.Accounts.AnyAsync(a => a.CompanyId == dto.CompanyId);
            if (exists)
                return BadRequest(new { success = false, message = "الشركة لديها حسابات بالفعل" });

            var accounts = GetDefaultAccounts(dto.CompanyId);
            foreach (var account in accounts)
                await _unitOfWork.Accounts.AddAsync(account);

            await _unitOfWork.SaveChangesAsync();
            return Ok(new { success = true, message = $"تم إنشاء {accounts.Count} حساب افتراضي", total = accounts.Count });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في تهيئة شجرة الحسابات");
            return StatusCode(500, new { success = false, message = "خطأ داخلي" });
        }
    }

    // ==================== القيود المحاسبية - Journal Entries ====================

    /// <summary>
    /// جلب القيود المحاسبية
    /// </summary>
    [HttpGet("journal-entries")]
    public async Task<IActionResult> GetJournalEntries(
        [FromQuery] Guid? companyId = null,
        [FromQuery] string? status = null,
        [FromQuery] DateTime? fromDate = null,
        [FromQuery] DateTime? toDate = null,
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 20)
    {
        try
        {
            var query = _unitOfWork.JournalEntries.AsQueryable();

            if (companyId.HasValue)
                query = query.Where(j => j.CompanyId == companyId);
            if (!string.IsNullOrEmpty(status) && Enum.TryParse<JournalEntryStatus>(status, true, out var st))
                query = query.Where(j => j.Status == st);
            if (fromDate.HasValue)
                query = query.Where(j => j.EntryDate >= fromDate.Value);
            if (toDate.HasValue)
                query = query.Where(j => j.EntryDate <= toDate.Value);

            var total = await query.CountAsync();
            var entries = await query
                .Include(j => j.Lines).ThenInclude(l => l.Account)
                .OrderByDescending(j => j.EntryDate)
                .ThenByDescending(j => j.CreatedAt)
                .Skip((page - 1) * pageSize)
                .Take(pageSize)
                .Select(j => new
                {
                    j.Id,
                    j.EntryNumber,
                    j.EntryDate,
                    j.Description,
                    j.TotalDebit,
                    j.TotalCredit,
                    ReferenceType = j.ReferenceType.ToString(),
                    j.ReferenceId,
                    Status = j.Status.ToString(),
                    j.Notes,
                    j.CompanyId,
                    j.CreatedById,
                    j.ApprovedById,
                    j.ApprovedAt,
                    j.CreatedAt,
                    Lines = j.Lines.Select(l => new
                    {
                        l.Id,
                        l.AccountId,
                        AccountCode = l.Account != null ? l.Account.Code : "",
                        AccountName = l.Account != null ? l.Account.Name : "",
                        l.DebitAmount,
                        l.CreditAmount,
                        l.Description,
                        l.EntityType,
                        l.EntityId
                    }).ToList()
                }).ToListAsync();

            return Ok(new { success = true, data = entries, total, page, pageSize });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في جلب القيود");
            return StatusCode(500, new { success = false, message = "خطأ داخلي" });
        }
    }

    /// <summary>
    /// جلب تفاصيل قيد مع سطوره
    /// </summary>
    [HttpGet("journal-entries/{id}")]
    public async Task<IActionResult> GetJournalEntry(Guid id)
    {
        try
        {
            var entry = await _unitOfWork.JournalEntries.AsQueryable()
                .Where(j => j.Id == id)
                .Select(j => new
                {
                    j.Id,
                    j.EntryNumber,
                    j.EntryDate,
                    j.Description,
                    j.TotalDebit,
                    j.TotalCredit,
                    ReferenceType = j.ReferenceType.ToString(),
                    j.ReferenceId,
                    Status = j.Status.ToString(),
                    j.Notes,
                    j.CompanyId,
                    j.CreatedById,
                    j.ApprovedById,
                    j.ApprovedAt,
                    j.CreatedAt,
                    Lines = j.Lines.Select(l => new
                    {
                        l.Id,
                        l.AccountId,
                        AccountCode = l.Account != null ? l.Account.Code : "",
                        AccountName = l.Account != null ? l.Account.Name : "",
                        l.DebitAmount,
                        l.CreditAmount,
                        l.Description,
                        l.EntityType,
                        l.EntityId
                    }).ToList()
                }).FirstOrDefaultAsync();

            if (entry == null)
                return NotFound(new { success = false, message = "القيد غير موجود" });

            return Ok(new { success = true, data = entry });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في جلب تفاصيل القيد");
            return StatusCode(500, new { success = false, message = "خطأ داخلي" });
        }
    }

    /// <summary>
    /// إنشاء قيد محاسبي يدوي
    /// </summary>
    [HttpPost("journal-entries")]
    public async Task<IActionResult> CreateJournalEntry([FromBody] CreateJournalEntryDto dto)
    {
        try
        {
            if (dto.Lines == null || dto.Lines.Count < 2)
                return BadRequest(new { success = false, message = "القيد يجب أن يحتوي على سطرين على الأقل" });

            var totalDebit = dto.Lines.Sum(l => l.DebitAmount);
            var totalCredit = dto.Lines.Sum(l => l.CreditAmount);

            if (Math.Abs(totalDebit - totalCredit) > 0.01m)
                return BadRequest(new { success = false, message = $"مجموع المدين ({totalDebit}) لا يساوي مجموع الدائن ({totalCredit})" });

            // توليد رقم القيد
            var entryNumber = await GenerateEntryNumber(dto.CompanyId);

            await _unitOfWork.BeginTransactionAsync();

            var entry = new JournalEntry
            {
                Id = Guid.NewGuid(),
                EntryNumber = entryNumber,
                EntryDate = dto.EntryDate ?? DateTime.UtcNow,
                Description = dto.Description,
                TotalDebit = totalDebit,
                TotalCredit = totalCredit,
                ReferenceType = JournalReferenceType.Manual,
                Status = JournalEntryStatus.Draft,
                Notes = dto.Notes,
                CompanyId = dto.CompanyId,
                CreatedById = dto.CreatedById
            };

            await _unitOfWork.JournalEntries.AddAsync(entry);

            foreach (var line in dto.Lines)
            {
                var entryLine = new JournalEntryLine
                {
                    JournalEntryId = entry.Id,
                    AccountId = line.AccountId,
                    DebitAmount = line.DebitAmount,
                    CreditAmount = line.CreditAmount,
                    Description = line.Description,
                    EntityType = line.EntityType,
                    EntityId = line.EntityId
                };
                await _unitOfWork.JournalEntryLines.AddAsync(entryLine);
            }

            await _unitOfWork.CommitTransactionAsync();
            return Ok(new { success = true, data = new { entry.Id, entry.EntryNumber }, message = "تم إنشاء القيد بنجاح" });
        }
        catch (Exception ex)
        {
            await _unitOfWork.RollbackTransactionAsync();
            _logger.LogError(ex, "خطأ في إنشاء القيد");
            return StatusCode(500, new { success = false, message = "خطأ داخلي" });
        }
    }

    /// <summary>
    /// اعتماد/ترحيل قيد - يحدّث أرصدة الحسابات
    /// </summary>
    [HttpPost("journal-entries/{id}/post")]
    public async Task<IActionResult> PostJournalEntry(Guid id, [FromBody] PostJournalEntryDto dto)
    {
        try
        {
            var entry = await _unitOfWork.JournalEntries.AsQueryable()
                .Include(j => j.Lines)
                .FirstOrDefaultAsync(j => j.Id == id);

            if (entry == null)
                return NotFound(new { success = false, message = "القيد غير موجود" });

            if (entry.Status != JournalEntryStatus.Draft)
                return BadRequest(new { success = false, message = "القيد مُعتمد بالفعل أو ملغي" });

            await _unitOfWork.BeginTransactionAsync();

            // تحديث أرصدة الحسابات
            foreach (var line in entry.Lines)
            {
                var account = await _unitOfWork.Accounts.GetByIdAsync(line.AccountId);
                if (account == null) continue;

                // الأصول والمصروفات: المدين يزيد، الدائن ينقص
                // الالتزامات والإيرادات وحقوق الملكية: الدائن يزيد، المدين ينقص
                if (account.AccountType == AccountType.Assets || account.AccountType == AccountType.Expenses)
                {
                    account.CurrentBalance += line.DebitAmount - line.CreditAmount;
                }
                else
                {
                    account.CurrentBalance += line.CreditAmount - line.DebitAmount;
                }

                _unitOfWork.Accounts.Update(account);
            }

            entry.Status = JournalEntryStatus.Posted;
            entry.ApprovedById = dto.ApprovedById;
            entry.ApprovedAt = DateTime.UtcNow;
            _unitOfWork.JournalEntries.Update(entry);

            await _unitOfWork.CommitTransactionAsync();
            return Ok(new { success = true, message = "تم اعتماد القيد وتحديث الأرصدة" });
        }
        catch (Exception ex)
        {
            await _unitOfWork.RollbackTransactionAsync();
            _logger.LogError(ex, "خطأ في اعتماد القيد");
            return StatusCode(500, new { success = false, message = "خطأ داخلي" });
        }
    }

    /// <summary>
    /// إلغاء قيد (عكس الأرصدة إذا كان مُعتمداً)
    /// </summary>
    [HttpPost("journal-entries/{id}/void")]
    public async Task<IActionResult> VoidJournalEntry(Guid id)
    {
        try
        {
            var entry = await _unitOfWork.JournalEntries.AsQueryable()
                .Include(j => j.Lines)
                .FirstOrDefaultAsync(j => j.Id == id);

            if (entry == null)
                return NotFound(new { success = false, message = "القيد غير موجود" });

            if (entry.Status == JournalEntryStatus.Voided)
                return BadRequest(new { success = false, message = "القيد ملغي بالفعل" });

            await _unitOfWork.BeginTransactionAsync();

            // عكس الأرصدة إذا كان مُعتمداً
            if (entry.Status == JournalEntryStatus.Posted)
            {
                foreach (var line in entry.Lines)
                {
                    var account = await _unitOfWork.Accounts.GetByIdAsync(line.AccountId);
                    if (account == null) continue;

                    if (account.AccountType == AccountType.Assets || account.AccountType == AccountType.Expenses)
                    {
                        account.CurrentBalance -= line.DebitAmount - line.CreditAmount;
                    }
                    else
                    {
                        account.CurrentBalance -= line.CreditAmount - line.DebitAmount;
                    }

                    _unitOfWork.Accounts.Update(account);
                }
            }

            entry.Status = JournalEntryStatus.Voided;
            _unitOfWork.JournalEntries.Update(entry);

            await _unitOfWork.CommitTransactionAsync();
            return Ok(new { success = true, message = "تم إلغاء القيد" });
        }
        catch (Exception ex)
        {
            await _unitOfWork.RollbackTransactionAsync();
            _logger.LogError(ex, "خطأ في إلغاء القيد");
            return StatusCode(500, new { success = false, message = "خطأ داخلي" });
        }
    }

    // ==================== الصندوق / القاصة - Cash Box ====================

    /// <summary>
    /// جلب صناديق الشركة
    /// </summary>
    [HttpGet("cashboxes")]
    public async Task<IActionResult> GetCashBoxes([FromQuery] Guid? companyId = null)
    {
        try
        {
            var query = _unitOfWork.CashBoxes.AsQueryable();
            if (companyId.HasValue)
                query = query.Where(c => c.CompanyId == companyId);

            var boxes = await query.OrderBy(c => c.Name).Select(c => new
            {
                c.Id,
                c.Name,
                CashBoxType = c.CashBoxType.ToString(),
                c.CurrentBalance,
                c.IsActive,
                c.ResponsibleUserId,
                c.LinkedAccountId,
                c.Notes,
                c.CompanyId,
                c.CreatedAt
            }).ToListAsync();

            return Ok(new { success = true, data = boxes });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في جلب الصناديق");
            return StatusCode(500, new { success = false, message = "خطأ داخلي" });
        }
    }

    /// <summary>
    /// إنشاء صندوق جديد
    /// </summary>
    [HttpPost("cashboxes")]
    public async Task<IActionResult> CreateCashBox([FromBody] CreateCashBoxDto dto)
    {
        try
        {
            // البحث عن حساب النقد و الصندوق (1110) الأب
            var parentCashAccount = await FindAccountByCode("1110", dto.CompanyId);
            
            // إنشاء حساب فرعي تحت 1110 لهذا الصندوق
            Guid? subAccountId = null;
            if (parentCashAccount != null)
            {
                // توليد كود فرعي: 1110 + أول رقم متاح
                var existingSubs = await _unitOfWork.Accounts.AsQueryable()
                    .Where(a => a.ParentAccountId == parentCashAccount.Id && a.CompanyId == dto.CompanyId)
                    .OrderBy(a => a.Code)
                    .ToListAsync();
                
                int nextNum = existingSubs.Count + 1;
                string subCode = $"1110{nextNum}";
                // تأكد أن الكود غير مكرر
                while (await _unitOfWork.Accounts.AnyAsync(a => a.Code == subCode && a.CompanyId == dto.CompanyId))
                {
                    nextNum++;
                    subCode = $"1110{nextNum}";
                }

                var subAccount = new Account
                {
                    Id = Guid.NewGuid(),
                    Code = subCode,
                    Name = $"صندوق: {dto.Name}",
                    NameEn = $"Cash Box: {dto.Name}",
                    AccountType = AccountType.Assets,
                    ParentAccountId = parentCashAccount.Id,
                    OpeningBalance = dto.InitialBalance,
                    CurrentBalance = dto.InitialBalance,
                    IsSystemAccount = false,
                    Level = parentCashAccount.Level + 1,
                    IsLeaf = true,
                    IsActive = true,
                    Description = $"حساب فرعي مرتبط بصندوق {dto.Name}",
                    CompanyId = dto.CompanyId
                };

                // تحديث الأب ليصبح غير نهائي
                if (parentCashAccount.IsLeaf)
                {
                    parentCashAccount.IsLeaf = false;
                    _unitOfWork.Accounts.Update(parentCashAccount);
                }

                await _unitOfWork.Accounts.AddAsync(subAccount);
                subAccountId = subAccount.Id;
            }

            var box = new CashBox
            {
                Id = Guid.NewGuid(),
                Name = dto.Name,
                CashBoxType = dto.CashBoxType,
                CurrentBalance = dto.InitialBalance,
                IsActive = true,
                ResponsibleUserId = dto.ResponsibleUserId,
                LinkedAccountId = subAccountId ?? dto.LinkedAccountId,
                Notes = dto.Notes,
                CompanyId = dto.CompanyId
            };

            await _unitOfWork.CashBoxes.AddAsync(box);
            await _unitOfWork.SaveChangesAsync();

            return Ok(new { success = true, data = new { box.Id, box.Name, LinkedAccountId = subAccountId }, message = "تم إنشاء الصندوق وحسابه الفرعي تحت النقد و الصندوق" });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في إنشاء صندوق");
            return StatusCode(500, new { success = false, message = "خطأ داخلي" });
        }
    }

    /// <summary>
    /// جلب حركات صندوق معين
    /// </summary>
    [HttpGet("cashboxes/{id}/transactions")]
    public async Task<IActionResult> GetCashTransactions(
        Guid id,
        [FromQuery] DateTime? fromDate = null,
        [FromQuery] DateTime? toDate = null,
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 20)
    {
        try
        {
            var query = _unitOfWork.CashTransactions.AsQueryable()
                .Where(t => t.CashBoxId == id);

            if (fromDate.HasValue)
                query = query.Where(t => t.CreatedAt >= fromDate.Value);
            if (toDate.HasValue)
                query = query.Where(t => t.CreatedAt <= toDate.Value);

            var total = await query.CountAsync();
            var transactions = await query
                .OrderByDescending(t => t.CreatedAt)
                .Skip((page - 1) * pageSize)
                .Take(pageSize)
                .Select(t => new
                {
                    t.Id,
                    t.CashBoxId,
                    TransactionType = t.TransactionType.ToString(),
                    t.Amount,
                    t.BalanceAfter,
                    t.Description,
                    t.JournalEntryId,
                    ReferenceType = t.ReferenceType.ToString(),
                    t.ReferenceId,
                    t.CreatedById,
                    t.CreatedAt
                }).ToListAsync();

            return Ok(new { success = true, data = transactions, total, page, pageSize });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في جلب حركات الصندوق");
            return StatusCode(500, new { success = false, message = "خطأ داخلي" });
        }
    }

    /// <summary>
    /// إيداع في الصندوق
    /// </summary>
    [HttpPost("cashboxes/{id}/deposit")]
    public async Task<IActionResult> DepositToCashBox(Guid id, [FromBody] CashBoxOperationDto dto)
    {
        try
        {
            var box = await _unitOfWork.CashBoxes.GetByIdAsync(id);
            if (box == null)
                return NotFound(new { success = false, message = "الصندوق غير موجود" });

            await _unitOfWork.BeginTransactionAsync();

            box.CurrentBalance += dto.Amount;
            _unitOfWork.CashBoxes.Update(box);

            var transaction = new CashTransaction
            {
                CashBoxId = id,
                TransactionType = CashTransactionType.Deposit,
                Amount = dto.Amount,
                BalanceAfter = box.CurrentBalance,
                Description = dto.Description ?? "إيداع",
                ReferenceType = dto.ReferenceType,
                ReferenceId = dto.ReferenceId,
                CreatedById = dto.CreatedById
            };

            await _unitOfWork.CashTransactions.AddAsync(transaction);
            await _unitOfWork.CommitTransactionAsync();

            return Ok(new { success = true, message = "تم الإيداع", newBalance = box.CurrentBalance });
        }
        catch (Exception ex)
        {
            await _unitOfWork.RollbackTransactionAsync();
            _logger.LogError(ex, "خطأ في الإيداع");
            return StatusCode(500, new { success = false, message = "خطأ داخلي" });
        }
    }

    /// <summary>
    /// سحب من الصندوق
    /// </summary>
    [HttpPost("cashboxes/{id}/withdraw")]
    public async Task<IActionResult> WithdrawFromCashBox(Guid id, [FromBody] CashBoxOperationDto dto)
    {
        try
        {
            var box = await _unitOfWork.CashBoxes.GetByIdAsync(id);
            if (box == null)
                return NotFound(new { success = false, message = "الصندوق غير موجود" });

            if (box.CurrentBalance < dto.Amount)
                return BadRequest(new { success = false, message = "رصيد الصندوق غير كافي" });

            await _unitOfWork.BeginTransactionAsync();

            box.CurrentBalance -= dto.Amount;
            _unitOfWork.CashBoxes.Update(box);

            var transaction = new CashTransaction
            {
                CashBoxId = id,
                TransactionType = CashTransactionType.Withdrawal,
                Amount = dto.Amount,
                BalanceAfter = box.CurrentBalance,
                Description = dto.Description ?? "سحب",
                ReferenceType = dto.ReferenceType,
                ReferenceId = dto.ReferenceId,
                CreatedById = dto.CreatedById
            };

            await _unitOfWork.CashTransactions.AddAsync(transaction);
            await _unitOfWork.CommitTransactionAsync();

            return Ok(new { success = true, message = "تم السحب", newBalance = box.CurrentBalance });
        }
        catch (Exception ex)
        {
            await _unitOfWork.RollbackTransactionAsync();
            _logger.LogError(ex, "خطأ في السحب");
            return StatusCode(500, new { success = false, message = "خطأ داخلي" });
        }
    }

    // ==================== رواتب الموظفين - Employee Salaries ====================

    /// <summary>
    /// جلب رواتب شهر معين
    /// </summary>
    [HttpGet("salaries")]
    public async Task<IActionResult> GetSalaries(
        [FromQuery] Guid? companyId = null,
        [FromQuery] int? month = null,
        [FromQuery] int? year = null,
        [FromQuery] string? status = null)
    {
        try
        {
            var query = _unitOfWork.EmployeeSalaries.AsQueryable();

            if (companyId.HasValue)
                query = query.Where(s => s.CompanyId == companyId);
            if (month.HasValue)
                query = query.Where(s => s.Month == month);
            if (year.HasValue)
                query = query.Where(s => s.Year == year);
            if (!string.IsNullOrEmpty(status) && Enum.TryParse<SalaryStatus>(status, true, out var st))
                query = query.Where(s => s.Status == st);

            var salaries = await query
                .OrderByDescending(s => s.Year)
                .ThenByDescending(s => s.Month)
                .Select(s => new
                {
                    s.Id,
                    s.UserId,
                    UserName = s.User != null ? s.User.FullName : "",
                    s.Month,
                    s.Year,
                    s.BaseSalary,
                    s.Allowances,
                    s.Deductions,
                    s.Bonuses,
                    s.NetSalary,
                    Status = s.Status.ToString(),
                    s.PaidAt,
                    s.JournalEntryId,
                    s.Notes,
                    s.CompanyId
                }).ToListAsync();

            var summary = new
            {
                TotalBaseSalary = salaries.Sum(s => s.BaseSalary),
                TotalAllowances = salaries.Sum(s => s.Allowances),
                TotalDeductions = salaries.Sum(s => s.Deductions),
                TotalBonuses = salaries.Sum(s => s.Bonuses),
                TotalNet = salaries.Sum(s => s.NetSalary),
                Count = salaries.Count
            };

            return Ok(new { success = true, data = salaries, summary });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في جلب الرواتب");
            return StatusCode(500, new { success = false, message = "خطأ داخلي" });
        }
    }

    /// <summary>
    /// إنشاء مسيّر رواتب شهري (لجميع موظفي الشركة)
    /// </summary>
    [HttpPost("salaries/generate")]
    public async Task<IActionResult> GenerateMonthlySalaries([FromBody] GenerateSalariesDto dto)
    {
        try
        {
            // التحقق من عدم وجود مسيّر مسبق
            var exists = await _unitOfWork.EmployeeSalaries.AnyAsync(
                s => s.CompanyId == dto.CompanyId && s.Month == dto.Month && s.Year == dto.Year);
            if (exists)
                return BadRequest(new { success = false, message = "مسيّر الرواتب لهذا الشهر موجود مسبقاً" });

            // جلب موظفي الشركة الذين لديهم رواتب
            var employees = await _unitOfWork.Users.AsQueryable()
                .Where(u => u.CompanyId == dto.CompanyId && u.IsActive && u.Salary.HasValue && u.Salary > 0)
                .ToListAsync();

            if (!employees.Any())
                return BadRequest(new { success = false, message = "لا يوجد موظفون بالشركة لهم رواتب محددة" });

            var salaries = new List<EmployeeSalary>();
            foreach (var emp in employees)
            {
                var salary = new EmployeeSalary
                {
                    UserId = emp.Id,
                    Month = dto.Month,
                    Year = dto.Year,
                    BaseSalary = emp.Salary ?? 0,
                    Allowances = 0,
                    Deductions = 0,
                    Bonuses = 0,
                    NetSalary = emp.Salary ?? 0,
                    Status = SalaryStatus.Pending,
                    CompanyId = dto.CompanyId
                };
                salaries.Add(salary);
                await _unitOfWork.EmployeeSalaries.AddAsync(salary);
            }

            await _unitOfWork.SaveChangesAsync();
            return Ok(new
            {
                success = true,
                message = $"تم إنشاء مسيّر رواتب لـ {salaries.Count} موظف",
                total = salaries.Count,
                totalAmount = salaries.Sum(s => s.NetSalary)
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في إنشاء مسيّر الرواتب");
            return StatusCode(500, new { success = false, message = "خطأ داخلي" });
        }
    }

    /// <summary>
    /// تعديل سطر راتب (بدلات، خصومات، مكافآت)
    /// </summary>
    [HttpPut("salaries/{id}")]
    public async Task<IActionResult> UpdateSalary(long id, [FromBody] UpdateSalaryDto dto)
    {
        try
        {
            var salary = await _unitOfWork.EmployeeSalaries.GetByIdAsync(id);
            if (salary == null)
                return NotFound(new { success = false, message = "سجل الراتب غير موجود" });

            if (salary.Status == SalaryStatus.Paid)
                return BadRequest(new { success = false, message = "لا يمكن تعديل راتب تم صرفه" });

            salary.BaseSalary = dto.BaseSalary ?? salary.BaseSalary;
            salary.Allowances = dto.Allowances ?? salary.Allowances;
            salary.Deductions = dto.Deductions ?? salary.Deductions;
            salary.Bonuses = dto.Bonuses ?? salary.Bonuses;
            salary.Notes = dto.Notes ?? salary.Notes;
            salary.NetSalary = salary.BaseSalary + salary.Allowances + salary.Bonuses - salary.Deductions;

            _unitOfWork.EmployeeSalaries.Update(salary);
            await _unitOfWork.SaveChangesAsync();

            return Ok(new { success = true, message = "تم تحديث الراتب", netSalary = salary.NetSalary });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في تعديل الراتب");
            return StatusCode(500, new { success = false, message = "خطأ داخلي" });
        }
    }

    /// <summary>
    /// صرف راتب (تحديث الحالة وإنشاء حركة صندوق)
    /// </summary>
    [HttpPost("salaries/{id}/pay")]
    public async Task<IActionResult> PaySalary(long id, [FromBody] PaySalaryDto dto)
    {
        try
        {
            var salary = await _unitOfWork.EmployeeSalaries.GetByIdAsync(id);
            if (salary == null)
                return NotFound(new { success = false, message = "سجل الراتب غير موجود" });

            if (salary.Status == SalaryStatus.Paid)
                return BadRequest(new { success = false, message = "الراتب مصروف بالفعل" });

            await _unitOfWork.BeginTransactionAsync();

            // خصم من الصندوق إذا محدد
            if (dto.CashBoxId.HasValue)
            {
                var box = await _unitOfWork.CashBoxes.GetByIdAsync(dto.CashBoxId.Value);
                if (box == null)
                    return BadRequest(new { success = false, message = "الصندوق غير موجود" });

                if (box.CurrentBalance < salary.NetSalary)
                    return BadRequest(new { success = false, message = "رصيد الصندوق غير كافي" });

                box.CurrentBalance -= salary.NetSalary;
                _unitOfWork.CashBoxes.Update(box);

                var cashTx = new CashTransaction
                {
                    CashBoxId = box.Id,
                    TransactionType = CashTransactionType.Withdrawal,
                    Amount = salary.NetSalary,
                    BalanceAfter = box.CurrentBalance,
                    Description = $"صرف راتب - {salary.Month}/{salary.Year}",
                    ReferenceType = JournalReferenceType.Salary,
                    ReferenceId = salary.Id.ToString(),
                    CreatedById = dto.PaidById
                };
                await _unitOfWork.CashTransactions.AddAsync(cashTx);
            }

            salary.Status = SalaryStatus.Paid;
            salary.PaidAt = DateTime.UtcNow;
            _unitOfWork.EmployeeSalaries.Update(salary);

            // === إنشاء قيد محاسبي تلقائي للراتب ===
            // مدين: حساب فرعي للموظف تحت 5100
            // دائن: حساب النقدية 1110
            var cashAcctSal = await FindAccountByCode("1110", salary.CompanyId);
            if (cashAcctSal != null)
            {
                // جلب اسم الموظف
                var empUser = await _unitOfWork.Users.GetByIdAsync(salary.UserId);
                var empName = empUser?.FullName ?? "موظف";
                var empSubAcct = await FindOrCreateSubAccount("5100", salary.UserId, empName, salary.CompanyId);

                var journalLines = new List<(Guid AccountId, decimal DebitAmount, decimal CreditAmount, string? LineDescription)>
                {
                    (empSubAcct.Id, salary.NetSalary, 0, $"راتب {empName} - {salary.Month}/{salary.Year}"),
                    (cashAcctSal.Id, 0, salary.NetSalary, $"صرف راتب {empName} من النقدية {salary.Month}/{salary.Year}")
                };
                await CreateAndPostJournalEntry(
                    salary.CompanyId, dto.PaidById,
                    $"صرف راتب {empName} - {salary.Month}/{salary.Year}",
                    JournalReferenceType.Salary, salary.Id.ToString(),
                    journalLines);
            }

            await _unitOfWork.CommitTransactionAsync();
            return Ok(new { success = true, message = "تم صرف الراتب" });
        }
        catch (Exception ex)
        {
            await _unitOfWork.RollbackTransactionAsync();
            _logger.LogError(ex, "خطأ في صرف الراتب");
            return StatusCode(500, new { success = false, message = "خطأ داخلي" });
        }
    }

    /// <summary>
    /// صرف جميع رواتب شهر دفعة واحدة
    /// </summary>
    [HttpPost("salaries/pay-all")]
    public async Task<IActionResult> PayAllSalaries([FromBody] PayAllSalariesDto dto)
    {
        try
        {
            var pending = await _unitOfWork.EmployeeSalaries.AsQueryable()
                .Where(s => s.CompanyId == dto.CompanyId && s.Month == dto.Month && s.Year == dto.Year && s.Status == SalaryStatus.Pending)
                .ToListAsync();

            if (!pending.Any())
                return BadRequest(new { success = false, message = "لا توجد رواتب بانتظار الصرف" });

            var totalAmount = pending.Sum(s => s.NetSalary);

            await _unitOfWork.BeginTransactionAsync();

            if (dto.CashBoxId.HasValue)
            {
                var box = await _unitOfWork.CashBoxes.GetByIdAsync(dto.CashBoxId.Value);
                if (box == null)
                    return BadRequest(new { success = false, message = "الصندوق غير موجود" });

                if (box.CurrentBalance < totalAmount)
                    return BadRequest(new { success = false, message = $"رصيد الصندوق ({box.CurrentBalance}) غير كافي لصرف ({totalAmount})" });

                box.CurrentBalance -= totalAmount;
                _unitOfWork.CashBoxes.Update(box);

                var cashTx = new CashTransaction
                {
                    CashBoxId = box.Id,
                    TransactionType = CashTransactionType.Withdrawal,
                    Amount = totalAmount,
                    BalanceAfter = box.CurrentBalance,
                    Description = $"صرف رواتب شهر {dto.Month}/{dto.Year} - {pending.Count} موظف",
                    ReferenceType = JournalReferenceType.Salary,
                    ReferenceId = $"{dto.Year}-{dto.Month:D2}",
                    CreatedById = dto.PaidById
                };
                await _unitOfWork.CashTransactions.AddAsync(cashTx);
            }

            foreach (var salary in pending)
            {
                salary.Status = SalaryStatus.Paid;
                salary.PaidAt = DateTime.UtcNow;
                _unitOfWork.EmployeeSalaries.Update(salary);
            }

            // === إنشاء قيد محاسبي تلقائي لجميع الرواتب ===
            // مدين: حساب فرعي لكل موظف تحت 5100
            // دائن: حساب النقدية 1110
            var cashAcctAll = await FindAccountByCode("1110", dto.CompanyId);
            if (cashAcctAll != null)
            {
                var journalLines = new List<(Guid AccountId, decimal DebitAmount, decimal CreditAmount, string? LineDescription)>();

                // سطر مدين لكل موظف بحسابه الفرعي
                foreach (var sal in pending)
                {
                    var empUser = await _unitOfWork.Users.GetByIdAsync(sal.UserId);
                    var empName = empUser?.FullName ?? "موظف";
                    var empSubAcct = await FindOrCreateSubAccount("5100", sal.UserId, empName, dto.CompanyId);
                    journalLines.Add((empSubAcct.Id, sal.NetSalary, 0, $"راتب {empName} - {dto.Month}/{dto.Year}"));
                }

                // سطر دائن واحد بإجمالي المبلغ من النقدية
                journalLines.Add((cashAcctAll.Id, 0, totalAmount, $"صرف رواتب {pending.Count} موظف - {dto.Month}/{dto.Year}"));

                await CreateAndPostJournalEntry(
                    dto.CompanyId, dto.PaidById,
                    $"صرف رواتب جماعي - شهر {dto.Month}/{dto.Year} ({pending.Count} موظف)",
                    JournalReferenceType.Salary, $"{dto.Year}-{dto.Month:D2}",
                    journalLines);
            }

            await _unitOfWork.CommitTransactionAsync();
            return Ok(new { success = true, message = $"تم صرف {pending.Count} راتب بإجمالي {totalAmount}", count = pending.Count, totalAmount });
        }
        catch (Exception ex)
        {
            await _unitOfWork.RollbackTransactionAsync();
            _logger.LogError(ex, "خطأ في صرف الرواتب الجماعي");
            return StatusCode(500, new { success = false, message = "خطأ داخلي" });
        }
    }

    // ==================== تحصيلات الفنيين - Technician Collections ====================

    /// <summary>
    /// جلب التحصيلات
    /// </summary>
    [HttpGet("collections")]
    public async Task<IActionResult> GetCollections(
        [FromQuery] Guid? companyId = null,
        [FromQuery] Guid? technicianId = null,
        [FromQuery] bool? isDelivered = null,
        [FromQuery] DateTime? fromDate = null,
        [FromQuery] DateTime? toDate = null,
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 20)
    {
        try
        {
            var query = _unitOfWork.TechnicianCollections.AsQueryable();

            if (companyId.HasValue)
                query = query.Where(c => c.CompanyId == companyId);
            if (technicianId.HasValue)
                query = query.Where(c => c.TechnicianId == technicianId);
            if (isDelivered.HasValue)
                query = query.Where(c => c.IsDelivered == isDelivered);
            if (fromDate.HasValue)
                query = query.Where(c => c.CollectionDate >= fromDate);
            if (toDate.HasValue)
                query = query.Where(c => c.CollectionDate <= toDate);

            var total = await query.CountAsync();
            var collections = await query
                .OrderByDescending(c => c.CollectionDate)
                .Skip((page - 1) * pageSize)
                .Take(pageSize)
                .Select(c => new
                {
                    c.Id,
                    c.TechnicianId,
                    TechnicianName = c.Technician != null ? c.Technician.FullName : "",
                    c.CitizenId,
                    c.ServiceRequestId,
                    c.Amount,
                    c.CollectionDate,
                    c.IsDelivered,
                    c.DeliveredAt,
                    c.DeliveredToUserId,
                    DeliveredToName = c.DeliveredToUser != null ? c.DeliveredToUser.FullName : "",
                    PaymentMethod = c.PaymentMethod.ToString(),
                    c.ReceiptNumber,
                    c.ReceivedBy,
                    c.Description,
                    c.Notes,
                    c.CompanyId,
                    c.JournalEntryId,
                    JournalEntryNumber = c.JournalEntry != null ? c.JournalEntry.EntryNumber : null,
                    c.CreatedAt
                }).ToListAsync();

            var summary = new
            {
                TotalCollected = collections.Sum(c => c.Amount),
                TotalDelivered = collections.Where(c => c.IsDelivered).Sum(c => c.Amount),
                TotalPending = collections.Where(c => !c.IsDelivered).Sum(c => c.Amount),
                Count = total
            };

            return Ok(new { success = true, data = collections, summary, total, page, pageSize });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في جلب التحصيلات");
            return StatusCode(500, new { success = false, message = "خطأ داخلي" });
        }
    }

    /// <summary>
    /// تسجيل تحصيل جديد
    /// </summary>
    [HttpPost("collections")]
    public async Task<IActionResult> CreateCollection([FromBody] CreateCollectionDto dto)
    {
        try
        {
            var collection = new TechnicianCollection
            {
                TechnicianId = dto.TechnicianId,
                CitizenId = dto.CitizenId,
                ServiceRequestId = dto.ServiceRequestId,
                Amount = dto.Amount,
                CollectionDate = dto.CollectionDate ?? DateTime.UtcNow,
                IsDelivered = false,
                Description = dto.Description,
                Notes = dto.Notes,
                PaymentMethod = dto.PaymentMethod,
                ReceiptNumber = dto.ReceiptNumber,
                ReceivedBy = dto.ReceivedBy,
                CompanyId = dto.CompanyId
            };

            await _unitOfWork.TechnicianCollections.AddAsync(collection);

            // ── تحديث رصيد الفني وتسجيل معاملة تسديد في نظام المستحقات ──
            var technician = await _unitOfWork.Users.GetByIdAsync(dto.TechnicianId);
            if (technician != null)
            {
                technician.TechTotalPayments += dto.Amount;
                technician.TechNetBalance = technician.TechTotalPayments - technician.TechTotalCharges;
                _unitOfWork.Users.Update(technician);

                var currentUserId = Guid.Empty;
                var userIdClaim = User.FindFirst(System.Security.Claims.ClaimTypes.NameIdentifier)?.Value
                               ?? User.FindFirst("sub")?.Value;
                if (!string.IsNullOrEmpty(userIdClaim))
                    Guid.TryParse(userIdClaim, out currentUserId);

                var tx = new TechnicianTransaction
                {
                    TechnicianId = technician.Id,
                    Type = TechnicianTransactionType.Payment,
                    Category = TechnicianTransactionCategory.CashPayment,
                    Amount = dto.Amount,
                    BalanceAfter = technician.TechNetBalance,
                    Description = dto.Description ?? "تحصيل نقدي",
                    ReferenceNumber = dto.ReceiptNumber ?? $"{DateTime.UtcNow:yyMMddHHmm}{Random.Shared.Next(1000, 9999)}",
                    Notes = dto.Notes,
                    ReceivedBy = dto.ReceivedBy,
                    CreatedById = currentUserId,
                    CompanyId = dto.CompanyId,
                    CreatedAt = DateTime.UtcNow
                };
                await _unitOfWork.TechnicianTransactions.AddAsync(tx);
            }

            await _unitOfWork.SaveChangesAsync();

            return Ok(new { success = true, data = new { collection.Id }, message = "تم تسجيل التحصيل وتحديث رصيد الفني" });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في تسجيل التحصيل");
            return StatusCode(500, new { success = false, message = "خطأ داخلي" });
        }
    }

    /// <summary>
    /// تسليم تحصيل للصندوق
    /// </summary>
    [HttpPost("collections/{id}/deliver")]
    public async Task<IActionResult> DeliverCollection(long id, [FromBody] DeliverCollectionDto dto)
    {
        try
        {
            var collection = await _unitOfWork.TechnicianCollections.GetByIdAsync(id);
            if (collection == null)
                return NotFound(new { success = false, message = "التحصيل غير موجود" });

            if (collection.IsDelivered)
                return BadRequest(new { success = false, message = "التحصيل مُسلّم بالفعل" });

            await _unitOfWork.BeginTransactionAsync();

            collection.IsDelivered = true;
            collection.DeliveredAt = DateTime.UtcNow;
            collection.DeliveredToUserId = dto.DeliveredToUserId;
            collection.CashBoxId = dto.CashBoxId;
            _unitOfWork.TechnicianCollections.Update(collection);

            // إيداع في الصندوق
            if (dto.CashBoxId.HasValue)
            {
                var box = await _unitOfWork.CashBoxes.GetByIdAsync(dto.CashBoxId.Value);
                if (box != null)
                {
                    box.CurrentBalance += collection.Amount;
                    _unitOfWork.CashBoxes.Update(box);

                    var cashTx = new CashTransaction
                    {
                        CashBoxId = box.Id,
                        TransactionType = CashTransactionType.Deposit,
                        Amount = collection.Amount,
                        BalanceAfter = box.CurrentBalance,
                        Description = $"تسليم تحصيل فني - #{collection.Id}",
                        ReferenceType = JournalReferenceType.TechnicianCollection,
                        ReferenceId = collection.Id.ToString(),
                        CreatedById = dto.DeliveredToUserId
                    };
                    await _unitOfWork.CashTransactions.AddAsync(cashTx);
                }
            }

            // === إنشاء قيد محاسبي تلقائي لتسليم التحصيل ===
            // مدين: حساب النقدية 1110 (استلمنا كاش من الفني)
            // دائن: حساب ذمم الفنيين 1140-sub (إقفال مستحقات الفني)
            // ملاحظة: الإيراد سُجّل مسبقاً عند تفعيل الاشتراك (Dr 1140 / Cr 4110|4120)
            var technician = await _unitOfWork.Users.GetByIdAsync(collection.TechnicianId);
            var cashAcct = await FindAccountByCode("1110", collection.CompanyId);
            var techSubAcct = await FindOrCreateSubAccount(
                "1140", collection.TechnicianId,
                technician?.FullName ?? "فني", collection.CompanyId);
            if (cashAcct != null)
            {
                var journalLines = new List<(Guid AccountId, decimal DebitAmount, decimal CreditAmount, string? LineDescription)>
                {
                    (cashAcct.Id, collection.Amount, 0, $"تسليم تحصيل فني #{collection.Id}"),
                    (techSubAcct.Id, 0, collection.Amount, $"إقفال ذمة فني #{collection.Id}")
                };
                await CreateAndPostJournalEntry(
                    collection.CompanyId, dto.DeliveredToUserId,
                    $"تسليم تحصيل فني #{collection.Id}",
                    JournalReferenceType.TechnicianCollection, collection.Id.ToString(),
                    journalLines);
            }

            await _unitOfWork.CommitTransactionAsync();
            return Ok(new { success = true, message = "تم تسليم التحصيل" });
        }
        catch (Exception ex)
        {
            await _unitOfWork.RollbackTransactionAsync();
            _logger.LogError(ex, "خطأ في تسليم التحصيل");
            return StatusCode(500, new { success = false, message = "خطأ داخلي" });
        }
    }

    /// <summary>
    /// ملخص تحصيلات فني معين
    /// </summary>
    [HttpGet("collections/technician/{technicianId}/summary")]
    public async Task<IActionResult> GetTechnicianCollectionSummary(Guid technicianId)
    {
        try
        {
            var collections = await _unitOfWork.TechnicianCollections.AsQueryable()
                .Where(c => c.TechnicianId == technicianId)
                .ToListAsync();

            var summary = new
            {
                TechnicianId = technicianId,
                TotalCollected = collections.Sum(c => c.Amount),
                TotalDelivered = collections.Where(c => c.IsDelivered).Sum(c => c.Amount),
                PendingAmount = collections.Where(c => !c.IsDelivered).Sum(c => c.Amount),
                PendingCount = collections.Count(c => !c.IsDelivered),
                TotalCount = collections.Count
            };

            return Ok(new { success = true, data = summary });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في ملخص التحصيلات");
            return StatusCode(500, new { success = false, message = "خطأ داخلي" });
        }
    }

    // ==================== المصروفات - Expenses ====================

    /// <summary>
    /// جلب المصروفات
    /// </summary>
    [HttpGet("expenses")]
    public async Task<IActionResult> GetExpenses(
        [FromQuery] Guid? companyId = null,
        [FromQuery] string? category = null,
        [FromQuery] DateTime? fromDate = null,
        [FromQuery] DateTime? toDate = null,
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 20)
    {
        try
        {
            var query = _unitOfWork.Expenses.AsQueryable();

            if (companyId.HasValue)
                query = query.Where(e => e.CompanyId == companyId);
            if (!string.IsNullOrEmpty(category))
                query = query.Where(e => e.Category == category);
            if (fromDate.HasValue)
                query = query.Where(e => e.ExpenseDate >= fromDate);
            if (toDate.HasValue)
                query = query.Where(e => e.ExpenseDate <= toDate);

            var total = await query.CountAsync();
            var expenses = await query
                .OrderByDescending(e => e.ExpenseDate)
                .Skip((page - 1) * pageSize)
                .Take(pageSize)
                .Select(e => new
                {
                    e.Id,
                    e.AccountId,
                    AccountName = e.Account != null ? e.Account.Name : "",
                    e.Amount,
                    e.Description,
                    e.ExpenseDate,
                    e.Category,
                    e.JournalEntryId,
                    e.PaidFromCashBoxId,
                    e.CreatedById,
                    e.AttachmentUrl,
                    e.Notes,
                    e.CompanyId,
                    e.CreatedAt
                }).ToListAsync();

            var totalAmount = await query.SumAsync(e => e.Amount);

            return Ok(new { success = true, data = expenses, total, totalAmount, page, pageSize });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في جلب المصروفات");
            return StatusCode(500, new { success = false, message = "خطأ داخلي" });
        }
    }

    /// <summary>
    /// تسجيل مصروف جديد
    /// </summary>
    [HttpPost("expenses")]
    public async Task<IActionResult> CreateExpense([FromBody] CreateExpenseDto dto)
    {
        try
        {
            await _unitOfWork.BeginTransactionAsync();

            var expense = new Expense
            {
                AccountId = dto.AccountId,
                Amount = dto.Amount,
                Description = dto.Description,
                ExpenseDate = dto.ExpenseDate ?? DateTime.UtcNow,
                Category = dto.Category,
                PaidFromCashBoxId = dto.PaidFromCashBoxId,
                CreatedById = dto.CreatedById,
                AttachmentUrl = dto.AttachmentUrl,
                Notes = dto.Notes,
                CompanyId = dto.CompanyId
            };

            await _unitOfWork.Expenses.AddAsync(expense);

            // خصم من الصندوق إذا محدد
            if (dto.PaidFromCashBoxId.HasValue)
            {
                var box = await _unitOfWork.CashBoxes.GetByIdAsync(dto.PaidFromCashBoxId.Value);
                if (box != null)
                {
                    if (box.CurrentBalance < dto.Amount)
                    {
                        await _unitOfWork.RollbackTransactionAsync();
                        return BadRequest(new { success = false, message = "رصيد الصندوق غير كافي" });
                    }

                    box.CurrentBalance -= dto.Amount;
                    _unitOfWork.CashBoxes.Update(box);

                    var cashTx = new CashTransaction
                    {
                        CashBoxId = box.Id,
                        TransactionType = CashTransactionType.Withdrawal,
                        Amount = dto.Amount,
                        BalanceAfter = box.CurrentBalance,
                        Description = $"مصروف: {dto.Description}",
                        ReferenceType = JournalReferenceType.Expense,
                        ReferenceId = expense.Id.ToString(),
                        CreatedById = dto.CreatedById
                    };
                    await _unitOfWork.CashTransactions.AddAsync(cashTx);
                }
            }

            // === إنشاء قيد محاسبي تلقائي للمصروف ===
            // مدين: حساب المصروف (من dto.AccountId أو حساب مصروفات متنوعة 5700)
            // دائن: حساب النقدية 1110
            var expenseAccountId = dto.AccountId;
            // التأكد من وجود حساب المصروف
            var expenseAccount = await _unitOfWork.Accounts.GetByIdAsync(expenseAccountId);
            if (expenseAccount == null)
            {
                // fallback: حساب مصروفات متنوعة
                var fallback = await FindAccountByCode("5700", dto.CompanyId);
                if (fallback != null) expenseAccountId = fallback.Id;
            }

            var cashAccount = await FindAccountByCode("1110", dto.CompanyId);
            if (cashAccount != null)
            {
                var journalLines = new List<(Guid AccountId, decimal DebitAmount, decimal CreditAmount, string? LineDescription)>
                {
                    (expenseAccountId, dto.Amount, 0, $"مصروف: {dto.Description}"),
                    (cashAccount.Id, 0, dto.Amount, $"دفع مصروف: {dto.Description}")
                };
                await CreateAndPostJournalEntry(
                    dto.CompanyId, dto.CreatedById,
                    $"مصروف تلقائي: {dto.Description}",
                    JournalReferenceType.Expense, expense.Id.ToString(),
                    journalLines);
            }

            await _unitOfWork.CommitTransactionAsync();
            return Ok(new { success = true, data = new { expense.Id }, message = "تم تسجيل المصروف" });
        }
        catch (Exception ex)
        {
            await _unitOfWork.RollbackTransactionAsync();
            _logger.LogError(ex, "خطأ في تسجيل المصروف");
            return StatusCode(500, new { success = false, message = "خطأ داخلي" });
        }
    }

    /// <summary>
    /// تعديل مصروف
    /// </summary>
    [HttpPut("expenses/{id}")]
    public async Task<IActionResult> UpdateExpense(long id, [FromBody] UpdateExpenseDto dto)
    {
        try
        {
            var expense = await _unitOfWork.Expenses.GetByIdAsync(id);
            if (expense == null)
                return NotFound(new { success = false, message = "المصروف غير موجود" });

            expense.Description = dto.Description ?? expense.Description;
            expense.Category = dto.Category ?? expense.Category;
            expense.Notes = dto.Notes ?? expense.Notes;
            expense.ExpenseDate = dto.ExpenseDate ?? expense.ExpenseDate;

            // إذا تغير المبلغ، تحديث الفرق في الصندوق والقيد
            if (dto.Amount.HasValue && dto.Amount.Value != expense.Amount)
            {
                var diff = dto.Amount.Value - expense.Amount;
                if (expense.PaidFromCashBoxId.HasValue)
                {
                    var box = await _unitOfWork.CashBoxes.GetByIdAsync(expense.PaidFromCashBoxId.Value);
                    if (box != null)
                    {
                        if (diff > 0 && box.CurrentBalance < diff)
                            return BadRequest(new { success = false, message = "رصيد الصندوق غير كافي للفرق" });
                        box.CurrentBalance -= diff;
                        _unitOfWork.CashBoxes.Update(box);
                    }
                }
                expense.Amount = dto.Amount.Value;
            }

            _unitOfWork.Expenses.Update(expense);
            await _unitOfWork.SaveChangesAsync();
            return Ok(new { success = true, message = "تم تحديث المصروف" });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في تعديل المصروف");
            return StatusCode(500, new { success = false, message = "خطأ داخلي" });
        }
    }

    /// <summary>
    /// حذف مصروف (ناعم) وإلغاء القيد المرتبط
    /// </summary>
    [HttpDelete("expenses/{id}")]
    public async Task<IActionResult> DeleteExpense(long id)
    {
        try
        {
            var expense = await _unitOfWork.Expenses.GetByIdAsync(id);
            if (expense == null)
                return NotFound(new { success = false, message = "المصروف غير موجود" });

            await _unitOfWork.BeginTransactionAsync();

            // إعادة المبلغ للصندوق
            if (expense.PaidFromCashBoxId.HasValue)
            {
                var box = await _unitOfWork.CashBoxes.GetByIdAsync(expense.PaidFromCashBoxId.Value);
                if (box != null)
                {
                    box.CurrentBalance += expense.Amount;
                    _unitOfWork.CashBoxes.Update(box);
                }
            }

            // إلغاء القيد المحاسبي المرتبط
            var relatedEntry = await _unitOfWork.JournalEntries.AsQueryable()
                .Include(j => j.Lines)
                .FirstOrDefaultAsync(j => j.ReferenceType == JournalReferenceType.Expense && j.ReferenceId == id.ToString() && j.Status != JournalEntryStatus.Voided);
            if (relatedEntry != null)
            {
                foreach (var line in relatedEntry.Lines)
                {
                    var account = await _unitOfWork.Accounts.GetByIdAsync(line.AccountId);
                    if (account == null) continue;
                    if (account.AccountType == AccountType.Assets || account.AccountType == AccountType.Expenses)
                        account.CurrentBalance -= line.DebitAmount - line.CreditAmount;
                    else
                        account.CurrentBalance -= line.CreditAmount - line.DebitAmount;
                    _unitOfWork.Accounts.Update(account);
                }
                relatedEntry.Status = JournalEntryStatus.Voided;
                _unitOfWork.JournalEntries.Update(relatedEntry);
            }

            expense.IsDeleted = true;
            expense.DeletedAt = DateTime.UtcNow;
            _unitOfWork.Expenses.Update(expense);

            await _unitOfWork.CommitTransactionAsync();
            return Ok(new { success = true, message = "تم حذف المصروف" });
        }
        catch (Exception ex)
        {
            await _unitOfWork.RollbackTransactionAsync();
            _logger.LogError(ex, "خطأ في حذف المصروف");
            return StatusCode(500, new { success = false, message = "خطأ داخلي" });
        }
    }

    /// <summary>
    /// تعديل تحصيل
    /// </summary>
    [HttpPut("collections/{id}")]
    public async Task<IActionResult> UpdateCollection(long id, [FromBody] UpdateCollectionDto dto)
    {
        try
        {
            var collection = await _unitOfWork.TechnicianCollections.GetByIdAsync(id);
            if (collection == null)
                return NotFound(new { success = false, message = "التحصيل غير موجود" });

            if (collection.IsDelivered)
                return BadRequest(new { success = false, message = "لا يمكن تعديل تحصيل تم تسليمه" });

            collection.Amount = dto.Amount ?? collection.Amount;
            collection.Description = dto.Description ?? collection.Description;
            collection.Notes = dto.Notes ?? collection.Notes;
            collection.ReceiptNumber = dto.ReceiptNumber ?? collection.ReceiptNumber;
            collection.CollectionDate = dto.CollectionDate ?? collection.CollectionDate;

            _unitOfWork.TechnicianCollections.Update(collection);
            await _unitOfWork.SaveChangesAsync();
            return Ok(new { success = true, message = "تم تحديث التحصيل" });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في تعديل التحصيل");
            return StatusCode(500, new { success = false, message = "خطأ داخلي" });
        }
    }

    /// <summary>
    /// حذف تحصيل (ناعم) وإلغاء القيد المرتبط
    /// </summary>
    [HttpDelete("collections/{id}")]
    public async Task<IActionResult> DeleteCollection(long id)
    {
        try
        {
            var collection = await _unitOfWork.TechnicianCollections.GetByIdAsync(id);
            if (collection == null)
                return NotFound(new { success = false, message = "التحصيل غير موجود" });

            await _unitOfWork.BeginTransactionAsync();

            // إذا مسلّم، إعادة المبلغ من الصندوق
            if (collection.IsDelivered && collection.CashBoxId.HasValue)
            {
                var box = await _unitOfWork.CashBoxes.GetByIdAsync(collection.CashBoxId.Value);
                if (box != null)
                {
                    box.CurrentBalance -= collection.Amount;
                    _unitOfWork.CashBoxes.Update(box);
                }
            }

            // إلغاء القيد المحاسبي المرتبط
            var relatedEntry = await _unitOfWork.JournalEntries.AsQueryable()
                .Include(j => j.Lines)
                .FirstOrDefaultAsync(j => j.ReferenceType == JournalReferenceType.TechnicianCollection && j.ReferenceId == id.ToString() && j.Status != JournalEntryStatus.Voided);
            if (relatedEntry != null)
            {
                foreach (var line in relatedEntry.Lines)
                {
                    var account = await _unitOfWork.Accounts.GetByIdAsync(line.AccountId);
                    if (account == null) continue;
                    if (account.AccountType == AccountType.Assets || account.AccountType == AccountType.Expenses)
                        account.CurrentBalance -= line.DebitAmount - line.CreditAmount;
                    else
                        account.CurrentBalance -= line.CreditAmount - line.DebitAmount;
                    _unitOfWork.Accounts.Update(account);
                }
                relatedEntry.Status = JournalEntryStatus.Voided;
                _unitOfWork.JournalEntries.Update(relatedEntry);
            }

            collection.IsDeleted = true;
            collection.DeletedAt = DateTime.UtcNow;
            _unitOfWork.TechnicianCollections.Update(collection);

            await _unitOfWork.CommitTransactionAsync();
            return Ok(new { success = true, message = "تم حذف التحصيل" });
        }
        catch (Exception ex)
        {
            await _unitOfWork.RollbackTransactionAsync();
            _logger.LogError(ex, "خطأ في حذف التحصيل");
            return StatusCode(500, new { success = false, message = "خطأ داخلي" });
        }
    }

    /// <summary>
    /// تعديل صندوق
    /// </summary>
    [HttpPut("cashboxes/{id}")]
    public async Task<IActionResult> UpdateCashBox(Guid id, [FromBody] UpdateCashBoxDto dto)
    {
        try
        {
            var box = await _unitOfWork.CashBoxes.GetByIdAsync(id);
            if (box == null)
                return NotFound(new { success = false, message = "الصندوق غير موجود" });

            box.Name = dto.Name ?? box.Name;
            box.Notes = dto.Notes ?? box.Notes;
            box.IsActive = dto.IsActive ?? box.IsActive;

            _unitOfWork.CashBoxes.Update(box);
            await _unitOfWork.SaveChangesAsync();
            return Ok(new { success = true, message = "تم تحديث الصندوق" });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في تعديل الصندوق");
            return StatusCode(500, new { success = false, message = "خطأ داخلي" });
        }
    }

    /// <summary>
    /// حذف صندوق (ناعم)
    /// </summary>
    [HttpDelete("cashboxes/{id}")]
    public async Task<IActionResult> DeleteCashBox(Guid id)
    {
        try
        {
            var box = await _unitOfWork.CashBoxes.GetByIdAsync(id);
            if (box == null)
                return NotFound(new { success = false, message = "الصندوق غير موجود" });

            // التحقق من عدم وجود رصيد
            if (box.CurrentBalance != 0)
                return BadRequest(new { success = false, message = $"لا يمكن حذف صندوق برصيد ({box.CurrentBalance}). يجب تفريغ الرصيد أولاً" });

            box.IsDeleted = true;
            box.DeletedAt = DateTime.UtcNow;
            _unitOfWork.CashBoxes.Update(box);
            await _unitOfWork.SaveChangesAsync();
            return Ok(new { success = true, message = "تم حذف الصندوق" });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في حذف الصندوق");
            return StatusCode(500, new { success = false, message = "خطأ داخلي" });
        }
    }

    /// <summary>
    /// تعديل قيد محاسبي (مسودة فقط)
    /// </summary>
    [HttpPut("journal-entries/{id}")]
    public async Task<IActionResult> UpdateJournalEntry(Guid id, [FromBody] UpdateJournalEntryDto dto)
    {
        try
        {
            var entry = await _unitOfWork.JournalEntries.AsQueryable()
                .Include(j => j.Lines)
                .FirstOrDefaultAsync(j => j.Id == id);

            if (entry == null)
                return NotFound(new { success = false, message = "القيد غير موجود" });

            if (entry.Status == JournalEntryStatus.Voided)
                return BadRequest(new { success = false, message = "لا يمكن تعديل قيد ملغي" });

            var wasPosted = entry.Status == JournalEntryStatus.Posted;

            await _unitOfWork.BeginTransactionAsync();

            // إذا كان مرحّلاً، نعكس أرصدة الحسابات القديمة أولاً
            if (wasPosted)
            {
                foreach (var line in entry.Lines)
                {
                    var account = await _unitOfWork.Accounts.GetByIdAsync(line.AccountId);
                    if (account == null) continue;
                    if (account.AccountType == AccountType.Assets || account.AccountType == AccountType.Expenses)
                        account.CurrentBalance -= line.DebitAmount - line.CreditAmount;
                    else
                        account.CurrentBalance -= line.CreditAmount - line.DebitAmount;
                    _unitOfWork.Accounts.Update(account);
                }
            }

            entry.Description = dto.Description ?? entry.Description;
            entry.Notes = dto.Notes ?? entry.Notes;
            entry.EntryDate = dto.EntryDate ?? entry.EntryDate;

            // تحديث السطور إذا وُجدت
            if (dto.Lines != null && dto.Lines.Any())
            {
                // حذف السطور القديمة
                foreach (var oldLine in entry.Lines.ToList())
                {
                    // soft delete
                    oldLine.IsDeleted = true;
                    oldLine.DeletedAt = DateTime.UtcNow;
                    _unitOfWork.JournalEntryLines.Update(oldLine);
                }

                decimal totalDebit = 0, totalCredit = 0;
                foreach (var lineDto in dto.Lines)
                {
                    var newLine = new JournalEntryLine
                    {
                        JournalEntryId = entry.Id,
                        AccountId = lineDto.AccountId,
                        DebitAmount = lineDto.DebitAmount,
                        CreditAmount = lineDto.CreditAmount,
                        Description = lineDto.Description,
                        EntityType = lineDto.EntityType,
                        EntityId = lineDto.EntityId
                    };
                    await _unitOfWork.JournalEntryLines.AddAsync(newLine);
                    totalDebit += lineDto.DebitAmount;
                    totalCredit += lineDto.CreditAmount;
                }

                if (totalDebit != totalCredit)
                {
                    await _unitOfWork.RollbackTransactionAsync();
                    return BadRequest(new { success = false, message = $"القيد غير متوازن: مدين {totalDebit} != دائن {totalCredit}" });
                }

                entry.TotalDebit = totalDebit;
                entry.TotalCredit = totalCredit;
            }

            // إذا كان مرحّلاً، نطبّق الأرصدة الجديدة
            if (wasPosted)
            {
                // جلب السطور الجديدة (غير محذوفة)
                var newLines = dto.Lines != null && dto.Lines.Any()
                    ? dto.Lines
                    : entry.Lines.Where(l => !l.IsDeleted).Select(l => new CreateJournalEntryLineDto(l.AccountId, l.DebitAmount, l.CreditAmount, l.Description, l.EntityType, l.EntityId)).ToList();

                foreach (var lineDto in newLines)
                {
                    var account = await _unitOfWork.Accounts.GetByIdAsync(lineDto.AccountId);
                    if (account == null) continue;
                    if (account.AccountType == AccountType.Assets || account.AccountType == AccountType.Expenses)
                        account.CurrentBalance += lineDto.DebitAmount - lineDto.CreditAmount;
                    else
                        account.CurrentBalance += lineDto.CreditAmount - lineDto.DebitAmount;
                    _unitOfWork.Accounts.Update(account);
                }
            }

            _unitOfWork.JournalEntries.Update(entry);
            await _unitOfWork.SaveChangesAsync();
            await _unitOfWork.CommitTransactionAsync();
            return Ok(new { success = true, message = "تم تحديث القيد" });
        }
        catch (Exception ex)
        {
            try { await _unitOfWork.RollbackTransactionAsync(); } catch { }
            _logger.LogError(ex, "خطأ في تعديل القيد");
            return StatusCode(500, new { success = false, message = "خطأ داخلي" });
        }
    }

    /// <summary>
    /// حذف قيد محاسبي (ناعم) - يُلغي أيضاً أرصدة الحسابات والكيانات المرتبطة
    /// </summary>
    [HttpDelete("journal-entries/{id}")]
    public async Task<IActionResult> DeleteJournalEntry(Guid id)
    {
        try
        {
            var entry = await _unitOfWork.JournalEntries.AsQueryable()
                .Include(j => j.Lines)
                .FirstOrDefaultAsync(j => j.Id == id);

            if (entry == null)
                return NotFound(new { success = false, message = "القيد غير موجود" });

            await _unitOfWork.BeginTransactionAsync();

            // 1. عكس الأرصدة إذا كان مُعتمداً
            if (entry.Status == JournalEntryStatus.Posted)
            {
                foreach (var line in entry.Lines)
                {
                    var account = await _unitOfWork.Accounts.GetByIdAsync(line.AccountId);
                    if (account == null) continue;
                    if (account.AccountType == AccountType.Assets || account.AccountType == AccountType.Expenses)
                        account.CurrentBalance -= line.DebitAmount - line.CreditAmount;
                    else
                        account.CurrentBalance -= line.CreditAmount - line.DebitAmount;
                    _unitOfWork.Accounts.Update(account);
                }
            }

            // 2. حذف ناعم لأسطر القيد
            foreach (var line in entry.Lines)
            {
                line.IsDeleted = true;
                line.DeletedAt = DateTime.UtcNow;
                _unitOfWork.JournalEntryLines.Update(line);
            }

            // 3. حذف الكيانات المرتبطة حسب نوع المرجع
            var refId = entry.ReferenceId;
            switch (entry.ReferenceType)
            {
                case JournalReferenceType.Expense:
                    if (long.TryParse(refId, out var expenseId))
                    {
                        var expense = await _unitOfWork.Expenses.GetByIdAsync(expenseId);
                        if (expense != null && !expense.IsDeleted)
                        {
                            // إعادة المبلغ للصندوق
                            if (expense.PaidFromCashBoxId.HasValue)
                            {
                                var box = await _unitOfWork.CashBoxes.GetByIdAsync(expense.PaidFromCashBoxId.Value);
                                if (box != null)
                                {
                                    box.CurrentBalance += expense.Amount;
                                    _unitOfWork.CashBoxes.Update(box);
                                }
                            }
                            expense.IsDeleted = true;
                            expense.DeletedAt = DateTime.UtcNow;
                            _unitOfWork.Expenses.Update(expense);
                            _logger.LogInformation("حذف مصروف مرتبط #{ExpenseId} عند حذف القيد", expenseId);
                        }
                    }
                    break;

                case JournalReferenceType.TechnicianCollection:
                    if (long.TryParse(refId, out var collectionId))
                    {
                        var collection = await _unitOfWork.TechnicianCollections.GetByIdAsync(collectionId);
                        if (collection != null && !collection.IsDeleted)
                        {
                            // إذا مسلّم، إعادة المبلغ من الصندوق
                            if (collection.IsDelivered && collection.CashBoxId.HasValue)
                            {
                                var box = await _unitOfWork.CashBoxes.GetByIdAsync(collection.CashBoxId.Value);
                                if (box != null)
                                {
                                    box.CurrentBalance -= collection.Amount;
                                    _unitOfWork.CashBoxes.Update(box);
                                }
                            }
                            collection.IsDeleted = true;
                            collection.DeletedAt = DateTime.UtcNow;
                            _unitOfWork.TechnicianCollections.Update(collection);
                            _logger.LogInformation("حذف تحصيل مرتبط #{CollectionId} عند حذف القيد", collectionId);
                        }
                    }
                    break;

                case JournalReferenceType.Salary:
                    if (long.TryParse(refId, out var salaryId))
                    {
                        var salary = await _unitOfWork.EmployeeSalaries.GetByIdAsync(salaryId);
                        if (salary != null && !salary.IsDeleted)
                        {
                            salary.IsDeleted = true;
                            salary.DeletedAt = DateTime.UtcNow;
                            _unitOfWork.EmployeeSalaries.Update(salary);
                            _logger.LogInformation("حذف راتب مرتبط #{SalaryId} عند حذف القيد", salaryId);
                        }
                    }
                    break;

                case JournalReferenceType.CashDeposit:
                case JournalReferenceType.CashWithdrawal:
                case JournalReferenceType.CashTransfer:
                    // حذف حركة الصندوق المرتبطة
                    var cashTx = await _unitOfWork.CashTransactions.AsQueryable()
                        .FirstOrDefaultAsync(ct => ct.JournalEntryId == id && !ct.IsDeleted);
                    if (cashTx != null)
                    {
                        // عكس رصيد الصندوق
                        var cashBox = await _unitOfWork.CashBoxes.GetByIdAsync(cashTx.CashBoxId);
                        if (cashBox != null)
                        {
                            cashBox.CurrentBalance -= cashTx.Amount;
                            _unitOfWork.CashBoxes.Update(cashBox);
                        }
                        cashTx.IsDeleted = true;
                        cashTx.DeletedAt = DateTime.UtcNow;
                        _unitOfWork.CashTransactions.Update(cashTx);
                        _logger.LogInformation("حذف حركة صندوق مرتبطة عند حذف القيد");
                    }
                    break;

                case JournalReferenceType.ServiceRequest:
                    // حذف معاملات الفني والوكيل المرتبطة بطلب الخدمة
                    if (Guid.TryParse(refId, out var srId))
                    {
                        // معاملة الفني
                        var srTechTx = await _unitOfWork.TechnicianTransactions.AsQueryable()
                            .FirstOrDefaultAsync(t => t.ServiceRequestId == srId && t.Type == TechnicianTransactionType.Charge && !t.IsDeleted);
                        if (srTechTx != null)
                        {
                            var tech = await _unitOfWork.Users.GetByIdAsync(srTechTx.TechnicianId);
                            if (tech != null)
                            {
                                tech.TechTotalCharges -= srTechTx.Amount;
                                tech.TechNetBalance = tech.TechTotalPayments - tech.TechTotalCharges;
                                _unitOfWork.Users.Update(tech);
                            }
                            srTechTx.IsDeleted = true;
                            srTechTx.DeletedAt = DateTime.UtcNow;
                            _unitOfWork.TechnicianTransactions.Update(srTechTx);
                            _logger.LogInformation("حذف معاملة فني مرتبطة بطلب خدمة عند حذف القيد");
                        }

                        // معاملة الوكيل
                        var srAgentTx = await _unitOfWork.AgentTransactions.AsQueryable()
                            .FirstOrDefaultAsync(t => t.ServiceRequestId == srId && t.Type == TransactionType.Charge && !t.IsDeleted);
                        if (srAgentTx != null)
                        {
                            var agent = await _unitOfWork.Agents.GetByIdAsync(srAgentTx.AgentId);
                            if (agent != null)
                            {
                                agent.TotalCharges -= srAgentTx.Amount;
                                agent.NetBalance = agent.TotalPayments - agent.TotalCharges;
                                _unitOfWork.Agents.Update(agent);
                            }
                            srAgentTx.IsDeleted = true;
                            srAgentTx.DeletedAt = DateTime.UtcNow;
                            _unitOfWork.AgentTransactions.Update(srAgentTx);
                            _logger.LogInformation("حذف معاملة وكيل مرتبطة بطلب خدمة عند حذف القيد");
                        }
                    }
                    break;

                case JournalReferenceType.FtthSubscription:
                    // حذف سجل الاشتراك + معاملاته المرتبطة
                    if (long.TryParse(refId, out var subLogId))
                    {
                        var subLog = await _unitOfWork.SubscriptionLogs.GetByIdAsync(subLogId);
                        if (subLog != null && !subLog.IsDeleted)
                        {
                            // معاملة الفني المرتبطة
                            if (subLog.LinkedTechnicianId.HasValue)
                            {
                                var ftthTechTx = await _unitOfWork.TechnicianTransactions.AsQueryable()
                                    .FirstOrDefaultAsync(t => t.ReferenceNumber == subLogId.ToString()
                                        && t.Type == TechnicianTransactionType.Charge && !t.IsDeleted);
                                if (ftthTechTx != null)
                                {
                                    var tech2 = await _unitOfWork.Users.GetByIdAsync(ftthTechTx.TechnicianId);
                                    if (tech2 != null)
                                    {
                                        tech2.TechTotalCharges -= ftthTechTx.Amount;
                                        tech2.TechNetBalance = tech2.TechTotalPayments - tech2.TechTotalCharges;
                                        _unitOfWork.Users.Update(tech2);
                                    }
                                    ftthTechTx.IsDeleted = true;
                                    ftthTechTx.DeletedAt = DateTime.UtcNow;
                                    _unitOfWork.TechnicianTransactions.Update(ftthTechTx);
                                }
                            }

                            // معاملة الوكيل المرتبطة
                            if (subLog.LinkedAgentId.HasValue)
                            {
                                var ftthAgentTx = await _unitOfWork.AgentTransactions.AsQueryable()
                                    .FirstOrDefaultAsync(t => t.ReferenceNumber == subLogId.ToString()
                                        && t.Type == TransactionType.Charge && !t.IsDeleted);
                                if (ftthAgentTx != null)
                                {
                                    var agent2 = await _unitOfWork.Agents.GetByIdAsync(ftthAgentTx.AgentId);
                                    if (agent2 != null)
                                    {
                                        agent2.TotalCharges -= ftthAgentTx.Amount;
                                        agent2.NetBalance = agent2.TotalPayments - agent2.TotalCharges;
                                        _unitOfWork.Agents.Update(agent2);
                                    }
                                    ftthAgentTx.IsDeleted = true;
                                    ftthAgentTx.DeletedAt = DateTime.UtcNow;
                                    _unitOfWork.AgentTransactions.Update(ftthAgentTx);
                                }
                            }

                            subLog.IsDeleted = true;
                            subLog.DeletedAt = DateTime.UtcNow;
                            _unitOfWork.SubscriptionLogs.Update(subLog);
                            _logger.LogInformation("حذف سجل اشتراك #{LogId} ومعاملاته عند حذف القيد", subLogId);
                        }
                    }
                    break;

                case JournalReferenceType.AgentTransaction:
                    // حذف معاملة الوكيل المرتبطة بالقيد
                    var agentTxByJe = await _unitOfWork.AgentTransactions.AsQueryable()
                        .FirstOrDefaultAsync(t => t.JournalEntryId == id && !t.IsDeleted);
                    if (agentTxByJe != null)
                    {
                        var agent3 = await _unitOfWork.Agents.GetByIdAsync(agentTxByJe.AgentId);
                        if (agent3 != null)
                        {
                            if (agentTxByJe.Type == TransactionType.Charge)
                                agent3.TotalCharges -= agentTxByJe.Amount;
                            else if (agentTxByJe.Type == TransactionType.Payment)
                                agent3.TotalPayments -= agentTxByJe.Amount;
                            agent3.NetBalance = agent3.TotalPayments - agent3.TotalCharges;
                            _unitOfWork.Agents.Update(agent3);
                        }
                        agentTxByJe.IsDeleted = true;
                        agentTxByJe.DeletedAt = DateTime.UtcNow;
                        _unitOfWork.AgentTransactions.Update(agentTxByJe);
                        _logger.LogInformation("حذف معاملة وكيل مرتبطة عند حذف القيد");
                    }
                    break;

                case JournalReferenceType.OperatorCashDelivery:
                case JournalReferenceType.OperatorCreditCollection:
                    // حذف حركات الصندوق المرتبطة بعمليات المشغل
                    var opCashTx = await _unitOfWork.CashTransactions.AsQueryable()
                        .FirstOrDefaultAsync(ct => ct.JournalEntryId == id && !ct.IsDeleted);
                    if (opCashTx != null)
                    {
                        var opBox = await _unitOfWork.CashBoxes.GetByIdAsync(opCashTx.CashBoxId);
                        if (opBox != null)
                        {
                            if (opCashTx.TransactionType == CashTransactionType.Deposit)
                                opBox.CurrentBalance -= opCashTx.Amount;
                            else
                                opBox.CurrentBalance += opCashTx.Amount;
                            _unitOfWork.CashBoxes.Update(opBox);
                        }
                        opCashTx.IsDeleted = true;
                        opCashTx.DeletedAt = DateTime.UtcNow;
                        _unitOfWork.CashTransactions.Update(opCashTx);
                        _logger.LogInformation("حذف حركة صندوق مشغل مرتبطة عند حذف القيد");
                    }
                    break;
            }

            // 4. حذف القيد نفسه
            entry.IsDeleted = true;
            entry.DeletedAt = DateTime.UtcNow;
            entry.Status = JournalEntryStatus.Voided;
            _unitOfWork.JournalEntries.Update(entry);

            await _unitOfWork.CommitTransactionAsync();

            _logger.LogInformation("تم حذف القيد {EntryNumber} وجميع الكيانات المرتبطة", entry.EntryNumber);
            return Ok(new { success = true, message = "تم حذف القيد وجميع السجلات المرتبطة به" });
        }
        catch (Exception ex)
        {
            await _unitOfWork.RollbackTransactionAsync();
            _logger.LogError(ex, "خطأ في حذف القيد");
            return StatusCode(500, new { success = false, message = "خطأ داخلي" });
        }
    }

    /// <summary>
    /// حذف راتب (ناعم) - فقط إذا لم يُصرف
    /// </summary>
    [HttpDelete("salaries/{id}")]
    public async Task<IActionResult> DeleteSalary(long id)
    {
        try
        {
            var salary = await _unitOfWork.EmployeeSalaries.GetByIdAsync(id);
            if (salary == null)
                return NotFound(new { success = false, message = "الراتب غير موجود" });

            if (salary.Status == SalaryStatus.Paid)
                return BadRequest(new { success = false, message = "لا يمكن حذف راتب تم صرفه" });

            salary.IsDeleted = true;
            salary.DeletedAt = DateTime.UtcNow;
            _unitOfWork.EmployeeSalaries.Update(salary);
            await _unitOfWork.SaveChangesAsync();
            return Ok(new { success = true, message = "تم حذف الراتب" });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في حذف الراتب");
            return StatusCode(500, new { success = false, message = "خطأ داخلي" });
        }
    }

    // ==================== التقارير المالية - Financial Reports ====================

    /// <summary>
    /// لوحة المحاسبة الرئيسية - ملخص شامل
    /// </summary>
    [HttpGet("dashboard")]
    public async Task<IActionResult> GetDashboard([FromQuery] Guid? companyId = null)
    {
        try
        {
            var now = DateTime.UtcNow;
            var monthStart = new DateTime(now.Year, now.Month, 1, 0, 0, 0, DateTimeKind.Utc);

            // أرصدة الصناديق
            var cashBoxesQuery = _unitOfWork.CashBoxes.AsQueryable();
            if (companyId.HasValue) cashBoxesQuery = cashBoxesQuery.Where(c => c.CompanyId == companyId);
            var totalCash = await cashBoxesQuery.Where(c => c.IsActive).SumAsync(c => (decimal?)c.CurrentBalance) ?? 0;

            // إيرادات الشهر (تحصيلات مُسلّمة)
            var collectionsQuery = _unitOfWork.TechnicianCollections.AsQueryable();
            if (companyId.HasValue) collectionsQuery = collectionsQuery.Where(c => c.CompanyId == companyId);
            var monthlyCollections = await collectionsQuery
                .Where(c => c.CollectionDate >= monthStart)
                .SumAsync(c => (decimal?)c.Amount) ?? 0;

            var pendingCollections = await collectionsQuery
                .Where(c => !c.IsDelivered)
                .SumAsync(c => (decimal?)c.Amount) ?? 0;

            // مصروفات الشهر
            var expensesQuery = _unitOfWork.Expenses.AsQueryable();
            if (companyId.HasValue) expensesQuery = expensesQuery.Where(e => e.CompanyId == companyId);
            var monthlyExpenses = await expensesQuery
                .Where(e => e.ExpenseDate >= monthStart)
                .SumAsync(e => (decimal?)e.Amount) ?? 0;

            // رواتب الشهر
            var salariesQuery = _unitOfWork.EmployeeSalaries.AsQueryable();
            if (companyId.HasValue) salariesQuery = salariesQuery.Where(s => s.CompanyId == companyId);
            var monthlySalaries = await salariesQuery
                .Where(s => s.Year == now.Year && s.Month == now.Month)
                .SumAsync(s => (decimal?)s.NetSalary) ?? 0;

            var unpaidSalaries = await salariesQuery
                .Where(s => s.Status == SalaryStatus.Pending)
                .SumAsync(s => (decimal?)s.NetSalary) ?? 0;

            // عدد القيود
            var journalQuery = _unitOfWork.JournalEntries.AsQueryable();
            if (companyId.HasValue) journalQuery = journalQuery.Where(j => j.CompanyId == companyId);
            var totalEntries = await journalQuery.CountAsync();
            var draftEntries = await journalQuery.CountAsync(j => j.Status == JournalEntryStatus.Draft);

            // أرصدة الحسابات من شجرة الحسابات (حسابات نهائية فقط)
            var accountsQuery = _unitOfWork.Accounts.AsQueryable().Where(a => a.IsLeaf && a.IsActive);
            if (companyId.HasValue) accountsQuery = accountsQuery.Where(a => a.CompanyId == companyId);
            var leafAccounts = await accountsQuery.ToListAsync();

            var totalAssets = leafAccounts.Where(a => a.AccountType == AccountType.Assets).Sum(a => a.CurrentBalance);
            var totalLiabilities = leafAccounts.Where(a => a.AccountType == AccountType.Liabilities).Sum(a => a.CurrentBalance);
            var totalEquity = leafAccounts.Where(a => a.AccountType == AccountType.Equity).Sum(a => a.CurrentBalance);
            var totalRevenue = leafAccounts.Where(a => a.AccountType == AccountType.Revenue).Sum(a => a.CurrentBalance);
            var totalExpensesFromAccounts = leafAccounts.Where(a => a.AccountType == AccountType.Expenses).Sum(a => a.CurrentBalance);

            // رصيد حساب النقد و الصندوق (1110 وفروعه)
            var cashAccount1110 = await _unitOfWork.Accounts.AsQueryable()
                .Where(a => a.Code == "1110")
                .Select(a => a.Id)
                .FirstOrDefaultAsync();
            decimal cashAccountBalance = 0;
            if (cashAccount1110 != default)
            {
                // مجموع أرصدة الحسابات النهائية تحت 1110 + رصيد 1110 نفسه إذا كان نهائي
                var cashLeafAccounts = leafAccounts.Where(a => a.ParentAccountId == cashAccount1110).Sum(a => a.CurrentBalance);
                var selfBalance = leafAccounts.Where(a => a.Id == cashAccount1110).Sum(a => a.CurrentBalance);
                cashAccountBalance = cashLeafAccounts + selfBalance;
            }

            // ═══ صافي الوكلاء (الصافي الكلي لجميع الوكلاء) ═══
            var agentsQuery = _unitOfWork.Agents.AsQueryable();
            if (companyId.HasValue) agentsQuery = agentsQuery.Where(a => a.CompanyId == companyId);
            // NetBalance = TotalPayments - TotalCharges → سالب = مديون، موجب = دائن
            var agentNetTotal = await agentsQuery
                .SumAsync(a => (decimal?)a.NetBalance) ?? 0;

            // ═══ صافي الفنيين (الصافي الكلي لجميع الفنيين) ═══
            var techQuery = _unitOfWork.Users.AsQueryable();
            if (companyId.HasValue) techQuery = techQuery.Where(u => u.CompanyId == companyId);
            // TechNetBalance = TotalPayments - TotalCharges → سالب = مديون، موجب = دائن
            var techNetTotal = await techQuery
                .Where(u => u.TechTotalCharges > 0 || u.TechTotalPayments > 0)
                .SumAsync(u => (decimal?)u.TechNetBalance) ?? 0;

            // الصافي الكلي = صافي الوكلاء + صافي الفنيين (سالب = مديون عليهم للشركة)
            var totalNet = agentNetTotal + techNetTotal;

            // ═══ رصيد القاصة (11101) ═══
            var cashRegisterBalance = leafAccounts
                .Where(a => a.Code == "11101")
                .Sum(a => a.CurrentBalance);

            // ═══ رصيد صندوق الشركة الرئيسي (11104) ═══
            var mainCashBoxBalance = leafAccounts
                .Where(a => a.Code == "11104")
                .Sum(a => a.CurrentBalance);

            // ═══ رصيد الصفحة (11102) ═══
            var pageBalance = leafAccounts
                .Where(a => a.Code == "11102")
                .Sum(a => a.CurrentBalance);

            // ═══ مستحقات المشغلين = نقد في صناديقهم (1110) + آجل في ذمتهم (1160) ═══
            var knownNonOperatorCodes = new HashSet<string> { "1110", "11101", "11102", "11103", "11104" };
            var operatorCashBoxes = leafAccounts
                .Where(a => a.Code != null && a.Code.StartsWith("1110") && !knownNonOperatorCodes.Contains(a.Code))
                .Sum(a => a.CurrentBalance);
            var operatorCredit = leafAccounts
                .Where(a => a.Code != null && a.Code.StartsWith("1160") && a.Code != "1160")
                .Sum(a => a.CurrentBalance);
            var operatorReceivables = operatorCashBoxes + operatorCredit;

            return Ok(new
            {
                success = true,
                data = new
                {
                    CashBoxes = new { TotalBalance = totalCash },
                    Collections = new
                    {
                        MonthlyTotal = monthlyCollections,
                        PendingDelivery = Math.Abs(totalNet)
                    },
                    Expenses = new { MonthlyTotal = monthlyExpenses },
                    Salaries = new
                    {
                        MonthlyTotal = monthlySalaries,
                        UnpaidTotal = unpaidSalaries
                    },
                    JournalEntries = new
                    {
                        Total = totalEntries,
                        DraftCount = draftEntries
                    },
                    NetMonthly = monthlyCollections - monthlyExpenses - monthlySalaries,
                    // أرصدة من شجرة الحسابات
                    AccountBalances = new
                    {
                        TotalAssets = totalAssets,
                        TotalLiabilities = totalLiabilities,
                        TotalEquity = totalEquity,
                        TotalRevenue = totalRevenue,
                        TotalExpenses = totalExpensesFromAccounts,
                        NetIncome = totalRevenue - totalExpensesFromAccounts,
                        CashAccountBalance = cashAccountBalance,
                        CashRegisterBalance = cashRegisterBalance,
                        MainCashBoxBalance = mainCashBoxBalance,
                        PageBalance = pageBalance,
                        OperatorReceivables = operatorReceivables
                    },
                    // تفاصيل الصافي
                    PendingDetails = new
                    {
                        AgentNet = agentNetTotal,       // سالب = مديون، موجب = دائن
                        TechnicianNet = techNetTotal,    // سالب = مديون، موجب = دائن
                        Total = totalNet,               // سالب = مديون، موجب = دائن
                        IsDebtor = totalNet < 0          // true = عليهم للشركة
                    }
                }
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في لوحة المحاسبة");
            return StatusCode(500, new { success = false, message = "خطأ داخلي" });
        }
    }

    /// <summary>
    /// كشف حساب - Account Statement
    /// </summary>
    [HttpGet("accounts/{id}/statement")]
    public async Task<IActionResult> GetAccountStatement(
        Guid id,
        [FromQuery] DateTime? fromDate = null,
        [FromQuery] DateTime? toDate = null)
    {
        try
        {
            var account = await _unitOfWork.Accounts.GetByIdAsync(id);
            if (account == null)
                return NotFound(new { success = false, message = "الحساب غير موجود" });

            var query = _unitOfWork.JournalEntryLines.AsQueryable()
                .Where(l => l.AccountId == id);

            if (fromDate.HasValue)
                query = query.Where(l => l.JournalEntry != null && l.JournalEntry.EntryDate >= fromDate);
            if (toDate.HasValue)
                query = query.Where(l => l.JournalEntry != null && l.JournalEntry.EntryDate <= toDate);

            var lines = await query
                .Where(l => l.JournalEntry != null && l.JournalEntry.Status == JournalEntryStatus.Posted)
                .OrderBy(l => l.JournalEntry!.EntryDate)
                .Select(l => new
                {
                    l.Id,
                    EntryNumber = l.JournalEntry != null ? l.JournalEntry.EntryNumber : "",
                    EntryDate = l.JournalEntry != null ? l.JournalEntry.EntryDate : DateTime.MinValue,
                    EntryDescription = l.JournalEntry != null ? l.JournalEntry.Description : "",
                    l.DebitAmount,
                    l.CreditAmount,
                    l.Description
                }).ToListAsync();

            var totalDebit = lines.Sum(l => l.DebitAmount);
            var totalCredit = lines.Sum(l => l.CreditAmount);

            return Ok(new
            {
                success = true,
                data = new
                {
                    Account = new { account.Id, account.Code, account.Name, AccountType = account.AccountType.ToString() },
                    Lines = lines,
                    Summary = new
                    {
                        TotalDebit = totalDebit,
                        TotalCredit = totalCredit,
                        Balance = account.CurrentBalance
                    }
                }
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في كشف الحساب");
            return StatusCode(500, new { success = false, message = "خطأ داخلي" });
        }
    }

    /// <summary>
    /// ميزان المراجعة - Trial Balance
    /// </summary>
    [HttpGet("reports/trial-balance")]
    public async Task<IActionResult> GetTrialBalance([FromQuery] Guid? companyId = null)
    {
        try
        {
            var query = _unitOfWork.Accounts.AsQueryable().Where(a => a.IsLeaf && a.IsActive);
            if (companyId.HasValue)
                query = query.Where(a => a.CompanyId == companyId);

            var accounts = await query.OrderBy(a => a.Code).Select(a => new
            {
                a.Id,
                a.Code,
                a.Name,
                AccountType = a.AccountType.ToString(),
                a.CurrentBalance,
                DebitBalance = (a.AccountType == AccountType.Assets || a.AccountType == AccountType.Expenses) && a.CurrentBalance > 0 ? a.CurrentBalance : 0,
                CreditBalance = (a.AccountType == AccountType.Liabilities || a.AccountType == AccountType.Revenue || a.AccountType == AccountType.Equity) && a.CurrentBalance > 0 ? a.CurrentBalance :
                    (a.AccountType == AccountType.Assets || a.AccountType == AccountType.Expenses) && a.CurrentBalance < 0 ? Math.Abs(a.CurrentBalance) : 0
            }).ToListAsync();

            return Ok(new
            {
                success = true,
                data = accounts,
                totals = new
                {
                    TotalDebit = accounts.Sum(a => a.DebitBalance),
                    TotalCredit = accounts.Sum(a => a.CreditBalance)
                }
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في ميزان المراجعة");
            return StatusCode(500, new { success = false, message = "خطأ داخلي" });
        }
    }

    // ==================== إدارة نسب عمولات الوكلاء ====================

    /// <summary>
    /// الحصول على نسب عمولات وكيل معين لكل الباقات
    /// </summary>
    [HttpGet("agent-commissions/rates/{agentId}")]
    public async Task<IActionResult> GetAgentCommissionRates(Guid agentId)
    {
        try
        {
            var rates = await _unitOfWork.AgentCommissionRates.AsQueryable()
                .Where(r => r.AgentId == agentId)
                .Join(_unitOfWork.InternetPlans.AsQueryable(),
                    r => r.InternetPlanId, p => p.Id,
                    (r, p) => new
                    {
                        r.Id,
                        r.AgentId,
                        r.InternetPlanId,
                        PlanName = p.NameAr,
                        PlanSpeed = p.SpeedMbps,
                        PlanMonthlyPrice = p.MonthlyPrice,
                        PlanProfitAmount = p.ProfitAmount,
                        r.CommissionPercentage,
                        CommissionAmount = p.ProfitAmount * r.CommissionPercentage / 100,
                        r.IsActive,
                        r.Notes,
                        r.CreatedAt
                    })
                .OrderBy(r => r.PlanName)
                .ToListAsync();

            return Ok(new { success = true, data = rates });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في جلب نسب عمولات الوكيل {AgentId}", agentId);
            return StatusCode(500, new { success = false, message = "خطأ داخلي" });
        }
    }

    /// <summary>
    /// الحصول على نسب عمولات جميع الوكلاء لشركة
    /// </summary>
    [HttpGet("agent-commissions/rates")]
    public async Task<IActionResult> GetAllCommissionRates([FromQuery] Guid companyId)
    {
        try
        {
            var rates = await _unitOfWork.AgentCommissionRates.AsQueryable()
                .Where(r => r.CompanyId == companyId)
                .Join(_unitOfWork.InternetPlans.AsQueryable(),
                    r => r.InternetPlanId, p => p.Id,
                    (r, p) => new { Rate = r, Plan = p })
                .Join(_unitOfWork.Agents.AsQueryable(),
                    rp => rp.Rate.AgentId, a => a.Id,
                    (rp, a) => new
                    {
                        rp.Rate.Id,
                        rp.Rate.AgentId,
                        AgentName = a.Name,
                        AgentCode = a.AgentCode,
                        rp.Rate.InternetPlanId,
                        PlanName = rp.Plan.NameAr,
                        PlanMonthlyPrice = rp.Plan.MonthlyPrice,
                        PlanProfitAmount = rp.Plan.ProfitAmount,
                        rp.Rate.CommissionPercentage,
                        CommissionAmount = rp.Plan.ProfitAmount * rp.Rate.CommissionPercentage / 100,
                        rp.Rate.IsActive,
                        rp.Rate.Notes
                    })
                .OrderBy(r => r.AgentName).ThenBy(r => r.PlanName)
                .ToListAsync();

            return Ok(new { success = true, data = rates });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في جلب نسب عمولات الشركة");
            return StatusCode(500, new { success = false, message = "خطأ داخلي" });
        }
    }

    /// <summary>
    /// إضافة أو تحديث نسبة عمولة وكيل لباقة
    /// </summary>
    [HttpPost("agent-commissions/rates")]
    public async Task<IActionResult> SetAgentCommissionRate([FromBody] SetAgentCommissionRateDto dto)
    {
        try
        {
            // التحقق من الوكيل والباقة
            var agent = await _unitOfWork.Agents.GetByIdAsync(dto.AgentId);
            if (agent == null) return NotFound(new { success = false, message = "الوكيل غير موجود" });

            var plan = await _unitOfWork.InternetPlans.GetByIdAsync(dto.InternetPlanId);
            if (plan == null) return NotFound(new { success = false, message = "الباقة غير موجودة" });

            // البحث عن نسبة موجودة
            var existing = await _unitOfWork.AgentCommissionRates.FirstOrDefaultAsync(
                r => r.AgentId == dto.AgentId && r.InternetPlanId == dto.InternetPlanId);

            if (existing != null)
            {
                existing.CommissionPercentage = dto.CommissionPercentage;
                existing.IsActive = dto.IsActive ?? true;
                existing.Notes = dto.Notes;
                existing.UpdatedAt = DateTime.UtcNow;
                _unitOfWork.AgentCommissionRates.Update(existing);
            }
            else
            {
                var rate = new AgentCommissionRate
                {
                    AgentId = dto.AgentId,
                    InternetPlanId = dto.InternetPlanId,
                    CommissionPercentage = dto.CommissionPercentage,
                    CompanyId = dto.CompanyId,
                    IsActive = dto.IsActive ?? true,
                    Notes = dto.Notes,
                    CreatedAt = DateTime.UtcNow
                };
                await _unitOfWork.AgentCommissionRates.AddAsync(rate);
            }

            await _unitOfWork.SaveChangesAsync();

            var commissionAmount = plan.ProfitAmount * dto.CommissionPercentage / 100;
            return Ok(new
            {
                success = true,
                message = $"تم تحديد عمولة {agent.Name} لباقة {plan.NameAr}: {dto.CommissionPercentage}% = {commissionAmount:N0}",
                data = new { dto.AgentId, dto.InternetPlanId, dto.CommissionPercentage, CommissionAmount = commissionAmount }
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في تحديد نسبة العمولة");
            return StatusCode(500, new { success = false, message = "خطأ داخلي" });
        }
    }

    /// <summary>
    /// تعيين نسب عمولة لوكيل لجميع الباقات دفعة واحدة
    /// </summary>
    [HttpPost("agent-commissions/rates/bulk")]
    public async Task<IActionResult> SetBulkCommissionRates([FromBody] BulkSetCommissionRatesDto dto)
    {
        try
        {
            var agent = await _unitOfWork.Agents.GetByIdAsync(dto.AgentId);
            if (agent == null) return NotFound(new { success = false, message = "الوكيل غير موجود" });

            int updated = 0, created = 0;
            foreach (var item in dto.Rates)
            {
                var plan = await _unitOfWork.InternetPlans.GetByIdAsync(item.InternetPlanId);
                if (plan == null) continue;

                var existing = await _unitOfWork.AgentCommissionRates.FirstOrDefaultAsync(
                    r => r.AgentId == dto.AgentId && r.InternetPlanId == item.InternetPlanId);

                if (existing != null)
                {
                    existing.CommissionPercentage = item.CommissionPercentage;
                    existing.IsActive = true;
                    existing.UpdatedAt = DateTime.UtcNow;
                    _unitOfWork.AgentCommissionRates.Update(existing);
                    updated++;
                }
                else
                {
                    await _unitOfWork.AgentCommissionRates.AddAsync(new AgentCommissionRate
                    {
                        AgentId = dto.AgentId,
                        InternetPlanId = item.InternetPlanId,
                        CommissionPercentage = item.CommissionPercentage,
                        CompanyId = dto.CompanyId,
                        IsActive = true,
                        CreatedAt = DateTime.UtcNow
                    });
                    created++;
                }
            }

            await _unitOfWork.SaveChangesAsync();
            return Ok(new { success = true, message = $"تم تحديث {updated} وإضافة {created} نسبة عمولة للوكيل {agent.Name}" });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في تعيين نسب العمولات");
            return StatusCode(500, new { success = false, message = "خطأ داخلي" });
        }
    }

    /// <summary>
    /// حذف نسبة عمولة
    /// </summary>
    [HttpDelete("agent-commissions/rates/{id}")]
    public async Task<IActionResult> DeleteCommissionRate(long id)
    {
        try
        {
            var rate = await _unitOfWork.AgentCommissionRates.GetByIdAsync(id);
            if (rate == null) return NotFound(new { success = false, message = "نسبة العمولة غير موجودة" });

            rate.IsDeleted = true;
            rate.DeletedAt = DateTime.UtcNow;
            _unitOfWork.AgentCommissionRates.Update(rate);
            await _unitOfWork.SaveChangesAsync();

            return Ok(new { success = true, message = "تم حذف نسبة العمولة" });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في حذف نسبة العمولة");
            return StatusCode(500, new { success = false, message = "خطأ داخلي" });
        }
    }

    /// <summary>
    /// تحديث ربح الباقة (ProfitAmount)
    /// </summary>
    [HttpPut("internet-plans/{id}/profit")]
    public async Task<IActionResult> UpdatePlanProfit(Guid id, [FromBody] UpdatePlanProfitDto dto)
    {
        try
        {
            var plan = await _unitOfWork.InternetPlans.GetByIdAsync(id);
            if (plan == null) return NotFound(new { success = false, message = "الباقة غير موجودة" });

            plan.ProfitAmount = dto.ProfitAmount;
            plan.UpdatedAt = DateTime.UtcNow;
            _unitOfWork.InternetPlans.Update(plan);
            await _unitOfWork.SaveChangesAsync();

            return Ok(new { success = true, message = $"تم تحديث ربح باقة {plan.NameAr} إلى {dto.ProfitAmount:N0}" });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في تحديث ربح الباقة");
            return StatusCode(500, new { success = false, message = "خطأ داخلي" });
        }
    }

    /// <summary>
    /// جلب الباقات مع أرباحها
    /// </summary>
    [HttpGet("internet-plans/with-profit")]
    public async Task<IActionResult> GetPlansWithProfit([FromQuery] Guid companyId)
    {
        try
        {
            var plans = await _unitOfWork.InternetPlans.AsQueryable()
                .Where(p => p.CompanyId == companyId || p.CompanyId == null)
                .Where(p => p.IsActive)
                .OrderBy(p => p.SortOrder)
                .Select(p => new
                {
                    p.Id,
                    p.Name,
                    p.NameAr,
                    p.SpeedMbps,
                    p.MonthlyPrice,
                    p.YearlyPrice,
                    p.InstallationFee,
                    p.ProfitAmount,
                    p.IsActive
                })
                .ToListAsync();

            return Ok(new { success = true, data = plans });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في جلب الباقات");
            return StatusCode(500, new { success = false, message = "خطأ داخلي" });
        }
    }

    // ==================== صرف أرباح/عمولات الوكلاء ====================

    /// <summary>
    /// صرف عمولة لوكيل
    /// </summary>
    [HttpPost("agent-commissions/pay")]
    public async Task<IActionResult> PayAgentCommission([FromBody] PayAgentCommissionDto dto)
    {
        try
        {
            // التحقق من الوكيل
            var agent = await _unitOfWork.Agents.GetByIdAsync(dto.AgentId);
            if (agent == null)
                return NotFound(new { success = false, message = "الوكيل غير موجود" });

            await _unitOfWork.BeginTransactionAsync();

            // خصم من الصندوق إذا محدد
            if (dto.CashBoxId.HasValue)
            {
                var box = await _unitOfWork.CashBoxes.GetByIdAsync(dto.CashBoxId.Value);
                if (box == null)
                    return BadRequest(new { success = false, message = "الصندوق غير موجود" });

                if (box.CurrentBalance < dto.Amount)
                    return BadRequest(new { success = false, message = $"رصيد الصندوق ({box.CurrentBalance}) غير كافي لصرف ({dto.Amount})" });

                box.CurrentBalance -= dto.Amount;
                _unitOfWork.CashBoxes.Update(box);

                var cashTx = new CashTransaction
                {
                    CashBoxId = box.Id,
                    TransactionType = CashTransactionType.Withdrawal,
                    Amount = dto.Amount,
                    BalanceAfter = box.CurrentBalance,
                    Description = $"صرف عمولة وكيل - {agent.Name}",
                    ReferenceType = JournalReferenceType.Manual,
                    ReferenceId = dto.AgentId.ToString(),
                    CreatedById = dto.PaidById
                };
                await _unitOfWork.CashTransactions.AddAsync(cashTx);
            }

            // === إنشاء قيد محاسبي تلقائي ===
            // مدين: حساب فرعي للوكيل تحت 5900 عمولات الوكلاء
            // دائن: حساب النقدية 1110
            var cashAcct = await FindAccountByCode("1110", dto.CompanyId);
            if (cashAcct != null)
            {
                var agentSubAcct = await FindOrCreateSubAccount("5900", dto.AgentId, agent.Name, dto.CompanyId);

                var journalLines = new List<(Guid AccountId, decimal DebitAmount, decimal CreditAmount, string? LineDescription)>
                {
                    (agentSubAcct.Id, dto.Amount, 0, $"عمولة وكيل {agent.Name} - {dto.Description ?? ""}"),
                    (cashAcct.Id, 0, dto.Amount, $"صرف عمولة {agent.Name} من النقدية")
                };
                await CreateAndPostJournalEntry(
                    dto.CompanyId, dto.PaidById,
                    $"صرف عمولة وكيل - {agent.Name}",
                    JournalReferenceType.Manual, dto.AgentId.ToString(),
                    journalLines);
            }

            await _unitOfWork.CommitTransactionAsync();
            return Ok(new { success = true, message = $"تم صرف عمولة {dto.Amount} للوكيل {agent.Name}" });
        }
        catch (Exception ex)
        {
            await _unitOfWork.RollbackTransactionAsync();
            _logger.LogError(ex, "خطأ في صرف عمولة الوكيل");
            return StatusCode(500, new { success = false, message = "خطأ داخلي" });
        }
    }

    // ==================== Helpers ====================

    private async Task<string> GenerateEntryNumber(Guid companyId)
    {
        var year = DateTime.UtcNow.Year;
        // IgnoreQueryFilters لعدّ جميع القيود بما فيها المحذوفة ناعمياً لتجنب تعارض الأرقام
        var count = await _unitOfWork.JournalEntries.AsQueryable()
            .IgnoreQueryFilters()
            .CountAsync(j => j.CompanyId == companyId && j.EntryDate.Year == year);
        return $"JE-{year}-{(count + 1):D4}";
    }

    /// <summary>
    /// إنشاء قيد محاسبي تلقائي وترحيله فوراً مع تحديث أرصدة الحسابات
    /// </summary>
    private async Task CreateAndPostJournalEntry(
        Guid companyId,
        Guid createdById,
        string description,
        JournalReferenceType referenceType,
        string? referenceId,
        List<(Guid AccountId, decimal DebitAmount, decimal CreditAmount, string? LineDescription)> lines)
    {
        var entryNumber = await GenerateEntryNumber(companyId);
        var entry = new JournalEntry
        {
            Id = Guid.NewGuid(),
            EntryNumber = entryNumber,
            EntryDate = DateTime.UtcNow,
            Description = description,
            TotalDebit = lines.Sum(l => l.DebitAmount),
            TotalCredit = lines.Sum(l => l.CreditAmount),
            ReferenceType = referenceType,
            ReferenceId = referenceId,
            Status = JournalEntryStatus.Posted,
            CompanyId = companyId,
            CreatedById = createdById,
            ApprovedById = createdById,
            ApprovedAt = DateTime.UtcNow,
            Lines = lines.Select(l => new JournalEntryLine
            {
                AccountId = l.AccountId,
                DebitAmount = l.DebitAmount,
                CreditAmount = l.CreditAmount,
                Description = l.LineDescription
            }).ToList()
        };

        await _unitOfWork.JournalEntries.AddAsync(entry);

        // تحديث أرصدة الحسابات فوراً
        foreach (var line in lines)
        {
            var account = await _unitOfWork.Accounts.GetByIdAsync(line.AccountId);
            if (account == null) continue;

            if (account.AccountType == AccountType.Assets || account.AccountType == AccountType.Expenses)
            {
                account.CurrentBalance += line.DebitAmount - line.CreditAmount;
            }
            else
            {
                account.CurrentBalance += line.CreditAmount - line.DebitAmount;
            }
            _unitOfWork.Accounts.Update(account);
        }
    }

    /// <summary>
    /// البحث عن حساب بالكود - يرجع أول حساب leaf نشط مطابق
    /// </summary>
    private async Task<Account?> FindAccountByCode(string code, Guid companyId)
    {
        return await _unitOfWork.Accounts.AsQueryable()
            .FirstOrDefaultAsync(a => a.Code == code && a.CompanyId == companyId && a.IsActive);
    }

    /// <summary>
    /// البحث عن حساب فرعي لشخص (موظف/وكيل) أو إنشاؤه تلقائياً تحت حساب أب
    /// </summary>
    private async Task<Account> FindOrCreateSubAccount(
        string parentCode, Guid personId, string personName, Guid companyId)
    {
        // البحث عن حساب فرعي موجود لهذا الشخص بالوصف
        var parent = await FindAccountByCode(parentCode, companyId);
        if (parent == null)
            throw new Exception($"الحساب الأب {parentCode} غير موجود");

        // بحث عن حساب فرعي يحمل personId في الوصف
        var existing = await _unitOfWork.Accounts.AsQueryable()
            .FirstOrDefaultAsync(a => a.ParentAccountId == parent.Id
                && a.CompanyId == companyId
                && a.Description == personId.ToString()
                && a.IsActive);

        if (existing != null) return existing;

        // إنشاء حساب فرعي جديد تلقائياً
        // حساب أعلى كود فرعي
        var siblings = await _unitOfWork.Accounts.AsQueryable()
            .Where(a => a.ParentAccountId == parent.Id && a.CompanyId == companyId)
            .Select(a => a.Code)
            .ToListAsync();

        int maxSuffix = 0;
        foreach (var code in siblings)
        {
            if (code.StartsWith(parentCode) && code.Length > parentCode.Length)
            {
                if (int.TryParse(code.Substring(parentCode.Length), out var num) && num > maxSuffix)
                    maxSuffix = num;
            }
        }
        var newCode = $"{parentCode}{maxSuffix + 1}";

        // تحديث الأب ليصبح غير نهائي
        if (parent.IsLeaf)
        {
            parent.IsLeaf = false;
            _unitOfWork.Accounts.Update(parent);
        }

        var subAccount = new Account
        {
            Id = Guid.NewGuid(),
            Code = newCode,
            Name = personName,
            NameEn = null,
            AccountType = parent.AccountType,
            ParentAccountId = parent.Id,
            OpeningBalance = 0,
            CurrentBalance = 0,
            IsSystemAccount = false,
            Level = parent.Level + 1,
            IsLeaf = true,
            IsActive = true,
            Description = personId.ToString(), // نخزن ID الشخص للربط
            CompanyId = companyId
        };

        await _unitOfWork.Accounts.AddAsync(subAccount);
        return subAccount;
    }

    private List<Account> GetDefaultAccounts(Guid companyId)
    {
        var accounts = new List<Account>();

        void Add(string code, string name, string? nameEn, AccountType type, string? parentCode, bool isLeaf = false, bool isSystem = true)
        {
            var parent = parentCode != null ? accounts.FirstOrDefault(a => a.Code == parentCode) : null;
            var level = parent != null ? parent.Level + 1 : 1;
            accounts.Add(new Account
            {
                Id = Guid.NewGuid(),
                Code = code,
                Name = name,
                NameEn = nameEn,
                AccountType = type,
                ParentAccountId = parent?.Id,
                Level = level,
                IsLeaf = isLeaf,
                IsSystemAccount = isSystem,
                CompanyId = companyId
            });
        }

        // === أصول ===
        Add("1000", "الأصول", "Assets", AccountType.Assets, null);
        Add("1100", "الأصول المتداولة", "Current Assets", AccountType.Assets, "1000");
        Add("1110", "النقد و الصندوق", "Cash & Cash Box", AccountType.Assets, "1100", true);
        Add("1120", "البنوك", "Banks", AccountType.Assets, "1100", true);
        Add("1130", "المدينون", "Accounts Receivable", AccountType.Assets, "1100", true);
        Add("1140", "تحصيلات تحت التسليم", "Collections Pending Delivery", AccountType.Assets, "1100", true);
        Add("1150", "ذمم الوكلاء", "Agent Receivables", AccountType.Assets, "1100", true);
        Add("1160", "ذمم المشغلين", "Operator Receivables", AccountType.Assets, "1100", true);
        Add("1170", "صندوق الدفع الإلكتروني", "Electronic Payment Box", AccountType.Assets, "1100", true);
        Add("1200", "الأصول الثابتة", "Fixed Assets", AccountType.Assets, "1000");
        Add("1210", "المعدات والأجهزة", "Equipment", AccountType.Assets, "1200", true);
        Add("1220", "الأثاث والتجهيزات", "Furniture & Fixtures", AccountType.Assets, "1200", true);

        // === الالتزامات ===
        Add("2000", "الالتزامات", "Liabilities", AccountType.Liabilities, null);
        Add("2100", "الالتزامات المتداولة", "Current Liabilities", AccountType.Liabilities, "2000");
        Add("2110", "الدائنون", "Accounts Payable", AccountType.Liabilities, "2100", true);
        Add("2120", "رواتب مستحقة", "Salaries Payable", AccountType.Liabilities, "2100", true);
        Add("2130", "أمانات الوكلاء", "Agent Deposits", AccountType.Liabilities, "2100", true);

        // === حقوق ملكية ===
        Add("3000", "حقوق الملكية", "Equity", AccountType.Equity, null);
        Add("3100", "رأس المال", "Capital", AccountType.Equity, "3000", true);
        Add("3200", "أرباح محتجزة", "Retained Earnings", AccountType.Equity, "3000", true);

        // === إيرادات ===
        Add("4000", "الإيرادات", "Revenue", AccountType.Revenue, null);
        Add("4100", "إيرادات الاشتراكات", "Subscription Revenue", AccountType.Revenue, "4000");
        Add("4110", "إيرادات التجديد", "Renewal Revenue", AccountType.Revenue, "4100", true);
        Add("4120", "إيرادات الشراء", "Purchase Revenue", AccountType.Revenue, "4100", true);
        Add("4200", "إيرادات التركيب", "Installation Revenue", AccountType.Revenue, "4000", true);
        Add("4300", "إيرادات الصيانة", "Maintenance Revenue", AccountType.Revenue, "4000", true);
        Add("4400", "إيرادات أخرى", "Other Revenue", AccountType.Revenue, "4000", true);

        // === مصروفات ===
        Add("5000", "المصروفات", "Expenses", AccountType.Expenses, null);
        Add("5100", "الرواتب والأجور", "Salaries & Wages", AccountType.Expenses, "5000", true);
        Add("5200", "الإيجار", "Rent", AccountType.Expenses, "5000", true);
        Add("5300", "المواد والمستلزمات", "Materials & Supplies", AccountType.Expenses, "5000", true);
        Add("5400", "الاتصالات والإنترنت", "Telecom & Internet", AccountType.Expenses, "5000", true);
        Add("5500", "النقل والمواصلات", "Transportation", AccountType.Expenses, "5000", true);
        Add("5600", "مصروفات إدارية", "Administrative Expenses", AccountType.Expenses, "5000", true);
        Add("5700", "مصروفات متنوعة", "Miscellaneous Expenses", AccountType.Expenses, "5000", true);
        Add("5800", "شراء مواد", "Material Purchase", AccountType.Expenses, "5000", true);
        Add("5900", "عمولات الوكلاء", "Agent Commissions", AccountType.Expenses, "5000", true);

        // تحديث isLeaf للحسابات الأب
        foreach (var acc in accounts.Where(a => accounts.Any(c => c.ParentAccountId == a.Id)))
            acc.IsLeaf = false;

        return accounts;
    }
}

// ==================== DTOs ====================

public record CreateAccountDto(
    string Code,
    string Name,
    string? NameEn,
    AccountType AccountType,
    Guid? ParentAccountId,
    decimal OpeningBalance,
    string? Description,
    Guid CompanyId
);

public record UpdateAccountDto(
    string? Name,
    string? NameEn,
    string? Description,
    bool? IsActive,
    decimal? OpeningBalance
);

public record SeedAccountsDto(Guid CompanyId);

public record CreateJournalEntryDto(
    string Description,
    DateTime? EntryDate,
    string? Notes,
    Guid CompanyId,
    Guid CreatedById,
    List<CreateJournalEntryLineDto> Lines
);

public record CreateJournalEntryLineDto(
    Guid AccountId,
    decimal DebitAmount,
    decimal CreditAmount,
    string? Description,
    string? EntityType,
    string? EntityId
);

public record PostJournalEntryDto(Guid? ApprovedById);

public record CreateCashBoxDto(
    string Name,
    CashBoxType CashBoxType,
    decimal InitialBalance,
    Guid? ResponsibleUserId,
    Guid? LinkedAccountId,
    string? Notes,
    Guid CompanyId
);

public record CashBoxOperationDto(
    decimal Amount,
    string? Description,
    JournalReferenceType ReferenceType,
    string? ReferenceId,
    Guid CreatedById
);

public record GenerateSalariesDto(Guid CompanyId, int Month, int Year);

public record UpdateSalaryDto(
    decimal? BaseSalary,
    decimal? Allowances,
    decimal? Deductions,
    decimal? Bonuses,
    string? Notes
);

public record PaySalaryDto(Guid? CashBoxId, Guid PaidById);

public record PayAllSalariesDto(Guid CompanyId, int Month, int Year, Guid? CashBoxId, Guid PaidById);

public record CreateCollectionDto(
    Guid TechnicianId,
    Guid? CitizenId,
    Guid? ServiceRequestId,
    decimal Amount,
    DateTime? CollectionDate,
    string? Description,
    string? Notes,
    PaymentMethod PaymentMethod,
    string? ReceiptNumber,
    string? ReceivedBy,
    Guid CompanyId
);

public record DeliverCollectionDto(Guid DeliveredToUserId, Guid? CashBoxId);

public record CreateExpenseDto(
    Guid AccountId,
    decimal Amount,
    string Description,
    DateTime? ExpenseDate,
    string? Category,
    Guid? PaidFromCashBoxId,
    Guid CreatedById,
    string? AttachmentUrl,
    string? Notes,
    Guid CompanyId
);

public record UpdateExpenseDto(
    decimal? Amount,
    string? Description,
    string? Category,
    string? Notes,
    DateTime? ExpenseDate
);

public record UpdateCollectionDto(
    decimal? Amount,
    string? Description,
    string? Notes,
    string? ReceiptNumber,
    DateTime? CollectionDate
);

public record UpdateCashBoxDto(
    string? Name,
    string? Notes,
    bool? IsActive
);

public record UpdateJournalEntryDto(
    string? Description,
    string? Notes,
    DateTime? EntryDate,
    List<CreateJournalEntryLineDto>? Lines
);

public record PayAgentCommissionDto(
    Guid AgentId,
    decimal Amount,
    string? Description,
    Guid? CashBoxId,
    Guid PaidById,
    Guid CompanyId
);

public record SetAgentCommissionRateDto(
    Guid AgentId,
    Guid InternetPlanId,
    decimal CommissionPercentage,
    Guid CompanyId,
    bool? IsActive,
    string? Notes
);

public record BulkSetCommissionRatesDto(
    Guid AgentId,
    Guid CompanyId,
    List<PlanCommissionRateItem> Rates
);

public record PlanCommissionRateItem(
    Guid InternetPlanId,
    decimal CommissionPercentage
);

public record UpdatePlanProfitDto(
    decimal ProfitAmount
);
