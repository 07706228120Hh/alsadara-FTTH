using Sadara.Domain.Enums;

namespace Sadara.Application.DTOs;

#region Authentication DTOs
public record LoginRequest(
    string PhoneNumber,
    string Password,
    string? DeviceId = null,
    string? DeviceInfo = null);

public record LoginResponse(
    string Token,
    string RefreshToken,
    DateTime ExpiresAt,
    UserDto User);

public record RegisterRequest(
    string FullName,
    string PhoneNumber,
    string Password,
    string? Email = null,
    UserRole Role = UserRole.Citizen);

public record RefreshTokenRequest(
    string RefreshToken);

public record ChangePasswordRequest(
    string CurrentPassword,
    string NewPassword,
    string ConfirmPassword);

public record VerifyPhoneRequest(
    string PhoneNumber,
    string VerificationCode);

public record ForgotPasswordRequest(
    string PhoneNumber);

public record ResetPasswordRequest(
    string PhoneNumber,
    string VerificationCode,
    string NewPassword,
    string ConfirmPassword);

public record FirebaseAuthRequest(
    string FirebaseToken,
    string? PhoneNumber = null,
    string? DeviceId = null,
    string? DeviceInfo = null);
#endregion

#region User DTOs
public record UserDto(
    Guid Id,
    string FullName,
    string PhoneNumber,
    string? Email,
    UserRole Role,
    bool IsActive,
    bool IsPhoneVerified,
    string? ProfileImageUrl,
    DateTime CreatedAt);

public record UpdateUserRequest(
    string? FullName,
    string? Email,
    string? ProfileImageUrl);
#endregion

#region Merchant DTOs
public record MerchantDto(
    Guid Id,
    Guid UserId,
    string BusinessName,
    string? BusinessNameAr,
    string? Description,
    string? Logo,
    string? Banner,
    string? Address,
    string City,
    string? PhoneNumber,
    string? Email,
    string? Website,
    decimal CommissionRate,
    bool IsVerified,
    bool IsActive,
    int MaxProducts,
    int MaxCustomers,
    decimal TotalSales,
    int TotalOrders,
    decimal Rating,
    int RatingCount,
    DateTime CreatedAt);

public record CreateMerchantRequest(
    string BusinessName,
    string? BusinessNameAr,
    string? Description,
    string? Logo,
    string? Banner,
    string? Address,
    string City,
    string PhoneNumber,
    string? Email,
    string? Website,
    decimal CommissionRate = 0.10m);

public record UpdateMerchantRequest(
    string? BusinessName,
    string? BusinessNameAr,
    string? Description,
    string? Logo,
    string? Banner,
    string? Address,
    string? City,
    string? PhoneNumber,
    string? Email,
    string? Website,
    decimal? CommissionRate,
    bool? IsVerified,
    bool? IsActive);
#endregion

#region Customer DTOs
public record CustomerDto(
    long Id,
    Guid MerchantId,
    string CustomerCode,
    string FullName,
    string PhoneNumber,
    string? Email,
    string City,
    string? Area,
    string? Address,
    decimal WalletBalance,
    int TotalOrders,
    decimal TotalSpent,
    DateTime? LastOrderDate,
    bool IsActive,
    DateTime CreatedAt);

public record CreateCustomerRequest(
    string FullName,
    string PhoneNumber,
    string City,
    string? Email = null,
    string? Area = null,
    string? Address = null);

public record UpdateCustomerRequest(
    string? FullName = null,
    string? PhoneNumber = null,
    string? City = null,
    string? Email = null,
    string? Area = null,
    string? Address = null,
    bool? IsActive = null);

public record CustomerFilterRequest(
    string? SearchTerm = null,
    string? City = null,
    string? Area = null,
    bool? IsActive = null,
    DateTime? FromDate = null,
    DateTime? ToDate = null,
    int PageNumber = 1,
    int PageSize = 20);

public record CustomerListResponse(
    IEnumerable<CustomerDto> Items,
    int TotalCount,
    int CurrentPage,
    int PageSize,
    int TotalPages);
