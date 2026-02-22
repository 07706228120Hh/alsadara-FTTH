using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Sadara.Domain.Entities;
using Sadara.Domain.Interfaces;

namespace Sadara.API.Controllers;

/// <summary>
/// إدارة أقسام الشركة ومهام كل قسم
/// </summary>
[ApiController]
[Route("api/companies/{companyId:guid}/departments")]
[Authorize(Policy = "CompanyAdminOrAbove")]
public class DepartmentsController(IUnitOfWork unitOfWork) : ControllerBase
{
    private readonly IUnitOfWork _unitOfWork = unitOfWork;

    #region Departments (الأقسام)

    /// <summary>
    /// جلب جميع أقسام الشركة مع مهامها
    /// </summary>
    [HttpGet]
    public async Task<IActionResult> GetAll(Guid companyId)
    {
        var departments = await _unitOfWork.Departments.AsQueryable()
            .Where(d => d.CompanyId == companyId)
            .Include(d => d.Tasks.Where(t => !t.IsDeleted))
            .OrderBy(d => d.SortOrder)
            .ThenBy(d => d.NameAr)
            .Select(d => new DepartmentResponse
            {
                Id = d.Id,
                NameAr = d.NameAr,
                Name = d.Name,
                SortOrder = d.SortOrder,
                IsActive = d.IsActive,
                CreatedAt = d.CreatedAt,
                Tasks = d.Tasks
                    .Where(t => !t.IsDeleted)
                    .OrderBy(t => t.SortOrder)
                    .ThenBy(t => t.NameAr)
                    .Select(t => new DepartmentTaskResponse
                    {
                        Id = t.Id,
                        NameAr = t.NameAr,
                        Name = t.Name,
                        SortOrder = t.SortOrder,
                        IsActive = t.IsActive,
                        CreatedAt = t.CreatedAt
                    }).ToList()
            })
            .ToListAsync();

        return Ok(new { success = true, data = departments });
    }

    /// <summary>
    /// إضافة قسم جديد
    /// </summary>
    [HttpPost]
    public async Task<IActionResult> Create(Guid companyId, [FromBody] CreateDepartmentRequest request)
    {
        // التحقق من وجود الشركة
        var company = await _unitOfWork.Companies.GetByIdAsync(companyId);
        if (company == null)
            return NotFound(new { success = false, message = "الشركة غير موجودة" });

        // التحقق من عدم تكرار الاسم
        var exists = await _unitOfWork.Departments.AnyAsync(
            d => d.CompanyId == companyId && d.NameAr == request.NameAr.Trim());
        if (exists)
            return BadRequest(new { success = false, message = $"القسم '{request.NameAr}' موجود بالفعل" });

        // حساب الترتيب التلقائي
        var maxSort = await _unitOfWork.Departments.AsQueryable()
            .Where(d => d.CompanyId == companyId)
            .Select(d => (int?)d.SortOrder)
            .MaxAsync() ?? 0;

        var department = new Department
        {
            NameAr = request.NameAr.Trim(),
            Name = request.Name?.Trim(),
            CompanyId = companyId,
            SortOrder = request.SortOrder ?? maxSort + 1,
            IsActive = true
        };

        await _unitOfWork.Departments.AddAsync(department);
        await _unitOfWork.SaveChangesAsync();

        return Ok(new
        {
            success = true,
            message = "تم إضافة القسم بنجاح",
            data = new DepartmentResponse
            {
                Id = department.Id,
                NameAr = department.NameAr,
                Name = department.Name,
                SortOrder = department.SortOrder,
                IsActive = department.IsActive,
                CreatedAt = department.CreatedAt,
                Tasks = new List<DepartmentTaskResponse>()
            }
        });
    }

    /// <summary>
    /// تعديل قسم
    /// </summary>
    [HttpPut("{departmentId:int}")]
    public async Task<IActionResult> Update(Guid companyId, int departmentId, [FromBody] UpdateDepartmentRequest request)
    {
        var department = await _unitOfWork.Departments.FirstOrDefaultAsync(
            d => d.Id == departmentId && d.CompanyId == companyId);
        if (department == null)
            return NotFound(new { success = false, message = "القسم غير موجود" });

        // التحقق من عدم تكرار الاسم
        if (!string.IsNullOrWhiteSpace(request.NameAr))
        {
            var exists = await _unitOfWork.Departments.AnyAsync(
                d => d.CompanyId == companyId && d.NameAr == request.NameAr.Trim() && d.Id != departmentId);
            if (exists)
                return BadRequest(new { success = false, message = $"القسم '{request.NameAr}' موجود بالفعل" });
            department.NameAr = request.NameAr.Trim();
        }

        if (request.Name != null) department.Name = request.Name.Trim();
        if (request.SortOrder.HasValue) department.SortOrder = request.SortOrder.Value;
        if (request.IsActive.HasValue) department.IsActive = request.IsActive.Value;
        department.UpdatedAt = DateTime.UtcNow;

        _unitOfWork.Departments.Update(department);
        await _unitOfWork.SaveChangesAsync();

        return Ok(new { success = true, message = "تم تعديل القسم بنجاح" });
    }

