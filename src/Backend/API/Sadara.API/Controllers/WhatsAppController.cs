using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Sadara.Domain.Entities;
using Sadara.Domain.Interfaces;

namespace Sadara.API.Controllers;

/// <summary>
/// API لإدارة محادثات واتساب — بديل Firestore
/// يستخدم API Key للمصادقة من تطبيق Desktop
/// و Webhook Secret لرسائل n8n الواردة
/// </summary>
[ApiController]
[Route("api/[controller]")]
[Tags("WhatsApp")]
public class WhatsAppController : ControllerBase
{
    private readonly IUnitOfWork _unitOfWork;
    private readonly IConfiguration _configuration;
    private readonly ILogger<WhatsAppController> _logger;

    public WhatsAppController(
        IUnitOfWork unitOfWork,
        IConfiguration configuration,
        ILogger<WhatsAppController> logger)
    {
        _unitOfWork = unitOfWork;
        _configuration = configuration;
        _logger = logger;
    }

    // ══════════════════════════════════════
    // Auth helpers
    // ══════════════════════════════════════

    private bool ValidateApiKey()
    {
        var apiKey = Request.Headers["X-Api-Key"].FirstOrDefault();
        var configKey = _configuration["Security:InternalApiKey"]
            ?? Environment.GetEnvironmentVariable("SADARA_INTERNAL_API_KEY")
            ?? "sadara-internal-2024-secure-key";
        return !string.IsNullOrEmpty(apiKey) && apiKey == configKey;
    }

    private bool ValidateWebhookSecret()
    {
        var secret = Request.Headers["X-Webhook-Secret"].FirstOrDefault();
        var configSecret = _configuration["WhatsApp:WebhookSecret"]
            ?? Environment.GetEnvironmentVariable("WHATSAPP_WEBHOOK_SECRET")
            ?? "";
        return !string.IsNullOrEmpty(secret) && secret == configSecret;
    }

    /// <summary>تطبيع رقم الهاتف إلى صيغة 964XXXXXXXXX</summary>
    private static string NormalizePhone(string phone)
    {
        if (string.IsNullOrWhiteSpace(phone)) return phone;
        phone = phone.Trim().Replace(" ", "").Replace("-", "");
        if (phone.StartsWith("+")) phone = phone[1..];
        if (phone.StartsWith("00")) phone = phone[2..];
        if (phone.StartsWith("07") && phone.Length == 11)
            phone = "964" + phone[1..];
        return phone;
    }

    // ══════════════════════════════════════
    // GET /api/whatsapp/conversations
    // ══════════════════════════════════════

    [HttpGet("conversations")]
    [AllowAnonymous]
    public async Task<IActionResult> GetConversations(
        [FromQuery] int limit = 200,
        [FromQuery] DateTime? updatedSince = null)
    {
        if (!ValidateApiKey())
            return Unauthorized(new { success = false, message = "Invalid API Key" });

        try
        {
            var query = _unitOfWork.WhatsAppConversations.AsQueryable();

            if (updatedSince.HasValue)
            {
                var since = updatedSince.Value.ToUniversalTime();
                query = query.Where(c => c.UpdatedAt > since || c.CreatedAt > since);
            }

            var conversations = await query
                .OrderByDescending(c => c.LastMessageTime)
                .Take(limit)
                .Select(c => new
                {
                    phoneNumber = c.PhoneNumber,
                    userName = c.UserName,
                    contactName = c.ContactName,
                    lastMessage = c.LastMessage,
                    lastMessageTime = c.LastMessageTime.ToString("o"),
                    lastMessageType = c.LastMessageType,
                    unreadCount = c.UnreadCount,
                    isIncoming = c.IsIncoming,
                    updatedAt = c.UpdatedAt != null ? c.UpdatedAt.Value.ToString("o") : null,
                    createdAt = c.CreatedAt.ToString("o"),
                })
                .ToListAsync();

            return Ok(new { success = true, data = conversations });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting WhatsApp conversations");
            return StatusCode(500, new { success = false, message = "حدث خطأ" });
        }
    }

    // ══════════════════════════════════════
    // GET /api/whatsapp/conversations/{phone}/messages
    // ══════════════════════════════════════

