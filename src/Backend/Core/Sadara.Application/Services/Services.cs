using AutoMapper;
using FluentValidation;
using Microsoft.Extensions.Logging;
using Sadara.Application.DTOs;
using Sadara.Domain.Entities;
using Sadara.Domain.Enums;
using Sadara.Domain.Interfaces;

namespace Sadara.Application.Services;

public interface IAuthService
{
    Task<ApiResponse<LoginResponse>> LoginAsync(LoginRequest request);
    Task<ApiResponse<LoginResponse>> RegisterAsync(RegisterRequest request);
    Task<ApiResponse<LoginResponse>> RefreshTokenAsync(RefreshTokenRequest request);
    Task<ApiResponse<bool>> ForgotPasswordAsync(ForgotPasswordRequest request);
    Task<ApiResponse<bool>> ResetPasswordAsync(ResetPasswordRequest request);
    Task<ApiResponse<bool>> VerifyPhoneAsync(VerifyPhoneRequest request);
    Task<ApiResponse<LoginResponse>> AuthenticateWithFirebaseAsync(FirebaseAuthRequest request);
}

public class AuthService : IAuthService
{
    private readonly IUnitOfWork _unitOfWork;
    private readonly IPasswordHasher _passwordHasher;
    private readonly IJwtService _jwtService;
    private readonly ISmsService _smsService;
    private readonly IMapper _mapper;
    private readonly ILogger<AuthService> _logger;
    private readonly IValidator<LoginRequest> _loginValidator;
    private readonly IValidator<RegisterRequest> _registerValidator;

    public AuthService(
        IUnitOfWork unitOfWork,
        IPasswordHasher passwordHasher,
        IJwtService jwtService,
        ISmsService smsService,
        IMapper mapper,
        ILogger<AuthService> logger,
        IValidator<LoginRequest> loginValidator,
        IValidator<RegisterRequest> registerValidator)
    {
        _unitOfWork = unitOfWork;
        _passwordHasher = passwordHasher;
        _jwtService = jwtService;
        _smsService = smsService;
        _mapper = mapper;
        _logger = logger;
        _loginValidator = loginValidator;
        _registerValidator = registerValidator;
    }

    public async Task<ApiResponse<LoginResponse>> LoginAsync(LoginRequest request)
    {
        var validation = await _loginValidator.ValidateAsync(request);
        if (!validation.IsValid)
            return ApiResponse<LoginResponse>.FailResponse("Validation error", validation.Errors.Select(e => e.ErrorMessage));

        var user = await _unitOfWork.Users.FirstOrDefaultAsync(u => u.PhoneNumber == request.PhoneNumber);
        
        if (user == null)
            return ApiResponse<LoginResponse>.FailResponse("Invalid credentials");

        if (user.LockoutEnd.HasValue && user.LockoutEnd > DateTime.UtcNow)
            return ApiResponse<LoginResponse>.FailResponse("Account locked");

        if (!user.IsActive)
            return ApiResponse<LoginResponse>.FailResponse("Account inactive");

        if (!_passwordHasher.VerifyPassword(request.Password, user.PasswordHash))
        {
            user.FailedLoginAttempts++;
            if (user.FailedLoginAttempts >= 5)
            {
                user.LockoutEnd = DateTime.UtcNow.AddMinutes(30);
                user.FailedLoginAttempts = 0;
            }
            await _unitOfWork.SaveChangesAsync();
            return ApiResponse<LoginResponse>.FailResponse("Invalid credentials");
        }

        user.FailedLoginAttempts = 0;
        user.LastLoginAt = DateTime.UtcNow;
        user.LastLoginDeviceId = request.DeviceId;
        user.LastLoginDeviceInfo = request.DeviceInfo;

        var accessToken = _jwtService.GenerateAccessToken(user);
        var refreshToken = _jwtService.GenerateRefreshToken();
        user.RefreshToken = refreshToken;
        user.RefreshTokenExpiryTime = DateTime.UtcNow.AddDays(7);

        await _unitOfWork.SaveChangesAsync();

        return ApiResponse<LoginResponse>.SuccessResponse(new LoginResponse(
            accessToken,
            refreshToken,
            DateTime.UtcNow.AddHours(1),
            _mapper.Map<UserDto>(user)
        ), "Login successful");
    }

