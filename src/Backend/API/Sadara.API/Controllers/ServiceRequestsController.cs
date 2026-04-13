using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Sadara.Application.Interfaces;
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
    private readonly IFcmNotificationService _fcmService;

    public ServiceRequestsController(IUnitOfWork unitOfWork, ILogger<ServiceRequestsController> logger, IFcmNotificationService fcmService)
    {
        _unitOfWork = unitOfWork;
        _logger = logger;
        _fcmService = fcmService;
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
        [FromQuery] string? technician = null,
        [FromQuery] string? customerPhone = null,
        [FromQuery] string? taskType = null,
        [FromQuery] string? createdByName = null,
        [FromQuery] string? search = null)
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

        // فلتر القسم: يدعم قسم واحد أو أقسام متعددة مفصولة بفاصلة
        if (!string.IsNullOrEmpty(department))
        {
            var depts = department.Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
            if (depts.Length == 1)
            {
                query = query.Where(r => r.Details != null && r.Details.Contains(depts[0]));
            }
            else
            {
                query = query.Where(r => r.Details != null && depts.Any(d => r.Details.Contains(d)));
            }
        }

        // فلتر الفني أو المنشئ: إذا وُجد كلاهما يُستخدم OR بينهما
        if (!string.IsNullOrEmpty(technician) && !string.IsNullOrEmpty(createdByName))
        {
            query = query.Where(r =>
                (r.Details != null && r.Details.Contains(technician)) ||
                (r.Technician != null && r.Technician.FullName == technician) ||
                (r.Details != null && r.Details.Contains(createdByName)));
        }
        else if (!string.IsNullOrEmpty(technician))
        {
            query = query.Where(r =>
                (r.Details != null && r.Details.Contains(technician)) ||
                (r.Technician != null && r.Technician.FullName == technician));
        }
        else if (!string.IsNullOrEmpty(createdByName))
        {
            query = query.Where(r =>
                r.Details != null && r.Details.Contains(createdByName));
        }

        // فلتر رقم هاتف العميل (بحث في Details JSON أو في PhoneNumber للمواطن)
        if (!string.IsNullOrEmpty(customerPhone))
        {
            query = query.Where(r =>
                (r.Details != null && r.Details.Contains(customerPhone)) ||
                (r.Citizen != null && r.Citizen.PhoneNumber.Contains(customerPhone)));
        }

        // فلتر نوع المهمة (مثلاً: "تحصيل مبلغ تجديد")
        if (!string.IsNullOrEmpty(taskType))
        {
            query = query.Where(r => r.Details != null && r.Details.Contains(taskType));
        }

        // بحث عام: اسم العميل، هاتف، فني، منشئ، رقم الطلب
        if (!string.IsNullOrEmpty(search))
        {
            query = query.Where(r =>
                (r.Details != null && r.Details.Contains(search)) ||
                (r.ContactPhone != null && r.ContactPhone.Contains(search)) ||
                (r.RequestNumber.Contains(search)) ||
                (r.Technician != null && r.Technician.FullName.Contains(search)) ||
                (r.Citizen != null && r.Citizen.FullName.Contains(search)) ||
                (r.Citizen != null && r.Citizen.PhoneNumber.Contains(search)));
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
            Details = dto.Details != null ? JsonSerializer.Serialize(dto.Details, new JsonSerializerOptions { Encoder = System.Text.Encodings.Web.JavaScriptEncoder.UnsafeRelaxedJsonEscaping }) : null,
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

            // ═══ ملاحظة: تم إزالة التسجيل المالي على الوكيل عند إكمال الطلب ═══
            // التسجيل يتم فقط عند تفعيل الاشتراك واختيار طريقة الدفع "وكيل"
            // في SubscriptionLogsController أو FtthAccountingController
            // هذا يمنع التسجيل المزدوج للمبلغ على الوكيل

            if ((newStatus == ServiceRequestStatus.Cancelled || newStatus == ServiceRequestStatus.Rejected)
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

                        // ═══ إلغاء القيد المحاسبي المرتبط ═══
                        if (existingCharge.JournalEntryId.HasValue)
                        {
                            var agentJe = await _unitOfWork.JournalEntries.AsQueryable()
                                .Include(j => j.Lines)
                                .FirstOrDefaultAsync(j => j.Id == existingCharge.JournalEntryId.Value && !j.IsDeleted);
                            if (agentJe != null)
                            {
                                if (agentJe.Status == JournalEntryStatus.Posted)
                                {
                                    foreach (var jLine in agentJe.Lines)
                                    {
                                        var acct = await _unitOfWork.Accounts.GetByIdAsync(jLine.AccountId);
                                        if (acct == null) continue;
                                        if (acct.AccountType == AccountType.Assets || acct.AccountType == AccountType.Expenses)
                                            acct.CurrentBalance -= jLine.DebitAmount - jLine.CreditAmount;
                                        else
                                            acct.CurrentBalance -= jLine.CreditAmount - jLine.DebitAmount;
                                        _unitOfWork.Accounts.Update(acct);
                                    }
                                }
                                foreach (var jLine in agentJe.Lines)
                                {
                                    jLine.IsDeleted = true;
                                    jLine.DeletedAt = DateTime.UtcNow;
                                }
                                agentJe.IsDeleted = true;
                                agentJe.DeletedAt = DateTime.UtcNow;
                                agentJe.Status = JournalEntryStatus.Voided;
                                _unitOfWork.JournalEntries.Update(agentJe);
                                _logger.LogInformation("تم إلغاء القيد المحاسبي {EntryNumber} بسبب إلغاء طلب الوكيل", agentJe.EntryNumber);
                            }
                        }

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

            // ═══ التسجيل المالي على الفني عند إكمال مهام الصيانة ═══
            // مهام الصيانة/الفنيين/الاتصالات/اللحام: تُسجَّل على الفني عند الإكمال
            // مهام الحسابات (شراء/تجديد): تُسجَّل من شاشة التجديد فقط

            // استخراج القسم من Details
            string departmentStr = "";
            try
            {
                if (!string.IsNullOrEmpty(request.Details))
                {
                    var dJson = System.Text.Json.JsonDocument.Parse(request.Details);
                    if (dJson.RootElement.TryGetProperty("department", out var deptProp))
                        departmentStr = deptProp.GetString() ?? "";
                }
            }
            catch { }

            // أقسام الحسابات — لا تُسجَّل هنا (تُسجَّل من شاشة التجديد)
            bool isAccountingDept = departmentStr == "الحسابات" || departmentStr == "الوكلاء" ||
                                    taskTypeStr == "شراء اشتراك" || taskTypeStr == "تجديد اشتراك";

            var shouldHandleTechCancellation = chargeTargetId.HasValue;

            if (shouldHandleTechCancellation)
            {
                bool hasTechFinancialChanges = false;

                if (newStatus == ServiceRequestStatus.Completed && !isAccountingDept)
                {
                    // مهمة صيانة/فني مكتملة مع مبلغ → سجّل على الفني
                    var chargeAmount = request.FinalCost ?? request.EstimatedCost ?? 0;
                    if (chargeAmount > 0 && chargeTargetId.HasValue)
                    {
                        var technician = await _unitOfWork.Users.GetByIdAsync(chargeTargetId.Value);
                        if (technician != null)
                        {
                            // تحقق من عدم وجود معاملة سابقة لنفس الطلب
                            var existingTx = await _unitOfWork.TechnicianTransactions.AsQueryable()
                                .AnyAsync(t => t.ServiceRequestId == id && t.Type == TechnicianTransactionType.Charge && !t.IsDeleted);

                            if (!existingTx)
                            {
                                technician.TechTotalCharges += chargeAmount;
                                technician.TechNetBalance = technician.TechTotalPayments - technician.TechTotalCharges;
                                _unitOfWork.Users.Update(technician);

                                var techTx = new TechnicianTransaction
                                {
                                    TechnicianId = technician.Id,
                                    Type = TechnicianTransactionType.Charge,
                                    Category = TechnicianTransactionCategory.Maintenance,
                                    Amount = chargeAmount,
                                    BalanceAfter = technician.TechNetBalance,
                                    Description = $"{taskTypeStr} - {request.RequestNumber}",
                                    ServiceRequestId = id,
                                    CreatedById = request.CompanyId ?? Guid.Empty,
                                    CompanyId = request.CompanyId ?? Guid.Empty,
                                    CreatedAt = DateTime.UtcNow,
                                };
                                await _unitOfWork.TechnicianTransactions.AddAsync(techTx);
                                hasTechFinancialChanges = true;

                                _logger.LogInformation("تم تسجيل {Amount} على الفني {TechId} — مهمة {RequestNumber} ({TaskType})",
                                    chargeAmount, technician.Id, request.RequestNumber, taskTypeStr);
                            }
                        }
                    }
                }
                else if (newStatus == ServiceRequestStatus.Completed && isAccountingDept)
                {
                    _logger.LogInformation("طلب {RequestNumber} (حسابات) مكتمل — التسجيل المالي يتم عند تفعيل الاشتراك", request.RequestNumber);
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

                            // ═══ إلغاء القيد المحاسبي المرتبط ═══
                            if (existingTechCharge.JournalEntryId.HasValue)
                            {
                                var techJe = await _unitOfWork.JournalEntries.AsQueryable()
                                    .Include(j => j.Lines)
                                    .FirstOrDefaultAsync(j => j.Id == existingTechCharge.JournalEntryId.Value && !j.IsDeleted);
                                if (techJe != null)
                                {
                                    if (techJe.Status == JournalEntryStatus.Posted)
                                    {
                                        foreach (var jLine in techJe.Lines)
                                        {
                                            var acct = await _unitOfWork.Accounts.GetByIdAsync(jLine.AccountId);
                                            if (acct == null) continue;
                                            if (acct.AccountType == AccountType.Assets || acct.AccountType == AccountType.Expenses)
                                                acct.CurrentBalance -= jLine.DebitAmount - jLine.CreditAmount;
                                            else
                                                acct.CurrentBalance -= jLine.CreditAmount - jLine.DebitAmount;
                                            _unitOfWork.Accounts.Update(acct);
                                        }
                                    }
                                    foreach (var jLine in techJe.Lines)
                                    {
                                        jLine.IsDeleted = true;
                                        jLine.DeletedAt = DateTime.UtcNow;
                                    }
                                    techJe.IsDeleted = true;
                                    techJe.DeletedAt = DateTime.UtcNow;
                                    techJe.Status = JournalEntryStatus.Voided;
                                    _unitOfWork.JournalEntries.Update(techJe);
                                    _logger.LogInformation("تم إلغاء القيد المحاسبي {EntryNumber} بسبب إلغاء مهمة الفني", techJe.EntryNumber);
                                }
                            }
                            else
                            {
                                // بحث عن القيد عبر ReferenceType + ReferenceId (للسجلات القديمة بدون JournalEntryId)
                                var techJeFallback = await _unitOfWork.JournalEntries.AsQueryable()
                                    .Include(j => j.Lines)
                                    .FirstOrDefaultAsync(j => j.ReferenceType == JournalReferenceType.ServiceRequest
                                        && j.ReferenceId == id.ToString() && !j.IsDeleted);
                                if (techJeFallback != null)
                                {
                                    if (techJeFallback.Status == JournalEntryStatus.Posted)
                                    {
                                        foreach (var jLine in techJeFallback.Lines)
                                        {
                                            var acct = await _unitOfWork.Accounts.GetByIdAsync(jLine.AccountId);
                                            if (acct == null) continue;
                                            if (acct.AccountType == AccountType.Assets || acct.AccountType == AccountType.Expenses)
                                                acct.CurrentBalance -= jLine.DebitAmount - jLine.CreditAmount;
                                            else
                                                acct.CurrentBalance -= jLine.CreditAmount - jLine.DebitAmount;
                                            _unitOfWork.Accounts.Update(acct);
                                        }
                                    }
                                    foreach (var jLine in techJeFallback.Lines)
                                    {
                                        jLine.IsDeleted = true;
                                        jLine.DeletedAt = DateTime.UtcNow;
                                    }
                                    techJeFallback.IsDeleted = true;
                                    techJeFallback.DeletedAt = DateTime.UtcNow;
                                    techJeFallback.Status = JournalEntryStatus.Voided;
                                    _unitOfWork.JournalEntries.Update(techJeFallback);
                                    _logger.LogInformation("تم إلغاء القيد المحاسبي {EntryNumber} (fallback) بسبب إلغاء مهمة الفني", techJeFallback.EntryNumber);
                                }
                            }

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

        // ═══════ القيود المحاسبية — معطّلة هنا ═══════
        // القيود تُنشأ عند تفعيل الاشتراك في SubscriptionLogs/FtthAccounting
        // لمنع التسجيل المزدوج

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
    public async Task<IActionResult> GetStatistics(
        [FromQuery] Guid? companyId = null,
        [FromQuery] string? department = null,
        [FromQuery] string? technician = null)
    {
        var query = _unitOfWork.ServiceRequests.AsQueryable();
        if (companyId.HasValue)
            query = query.Where(r => r.CompanyId == companyId);
        if (!string.IsNullOrEmpty(department))
        {
            var depts = department.Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
            query = query.Where(r => r.Details != null && depts.Any(d => r.Details.Contains(d)));
        }
        if (!string.IsNullOrEmpty(technician))
            query = query.Where(r => r.Details != null && r.Details.Contains(technician));

        var stats = new
        {
            Total = await query.CountAsync(),
            Pending = await query.CountAsync(r => r.Status == ServiceRequestStatus.Pending),
            Reviewing = await query.CountAsync(r => r.Status == ServiceRequestStatus.Reviewing),
            Approved = await query.CountAsync(r => r.Status == ServiceRequestStatus.Approved),
            Assigned = await query.CountAsync(r => r.Status == ServiceRequestStatus.Assigned),
            InProgress = await query.CountAsync(r => r.Status == ServiceRequestStatus.InProgress),
            Completed = await query.CountAsync(r => r.Status == ServiceRequestStatus.Completed),
            Cancelled = await query.CountAsync(r => r.Status == ServiceRequestStatus.Cancelled),
            Rejected = await query.CountAsync(r => r.Status == ServiceRequestStatus.Rejected),
            OnHold = await query.CountAsync(r => r.Status == ServiceRequestStatus.OnHold),
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
    [Authorize]
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
            // التحقق من عدم وجود مهمة مكررة لنفس رقم الهاتف ونفس النوع في نفس اليوم
            // مهمة "تركيب" لا تمنع "شراء اشتراك" — فقط نفس النوع يُمنع
            if (!string.IsNullOrWhiteSpace(dto.CustomerPhone))
            {
                var todayUtc = DateTime.UtcNow.Date;
                var taskType = dto.TaskType ?? "";
                var duplicate = await _unitOfWork.ServiceRequests.FirstOrDefaultAsync(r =>
                    r.ContactPhone == dto.CustomerPhone &&
                    r.CreatedAt >= todayUtc &&
                    r.Status != ServiceRequestStatus.Cancelled &&
                    r.Details != null && r.Details.Contains(taskType));

                if (duplicate != null)
                {
                    return Conflict(new
                    {
                        success = false,
                        message = $"توجد مهمة '{taskType}' اليوم لنفس الرقم ({dto.CustomerPhone}) — رقم الطلب: {duplicate.RequestNumber}",
                        existingRequestNumber = duplicate.RequestNumber,
                        existingRequestId = duplicate.Id
                    });
                }
            }

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

            // جلب اسم المستخدم الذي أنشأ المهمة
            var creatorId = GetCurrentUserId();
            var creator = creatorId != Guid.Empty
                ? await _unitOfWork.Users.GetByIdAsync(creatorId)
                : null;

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
                ["createdByName"] = creator?.FullName ?? "غير معروف",
                ["createdById"] = creatorId != Guid.Empty ? creatorId.ToString() : null,
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
                Details = JsonSerializer.Serialize(details, new JsonSerializerOptions { Encoder = System.Text.Encodings.Web.JavaScriptEncoder.UnsafeRelaxedJsonEscaping }),
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

        request.Details = JsonSerializer.Serialize(details, new JsonSerializerOptions { Encoder = System.Text.Encodings.Web.JavaScriptEncoder.UnsafeRelaxedJsonEscaping });
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
    /// تعديل بيانات المهمة (بدون تغيير الحالة تلقائياً)
    /// </summary>
    [HttpPatch("{id:guid}/update-task")]
    [Authorize(Policy = "TechnicianOrAbove")]
    public async Task<IActionResult> UpdateTask(Guid id, [FromBody] UpdateTaskDto dto)
    {
        var request = await _unitOfWork.ServiceRequests.GetByIdAsync(id);
        if (request == null)
            return NotFound(new { success = false, message = "الطلب غير موجود" });

        // تحديث Details JSON
        var details = new Dictionary<string, object?>();
        if (!string.IsNullOrEmpty(request.Details))
        {
            try
            {
                details = JsonSerializer.Deserialize<Dictionary<string, object?>>(request.Details) ?? new();
            }
            catch { details = new(); }
        }

        if (dto.Department != null) details["department"] = dto.Department;
        if (dto.Leader != null) details["leader"] = dto.Leader;
        if (dto.Technician != null) details["technician"] = dto.Technician;
        if (dto.TechnicianPhone != null) details["technicianPhone"] = dto.TechnicianPhone;
        if (dto.FBG != null) details["fbg"] = dto.FBG;
        if (dto.FAT != null) details["fat"] = dto.FAT;
        if (dto.Notes != null) details["notes"] = dto.Notes;
        if (dto.Summary != null) details["summary"] = dto.Summary;
        if (dto.Priority != null) details["priority"] = dto.Priority;

        // تحديث الحقول المباشرة
        if (dto.CustomerName != null) details["customerName"] = dto.CustomerName;
        if (dto.CustomerPhone != null) { details["customerPhone"] = dto.CustomerPhone; request.ContactPhone = dto.CustomerPhone; }
        if (dto.Location != null) request.Address = dto.Location;
        if (dto.Amount.HasValue) request.FinalCost = dto.Amount.Value;

        // تحديث الحالة إن أُرسلت
        var oldStatus = request.Status;
        if (!string.IsNullOrEmpty(dto.Status) && Enum.TryParse<ServiceRequestStatus>(dto.Status, true, out var newStatus) && newStatus != oldStatus)
        {
            if (!IsValidStatusTransition(oldStatus, newStatus))
            {
                return BadRequest(new { success = false, message = $"لا يمكن الانتقال من '{oldStatus}' إلى '{newStatus}'" });
            }
            request.Status = newStatus;
            request.StatusNote = dto.Notes;

            switch (newStatus)
            {
                case ServiceRequestStatus.Reviewing: request.ReviewedAt = DateTime.UtcNow; break;
                case ServiceRequestStatus.InProgress: request.StartedAt = DateTime.UtcNow; break;
                case ServiceRequestStatus.Completed: request.CompletedAt = DateTime.UtcNow; break;
                case ServiceRequestStatus.Cancelled: request.CancelledAt = DateTime.UtcNow; break;
            }

            var history = new ServiceRequestStatusHistory
            {
                ServiceRequestId = id,
                FromStatus = oldStatus,
                ToStatus = newStatus,
                Note = dto.Notes ?? "تعديل المهمة",
                ChangedById = GetCurrentUserId(),
                CreatedAt = DateTime.UtcNow
            };
            await _unitOfWork.ServiceRequestStatusHistories.AddAsync(history);
        }

        // تحديث الفني
        if (!string.IsNullOrEmpty(dto.Technician))
        {
            var techUser = await _unitOfWork.Users.AsQueryable()
                .FirstOrDefaultAsync(u => u.FullName == dto.Technician && !u.IsDeleted);
            if (techUser != null)
                request.TechnicianId = techUser.Id;
        }

        request.Details = JsonSerializer.Serialize(details, new JsonSerializerOptions { Encoder = System.Text.Encodings.Web.JavaScriptEncoder.UnsafeRelaxedJsonEscaping });
        request.UpdatedAt = DateTime.UtcNow;

        _unitOfWork.ServiceRequests.Update(request);
        await _unitOfWork.SaveChangesAsync();

        _logger.LogInformation("تم تعديل المهمة {Id}", id);
        return Ok(new { success = true, message = "تم تعديل المهمة بنجاح" });
    }

    /// <summary>
    /// بيانات القوائم المنسدلة للمهام (الأقسام، الفنيين، إلخ)
    /// </summary>
    [HttpGet("task-lookup")]
    [Authorize(Policy = "TechnicianOrAbove")]
    public async Task<IActionResult> GetTaskLookupData()
    {
        // جلب companyId من التوكن
        var companyIdClaim = User.FindFirst("company_id")?.Value;
        Guid? companyId = null;
        if (!string.IsNullOrEmpty(companyIdClaim) && Guid.TryParse(companyIdClaim, out var parsedId))
            companyId = parsedId;

        // جلب الأقسام من قاعدة البيانات إن وجدت
        var dbDepartments = companyId.HasValue
            ? await _unitOfWork.Departments.AsQueryable()
                .Where(d => d.CompanyId == companyId.Value && d.IsActive)
                .OrderBy(d => d.SortOrder).ThenBy(d => d.NameAr)
                .Include(d => d.Tasks.Where(t => !t.IsDeleted && t.IsActive))
                .ToListAsync()
            : new List<Department>();

        object departments;
        object departmentTasks;
        object taskTypes;

        if (dbDepartments.Count > 0)
        {
            // استخدام الأقسام والمهام من قاعدة البيانات
            departments = dbDepartments.Select(d => new { id = d.Id.ToString(), nameAr = d.NameAr, name = d.Name ?? d.NameAr }).ToArray();

            var deptTasksDict = new Dictionary<string, string[]>();
            var allTaskTypes = new HashSet<string>();
            foreach (var dept in dbDepartments)
            {
                var tasks = dept.Tasks
                    .OrderBy(t => t.SortOrder).ThenBy(t => t.NameAr)
                    .Select(t => t.NameAr).ToArray();
                if (tasks.Length > 0)
                {
                    deptTasksDict[dept.NameAr] = tasks;
                    foreach (var t in tasks) allTaskTypes.Add(t);
                }
            }
            departmentTasks = deptTasksDict;
            taskTypes = allTaskTypes.ToArray();
        }
        else
        {
            // القيم الافتراضية إذا لم توجد أقسام في قاعدة البيانات
            departments = new[]
            {
                new { id = "maintenance", nameAr = "الصيانة", name = "Maintenance" },
                new { id = "accounts", nameAr = "الحسابات", name = "Accounts" },
                new { id = "technicians", nameAr = "الفنيين", name = "Technicians" },
                new { id = "agents", nameAr = "الوكلاء", name = "Agents" },
                new { id = "communications", nameAr = "الاتصالات", name = "Communications" },
                new { id = "welding", nameAr = "اللحام", name = "Welding" }
            };
            departmentTasks = new Dictionary<string, string[]>
            {
                ["الصيانة"] = new[] { "تركيب", "إصلاح", "صيانة دورية", "فحص", "استبدال", "طوارئ" },
                ["الحسابات"] = new[] { "شراء اشتراك", "تجديد اشتراك", "استشارة", "مراجعة حساب" },
                ["الفنيين"] = new[] { "تركيب", "إصلاح", "صيانة دورية", "فحص", "استبدال", "طوارئ" },
                ["الوكلاء"] = new[] { "شراء اشتراك", "تجديد اشتراك", "استشارة" },
                ["الاتصالات"] = new[] { "إصلاح", "فحص", "صيانة دورية", "طوارئ" },
                ["اللحام"] = new[] { "لحام ألياف", "إصلاح كابل", "تمديد", "فحص" }
            };
            taskTypes = new[]
            {
                "شراء اشتراك", "تركيب", "إصلاح", "صيانة دورية",
                "فحص", "استبدال", "طوارئ", "استشارة",
                "تجديد اشتراك", "مراجعة حساب", "لحام ألياف", "إصلاح كابل", "تمديد"
            };
        }

        var data = new
        {
            departments,
            priorities = new[]
            {
                new { value = 1, label = "عاجل", color = "#EF4444" },
                new { value = 2, label = "عالي", color = "#F59E0B" },
                new { value = 3, label = "متوسط", color = "#3B82F6" },
                new { value = 4, label = "منخفض", color = "#10B981" }
            },
            departmentTasks,
            taskTypes,
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
            fbgOptions = await _unitOfWork.ZoneStatistics.AsQueryable()
                .Where(z => !string.IsNullOrEmpty(z.ZoneName))
                .OrderBy(z => z.ZoneName)
                .Select(z => z.ZoneName)
                .Distinct()
                .ToListAsync()
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

            // تصفية حسب القسم إن وُجد — تدعم القسم القديم + UserDepartments الجديد
            if (!string.IsNullOrWhiteSpace(department))
            {
                var deptUserIds = await _unitOfWork.UserDepartments.AsQueryable()
                    .Include(ud => ud.Department)
                    .Where(ud => ud.Department != null && ud.Department.NameAr == department)
                    .Select(ud => ud.UserId)
                    .ToListAsync();

                query = query.Where(u =>
                    u.Department == department ||
                    string.IsNullOrEmpty(u.Department) ||
                    deptUserIds.Contains(u.Id));
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

            // القادة: جلب من كل الأقسام (القائد يشرف على عدة أقسام)
            var allStaffForLeaders = await _unitOfWork.Users.AsQueryable()
                .Where(u => u.Role == UserRole.TechnicalLeader || u.Role == UserRole.Manager)
                .Select(u => new { u.Id, Name = u.FullName, u.PhoneNumber, u.Department, Role = u.Role.ToString(), u.EmployeeCode })
                .OrderBy(u => u.Name)
                .ToListAsync();

            var leaders = allStaffForLeaders.ToList();

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

    /// جلب أقسام المستخدم الحالي (للليدر/المدير الذي يشرف على أقسام متعددة)
    [HttpGet("my-departments")]
    [Authorize(Policy = "TechnicianOrAbove")]
    public async Task<IActionResult> GetMyDepartments()
    {
        try
        {
            var userId = GetCurrentUserId();
            if (userId == Guid.Empty)
                return Unauthorized(new { success = false, message = "غير مصرح" });

            var user = await _unitOfWork.Users.GetByIdAsync(userId);
            if (user == null)
                return NotFound(new { success = false, message = "المستخدم غير موجود" });

            // جلب الأقسام من UserDepartments
            var userDepts = await _unitOfWork.UserDepartments.AsQueryable()
                .Where(ud => ud.UserId == userId)
                .Include(ud => ud.Department)
                .OrderByDescending(ud => ud.IsPrimary)
                .ThenBy(ud => ud.Department.NameAr)
                .Select(ud => new
                {
                    ud.Department.Id,
                    Name = ud.Department.NameAr ?? ud.Department.Name,
                    ud.IsPrimary,
                })
                .ToListAsync();

            // إذا لم يكن لديه أقسام في الجدول الجديد، أرجع القسم القديم
            if (!userDepts.Any() && !string.IsNullOrEmpty(user.Department))
            {
                return Ok(new
                {
                    success = true,
                    data = new[]
                    {
                        new { Id = 0, Name = user.Department, IsPrimary = true }
                    }
                });
            }

            return Ok(new { success = true, data = userDepts });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في جلب أقسام المستخدم");
            return StatusCode(500, new { success = false, message = "خطأ في جلب الأقسام" });
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
        [ServiceRequestStatus.Completed] = new[] { ServiceRequestStatus.Pending, ServiceRequestStatus.Reviewing, ServiceRequestStatus.Assigned, ServiceRequestStatus.InProgress, ServiceRequestStatus.OnHold, ServiceRequestStatus.Cancelled },
        [ServiceRequestStatus.Cancelled] = new[] { ServiceRequestStatus.Pending, ServiceRequestStatus.Reviewing, ServiceRequestStatus.Assigned, ServiceRequestStatus.InProgress, ServiceRequestStatus.OnHold, ServiceRequestStatus.Completed },
        [ServiceRequestStatus.Rejected] = new[] { ServiceRequestStatus.Pending, ServiceRequestStatus.Reviewing, ServiceRequestStatus.Assigned, ServiceRequestStatus.InProgress, ServiceRequestStatus.OnHold },
    };

    private static bool IsValidStatusTransition(ServiceRequestStatus from, ServiceRequestStatus to)
    {
        // السماح بجميع الانتقالات بدون قيود
        return true;
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

        // إشعار لمنشئ المهمة عند الإكمال أو الإلغاء (من Details JSON)
        if (newStatus == ServiceRequestStatus.Completed || newStatus == ServiceRequestStatus.Cancelled)
        {
            try
            {
                if (!string.IsNullOrEmpty(request.Details))
                {
                    var details = System.Text.Json.JsonSerializer.Deserialize<Dictionary<string, System.Text.Json.JsonElement>>(request.Details);
                    if (details != null && details.TryGetValue("createdById", out var creatorIdEl))
                    {
                        var creatorIdStr = creatorIdEl.GetString();
                        if (!string.IsNullOrEmpty(creatorIdStr) && Guid.TryParse(creatorIdStr, out var creatorId))
                        {
                            // لا ترسل إشعار مزدوج إذا كان المنشئ هو نفسه المعيّن أو الفني
                            if (creatorId != request.AssignedToId && creatorId != request.TechnicianId)
                            {
                                var creatorName = details.TryGetValue("createdByName", out var nameEl) ? nameEl.GetString() : null;
                                var taskType = details.TryGetValue("taskType", out var typeEl) ? typeEl.GetString() : null;
                                var statusMsg = newStatus == ServiceRequestStatus.Completed ? "تم إنهاء" : "تم إلغاء";

                                notifications.Add(new Notification
                                {
                                    UserId = creatorId,
                                    Title = $"{statusMsg} المهمة {request.RequestNumber}",
                                    TitleAr = $"{statusMsg} المهمة {request.RequestNumber}",
                                    Body = $"{statusMsg} المهمة ({taskType ?? "مهمة"}) التي أنشأتها — الحالة: {statusAr}",
                                    BodyAr = $"{statusMsg} المهمة ({taskType ?? "مهمة"}) التي أنشأتها — الحالة: {statusAr}",
                                    Type = NotificationType.RequestStatusUpdate,
                                    ReferenceId = request.Id,
                                    ReferenceType = "ServiceRequest",
                                    CreatedAt = DateTime.UtcNow
                                });
                            }
                        }
                    }
                }
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "فشل استخراج createdById من Details للطلب {RequestNumber}", request.RequestNumber);
            }
        }

        foreach (var n in notifications)
        {
            await _unitOfWork.Notifications.AddAsync(n);
        }

        // Send FCM push notifications for status changes
        if (notifications.Count > 0)
        {
            var fcmData = new Dictionary<string, string>
            {
                ["type"] = "status_changed",
                ["requestId"] = request.Id.ToString(),
                ["requestNumber"] = request.RequestNumber ?? "",
                ["newStatus"] = newStatus.ToString()
            };

            var userIds = notifications.Select(n => n.UserId).Distinct().ToList();
            _ = _fcmService.SendToUsersAsync(userIds, $"تحديث طلب {request.RequestNumber}", $"تم تغيير حالة الطلب إلى: {statusAr}", fcmData);
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
        var title = "تم تعيينك لمهمة جديدة";
        var body = $"تم تعيينك للعمل على الطلب {request.RequestNumber} - {request.ContactPhone}";

        await _unitOfWork.Notifications.AddAsync(new Notification
        {
            UserId = technicianUserId,
            Title = title,
            TitleAr = title,
            Body = body,
            BodyAr = body,
            Type = NotificationType.RequestAssigned,
            ReferenceId = request.Id,
            ReferenceType = "ServiceRequest",
            CreatedAt = DateTime.UtcNow
        });

        // Send FCM push notification
        _ = _fcmService.SendToUserAsync(technicianUserId, title, body, new Dictionary<string, string>
        {
            ["type"] = "task_assigned",
            ["requestId"] = request.Id.ToString(),
            ["requestNumber"] = request.RequestNumber ?? ""
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
/// تعديل بيانات المهمة
/// </summary>
public class UpdateTaskDto
{
    public string? Status { get; set; }
    public string? Department { get; set; }
    public string? Leader { get; set; }
    public string? Technician { get; set; }
    public string? TechnicianPhone { get; set; }
    public string? CustomerName { get; set; }
    public string? CustomerPhone { get; set; }
    public string? FBG { get; set; }
    public string? FAT { get; set; }
    public string? Location { get; set; }
    public string? Notes { get; set; }
    public string? Summary { get; set; }
    public string? Priority { get; set; }
    public decimal? Amount { get; set; }
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

        if (existing != null)
        {
            // تحديث الاسم إذا تغيّر (مثلاً إزالة بادئة "ذمة وكيل")
            if (existing.Name != personName)
            {
                existing.Name = personName;
                unitOfWork.Accounts.Update(existing);
            }
            return existing;
        }

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

    public static async Task<Guid> CreateAndPostJournalEntry(
        IUnitOfWork unitOfWork,
        Guid companyId,
        Guid createdById,
        string description,
        JournalReferenceType referenceType,
        string? referenceId,
        List<(Guid AccountId, decimal DebitAmount, decimal CreditAmount, string? LineDescription)> lines)
    {
        var year = DateTime.UtcNow.Year;
        // IgnoreQueryFilters لعدّ جميع القيود بما فيها المحذوفة ناعمياً لتجنب تعارض الأرقام
        var count = await unitOfWork.JournalEntries.AsQueryable()
            .IgnoreQueryFilters()
            .CountAsync(j => j.CompanyId == companyId && j.EntryDate.Year == year);
        var entryNumber = $"JE-{year}-{(count + 1):D4}";

        var entryId = Guid.NewGuid();
        var entry = new JournalEntry
        {
            Id = entryId,
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

        return entryId;
    }
}

#endregion
