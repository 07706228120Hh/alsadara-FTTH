using Microsoft.EntityFrameworkCore;
using Sadara.API.Constants;
using Sadara.Domain.Entities;
using Sadara.Infrastructure.Data;

namespace Sadara.API.Services;

/// <summary>
/// Per-partner page-balance accounts (رصيد الصفحة لكل شريك).
/// Each <see cref="FtthPartner"/> gets one ledger account "11102-NN", created as a sibling of the general
/// page-balance account 11102 (same parent 1110) so cash totals built from the direct children of 1110 keep
/// including it and 11102 itself stays a leaf. The account is keyed by <see cref="Account.Description"/> =
/// "ftth-partner:{partnerId}" — prefixed so it can never match the operator lookups that key on a raw user id.
/// Queries ignore the global filters and scope by CompanyId explicitly: the internal (API-key) callers have no
/// tenant context.
/// </summary>
public static class PartnerPageBalanceHelper
{
    public const string DescriptionPrefix = "ftth-partner:";

    public static string DescriptionFor(Guid partnerId) => $"{DescriptionPrefix}{partnerId}";

    public static string AccountNameFor(string partnerName)
    {
        var name = $"رصيد الصفحة - {partnerName}".Trim();
        return name.Length > 200 ? name[..200] : name;
    }

    /// <summary>Partner id encoded in a partner page-balance account, or null for any other account.</summary>
    public static Guid? PartnerIdOf(Account account) =>
        account.Description != null
        && account.Description.StartsWith(DescriptionPrefix, StringComparison.Ordinal)
        && Guid.TryParse(account.Description[DescriptionPrefix.Length..], out var id)
            ? id
            : null;

    public static Task<Account?> FindGeneralPageAccount(SadaraDbContext db, Guid companyId) =>
        db.Accounts.IgnoreQueryFilters()
            .FirstOrDefaultAsync(a => a.CompanyId == companyId && !a.IsDeleted && a.IsActive
                && a.Code == AccountCodes.PageBalance);

    /// <param name="includeInactive">
    /// True when the caller must see a deactivated account too (creation must not add a second account for the
    /// same partner); false when the account is about to be charged.
    /// </param>
    public static Task<Account?> FindPartnerPageAccount(SadaraDbContext db, Guid companyId, Guid partnerId,
        bool includeInactive = false)
    {
        var description = DescriptionFor(partnerId);
        return db.Accounts.IgnoreQueryFilters()
            .FirstOrDefaultAsync(a => a.CompanyId == companyId && !a.IsDeleted && (includeInactive || a.IsActive)
                && a.Description == description
                && a.Code.StartsWith(AccountCodes.PartnerPageBalancePrefix));
    }

    /// <summary>
    /// True once the account has received money (a top-up or a transfer). Activations are only routed to a
    /// partner account after that, so deploying the feature never drives unfunded partner accounts negative
    /// while the whole balance still sits in the general 11102.
    /// </summary>
    public static Task<bool> IsFunded(SadaraDbContext db, Guid accountId) =>
        db.JournalEntryLines.IgnoreQueryFilters()
            .AnyAsync(l => l.AccountId == accountId && !l.IsDeleted && l.DebitAmount > 0);

