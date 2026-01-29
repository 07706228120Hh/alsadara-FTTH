using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Sadara.Domain.Entities;
using Sadara.Domain.Enums;
using Sadara.Domain.Interfaces;
using System.Text.Json;

namespace Sadara.API.Controllers;

/// <summary>
/// إدارة طلبات الخدمة - نظام العمليات والموافقات
/// </summary>
[ApiController]
[Route("api/[controller]")]
[Authorize]
public class ServiceRequestsController : ControllerBase
{
    private readonly IUnitOfWork _unitOfWork;
    private readonly ILogger<ServiceRequestsController> _logger;

    public ServiceRequestsController(IUnitOfWork unitOfWork, ILogger<ServiceRequestsController> logger)
    {
        _unitOfWork = unitOfWork;
        _logger = logger;
    }

    #region Service Requests CRUD

    /// <summary>
    /// جميع الطلبات - حسب الصلاحية
    /// </summary>
    [HttpGet]
    public async Task<IActionResult> GetAll(
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 20,
        [FromQuery] string? status = null,
        [FromQuery] int? serviceId = null,
        [FromQuery] Guid? companyId = null)
    {
        var query = _unitOfWork.ServiceRequests.AsQueryable();

        if (!string.IsNullOrEmpty(status) && Enum.TryParse<ServiceRequestStatus>(status, true, out var statusEnum))
            query = query.Where(r => r.Status == statusEnum);

        if (serviceId.HasValue)
            query = query.Where(r => r.ServiceId == serviceId);

        if (companyId.HasValue)
            query = query.Where(r => r.CompanyId == companyId);

        var total = await query.CountAsync();
        var requests = await query
            .Include(r => r.Citizen)
            .Include(r => r.Service)
            .Include(r => r.Company)
            .Include(r => r.AssignedTo)
            .OrderByDescending(r => r.CreatedAt)
            .Skip((page - 1) * pageSize)
            .Take(pageSize)
            .Select(r => new ServiceRequestResponse
            {
                Id = r.Id,
                RequestNumber = r.RequestNumber,
                ServiceId = r.ServiceId,
                ServiceName = r.Service != null ? r.Service.Name : null,
                ServiceNameAr = r.Service != null ? r.Service.NameAr : null,
                OperationTypeId = r.OperationTypeId,
                CitizenId = r.CitizenId,
                CitizenName = r.Citizen != null ? r.Citizen.FullName : null,
                CitizenPhone = r.Citizen != null ? r.Citizen.PhoneNumber : null,
                CompanyId = r.CompanyId,
                CompanyName = r.Company != null ? r.Company.Name : null,
                Details = r.Details,
                Status = r.Status.ToString(),
                StatusNote = r.StatusNote,
                Priority = r.Priority,
                AssignedToId = r.AssignedToId,
                AssignedToName = r.AssignedTo != null ? r.AssignedTo.FullName : null,
                CreatedAt = r.CreatedAt,
                UpdatedAt = r.UpdatedAt,
                CompletedAt = r.CompletedAt
            })
            .ToListAsync();

        return Ok(new { success = true, data = requests, total, page, pageSize });
    }

    /// <summary>
    /// طلب بالمعرف
    /// </summary>
    [HttpGet("{id:guid}")]
    public async Task<IActionResult> GetById(Guid id)
    {
        var request = await _unitOfWork.ServiceRequests.AsQueryable()
            .Include(r => r.Citizen)
            .Include(r => r.Service)
            .Include(r => r.OperationType)
            .Include(r => r.Company)
            .Include(r => r.AssignedTo)
            .Include(r => r.Comments)
                .ThenInclude(c => c.User)
            .Include(r => r.Attachments)
            .Include(r => r.StatusHistory)
                .ThenInclude(h => h.ChangedBy)
            .FirstOrDefaultAsync(r => r.Id == id);

        if (request == null)
            return NotFound(new { success = false, message = "الطلب غير موجود" });

        return Ok(new { success = true, data = MapToDetailedResponse(request) });
    }

