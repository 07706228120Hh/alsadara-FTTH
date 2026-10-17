using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Microsoft.IdentityModel.Tokens;
using Sadara.Domain.Entities;
using Sadara.Domain.Enums;
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
    // ==================== OTP policy ====================
    // The OTP is a 6-digit secret that proves ownership of the phone number. It must never
    // leave the server except through the (future) SMS channel: not in API responses, not in logs.

    /// <summary>OTP lifetime.</summary>
    public static readonly TimeSpan OtpLifetime = TimeSpan.FromMinutes(10);

    /// <summary>Wrong guesses allowed per issued code before the code is burned and the account is locked.</summary>
    public const int MaxOtpAttempts = 5;

    /// <summary>Lockout applied after <see cref="MaxOtpAttempts"/> wrong guesses (blocks verify/reset/resend).</summary>
    public static readonly TimeSpan OtpLockout = TimeSpan.FromMinutes(15);

    /// <summary>Minimum delay between two issued codes for the same citizen (anti resend-and-guess cycling).</summary>
    public static readonly TimeSpan OtpResendCooldown = TimeSpan.FromSeconds(60);

    /// <summary>
    /// Development-only switch that echoes the OTP back as <c>debugOtp</c>. Honoured ONLY when the host
    /// environment is Development AND this flag is explicitly true. Default false; ignored in production.
    /// </summary>
    public const string ExposeDebugOtpConfigKey = "CitizenAuth:ExposeDebugOtpInDevelopment";

    private readonly SadaraDbContext _context;
    private readonly IConfiguration _configuration;
    private readonly ILogger<CitizenAuthController> _logger;
    private readonly IHostEnvironment _environment;

    public CitizenAuthController(
        SadaraDbContext context,
        IConfiguration configuration,
        ILogger<CitizenAuthController> logger,
        IHostEnvironment environment)
    {
        _context = context;
        _configuration = configuration;
        _logger = logger;
        _environment = environment;
    }

    /// <summary>True only in Development with the explicit opt-in flag; never in production.</summary>
    private bool ExposeDebugOtp =>
        _environment.IsDevelopment() && _configuration.GetValue<bool>(ExposeDebugOtpConfigKey);

    /// <summary>Adds <c>debugOtp</c> to a response body only under <see cref="ExposeDebugOtp"/>.</summary>
    private Dictionary<string, object?> WithDebugOtp(Dictionary<string, object?> body, string otp)
    {
        if (ExposeDebugOtp)
            body["debugOtp"] = otp;
        return body;
    }

    private static bool IsLockedOut(Citizen citizen) =>
        citizen.LockoutEnd.HasValue && citizen.LockoutEnd.Value > DateTime.UtcNow;

    private static bool IsInResendCooldown(Citizen citizen) =>
        citizen.VerificationCodeExpiresAt.HasValue &&
        citizen.VerificationCodeExpiresAt.Value - OtpLifetime + OtpResendCooldown > DateTime.UtcNow;

    private ObjectResult LockedOutResult() => StatusCode(StatusCodes.Status429TooManyRequests, new
    {
        success = false,
        messageAr = "تم تجاوز عدد المحاولات المسموح. حاول لاحقاً",
        message = "Too many attempts. Try again later"
    });

    private ObjectResult CooldownResult() => StatusCode(StatusCodes.Status429TooManyRequests, new
    {
        success = false,
        messageAr = "يرجى الانتظار قليلاً قبل طلب كود جديد",
        message = "Please wait before requesting a new code"
    });

    private enum OtpCheckResult { Ok, LockedOut, NoActiveCode, Expired, Invalid, InvalidAndLocked }

    /// <summary>
    /// Verifies and consumes the citizen's OTP with brute-force protection:
    ///   - lockout check, expiry check;
    ///   - an attempt is reserved atomically in SQL BEFORE comparing, so parallel guesses cannot
    ///     exceed <see cref="MaxOtpAttempts"/> per code (no read-modify-write race);
    ///   - constant-time comparison;
    ///   - on success the code is consumed atomically (single use) and counters are reset.
    /// Uses the existing Citizen.FailedLoginAttempts/LockoutEnd columns (no schema change).
    /// On <see cref="OtpCheckResult.Ok"/> the tracked entity is refreshed and the caller must SaveChanges.
    /// </summary>
    private async Task<OtpCheckResult> CheckAndConsumeOtpAsync(Citizen citizen, string? code)
    {
        var now = DateTime.UtcNow;

        if (IsLockedOut(citizen))
            return OtpCheckResult.LockedOut;

        if (string.IsNullOrEmpty(citizen.VerificationCode) || !citizen.VerificationCodeExpiresAt.HasValue)
            return OtpCheckResult.NoActiveCode;

        if (citizen.VerificationCodeExpiresAt.Value <= now)
            return OtpCheckResult.Expired;

        // Reserve one attempt atomically; 0 rows => attempts exhausted / locked / code gone.
        var reserved = await _context.Citizens
            .Where(c => c.Id == citizen.Id
                        && c.VerificationCode != null
                        && c.FailedLoginAttempts < MaxOtpAttempts
                        && (c.LockoutEnd == null || c.LockoutEnd <= now))
            .ExecuteUpdateAsync(s => s.SetProperty(c => c.FailedLoginAttempts, c => c.FailedLoginAttempts + 1));

        // Refresh tracked state so later SaveChanges diffs against the real row.
        await _context.Entry(citizen).ReloadAsync();

        if (reserved == 0)
            return IsLockedOut(citizen) || citizen.FailedLoginAttempts >= MaxOtpAttempts
                ? OtpCheckResult.LockedOut
                : OtpCheckResult.NoActiveCode;

        var storedCode = citizen.VerificationCode;
        if (string.IsNullOrEmpty(storedCode))
            return OtpCheckResult.NoActiveCode;

        if (!OtpEquals(storedCode, code))
        {
            if (citizen.FailedLoginAttempts >= MaxOtpAttempts)
            {
                // Burn the code and lock; counter restarts after the lockout.
                var lockUntil = now.Add(OtpLockout);
                await _context.Citizens
                    .Where(c => c.Id == citizen.Id)
                    .ExecuteUpdateAsync(s => s
                        .SetProperty(c => c.VerificationCode, (string?)null)
                        .SetProperty(c => c.VerificationCodeExpiresAt, (DateTime?)null)
                        .SetProperty(c => c.FailedLoginAttempts, 0)
                        .SetProperty(c => c.LockoutEnd, lockUntil));
                await _context.Entry(citizen).ReloadAsync();

                _logger.LogWarning("Citizen {CitizenId} locked after {Max} wrong OTP attempts", citizen.Id, MaxOtpAttempts);
                return OtpCheckResult.InvalidAndLocked;
            }

            return OtpCheckResult.Invalid;
        }

        // Consume atomically: only one concurrent request can win the code.
        var consumed = await _context.Citizens
            .Where(c => c.Id == citizen.Id && c.VerificationCode == storedCode)
            .ExecuteUpdateAsync(s => s
                .SetProperty(c => c.VerificationCode, (string?)null)
                .SetProperty(c => c.VerificationCodeExpiresAt, (DateTime?)null)
                .SetProperty(c => c.FailedLoginAttempts, 0)
                .SetProperty(c => c.LockoutEnd, (DateTime?)null));
        await _context.Entry(citizen).ReloadAsync();

        return consumed == 1 ? OtpCheckResult.Ok : OtpCheckResult.NoActiveCode;
    }

    /// <summary>Maps a failed OTP check to the HTTP response (same messages as before for invalid/expired).</summary>
    private IActionResult OtpFailureResult(OtpCheckResult result) => result switch
    {
        OtpCheckResult.LockedOut or OtpCheckResult.InvalidAndLocked => LockedOutResult(),
        OtpCheckResult.Expired => BadRequest(new { success = false, messageAr = "انتهت صلاحية الكود", message = "Code expired" }),
        _ => BadRequest(new { success = false, messageAr = "الكود غير صحيح", message = "Invalid code" }),
    };

    private static bool OtpEquals(string expected, string? provided)
    {
        if (provided is null)
            return false;
        return CryptographicOperations.FixedTimeEquals(
            Encoding.UTF8.GetBytes(expected),
            Encoding.UTF8.GetBytes(provided.Trim()));
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
            var carriedFailedAttempts = 0;
            DateTime? carriedLockoutEnd = null;
            if (existingCitizen != null)
            {
                if (existingCitizen.IsBanned)
                    return BadRequest(new { success = false, messageAr = "هذا الحساب محظور", message = "This account is banned" });

                if (existingCitizen.IsPhoneVerified)
                    return BadRequest(new { success = false, messageAr = "رقم الهاتف مسجل مسبقاً", message = "Phone number already registered" });

                // Re-registering must not reset the OTP brute-force counters (otherwise register→guess×5→register
                // would give unlimited guesses for someone else's phone).
                if (IsLockedOut(existingCitizen))
                    return LockedOutResult();
                if (IsInResendCooldown(existingCitizen))
                    return CooldownResult();

                carriedFailedAttempts = existingCitizen.FailedLoginAttempts;
                carriedLockoutEnd = existingCitizen.LockoutEnd;

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
                LanguagePreference = request.Language ?? "ar",
                FailedLoginAttempts = carriedFailedAttempts,
                LockoutEnd = carriedLockoutEnd
            };

            // TODO: إرسال كود OTP للهاتف عبر مزوّد SMS حقيقي (غير متوفّر حالياً).
            // OTP must never be returned in the response nor written to logs.
            var otp = GenerateOTP();
            citizen.VerificationCode = otp;
            citizen.VerificationCodeExpiresAt = DateTime.UtcNow.Add(OtpLifetime);

            _context.Citizens.Add(citizen);
            await _context.SaveChangesAsync();

            _logger.LogInformation("New citizen registered: {CitizenId}", citizen.Id);

            return Ok(WithDebugOtp(new Dictionary<string, object?>
            {
                ["success"] = true,
                ["messageAr"] = "تم التسجيل بنجاح. تم إرسال كود التفعيل",
                ["message"] = "Registration successful. Verification code sent",
                ["citizenId"] = citizen.Id,
            }, otp));
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

            var otpResult = await CheckAndConsumeOtpAsync(citizen, request.Code);
            if (otpResult != OtpCheckResult.Ok)
                return OtpFailureResult(otpResult);

            citizen.IsPhoneVerified = true;
            citizen.IsActive = true;
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

            if (IsLockedOut(citizen))
                return LockedOutResult();
            if (IsInResendCooldown(citizen))
                return CooldownResult();

            // New code; the attempt counter is intentionally NOT reset (resend must not grant fresh guesses).
            var otp = GenerateOTP();
            citizen.VerificationCode = otp;
            citizen.VerificationCodeExpiresAt = DateTime.UtcNow.Add(OtpLifetime);
            await _context.SaveChangesAsync();

            _logger.LogInformation("OTP resent for citizen {CitizenId}", citizen.Id);

            return Ok(WithDebugOtp(new Dictionary<string, object?>
            {
                ["success"] = true,
                ["messageAr"] = "تم إرسال كود جديد",
                ["message"] = "New code sent",
            }, otp));
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

            if (IsLockedOut(citizen))
                return LockedOutResult();
            if (IsInResendCooldown(citizen))
                return CooldownResult();

            var otp = GenerateOTP();
            citizen.VerificationCode = otp;
            citizen.VerificationCodeExpiresAt = DateTime.UtcNow.Add(OtpLifetime);
            await _context.SaveChangesAsync();

            _logger.LogInformation("Password reset OTP issued for citizen {CitizenId}", citizen.Id);

            return Ok(WithDebugOtp(new Dictionary<string, object?>
            {
                ["success"] = true,
                ["messageAr"] = "تم إرسال كود التفعيل",
                ["message"] = "OTP sent",
                ["citizenId"] = citizen.Id,
            }, otp));
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

            var otpResult = await CheckAndConsumeOtpAsync(citizen, request.Code);
            if (otpResult != OtpCheckResult.Ok)
                return OtpFailureResult(otpResult);

            citizen.PasswordHash = HashPassword(request.NewPassword);
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
    [Authorize]
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
    [Authorize]
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
    [Authorize]
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
    [Authorize]
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

    // ==================== طلب سحب ديلفري ====================

    /// <summary>
    /// إنشاء طلب سحب ديلفري
    /// </summary>
    [HttpPost("delivery-withdrawal")]
    [Authorize]
    public async Task<IActionResult> CreateDeliveryWithdrawal([FromBody] DeliveryWithdrawalRequest dto)
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
                return NotFound(new { success = false, messageAr = "المواطن غير موجود" });

            // إنشاء رقم طلب فريد
            var count = await _context.ServiceRequests.CountAsync() + 1;
            var requestNumber = $"DW-{DateTime.UtcNow:yyyy}-{count:D5}";

            var serviceRequest = new ServiceRequest
            {
                Id = Guid.NewGuid(),
                RequestNumber = requestNumber,
                ServiceId = 11, // بوابة المواطن
                OperationTypeId = 12, // سحب ديلفري
                CitizenId = null, // ServiceRequest.CitizenId points to User, not Citizen
                CompanyId = citizen.CompanyId,
                Status = ServiceRequestStatus.Pending,
                Priority = 2,
                Address = dto.Address,
                ContactPhone = dto.ContactPhone,
                EstimatedCost = dto.Amount,
                Details = System.Text.Json.JsonSerializer.Serialize(new
                {
                    type = "delivery_withdrawal",
                    customerName = citizen.FullName,
                    customerPhone = citizen.PhoneNumber,
                    amount = dto.Amount,
                    latitude = dto.Latitude,
                    longitude = dto.Longitude,
                    locationUrl = $"https://www.google.com/maps?q={dto.Latitude},{dto.Longitude}",
                    citizenId = citizenId,
                    citizenCity = citizen.City,
                    citizenAddress = citizen.FullAddress,
                    notes = dto.Notes,
                    source = "بوابة المواطن",
                    requestedAt = DateTime.UtcNow
                }, new System.Text.Json.JsonSerializerOptions { Encoder = System.Text.Encodings.Web.JavaScriptEncoder.UnsafeRelaxedJsonEscaping }),
                RequestedAt = DateTime.UtcNow,
                CreatedAt = DateTime.UtcNow
            };

            _context.ServiceRequests.Add(serviceRequest);
            await _context.SaveChangesAsync();

            _logger.LogInformation("طلب سحب ديلفري جديد: {RequestNumber} من المواطن {CitizenName}",
                requestNumber, citizen.FullName);

            return Ok(new
            {
                success = true,
                messageAr = "تم إرسال طلب السحب بنجاح",
                message = "Delivery withdrawal request created",
                requestNumber,
                requestId = serviceRequest.Id
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error creating delivery withdrawal");
            return StatusCode(500, new { success = false, messageAr = "حدث خطأ أثناء إرسال الطلب" });
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
        var key = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(_configuration["Jwt:Secret"] ?? _configuration["Jwt:Key"] ?? throw new InvalidOperationException("Jwt:Secret غير مضبوط — fail-closed.")));
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
            issuer: _configuration["Jwt:Issuer"] ?? "SadaraPlatform",
            audience: _configuration["Jwt:Audience"] ?? "SadaraClients",
            claims: claims,
            expires: DateTime.UtcNow.AddDays(30),
            signingCredentials: credentials
        );

        return new JwtSecurityTokenHandler().WriteToken(token);
    }

    /// <summary>Cryptographically secure 6-digit OTP (was System.Random, predictable and excluding 999999).</summary>
    private static string GenerateOTP() =>
        RandomNumberGenerator.GetInt32(100000, 1000000).ToString(System.Globalization.CultureInfo.InvariantCulture);

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

public class DeliveryWithdrawalRequest
{
    public decimal Amount { get; set; }
    public string ContactPhone { get; set; } = string.Empty;
    public string Address { get; set; } = string.Empty;
    public double Latitude { get; set; }
    public double Longitude { get; set; }
    public string? Notes { get; set; }
}