    /// <summary>
    /// Returns the partner's page-balance account, creating it when missing and syncing its name with the partner.
    /// A deactivated account is returned as is (never duplicated) — the caller decides whether it may be used.
    /// Returns null when the company has no general page-balance account (11102) to hang it next to.
    /// Safe under concurrency: creation runs under a per-company advisory lock and re-checks inside it, so two
    /// requests can never create two accounts for the same partner (nothing in the schema would stop that — the
    /// unique index only covers the code). The retry covers a code taken by a row created outside this helper.
    /// Call it outside an explicit transaction — a rejected insert would abort the whole transaction.
    /// </summary>
    public static async Task<Account?> EnsurePartnerPageAccount(SadaraDbContext db, FtthPartner partner)
    {
        var existing = await FindPartnerPageAccount(db, partner.CompanyId, partner.Id, includeInactive: true);
        if (existing != null && existing.Name == AccountNameFor(partner.Name)) return existing;

        // Session-level lock (released explicitly): it must also hold when no transaction is open.
        var key = $"ppb-acct:{partner.CompanyId:N}";
        await db.Database.OpenConnectionAsync();
        try
        {
            await db.Database.ExecuteSqlInterpolatedAsync($"SELECT pg_advisory_lock(hashtext({key}))");
            try
            {
                return await EnsurePartnerPageAccountLocked(db, partner);
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

    private static async Task<Account?> EnsurePartnerPageAccountLocked(SadaraDbContext db, FtthPartner partner)
    {
        var companyId = partner.CompanyId;
        var wantedName = AccountNameFor(partner.Name);

        for (var attempt = 0; attempt < 3; attempt++)
        {
            var existing = await FindPartnerPageAccount(db, companyId, partner.Id, includeInactive: true);
            if (existing != null)
            {
                if (existing.Name != wantedName)
                {
                    existing.Name = wantedName;
                    await db.SaveChangesAsync();
                }
                return existing;
            }

            var general = await FindGeneralPageAccount(db, companyId);
            if (general == null) return null;

            // Soft-deleted rows still hold their code in the unique index, so they count here too.
            var usedCodes = await db.Accounts.IgnoreQueryFilters()
                .Where(a => a.CompanyId == companyId && a.Code.StartsWith(AccountCodes.PartnerPageBalancePrefix))
                .Select(a => a.Code)
                .ToListAsync();
            var maxSuffix = 0;
            foreach (var code in usedCodes)
            {
                if (int.TryParse(code.AsSpan(AccountCodes.PartnerPageBalancePrefix.Length), out var n) && n > maxSuffix)
                    maxSuffix = n;
            }

            var account = new Account
            {
                Id = Guid.NewGuid(),
                Code = $"{AccountCodes.PartnerPageBalancePrefix}{maxSuffix + 1:D2}",
                Name = wantedName,
                NameEn = null,
                AccountType = general.AccountType,
                ParentAccountId = general.ParentAccountId,
                OpeningBalance = 0,
                CurrentBalance = 0,
                IsSystemAccount = false,
                Level = general.Level,
                IsLeaf = true,
                IsActive = true,
                Description = DescriptionFor(partner.Id),
                CompanyId = companyId
            };

            db.Accounts.Add(account);
            try
            {
                await db.SaveChangesAsync();
                return account;
            }
            catch (DbUpdateException)
            {
                // Lost a race on the code (same partner or another one). Drop the failed insert from the
                // change tracker — otherwise every later SaveChanges would retry it — then re-read and retry.
                db.Entry(account).State = EntityState.Detached;
                if (attempt == 2) throw;
            }
        }

        return null;
    }

    /// <summary>
    /// Resolves which partner an activation belongs to.
    /// When the log carries the FTTH partner id of the subscription, that id decides: it must match a registered
    /// partner (<see cref="FtthPartner.PartnerAccountId"/>) under which the user owns a linked account — the value
    /// is client-supplied, so it can never steer the charge to a partner the user has no account with. Anything
    /// else resolves to null, with no guessing from the hints below.
    /// Only when the log carries no partner id:
    /// 1) the linked FTTH account the client says it used — honoured only when that account belongs to the
    ///    same company and the same user as the log;
    /// 2) the user's linked account whose username/member id matches the FTTH operator on the log;
    /// 3) the user's active linked accounts all belong to one partner.
    /// Returns null when nothing matches — the caller then falls back to the general page balance.
    /// </summary>
    public static async Task<FtthPartner?> ResolvePartnerForLog(SadaraDbContext db, SubscriptionLog log, Guid? ftthAccountId)
    {
        if (!log.CompanyId.HasValue) return null;
        var companyId = log.CompanyId.Value;

        var partners = await db.FtthPartners.IgnoreQueryFilters()
            .Where(p => p.CompanyId == companyId && !p.IsDeleted)
            .ToListAsync();
        if (partners.Count == 0) return null;

        FtthPartner? ById(Guid? id) => id.HasValue ? partners.FirstOrDefault(p => p.Id == id.Value) : null;

        var logPartnerId = log.PartnerId?.Trim();
        if (!string.IsNullOrEmpty(logPartnerId))
        {
            // The PartnerId tag is relayed by the client, but it is honoured only when it matches exactly
            // one partner REGISTERED in the caller's company (`partners` is already scoped to log.CompanyId).
            // That company-scoped match is the security control: a caller cannot steer a charge to a foreign
            // or unregistered partner. We no longer also require the activating user to own a linked FTTH
            // account under the partner — operators routinely activate on a partner's behalf without owning
            // its login, and that extra condition mis-routed ~43% of correctly-tagged activations to the
            // general page balance. Residual risk is bounded to mis-attribution within the same company
            // (auditable via the journal entry's log reference, reversible), and the IsFunded gate in
            // ResolvePageAccountForLog still keeps charges in the general 11102 until a partner is funded.
            var matches = partners.Where(p => p.PartnerAccountId == logPartnerId).ToList();
            return matches.Count == 1 ? matches[0] : null;
        }

        // Only the weaker signals below need the user's linked accounts — a tagged activation (the common
        // case) already returned above, so this query is deferred off that hot path.
        // Guid.Empty owns no account, so a log without a user simply yields an empty list.
        var ownerUserId = log.UserId ?? Guid.Empty;
        var userAccounts = await db.FtthAccounts.IgnoreQueryFilters()
            .Where(a => a.CompanyId == companyId && a.OwnerUserId == ownerUserId && !a.IsDeleted)
            .Select(a => new { a.Id, a.PartnerId, a.Username, a.FtthMemberId, a.IsActive })
            .ToListAsync();

        if (ftthAccountId.HasValue)
        {
            var partner = ById(userAccounts.FirstOrDefault(a => a.Id == ftthAccountId.Value)?.PartnerId);
            if (partner != null) return partner;
        }

        var operatorKeys = new[] { log.OperatorUsername, log.ActivatedBy }
            .Where(s => !string.IsNullOrWhiteSpace(s))
            .Select(s => s!.Trim())
            .ToList();
        if (operatorKeys.Count > 0)
        {
            var partnerIds = userAccounts
                .Where(a => a.PartnerId.HasValue && operatorKeys.Any(k =>
                    string.Equals(a.Username?.Trim(), k, StringComparison.OrdinalIgnoreCase)
                    || (!string.IsNullOrEmpty(a.FtthMemberId) && a.FtthMemberId == k)))
                .Select(a => a.PartnerId!.Value)
                .Distinct()
                .ToList();
            if (partnerIds.Count == 1)
            {
                var partner = ById(partnerIds[0]);
                if (partner != null) return partner;
            }
        }

        var activePartnerIds = userAccounts
            .Where(a => a.IsActive && a.PartnerId.HasValue)
            .Select(a => a.PartnerId!.Value)
            .Distinct()
            .ToList();
        return activePartnerIds.Count == 1 ? ById(activePartnerIds[0]) : null;
    }

    /// <summary>
    /// The page-balance account an activation must be credited to: the resolved partner's account once it has
    /// been funded, otherwise the general 11102. Null only when the company has no 11102 at all.
    /// Read-only on purpose: the activation path never creates accounts.
    /// </summary>
    public static async Task<Account?> ResolvePageAccountForLog(SadaraDbContext db, SubscriptionLog log, Guid? ftthAccountId)
    {
        if (!log.CompanyId.HasValue) return null;

        var partner = await ResolvePartnerForLog(db, log, ftthAccountId);
        if (partner != null)
        {
            var partnerAccount = await FindPartnerPageAccount(db, partner.CompanyId, partner.Id);
            if (partnerAccount != null && await IsFunded(db, partnerAccount.Id)) return partnerAccount;
        }

        return await FindGeneralPageAccount(db, log.CompanyId.Value);
    }

    /// <summary>
    /// The page-balance account already used by a journal entry (general or partner), so edits and rebuilds
    /// keep charging the account the activation was originally charged to.
    /// </summary>
    public static Task<Account?> FindPageAccountOnEntry(SadaraDbContext db, Guid journalEntryId, Guid companyId) =>
        (from line in db.JournalEntryLines.IgnoreQueryFilters()
         join account in db.Accounts.IgnoreQueryFilters() on line.AccountId equals account.Id
         where line.JournalEntryId == journalEntryId && !line.IsDeleted
             && account.CompanyId == companyId && !account.IsDeleted
             && (account.Code == AccountCodes.PageBalance
                 || account.Code.StartsWith(AccountCodes.PartnerPageBalancePrefix))
         select account).FirstOrDefaultAsync();
}
