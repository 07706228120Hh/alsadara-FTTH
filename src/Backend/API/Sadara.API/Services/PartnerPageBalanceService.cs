using System.Text.RegularExpressions;
using Microsoft.EntityFrameworkCore;
using Sadara.API.Constants;
using Sadara.API.Controllers;
using Sadara.Domain.Entities;
using Sadara.Domain.Enums;
using Sadara.Domain.Interfaces;
using Sadara.Infrastructure.Data;

namespace Sadara.API.Services;

/// <summary>Where the money of a partner page-balance top-up comes from.</summary>
public enum PartnerFundingSource
{
    PettyCash,          // 11101 القاصة
    CompanyMainCash,    // 11104 صندوق الشركة الرئيسي
    GeneralPageBalance  // 11102 الرصيد العام
}

public sealed record PartnerPageBalanceResult(
    bool Success,
    int StatusCode,
    string Message,
    Guid? JournalEntryId = null,
    decimal? PartnerBalance = null,
    decimal? SourceBalance = null,
    bool Duplicate = false);

public sealed record PartnerPageBalanceRow(
    Guid? PartnerId,
    string Name,
    bool IsActive,
    bool PartnerDeleted,
    string? PartnerAccountId,
    Guid? AccountId,
    string? Code,
    decimal Balance);

public sealed record PartnerPageBalanceOverview(
    bool HasPageAccount,
    decimal GeneralBalance,
    decimal PartnersTotal,
    bool HasPettyCash,
    decimal PettyCashBalance,
    bool HasCompanyMainCash,
    decimal CompanyMainCashBalance,
    List<PartnerPageBalanceRow> Partners);

public sealed record PartnerPageStatementRow(
    Guid JournalEntryId,
    string EntryNumber,
    DateTime EntryDate,
    DateTime CreatedAt,
    string Description,
    decimal Debit,
    decimal Credit,
    string Kind,
    string? ReferenceId,
    bool CanReverse,
    bool Reversed);

public sealed record PartnerPageStatement(
    Guid PartnerId,
    string PartnerName,
    Guid? AccountId,
    string? Code,
    decimal CurrentBalance,
    decimal TotalDebit,
    decimal TotalCredit,
    int Total,
    int Page,
    int PageSize,
    List<PartnerPageStatementRow> Rows);

/// <summary>
/// Money movements of the per-partner page-balance accounts: top-up from a cash box, transfer from the general
/// page balance, reversal, overview and statement. Every movement is one balanced journal entry posted through
/// <see cref="ServiceRequestAccountingHelper.CreateAndPostJournalEntry"/> (a single SaveChanges ⇒ atomic).
/// The company id is always supplied by the caller from the token; every query scopes by it explicitly.
/// </summary>
public static partial class PartnerPageBalanceService
{
    public const string TopUpReferencePrefix = "ppb:topup:";
    public const string TransferReferencePrefix = "ppb:xfer:";
    public const string ReversalReferencePrefix = "ppb:rev:";
    public const string ReturnReferencePrefix = "ppb:ret:";

    private const decimal MaxAmount = 1_000_000_000_000m;
    private const int MaxNotesLength = 200;
    private const int MaxStatementPage = 100_000;

    [GeneratedRegex("^[A-Za-z0-9_-]{8,40}$")]
    private static partial Regex IdempotencyKeyRegex();

    private static PartnerPageBalanceResult Fail(int status, string message) => new(false, status, message);

    private static string Truncate(string value, int max) => value.Length > max ? value[..max] : value;

    private static bool IsBidiControl(char c) =>
        c is (>= '\u200E' and <= '\u200F') or (>= '\u202A' and <= '\u202E') or (>= '\u2066' and <= '\u2069');

    /// <summary>Free text that ends up in a journal description: no control/bidi characters, bounded length.</summary>
    private static string? CleanNotes(string? notes)
    {
        if (string.IsNullOrWhiteSpace(notes)) return null;
        var cleaned = new string(notes.Where(c => !char.IsControl(c) && !IsBidiControl(c)).ToArray()).Trim();
        return cleaned.Length == 0 ? null : Truncate(cleaned, MaxNotesLength);
    }

    private static string SourceCode(PartnerFundingSource source) => source switch
    {
        PartnerFundingSource.PettyCash => AccountCodes.PettyCash,
        PartnerFundingSource.CompanyMainCash => AccountCodes.CompanyMainCash,
        _ => AccountCodes.PageBalance
    };

