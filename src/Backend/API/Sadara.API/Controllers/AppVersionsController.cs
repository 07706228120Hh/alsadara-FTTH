using System.Text.Json;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Caching.Memory;
using Sadara.Domain.Interfaces;

namespace Sadara.API.Controllers;

[ApiController]
[Route("api/[controller]")]
public class AppVersionsController : ControllerBase
{
    private readonly IUnitOfWork _unitOfWork;
    private readonly IHttpClientFactory _httpClientFactory;
    private readonly IMemoryCache _cache;

    // مستودع الإصدارات (نفس مستودع auto_update_service في التطبيق).
    private const string GithubOwner = "07706228120Hh";
    private const string GithubRepo = "alsadara-FTTH";
    private const string GithubLatestApi =
        "https://api.github.com/repos/" + GithubOwner + "/" + GithubRepo + "/releases/latest";
    private const string ManifestCacheKey = "app_update_manifest_latest";
    // علَم تخزين سلبي قصير أثناء انقطاع GitHub (يمنع عاصفة مكالمات صادرة).
    private const string ManifestNegKey = "app_update_manifest_neg";
    // قفل مشترك (static لأن الكنترولر transient) لتجميع الطلبات المتزامنة
    // ومنع cache stampede عند انتهاء الصلاحية.
    private static readonly SemaphoreSlim _manifestLock = new(1, 1);

    public AppVersionsController(
        IUnitOfWork unitOfWork,
        IHttpClientFactory httpClientFactory,
        IMemoryCache cache)
    {
        _unitOfWork = unitOfWork;
        _httpClientFactory = httpClientFactory;
        _cache = cache;
    }

    [HttpGet("check")]
    public async Task<IActionResult> CheckVersion([FromQuery] string platform, [FromQuery] string currentVersion)
    {
        var latestVersion = await _unitOfWork.AppVersions.AsQueryable()
            .Where(v => v.Platform.ToLower() == platform.ToLower() && v.IsActive)
            .OrderByDescending(v => v.CreatedAt)
            .FirstOrDefaultAsync();

        if (latestVersion == null)
            return Ok(new
            {
                success = true,
                data = new
                {
                    updateAvailable = false,
                    forceUpdate = false
                }
            });

        var isUpdateAvailable = CompareVersions(currentVersion, latestVersion.Version) < 0;
        var isForceUpdate = latestVersion.ForceUpdate &&
                           !string.IsNullOrEmpty(latestVersion.MinVersion) &&
                           CompareVersions(currentVersion, latestVersion.MinVersion) < 0;

        return Ok(new
        {
            success = true,
            data = new
            {
                updateAvailable = isUpdateAvailable,
                forceUpdate = isForceUpdate,
                latestVersion = latestVersion.Version,
                minVersion = latestVersion.MinVersion,
                downloadUrl = latestVersion.DownloadUrl,
                releaseNotes = latestVersion.ReleaseNotes
            }
        });
    }

    [HttpGet("latest/{platform}")]
    public async Task<IActionResult> GetLatest(string platform)
    {
        var version = await _unitOfWork.AppVersions.AsQueryable()
            .Where(v => v.Platform.ToLower() == platform.ToLower() && v.IsActive)
            .OrderByDescending(v => v.CreatedAt)
            .FirstOrDefaultAsync();

        if (version == null)
            return NotFound(new { success = false, message = "لم يتم العثور على إصدار" });

        return Ok(new { success = true, data = version });
    }