    /// <summary>
    /// طلب برقم الطلب
    /// </summary>
    [HttpGet("by-number/{requestNumber}")]
    public async Task<IActionResult> GetByNumber(string requestNumber)
    {
        var request = await _unitOfWork.ServiceRequests.AsQueryable()
            .Include(r => r.Citizen)
            .Include(r => r.Service)
            .FirstOrDefaultAsync(r => r.RequestNumber == requestNumber);

        if (request == null)
            return NotFound(new { success = false, message = "الطلب غير موجود" });

        return Ok(new { success = true, data = MapToResponse(request) });
    }

    /// <summary>
    /// إنشاء طلب جديد
    /// </summary>
    [HttpPost]
    public async Task<IActionResult> Create([FromBody] CreateServiceRequestDto dto)
    {
        // التحقق من الخدمة
        var service = await _unitOfWork.Services.GetByIdAsync(dto.ServiceId);
        if (service == null || !service.IsActive)
            return BadRequest(new { success = false, message = "الخدمة غير متوفرة" });

        // التحقق من نوع العملية
        var opType = await _unitOfWork.OperationTypes.GetByIdAsync(dto.OperationTypeId);
        if (opType == null)
            return BadRequest(new { success = false, message = "نوع العملية غير صالح" });

        var request = new ServiceRequest
        {
            Id = Guid.NewGuid(),
            RequestNumber = GenerateRequestNumber(),
            ServiceId = dto.ServiceId,
            OperationTypeId = dto.OperationTypeId,
            CitizenId = dto.CitizenId,
            CompanyId = dto.CompanyId,
            Details = dto.Details != null ? JsonSerializer.Serialize(dto.Details) : null,
            Address = dto.Address,
            City = dto.City,
            Area = dto.Area,
            ContactPhone = dto.ContactPhone,
            Status = ServiceRequestStatus.Pending,
            Priority = dto.Priority,
            RequestedAt = DateTime.UtcNow,
            CreatedAt = DateTime.UtcNow
        };

        await _unitOfWork.ServiceRequests.AddAsync(request);

        // إضافة سجل الحالة
        var statusHistory = new ServiceRequestStatusHistory
        {
            ServiceRequestId = request.Id,
            FromStatus = ServiceRequestStatus.Pending,
            ToStatus = ServiceRequestStatus.Pending,
            Note = "تم إنشاء الطلب",
            ChangedById = dto.CitizenId,
            CreatedAt = DateTime.UtcNow
        };
        await _unitOfWork.ServiceRequestStatusHistories.AddAsync(statusHistory);

        await _unitOfWork.SaveChangesAsync();

        _logger.LogInformation("تم إنشاء طلب جديد: {RequestNumber}", request.RequestNumber);

        return CreatedAtAction(nameof(GetById), new { id = request.Id }, new
        {
            success = true,
            data = new
            {
                request.Id,
                request.RequestNumber,
                Status = request.Status.ToString(),
                request.CreatedAt
            }
        });
    }

    /// <summary>
    /// تحديث حالة الطلب
    /// </summary>
    [HttpPatch("{id:guid}/status")]
    public async Task<IActionResult> UpdateStatus(Guid id, [FromBody] UpdateStatusDto dto)
    {
        var request = await _unitOfWork.ServiceRequests.GetByIdAsync(id);
        if (request == null)
            return NotFound(new { success = false, message = "الطلب غير موجود" });

        if (!Enum.TryParse<ServiceRequestStatus>(dto.Status, true, out var newStatus))
            return BadRequest(new { success = false, message = "الحالة غير صالحة" });

        var oldStatus = request.Status;
        request.Status = newStatus;
        request.StatusNote = dto.Note;
        request.UpdatedAt = DateTime.UtcNow;

        // تحديث التواريخ حسب الحالة
        switch (newStatus)
        {
            case ServiceRequestStatus.Reviewing:
                request.ReviewedAt = DateTime.UtcNow;
                break;
            case ServiceRequestStatus.InProgress:
                request.StartedAt = DateTime.UtcNow;
                break;
            case ServiceRequestStatus.Completed:
                request.CompletedAt = DateTime.UtcNow;
                break;
            case ServiceRequestStatus.Cancelled:
                request.CancelledAt = DateTime.UtcNow;
                break;
        }

        // سجل التغيير
        var history = new ServiceRequestStatusHistory
        {
            ServiceRequestId = id,
            FromStatus = oldStatus,
            ToStatus = newStatus,
            Note = dto.Note,
            ChangedById = GetCurrentUserId(),
            CreatedAt = DateTime.UtcNow
        };

        _unitOfWork.ServiceRequests.Update(request);
        await _unitOfWork.ServiceRequestStatusHistories.AddAsync(history);
        await _unitOfWork.SaveChangesAsync();

        _logger.LogInformation("تم تحديث حالة الطلب {Id} من {OldStatus} إلى {NewStatus}", id, oldStatus, newStatus);

        return Ok(new { success = true, message = "تم تحديث الحالة بنجاح" });
    }

