using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Sadara.Domain.Interfaces;

namespace Sadara.API.Controllers;

[ApiController]
[Route("api/[controller]")]
public class AdvertisingsController : ControllerBase
{
    private readonly IUnitOfWork _unitOfWork;

    public AdvertisingsController(IUnitOfWork unitOfWork)
    {
        _unitOfWork = unitOfWork;
    }

    [HttpGet]
    public async Task<IActionResult> GetAll()
    {
        var advertisings = await _unitOfWork.Advertisings.AsQueryable()
            .Where(a => a.IsActive)
            .OrderBy(a => a.SortOrder)
            .ToListAsync();

        return Ok(new { success = true, data = advertisings });
    }

    [HttpGet("active")]
    public async Task<IActionResult> GetActive()
    {
        var now = DateTime.UtcNow;
        var advertisings = await _unitOfWork.Advertisings.AsQueryable()
            .Where(a => a.IsActive &&
                       (a.StartDate == null || a.StartDate <= now) &&
                       (a.EndDate == null || a.EndDate >= now))
            .OrderBy(a => a.SortOrder)
            .ToListAsync();

        return Ok(new { success = true, data = advertisings });
    }

    [HttpGet("{id:int}")]
    public async Task<IActionResult> GetById(int id)
    {
        var advertising = await _unitOfWork.Advertisings.GetByIdAsync(id);
        if (advertising == null)
            return NotFound(new { success = false, message = "الإعلان غير موجود" });

        return Ok(new { success = true, data = advertising });
    }

    [HttpPost("{id:int}/click")]
    [Authorize]
    public async Task<IActionResult> RecordClick(int id)
    {
        var advertising = await _unitOfWork.Advertisings.GetByIdAsync(id);
        if (advertising == null)
            return NotFound();

        advertising.ClickCount++;
        _unitOfWork.Advertisings.Update(advertising);
        await _unitOfWork.SaveChangesAsync();

        return Ok(new { success = true });
    }

    [HttpPost("{id:int}/view")]
    [Authorize]
    public async Task<IActionResult> RecordView(int id)
    {
        var advertising = await _unitOfWork.Advertisings.GetByIdAsync(id);
        if (advertising == null)
            return NotFound();

        advertising.ViewCount++;
        _unitOfWork.Advertisings.Update(advertising);
        await _unitOfWork.SaveChangesAsync();

        return Ok(new { success = true });
    }
}