    /// <summary>
    /// حذف قسم (حذف ناعم)
    /// </summary>
    [HttpDelete("{departmentId:int}")]
    public async Task<IActionResult> Delete(Guid companyId, int departmentId)
    {
        var department = await _unitOfWork.Departments.FirstOrDefaultAsync(
            d => d.Id == departmentId && d.CompanyId == companyId);
        if (department == null)
            return NotFound(new { success = false, message = "القسم غير موجود" });

        // حذف ناعم للقسم ومهامه
        department.IsDeleted = true;
        department.DeletedAt = DateTime.UtcNow;
        _unitOfWork.Departments.Update(department);

        var tasks = await _unitOfWork.DepartmentTasks.FindAsync(t => t.DepartmentId == departmentId);
        foreach (var task in tasks)
        {
            task.IsDeleted = true;
            task.DeletedAt = DateTime.UtcNow;
            _unitOfWork.DepartmentTasks.Update(task);
        }

        await _unitOfWork.SaveChangesAsync();

        return Ok(new { success = true, message = "تم حذف القسم ومهامه بنجاح" });
    }

    #endregion

    #region Department Tasks (مهام القسم)

    /// <summary>
    /// إضافة مهمة جديدة لقسم
    /// </summary>
    [HttpPost("{departmentId:int}/tasks")]
    public async Task<IActionResult> CreateTask(Guid companyId, int departmentId, [FromBody] CreateDepartmentTaskRequest request)
    {
        // التحقق من وجود القسم ويتبع الشركة
        var department = await _unitOfWork.Departments.FirstOrDefaultAsync(
            d => d.Id == departmentId && d.CompanyId == companyId);
        if (department == null)
            return NotFound(new { success = false, message = "القسم غير موجود" });

        // التحقق من عدم تكرار الاسم
        var exists = await _unitOfWork.DepartmentTasks.AnyAsync(
            t => t.DepartmentId == departmentId && t.NameAr == request.NameAr.Trim());
        if (exists)
            return BadRequest(new { success = false, message = $"المهمة '{request.NameAr}' موجودة بالفعل في هذا القسم" });

        // حساب الترتيب التلقائي
        var maxSort = await _unitOfWork.DepartmentTasks.AsQueryable()
            .Where(t => t.DepartmentId == departmentId)
            .Select(t => (int?)t.SortOrder)
            .MaxAsync() ?? 0;

        var task = new DepartmentTask
        {
            NameAr = request.NameAr.Trim(),
            Name = request.Name?.Trim(),
            DepartmentId = departmentId,
            SortOrder = request.SortOrder ?? maxSort + 1,
            IsActive = true
        };

        await _unitOfWork.DepartmentTasks.AddAsync(task);
        await _unitOfWork.SaveChangesAsync();

        return Ok(new
        {
            success = true,
            message = "تم إضافة المهمة بنجاح",
            data = new DepartmentTaskResponse
            {
                Id = task.Id,
                NameAr = task.NameAr,
                Name = task.Name,
                SortOrder = task.SortOrder,
                IsActive = task.IsActive,
                CreatedAt = task.CreatedAt
            }
        });
    }

    /// <summary>
    /// تعديل مهمة
    /// </summary>
    [HttpPut("{departmentId:int}/tasks/{taskId:int}")]
    public async Task<IActionResult> UpdateTask(Guid companyId, int departmentId, int taskId, [FromBody] UpdateDepartmentTaskRequest request)
    {
        // التحقق من وجود القسم ويتبع الشركة
        var department = await _unitOfWork.Departments.FirstOrDefaultAsync(
            d => d.Id == departmentId && d.CompanyId == companyId);
        if (department == null)
            return NotFound(new { success = false, message = "القسم غير موجود" });

        var task = await _unitOfWork.DepartmentTasks.FirstOrDefaultAsync(
            t => t.Id == taskId && t.DepartmentId == departmentId);
        if (task == null)
            return NotFound(new { success = false, message = "المهمة غير موجودة" });

        if (!string.IsNullOrWhiteSpace(request.NameAr))
        {
            var exists = await _unitOfWork.DepartmentTasks.AnyAsync(
                t => t.DepartmentId == departmentId && t.NameAr == request.NameAr.Trim() && t.Id != taskId);
            if (exists)
                return BadRequest(new { success = false, message = $"المهمة '{request.NameAr}' موجودة بالفعل" });
            task.NameAr = request.NameAr.Trim();
        }

        if (request.Name != null) task.Name = request.Name.Trim();
        if (request.SortOrder.HasValue) task.SortOrder = request.SortOrder.Value;
        if (request.IsActive.HasValue) task.IsActive = request.IsActive.Value;
        task.UpdatedAt = DateTime.UtcNow;

        _unitOfWork.DepartmentTasks.Update(task);
        await _unitOfWork.SaveChangesAsync();

        return Ok(new { success = true, message = "تم تعديل المهمة بنجاح" });
    }

