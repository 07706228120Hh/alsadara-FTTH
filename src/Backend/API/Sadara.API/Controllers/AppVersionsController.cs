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

            return Ok(new
            {
                success = true,
                data = new
                {
                    version =
                        (root.TryGetProperty("tag_name", out var t) ? t.GetString() ?? "" : "")
                        .Replace("v", ""),
                    downloadUrl = url,
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
    private async Task<string?> GetLatestReleaseJsonCachedAsync()
    {
        if (_cache.TryGetValue(ManifestCacheKey, out string? cached) &&
            !string.IsNullOrEmpty(cached))
        {
            return cached;
        }

        var client = _httpClientFactory.CreateClient();
        client.Timeout = TimeSpan.FromSeconds(15);

        using var req = new HttpRequestMessage(HttpMethod.Get, GithubLatestApi);
        // GitHub يرفض الطلبات بلا User-Agent بـ403.
        req.Headers.Add("User-Agent", "Sadara-Update-Manifest");
        req.Headers.Add("Accept", "application/vnd.github+json");
        req.Headers.Add("X-GitHub-Api-Version", "2022-11-28");

        var resp = await client.SendAsync(req);
        if (!resp.IsSuccessStatusCode)
        {
            return null;
        }

        var body = await resp.Content.ReadAsStringAsync();
        _cache.Set(ManifestCacheKey, body, TimeSpan.FromMinutes(10));
        return body;
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