    [HttpGet("conversations/{phone}/messages")]
    [AllowAnonymous]
    public async Task<IActionResult> GetMessages(string phone, [FromQuery] int limit = 200)
    {
        if (!ValidateApiKey())
            return Unauthorized(new { success = false, message = "Invalid API Key" });

        try
        {
            var normalizedPhone = NormalizePhone(phone);

            var conversation = await _unitOfWork.WhatsAppConversations
                .FirstOrDefaultAsync(c => c.PhoneNumber == normalizedPhone);

            if (conversation == null)
                return Ok(new { success = true, data = Array.Empty<object>() });

            var messages = await _unitOfWork.WhatsAppMessages.AsQueryable()
                .Where(m => m.ConversationId == conversation.Id)
                .OrderBy(m => m.CreatedAt)
                .Take(limit)
                .Select(m => new
                {
                    messageId = m.ExternalMessageId,
                    phoneNumber = m.PhoneNumber,
                    text = m.Text,
                    messageType = m.MessageType,
                    direction = m.Direction,
                    status = m.Status,
                    contactName = m.ContactName,
                    mediaId = m.MediaId,
                    mediaUrl = m.MediaUrl,
                    mimeType = m.MimeType,
                    mediaFileName = m.MediaFileName,
                    createdAt = m.CreatedAt.ToString("o"),
                })
                .ToListAsync();

            return Ok(new { success = true, data = messages });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting messages for {Phone}", phone);
            return StatusCode(500, new { success = false, message = "حدث خطأ" });
        }
    }

    // ══════════════════════════════════════
    // GET /api/whatsapp/unread-count
    // ══════════════════════════════════════

    [HttpGet("unread-count")]
    [AllowAnonymous]
    public async Task<IActionResult> GetUnreadCount()
    {
        if (!ValidateApiKey())
            return Unauthorized(new { success = false, message = "Invalid API Key" });

        try
        {
            var count = await _unitOfWork.WhatsAppConversations.AsQueryable()
                .SumAsync(c => c.UnreadCount);

            return Ok(new { success = true, data = new { unreadCount = count } });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting unread count");
            return StatusCode(500, new { success = false, message = "حدث خطأ" });
        }
    }

    // ══════════════════════════════════════
    // POST /api/whatsapp/conversations/{phone}/messages
    // تسجيل رسالة صادرة
    // ══════════════════════════════════════

    [HttpPost("conversations/{phone}/messages")]
    [AllowAnonymous]
    public async Task<IActionResult> SendMessage(string phone, [FromBody] SendMessageRequest request)
    {
        if (!ValidateApiKey())
            return Unauthorized(new { success = false, message = "Invalid API Key" });

        try
        {
            var normalizedPhone = NormalizePhone(phone);
            var now = DateTime.UtcNow;

            // البحث عن المحادثة أو إنشاؤها
            var conversation = await _unitOfWork.WhatsAppConversations
                .FirstOrDefaultAsync(c => c.PhoneNumber == normalizedPhone);

            if (conversation == null)
            {
                conversation = new WhatsAppConversation
                {
                    PhoneNumber = normalizedPhone,
                    LastMessage = request.Message ?? "",
                    LastMessageTime = now,
                    LastMessageType = request.Type ?? "text",
                    IsIncoming = false,
                    UnreadCount = 0,
                };
                await _unitOfWork.WhatsAppConversations.AddAsync(conversation);
                await _unitOfWork.SaveChangesAsync();
            }
            else
            {
                conversation.LastMessage = request.Message ?? "";
                conversation.LastMessageTime = now;
                conversation.LastMessageType = request.Type ?? "text";
                conversation.IsIncoming = false;
                conversation.UpdatedAt = now;
                _unitOfWork.WhatsAppConversations.Update(conversation);
            }

            // إنشاء الرسالة
            var message = new WhatsAppMessage
            {
                ExternalMessageId = $"out_{now.Ticks}",
                ConversationId = conversation.Id,
                PhoneNumber = normalizedPhone,
                Text = request.Message ?? "",
                MessageType = request.Type ?? "text",
                Direction = "outgoing",
                Status = "sent",
            };
            await _unitOfWork.WhatsAppMessages.AddAsync(message);
            await _unitOfWork.SaveChangesAsync();

            return Ok(new { success = true, message = "تم حفظ الرسالة" });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error sending message to {Phone}", phone);
            return StatusCode(500, new { success = false, message = "حدث خطأ" });
        }
    }

