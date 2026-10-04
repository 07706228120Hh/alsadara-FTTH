using Microsoft.EntityFrameworkCore;
using Sadara.Application.Interfaces;
using Sadara.Infrastructure.Data;

namespace Sadara.API.Services;

/// <summary>
/// خدمة المزامنة الخلفية الدورية لوحدة «وكيل SAS».
///
/// الفكرة (مقابل FtthSyncBackgroundService الثقيل): لقطة مشتركي الساس تعيش في قاعدة خدمة Python،
/// وهذه الخدمة تكتفي بـ**تحفيز** مزامنة كل حساب ساس دورياً عبر البوّابة → Python → SAS4،
/// فيبقى «المحلي السريع» حديثاً دائماً (نموذج «محلي أولاً + تحديث خلفي»).
///
/// العزل محفوظ: كل حساب يُزامَن باعتماده هو (يُفكّ تشفيره في الذاكرة فقط لحظة التمرير).
/// الفاصل يحترم <see cref="Sadara.Domain.Entities.CompanySasSettings"/> لكل شركة (الافتراضي 15 دقيقة).
/// الفشل معزول لكل حساب (لا يُوقف البقية) ويُسجَّل في <c>SasAccount.SyncStatus</c>.
/// </summary>
public class SasSyncBackgroundService : BackgroundService
{
    /// <summary>الفاصل الافتراضي بين مزامنتين لحساب حين لا توجد إعدادات شركة.</summary>
    private const int DefaultIntervalMinutes = 15;

    /// <summary>كم مرّة نفحص الحسابات المستحقّة للمزامنة.</summary>
    private static readonly TimeSpan CheckInterval = TimeSpan.FromMinutes(5);

    /// <summary>حدّ أقصى للمزامنات المتوازية (حماية من ضغط SAS4/الخدمة).</summary>
    private const int MaxParallel = 3;

    private readonly IServiceScopeFactory _scopeFactory;
    private readonly ILogger<SasSyncBackgroundService> _logger;

    public SasSyncBackgroundService(
        IServiceScopeFactory scopeFactory, ILogger<SasSyncBackgroundService> logger)
    {
        _scopeFactory = scopeFactory;
        _logger = logger;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        _logger.LogInformation("SAS Sync Background Service started");
        // تأخير بدء بسيط ليكمل الإقلاع قبل أول فحص.
        await Task.Delay(TimeSpan.FromSeconds(45), stoppingToken);

        while (!stoppingToken.IsCancellationRequested)
        {
            try { await RunDueSyncsAsync(stoppingToken); }
            catch (Exception ex) when (ex is not OperationCanceledException)
            { _logger.LogError(ex, "خطأ في حلقة مزامنة الساس الخلفية"); }

            await Task.Delay(CheckInterval, stoppingToken);
        }
    }

    private async Task RunDueSyncsAsync(CancellationToken ct)
    {
        using var scope = _scopeFactory.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<SadaraDbContext>();
        var now = DateTime.UtcNow;

        // إعدادات الساس لكل شركة (الفاصل + التفعيل) — خريطة سريعة.
        var settings = await db.CompanySasSettings
            .AsNoTracking()
            .Where(s => !s.IsDeleted)
            .ToDictionaryAsync(s => s.CompanyId, ct);

        // الحسابات المفعّلة غير المحذوفة.
        var accounts = await db.SasAccounts
            .Where(a => a.IsActive && !a.IsDeleted)
            .ToListAsync(ct);

        // رشّح المستحقّين: الشركة مفعّلة المزامنة + مرّ الفاصل منذ آخر مزامنة.
        var due = new List<Sadara.Domain.Entities.SasAccount>();
        foreach (var acc in accounts)
        {
            settings.TryGetValue(acc.CompanyId, out var cs);
            if (cs != null && !cs.IsAutoSyncEnabled) continue; // الشركة أوقفت المزامنة التلقائية

            var interval = (cs != null && cs.SyncIntervalMinutes > 0)
                ? cs.SyncIntervalMinutes
                : DefaultIntervalMinutes;

            if (acc.LastSyncAt.HasValue &&
                (now - acc.LastSyncAt.Value).TotalMinutes < interval)
                continue; // زُومن حديثاً

            due.Add(acc);
        }

        if (due.Count == 0) return;
        _logger.LogInformation("SAS auto-sync: {Count} حساب مستحقّ للمزامنة", due.Count);

        // مزامنة بتوازٍ محدود؛ كل حساب في نطاق خدمة مستقل (DbContext/عميل مستقلّان).
        var sem = new SemaphoreSlim(MaxParallel);
        var tasks = due.Select(async acc =>
        {
            await sem.WaitAsync(ct);
            try { await SyncOneAsync(acc.Id, ct); }
            finally { sem.Release(); }
        });
        await Task.WhenAll(tasks);
    }

    /// <summary>مزامنة حساب واحد بنطاق مستقل — يُفكّ الاعتماد في الذاكرة فقط ويُحدَّث LastSyncAt/SyncStatus.</summary>
    private async Task SyncOneAsync(Guid accountId, CancellationToken ct)
    {
        using var scope = _scopeFactory.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<SadaraDbContext>();
        var protector = scope.ServiceProvider.GetRequiredService<ISecretProtector>();
        var sasClient = scope.ServiceProvider.GetRequiredService<ISasServiceClient>();

        var acc = await db.SasAccounts.FirstOrDefaultAsync(
            a => a.Id == accountId && a.IsActive && !a.IsDeleted, ct);
        if (acc == null) return;

        try
        {
            var password = protector.Unprotect(acc.PasswordEncrypted); // في الذاكرة فقط
            await sasClient.SyncAccountAsync(acc.ServerUrl, acc.Username, password, acc.Id.ToString(), ct);
            acc.LastSyncAt = DateTime.UtcNow;
            acc.SyncStatus = "ok";
            await db.SaveChangesAsync(ct);
        }
        catch (OperationCanceledException) { throw; }
        catch (Exception ex)
        {
            // فشل معزول: نُحدّث الحالة ولا نُسقط بقية الحسابات. لا نطبع الأسرار.
            _logger.LogWarning("فشل مزامنة حساب الساس {AccountId}: {Error}", acc.Id, ex.Message);
            acc.LastSyncAt = DateTime.UtcNow; // نؤخّر إعادة المحاولة للفاصل التالي (تفادي عاصفة إعادة)
            acc.SyncStatus = "error";
            try { await db.SaveChangesAsync(ct); } catch { /* تجاهل */ }
        }
    }
}
