using Microsoft.AspNetCore.Mvc;
using Sadara.Application.DTOs;
using Sadara.Application.Services;

namespace Sadara.API.Controllers;

[ApiController]
[Route("api/[controller]")]
public class AuthController : ControllerBase
{
    private readonly IAuthService _authService;

    public AuthController(IAuthService authService)
    {
        _authService = authService;
    }

    [HttpPost("login")]
    public async Task<IActionResult> Login([FromBody] LoginRequest request)
    {
        var result = await _authService.LoginAsync(request);
        return result.Success ? Ok(result) : BadRequest(result);
    }

    [HttpPost("register")]
    public async Task<IActionResult> Register([FromBody] RegisterRequest request)
    {
        var result = await _authService.RegisterAsync(request);
        return result.Success ? Ok(result) : BadRequest(result);
    }

    [HttpPost("refresh-token")]
    public async Task<IActionResult> RefreshToken([FromBody] RefreshTokenRequest request)
    {
        var result = await _authService.RefreshTokenAsync(request);
        return result.Success ? Ok(result) : BadRequest(result);
    }

    [HttpPost("forgot-password")]
    public async Task<IActionResult> ForgotPassword([FromBody] Sadara.Application.DTOs.ForgotPasswordRequest request)
    {
        var result = await _authService.ForgotPasswordAsync(request);
        return Ok(result);
    }

    [HttpPost("reset-password")]
    public async Task<IActionResult> ResetPassword([FromBody] Sadara.Application.DTOs.ResetPasswordRequest request)
    {
        var result = await _authService.ResetPasswordAsync(request);
        return result.Success ? Ok(result) : BadRequest(result);
    }

    [HttpPost("verify-phone")]
    public async Task<IActionResult> VerifyPhone([FromBody] Sadara.Application.DTOs.VerifyPhoneRequest request)
    {
        var result = await _authService.VerifyPhoneAsync(request);
        return result.Success ? Ok(result) : BadRequest(result);
    }

    /// <summary>
    /// مصادقة عبر Firebase Token
    /// يستخدم للمستخدمين المسجلين عبر Firebase
    /// </summary>
    [HttpPost("firebase")]
    public async Task<IActionResult> FirebaseAuth([FromBody] FirebaseAuthRequest request)
    {
        var result = await _authService.AuthenticateWithFirebaseAsync(request);
        return result.Success ? Ok(result) : BadRequest(result);
    }
}