    /// <summary>
    /// manifest التحديث: يجلب آخر إصدار من GitHub مرّة واحدة من الخادم مع
    /// تخزين مؤقت (IMemoryCache، 10 دقائق). فكل الأجهزة تسأل خادمنا بدل
    /// مناداة api.github.com مباشرةً ⇒ IP واحد (الخادم) يسأل GitHub، وهذا
    /// يلغي حدّ المعدّل (60/ساعة/IP المشترك) والحجب على أجهزة بعينها.
    /// عام (بلا مصادقة) لأنه يُفحص قبل الدخول؛ لا يكشف أي بيانات حسّاسة
    /// (مجرد ما هو منشور علناً على صفحة إصدارات GitHub).
    /// </summary>
    [HttpGet("manifest")]
    public async Task<IActionResult> GetUpdateManifest([FromQuery] string platform = "windows")
    {
        try
        {
            var json = await GetLatestReleaseJsonCachedAsync();
            if (string.IsNullOrEmpty(json))
            {
                // تعذّر الجلب ولا نسخة مخزّنة — التطبيق يسقط لمساره الاحتياطي (github.com).
                return StatusCode(502,
                    new { success = false, message = "تعذّر جلب معلومات الإصدار حالياً" });
            }

            using var doc = JsonDocument.Parse(json);
            var root = doc.RootElement;
            var (url, size, name) = SelectAsset(root, platform);

            // نُعيد رابط تنزيل عبر خادمنا (caching proxy) بدل رابط GitHub المباشر:
            // شبكة توزيع GitHub (objects.githubusercontent.com) محجوبة/مخنوقة على
            // بعض شبكات العملاء ⇒ التحميل يعلَق على 0%. خادمنا يصل GitHub بسرعة،
            // فيبثّ الملف للعميل الذي يصل خادمنا أصلاً. يتضمّن الرابط اسم الملف
            // الحقيقي كي يحفظه التطبيق بامتداد ‎.exe الصحيح.
            var publicUrl = BuildMirrorUrl(platform, name, url);

            return Ok(new
            {
                success = true,
                data = new
                {
                    version =
                        (root.TryGetProperty("tag_name", out var t) ? t.GetString() ?? "" : "")
                        .Replace("v", ""),
                    downloadUrl = publicUrl,
                    downloadSize = size,
                    assetName = name,
                    releaseNotes = root.TryGetProperty("body", out var b) ? b.GetString() ?? "" : "",
                    publishedAt =
                        root.TryGetProperty("published_at", out var p) ? p.GetString() ?? "" : ""
                }
            });
        }
        catch
        {
            return StatusCode(502,
                new { success = false, message = "تعذّر جلب معلومات الإصدار حالياً" });
        }
    }

    /// جلب أحدث إصدار من GitHub مع cache 10 دقائق (نصّ JSON خام).
    /// يستخدم قفلاً مشتركاً لتجميع الطلبات المتزامنة، وتخزيناً سلبياً قصيراً
    /// أثناء انقطاع GitHub كيلا يُطلق كل طلب وارد مكالمة صادرة جديدة.
    private async Task<string?> GetLatestReleaseJsonCachedAsync()
    {
        if (_cache.TryGetValue(ManifestCacheKey, out string? cached) &&
            !string.IsNullOrEmpty(cached))
        {
            return cached;
        }
        if (_cache.TryGetValue(ManifestNegKey, out bool _))
        {
            return null; // في فترة التهدئة بعد فشل حديث
        }

        await _manifestLock.WaitAsync();
        try
        {
            // فحص ثانٍ بعد القفل: قد يكون طلب سابق ملأ الـcache أثناء الانتظار.
            if (_cache.TryGetValue(ManifestCacheKey, out string? again) &&
                !string.IsNullOrEmpty(again))
            {
                return again;
            }
            if (_cache.TryGetValue(ManifestNegKey, out bool _))
            {
                return null;
            }

            var client = _httpClientFactory.CreateClient();
            client.Timeout = TimeSpan.FromSeconds(10);

            using var req = new HttpRequestMessage(HttpMethod.Get, GithubLatestApi);
            // GitHub يرفض الطلبات بلا User-Agent بـ403.
            req.Headers.Add("User-Agent", "Sadara-Update-Manifest");
            req.Headers.Add("Accept", "application/vnd.github+json");
            req.Headers.Add("X-GitHub-Api-Version", "2022-11-28");

            try
            {
                var resp = await client.SendAsync(req);
                if (!resp.IsSuccessStatusCode)
                {
                    _cache.Set(ManifestNegKey, true, TimeSpan.FromSeconds(45));
                    return null;
                }

                var body = await resp.Content.ReadAsStringAsync();
                _cache.Set(ManifestCacheKey, body, TimeSpan.FromMinutes(10));
                return body;
            }
            catch
            {
                // فشل شبكي/مهلة: تهدئة قصيرة تمنع العاصفة أثناء انقطاع GitHub.
                _cache.Set(ManifestNegKey, true, TimeSpan.FromSeconds(45));
                return null;
            }
        }
        finally
        {
            _manifestLock.Release();
        }
    }

