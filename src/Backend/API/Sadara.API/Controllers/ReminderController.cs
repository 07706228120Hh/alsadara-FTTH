using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Sadara.Domain.Entities;
using Sadara.Domain.Interfaces;

namespace Sadara.API.Controllers;

[ApiController]
[Route("api/reminders")]
[Tags("Reminders")]
public class ReminderController : ControllerBase
{
    private readonly IUnitOfWork _unitOfWork;
    private readonly IConfiguration _configuration;
    private readonly ILogger<ReminderController> _logger;
    private readonly IHttpClientFactory _httpClientFactory;

    public ReminderController(
        IUnitOfWork unitOfWork,
        IConfiguration configuration,
        ILogger<ReminderController> logger,
        IHttpClientFactory httpClientFactory)
    {
        _unitOfWork = unitOfWork;
        _configuration = configuration;
        _logger = logger;
        _httpClientFactory = httpClientFactory;
    }

    private bool ValidateApiKey()
    {
        var apiKey = Request.Headers["X-Api-Key"].FirstOrDefault();
        var configKey = _configuration["Security:InternalApiKey"] ?? "";
        return !string.IsNullOrEmpty(apiKey) && apiKey == configKey;
    }

    private string N8nBaseUrl => _configuration["N8N:BaseUrl"] ?? "https://n8n.srv991906.hstgr.cloud";
    private string N8nApiKey => _configuration["N8N:ApiKey"] ?? "";
    private string N8nWorkflowId => _configuration["N8N:ReminderWorkflowId"] ?? "jjFlKzblDkkMAM6g";

    // ══════════════════════════════════════
    // GET /api/reminders/settings
    // ══════════════════════════════════════

