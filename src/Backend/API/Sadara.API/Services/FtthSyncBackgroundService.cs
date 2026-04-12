using System.Net;
using System.Net.Http.Headers;
using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using Sadara.Domain.Entities;
using Sadara.Infrastructure.Data;

namespace Sadara.API.Services;

/// <summary>
/// خدمة المزامنة التلقائية — مطابقة تماماً لآلية التطبيق (sync_service.dart)
///
/// المراحل:
///   1. جلب الاشتراكات (10 صفحات متوازية، 150/صفحة، retry 3)
///   2. جلب التفاصيل FDT/FAT/GPS/Username (500 دفعة متوازية، 150 ID/دفعة، retry 3+5)
///   3. جلب الهواتف (500 طلب متوازي، timeout 3s، retry 3، تجديد token كل 10%)
///   4. حفظ في DB
/// </summary>
public class FtthSyncBackgroundService : BackgroundService
{
    private const string FtthBaseUrl = "https://admin.ftth.iq";
    private const string FtthClientApp = "53d57a7f-3f89-4e9d-873b-3d071bc6dd9f";

    // ═══ ثوابت مطابقة للتطبيق (sync_settings_service.dart defaults) ═══
    private const int PageSize = 150;                   // عدد العناصر في كل صفحة/دفعة
    private const int SubscriptionParallel = 10;         // اشتراكات: 10 صفحات متوازية — مثل التطبيق
    private const int DetailsParallel = 500;            // تفاصيل: 500 دفعة متوازية — مثل التطبيق
    private const int PhoneParallel = 500;              // هواتف: 500 طلب متوازي — مثل التطبيق
    private const int PhoneTimeoutSeconds = 3;          // timeout هاتف: 3 ثواني (مثل التطبيق)
    private const int DetailTimeoutSeconds = 90;        // timeout تفاصيل: 90 ثانية
    private const int SubscriptionTimeoutSeconds = 60;  // timeout اشتراك: 60 ثانية
    private const int MaxBatchRetries = 3;              // 3 محاولات إعادة للدفعات
    private const int MaxPageRetries = 5;               // 5 محاولات إعادة لكل طلب
    private const int PhoneBatchesBeforeSave = 10;      // تخزين الهواتف كل 10 دفعات

    private readonly IServiceScopeFactory _scopeFactory;
    private readonly ILogger<FtthSyncBackgroundService> _logger;
    private readonly Dictionary<Guid, CancellationTokenSource> _activeSyncs = new();

    // FTTH credentials للتجديد أثناء المزامنة
    private string _ftthUsername = "";
    private string _ftthPassword = "";

    public FtthSyncBackgroundService(IServiceScopeFactory scopeFactory, ILogger<FtthSyncBackgroundService> logger)
    {
        _scopeFactory = scopeFactory;
        _logger = logger;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        _logger.LogInformation("FTTH Sync Background Service started");
        await Task.Delay(TimeSpan.FromSeconds(30), stoppingToken);

        while (!stoppingToken.IsCancellationRequested)
        {
            try { await CheckAndRunSyncs(stoppingToken); }
            catch (Exception ex) when (ex is not OperationCanceledException)
            { _logger.LogError(ex, "Error in FTTH sync check loop"); }

            await Task.Delay(TimeSpan.FromMinutes(5), stoppingToken);
        }
    }

    private async Task CheckAndRunSyncs(CancellationToken stoppingToken)
    {
        using var scope = _scopeFactory.CreateScope();
        var context = scope.ServiceProvider.GetRequiredService<SadaraDbContext>();
        var now = DateTime.UtcNow;

        var allSettings = await context.CompanyFtthSettings
            .Where(x => !x.IsDeleted).ToListAsync(stoppingToken);

        foreach (var settings in allSettings)
        {
            if (stoppingToken.IsCancellationRequested) break;
            if (_activeSyncs.ContainsKey(settings.CompanyId)) continue;

            if (settings.IsSyncInProgress)
            {
                var pendingLog = await context.FtthSyncLogs
                    .Where(x => x.CompanyId == settings.CompanyId && x.Status == "InProgress")
                    .OrderByDescending(x => x.StartedAt)
                    .FirstOrDefaultAsync(stoppingToken);

                if (pendingLog != null)
                {
                    _ = Task.Run(() => RunSyncForCompany(settings.CompanyId, pendingLog.Id, pendingLog.TriggerSource), CancellationToken.None);
                    continue;
                }
            }

            if (!settings.IsAutoSyncEnabled) continue;
            if (now.Hour < settings.SyncStartHour || now.Hour >= settings.SyncEndHour) continue;
            if (settings.LastSyncAt.HasValue && (now - settings.LastSyncAt.Value).TotalMinutes < settings.SyncIntervalMinutes) continue;

            // إيقاف المزامنة التلقائية بعد 3 فشل متتالي — لتجنب حظر IP
            // تُستأنف بعد ساعة أو عند trigger يدوي
            if (settings.ConsecutiveFailures >= 3)
            {
                // السماح بمحاولة واحدة كل ساعة
                if (settings.UpdatedAt.HasValue && (now - settings.UpdatedAt.Value).TotalHours < 1)
                    continue;
                _logger.LogInformation("Auto-sync paused for {CompanyId} ({Failures} failures), retrying after 1 hour cooldown",
                    settings.CompanyId, settings.ConsecutiveFailures);
            }

            settings.IsSyncInProgress = true;
            context.CompanyFtthSettings.Update(settings);
            var log = new FtthSyncLog { CompanyId = settings.CompanyId, StartedAt = DateTime.UtcNow, Status = "InProgress", TriggerSource = "Auto" };
            context.FtthSyncLogs.Add(log);
            await context.SaveChangesAsync(stoppingToken);

            _ = Task.Run(() => RunSyncForCompany(settings.CompanyId, log.Id, "Auto"), CancellationToken.None);
        }
    }

    // ═══════════════════════════════════════════════════════════
    // تنفيذ المزامنة الكاملة — 4 مراحل
    // ═══════════════════════════════════════════════════════════

