using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Sadara.Domain.Entities;
using Sadara.Domain.Enums;
using Sadara.Domain.Interfaces;
using System.Globalization;
using System.Text;

namespace Sadara.API.Controllers;

/// <summary>
/// تقارير الموارد البشرية - الحضور، الرواتب، الإجازات، تصدير CSV
/// </summary>
[ApiController]
[Route("api/hr-reports")]
[Authorize]
public class HrReportsController(IUnitOfWork unitOfWork, ILogger<HrReportsController> logger) : ControllerBase
{
    private readonly IUnitOfWork _unitOfWork = unitOfWork;
    private readonly ILogger<HrReportsController> _logger = logger;

    // ==================== تقرير الحضور الشهري ====================

    /// <summary>
    /// تقرير الحضور الشهري الشامل لجميع الموظفين
    /// </summary>
    [HttpGet("attendance/monthly")]
    [Authorize(Policy = "Admin")]
    public async Task<IActionResult> GetMonthlyAttendanceReport(
        [FromQuery] Guid companyId,
        [FromQuery] int? month = null,
        [FromQuery] int? year = null)
    {
        try
        {
            var targetMonth = month ?? DateTime.UtcNow.Month;
            var targetYear = year ?? DateTime.UtcNow.Year;
            var startDate = new DateOnly(targetYear, targetMonth, 1);
            var endDate = startDate.AddMonths(1).AddDays(-1);

            var records = await _unitOfWork.AttendanceRecords.AsQueryable()
                .Where(a => a.CompanyId == companyId && a.Date >= startDate && a.Date <= endDate)
                .ToListAsync();

            var employees = await _unitOfWork.Users.AsQueryable()
                .Where(u => u.CompanyId == companyId && u.IsActive)
                .Select(u => new { u.Id, u.FullName, u.PhoneNumber })
                .ToListAsync();

            var employeeReports = employees.Select(emp =>
            {
                var empRecords = records.Where(r => r.UserId == emp.Id).ToList();
                return new
                {
                    UserId = emp.Id,
                    EmployeeName = emp.FullName,
                    Phone = emp.PhoneNumber,
                    PresentDays = empRecords.Count(r => r.Status == AttendanceStatus.Present),
                    LateDays = empRecords.Count(r => r.Status == AttendanceStatus.Late),
                    AbsentDays = empRecords.Count(r => r.Status == AttendanceStatus.Absent),
                    HalfDays = empRecords.Count(r => r.Status == AttendanceStatus.HalfDay),
                    EarlyDepartureDays = empRecords.Count(r => r.Status == AttendanceStatus.EarlyDeparture),
                    TotalLateMinutes = empRecords.Sum(r => r.LateMinutes ?? 0),
                    TotalOvertimeMinutes = empRecords.Sum(r => r.OvertimeMinutes ?? 0),
                    TotalWorkedMinutes = empRecords.Sum(r => r.WorkedMinutes ?? 0),
                    TotalEarlyDepartureMinutes = empRecords.Sum(r => r.EarlyDepartureMinutes ?? 0),
                    TotalRecords = empRecords.Count
                };
            }).OrderBy(e => e.EmployeeName).ToList();

            var summary = new
            {
                Month = targetMonth,
                Year = targetYear,
                TotalEmployees = employees.Count,
                TotalPresent = employeeReports.Sum(e => e.PresentDays),
                TotalLate = employeeReports.Sum(e => e.LateDays),
                TotalAbsent = employeeReports.Sum(e => e.AbsentDays),
                TotalLateMinutes = employeeReports.Sum(e => e.TotalLateMinutes),
                TotalOvertimeMinutes = employeeReports.Sum(e => e.TotalOvertimeMinutes),
                AverageAttendanceRate = employees.Count > 0
                    ? Math.Round((double)employeeReports.Sum(e => e.PresentDays + e.LateDays) /
                        (employees.Count * endDate.Day) * 100, 1)
                    : 0
            };

            return Ok(new { success = true, data = employeeReports, summary });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في تقرير الحضور الشهري");
            return StatusCode(500, new { success = false, message = "خطأ داخلي" });
        }
    }

    // ==================== تقرير الرواتب الشهري ====================

