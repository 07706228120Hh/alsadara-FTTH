using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Sadara.API.Authorization;
using Sadara.Application.Interfaces;
using Sadara.Domain.Entities;
using Sadara.Domain.Enums;
using Sadara.Infrastructure.Data;

namespace Sadara.API.Controllers;

/// <summary>
/// سجل العقارات المستقل (Property Registry) — نواة محايدة الخدمة محورها QR دائم.
///
/// العقار كيان أول: له QrToken دائم + NPN وطني ذرّي لكل محافظة + موقع + صورة. يُربط به
/// المواطن (<see cref="PropertyResident"/>) ثم خدمات متعدّدة (<see cref="PropertyService"/>)
/// — إنترنت الآن، ماستر/أي خدمة مستقبلاً. مسح الـQR → حلّ العقار + المواطنون + الخدمات حيّاً.
///
/// العزل ثلاثي: شركة (<c>CompanyId</c> من التوكن) + منشئ (<c>CreatedByUserId</c>) + صلاحية
/// <c>property_registry</c> (النظام الثاني، failClosed). المرحلة 1: العقار + NPN + QR (المواطن
/// والخدمات في المراحل التالية؛ كياناتها معرّفة ونقاطها تُضاف لاحقاً).
/// </summary>
[ApiController]
[Route("api/properties")]
[Authorize]
public class PropertiesController : ControllerBase
{
    private readonly SadaraDbContext _db;
    private readonly ICurrentTenant _tenant;
    private readonly ILogger<PropertiesController> _logger;
    private readonly IWebHostEnvironment _env;

    public PropertiesController(
        SadaraDbContext db,
        ICurrentTenant tenant,
        ILogger<PropertiesController> logger,
        IWebHostEnvironment env)
    {
        _db = db;
        _tenant = tenant;
        _logger = logger;
        _env = env;
    }

    // ============ حرّاس النطاق (نفس نمط SasAgentController) ============

    private Guid GetCurrentUserId()
    {
        var userIdClaim = User.FindFirst(System.Security.Claims.ClaimTypes.NameIdentifier)?.Value
                       ?? User.FindFirst("sub")?.Value;
        if (!string.IsNullOrEmpty(userIdClaim) && Guid.TryParse(userIdClaim, out var userId))
            return userId;
        return Guid.Empty;
    }

    private bool TryResolveScope(out Guid companyId, out Guid userId, out IActionResult? denied)
    {
        companyId = Guid.Empty;
        userId = Guid.Empty;
        denied = null;
        if (_tenant.CompanyId is not Guid cid || cid == Guid.Empty)
        {
            denied = Forbid();
            return false;
        }
        var uid = GetCurrentUserId();
        if (uid == Guid.Empty)
        {
            denied = Forbid();
            return false;
        }
        companyId = cid;
        userId = uid;
        return true;
    }

    // ============ العقارات ============

    /// <summary>قائمة عقارات الشركة (بحث/تصفية/ترقيم).</summary>
    [HttpGet]
    [RequirePermission("property_registry", "view", PermissionSystem.Second, failClosed: true)]
    public async Task<IActionResult> GetProperties(
        [FromQuery] string? q,
        [FromQuery] PropertyType? propertyType,
        [FromQuery] PropertyOwnership? ownership,
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 30,
        CancellationToken ct = default)
    {
        if (!TryResolveScope(out var companyId, out _, out var denied)) return denied!;
        page = Math.Max(1, page);
        pageSize = Math.Clamp(pageSize, 1, 200);

        var query = _db.Properties.AsNoTracking().Where(x => x.CompanyId == companyId);
        if (propertyType.HasValue) query = query.Where(x => x.PropertyType == propertyType.Value);
        if (ownership.HasValue) query = query.Where(x => x.Ownership == ownership.Value);
        if (!string.IsNullOrWhiteSpace(q))
        {
            var s = q.Trim();
            query = query.Where(x =>
                x.Npn.Contains(s) || x.NpnDisplay.Contains(s) ||
                (x.IqPin != null && x.IqPin.Contains(s)) ||
                x.Governorate.Contains(s) || x.Area.Contains(s) || x.District.Contains(s) ||
                (x.Landmark != null && x.Landmark.Contains(s)));
        }

        var total = await query.CountAsync(ct);
        var rows = await query
            .OrderByDescending(x => x.CreatedAt)
            .Skip((page - 1) * pageSize).Take(pageSize)
            .Select(x => ToDto(x))
            .ToListAsync(ct);

        return Ok(new { success = true, data = rows, total, page, pageSize });
    }