    [HttpGet("settings")]
    [AllowAnonymous]
    public async Task<IActionResult> GetSettings([FromQuery] string? tenantId)
    {
        if (!ValidateApiKey())
            return Unauthorized(new { success = false });

        try
        {
            var tid = tenantId ?? "default";
            var settings = await _unitOfWork.ReminderSettings
                .FirstOrDefaultAsync(s => s.TenantId == tid);

            if (settings == null)
                return Ok(new { success = true, data = new { tenantId = tid, isEnabled = false, batchesJson = "[]" } });

            return Ok(new
            {
                success = true,
                data = new
                {
                    tenantId = settings.TenantId,
                    isEnabled = settings.IsEnabled,
                    batchesJson = settings.BatchesJson,
                }
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting reminder settings");
            return StatusCode(500, new { success = false });
        }
    }

    // ══════════════════════════════════════
    // POST /api/reminders/settings
    // حفظ + تحديث cron في n8n
    // ══════════════════════════════════════

    [HttpPost("settings")]
    [AllowAnonymous]
    public async Task<IActionResult> SaveSettings([FromBody] SaveSettingsRequest request)
    {
        if (!ValidateApiKey())
            return Unauthorized(new { success = false });

        try
        {
            var tid = request.TenantId ?? "default";
            var existing = await _unitOfWork.ReminderSettings
                .FirstOrDefaultAsync(s => s.TenantId == tid);

            if (existing != null)
            {
                existing.IsEnabled = request.IsEnabled;
                existing.BatchesJson = request.BatchesJson ?? "[]";
                existing.UpdatedAt = DateTime.UtcNow;
                _unitOfWork.ReminderSettings.Update(existing);
            }
            else
            {
                await _unitOfWork.ReminderSettings.AddAsync(new ReminderSettings
                {
                    TenantId = tid,
                    IsEnabled = request.IsEnabled,
                    BatchesJson = request.BatchesJson ?? "[]",
                });
            }

            await _unitOfWork.SaveChangesAsync();

            // تحديث n8n workflow cron
            await UpdateN8nCron(request.IsEnabled, request.BatchesJson);

            return Ok(new { success = true });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error saving reminder settings");
            return StatusCode(500, new { success = false });
        }
    }

    // ══════════════════════════════════════
    // GET /api/reminders/logs
    // ══════════════════════════════════════

    [HttpGet("logs")]
    [AllowAnonymous]
    public async Task<IActionResult> GetLogs([FromQuery] int limit = 50)
    {
        if (!ValidateApiKey())
            return Unauthorized(new { success = false });

        try
        {
            var logs = await _unitOfWork.ReminderExecutionLogs.AsQueryable()
                .OrderByDescending(l => l.ExecutedAt)
                .Take(limit)
                .Select(l => new
                {
                    l.Id,
                    l.BatchId,
                    l.Days,
                    l.Total,
                    l.Sent,
                    l.Failed,
                    executedAt = l.ExecutedAt.ToString("o"),
                    l.IsManual,
                    l.TriggeredBy,
                })
                .ToListAsync();

            return Ok(new { success = true, data = logs });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting reminder logs");
            return StatusCode(500, new { success = false });
        }
    }

    // ══════════════════════════════════════
    // POST /api/reminders/logs
    // يُستدعى من n8n بعد التنفيذ
    // ══════════════════════════════════════

    [HttpPost("logs")]
    [AllowAnonymous]
    public async Task<IActionResult> SaveLog([FromBody] SaveLogRequest request)
    {
        if (!ValidateApiKey())
            return Unauthorized(new { success = false });

        try
        {
            await _unitOfWork.ReminderExecutionLogs.AddAsync(new ReminderExecutionLog
            {
                TenantId = request.TenantId ?? "default",
                BatchId = request.BatchId,
                Days = request.Days,
                Total = request.Total,
                Sent = request.Sent,
                Failed = request.Failed,
                ExecutedAt = DateTime.UtcNow,
                IsManual = request.IsManual,
                TriggeredBy = request.TriggeredBy,
            });

            await _unitOfWork.SaveChangesAsync();
            return Ok(new { success = true });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error saving reminder log");
            return StatusCode(500, new { success = false });
        }
    }

    // ══════════════════════════════════════
    // POST /api/reminders/send-now
    // إرسال يدوي — يشغّل n8n workflow
    // ══════════════════════════════════════

    [HttpPost("send-now")]
    [AllowAnonymous]
    public async Task<IActionResult> SendNow([FromBody] SendNowRequest request)
    {
        if (!ValidateApiKey())
            return Unauthorized(new { success = false });

        try
        {
            var client = _httpClientFactory.CreateClient();
            client.DefaultRequestHeaders.Add("X-N8N-API-KEY", N8nApiKey);

            // تشغيل workflow يدوياً عبر n8n API
            var response = await client.PostAsync(
                $"{N8nBaseUrl}/api/v1/executions",
                new StringContent(
                    System.Text.Json.JsonSerializer.Serialize(new { workflowId = N8nWorkflowId }),
                    System.Text.Encoding.UTF8,
                    "application/json"
                )
            );

            return Ok(new
            {
                success = true,
                message = "تم تشغيل التذكير يدوياً",
                days = request.Days,
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error triggering manual reminder");
            return StatusCode(500, new { success = false });
        }
    }

    // ══════════════════════════════════════
    // تحديث cron في n8n
    // ══════════════════════════════════════

    private async Task UpdateN8nCron(bool enabled, string? batchesJson)
    {
        try
        {
            if (string.IsNullOrEmpty(N8nApiKey)) return;

            var client = _httpClientFactory.CreateClient();
            client.DefaultRequestHeaders.Add("X-N8N-API-KEY", N8nApiKey);

            if (!enabled)
            {
                // إيقاف workflow
                await client.PostAsync($"{N8nBaseUrl}/api/v1/workflows/{N8nWorkflowId}/deactivate", null);
                return;
            }

            // استخراج أول وجبة مفعّلة لتحديث cron
            var batches = System.Text.Json.JsonSerializer.Deserialize<List<BatchConfig>>(batchesJson ?? "[]");
            var activeBatch = batches?.FirstOrDefault(b => b.enabled);

            if (activeBatch == null)
            {
                await client.PostAsync($"{N8nBaseUrl}/api/v1/workflows/{N8nWorkflowId}/deactivate", null);
                return;
            }

            // جلب workflow الحالي
            var getResponse = await client.GetAsync($"{N8nBaseUrl}/api/v1/workflows/{N8nWorkflowId}");
            if (!getResponse.IsSuccessStatusCode) return;

            var wfJson = await getResponse.Content.ReadAsStringAsync();
            using var doc = System.Text.Json.JsonDocument.Parse(wfJson);
            var root = doc.RootElement;

            // تحديث cron expression في trigger node
            var cronExpression = $"{activeBatch.minute} {activeBatch.hour} * * *";

            // بناء payload للتحديث — نحدّث nodes
            var nodes = new List<object>();
            foreach (var node in root.GetProperty("nodes").EnumerateArray())
            {
                var nodeName = node.GetProperty("name").GetString();
                if (nodeName == "Every Hour" || nodeName == "Schedule Trigger")
                {
                    // تحديث cron
                    nodes.Add(new
                    {
                        parameters = new
                        {
                            rule = new
                            {
                                interval = new[] { new { field = "cronExpression", expression = cronExpression } }
                            }
                        },
                        id = node.GetProperty("id").GetString(),
                        name = node.GetProperty("name").GetString(),
                        type = node.GetProperty("type").GetString(),
                        typeVersion = node.GetProperty("typeVersion").GetDouble(),
                        position = new[] {
                            node.GetProperty("position")[0].GetInt32(),
                            node.GetProperty("position")[1].GetInt32()
                        },
                    });
                }
                else if (nodeName == "Configuration")
                {
                    // تحديث days في Configuration node
                    nodes.Add(System.Text.Json.JsonSerializer.Deserialize<object>(node.GetRawText())!);
                }
                else
                {
                    nodes.Add(System.Text.Json.JsonSerializer.Deserialize<object>(node.GetRawText())!);
                }
            }

            var connections = System.Text.Json.JsonSerializer.Deserialize<object>(
                root.GetProperty("connections").GetRawText())!;

            var updatePayload = new
            {
                name = root.GetProperty("name").GetString(),
                nodes,
                connections,
                settings = new { executionOrder = "v1" },
            };

            var content = new StringContent(
                System.Text.Json.JsonSerializer.Serialize(updatePayload),
                System.Text.Encoding.UTF8,
                "application/json"
            );

            await client.PutAsync($"{N8nBaseUrl}/api/v1/workflows/{N8nWorkflowId}", content);

            // تفعيل
            await client.PostAsync($"{N8nBaseUrl}/api/v1/workflows/{N8nWorkflowId}/activate", null);

            _logger.LogInformation("Updated n8n reminder cron to: {Cron}", cronExpression);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error updating n8n cron");
        }
    }

    // ══════════════════════════════════════
    // DTOs
    // ══════════════════════════════════════

    public class SaveSettingsRequest
    {
        public string? TenantId { get; set; }
        public bool IsEnabled { get; set; }
        public string? BatchesJson { get; set; }
    }

    public class SaveLogRequest
    {
        public string? TenantId { get; set; }
        public string? BatchId { get; set; }
        public int Days { get; set; }
        public int Total { get; set; }
        public int Sent { get; set; }
        public int Failed { get; set; }
        public bool IsManual { get; set; }
        public string? TriggeredBy { get; set; }
    }

    public class SendNowRequest
    {
        public int Days { get; set; }
        public string? TriggeredBy { get; set; }
    }

    private class BatchConfig
    {
        public string? id { get; set; }
        public int hour { get; set; }
        public int minute { get; set; }
        public int days { get; set; }
        public bool enabled { get; set; }
    }
}