    /// <summary>
    /// تقرير الرواتب الشهري مع تفاصيل الحضور والخصومات
    /// </summary>
    [HttpGet("salaries/monthly")]
    [Authorize(Policy = "Admin")]
    public async Task<IActionResult> GetMonthlySalaryReport(
        [FromQuery] Guid companyId,
        [FromQuery] int? month = null,
        [FromQuery] int? year = null)
    {
        try
        {
            var targetMonth = month ?? DateTime.UtcNow.Month;
            var targetYear = year ?? DateTime.UtcNow.Year;

            var salaries = await _unitOfWork.EmployeeSalaries.AsQueryable()
                .Where(s => s.CompanyId == companyId && s.Month == targetMonth && s.Year == targetYear)
                .Select(s => new
                {
                    s.Id,
                    s.UserId,
                    EmployeeName = s.User != null ? s.User.FullName : "",
                    s.BaseSalary,
                    s.Allowances,
                    s.Deductions,
                    s.Bonuses,
                    s.NetSalary,
                    Status = s.Status.ToString(),
                    s.PaidAt,
                    // تفاصيل الحضور
                    s.AttendanceDays,
                    s.AbsentDays,
                    s.TotalLateMinutes,
                    s.TotalOvertimeMinutes,
                    s.TotalEarlyDepartureMinutes,
                    s.UnpaidLeaveDays,
                    s.PaidLeaveDays,
                    // تفاصيل الخصومات
                    s.LateDeduction,
                    s.AbsentDeduction,
                    s.EarlyDepartureDeduction,
                    s.UnpaidLeaveDeduction,
                    s.OvertimeBonus,
                    s.ExpectedWorkDays
                }).OrderBy(s => s.EmployeeName).ToListAsync();

            var summary = new
            {
                Month = targetMonth,
                Year = targetYear,
                TotalEmployees = salaries.Count,
                TotalBaseSalary = salaries.Sum(s => s.BaseSalary),
                TotalAllowances = salaries.Sum(s => s.Allowances),
                TotalDeductions = salaries.Sum(s => s.Deductions),
                TotalBonuses = salaries.Sum(s => s.Bonuses),
                TotalNetSalary = salaries.Sum(s => s.NetSalary),
                TotalLateDeduction = salaries.Sum(s => s.LateDeduction),
                TotalAbsentDeduction = salaries.Sum(s => s.AbsentDeduction),
                TotalOvertimeBonus = salaries.Sum(s => s.OvertimeBonus),
                PaidCount = salaries.Count(s => s.Status == "Paid"),
                PendingCount = salaries.Count(s => s.Status == "Pending")
            };

            return Ok(new { success = true, data = salaries, summary });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في تقرير الرواتب");
            return StatusCode(500, new { success = false, message = "خطأ داخلي" });
        }
    }

    // ==================== تقرير الإجازات ====================

    /// <summary>
    /// تقرير الإجازات الشهري/السنوي
    /// </summary>
    [HttpGet("leaves/summary")]
    [Authorize(Policy = "Admin")]
    public async Task<IActionResult> GetLeavesReport(
        [FromQuery] Guid companyId,
        [FromQuery] int? year = null,
        [FromQuery] int? month = null)
    {
        try
        {
            var targetYear = year ?? DateTime.UtcNow.Year;
            var startDate = month.HasValue
                ? new DateOnly(targetYear, month.Value, 1)
                : new DateOnly(targetYear, 1, 1);
            var endDate = month.HasValue
                ? startDate.AddMonths(1).AddDays(-1)
                : new DateOnly(targetYear, 12, 31);

            var leaves = await _unitOfWork.LeaveRequests.AsQueryable()
                .Where(l => l.CompanyId == companyId
                    && l.StartDate >= startDate && l.StartDate <= endDate)
                .ToListAsync();

            var employees = await _unitOfWork.Users.AsQueryable()
                .Where(u => u.CompanyId == companyId && u.IsActive)
                .Select(u => new { u.Id, u.FullName })
                .ToListAsync();

            var employeeLeaves = employees.Select(emp =>
            {
                var empLeaves = leaves.Where(l => l.UserId == emp.Id).ToList();
                return new
                {
                    UserId = emp.Id,
                    EmployeeName = emp.FullName,
                    TotalRequests = empLeaves.Count,
                    Approved = empLeaves.Count(l => l.Status == LeaveRequestStatus.Approved),
                    Rejected = empLeaves.Count(l => l.Status == LeaveRequestStatus.Rejected),
                    Pending = empLeaves.Count(l => l.Status == LeaveRequestStatus.Pending),
                    TotalDaysApproved = empLeaves.Where(l => l.Status == LeaveRequestStatus.Approved).Sum(l => l.TotalDays),
                    ByType = new
                    {
                        Annual = empLeaves.Where(l => l.LeaveType == LeaveType.Annual && l.Status == LeaveRequestStatus.Approved).Sum(l => l.TotalDays),
                        Sick = empLeaves.Where(l => l.LeaveType == LeaveType.Sick && l.Status == LeaveRequestStatus.Approved).Sum(l => l.TotalDays),
                        Unpaid = empLeaves.Where(l => l.LeaveType == LeaveType.Unpaid && l.Status == LeaveRequestStatus.Approved).Sum(l => l.TotalDays),
                        Emergency = empLeaves.Where(l => l.LeaveType == LeaveType.Emergency && l.Status == LeaveRequestStatus.Approved).Sum(l => l.TotalDays),
                        Other = empLeaves.Where(l => l.LeaveType != LeaveType.Annual
                            && l.LeaveType != LeaveType.Sick
                            && l.LeaveType != LeaveType.Unpaid
                            && l.LeaveType != LeaveType.Emergency
                            && l.Status == LeaveRequestStatus.Approved).Sum(l => l.TotalDays)
                    }
                };
            }).Where(e => e.TotalRequests > 0).OrderByDescending(e => e.TotalDaysApproved).ToList();

            var summary = new
            {
                Year = targetYear,
                Month = month,
                TotalRequests = leaves.Count,
                TotalApproved = leaves.Count(l => l.Status == LeaveRequestStatus.Approved),
                TotalRejected = leaves.Count(l => l.Status == LeaveRequestStatus.Rejected),
                TotalPending = leaves.Count(l => l.Status == LeaveRequestStatus.Pending),
                TotalDaysApproved = leaves.Where(l => l.Status == LeaveRequestStatus.Approved).Sum(l => l.TotalDays)
            };

            return Ok(new { success = true, data = employeeLeaves, summary });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في تقرير الإجازات");
            return StatusCode(500, new { success = false, message = "خطأ داخلي" });
        }
    }

