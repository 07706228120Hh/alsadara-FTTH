using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Sadara.Domain.Entities;
using Sadara.Domain.Interfaces;

namespace Sadara.API.Controllers;

[ApiController]
[Route("api/[controller]")]
public class AttendanceController(IUnitOfWork unitOfWork) : ControllerBase
{
    private readonly IUnitOfWork _unitOfWork = unitOfWork;

    /// <summary>تسجيل حضور</summary>
    [HttpPost("checkin")]
    [Authorize(Policy = "Admin")]
    public async Task<IActionResult> CheckIn([FromBody] CheckInRequest request)
    {
        // التحقق من عدم وجود حضور مسجل لنفس اليوم
        var today = DateOnly.FromDateTime(DateTime.UtcNow);
        var existing = await _unitOfWork.AttendanceRecords
            .FirstOrDefaultAsync(a => a.UserId == request.UserId && a.Date == today);

        if (existing != null && existing.CheckInTime != null)
        {
            return BadRequest(new { message = "تم تسجيل الحضور مسبقاً لهذا اليوم" });
        }

        var record = existing ?? new AttendanceRecord
        {
            UserId = request.UserId,
            UserName = request.UserName,
            CompanyId = request.CompanyId,
            Date = today,
        };

        record.CheckInTime = DateTime.UtcNow;
        record.CenterName = request.CenterName;
        record.CheckInLatitude = request.Latitude;
        record.CheckInLongitude = request.Longitude;
        record.SecurityCode = request.SecurityCode;

        if (existing == null)
            await _unitOfWork.AttendanceRecords.AddAsync(record);
        else
            _unitOfWork.AttendanceRecords.Update(record);

        await _unitOfWork.SaveChangesAsync();

        return Ok(new { message = "تم تسجيل الحضور بنجاح", record });
    }

    /// <summary>تسجيل انصراف</summary>
    [HttpPost("checkout")]
    [Authorize(Policy = "Admin")]
    public async Task<IActionResult> CheckOut([FromBody] CheckOutRequest request)
    {
        var today = DateOnly.FromDateTime(DateTime.UtcNow);
        var record = await _unitOfWork.AttendanceRecords
            .FirstOrDefaultAsync(a => a.UserId == request.UserId && a.Date == today);

        if (record == null)
        {
            return BadRequest(new { message = "لم يتم تسجيل الحضور اليوم" });
        }

        if (record.CheckOutTime != null)
        {
            return BadRequest(new { message = "تم تسجيل الانصراف مسبقاً" });
        }

        record.CheckOutTime = DateTime.UtcNow;
        record.CheckOutLatitude = request.Latitude;
        record.CheckOutLongitude = request.Longitude;
        record.Notes = request.Notes;
        record.UpdatedAt = DateTime.UtcNow;

        _unitOfWork.AttendanceRecords.Update(record);
        await _unitOfWork.SaveChangesAsync();

        return Ok(new { message = "تم تسجيل الانصراف بنجاح", record });
    }

    /// <summary>جلب سجل الحضور الشهري لموظف</summary>
    [HttpGet("{userId}/monthly")]
    [Authorize(Policy = "Admin")]
    public async Task<IActionResult> GetMonthlyAttendance(Guid userId, [FromQuery] int? year, [FromQuery] int? month)
    {
        var targetYear = year ?? DateTime.UtcNow.Year;
        var targetMonth = month ?? DateTime.UtcNow.Month;
        var startDate = new DateOnly(targetYear, targetMonth, 1);
        var endDate = startDate.AddMonths(1).AddDays(-1);

        var records = await _unitOfWork.AttendanceRecords
            .AsQueryable()
            .Where(a => a.UserId == userId && a.Date >= startDate && a.Date <= endDate)
            .OrderBy(a => a.Date)
            .ToListAsync();

        return Ok(new
        {
            userId,
            year = targetYear,
            month = targetMonth,
            totalDays = records.Count,
            records = records.Select(r => new
            {
                r.Id,
                date = r.Date.ToString("yyyy-MM-dd"),
                checkInTime = r.CheckInTime?.ToString("HH:mm:ss"),
                checkOutTime = r.CheckOutTime?.ToString("HH:mm:ss"),
                r.CenterName,
                r.SecurityCode,
                r.Notes
            })
        });
    }

    /// <summary>جلب حضور جميع الموظفين لتاريخ معين</summary>
    [HttpGet("daily")]
    [Authorize(Policy = "Admin")]
    public async Task<IActionResult> GetDailyAttendance([FromQuery] string? date, [FromQuery] Guid? companyId)
    {
        var targetDate = string.IsNullOrEmpty(date) 
            ? DateOnly.FromDateTime(DateTime.UtcNow) 
            : DateOnly.Parse(date);

        var query = _unitOfWork.AttendanceRecords.AsQueryable()
            .Where(a => a.Date == targetDate);

        if (companyId.HasValue)
            query = query.Where(a => a.CompanyId == companyId.Value);

        var records = await query.OrderBy(a => a.UserName).ToListAsync();

        return Ok(records);
    }

    /// <summary>جلب مراكز العمل</summary>
    [HttpGet("centers")]
    [Authorize(Policy = "Admin")]
    public async Task<IActionResult> GetCenters([FromQuery] Guid? companyId)
    {
        var query = _unitOfWork.WorkCenters.AsQueryable();
        
        if (companyId.HasValue)
            query = query.Where(c => c.CompanyId == companyId.Value);

        var centers = await query.Where(c => c.IsActive).ToListAsync();
        return Ok(centers);
    }

    /// <summary>إضافة مركز عمل</summary>
    [HttpPost("centers")]
    [Authorize(Policy = "Admin")]
    public async Task<IActionResult> AddCenter([FromBody] AddCenterRequest request)
    {
        var center = new WorkCenter
        {
            Name = request.Name,
            Latitude = request.Latitude,
            Longitude = request.Longitude,
            RadiusMeters = request.RadiusMeters ?? 200,
            CompanyId = request.CompanyId,
        };

        await _unitOfWork.WorkCenters.AddAsync(center);
        await _unitOfWork.SaveChangesAsync();

        return Ok(center);
    }
}

// DTOs
public record CheckInRequest(Guid UserId, string UserName, Guid? CompanyId, string? CenterName, 
    double? Latitude, double? Longitude, string? SecurityCode);

public record CheckOutRequest(Guid UserId, double? Latitude, double? Longitude, string? Notes);

public record AddCenterRequest(string Name, double Latitude, double Longitude, double? RadiusMeters, Guid? CompanyId);