    /// <summary>تفاصيل عقار واحد.</summary>
    [HttpGet("{id:guid}")]
    [RequirePermission("property_registry", "view", PermissionSystem.Second, failClosed: true)]
    public async Task<IActionResult> GetProperty(Guid id, CancellationToken ct)
    {
        if (!TryResolveScope(out var companyId, out _, out var denied)) return denied!;
        var p = await _db.Properties.AsNoTracking()
            .FirstOrDefaultAsync(x => x.Id == id && x.CompanyId == companyId, ct);
        if (p == null) return NotFound(new { success = false, message = "العقار غير موجود" });
        var (residents, services) = await LoadLinksAsync(p.Id, companyId, ct);
        return Ok(new { success = true, data = ToDto(p), residents, services });
    }

    /// <summary>حلّ الـQR الدائم → العقار + ملخّص (المواطنون/الخدمات تُضاف في المراحل التالية).</summary>
    [HttpGet("by-qr/{token}")]
    [RequirePermission("property_registry", "view", PermissionSystem.Second, failClosed: true)]
    public async Task<IActionResult> ResolveByQr(string token, CancellationToken ct)
    {
        if (!TryResolveScope(out var companyId, out _, out var denied)) return denied!;
        var t = (token ?? string.Empty).Trim();
        // دعم تمرير الحمولة الكاملة SADARA|P:<token> أو الرمز وحده.
        var marker = t.IndexOf("P:", StringComparison.Ordinal);
        if (marker >= 0) t = t[(marker + 2)..].Split('|')[0].Trim();
        var p = await _db.Properties.AsNoTracking()
            .FirstOrDefaultAsync(x => x.QrToken == t && x.CompanyId == companyId, ct);
        if (p == null) return NotFound(new { success = false, message = "لا عقار بهذا الرمز" });
        var (residents, services) = await LoadLinksAsync(p.Id, companyId, ct);
        return Ok(new { success = true, data = ToDto(p), residents, services });
    }

    /// <summary>إنشاء عقار: يخصّص NPN ذرّياً لكل محافظة + QrToken دائم + IqPin من الإحداثيات.</summary>
    [HttpPost]
    [RequirePermission("property_registry", "manage", PermissionSystem.Second, failClosed: true)]
    public async Task<IActionResult> CreateProperty([FromBody] PropertyUpsertRequest request, CancellationToken ct)
    {
        if (!TryResolveScope(out var companyId, out var userId, out var denied)) return denied!;
        if (request.GovCode <= 0 || string.IsNullOrWhiteSpace(request.Governorate))
            return BadRequest(new { success = false, message = "المحافظة ورمزها مطلوبان" });

        // تخصيص NPN ذرّي لكل محافظة عبر upsert+increment في عبارة واحدة (آمن تحت التزامن).
        int seq;
        try
        {
            seq = (await _db.Database.SqlQueryRaw<int>(
                "INSERT INTO \"PropertyNpnCounters\" (\"GovCode\",\"LastSeq\") VALUES ({0}, 1) " +
                "ON CONFLICT (\"GovCode\") DO UPDATE SET \"LastSeq\" = \"PropertyNpnCounters\".\"LastSeq\" + 1 " +
                "RETURNING \"LastSeq\" AS \"Value\"",
                request.GovCode).ToListAsync(ct)).First();
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "فشل تخصيص NPN للمحافظة {Gov}", request.GovCode);
            return StatusCode(500, new { success = false, message = "تعذّر تخصيص رقم العقار" });
        }