    private async Task RunSyncForCompany(Guid companyId, long logId, string triggerSource)
    {
        var cts = new CancellationTokenSource();
        _activeSyncs[companyId] = cts;
        var stopwatch = System.Diagnostics.Stopwatch.StartNew();

        try
        {
            using var scope = _scopeFactory.CreateScope();
            var context = scope.ServiceProvider.GetRequiredService<SadaraDbContext>();
            var settings = await context.CompanyFtthSettings.FirstOrDefaultAsync(x => x.CompanyId == companyId && !x.IsDeleted);
            if (settings == null) return;

            _ftthUsername = settings.FtthUsername;
            _ftthPassword = settings.FtthPassword;

            _logger.LogInformation("=== FTTH SYNC START === Company: {Id}, Trigger: {Trigger}", companyId, triggerSource);

            // ── المرحلة 0: تسجيل الدخول ──
            await UpdateProgress(companyId, "login", 2, "تسجيل الدخول إلى FTTH...", 0, 0);
            _logger.LogInformation("Logging in to FTTH with user: {User}", _ftthUsername);
            var token = await LoginToFtth(_ftthUsername, _ftthPassword);
            if (string.IsNullOrEmpty(token))
            { await FinishSync(context, settings, logId, stopwatch, false, "فشل تسجيل الدخول إلى FTTH", 0, 0, 0, 0, 0); return; }
            _logger.LogInformation("FTTH login successful, token length: {Len}", token.Length);

            // ── المرحلة 1: جلب الاشتراكات (5% → 25%) ──
            await UpdateProgress(companyId, "subscribers", 5, "جلب الاشتراكات...", 0, 0);
            var subscribers = await FetchAllSubscriptions(token, cts.Token, companyId);
            if (cts.Token.IsCancellationRequested)
            { await FinishSync(context, settings, logId, stopwatch, false, "تم الإلغاء", subscribers.Count, 0, 0, 0, 0, "Cancelled"); return; }

            // ── المرحلة 1.5: حفظ ذكي — مقارنة مع الموجود ──
            await UpdateProgress(companyId, "saving_subs", 26, "مقارنة وحفظ الاشتراكات...", 0, subscribers.Count);
            var (newCount, updatedCount, skippedCount, deletedCount) = await SmartSaveSubscribers(context, companyId, subscribers);
            _logger.LogInformation("Smart save: {New} new, {Updated} updated, {Skipped} skipped, {Deleted} deleted",
                newCount, updatedCount, skippedCount, deletedCount);

            // ── المرحلة 2: جلب التفاصيل — فقط للناقصين ──
            // جلب من DB: المشتركين بدون تفاصيل
            var subsWithoutDetails = await context.FtthSubscriberCaches
                .Where(x => x.CompanyId == companyId && !x.IsDeleted && !x.DetailsFetched)
                .Select(x => x.CustomerId).Distinct().ToListAsync();

            int detailsCount = 0;
            if (subsWithoutDetails.Count > 0)
            {
                await UpdateProgress(companyId, "details", 30,
                    $"جلب تفاصيل {subsWithoutDetails.Count:N0} مشترك بدون تفاصيل...", 0, subsWithoutDetails.Count);
                token = await RefreshTokenIfNeeded(token);
                detailsCount = await FetchAndSaveDetails(token, context, companyId, subsWithoutDetails, cts.Token);
            }
            else
            {
                await UpdateProgress(companyId, "details", 55, "كل المشتركين لديهم تفاصيل ✅", 0, 0);
                _logger.LogInformation("Details: all subscribers have details, skipping");
            }

            // ── المرحلة 3: جلب الهواتف — فقط للناقصين ──
            var subsWithoutPhone = await context.FtthSubscriberCaches
                .Where(x => x.CompanyId == companyId && !x.IsDeleted && (x.Phone == "" || x.Phone == null))
                .Select(x => x.CustomerId).Distinct().ToListAsync();

            int phonesCount = 0;
            if (subsWithoutPhone.Count > 0)
            {
                await UpdateProgress(companyId, "phones", 60,
                    $"جلب هواتف {subsWithoutPhone.Count:N0} مشترك بدون رقم...", 0, subsWithoutPhone.Count);
                token = await RefreshTokenIfNeeded(token);
                phonesCount = await FetchAndSavePhones(token, context, companyId, subsWithoutPhone, cts.Token);
            }
            else
            {
                await UpdateProgress(companyId, "phones", 88, "كل المشتركين لديهم أرقام ✅", 0, 0);
                _logger.LogInformation("Phones: all subscribers have phones, skipping");
            }

            // ── النتيجة النهائية ──
            var totalInDb = await context.FtthSubscriberCaches.CountAsync(x => x.CompanyId == companyId && !x.IsDeleted);
            await UpdateProgress(companyId, "done", 100, "اكتملت المزامنة بنجاح ✅", totalInDb, totalInDb);

            await FinishSync(context, settings, logId, stopwatch, true, null, totalInDb, phonesCount, detailsCount, newCount, updatedCount);
            _logger.LogInformation("=== FTTH SYNC DONE === {Total} in DB, {New} new, {Updated} updated, {Skipped} skipped, {Deleted} deleted, {Phones} phones, {Details} details, {Duration}s",
                totalInDb, newCount, updatedCount, skippedCount, deletedCount, phonesCount, detailsCount, stopwatch.Elapsed.TotalSeconds);
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            _logger.LogError(ex, "FTTH sync failed for company {CompanyId}", companyId);
            try
            {
                using var scope2 = _scopeFactory.CreateScope();
                var ctx2 = scope2.ServiceProvider.GetRequiredService<SadaraDbContext>();
                var s = await ctx2.CompanyFtthSettings.FirstOrDefaultAsync(x => x.CompanyId == companyId && !x.IsDeleted);
                if (s != null) await FinishSync(ctx2, s, logId, stopwatch, false, ex.Message, 0, 0, 0, 0, 0);
            }
            catch (Exception innerEx) { _logger.LogError(innerEx, "Failed to update sync status after error"); }
        }
        finally { _activeSyncs.Remove(companyId); cts.Dispose(); }
    }

    // ═══════════════════════════════════════════════════════════
    // المرحلة 1: جلب الاشتراكات — مطابق لـ _fetchAllSubscribers
    // ═══════════════════════════════════════════════════════════

    private async Task<List<Dictionary<string, object?>>> FetchAllSubscriptions(string token, CancellationToken ct, Guid companyId)
    {
        var all = new List<Dictionary<string, object?>>();

        // الصفحة الأولى لمعرفة totalCount — مع retry
        string firstJson = "";
        for (int attempt = 1; attempt <= MaxPageRetries; attempt++)
        {
            try
            {
                using var c = CreateClient(token, SubscriptionTimeoutSeconds);
                firstJson = await c.GetStringAsync($"{FtthBaseUrl}/api/subscriptions?sortCriteria.property=expires&sortCriteria.direction=asc&hierarchyLevel=0&pageNumber=1&pageSize={PageSize}", ct);
                break;
            }
            catch when (attempt < MaxPageRetries)
            {
                _logger.LogWarning("First page attempt {A} failed, retrying...", attempt);
                await Task.Delay(TimeSpan.FromSeconds(attempt * 2), ct);
            }
        }
        if (string.IsNullOrEmpty(firstJson)) throw new Exception("فشل جلب الصفحة الأولى من الاشتراكات");
        var firstDoc = JsonDocument.Parse(firstJson);
        var totalCount = firstDoc.RootElement.TryGetProperty("totalCount", out var tc) ? tc.GetInt32() : 0;
        var totalPages = Math.Max(1, (int)Math.Ceiling((double)totalCount / PageSize));
        _logger.LogInformation("Subscriptions: {Total} total, {Pages} pages (parallel={Parallel})", totalCount, totalPages, SubscriptionParallel);

        foreach (var item in firstDoc.RootElement.GetProperty("items").EnumerateArray())
            all.Add(ConvertSubscription(item));

        // جلب باقي الصفحات — 10 متوازي مع retry 3
        var currentPage = 2;
        while (currentPage <= totalPages && !ct.IsCancellationRequested)
        {
            var endPage = Math.Min(currentPage + SubscriptionParallel - 1, totalPages);
            var pagesToFetch = Enumerable.Range(currentPage, endPage - currentPage + 1).ToList();

            var successful = new Dictionary<int, List<Dictionary<string, object?>>>();
            var failed = new List<int>(pagesToFetch);

            for (int retry = 0; retry < MaxBatchRetries && failed.Count > 0 && !ct.IsCancellationRequested; retry++)
            {
                if (retry > 0)
                {
                    _logger.LogInformation("Subscription retry: {Count} pages (attempt {A})", failed.Count, retry + 1);
                    await Task.Delay(TimeSpan.FromSeconds(retry * 2), ct);
                }
                var tasks = failed.Select(p => FetchOnePage(token, p, ct)).ToList();
                var results = await Task.WhenAll(tasks);
                var nextFailed = new List<int>();
                for (int i = 0; i < failed.Count; i++)
                { if (results[i].Count > 0) successful[failed[i]] = results[i]; else nextFailed.Add(failed[i]); }
                failed = nextFailed;
            }

            if (failed.Count > 0) _logger.LogWarning("Subscription: {Count} pages failed: [{Pages}]", failed.Count, string.Join(",", failed));
            foreach (var p in successful.Keys.OrderBy(k => k)) all.AddRange(successful[p]);

            currentPage = endPage + 1;
            var pct = 5 + (int)(20.0 * all.Count / Math.Max(totalCount, 1));
            await UpdateProgress(companyId, "subscribers", pct, $"جلب الاشتراكات: {all.Count:N0}/{totalCount:N0} — صفحة {Math.Min(endPage, totalPages)}/{totalPages}", all.Count, totalCount);
            if (currentPage <= totalPages && !ct.IsCancellationRequested) await Task.Delay(300, ct); // 300ms مثل التطبيق
        }

        _logger.LogInformation("Subscriptions done: {Count}/{Total}", all.Count, totalCount);
        return all;
    }