    /// <summary>
    /// تعيين موظف للطلب
    /// </summary>
    [HttpPatch("{id:guid}/assign")]
    public async Task<IActionResult> AssignToEmployee(Guid id, [FromBody] AssignRequestDto dto)
    {
        var request = await _unitOfWork.ServiceRequests.GetByIdAsync(id);
        if (request == null)
            return NotFound(new { success = false, message = "الطلب غير موجود" });

        var employee = await _unitOfWork.Users.GetByIdAsync(dto.EmployeeId);
        if (employee == null)
            return BadRequest(new { success = false, message = "الموظف غير موجود" });

        var oldStatus = request.Status;
        request.AssignedToId = dto.EmployeeId;
        request.AssignedAt = DateTime.UtcNow;
        request.Status = ServiceRequestStatus.Assigned;
        request.UpdatedAt = DateTime.UtcNow;

        // سجل التغيير
        var history = new ServiceRequestStatusHistory
        {
            ServiceRequestId = id,
            FromStatus = oldStatus,
            ToStatus = ServiceRequestStatus.Assigned,
            Note = $"تم تعيين الطلب للموظف: {employee.FullName}",
            ChangedById = GetCurrentUserId(),
            CreatedAt = DateTime.UtcNow
        };

        _unitOfWork.ServiceRequests.Update(request);
        await _unitOfWork.ServiceRequestStatusHistories.AddAsync(history);
        await _unitOfWork.SaveChangesAsync();

        return Ok(new { success = true, message = "تم تعيين الموظف بنجاح" });
    }

    #endregion

    #region Comments

    /// <summary>
    /// إضافة تعليق
    /// </summary>
    [HttpPost("{id:guid}/comments")]
    public async Task<IActionResult> AddComment(Guid id, [FromBody] AddCommentDto dto)
    {
        var request = await _unitOfWork.ServiceRequests.GetByIdAsync(id);
        if (request == null)
            return NotFound(new { success = false, message = "الطلب غير موجود" });

        var comment = new ServiceRequestComment
        {
            ServiceRequestId = id,
            UserId = GetCurrentUserId(),
            Content = dto.Content,
            IsVisibleToCitizen = dto.IsVisibleToCitizen,
            IsSystemGenerated = false,
            CreatedAt = DateTime.UtcNow
        };

        await _unitOfWork.ServiceRequestComments.AddAsync(comment);
        await _unitOfWork.SaveChangesAsync();

        return Ok(new { success = true, message = "تم إضافة التعليق" });
    }

    /// <summary>
    /// تعليقات الطلب
    /// </summary>
    [HttpGet("{id:guid}/comments")]
    public async Task<IActionResult> GetComments(Guid id)
    {
        var comments = await _unitOfWork.ServiceRequestComments.AsQueryable()
            .Where(c => c.ServiceRequestId == id)
            .Include(c => c.User)
            .OrderBy(c => c.CreatedAt)
            .Select(c => new
            {
                c.Id,
                c.Content,
                c.IsVisibleToCitizen,
                c.IsSystemGenerated,
                c.CreatedAt,
                UserName = c.User != null ? c.User.FullName : "غير معروف"
            })
            .ToListAsync();

        return Ok(new { success = true, data = comments });
    }

    #endregion

    #region Attachments

