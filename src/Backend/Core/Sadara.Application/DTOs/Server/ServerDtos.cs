namespace Sadara.Application.DTOs.Server;

// Server DTOs
public class ServerHealthStatus
{
    public DateTime Timestamp { get; set; }
    public string ServerName { get; set; } = string.Empty;
    public string OperatingSystem { get; set; } = string.Empty;
    public string DotNetVersion { get; set; } = string.Empty;
    public int ProcessorCount { get; set; }
    public bool Is64Bit { get; set; }
    public long MemoryUsedMb { get; set; }
    public long GcTotalMemoryMb { get; set; }
    public TimeSpan ProcessUptime { get; set; }
    public int ThreadCount { get; set; }
    public string ApiStatus { get; set; } = string.Empty;
    public string DatabaseStatus { get; set; } = string.Empty;
    public bool IsHealthy { get; set; }
    public string? ErrorMessage { get; set; }
}

public class DiskUsageInfo
{
    public DateTime Timestamp { get; set; }
    public List<DriveUsage> Drives { get; set; } = new();
    public string? ErrorMessage { get; set; }
}

public class DriveUsage
{
    public string DriveName { get; set; } = string.Empty;
    public string DriveType { get; set; } = string.Empty;
    public double TotalSizeGb { get; set; }
    public double FreeSpaceGb { get; set; }
    public double UsedSpaceGb { get; set; }
    public double UsagePercent { get; set; }
}

public class NetworkStats
{
    public DateTime Timestamp { get; set; }
    public List<NetworkInterfaceStats> Interfaces { get; set; } = new();
    public string? ErrorMessage { get; set; }
}

public class NetworkInterfaceStats
{
    public string Name { get; set; } = string.Empty;
    public string Description { get; set; } = string.Empty;
    public string Type { get; set; } = string.Empty;
    public long Speed { get; set; }
    public long BytesSent { get; set; }
    public long BytesReceived { get; set; }
    public long PacketsSent { get; set; }
    public long PacketsReceived { get; set; }
}

public class ProcessInfo
{
    public int ProcessId { get; set; }
    public string ProcessName { get; set; } = string.Empty;
    public long MemoryMb { get; set; }
    public int ThreadCount { get; set; }
    public DateTime StartTime { get; set; }
}

public class ServiceStatus
{
    public string ServiceName { get; set; } = string.Empty;
    public DateTime Timestamp { get; set; }
    public string Status { get; set; } = string.Empty;
    public bool IsRunning { get; set; }
    public string? ErrorMessage { get; set; }
}

public class CommandResult
{
    public string Command { get; set; } = string.Empty;
    public DateTime Timestamp { get; set; }
    public bool Success { get; set; }
    public string? Output { get; set; }
    public string? ErrorOutput { get; set; }
    public int ExitCode { get; set; }
    public string? ErrorMessage { get; set; }
}

public class ApplicationLogs
{
    public DateTime Timestamp { get; set; }
    public List<string> Lines { get; set; } = new();
    public string? ErrorMessage { get; set; }
}