    private static string SourceName(PartnerFundingSource source) => source switch
    {
        PartnerFundingSource.PettyCash => "القاصة",
        PartnerFundingSource.CompanyMainCash => "صندوق الشركة الرئيسي",
        _ => "الرصيد العام"
    };

    private static Task<Account?> FindAccountByCode(SadaraDbContext db, Guid companyId, string code) =>
        db.Accounts.IgnoreQueryFilters()
            .FirstOrDefaultAsync(a => a.CompanyId == companyId && !a.IsDeleted && a.IsActive && a.Code == code);

    private static Task<FtthPartner?> FindPartner(SadaraDbContext db, Guid companyId, Guid partnerId) =>
        db.FtthPartners.IgnoreQueryFilters()
            .FirstOrDefaultAsync(p => p.Id == partnerId && p.CompanyId == companyId && !p.IsDeleted);

    /// <summary>
    /// Serializes page-balance movements of one company with a session-level advisory lock, so the balance check
    /// and the idempotency check cannot race. Session-level (not transaction-level) on purpose: the journal
    /// helper retries on an entry-number collision, which an open PostgreSQL transaction would not survive.
    /// </summary>
    private static async Task<T> WithCompanyLock<T>(SadaraDbContext db, Guid companyId, Func<Task<T>> body)
    {
        var key = $"ppb:{companyId:N}";
        await db.Database.OpenConnectionAsync();
        try
        {
            await db.Database.ExecuteSqlInterpolatedAsync($"SELECT pg_advisory_lock(hashtext({key}))");
            try
            {
                return await body();
            }
            finally
            {
                await db.Database.ExecuteSqlInterpolatedAsync($"SELECT pg_advisory_unlock(hashtext({key}))");
            }
        }
        finally
        {
            await db.Database.CloseConnectionAsync();
        }
    }

