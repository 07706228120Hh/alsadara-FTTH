using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Microsoft.IdentityModel.Tokens;
using Sadara.Domain.Entities;
using Sadara.Infrastructure.Data;
using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;

namespace Sadara.API.Controllers;

/// <summary>
/// مصادقة المواطنين - تسجيل دخول/خروج، إنشاء حساب
/// </summary>
[ApiController]
[Route("api/citizen")]
[Tags("Citizen Auth")]
public class CitizenAuthController : ControllerBase
{
    private readonly SadaraDbContext _context;
    private readonly IConfiguration _configuration;
    private readonly ILogger<CitizenAuthController> _logger;

    public CitizenAuthController(
        SadaraDbContext context,
        IConfiguration configuration,
        ILogger<CitizenAuthController> logger)
    {
        _context = context;
        _configuration = configuration;
        _logger = logger;
    }

    // ==================== دوال مساعدة للتحقق من رقم الهاتف ====================

    /// <summary>
    /// تنظيف رقم الهاتف وإرجاعه بالصيغة الدولية
    /// يدعم الأرقام السعودية (+966) والعراقية (+964)
    /// </summary>
    private (string? fullPhone, string? error, string? errorAr) NormalizePhoneNumber(string phoneNumber)
    {
        if (string.IsNullOrWhiteSpace(phoneNumber))
            return (null, "Phone number is required", "رقم الهاتف مطلوب");

        // إزالة جميع الأحرف غير الرقمية
        var cleanPhone = Regex.Replace(phoneNumber, @"[^\d]", "");

        // === الأرقام العراقية ===
        // الأشكال المدعومة:
        // +964 7xx xxx xxxx, 00964 7xx xxx xxxx, 964 7xx xxx xxxx
        // 07xx xxx xxxx, 7xx xxx xxxx
        if (cleanPhone.StartsWith("964"))
        {
            cleanPhone = cleanPhone.Substring(3); // إزالة 964
        }
        else if (cleanPhone.StartsWith("00964"))
        {
            cleanPhone = cleanPhone.Substring(5); // إزالة 00964
        }

        // إذا كان الرقم يبدأ بـ 07 (عراقي) أو 7 بدون الصفر
        if (cleanPhone.StartsWith("07") || (cleanPhone.StartsWith("7") && cleanPhone.Length == 10))
        {
            if (cleanPhone.StartsWith("0"))
                cleanPhone = cleanPhone.Substring(1); // إزالة الصفر

            // التحقق من صحة الرقم العراقي (10 أرقام تبدأ بـ 7)
            if (cleanPhone.Length == 10 && cleanPhone.StartsWith("7"))
            {
                // التحقق من أنه أحد أكواد شركات الاتصالات العراقية
                // 750-759 (Korek), 770-779 (Asia Cell), 780-789 (Zain), 790-799 (Various)
                var prefix = cleanPhone.Substring(0, 3);
                var validPrefixes = new[] { "750", "751", "752", "753", "754", "755", "756", "757", "758", "759",
                                            "770", "771", "772", "773", "774", "775", "776", "777", "778", "779",
                                            "780", "781", "782", "783", "784", "785", "786", "787", "788", "789",
                                            "790", "791", "792", "793", "794", "795", "796", "797", "798", "799" };

                if (validPrefixes.Contains(prefix))
                {
                    return ($"+964{cleanPhone}", null, null);
                }
            }
        }

        // === الأرقام السعودية ===
        // الأشكال المدعومة:
        // +966 5x xxx xxxx, 00966 5x xxx xxxx, 966 5x xxx xxxx
        // 05x xxx xxxx, 5x xxx xxxx
        if (cleanPhone.StartsWith("966"))
        {
            cleanPhone = cleanPhone.Substring(3); // إزالة 966
        }
        else if (cleanPhone.StartsWith("00966"))
        {
            cleanPhone = cleanPhone.Substring(5); // إزالة 00966
        }

        if (cleanPhone.StartsWith("0"))
            cleanPhone = cleanPhone.Substring(1); // إزالة الصفر

        // التحقق من صحة الرقم السعودي (9 أرقام تبدأ بـ 5)
        if (cleanPhone.Length == 9 && cleanPhone.StartsWith("5"))
        {
            return ($"+966{cleanPhone}", null, null);
        }

        // إذا لم يتطابق مع أي صيغة
        return (null, "Invalid phone number. Supported: Saudi (+966 05xxxxxxxx) or Iraqi (+964 07xxxxxxxxx)", 
                "رقم الهاتف غير صحيح. الأرقام المدعومة: سعودي (+966 05xxxxxxxx) أو عراقي (+964 07xxxxxxxxx)");
    }

