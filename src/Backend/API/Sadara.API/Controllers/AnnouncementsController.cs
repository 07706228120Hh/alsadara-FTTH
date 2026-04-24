using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Sadara.Application.Interfaces;
using Sadara.Domain.Entities;
using Sadara.Domain.Interfaces;

namespace Sadara.API.Controllers;

[ApiController]
[Route("api/[controller]")]
[Authorize]
public class AnnouncementsController : ControllerBase
{
    private readonly IUnitOfWork _uow;
    private readonly IWebHostEnvironment _env;
    private readonly IFcmNotificationService _fcmService;

    public AnnouncementsController(IUnitOfWork uow, IWebHostEnvironment env, IFcmNotificationService fcmService)
    {
        _uow = uow;
        _env = env;
        _fcmService = fcmService;
    }

    // ═══════════════════════════════════════
    // جلب الإعلانات الموجهة للمستخدم الحالي
    // ═══════════════════════════════════════

    /// <summary>الإعلانات الموجهة لي — مرتبة: مثبت أولاً ثم الأحدث</summary>
    [HttpGet("my")]
    public async Task<IActionResult> GetMyAnnouncements([FromQuery] int page = 1, [FromQuery] int pageSize = 20)
    {
        var userId = GetUserId();
        var user = await _uow.Users.GetByIdAsync(userId);
        if (user == null) return Unauthorized(new { success = false, message = "غير مصرح" });

        var now = DateTime.UtcNow;

        var query = _uow.Announcements.AsQueryable()
            .Where(a => a.CompanyId == user.CompanyId
                        && a.IsPublished
                        && (a.ExpiresAt == null || a.ExpiresAt > now))
            .Where(a =>
                a.TargetType == AnnouncementTargetType.All
                || (a.TargetType == AnnouncementTargetType.Department && a.TargetValue == user.Department)
                || (a.TargetType == AnnouncementTargetType.Role && a.TargetValue == user.Role.ToString())
                || (a.TargetType == AnnouncementTargetType.Location && a.TargetValue == user.Center)
                || (a.TargetType == AnnouncementTargetType.Custom && a.Targets.Any(t => t.UserId == userId))
            );

        var total = await query.CountAsync();
        var announcements = await query
            .OrderByDescending(a => a.IsPinned)
            .ThenByDescending(a => a.CreatedAt)
            .Skip((page - 1) * pageSize)
            .Take(pageSize)
            .Select(a => new
            {
                id = a.Id,
                title = a.Title,
                body = a.Body,
                imageUrl = a.ImageUrl,
                targetType = (int)a.TargetType,
                targetValue = a.TargetValue,
                isUrgent = a.IsUrgent,
                isPinned = a.IsPinned,
                createdAt = a.CreatedAt,
                expiresAt = a.ExpiresAt,
                createdBy = a.CreatedByUser != null ? a.CreatedByUser.FullName : "",
                isRead = a.Reads.Any(r => r.UserId == userId),
            })
            .ToListAsync();

        return Ok(new { success = true, data = announcements, total, page, pageSize });
    }

    /// <summary>تسجيل قراءة إعلان</summary>
    [HttpPatch("{id:long}/read")]
    public async Task<IActionResult> MarkAsRead(long id)
    {
        var userId = GetUserId();
        var exists = await _uow.AnnouncementReads.AnyAsync(r => r.AnnouncementId == id && r.UserId == userId);
        if (!exists)
        {
            await _uow.AnnouncementReads.AddAsync(new AnnouncementRead
            {
                AnnouncementId = id,
                UserId = userId,
                ReadAt = DateTime.UtcNow,
            });
            await _uow.SaveChangesAsync();
        }
        return Ok(new { success = true });
    }

    /// <summary>عدد الإعلانات غير المقروءة</summary>
    [HttpGet("unread-count")]
    public async Task<IActionResult> GetUnreadCount()
    {
        var userId = GetUserId();
        var user = await _uow.Users.GetByIdAsync(userId);
        if (user == null) return Unauthorized(new { success = false });

        var now = DateTime.UtcNow;
        var count = await _uow.Announcements.AsQueryable()
            .Where(a => a.CompanyId == user.CompanyId && a.IsPublished
                        && (a.ExpiresAt == null || a.ExpiresAt > now)
                        && !a.Reads.Any(r => r.UserId == userId))
            .Where(a =>
                a.TargetType == AnnouncementTargetType.All
                || (a.TargetType == AnnouncementTargetType.Department && a.TargetValue == user.Department)
                || (a.TargetType == AnnouncementTargetType.Role && a.TargetValue == user.Role.ToString())
                || (a.TargetType == AnnouncementTargetType.Location && a.TargetValue == user.Center)
                || (a.TargetType == AnnouncementTargetType.Custom && a.Targets.Any(t => t.UserId == userId))
            )
            .CountAsync();

        return Ok(new { success = true, count });
    }