    /// <summary>
    /// Debits the partner's page-balance account and credits the source (cash box or general page balance).
    /// Rejected when the source does not hold the amount. A repeated <paramref name="idempotencyKey"/> for the
    /// same partner returns the first entry instead of posting again.
    /// </summary>
    public static async Task<PartnerPageBalanceResult> Fund(
        SadaraDbContext db,
        IUnitOfWork unitOfWork,
        Guid companyId,
        Guid partnerId,
        PartnerFundingSource source,
        decimal amount,
        string? notes,
        string? idempotencyKey,
        Guid createdById)
    {
        if (amount <= 0)
            return Fail(400, "المبلغ يجب أن يكون أكبر من صفر");
        if (amount > MaxAmount || decimal.Round(amount, 2) != amount)
            return Fail(400, "المبلغ غير صالح");

        var key = string.IsNullOrWhiteSpace(idempotencyKey) ? null : idempotencyKey.Trim();
        if (key != null && !IdempotencyKeyRegex().IsMatch(key))
            return Fail(400, "معرّف العملية غير صالح");

        var partner = await FindPartner(db, companyId, partnerId);
        if (partner == null)
            return Fail(404, "الشريك غير موجود");

        // Outside the lock and outside any transaction: creating the account may lose a race and retry.
        var partnerAccount = await PartnerPageBalanceHelper.EnsurePartnerPageAccount(db, partner);
        if (partnerAccount == null)
            return Fail(400, "حساب رصيد الصفحة (11102) غير موجود في شجرة الحسابات");
        if (!partnerAccount.IsActive)
            return Fail(400, "حساب رصيد هذا الشريك معطّل في شجرة الحسابات");

        var isTransfer = source == PartnerFundingSource.GeneralPageBalance;
        var referenceId = (isTransfer ? TransferReferencePrefix : TopUpReferencePrefix)
            + partnerId.ToString("N") + (key != null ? ":" + key : "");

        return await WithCompanyLock(db, companyId, async () =>
        {
            var sourceAccount = await FindAccountByCode(db, companyId, SourceCode(source));
            if (sourceAccount == null)
                return Fail(400, $"حساب {SourceName(source)} ({SourceCode(source)}) غير موجود في شجرة الحسابات");

            if (key != null)
            {
                var existing = await db.JournalEntries.IgnoreQueryFilters().AsNoTracking()
                    .Include(j => j.Lines)
                    .FirstOrDefaultAsync(j => j.CompanyId == companyId && !j.IsDeleted
                        && j.ReferenceType == JournalReferenceType.CashTransfer && j.ReferenceId == referenceId);
                if (existing != null)
                {
                    // The key identifies one request: replaying it with another amount or source is a conflict,
                    // not a silent success.
                    var samePayload =
                        existing.Lines.Any(l => !l.IsDeleted && l.AccountId == partnerAccount.Id && l.DebitAmount == amount)
                        && existing.Lines.Any(l => !l.IsDeleted && l.AccountId == sourceAccount.Id && l.CreditAmount == amount);
                    if (!samePayload)
                        return Fail(409, "معرّف العملية مستخدم مسبقاً لعملية مختلفة");

                    await db.Entry(partnerAccount).ReloadAsync();
                    return new PartnerPageBalanceResult(true, 200, "العملية منفّذة مسبقاً", existing.Id,
                        partnerAccount.CurrentBalance, Duplicate: true);
                }
            }

            // Re-read under the lock: both entities may have been loaded before a concurrent movement.
            await db.Entry(sourceAccount).ReloadAsync();
            await db.Entry(partnerAccount).ReloadAsync();

            if (sourceAccount.CurrentBalance < amount)
                return Fail(400, $"رصيد {SourceName(source)} غير كافٍ (المتاح {sourceAccount.CurrentBalance:N0})");

            var description = isTransfer
                ? $"تحويل من الرصيد العام إلى رصيد الصفحة - {partner.Name}"
                : $"شحن رصيد الصفحة - {partner.Name} من {SourceName(source)}";
            var cleanNotes = CleanNotes(notes);
            if (cleanNotes != null)
                description += $" — {cleanNotes}";

            var lines = new List<(Guid AccountId, decimal DebitAmount, decimal CreditAmount, string? LineDescription)>
            {
                (partnerAccount.Id, amount, 0, $"إضافة إلى رصيد الصفحة - {partner.Name}"),
                (sourceAccount.Id, 0, amount, $"سحب من {SourceName(source)}")
            };

            var entryId = await ServiceRequestAccountingHelper.CreateAndPostJournalEntry(
                unitOfWork, companyId, createdById, Truncate(description, 500),
                JournalReferenceType.CashTransfer, referenceId, lines);

            return new PartnerPageBalanceResult(true, 200,
                isTransfer ? $"تم تحويل {amount:N0} إلى {partner.Name}" : $"تم شحن {amount:N0} إلى {partner.Name}",
                entryId, partnerAccount.CurrentBalance, sourceAccount.CurrentBalance);
        });
    }