    public async Task<ApiResponse<LoginResponse>> RegisterAsync(RegisterRequest request)
    {
        var validation = await _registerValidator.ValidateAsync(request);
        if (!validation.IsValid)
            return ApiResponse<LoginResponse>.FailResponse("Validation error", validation.Errors.Select(e => e.ErrorMessage));

        var existingUser = await _unitOfWork.Users.FirstOrDefaultAsync(u => u.PhoneNumber == request.PhoneNumber);
        if (existingUser != null)
            return ApiResponse<LoginResponse>.FailResponse("Phone already registered");

        var user = new User
        {
            Id = Guid.NewGuid(),
            FullName = request.FullName,
            PhoneNumber = request.PhoneNumber,
            Email = request.Email,
            PasswordHash = _passwordHasher.HashPassword(request.Password),
            Role = request.Role,
            IsActive = true,
            VerificationCode = Random.Shared.Next(100000, 999999).ToString(),
            VerificationCodeExpiresAt = DateTime.UtcNow.AddMinutes(10)
        };

        await _unitOfWork.Users.AddAsync(user);
        await _unitOfWork.SaveChangesAsync();

        await _smsService.SendSmsAsync(user.PhoneNumber, $"Code: {user.VerificationCode}");

        var accessToken = _jwtService.GenerateAccessToken(user);
        var refreshToken = _jwtService.GenerateRefreshToken();
        user.RefreshToken = refreshToken;
        user.RefreshTokenExpiryTime = DateTime.UtcNow.AddDays(7);

        await _unitOfWork.SaveChangesAsync();

        return ApiResponse<LoginResponse>.SuccessResponse(new LoginResponse(
            accessToken,
            refreshToken,
            DateTime.UtcNow.AddHours(1),
            _mapper.Map<UserDto>(user)
        ), "Registration successful");
    }

    public async Task<ApiResponse<LoginResponse>> RefreshTokenAsync(RefreshTokenRequest request)
    {
        var user = await _unitOfWork.Users.FirstOrDefaultAsync(u => 
            u.RefreshToken == request.RefreshToken && 
            u.RefreshTokenExpiryTime > DateTime.UtcNow);

        if (user == null)
            return ApiResponse<LoginResponse>.FailResponse("Invalid refresh token");

        var accessToken = _jwtService.GenerateAccessToken(user);
        var newRefreshToken = _jwtService.GenerateRefreshToken();
        user.RefreshToken = newRefreshToken;
        user.RefreshTokenExpiryTime = DateTime.UtcNow.AddDays(7);

        await _unitOfWork.SaveChangesAsync();

        return ApiResponse<LoginResponse>.SuccessResponse(new LoginResponse(
            accessToken,
            newRefreshToken,
            DateTime.UtcNow.AddHours(1),
            _mapper.Map<UserDto>(user)
        ));
    }

    public async Task<ApiResponse<bool>> ForgotPasswordAsync(ForgotPasswordRequest request)
    {
        var user = await _unitOfWork.Users.FirstOrDefaultAsync(u => u.PhoneNumber == request.PhoneNumber);
        if (user != null)
        {
            user.VerificationCode = Random.Shared.Next(100000, 999999).ToString();
            user.VerificationCodeExpiresAt = DateTime.UtcNow.AddMinutes(10);
            await _unitOfWork.SaveChangesAsync();
            await _smsService.SendSmsAsync(user.PhoneNumber, $"Reset code: {user.VerificationCode}");
        }
        return ApiResponse<bool>.SuccessResponse(true, "If registered, code sent");
    }

