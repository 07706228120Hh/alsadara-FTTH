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

    public PropertiesController(
        SadaraDbContext db,
        ICurrentTenant tenant,
        ILogger<PropertiesController> logger)
    {
        _db = db;
        _tenant = tenant;
        _logger = logger;
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
        return Ok(new { success = true, data = ToDto(p) });
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
        return Ok(new { success = true, data = ToDto(p), residents = Array.Empty<object>(), services = Array.Empty<object>() });
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

    // ============ مساعدات ============

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
    string? District,
    string? Landmark,
    string? AddressDetails,
    double? Latitude,
    double? Longitude,
    PropertyType? PropertyType,
    PropertyOwnership? Ownership,
    string? Notes);