    /// <summary>
    /// إضافة مرفق
    /// </summary>
    [HttpPost("{id:guid}/attachments")]
    [Consumes("multipart/form-data")]
    public async Task<IActionResult> AddAttachment(Guid id, IFormFile file, [FromForm] string? description = null)
    {
        var request = await _unitOfWork.ServiceRequests.GetByIdAsync(id);
        if (request == null)
            return NotFound(new { success = false, message = "الطلب غير موجود" });

        // حفظ الملف
        var uploadsPath = Path.Combine(Directory.GetCurrentDirectory(), "uploads", "attachments");
        Directory.CreateDirectory(uploadsPath);

        var fileName = $"{id}_{DateTime.UtcNow:yyyyMMddHHmmss}_{file.FileName}";
        var filePath = Path.Combine(uploadsPath, fileName);

        using (var stream = new FileStream(filePath, FileMode.Create))
        {
            await file.CopyToAsync(stream);
        }

        var attachment = new ServiceRequestAttachment
        {
            ServiceRequestId = id,
            UploadedById = GetCurrentUserId(),
            FileName = file.FileName,
            FileUrl = $"/uploads/attachments/{fileName}",
            FileType = file.ContentType,
            FileSizeBytes = file.Length,
            Description = description,
            CreatedAt = DateTime.UtcNow
        };

        await _unitOfWork.ServiceRequestAttachments.AddAsync(attachment);
        await _unitOfWork.SaveChangesAsync();

        return Ok(new { success = true, data = new { attachment.Id, attachment.FileUrl } });
    }

    /// <summary>
    /// مرفقات الطلب
    /// </summary>
    [HttpGet("{id:guid}/attachments")]
    public async Task<IActionResult> GetAttachments(Guid id)
    {
        var attachments = await _unitOfWork.ServiceRequestAttachments.AsQueryable()
            .Where(a => a.ServiceRequestId == id)
            .Include(a => a.UploadedBy)
            .Select(a => new
            {
                a.Id,
                a.FileName,
                a.FileUrl,
                a.FileType,
                a.FileSizeBytes,
                a.Description,
                a.CreatedAt,
                UploadedByName = a.UploadedBy != null ? a.UploadedBy.FullName : "غير معروف"
            })
            .ToListAsync();

        return Ok(new { success = true, data = attachments });
    }

    #endregion

    #region Statistics

    /// <summary>
    /// إحصائيات الطلبات
    /// </summary>
    [HttpGet("statistics")]
    public async Task<IActionResult> GetStatistics([FromQuery] Guid? companyId = null)
    {
        var query = _unitOfWork.ServiceRequests.AsQueryable();
        if (companyId.HasValue)
            query = query.Where(r => r.CompanyId == companyId);

        var stats = new
        {
            Total = await query.CountAsync(),
            Pending = await query.CountAsync(r => r.Status == ServiceRequestStatus.Pending),
            Reviewing = await query.CountAsync(r => r.Status == ServiceRequestStatus.Reviewing),
            InProgress = await query.CountAsync(r => r.Status == ServiceRequestStatus.InProgress),
            Completed = await query.CountAsync(r => r.Status == ServiceRequestStatus.Completed),
            Cancelled = await query.CountAsync(r => r.Status == ServiceRequestStatus.Cancelled),
            Rejected = await query.CountAsync(r => r.Status == ServiceRequestStatus.Rejected),
            TodayCreated = await query.CountAsync(r => r.CreatedAt >= DateTime.UtcNow.Date),
            TodayCompleted = await query.CountAsync(r => r.CompletedAt >= DateTime.UtcNow.Date)
        };

        return Ok(new { success = true, data = stats });
    }

    /// <summary>
    /// الطلبات المعينة لموظف
    /// </summary>
    [HttpGet("my-assigned")]
    public async Task<IActionResult> GetMyAssigned([FromQuery] int page = 1, [FromQuery] int pageSize = 20)
    {
        var userId = GetCurrentUserId();
        var query = _unitOfWork.ServiceRequests.AsQueryable()
            .Where(r => r.AssignedToId == userId && 
                        r.Status != ServiceRequestStatus.Completed && 
                        r.Status != ServiceRequestStatus.Cancelled);

        var total = await query.CountAsync();
        var requests = await query
            .Include(r => r.Service)
            .Include(r => r.Citizen)
            .OrderByDescending(r => r.Priority)
            .ThenBy(r => r.CreatedAt)
            .Skip((page - 1) * pageSize)
            .Take(pageSize)
            .ToListAsync();

        return Ok(new { success = true, data = requests.Select(MapToResponse), total, page, pageSize });
    }