    public async Task<ApiResponse<bool>> ResetPasswordAsync(ResetPasswordRequest request)
    {
        var user = await _unitOfWork.Users.FirstOrDefaultAsync(u => 
            u.PhoneNumber == request.PhoneNumber && 
            u.VerificationCode == request.VerificationCode &&
            u.VerificationCodeExpiresAt > DateTime.UtcNow);

        if (user == null)
            return ApiResponse<bool>.FailResponse("Invalid or expired code");

        user.PasswordHash = _passwordHasher.HashPassword(request.NewPassword);
        user.VerificationCode = null;
        user.RefreshToken = null;
        
        await _unitOfWork.SaveChangesAsync();
        return ApiResponse<bool>.SuccessResponse(true, "Password reset successful");
    }

    public async Task<ApiResponse<bool>> VerifyPhoneAsync(VerifyPhoneRequest request)
    {
        var user = await _unitOfWork.Users.FirstOrDefaultAsync(u => 
            u.PhoneNumber == request.PhoneNumber && 
            u.VerificationCode == request.VerificationCode &&
            u.VerificationCodeExpiresAt > DateTime.UtcNow);

        if (user == null)
            return ApiResponse<bool>.FailResponse("Invalid or expired code");

        user.IsPhoneVerified = true;
        user.VerificationCode = null;
        
        await _unitOfWork.SaveChangesAsync();
        return ApiResponse<bool>.SuccessResponse(true, "Phone verified");
    }

    /// <summary>
    /// مصادقة عبر Firebase Token
    /// إذا كان المستخدم موجوداً يتم إنشاء توكن له
    /// إذا لم يكن موجوداً يتم إنشاء حساب جديد
    /// </summary>
    public async Task<ApiResponse<LoginResponse>> AuthenticateWithFirebaseAsync(FirebaseAuthRequest request)
    {
        try
        {
            // التحقق من Firebase Token (في الإنتاج يجب التحقق الفعلي من Firebase)
            if (string.IsNullOrEmpty(request.FirebaseToken))
                return ApiResponse<LoginResponse>.FailResponse("Firebase token is required");

            // البحث عن المستخدم برقم الهاتف
            var user = await _unitOfWork.Users.FirstOrDefaultAsync(u => u.PhoneNumber == request.PhoneNumber);

            if (user == null)
            {
                // إنشاء مستخدم جديد
                user = new User
                {
                    Id = Guid.NewGuid(),
                    FullName = "مستخدم جديد",
                    PhoneNumber = request.PhoneNumber ?? "",
                    Role = UserRole.Citizen,
                    IsActive = true,
                    IsPhoneVerified = true, // تم التحقق عبر Firebase
                    PasswordHash = _passwordHasher.HashPassword(Guid.NewGuid().ToString()) // كلمة مرور عشوائية
                };

                await _unitOfWork.Users.AddAsync(user);
                _logger.LogInformation("Created new user from Firebase: {Phone}", request.PhoneNumber);
            }

            // إنشاء التوكنات
            var accessToken = _jwtService.GenerateAccessToken(user);
            var refreshToken = _jwtService.GenerateRefreshToken();
            
            user.RefreshToken = refreshToken;
            user.RefreshTokenExpiryTime = DateTime.UtcNow.AddDays(7);
            user.LastLoginAt = DateTime.UtcNow;

            await _unitOfWork.SaveChangesAsync();

            return ApiResponse<LoginResponse>.SuccessResponse(new LoginResponse(
                accessToken,
                refreshToken,
                DateTime.UtcNow.AddHours(1),
                _mapper.Map<UserDto>(user)
            ), "Firebase authentication successful");
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Firebase authentication failed");
            return ApiResponse<LoginResponse>.FailResponse("Firebase authentication failed");
        }
    }
}

