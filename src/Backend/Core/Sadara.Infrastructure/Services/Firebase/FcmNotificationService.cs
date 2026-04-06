using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using Microsoft.IdentityModel.Tokens;
using Sadara.Application.Interfaces;
using Sadara.Infrastructure.Data;

namespace Sadara.Infrastructure.Services.Firebase;

/// <summary>
/// FCM HTTP v1 API notification service using service account JWT authentication.
/// خدمة إرسال الإشعارات عبر Firebase Cloud Messaging HTTP v1 API
/// </summary>
public class FcmNotificationService : IFcmNotificationService
{
    private readonly IHttpClientFactory _httpClientFactory;
    private readonly ILogger<FcmNotificationService> _logger;
    private readonly IServiceProvider _serviceProvider;
    private readonly string _projectId;
    private readonly string _serviceAccountPath;

    private string? _cachedAccessToken;
    private DateTime _tokenExpiry = DateTime.MinValue;
    private readonly SemaphoreSlim _tokenLock = new(1, 1);

    // Service account fields (loaded once)
    private string? _clientEmail;
    private RSA? _privateKey;
    private bool _serviceAccountLoaded;

    public FcmNotificationService(
        IHttpClientFactory httpClientFactory,
        IConfiguration configuration,
        ILogger<FcmNotificationService> logger,
        IServiceProvider serviceProvider)
    {
        _httpClientFactory = httpClientFactory;
        _logger = logger;
        _serviceProvider = serviceProvider;
        _projectId = configuration["Firebase:ProjectId"] ?? "web-app-sadara";
        _serviceAccountPath = configuration["Firebase:ServiceAccountPath"] ?? "../../../secrets/firebase-service-account.json";
    }

    /// <summary>
    /// Send push notification to a single user (all their registered devices)
    /// </summary>
    public async Task SendToUserAsync(Guid userId, string title, string body, Dictionary<string, string>? data = null)
    {
        await SendToUsersAsync(new[] { userId }, title, body, data);
    }

    /// <summary>
    /// Send push notification to multiple users
    /// </summary>
    public async Task SendToUsersAsync(IEnumerable<Guid> userIds, string title, string body, Dictionary<string, string>? data = null)
    {
        try
        {
            var userIdList = userIds.ToList();
            if (userIdList.Count == 0) return;

            // Get tokens from DB using a scoped context
            using var scope = _serviceProvider.CreateScope();
            var dbContext = scope.ServiceProvider.GetRequiredService<SadaraDbContext>();

            var tokens = await dbContext.UserFcmTokens
                .Where(t => userIdList.Contains(t.UserId) && !t.IsDeleted)
                .Select(t => new { t.Id, t.Token, t.UserId })
                .ToListAsync();

            if (tokens.Count == 0)
            {
                _logger.LogDebug("No FCM tokens found for users {UserIds}", string.Join(",", userIdList));
                return;
            }

            var accessToken = await GetAccessTokenAsync();
            if (string.IsNullOrEmpty(accessToken))
            {
                _logger.LogError("Failed to obtain FCM access token - notifications not sent");
                return;
            }

            var invalidTokenIds = new List<long>();

            foreach (var tokenRecord in tokens)
            {
                var success = await SendToTokenAsync(accessToken, tokenRecord.Token, title, body, data);
                if (!success)
                {
                    invalidTokenIds.Add(tokenRecord.Id);
                }
            }

            // Remove invalid/expired tokens
            if (invalidTokenIds.Count > 0)
            {
                var invalidTokens = await dbContext.UserFcmTokens
                    .Where(t => invalidTokenIds.Contains(t.Id))
                    .ToListAsync();

                foreach (var t in invalidTokens)
                {
                    t.IsDeleted = true;
                    t.DeletedAt = DateTime.UtcNow;
                }

                await dbContext.SaveChangesAsync();
                _logger.LogInformation("Removed {Count} invalid FCM tokens", invalidTokenIds.Count);
            }
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error sending FCM notifications to users");
        }
    }

    /// <summary>
    /// Send a single FCM message to a specific token via FCM HTTP v1 API
    /// </summary>
    private async Task<bool> SendToTokenAsync(string accessToken, string fcmToken, string title, string body, Dictionary<string, string>? data)
    {
        try
        {
            var client = _httpClientFactory.CreateClient();
            client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", accessToken);

            var message = new Dictionary<string, object>
            {
                ["message"] = new Dictionary<string, object>
                {
                    ["token"] = fcmToken,
                    ["notification"] = new Dictionary<string, string>
                    {
                        ["title"] = title,
                        ["body"] = body
                    },
                    ["android"] = new Dictionary<string, object>
                    {
                        ["priority"] = "high",
                        ["notification"] = new Dictionary<string, string>
                        {
                            ["sound"] = "default",
                            ["channel_id"] = "tasks_channel"
                        }
                    }
                }
            };

            // Add data payload if provided
            if (data != null && data.Count > 0)
            {
                var msg = (Dictionary<string, object>)message["message"];
                msg["data"] = data;
            }

            var url = $"https://fcm.googleapis.com/v1/projects/{_projectId}/messages:send";
            var response = await client.PostAsJsonAsync(url, message);

            if (response.IsSuccessStatusCode)
            {
                return true;
            }

            var errorBody = await response.Content.ReadAsStringAsync();

            // Check for invalid/unregistered token errors
            if (response.StatusCode == System.Net.HttpStatusCode.NotFound ||
                errorBody.Contains("UNREGISTERED") ||
                errorBody.Contains("INVALID_ARGUMENT") ||
                errorBody.Contains("NOT_FOUND"))
            {
                _logger.LogWarning("FCM token is invalid/unregistered: {Token}", fcmToken[..Math.Min(20, fcmToken.Length)] + "...");
                return false; // Signal to remove this token
            }

            _logger.LogWarning("FCM send failed with status {StatusCode}: {Error}", response.StatusCode, errorBody);
            return true; // Don't remove token for transient errors
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error sending FCM message to token");
            return true; // Don't remove token on network errors
        }
    }

