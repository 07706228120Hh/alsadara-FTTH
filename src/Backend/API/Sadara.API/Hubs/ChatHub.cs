using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.SignalR;
using Microsoft.EntityFrameworkCore;
using Sadara.Domain.Entities;
using Sadara.Domain.Interfaces;

namespace Sadara.API.Hubs;

/// <summary>
/// SignalR Hub — نظام المحادثة الفوري
/// يدير الاتصالات، إرسال/استقبال الرسائل، حالة الكتابة، وإيصالات القراءة
/// </summary>
[Authorize]
public class ChatHub : Hub
{
    private readonly IServiceScopeFactory _scopeFactory;
    private readonly ILogger<ChatHub> _logger;

    // تتبع المستخدمين المتصلين: UserId → Set<ConnectionId>
    private static readonly Dictionary<string, HashSet<string>> _onlineUsers = new();
    private static readonly object _lock = new();

    public ChatHub(IServiceScopeFactory scopeFactory, ILogger<ChatHub> logger)
    {
        _scopeFactory = scopeFactory;
        _logger = logger;
    }

    /// <summary>عند الاتصال — انضمام لغرف المستخدم + إعلان Online</summary>
    public override async Task OnConnectedAsync()
    {
        var userId = GetUserId();
        if (userId == null) { Context.Abort(); return; }

        // تسجيل الاتصال
        lock (_lock)
        {
            if (!_onlineUsers.ContainsKey(userId))
                _onlineUsers[userId] = new HashSet<string>();
            _onlineUsers[userId].Add(Context.ConnectionId);
        }

        // انضمام لجميع غرف المستخدم
        using var scope = _scopeFactory.CreateScope();
        var uow = scope.ServiceProvider.GetRequiredService<IUnitOfWork>();
        var userGuid = Guid.Parse(userId);

        var memberships = await uow.ChatRoomMembers.AsQueryable()
            .Where(m => m.UserId == userGuid && !m.IsDeleted)
            .Select(m => m.ChatRoomId.ToString())
            .ToListAsync();

        foreach (var roomId in memberships)
        {
            await Groups.AddToGroupAsync(Context.ConnectionId, $"chat_{roomId}");
        }

        // إعلام الآخرين بأنه أونلاين
        await Clients.Others.SendAsync("UserOnline", userId);

        _logger.LogInformation("Chat: User {UserId} connected ({ConnId})", userId, Context.ConnectionId);
        await base.OnConnectedAsync();
    }

    /// <summary>عند قطع الاتصال</summary>
    public override async Task OnDisconnectedAsync(Exception? exception)
    {
        var userId = GetUserId();
        if (userId != null)
        {
            bool isLastConnection = false;
            lock (_lock)
            {
                if (_onlineUsers.ContainsKey(userId))
                {
                    _onlineUsers[userId].Remove(Context.ConnectionId);
                    if (_onlineUsers[userId].Count == 0)
                    {
                        _onlineUsers.Remove(userId);
                        isLastConnection = true;
                    }
                }
            }

            if (isLastConnection)
            {
                await Clients.Others.SendAsync("UserOffline", userId);
            }
        }

        await base.OnDisconnectedAsync(exception);
    }