    // ==================== التسجيل والتفعيل ====================

    /// <summary>
    /// تسجيل مواطن جديد
    /// </summary>
    [HttpPost("register")]
    public async Task<IActionResult> Register([FromBody] CitizenRegisterRequest request)
    {
        try
        {
            // التحقق من رقم الهاتف وتنظيفه (يدعم السعودي والعراقي)
            var (fullPhone, error, errorAr) = NormalizePhoneNumber(request.PhoneNumber);
            if (fullPhone == null)
                return BadRequest(new { success = false, messageAr = errorAr, message = error });

            // التحقق من عدم وجود الرقم
            var existingCitizen = await _context.Citizens.FirstOrDefaultAsync(c => c.PhoneNumber == fullPhone);
            if (existingCitizen != null)
            {
                if (existingCitizen.IsBanned)
                    return BadRequest(new { success = false, messageAr = "هذا الحساب محظور", message = "This account is banned" });

                if (existingCitizen.IsPhoneVerified)
                    return BadRequest(new { success = false, messageAr = "رقم الهاتف مسجل مسبقاً", message = "Phone number already registered" });

                // إذا كان غير مفعل، نحذفه ونسجل من جديد
                _context.Citizens.Remove(existingCitizen);
            }

            // البحث عن الشركة المرتبطة بنظام المواطن
            var linkedCompany = await _context.Companies
                .FirstOrDefaultAsync(c => c.IsLinkedToCitizenPortal && c.IsActive);

            if (linkedCompany == null)
            {
                _logger.LogWarning("No company linked to citizen portal. Creating citizen without company.");
            }

            // إنشاء المواطن
            var citizen = new Citizen
            {
                Id = Guid.NewGuid(),
                FullName = request.FullName,
                PhoneNumber = fullPhone,
                PasswordHash = HashPassword(request.Password),
                Email = request.Email,
                City = request.City,
                District = request.District,
                FullAddress = request.Address,
                CompanyId = linkedCompany?.Id, // ربط بالشركة المرتبطة بنظام المواطن (nullable)
                AssignedToCompanyAt = linkedCompany != null ? DateTime.UtcNow : null,
                IsActive = false, // غير نشط حتى يتم التفعيل
                IsPhoneVerified = false,
                LanguagePreference = request.Language ?? "ar"
            };

            _context.Citizens.Add(citizen);
            await _context.SaveChangesAsync();

            // TODO: إرسال كود OTP للهاتف
            var otp = GenerateOTP();
            citizen.VerificationCode = otp;
            citizen.VerificationCodeExpiresAt = DateTime.UtcNow.AddMinutes(10);
            await _context.SaveChangesAsync();

            _logger.LogInformation("New citizen registered: {Phone}, OTP: {OTP}", fullPhone, otp);

            return Ok(new
            {
                success = true,
                messageAr = "تم التسجيل بنجاح. تم إرسال كود التفعيل",
                message = "Registration successful. Verification code sent",
                citizenId = citizen.Id,
                // في الإنتاج، لا ترسل OTP في الرد
                debugOtp = otp // للتطوير فقط
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error in citizen registration");
            return StatusCode(500, new { success = false, messageAr = "حدث خطأ أثناء التسجيل", message = "Registration error" });
        }
    }

    /// <summary>
    /// تفعيل رقم الهاتف بالكود
    /// </summary>
    [HttpPost("verify-phone")]
    public async Task<IActionResult> VerifyPhone([FromBody] VerifyPhoneRequest request)
    {
        try
        {
            var citizen = await _context.Citizens.FirstOrDefaultAsync(c => c.Id == request.CitizenId);
            if (citizen == null)
                return NotFound(new { success = false, messageAr = "المستخدم غير موجود", message = "User not found" });

            if (citizen.IsPhoneVerified)
                return BadRequest(new { success = false, messageAr = "الهاتف مفعل مسبقاً", message = "Phone already verified" });

            if (citizen.VerificationCode != request.Code)
                return BadRequest(new { success = false, messageAr = "الكود غير صحيح", message = "Invalid code" });

            if (citizen.VerificationCodeExpiresAt < DateTime.UtcNow)
                return BadRequest(new { success = false, messageAr = "انتهت صلاحية الكود", message = "Code expired" });

            citizen.IsPhoneVerified = true;
            citizen.IsActive = true;
            citizen.VerificationCode = null;
            citizen.VerificationCodeExpiresAt = null;
            citizen.UpdatedAt = DateTime.UtcNow;

            await _context.SaveChangesAsync();

            // إنشاء JWT token
            var token = GenerateJwtToken(citizen);

            return Ok(new
            {
                success = true,
                messageAr = "تم تفعيل الحساب بنجاح",
                message = "Account activated successfully",
                token,
                citizen = new CitizenProfileResponse
                {
                    Id = citizen.Id,
                    FullName = citizen.FullName,
                    PhoneNumber = citizen.PhoneNumber,
                    Email = citizen.Email,
                    City = citizen.City,
                    District = citizen.District,
                    CompanyId = citizen.CompanyId,
                    HasCompany = true
                }
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error verifying phone");
            return StatusCode(500, new { success = false, messageAr = "حدث خطأ", message = "Error occurred" });
        }
    }

    /// <summary>
    /// إعادة إرسال كود التفعيل
    /// </summary>
    [HttpPost("resend-otp")]
    public async Task<IActionResult> ResendOTP([FromBody] ResendOTPRequest request)
    {
        try
        {
            var citizen = await _context.Citizens.FirstOrDefaultAsync(c => c.Id == request.CitizenId);
            if (citizen == null)
                return NotFound(new { success = false, messageAr = "المستخدم غير موجود", message = "User not found" });

            if (citizen.IsPhoneVerified)
                return BadRequest(new { success = false, messageAr = "الهاتف مفعل مسبقاً", message = "Phone already verified" });

            var otp = GenerateOTP();
            citizen.VerificationCode = otp;
            citizen.VerificationCodeExpiresAt = DateTime.UtcNow.AddMinutes(10);
            await _context.SaveChangesAsync();

            _logger.LogInformation("OTP resent to: {Phone}, OTP: {OTP}", citizen.PhoneNumber, otp);

            return Ok(new
            {
                success = true,
                messageAr = "تم إرسال كود جديد",
                message = "New code sent",
                debugOtp = otp // للتطوير فقط
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error resending OTP");
            return StatusCode(500, new { success = false, messageAr = "حدث خطأ", message = "Error occurred" });
        }
    }

    // ==================== تسجيل الدخول ====================

    /// <summary>
    /// تسجيل دخول المواطن
    /// </summary>
    [HttpPost("login")]
    public async Task<IActionResult> Login([FromBody] CitizenLoginRequest request)
    {
        try
        {
            // التحقق من رقم الهاتف وتنظيفه (يدعم السعودي والعراقي)
            var (fullPhone, error, errorAr) = NormalizePhoneNumber(request.PhoneNumber);
            if (fullPhone == null)
                return Unauthorized(new { success = false, messageAr = errorAr, message = error });

            var citizen = await _context.Citizens
                .Include(c => c.Company)
                .FirstOrDefaultAsync(c => c.PhoneNumber == fullPhone);

            if (citizen == null)
                return Unauthorized(new { success = false, messageAr = "رقم الهاتف أو كلمة المرور غير صحيحة", message = "Invalid credentials" });

            if (!citizen.IsActive)
                return Unauthorized(new { success = false, messageAr = "الحساب غير نشط", message = "Account is inactive" });

            if (citizen.IsBanned)
                return Unauthorized(new { success = false, messageAr = "الحساب محظور", message = "Account is banned" });

            if (!VerifyPassword(request.Password, citizen.PasswordHash))
                return Unauthorized(new { success = false, messageAr = "رقم الهاتف أو كلمة المرور غير صحيحة", message = "Invalid credentials" });

            // تحديث آخر تسجيل دخول
            citizen.LastLoginAt = DateTime.UtcNow;
            citizen.UpdatedAt = DateTime.UtcNow;

            // تحديث بيانات الجهاز
            if (!string.IsNullOrEmpty(request.DeviceId))
                citizen.DeviceId = request.DeviceId;
            if (!string.IsNullOrEmpty(request.FcmToken))
                citizen.FirebaseToken = request.FcmToken;
            if (!string.IsNullOrEmpty(request.Platform))
                citizen.DeviceInfo = request.Platform;

            await _context.SaveChangesAsync();

            var token = GenerateJwtToken(citizen);

            return Ok(new
            {
                success = true,
                messageAr = "تم تسجيل الدخول بنجاح",
                message = "Login successful",
                token,
                citizen = new CitizenProfileResponse
                {
                    Id = citizen.Id,
                    FullName = citizen.FullName,
                    PhoneNumber = citizen.PhoneNumber,
                    Email = citizen.Email,
                    City = citizen.City,
                    District = citizen.District,
                    FullAddress = citizen.FullAddress,
                    ProfileImageUrl = citizen.ProfileImageUrl,
                    CompanyId = citizen.CompanyId,
                    CompanyName = citizen.Company?.NameAr,
                    CompanyLogo = citizen.Company?.LogoUrl,
                    HasCompany = true
                }
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error in citizen login");
            return StatusCode(500, new { success = false, messageAr = "حدث خطأ", message = "Login error" });
        }
    }

    // ==================== استعادة كلمة المرور ====================

    /// <summary>
    /// طلب استعادة كلمة المرور
    /// </summary>
    [HttpPost("forgot-password")]
    public async Task<IActionResult> ForgotPassword([FromBody] ForgotPasswordRequest request)
    {
        try
        {
            // التحقق من رقم الهاتف وتنظيفه (يدعم السعودي والعراقي)
            var (fullPhone, error, errorAr) = NormalizePhoneNumber(request.PhoneNumber);
            if (fullPhone == null)
                return BadRequest(new { success = false, messageAr = errorAr, message = error });

            var citizen = await _context.Citizens.FirstOrDefaultAsync(c => c.PhoneNumber == fullPhone);
            if (citizen == null)
            {
                // لا نفصح عن وجود الحساب
                return Ok(new { success = true, messageAr = "إذا كان الرقم مسجلاً، سيتم إرسال كود التفعيل", message = "If registered, OTP will be sent" });
            }

            var otp = GenerateOTP();
            citizen.VerificationCode = otp;
            citizen.VerificationCodeExpiresAt = DateTime.UtcNow.AddMinutes(10);
            await _context.SaveChangesAsync();

            _logger.LogInformation("Password reset OTP for: {Phone}, OTP: {OTP}", fullPhone, otp);

            return Ok(new
            {
                success = true,
                messageAr = "تم إرسال كود التفعيل",
                message = "OTP sent",
                citizenId = citizen.Id,
                debugOtp = otp // للتطوير فقط
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error in forgot password");
            return StatusCode(500, new { success = false, messageAr = "حدث خطأ", message = "Error occurred" });
        }
    }

    /// <summary>
    /// إعادة تعيين كلمة المرور
    /// </summary>
    [HttpPost("reset-password")]
    public async Task<IActionResult> ResetPassword([FromBody] ResetPasswordRequest request)
    {
        try
        {
            var citizen = await _context.Citizens.FirstOrDefaultAsync(c => c.Id == request.CitizenId);
            if (citizen == null)
                return NotFound(new { success = false, messageAr = "المستخدم غير موجود", message = "User not found" });

            if (citizen.VerificationCode != request.Code)
                return BadRequest(new { success = false, messageAr = "الكود غير صحيح", message = "Invalid code" });

            if (citizen.VerificationCodeExpiresAt < DateTime.UtcNow)
                return BadRequest(new { success = false, messageAr = "انتهت صلاحية الكود", message = "Code expired" });

            citizen.PasswordHash = HashPassword(request.NewPassword);
            citizen.VerificationCode = null;
            citizen.VerificationCodeExpiresAt = null;
            citizen.UpdatedAt = DateTime.UtcNow;

            await _context.SaveChangesAsync();

            return Ok(new
            {
                success = true,
                messageAr = "تم تغيير كلمة المرور بنجاح",
                message = "Password changed successfully"
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error resetting password");
            return StatusCode(500, new { success = false, messageAr = "حدث خطأ", message = "Error occurred" });
        }
    }

    // ==================== الملف الشخصي ====================

    /// <summary>
    /// الحصول على الملف الشخصي
    /// </summary>
    [HttpGet("profile")]
    [Authorize(AuthenticationSchemes = "CitizenJwt")]
    public async Task<IActionResult> GetProfile()
    {
        try
        {
            var citizenId = GetCurrentCitizenId();
            if (citizenId == null)
                return Unauthorized();

            var citizen = await _context.Citizens
                .Include(c => c.Company)
                .FirstOrDefaultAsync(c => c.Id == citizenId);

            if (citizen == null)
                return NotFound();

            return Ok(new
            {
                success = true,
                citizen = new CitizenProfileResponse
                {
                    Id = citizen.Id,
                    FullName = citizen.FullName,
                    PhoneNumber = citizen.PhoneNumber,
                    Email = citizen.Email,
                    City = citizen.City,
                    District = citizen.District,
                    FullAddress = citizen.FullAddress,
                    ProfileImageUrl = citizen.ProfileImageUrl,
                    Latitude = citizen.Latitude,
                    Longitude = citizen.Longitude,
                    CompanyId = citizen.CompanyId,
                    CompanyName = citizen.Company?.NameAr,
                    CompanyLogo = citizen.Company?.LogoUrl,
                    HasCompany = true,
                    IsActive = citizen.IsActive,
                    Language = citizen.LanguagePreference
                }
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting profile");
            return StatusCode(500, new { success = false, messageAr = "حدث خطأ", message = "Error occurred" });
        }
    }

    /// <summary>
    /// تحديث الملف الشخصي
    /// </summary>
    [HttpPut("profile")]
    [Authorize(AuthenticationSchemes = "CitizenJwt")]
    public async Task<IActionResult> UpdateProfile([FromBody] UpdateProfileRequest request)
    {
        try
        {
            var citizenId = GetCurrentCitizenId();
            if (citizenId == null)
                return Unauthorized();

            var citizen = await _context.Citizens.FindAsync(citizenId);
            if (citizen == null)
                return NotFound();

            if (!string.IsNullOrEmpty(request.FullName))
                citizen.FullName = request.FullName;
            if (!string.IsNullOrEmpty(request.Email))
                citizen.Email = request.Email;
            if (!string.IsNullOrEmpty(request.City))
                citizen.City = request.City;
            if (!string.IsNullOrEmpty(request.District))
                citizen.District = request.District;
            if (!string.IsNullOrEmpty(request.FullAddress))
                citizen.FullAddress = request.FullAddress;
            if (request.Latitude.HasValue)
                citizen.Latitude = request.Latitude;
            if (request.Longitude.HasValue)
                citizen.Longitude = request.Longitude;
            if (!string.IsNullOrEmpty(request.Language))
                citizen.LanguagePreference = request.Language;

            citizen.UpdatedAt = DateTime.UtcNow;
            await _context.SaveChangesAsync();

            return Ok(new
            {
                success = true,
                messageAr = "تم تحديث الملف الشخصي",
                message = "Profile updated"
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error updating profile");
            return StatusCode(500, new { success = false, messageAr = "حدث خطأ", message = "Error occurred" });
        }
    }

    /// <summary>
    /// تغيير كلمة المرور
    /// </summary>
    [HttpPost("change-password")]
    [Authorize(AuthenticationSchemes = "CitizenJwt")]
    public async Task<IActionResult> ChangePassword([FromBody] CitizenChangePasswordRequest request)
    {
        try
        {
            var citizenId = GetCurrentCitizenId();
            if (citizenId == null)
                return Unauthorized();

            var citizen = await _context.Citizens.FindAsync(citizenId);
            if (citizen == null)
                return NotFound();

            if (!VerifyPassword(request.CurrentPassword, citizen.PasswordHash))
                return BadRequest(new { success = false, messageAr = "كلمة المرور الحالية غير صحيحة", message = "Current password is incorrect" });

            citizen.PasswordHash = HashPassword(request.NewPassword);
            citizen.UpdatedAt = DateTime.UtcNow;
            await _context.SaveChangesAsync();

            return Ok(new
            {
                success = true,
                messageAr = "تم تغيير كلمة المرور",
                message = "Password changed"
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error changing password");
            return StatusCode(500, new { success = false, messageAr = "حدث خطأ", message = "Error occurred" });
        }
    }

    /// <summary>
    /// تحديث FCM Token
    /// </summary>
    [HttpPost("update-fcm-token")]
    [Authorize(AuthenticationSchemes = "CitizenJwt")]
    public async Task<IActionResult> UpdateFcmToken([FromBody] UpdateFcmTokenRequest request)
    {
        try
        {
            var citizenId = GetCurrentCitizenId();
            if (citizenId == null)
                return Unauthorized();

            var citizen = await _context.Citizens.FindAsync(citizenId);
            if (citizen == null)
                return NotFound();

            citizen.FirebaseToken = request.FcmToken;
            citizen.DeviceId = request.DeviceId;
            citizen.DeviceInfo = request.Platform;
            citizen.UpdatedAt = DateTime.UtcNow;

            await _context.SaveChangesAsync();

            return Ok(new { success = true });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error updating FCM token");
            return StatusCode(500, new { success = false });
        }
    }

    // ==================== Helper Methods ====================

    private Guid? GetCurrentCitizenId()
    {
        var claim = User.FindFirst(ClaimTypes.NameIdentifier);
        if (claim == null || !Guid.TryParse(claim.Value, out var id))
            return null;
        return id;
    }

    private string GenerateJwtToken(Citizen citizen)
    {
        var key = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(_configuration["Jwt:Key"] ?? "YourDefaultSecretKey123456789012345678901234"));
        var credentials = new SigningCredentials(key, SecurityAlgorithms.HmacSha256);

        var claims = new List<Claim>
        {
            new Claim(ClaimTypes.NameIdentifier, citizen.Id.ToString()),
            new Claim(ClaimTypes.MobilePhone, citizen.PhoneNumber),
            new Claim(ClaimTypes.Name, citizen.FullName),
            new Claim("type", "citizen")
        };

        // إضافة companyId فقط إذا كان موجوداً
        if (citizen.CompanyId.HasValue)
        {
            claims.Add(new Claim("companyId", citizen.CompanyId.Value.ToString()));
        }

        var token = new JwtSecurityToken(
            issuer: _configuration["Jwt:Issuer"] ?? "SadaraAPI",
            audience: _configuration["Jwt:Audience"] ?? "SadaraCitizen",
            claims: claims,
            expires: DateTime.UtcNow.AddDays(30),
            signingCredentials: credentials
        );

        return new JwtSecurityTokenHandler().WriteToken(token);
    }

    private string GenerateOTP()
    {
        var random = new Random();
        return random.Next(100000, 999999).ToString();
    }

    private string HashPassword(string password)
    {
        using var sha256 = SHA256.Create();
        var bytes = sha256.ComputeHash(Encoding.UTF8.GetBytes(password + "SadaraSalt2024"));
        return Convert.ToBase64String(bytes);
    }

    private bool VerifyPassword(string password, string hash)
    {
        return HashPassword(password) == hash;
    }
}

// ==================== DTOs ====================

public class CitizenRegisterRequest
{
    public string FullName { get; set; } = string.Empty;
    public string PhoneNumber { get; set; } = string.Empty;
    public string Password { get; set; } = string.Empty;
    public string? Email { get; set; }
    public string? City { get; set; }
    public string? District { get; set; }
    public string? Address { get; set; }
    public string? Language { get; set; }
}

public class VerifyPhoneRequest
{
    public Guid CitizenId { get; set; }
    public string Code { get; set; } = string.Empty;
}

public class ResendOTPRequest
{
    public Guid CitizenId { get; set; }
}

public class CitizenLoginRequest
{
    public string PhoneNumber { get; set; } = string.Empty;
    public string Password { get; set; } = string.Empty;
    public string? DeviceId { get; set; }
    public string? FcmToken { get; set; }
    public string? Platform { get; set; }
}

public class ForgotPasswordRequest
{
    public string PhoneNumber { get; set; } = string.Empty;
}

public class ResetPasswordRequest
{
    public Guid CitizenId { get; set; }
    public string Code { get; set; } = string.Empty;
    public string NewPassword { get; set; } = string.Empty;
}

public class UpdateProfileRequest
{
    public string? FullName { get; set; }
    public string? Email { get; set; }
    public string? City { get; set; }
    public string? District { get; set; }
    public string? FullAddress { get; set; }
    public double? Latitude { get; set; }
    public double? Longitude { get; set; }
    public string? Language { get; set; }
}

public class CitizenChangePasswordRequest
{
    public string CurrentPassword { get; set; } = string.Empty;
    public string NewPassword { get; set; } = string.Empty;
}

public class UpdateFcmTokenRequest
{
    public string? FcmToken { get; set; }
    public string? DeviceId { get; set; }
    public string? Platform { get; set; }
}

public class CitizenProfileResponse
{
    public Guid Id { get; set; }
    public string FullName { get; set; } = string.Empty;
    public string PhoneNumber { get; set; } = string.Empty;
    public string? Email { get; set; }
    public string? City { get; set; }
    public string? District { get; set; }
    public string? FullAddress { get; set; }
    public string? ProfileImageUrl { get; set; }
    public double? Latitude { get; set; }
    public double? Longitude { get; set; }
    public Guid? CompanyId { get; set; }
    public string? CompanyName { get; set; }
    public string? CompanyLogo { get; set; }
    public bool HasCompany { get; set; }
    public bool IsActive { get; set; }
    public string Language { get; set; } = "ar";
}
