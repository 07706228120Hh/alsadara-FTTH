using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Sadara.Application.Interfaces;

namespace Sadara.API.Controllers;

/// <summary>
/// Server Control API - Super Admin Only
/// تحكم كامل بالسيرفر للسوبر أدمن فقط
/// </summary>
[ApiController]
[Route("api/[controller]")]
[Authorize(Policy = "SuperAdminOnly")]
public class ServerController : ControllerBase
{
    private readonly IVpsControlService _vpsService;
    private readonly IFirebaseAdminService _firebaseService;
    private readonly ILogger<ServerController> _logger;

    public ServerController(
        IVpsControlService vpsService,
        IFirebaseAdminService firebaseService,
        ILogger<ServerController> logger)
    {
        _vpsService = vpsService;
        _firebaseService = firebaseService;
        _logger = logger;
    }

    #region Server Health & Monitoring

    /// <summary>
    /// Get server health status
    /// حالة السيرفر الشاملة
    /// </summary>
    [HttpGet("health")]
    public async Task<IActionResult> GetServerHealth()
    {
        try
        {
            var health = await _vpsService.GetServerHealthAsync();
            return Ok(new
            {
                success = true,
                data = health
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting server health");
            return StatusCode(500, new { success = false, message = "Error getting server health" });
        }
    }

    /// <summary>
    /// Get disk usage
    /// استخدام القرص
    /// </summary>
    [HttpGet("disk")]
    public async Task<IActionResult> GetDiskUsage()
    {
        try
        {
            var disk = await _vpsService.GetDiskUsageAsync();
            return Ok(new
            {
                success = true,
                data = disk
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting disk usage");
            return StatusCode(500, new { success = false, message = "Error getting disk usage" });
        }
    }

    /// <summary>
    /// Get network statistics
    /// إحصائيات الشبكة
    /// </summary>
    [HttpGet("network")]
    public async Task<IActionResult> GetNetworkStats()
    {
        try
        {
            var network = await _vpsService.GetNetworkStatsAsync();
            return Ok(new
            {
                success = true,
                data = network
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting network stats");
            return StatusCode(500, new { success = false, message = "Error getting network stats" });
        }
    }

    /// <summary>
    /// Get top processes
    /// أكثر العمليات استخداماً
    /// </summary>
    [HttpGet("processes")]
    public async Task<IActionResult> GetTopProcesses([FromQuery] int count = 10)
    {
        try
        {
            var processes = await _vpsService.GetTopProcessesAsync(count);
            return Ok(new
            {
                success = true,
                data = processes
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting processes");
            return StatusCode(500, new { success = false, message = "Error getting processes" });
        }
    }

    #endregion

    #region Service Management

    /// <summary>
    /// Get service status
    /// حالة خدمة معينة
    /// </summary>
    [HttpGet("services/{serviceName}/status")]
    public async Task<IActionResult> GetServiceStatus(string serviceName)
    {
        try
        {
            var status = await _vpsService.GetServiceStatusAsync(serviceName);
            return Ok(new
            {
                success = true,
                data = status
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting service status: {Service}", serviceName);
            return StatusCode(500, new { success = false, message = "Error getting service status" });
        }
    }

    /// <summary>
    /// Restart API service
    /// إعادة تشغيل خدمة API
    /// </summary>
    [HttpPost("services/api/restart")]
    public async Task<IActionResult> RestartApiService()
    {
        try
        {
            _logger.LogWarning("API restart requested by SuperAdmin");
            var success = await _vpsService.RestartApiServiceAsync();

            if (success)
            {
                return Ok(new { success = true, message = "API service restart initiated" });
            }

            return StatusCode(500, new { success = false, message = "Failed to restart API service" });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error restarting API service");
            return StatusCode(500, new { success = false, message = "Error restarting API service" });
        }
    }

    #endregion

    #region Logs

    /// <summary>
    /// Get recent application logs
    /// سجلات التطبيق الأخيرة
    /// </summary>
    [HttpGet("logs")]
    public async Task<IActionResult> GetLogs([FromQuery] int lines = 100)
    {
        try
        {
            var logs = await _vpsService.GetRecentLogsAsync(lines);
            return Ok(new
            {
                success = true,
                data = logs
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting logs");
            return StatusCode(500, new { success = false, message = "Error getting logs" });
        }
    }

    #endregion

    #region Firebase Admin

    /// <summary>
    /// Get Firebase user by phone
    /// معلومات مستخدم Firebase
    /// </summary>
    [HttpGet("firebase/users/phone/{phoneNumber}")]
    public async Task<IActionResult> GetFirebaseUser(string phoneNumber)
    {
        try
        {
            var user = await _firebaseService.GetUserByPhoneAsync(phoneNumber);
            if (user == null)
            {
                return NotFound(new { success = false, message = "Firebase user not found" });
            }

            return Ok(new { success = true, data = user });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting Firebase user: {Phone}", phoneNumber);
            return StatusCode(500, new { success = false, message = "Error getting Firebase user" });
        }
    }

    /// <summary>
    /// Disable Firebase user
    /// تعطيل مستخدم في Firebase
    /// </summary>
    [HttpPost("firebase/users/{uid}/disable")]
    public async Task<IActionResult> DisableFirebaseUser(string uid)
    {
        try
        {
            var success = await _firebaseService.DisableUserAsync(uid);
            if (success)
            {
                _logger.LogWarning("Firebase user disabled by SuperAdmin: {Uid}", uid);
                return Ok(new { success = true, message = "Firebase user disabled" });
            }

            return StatusCode(500, new { success = false, message = "Failed to disable Firebase user" });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error disabling Firebase user: {Uid}", uid);
            return StatusCode(500, new { success = false, message = "Error disabling Firebase user" });
        }
    }

    /// <summary>
    /// Enable Firebase user
    /// تفعيل مستخدم في Firebase
    /// </summary>
    [HttpPost("firebase/users/{uid}/enable")]
    public async Task<IActionResult> EnableFirebaseUser(string uid)
    {
        try
        {
            var success = await _firebaseService.EnableUserAsync(uid);
            if (success)
            {
                _logger.LogInformation("Firebase user enabled by SuperAdmin: {Uid}", uid);
                return Ok(new { success = true, message = "Firebase user enabled" });
            }

            return StatusCode(500, new { success = false, message = "Failed to enable Firebase user" });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error enabling Firebase user: {Uid}", uid);
            return StatusCode(500, new { success = false, message = "Error enabling Firebase user" });
        }
    }

    /// <summary>
    /// Delete Firebase user
    /// حذف مستخدم من Firebase
    /// </summary>
    [HttpDelete("firebase/users/{uid}")]
    public async Task<IActionResult> DeleteFirebaseUser(string uid)
    {
        try
        {
            var success = await _firebaseService.DeleteUserAsync(uid);
            if (success)
            {
                _logger.LogWarning("Firebase user deleted by SuperAdmin: {Uid}", uid);
                return Ok(new { success = true, message = "Firebase user deleted" });
            }

            return StatusCode(500, new { success = false, message = "Failed to delete Firebase user" });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error deleting Firebase user: {Uid}", uid);
            return StatusCode(500, new { success = false, message = "Error deleting Firebase user" });
        }
    }

    /// <summary>
    /// Get Firebase Auth statistics
    /// إحصائيات Firebase Auth
    /// </summary>
    [HttpGet("firebase/stats")]
    public async Task<IActionResult> GetFirebaseStats()
    {
        try
        {
            var stats = await _firebaseService.GetAuthStatsAsync();
            return Ok(new { success = true, data = stats });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting Firebase stats");
            return StatusCode(500, new { success = false, message = "Error getting Firebase stats" });
        }
    }

    #endregion

    #region Command Execution

    /// <summary>
    /// Execute whitelisted command
    /// تنفيذ أمر مسموح به
    /// </summary>
    [HttpPost("execute")]
    public async Task<IActionResult> ExecuteCommand([FromBody] CommandRequest request)
    {
        try
        {
            _logger.LogWarning("Command execution requested by SuperAdmin: {Command}", request.Command);
            var result = await _vpsService.ExecuteCommandAsync(request.Command, request.RequiresSudo);
            return Ok(new { success = result.Success, data = result });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error executing command: {Command}", request.Command);
            return StatusCode(500, new { success = false, message = "Error executing command" });
        }
    }

    #endregion

    #region Dashboard Summary

    /// <summary>
    /// Get complete dashboard summary
    /// ملخص لوحة التحكم الكامل
    /// </summary>
    [HttpGet("dashboard")]
    public async Task<IActionResult> GetDashboardSummary()
    {
        try
        {
            var healthTask = _vpsService.GetServerHealthAsync();
            var diskTask = _vpsService.GetDiskUsageAsync();
            var networkTask = _vpsService.GetNetworkStatsAsync();
            var processesTask = _vpsService.GetTopProcessesAsync(5);
            var firebaseTask = _firebaseService.GetAuthStatsAsync();

            await Task.WhenAll(healthTask, diskTask, networkTask, processesTask, firebaseTask);

            return Ok(new
            {
                success = true,
                data = new
                {
                    serverHealth = healthTask.Result,
                    diskUsage = diskTask.Result,
                    network = networkTask.Result,
                    topProcesses = processesTask.Result,
                    firebase = firebaseTask.Result,
                    timestamp = DateTime.UtcNow
                }
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting dashboard summary");
            return StatusCode(500, new { success = false, message = "Error getting dashboard summary" });
        }
    }

    #endregion
}

public class CommandRequest
{
    public string Command { get; set; } = string.Empty;
    public bool RequiresSudo { get; set; }
}