    // ══════════════════════════════════════
    // PUT /api/whatsapp/conversations/{phone}/read
    // تصفير عدد غير المقروءة
    // ══════════════════════════════════════

    [HttpPut("conversations/{phone}/read")]
    [AllowAnonymous]
    public async Task<IActionResult> MarkAsRead(string phone)
    {
        if (!ValidateApiKey())
            return Unauthorized(new { success = false, message = "Invalid API Key" });

        try
        {
            var normalizedPhone = NormalizePhone(phone);
            var conversation = await _unitOfWork.WhatsAppConversations
                .FirstOrDefaultAsync(c => c.PhoneNumber == normalizedPhone);

            if (conversation == null)
                return NotFound(new { success = false, message = "المحادثة غير موجودة" });

            conversation.UnreadCount = 0;
            conversation.UpdatedAt = DateTime.UtcNow;
            _unitOfWork.WhatsAppConversations.Update(conversation);
            await _unitOfWork.SaveChangesAsync();

            return Ok(new { success = true });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error marking conversation as read: {Phone}", phone);
            return StatusCode(500, new { success = false, message = "حدث خطأ" });
        }
    }

    // ══════════════════════════════════════
    // DELETE /api/whatsapp/conversations/{phone}
    // حذف محادثة (soft delete)
    // ══════════════════════════════════════

    [HttpDelete("conversations/{phone}")]
    [AllowAnonymous]
    public async Task<IActionResult> DeleteConversation(string phone)
    {
        if (!ValidateApiKey())
            return Unauthorized(new { success = false, message = "Invalid API Key" });

        try
        {
            var normalizedPhone = NormalizePhone(phone);
            var conversation = await _unitOfWork.WhatsAppConversations
                .FirstOrDefaultAsync(c => c.PhoneNumber == normalizedPhone);

            if (conversation == null)
                return NotFound(new { success = false, message = "المحادثة غير موجودة" });

            // حذف الرسائل أولاً (soft delete)
            var messages = await _unitOfWork.WhatsAppMessages.AsQueryable()
                .Where(m => m.ConversationId == conversation.Id)
                .ToListAsync();

            foreach (var msg in messages)
            {
                msg.IsDeleted = true;
                msg.DeletedAt = DateTime.UtcNow;
                _unitOfWork.WhatsAppMessages.Update(msg);
            }

            // حذف المحادثة (soft delete)
            conversation.IsDeleted = true;
            conversation.DeletedAt = DateTime.UtcNow;
            _unitOfWork.WhatsAppConversations.Update(conversation);

            await _unitOfWork.SaveChangesAsync();
            return Ok(new { success = true, message = "تم حذف المحادثة" });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error deleting conversation: {Phone}", phone);
            return StatusCode(500, new { success = false, message = "حدث خطأ" });
        }
    }

    // ══════════════════════════════════════
    // POST /api/whatsapp/webhook/incoming
    // Webhook لرسائل n8n الواردة
    // ══════════════════════════════════════