    #endregion

    #region Services & OperationTypes

    /// <summary>
    /// الخدمات المتاحة
    /// </summary>
    [HttpGet("services")]
    [AllowAnonymous]
    public async Task<IActionResult> GetServices()
    {
        var services = await _unitOfWork.Services.AsQueryable()
            .Where(s => s.IsActive)
            .Include(s => s.Operations)
                .ThenInclude(o => o.OperationType)
            .Select(s => new
            {
                s.Id,
                s.Name,
                s.NameAr,
                s.Description,
                s.Icon,
                s.Color,
                OperationTypes = s.Operations.Where(o => o.IsActive && o.OperationType.IsActive).Select(o => new
                {
                    o.OperationType.Id,
                    o.OperationType.Name,
                    o.OperationType.NameAr,
                    o.OperationType.Icon,
                    o.OperationType.RequiresApproval,
                    o.OperationType.EstimatedDays,
                    o.BasePrice
                })
            })
            .ToListAsync();

        return Ok(new { success = true, data = services });
    }

    #endregion

    #region Helper Methods

    private Guid GetCurrentUserId()
    {
        var claim = User.FindFirst("sub") ?? User.FindFirst(System.Security.Claims.ClaimTypes.NameIdentifier);
        return claim != null ? Guid.Parse(claim.Value) : Guid.Empty;
    }

    private static string GenerateRequestNumber()
    {
        return $"SR-{DateTime.UtcNow:yyyyMMdd}-{Guid.NewGuid().ToString()[..6].ToUpper()}";
    }

    private static ServiceRequestResponse MapToResponse(ServiceRequest r)
    {
        return new ServiceRequestResponse
        {
            Id = r.Id,
            RequestNumber = r.RequestNumber,
            ServiceId = r.ServiceId,
            ServiceName = r.Service?.Name,
            ServiceNameAr = r.Service?.NameAr,
            OperationTypeId = r.OperationTypeId,
            CitizenId = r.CitizenId,
            CitizenName = r.Citizen?.FullName,
            CompanyId = r.CompanyId,
            CompanyName = r.Company?.Name,
            Status = r.Status.ToString(),
            Priority = r.Priority,
            CreatedAt = r.CreatedAt,
            UpdatedAt = r.UpdatedAt
        };
    }

    private static ServiceRequestDetailResponse MapToDetailedResponse(ServiceRequest r)
    {
        return new ServiceRequestDetailResponse
        {
            Id = r.Id,
            RequestNumber = r.RequestNumber,
            ServiceId = r.ServiceId,
            ServiceName = r.Service?.Name,
            ServiceNameAr = r.Service?.NameAr,
            OperationTypeId = r.OperationTypeId,
            OperationTypeName = r.OperationType?.Name,
            CitizenId = r.CitizenId,
            CitizenName = r.Citizen?.FullName,
            CitizenPhone = r.Citizen?.PhoneNumber,
            CompanyId = r.CompanyId,
            CompanyName = r.Company?.Name,
            Details = r.Details,
            Address = r.Address,
            City = r.City,
            Area = r.Area,
            ContactPhone = r.ContactPhone,
            Status = r.Status.ToString(),
            StatusNote = r.StatusNote,
            Priority = r.Priority,
            EstimatedCost = r.EstimatedCost,
            FinalCost = r.FinalCost,
            AssignedToId = r.AssignedToId,
            AssignedToName = r.AssignedTo?.FullName,
            CreatedAt = r.CreatedAt,
            UpdatedAt = r.UpdatedAt,
            CompletedAt = r.CompletedAt,
            Comments = r.Comments?.Select(c => new CommentResponse
            {
                Id = c.Id,
                Content = c.Content,
                IsVisibleToCitizen = c.IsVisibleToCitizen,
                UserName = c.User?.FullName ?? "غير معروف",
                CreatedAt = c.CreatedAt
            }).ToList() ?? new(),
            Attachments = r.Attachments?.Select(a => new AttachmentResponse
            {
                Id = a.Id,
                FileName = a.FileName,
                FileUrl = a.FileUrl,
                FileType = a.FileType,
                FileSizeBytes = a.FileSizeBytes,
                Description = a.Description,
                CreatedAt = a.CreatedAt
            }).ToList() ?? new(),
            StatusHistory = r.StatusHistory?.OrderBy(h => h.CreatedAt).Select(h => new StatusHistoryResponse
            {
                FromStatus = h.FromStatus.ToString(),
                ToStatus = h.ToStatus.ToString(),
                Note = h.Note,
                ChangedBy = h.ChangedBy?.FullName,
                ChangedAt = h.CreatedAt
            }).ToList() ?? new()
        };
    }