    /// <summary>
    /// حذف مهمة (حذف ناعم)
    /// </summary>
    [HttpDelete("{departmentId:int}/tasks/{taskId:int}")]
    public async Task<IActionResult> DeleteTask(Guid companyId, int departmentId, int taskId)
    {
        // التحقق من وجود القسم ويتبع الشركة
        var department = await _unitOfWork.Departments.FirstOrDefaultAsync(
            d => d.Id == departmentId && d.CompanyId == companyId);
        if (department == null)
            return NotFound(new { success = false, message = "القسم غير موجود" });

        var task = await _unitOfWork.DepartmentTasks.FirstOrDefaultAsync(
            t => t.Id == taskId && t.DepartmentId == departmentId);
        if (task == null)
            return NotFound(new { success = false, message = "المهمة غير موجودة" });

        task.IsDeleted = true;
        task.DeletedAt = DateTime.UtcNow;
        _unitOfWork.DepartmentTasks.Update(task);
        await _unitOfWork.SaveChangesAsync();

        return Ok(new { success = true, message = "تم حذف المهمة بنجاح" });
    }

    #endregion

    #region Seed Default Departments (تهيئة الأقسام الافتراضية)

    /// <summary>
    /// تهيئة الأقسام الافتراضية للشركة (تُستخدم مرة واحدة أو عند الحاجة)
    /// </summary>
    [HttpPost("seed-defaults")]
    public async Task<IActionResult> SeedDefaults(Guid companyId)
    {
        var company = await _unitOfWork.Companies.GetByIdAsync(companyId);
        if (company == null)
            return NotFound(new { success = false, message = "الشركة غير موجودة" });

        // التحقق من عدم وجود أقسام مسبقاً
        var existingCount = await _unitOfWork.Departments.CountAsync(d => d.CompanyId == companyId);
        if (existingCount > 0)
            return BadRequest(new { success = false, message = "الشركة لديها أقسام بالفعل" });

        // الأقسام الافتراضية مع مهامها
        var defaultDepartments = new Dictionary<string, string[]>
        {
            ["الصيانة"] = new[] { "تركيب", "إصلاح", "صيانة دورية", "فحص", "استبدال", "طوارئ" },
            ["الحسابات"] = new[] { "شراء اشتراك", "تجديد اشتراك", "استشارة", "مراجعة حساب" },
            ["الفنيين"] = new[] { "تركيب", "إصلاح", "صيانة دورية", "فحص", "استبدال", "طوارئ" },
            ["الوكلاء"] = new[] { "شراء اشتراك", "تجديد اشتراك", "استشارة" },
            ["الاتصالات"] = new[] { "إصلاح", "فحص", "صيانة دورية", "طوارئ" },
            ["اللحام"] = new[] { "لحام ألياف", "إصلاح كابل", "تمديد", "فحص" }
        };

        int sortOrder = 1;
        foreach (var (deptName, tasks) in defaultDepartments)
        {
            var dept = new Department
            {
                NameAr = deptName,
                CompanyId = companyId,
                SortOrder = sortOrder++,
                IsActive = true
            };
            await _unitOfWork.Departments.AddAsync(dept);
            await _unitOfWork.SaveChangesAsync(); // لنحصل على ID

            int taskSort = 1;
            foreach (var taskName in tasks)
            {
                var task = new DepartmentTask
                {
                    NameAr = taskName,
                    DepartmentId = dept.Id,
                    SortOrder = taskSort++,
                    IsActive = true
                };
                await _unitOfWork.DepartmentTasks.AddAsync(task);
            }
            await _unitOfWork.SaveChangesAsync();
        }

        return Ok(new { success = true, message = "تم تهيئة الأقسام الافتراضية بنجاح" });
    }

    #endregion
}

#region DTOs

public class DepartmentResponse
{
    public int Id { get; set; }
    public string NameAr { get; set; } = string.Empty;
    public string? Name { get; set; }
    public int SortOrder { get; set; }
    public bool IsActive { get; set; }
    public DateTime CreatedAt { get; set; }
    public List<DepartmentTaskResponse> Tasks { get; set; } = new();
}

public class DepartmentTaskResponse
{
    public int Id { get; set; }
    public string NameAr { get; set; } = string.Empty;
    public string? Name { get; set; }
    public int SortOrder { get; set; }
    public bool IsActive { get; set; }
    public DateTime CreatedAt { get; set; }
}

public class CreateDepartmentRequest
{
    public string NameAr { get; set; } = string.Empty;
    public string? Name { get; set; }
    public int? SortOrder { get; set; }
}

public class UpdateDepartmentRequest
{
    public string? NameAr { get; set; }
    public string? Name { get; set; }
    public int? SortOrder { get; set; }
    public bool? IsActive { get; set; }
}

public class CreateDepartmentTaskRequest
{
    public string NameAr { get; set; } = string.Empty;
    public string? Name { get; set; }
    public int? SortOrder { get; set; }
}

public class UpdateDepartmentTaskRequest
{
    public string? NameAr { get; set; }
    public string? Name { get; set; }
    public int? SortOrder { get; set; }
    public bool? IsActive { get; set; }
}

#endregion