public interface ICustomerService
{
    Task<ApiResponse<CustomerDto>> GetByIdAsync(long id, Guid merchantId);
    Task<ApiResponse<CustomerListResponse>> GetAllAsync(Guid merchantId, CustomerFilterRequest filter);
    Task<ApiResponse<CustomerDto>> CreateAsync(Guid merchantId, CreateCustomerRequest request);
    Task<ApiResponse<CustomerDto>> UpdateAsync(long id, Guid merchantId, UpdateCustomerRequest request);
    Task<ApiResponse<bool>> DeleteAsync(long id, Guid merchantId);
}

public class CustomerService : ICustomerService
{
    private readonly IUnitOfWork _unitOfWork;
    private readonly IMapper _mapper;
    private readonly ILogger<CustomerService> _logger;
    private readonly IValidator<CreateCustomerRequest> _createValidator;

    public CustomerService(
        IUnitOfWork unitOfWork,
        IMapper mapper,
        ILogger<CustomerService> logger,
        IValidator<CreateCustomerRequest> createValidator)
    {
        _unitOfWork = unitOfWork;
        _mapper = mapper;
        _logger = logger;
        _createValidator = createValidator;
    }

    public async Task<ApiResponse<CustomerDto>> GetByIdAsync(long id, Guid merchantId)
    {
        var customer = await _unitOfWork.Customers.FirstOrDefaultAsync(c => c.Id == id && c.MerchantId == merchantId);
        if (customer == null)
            return ApiResponse<CustomerDto>.FailResponse("Customer not found");
        return ApiResponse<CustomerDto>.SuccessResponse(_mapper.Map<CustomerDto>(customer));
    }

    public async Task<ApiResponse<CustomerListResponse>> GetAllAsync(Guid merchantId, CustomerFilterRequest filter)
    {
        var query = _unitOfWork.Customers.AsQueryable().Where(c => c.MerchantId == merchantId);

        if (!string.IsNullOrEmpty(filter.SearchTerm))
        {
            var term = filter.SearchTerm.ToLower();
            query = query.Where(c => c.FullName.ToLower().Contains(term) || c.PhoneNumber.Contains(term));
        }

        if (!string.IsNullOrEmpty(filter.City))
            query = query.Where(c => c.City == filter.City);

        if (filter.IsActive.HasValue)
            query = query.Where(c => c.IsActive == filter.IsActive.Value);

        var totalCount = query.Count();
        var totalPages = (int)Math.Ceiling(totalCount / (double)filter.PageSize);

        var customers = query
            .OrderByDescending(c => c.CreatedAt)
            .Skip((filter.PageNumber - 1) * filter.PageSize)
            .Take(filter.PageSize)
            .ToList();

        return ApiResponse<CustomerListResponse>.SuccessResponse(new CustomerListResponse(
            _mapper.Map<IEnumerable<CustomerDto>>(customers),
            totalCount,
            filter.PageNumber,
            filter.PageSize,
            totalPages
        ));
    }

    public async Task<ApiResponse<CustomerDto>> CreateAsync(Guid merchantId, CreateCustomerRequest request)
    {
        var validation = await _createValidator.ValidateAsync(request);
        if (!validation.IsValid)
            return ApiResponse<CustomerDto>.FailResponse("Validation error", validation.Errors.Select(e => e.ErrorMessage));

        var merchant = await _unitOfWork.Merchants.GetByIdAsync(merchantId);
        if (merchant == null)
            return ApiResponse<CustomerDto>.FailResponse("Merchant not found");

        var count = await _unitOfWork.Customers.CountAsync(c => c.MerchantId == merchantId);
        if (count >= merchant.MaxCustomers)
            return ApiResponse<CustomerDto>.FailResponse("Customer limit reached");

        var existing = await _unitOfWork.Customers.FirstOrDefaultAsync(c => 
            c.MerchantId == merchantId && c.PhoneNumber == request.PhoneNumber);
        if (existing != null)
            return ApiResponse<CustomerDto>.FailResponse("Phone already registered");

        var customer = _mapper.Map<Customer>(request);
        customer.MerchantId = merchantId;
        customer.CustomerCode = $"C{(count + 1):D6}";

        await _unitOfWork.Customers.AddAsync(customer);
        await _unitOfWork.SaveChangesAsync();

        return ApiResponse<CustomerDto>.SuccessResponse(_mapper.Map<CustomerDto>(customer), "Customer created");
    }

