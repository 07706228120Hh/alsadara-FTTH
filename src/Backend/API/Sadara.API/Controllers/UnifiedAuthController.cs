using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Microsoft.IdentityModel.Tokens;
using Sadara.Domain.Entities;
using Sadara.Domain.Enums;
using Sadara.Domain.Interfaces;
using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using System.Text;
using System.Text.Json;

namespace Sadara.API.Controllers;

/// <summary>
/// نظام مصادقة موحد لجميع أنواع المستخدمين
/// Unified Auth System - supports all user types:
/// - SuperAdmin / SystemAdmin (بدون كود شركة)
/// - CompanyAdmin / Employee / Technician (مع كود شركة)
/// - Citizen (بدون كود شركة)
/// </summary>
[ApiController]
[Route("api/v2/auth")]
[Consumes("application/json")]
[Produces("application/json")]
public class UnifiedAuthController : ControllerBase
{
    private readonly IUnitOfWork _unitOfWork;
    private readonly IConfiguration _configuration;
    private readonly ILogger<UnifiedAuthController> _logger;

    public UnifiedAuthController(
        IUnitOfWork unitOfWork,
        IConfiguration configuration,
        ILogger<UnifiedAuthController> logger)
    {
        _unitOfWork = unitOfWork;
        _configuration = configuration;
        _logger = logger;
    }

    #region Unified Login

