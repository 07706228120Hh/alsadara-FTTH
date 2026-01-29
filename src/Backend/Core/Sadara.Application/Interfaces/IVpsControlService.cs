using Sadara.Application.DTOs.Server;

namespace Sadara.Application.Interfaces;

/// <summary>
/// Interface for VPS/Server Control operations
/// واجهة عمليات إدارة السيرفر
/// </summary>
public interface IVpsControlService
{
    /// <summary>
    /// Get server health status
    /// الحصول على حالة السيرفر
    /// </summary>
    Task<ServerHealthStatus> GetServerHealthAsync();

    /// <summary>
    /// Get disk usage information
    /// معلومات استخدام القرص
    /// </summary>
    Task<DiskUsageInfo> GetDiskUsageAsync();

    /// <summary>
    /// Get network statistics
    /// إحصائيات الشبكة
    /// </summary>
    Task<NetworkStats> GetNetworkStatsAsync();

    /// <summary>
    /// Get top processes by memory usage
    /// أكثر العمليات استخداماً للذاكرة
    /// </summary>
    Task<List<ProcessInfo>> GetTopProcessesAsync(int count = 10);

    /// <summary>
    /// Get status of a specific service
    /// حالة خدمة معينة
    /// </summary>
    Task<ServiceStatus> GetServiceStatusAsync(string serviceName);

    /// <summary>
    /// Execute a whitelisted command
    /// تنفيذ أمر مسموح به
    /// </summary>
    Task<CommandResult> ExecuteCommandAsync(string command, bool requiresSudo = false);

    /// <summary>
    /// Restart the API service
    /// إعادة تشغيل خدمة API
    /// </summary>
    Task<bool> RestartApiServiceAsync();

    /// <summary>
    /// Get recent application logs
    /// سجلات التطبيق الأخيرة
    /// </summary>
    Task<ApplicationLogs> GetRecentLogsAsync(int lines = 100);
}