    // أقفال لكل ملف لمنع تنزيلات متزامنة مكرّرة لنفس الأصل (cache stampede).
    private static readonly System.Collections.Concurrent.ConcurrentDictionary<string, SemaphoreSlim>
        _downloadLocks = new();

    /// بناء رابط التنزيل عبر خادمنا (يتضمّن اسم الملف الحقيقي في المسار كي
    /// يحفظه التطبيق بامتداده الصحيح). يسقط لرابط GitHub إن غاب الأصل/المضيف.
    private string BuildMirrorUrl(string platform, string assetName, string fallbackUrl)
    {
        if (string.IsNullOrEmpty(assetName) || string.IsNullOrEmpty(fallbackUrl))
            return fallbackUrl;
        var host = Request.Host.HasValue ? Request.Host.Value : "";
        if (string.IsNullOrEmpty(host)) return fallbackUrl;
        var scheme = host.Contains("localhost", StringComparison.OrdinalIgnoreCase)
            ? Request.Scheme
            : "https";
        var file = Uri.EscapeDataString(System.IO.Path.GetFileName(assetName));
        return $"{scheme}://{host}/api/appversions/download/{platform.ToLowerInvariant()}/{file}";
    }

    /// <summary>
    /// تنزيل ملف التثبيت عبر خادمنا (caching proxy). يجلب الأصل من GitHub مرّة
    /// واحدة جهة الخادم (يصل GitHub بسرعة) ويُخزّنه مؤقتاً ثم يبثّه للعميل مع
    /// دعم Range (استئناف). يصحّح مشكلة تعلّق التحميل على 0% عند العملاء الذين
    /// تُحجب عنهم شبكة توزيع GitHub. عام (بلا مصادقة) لأنه يُستدعى قبل الدخول؛
    /// لا يبثّ إلا الأصل المنشور علناً لأحدث إصدار.
    /// </summary>
    [HttpGet("download/{platform}/{fileName}")]
    public async Task<IActionResult> DownloadInstaller(string platform, string fileName)
    {
        fileName = System.IO.Path.GetFileName(fileName ?? ""); // تنظيف ضد المسارات
        if (string.IsNullOrEmpty(fileName))
            return BadRequest(new { success = false, message = "اسم ملف غير صالح" });

        var json = await GetLatestReleaseJsonCachedAsync();
        if (string.IsNullOrEmpty(json))
            return StatusCode(502, new { success = false, message = "تعذّر جلب معلومات الإصدار حالياً" });

        using var doc = JsonDocument.Parse(json);
        var (url, size, name) = SelectAsset(doc.RootElement, platform);
        if (string.IsNullOrEmpty(url) || string.IsNullOrEmpty(name))
            return NotFound(new { success = false, message = "لا يوجد ملف لهذه المنصّة" });

        // لا نبثّ إلا أصل أحدث إصدار (نمنع جلب أي ملف اعتباطي عبر الوسيط).
        var safeName = System.IO.Path.GetFileName(name);
        if (!string.Equals(safeName, fileName, StringComparison.OrdinalIgnoreCase))
            return NotFound(new { success = false, message = "الملف المطلوب غير متاح" });

        var cacheDir = System.IO.Path.Combine(System.IO.Path.GetTempPath(), "sadara-updates");
        System.IO.Directory.CreateDirectory(cacheDir);
        var cachePath = System.IO.Path.Combine(cacheDir, safeName);

        var cached = System.IO.File.Exists(cachePath) &&
                     (size <= 0 || new System.IO.FileInfo(cachePath).Length == size);
        if (!cached)
        {
            var ok = await EnsureCachedAsync(url, cachePath, safeName, size);
            if (!ok)
                return StatusCode(502, new { success = false, message = "تعذّر تجهيز ملف التحديث" });
        }

        return PhysicalFile(cachePath, "application/octet-stream", safeName, enableRangeProcessing: true);
    }