    /// <summary>تقرير من قرأ ومن لم يقرأ إعلان معين</summary>
    [HttpGet("{id:long}/read-report")]
    public async Task<IActionResult> GetReadReport(long id)
    {
        var userId = GetUserId();
        var user = await _uow.Users.GetByIdAsync(userId);
        if (user?.CompanyId == null) return Unauthorized(new { success = false });

        var announcement = await _uow.Announcements.GetByIdAsync(id);
        if (announcement == null || announcement.CompanyId != user.CompanyId)
            return NotFound(new { success = false });

        // جلب قائمة من قرأ
        var reads = await _uow.AnnouncementReads.AsQueryable()
            .Where(r => r.AnnouncementId == id)
            .Select(r => new { userId = r.UserId, name = r.User != null ? r.User.FullName : "", readAt = r.ReadAt })
            .ToListAsync();

        // جلب قائمة المستهدفين
        List<object> targetUsers;
        if (announcement.TargetType == AnnouncementTargetType.All)
        {
            targetUsers = await _uow.Users.AsQueryable()
                .Where(u => u.CompanyId == user.CompanyId && u.IsActive)
                .Select(u => (object)new { userId = u.Id, name = u.FullName })
                .ToListAsync();
        }
        else if (announcement.TargetType == AnnouncementTargetType.Custom)
        {
            targetUsers = await _uow.AnnouncementTargets.AsQueryable()
                .Where(t => t.AnnouncementId == id)
                .Select(t => (object)new { userId = t.UserId, name = t.User != null ? t.User.FullName : "" })
                .ToListAsync();
        }
        else
        {
            var q = _uow.Users.AsQueryable().Where(u => u.CompanyId == user.CompanyId && u.IsActive);
            if (announcement.TargetType == AnnouncementTargetType.Department)
            {
                var deptUserIds = await _uow.UserDepartments.AsQueryable()
                    .Include(ud => ud.Department)
                    .Where(ud => ud.Department != null && ud.Department.NameAr == announcement.TargetValue)
                    .Select(ud => ud.UserId)
                    .ToListAsync();
                q = q.Where(u => u.Department == announcement.TargetValue || deptUserIds.Contains(u.Id));
            }
            else if (announcement.TargetType == AnnouncementTargetType.Role)
                q = q.Where(u => u.Role.ToString() == announcement.TargetValue);
            else if (announcement.TargetType == AnnouncementTargetType.Location)
                q = q.Where(u => u.Center == announcement.TargetValue);
            targetUsers = await q.Select(u => (object)new { userId = u.Id, name = u.FullName }).ToListAsync();
        }

        var readUserIds = reads.Select(r => r.userId).ToHashSet();
        var notRead = targetUsers
            .Where(t => !readUserIds.Contains(((dynamic)t).userId))
            .ToList();

        return Ok(new
        {
            success = true,
            data = new
            {
                totalTargeted = targetUsers.Count,
                totalRead = reads.Count,
                totalNotRead = notRead.Count,
                readUsers = reads,
                notReadUsers = notRead,
            }
        });
    }

    // ═══════════════════════════════════════
    // إدارة الإعلانات (CRUD)
    // ═══════════════════════════════════════

    [HttpGet]
    public async Task<IActionResult> GetAll([FromQuery] int page = 1, [FromQuery] int pageSize = 20)
    {
        var userId = GetUserId();
        var user = await _uow.Users.GetByIdAsync(userId);
        if (user == null) return Unauthorized(new { success = false });

        var query = _uow.Announcements.AsQueryable()
            .Where(a => a.CompanyId == user.CompanyId)
            .OrderByDescending(a => a.IsPinned)
            .ThenByDescending(a => a.CreatedAt);

        var total = await query.CountAsync();
        var announcements = await query
            .Skip((page - 1) * pageSize)
            .Take(pageSize)
            .Select(a => new
            {
                id = a.Id,
                title = a.Title,
                body = a.Body,
                imageUrl = a.ImageUrl,
                targetType = (int)a.TargetType,
                targetValue = a.TargetValue,
                isPublished = a.IsPublished,
                isUrgent = a.IsUrgent,
                isPinned = a.IsPinned,
                createdAt = a.CreatedAt,
                expiresAt = a.ExpiresAt,
                createdBy = a.CreatedByUser != null ? a.CreatedByUser.FullName : "",
                readCount = a.Reads.Count(),
                targetUsers = a.TargetType == AnnouncementTargetType.Custom
                    ? a.Targets.Select(t => new { userId = t.UserId, name = t.User != null ? t.User.FullName : "" }).ToList()
                    : null,
            })
            .ToListAsync();

        return Ok(new { success = true, data = announcements, total, page, pageSize });
    }