    /// <summary>
    /// Moves money from a partner's page-balance account back to the general 11102. Works on the account itself,
    /// so the balance of a deleted partner (or of a deactivated account) can still be recovered.
    /// </summary>
    public static async Task<PartnerPageBalanceResult> ReturnToGeneral(
        SadaraDbContext db,
        IUnitOfWork unitOfWork,
        Guid companyId,
        Guid partnerId,
        decimal amount,
        string? notes,
        string? idempotencyKey,
        Guid createdById)
    {
        if (amount <= 0)
            return Fail(400, "المبلغ يجب أن يكون أكبر من صفر");
        if (amount > MaxAmount || decimal.Round(amount, 2) != amount)
            return Fail(400, "المبلغ غير صالح");

        var key = string.IsNullOrWhiteSpace(idempotencyKey) ? null : idempotencyKey.Trim();
        if (key != null && !IdempotencyKeyRegex().IsMatch(key))
            return Fail(400, "معرّف العملية غير صالح");

        var partnerAccount = await PartnerPageBalanceHelper.FindPartnerPageAccount(db, companyId, partnerId, includeInactive: true);
        if (partnerAccount == null)
            return Fail(404, "لا يوجد حساب رصيد لهذا الشريك");

        var referenceId = ReturnReferencePrefix + partnerId.ToString("N") + (key != null ? ":" + key : "");

        return await WithCompanyLock(db, companyId, async () =>
        {
            var general = await PartnerPageBalanceHelper.FindGeneralPageAccount(db, companyId);
            if (general == null)
                return Fail(400, "حساب رصيد الصفحة (11102) غير موجود في شجرة الحسابات");

            if (key != null)
            {
                var existing = await db.JournalEntries.IgnoreQueryFilters().AsNoTracking()
                    .Include(j => j.Lines)
                    .FirstOrDefaultAsync(j => j.CompanyId == companyId && !j.IsDeleted
                        && j.ReferenceType == JournalReferenceType.CashTransfer && j.ReferenceId == referenceId);
                if (existing != null)
                {
                    var samePayload =
                        existing.Lines.Any(l => !l.IsDeleted && l.AccountId == partnerAccount.Id && l.CreditAmount == amount);
                    if (!samePayload)
                        return Fail(409, "معرّف العملية مستخدم مسبقاً لعملية مختلفة");

                    await db.Entry(partnerAccount).ReloadAsync();
                    return new PartnerPageBalanceResult(true, 200, "العملية منفّذة مسبقاً", existing.Id,
                        partnerAccount.CurrentBalance, Duplicate: true);
                }
            }

            await db.Entry(general).ReloadAsync();
            await db.Entry(partnerAccount).ReloadAsync();

            if (partnerAccount.CurrentBalance < amount)
                return Fail(400, $"رصيد الشريك غير كافٍ (المتاح {partnerAccount.CurrentBalance:N0})");

            var description = $"إرجاع من {partnerAccount.Name} إلى الرصيد العام";
            var cleanNotes = CleanNotes(notes);
            if (cleanNotes != null)
                description += $" — {cleanNotes}";

            var lines = new List<(Guid AccountId, decimal DebitAmount, decimal CreditAmount, string? LineDescription)>
            {
                (general.Id, amount, 0, "إضافة إلى الرصيد العام"),
                (partnerAccount.Id, 0, amount, "إرجاع إلى الرصيد العام")
            };

            var entryId = await ServiceRequestAccountingHelper.CreateAndPostJournalEntry(
                unitOfWork, companyId, createdById, Truncate(description, 500),
                JournalReferenceType.CashTransfer, referenceId, lines);

            return new PartnerPageBalanceResult(true, 200, $"تم إرجاع {amount:N0} إلى الرصيد العام",
                entryId, partnerAccount.CurrentBalance, general.CurrentBalance);
        });
    }

    /// <summary>
    /// Reverses a top-up/transfer by posting the opposite entry (the original stays for the audit trail).
    /// Only entries created by <see cref="Fund"/> can be reversed, and only once.
    /// </summary>
    public static async Task<PartnerPageBalanceResult> Reverse(
        SadaraDbContext db,
        IUnitOfWork unitOfWork,
        Guid companyId,
        Guid journalEntryId,
        Guid createdById)
    {
        return await WithCompanyLock(db, companyId, async () =>
        {
            var entry = await db.JournalEntries.IgnoreQueryFilters()
                .Include(j => j.Lines)
                .FirstOrDefaultAsync(j => j.Id == journalEntryId && j.CompanyId == companyId && !j.IsDeleted);
            if (entry == null)
                return Fail(404, "القيد غير موجود");

            var isFunding = entry.ReferenceType == JournalReferenceType.CashTransfer
                && entry.ReferenceId != null
                && (entry.ReferenceId.StartsWith(TopUpReferencePrefix, StringComparison.Ordinal)
                    || entry.ReferenceId.StartsWith(TransferReferencePrefix, StringComparison.Ordinal));
            if (!isFunding || entry.Status != JournalEntryStatus.Posted)
                return Fail(400, "هذا القيد ليس عملية شحن رصيد شريك قابلة للعكس");

            var reversalReference = ReversalReferencePrefix + entry.Id.ToString("N");
            var alreadyReversed = await db.JournalEntries.IgnoreQueryFilters()
                .AnyAsync(j => j.CompanyId == companyId && !j.IsDeleted
                    && j.ReferenceType == JournalReferenceType.CashTransfer && j.ReferenceId == reversalReference);
            if (alreadyReversed)
                return Fail(409, "تم عكس هذه العملية مسبقاً");

            var lines = entry.Lines
                .Where(l => !l.IsDeleted)
                .Select(l => (l.AccountId, DebitAmount: l.CreditAmount, CreditAmount: l.DebitAmount,
                    LineDescription: (string?)"عكس عملية شحن"))
                .ToList();
            if (lines.Count == 0)
                return Fail(400, "القيد لا يحتوي أسطراً قابلة للعكس");

            // Money already spent on activations cannot be taken back: the reversal must not drive the funded
            // account negative.
            foreach (var funded in entry.Lines.Where(l => !l.IsDeleted && l.DebitAmount > 0))
            {
                var balance = await db.Accounts.IgnoreQueryFilters().AsNoTracking()
                    .Where(a => a.Id == funded.AccountId && a.CompanyId == companyId)
                    .Select(a => (decimal?)a.CurrentBalance)
                    .FirstOrDefaultAsync();
                if (balance == null || balance.Value < funded.DebitAmount)
                    return Fail(400, "لا يمكن عكس العملية: الرصيد المتبقي للشريك أقل من مبلغ الشحن");
            }

            var entryId = await ServiceRequestAccountingHelper.CreateAndPostJournalEntry(
                unitOfWork, companyId, createdById, Truncate($"عكس: {entry.Description}", 500),
                JournalReferenceType.CashTransfer, reversalReference, lines);

            return new PartnerPageBalanceResult(true, 200, "تم عكس العملية", entryId);
        });
    }