    [HttpPost("webhook/incoming")]
    [AllowAnonymous]
    public async Task<IActionResult> IncomingWebhook([FromBody] IncomingMessageRequest request)
    {
        if (!ValidateWebhookSecret() && !ValidateApiKey())
            return Unauthorized(new { success = false, message = "Invalid webhook secret" });

        try
        {
            var normalizedPhone = NormalizePhone(request.PhoneNumber ?? "");
            if (string.IsNullOrWhiteSpace(normalizedPhone))
                return BadRequest(new { success = false, message = "رقم الهاتف مطلوب" });

            var now = DateTime.UtcNow;

            // البحث عن المحادثة أو إنشاؤها
            var conversation = await _unitOfWork.WhatsAppConversations
                .FirstOrDefaultAsync(c => c.PhoneNumber == normalizedPhone);

            if (conversation == null)
            {
                conversation = new WhatsAppConversation
                {
                    PhoneNumber = normalizedPhone,
                    ContactName = request.ContactName,
                    UserName = request.ContactName,
                    LastMessage = request.Text ?? "",
                    LastMessageTime = now,
                    LastMessageType = request.MessageType ?? "text",
                    IsIncoming = true,
                    UnreadCount = 1,
                };
                await _unitOfWork.WhatsAppConversations.AddAsync(conversation);
                await _unitOfWork.SaveChangesAsync();
            }
            else
            {
                conversation.LastMessage = request.Text ?? "";
                conversation.LastMessageTime = now;
                conversation.LastMessageType = request.MessageType ?? "text";
                conversation.IsIncoming = true;
                conversation.UnreadCount += 1;
                conversation.UpdatedAt = now;
                if (!string.IsNullOrWhiteSpace(request.ContactName))
                    conversation.ContactName = request.ContactName;
                _unitOfWork.WhatsAppConversations.Update(conversation);
            }

            // التحقق من عدم تكرار الرسالة
            var externalId = request.MessageId ?? $"in_{now.Ticks}";
            var exists = await _unitOfWork.WhatsAppMessages
                .AnyAsync(m => m.ExternalMessageId == externalId);

            if (!exists)
            {
                var message = new WhatsAppMessage
                {
                    ExternalMessageId = externalId,
                    ConversationId = conversation.Id,
                    PhoneNumber = normalizedPhone,
                    Text = request.Text ?? "",
                    MessageType = request.MessageType ?? "text",
                    Direction = "incoming",
                    Status = "received",
                    ContactName = request.ContactName,
                    MediaId = request.MediaId,
                    MediaUrl = request.MediaUrl,
                    MimeType = request.MimeType,
                    MediaFileName = request.MediaFileName,
                };
                await _unitOfWork.WhatsAppMessages.AddAsync(message);
            }

            await _unitOfWork.SaveChangesAsync();
            return Ok(new { success = true, message = "تم حفظ الرسالة الواردة" });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error processing incoming webhook");
            return StatusCode(500, new { success = false, message = "حدث خطأ" });
        }
    }

    // ══════════════════════════════════════
    // POST /api/whatsapp/webhook/status
    // تحديث حالة رسالة
    // ══════════════════════════════════════

    [HttpPost("webhook/status")]
    [AllowAnonymous]
    public async Task<IActionResult> StatusWebhook([FromBody] StatusUpdateRequest request)
    {
        if (!ValidateWebhookSecret() && !ValidateApiKey())
            return Unauthorized(new { success = false, message = "Invalid webhook secret" });

        try
        {
            if (string.IsNullOrWhiteSpace(request.MessageId))
                return BadRequest(new { success = false, message = "معرف الرسالة مطلوب" });

            var message = await _unitOfWork.WhatsAppMessages
                .FirstOrDefaultAsync(m => m.ExternalMessageId == request.MessageId);

            if (message == null)
                return NotFound(new { success = false, message = "الرسالة غير موجودة" });

            message.Status = request.Status ?? message.Status;
            message.UpdatedAt = DateTime.UtcNow;
            _unitOfWork.WhatsAppMessages.Update(message);
            await _unitOfWork.SaveChangesAsync();

            return Ok(new { success = true });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error updating message status");
            return StatusCode(500, new { success = false, message = "حدث خطأ" });
        }
    }

    // ══════════════════════════════════════
    // GET /api/whatsapp/batch-reports
    // ══════════════════════════════════════

    [HttpGet("batch-reports")]
    [AllowAnonymous]
    public async Task<IActionResult> GetBatchReports([FromQuery] int limit = 50)
    {
        if (!ValidateApiKey())
            return Unauthorized(new { success = false, message = "Invalid API Key" });

        try
        {
            var reports = await _unitOfWork.WhatsAppBatchReports.AsQueryable()
                .OrderByDescending(r => r.CreatedAt)
                .Take(limit)
                .Select(r => new
                {
                    r.Id,
                    r.BatchId,
                    r.TemplateType,
                    r.Total,
                    r.Sent,
                    r.Failed,
                    r.Rate,
                    completedAt = r.CompletedAt != null ? r.CompletedAt.Value.ToString("o") : null,
                    r.Warning,
                    r.FailedSummary,
                    r.EarlyStop,
                    r.EarlyStopReason,
                    r.Status,
                    createdAt = r.CreatedAt.ToString("o"),
                })
                .ToListAsync();

            return Ok(new { success = true, data = reports });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting batch reports");
            return StatusCode(500, new { success = false, message = "حدث خطأ" });
        }
    }