    /// تنزيل الأصل من GitHub إلى الكاش بأمان (ملف مؤقت ثم نقل ذرّي)، مع قفل
    /// لكل ملف لمنع التنزيلات المتزامنة. يُعيد true عند جاهزية الكاش.
    private async Task<bool> EnsureCachedAsync(string url, string cachePath, string name, long expectedSize)
    {
        var gate = _downloadLocks.GetOrAdd(name, _ => new SemaphoreSlim(1, 1));
        await gate.WaitAsync();
        try
        {
            if (System.IO.File.Exists(cachePath) &&
                (expectedSize <= 0 || new System.IO.FileInfo(cachePath).Length == expectedSize))
                return true;

            var client = _httpClientFactory.CreateClient();
            client.Timeout = TimeSpan.FromMinutes(5);
            using var req = new HttpRequestMessage(HttpMethod.Get, url);
            req.Headers.Add("User-Agent", "Sadara-Update-Mirror");

            using var resp = await client.SendAsync(req, HttpCompletionOption.ResponseHeadersRead);
            if (!resp.IsSuccessStatusCode) return false;

            var tmp = cachePath + ".downloading";
            await using (var fs = System.IO.File.Create(tmp))
            {
                await resp.Content.CopyToAsync(fs);
            }

            if (expectedSize > 0 && new System.IO.FileInfo(tmp).Length != expectedSize)
            {
                System.IO.File.Delete(tmp);
                return false;
            }

            if (System.IO.File.Exists(cachePath)) System.IO.File.Delete(cachePath);
            System.IO.File.Move(tmp, cachePath);
            return true;
        }
        catch
        {
            return false;
        }
        finally
        {
            gate.Release();
        }
    }

    /// اختيار أصل التحميل حسب المنصّة بنفس أولوية التطبيق:
    /// Android: ‎.apk · Windows: Setup.exe → أي ‎.exe → ‎.zip.
    private static (string url, long size, string name) SelectAsset(
        JsonElement root, string platform)
    {
        if (!root.TryGetProperty("assets", out var assets) ||
            assets.ValueKind != JsonValueKind.Array)
        {
            return ("", 0, "");
        }

        (string url, long size, string name) Pick(Func<string, bool> match)
        {
            foreach (var a in assets.EnumerateArray())
            {
                var name = a.TryGetProperty("name", out var n) ? n.GetString() ?? "" : "";
                var url = a.TryGetProperty("browser_download_url", out var u)
                    ? u.GetString() ?? ""
                    : "";
                if (url.Length == 0) continue;
                if (match(name.ToLowerInvariant()))
                {
                    long size = a.TryGetProperty("size", out var s) && s.TryGetInt64(out var sv)
                        ? sv
                        : 0;
                    return (url, size, name);
                }
            }
            return ("", 0, "");
        }

        if (platform.Equals("android", StringComparison.OrdinalIgnoreCase))
        {
            return Pick(n => n.EndsWith(".apk"));
        }

        var setup = Pick(n => n.Contains("setup") && n.EndsWith(".exe"));
        if (setup.url.Length > 0) return setup;
        var exe = Pick(n => n.EndsWith(".exe"));
        if (exe.url.Length > 0) return exe;
        return Pick(n => n.EndsWith(".zip"));
    }

    private int CompareVersions(string version1, string version2)
    {
        var v1Parts = version1.Split('.').Select(int.Parse).ToArray();
        var v2Parts = version2.Split('.').Select(int.Parse).ToArray();

        for (int i = 0; i < Math.Max(v1Parts.Length, v2Parts.Length); i++)
        {
            var v1Part = i < v1Parts.Length ? v1Parts[i] : 0;
            var v2Part = i < v2Parts.Length ? v2Parts[i] : 0;

            if (v1Part < v2Part) return -1;
            if (v1Part > v2Part) return 1;
        }

        return 0;
    }
}