    public async Task<ApiResponse<CustomerDto>> UpdateAsync(long id, Guid merchantId, UpdateCustomerRequest request)
    {
        var customer = await _unitOfWork.Customers.FirstOrDefaultAsync(c => c.Id == id && c.MerchantId == merchantId);
        if (customer == null)
            return ApiResponse<CustomerDto>.FailResponse("Customer not found");

        _mapper.Map(request, customer);
        _unitOfWork.Customers.Update(customer);
        await _unitOfWork.SaveChangesAsync();

        return ApiResponse<CustomerDto>.SuccessResponse(_mapper.Map<CustomerDto>(customer), "Customer updated");
    }

    public async Task<ApiResponse<bool>> DeleteAsync(long id, Guid merchantId)
    {
        var customer = await _unitOfWork.Customers.FirstOrDefaultAsync(c => c.Id == id && c.MerchantId == merchantId);
        if (customer == null)
            return ApiResponse<bool>.FailResponse("Customer not found");

        customer.IsDeleted = true;
        customer.DeletedAt = DateTime.UtcNow;
        _unitOfWork.Customers.Update(customer);
        await _unitOfWork.SaveChangesAsync();

        return ApiResponse<bool>.SuccessResponse(true, "Customer deleted");
    }
}

public interface IOrderService
{
    Task<ApiResponse<OrderDto>> GetByIdAsync(Guid id, Guid merchantId);
    Task<ApiResponse<PagedResponse<OrderDto>>> GetAllAsync(Guid merchantId, OrderFilterRequest filter);
    Task<ApiResponse<OrderDto>> CreateAsync(Guid merchantId, CreateOrderRequest request);
    Task<ApiResponse<OrderDto>> UpdateStatusAsync(Guid id, Guid merchantId, UpdateOrderStatusRequest request, string? changedBy = null);
}

public class OrderService : IOrderService
{
    private readonly IUnitOfWork _unitOfWork;
    private readonly IMapper _mapper;
    private readonly ILogger<OrderService> _logger;

    public OrderService(IUnitOfWork unitOfWork, IMapper mapper, ILogger<OrderService> logger)
    {
        _unitOfWork = unitOfWork;
        _mapper = mapper;
        _logger = logger;
    }

    public async Task<ApiResponse<OrderDto>> GetByIdAsync(Guid id, Guid merchantId)
    {
        var order = await _unitOfWork.Orders.FirstOrDefaultAsync(o => o.Id == id && o.MerchantId == merchantId);
        if (order == null)
            return ApiResponse<OrderDto>.FailResponse("Order not found");
        return ApiResponse<OrderDto>.SuccessResponse(_mapper.Map<OrderDto>(order));
    }

    public async Task<ApiResponse<PagedResponse<OrderDto>>> GetAllAsync(Guid merchantId, OrderFilterRequest filter)
    {
        var query = _unitOfWork.Orders.AsQueryable().Where(o => o.MerchantId == merchantId);

        if (filter.Status.HasValue)
            query = query.Where(o => o.Status == filter.Status.Value);

        if (filter.CustomerId.HasValue)
            query = query.Where(o => o.CustomerId == filter.CustomerId.Value);

        var totalCount = query.Count();
        var totalPages = (int)Math.Ceiling(totalCount / (double)filter.PageSize);

        var orders = query
            .OrderByDescending(o => o.CreatedAt)
            .Skip((filter.PageNumber - 1) * filter.PageSize)
            .Take(filter.PageSize)
            .ToList();

        return ApiResponse<PagedResponse<OrderDto>>.SuccessResponse(new PagedResponse<OrderDto>(
            _mapper.Map<IEnumerable<OrderDto>>(orders),
            totalCount,
            filter.PageNumber,
            filter.PageSize,
            totalPages
        ));
    }