    // ══════════════════════════════════════
    // POST /api/whatsapp/batch-reports
    // ══════════════════════════════════════

    [HttpPost("batch-reports")]
    [AllowAnonymous]
    public async Task<IActionResult> SaveBatchReport([FromBody] BatchReportRequest request)
    {
        if (!ValidateApiKey() && !ValidateWebhookSecret())
            return Unauthorized(new { success = false, message = "Invalid API Key" });

        try
        {
            var report = new WhatsAppBatchReport
            {
                BatchId = request.BatchId ?? $"batch_{DateTime.UtcNow.Ticks}",
                TemplateType = request.TemplateType,
                Total = request.Total,
                Sent = request.Sent,
                Failed = request.Failed,
                Rate = request.Rate,
                CompletedAt = !string.IsNullOrWhiteSpace(request.CompletedAt)
                    ? DateTime.Parse(request.CompletedAt).ToUniversalTime()
                    : DateTime.UtcNow,
                Warning = request.Warning,
                FailedSummary = request.FailedSummary,
                EarlyStop = request.EarlyStop,
                EarlyStopReason = request.EarlyStopReason,
                Status = request.EarlyStop ? "stopped" : "completed",
            };

            await _unitOfWork.WhatsAppBatchReports.AddAsync(report);
            await _unitOfWork.SaveChangesAsync();

            return Ok(new { success = true, id = report.Id });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error saving batch report");
            return StatusCode(500, new { success = false, message = "حدث خطأ" });
        }
    }

    // ══════════════════════════════════════
    // DELETE /api/whatsapp/batch-reports/{id}
    // ══════════════════════════════════════

    [HttpDelete("batch-reports/{id:long}")]
    [AllowAnonymous]
    public async Task<IActionResult> DeleteBatchReport(long id)
    {
        if (!ValidateApiKey())
            return Unauthorized(new { success = false, message = "Invalid API Key" });

        try
        {
            var report = await _unitOfWork.WhatsAppBatchReports
                .FirstOrDefaultAsync(r => r.Id == id);

            if (report == null)
                return NotFound(new { success = false, message = "التقرير غير موجود" });

            report.IsDeleted = true;
            report.DeletedAt = DateTime.UtcNow;
            _unitOfWork.WhatsAppBatchReports.Update(report);
            await _unitOfWork.SaveChangesAsync();

            return Ok(new { success = true });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error deleting batch report {Id}", id);
            return StatusCode(500, new { success = false, message = "حدث خطأ" });
        }
    }

    // ══════════════════════════════════════
    // Request DTOs
    // ══════════════════════════════════════

    public class SendMessageRequest
    {
        public string? Message { get; set; }
        public string? Type { get; set; }
    }

    public class IncomingMessageRequest
    {
        public string? MessageId { get; set; }
        public string? PhoneNumber { get; set; }
        public string? Text { get; set; }
        public string? MessageType { get; set; }
        public string? ContactName { get; set; }
        public long? Timestamp { get; set; }
        public string? MediaId { get; set; }
        public string? MediaUrl { get; set; }
        public string? MimeType { get; set; }
        public string? MediaFileName { get; set; }
    }

    public class StatusUpdateRequest
    {
        public string? MessageId { get; set; }
        public string? Status { get; set; }
    }

    public class BatchReportRequest
    {
        public string? BatchId { get; set; }
        public string? TemplateType { get; set; }
        public int Total { get; set; }
        public int Sent { get; set; }
        public int Failed { get; set; }
        public string? Rate { get; set; }
        public string? CompletedAt { get; set; }
        public string? Warning { get; set; }
        public string? FailedSummary { get; set; }
        public bool EarlyStop { get; set; }
        public string? EarlyStopReason { get; set; }
    }
}
