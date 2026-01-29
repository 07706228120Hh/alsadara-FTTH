using Sadara.Application.DTOs.Firebase;

namespace Sadara.Application.Interfaces;

/// <summary>
/// Interface for Firebase Admin operations
/// واجهة عمليات Firebase Admin للسوبر أدمن
/// </summary>
public interface IFirebaseAdminService
{
    /// <summary>
    /// Get user by phone number from Firebase
    /// </summary>
    Task<FirebaseUserInfo?> GetUserByPhoneAsync(string phoneNumber);

    /// <summary>
    /// Disable a Firebase user account
    /// </summary>
    Task<bool> DisableUserAsync(string uid);

    /// <summary>
    /// Enable a Firebase user account
    /// </summary>
    Task<bool> EnableUserAsync(string uid);

    /// <summary>
    /// Delete a Firebase user account
    /// </summary>
    Task<bool> DeleteUserAsync(string uid);

    /// <summary>
    /// List Firebase users
    /// </summary>
    Task<List<FirebaseUserInfo>> ListUsersAsync(int maxResults = 100);

    /// <summary>
    /// Send verification code to phone
    /// </summary>
    Task<bool> SendVerificationCodeAsync(string phoneNumber);

    /// <summary>
    /// Get Firebase Auth statistics
    /// </summary>
    Task<FirebaseAuthStats> GetAuthStatsAsync();
}