    /// <summary>
    /// Get OAuth2 access token using service account JWT
    /// Caches the token and refreshes when near expiry
    /// </summary>
    private async Task<string?> GetAccessTokenAsync()
    {
        // Return cached token if still valid (with 5 min buffer)
        if (_cachedAccessToken != null && DateTime.UtcNow < _tokenExpiry.AddMinutes(-5))
        {
            return _cachedAccessToken;
        }

        await _tokenLock.WaitAsync();
        try
        {
            // Double-check after acquiring lock
            if (_cachedAccessToken != null && DateTime.UtcNow < _tokenExpiry.AddMinutes(-5))
            {
                return _cachedAccessToken;
            }

            EnsureServiceAccountLoaded();
            if (_clientEmail == null || _privateKey == null)
            {
                return null;
            }

            var now = DateTimeOffset.UtcNow;
            var expiry = now.AddHours(1);

            // Build JWT header and payload
            var header = Base64UrlEncode(JsonSerializer.SerializeToUtf8Bytes(new
            {
                alg = "RS256",
                typ = "JWT"
            }));

            var payload = Base64UrlEncode(JsonSerializer.SerializeToUtf8Bytes(new
            {
                iss = _clientEmail,
                scope = "https://www.googleapis.com/auth/firebase.messaging",
                aud = "https://oauth2.googleapis.com/token",
                iat = now.ToUnixTimeSeconds(),
                exp = expiry.ToUnixTimeSeconds()
            }));

            var signatureInput = $"{header}.{payload}";
            var signatureBytes = _privateKey.SignData(
                Encoding.ASCII.GetBytes(signatureInput),
                HashAlgorithmName.SHA256,
                RSASignaturePadding.Pkcs1);
            var signature = Base64UrlEncode(signatureBytes);

            var jwt = $"{header}.{payload}.{signature}";

            // Exchange JWT for access token
            var client = _httpClientFactory.CreateClient();
            var tokenRequest = new FormUrlEncodedContent(new Dictionary<string, string>
            {
                ["grant_type"] = "urn:ietf:params:oauth:grant-type:jwt-bearer",
                ["assertion"] = jwt
            });

            var response = await client.PostAsync("https://oauth2.googleapis.com/token", tokenRequest);
            if (!response.IsSuccessStatusCode)
            {
                var error = await response.Content.ReadAsStringAsync();
                _logger.LogError("Failed to get OAuth2 token: {StatusCode} - {Error}", response.StatusCode, error);
                return null;
            }

            var tokenResponse = await response.Content.ReadFromJsonAsync<JsonElement>();
            _cachedAccessToken = tokenResponse.GetProperty("access_token").GetString();
            var expiresIn = tokenResponse.GetProperty("expires_in").GetInt32();
            _tokenExpiry = DateTime.UtcNow.AddSeconds(expiresIn);

            _logger.LogDebug("FCM OAuth2 token obtained, expires in {ExpiresIn}s", expiresIn);
            return _cachedAccessToken;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error obtaining FCM OAuth2 access token");
            return null;
        }
        finally
        {
            _tokenLock.Release();
        }
    }

    /// <summary>
    /// Load service account JSON file (private key + client email)
    /// </summary>
    private void EnsureServiceAccountLoaded()
    {
        if (_serviceAccountLoaded) return;

        try
        {
            var path = Path.IsPathRooted(_serviceAccountPath)
                ? _serviceAccountPath
                : Path.Combine(AppContext.BaseDirectory, _serviceAccountPath);

            if (!File.Exists(path))
            {
                _logger.LogError("Firebase service account file not found at: {Path}", path);
                _serviceAccountLoaded = true;
                return;
            }

            var json = File.ReadAllText(path);
            var doc = JsonDocument.Parse(json);
            var root = doc.RootElement;

            _clientEmail = root.GetProperty("client_email").GetString();
            var privateKeyPem = root.GetProperty("private_key").GetString();

            if (string.IsNullOrEmpty(_clientEmail) || string.IsNullOrEmpty(privateKeyPem))
            {
                _logger.LogError("Service account file missing client_email or private_key");
                _serviceAccountLoaded = true;
                return;
            }

            _privateKey = RSA.Create();
            _privateKey.ImportFromPem(privateKeyPem);

            _serviceAccountLoaded = true;
            _logger.LogInformation("Firebase service account loaded: {Email}", _clientEmail);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error loading Firebase service account");
            _serviceAccountLoaded = true;
        }
    }

    private static string Base64UrlEncode(byte[] data)
    {
        return Convert.ToBase64String(data)
            .TrimEnd('=')
            .Replace('+', '-')
            .Replace('/', '_');
    }
}