    /// <summary>
    /// تسجيل دخول موحد لجميع المستخدمين
    /// </summary>
    /// <remarks>
    /// أمثلة:
    /// 
    /// **SuperAdmin/Citizen (بدون كود شركة):**
    /// ```json
    /// {
    ///   "username": "0770000000",
    ///   "password": "123456"
    /// }
    /// ```
    /// 
    /// **موظف شركة (مع كود شركة):**
    /// ```json
    /// {
    ///   "username": "0771234567",
    ///   "password": "123456",
    ///   "companyCode": "SADARA"
    /// }
    /// ```
    /// </remarks>
    [HttpPost("login")]
    [AllowAnonymous]
    public async Task<IActionResult> Login([FromBody] UnifiedLoginRequest request)
    {
        try
        {
            // التحقق من البيانات المطلوبة
            if (string.IsNullOrWhiteSpace(request.Username) || 
                string.IsNullOrWhiteSpace(request.Password))
            {
                return BadRequest(new UnifiedApiResponse<object>
                {
                    Success = false,
                    Message = "اسم المستخدم وكلمة المرور مطلوبان",
                    Code = "MISSING_CREDENTIALS"
                });
            }

            User? user = null;
            Company? company = null;

            // ============ تسجيل دخول مع كود شركة ============
            if (!string.IsNullOrWhiteSpace(request.CompanyCode))
            {
                // البحث عن الشركة
                company = await _unitOfWork.Companies.AsQueryable()
                    .FirstOrDefaultAsync(c => c.Code == request.CompanyCode && !c.IsDeleted);

                if (company == null)
                {
                    return Unauthorized(new UnifiedApiResponse<object>
                    {
                        Success = false,
                        Message = "كود الشركة غير صحيح",
                        Code = "INVALID_COMPANY_CODE"
                    });
                }

                // التحقق من حالة الشركة
                if (!company.IsActive)
                {
                    return Unauthorized(new UnifiedApiResponse<object>
                    {
                        Success = false,
                        Message = "الشركة معطلة",
                        Code = "COMPANY_DISABLED"
                    });
                }

                // التحقق من انتهاء الاشتراك
                if (company.SubscriptionEndDate < DateTime.UtcNow)
                {
                    return Unauthorized(new UnifiedApiResponse<object>
                    {
                        Success = false,
                        Message = "انتهى اشتراك الشركة",
                        Code = "SUBSCRIPTION_EXPIRED"
                    });
                }

                // البحث عن المستخدم في الشركة (بـ Username أو PhoneNumber أو Email أو EmployeeCode)
                user = await _unitOfWork.Users.AsQueryable()
                    .FirstOrDefaultAsync(u => 
                        u.CompanyId == company.Id &&
                        (u.Username == request.Username ||
                         u.PhoneNumber == request.Username || 
                         u.Email == request.Username || 
                         u.EmployeeCode == request.Username) &&
                        u.Role >= UserRole.Employee &&
                        !u.IsDeleted);
            }
            // ============ تسجيل دخول بدون كود شركة ============
            else
            {
                user = await _unitOfWork.Users.AsQueryable()
                    .Include(u => u.Company)
                    .FirstOrDefaultAsync(u => 
                        (u.Username == request.Username ||
                         u.PhoneNumber == request.Username || 
                         u.Email == request.Username) &&
                        !u.IsDeleted);

                // جلب الشركة إذا كان المستخدم تابع لشركة
                if (user?.Company != null)
                {
                    company = user.Company;
                }
            }

            // التحقق من وجود المستخدم
            if (user == null)
            {
                _logger.LogWarning("محاولة دخول فاشلة: {Username}", request.Username);
                return Unauthorized(new UnifiedApiResponse<object>
                {
                    Success = false,
                    Message = "اسم المستخدم أو كلمة المرور غير صحيحة",
                    Code = "INVALID_CREDENTIALS"
                });
            }

            // التحقق من الحالة
            if (!user.IsActive)
            {
                return Unauthorized(new UnifiedApiResponse<object>
                {
                    Success = false,
                    Message = "الحساب معطل",
                    Code = "ACCOUNT_DISABLED"
                });
            }

            // التحقق من القفل
            if (user.LockoutEnd.HasValue && user.LockoutEnd > DateTime.UtcNow)
            {
                var remainingTime = user.LockoutEnd.Value - DateTime.UtcNow;
                return Unauthorized(new UnifiedApiResponse<object>
                {
                    Success = false,
                    Message = $"الحساب مقفل. حاول بعد {remainingTime.Minutes} دقيقة",
                    Code = "ACCOUNT_LOCKED",
                    Data = new { lockoutMinutes = remainingTime.TotalMinutes }
                });
            }

            // التحقق من كلمة المرور
            if (!BCrypt.Net.BCrypt.Verify(request.Password, user.PasswordHash))
            {
                user.FailedLoginAttempts++;
                
                if (user.FailedLoginAttempts >= 5)
                {
                    user.LockoutEnd = DateTime.UtcNow.AddMinutes(30);
                    user.FailedLoginAttempts = 0;
                    _logger.LogWarning("تم قفل حساب: {UserId}", user.Id);
                }
                
                _unitOfWork.Users.Update(user);
                await _unitOfWork.SaveChangesAsync();
                
                return Unauthorized(new UnifiedApiResponse<object>
                {
                    Success = false,
                    Message = "اسم المستخدم أو كلمة المرور غير صحيحة",
                    Code = "INVALID_CREDENTIALS"
                });
            }

            // تسجيل الدخول ناجح
            user.FailedLoginAttempts = 0;
            user.LastLoginAt = DateTime.UtcNow;
            user.LockoutEnd = null;
            user.LastLoginDeviceInfo = request.DeviceInfo;
            
            // إنشاء التوكنات
            var token = GenerateJwtToken(user, company);
            var refreshToken = GenerateRefreshToken();
            
            user.RefreshToken = refreshToken;
            user.RefreshTokenExpiryTime = DateTime.UtcNow.AddDays(7);
            
            _unitOfWork.Users.Update(user);
            await _unitOfWork.SaveChangesAsync();

            _logger.LogInformation("تسجيل دخول ناجح: {UserId} ({Role})", user.Id, user.Role);

            return Ok(new UnifiedApiResponse<UnifiedLoginResponse>
            {
                Success = true,
                Message = "تم تسجيل الدخول بنجاح",
                Data = new UnifiedLoginResponse
                {
                    User = MapToUserResponse(user),
                    Company = company != null ? MapToCompanyResponse(company) : null,
                    Token = token,
                    RefreshToken = refreshToken,
                    ExpiresAt = DateTime.UtcNow.AddHours(24)
                }
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في تسجيل الدخول");
            return StatusCode(500, new UnifiedApiResponse<object>
            {
                Success = false,
                Message = "حدث خطأ في النظام",
                Code = "INTERNAL_ERROR"
            });
        }
    }

    #endregion

    #region Citizen Registration

    /// <summary>
    /// تسجيل مواطن جديد
    /// </summary>
    [HttpPost("register/citizen")]
    [AllowAnonymous]
    public async Task<IActionResult> RegisterCitizen([FromBody] CitizenRegistrationRequest request)
    {
        try
        {
            if (string.IsNullOrWhiteSpace(request.PhoneNumber) || 
                string.IsNullOrWhiteSpace(request.Password) ||
                string.IsNullOrWhiteSpace(request.FullName))
            {
                return BadRequest(new UnifiedApiResponse<object>
                {
                    Success = false,
                    Message = "جميع الحقول مطلوبة",
                    Code = "MISSING_FIELDS"
                });
            }

            // التحقق من عدم وجود المستخدم
            var existingUser = await _unitOfWork.Users.AsQueryable()
                .FirstOrDefaultAsync(u => u.PhoneNumber == request.PhoneNumber && !u.IsDeleted);

            if (existingUser != null)
            {
                return BadRequest(new UnifiedApiResponse<object>
                {
                    Success = false,
                    Message = "رقم الهاتف مسجل مسبقاً",
                    Code = "PHONE_EXISTS"
                });
            }

            // إنشاء المستخدم
            var user = new User
            {
                Id = Guid.NewGuid(),
                FullName = request.FullName,
                PhoneNumber = request.PhoneNumber,
                Email = request.Email,
                PasswordHash = BCrypt.Net.BCrypt.HashPassword(request.Password),
                Role = UserRole.Citizen,
                City = request.City,
                Area = request.Area,
                Address = request.Address,
                IsActive = true,
                CreatedAt = DateTime.UtcNow
            };

            await _unitOfWork.Users.AddAsync(user);
            await _unitOfWork.SaveChangesAsync();

            // إنشاء التوكن
            var token = GenerateJwtToken(user, null);
            var refreshToken = GenerateRefreshToken();
            
            user.RefreshToken = refreshToken;
            user.RefreshTokenExpiryTime = DateTime.UtcNow.AddDays(7);
            _unitOfWork.Users.Update(user);
            await _unitOfWork.SaveChangesAsync();

            _logger.LogInformation("تسجيل مواطن جديد: {UserId}", user.Id);

            return Ok(new UnifiedApiResponse<UnifiedLoginResponse>
            {
                Success = true,
                Message = "تم التسجيل بنجاح",
                Data = new UnifiedLoginResponse
                {
                    User = MapToUserResponse(user),
                    Company = null,
                    Token = token,
                    RefreshToken = refreshToken,
                    ExpiresAt = DateTime.UtcNow.AddHours(24)
                }
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في تسجيل مواطن");
            return StatusCode(500, new UnifiedApiResponse<object>
            {
                Success = false,
                Message = "حدث خطأ في النظام"
            });
        }
    }

    #endregion

    #region OTP Authentication

    /// <summary>
    /// إرسال رمز التحقق OTP
    /// </summary>
    [HttpPost("send-otp")]
    [AllowAnonymous]
    public async Task<IActionResult> SendOtp([FromBody] SendOtpRequest request)
    {
        try
        {
            if (string.IsNullOrWhiteSpace(request.PhoneNumber))
            {
                return BadRequest(new UnifiedApiResponse<object>
                {
                    Success = false,
                    Message = "رقم الهاتف مطلوب"
                });
            }

            var user = await _unitOfWork.Users.AsQueryable()
                .FirstOrDefaultAsync(u => u.PhoneNumber == request.PhoneNumber && !u.IsDeleted);

            if (user == null)
            {
                return NotFound(new UnifiedApiResponse<object>
                {
                    Success = false,
                    Message = "المستخدم غير موجود",
                    Code = "USER_NOT_FOUND"
                });
            }

            // توليد OTP
            var otp = new Random().Next(100000, 999999).ToString();
            user.VerificationCode = otp;
            user.VerificationCodeExpiresAt = DateTime.UtcNow.AddMinutes(5);
            
            _unitOfWork.Users.Update(user);
            await _unitOfWork.SaveChangesAsync();

            // TODO: إرسال OTP عبر SMS
            _logger.LogInformation("OTP sent to {Phone}: {OTP}", request.PhoneNumber, otp);

            return Ok(new UnifiedApiResponse<object>
            {
                Success = true,
                Message = "تم إرسال رمز التحقق",
                // في بيئة التطوير فقط
                Data = _configuration["Environment"] == "Development" ? new { otp } : null
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في إرسال OTP");
            return StatusCode(500, new UnifiedApiResponse<object>
            {
                Success = false,
                Message = "حدث خطأ في النظام"
            });
        }
    }

    /// <summary>
    /// تسجيل دخول بـ OTP
    /// </summary>
    [HttpPost("login-otp")]
    [AllowAnonymous]
    public async Task<IActionResult> LoginWithOtp([FromBody] OtpLoginRequest request)
    {
        try
        {
            if (string.IsNullOrWhiteSpace(request.PhoneNumber) || 
                string.IsNullOrWhiteSpace(request.Otp))
            {
                return BadRequest(new UnifiedApiResponse<object>
                {
                    Success = false,
                    Message = "رقم الهاتف ورمز التحقق مطلوبان"
                });
            }

            var user = await _unitOfWork.Users.AsQueryable()
                .Include(u => u.Company)
                .FirstOrDefaultAsync(u => u.PhoneNumber == request.PhoneNumber && !u.IsDeleted);

            if (user == null)
            {
                return Unauthorized(new UnifiedApiResponse<object>
                {
                    Success = false,
                    Message = "المستخدم غير موجود"
                });
            }

            // التحقق من OTP
            if (user.VerificationCode != request.Otp ||
                user.VerificationCodeExpiresAt < DateTime.UtcNow)
            {
                return Unauthorized(new UnifiedApiResponse<object>
                {
                    Success = false,
                    Message = "رمز التحقق غير صحيح أو منتهي",
                    Code = "INVALID_OTP"
                });
            }

            // مسح OTP
            user.VerificationCode = null;
            user.VerificationCodeExpiresAt = null;
            user.IsPhoneVerified = true;
            user.LastLoginAt = DateTime.UtcNow;

            // إنشاء التوكن
            var token = GenerateJwtToken(user, user.Company);
            var refreshToken = GenerateRefreshToken();
            
            user.RefreshToken = refreshToken;
            user.RefreshTokenExpiryTime = DateTime.UtcNow.AddDays(7);
            
            _unitOfWork.Users.Update(user);
            await _unitOfWork.SaveChangesAsync();

            return Ok(new UnifiedApiResponse<UnifiedLoginResponse>
            {
                Success = true,
                Message = "تم تسجيل الدخول بنجاح",
                Data = new UnifiedLoginResponse
                {
                    User = MapToUserResponse(user),
                    Company = user.Company != null ? MapToCompanyResponse(user.Company) : null,
                    Token = token,
                    RefreshToken = refreshToken,
                    ExpiresAt = DateTime.UtcNow.AddHours(24)
                }
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في تسجيل دخول OTP");
            return StatusCode(500, new UnifiedApiResponse<object>
            {
                Success = false,
                Message = "حدث خطأ في النظام"
            });
        }
    }

    #endregion

    #region Token Management

    /// <summary>
    /// تحديث التوكن
    /// </summary>
    [HttpPost("refresh-token")]
    [AllowAnonymous]
    public async Task<IActionResult> RefreshToken([FromBody] UnifiedRefreshTokenRequest request)
    {
        try
        {
            var user = await _unitOfWork.Users.AsQueryable()
                .Include(u => u.Company)
                .FirstOrDefaultAsync(u => 
                    u.RefreshToken == request.RefreshToken &&
                    u.RefreshTokenExpiryTime > DateTime.UtcNow &&
                    !u.IsDeleted);

            if (user == null)
            {
                return Unauthorized(new UnifiedApiResponse<object>
                {
                    Success = false,
                    Message = "التوكن غير صالح أو منتهي",
                    Code = "INVALID_TOKEN"
                });
            }

            var newToken = GenerateJwtToken(user, user.Company);
            var newRefreshToken = GenerateRefreshToken();

            user.RefreshToken = newRefreshToken;
            user.RefreshTokenExpiryTime = DateTime.UtcNow.AddDays(7);
            _unitOfWork.Users.Update(user);
            await _unitOfWork.SaveChangesAsync();

            return Ok(new UnifiedApiResponse<UnifiedLoginResponse>
            {
                Success = true,
                Message = "تم تحديث التوكن",
                Data = new UnifiedLoginResponse
                {
                    User = MapToUserResponse(user),
                    Company = user.Company != null ? MapToCompanyResponse(user.Company) : null,
                    Token = newToken,
                    RefreshToken = newRefreshToken,
                    ExpiresAt = DateTime.UtcNow.AddHours(24)
                }
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في تحديث التوكن");
            return StatusCode(500, new UnifiedApiResponse<object>
            {
                Success = false,
                Message = "حدث خطأ في النظام"
            });
        }
    }

    /// <summary>
    /// تسجيل الخروج
    /// </summary>
    [HttpPost("logout")]
    [Authorize]
    public async Task<IActionResult> Logout()
    {
        try
        {
            var userId = User.FindFirst(ClaimTypes.NameIdentifier)?.Value;
            if (string.IsNullOrEmpty(userId))
            {
                return Unauthorized();
            }

            var user = await _unitOfWork.Users.AsQueryable()
                .FirstOrDefaultAsync(u => u.Id == Guid.Parse(userId));

            if (user != null)
            {
                user.RefreshToken = null;
                user.RefreshTokenExpiryTime = null;
                _unitOfWork.Users.Update(user);
                await _unitOfWork.SaveChangesAsync();
            }

            return Ok(new UnifiedApiResponse<object>
            {
                Success = true,
                Message = "تم تسجيل الخروج بنجاح"
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في تسجيل الخروج");
            return StatusCode(500, new UnifiedApiResponse<object>
            {
                Success = false,
                Message = "حدث خطأ في النظام"
            });
        }
    }

    #endregion

    #region Get Current User

    /// <summary>
    /// الحصول على بيانات المستخدم الحالي
    /// </summary>
    [HttpGet("me")]
    [Authorize]
    public async Task<IActionResult> GetCurrentUser()
    {
        try
        {
            var userId = User.FindFirst(ClaimTypes.NameIdentifier)?.Value;
            if (string.IsNullOrEmpty(userId))
            {
                return Unauthorized();
            }

            var user = await _unitOfWork.Users.AsQueryable()
                .Include(u => u.Company)
                .FirstOrDefaultAsync(u => u.Id == Guid.Parse(userId) && !u.IsDeleted);

            if (user == null)
            {
                return NotFound(new UnifiedApiResponse<object>
                {
                    Success = false,
                    Message = "المستخدم غير موجود"
                });
            }

            return Ok(new UnifiedApiResponse<UnifiedUserResponse>
            {
                Success = true,
                Data = MapToUserResponse(user)
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في جلب بيانات المستخدم");
            return StatusCode(500, new UnifiedApiResponse<object>
            {
                Success = false,
                Message = "حدث خطأ في النظام"
            });
        }
    }

    #endregion

    #region Password Management

    /// <summary>
    /// تغيير كلمة المرور
    /// </summary>
    [HttpPost("change-password")]
    [Authorize]
    public async Task<IActionResult> ChangePassword([FromBody] UnifiedChangePasswordRequest request)
    {
        try
        {
            var userId = User.FindFirst(ClaimTypes.NameIdentifier)?.Value;
            if (string.IsNullOrEmpty(userId))
            {
                return Unauthorized();
            }

            var user = await _unitOfWork.Users.AsQueryable()
                .FirstOrDefaultAsync(u => u.Id == Guid.Parse(userId) && !u.IsDeleted);

            if (user == null)
            {
                return NotFound();
            }

            if (!BCrypt.Net.BCrypt.Verify(request.CurrentPassword, user.PasswordHash))
            {
                return BadRequest(new UnifiedApiResponse<object>
                {
                    Success = false,
                    Message = "كلمة المرور الحالية غير صحيحة"
                });
            }

            user.PasswordHash = BCrypt.Net.BCrypt.HashPassword(request.NewPassword);
            _unitOfWork.Users.Update(user);
            await _unitOfWork.SaveChangesAsync();

            return Ok(new UnifiedApiResponse<object>
            {
                Success = true,
                Message = "تم تغيير كلمة المرور بنجاح"
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في تغيير كلمة المرور");
            return StatusCode(500, new UnifiedApiResponse<object>
            {
                Success = false,
                Message = "حدث خطأ في النظام"
            });
        }
    }

    /// <summary>
    /// طلب إعادة تعيين كلمة المرور
    /// </summary>
    [HttpPost("forgot-password")]
    [AllowAnonymous]
    public async Task<IActionResult> ForgotPassword([FromBody] UnifiedForgotPasswordRequest request)
    {
        try
        {
            var user = await _unitOfWork.Users.AsQueryable()
                .FirstOrDefaultAsync(u => u.PhoneNumber == request.PhoneNumber && !u.IsDeleted);

            if (user == null)
            {
                // لا نكشف وجود المستخدم
                return Ok(new UnifiedApiResponse<object>
                {
                    Success = true,
                    Message = "إذا كان رقم الهاتف مسجلاً، سيتم إرسال رمز التحقق"
                });
            }

            var otp = new Random().Next(100000, 999999).ToString();
            user.VerificationCode = otp;
            user.VerificationCodeExpiresAt = DateTime.UtcNow.AddMinutes(10);
            
            _unitOfWork.Users.Update(user);
            await _unitOfWork.SaveChangesAsync();

            // TODO: إرسال OTP عبر SMS
            _logger.LogInformation("Password reset OTP sent to {Phone}", request.PhoneNumber);

            return Ok(new UnifiedApiResponse<object>
            {
                Success = true,
                Message = "تم إرسال رمز التحقق",
                Data = _configuration["Environment"] == "Development" ? new { otp } : null
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في طلب إعادة تعيين كلمة المرور");
            return StatusCode(500, new UnifiedApiResponse<object>
            {
                Success = false,
                Message = "حدث خطأ في النظام"
            });
        }
    }

    /// <summary>
    /// إعادة تعيين كلمة المرور بـ OTP
    /// </summary>
    [HttpPost("reset-password")]
    [AllowAnonymous]
    public async Task<IActionResult> ResetPassword([FromBody] UnifiedResetPasswordRequest request)
    {
        try
        {
            var user = await _unitOfWork.Users.AsQueryable()
                .FirstOrDefaultAsync(u => 
                    u.PhoneNumber == request.PhoneNumber && 
                    u.VerificationCode == request.Otp &&
                    u.VerificationCodeExpiresAt > DateTime.UtcNow &&
                    !u.IsDeleted);

            if (user == null)
            {
                return BadRequest(new UnifiedApiResponse<object>
                {
                    Success = false,
                    Message = "رمز التحقق غير صحيح أو منتهي"
                });
            }

            user.PasswordHash = BCrypt.Net.BCrypt.HashPassword(request.NewPassword);
            user.VerificationCode = null;
            user.VerificationCodeExpiresAt = null;
            user.FailedLoginAttempts = 0;
            user.LockoutEnd = null;
            
            _unitOfWork.Users.Update(user);
            await _unitOfWork.SaveChangesAsync();

            return Ok(new UnifiedApiResponse<object>
            {
                Success = true,
                Message = "تم إعادة تعيين كلمة المرور بنجاح"
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في إعادة تعيين كلمة المرور");
            return StatusCode(500, new UnifiedApiResponse<object>
            {
                Success = false,
                Message = "حدث خطأ في النظام"
            });
        }
    }

    #endregion

    #region Profile Management

    /// <summary>
    /// تحديث بيانات الملف الشخصي
    /// </summary>
    [HttpPut("profile")]
    [Authorize]
    public async Task<IActionResult> UpdateProfile([FromBody] UnifiedUpdateProfileRequest request)
    {
        try
        {
            var userId = User.FindFirst(ClaimTypes.NameIdentifier)?.Value;
            if (string.IsNullOrEmpty(userId))
            {
                return Unauthorized();
            }

            var user = await _unitOfWork.Users.AsQueryable()
                .FirstOrDefaultAsync(u => u.Id == Guid.Parse(userId) && !u.IsDeleted);

            if (user == null)
            {
                return NotFound();
            }

            // التحقق من عدم تكرار اسم المستخدم
            if (!string.IsNullOrEmpty(request.Username))
            {
                var existingUser = await _unitOfWork.Users.AsQueryable()
                    .FirstOrDefaultAsync(u => u.Username == request.Username && u.Id != user.Id && !u.IsDeleted);

                if (existingUser != null)
                {
                    return BadRequest(new UnifiedApiResponse<object>
                    {
                        Success = false,
                        Message = "اسم المستخدم مستخدم من قبل"
                    });
                }
                user.Username = request.Username;
            }

            // تحديث البيانات الأخرى
            if (!string.IsNullOrEmpty(request.FullName))
                user.FullName = request.FullName;
            
            if (!string.IsNullOrEmpty(request.Email))
                user.Email = request.Email;
            
            if (!string.IsNullOrEmpty(request.City))
                user.City = request.City;
            
            if (!string.IsNullOrEmpty(request.Area))
                user.Area = request.Area;
            
            if (!string.IsNullOrEmpty(request.Address))
                user.Address = request.Address;

            user.UpdatedAt = DateTime.UtcNow;
            _unitOfWork.Users.Update(user);
            await _unitOfWork.SaveChangesAsync();

            return Ok(new UnifiedApiResponse<UnifiedUserResponse>
            {
                Success = true,
                Message = "تم تحديث البيانات بنجاح",
                Data = new UnifiedUserResponse
                {
                    Id = user.Id,
                    FullName = user.FullName,
                    Username = user.Username,
                    PhoneNumber = user.PhoneNumber,
                    Email = user.Email,
                    Role = user.Role.ToString(),
                    RoleId = (int)user.Role,
                    UserType = GetUserType(user.Role),
                    CompanyId = user.CompanyId,
                    City = user.City,
                    Area = user.Area,
                    Address = user.Address
                }
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في تحديث الملف الشخصي");
            return StatusCode(500, new UnifiedApiResponse<object>
            {
                Success = false,
                Message = "حدث خطأ في النظام"
            });
        }
    }

    /// <summary>
    /// تحديث اسم المستخدم فقط
    /// </summary>
    [HttpPut("profile/username")]
    [Authorize]
    public async Task<IActionResult> UpdateUsername([FromBody] UnifiedUpdateUsernameRequest request)
    {
        try
        {
            var userId = User.FindFirst(ClaimTypes.NameIdentifier)?.Value;
            if (string.IsNullOrEmpty(userId))
            {
                return Unauthorized();
            }

            var user = await _unitOfWork.Users.AsQueryable()
                .FirstOrDefaultAsync(u => u.Id == Guid.Parse(userId) && !u.IsDeleted);

            if (user == null)
            {
                return NotFound();
            }

            // التحقق من صحة اسم المستخدم
            if (string.IsNullOrEmpty(request.NewUsername) || request.NewUsername.Length < 4)
            {
                return BadRequest(new UnifiedApiResponse<object>
                {
                    Success = false,
                    Message = "اسم المستخدم يجب أن يكون 4 أحرف على الأقل"
                });
            }

            // التحقق من عدم وجود أحرف خاصة
            if (!System.Text.RegularExpressions.Regex.IsMatch(request.NewUsername, @"^[a-zA-Z0-9_]+$"))
            {
                return BadRequest(new UnifiedApiResponse<object>
                {
                    Success = false,
                    Message = "اسم المستخدم يمكن أن يحتوي على أحرف وأرقام و _ فقط"
                });
            }

            // التحقق من عدم تكرار اسم المستخدم
            var existingUser = await _unitOfWork.Users.AsQueryable()
                .FirstOrDefaultAsync(u => u.Username == request.NewUsername && u.Id != user.Id && !u.IsDeleted);

            if (existingUser != null)
            {
                return BadRequest(new UnifiedApiResponse<object>
                {
                    Success = false,
                    Message = "اسم المستخدم مستخدم من قبل"
                });
            }

            user.Username = request.NewUsername;
            user.UpdatedAt = DateTime.UtcNow;
            _unitOfWork.Users.Update(user);
            await _unitOfWork.SaveChangesAsync();

            return Ok(new UnifiedApiResponse<object>
            {
                Success = true,
                Message = "تم تحديث اسم المستخدم بنجاح",
                Data = new { Username = user.Username }
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في تحديث اسم المستخدم");
            return StatusCode(500, new UnifiedApiResponse<object>
            {
                Success = false,
                Message = "حدث خطأ في النظام"
            });
        }
    }

    #endregion

    #region SuperAdmin Setup

    /// <summary>
    /// إنشاء SuperAdmin (مرة واحدة فقط - للإعداد الأولي)
    /// </summary>
    [HttpPost("setup/super-admin")]
    [AllowAnonymous]
    public async Task<IActionResult> SetupSuperAdmin([FromBody] SuperAdminSetupRequest request)
    {
        try
        {
            var setupKey = _configuration["SuperAdminSetupKey"] ?? "SADARA-SETUP-2026-SECURE";
            if (request.SetupKey != setupKey)
            {
                return Unauthorized(new UnifiedApiResponse<object>
                {
                    Success = false,
                    Message = "مفتاح الإعداد غير صحيح"
                });
            }

            var existingSuperAdmin = await _unitOfWork.Users.AsQueryable()
                .AnyAsync(u => u.Role == UserRole.SuperAdmin && !u.IsDeleted);

            if (existingSuperAdmin)
            {
                return BadRequest(new UnifiedApiResponse<object>
                {
                    Success = false,
                    Message = "يوجد SuperAdmin بالفعل"
                });
            }

            var superAdmin = new User
            {
                Id = Guid.NewGuid(),
                FullName = request.FullName,
                PhoneNumber = request.PhoneNumber,
                Email = request.Email,
                PasswordHash = BCrypt.Net.BCrypt.HashPassword(request.Password),
                Role = UserRole.SuperAdmin,
                IsActive = true,
                IsPhoneVerified = true,
                CreatedAt = DateTime.UtcNow
            };

            await _unitOfWork.Users.AddAsync(superAdmin);
            await _unitOfWork.SaveChangesAsync();

            _logger.LogWarning("تم إنشاء SuperAdmin جديد: {UserId}", superAdmin.Id);

            return Ok(new UnifiedApiResponse<object>
            {
                Success = true,
                Message = "تم إنشاء SuperAdmin بنجاح",
                Data = new { id = superAdmin.Id }
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في إنشاء SuperAdmin");
            return StatusCode(500, new UnifiedApiResponse<object>
            {
                Success = false,
                Message = "حدث خطأ في النظام"
            });
        }
    }

    #endregion

    #region Helper Methods

    private string GenerateJwtToken(User user, Company? company)
    {
        var key = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(
            _configuration["Jwt:Secret"] ?? _configuration["Jwt:Key"] ?? "YourSuperSecretKeyThatIsAtLeast32CharactersLong!"));
        var credentials = new SigningCredentials(key, SecurityAlgorithms.HmacSha256);

        var claims = new List<Claim>
        {
            new(ClaimTypes.NameIdentifier, user.Id.ToString()),
            new(ClaimTypes.Name, user.FullName),
            new(ClaimTypes.MobilePhone, user.PhoneNumber),
            new(ClaimTypes.Role, user.Role.ToString()),
            new("role_id", ((int)user.Role).ToString()),
            new("user_type", GetUserType(user.Role))
        };

        if (!string.IsNullOrEmpty(user.Email))
            claims.Add(new Claim(ClaimTypes.Email, user.Email));

        if (company != null)
        {
            claims.Add(new Claim("company_id", company.Id.ToString()));
            claims.Add(new Claim("company_code", company.Code));
            claims.Add(new Claim("company_name", company.Name));
        }

        var token = new JwtSecurityToken(
            issuer: _configuration["Jwt:Issuer"] ?? "SadaraPlatform",
            audience: _configuration["Jwt:Audience"] ?? "SadaraClients",
            claims: claims,
            expires: DateTime.UtcNow.AddHours(24),
            signingCredentials: credentials
        );

        return new JwtSecurityTokenHandler().WriteToken(token);
    }

    private static string GenerateRefreshToken()
    {
        var randomBytes = new byte[64];
        using var rng = System.Security.Cryptography.RandomNumberGenerator.Create();
        rng.GetBytes(randomBytes);
        return Convert.ToBase64String(randomBytes);
    }

    private static string GetUserType(UserRole role)
    {
        return role switch
        {
            UserRole.SuperAdmin => "super_admin",
            UserRole.CompanyAdmin => "company_admin",
            UserRole.Manager => "manager",
            UserRole.TechnicalLeader => "technical_leader",
            UserRole.Technician => "technician",
            UserRole.Employee => "employee",
            UserRole.Viewer => "viewer",
            UserRole.Citizen => "citizen",
            UserRole.Merchant => "merchant",
            UserRole.Driver => "driver",
            _ => "unknown"
        };
    }

    private static UnifiedUserResponse MapToUserResponse(User user)
    {
        return new UnifiedUserResponse
        {
            Id = user.Id,
            FullName = user.FullName,
            Username = user.Username,
            PhoneNumber = user.PhoneNumber,
            Email = user.Email,
            Role = user.Role.ToString(),
            RoleId = (int)user.Role,
            UserType = GetUserType(user.Role),
            ProfileImageUrl = user.ProfileImageUrl,
            IsActive = user.IsActive,
            IsPhoneVerified = user.IsPhoneVerified,
            CompanyId = user.CompanyId,
            Department = user.Department,
            EmployeeCode = user.EmployeeCode,
            City = user.City,
            Area = user.Area,
            Address = user.Address,
            FirstSystemPermissions = user.FirstSystemPermissions,
            SecondSystemPermissions = user.SecondSystemPermissions,
            FirstSystemPermissionsV2 = user.FirstSystemPermissionsV2,
            SecondSystemPermissionsV2 = user.SecondSystemPermissionsV2,
            LastLoginAt = user.LastLoginAt
        };
    }

    private static UnifiedCompanyResponse MapToCompanyResponse(Company company)
    {
        return new UnifiedCompanyResponse
        {
            Id = company.Id,
            Name = company.Name,
            Code = company.Code,
            LogoUrl = company.LogoUrl,
            SubscriptionEndDate = company.SubscriptionEndDate,
            EnabledFirstSystemFeatures = company.EnabledFirstSystemFeatures,
            EnabledSecondSystemFeatures = company.EnabledSecondSystemFeatures
        };
    }

    #endregion
}

#region Unified Auth DTOs

public class UnifiedApiResponse<T>
{
    public bool Success { get; set; }
    public string? Message { get; set; }
    public string? Code { get; set; }
    public T? Data { get; set; }
}

public class UnifiedLoginRequest
{
    /// <summary>رقم الهاتف أو البريد أو كود الموظف</summary>
    public string Username { get; set; } = string.Empty;
    
    /// <summary>كلمة المرور</summary>
    public string Password { get; set; } = string.Empty;
    
    /// <summary>كود الشركة (اختياري - للموظفين فقط)</summary>
    public string? CompanyCode { get; set; }
    
    /// <summary>معلومات الجهاز</summary>
    public string? DeviceInfo { get; set; }
}

public class UnifiedLoginResponse
{
    public UnifiedUserResponse User { get; set; } = new();
    public UnifiedCompanyResponse? Company { get; set; }
    public string Token { get; set; } = string.Empty;
    public string RefreshToken { get; set; } = string.Empty;
    public DateTime ExpiresAt { get; set; }
}

public class UnifiedUserResponse
{
    public Guid Id { get; set; }
    public string FullName { get; set; } = string.Empty;
    public string? Username { get; set; }
    public string PhoneNumber { get; set; } = string.Empty;
    public string? Email { get; set; }
    public string Role { get; set; } = string.Empty;
    public int RoleId { get; set; }
    public string UserType { get; set; } = string.Empty;
    public string? ProfileImageUrl { get; set; }
    public bool IsActive { get; set; }
    public bool IsPhoneVerified { get; set; }
    public Guid? CompanyId { get; set; }
    public string? Department { get; set; }
    public string? EmployeeCode { get; set; }
    public string? City { get; set; }
    public string? Area { get; set; }
    public string? Address { get; set; }
    public string? FirstSystemPermissions { get; set; }
    public string? SecondSystemPermissions { get; set; }
    public string? FirstSystemPermissionsV2 { get; set; }
    public string? SecondSystemPermissionsV2 { get; set; }
    public DateTime? LastLoginAt { get; set; }
}

public class UnifiedCompanyResponse
{
    public Guid Id { get; set; }
    public string Name { get; set; } = string.Empty;
    public string Code { get; set; } = string.Empty;
    public string? LogoUrl { get; set; }
    public DateTime? SubscriptionEndDate { get; set; }
    public string? EnabledFirstSystemFeatures { get; set; }
    public string? EnabledSecondSystemFeatures { get; set; }
}

public class CitizenRegistrationRequest
{
    public string FullName { get; set; } = string.Empty;
    public string PhoneNumber { get; set; } = string.Empty;
    public string Password { get; set; } = string.Empty;
    public string? Email { get; set; }
    public string? City { get; set; }
    public string? Area { get; set; }
    public string? Address { get; set; }
}

public class SendOtpRequest
{
    public string PhoneNumber { get; set; } = string.Empty;
}

public class OtpLoginRequest
{
    public string PhoneNumber { get; set; } = string.Empty;
    public string Otp { get; set; } = string.Empty;
}

public class UnifiedRefreshTokenRequest
{
    public string RefreshToken { get; set; } = string.Empty;
}

public class UnifiedChangePasswordRequest
{
    public string CurrentPassword { get; set; } = string.Empty;
    public string NewPassword { get; set; } = string.Empty;
}

public class UnifiedForgotPasswordRequest
{
    public string PhoneNumber { get; set; } = string.Empty;
}

public class UnifiedResetPasswordRequest
{
    public string PhoneNumber { get; set; } = string.Empty;
    public string Otp { get; set; } = string.Empty;
    public string NewPassword { get; set; } = string.Empty;
}

public class SuperAdminSetupRequest
{
    public string SetupKey { get; set; } = string.Empty;
    public string FullName { get; set; } = string.Empty;
    public string PhoneNumber { get; set; } = string.Empty;
    public string? Email { get; set; }
    public string Password { get; set; } = string.Empty;
}

public class UnifiedUpdateProfileRequest
{
    public string? Username { get; set; }
    public string? FullName { get; set; }
    public string? Email { get; set; }
    public string? City { get; set; }
    public string? Area { get; set; }
    public string? Address { get; set; }
}

public class UnifiedUpdateUsernameRequest
{
    public string NewUsername { get; set; } = string.Empty;
}

#endregion
