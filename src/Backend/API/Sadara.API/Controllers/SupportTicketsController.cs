using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Sadara.Domain.Entities;
using Sadara.Domain.Enums;
using Sadara.Infrastructure.Data;
using System.Security.Claims;

namespace Sadara.API.Controllers;

/// <summary>
/// تذاكر الدعم الفني للمواطنين
/// </summary>
[ApiController]
[Route("api/citizen/support")]
[Tags("Support Tickets")]
[Authorize(AuthenticationSchemes = "CitizenJwt")]
public class SupportTicketsController : ControllerBase
{
    private readonly SadaraDbContext _context;
    private readonly ILogger<SupportTicketsController> _logger;

    public SupportTicketsController(SadaraDbContext context, ILogger<SupportTicketsController> logger)
    {
        _context = context;
        _logger = logger;
    }

    /// <summary>
    /// إنشاء تذكرة دعم جديدة
    /// </summary>
    [HttpPost]
    public async Task<IActionResult> CreateTicket([FromBody] CreateTicketRequest request)
    {
        try
        {
            var citizenId = GetCurrentCitizenId();
            if (citizenId == null)
                return Unauthorized();

            var citizen = await _context.Citizens.FindAsync(citizenId);
            if (citizen == null)
                return NotFound(new { success = false, messageAr = "المستخدم غير موجود", message = "User not found" });

            var ticketNumber = $"TKT-{DateTime.UtcNow:yyyyMMdd}-{Guid.NewGuid().ToString("N").Substring(0, 6).ToUpper()}";

            var ticket = new SupportTicket
            {
                Id = Guid.NewGuid(),
                TicketNumber = ticketNumber,
                CitizenId = citizenId!.Value,
                CompanyId = citizen.CompanyId ?? Guid.Empty,
                Category = request.Category,
                Subject = request.Subject,
                Description = request.Description ?? string.Empty,
                Priority = request.Priority,
                Status = TicketStatus.Open,
                CreatedAt = DateTime.UtcNow
            };

            _context.SupportTickets.Add(ticket);
            await _context.SaveChangesAsync();

            _logger.LogInformation("New support ticket created: {TicketNumber}", ticketNumber);

            return Ok(new
            {
                success = true,
                messageAr = "تم إنشاء التذكرة بنجاح",
                message = "Ticket created successfully",
                ticket = new
                {
                    ticket.Id,
                    ticketNumber,
                    status = "Open",
                    statusAr = "مفتوحة"
                }
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error creating ticket");
            return StatusCode(500, new { success = false, messageAr = "حدث خطأ", message = "Error occurred" });
        }
    }

    /// <summary>
    /// الحصول على جميع تذاكري
    /// </summary>
    [HttpGet]
    public async Task<IActionResult> GetMyTickets([FromQuery] TicketStatus? status = null)
    {
        try
        {
            var citizenId = GetCurrentCitizenId();
            if (citizenId == null)
                return Unauthorized();

            var query = _context.SupportTickets
                .Include(t => t.Company)
                .Where(t => t.CitizenId == citizenId);

            if (status.HasValue)
                query = query.Where(t => t.Status == status);

            var tickets = await query
                .OrderByDescending(t => t.CreatedAt)
                .Select(t => new TicketResponse
                {
                    Id = t.Id,
                    TicketNumber = t.TicketNumber,
                    Subject = t.Subject,
                    Category = t.Category.ToString(),
                    CategoryAr = GetCategoryArabic(t.Category),
                    Priority = t.Priority.ToString(),
                    PriorityAr = GetPriorityArabic(t.Priority),
                    Status = t.Status.ToString(),
                    StatusAr = GetStatusArabic(t.Status),
                    CompanyName = t.Company!.NameAr,
                    AssigneeName = t.AssignedTo != null ? t.AssignedTo.FullName : null,
                    CreatedAt = t.CreatedAt,
                    UpdatedAt = t.UpdatedAt,
                    ResolvedAt = t.ResolvedAt,
                    HasUnreadMessages = t.Messages.Any(m => m.UserId != null && !m.IsRead)
                })
                .ToListAsync();

            return Ok(new
            {
                success = true,
                count = tickets.Count,
                tickets
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting tickets");
            return StatusCode(500, new { success = false, messageAr = "حدث خطأ", message = "Error occurred" });
        }
    }

    /// <summary>
    /// الحصول على تفاصيل تذكرة
    /// </summary>
    [HttpGet("{id}")]
    public async Task<IActionResult> GetTicket(Guid id)
    {
        try
        {
            var citizenId = GetCurrentCitizenId();
            if (citizenId == null)
                return Unauthorized();

            var ticket = await _context.SupportTickets
                .Include(t => t.Company)
                .Include(t => t.AssignedTo)
                .Include(t => t.Messages.OrderBy(m => m.CreatedAt))
                .Where(t => t.Id == id && t.CitizenId == citizenId)
                .FirstOrDefaultAsync();

            if (ticket == null)
                return NotFound(new { success = false, messageAr = "التذكرة غير موجودة", message = "Ticket not found" });

            // تحديث الرسائل كمقروءة
            var unreadMessages = ticket.Messages.Where(m => m.UserId != null && !m.IsRead).ToList();
            foreach (var msg in unreadMessages)
            {
                msg.IsRead = true;
                msg.ReadAt = DateTime.UtcNow;
            }
            await _context.SaveChangesAsync();

            var response = new TicketDetailResponse
            {
                Id = ticket.Id,
                TicketNumber = ticket.TicketNumber,
                Subject = ticket.Subject,
                Description = ticket.Description,
                Category = ticket.Category.ToString(),
                CategoryAr = GetCategoryArabic(ticket.Category),
                Priority = ticket.Priority.ToString(),
                PriorityAr = GetPriorityArabic(ticket.Priority),
                Status = ticket.Status.ToString(),
                StatusAr = GetStatusArabic(ticket.Status),
                CompanyId = ticket.CompanyId,
                CompanyName = ticket.Company!.NameAr,
                CompanyLogo = ticket.Company.LogoUrl,
                AssigneeId = ticket.AssignedToId,
                AssigneeName = ticket.AssignedTo?.FullName,
                ResolutionNotes = ticket.ResolutionNotes,
                SatisfactionRating = ticket.Rating,
                CreatedAt = ticket.CreatedAt,
                UpdatedAt = ticket.UpdatedAt,
                ResolvedAt = ticket.ResolvedAt,
                Messages = ticket.Messages.Select(m => new TicketMessageResponse
                {
                    Id = m.Id,
                    Message = m.Content,
                    IsFromCitizen = m.CitizenId != null,
                    SenderName = m.CitizenId != null ? "أنت" : (m.User?.FullName ?? "فريق الدعم"),
                    Attachments = m.Attachments,
                    CreatedAt = m.CreatedAt,
                    IsRead = m.IsRead
                }).ToList()
            };

            return Ok(new { success = true, ticket = response });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting ticket");
            return StatusCode(500, new { success = false, messageAr = "حدث خطأ", message = "Error occurred" });
        }
    }

    /// <summary>
    /// إضافة رسالة للتذكرة
    /// </summary>
    [HttpPost("{id}/messages")]
    public async Task<IActionResult> AddMessage(Guid id, [FromBody] AddMessageRequest request)
    {
        try
        {
            var citizenId = GetCurrentCitizenId();
            if (citizenId == null)
                return Unauthorized();

            var ticket = await _context.SupportTickets
                .FirstOrDefaultAsync(t => t.Id == id && t.CitizenId == citizenId);

            if (ticket == null)
                return NotFound(new { success = false, messageAr = "التذكرة غير موجودة", message = "Ticket not found" });

            if (ticket.Status == TicketStatus.Closed)
                return BadRequest(new { success = false, messageAr = "التذكرة مغلقة", message = "Ticket is closed" });

            var message = new TicketMessage
            {
                Id = Guid.NewGuid(),
                TicketId = id,
                CitizenId = citizenId,
                Content = request.Message,
                Attachments = request.Attachments,
                CreatedAt = DateTime.UtcNow
            };

            _context.TicketMessages.Add(message);

            // إعادة فتح التذكرة إذا كانت مغلقة
            if (ticket.Status == TicketStatus.Resolved)
            {
                ticket.Status = TicketStatus.Open;
            }

            ticket.UpdatedAt = DateTime.UtcNow;

            await _context.SaveChangesAsync();

            return Ok(new
            {
                success = true,
                messageAr = "تم إرسال الرسالة",
                message = "Message sent",
                messageResponse = new TicketMessageResponse
                {
                    Id = message.Id,
                    Message = message.Content,
                    IsFromCitizen = true,
                    SenderName = "أنت",
                    CreatedAt = message.CreatedAt
                }
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error adding message");
            return StatusCode(500, new { success = false, messageAr = "حدث خطأ", message = "Error occurred" });
        }
    }

    /// <summary>
    /// تقييم حل التذكرة
    /// </summary>
    [HttpPost("{id}/rate")]
    public async Task<IActionResult> RateTicket(Guid id, [FromBody] RateTicketRequest request)
    {
        try
        {
            var citizenId = GetCurrentCitizenId();
            if (citizenId == null)
                return Unauthorized();

            var ticket = await _context.SupportTickets
                .FirstOrDefaultAsync(t => t.Id == id && t.CitizenId == citizenId);

            if (ticket == null)
                return NotFound(new { success = false, messageAr = "التذكرة غير موجودة", message = "Ticket not found" });

            if (ticket.Status != TicketStatus.Resolved && ticket.Status != TicketStatus.Closed)
                return BadRequest(new { success = false, messageAr = "يجب حل التذكرة أولاً للتقييم", message = "Ticket must be resolved first" });

            if (request.Rating < 1 || request.Rating > 5)
                return BadRequest(new { success = false, messageAr = "التقييم يجب أن يكون من 1 إلى 5", message = "Rating must be 1-5" });

            ticket.Rating = request.Rating;
            ticket.RatingFeedback = request.Comment;
            ticket.UpdatedAt = DateTime.UtcNow;

            await _context.SaveChangesAsync();

            return Ok(new
            {
                success = true,
                messageAr = "شكراً لتقييمك",
                message = "Thank you for your feedback"
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error rating ticket");
            return StatusCode(500, new { success = false, messageAr = "حدث خطأ", message = "Error occurred" });
        }
    }

    /// <summary>
    /// إغلاق تذكرة
    /// </summary>
    [HttpPost("{id}/close")]
    public async Task<IActionResult> CloseTicket(Guid id)
    {
        try
        {
            var citizenId = GetCurrentCitizenId();
            if (citizenId == null)
                return Unauthorized();

            var ticket = await _context.SupportTickets
                .FirstOrDefaultAsync(t => t.Id == id && t.CitizenId == citizenId);

            if (ticket == null)
                return NotFound(new { success = false, messageAr = "التذكرة غير موجودة", message = "Ticket not found" });

            if (ticket.Status == TicketStatus.Closed)
                return BadRequest(new { success = false, messageAr = "التذكرة مغلقة مسبقاً", message = "Ticket already closed" });

            ticket.Status = TicketStatus.Closed;
            ticket.UpdatedAt = DateTime.UtcNow;

            await _context.SaveChangesAsync();

            return Ok(new
            {
                success = true,
                messageAr = "تم إغلاق التذكرة",
                message = "Ticket closed"
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error closing ticket");
            return StatusCode(500, new { success = false, messageAr = "حدث خطأ", message = "Error occurred" });
        }
    }

    /// <summary>
    /// الحصول على إحصائيات التذاكر
    /// </summary>
    [HttpGet("stats")]
    public async Task<IActionResult> GetTicketStats()
    {
        try
        {
            var citizenId = GetCurrentCitizenId();
            if (citizenId == null)
                return Unauthorized();

            var stats = await _context.SupportTickets
                .Where(t => t.CitizenId == citizenId)
                .GroupBy(t => 1)
                .Select(g => new
                {
                    Total = g.Count(),
                    Open = g.Count(t => t.Status == TicketStatus.Open),
                    InProgress = g.Count(t => t.Status == TicketStatus.InProgress),
                    Resolved = g.Count(t => t.Status == TicketStatus.Resolved),
                    Closed = g.Count(t => t.Status == TicketStatus.Closed)
                })
                .FirstOrDefaultAsync();

            return Ok(new
            {
                success = true,
                stats = stats ?? new { Total = 0, Open = 0, InProgress = 0, Resolved = 0, Closed = 0 }
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting stats");
            return StatusCode(500, new { success = false, messageAr = "حدث خطأ", message = "Error occurred" });
        }
    }

    // ==================== Helper Methods ====================

    private Guid? GetCurrentCitizenId()
    {
        var claim = User.FindFirst(ClaimTypes.NameIdentifier);
        if (claim == null || !Guid.TryParse(claim.Value, out var id))
            return null;
        return id;
    }

    private static string GetCategoryArabic(TicketCategory category) => category switch
    {
        TicketCategory.General => "عام",
        TicketCategory.Technical => "مشكلة تقنية",
        TicketCategory.Billing => "الفواتير",
        TicketCategory.Installation => "تركيب",
        TicketCategory.Complaint => "شكوى",
        TicketCategory.Suggestion => "اقتراح",
        _ => category.ToString()
    };

    private static string GetPriorityArabic(RequestPriority priority) => priority switch
    {
        RequestPriority.Low => "منخفضة",
        RequestPriority.Normal => "عادية",
        RequestPriority.High => "مرتفعة",
        RequestPriority.Urgent => "عاجلة",
        _ => priority.ToString()
    };

    private static string GetStatusArabic(TicketStatus status) => status switch
    {
        TicketStatus.Open => "مفتوحة",
        TicketStatus.InProgress => "قيد المعالجة",
        TicketStatus.WaitingCustomer => "بانتظار الرد",
        TicketStatus.Resolved => "تم الحل",
        TicketStatus.Closed => "مغلقة",
        _ => status.ToString()
    };
}

// ==================== DTOs ====================

public class CreateTicketRequest
{
    public TicketCategory Category { get; set; } = TicketCategory.General;
    public string Subject { get; set; } = string.Empty;
    public string? Description { get; set; }
    public RequestPriority Priority { get; set; } = RequestPriority.Normal;
}

public class TicketResponse
{
    public Guid Id { get; set; }
    public string TicketNumber { get; set; } = string.Empty;
    public string Subject { get; set; } = string.Empty;
    public string Category { get; set; } = string.Empty;
    public string CategoryAr { get; set; } = string.Empty;
    public string Priority { get; set; } = string.Empty;
    public string PriorityAr { get; set; } = string.Empty;
    public string Status { get; set; } = string.Empty;
    public string StatusAr { get; set; } = string.Empty;
    public string CompanyName { get; set; } = string.Empty;
    public string? AssigneeName { get; set; }
    public DateTime CreatedAt { get; set; }
    public DateTime? UpdatedAt { get; set; }
    public DateTime? ResolvedAt { get; set; }
    public bool HasUnreadMessages { get; set; }
}

public class TicketDetailResponse : TicketResponse
{
    public string? Description { get; set; }
    public Guid CompanyId { get; set; }
    public string? CompanyLogo { get; set; }
    public Guid? AssigneeId { get; set; }
    public string? ResolutionNotes { get; set; }
    public int? SatisfactionRating { get; set; }
    public List<TicketMessageResponse> Messages { get; set; } = new();
}

public class TicketMessageResponse
{
    public Guid Id { get; set; }
    public string Message { get; set; } = string.Empty;
    public bool IsFromCitizen { get; set; }
    public string SenderName { get; set; } = string.Empty;
    public string? Attachments { get; set; }
    public DateTime CreatedAt { get; set; }
    public bool IsRead { get; set; }
}

public class AddMessageRequest
{
    public string Message { get; set; } = string.Empty;
    public string? Attachments { get; set; }
}

public class RateTicketRequest
{
    public int Rating { get; set; }
    public string? Comment { get; set; }
}