        var (iqPin, iqPinDisplay) = BuildIqPin(request.Latitude, request.Longitude);
        var p = new Property
        {
            Id = Guid.NewGuid(),
            CompanyId = companyId,
            CreatedByUserId = userId,
            QrToken = Guid.NewGuid().ToString("N"), // دائم فريد
            Npn = $"{request.GovCode:D2}{seq:D9}",
            NpnDisplay = $"{request.GovCode:D2}-{seq:D9}",
            IqPin = iqPin,
            IqPinDisplay = iqPinDisplay,
            GovCode = request.GovCode,
            Governorate = request.Governorate.Trim(),
            Area = (request.Area ?? string.Empty).Trim(),
            Address2 = Nullify(request.Address2),
            Address3 = Nullify(request.Address3),
            OwnerName = Nullify(request.OwnerName),
            OwnerPhone = Nullify(request.OwnerPhone),
            District = (request.District ?? string.Empty).Trim(),
            Landmark = Nullify(request.Landmark),
            AddressDetails = Nullify(request.AddressDetails),
            Latitude = request.Latitude,
            Longitude = request.Longitude,
            PropertyType = request.PropertyType ?? PropertyType.Residential,
            Ownership = request.Ownership ?? PropertyOwnership.Owned,
            Notes = Nullify(request.Notes)
        };
        await _db.Properties.AddAsync(p, ct);
        await _db.SaveChangesAsync(ct);
        return Ok(new { success = true, data = ToDto(p), message = "تم تسجيل العقار" });
    }

    /// <summary>تعديل عقار (NPN/QrToken ثابتان؛ يُعاد حساب IqPin عند تغيّر الموقع).</summary>
    [HttpPut("{id:guid}")]
    [RequirePermission("property_registry", "manage", PermissionSystem.Second, failClosed: true)]
    public async Task<IActionResult> UpdateProperty(Guid id, [FromBody] PropertyUpsertRequest request, CancellationToken ct)
    {
        if (!TryResolveScope(out var companyId, out _, out var denied)) return denied!;
        var p = await _db.Properties.FirstOrDefaultAsync(x => x.Id == id && x.CompanyId == companyId, ct);
        if (p == null) return NotFound(new { success = false, message = "العقار غير موجود" });

        if (!string.IsNullOrWhiteSpace(request.Governorate)) p.Governorate = request.Governorate.Trim();
        if (request.Area != null) p.Area = request.Area.Trim();
        if (request.Address2 != null) p.Address2 = Nullify(request.Address2);
        if (request.Address3 != null) p.Address3 = Nullify(request.Address3);
        if (request.OwnerName != null) p.OwnerName = Nullify(request.OwnerName);
        if (request.OwnerPhone != null) p.OwnerPhone = Nullify(request.OwnerPhone);
        if (request.District != null) p.District = request.District.Trim();
        p.Landmark = Nullify(request.Landmark) ?? p.Landmark;
        p.AddressDetails = Nullify(request.AddressDetails) ?? p.AddressDetails;
        if (request.PropertyType.HasValue) p.PropertyType = request.PropertyType.Value;
        if (request.Ownership.HasValue) p.Ownership = request.Ownership.Value;
        p.Notes = Nullify(request.Notes) ?? p.Notes;

        // عند تغيّر الموقع: أعِد حساب IqPin (NPN يبقى ثابتاً).
        if (request.Latitude.HasValue && request.Longitude.HasValue &&
            (request.Latitude != p.Latitude || request.Longitude != p.Longitude))
        {
            p.Latitude = request.Latitude;
            p.Longitude = request.Longitude;
            (p.IqPin, p.IqPinDisplay) = BuildIqPin(p.Latitude, p.Longitude);
        }
        p.UpdatedAt = DateTime.UtcNow;
        _db.Properties.Update(p);
        await _db.SaveChangesAsync(ct);
        return Ok(new { success = true, data = ToDto(p), message = "تم تحديث العقار" });
    }

    /// <summary>حذف عقار (ناعم).</summary>
    [HttpDelete("{id:guid}")]
    [RequirePermission("property_registry", "manage", PermissionSystem.Second, failClosed: true)]
    public async Task<IActionResult> DeleteProperty(Guid id, CancellationToken ct)
    {
        if (!TryResolveScope(out var companyId, out _, out var denied)) return denied!;
        var p = await _db.Properties.FirstOrDefaultAsync(x => x.Id == id && x.CompanyId == companyId, ct);
        if (p == null) return NotFound(new { success = false, message = "العقار غير موجود" });
        p.IsDeleted = true;
        p.DeletedAt = DateTime.UtcNow;
        _db.Properties.Update(p);
        await _db.SaveChangesAsync(ct);
        return Ok(new { success = true, message = "تم حذف العقار" });
    }

    // ============ المواطنون المرتبطون (إعادة استخدام Citizen) ============

    /// <summary>بحث عن مواطني الشركة لربطهم بعقار (للمنتقي).</summary>
    [HttpGet("citizens")]
    [RequirePermission("property_registry", "view", PermissionSystem.Second, failClosed: true)]
    public async Task<IActionResult> SearchCitizens([FromQuery] string? q, CancellationToken ct)
    {
        if (!TryResolveScope(out var companyId, out _, out var denied)) return denied!;
        var query = _db.Citizens.AsNoTracking().Where(c => c.CompanyId == companyId && !c.IsDeleted);
        if (!string.IsNullOrWhiteSpace(q))
        {
            var s = q.Trim();
            query = query.Where(c => c.FullName.Contains(s) || c.PhoneNumber.Contains(s));
        }
        var rows = await query.OrderBy(c => c.FullName).Take(30)
            .Select(c => new { id = c.Id, name = c.FullName, phone = c.PhoneNumber, district = c.District })
            .ToListAsync(ct);
        return Ok(new { success = true, data = rows });
    }

    /// <summary>ربط مواطن بعقار (مالك/مستأجر/ساكن).</summary>
    [HttpPost("{id:guid}/residents")]
    [RequirePermission("property_registry", "manage", PermissionSystem.Second, failClosed: true)]
    public async Task<IActionResult> LinkResident(Guid id, [FromBody] LinkResidentRequest request, CancellationToken ct)
    {
        if (!TryResolveScope(out var companyId, out _, out var denied)) return denied!;
        if (await GetOwnedPropertyAsync(id, companyId, ct) == null)
            return NotFound(new { success = false, message = "العقار غير موجود" });
        // تحقّق أن المواطن ضمن الشركة (عزل).
        var citizenOk = await _db.Citizens.AsNoTracking()
            .AnyAsync(c => c.Id == request.CitizenId && c.CompanyId == companyId && !c.IsDeleted, ct);
        if (!citizenOk) return BadRequest(new { success = false, message = "المواطن غير موجود في شركتك" });
        // منع التكرار.
        var exists = await _db.PropertyResidents.AsNoTracking()
            .AnyAsync(r => r.PropertyId == id && r.CitizenId == request.CitizenId && !r.IsDeleted, ct);
        if (exists) return Conflict(new { success = false, message = "المواطن مرتبط بالعقار مسبقاً" });

        var res = new PropertyResident
        {
            Id = Guid.NewGuid(),
            CompanyId = companyId,
            PropertyId = id,
            CitizenId = request.CitizenId,
            Relationship = request.Relationship ?? ResidentRelationship.Owner,
            IsPrimary = request.IsPrimary ?? false
        };
        await _db.PropertyResidents.AddAsync(res, ct);
        await _db.SaveChangesAsync(ct);
        return Ok(new { success = true, id = res.Id, message = "تم ربط المواطن" });
    }

    /// <summary>فكّ ربط مواطن عن عقار (ناعم).</summary>
    [HttpDelete("{id:guid}/residents/{residentId:guid}")]
    [RequirePermission("property_registry", "manage", PermissionSystem.Second, failClosed: true)]
    public async Task<IActionResult> UnlinkResident(Guid id, Guid residentId, CancellationToken ct)
    {
        if (!TryResolveScope(out var companyId, out _, out var denied)) return denied!;
        var r = await _db.PropertyResidents
            .FirstOrDefaultAsync(x => x.Id == residentId && x.PropertyId == id && x.CompanyId == companyId, ct);
        if (r == null) return NotFound(new { success = false, message = "الربط غير موجود" });
        r.IsDeleted = true; r.DeletedAt = DateTime.UtcNow;
        _db.PropertyResidents.Update(r);
        await _db.SaveChangesAsync(ct);
        return Ok(new { success = true, message = "تم فكّ الربط" });
    }

    // ============ خدمات العقار (موصّل عام) ============

    /// <summary>إضافة خدمة لعقار (إنترنت/ماستر/…).</summary>
    [HttpPost("{id:guid}/services")]
    [RequirePermission("property_registry", "manage", PermissionSystem.Second, failClosed: true)]
    public async Task<IActionResult> AddService(Guid id, [FromBody] UpsertServiceRequest request, CancellationToken ct)
    {
        if (!TryResolveScope(out var companyId, out _, out var denied)) return denied!;
        if (await GetOwnedPropertyAsync(id, companyId, ct) == null)
            return NotFound(new { success = false, message = "العقار غير موجود" });

        var svc = new PropertyService
        {
            Id = Guid.NewGuid(),
            CompanyId = companyId,
            PropertyId = id,
            ServiceType = request.ServiceType ?? PropertyServiceType.Internet,
            ProviderType = request.ProviderType ?? PropertyServiceProvider.Sas,
            ProviderRefId = Nullify(request.ProviderRefId),
            SubscriberRef = Nullify(request.SubscriberRef),
            Status = request.Status ?? PropertyServiceStatus.Active,
            StartDate = request.StartDate,
            EndDate = request.EndDate,
            Notes = Nullify(request.Notes),
            AgentName = Nullify(request.AgentName),
            AccountNumber = Nullify(request.AccountNumber),
            MasterPhotoPath = Nullify(request.MasterPhotoPath),
            CivilIdPhotoPath = Nullify(request.CivilIdPhotoPath)
        };
        await _db.PropertyServices.AddAsync(svc, ct);
        await _db.SaveChangesAsync(ct);
        return Ok(new { success = true, id = svc.Id, message = "تمت إضافة الخدمة" });
    }

    /// <summary>تعديل خدمة عقار (الحالة/التواريخ/المرجع).</summary>
    [HttpPut("{id:guid}/services/{serviceId:guid}")]
    [RequirePermission("property_registry", "manage", PermissionSystem.Second, failClosed: true)]
    public async Task<IActionResult> UpdateService(Guid id, Guid serviceId, [FromBody] UpsertServiceRequest request, CancellationToken ct)
    {
        if (!TryResolveScope(out var companyId, out _, out var denied)) return denied!;
        var svc = await _db.PropertyServices
            .FirstOrDefaultAsync(x => x.Id == serviceId && x.PropertyId == id && x.CompanyId == companyId, ct);
        if (svc == null) return NotFound(new { success = false, message = "الخدمة غير موجودة" });
        if (request.ServiceType.HasValue) svc.ServiceType = request.ServiceType.Value;
        if (request.ProviderType.HasValue) svc.ProviderType = request.ProviderType.Value;
        if (request.ProviderRefId != null) svc.ProviderRefId = Nullify(request.ProviderRefId);
        if (request.SubscriberRef != null) svc.SubscriberRef = Nullify(request.SubscriberRef);
        if (request.Status.HasValue) svc.Status = request.Status.Value;
        if (request.StartDate.HasValue) svc.StartDate = request.StartDate;
        if (request.EndDate.HasValue) svc.EndDate = request.EndDate;
        if (request.Notes != null) svc.Notes = Nullify(request.Notes);
        if (request.AgentName != null) svc.AgentName = Nullify(request.AgentName);
        if (request.AccountNumber != null) svc.AccountNumber = Nullify(request.AccountNumber);
        if (request.MasterPhotoPath != null) svc.MasterPhotoPath = Nullify(request.MasterPhotoPath);
        if (request.CivilIdPhotoPath != null) svc.CivilIdPhotoPath = Nullify(request.CivilIdPhotoPath);
        svc.UpdatedAt = DateTime.UtcNow;
        _db.PropertyServices.Update(svc);
        await _db.SaveChangesAsync(ct);
        return Ok(new { success = true, message = "تم تحديث الخدمة" });
    }

    /// <summary>إزالة خدمة عقار (ناعم).</summary>
    [HttpDelete("{id:guid}/services/{serviceId:guid}")]
    [RequirePermission("property_registry", "manage", PermissionSystem.Second, failClosed: true)]
    public async Task<IActionResult> RemoveService(Guid id, Guid serviceId, CancellationToken ct)
    {
        if (!TryResolveScope(out var companyId, out _, out var denied)) return denied!;
        var svc = await _db.PropertyServices
            .FirstOrDefaultAsync(x => x.Id == serviceId && x.PropertyId == id && x.CompanyId == companyId, ct);
        if (svc == null) return NotFound(new { success = false, message = "الخدمة غير موجودة" });
        svc.IsDeleted = true; svc.DeletedAt = DateTime.UtcNow;
        _db.PropertyServices.Update(svc);
        await _db.SaveChangesAsync(ct);
        return Ok(new { success = true, message = "تمت إزالة الخدمة" });
    }

    // ============ ربط المهام (ServiceRequest) — توجيه فني لعقار ============

    /// <summary>مهام العقار: طلبات الخدمة المرتبطة بالعقار (معزولة بالشركة).</summary>
    [HttpGet("{id:guid}/tasks")]
    [RequirePermission("property_registry", "view", PermissionSystem.Second, failClosed: true)]
    public async Task<IActionResult> GetPropertyTasks(Guid id, CancellationToken ct)
    {
        if (!TryResolveScope(out var companyId, out _, out var denied)) return denied!;
        if (await GetOwnedPropertyAsync(id, companyId, ct) == null)
            return NotFound(new { success = false, message = "العقار غير موجود" });

        var rows = await _db.ServiceRequests.AsNoTracking()
            .Where(r => r.PropertyId == id && r.CompanyId == companyId)
            .OrderByDescending(r => r.CreatedAt)
            .Select(r => new
            {
                id = r.Id,
                requestNumber = r.RequestNumber,
                status = r.Status.ToString(),
                department = r.Department,
                technicianName = r.TechnicianName,
                priority = r.Priority,
                address = r.Address,
                area = r.Area,
                contactPhone = r.ContactPhone,
                requestedAt = r.RequestedAt,
                createdAt = r.CreatedAt
            })
            .ToListAsync(ct);
        return Ok(new { success = true, data = rows });
    }

    /// <summary>الخدمات والعمليات المتاحة (لمنتقي «إنشاء مهمة لعقار»).</summary>
    [HttpGet("service-lookups")]
    [RequirePermission("property_registry", "view", PermissionSystem.Second, failClosed: true)]
    public async Task<IActionResult> GetServiceLookups(CancellationToken ct)
    {
        if (!TryResolveScope(out _, out _, out var denied)) return denied!;
        var ops = await _db.ServiceOperations.AsNoTracking()
            .Where(so => so.IsActive && so.Service.IsActive)
            .Select(so => new
            {
                serviceId = so.ServiceId,
                serviceName = so.Service.NameAr,
                operationTypeId = so.OperationTypeId,
                operationName = so.OperationType.NameAr,
                requiresTechnician = so.OperationType.RequiresTechnician
            })
            .ToListAsync(ct);

        var services = ops
            .GroupBy(o => new { o.serviceId, o.serviceName })
            .Select(g => new
            {
                id = g.Key.serviceId,
                nameAr = g.Key.serviceName,
                operations = g.Select(o => new
                {
                    id = o.operationTypeId,
                    nameAr = o.operationName,
                    requiresTechnician = o.requiresTechnician
                }).ToList()
            })
            .ToList();
        return Ok(new { success = true, data = services });
    }

    /// <summary>
    /// إنشاء مهمة (طلب خدمة) مرتبطة بالعقار. يملأ العنوان/المنطقة/الهاتف/المواطن من العقار
    /// وساكنه الأساسي تلقائياً، ويضع <c>PropertyId</c> للربط الدائم.
    /// </summary>
    [HttpPost("{id:guid}/tasks")]
    [RequirePermission("property_registry", "manage", PermissionSystem.Second, failClosed: true)]
    public async Task<IActionResult> CreatePropertyTask(Guid id, [FromBody] CreatePropertyTaskRequest request, CancellationToken ct)
    {
        if (!TryResolveScope(out var companyId, out var userId, out var denied)) return denied!;
        var p = await GetOwnedPropertyAsync(id, companyId, ct);
        if (p == null) return NotFound(new { success = false, message = "العقار غير موجود" });

        // تحقّق أن الخدمة/العملية موجودتان ومفعّلتان (عزل مرجعي).
        var opOk = await _db.ServiceOperations.AsNoTracking()
            .AnyAsync(so => so.ServiceId == request.ServiceId && so.OperationTypeId == request.OperationTypeId
                         && so.IsActive && so.Service.IsActive, ct);
        if (!opOk) return BadRequest(new { success = false, message = "الخدمة أو العملية غير متاحة" });

        // الساكن الأساسي (إن وُجد) لتعبئة المواطن والهاتف.
        var primary = await _db.PropertyResidents.AsNoTracking()
            .Where(r => r.PropertyId == id && r.CompanyId == companyId)
            .OrderByDescending(r => r.IsPrimary)
            .Join(_db.Citizens.AsNoTracking(), r => r.CitizenId, c => c.Id,
                  (r, c) => new { c.Id, c.PhoneNumber })
            .FirstOrDefaultAsync(ct);

        var address = string.Join("، ",
            new[] { p.Governorate, p.Area, p.District, p.Landmark, p.AddressDetails }
            .Where(s => !string.IsNullOrWhiteSpace(s)));

        var req = new ServiceRequest
        {
            Id = Guid.NewGuid(),
            RequestNumber = $"{DateTime.UtcNow:yyMMddHHmm}{Random.Shared.Next(1000, 9999)}",
            ServiceId = request.ServiceId,
            OperationTypeId = request.OperationTypeId,
            CitizenId = primary?.Id,
            CompanyId = companyId,
            PropertyId = id,
            Department = Nullify(request.Department),
            TechnicianName = Nullify(request.Technician),
            Address = Nullify(address),
            City = Nullify(p.Governorate),
            Area = Nullify(p.Area),
            ContactPhone = primary?.PhoneNumber,
            Status = ServiceRequestStatus.Pending,
            StatusNote = Nullify(request.Note),
            Priority = request.Priority is >= 1 and <= 5 ? request.Priority!.Value : 3,
            RequestedAt = DateTime.UtcNow,
            CreatedAt = DateTime.UtcNow
        };
        await _db.ServiceRequests.AddAsync(req, ct);
        await _db.ServiceRequestStatusHistories.AddAsync(new ServiceRequestStatusHistory
        {
            ServiceRequestId = req.Id,
            FromStatus = ServiceRequestStatus.Pending,
            ToStatus = ServiceRequestStatus.Pending,
            Note = "تم إنشاء المهمة من سجل العقارات",
            ChangedById = userId,
            CreatedAt = DateTime.UtcNow
        }, ct);
        await _db.SaveChangesAsync(ct);

        return Ok(new
        {
            success = true,
            data = new { id = req.Id, requestNumber = req.RequestNumber, status = req.Status.ToString() },
            message = "تم إنشاء المهمة وربطها بالعقار"
        });
    }

    // ============ صور خاصة (الماستر/الهوية) — تخزين معزول بالشركة + عرض مُصرّح فقط ============

    /// <summary>
    /// رفع صورة خاصة بالعقار/الخدمة (صورة ماستر أو هوية أحوال مدنية). تُخزَّن تحت مجلد الشركة
    /// (عزل)، وتُرجع اسم الملف فقط — يُحفَظ في حقل الخدمة. الصور الحسّاسة لا تُخدَم كـstatic عام.
    /// </summary>
    [HttpPost("upload-image")]
    [RequestSizeLimit(10 * 1024 * 1024)]
    [RequirePermission("property_registry", "manage", PermissionSystem.Second, failClosed: true)]
    public async Task<IActionResult> UploadImage(IFormFile file, CancellationToken ct)
    {
        if (!TryResolveScope(out var companyId, out _, out var denied)) return denied!;
        if (file == null || file.Length == 0)
            return BadRequest(new { success = false, message = "لا يوجد ملف" });

        var allowed = new[] { "image/jpeg", "image/png", "image/webp" };
        if (!allowed.Contains((file.ContentType ?? string.Empty).ToLowerInvariant()))
            return BadRequest(new { success = false, message = "نوع الملف غير مسموح (JPG/PNG/WEBP فقط)" });

        var dir = Path.Combine(_env.ContentRootPath, "uploads", "properties", companyId.ToString("N"));
        Directory.CreateDirectory(dir);

        var ext = Path.GetExtension(file.FileName);
        if (ext.Length > 5 || string.IsNullOrEmpty(ext)) ext = ".jpg";
        var fileName = $"{Guid.NewGuid():N}{ext}";
        var fullPath = Path.Combine(dir, fileName);
        using (var stream = new FileStream(fullPath, FileMode.Create))
            await file.CopyToAsync(stream, ct);

        // يُرجع اسم الملف (يُحفَظ في الحقل) + مسار العرض المُصرّح.
        return Ok(new { success = true, data = new { fileName, url = $"/api/properties/image/{fileName}" } });
    }

    /// <summary>عرض صورة خاصة — مُصرّح + معزول بالشركة (المسار يُشتقّ من شركة المتصل، لا يُمرَّر).</summary>
    [HttpGet("image/{fileName}")]
    [RequirePermission("property_registry", "view", PermissionSystem.Second, failClosed: true)]
    public IActionResult GetImage(string fileName)
    {
        if (!TryResolveScope(out var companyId, out _, out var denied)) return denied!;
        // حماية من اجتياز المسار: نأخذ اسم الملف فقط.
        var safe = Path.GetFileName(fileName ?? string.Empty);
        if (string.IsNullOrWhiteSpace(safe))
            return BadRequest(new { success = false, message = "اسم ملف غير صالح" });

        var fullPath = Path.Combine(_env.ContentRootPath, "uploads", "properties", companyId.ToString("N"), safe);
        if (!System.IO.File.Exists(fullPath))
            return NotFound(new { success = false, message = "الصورة غير موجودة" });

        var mime = Path.GetExtension(safe).ToLowerInvariant() switch
        {
            ".png" => "image/png",
            ".webp" => "image/webp",
            _ => "image/jpeg"
        };
        return PhysicalFile(fullPath, mime);
    }

    // ============ مساعدات ============

    private async Task<Property?> GetOwnedPropertyAsync(Guid id, Guid companyId, CancellationToken ct) =>
        await _db.Properties.FirstOrDefaultAsync(x => x.Id == id && x.CompanyId == companyId, ct);

    /// <summary>يحمّل المواطنين (مع بيانات Citizen) والخدمات المرتبطة بعقار للعرض.</summary>
    private async Task<(List<object> residents, List<object> services)> LoadLinksAsync(Guid propertyId, Guid companyId, CancellationToken ct)
    {
        var residents = await _db.PropertyResidents.AsNoTracking()
            .Where(r => r.PropertyId == propertyId && r.CompanyId == companyId)
            .Join(_db.Citizens.AsNoTracking(), r => r.CitizenId, c => c.Id, (r, c) => new
            {
                id = r.Id,
                citizenId = c.Id,
                name = c.FullName,
                phone = c.PhoneNumber,
                relationship = r.Relationship.ToString(),
                isPrimary = r.IsPrimary
            })
            .ToListAsync(ct);

        var services = await _db.PropertyServices.AsNoTracking()
            .Where(s => s.PropertyId == propertyId && s.CompanyId == companyId)
            .OrderByDescending(s => s.CreatedAt)
            .Select(s => new
            {
                id = s.Id,
                serviceType = s.ServiceType.ToString(),
                providerType = s.ProviderType.ToString(),
                providerRefId = s.ProviderRefId,
                subscriberRef = s.SubscriberRef,
                status = s.Status.ToString(),
                startDate = s.StartDate,
                endDate = s.EndDate,
                notes = s.Notes,
                agentName = s.AgentName,
                accountNumber = s.AccountNumber,
                hasMasterPhoto = !string.IsNullOrEmpty(s.MasterPhotoPath),
                masterPhotoPath = s.MasterPhotoPath,
                hasCivilIdPhoto = !string.IsNullOrEmpty(s.CivilIdPhotoPath),
                civilIdPhotoPath = s.CivilIdPhotoPath
            })
            .ToListAsync(ct);

        return (residents.Cast<object>().ToList(), services.Cast<object>().ToList());
    }

    private static string? Nullify(string? s) => string.IsNullOrWhiteSpace(s) ? null : s.Trim();

    /// <summary>توليد IQ-PIN مبسّط من الإحداثيات (المرحلة 1): صيغة عرض قابلة للتطوير لاحقاً.</summary>
    private static (string?, string?) BuildIqPin(double? lat, double? lon)
    {
        if (lat is not double la || lon is not double lo) return (null, null);
        var raw = $"{la:F5},{lo:F5}";
        var disp = $"IQ {la:F4}N {lo:F4}E";
        return (raw, disp);
    }

    private static object ToDto(Property x) => new
    {
        id = x.Id,
        qrToken = x.QrToken,
        qrPayload = $"SADARA|P:{x.QrToken}",
        npn = x.Npn,
        npnDisplay = x.NpnDisplay,
        iqPin = x.IqPin,
        iqPinDisplay = x.IqPinDisplay,
        govCode = x.GovCode,
        governorate = x.Governorate,
        area = x.Area,
        address2 = x.Address2,
        address3 = x.Address3,
        ownerName = x.OwnerName,
        ownerPhone = x.OwnerPhone,
        district = x.District,
        landmark = x.Landmark,
        addressDetails = x.AddressDetails,
        latitude = x.Latitude,
        longitude = x.Longitude,
        propertyType = x.PropertyType.ToString(),
        ownership = x.Ownership.ToString(),
        hasPhoto = !string.IsNullOrEmpty(x.PhotoPath),
        notes = x.Notes,
        createdAt = x.CreatedAt
    };
}