    /// <summary>
    /// Balances of the general page account, the two funding cash boxes and every partner account.
    /// Read-only: a partner without an account yet is listed with a zero balance (the first funding creates it).
    /// </summary>
    public static async Task<PartnerPageBalanceOverview> GetOverview(SadaraDbContext db, Guid companyId)
    {
        var general = await PartnerPageBalanceHelper.FindGeneralPageAccount(db, companyId);
        var petty = await FindAccountByCode(db, companyId, AccountCodes.PettyCash);
        var main = await FindAccountByCode(db, companyId, AccountCodes.CompanyMainCash);

        var partners = await db.FtthPartners.IgnoreQueryFilters()
            .Where(p => p.CompanyId == companyId && !p.IsDeleted)
            .OrderBy(p => p.Name)
            .ToListAsync();

        var partnerAccounts = await db.Accounts.IgnoreQueryFilters().AsNoTracking()
            .Where(a => a.CompanyId == companyId && !a.IsDeleted
                && a.Code.StartsWith(AccountCodes.PartnerPageBalancePrefix))
            .OrderBy(a => a.Code)
            .ToListAsync();
        var accountByPartner = new Dictionary<Guid, Account>();
        foreach (var candidate in partnerAccounts)
        {
            var ownerId = PartnerPageBalanceHelper.PartnerIdOf(candidate);
            if (ownerId.HasValue) accountByPartner.TryAdd(ownerId.Value, candidate);
        }

        var rows = new List<PartnerPageBalanceRow>();
        var seenAccountIds = new HashSet<Guid>();
        foreach (var partner in partners)
        {
            accountByPartner.TryGetValue(partner.Id, out var account);
            if (account != null) seenAccountIds.Add(account.Id);
            rows.Add(new PartnerPageBalanceRow(partner.Id, partner.Name, partner.IsActive, false,
                partner.PartnerAccountId, account?.Id, account?.Code, account?.CurrentBalance ?? 0));
        }

        // Accounts of deleted partners that still hold money must stay visible.
        foreach (var account in partnerAccounts.Where(a => !seenAccountIds.Contains(a.Id) && a.CurrentBalance != 0))
        {
            rows.Add(new PartnerPageBalanceRow(PartnerPageBalanceHelper.PartnerIdOf(account), account.Name, false, true,
                null, account.Id, account.Code, account.CurrentBalance));
        }

        return new PartnerPageBalanceOverview(
            general != null,
            general?.CurrentBalance ?? 0,
            rows.Sum(r => r.Balance),
            petty != null,
            petty?.CurrentBalance ?? 0,
            main != null,
            main?.CurrentBalance ?? 0,
            rows);
    }

