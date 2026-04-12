using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.SignalR;
using Microsoft.EntityFrameworkCore;
using Sadara.API.Hubs;
using Sadara.Application.Interfaces;
using Sadara.Domain.Entities;
using Sadara.Domain.Interfaces;

namespace Sadara.API.Controllers;

/// <summary>
/// نظام المحادثة الداخلي — REST API
/// يدير الغرف، الرسائل، المرفقات، والأعضاء
/// </summary>
[ApiController]
[Route("api/[controller]")]
[Authorize]
public class ChatController : ControllerBase
{
    private readonly IUnitOfWork _uow;
    private readonly IHubContext<ChatHub> _chatHub;
    private readonly IFcmNotificationService _fcmService;
    private readonly ILogger<ChatController> _logger;
    private readonly IWebHostEnvironment _env;

    public ChatController(
        IUnitOfWork uow,
        IHubContext<ChatHub> chatHub,
        IFcmNotificationService fcmService,
        ILogger<ChatController> logger,
        IWebHostEnvironment env)
    {
        _uow = uow;
        _chatHub = chatHub;
        _fcmService = fcmService;
        _logger = logger;
        _env = env;
    }

    // ═══════════════════════════════════════
    // الغرف
    // ═══════════════════════════════════════

    /// <summary>قائمة محادثاتي (مرتبة بآخر رسالة)</summary>
    [HttpGet("rooms")]
    public async Task<IActionResult> GetMyRooms()
    {
        var userId = GetUserId();

        var rooms = await _uow.ChatRoomMembers.AsQueryable()
            .Where(m => m.UserId == userId && !m.IsDeleted)
            .Include(m => m.ChatRoom)
            .Select(m => new
            {
                id = m.ChatRoom.Id,
                type = (int)m.ChatRoom.Type,
                name = m.ChatRoom.Name,
                avatarUrl = m.ChatRoom.AvatarUrl,
                departmentId = m.ChatRoom.DepartmentId,
                lastMessageAt = m.ChatRoom.LastMessageAt,
                lastMessagePreview = m.ChatRoom.LastMessagePreview,
                lastMessageSenderName = m.ChatRoom.LastMessageSenderName,
                isMuted = m.IsMuted,
                isPinned = m.IsPinned,
                isAdmin = m.IsAdmin,
                lastReadAt = m.LastReadAt,
                memberCount = m.ChatRoom.Members.Count(mb => !mb.IsDeleted),
                unreadCount = m.ChatRoom.Messages
                    .Count(msg => !msg.IsDeleted && msg.CreatedAt > (m.LastReadAt ?? DateTime.MinValue) && msg.SenderId != userId),
            })
            .OrderByDescending(r => r.isPinned)
            .ThenByDescending(r => r.lastMessageAt)
            .ToListAsync();

        // للمحادثات الخاصة: جلب اسم الطرف الآخر
        var directRoomIds = rooms.Where(r => r.type == (int)ChatRoomType.Direct).Select(r => r.id).ToList();
        var otherMembers = new Dictionary<Guid, object>();

        if (directRoomIds.Any())
        {
            var others = await _uow.ChatRoomMembers.AsQueryable()
                .Where(m => directRoomIds.Contains(m.ChatRoomId) && m.UserId != userId && !m.IsDeleted)
                .Include(m => m.User)
                .Select(m => new
                {
                    roomId = m.ChatRoomId,
                    userId = m.UserId,
                    fullName = m.User.FullName,
                    profileImageUrl = m.User.ProfileImageUrl,
                    department = m.User.Department,
                })
                .ToListAsync();

            foreach (var o in others)
                otherMembers[o.roomId] = o;
        }

        var result = rooms.Select(r => new
        {
            r.id,
            r.type,
            name = r.type == (int)ChatRoomType.Direct && otherMembers.ContainsKey(r.id)
                ? ((dynamic)otherMembers[r.id]).fullName
                : r.name,
            avatarUrl = r.type == (int)ChatRoomType.Direct && otherMembers.ContainsKey(r.id)
                ? ((dynamic)otherMembers[r.id]).profileImageUrl
                : r.avatarUrl,
            r.departmentId,
            r.lastMessageAt,
            r.lastMessagePreview,
            r.lastMessageSenderName,
            r.isMuted,
            r.isPinned,
            r.isAdmin,
            r.memberCount,
            r.unreadCount,
            otherUser = r.type == (int)ChatRoomType.Direct && otherMembers.ContainsKey(r.id)
                ? otherMembers[r.id] : null,
        });

        return Ok(result);
    }