/// <summary>طلب إنشاء/تعديل عقار.</summary>
public record PropertyUpsertRequest(
    int GovCode,
    string Governorate,
    string? Area,
    string? Address2,
    string? Address3,
    string? OwnerName,
    string? OwnerPhone,
    string? District,
    string? Landmark,
    string? AddressDetails,
    double? Latitude,
    double? Longitude,
    PropertyType? PropertyType,
    PropertyOwnership? Ownership,
    string? Notes);

/// <summary>طلب ربط مواطن (Citizen موجود) بعقار.</summary>
public record LinkResidentRequest(
    Guid CitizenId,
    ResidentRelationship? Relationship,
    bool? IsPrimary);

/// <summary>طلب إضافة/تعديل خدمة عقار (موصّل عام + حقول خاصة بالنوع).</summary>
public record UpsertServiceRequest(
    PropertyServiceType? ServiceType,
    PropertyServiceProvider? ProviderType,
    string? ProviderRefId,
    string? SubscriberRef,
    PropertyServiceStatus? Status,
    DateTime? StartDate,
    DateTime? EndDate,
    string? Notes,
    string? AgentName,
    string? AccountNumber,
    string? MasterPhotoPath,
    string? CivilIdPhotoPath);

/// <summary>طلب إنشاء مهمة (طلب خدمة) مرتبطة بعقار.</summary>
public record CreatePropertyTaskRequest(
    int ServiceId,
    int OperationTypeId,
    int? Priority,
    string? Department,
    string? Technician,
    string? Note);