    public async Task<ApiResponse<OrderDto>> CreateAsync(Guid merchantId, CreateOrderRequest request)
    {
        var customer = await _unitOfWork.Customers.FirstOrDefaultAsync(c => c.Id == request.CustomerId && c.MerchantId == merchantId);
        if (customer == null)
            return ApiResponse<OrderDto>.FailResponse("Customer not found");

        await _unitOfWork.BeginTransactionAsync();

        try
        {
            var order = new Order
            {
                Id = Guid.NewGuid(),
                MerchantId = merchantId,
                CustomerId = request.CustomerId,
                OrderNumber = $"ORD-{DateTime.UtcNow:yyyyMMdd}-{Random.Shared.Next(1000, 9999)}",
                Status = OrderStatus.Pending,
                DeliveryAddress = request.DeliveryAddress,
                DeliveryCity = request.DeliveryCity,
                DeliveryArea = request.DeliveryArea,
                Notes = request.Notes
            };

            decimal subTotal = 0;
            var items = new List<OrderItem>();

            foreach (var itemRequest in request.Items)
            {
                var product = await _unitOfWork.Products.GetByIdAsync(itemRequest.ProductId);
                if (product == null || product.MerchantId != merchantId)
                    return ApiResponse<OrderDto>.FailResponse($"Product {itemRequest.ProductId} not found");

                if (product.StockQuantity < itemRequest.Quantity)
                    return ApiResponse<OrderDto>.FailResponse($"Insufficient stock for {product.Name}");

                var unitPrice = product.DiscountPrice ?? product.Price;
                var item = new OrderItem
                {
                    Id = Guid.NewGuid(),
                    OrderId = order.Id,
                    ProductId = product.Id,
                    ProductName = product.Name,
                    ProductNameAr = product.NameAr,
                    UnitPrice = unitPrice,
                    Quantity = itemRequest.Quantity,
                    TotalPrice = unitPrice * itemRequest.Quantity,
                    Notes = itemRequest.Notes
                };

                items.Add(item);
                subTotal += item.TotalPrice;

                product.StockQuantity -= itemRequest.Quantity;
                product.SoldCount += itemRequest.Quantity;
                _unitOfWork.Products.Update(product);
            }

            order.Items = items;
            order.SubTotal = subTotal;
            order.TotalAmount = subTotal;

            customer.TotalOrders++;
            customer.TotalSpent += order.TotalAmount;
            customer.LastOrderDate = DateTime.UtcNow;
            _unitOfWork.Customers.Update(customer);

            await _unitOfWork.Orders.AddAsync(order);
            await _unitOfWork.CommitTransactionAsync();

            return ApiResponse<OrderDto>.SuccessResponse(_mapper.Map<OrderDto>(order), "Order created");
        }
        catch (Exception ex)
        {
            await _unitOfWork.RollbackTransactionAsync();
            _logger.LogError(ex, "Error creating order");
            return ApiResponse<OrderDto>.FailResponse("Error creating order");
        }
    }

    public async Task<ApiResponse<OrderDto>> UpdateStatusAsync(Guid id, Guid merchantId, UpdateOrderStatusRequest request, string? changedBy = null)
    {
        var order = await _unitOfWork.Orders.FirstOrDefaultAsync(o => o.Id == id && o.MerchantId == merchantId);
        if (order == null)
            return ApiResponse<OrderDto>.FailResponse("Order not found");

        order.Status = request.Status;
        if (request.Status == OrderStatus.Delivered)
            order.ActualDeliveryDate = DateTime.UtcNow;

        _unitOfWork.Orders.Update(order);
        await _unitOfWork.SaveChangesAsync();

        return ApiResponse<OrderDto>.SuccessResponse(_mapper.Map<OrderDto>(order), "Status updated");
    }
}