    #endregion
}

#region DTOs

public class ServiceRequestResponse
{
    public Guid Id { get; set; }
    public string RequestNumber { get; set; } = string.Empty;
    public int ServiceId { get; set; }
    public string? ServiceName { get; set; }
    public string? ServiceNameAr { get; set; }
    public int OperationTypeId { get; set; }
    public Guid CitizenId { get; set; }
    public string? CitizenName { get; set; }
    public string? CitizenPhone { get; set; }
    public Guid? CompanyId { get; set; }
    public string? CompanyName { get; set; }
    public string? Details { get; set; }
    public string Status { get; set; } = string.Empty;
    public string? StatusNote { get; set; }
    public int Priority { get; set; }
    public Guid? AssignedToId { get; set; }
    public string? AssignedToName { get; set; }
    public DateTime CreatedAt { get; set; }
    public DateTime? UpdatedAt { get; set; }
    public DateTime? CompletedAt { get; set; }
}

public class ServiceRequestDetailResponse : ServiceRequestResponse
{
    public string? OperationTypeName { get; set; }
    public string? Address { get; set; }
    public string? City { get; set; }
    public string? Area { get; set; }
    public string? ContactPhone { get; set; }
    public decimal? EstimatedCost { get; set; }
    public decimal? FinalCost { get; set; }
    public List<CommentResponse> Comments { get; set; } = new();
    public List<AttachmentResponse> Attachments { get; set; } = new();
    public List<StatusHistoryResponse> StatusHistory { get; set; } = new();
}

public class CommentResponse
{
    public long Id { get; set; }
    public string Content { get; set; } = string.Empty;
    public bool IsVisibleToCitizen { get; set; }
    public string UserName { get; set; } = string.Empty;
    public DateTime CreatedAt { get; set; }
}

public class AttachmentResponse
{
    public long Id { get; set; }
    public string FileName { get; set; } = string.Empty;
    public string FileUrl { get; set; } = string.Empty;
    public string? FileType { get; set; }
    public long FileSizeBytes { get; set; }
    public string? Description { get; set; }
    public DateTime CreatedAt { get; set; }
}

public class StatusHistoryResponse
{
    public string FromStatus { get; set; } = string.Empty;
    public string ToStatus { get; set; } = string.Empty;
    public string? Note { get; set; }
    public string? ChangedBy { get; set; }
    public DateTime ChangedAt { get; set; }
}

public class CreateServiceRequestDto
{
    public int ServiceId { get; set; }
    public int OperationTypeId { get; set; }
    public Guid CitizenId { get; set; }
    public Guid? CompanyId { get; set; }
    public Dictionary<string, object>? Details { get; set; }
    public string? Address { get; set; }
    public string? City { get; set; }
    public string? Area { get; set; }
    public string? ContactPhone { get; set; }
    public int Priority { get; set; } = 3;
}

public class UpdateStatusDto
{
    public string Status { get; set; } = string.Empty;
    public string? Note { get; set; }
}

public class AssignRequestDto
{
    public Guid EmployeeId { get; set; }
}

public class AddCommentDto
{
    public string Content { get; set; } = string.Empty;
    public bool IsVisibleToCitizen { get; set; } = true;
}

#endregion