#endregion

#region Product DTOs
public record ProductDto(
    Guid Id,
    Guid MerchantId,
    string MerchantName,
    string Name,
    string? NameAr,
    string? Description,
    string? DescriptionAr,
    decimal Price,
    decimal? DiscountPrice,
    int StockQuantity,
    int SoldCount,
    string? ImageUrl,
    string? ImageUrl2,
    string? ImageUrl3,
    string? ImageUrl4,
    Guid? CategoryId,
    string? CategoryName,
    bool IsActive,
    bool IsFeatured,
    int ViewCount,
    decimal Rating,
    int RatingCount,
    DateTime CreatedAt,
    List<string>? Images = null);

public record CategoryDto(
    int Id,
    string Name,
    string? Description,
    string? ImageUrl,
    int? ParentCategoryId,
    string? ParentCategoryName,
    int ProductCount,
    bool IsActive,
    int SortOrder);

public record ProductVariantDto(
    int Id,
    int ProductId,
    string Name,
    string? Value,
    decimal? PriceModifier,
    int StockQuantity,
    string? Sku,
    bool IsActive);

public record CreateProductRequest(
    string Name,
    string? NameAr,
    string? Description,
    string? DescriptionAr,
    decimal Price,
    decimal? DiscountPrice,
    int StockQuantity,
    string? ImageUrl,
    string? ImageUrl2,
    string? ImageUrl3,
    string? ImageUrl4,
    Guid? CategoryId,
    bool IsActive = true,
    bool IsFeatured = false);

public record CreateProductVariantRequest(
    string Name,
    string? Value,
    decimal? PriceModifier,
    int StockQuantity,
    string? Sku);

public record UpdateProductRequest(
    string? Name,
    string? NameAr,
    string? Description,
    string? DescriptionAr,
    decimal? Price,
    decimal? DiscountPrice,
    int? StockQuantity,
    string? ImageUrl,
    string? ImageUrl2,
    string? ImageUrl3,
    string? ImageUrl4,
    Guid? CategoryId,
    bool? IsActive,
    bool? IsFeatured);
#endregion

#region Order DTOs
public record OrderDto(
    Guid Id,
    Guid MerchantId,
    string MerchantName,
    long CustomerId,
    string CustomerName,
    string OrderNumber,
    OrderStatus Status,
    decimal SubTotal,
    decimal ShippingCost,
    decimal Discount,
    decimal TotalAmount,
    string? DeliveryAddress,
    string? DeliveryCity,
    string? DeliveryArea,
    string? Notes,
    string? TrackingNumber,
    DateTime? EstimatedDeliveryDate,
    DateTime? ActualDeliveryDate,
    DateTime CreatedAt,
    DateTime? UpdatedAt,
    IEnumerable<OrderItemDto> Items);

public record OrderItemDto(
    Guid Id,
    Guid OrderId,
    Guid ProductId,
    string ProductName,
    string? ProductNameAr,
    string? ProductImageUrl,
    int Quantity,
    decimal UnitPrice,
    decimal TotalPrice,
    string? Notes);

public record OrderStatusHistoryDto(
    int Id,
    Guid OrderId,
    OrderStatus Status,
    string? Notes,
    string? ChangedBy,
    DateTime CreatedAt);

public record CreateOrderRequest(
    long CustomerId,
    string? DeliveryAddress,
    string? DeliveryCity,
    string? DeliveryArea,
    string? Notes,
    decimal ShippingCost = 0,
    decimal Discount = 0,
    List<CreateOrderItemRequest> Items = null!);

public record CreateOrderItemRequest(
    Guid ProductId,
    int Quantity,
    string? Notes = null);

public record UpdateOrderStatusRequest(
    OrderStatus Status,
    string? Notes = null,
    string? TrackingNumber = null,
    DateTime? EstimatedDeliveryDate = null);

