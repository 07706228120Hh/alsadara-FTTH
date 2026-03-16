using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Sadara.Domain.Entities;
using Sadara.Domain.Interfaces;

namespace Sadara.API.Controllers;

/// <summary>
/// إدارة مشتركي IPTV - يستخدم API Key للمصادقة
/// </summary>
[ApiController]
[Route("api/iptv-subscribers")]
public class IptvSubscribersController : ControllerBase
{
    private readonly IUnitOfWork _unitOfWork;
    private readonly IConfiguration _configuration;

    public IptvSubscribersController(IUnitOfWork unitOfWork, IConfiguration configuration)
    {
        _unitOfWork = unitOfWork;
        _configuration = configuration;
    }

    private bool ValidateApiKey()
    {
        var apiKey = Request.Headers["X-Api-Key"].FirstOrDefault();
        var configKey = _configuration["Security:InternalApiKey"]
            ?? Environment.GetEnvironmentVariable("SADARA_INTERNAL_API_KEY")
            ?? "sadara-internal-2024-secure-key";
        return !string.IsNullOrEmpty(apiKey) && apiKey == configKey;
    }

    /// <summary>جلب جميع مشتركي IPTV لشركة محددة</summary>
    [HttpGet]
    public async Task<IActionResult> GetAll([FromQuery] string companyId)
    {
        if (!ValidateApiKey()) return Unauthorized(new { message = "API Key غير صالح" });
        if (string.IsNullOrEmpty(companyId)) return BadRequest(new { message = "companyId مطلوب" });

        var items = await _unitOfWork.IptvSubscribers.AsQueryable()
            .Where(s => s.CompanyId == companyId)
            .OrderByDescending(s => s.CreatedAt)
            .ToListAsync();

        return Ok(new { data = items });
    }

    /// <summary>جلب مشترك IPTV بالمعرف</summary>
    [HttpGet("{id}")]
    public async Task<IActionResult> GetById(long id)
    {
        if (!ValidateApiKey()) return Unauthorized(new { message = "API Key غير صالح" });

        var subscriber = await _unitOfWork.IptvSubscribers.GetByIdAsync(id);
        if (subscriber == null) return NotFound(new { message = "المشترك غير موجود" });

        return Ok(new { data = subscriber });
    }

    /// <summary>إنشاء مشترك IPTV جديد</summary>
    [HttpPost]
    public async Task<IActionResult> Create([FromBody] CreateIptvSubscriberRequest request)
    {
        if (!ValidateApiKey()) return Unauthorized(new { message = "API Key غير صالح" });
        if (string.IsNullOrEmpty(request.CompanyId)) return BadRequest(new { message = "companyId مطلوب" });
        if (string.IsNullOrEmpty(request.CustomerName)) return BadRequest(new { message = "customerName مطلوب" });

        var subscriber = new IptvSubscriber
        {
            CompanyId = request.CompanyId,
            SubscriptionId = request.SubscriptionId,
            CustomerName = request.CustomerName,
            Phone = request.Phone,
            IptvUsername = request.IptvUsername,
            IptvPassword = request.IptvPassword,
            IptvCode = request.IptvCode,
            ActivationDate = request.ActivationDate,
            DurationMonths = request.DurationMonths,
            IsActive = request.IsActive,
            Location = request.Location,
            Notes = request.Notes,
        };

        await _unitOfWork.IptvSubscribers.AddAsync(subscriber);
        await _unitOfWork.SaveChangesAsync();

        return Ok(new { data = subscriber });
    }

    /// <summary>تعديل مشترك IPTV</summary>
    [HttpPut("{id}")]
    public async Task<IActionResult> Update(long id, [FromBody] UpdateIptvSubscriberRequest request)
    {
        if (!ValidateApiKey()) return Unauthorized(new { message = "API Key غير صالح" });

        var subscriber = await _unitOfWork.IptvSubscribers.GetByIdAsync(id);
        if (subscriber == null) return NotFound(new { message = "المشترك غير موجود" });

        subscriber.SubscriptionId = request.SubscriptionId;
        subscriber.CustomerName = request.CustomerName;
        subscriber.Phone = request.Phone;
        subscriber.IptvUsername = request.IptvUsername;
        subscriber.IptvPassword = request.IptvPassword;
        subscriber.IptvCode = request.IptvCode;
        subscriber.ActivationDate = request.ActivationDate;
        subscriber.DurationMonths = request.DurationMonths;
        subscriber.IsActive = request.IsActive;
        subscriber.Location = request.Location;
        subscriber.Notes = request.Notes;
        subscriber.UpdatedAt = DateTime.UtcNow;

        _unitOfWork.IptvSubscribers.Update(subscriber);
        await _unitOfWork.SaveChangesAsync();

        return Ok(new { success = true, data = subscriber });
    }

    /// <summary>حذف مشترك IPTV (حذف ناعم)</summary>
    [HttpDelete("{id}")]
    public async Task<IActionResult> Delete(long id)
    {
        if (!ValidateApiKey()) return Unauthorized(new { message = "API Key غير صالح" });

        var subscriber = await _unitOfWork.IptvSubscribers.GetByIdAsync(id);
        if (subscriber == null) return NotFound(new { message = "المشترك غير موجود" });

        subscriber.IsDeleted = true;
        subscriber.DeletedAt = DateTime.UtcNow;
        _unitOfWork.IptvSubscribers.Update(subscriber);
        await _unitOfWork.SaveChangesAsync();

        return Ok(new { success = true, message = "تم الحذف بنجاح" });
    }
}

public record CreateIptvSubscriberRequest(
    string CompanyId,
    string? SubscriptionId,
    string CustomerName,
    string? Phone,
    string? IptvUsername,
    string? IptvPassword,
    string? IptvCode,
    DateTime? ActivationDate,
    int DurationMonths = 1,
    bool IsActive = true,
    string? Location = null,
    string? Notes = null
);

public record UpdateIptvSubscriberRequest(
    string? SubscriptionId,
    string CustomerName,
    string? Phone,
    string? IptvUsername,
    string? IptvPassword,
    string? IptvCode,
    DateTime? ActivationDate,
    int DurationMonths = 1,
    bool IsActive = true,
    string? Location = null,
    string? Notes = null
);