    private async Task<List<Dictionary<string, object?>>> FetchOnePage(string token, int pageNum, CancellationToken ct)
    {
        var url = $"{FtthBaseUrl}/api/subscriptions?sortCriteria.property=expires&sortCriteria.direction=asc&hierarchyLevel=0&pageNumber={pageNum}&pageSize={PageSize}";
        for (int attempt = 1; attempt <= MaxPageRetries; attempt++)
        {
            try
            {
                using var c = CreateClient(token, SubscriptionTimeoutSeconds);
                using var res = await c.GetAsync(url, ct);
                if (res.IsSuccessStatusCode)
                {
                    var doc = JsonDocument.Parse(await res.Content.ReadAsStringAsync(ct));
                    var result = new List<Dictionary<string, object?>>();
                    foreach (var item in doc.RootElement.GetProperty("items").EnumerateArray()) result.Add(ConvertSubscription(item));
                    return result;
                }
                if ((int)res.StatusCode == 418) { await Task.Delay(TimeSpan.FromSeconds(attempt * 5), ct); continue; }
            }
            catch (OperationCanceledException) { throw; }
            catch { if (attempt < MaxPageRetries) await Task.Delay(TimeSpan.FromSeconds(attempt * 2), ct); }
        }
        return new();
    }

    // ═══════════════════════════════════════════════════════════
    // المرحلة 2: جلب التفاصيل — مطابق لـ fetchSubscriptionAddresses
    // /api/addresses?accountIds=X&accountIds=Y (150 ID/دفعة، 500 متوازي)
    // ═══════════════════════════════════════════════════════════

    private async Task<int> FetchAndLinkDetails(string token, List<Dictionary<string, object?>> subscribers, CancellationToken ct, Guid companyId)
    {
        // جمع customerIds فريدة
        var customerIds = subscribers.Select(s => s["CustomerId"]?.ToString() ?? "").Where(id => !string.IsNullOrEmpty(id)).Distinct().ToList();
        _logger.LogInformation("Details: {Count} unique customers, parallel={Parallel}, pageSize={Size}", customerIds.Count, DetailsParallel, PageSize);

        // بناء lookup: customerId → subscribers
        var customerMap = new Dictionary<string, List<Dictionary<string, object?>>>();
        foreach (var sub in subscribers)
        {
            var cid = sub["CustomerId"]?.ToString() ?? "";
            if (string.IsNullOrEmpty(cid)) continue;
            if (!customerMap.ContainsKey(cid)) customerMap[cid] = new();
            customerMap[cid].Add(sub);
        }

        // تقسيم إلى دفعات (150 ID بالدفعة)
        var idBatches = new List<List<string>>();
        for (int i = 0; i < customerIds.Count; i += PageSize)
            idBatches.Add(customerIds.Skip(i).Take(PageSize).ToList());

        var totalBatches = idBatches.Count;
        int detailsLinked = 0;
        int currentBatch = 0;
        var failedBatchIds = new List<string>();
        var currentToken = token;

        // تجديد Token كل 10%
        var refreshInterval = Math.Max(1, totalBatches / 10);

        while (currentBatch < totalBatches && !ct.IsCancellationRequested)
        {
            var endBatch = Math.Min(currentBatch + DetailsParallel, totalBatches);
            var batchIndices = Enumerable.Range(currentBatch, endBatch - currentBatch).ToList();

            // تجديد Token كل 10%
            if (currentBatch > 0 && currentBatch % refreshInterval == 0)
            {
                _logger.LogInformation("Details: refreshing token at batch {B}/{T}", currentBatch, totalBatches);
                currentToken = await RefreshTokenIfNeeded(currentToken);
            }

            // جلب متوازي مع retry
            var successful = new Dictionary<int, List<(string customerId, JsonElement data)>>();
            var failed = new List<int>(batchIndices);

            for (int retry = 0; retry < MaxBatchRetries && failed.Count > 0 && !ct.IsCancellationRequested; retry++)
            {
                if (retry > 0) { await Task.Delay(TimeSpan.FromSeconds(retry * 2), ct); }
                var tasks = failed.Select(idx => FetchAddressesBatch(currentToken, idBatches[idx], ct)).ToList();
                var results = await Task.WhenAll(tasks);
                var nextFailed = new List<int>();
                for (int i = 0; i < failed.Count; i++)
                { if (results[i] != null && results[i]!.Count > 0) successful[failed[i]] = results[i]!; else nextFailed.Add(failed[i]); }
                failed = nextFailed;
            }

            if (failed.Count > 0)
                foreach (var idx in failed) failedBatchIds.AddAll(idBatches[idx]);

            // تطبيق النتائج على المشتركين
            foreach (var batchIdx in successful.Keys.OrderBy(k => k))
            {
                foreach (var (customerId, data) in successful[batchIdx])
                {
                    if (string.IsNullOrEmpty(customerId) || !customerMap.TryGetValue(customerId, out var subs)) continue;
                    if (data.ValueKind != JsonValueKind.Object) continue;
                    var dd = data.TryGetProperty("deviceDetails", out var d) && d.ValueKind == JsonValueKind.Object ? d : default;
                    var gps = data.TryGetProperty("gpsCoordinate", out var g) && g.ValueKind == JsonValueKind.Object ? g : default;
                    var username = dd.ValueKind != JsonValueKind.Undefined && dd.TryGetProperty("username", out var u) ? u.ToString() : "";
                    var fdtName = dd.ValueKind != JsonValueKind.Undefined && dd.TryGetProperty("fdt", out var fdt) && fdt.TryGetProperty("displayValue", out var fdtV) ? fdtV.ToString() : "";
                    var fatName = dd.ValueKind != JsonValueKind.Undefined && dd.TryGetProperty("fat", out var fat) && fat.TryGetProperty("displayValue", out var fatV) ? fatV.ToString() : "";
                    var serial = dd.ValueKind != JsonValueKind.Undefined && dd.TryGetProperty("serial", out var s) ? s.ToString() : "";
                    var gpsLat = gps.ValueKind != JsonValueKind.Undefined && gps.TryGetProperty("latitude", out var lat) ? lat.ToString() : "";
                    var gpsLng = gps.ValueKind != JsonValueKind.Undefined && gps.TryGetProperty("longitude", out var lng) ? lng.ToString() : "";
                    var isTrial = data.TryGetProperty("isTrial", out var tr) && tr.ValueKind == JsonValueKind.True;
                    var isPending = data.TryGetProperty("isPending", out var pn) && pn.ValueKind == JsonValueKind.True;

                    foreach (var sub in subs)
                    {
                        if (!string.IsNullOrEmpty(username)) sub["Username"] = username;
                        sub["FdtName"] = fdtName; sub["FatName"] = fatName;
                        sub["DeviceSerial"] = serial; sub["GpsLat"] = gpsLat; sub["GpsLng"] = gpsLng;
                        sub["IsTrial"] = isTrial; sub["IsPending"] = isPending;
                        sub["DetailsFetched"] = true; sub["DetailsFetchedAt"] = DateTime.UtcNow;
                        detailsLinked++;
                    }
                }
            }

            currentBatch = endBatch;
            var pct = 25 + (int)(30.0 * currentBatch / Math.Max(totalBatches, 1));
            await UpdateProgress(companyId, "details", pct, $"جلب التفاصيل: {detailsLinked:N0} — دفعة {currentBatch}/{totalBatches}", currentBatch, totalBatches);
            if (currentBatch < totalBatches && !ct.IsCancellationRequested) await Task.Delay(3000, ct);
        }

        // محاولة نهائية للفاشلين بدفعات صغيرة (5 IDs بالمرة) — مثل التطبيق
        if (failedBatchIds.Count > 0 && !ct.IsCancellationRequested)
        {
            _logger.LogInformation("Details: final retry for {Count} failed IDs", failedBatchIds.Count);
            currentToken = await RefreshTokenIfNeeded(currentToken);
            for (int i = 0; i < failedBatchIds.Count && !ct.IsCancellationRequested; i += 5)
            {
                var microBatch = failedBatchIds.Skip(i).Take(5).ToList();
                var result = await FetchAddressesBatch(currentToken, microBatch, ct);
                if (result != null)
                {
                    foreach (var (cid, data) in result)
                    {
                        if (!customerMap.TryGetValue(cid, out var subs)) continue;
                        var dd = data.TryGetProperty("deviceDetails", out var d) ? d : default;
                        foreach (var sub in subs)
                        {
                            sub["DetailsFetched"] = true; sub["DetailsFetchedAt"] = DateTime.UtcNow;
                            if (dd.ValueKind != JsonValueKind.Undefined)
                            {
                                if (dd.TryGetProperty("username", out var u2)) sub["Username"] = u2.ToString();
                                if (dd.TryGetProperty("fdt", out var f) && f.TryGetProperty("displayValue", out var fv)) sub["FdtName"] = fv.ToString();
                                if (dd.TryGetProperty("fat", out var fa) && fa.TryGetProperty("displayValue", out var fav)) sub["FatName"] = fav.ToString();
                                if (dd.TryGetProperty("serial", out var se)) sub["DeviceSerial"] = se.ToString();
                            }
                            detailsLinked++;
                        }
                    }
                }
                await Task.Delay(3000, ct); // 3 ثواني بين المحاولات النهائية — مثل التطبيق
            }
        }

        _logger.LogInformation("Details done: {Count} linked", detailsLinked);
        return detailsLinked;
    }

