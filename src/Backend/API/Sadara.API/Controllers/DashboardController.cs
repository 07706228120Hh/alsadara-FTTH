using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Sadara.Domain.Interfaces;

namespace Sadara.API.Controllers;

[ApiController]
[Route("api/[controller]")]
[Authorize(Policy = "Admin")]
public class DashboardController : ControllerBase
{
    private readonly IUnitOfWork _unitOfWork;

    public DashboardController(IUnitOfWork unitOfWork)
    {
        _unitOfWork = unitOfWork;
    }

    [HttpGet("stats")]
    public async Task<IActionResult> GetStats()
    {
        var totalUsers = await _unitOfWork.Users.CountAsync();
        var totalMerchants = await _unitOfWork.Merchants.CountAsync();
        var totalCustomers = await _unitOfWork.Customers.CountAsync();
        var totalProducts = await _unitOfWork.Products.CountAsync();
        var totalOrders = await _unitOfWork.Orders.CountAsync();

        var todayOrders = await _unitOfWork.Orders.CountAsync(o => o.CreatedAt.Date == DateTime.UtcNow.Date);
        var pendingOrders = await _unitOfWork.Orders.CountAsync(o => o.Status == Sadara.Domain.Enums.OrderStatus.Pending);

        return Ok(new
        {
            success = true,
            data = new
            {
                totalUsers,
                totalMerchants,
                totalCustomers,
                totalProducts,
                totalOrders,
                todayOrders,
                pendingOrders
            }
        });
    }

    [HttpGet("orders/chart")]
    public async Task<IActionResult> GetOrdersChart([FromQuery] int days = 30)
    {
        var startDate = DateTime.UtcNow.AddDays(-days);

        var ordersPerDay = await _unitOfWork.Orders.AsQueryable()
            .Where(o => o.CreatedAt >= startDate)
            .GroupBy(o => o.CreatedAt.Date)
            .Select(g => new
            {
                date = g.Key,
                count = g.Count(),
                total = g.Sum(o => o.TotalAmount)
            })
            .OrderBy(x => x.date)
            .ToListAsync();

        return Ok(new { success = true, data = ordersPerDay });
    }

    [HttpGet("revenue/chart")]
    public async Task<IActionResult> GetRevenueChart([FromQuery] int months = 12)
    {
        var startDate = DateTime.UtcNow.AddMonths(-months);

        var revenuePerMonth = await _unitOfWork.Orders.AsQueryable()
            .Where(o => o.CreatedAt >= startDate && o.PaymentStatus == Sadara.Domain.Enums.PaymentStatus.Success)
            .GroupBy(o => new { o.CreatedAt.Year, o.CreatedAt.Month })
            .Select(g => new
            {
                year = g.Key.Year,
                month = g.Key.Month,
                revenue = g.Sum(o => o.TotalAmount),
                orders = g.Count()
            })
            .OrderBy(x => x.year)
            .ThenBy(x => x.month)
            .ToListAsync();

        return Ok(new { success = true, data = revenuePerMonth });
    }

    [HttpGet("merchants/top")]
    public async Task<IActionResult> GetTopMerchants([FromQuery] int count = 10)
    {
        var topMerchants = await _unitOfWork.Orders.AsQueryable()
            .GroupBy(o => o.MerchantId)
            .Select(g => new
            {
                merchantId = g.Key,
                totalOrders = g.Count(),
                totalRevenue = g.Sum(o => o.TotalAmount)
            })
            .OrderByDescending(x => x.totalRevenue)
            .Take(count)
            .ToListAsync();

        return Ok(new { success = true, data = topMerchants });
    }

    [HttpGet("products/top")]
    public async Task<IActionResult> GetTopProducts([FromQuery] int count = 10)
    {
        var topProducts = await _unitOfWork.OrderItems.AsQueryable()
            .GroupBy(oi => oi.ProductId)
            .Select(g => new
            {
                productId = g.Key,
                totalSold = g.Sum(oi => oi.Quantity),
                totalRevenue = g.Sum(oi => oi.TotalPrice)
            })
            .OrderByDescending(x => x.totalSold)
            .Take(count)
            .ToListAsync();

        return Ok(new { success = true, data = topProducts });
    }

    [HttpGet("recent-orders")]
    public async Task<IActionResult> GetRecentOrders([FromQuery] int count = 10)
    {
        var recentOrders = await _unitOfWork.Orders.AsQueryable()
            .OrderByDescending(o => o.CreatedAt)
            .Take(count)
            .Select(o => new
            {
                o.Id,
                o.OrderNumber,
                o.TotalAmount,
                status = o.Status.ToString(),
                o.CreatedAt
            })
            .ToListAsync();

        return Ok(new { success = true, data = recentOrders });
    }

    [HttpGet("recent-users")]
    public async Task<IActionResult> GetRecentUsers([FromQuery] int count = 10)
    {
        var recentUsers = await _unitOfWork.Users.AsQueryable()
            .OrderByDescending(u => u.CreatedAt)
            .Take(count)
            .Select(u => new
            {
                u.Id,
                u.FullName,
                u.PhoneNumber,
                role = u.Role.ToString(),
                u.CreatedAt
            })
            .ToListAsync();

        return Ok(new { success = true, data = recentUsers });
    }
}
