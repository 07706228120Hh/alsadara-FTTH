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
                    id = l.Id,
                    batchId = l.BatchId,
                    days = l.Days,
                    total = l.Total,
                    sent = l.Sent,
                    failed = l.Failed,
                    executedAt = l.ExecutedAt.ToString("o"),
                    isManual = l.IsManual,
                    triggeredBy = l.TriggeredBy,
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
                await client.PostAsync($"{N8nBaseUrl}/api/v1/workflows/{N8nWorkflowId}/deactivate", null);
                return;
            }

            var batches = System.Text.Json.JsonSerializer.Deserialize<List<BatchConfig>>(batchesJson ?? "[]");
            var activeBatches = batches?.Where(b => b.enabled).ToList();

            if (activeBatches == null || activeBatches.Count == 0)
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

            // بناء cron expressions لكل الوجبات المفعّلة (تحويل بغداد +3 → UTC)
            var cronIntervals = activeBatches.Select(b => new
            {
                field = "cronExpression",
                expression = $"{b.minute} {(b.hour - 3 + 24) % 24} * * *"
            }).ToArray();

            // بناء خريطة الوجبات: "hour:minute=days|hour:minute=days"
            var batchMap = string.Join("|", activeBatches.Select(b => $"{b.hour}:{b.minute}={b.days}"));

            var nodes = new List<object>();
            foreach (var node in root.GetProperty("nodes").EnumerateArray())
            {
                var nodeName = node.GetProperty("name").GetString();
                if (nodeName == "Every Hour" || nodeName == "Schedule Trigger")
                {
                    nodes.Add(new
                    {
                        parameters = new
                        {
                            rule = new { interval = cronIntervals }
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
                    var cfgNode = System.Text.Json.JsonSerializer.Deserialize<System.Text.Json.JsonElement>(node.GetRawText());
                    var assignments = cfgNode.GetProperty("parameters")
                        .GetProperty("assignments")
                        .GetProperty("assignments");

                    var updatedAssignments = new List<object>();
                    bool hasBatchMap = false;
                    foreach (var assignment in assignments.EnumerateArray())
                    {
                        var aName = assignment.GetProperty("name").GetString();
                        if (aName == "batchMap")
                        {
                            hasBatchMap = true;
                            updatedAssignments.Add(new
                            {
                                id = assignment.GetProperty("id").GetString(),
                                name = "batchMap",
                                value = batchMap,
                                type = "string"
                            });
                        }
                        else
                        {
                            updatedAssignments.Add(
                                System.Text.Json.JsonSerializer.Deserialize<object>(assignment.GetRawText())!);
                        }
                    }

                    // إضافة batchMap إذا لم تكن موجودة
                    if (!hasBatchMap)
                    {
                        updatedAssignments.Add(new
                        {
                            id = "cfg-batchmap",
                            name = "batchMap",
                            value = batchMap,
                            type = "string"
                        });
                    }

                    nodes.Add(new
                    {
                        parameters = new
                        {
                            assignments = new { assignments = updatedAssignments }
                        },
                        id = cfgNode.GetProperty("id").GetString(),
                        name = cfgNode.GetProperty("name").GetString(),
                        type = cfgNode.GetProperty("type").GetString(),
                        typeVersion = cfgNode.GetProperty("typeVersion").GetDouble(),
                        position = new[] {
                            cfgNode.GetProperty("position")[0].GetInt32(),
                            cfgNode.GetProperty("position")[1].GetInt32()
                        },
                    });
                }
                else if (nodeName == "Calculate Dates")
                {
                    // تحديث كود Calculate Dates ليقرأ batchMap ويحدد days تلقائياً
                    var calcNode = System.Text.Json.JsonSerializer.Deserialize<System.Text.Json.JsonElement>(node.GetRawText());
                    var newJsCode = @"const config = $('Configuration').first().json;
const token = $json.access_token;
// تحديد days من batchMap حسب الوقت الحالي (بتوقيت بغداد)
let days = Number(config.days || 0);
const batchMap = config.batchMap || '';
if (batchMap) {
  const now = new Date();
  const baghdadOffset = 3 * 60;
  const bNow = new Date(now.getTime() + (baghdadOffset + now.getTimezoneOffset()) * 60000);
  const curH = bNow.getHours();
  const curM = bNow.getMinutes();
  let bestDiff = 999;
  for (const entry of batchMap.split('|')) {
    const [hm, d] = entry.split('=');
    const [h, m] = hm.split(':').map(Number);
    const diff = Math.abs((curH * 60 + curM) - (h * 60 + m));
    if (diff < bestDiff) { bestDiff = diff; days = Number(d); }
  }
}
const baghdadOff = 3 * 60;
const nowD = new Date();
const baghdadNow = new Date(nowD.getTime() + (baghdadOff + nowD.getTimezoneOffset()) * 60000);
const target = new Date(baghdadNow);
target.setDate(target.getDate() + days);
const fromBaghdad = new Date(target.getFullYear(), target.getMonth(), target.getDate(), 0, 0, 0);
const toBaghdad = new Date(target.getFullYear(), target.getMonth(), target.getDate(), 23, 59, 59);
const fromUTC = new Date(fromBaghdad.getTime() - baghdadOff * 60000).toISOString();
const toUTC = new Date(toBaghdad.getTime() - baghdadOff * 60000).toISOString();
return [{ json: { access_token: token, fromExpirationDate: fromUTC, toExpirationDate: toUTC, pageNumber: 1, pageSize: 150, config: config, days: days } }];";

                    nodes.Add(new
                    {
                        parameters = new { jsCode = newJsCode },
                        id = calcNode.GetProperty("id").GetString(),
                        name = calcNode.GetProperty("name").GetString(),
                        type = calcNode.GetProperty("type").GetString(),
                        typeVersion = calcNode.GetProperty("typeVersion").GetDouble(),
                        position = new[] {
                            calcNode.GetProperty("position")[0].GetInt32(),
                            calcNode.GetProperty("position")[1].GetInt32()
                        },
                    });
                }
                else if (nodeName == "Build Report")
                {
                    // تحديث Build Report ليقرأ days من Calculate Dates بدل Configuration
                    var brNode = System.Text.Json.JsonSerializer.Deserialize<System.Text.Json.JsonElement>(node.GetRawText());
                    var brCode = @"const store = $getWorkflowStaticData('global');
const stats = store.stats || { total: 0, withPhone: 0, noPhone: 0, sent: 0, failed: 0 };
const config = $('Configuration').first().json;
const calcDays = $('Calculate Dates').first().json.days;
const days = (calcDays !== undefined && calcDays !== null) ? Number(calcDays) : Number(config.days || 0);
const now = new Date();
const bNow = new Date(now.getTime() + 180 * 60000);
const time = String(bNow.getHours()).padStart(2,'0') + ':' + String(bNow.getMinutes()).padStart(2,'0');
const date = bNow.toISOString().split('T')[0];
store.stats = null;
const dLabel = days === 0 ? '\u0627\u0644\u0645\u0646\u062a\u0647\u064a \u0627\u0644\u064a\u0648\u0645' : days === 1 ? '\u0627\u0644\u0645\u0646\u062a\u0647\u064a \u063a\u062f\u0627\u064b' : '\u062e\u0644\u0627\u0644 ' + days + ' \u0623\u064a\u0627\u0645';
return [{ json: { total: stats.total, sent: stats.sent, failed: stats.failed, withPhone: stats.withPhone, noPhone: stats.noPhone, time, date, days, apiKey: config.apiKey, managerPhone: config.managerPhone, phoneNumberId: config.phoneNumberId, message: '\ud83d\udcca *\u062a\u0642\u0631\u064a\u0631 \u0627\u0644\u062a\u0630\u0643\u064a\u0631 - ' + dLabel + '*\n\n' + date + ' - ' + time + '\n\n\u0627\u0644\u0645\u0634\u062a\u0631\u0643\u064a\u0646: *' + stats.total + '*\n\u0623\u0631\u0633\u0644: *' + stats.sent + '*\n\u0641\u0634\u0644: *' + stats.failed + '*' } }];";

                    nodes.Add(new
                    {
                        parameters = new { jsCode = brCode },
                        id = brNode.GetProperty("id").GetString(),
                        name = brNode.GetProperty("name").GetString(),
                        type = brNode.GetProperty("type").GetString(),
                        typeVersion = brNode.GetProperty("typeVersion").GetDouble(),
                        position = new[] {
                            brNode.GetProperty("position")[0].GetInt32(),
                            brNode.GetProperty("position")[1].GetInt32()
                        },
                    });
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

            _logger.LogInformation("Updated n8n reminder crons: {Crons}, batchMap: {Map}",
                string.Join(", ", activeBatches.Select(b => $"{b.minute} {b.hour} * * *")),
                batchMap);
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
