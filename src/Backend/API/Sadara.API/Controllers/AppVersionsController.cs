using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Sadara.Domain.Interfaces;

namespace Sadara.API.Controllers;

[ApiController]
[Route("api/[controller]")]
public class AppVersionsController : ControllerBase
{
    private readonly IUnitOfWork _unitOfWork;

    public AppVersionsController(IUnitOfWork unitOfWork)
    {
        _unitOfWork = unitOfWork;
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
