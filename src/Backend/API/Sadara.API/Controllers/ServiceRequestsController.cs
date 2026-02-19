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
        [FromQuery] Guid? companyId = null,
        [FromQuery] string? source = null,
        [FromQuery] string? department = null,
        [FromQuery] string? technician = null)
    {
        var query = _unitOfWork.ServiceRequests.AsQueryable();

        if (!string.IsNullOrEmpty(status) && Enum.TryParse<ServiceRequestStatus>(status, true, out var statusEnum))
            query = query.Where(r => r.Status == statusEnum);

        if (serviceId.HasValue)
            query = query.Where(r => r.ServiceId == serviceId);

        if (companyId.HasValue)
            query = query.Where(r => r.CompanyId == companyId);

        // فلتر المصدر: agent = طلبات الوكلاء فقط، company = طلبات الشركة فقط
        if (!string.IsNullOrEmpty(source))
        {
            if (source.Equals("agent", StringComparison.OrdinalIgnoreCase))
                query = query.Where(r => r.AgentId != null);
            else if (source.Equals("company", StringComparison.OrdinalIgnoreCase))
                query = query.Where(r => r.AgentId == null);
        }

        // فلتر القسم: البحث في حقل Details JSON عن اسم القسم
        if (!string.IsNullOrEmpty(department))
        {
            query = query.Where(r => r.Details != null && r.Details.Contains(department));
        }

        // فلتر الفني: البحث في Details JSON أو في TechnicianName
        if (!string.IsNullOrEmpty(technician))
        {
            query = query.Where(r => 
                (r.Details != null && r.Details.Contains(technician)) ||
                (r.Technician != null && r.Technician.FullName == technician));
        }

        var total = await query.CountAsync();
        var requests = await query
            .Include(r => r.Citizen)
            .Include(r => r.Service)
            .Include(r => r.OperationType)
            .Include(r => r.Company)
            .Include(r => r.Agent)
            .Include(r => r.AssignedTo)
            .Include(r => r.Technician)
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
                OperationTypeName = r.OperationType != null ? r.OperationType.NameAr : null,
                EstimatedCost = r.EstimatedCost,
                CitizenId = r.CitizenId,
                CitizenName = r.Citizen != null ? r.Citizen.FullName : null,
                CitizenPhone = r.Citizen != null ? r.Citizen.PhoneNumber : null,
                CompanyId = r.CompanyId,
                CompanyName = r.Company != null ? r.Company.Name : null,
                AgentId = r.AgentId,
                AgentName = r.Agent != null ? r.Agent.Name : null,
                AgentCode = r.Agent != null ? r.Agent.AgentCode : null,
                AgentNetBalance = r.Agent != null ? r.Agent.NetBalance : null,
                Details = r.Details,
                Status = r.Status.ToString(),
                StatusNote = r.StatusNote,
                Priority = r.Priority,
                AssignedToId = r.AssignedToId,
                AssignedToName = r.AssignedTo != null ? r.AssignedTo.FullName : null,
                TechnicianId = r.TechnicianId,
                TechnicianName = r.Technician != null ? r.Technician.FullName : null,
                FinalCost = r.FinalCost,
                Address = r.Address,
                ContactPhone = r.ContactPhone,
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
            .Include(r => r.Agent)
            .Include(r => r.AssignedTo)
            .Include(r => r.Technician)
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
            ChangedById = dto.CitizenId ?? GetCurrentUserId(),
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

        // ═══════ فرض ترتيب الحالات (State Machine) ═══════
        if (!IsValidStatusTransition(request.Status, newStatus))
        {
            return BadRequest(new
            {
                success = false,
                message = $"لا يمكن الانتقال من '{request.Status}' إلى '{newStatus}'. الانتقالات المسموحة: {string.Join(", ", GetAllowedTransitions(request.Status))}"
            });
        }

        var oldStatus = request.Status;
        request.Status = newStatus;
        request.StatusNote = dto.Note;
        request.UpdatedAt = DateTime.UtcNow;

        // تحديث التكلفة النهائية إذا أُرسلت
        if (dto.Amount.HasValue && dto.Amount.Value > 0)
        {
            request.FinalCost = dto.Amount.Value;
        }

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

        // ═══════ إشعارات تلقائية ═══════
        await CreateStatusChangeNotifications(request, oldStatus, newStatus);

        // ═══════ حفظ تغيير الحالة + السجل + الإشعارات أولاً ═══════
        await _unitOfWork.SaveChangesAsync();

        _logger.LogInformation("تم تحديث حالة الطلب {Id} من {OldStatus} إلى {NewStatus}", id, oldStatus, newStatus);

        // ═══════ المعالجة المالية (حفظ منفصل - لا يؤثر على تغيير الحالة) ═══════
        try
        {
            bool hasFinancialChanges = false;

            if (newStatus == ServiceRequestStatus.Completed && request.AgentId.HasValue && request.EstimatedCost > 0)
            {
                var agent = await _unitOfWork.Agents.GetByIdAsync(request.AgentId.Value);
                if (agent != null)
                {
                    var existingTx = await _unitOfWork.AgentTransactions.AsQueryable()
                        .AnyAsync(t => t.ServiceRequestId == id && t.Type == TransactionType.Charge && !t.IsDeleted);

                    if (!existingTx)
                    {
                        var cost = request.FinalCost ?? request.EstimatedCost ?? 0;
                        if (cost > 0)
                        {
                            agent.TotalCharges += cost;
                            agent.NetBalance = agent.TotalPayments - agent.TotalCharges;
                            _unitOfWork.Agents.Update(agent);

                            var transaction = new AgentTransaction
                            {
                                AgentId = agent.Id,
                                Type = TransactionType.Charge,
                                Category = TransactionCategory.NewSubscription,
                                Amount = cost,
                                BalanceAfter = agent.NetBalance,
                                Description = $"طلب خدمة مكتمل: {request.RequestNumber}",
                                ReferenceNumber = request.RequestNumber,
                                ServiceRequestId = id,
                                CreatedById = GetCurrentUserId(),
                                CreatedAt = DateTime.UtcNow
                            };
                            await _unitOfWork.AgentTransactions.AddAsync(transaction);
                            hasFinancialChanges = true;
                            _logger.LogInformation("تم خصم {Cost} من رصيد الوكيل {AgentId} للطلب {RequestNumber}", cost, agent.Id, request.RequestNumber);
                        }
                    }
                }
            }
            else if ((newStatus == ServiceRequestStatus.Cancelled || newStatus == ServiceRequestStatus.Rejected)
                     && request.AgentId.HasValue)
            {
                var existingCharge = await _unitOfWork.AgentTransactions.AsQueryable()
                    .FirstOrDefaultAsync(t => t.ServiceRequestId == id && t.Type == TransactionType.Charge && !t.IsDeleted);

                if (existingCharge != null)
                {
                    var agent = await _unitOfWork.Agents.GetByIdAsync(request.AgentId.Value);
                    if (agent != null)
                    {
                        agent.TotalCharges -= existingCharge.Amount;
                        agent.NetBalance = agent.TotalPayments - agent.TotalCharges;
                        _unitOfWork.Agents.Update(agent);

                        existingCharge.IsDeleted = true;
                        existingCharge.DeletedAt = DateTime.UtcNow;
                        _unitOfWork.AgentTransactions.Update(existingCharge);
                        hasFinancialChanges = true;

                        _logger.LogInformation("تم استرداد {Amount} لرصيد الوكيل {AgentId} بسبب {Status} الطلب {RequestNumber}",
                            existingCharge.Amount, agent.Id, newStatus, request.RequestNumber);
                    }
                }
            }

            if (hasFinancialChanges)
                await _unitOfWork.SaveChangesAsync();
        }
        catch (Exception finEx)
        {
            _logger.LogWarning(finEx, "فشلت المعالجة المالية للطلب {RequestNumber} - تم تحديث الحالة بنجاح", request.RequestNumber);
        }

        // ═══════ المعالجة المالية للفني (أي مهمة لها فني ومبلغ) ═══════
        try
        {
            // تحديد نوع المهمة والفني المستهدف
            string taskTypeStr = "";
            string? originalTechnicianName = null;
            if (!string.IsNullOrEmpty(request.Details))
            {
                try
                {
                    var detailsJson = System.Text.Json.JsonDocument.Parse(request.Details);
                    if (detailsJson.RootElement.TryGetProperty("taskType", out var taskTypeProp))
                        taskTypeStr = taskTypeProp.GetString() ?? "";
                    if (detailsJson.RootElement.TryGetProperty("technician", out var techProp))
                        originalTechnicianName = techProp.GetString();
                }
                catch { /* Details ليست JSON صالحة */ }
            }

            // تحديد الفني المستهدف للخصم:
            // 1. إذا يوجد اسم فني في Details["technician"] → ابحث عنه بالاسم
            // 2. وإلا → الفني المعيّن على الطلب (request.TechnicianId)
            Guid? chargeTargetId = null;
            if (!string.IsNullOrEmpty(originalTechnicianName))
            {
                var originalTech = await _unitOfWork.Users.AsQueryable()
                    .FirstOrDefaultAsync(u => u.FullName == originalTechnicianName && !u.IsDeleted);
                if (originalTech != null)
                    chargeTargetId = originalTech.Id;
            }
            if (!chargeTargetId.HasValue && request.TechnicianId.HasValue)
            {
                chargeTargetId = request.TechnicianId.Value;
            }

            var shouldChargeTechnician = chargeTargetId.HasValue;

            if (shouldChargeTechnician)
            {
                bool hasTechFinancialChanges = false;
                var txCategory = TechnicianTransactionCategory.Maintenance; // الافتراضي
                var txDescription = string.IsNullOrEmpty(taskTypeStr) ? "مهمة مكتملة" : taskTypeStr;
                if (taskTypeStr.Contains("اشتراك", StringComparison.OrdinalIgnoreCase))
                    txCategory = TechnicianTransactionCategory.Subscription;

                if (newStatus == ServiceRequestStatus.Completed)
                {
                    var cost = request.FinalCost ?? request.EstimatedCost ?? 0;
                    if (cost > 0)
                    {
                        // تحقق من عدم وجود معاملة مكررة
                        var existingTechTx = await _unitOfWork.TechnicianTransactions.AsQueryable()
                            .AnyAsync(t => t.ServiceRequestId == id && t.Type == TechnicianTransactionType.Charge && !t.IsDeleted);

                        if (!existingTechTx)
                        {
                            var technician = await _unitOfWork.Users.GetByIdAsync(chargeTargetId!.Value);
                            if (technician != null)
                            {
                                technician.TechTotalCharges += cost;
                                technician.TechNetBalance = technician.TechTotalPayments - technician.TechTotalCharges;
                                _unitOfWork.Users.Update(technician);

                                var techTx = new TechnicianTransaction
                                {
                                    TechnicianId = technician.Id,
                                    Type = TechnicianTransactionType.Charge,
                                    Category = txCategory,
                                    Amount = cost,
                                    BalanceAfter = technician.TechNetBalance,
                                    Description = $"{txDescription}: {request.RequestNumber}",
                                    ReferenceNumber = request.RequestNumber,
                                    ServiceRequestId = id,
                                    CreatedById = GetCurrentUserId(),
                                    CompanyId = request.CompanyId ?? technician.CompanyId ?? Guid.Empty,
                                    CreatedAt = DateTime.UtcNow
                                };
                                await _unitOfWork.TechnicianTransactions.AddAsync(techTx);
                                hasTechFinancialChanges = true;

                                _logger.LogInformation("تم خصم {Cost} على الفني {TechName} للمهمة {RequestNumber} ({Category})",
                                    cost, technician.FullName, request.RequestNumber, txCategory);
                            }
                        }
                    }
                }
                else if (newStatus == ServiceRequestStatus.Cancelled || newStatus == ServiceRequestStatus.Rejected)
                {
                    // استرداد المبلغ إذا كانت هناك معاملة سابقة
                    var existingTechCharge = await _unitOfWork.TechnicianTransactions.AsQueryable()
                        .FirstOrDefaultAsync(t => t.ServiceRequestId == id && t.Type == TechnicianTransactionType.Charge && !t.IsDeleted);

                    if (existingTechCharge != null)
                    {
                        var technician = await _unitOfWork.Users.GetByIdAsync(existingTechCharge.TechnicianId);
                        if (technician != null)
                        {
                            technician.TechTotalCharges -= existingTechCharge.Amount;
                            technician.TechNetBalance = technician.TechTotalPayments - technician.TechTotalCharges;
                            _unitOfWork.Users.Update(technician);

                            existingTechCharge.IsDeleted = true;
                            existingTechCharge.DeletedAt = DateTime.UtcNow;
                            _unitOfWork.TechnicianTransactions.Update(existingTechCharge);
                            hasTechFinancialChanges = true;

                            _logger.LogInformation("تم استرداد {Amount} من الفني {TechName} بسبب {Status} المهمة {RequestNumber}",
                                existingTechCharge.Amount, technician.FullName, newStatus, request.RequestNumber);
                        }
                    }
                }

                if (hasTechFinancialChanges)
                    await _unitOfWork.SaveChangesAsync();
            }
        }
        catch (Exception techFinEx)
        {
            _logger.LogWarning(techFinEx, "فشلت المعالجة المالية للفني في الطلب {RequestNumber} - تم تحديث الحالة بنجاح", request.RequestNumber);
        }

        // ═══════ القيود المحاسبية (حفظ منفصل ثالث) ═══════
        try
        {
            if (newStatus == ServiceRequestStatus.Completed && request.AgentId.HasValue && request.CompanyId.HasValue && request.EstimatedCost > 0)
            {
                var agent = await _unitOfWork.Agents.GetByIdAsync(request.AgentId.Value);
                if (agent != null)
                {
                    var cost = request.FinalCost ?? request.EstimatedCost ?? 0;
                    if (cost > 0)
                    {
                        var agentSubAcct = await ServiceRequestAccountingHelper.FindOrCreateSubAccount(
                            _unitOfWork, "1150", agent.Id, agent.Name, request.CompanyId.Value);
                        var revenueAcct = await ServiceRequestAccountingHelper.FindAccountByCode(
                            _unitOfWork, "4100", request.CompanyId.Value);

                        if (revenueAcct != null)
                        {
                            var journalLines = new List<(Guid AccountId, decimal DebitAmount, decimal CreditAmount, string? LineDescription)>
                            {
                                (agentSubAcct.Id, cost, 0, $"ذمم وكيل {agent.Name} - طلب {request.RequestNumber}"),
                                (revenueAcct.Id, 0, cost, $"إيراد خدمة عبر وكيل {agent.Name}")
                            };
                            await ServiceRequestAccountingHelper.CreateAndPostJournalEntry(
                                _unitOfWork, request.CompanyId.Value, GetCurrentUserId(),
                                $"إكمال طلب خدمة {request.RequestNumber} - وكيل {agent.Name}",
                                JournalReferenceType.ServiceRequest, request.Id.ToString(),
                                journalLines);
                            await _unitOfWork.SaveChangesAsync();
                        }
                    }
                }
            }
        }
        catch (Exception acctEx)
        {
            _logger.LogWarning(acctEx, "فشل إنشاء القيد المحاسبي للطلب {RequestNumber} - تم تحديث الحالة والمعالجة المالية بنجاح", request.RequestNumber);
        }

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
    public async Task<IActionResult> GetMyAssigned(
        [FromQuery] int page = 1, 
        [FromQuery] int pageSize = 20,
        [FromQuery] string? technicianName = null,
        [FromQuery] bool includeCompleted = false)
    {
        var userId = GetCurrentUserId();
        var query = _unitOfWork.ServiceRequests.AsQueryable();

        // فلترة حسب الفني - باسم الفني في Details JSON أو بالـ TechnicianId/AssignedToId
        if (!string.IsNullOrEmpty(technicianName))
        {
            query = query.Where(r => 
                (r.Details != null && r.Details.Contains(technicianName)) ||
                r.AssignedToId == userId ||
                r.TechnicianId == userId);
        }
        else
        {
            query = query.Where(r => r.AssignedToId == userId || r.TechnicianId == userId);
        }

        // استبعاد المكتملة والملغية إلا إذا طلب العكس
        if (!includeCompleted)
        {
            query = query.Where(r => r.Status != ServiceRequestStatus.Completed && 
                                    r.Status != ServiceRequestStatus.Cancelled);
        }

        var total = await query.CountAsync();
        var requests = await query
            .Include(r => r.Service)
            .Include(r => r.OperationType)
            .Include(r => r.Citizen)
            .Include(r => r.Company)
            .Include(r => r.Agent)
            .Include(r => r.AssignedTo)
            .Include(r => r.Technician)
            .OrderByDescending(r => r.Priority)
            .ThenByDescending(r => r.CreatedAt)
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
                OperationTypeName = r.OperationType != null ? r.OperationType.NameAr : null,
                EstimatedCost = r.EstimatedCost,
                CitizenId = r.CitizenId,
                CitizenName = r.Citizen != null ? r.Citizen.FullName : null,
                CitizenPhone = r.Citizen != null ? r.Citizen.PhoneNumber : null,
                CompanyId = r.CompanyId,
                CompanyName = r.Company != null ? r.Company.Name : null,
                AgentId = r.AgentId,
                AgentName = r.Agent != null ? r.Agent.Name : null,
                AgentCode = r.Agent != null ? r.Agent.AgentCode : null,
                AgentNetBalance = r.Agent != null ? r.Agent.NetBalance : null,
                Details = r.Details,
                Status = r.Status.ToString(),
                StatusNote = r.StatusNote,
                Priority = r.Priority,
                AssignedToId = r.AssignedToId,
                AssignedToName = r.AssignedTo != null ? r.AssignedTo.FullName : null,
                TechnicianId = r.TechnicianId,
                TechnicianName = r.Technician != null ? r.Technician.FullName : null,
                FinalCost = r.FinalCost,
                Address = r.Address,
                ContactPhone = r.ContactPhone,
                CreatedAt = r.CreatedAt,
                UpdatedAt = r.UpdatedAt,
                CompletedAt = r.CompletedAt
            })
            .ToListAsync();

        return Ok(new { success = true, data = requests, total, page, pageSize });
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

    /// <summary>
    /// حذف طلب خدمة - مدير النظام فقط
    /// </summary>
    [HttpDelete("{id:guid}")]
    [Authorize(Policy = "SuperAdmin")]
    public async Task<IActionResult> DeleteRequest(Guid id)
    {
        try
        {
            var request = await _unitOfWork.ServiceRequests.GetByIdAsync(id);
            if (request == null)
                return NotFound(new { success = false, message = "الطلب غير موجود" });

            // حذف المعاملة المالية المرتبطة إن وجدت (مع عكس الرصيد)
            var linkedTransaction = await _unitOfWork.AgentTransactions.AsQueryable()
                .FirstOrDefaultAsync(t => t.ServiceRequestId == id);
            if (linkedTransaction != null)
            {
                var agent = await _unitOfWork.Agents.GetByIdAsync(linkedTransaction.AgentId);
                if (agent != null)
                {
                    if (linkedTransaction.Type == TransactionType.Charge)
                        agent.TotalCharges -= linkedTransaction.Amount;
                    else if (linkedTransaction.Type == TransactionType.Payment)
                        agent.TotalPayments -= linkedTransaction.Amount;

                    agent.NetBalance = agent.TotalPayments - agent.TotalCharges;
                    _unitOfWork.Agents.Update(agent);
                }

                _unitOfWork.AgentTransactions.Delete(linkedTransaction);
            }

            // حذف السجلات المرتبطة بالطلب
            var statusHistories = await _unitOfWork.ServiceRequestStatusHistories.AsQueryable()
                .Where(h => h.ServiceRequestId == id).ToListAsync();
            foreach (var h in statusHistories)
                _unitOfWork.ServiceRequestStatusHistories.Delete(h);

            var comments = await _unitOfWork.ServiceRequestComments.AsQueryable()
                .Where(c => c.ServiceRequestId == id).ToListAsync();
            foreach (var c in comments)
                _unitOfWork.ServiceRequestComments.Delete(c);

            var attachments = await _unitOfWork.ServiceRequestAttachments.AsQueryable()
                .Where(a => a.ServiceRequestId == id).ToListAsync();
            foreach (var a in attachments)
                _unitOfWork.ServiceRequestAttachments.Delete(a);

            // حذف الطلب بشكل كامل من قاعدة البيانات
            _unitOfWork.ServiceRequests.Delete(request);

            await _unitOfWork.SaveChangesAsync();

            _logger.LogInformation("SuperAdmin hard-deleted service request {Id}", id);

            return Ok(new { success = true, message = "تم حذف الطلب بشكل كامل" });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error deleting service request {Id}", id);
            return StatusCode(500, new { success = false, message = "حدث خطأ أثناء حذف الطلب" });
        }
    }

    #endregion

    #region Task Management (نظام المهام الموحد)

    /// <summary>
    /// إنشاء مهمة/طلب مباشر من تطبيق الشركة (يحل محل Google Sheets)
    /// </summary>
    [HttpPost("create-task")]
    [Authorize(Policy = "TechnicianOrAbove")]
    public async Task<IActionResult> CreateTask([FromBody] CreateTaskDto dto)
    {
        try
        {
            // تحديد نوع العملية بناءً على نوع المهمة
            var operationTypeId = dto.OperationTypeId ?? dto.TaskType switch
            {
                "شراء اشتراك" => 8,      // New Subscription
                "تركيب" => 1,            // Installation
                "إصلاح" => 2,            // Repair
                "صيانة دورية" => 3,       // Periodic Maintenance
                "فحص" => 4,              // Inspection
                "استبدال" => 5,           // Replacement
                "طوارئ" => 6,            // Emergency
                "استشارة" => 7,           // Consultation
                _ => 1                    // Default: Installation
            };

            // تحويل الأولوية من نص عربي إلى رقم
            var priority = dto.Priority switch
            {
                "عاجل" => 1,
                "عالي" => 2,
                "متوسط" => 3,
                "منخفض" => 4,
                _ => 3
            };

            // بناء تفاصيل JSON مع جميع بيانات المهمة
            var details = new Dictionary<string, object?>
            {
                ["taskType"] = dto.TaskType,
                ["department"] = dto.Department,
                ["leader"] = dto.Leader,
                ["technician"] = dto.Technician,
                ["technicianPhone"] = dto.TechnicianPhone,
                ["customerName"] = dto.CustomerName,
                ["customerPhone"] = dto.CustomerPhone,
                ["fbg"] = dto.FBG,
                ["fat"] = dto.FAT,
                ["notes"] = dto.Notes,
                ["summary"] = dto.Summary,
                ["source"] = "companyDesktop",
                ["priorityLabel"] = dto.Priority
            };

            // إضافة بيانات الاشتراك إن وجدت
            if (!string.IsNullOrEmpty(dto.ServiceType))
                details["serviceType"] = dto.ServiceType;
            if (!string.IsNullOrEmpty(dto.SubscriptionDuration))
                details["subscriptionDuration"] = dto.SubscriptionDuration;
            if (dto.SubscriptionAmount.HasValue)
                details["subscriptionAmount"] = dto.SubscriptionAmount.Value;

            var request = new ServiceRequest
            {
                Id = Guid.NewGuid(),
                RequestNumber = GenerateRequestNumber(),
                ServiceId = dto.ServiceId,
                OperationTypeId = operationTypeId,
                Details = JsonSerializer.Serialize(details),
                Address = dto.Location,
                ContactPhone = dto.CustomerPhone,
                Status = ServiceRequestStatus.Pending,
                Priority = priority,
                EstimatedCost = dto.SubscriptionAmount,
                RequestedAt = DateTime.UtcNow,
                CreatedAt = DateTime.UtcNow
            };

            // تعيين تلقائي: إذا تم تحديد فني، ابحث عنه وعيّنه مباشرة
            if (!string.IsNullOrEmpty(dto.Technician))
            {
                var technicianUser = await _unitOfWork.Users.AsQueryable()
                    .FirstOrDefaultAsync(u => u.FullName == dto.Technician && !u.IsDeleted);
                if (technicianUser != null)
                {
                    request.TechnicianId = technicianUser.Id;
                    request.AssignedToId = technicianUser.Id;
                    request.Status = ServiceRequestStatus.Assigned;
                    request.AssignedAt = DateTime.UtcNow;
                    _logger.LogInformation("تعيين تلقائي للفني {TechnicianName} (ID: {TechnicianId})", dto.Technician, technicianUser.Id);
                    
                    // إشعار الفني بالتعيين
                    await NotifyTechnicianOfAssignment(request, technicianUser.Id, dto.Technician);
                }
            }

            await _unitOfWork.ServiceRequests.AddAsync(request);

            // سجل الحالة
            var statusHistory = new ServiceRequestStatusHistory
            {
                ServiceRequestId = request.Id,
                FromStatus = ServiceRequestStatus.Pending,
                ToStatus = request.Status,
                Note = request.Status == ServiceRequestStatus.Assigned
                    ? $"تم إنشاء وتعيين مهمة: {dto.TaskType} - {dto.CustomerName} → الفني: {dto.Technician}"
                    : $"تم إنشاء مهمة: {dto.TaskType} - {dto.CustomerName}",
                ChangedById = GetCurrentUserId(),
                CreatedAt = DateTime.UtcNow
            };
            await _unitOfWork.ServiceRequestStatusHistories.AddAsync(statusHistory);

            await _unitOfWork.SaveChangesAsync();

            _logger.LogInformation("تم إنشاء مهمة جديدة: {RequestNumber} - {TaskType}", request.RequestNumber, dto.TaskType);

            return CreatedAtAction(nameof(GetById), new { id = request.Id }, new
            {
                success = true,
                data = new
                {
                    request.Id,
                    request.RequestNumber,
                    Status = request.Status.ToString(),
                    TaskType = dto.TaskType,
                    request.CreatedAt
                }
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في إنشاء المهمة");
            return StatusCode(500, new { success = false, message = "حدث خطأ أثناء إنشاء المهمة" });
        }
    }

    /// <summary>
    /// تعيين مهمة مع تفاصيل فنية (فني، قسم، FBG، FAT)
    /// </summary>
    [HttpPatch("{id:guid}/assign-task")]
    [Authorize(Policy = "CompanyAdminOrAbove")]
    public async Task<IActionResult> AssignTask(Guid id, [FromBody] AssignTaskDto dto)
    {
        var request = await _unitOfWork.ServiceRequests.GetByIdAsync(id);
        if (request == null)
            return NotFound(new { success = false, message = "الطلب غير موجود" });

        // تحديث Details JSON بإضافة بيانات التعيين
        var details = new Dictionary<string, object?>();
        if (!string.IsNullOrEmpty(request.Details))
        {
            try
            {
                details = JsonSerializer.Deserialize<Dictionary<string, object?>>(request.Details) ?? new();
            }
            catch { details = new(); }
        }

        if (!string.IsNullOrEmpty(dto.Department)) details["department"] = dto.Department;
        if (!string.IsNullOrEmpty(dto.Leader)) details["leader"] = dto.Leader;
        if (!string.IsNullOrEmpty(dto.Technician)) details["technician"] = dto.Technician;
        if (!string.IsNullOrEmpty(dto.TechnicianPhone)) details["technicianPhone"] = dto.TechnicianPhone;
        if (!string.IsNullOrEmpty(dto.FBG)) details["fbg"] = dto.FBG;
        if (!string.IsNullOrEmpty(dto.FAT)) details["fat"] = dto.FAT;

        // تحديث العنوان
        if (!string.IsNullOrEmpty(dto.Address))
            request.Address = dto.Address;

        request.Details = JsonSerializer.Serialize(details);
        request.AssignedAt = DateTime.UtcNow;
        request.UpdatedAt = DateTime.UtcNow;

        // تعيين الموظف إن وجد
        if (dto.EmployeeId.HasValue)
        {
            var employee = await _unitOfWork.Users.GetByIdAsync(dto.EmployeeId.Value);
            if (employee != null)
            {
                request.AssignedToId = dto.EmployeeId;
            }
        }

        // البحث عن الفني وتعيين TechnicianId
        if (!string.IsNullOrEmpty(dto.Technician))
        {
            var techUser = await _unitOfWork.Users.AsQueryable()
                .FirstOrDefaultAsync(u => u.FullName == dto.Technician && !u.IsDeleted);
            if (techUser != null)
            {
                request.TechnicianId = techUser.Id;
                // إذا لم يتم تحديد EmployeeId، عيّن الفني كـ AssignedTo أيضاً
                if (!dto.EmployeeId.HasValue)
                    request.AssignedToId = techUser.Id;
            }
        }

        // تحديث الحالة إلى معينة
        var oldStatus = request.Status;
        if (request.Status == ServiceRequestStatus.Pending || request.Status == ServiceRequestStatus.Reviewing)
        {
            request.Status = ServiceRequestStatus.Assigned;
        }

        // سجل التغيير
        var history = new ServiceRequestStatusHistory
        {
            ServiceRequestId = id,
            FromStatus = oldStatus,
            ToStatus = request.Status,
            Note = dto.Note ?? $"تم تعيين المهمة - الفني: {dto.Technician ?? "غير محدد"} | القسم: {dto.Department ?? "غير محدد"}",
            ChangedById = GetCurrentUserId(),
            CreatedAt = DateTime.UtcNow
        };

        _unitOfWork.ServiceRequests.Update(request);
        await _unitOfWork.ServiceRequestStatusHistories.AddAsync(history);

        // إشعار الفني عند التعيين
        if (request.TechnicianId.HasValue)
        {
            await NotifyTechnicianOfAssignment(request, request.TechnicianId.Value, dto.Technician);
        }
        else if (request.AssignedToId.HasValue)
        {
            await NotifyTechnicianOfAssignment(request, request.AssignedToId.Value, dto.Technician);
        }

        await _unitOfWork.SaveChangesAsync();

        _logger.LogInformation("تم تعيين المهمة {Id} - الفني: {Technician}, القسم: {Department}", id, dto.Technician, dto.Department);

        return Ok(new { success = true, message = "تم تعيين المهمة بنجاح" });
    }

    /// <summary>
    /// بيانات القوائم المنسدلة للمهام (الأقسام، الفنيين، إلخ)
    /// </summary>
    [HttpGet("task-lookup")]
    [Authorize(Policy = "TechnicianOrAbove")]
    public IActionResult GetTaskLookupData()
    {
        var data = new
        {
            departments = new[]
            {
                new { id = "maintenance", nameAr = "الصيانة", name = "Maintenance" },
                new { id = "accounts", nameAr = "الحسابات", name = "Accounts" },
                new { id = "technicians", nameAr = "الفنيين", name = "Technicians" },
                new { id = "agents", nameAr = "الوكلاء", name = "Agents" },
                new { id = "communications", nameAr = "الاتصالات", name = "Communications" },
                new { id = "welding", nameAr = "اللحام", name = "Welding" }
            },
            priorities = new[]
            {
                new { value = 1, label = "عاجل", color = "#EF4444" },
                new { value = 2, label = "عالي", color = "#F59E0B" },
                new { value = 3, label = "متوسط", color = "#3B82F6" },
                new { value = 4, label = "منخفض", color = "#10B981" }
            },
            // مهام كل قسم - بديل عن Google Sheets (ورقة ALKSM)
            departmentTasks = new Dictionary<string, string[]>
            {
                ["الصيانة"] = new[] { "تركيب", "إصلاح", "صيانة دورية", "فحص", "استبدال", "طوارئ" },
                ["الحسابات"] = new[] { "شراء اشتراك", "تجديد اشتراك", "استشارة", "مراجعة حساب" },
                ["الفنيين"] = new[] { "تركيب", "إصلاح", "صيانة دورية", "فحص", "استبدال", "طوارئ" },
                ["الوكلاء"] = new[] { "شراء اشتراك", "تجديد اشتراك", "استشارة" },
                ["الاتصالات"] = new[] { "إصلاح", "فحص", "صيانة دورية", "طوارئ" },
                ["اللحام"] = new[] { "لحام ألياف", "إصلاح كابل", "تمديد", "فحص" }
            },
            taskTypes = new[]
            {
                "شراء اشتراك", "تركيب", "إصلاح", "صيانة دورية",
                "فحص", "استبدال", "طوارئ", "استشارة",
                "تجديد اشتراك", "مراجعة حساب", "لحام ألياف", "إصلاح كابل", "تمديد"
            },
            serviceTypes = new[] { "35", "50", "75", "150" },
            subscriptionDurations = new[]
            {
                new { value = "شهر", months = 1 },
                new { value = "شهرين", months = 2 },
                new { value = "ثلاث أشهر", months = 3 },
                new { value = "6 أشهر", months = 6 },
                new { value = "سنة", months = 12 }
            },
            statuses = new[]
            {
                new { value = "Pending", label = "مفتوحة" },
                new { value = "Reviewing", label = "قيد المراجعة" },
                new { value = "Approved", label = "موافق عليه" },
                new { value = "Assigned", label = "معينة" },
                new { value = "InProgress", label = "قيد التنفيذ" },
                new { value = "Completed", label = "مكتملة" },
                new { value = "Cancelled", label = "ملغية" },
                new { value = "Rejected", label = "مرفوضة" },
                new { value = "OnHold", label = "معلقة" }
            },
            // خيارات FBG - بديل عن Google Sheets (ورقة Sheet1)
            fbgOptions = new[]
            {
                "FBG-01", "FBG-02", "FBG-03", "FBG-04", "FBG-05",
                "FBG-06", "FBG-07", "FBG-08", "FBG-09", "FBG-10",
                "FBG-11", "FBG-12", "FBG-13", "FBG-14", "FBG-15",
                "FBG-16", "FBG-17", "FBG-18", "FBG-19", "FBG-20"
            }
        };

        return Ok(new { success = true, data });
    }

    /// <summary>
    /// جلب الموظفين (فنيين وليدرز) للمهام - بديل عن Google Sheets (ورقة المستخدمين)
    /// </summary>
    [HttpGet("task-staff")]
    [Authorize(Policy = "TechnicianOrAbove")]
    public async Task<IActionResult> GetTaskStaff([FromQuery] string? department = null)
    {
        try
        {
            // جلب الموظفين بأدوار فنية وقيادية
            var staffRoles = new[]
            {
                UserRole.Technician,
                UserRole.TechnicalLeader,
                UserRole.Manager,
                UserRole.Employee
            };

            var query = _unitOfWork.Users.AsQueryable()
                .Where(u => staffRoles.Contains(u.Role));

            // تصفية حسب القسم إن وُجد
            if (!string.IsNullOrWhiteSpace(department))
            {
                query = query.Where(u => u.Department == department || string.IsNullOrEmpty(u.Department));
            }

            var staff = await query
                .Select(u => new
                {
                    u.Id,
                    Name = u.FullName,
                    u.PhoneNumber,
                    u.Department,
                    Role = u.Role.ToString(),
                    u.EmployeeCode
                })
                .OrderBy(u => u.Role)
                .ThenBy(u => u.Name)
                .ToListAsync();

            var leaders = staff
                .Where(s => s.Role == nameof(UserRole.TechnicalLeader) || s.Role == nameof(UserRole.Manager))
                .ToList();

            var technicians = staff
                .Where(s => s.Role == nameof(UserRole.Technician) || s.Role == nameof(UserRole.TechnicalLeader))
                .ToList();

            return Ok(new
            {
                success = true,
                data = new
                {
                    leaders,
                    technicians,
                    allStaff = staff
                }
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في جلب بيانات الموظفين للمهام");
            return StatusCode(500, new { success = false, message = "خطأ في جلب بيانات الموظفين" });
        }
    }

    #endregion

    #region Helper Methods

    /// <summary>
    /// الانتقالات المسموحة بين الحالات (State Machine)
    /// </summary>
    private static readonly Dictionary<ServiceRequestStatus, ServiceRequestStatus[]> AllowedTransitions = new()
    {
        [ServiceRequestStatus.Pending] = new[] { ServiceRequestStatus.Reviewing, ServiceRequestStatus.Assigned, ServiceRequestStatus.InProgress, ServiceRequestStatus.Cancelled, ServiceRequestStatus.Rejected },
        [ServiceRequestStatus.Reviewing] = new[] { ServiceRequestStatus.Approved, ServiceRequestStatus.Assigned, ServiceRequestStatus.InProgress, ServiceRequestStatus.Rejected, ServiceRequestStatus.Cancelled },
        [ServiceRequestStatus.Approved] = new[] { ServiceRequestStatus.Assigned, ServiceRequestStatus.InProgress, ServiceRequestStatus.Cancelled },
        [ServiceRequestStatus.Assigned] = new[] { ServiceRequestStatus.InProgress, ServiceRequestStatus.Completed, ServiceRequestStatus.OnHold, ServiceRequestStatus.Cancelled },
        [ServiceRequestStatus.InProgress] = new[] { ServiceRequestStatus.Completed, ServiceRequestStatus.OnHold, ServiceRequestStatus.Cancelled },
        [ServiceRequestStatus.OnHold] = new[] { ServiceRequestStatus.InProgress, ServiceRequestStatus.Assigned, ServiceRequestStatus.Cancelled },
        [ServiceRequestStatus.Completed] = Array.Empty<ServiceRequestStatus>(),  // حالة نهائية
        [ServiceRequestStatus.Cancelled] = Array.Empty<ServiceRequestStatus>(),  // حالة نهائية
        [ServiceRequestStatus.Rejected] = Array.Empty<ServiceRequestStatus>(),   // حالة نهائية
    };

    private static bool IsValidStatusTransition(ServiceRequestStatus from, ServiceRequestStatus to)
    {
        if (from == to) return true; // السماح بنفس الحالة (no-op)
        return AllowedTransitions.TryGetValue(from, out var allowed) && allowed.Contains(to);
    }

    private static IEnumerable<string> GetAllowedTransitions(ServiceRequestStatus from)
    {
        return AllowedTransitions.TryGetValue(from, out var allowed)
            ? allowed.Select(s => s.ToString())
            : Enumerable.Empty<string>();
    }

    /// <summary>
    /// إنشاء إشعار تلقائي عند تغيير حالة طلب
    /// </summary>
    private async Task CreateStatusChangeNotifications(ServiceRequest request, ServiceRequestStatus oldStatus, ServiceRequestStatus newStatus)
    {
        var notifications = new List<Notification>();
        var statusAr = newStatus switch
        {
            ServiceRequestStatus.Pending => "جديد",
            ServiceRequestStatus.Reviewing => "قيد المراجعة",
            ServiceRequestStatus.Approved => "موافق عليه",
            ServiceRequestStatus.Assigned => "معينة",
            ServiceRequestStatus.InProgress => "قيد التنفيذ",
            ServiceRequestStatus.Completed => "مكتملة",
            ServiceRequestStatus.Cancelled => "ملغية",
            ServiceRequestStatus.Rejected => "مرفوضة",
            ServiceRequestStatus.OnHold => "معلقة",
            _ => newStatus.ToString()
        };

        // إشعار للموظف المعيّن
        if (request.AssignedToId.HasValue)
        {
            notifications.Add(new Notification
            {
                UserId = request.AssignedToId.Value,
                Title = $"تحديث طلب {request.RequestNumber}",
                TitleAr = $"تحديث طلب {request.RequestNumber}",
                Body = $"تم تغيير حالة الطلب إلى: {statusAr}",
                BodyAr = $"تم تغيير حالة الطلب إلى: {statusAr}",
                Type = NotificationType.RequestStatusUpdate,
                ReferenceId = request.Id,
                ReferenceType = "ServiceRequest",
                CreatedAt = DateTime.UtcNow
            });
        }

        // إشعار للفني المعيّن (إذا مختلف عن AssignedTo)
        if (request.TechnicianId.HasValue && request.TechnicianId != request.AssignedToId)
        {
            notifications.Add(new Notification
            {
                UserId = request.TechnicianId.Value,
                Title = $"تحديث طلب {request.RequestNumber}",
                TitleAr = $"تحديث طلب {request.RequestNumber}",
                Body = $"تم تغيير حالة الطلب إلى: {statusAr}",
                BodyAr = $"تم تغيير حالة الطلب إلى: {statusAr}",
                Type = NotificationType.RequestStatusUpdate,
                ReferenceId = request.Id,
                ReferenceType = "ServiceRequest",
                CreatedAt = DateTime.UtcNow
            });
        }

        foreach (var n in notifications)
        {
            await _unitOfWork.Notifications.AddAsync(n);
        }
    }

    /// <summary>
    /// إشعار المدراء عند وصول طلب وكيل جديد
    /// </summary>
    private async Task NotifyAdminsOfAgentRequest(ServiceRequest request, string agentName)
    {
        // جلب المدراء ومديري الشركة
        var adminRoles = new[] { UserRole.CompanyAdmin, UserRole.Manager, UserRole.SuperAdmin };
        var admins = await _unitOfWork.Users.AsQueryable()
            .Where(u => adminRoles.Contains(u.Role) && !u.IsDeleted)
            .Select(u => u.Id)
            .ToListAsync();

        foreach (var adminId in admins)
        {
            await _unitOfWork.Notifications.AddAsync(new Notification
            {
                UserId = adminId,
                Title = "طلب وكيل جديد",
                TitleAr = "طلب وكيل جديد",
                Body = $"طلب جديد من الوكيل {agentName}: {request.RequestNumber}",
                BodyAr = $"طلب جديد من الوكيل {agentName}: {request.RequestNumber}",
                Type = NotificationType.AgentRequest,
                ReferenceId = request.Id,
                ReferenceType = "ServiceRequest",
                CreatedAt = DateTime.UtcNow
            });
        }
    }

    /// <summary>
    /// إشعار الفني عند تعيينه لمهمة
    /// </summary>
    private async Task NotifyTechnicianOfAssignment(ServiceRequest request, Guid technicianUserId, string? technicianName)
    {
        await _unitOfWork.Notifications.AddAsync(new Notification
        {
            UserId = technicianUserId,
            Title = "تم تعيينك لمهمة جديدة",
            TitleAr = "تم تعيينك لمهمة جديدة",
            Body = $"تم تعيينك للعمل على الطلب {request.RequestNumber} - {request.ContactPhone}",
            BodyAr = $"تم تعيينك للعمل على الطلب {request.RequestNumber} - {request.ContactPhone}",
            Type = NotificationType.RequestAssigned,
            ReferenceId = request.Id,
            ReferenceType = "ServiceRequest",
            CreatedAt = DateTime.UtcNow
        });
    }

    private Guid GetCurrentUserId()
    {
        var claim = User.FindFirst("sub") ?? User.FindFirst(System.Security.Claims.ClaimTypes.NameIdentifier);
        return claim != null ? Guid.Parse(claim.Value) : Guid.Empty;
    }

    private static string GenerateRequestNumber()
    {
        return $"{DateTime.UtcNow:yyMMddHHmm}{Random.Shared.Next(1000, 9999)}";
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
            OperationTypeName = r.OperationType?.NameAr,
            EstimatedCost = r.EstimatedCost,
            CitizenId = r.CitizenId,
            CitizenName = r.Citizen?.FullName,
            CompanyId = r.CompanyId,
            CompanyName = r.Company?.Name,
            AgentId = r.AgentId,
            AgentName = r.Agent?.Name,
            AgentCode = r.Agent?.AgentCode,
            AgentNetBalance = r.Agent?.NetBalance,
            Status = r.Status.ToString(),
            Priority = r.Priority,
            TechnicianId = r.TechnicianId,
            TechnicianName = r.Technician?.FullName,
            FinalCost = r.FinalCost,
            Address = r.Address,
            ContactPhone = r.ContactPhone,
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
            OperationTypeName = r.OperationType?.NameAr,
            CitizenId = r.CitizenId,
            CitizenName = r.Citizen?.FullName,
            CitizenPhone = r.Citizen?.PhoneNumber,
            CompanyId = r.CompanyId,
            CompanyName = r.Company?.Name,
            AgentId = r.AgentId,
            AgentName = r.Agent?.Name,
            AgentCode = r.Agent?.AgentCode,
            AgentNetBalance = r.Agent?.NetBalance,
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
            TechnicianId = r.TechnicianId,
            TechnicianName = r.Technician?.FullName,
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
    public string? OperationTypeName { get; set; }
    public decimal? EstimatedCost { get; set; }
    public Guid? CitizenId { get; set; }
    public string? CitizenName { get; set; }
    public string? CitizenPhone { get; set; }
    public Guid? CompanyId { get; set; }
    public string? CompanyName { get; set; }
    public Guid? AgentId { get; set; }
    public string? AgentName { get; set; }
    public string? AgentCode { get; set; }
    public decimal? AgentNetBalance { get; set; }
    public string? Details { get; set; }
    public string Status { get; set; } = string.Empty;
    public string? StatusNote { get; set; }
    public int Priority { get; set; }
    public Guid? AssignedToId { get; set; }
    public string? AssignedToName { get; set; }
    public Guid? TechnicianId { get; set; }
    public string? TechnicianName { get; set; }
    public decimal? FinalCost { get; set; }
    public string? Address { get; set; }
    public string? ContactPhone { get; set; }
    public DateTime CreatedAt { get; set; }
    public DateTime? UpdatedAt { get; set; }
    public DateTime? CompletedAt { get; set; }
}

public class ServiceRequestDetailResponse : ServiceRequestResponse
{
    public string? City { get; set; }
    public string? Area { get; set; }
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
    public Guid? CitizenId { get; set; }
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
    /// <summary>المبلغ النهائي (اختياري - يُستخدم لتحديث التكلفة النهائية عند الإكمال)</summary>
    public decimal? Amount { get; set; }
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

/// <summary>
/// إنشاء مهمة/طلب مباشر من تطبيق الشركة
/// </summary>
public class CreateTaskDto
{
    /// <summary>نوع المهمة - مثل "صيانة"، "شراء اشتراك"، "فحص"</summary>
    public string TaskType { get; set; } = string.Empty;
    
    /// <summary>القسم - الصيانة، الحسابات، الفنيين، الوكلاء، الاتصالات، اللحام</summary>
    public string? Department { get; set; }
    
    /// <summary>القائد المسؤول</summary>
    public string? Leader { get; set; }
    
    /// <summary>اسم الفني</summary>
    public string? Technician { get; set; }
    
    /// <summary>رقم هاتف الفني</summary>
    public string? TechnicianPhone { get; set; }
    
    /// <summary>اسم العميل</summary>
    public string CustomerName { get; set; } = string.Empty;
    
    /// <summary>رقم هاتف العميل</summary>
    public string CustomerPhone { get; set; } = string.Empty;
    
    /// <summary>FBG - معرف صندوق التوزيع</summary>
    public string? FBG { get; set; }
    
    /// <summary>FAT - معرف نقطة النهاية</summary>
    public string? FAT { get; set; }
    
    /// <summary>الموقع/العنوان</summary>
    public string? Location { get; set; }
    
    /// <summary>ملاحظات</summary>
    public string? Notes { get; set; }
    
    /// <summary>ملخص المهمة</summary>
    public string? Summary { get; set; }
    
    /// <summary>الأولوية - منخفض، متوسط، عالي، عاجل</summary>
    public string Priority { get; set; } = "متوسط";
    
    /// <summary>نوع الخدمة FTTH (35, 50, 75, 150)</summary>
    public string? ServiceType { get; set; }
    
    /// <summary>مدة الاشتراك - شهر، شهرين، ثلاث أشهر، 6 أشهر، سنة</summary>
    public string? SubscriptionDuration { get; set; }
    
    /// <summary>مبلغ الاشتراك</summary>
    public decimal? SubscriptionAmount { get; set; }
    
    /// <summary>معرف الخدمة (اختياري - افتراضي 9 = Internet FTTH)</summary>
    public int ServiceId { get; set; } = 9;
    
    /// <summary>معرف نوع العملية (اختياري)</summary>
    public int? OperationTypeId { get; set; }
}

/// <summary>
/// تعيين مهمة مع تفاصيل FTTH
/// </summary>
public class AssignTaskDto
{
    /// <summary>القسم</summary>
    public string? Department { get; set; }
    
    /// <summary>القائد</summary>
    public string? Leader { get; set; }
    
    /// <summary>اسم الفني</summary>
    public string? Technician { get; set; }
    
    /// <summary>رقم هاتف الفني</summary>
    public string? TechnicianPhone { get; set; }
    
    /// <summary>FBG</summary>
    public string? FBG { get; set; }
    
    /// <summary>FAT</summary>
    public string? FAT { get; set; }
    
    /// <summary>الموقع / العنوان</summary>
    public string? Address { get; set; }
    
    /// <summary>معرف الموظف المعين (اختياري)</summary>
    public Guid? EmployeeId { get; set; }
    
    /// <summary>ملاحظة التعيين</summary>
    public string? Note { get; set; }
}

#endregion

#region Accounting Helpers

/// <summary>
/// دوال مساعدة للربط المحاسبي - تُستخدم عند إكمال/إلغاء طلبات الوكلاء
/// </summary>
public static class ServiceRequestAccountingHelper
{
    public static async Task<Account?> FindAccountByCode(IUnitOfWork unitOfWork, string code, Guid companyId)
    {
        return await unitOfWork.Accounts.AsQueryable()
            .FirstOrDefaultAsync(a => a.Code == code && a.CompanyId == companyId && a.IsActive);
    }

    public static async Task<Account> FindOrCreateSubAccount(
        IUnitOfWork unitOfWork, string parentCode, Guid personId, string personName, Guid companyId)
    {
        var parent = await FindAccountByCode(unitOfWork, parentCode, companyId);
        if (parent == null)
            throw new Exception($"الحساب الأب {parentCode} غير موجود");

        var existing = await unitOfWork.Accounts.AsQueryable()
            .FirstOrDefaultAsync(a => a.ParentAccountId == parent.Id
                && a.CompanyId == companyId
                && a.Description == personId.ToString()
                && a.IsActive);

        if (existing != null) return existing;

        var siblings = await unitOfWork.Accounts.AsQueryable()
            .Where(a => a.ParentAccountId == parent.Id && a.CompanyId == companyId)
            .Select(a => a.Code)
            .ToListAsync();

        int maxSuffix = 0;
        foreach (var code in siblings)
        {
            if (code.StartsWith(parentCode) && code.Length > parentCode.Length)
            {
                if (int.TryParse(code.Substring(parentCode.Length), out var num) && num > maxSuffix)
                    maxSuffix = num;
            }
        }
        var newCode = $"{parentCode}{maxSuffix + 1}";

        if (parent.IsLeaf)
        {
            parent.IsLeaf = false;
            unitOfWork.Accounts.Update(parent);
        }

        var subAccount = new Account
        {
            Id = Guid.NewGuid(),
            Code = newCode,
            Name = personName,
            NameEn = null,
            AccountType = parent.AccountType,
            ParentAccountId = parent.Id,
            OpeningBalance = 0,
            CurrentBalance = 0,
            IsSystemAccount = false,
            Level = parent.Level + 1,
            IsLeaf = true,
            IsActive = true,
            Description = personId.ToString(),
            CompanyId = companyId
        };

        await unitOfWork.Accounts.AddAsync(subAccount);
        return subAccount;
    }

    public static async Task CreateAndPostJournalEntry(
        IUnitOfWork unitOfWork,
        Guid companyId,
        Guid createdById,
        string description,
        JournalReferenceType referenceType,
        string? referenceId,
        List<(Guid AccountId, decimal DebitAmount, decimal CreditAmount, string? LineDescription)> lines)
    {
        var year = DateTime.UtcNow.Year;
        var count = await unitOfWork.JournalEntries.CountAsync(
            j => j.CompanyId == companyId && j.EntryDate.Year == year);
        var entryNumber = $"JE-{year}-{(count + 1):D4}";

        var entry = new JournalEntry
        {
            Id = Guid.NewGuid(),
            EntryNumber = entryNumber,
            EntryDate = DateTime.UtcNow,
            Description = description,
            TotalDebit = lines.Sum(l => l.DebitAmount),
            TotalCredit = lines.Sum(l => l.CreditAmount),
            ReferenceType = referenceType,
            ReferenceId = referenceId,
            Status = JournalEntryStatus.Posted,
            CompanyId = companyId,
            CreatedById = createdById,
            ApprovedById = createdById,
            ApprovedAt = DateTime.UtcNow,
            Lines = lines.Select(l => new JournalEntryLine
            {
                AccountId = l.AccountId,
                DebitAmount = l.DebitAmount,
                CreditAmount = l.CreditAmount,
                Description = l.LineDescription
            }).ToList()
        };

        await unitOfWork.JournalEntries.AddAsync(entry);

        foreach (var line in lines)
        {
            var account = await unitOfWork.Accounts.GetByIdAsync(line.AccountId);
            if (account == null) continue;

            if (account.AccountType == AccountType.Assets || account.AccountType == AccountType.Expenses)
            {
                account.CurrentBalance += line.DebitAmount - line.CreditAmount;
            }
            else
            {
                account.CurrentBalance += line.CreditAmount - line.DebitAmount;
            }
            unitOfWork.Accounts.Update(account);
        }
    }
}

#endregion
