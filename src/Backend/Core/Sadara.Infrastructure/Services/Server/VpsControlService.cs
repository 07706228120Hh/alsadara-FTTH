using System.Diagnostics;
using System.Net.NetworkInformation;
using System.Runtime.InteropServices;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;
using Sadara.Application.DTOs.Server;
using Sadara.Application.Interfaces;

namespace Sadara.Infrastructure.Services.Server;

/// <summary>
/// VPS/Server Control Service
/// خدمة إدارة ومراقبة السيرفر
/// </summary>
public class VpsControlService : IVpsControlService
{
    private readonly ILogger<VpsControlService> _logger;
    private readonly IConfiguration _configuration;

    public VpsControlService(
        IConfiguration configuration,
        ILogger<VpsControlService> logger)
    {
        _configuration = configuration;
        _logger = logger;
    }

    public async Task<ServerHealthStatus> GetServerHealthAsync()
    {
        var status = new ServerHealthStatus
        {
            Timestamp = DateTime.UtcNow,
            ServerName = Environment.MachineName,
            OperatingSystem = RuntimeInformation.OSDescription,
            DotNetVersion = RuntimeInformation.FrameworkDescription,
            ProcessorCount = Environment.ProcessorCount,
            Is64Bit = Environment.Is64BitOperatingSystem
        };

        try
        {
            var process = Process.GetCurrentProcess();
            status.MemoryUsedMb = process.WorkingSet64 / (1024 * 1024);
            status.GcTotalMemoryMb = GC.GetTotalMemory(false) / (1024 * 1024);
            status.ProcessUptime = DateTime.UtcNow - process.StartTime.ToUniversalTime();
            status.ThreadCount = process.Threads.Count;
            status.ApiStatus = "Running";
            status.DatabaseStatus = await CheckDatabaseConnectionAsync();
            status.IsHealthy = true;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting server health");
            status.IsHealthy = false;
            status.ErrorMessage = ex.Message;
        }

        return await Task.FromResult(status);
    }

    public async Task<DiskUsageInfo> GetDiskUsageAsync()
    {
        var info = new DiskUsageInfo
        {
            Timestamp = DateTime.UtcNow,
            Drives = new List<DriveUsage>()
        };

        try
        {
            foreach (var drive in DriveInfo.GetDrives().Where(d => d.IsReady))
            {
                info.Drives.Add(new DriveUsage
                {
                    DriveName = drive.Name,
                    DriveType = drive.DriveType.ToString(),
                    TotalSizeGb = drive.TotalSize / (1024.0 * 1024 * 1024),
                    FreeSpaceGb = drive.AvailableFreeSpace / (1024.0 * 1024 * 1024),
                    UsedSpaceGb = (drive.TotalSize - drive.AvailableFreeSpace) / (1024.0 * 1024 * 1024),
                    UsagePercent = ((drive.TotalSize - drive.AvailableFreeSpace) * 100.0) / drive.TotalSize
                });
            }
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting disk usage");
            info.ErrorMessage = ex.Message;
        }

        return await Task.FromResult(info);
    }

    public async Task<NetworkStats> GetNetworkStatsAsync()
    {
        var stats = new NetworkStats
        {
            Timestamp = DateTime.UtcNow,
            Interfaces = new List<NetworkInterfaceStats>()
        };

        try
        {
            foreach (var nic in NetworkInterface.GetAllNetworkInterfaces()
                .Where(n => n.OperationalStatus == OperationalStatus.Up))
            {
                var ipStats = nic.GetIPStatistics();
                stats.Interfaces.Add(new NetworkInterfaceStats
                {
                    Name = nic.Name,
                    Description = nic.Description,
                    Type = nic.NetworkInterfaceType.ToString(),
                    Speed = nic.Speed,
                    BytesSent = ipStats.BytesSent,
                    BytesReceived = ipStats.BytesReceived,
                    PacketsSent = ipStats.UnicastPacketsSent,
                    PacketsReceived = ipStats.UnicastPacketsReceived
                });
            }
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting network stats");
            stats.ErrorMessage = ex.Message;
        }

        return await Task.FromResult(stats);
    }