    [HttpPost]
    public async Task<IActionResult> Create([FromBody] CreateAnnouncementDto dto)
    {
        var userId = GetUserId();
        var user = await _uow.Users.GetByIdAsync(userId);
        if (user?.CompanyId == null) return Unauthorized(new { success = false });

        var announcement = new Announcement
        {
            CompanyId = user.CompanyId.Value,
            Title = dto.Title,
            Body = dto.Body,
            ImageUrl = dto.ImageUrl,
            TargetType = (AnnouncementTargetType)dto.TargetType,
            TargetValue = dto.TargetValue,
            IsPublished = dto.IsPublished,
            IsUrgent = dto.IsUrgent,
            IsPinned = dto.IsPinned,
            ExpiresAt = dto.ExpiresAt?.ToUniversalTime(),
            CreatedByUserId = userId,
        };

        await _uow.Announcements.AddAsync(announcement);
        await _uow.SaveChangesAsync();

        if (dto.TargetType == 4 && dto.TargetUserIds?.Any() == true)
        {
            foreach (var uid in dto.TargetUserIds)
            {
                await _uow.AnnouncementTargets.AddAsync(new AnnouncementTarget
                {
                    AnnouncementId = announcement.Id,
                    UserId = uid,
                });
            }
            await _uow.SaveChangesAsync();
        }

        // إرسال إشعار FCM عند النشر
        if (dto.IsPublished)
        {
            _ = Task.Run(async () =>
            {
                try
                {
                    var targetUserIds = await GetTargetUserIds(announcement, user.CompanyId.Value);
                    if (targetUserIds.Any())
                    {
                        var fcmData = new Dictionary<string, string>
                        {
                            { "type", "announcement" },
                            { "announcementId", announcement.Id.ToString() },
                            { "isUrgent", dto.IsUrgent.ToString().ToLower() },
                        };
                        await _fcmService.SendToUsersAsync(
                            targetUserIds,
                            dto.IsUrgent ? $"🔴 عاجل: {dto.Title}" : $"📢 {dto.Title}",
                            dto.Body.Length > 100 ? dto.Body[..100] + "..." : dto.Body,
                            fcmData
                        );
                    }
                }
                catch { /* لا نريد فشل النشر بسبب FCM */ }
            });
        }

        return Ok(new { success = true, data = new { id = announcement.Id } });
    }

    [HttpPut("{id:long}")]
    public async Task<IActionResult> Update(long id, [FromBody] CreateAnnouncementDto dto)
    {
        var userId = GetUserId();
        var user = await _uow.Users.GetByIdAsync(userId);
        if (user?.CompanyId == null) return Unauthorized(new { success = false });

        var announcement = await _uow.Announcements.GetByIdAsync(id);
        if (announcement == null || announcement.CompanyId != user.CompanyId)
            return NotFound(new { success = false, message = "الإعلان غير موجود" });

        var wasUnpublished = !announcement.IsPublished;

        announcement.Title = dto.Title;
        announcement.Body = dto.Body;
        announcement.ImageUrl = dto.ImageUrl;
        announcement.TargetType = (AnnouncementTargetType)dto.TargetType;
        announcement.TargetValue = dto.TargetValue;
        announcement.IsPublished = dto.IsPublished;
        announcement.IsUrgent = dto.IsUrgent;
        announcement.IsPinned = dto.IsPinned;
        announcement.ExpiresAt = dto.ExpiresAt?.ToUniversalTime();
        announcement.UpdatedAt = DateTime.UtcNow;

        _uow.Announcements.Update(announcement);

        var oldTargets = await _uow.AnnouncementTargets.FindAsync(t => t.AnnouncementId == id);
        foreach (var t in oldTargets) _uow.AnnouncementTargets.Delete(t);

        if (dto.TargetType == 4 && dto.TargetUserIds?.Any() == true)
        {
            foreach (var uid in dto.TargetUserIds)
            {
                await _uow.AnnouncementTargets.AddAsync(new AnnouncementTarget { AnnouncementId = id, UserId = uid });
            }
        }

        await _uow.SaveChangesAsync();

        // FCM عند نشر مسودة للمرة الأولى
        if (wasUnpublished && dto.IsPublished)
        {
            _ = Task.Run(async () =>
            {
                try
                {
                    var targetUserIds = await GetTargetUserIds(announcement, user.CompanyId!.Value);
                    if (targetUserIds.Any())
                    {
                        await _fcmService.SendToUsersAsync(
                            targetUserIds,
                            dto.IsUrgent ? $"🔴 عاجل: {dto.Title}" : $"📢 {dto.Title}",
                            dto.Body.Length > 100 ? dto.Body[..100] + "..." : dto.Body,
                            new Dictionary<string, string> { { "type", "announcement" }, { "announcementId", id.ToString() }, { "isUrgent", dto.IsUrgent.ToString().ToLower() } }
                        );
                    }
                }
                catch { }
            });
        }

        return Ok(new { success = true });
    }