    // ==================== داشبورد HR ====================

    /// <summary>
    /// داشبورد الموارد البشرية - إحصائيات عامة
    /// </summary>
    [HttpGet("dashboard")]
    [Authorize(Policy = "Admin")]
    public async Task<IActionResult> GetHrDashboard([FromQuery] Guid companyId)
    {
        try
        {
            var today = DateOnly.FromDateTime(DateTime.UtcNow);
            var currentMonth = DateTime.UtcNow.Month;
            var currentYear = DateTime.UtcNow.Year;
            var monthStart = new DateOnly(currentYear, currentMonth, 1);
            var monthEnd = monthStart.AddMonths(1).AddDays(-1);

            // إحصاء الموظفين
            var totalEmployees = await _unitOfWork.Users.CountAsync(
                u => u.CompanyId == companyId && u.IsActive);

            // حضور اليوم
            var todayRecords = await _unitOfWork.AttendanceRecords.AsQueryable()
                .Where(a => a.CompanyId == companyId && a.Date == today)
                .ToListAsync();

            // حضور الشهر
            var monthRecords = await _unitOfWork.AttendanceRecords.AsQueryable()
                .Where(a => a.CompanyId == companyId && a.Date >= monthStart && a.Date <= monthEnd)
                .ToListAsync();

            // إجازات الشهر
            var monthLeaves = await _unitOfWork.LeaveRequests.AsQueryable()
                .Where(l => l.CompanyId == companyId
                    && l.Status == LeaveRequestStatus.Approved
                    && l.StartDate <= monthEnd && l.EndDate >= monthStart)
                .ToListAsync();

            // رواتب الشهر
            var salaries = await _unitOfWork.EmployeeSalaries.AsQueryable()
                .Where(s => s.CompanyId == companyId && s.Month == currentMonth && s.Year == currentYear)
                .ToListAsync();

            // إجازات معلقة
            var pendingLeaves = await _unitOfWork.LeaveRequests.CountAsync(
                l => l.CompanyId == companyId && l.Status == LeaveRequestStatus.Pending);

            return Ok(new
            {
                success = true,
                data = new
                {
                    // إحصائيات عامة
                    TotalEmployees = totalEmployees,
                    CurrentMonth = currentMonth,
                    CurrentYear = currentYear,

                    // حضور اليوم
                    Today = new
                    {
                        Date = today.ToString("yyyy-MM-dd"),
                        PresentCount = todayRecords.Count(r => r.Status == AttendanceStatus.Present),
                        LateCount = todayRecords.Count(r => r.Status == AttendanceStatus.Late),
                        AbsentCount = totalEmployees - todayRecords.Count,
                        CheckedInCount = todayRecords.Count
                    },

                    // حضور الشهر
                    MonthlyAttendance = new
                    {
                        TotalPresent = monthRecords.Count(r => r.Status == AttendanceStatus.Present),
                        TotalLate = monthRecords.Count(r => r.Status == AttendanceStatus.Late),
                        TotalAbsent = monthRecords.Count(r => r.Status == AttendanceStatus.Absent),
                        TotalLateMinutes = monthRecords.Sum(r => r.LateMinutes ?? 0),
                        TotalOvertimeMinutes = monthRecords.Sum(r => r.OvertimeMinutes ?? 0),
                        AttendanceRate = totalEmployees > 0 && monthEnd.Day > 0
                            ? Math.Round((double)monthRecords.Count(r =>
                                r.Status == AttendanceStatus.Present || r.Status == AttendanceStatus.Late)
                                / (totalEmployees * today.Day) * 100, 1)
                            : 0
                    },

                    // الإجازات
                    Leaves = new
                    {
                        ApprovedThisMonth = monthLeaves.Count,
                        TotalDaysThisMonth = monthLeaves.Sum(l => l.TotalDays),
                        PendingRequests = pendingLeaves
                    },

                    // الرواتب
                    Salaries = new
                    {
                        Generated = salaries.Any(),
                        TotalBaseSalary = salaries.Sum(s => s.BaseSalary), // إجمالي الرواتب الأساسية (مرجعي)
                        TotalNet = salaries.Sum(s => s.NetSalary),  // الصافي الفعلي (حسب الحضور)
                        TotalDeductions = salaries.Sum(s => s.Deductions),
                        TotalBonuses = salaries.Sum(s => s.Bonuses),
                        TotalAttendanceDays = salaries.Sum(s => s.AttendanceDays),
                        PaidCount = salaries.Count(s => s.Status == SalaryStatus.Paid),
                        PendingCount = salaries.Count(s => s.Status == SalaryStatus.Pending)
                    },

                    // أكثر الموظفين تأخراً هذا الشهر
                    TopLateEmployees = monthRecords
                        .GroupBy(r => new { r.UserId, r.UserName })
                        .Select(g => new
                        {
                            g.Key.UserId,
                            EmployeeName = g.Key.UserName,
                            LateDays = g.Count(r => r.Status == AttendanceStatus.Late),
                            TotalLateMinutes = g.Sum(r => r.LateMinutes ?? 0)
                        })
                        .OrderByDescending(x => x.TotalLateMinutes)
                        .Take(5)
                        .ToList(),

                    // أكثر الموظفين ساعات إضافية
                    TopOvertimeEmployees = monthRecords
                        .GroupBy(r => new { r.UserId, r.UserName })
                        .Select(g => new
                        {
                            g.Key.UserId,
                            EmployeeName = g.Key.UserName,
                            TotalOvertimeMinutes = g.Sum(r => r.OvertimeMinutes ?? 0)
                        })
                        .Where(x => x.TotalOvertimeMinutes > 0)
                        .OrderByDescending(x => x.TotalOvertimeMinutes)
                        .Take(5)
                        .ToList()
                }
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في داشبورد الموارد البشرية");
            return StatusCode(500, new { success = false, message = "خطأ داخلي" });
        }
    }

    // ==================== تقرير موظف فردي ====================

    /// <summary>
    /// تقرير شامل لموظف واحد
    /// </summary>
    [HttpGet("employee/{userId}")]
    [Authorize(Policy = "Admin")]
    public async Task<IActionResult> GetEmployeeReport(Guid userId,
        [FromQuery] int? month = null, [FromQuery] int? year = null)
    {
        try
        {
            var targetMonth = month ?? DateTime.UtcNow.Month;
            var targetYear = year ?? DateTime.UtcNow.Year;
            var startDate = new DateOnly(targetYear, targetMonth, 1);
            var endDate = startDate.AddMonths(1).AddDays(-1);

            var employee = await _unitOfWork.Users.AsQueryable()
                .Where(u => u.Id == userId)
                .Select(u => new { u.Id, u.FullName, u.PhoneNumber, u.Email, u.Role, u.Salary })
                .FirstOrDefaultAsync();

            if (employee == null)
                return NotFound(new { success = false, message = "الموظف غير موجود" });

            // حضور الشهر
            var attendance = await _unitOfWork.AttendanceRecords.AsQueryable()
                .Where(a => a.UserId == userId && a.Date >= startDate && a.Date <= endDate)
                .OrderBy(a => a.Date)
                .ToListAsync();

            // الراتب
            var salary = await _unitOfWork.EmployeeSalaries.AsQueryable()
                .Where(s => s.UserId == userId && s.Month == targetMonth && s.Year == targetYear)
                .FirstOrDefaultAsync();

            // الخصومات والمكافآت والبدلات اليدوية (من جدول EmployeeDeductionBonuses)
            var adjustments = await _unitOfWork.EmployeeDeductionBonuses.AsQueryable()
                .Where(a => a.UserId == userId && a.Month == targetMonth && a.Year == targetYear && a.IsActive)
                .OrderByDescending(a => a.CreatedAt)
                .ToListAsync();

            var manualDeductions = adjustments.Where(a => a.Type == AdjustmentType.Deduction).ToList();
            var manualBonuses = adjustments.Where(a => a.Type == AdjustmentType.Bonus).ToList();
            var manualAllowances = adjustments.Where(a => a.Type == AdjustmentType.Allowance).ToList();

            // حساب الخصومات/المكافآت المعلقة (لم تُطبّق على مسيّر بعد)
            var pendingDeductions = manualDeductions.Where(a => !a.IsApplied && a.Category != "سلفة").Sum(a => a.Amount);
            var pendingAdvances = manualDeductions.Where(a => !a.IsApplied && a.Category == "سلفة").Sum(a => a.Amount);
            var pendingBonuses = manualBonuses.Where(a => !a.IsApplied).Sum(a => a.Amount);
            var pendingAllowances = manualAllowances.Where(a => !a.IsApplied).Sum(a => a.Amount);
            var totalPendingMinus = pendingDeductions + pendingAdvances;

            object salaryResponse;
            if (salary != null)
            {
                // إضافة الخصومات المعلقة التي أُضيفت بعد إنشاء المسيّر
                var totalDeductions = salary.Deductions + pendingDeductions;
                var totalBonuses = salary.Bonuses + pendingBonuses;
                var totalAllowances = salary.Allowances + pendingAllowances;
                var adjustedNet = salary.NetSalary - totalPendingMinus + pendingBonuses + pendingAllowances;

                salaryResponse = new
                {
                    salary.BaseSalary,
                    Allowances = totalAllowances,
                    Deductions = totalDeductions,
                    Bonuses = totalBonuses,
                    NetSalary = adjustedNet,
                    Status = salary.Status.ToString(),
                    salary.LateDeduction,
                    salary.AbsentDeduction,
                    salary.EarlyDepartureDeduction,
                    salary.UnpaidLeaveDeduction,
                    salary.OvertimeBonus,
                    ManualDeductions = salary.ManualDeductions + pendingDeductions,
                    ManualBonuses = salary.ManualBonuses + pendingBonuses,
                    Advances = pendingAdvances + manualDeductions.Where(a => a.IsApplied && a.Category == "سلفة").Sum(a => a.Amount)
                };
            }
            else if (employee.Salary > 0 || adjustments.Any())
            {
                // حساب تقديري قبل إصدار المسيّر
                var baseSalary = employee.Salary;
                var totalManualDeductions = manualDeductions.Where(a => a.Category != "سلفة").Sum(a => a.Amount);
                var totalManualAdvances = manualDeductions.Where(a => a.Category == "سلفة").Sum(a => a.Amount);
                var totalManualBonuses = manualBonuses.Sum(a => a.Amount);
                var totalManualAllowances = manualAllowances.Sum(a => a.Amount);
                var estimatedNet = baseSalary + totalManualAllowances + totalManualBonuses - totalManualDeductions - totalManualAdvances;

                salaryResponse = new
                {
                    BaseSalary = baseSalary,
                    Allowances = totalManualAllowances,
                    Deductions = totalManualDeductions,
                    Bonuses = totalManualBonuses,
                    NetSalary = estimatedNet,
                    Status = "Draft",
                    LateDeduction = 0m,
                    AbsentDeduction = 0m,
                    EarlyDepartureDeduction = 0m,
                    UnpaidLeaveDeduction = 0m,
                    OvertimeBonus = 0m,
                    ManualDeductions = totalManualDeductions,
                    ManualBonuses = totalManualBonuses,
                    Advances = totalManualAdvances
                };
            }
            else
            {
                salaryResponse = null;
            }

            // الإجازات
            var leaves = await _unitOfWork.LeaveRequests.AsQueryable()
                .Where(l => l.UserId == userId && l.StartDate >= startDate && l.StartDate <= endDate)
                .ToListAsync();

            return Ok(new
            {
                success = true,
                data = new
                {
                    Employee = employee,
                    Month = targetMonth,
                    Year = targetYear,
                    Attendance = new
                    {
                        PresentDays = attendance.Count(r => r.Status == AttendanceStatus.Present),
                        LateDays = attendance.Count(r => r.Status == AttendanceStatus.Late),
                        AbsentDays = attendance.Count(r => r.Status == AttendanceStatus.Absent),
                        HalfDays = attendance.Count(r => r.Status == AttendanceStatus.HalfDay),
                        EarlyDepartureDays = attendance.Count(r => r.Status == AttendanceStatus.EarlyDeparture),
                        TotalLateMinutes = attendance.Sum(r => r.LateMinutes ?? 0),
                        TotalOvertimeMinutes = attendance.Sum(r => r.OvertimeMinutes ?? 0),
                        TotalWorkedMinutes = attendance.Sum(r => r.WorkedMinutes ?? 0),
                        DailyRecords = attendance.Select(r => new
                        {
                            r.Id,
                            Date = r.Date.ToString("yyyy-MM-dd"),
                            CheckIn = r.CheckInTime?.ToString("HH:mm"),
                            CheckOut = r.CheckOutTime?.ToString("HH:mm"),
                            Status = r.Status.ToString(),
                            r.LateMinutes,
                            r.OvertimeMinutes,
                            r.WorkedMinutes,
                            r.EarlyDepartureMinutes,
                            r.Notes
                        })
                    },
                    Salary = salaryResponse,
                    // الخصومات والمكافآت والبدلات اليدوية (تفاصيل كل عملية)
                    Adjustments = new
                    {
                        Deductions = manualDeductions.Where(a => a.Category != "سلفة").Select(a => new
                        {
                            a.Id,
                            a.Amount,
                            a.Category,
                            a.Description,
                            a.IsApplied,
                            CreatedAt = a.CreatedAt.ToString("yyyy-MM-dd")
                        }),
                        Advances = manualDeductions.Where(a => a.Category == "سلفة").Select(a => new
                        {
                            a.Id,
                            a.Amount,
                            a.Category,
                            a.Description,
                            a.IsApplied,
                            CreatedAt = a.CreatedAt.ToString("yyyy-MM-dd")
                        }),
                        Bonuses = manualBonuses.Select(a => new
                        {
                            a.Id,
                            a.Amount,
                            a.Category,
                            a.Description,
                            a.IsApplied,
                            CreatedAt = a.CreatedAt.ToString("yyyy-MM-dd")
                        }),
                        Allowances = manualAllowances.Select(a => new
                        {
                            a.Id,
                            a.Amount,
                            a.Category,
                            a.Description,
                            a.IsApplied,
                            CreatedAt = a.CreatedAt.ToString("yyyy-MM-dd")
                        }),
                        TotalDeductions = manualDeductions.Where(a => a.Category != "سلفة").Sum(a => a.Amount),
                        TotalAdvances = manualDeductions.Where(a => a.Category == "سلفة").Sum(a => a.Amount),
                        TotalBonuses = manualBonuses.Sum(a => a.Amount),
                        TotalAllowances = manualAllowances.Sum(a => a.Amount)
                    },
                    Leaves = new
                    {
                        TotalRequests = leaves.Count,
                        ApprovedDays = leaves.Where(l => l.Status == LeaveRequestStatus.Approved).Sum(l => l.TotalDays),
                        Requests = leaves.Select(l => new
                        {
                            l.Id,
                            LeaveType = l.LeaveType.ToString(),
                            Status = l.Status.ToString(),
                            StartDate = l.StartDate.ToString("yyyy-MM-dd"),
                            EndDate = l.EndDate.ToString("yyyy-MM-dd"),
                            l.TotalDays,
                            l.Reason
                        })
                    }
                }
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في تقرير الموظف");
            return StatusCode(500, new { success = false, message = "خطأ داخلي" });
        }
    }

    // ==================== تقريري الشخصي ====================

    /// <summary>
    /// تقرير الموظف الشخصي (يجلب بيانات المستخدم الحالي)
    /// </summary>
    [HttpGet("my-report")]
    [Authorize]
    public async Task<IActionResult> GetMyReport(
        [FromQuery] int? month = null, [FromQuery] int? year = null)
    {
        try
        {
            var claim = User.FindFirst("sub") ?? User.FindFirst(System.Security.Claims.ClaimTypes.NameIdentifier);
            if (claim == null)
                return Unauthorized(new { success = false, message = "غير مصادق" });

            var userId = Guid.Parse(claim.Value);
            return await GetEmployeeReport(userId, month, year);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في تقريري الشخصي");
            return StatusCode(500, new { success = false, message = "خطأ داخلي" });
        }
    }

    // ==================== تصدير CSV ====================

    /// <summary>
    /// تصدير تقرير الحضور الشهري كملف CSV
    /// </summary>
    [HttpGet("export/attendance")]
    [Authorize(Policy = "Admin")]
    public async Task<IActionResult> ExportAttendanceCsv(
        [FromQuery] Guid companyId,
        [FromQuery] int? month = null,
        [FromQuery] int? year = null)
    {
        try
        {
            var targetMonth = month ?? DateTime.UtcNow.Month;
            var targetYear = year ?? DateTime.UtcNow.Year;
            var startDate = new DateOnly(targetYear, targetMonth, 1);
            var endDate = startDate.AddMonths(1).AddDays(-1);

            var records = await _unitOfWork.AttendanceRecords.AsQueryable()
                .Where(a => a.CompanyId == companyId && a.Date >= startDate && a.Date <= endDate)
                .OrderBy(a => a.UserName).ThenBy(a => a.Date)
                .ToListAsync();

            var csv = new StringBuilder();
            // BOM for Arabic support
            csv.Append('\uFEFF');
            csv.AppendLine("اسم الموظف,التاريخ,وقت الحضور,وقت الانصراف,الحالة,دقائق التأخير,دقائق إضافية,دقائق العمل,مغادرة مبكرة,الملاحظات");

            foreach (var r in records)
            {
                csv.AppendLine(string.Join(",",
                    CsvEscape(r.UserName ?? ""),
                    r.Date.ToString("yyyy-MM-dd"),
                    r.CheckInTime?.ToString("HH:mm:ss") ?? "",
                    r.CheckOutTime?.ToString("HH:mm:ss") ?? "",
                    GetArabicStatus(r.Status),
                    r.LateMinutes?.ToString() ?? "0",
                    r.OvertimeMinutes?.ToString() ?? "0",
                    r.WorkedMinutes?.ToString() ?? "0",
                    r.EarlyDepartureMinutes?.ToString() ?? "0",
                    CsvEscape(r.Notes ?? "")
                ));
            }

            var fileName = $"attendance_{targetYear}_{targetMonth:D2}.csv";
            return File(Encoding.UTF8.GetBytes(csv.ToString()), "text/csv; charset=utf-8", fileName);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في تصدير تقرير الحضور");
            return StatusCode(500, new { success = false, message = "خطأ داخلي" });
        }
    }

    /// <summary>
    /// تصدير تقرير الرواتب كملف CSV
    /// </summary>
    [HttpGet("export/salaries")]
    [Authorize(Policy = "Admin")]
    public async Task<IActionResult> ExportSalariesCsv(
        [FromQuery] Guid companyId,
        [FromQuery] int? month = null,
        [FromQuery] int? year = null)
    {
        try
        {
            var targetMonth = month ?? DateTime.UtcNow.Month;
            var targetYear = year ?? DateTime.UtcNow.Year;

            var salaries = await _unitOfWork.EmployeeSalaries.AsQueryable()
                .Where(s => s.CompanyId == companyId && s.Month == targetMonth && s.Year == targetYear)
                .Include(s => s.User)
                .OrderBy(s => s.User!.FullName)
                .ToListAsync();

            var csv = new StringBuilder();
            csv.Append('\uFEFF');
            csv.AppendLine("اسم الموظف,الراتب الأساسي,البدلات,المكافآت,الخصومات,صافي الراتب,الحالة,أيام الحضور,أيام الغياب,دقائق التأخير,خصم التأخير,خصم الغياب,ساعات إضافية,مكافأة إضافي,إجازات بدون راتب,خصم إجازات");

            foreach (var s in salaries)
            {
                csv.AppendLine(string.Join(",",
                    CsvEscape(s.User?.FullName ?? ""),
                    s.BaseSalary.ToString("F2", CultureInfo.InvariantCulture),
                    s.Allowances.ToString("F2", CultureInfo.InvariantCulture),
                    s.Bonuses.ToString("F2", CultureInfo.InvariantCulture),
                    s.Deductions.ToString("F2", CultureInfo.InvariantCulture),
                    s.NetSalary.ToString("F2", CultureInfo.InvariantCulture),
                    s.Status == SalaryStatus.Paid ? "مصروف" : "معلق",
                    s.AttendanceDays,
                    s.AbsentDays,
                    s.TotalLateMinutes,
                    s.LateDeduction.ToString("F2", CultureInfo.InvariantCulture),
                    s.AbsentDeduction.ToString("F2", CultureInfo.InvariantCulture),
                    s.TotalOvertimeMinutes,
                    s.OvertimeBonus.ToString("F2", CultureInfo.InvariantCulture),
                    s.UnpaidLeaveDays,
                    s.UnpaidLeaveDeduction.ToString("F2", CultureInfo.InvariantCulture)
                ));
            }

            var fileName = $"salaries_{targetYear}_{targetMonth:D2}.csv";
            return File(Encoding.UTF8.GetBytes(csv.ToString()), "text/csv; charset=utf-8", fileName);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في تصدير تقرير الرواتب");
            return StatusCode(500, new { success = false, message = "خطأ داخلي" });
        }
    }

    /// <summary>
    /// تصدير تقرير الإجازات كملف CSV
    /// </summary>
    [HttpGet("export/leaves")]
    [Authorize(Policy = "Admin")]
    public async Task<IActionResult> ExportLeavesCsv(
        [FromQuery] Guid companyId,
        [FromQuery] int? year = null)
    {
        try
        {
            var targetYear = year ?? DateTime.UtcNow.Year;
            var startDate = new DateOnly(targetYear, 1, 1);
            var endDate = new DateOnly(targetYear, 12, 31);

            var leaves = await _unitOfWork.LeaveRequests.AsQueryable()
                .Where(l => l.CompanyId == companyId && l.StartDate >= startDate && l.StartDate <= endDate)
                .OrderBy(l => l.UserName).ThenBy(l => l.StartDate)
                .ToListAsync();

            var csv = new StringBuilder();
            csv.Append('\uFEFF');
            csv.AppendLine("اسم الموظف,نوع الإجازة,تاريخ البدء,تاريخ الانتهاء,عدد الأيام,الحالة,السبب");

            foreach (var l in leaves)
            {
                csv.AppendLine(string.Join(",",
                    CsvEscape(l.UserName ?? ""),
                    GetArabicLeaveType(l.LeaveType),
                    l.StartDate.ToString("yyyy-MM-dd"),
                    l.EndDate.ToString("yyyy-MM-dd"),
                    l.TotalDays,
                    GetArabicLeaveStatus(l.Status),
                    CsvEscape(l.Reason ?? "")
                ));
            }

            var fileName = $"leaves_{targetYear}.csv";
            return File(Encoding.UTF8.GetBytes(csv.ToString()), "text/csv; charset=utf-8", fileName);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في تصدير تقرير الإجازات");
            return StatusCode(500, new { success = false, message = "خطأ داخلي" });
        }
    }

    // ==================== Helper Methods ====================

    private static string CsvEscape(string value)
    {
        if (string.IsNullOrEmpty(value)) return "";
        if (value.Contains(',') || value.Contains('"') || value.Contains('\n'))
            return $"\"{value.Replace("\"", "\"\"")}\"";
        return value;
    }

    private static string GetArabicStatus(AttendanceStatus status) => status switch
    {
        AttendanceStatus.Present => "حاضر",
        AttendanceStatus.Late => "متأخر",
        AttendanceStatus.Absent => "غائب",
        AttendanceStatus.HalfDay => "نصف يوم",
        AttendanceStatus.EarlyDeparture => "مغادرة مبكرة",
        _ => status.ToString()
    };

    private static string GetArabicLeaveType(LeaveType type) => type switch
    {
        LeaveType.Annual => "سنوية",
        LeaveType.Sick => "مرضية",
        LeaveType.Unpaid => "بدون راتب",
        LeaveType.Emergency => "طارئة",
        LeaveType.Official => "رسمية",
        LeaveType.Marriage => "زواج",
        LeaveType.Parental => "أمومة/أبوة",
        LeaveType.Bereavement => "وفاة",
        _ => type.ToString()
    };

    private static string GetArabicLeaveStatus(LeaveRequestStatus status) => status switch
    {
        LeaveRequestStatus.Pending => "معلق",
        LeaveRequestStatus.Approved => "معتمد",
        LeaveRequestStatus.Rejected => "مرفوض",
        LeaveRequestStatus.Cancelled => "ملغي",
        _ => status.ToString()
    };
}