    private async Task<List<(string customerId, JsonElement data)>?> FetchAddressesBatch(string token, List<string> ids, CancellationToken ct)
    {
        try
        {
            var query = string.Join("&", ids.Select(id => $"accountIds={id}"));
            using var c = CreateClient(token, DetailTimeoutSeconds);
            var response = await c.GetStringAsync($"{FtthBaseUrl}/api/addresses?{query}", ct);
            var doc = JsonDocument.Parse(response);

            // التعامل مع أنواع استجابة مختلفة — مثل التطبيق
            JsonElement items;
            if (doc.RootElement.ValueKind == JsonValueKind.Array) items = doc.RootElement;
            else if (doc.RootElement.TryGetProperty("items", out var ip) && ip.ValueKind == JsonValueKind.Array) items = ip;
            else if (doc.RootElement.ValueKind == JsonValueKind.Object) { return new List<(string, JsonElement)> { ExtractCustomerId(doc.RootElement) }; }
            else return null;

            var results = new List<(string, JsonElement)>();
            foreach (var item in items.EnumerateArray())
            {
                if (item.ValueKind != JsonValueKind.Object) continue; // تخطي null
                var entry = ExtractCustomerId(item);
                if (!string.IsNullOrEmpty(entry.customerId)) results.Add(entry);
            }
            return results;
        }
        catch (Exception ex)
        {
            _logger.LogWarning("FetchAddressesBatch failed for {Count} IDs: {Error}", ids.Count, ex.Message);
            return null;
        }
    }

    private (string customerId, JsonElement data) ExtractCustomerId(JsonElement item)
    {
        var cid = "";
        if (item.TryGetProperty("customer", out var cust) && cust.ValueKind == JsonValueKind.Object && cust.TryGetProperty("id", out var cidP))
            cid = cidP.ToString();
        if (string.IsNullOrEmpty(cid) && item.TryGetProperty("accountId", out var aid))
            cid = aid.ToString();
        if (string.IsNullOrEmpty(cid) && item.TryGetProperty("customerId", out var cid2))
            cid = cid2.ToString();
        return (cid, item);
    }

    // ═══════════════════════════════════════════════════════════
    // المرحلة 3: جلب الهواتف — مطابق لـ fetchPhoneNumbers
    // GET /api/customers/{id} → model.primaryContact.mobile
    // 500 متوازي، timeout 3s، retry 3، تجديد token كل 10%
    // ═══════════════════════════════════════════════════════════

