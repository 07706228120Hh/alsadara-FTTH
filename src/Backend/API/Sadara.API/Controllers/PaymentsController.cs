using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Sadara.Domain.Entities;
using Sadara.Domain.Enums;
using Sadara.Domain.Interfaces;

namespace Sadara.API.Controllers;

[ApiController]
[Route("api/[controller]")]
public class PaymentsController : ControllerBase
{
    private readonly IUnitOfWork _unitOfWork;

    public PaymentsController(IUnitOfWork unitOfWork)
    {
        _unitOfWork = unitOfWork;
    }

    [HttpGet]
    [Authorize(Policy = "Admin")]
    public async Task<IActionResult> GetAll([FromQuery] PaymentStatus? status, [FromQuery] int page = 1, [FromQuery] int pageSize = 20)
    {
        var query = _unitOfWork.Payments.AsQueryable();

        if (status.HasValue)
            query = query.Where(p => p.Status == status.Value);

        var total = await query.CountAsync();
        var payments = await query
            .OrderByDescending(p => p.CreatedAt)
            .Skip((page - 1) * pageSize)
            .Take(pageSize)
            .ToListAsync();

        return Ok(new { success = true, data = payments, total, page, pageSize });
    }

    [HttpGet("{id:guid}")]
    [Authorize]
    public async Task<IActionResult> GetById(Guid id)
    {
        var payment = await _unitOfWork.Payments.GetByIdAsync(id);
        if (payment == null)
            return NotFound(new { success = false, message = "الدفعة غير موجودة" });

        return Ok(new { success = true, data = payment });
    }

    [HttpGet("order/{orderId:guid}")]
    [Authorize]
    public async Task<IActionResult> GetByOrder(Guid orderId)
    {
        var payments = await _unitOfWork.Payments.FindAsync(p => p.OrderId == orderId);
        return Ok(new { success = true, data = payments });
    }

    [HttpPost("initiate")]
    [Authorize]
    public async Task<IActionResult> InitiatePayment([FromBody] InitiatePaymentRequest request)
    {
        var order = await _unitOfWork.Orders.GetByIdAsync(request.OrderId);
        if (order == null)
            return NotFound(new { success = false, message = "الطلب غير موجود" });

        var payment = new Payment
        {
            Id = Guid.NewGuid(),
            OrderId = request.OrderId,
            UserId = request.UserId,
            Amount = request.Amount,
            Method = request.Method,
            Status = PaymentStatus.Pending,
            TransactionId = Guid.NewGuid().ToString("N"),
            PayerPhone = request.PayerPhone,
            PayerName = request.PayerName,
            CreatedAt = DateTime.UtcNow
        };

        await _unitOfWork.Payments.AddAsync(payment);
        await _unitOfWork.SaveChangesAsync();

        // Generate payment URL based on method
        string paymentUrl = request.Method switch
        {
            PaymentMethod.ZainCash => GenerateZainCashUrl(payment),
            PaymentMethod.FastPay => GenerateFastPayUrl(payment),
            _ => string.Empty
        };

        return Ok(new
        {
            success = true,
            data = new
            {
                paymentId = payment.Id,
                transactionId = payment.TransactionId,
                amount = payment.Amount,
                method = payment.Method.ToString(),
                paymentUrl
            }
        });
    }

    [HttpPost("callback/zaincash")]
    public async Task<IActionResult> ZainCashCallback([FromBody] ZainCashCallbackRequest request)
    {
        var payment = await _unitOfWork.Payments.FirstOrDefaultAsync(p => p.TransactionId == request.TransactionId);
        if (payment == null)
            return NotFound();

        payment.Status = request.Status == "success" ? PaymentStatus.Success : PaymentStatus.Failed;
        payment.GatewayTransactionId = request.GatewayTransactionId;
        payment.GatewayResponse = request.Message;
        payment.PaidAt = request.Status == "success" ? DateTime.UtcNow : null;

        _unitOfWork.Payments.Update(payment);

        // Update order status if payment successful
        if (payment.Status == PaymentStatus.Success)
        {
            var order = await _unitOfWork.Orders.GetByIdAsync(payment.OrderId);
            if (order != null)
            {
                order.PaymentStatus = PaymentStatus.Success;
                order.Status = OrderStatus.Confirmed;
                _unitOfWork.Orders.Update(order);
            }
        }

        await _unitOfWork.SaveChangesAsync();

        return Ok(new { success = true });
    }

    [HttpPost("refund/{id:guid}")]
    [Authorize(Policy = "Admin")]
    public async Task<IActionResult> Refund(Guid id, [FromBody] RefundRequest request)
    {
        var payment = await _unitOfWork.Payments.GetByIdAsync(id);
        if (payment == null)
            return NotFound(new { success = false, message = "الدفعة غير موجودة" });

        if (payment.Status != PaymentStatus.Success)
            return BadRequest(new { success = false, message = "لا يمكن استرداد دفعة غير ناجحة" });

        payment.Status = PaymentStatus.Refunded;
        payment.RefundedAt = DateTime.UtcNow;
        payment.RefundAmount = request.Amount ?? payment.Amount;
        payment.RefundReason = request.Reason;

        _unitOfWork.Payments.Update(payment);
        await _unitOfWork.SaveChangesAsync();

        return Ok(new { success = true, message = "تم استرداد المبلغ بنجاح" });
    }

    private string GenerateZainCashUrl(Payment payment)
    {
        // TODO: Implement actual ZainCash integration
        return $"https://zaincash.iq/pay?amount={payment.Amount}&txn={payment.TransactionId}";
    }

    private string GenerateFastPayUrl(Payment payment)
    {
        // TODO: Implement actual FastPay integration
        return $"https://fastpay.iq/pay?amount={payment.Amount}&txn={payment.TransactionId}";
    }
}

public record InitiatePaymentRequest(
    Guid OrderId,
    Guid? UserId,
    decimal Amount,
    PaymentMethod Method,
    string? PayerPhone,
    string? PayerName
);

public record ZainCashCallbackRequest(
    string TransactionId,
    string GatewayTransactionId,
    string Status,
    string? Message
);

public record RefundRequest(
    decimal? Amount,
    string? Reason
);