public record OrderFilterRequest(
    string? Search = null,
    OrderStatus? Status = null,
    long? CustomerId = null,
    DateTime? FromDate = null,
    DateTime? ToDate = null,
    int PageNumber = 1,
    int PageSize = 20);
#endregion

#region Payment DTOs
public record PaymentDto(
    Guid Id,
    Guid OrderId,
    string OrderNumber,
    PaymentMethod Method,
    PaymentStatus Status,
    decimal Amount,
    string? TransactionId,
    string? PaymentReference,
    string? Notes,
    DateTime? PaidAt,
    DateTime CreatedAt);

public record CreatePaymentRequest(
    Guid OrderId,
    PaymentMethod Method,
    decimal Amount,
    string? TransactionId = null,
    string? PaymentReference = null,
    string? Notes = null);

public record UpdatePaymentStatusRequest(
    PaymentStatus Status,
    string? TransactionId = null,
    string? Notes = null);

public record TopUpWalletRequest(
    decimal Amount,
    PaymentMethod Method,
    string? Notes = null);
#endregion

#region Notification DTOs
public record NotificationDto(
    int Id,
    int UserId,
    string Title,
    string Message,
    NotificationType Type,
    bool IsRead,
    string? ActionUrl,
    string? ImageUrl,
    DateTime CreatedAt,
    DateTime? ReadAt);

public record CreateNotificationRequest(
    int UserId,
    string Title,
    string Message,
    NotificationType Type,
    string? ActionUrl = null,
    string? ImageUrl = null);

public record MarkNotificationReadRequest(int[] NotificationIds);
#endregion

#region Common DTOs
public record ApiResponse<T>(
    bool Success,
    string Message,
    T? Data,
    IEnumerable<string>? Errors = null)
{
    public static ApiResponse<T> SuccessResponse(T data, string message = "Success")
        => new(true, message, data);

    public static ApiResponse<T> FailResponse(string message, IEnumerable<string>? errors = null)
        => new(false, message, default, errors);
}

public record PagedResponse<T>(
    IEnumerable<T> Items,
    int TotalCount,
    int CurrentPage,
    int PageSize,
    int TotalPages)
{
    public bool HasPreviousPage => CurrentPage > 1;
    public bool HasNextPage => CurrentPage < TotalPages;
}

public record PaginationRequest(
    int PageNumber = 1,
    int PageSize = 10)
{
    public int Skip => (PageNumber - 1) * PageSize;
    public int Take => PageSize;
}

public record SearchRequest(
    string? Query,
    int PageNumber = 1,
    int PageSize = 10,
    string? SortBy = null,
    bool SortDescending = false);
#endregion

#region City DTOs
public record CityDto(
    int Id,
    string Name,
    string? Region,
    decimal? ShippingCost,
    bool IsActive,
    int SortOrder);

public record CreateCityRequest(
    string Name,
    string? Region,
    decimal? ShippingCost,
    bool IsActive = true,
    int SortOrder = 0);

public record UpdateCityRequest(
    string? Name,
    string? Region,
    decimal? ShippingCost,
    bool? IsActive,
    int? SortOrder);
#endregion

#region Review DTOs
public record ReviewDto(
    int Id,
    int ProductId,
    string ProductName,
    int CustomerId,
    string CustomerName,
    int Rating,
    string? Comment,
    bool IsVerifiedPurchase,
    DateTime CreatedAt);

public record CreateReviewRequest(
    int ProductId,
    int CustomerId,
    int Rating,
    string? Comment);
#endregion

#region Dashboard DTOs
public record DashboardStatsDto(
    int TotalUsers,
    int TotalMerchants,
    int TotalCustomers,
    int TotalProducts,
    int TotalOrders,
    decimal TotalRevenue,
    int PendingOrders,
    int TodayOrders,
    decimal TodayRevenue);

public record MerchantDashboardDto(
    int TotalProducts,
    int TotalOrders,
    decimal TotalSales,
    int PendingOrders,
    int TodayOrders,
    decimal TodayRevenue,
    decimal Rating,
    int RatingCount);
#endregion