    private async Task<int> FetchAndLinkPhones(string token, List<Dictionary<string, object?>> subscribers, CancellationToken ct, Guid companyId)
    {
        // جمع customerIds فريدة — مثل التطبيق (.toSet())
        var customerToSubs = new Dictionary<string, List<Dictionary<string, object?>>>();
        foreach (var sub in subscribers)
        {
            var cid = sub["CustomerId"]?.ToString() ?? "";
            if (string.IsNullOrEmpty(cid)) continue;
            if (!customerToSubs.ContainsKey(cid)) customerToSubs[cid] = new();
            customerToSubs[cid].Add(sub);
        }
        var customerIds = customerToSubs.Keys.ToList();
        _logger.LogInformation("Phones: {Count} unique customers, parallel={P}, timeout={T}s", customerIds.Count, PhoneParallel, PhoneTimeoutSeconds);

        int phonesLinked = 0;
        int totalFetched = 0;
        var currentToken = token;

        // حساب المجموعات — مثل التطبيق
        var totalBatches = (int)Math.Ceiling((double)customerIds.Count / PhoneParallel);
        var totalSaveGroups = (int)Math.Ceiling((double)totalBatches / PhoneBatchesBeforeSave);
        var refreshInterval = Math.Max(1, totalSaveGroups / 10); // تجديد كل 10%
        int lastRefreshAt = 0;

        int currentIndex = 0;
        int batchNum = 0;
        int saveGroupNum = 0;
        var customersToUpdate = new List<(string customerId, string phone)>();

        while (currentIndex < customerIds.Count && !ct.IsCancellationRequested)
        {
            saveGroupNum++;

            // تجديد Token كل 10% — مطابق للتطبيق
            if (saveGroupNum - lastRefreshAt >= refreshInterval && saveGroupNum > 1)
            {
                _logger.LogInformation("Phones: refreshing token at group {G}/{T}", saveGroupNum, totalSaveGroups);
                currentToken = await RefreshTokenIfNeeded(currentToken);
                lastRefreshAt = saveGroupNum;
            }

            // جلب 10 دفعات متوازية قبل التخزين — مطابق للتطبيق
            for (int b = 0; b < PhoneBatchesBeforeSave && currentIndex < customerIds.Count && !ct.IsCancellationRequested; b++)
            {
                batchNum++;
                var endIndex = Math.Min(currentIndex + PhoneParallel, customerIds.Count);
                var batch = customerIds.GetRange(currentIndex, endIndex - currentIndex);

                // جلب متوازي مع retry — مطابق للتطبيق
                var successfulResults = new Dictionary<string, string>();
                var failedIds = new List<string>(batch);

                for (int retry = 0; retry < MaxBatchRetries && failedIds.Count > 0 && !ct.IsCancellationRequested; retry++)
                {
                    if (retry > 0) await Task.Delay(TimeSpan.FromSeconds(retry * 2), ct);

                    var tasks = failedIds.Select(cid => FetchPhoneOnly(currentToken, cid, ct)).ToList();
                    var results = await Task.WhenAll(tasks);

                    var nextFailed = new List<string>();
                    for (int i = 0; i < failedIds.Count; i++)
                    {
                        if (results[i] != null) successfulResults[failedIds[i]] = results[i]!;
                        else nextFailed.Add(failedIds[i]);
                    }
                    failedIds = nextFailed;
                }

                foreach (var kv in successfulResults) customersToUpdate.Add((kv.Key, kv.Value));
                totalFetched += batch.Count;
                currentIndex = endIndex;

                // تحديث التقدم
                var pct = 55 + (int)(33.0 * currentIndex / Math.Max(customerIds.Count, 1));
                await UpdateProgress(companyId, "phones", pct,
                    $"جلب الهواتف: {customersToUpdate.Count:N0} رقم — {currentIndex:N0}/{customerIds.Count:N0} مشترك",
                    currentIndex, customerIds.Count);
            }

            // تطبيق النتائج على المشتركين — مطابق للتطبيق
            foreach (var (cid, phone) in customersToUpdate)
            {
                if (customerToSubs.TryGetValue(cid, out var subs))
                    foreach (var sub in subs) sub["Phone"] = phone;
                phonesLinked++;
            }
            customersToUpdate.Clear();

            // انتظار بين مجموعات التخزين — مطابق للتطبيق (3 ثواني)
            if (currentIndex < customerIds.Count && !ct.IsCancellationRequested)
                await Task.Delay(3000, ct);
        }

        _logger.LogInformation("Phones done: {Found}/{Total}", phonesLinked, customerIds.Count);
        return phonesLinked;
    }

    /// <summary>جلب رقم هاتف واحد — مطابق لـ _fetchPhoneOnly في التطبيق</summary>
    private async Task<string?> FetchPhoneOnly(string token, string customerId, CancellationToken ct)
    {
        try
        {
            using var c = CreateClient(token, PhoneTimeoutSeconds); // timeout 3 ثواني مثل التطبيق
            var json = await c.GetStringAsync($"{FtthBaseUrl}/api/customers/{customerId}", ct);
            var doc = JsonDocument.Parse(json);

            if (doc.RootElement.TryGetProperty("model", out var model)
                && model.TryGetProperty("primaryContact", out var contact)
                && contact.TryGetProperty("mobile", out var mobile))
            {
                var phone = mobile.GetString();
                if (!string.IsNullOrEmpty(phone)) return phone;
            }
        }
        catch { /* تجاهل — مثل التطبيق */ }
        return null;
    }

    // ═══════════════════════════════════════════════════════════
    // حفظ ذكي — مقارنة + insert/update/skip/delete
    // ═══════════════════════════════════════════════════════════

    private async Task<(int newCount, int updatedCount, int skippedCount, int deletedCount)> SmartSaveSubscribers(
        SadaraDbContext context, Guid companyId, List<Dictionary<string, object?>> subscribers)
    {
        int newCount = 0, updatedCount = 0, skippedCount = 0, deletedCount = 0;

        // جلب كل الموجودين في DB (بما فيها المحذوفة soft delete)
        var existingAll = await context.FtthSubscriberCaches
            .IgnoreQueryFilters()
            .Where(x => x.CompanyId == companyId)
            .ToListAsync();
        var existingMap = new Dictionary<string, FtthSubscriberCache>();
        foreach (var e in existingAll)
        {
            existingMap.TryAdd(e.SubscriptionId, e); // أول واحد يكسب إذا تكرر
        }

        // تتبع أي subscriptionIds جاءت من FTTH + تجنب التكرار من API
        var ftthIds = new HashSet<string>();
        var processedInThisBatch = new HashSet<string>();

        foreach (var sub in subscribers)
        {
            var subId = sub["SubscriptionId"]?.ToString() ?? "";
            if (string.IsNullOrEmpty(subId)) continue;
            ftthIds.Add(subId);

            // تجنب معالجة نفس الـ ID مرتين (API يرجع تكرارات أحياناً)
            if (!processedInThisBatch.Add(subId)) continue;

            if (existingMap.TryGetValue(subId, out var existing))
            {
                // إذا كان محذوف soft delete — أعد إحيائه
                if (existing.IsDeleted)
                {
                    existing.IsDeleted = false;
                    existing.DeletedAt = null;
                }
                // موجود — هل تغيّر؟
                var newStatus = sub["Status"]?.ToString() ?? "";
                var newExpires = sub["Expires"]?.ToString() ?? "";
                var newDisplayName = sub["DisplayName"]?.ToString() ?? "";

                if (existing.Status == newStatus && existing.Expires == newExpires && existing.DisplayName == newDisplayName)
                {
                    skippedCount++; // لم يتغير — لا نكتب
                    continue;
                }

                // تغيّر — نحدّث الحقول الأساسية فقط (لا نمسح التفاصيل والهاتف!)
                existing.CustomerId = sub["CustomerId"]?.ToString() ?? existing.CustomerId;
                existing.DisplayName = newDisplayName;
                existing.Status = newStatus;
                existing.AutoRenew = sub["AutoRenew"] is bool ar && ar;
                existing.ProfileName = sub["ProfileName"]?.ToString() ?? existing.ProfileName;
                existing.BundleId = sub["BundleId"]?.ToString();
                existing.ZoneId = sub["ZoneId"]?.ToString();
                existing.ZoneName = sub["ZoneName"]?.ToString() ?? existing.ZoneName;
                existing.StartedAt = sub["StartedAt"]?.ToString();
                existing.Expires = newExpires;
                existing.CommitmentPeriod = sub["CommitmentPeriod"]?.ToString();
                existing.LockedMac = sub["LockedMac"]?.ToString();
                existing.IsSuspended = sub["IsSuspended"] is bool isSusp && isSusp;
                existing.SuspensionReason = sub["SuspensionReason"]?.ToString();
                existing.ServicesJson = sub["ServicesJson"]?.ToString();
                existing.UpdatedAt = DateTime.UtcNow;
                // لا نمسح: Phone, FdtName, FatName, Username, DetailsFetched — هذه تُجلب في مراحل لاحقة
                context.FtthSubscriberCaches.Update(existing);
                updatedCount++;
            }
            else
            {
                // جديد — INSERT
                var e = new FtthSubscriberCache { CompanyId = companyId, SubscriptionId = subId };
                MapData(sub, e);
                context.FtthSubscriberCaches.Add(e);
                newCount++;
            }
        }

        // حذف المشتركين الموجودين في DB لكن غير موجودين في FTTH (zombie records)
        foreach (var (subId, existing) in existingMap)
        {
            if (!ftthIds.Contains(subId))
            {
                existing.IsDeleted = true;
                existing.DeletedAt = DateTime.UtcNow;
                context.FtthSubscriberCaches.Update(existing);
                deletedCount++;
            }
        }

        await context.SaveChangesAsync();
        return (newCount, updatedCount, skippedCount, deletedCount);
    }

