using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Hosting;
using Sadara.API.Services;
using Sadara.Domain.Entities;
using Sadara.Domain.Enums;
using Sadara.Domain.Interfaces;
using Sadara.Infrastructure.Data;

namespace Sadara.API.Controllers;

/// <summary>
/// [تطوير فقط] محاكاة فوترة الساس — ينشئ <see cref="SubscriptionLog"/> بمصدر Sas + القيد المحاسبي
/// الحقيقي عبر <see cref="ISubscriptionAccountingService"/>، **بلا أي نداء SAS4** (لا تفعيل/خصم حقيقي).
///
/// ⚠️ محصور ببيئة Development فقط (يعيد 404 خارجها) + مفتاح X-Api-Key الداخلي.
/// للاختبار المحلي فقط — يُحذف هذا الملف قبل النشر (مُدرَج في PRE_DEPLOY_CHECKLIST).
/// </summary>
[ApiController]
[Route("api/sas-dev")]
public class SasDevController : ControllerBase
{
    private readonly SadaraDbContext _db;
    private readonly IUnitOfWork _unitOfWork;
    private readonly ISubscriptionAccountingService _accounting;
    private readonly IConfiguration _config;
    private readonly IWebHostEnvironment _env;
    private readonly ILogger<SasDevController> _logger;

    public SasDevController(
        SadaraDbContext db,
        IUnitOfWork unitOfWork,
        ISubscriptionAccountingService accounting,
        IConfiguration config,
        IWebHostEnvironment env,
        ILogger<SasDevController> logger)
    {
        _db = db;
        _unitOfWork = unitOfWork;
        _accounting = accounting;
        _config = config;
        _env = env;
        _logger = logger;
    }

    /// <summary>محاكاة عملية تفعيل مفوترة واحدة (بلا SAS4) لاختبار دورة المحاسبة.</summary>
    [HttpPost("simulate-billing")]
    public async Task<IActionResult> SimulateBilling([FromBody] SasSimulateBillingRequest? req, CancellationToken ct)
    {
        // حارس 1: بيئة التطوير فقط
        if (!_env.IsDevelopment())
            return NotFound();

        // حارس 2: مفتاح API الداخلي
        var provided = Request.Headers["X-Api-Key"].FirstOrDefault();
        var configured = _config["Security:InternalApiKey"]
                         ?? Environment.GetEnvironmentVariable("SADARA_INTERNAL_API_KEY");
        if (string.IsNullOrEmpty(configured) || provided != configured)
            return Unauthorized(new { success = false, message = "Invalid API Key" });

        req ??= new SasSimulateBillingRequest();

        // اختر حساب ساس (بالمعرّف أو أوّل حساب)
        var account = req.AccountId.HasValue
            ? await _db.SasAccounts.FirstOrDefaultAsync(x => x.Id == req.AccountId.Value && !x.IsDeleted, ct)
            : await _db.SasAccounts.FirstOrDefaultAsync(x => !x.IsDeleted, ct);
        if (account == null)
            return NotFound(new { success = false, message = "لا يوجد حساب ساس في القاعدة" });

        var basePrice = req.BasePrice ?? 10000m;
        var maintenanceFee = req.MaintenanceFee ?? 0m;
        var manualDiscount = req.ManualDiscount ?? 0m;
        var collectionType = string.IsNullOrWhiteSpace(req.CollectionType) ? "cash" : req.CollectionType!.Trim();
        var txn = "SIM-" + Guid.NewGuid().ToString("N");
        var collected = basePrice + maintenanceFee - manualDiscount;

        var log = new SubscriptionLog
        {
            Source = SubscriptionLogSource.Sas,
            SasAccountId = account.Id,
            SubscriberUid = req.SubscriberUid ?? "0",
            SubscriberUsername = req.SubscriberUsername ?? "TEST-SIM",
            PlanName = req.PlanName ?? "باقة تجريبية (محاكاة)",
            OperationType = "purchase",
            CollectionType = collectionType,
            BasePrice = basePrice,
            CompanyDiscount = 0,
            MaintenanceFee = maintenanceFee,
            ManualDiscount = manualDiscount,
            SystemDiscountEnabled = true,
            PlanPrice = basePrice,
            Currency = "IQD",
            CompanyId = account.CompanyId,
            UserId = account.OwnerUserId,
            FtthTransactionId = txn,
            SessionId = txn,
            ActivationDate = DateTime.UtcNow,
            SubscriptionNotes = "محاكاة اختبار — بلا نداء SAS4 (SIMULATED)",
            ReconciliationNotes = "activate"
        };
        await _unitOfWork.SubscriptionLogs.AddAsync(log, ct);
        await _unitOfWork.SaveChangesAsync(ct);

        Guid? journalEntryId = null;
        string? journalError = null;
        try
        {
            var input = new SubscriptionAccountingInput
            {
                BasePrice = basePrice,
                CompanyDiscount = 0,
                ManualDiscount = manualDiscount,
                MaintenanceFee = maintenanceFee,
                PlanPrice = basePrice,
                SystemDiscountEnabled = true,
                CollectionType = collectionType,
                PlanName = log.PlanName,
                CustomerName = log.SubscriberUsername,
                OperationType = "purchase",
                EntryDate = log.ActivationDate
            };
            journalEntryId = await _accounting.RecordAsync(log, input, account.CompanyId, account.OwnerUserId, ct);
            if (journalEntryId.HasValue)
            {
                log.JournalEntryId = journalEntryId;
                _unitOfWork.SubscriptionLogs.Update(log);
                await _unitOfWork.SaveChangesAsync(ct);
            }
        }
        catch (Exception ex)
        {
            journalError = ex.Message;
            _logger.LogWarning(ex, "محاكاة فوترة الساس: فشل إنشاء القيد للسجل {LogId}", log.Id);
        }

        return Ok(new
        {
            success = true,
            simulated = true,
            logId = log.Id,
            journalEntryId,
            journalError,
            accountId = account.Id,
            companyId = account.CompanyId,
            basePrice,
            maintenanceFee,
            manualDiscount,
            collectedAmount = collected,
            collectionType
        });
    }
}

/// <summary>جسم طلب محاكاة الفوترة (كلها اختيارية بقيم افتراضية).</summary>
public class SasSimulateBillingRequest
{
    public Guid? AccountId { get; set; }
    public string? SubscriberUid { get; set; }
    public string? SubscriberUsername { get; set; }
    public string? PlanName { get; set; }
    public decimal? BasePrice { get; set; }
    public decimal? MaintenanceFee { get; set; }
    public decimal? ManualDiscount { get; set; }
    public string? CollectionType { get; set; }
}