    /// <summary>Movements on a partner's page-balance account, newest first. Null when the partner is unknown.</summary>
    public static async Task<PartnerPageStatement?> GetStatement(
        SadaraDbContext db,
        Guid companyId,
        Guid partnerId,
        DateTime? from,
        DateTime? to,
        int page,
        int pageSize)
    {
        var partner = await FindPartner(db, companyId, partnerId);
        if (partner == null) return null;
        page = Math.Clamp(page, 1, MaxStatementPage);
        pageSize = Math.Clamp(pageSize, 1, 200);

        // Read-only: no account yet (never funded) ⇒ an empty statement.
        var account = await PartnerPageBalanceHelper.FindPartnerPageAccount(db, companyId, partner.Id, includeInactive: true);
        if (account == null)
            return new PartnerPageStatement(partner.Id, partner.Name, null, null, 0, 0, 0, 0, page, pageSize, new());

        var query =
            from line in db.JournalEntryLines.IgnoreQueryFilters()
            join entry in db.JournalEntries.IgnoreQueryFilters() on line.JournalEntryId equals entry.Id
            where line.AccountId == account.Id && !line.IsDeleted
                && !entry.IsDeleted && entry.CompanyId == companyId && entry.Status == JournalEntryStatus.Posted
            select new { line, entry };
        if (from.HasValue) query = query.Where(x => x.entry.EntryDate >= from.Value);
        if (to.HasValue) query = query.Where(x => x.entry.EntryDate <= to.Value);

        var total = await query.CountAsync();
        var totalDebit = await query.SumAsync(x => (decimal?)x.line.DebitAmount) ?? 0;
        var totalCredit = await query.SumAsync(x => (decimal?)x.line.CreditAmount) ?? 0;

        var items = await query
            .OrderByDescending(x => x.entry.EntryDate)
            .ThenByDescending(x => x.entry.CreatedAt)
            .ThenByDescending(x => x.line.Id)
            .Skip((page - 1) * pageSize)
            .Take(pageSize)
            .Select(x => new
            {
                x.entry.Id,
                x.entry.EntryNumber,
                x.entry.EntryDate,
                x.entry.CreatedAt,
                x.entry.Description,
                x.entry.ReferenceType,
                x.entry.ReferenceId,
                x.line.DebitAmount,
                x.line.CreditAmount
            })
            .ToListAsync();

        var fundingReversalRefs = items
            .Where(i => IsFundingReference(i.ReferenceType, i.ReferenceId))
            .Select(i => ReversalReferencePrefix + i.Id.ToString("N"))
            .ToList();
        var reversedRefs = fundingReversalRefs.Count == 0
            ? new HashSet<string>()
            : (await db.JournalEntries.IgnoreQueryFilters()
                .Where(j => j.CompanyId == companyId && !j.IsDeleted
                    && j.ReferenceType == JournalReferenceType.CashTransfer
                    && j.ReferenceId != null && fundingReversalRefs.Contains(j.ReferenceId))
                .Select(j => j.ReferenceId!)
                .ToListAsync()).ToHashSet();

        var rows = items.Select(i =>
        {
            var funding = IsFundingReference(i.ReferenceType, i.ReferenceId);
            var reversed = funding && reversedRefs.Contains(ReversalReferencePrefix + i.Id.ToString("N"));
            return new PartnerPageStatementRow(i.Id, i.EntryNumber, i.EntryDate, i.CreatedAt, i.Description,
                i.DebitAmount, i.CreditAmount, KindOf(i.ReferenceType, i.ReferenceId), i.ReferenceId,
                funding && !reversed, reversed);
        }).ToList();

        return new PartnerPageStatement(partner.Id, partner.Name, account.Id, account.Code, account.CurrentBalance,
            totalDebit, totalCredit, total, page, pageSize, rows);
    }

    private static bool IsFundingReference(JournalReferenceType type, string? referenceId) =>
        type == JournalReferenceType.CashTransfer && referenceId != null
        && (referenceId.StartsWith(TopUpReferencePrefix, StringComparison.Ordinal)
            || referenceId.StartsWith(TransferReferencePrefix, StringComparison.Ordinal));

    private static string KindOf(JournalReferenceType type, string? referenceId)
    {
        if (type == JournalReferenceType.FtthSubscription) return "activation";
        if (type == JournalReferenceType.CashTransfer && referenceId != null)
        {
            if (referenceId.StartsWith(TopUpReferencePrefix, StringComparison.Ordinal)) return "topup";
            if (referenceId.StartsWith(TransferReferencePrefix, StringComparison.Ordinal)) return "transfer";
            if (referenceId.StartsWith(ReversalReferencePrefix, StringComparison.Ordinal)) return "reversal";
            if (referenceId.StartsWith(ReturnReferencePrefix, StringComparison.Ordinal)) return "return";
        }
        return "other";
    }
}