    // ═══════════════════════════════════════════════════════════
    // جلب تفاصيل ذكي — فقط للناقصين، يحفظ في DB فوراً
    // ═══════════════════════════════════════════════════════════

    private async Task<int> FetchAndSaveDetails(string token, SadaraDbContext context, Guid companyId,
        List<string> customerIds, CancellationToken ct)
    {
        _logger.LogInformation("Smart Details: {Count} customers without details", customerIds.Count);

        // بناء lookup: customerId → DB entities
        var dbEntities = await context.FtthSubscriberCaches
            .Where(x => x.CompanyId == companyId && !x.IsDeleted)
            .ToListAsync(ct);
        var customerMap = new Dictionary<string, List<FtthSubscriberCache>>();
        foreach (var e in dbEntities)
        {
            if (string.IsNullOrEmpty(e.CustomerId)) continue;
            if (!customerMap.ContainsKey(e.CustomerId)) customerMap[e.CustomerId] = new();
            customerMap[e.CustomerId].Add(e);
        }

        // تقسيم إلى دفعات
        var idBatches = new List<List<string>>();
        for (int i = 0; i < customerIds.Count; i += PageSize)
            idBatches.Add(customerIds.Skip(i).Take(PageSize).ToList());

        int detailsLinked = 0;
        int currentBatch = 0;
        var totalBatches = idBatches.Count;
        var currentToken = token;
        var refreshInterval = Math.Max(1, totalBatches / 10);

        while (currentBatch < totalBatches && !ct.IsCancellationRequested)
        {
            var endBatch = Math.Min(currentBatch + DetailsParallel, totalBatches);
            var batchIndices = Enumerable.Range(currentBatch, endBatch - currentBatch).ToList();

            if (currentBatch > 0 && currentBatch % refreshInterval == 0)
                currentToken = await RefreshTokenIfNeeded(currentToken);

            // جلب متوازي مع retry
            var successful = new Dictionary<int, List<(string customerId, JsonElement data)>>();
            var failed = new List<int>(batchIndices);
            for (int retry = 0; retry < MaxBatchRetries && failed.Count > 0 && !ct.IsCancellationRequested; retry++)
            {
                if (retry > 0) await Task.Delay(TimeSpan.FromSeconds(retry * 2), ct);
                var tasks = failed.Select(idx => FetchAddressesBatch(currentToken, idBatches[idx], ct)).ToList();
                var results = await Task.WhenAll(tasks);
                var nextFailed = new List<int>();
                for (int i = 0; i < failed.Count; i++)
                { if (results[i] != null && results[i]!.Count > 0) successful[failed[i]] = results[i]!; else nextFailed.Add(failed[i]); }
                failed = nextFailed;
            }

            // تطبيق النتائج على DB مباشرة
            foreach (var batchIdx in successful.Keys.OrderBy(k => k))
            {
                foreach (var (customerId, data) in successful[batchIdx])
                {
                    if (string.IsNullOrEmpty(customerId) || !customerMap.TryGetValue(customerId, out var entities)) continue;
                    if (data.ValueKind != JsonValueKind.Object) continue;
                    var dd = data.TryGetProperty("deviceDetails", out var d) && d.ValueKind == JsonValueKind.Object ? d : default;
                    var gps = data.TryGetProperty("gpsCoordinate", out var g) && g.ValueKind == JsonValueKind.Object ? g : default;

                    foreach (var entity in entities)
                    {
                        if (dd.ValueKind != JsonValueKind.Undefined)
                        {
                            if (dd.TryGetProperty("username", out var u)) entity.Username = u.ToString();
                            if (dd.TryGetProperty("fdt", out var fdt) && fdt.TryGetProperty("displayValue", out var fdtV)) entity.FdtName = fdtV.ToString();
                            if (dd.TryGetProperty("fat", out var fat) && fat.TryGetProperty("displayValue", out var fatV)) entity.FatName = fatV.ToString();
                            if (dd.TryGetProperty("serial", out var s)) entity.DeviceSerial = s.ToString();
                        }
                        if (gps.ValueKind != JsonValueKind.Undefined)
                        {
                            if (gps.TryGetProperty("latitude", out var lat)) entity.GpsLat = lat.ToString();
                            if (gps.TryGetProperty("longitude", out var lng)) entity.GpsLng = lng.ToString();
                        }
                        entity.IsTrial = data.TryGetProperty("isTrial", out var tr) && tr.ValueKind == JsonValueKind.True;
                        entity.IsPending = data.TryGetProperty("isPending", out var pn) && pn.ValueKind == JsonValueKind.True;
                        entity.DetailsFetched = true;
                        entity.DetailsFetchedAt = DateTime.UtcNow;
                        entity.UpdatedAt = DateTime.UtcNow;
                        context.FtthSubscriberCaches.Update(entity);
                        detailsLinked++;
                    }
                }
            }

            // حفظ كل دفعة
            await context.SaveChangesAsync(ct);

            currentBatch = endBatch;
            var pct = 30 + (int)(25.0 * currentBatch / Math.Max(totalBatches, 1));
            await UpdateProgress(companyId, "details", pct,
                $"جلب التفاصيل: {detailsLinked:N0} — دفعة {currentBatch}/{totalBatches}", currentBatch, totalBatches);
            if (currentBatch < totalBatches && !ct.IsCancellationRequested) await Task.Delay(300, ct); // 300ms مثل التطبيق
        }

        _logger.LogInformation("Smart Details done: {Count} linked", detailsLinked);
        return detailsLinked;
    }