    /// <summary>إرسال رسالة جديدة</summary>
    public async Task SendMessage(string roomId, string content, int messageType, string? replyToMessageId, List<string>? mentionUserIds)
    {
        var userId = GetUserId();
        if (userId == null) return;

        using var scope = _scopeFactory.CreateScope();
        var uow = scope.ServiceProvider.GetRequiredService<IUnitOfWork>();
        var fcmService = scope.ServiceProvider.GetRequiredService<Sadara.Application.Interfaces.IFcmNotificationService>();

        var userGuid = Guid.Parse(userId);
        var roomGuid = Guid.Parse(roomId);

        // التحقق من العضوية
        var isMember = await uow.ChatRoomMembers.AnyAsync(m =>
            m.ChatRoomId == roomGuid && m.UserId == userGuid && !m.IsDeleted);
        if (!isMember) return;

        // جلب بيانات المرسل
        var sender = await uow.Users.GetByIdAsync(userGuid);
        if (sender == null) return;

        // إنشاء الرسالة
        var message = new ChatMessage
        {
            Id = Guid.NewGuid(),
            ChatRoomId = roomGuid,
            SenderId = userGuid,
            MessageType = (ChatMessageType)messageType,
            Content = content,
            ReplyToMessageId = string.IsNullOrEmpty(replyToMessageId) ? null : Guid.Parse(replyToMessageId),
        };

        await uow.ChatMessages.AddAsync(message);

        // تحديث آخر رسالة في الغرفة
        var room = await uow.ChatRooms.GetByIdAsync(roomGuid);
        if (room != null)
        {
            room.LastMessageAt = DateTime.UtcNow;
            room.LastMessageSenderName = sender.FullName;
            room.LastMessagePreview = messageType == 0
                ? (content?.Length > 100 ? content[..100] + "..." : content)
                : GetMessageTypeLabel((ChatMessageType)messageType);
            uow.ChatRooms.Update(room);
        }

        // حفظ التاقات
        if (mentionUserIds?.Any() == true)
        {
            foreach (var mentionId in mentionUserIds)
            {
                await uow.ChatMentions.AddAsync(new ChatMention
                {
                    ChatMessageId = message.Id,
                    MentionedUserId = Guid.Parse(mentionId),
                });
            }
        }

        await uow.SaveChangesAsync();

        // بث الرسالة لجميع أعضاء الغرفة
        var messageData = new
        {
            id = message.Id.ToString(),
            roomId = roomId,
            senderId = userId,
            senderName = sender.FullName,
            senderAvatar = sender.ProfileImageUrl,
            messageType = messageType,
            content = content,
            replyToMessageId = replyToMessageId,
            isForwarded = false,
            createdAt = message.CreatedAt.ToString("o"),
            mentions = mentionUserIds ?? new List<string>(),
        };

        await Clients.Group($"chat_{roomId}").SendAsync("ReceiveMessage", messageData);

        // إرسال FCM للغائبين (غير المتصلين عبر SignalR)
        _ = Task.Run(async () =>
        {
            try
            {
                using var bgScope = _scopeFactory.CreateScope();
                var bgUow = bgScope.ServiceProvider.GetRequiredService<IUnitOfWork>();
                var bgFcm = bgScope.ServiceProvider.GetRequiredService<Sadara.Application.Interfaces.IFcmNotificationService>();

                var memberIds = await bgUow.ChatRoomMembers.AsQueryable()
                    .Where(m => m.ChatRoomId == roomGuid && m.UserId != userGuid && !m.IsMuted && !m.IsDeleted)
                    .Select(m => m.UserId)
                    .ToListAsync();

                // استبعاد المتصلين حالياً
                List<Guid> offlineMembers;
                lock (_lock)
                {
                    offlineMembers = memberIds
                        .Where(id => !_onlineUsers.ContainsKey(id.ToString()))
                        .ToList();
                }

                if (offlineMembers.Any())
                {
                    var roomName = room?.Name ?? sender.FullName;
                    var preview = messageType == 0 ? content ?? "" : GetMessageTypeLabel((ChatMessageType)messageType);

                    await bgFcm.SendToUsersAsync(
                        offlineMembers,
                        $"رسالة جديدة من {sender.FullName}",
                        preview.Length > 200 ? preview[..200] : preview,
                        new Dictionary<string, string>
                        {
                            ["type"] = "chat_message",
                            ["roomId"] = roomId,
                            ["messageId"] = message.Id.ToString(),
                        });
                }

                // إشعار خاص للتاقات
                if (mentionUserIds?.Any() == true)
                {
                    var mentionGuids = mentionUserIds.Select(Guid.Parse).ToList();
                    await bgFcm.SendToUsersAsync(
                        mentionGuids,
                        $"📌 {sender.FullName} ذكرك في المحادثة",
                        content?.Length > 200 ? content[..200] : content ?? "",
                        new Dictionary<string, string>
                        {
                            ["type"] = "chat_mention",
                            ["roomId"] = roomId,
                            ["messageId"] = message.Id.ToString(),
                        });
                }
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Chat FCM notification failed for room {RoomId}", roomId);
            }
        });
    }

    /// <summary>تحديث حالة القراءة</summary>
    public async Task MarkAsRead(string roomId)
    {
        var userId = GetUserId();
        if (userId == null) return;

        using var scope = _scopeFactory.CreateScope();
        var uow = scope.ServiceProvider.GetRequiredService<IUnitOfWork>();

        var userGuid = Guid.Parse(userId);
        var roomGuid = Guid.Parse(roomId);

        var member = await uow.ChatRoomMembers.FirstOrDefaultAsync(m =>
            m.ChatRoomId == roomGuid && m.UserId == userGuid && !m.IsDeleted);

        if (member != null)
        {
            member.LastReadAt = DateTime.UtcNow;
            uow.ChatRoomMembers.Update(member);
            await uow.SaveChangesAsync();
        }

        await Clients.Group($"chat_{roomId}").SendAsync("MessageRead", roomId, userId, DateTime.UtcNow.ToString("o"));
    }

    /// <summary>حالة الكتابة</summary>
    public async Task StartTyping(string roomId)
    {
        var userId = GetUserId();
        if (userId == null) return;

        using var scope = _scopeFactory.CreateScope();
        var uow = scope.ServiceProvider.GetRequiredService<IUnitOfWork>();
        var sender = await uow.Users.GetByIdAsync(Guid.Parse(userId));

        await Clients.OthersInGroup($"chat_{roomId}").SendAsync("UserTyping", roomId, userId, sender?.FullName ?? "");
    }

    /// <summary>توقف عن الكتابة</summary>
    public async Task StopTyping(string roomId)
    {
        var userId = GetUserId();
        await Clients.OthersInGroup($"chat_{roomId}").SendAsync("UserStoppedTyping", roomId, userId);
    }

    /// <summary>التحقق من المستخدمين المتصلين</summary>
    public Task<List<string>> GetOnlineUsers()
    {
        lock (_lock)
        {
            return Task.FromResult(_onlineUsers.Keys.ToList());
        }
    }

    /// <summary>انضمام لغرفة جديدة (يُستدعى عند إنشاء/إضافة لغرفة)</summary>
    public async Task JoinRoom(string roomId)
    {
        await Groups.AddToGroupAsync(Context.ConnectionId, $"chat_{roomId}");
    }

    // ═══ Helpers ═══

    private string? GetUserId()
    {
        return Context.User?.FindFirst(ClaimTypes.NameIdentifier)?.Value
            ?? Context.User?.FindFirst("sub")?.Value;
    }

    private static string GetMessageTypeLabel(ChatMessageType type) => type switch
    {
        ChatMessageType.Image => "📷 صورة",
        ChatMessageType.Audio => "🎤 رسالة صوتية",
        ChatMessageType.Location => "📍 موقع",
        ChatMessageType.Contact => "👤 جهة اتصال",
        ChatMessageType.File => "📎 ملف",
        _ => "",
    };
}