    /// <summary>جميع محادثات الشركة (مدير الشركة فقط)</summary>
    [HttpGet("rooms/all")]
    public async Task<IActionResult> GetAllCompanyRooms()
    {
        var userId = GetUserId();
        var user = await _uow.Users.GetByIdAsync(userId);
        if (user == null) return Unauthorized();
        if (!user.IsCompanyAdminOrAbove)
            return StatusCode(403, new { error = "فقط مدير الشركة" });

        var companyId = user.CompanyId;
        if (companyId == null) return BadRequest("لا توجد شركة");

        var rooms = await _uow.ChatRooms.AsQueryable()
            .Where(r => r.CompanyId == companyId.Value && !r.IsDeleted)
            .OrderByDescending(r => r.LastMessageAt)
            .Select(r => new
            {
                id = r.Id,
                type = (int)r.Type,
                name = r.Name,
                createdByName = r.CreatedByUser.FullName,
                memberCount = r.Members.Count(m => !m.IsDeleted),
                messageCount = r.Messages.Count(m => !m.IsDeleted),
                lastMessageAt = r.LastMessageAt,
                lastMessagePreview = r.LastMessagePreview,
                lastMessageSenderName = r.LastMessageSenderName,
                createdAt = r.CreatedAt,
                // أسماء الأعضاء (أول 5)
                memberNames = r.Members
                    .Where(m => !m.IsDeleted)
                    .Select(m => m.User.FullName)
                    .Take(5)
                    .ToList(),
            })
            .ToListAsync();

        return Ok(rooms);
    }