    // ═══════════════════════════════════════════════════════════
    // جلب هواتف ذكي — فقط للناقصين، يحفظ في DB فوراً
    // ═══════════════════════════════════════════════════════════

    private async Task<int> FetchAndSavePhones(string token, SadaraDbContext context, Guid companyId,
        List<string> customerIds, CancellationToken ct)
    {
        _logger.LogInformation("Smart Phones: {Count} customers without phone", customerIds.Count);

        // بناء lookup: customerId → DB entities
        var dbEntities = await context.FtthSubscriberCaches
            .Where(x => x.CompanyId == companyId && !x.IsDeleted && (x.Phone == "" || x.Phone == null))
            .ToListAsync(ct);
        var customerMap = new Dictionary<string, List<FtthSubscriberCache>>();
        foreach (var e in dbEntities)
        {
            if (string.IsNullOrEmpty(e.CustomerId)) continue;
            if (!customerMap.ContainsKey(e.CustomerId)) customerMap[e.CustomerId] = new();
            customerMap[e.CustomerId].Add(e);
        }

        int phonesLinked = 0;
        int currentIndex = 0;
        var currentToken = token;
        var totalBatches = (int)Math.Ceiling((double)customerIds.Count / PhoneParallel);
        var totalSaveGroups = (int)Math.Ceiling((double)totalBatches / PhoneBatchesBeforeSave);
        var refreshInterval = Math.Max(1, totalSaveGroups / 10);
        int saveGroupNum = 0;

        while (currentIndex < customerIds.Count && !ct.IsCancellationRequested)
        {
            saveGroupNum++;

            if (saveGroupNum > 1 && (saveGroupNum - 1) % refreshInterval == 0)
                currentToken = await RefreshTokenIfNeeded(currentToken);

            for (int b = 0; b < PhoneBatchesBeforeSave && currentIndex < customerIds.Count && !ct.IsCancellationRequested; b++)
            {
                var endIndex = Math.Min(currentIndex + PhoneParallel, customerIds.Count);
                var batch = customerIds.GetRange(currentIndex, endIndex - currentIndex);

                // جلب متوازي مع retry
                var successfulResults = new Dictionary<string, string>();
                var failedIds = new List<string>(batch);
                for (int retry = 0; retry < MaxBatchRetries && failedIds.Count > 0 && !ct.IsCancellationRequested; retry++)
                {
                    if (retry > 0) await Task.Delay(TimeSpan.FromSeconds(retry * 2), ct);
                    var tasks = failedIds.Select(cid => FetchPhoneOnly(currentToken, cid, ct)).ToList();
                    var results = await Task.WhenAll(tasks);
                    var nextFailed = new List<string>();
                    for (int i = 0; i < failedIds.Count; i++)
                    { if (results[i] != null) successfulResults[failedIds[i]] = results[i]!; else nextFailed.Add(failedIds[i]); }
                    failedIds = nextFailed;
                }

                // تطبيق على DB مباشرة
                foreach (var (cid, phone) in successfulResults)
                {
                    if (customerMap.TryGetValue(cid, out var entities))
                    {
                        foreach (var entity in entities)
                        {
                            entity.Phone = phone;
                            entity.UpdatedAt = DateTime.UtcNow;
                            context.FtthSubscriberCaches.Update(entity);
                        }
                        phonesLinked++;
                    }
                }

                currentIndex = endIndex;
                var pct = 60 + (int)(28.0 * currentIndex / Math.Max(customerIds.Count, 1));
                await UpdateProgress(companyId, "phones", pct,
                    $"جلب الهواتف: {phonesLinked:N0} رقم — {currentIndex:N0}/{customerIds.Count:N0}",
                    currentIndex, customerIds.Count);
            }

            // حفظ بعد كل مجموعة
            await context.SaveChangesAsync(ct);

            if (currentIndex < customerIds.Count && !ct.IsCancellationRequested)
                await Task.Delay(3000, ct);
        }

        _logger.LogInformation("Smart Phones done: {Found}/{Total}", phonesLinked, customerIds.Count);
        return phonesLinked;
    }

    // ═══════════════════════════════════════════════════════════
    // أدوات مساعدة
    // ═══════════════════════════════════════════════════════════

    private HttpClient CreateClient(string token, int timeoutSeconds)
    {
        // نفس الطريقة التي كانت تعمل في الإصدار السابق
        var client = new HttpClient { Timeout = TimeSpan.FromSeconds(timeoutSeconds) };
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", token);
        client.DefaultRequestHeaders.Accept.Add(new MediaTypeWithQualityHeaderValue("application/json"));
        client.DefaultRequestHeaders.Add("x-client-app", FtthClientApp);
        client.DefaultRequestHeaders.Add("x-user-role", "0");
        client.DefaultRequestHeaders.Add("Origin", "https://admin.ftth.iq");
        client.DefaultRequestHeaders.Add("Referer", "https://admin.ftth.iq/");
        client.DefaultRequestHeaders.Add("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64)");
        return client;
    }

    private async Task<string?> LoginToFtth(string username, string password)
    {
        try
        {
            using var client = new HttpClient { Timeout = TimeSpan.FromSeconds(30) };
            client.DefaultRequestHeaders.Add("Origin", "https://admin.ftth.iq");
            client.DefaultRequestHeaders.Add("Referer", "https://admin.ftth.iq/");
            client.DefaultRequestHeaders.Add("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64)");
            client.DefaultRequestHeaders.Add("x-client-app", FtthClientApp);
            client.DefaultRequestHeaders.Add("x-user-role", "0");
            var content = new FormUrlEncodedContent(new[] {
                new KeyValuePair<string, string>("username", username),
                new KeyValuePair<string, string>("password", password),
                new KeyValuePair<string, string>("grant_type", "password"),
                new KeyValuePair<string, string>("scope", "openid profile"),
            });
            var response = await client.PostAsync($"{FtthBaseUrl}/api/auth/Contractor/token", content);
            if (!response.IsSuccessStatusCode) { _logger.LogWarning("FTTH login failed: {Status}", response.StatusCode); return null; }
            var doc = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
            return doc.RootElement.GetProperty("access_token").GetString();
        }
        catch (Exception ex) { _logger.LogError(ex, "FTTH login error"); return null; }
    }

    private async Task<string> RefreshTokenIfNeeded(string currentToken)
    {
        var newToken = await LoginToFtth(_ftthUsername, _ftthPassword);
        if (!string.IsNullOrEmpty(newToken)) { _logger.LogInformation("Token refreshed"); return newToken; }
        return currentToken;
    }