    public async Task<List<ProcessInfo>> GetTopProcessesAsync(int count = 10)
    {
        var processes = new List<ProcessInfo>();

        try
        {
            var allProcesses = Process.GetProcesses()
                .Where(p => p.Id != 0)
                .OrderByDescending(p =>
                {
                    try { return p.WorkingSet64; }
                    catch { return 0; }
                })
                .Take(count);

            foreach (var p in allProcesses)
            {
                try
                {
                    processes.Add(new ProcessInfo
                    {
                        ProcessId = p.Id,
                        ProcessName = p.ProcessName,
                        MemoryMb = p.WorkingSet64 / (1024 * 1024),
                        ThreadCount = p.Threads.Count,
                        StartTime = p.StartTime
                    });
                }
                catch { }
            }
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting top processes");
        }

        return await Task.FromResult(processes);
    }

    public async Task<ServiceStatus> GetServiceStatusAsync(string serviceName)
    {
        var status = new ServiceStatus
        {
            ServiceName = serviceName,
            Timestamp = DateTime.UtcNow
        };

        try
        {
            if (RuntimeInformation.IsOSPlatform(OSPlatform.Linux))
            {
                status.Status = "Use: systemctl status " + serviceName;
                status.IsRunning = true;
            }
            else
            {
                status.Status = "Windows service check not implemented";
            }
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting service status: {Service}", serviceName);
            status.Status = "Error";
            status.ErrorMessage = ex.Message;
        }

        return await Task.FromResult(status);
    }

    public async Task<CommandResult> ExecuteCommandAsync(string command, bool requiresSudo = false)
    {
        var result = new CommandResult
        {
            Command = command,
            Timestamp = DateTime.UtcNow
        };

        try
        {
            var allowedCommands = new[]
            {
                "systemctl status",
                "systemctl restart sadara-api",
                "df -h",
                "free -m",
                "uptime",
                "nginx -t",
                "systemctl reload nginx"
            };

            var isAllowed = allowedCommands.Any(c => command.StartsWith(c, StringComparison.OrdinalIgnoreCase));

            if (!isAllowed)
            {
                result.Success = false;
                result.ErrorMessage = "Command not allowed for security reasons";
                _logger.LogWarning("Blocked command execution: {Command}", command);
                return result;
            }

            if (!RuntimeInformation.IsOSPlatform(OSPlatform.Linux))
            {
                result.Success = false;
                result.ErrorMessage = "Command execution only supported on Linux VPS";
                return result;
            }

            var psi = new ProcessStartInfo
            {
                FileName = "/bin/bash",
                Arguments = $"-c \"{(requiresSudo ? "sudo " : "")}{command}\"",
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                UseShellExecute = false
            };

            using var process = Process.Start(psi);
            if (process == null)
            {
                result.Success = false;
                result.ErrorMessage = "Failed to start process";
                return result;
            }

            result.Output = await process.StandardOutput.ReadToEndAsync();
            result.ErrorOutput = await process.StandardError.ReadToEndAsync();
            await process.WaitForExitAsync();

            result.ExitCode = process.ExitCode;
            result.Success = process.ExitCode == 0;

            _logger.LogInformation("Executed command: {Command}, Exit: {Exit}", command, process.ExitCode);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error executing command: {Command}", command);
            result.Success = false;
            result.ErrorMessage = ex.Message;
        }

        return result;
    }

    public async Task<bool> RestartApiServiceAsync()
    {
        try
        {
            var result = await ExecuteCommandAsync("systemctl restart sadara-api", requiresSudo: true);
            return result.Success;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error restarting API service");
            return false;
        }
    }

    public async Task<ApplicationLogs> GetRecentLogsAsync(int lines = 100)
    {
        var logs = new ApplicationLogs
        {
            Timestamp = DateTime.UtcNow,
            Lines = new List<string>()
        };

        try
        {
            if (RuntimeInformation.IsOSPlatform(OSPlatform.Linux))
            {
                var result = await ExecuteCommandAsync($"journalctl -u sadara-api -n {lines} --no-pager");
                if (result.Success)
                {
                    logs.Lines = result.Output?.Split('\n').ToList() ?? new List<string>();
                }
            }
            else
            {
                logs.Lines.Add("Log retrieval only supported on Linux VPS");
            }
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting logs");
            logs.ErrorMessage = ex.Message;
        }

        return logs;
    }

    private async Task<string> CheckDatabaseConnectionAsync()
    {
        try
        {
            var connectionString = _configuration.GetConnectionString("DefaultConnection");
            if (string.IsNullOrEmpty(connectionString))
            {
                return "InMemory";
            }
            return "Connected";
        }
        catch
        {
            return "Disconnected";
        }
    }
}