    /// <summary>إنشاء غرفة محادثة جديدة</summary>
    [HttpPost("rooms")]
    public async Task<IActionResult> CreateRoom([FromBody] CreateRoomDto dto)
    {
        try
        {
        var userId = GetUserId();
        var user = await _uow.Users.GetByIdAsync(userId);
        if (user == null) return Unauthorized();

        var companyId = user.CompanyId;
        if (companyId == null) return BadRequest("المستخدم غير مرتبط بشركة");

        // التحقق من وجود محادثة خاصة مسبقاً
        if (dto.Type == ChatRoomType.Direct && dto.MemberIds?.Count == 1)
        {
            var otherUserId = dto.MemberIds[0];

            // جلب غرف المستخدم الحالي (Direct فقط)
            var myDirectRoomIds = await _uow.ChatRoomMembers.AsQueryable()
                .Where(m => m.UserId == userId && !m.IsDeleted && m.ChatRoom.Type == ChatRoomType.Direct)
                .Select(m => m.ChatRoomId)
                .ToListAsync();

            if (myDirectRoomIds.Any())
            {
                // هل الطرف الآخر عضو في إحداها؟
                var existingRoom = await _uow.ChatRoomMembers.AsQueryable()
                    .Where(m => m.UserId == otherUserId && !m.IsDeleted && myDirectRoomIds.Contains(m.ChatRoomId))
                    .Select(m => m.ChatRoomId)
                    .FirstOrDefaultAsync();

                if (existingRoom != Guid.Empty)
                {
                    var room = await _uow.ChatRooms.GetByIdAsync(existingRoom);
                    if (room != null)
                        return Ok(new { id = room.Id, exists = true });
                }
            }
        }

        // التحقق من محادثة قسم موجودة
        if (dto.Type == ChatRoomType.Department && dto.DepartmentId.HasValue)
        {
            var existingDeptRoom = await _uow.ChatRooms.FirstOrDefaultAsync(r =>
                r.CompanyId == companyId.Value &&
                r.Type == ChatRoomType.Department &&
                r.DepartmentId == dto.DepartmentId.Value &&
                !r.IsDeleted);

            if (existingDeptRoom != null)
                return Ok(new { id = existingDeptRoom.Id, exists = true });
        }

        var chatRoom = new ChatRoom
        {
            Id = Guid.NewGuid(),
            CompanyId = companyId.Value,
            Type = dto.Type,
            DepartmentId = dto.DepartmentId,
            Name = dto.Name,
            CreatedByUserId = userId,
        };

        await _uow.ChatRooms.AddAsync(chatRoom);

        // إضافة المنشئ كعضو ومدير
        await _uow.ChatRoomMembers.AddAsync(new ChatRoomMember
        {
            ChatRoomId = chatRoom.Id,
            UserId = userId,
            IsAdmin = true,
        });

        // إضافة الأعضاء
        if (dto.Type == ChatRoomType.Department && dto.DepartmentId.HasValue)
        {
            // جلب جميع أعضاء القسم
            var deptMembers = await _uow.UserDepartments.AsQueryable()
                .Where(ud => ud.DepartmentId == dto.DepartmentId.Value && !ud.IsDeleted)
                .Select(ud => ud.UserId)
                .ToListAsync();

            foreach (var memberId in deptMembers.Where(id => id != userId))
            {
                await _uow.ChatRoomMembers.AddAsync(new ChatRoomMember
                {
                    ChatRoomId = chatRoom.Id,
                    UserId = memberId,
                });
            }
        }
        else if (dto.Type == ChatRoomType.Broadcast)
        {
            // جلب جميع موظفي الشركة
            var companyEmployees = await _uow.Users.AsQueryable()
                .Where(u => u.CompanyId == companyId.Value && u.IsActive && !u.IsDeleted && u.Id != userId)
                .Select(u => u.Id)
                .ToListAsync();

            foreach (var empId in companyEmployees)
            {
                await _uow.ChatRoomMembers.AddAsync(new ChatRoomMember
                {
                    ChatRoomId = chatRoom.Id,
                    UserId = empId,
                });
            }
        }
        else if (dto.MemberIds?.Any() == true)
        {
            foreach (var memberId in dto.MemberIds.Where(id => id != userId))
            {
                await _uow.ChatRoomMembers.AddAsync(new ChatRoomMember
                {
                    ChatRoomId = chatRoom.Id,
                    UserId = memberId,
                });
            }
        }

        await _uow.SaveChangesAsync();

        return Ok(new { id = chatRoom.Id, exists = false });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "CreateRoom failed: {Error}", ex.Message);
            return StatusCode(500, new { error = ex.Message });
        }
    }

    /// <summary>أعضاء الغرفة</summary>
    [HttpGet("rooms/{roomId}/members")]
    public async Task<IActionResult> GetRoomMembers(Guid roomId)
    {
        var userId = GetUserId();

        // التحقق من العضوية
        var isMember = await _uow.ChatRoomMembers.AnyAsync(m =>
            m.ChatRoomId == roomId && m.UserId == userId && !m.IsDeleted);
        if (!isMember) return Forbid();

        var members = await _uow.ChatRoomMembers.AsQueryable()
            .Where(m => m.ChatRoomId == roomId && !m.IsDeleted)
            .Include(m => m.User)
            .Select(m => new
            {
                userId = m.UserId,
                fullName = m.User.FullName,
                profileImageUrl = m.User.ProfileImageUrl,
                department = m.User.Department,
                role = (int)m.User.Role,
                phoneNumber = m.User.PhoneNumber,
                email = m.User.Email,
                isAdmin = m.IsAdmin,
                joinedAt = m.JoinedAt,
                isActive = m.User.IsActive,
            })
            .OrderByDescending(m => m.isAdmin)
            .ThenBy(m => m.fullName)
            .ToListAsync();

        return Ok(members);
    }

    // ═══════════════════════════════════════
    // الرسائل
    // ═══════════════════════════════════════

    /// <summary>رسائل غرفة (مع pagination)</summary>
    [HttpGet("rooms/{roomId}/messages")]
    public async Task<IActionResult> GetMessages(Guid roomId, [FromQuery] int page = 1, [FromQuery] int pageSize = 50, [FromQuery] string? before = null)
    {
        var userId = GetUserId();

        // السماح للمدير (CompanyAdmin+) بقراءة كل المحادثات
        var currentUser = await _uow.Users.GetByIdAsync(userId);
        if (currentUser?.IsCompanyAdminOrAbove != true)
        {
            var isMember = await _uow.ChatRoomMembers.AnyAsync(m =>
                m.ChatRoomId == roomId && m.UserId == userId && !m.IsDeleted);
            if (!isMember) return Forbid();
        }

        var query = _uow.ChatMessages.AsQueryable()
            .Where(m => m.ChatRoomId == roomId && !m.IsDeleted);

        // تحميل رسائل أقدم من وقت معين (للتمرير لأعلى)
        if (!string.IsNullOrEmpty(before) && DateTime.TryParse(before, out var beforeDate))
        {
            query = query.Where(m => m.CreatedAt < beforeDate.ToUniversalTime());
        }

        var messages = await query
            .OrderByDescending(m => m.CreatedAt)
            .Skip((page - 1) * pageSize)
            .Take(pageSize)
            .Include(m => m.Sender)
            .Include(m => m.Attachments)
            .Include(m => m.Mentions)
            .Include(m => m.ReplyToMessage).ThenInclude(r => r!.Sender)
            .Select(m => new
            {
                id = m.Id,
                senderId = m.SenderId,
                senderName = m.Sender.FullName,
                senderAvatar = m.Sender.ProfileImageUrl,
                messageType = (int)m.MessageType,
                content = m.Content,
                isForwarded = m.IsForwarded,
                createdAt = m.CreatedAt,
                replyTo = m.ReplyToMessage == null ? null : new
                {
                    id = m.ReplyToMessage.Id,
                    senderName = m.ReplyToMessage.Sender.FullName,
                    content = m.ReplyToMessage.Content,
                    messageType = (int)m.ReplyToMessage.MessageType,
                },
                attachments = m.Attachments.Where(a => !a.IsDeleted).Select(a => new
                {
                    id = a.Id,
                    fileName = a.FileName,
                    filePath = a.FilePath,
                    fileSize = a.FileSize,
                    mimeType = a.MimeType,
                    thumbnailPath = a.ThumbnailPath,
                    durationSeconds = a.DurationSeconds,
                }),
                mentions = m.Mentions.Where(mn => !mn.IsDeleted).Select(mn => mn.MentionedUserId),
                isRead = m.ChatRoom.Members
                    .Any(member => member.UserId != m.SenderId && !member.IsDeleted &&
                         member.LastReadAt != null && member.LastReadAt >= m.CreatedAt),
                reactions = m.Reactions.Where(r => !r.IsDeleted).Select(r => new { emoji = r.Emoji, userId = r.UserId }),
            })
            .ToListAsync();

        return Ok(messages);
    }

    /// <summary>حذف محادثة كاملة (مدير الشركة فقط)</summary>
    [HttpDelete("rooms/{roomId}")]
    public async Task<IActionResult> DeleteRoom(Guid roomId)
    {
        try
        {
            var userId = GetUserId();
            var user = await _uow.Users.GetByIdAsync(userId);
            if (user == null) return Unauthorized();

            // فقط CompanyAdmin أو أعلى
            if (!user.IsCompanyAdminOrAbove)
                return StatusCode(403, new { error = "فقط مدير الشركة يمكنه حذف المحادثات" });

            var room = await _uow.ChatRooms.GetByIdAsync(roomId);
            if (room == null) return NotFound();

            // التأكد أن الغرفة تابعة لنفس الشركة
            if (room.CompanyId != user.CompanyId)
                return Forbid();

            // حذف ناعم للغرفة
            room.IsDeleted = true;
            room.DeletedAt = DateTime.UtcNow;
            _uow.ChatRooms.Update(room);

            // حذف ناعم لجميع الأعضاء
            var members = await _uow.ChatRoomMembers.FindAsync(m => m.ChatRoomId == roomId && !m.IsDeleted);
            foreach (var member in members)
            {
                member.IsDeleted = true;
                member.DeletedAt = DateTime.UtcNow;
                _uow.ChatRoomMembers.Update(member);
            }

            await _uow.SaveChangesAsync();

            // إعلام الأعضاء عبر SignalR
            await _chatHub.Clients.Group($"chat_{roomId}").SendAsync("RoomDeleted", roomId.ToString());

            _logger.LogInformation("Room {RoomId} deleted by admin {UserId}", roomId, userId);
            return Ok(new { success = true });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "DeleteRoom failed");
            return StatusCode(500, new { error = ex.Message });
        }
    }

    /// <summary>حذف رسالة (soft delete)</summary>
    [HttpDelete("messages/{messageId}")]
    public async Task<IActionResult> DeleteMessage(Guid messageId)
    {
        var userId = GetUserId();

        var message = await _uow.ChatMessages.GetByIdAsync(messageId);
        if (message == null) return NotFound();

        // فقط المرسل أو مدير الغرفة يمكنه الحذف
        if (message.SenderId != userId)
        {
            var isAdmin = await _uow.ChatRoomMembers.AnyAsync(m =>
                m.ChatRoomId == message.ChatRoomId && m.UserId == userId && m.IsAdmin && !m.IsDeleted);
            if (!isAdmin) return Forbid();
        }

        message.IsDeleted = true;
        message.DeletedAt = DateTime.UtcNow;
        _uow.ChatMessages.Update(message);
        await _uow.SaveChangesAsync();

        await _chatHub.Clients.Group($"chat_{message.ChatRoomId}").SendAsync("MessageDeleted", messageId.ToString(), message.ChatRoomId.ToString());

        return Ok();
    }

    /// <summary>إرسال رسالة عبر REST API (بديل عن SignalR)</summary>
    [HttpPost("rooms/{roomId}/messages")]
    public async Task<IActionResult> SendMessage(Guid roomId, [FromBody] SendMessageDto dto)
    {
        try
        {
            var userId = GetUserId();

            var isMember = await _uow.ChatRoomMembers.AnyAsync(m =>
                m.ChatRoomId == roomId && m.UserId == userId && !m.IsDeleted);
            if (!isMember) return Forbid();

            var sender = await _uow.Users.GetByIdAsync(userId);
            if (sender == null) return Unauthorized();

            var message = new ChatMessage
            {
                Id = Guid.NewGuid(),
                ChatRoomId = roomId,
                SenderId = userId,
                MessageType = (ChatMessageType)(dto.MessageType),
                Content = dto.Content,
                ReplyToMessageId = dto.ReplyToMessageId,
            };
            await _uow.ChatMessages.AddAsync(message);

            // تحديث آخر رسالة في الغرفة
            var room = await _uow.ChatRooms.GetByIdAsync(roomId);
            if (room != null)
            {
                room.LastMessageAt = DateTime.UtcNow;
                room.LastMessageSenderName = sender.FullName;
                room.LastMessagePreview = dto.MessageType == 0
                    ? (dto.Content?.Length > 100 ? dto.Content[..100] + "..." : dto.Content)
                    : dto.MessageType switch { 1 => "📷 صورة", 2 => "🎤 صوت", 3 => "📍 موقع", 4 => "👤 جهة اتصال", 5 => "📎 ملف", _ => "" };
                _uow.ChatRooms.Update(room);
            }

            // حفظ التاقات
            if (dto.MentionUserIds?.Any() == true)
            {
                foreach (var mentionId in dto.MentionUserIds)
                {
                    await _uow.ChatMentions.AddAsync(new ChatMention
                    {
                        ChatMessageId = message.Id,
                        MentionedUserId = mentionId,
                    });
                }
            }

            await _uow.SaveChangesAsync();

            // بث عبر SignalR
            var messageData = new
            {
                id = message.Id.ToString(),
                roomId = roomId.ToString(),
                senderId = userId.ToString(),
                senderName = sender.FullName,
                senderAvatar = sender.ProfileImageUrl,
                messageType = dto.MessageType,
                content = dto.Content,
                replyToMessageId = dto.ReplyToMessageId?.ToString(),
                isForwarded = false,
                createdAt = message.CreatedAt.ToString("o"),
                mentions = dto.MentionUserIds?.Select(id => id.ToString()).ToList() ?? new List<string>(),
            };
            await _chatHub.Clients.Group($"chat_{roomId}").SendAsync("ReceiveMessage", messageData);

            // FCM للغائبين
            _ = Task.Run(async () =>
            {
                try
                {
                    using var scope = HttpContext.RequestServices.CreateScope();
                    var uow = scope.ServiceProvider.GetRequiredService<IUnitOfWork>();
                    var fcm = scope.ServiceProvider.GetRequiredService<IFcmNotificationService>();

                    var memberIds = await uow.ChatRoomMembers.AsQueryable()
                        .Where(m => m.ChatRoomId == roomId && m.UserId != userId && !m.IsMuted && !m.IsDeleted)
                        .Select(m => m.UserId)
                        .ToListAsync();

                    if (memberIds.Any())
                    {
                        var roomName = room?.Name ?? sender.FullName;
                        var preview = dto.MessageType == 0 ? dto.Content ?? "" : "📎 مرفق";
                        await fcm.SendToUsersAsync(memberIds, $"رسالة من {sender.FullName}", preview.Length > 200 ? preview[..200] : preview,
                            new Dictionary<string, string> { ["type"] = "chat_message", ["roomId"] = roomId.ToString(), ["messageId"] = message.Id.ToString() });
                    }
                }
                catch (Exception ex) { _logger.LogError(ex, "Chat FCM failed"); }
            });

            return Ok(new
            {
                id = message.Id,
                roomId = roomId,
                senderId = userId,
                senderName = sender.FullName,
                senderAvatar = sender.ProfileImageUrl,
                messageType = dto.MessageType,
                content = dto.Content,
                createdAt = message.CreatedAt,
                isForwarded = false,
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "SendMessage REST failed");
            return StatusCode(500, new { error = ex.Message });
        }
    }

    // ═══════════════════════════════════════
    // المرفقات
    // ═══════════════════════════════════════

    /// <summary>رفع مرفق (صورة/صوت/ملف)</summary>
    [HttpPost("rooms/{roomId}/attachments")]
    [RequestSizeLimit(50 * 1024 * 1024)] // 50 MB
    public async Task<IActionResult> UploadAttachment(Guid roomId, IFormFile file)
    {
        var userId = GetUserId();

        var isMember = await _uow.ChatRoomMembers.AnyAsync(m =>
            m.ChatRoomId == roomId && m.UserId == userId && !m.IsDeleted);
        if (!isMember) return Forbid();

        if (file == null || file.Length == 0)
            return BadRequest("لم يتم اختيار ملف");

        // التحقق من نوع الملف
        var allowedTypes = new[] { "image/", "audio/", "video/", "application/pdf", "application/msword",
            "application/vnd.openxmlformats", "text/" };
        if (!allowedTypes.Any(t => file.ContentType.StartsWith(t)))
            return BadRequest("نوع الملف غير مسموح");

        // إنشاء مجلد التخزين
        var uploadsDir = Path.Combine(_env.ContentRootPath, "uploads", "chat", roomId.ToString());
        Directory.CreateDirectory(uploadsDir);

        // حفظ الملف
        var ext = Path.GetExtension(file.FileName);
        var savedName = $"{Guid.NewGuid()}{ext}";
        var filePath = Path.Combine(uploadsDir, savedName);

        using (var stream = new FileStream(filePath, FileMode.Create))
        {
            await file.CopyToAsync(stream);
        }

        var relativePath = $"/uploads/chat/{roomId}/{savedName}";

        // إنشاء صورة مصغرة للصور
        string? thumbnailPath = null;
        if (file.ContentType.StartsWith("image/"))
        {
            thumbnailPath = relativePath; // يمكن تحسينه لاحقاً بإنشاء thumbnail فعلي
        }

        return Ok(new
        {
            fileName = file.FileName,
            filePath = relativePath,
            fileSize = file.Length,
            mimeType = file.ContentType,
            thumbnailPath = thumbnailPath,
        });
    }

    /// <summary>تنزيل/عرض مرفق</summary>
    [HttpGet("attachments/{**filePath}")]
    public IActionResult GetAttachment(string filePath)
    {
        var fullPath = Path.Combine(_env.ContentRootPath, filePath);
        if (!System.IO.File.Exists(fullPath))
            return NotFound();

        var mimeType = filePath.EndsWith(".jpg") || filePath.EndsWith(".jpeg") ? "image/jpeg"
            : filePath.EndsWith(".png") ? "image/png"
            : filePath.EndsWith(".webp") ? "image/webp"
            : filePath.EndsWith(".mp3") ? "audio/mpeg"
            : filePath.EndsWith(".aac") ? "audio/aac"
            : filePath.EndsWith(".ogg") ? "audio/ogg"
            : filePath.EndsWith(".m4a") ? "audio/mp4"
            : filePath.EndsWith(".pdf") ? "application/pdf"
            : "application/octet-stream";

        return PhysicalFile(fullPath, mimeType);
    }

    // ═══════════════════════════════════════
    // العداد والبحث
    // ═══════════════════════════════════════

    /// <summary>عدد الرسائل غير المقروءة الكلي</summary>
    [HttpGet("unread-count")]
    public async Task<IActionResult> GetUnreadCount()
    {
        var userId = GetUserId();

        var totalUnread = await _uow.ChatRoomMembers.AsQueryable()
            .Where(m => m.UserId == userId && !m.IsDeleted && !m.IsMuted)
            .SumAsync(m => m.ChatRoom.Messages
                .Count(msg => !msg.IsDeleted && msg.CreatedAt > (m.LastReadAt ?? DateTime.MinValue) && msg.SenderId != userId));

        return Ok(new { unreadCount = totalUnread });
    }

    /// <summary>بحث في الرسائل</summary>
    [HttpGet("search")]
    public async Task<IActionResult> SearchMessages([FromQuery] string q, [FromQuery] int page = 1, [FromQuery] int pageSize = 20)
    {
        var userId = GetUserId();
        if (string.IsNullOrWhiteSpace(q)) return Ok(Array.Empty<object>());

        // جلب غرف المستخدم
        var myRoomIds = await _uow.ChatRoomMembers.AsQueryable()
            .Where(m => m.UserId == userId && !m.IsDeleted)
            .Select(m => m.ChatRoomId)
            .ToListAsync();

        var results = await _uow.ChatMessages.AsQueryable()
            .Where(m => myRoomIds.Contains(m.ChatRoomId) && !m.IsDeleted &&
                        m.MessageType == ChatMessageType.Text &&
                        m.Content != null && EF.Functions.ILike(m.Content, $"%{q}%"))
            .OrderByDescending(m => m.CreatedAt)
            .Skip((page - 1) * pageSize)
            .Take(pageSize)
            .Include(m => m.Sender)
            .Include(m => m.ChatRoom)
            .Select(m => new
            {
                messageId = m.Id,
                roomId = m.ChatRoomId,
                roomName = m.ChatRoom.Name,
                senderName = m.Sender.FullName,
                content = m.Content,
                createdAt = m.CreatedAt,
            })
            .ToListAsync();

        return Ok(results);
    }

    /// <summary>بطاقة تعريف الموظف</summary>
    [HttpGet("users/{targetUserId}/profile-card")]
    public async Task<IActionResult> GetProfileCard(Guid targetUserId)
    {
        var user = await _uow.Users.GetByIdAsync(targetUserId);
        if (user == null) return NotFound();

        // جلب أقسام المستخدم
        var departments = await _uow.UserDepartments.AsQueryable()
            .Where(ud => ud.UserId == targetUserId && !ud.IsDeleted)
            .Include(ud => ud.Department)
            .Select(ud => new { id = ud.DepartmentId, name = ud.Department.NameAr })
            .ToListAsync();

        return Ok(new
        {
            userId = user.Id,
            fullName = user.FullName,
            phoneNumber = user.PhoneNumber,
            email = user.Email,
            profileImageUrl = user.ProfileImageUrl,
            department = user.Department,
            departments = departments,
            role = (int)user.Role,
            roleName = user.Role.ToString(),
            center = user.Center,
            employeeCode = user.EmployeeCode,
            isActive = user.IsActive,
            lastLoginAt = user.LastLoginAt,
        });
    }

    /// <summary>قائمة الموظفين المتاحين لبدء محادثة</summary>
    [HttpGet("available-users")]
    public async Task<IActionResult> GetAvailableUsers([FromQuery] string? search)
    {
        var userId = GetUserId();
        var user = await _uow.Users.GetByIdAsync(userId);
        if (user?.CompanyId == null) return Ok(Array.Empty<object>());

        var query = _uow.Users.AsQueryable()
            .Where(u => u.CompanyId == user.CompanyId && u.IsActive && !u.IsDeleted && u.Id != userId);

        if (!string.IsNullOrWhiteSpace(search))
        {
            query = query.Where(u =>
                EF.Functions.ILike(u.FullName, $"%{search}%") ||
                (u.PhoneNumber != null && u.PhoneNumber.Contains(search)) ||
                (u.Department != null && EF.Functions.ILike(u.Department, $"%{search}%")));
        }

        var users = await query
            .OrderBy(u => u.FullName)
            .Take(50)
            .Select(u => new
            {
                userId = u.Id,
                fullName = u.FullName,
                phoneNumber = u.PhoneNumber,
                profileImageUrl = u.ProfileImageUrl,
                department = u.Department,
                role = (int)u.Role,
            })
            .ToListAsync();

        return Ok(users);
    }

    /// <summary>قائمة الأقسام لإنشاء محادثة قسم</summary>
    [HttpGet("available-departments")]
    public async Task<IActionResult> GetAvailableDepartments()
    {
        var userId = GetUserId();
        var user = await _uow.Users.GetByIdAsync(userId);
        if (user?.CompanyId == null) return Ok(Array.Empty<object>());

        var departments = await _uow.Departments.AsQueryable()
            .Where(d => d.CompanyId == user.CompanyId.Value && d.IsActive && !d.IsDeleted)
            .OrderBy(d => d.SortOrder)
            .Select(d => new
            {
                id = d.Id,
                nameAr = d.NameAr,
                name = d.Name,
                memberCount = d.UserDepartments.Count(ud => !ud.IsDeleted),
            })
            .ToListAsync();

        return Ok(departments);
    }

    /// <summary>كتم/إلغاء كتم إشعارات غرفة</summary>
    /// <summary>تحديث حالة القراءة عبر REST</summary>
    [HttpPut("rooms/{roomId}/mark-read")]
    public async Task<IActionResult> MarkAsRead(Guid roomId)
    {
        var userId = GetUserId();
        var member = await _uow.ChatRoomMembers.FirstOrDefaultAsync(m =>
            m.ChatRoomId == roomId && m.UserId == userId && !m.IsDeleted);
        if (member == null) return NotFound();

        member.LastReadAt = DateTime.UtcNow;
        _uow.ChatRoomMembers.Update(member);
        await _uow.SaveChangesAsync();
        return Ok();
    }

    /// <summary>إضافة/تبديل تفاعل (Reaction) على رسالة</summary>
    [HttpPost("messages/{messageId}/reactions")]
    public async Task<IActionResult> ToggleReaction(Guid messageId, [FromBody] ReactionDto dto)
    {
        var userId = GetUserId();

        // هل يوجد reaction مسبق بنفس الإيموجي؟
        var existing = await _uow.ChatReactions.FirstOrDefaultAsync(r =>
            r.ChatMessageId == messageId && r.UserId == userId && r.Emoji == dto.Emoji && !r.IsDeleted);

        if (existing != null)
        {
            // إزالة
            existing.IsDeleted = true;
            existing.DeletedAt = DateTime.UtcNow;
            _uow.ChatReactions.Update(existing);
        }
        else
        {
            // إضافة
            await _uow.ChatReactions.AddAsync(new ChatReaction
            {
                ChatMessageId = messageId,
                UserId = userId,
                Emoji = dto.Emoji,
            });
        }

        await _uow.SaveChangesAsync();

        // جلب كل reactions للرسالة
        var reactions = await _uow.ChatReactions.AsQueryable()
            .Where(r => r.ChatMessageId == messageId && !r.IsDeleted)
            .Include(r => r.User)
            .Select(r => new { emoji = r.Emoji, userId = r.UserId, userName = r.User.FullName })
            .ToListAsync();

        // بث عبر SignalR
        var msg = await _uow.ChatMessages.GetByIdAsync(messageId);
        if (msg != null)
        {
            await _chatHub.Clients.Group($"chat_{msg.ChatRoomId}").SendAsync("ReactionUpdated", new
            {
                messageId = messageId.ToString(),
                roomId = msg.ChatRoomId.ToString(),
                reactions = reactions,
            });
        }

        return Ok(reactions);
    }

    /// <summary>جلب reactions لرسالة</summary>
    [HttpGet("messages/{messageId}/reactions")]
    public async Task<IActionResult> GetReactions(Guid messageId)
    {
        var reactions = await _uow.ChatReactions.AsQueryable()
            .Where(r => r.ChatMessageId == messageId && !r.IsDeleted)
            .Include(r => r.User)
            .Select(r => new { emoji = r.Emoji, userId = r.UserId, userName = r.User.FullName })
            .ToListAsync();

        return Ok(reactions);
    }

    /// <summary>تثبيت/إلغاء تثبيت محادثة</summary>
    /// <summary>مغادرة المجموعة</summary>
    [HttpPost("rooms/{roomId}/leave")]
    public async Task<IActionResult> LeaveRoom(Guid roomId)
    {
        var userId = GetUserId();
        var member = await _uow.ChatRoomMembers.FirstOrDefaultAsync(m =>
            m.ChatRoomId == roomId && m.UserId == userId && !m.IsDeleted);
        if (member == null) return NotFound();

        member.IsDeleted = true;
        member.DeletedAt = DateTime.UtcNow;
        _uow.ChatRoomMembers.Update(member);
        await _uow.SaveChangesAsync();
        return Ok();
    }

    /// <summary>تعديل اسم المجموعة</summary>
    [HttpPut("rooms/{roomId}/name")]
    public async Task<IActionResult> UpdateRoomName(Guid roomId, [FromBody] UpdateRoomNameDto dto)
    {
        var userId = GetUserId();

        // التحقق من أنه مدير الغرفة
        var isAdmin = await _uow.ChatRoomMembers.AnyAsync(m =>
            m.ChatRoomId == roomId && m.UserId == userId && m.IsAdmin && !m.IsDeleted);
        if (!isAdmin) return StatusCode(403, new { error = "فقط مدير المجموعة يمكنه تعديل الاسم" });

        var room = await _uow.ChatRooms.GetByIdAsync(roomId);
        if (room == null) return NotFound();

        room.Name = dto.Name;
        room.UpdatedAt = DateTime.UtcNow;
        _uow.ChatRooms.Update(room);
        await _uow.SaveChangesAsync();

        return Ok(new { success = true, name = room.Name });
    }

    [HttpPut("rooms/{roomId}/pin")]
    public async Task<IActionResult> TogglePin(Guid roomId, [FromBody] TogglePinDto dto)
    {
        var userId = GetUserId();
        var member = await _uow.ChatRoomMembers.FirstOrDefaultAsync(m =>
            m.ChatRoomId == roomId && m.UserId == userId && !m.IsDeleted);
        if (member == null) return NotFound();

        member.IsPinned = dto.Pinned;
        _uow.ChatRoomMembers.Update(member);
        await _uow.SaveChangesAsync();
        return Ok();
    }

    [HttpPut("rooms/{roomId}/mute")]
    public async Task<IActionResult> ToggleMute(Guid roomId, [FromBody] ToggleMuteDto dto)
    {
        var userId = GetUserId();

        var member = await _uow.ChatRoomMembers.FirstOrDefaultAsync(m =>
            m.ChatRoomId == roomId && m.UserId == userId && !m.IsDeleted);
        if (member == null) return NotFound();

        member.IsMuted = dto.Muted;
        _uow.ChatRoomMembers.Update(member);
        await _uow.SaveChangesAsync();

        return Ok();
    }

    /// <summary>إضافة أعضاء لمجموعة</summary>
    [HttpPost("rooms/{roomId}/members")]
    public async Task<IActionResult> AddMembers(Guid roomId, [FromBody] AddMembersDto dto)
    {
        var userId = GetUserId();

        // التحقق من أنه مدير الغرفة
        var isAdmin = await _uow.ChatRoomMembers.AnyAsync(m =>
            m.ChatRoomId == roomId && m.UserId == userId && m.IsAdmin && !m.IsDeleted);
        if (!isAdmin) return Forbid();

        foreach (var memberId in dto.UserIds)
        {
            var exists = await _uow.ChatRoomMembers.AnyAsync(m =>
                m.ChatRoomId == roomId && m.UserId == memberId && !m.IsDeleted);
            if (exists) continue;

            await _uow.ChatRoomMembers.AddAsync(new ChatRoomMember
            {
                ChatRoomId = roomId,
                UserId = memberId,
            });
        }

        await _uow.SaveChangesAsync();

        // إعلام الأعضاء الجدد عبر SignalR
        foreach (var memberId in dto.UserIds)
        {
            await _chatHub.Clients.User(memberId.ToString()).SendAsync("AddedToRoom", roomId.ToString());
        }

        return Ok();
    }

    /// <summary>إزالة عضو من مجموعة</summary>
    [HttpDelete("rooms/{roomId}/members/{memberId}")]
    public async Task<IActionResult> RemoveMember(Guid roomId, Guid memberId)
    {
        var userId = GetUserId();

        var isAdmin = await _uow.ChatRoomMembers.AnyAsync(m =>
            m.ChatRoomId == roomId && m.UserId == userId && m.IsAdmin && !m.IsDeleted);
        if (!isAdmin) return Forbid();

        var member = await _uow.ChatRoomMembers.FirstOrDefaultAsync(m =>
            m.ChatRoomId == roomId && m.UserId == memberId && !m.IsDeleted);
        if (member == null) return NotFound();

        member.IsDeleted = true;
        member.DeletedAt = DateTime.UtcNow;
        _uow.ChatRoomMembers.Update(member);
        await _uow.SaveChangesAsync();

        await _chatHub.Clients.User(memberId.ToString()).SendAsync("RemovedFromRoom", roomId.ToString());

        return Ok();
    }

    // ═══ DTOs ═══

    private Guid GetUserId()
    {
        var claim = User.FindFirst(ClaimTypes.NameIdentifier)?.Value
            ?? User.FindFirst("sub")?.Value;
        return Guid.Parse(claim!);
    }
}

// ═══ Request DTOs ═══

public class CreateRoomDto
{
    public ChatRoomType Type { get; set; }
    public string? Name { get; set; }
    public int? DepartmentId { get; set; }
    public List<Guid>? MemberIds { get; set; }
}

public class ReactionDto
{
    public string Emoji { get; set; } = string.Empty;
}

public class UpdateRoomNameDto
{
    public string Name { get; set; } = string.Empty;
}

public class TogglePinDto
{
    public bool Pinned { get; set; }
}

public class ToggleMuteDto
{
    public bool Muted { get; set; }
}

public class AddMembersDto
{
    public List<Guid> UserIds { get; set; } = new();
}

public class SendMessageDto
{
    public string? Content { get; set; }
    public int MessageType { get; set; } = 0;
    public Guid? ReplyToMessageId { get; set; }
    public List<Guid>? MentionUserIds { get; set; }
}