    private Dictionary<string, object?> ConvertSubscription(JsonElement item)
    {
        var customer = item.TryGetProperty("customer", out var c) ? c : default;
        var zone = item.TryGetProperty("zone", out var z) ? z : default;
        var selfData = item.TryGetProperty("self", out var s) ? s : default;
        var dd = item.TryGetProperty("deviceDetails", out var d) ? d : default;

        var customerId = customer.ValueKind != JsonValueKind.Undefined && customer.TryGetProperty("id", out var cid) ? cid.ToString() : "";
        var subscriptionId = selfData.ValueKind != JsonValueKind.Undefined && selfData.TryGetProperty("id", out var sid) ? sid.ToString() : customerId;

        string? servicesJson = null;
        if (item.TryGetProperty("services", out var svc) && svc.ValueKind == JsonValueKind.Array) servicesJson = svc.GetRawText();
        var profileName = "";
        if (item.TryGetProperty("services", out var sv2) && sv2.ValueKind == JsonValueKind.Array)
            foreach (var se in sv2.EnumerateArray()) { if (se.TryGetProperty("displayValue", out var dv)) { profileName = dv.ToString(); break; } }

        return new() {
            ["SubscriptionId"] = subscriptionId, ["CustomerId"] = customerId,
            ["Username"] = dd.ValueKind != JsonValueKind.Undefined && dd.TryGetProperty("username", out var un) ? un.ToString() : "",
            ["DisplayName"] = customer.ValueKind != JsonValueKind.Undefined && customer.TryGetProperty("displayValue", out var dn) ? dn.ToString() : "",
            ["Status"] = item.TryGetProperty("status", out var st) ? st.ToString() : "",
            ["AutoRenew"] = item.TryGetProperty("autoRenew", out var ar) && ar.ValueKind == JsonValueKind.True,
            ["ProfileName"] = profileName,
            ["BundleId"] = item.TryGetProperty("bundleId", out var bi) ? bi.ToString() : null,
            ["ZoneId"] = zone.ValueKind != JsonValueKind.Undefined && zone.TryGetProperty("id", out var zi) ? zi.ToString() : null,
            ["ZoneName"] = zone.ValueKind != JsonValueKind.Undefined && zone.TryGetProperty("displayValue", out var zn) ? zn.ToString() : "",
            ["StartedAt"] = item.TryGetProperty("startedAt", out var sa) ? sa.ToString() : null,
            ["Expires"] = item.TryGetProperty("expires", out var ex) ? ex.ToString() : null,
            ["CommitmentPeriod"] = item.TryGetProperty("commitmentPeriod", out var cp) ? cp.ToString() : null,
            ["Phone"] = item.TryGetProperty("customerSummary", out var cs) && cs.TryGetProperty("primaryPhone", out var ph) ? ph.ToString() : "",
            ["LockedMac"] = item.TryGetProperty("lockedMac", out var lm) ? lm.ToString() : null,
            ["IsSuspended"] = item.TryGetProperty("isSuspended", out var isSusp) && isSusp.ValueKind == JsonValueKind.True,
            ["SuspensionReason"] = item.TryGetProperty("suspensionReason", out var sr) ? sr.ToString() : null,
            ["ServicesJson"] = servicesJson,
            ["FdtName"] = "", ["FatName"] = "", ["DeviceSerial"] = "",
            ["GpsLat"] = null as string, ["GpsLng"] = null as string,
            ["IsTrial"] = false, ["IsPending"] = false,
            ["DetailsFetched"] = false, ["DetailsFetchedAt"] = null as DateTime?,
        };
    }

    private void MapData(Dictionary<string, object?> data, FtthSubscriberCache e)
    {
        e.CustomerId = data["CustomerId"]?.ToString() ?? "";
        e.Username = data["Username"]?.ToString() ?? "";
        e.DisplayName = data["DisplayName"]?.ToString() ?? "";
        e.Status = data["Status"]?.ToString() ?? "";
        e.AutoRenew = data["AutoRenew"] is bool ar && ar;
        e.ProfileName = data["ProfileName"]?.ToString() ?? "";
        e.BundleId = data["BundleId"]?.ToString();
        e.ZoneId = data["ZoneId"]?.ToString();
        e.ZoneName = data["ZoneName"]?.ToString() ?? "";
        e.StartedAt = data["StartedAt"]?.ToString();
        e.Expires = data["Expires"]?.ToString();
        e.CommitmentPeriod = data["CommitmentPeriod"]?.ToString();
        e.Phone = data["Phone"]?.ToString() ?? "";
        e.LockedMac = data["LockedMac"]?.ToString();
        e.FdtName = data["FdtName"]?.ToString() ?? "";
        e.FatName = data["FatName"]?.ToString() ?? "";
        e.DeviceSerial = data["DeviceSerial"]?.ToString() ?? "";
        e.GpsLat = data["GpsLat"]?.ToString();
        e.GpsLng = data["GpsLng"]?.ToString();
        e.IsTrial = data["IsTrial"] is bool it && it;
        e.IsPending = data["IsPending"] is bool ip && ip;
        e.IsSuspended = data["IsSuspended"] is bool isSusp && isSusp;
        e.SuspensionReason = data["SuspensionReason"]?.ToString();
        e.DetailsFetched = data["DetailsFetched"] is bool df && df;
        e.DetailsFetchedAt = data["DetailsFetchedAt"] as DateTime?;
        e.ServicesJson = data["ServicesJson"]?.ToString();
    }

    private async Task UpdateProgress(Guid companyId, string stage, int progress, string message, int fetched, int total)
    {
        try
        {
            using var scope = _scopeFactory.CreateScope();
            var ctx = scope.ServiceProvider.GetRequiredService<SadaraDbContext>();
            var s = await ctx.CompanyFtthSettings.FirstOrDefaultAsync(x => x.CompanyId == companyId && !x.IsDeleted);
            if (s == null) return;
            s.SyncStage = stage; s.SyncProgress = progress; s.SyncMessage = message;
            s.SyncFetchedCount = fetched; s.SyncTotalCount = total;
            ctx.CompanyFtthSettings.Update(s); await ctx.SaveChangesAsync();
        }
        catch { }
    }

    private async Task FinishSync(SadaraDbContext context, CompanyFtthSettings settings, long logId,
        System.Diagnostics.Stopwatch stopwatch, bool success, string? error,
        int subscribersCount, int phonesCount, int detailsCount, int newCount, int updatedCount, string? statusOverride = null)
    {
        stopwatch.Stop();
        settings.IsSyncInProgress = false;
        settings.LastSyncAt = success ? DateTime.UtcNow : settings.LastSyncAt;
        settings.LastSyncError = error;
        settings.ConsecutiveFailures = success ? 0 : settings.ConsecutiveFailures + 1;
        if (success) settings.CurrentDbCount = subscribersCount;
        settings.UpdatedAt = DateTime.UtcNow;
        settings.SyncStage = null; settings.SyncProgress = 0; settings.SyncMessage = null;
        settings.SyncFetchedCount = 0; settings.SyncTotalCount = 0;
        context.CompanyFtthSettings.Update(settings);

        var log = await context.FtthSyncLogs.FindAsync(logId);
        if (log != null)
        {
            log.Status = statusOverride ?? (success ? "Success" : "Failed");
            log.CompletedAt = DateTime.UtcNow;
            log.SubscribersCount = subscribersCount; log.PhonesCount = phonesCount;
            log.DetailsCount = detailsCount; log.NewCount = newCount; log.UpdatedCount = updatedCount;
            log.ErrorMessage = error; log.DurationSeconds = (int)stopwatch.Elapsed.TotalSeconds;
            context.FtthSyncLogs.Update(log);
        }
        await context.SaveChangesAsync();
    }
}

// Extension helper
static class ListExtensions
{
    public static void AddAll<T>(this List<T> list, IEnumerable<T> items) => list.AddRange(items);
}