    [HttpDelete("{id:long}")]
    public async Task<IActionResult> Delete(long id)
    {
        var userId = GetUserId();
        var user = await _uow.Users.GetByIdAsync(userId);
        if (user?.CompanyId == null) return Unauthorized(new { success = false });

        var announcement = await _uow.Announcements.GetByIdAsync(id);
        if (announcement == null || announcement.CompanyId != user.CompanyId)
            return NotFound(new { success = false, message = "الإعلان غير موجود" });

        announcement.IsDeleted = true;
        announcement.DeletedAt = DateTime.UtcNow;
        _uow.Announcements.Update(announcement);
        await _uow.SaveChangesAsync();

        return Ok(new { success = true });
    }

    [HttpPost("upload-image")]
    [RequestSizeLimit(10 * 1024 * 1024)]
    public async Task<IActionResult> UploadImage(IFormFile file)
    {
        if (file == null || file.Length == 0)
            return BadRequest(new { success = false, message = "لا يوجد ملف" });

        var allowedTypes = new[] { "image/jpeg", "image/png", "image/gif", "image/webp" };
        if (!allowedTypes.Contains(file.ContentType.ToLower()))
            return BadRequest(new { success = false, message = "نوع الملف غير مسموح" });

        var uploadsDir = Path.Combine(_env.ContentRootPath, "uploads", "announcements");
        Directory.CreateDirectory(uploadsDir);

        var ext = Path.GetExtension(file.FileName);
        var fileName = $"{Guid.NewGuid()}{ext}";
        var filePath = Path.Combine(uploadsDir, fileName);

        using (var stream = new FileStream(filePath, FileMode.Create))
            await file.CopyToAsync(stream);

        return Ok(new { success = true, data = new { url = $"/uploads/announcements/{fileName}", fileName } });
    }

    // ═══ Helpers ═══

    private Guid GetUserId()
    {
        var claim = User.FindFirst(ClaimTypes.NameIdentifier)?.Value ?? User.FindFirst("sub")?.Value;
        return Guid.Parse(claim!);
    }

    private async Task<List<Guid>> GetTargetUserIds(Announcement announcement, Guid companyId)
    {
        if (announcement.TargetType == AnnouncementTargetType.All)
        {
            return await _uow.Users.AsQueryable()
                .Where(u => u.CompanyId == companyId && u.IsActive)
                .Select(u => u.Id).ToListAsync();
        }
        if (announcement.TargetType == AnnouncementTargetType.Custom)
        {
            return await _uow.AnnouncementTargets.AsQueryable()
                .Where(t => t.AnnouncementId == announcement.Id)
                .Select(t => t.UserId).ToListAsync();
        }
        var q = _uow.Users.AsQueryable().Where(u => u.CompanyId == companyId && u.IsActive);
        if (announcement.TargetType == AnnouncementTargetType.Department)
        {
            var deptUserIds = await _uow.UserDepartments.AsQueryable()
                .Include(ud => ud.Department)
                .Where(ud => ud.Department != null && ud.Department.NameAr == announcement.TargetValue)
                .Select(ud => ud.UserId)
                .ToListAsync();
            q = q.Where(u => u.Department == announcement.TargetValue || deptUserIds.Contains(u.Id));
        }
        else if (announcement.TargetType == AnnouncementTargetType.Role)
            q = q.Where(u => u.Role.ToString() == announcement.TargetValue);
        else if (announcement.TargetType == AnnouncementTargetType.Location)
            q = q.Where(u => u.Center == announcement.TargetValue);
        return await q.Select(u => u.Id).ToListAsync();
    }
}

public class CreateAnnouncementDto
{
    public string Title { get; set; } = string.Empty;
    public string Body { get; set; } = string.Empty;
    public string? ImageUrl { get; set; }
    public int TargetType { get; set; } = 0;
    public string? TargetValue { get; set; }
    public bool IsPublished { get; set; } = true;
    public bool IsUrgent { get; set; } = false;
    public bool IsPinned { get; set; } = false;
    public DateTime? ExpiresAt { get; set; }
    public List<Guid>? TargetUserIds { get; set; }
}
