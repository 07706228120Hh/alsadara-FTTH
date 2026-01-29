using System.Net.Http.Json;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;
using Sadara.Application.DTOs.Firebase;
using Sadara.Application.Interfaces;

namespace Sadara.Infrastructure.Services.Firebase;

/// <summary>
/// Firebase Admin Service for managing users via Firebase REST API
/// خدمة إدارة Firebase للسوبر أدمن
/// </summary>
public class FirebaseAdminService : IFirebaseAdminService
{
    private readonly HttpClient _httpClient;
    private readonly ILogger<FirebaseAdminService> _logger;
    private readonly string _apiKey;
    private readonly string _projectId;

    public FirebaseAdminService(
        HttpClient httpClient,
        IConfiguration configuration,
        ILogger<FirebaseAdminService> logger)
    {
        _httpClient = httpClient;
        _logger = logger;
        _apiKey = configuration["Firebase:ApiKey"] ?? "";
        _projectId = configuration["Firebase:ProjectId"] ?? "";
    }

    public async Task<FirebaseUserInfo?> GetUserByPhoneAsync(string phoneNumber)
    {
        try
        {
            if (string.IsNullOrEmpty(_apiKey))
            {
                _logger.LogWarning("Firebase API key not configured");
                return null;
            }

            var url = $"https://identitytoolkit.googleapis.com/v1/accounts:lookup?key={_apiKey}";

            var request = new { phoneNumber = phoneNumber };
            var response = await _httpClient.PostAsJsonAsync(url, request);

            if (!response.IsSuccessStatusCode)
            {
                _logger.LogWarning("Failed to get Firebase user by phone: {Phone}", phoneNumber);
                return null;
            }

            var result = await response.Content.ReadFromJsonAsync<FirebaseLookupResponse>();
            var user = result?.Users?.FirstOrDefault();

            if (user == null) return null;

            return new FirebaseUserInfo
            {
                Uid = user.LocalId ?? string.Empty,
                PhoneNumber = user.PhoneNumber,
                Email = user.Email,
                DisplayName = user.DisplayName,
                Disabled = user.Disabled,
                CreatedAt = DateTimeOffset.FromUnixTimeMilliseconds(long.Parse(user.CreatedAt ?? "0")).DateTime,
                LastSignInAt = string.IsNullOrEmpty(user.LastLoginAt) 
                    ? null 
                    : DateTimeOffset.FromUnixTimeMilliseconds(long.Parse(user.LastLoginAt)).DateTime
            };
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting Firebase user by phone: {Phone}", phoneNumber);
            return null;
        }
    }

    public async Task<bool> DisableUserAsync(string uid)
    {
        try
        {
            if (string.IsNullOrEmpty(_apiKey)) return false;

            var url = $"https://identitytoolkit.googleapis.com/v1/accounts:update?key={_apiKey}";
            var request = new { localId = uid, disableUser = true };
            var response = await _httpClient.PostAsJsonAsync(url, request);

            if (response.IsSuccessStatusCode)
            {
                _logger.LogInformation("Firebase user disabled: {Uid}", uid);
                return true;
            }

            _logger.LogWarning("Failed to disable Firebase user: {Uid}", uid);
            return false;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error disabling Firebase user: {Uid}", uid);
            return false;
        }
    }

    public async Task<bool> EnableUserAsync(string uid)
    {
        try
        {
            if (string.IsNullOrEmpty(_apiKey)) return false;

            var url = $"https://identitytoolkit.googleapis.com/v1/accounts:update?key={_apiKey}";
            var request = new { localId = uid, disableUser = false };
            var response = await _httpClient.PostAsJsonAsync(url, request);

            if (response.IsSuccessStatusCode)
            {
                _logger.LogInformation("Firebase user enabled: {Uid}", uid);
                return true;
            }

            _logger.LogWarning("Failed to enable Firebase user: {Uid}", uid);
            return false;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error enabling Firebase user: {Uid}", uid);
            return false;
        }
    }

    public async Task<bool> DeleteUserAsync(string uid)
    {
        try
        {
            if (string.IsNullOrEmpty(_apiKey)) return false;

            var url = $"https://identitytoolkit.googleapis.com/v1/accounts:delete?key={_apiKey}";
            var request = new { localId = uid };
            var response = await _httpClient.PostAsJsonAsync(url, request);

            if (response.IsSuccessStatusCode)
            {
                _logger.LogInformation("Firebase user deleted: {Uid}", uid);
                return true;
            }

            _logger.LogWarning("Failed to delete Firebase user: {Uid}", uid);
            return false;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error deleting Firebase user: {Uid}", uid);
            return false;
        }
    }

    public async Task<List<FirebaseUserInfo>> ListUsersAsync(int maxResults = 100)
    {
        _logger.LogWarning("ListUsers requires Firebase Admin SDK with service account credentials");
        return new List<FirebaseUserInfo>();
    }

    public async Task<bool> SendVerificationCodeAsync(string phoneNumber)
    {
        try
        {
            if (string.IsNullOrEmpty(_apiKey)) return false;

            var url = $"https://identitytoolkit.googleapis.com/v1/accounts:sendVerificationCode?key={_apiKey}";
            var request = new { phoneNumber = phoneNumber };
            var response = await _httpClient.PostAsJsonAsync(url, request);

            if (response.IsSuccessStatusCode)
            {
                _logger.LogInformation("Verification code sent to: {Phone}", phoneNumber);
                return true;
            }

            _logger.LogWarning("Failed to send verification code to: {Phone}", phoneNumber);
            return false;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error sending verification code to: {Phone}", phoneNumber);
            return false;
        }
    }

    public async Task<FirebaseAuthStats> GetAuthStatsAsync()
    {
        return await Task.FromResult(new FirebaseAuthStats
        {
            TotalUsers = 0,
            ActiveUsers = 0,
            DisabledUsers = 0,
            VerifiedUsers = 0,
            LastUpdated = DateTime.UtcNow
        });
    }
}

// Internal response models
internal class FirebaseLookupResponse
{
    public List<FirebaseUserRecord>? Users { get; set; }
}

internal class FirebaseUserRecord
{
    public string? LocalId { get; set; }
    public string? Email { get; set; }
    public string? PhoneNumber { get; set; }
    public string? DisplayName { get; set; }
    public bool Disabled { get; set; }
    public string? CreatedAt { get; set; }
    public string? LastLoginAt { get; set; }
}
