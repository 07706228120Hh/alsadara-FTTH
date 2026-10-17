using System.Collections.Concurrent;
using System.Text.Json;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.FileProviders;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using Sadara.API.Controllers;
using Sadara.Domain.Entities;
using Sadara.Integration.Tests.Support;
using Xunit;

namespace Sadara.Integration.Tests;

/// <summary>
/// Phase 0 / Stream E: citizen OTP leak + brute-force hardening of <see cref="CitizenAuthController"/>.
/// Proves that:
///   - the OTP is never returned in register / resend-otp / forgot-password responses outside
///     Development+explicit flag, and is never written to logs;
///   - wrong OTP guesses are capped (lockout), including under parallel requests and across
///     resend / re-register cycles;
///   - a correct code works once (single use).
/// Real Postgres via Testcontainers (skipped clearly when Docker is unavailable).
/// Each test uses its own random phone number, so it can share the "Postgres" collection.
/// </summary>
[Collection("Postgres")]
public sealed class CitizenAuthOtpTests
{
    private readonly PostgresFixture _fx;

    // Random per-run signing key for the test only — never a real secret.
    private static readonly string TestJwtSecret = "test-jwt-" + Guid.NewGuid().ToString("N") + Guid.NewGuid().ToString("N");

    public CitizenAuthOtpTests(PostgresFixture fx) => _fx = fx;

    // ═══════ infrastructure ═══════

    private sealed class TestHostEnvironment : IHostEnvironment
    {
        public TestHostEnvironment(string name) => EnvironmentName = name;
        public string EnvironmentName { get; set; }
        public string ApplicationName { get; set; } = "Sadara.API.Tests";
        public string ContentRootPath { get; set; } = AppContext.BaseDirectory;
        public IFileProvider ContentRootFileProvider { get; set; } = new NullFileProvider();
    }

    /// <summary>Captures every formatted log line so tests can assert the OTP never reaches logs.</summary>
    private sealed class CapturingLogger<T> : ILogger<T>
    {
        public ConcurrentQueue<string> Lines { get; } = new();
        public IDisposable? BeginScope<TState>(TState state) where TState : notnull => null;
        public bool IsEnabled(LogLevel logLevel) => true;
        public void Log<TState>(LogLevel logLevel, EventId eventId, TState state, Exception? exception,
            Func<TState, Exception?, string> formatter)
        {
            Lines.Enqueue(formatter(state, exception));
            if (state is IEnumerable<KeyValuePair<string, object?>> kvs)
                foreach (var kv in kvs)
                    Lines.Enqueue($"{kv.Key}={kv.Value}");
        }
    }

    private sealed record Ctl(CitizenAuthController Controller, CapturingLogger<CitizenAuthController> Logger, IDisposable Db) : IDisposable
    {
        public void Dispose() => Db.Dispose();
    }

    private Ctl Build(string environment = "Production", bool exposeFlag = false)
    {
        var config = new ConfigurationBuilder()
            .AddInMemoryCollection(new Dictionary<string, string?>
            {
                ["Jwt:Secret"] = TestJwtSecret,
                ["Jwt:Issuer"] = "SadaraPlatform",
                ["Jwt:Audience"] = "SadaraClients",
                [CitizenAuthController.ExposeDebugOtpConfigKey] = exposeFlag ? "true" : "false",
            })
            .Build();

        // Anonymous citizen endpoints run without a company in the token (isolation flag OFF).
        var db = _fx.CreateContext(new TestTenant());
        var logger = new CapturingLogger<CitizenAuthController>();
        var controller = new CitizenAuthController(db, config, logger, new TestHostEnvironment(environment))
        {
            ControllerContext = new ControllerContext { HttpContext = new DefaultHttpContext() }
        };
        return new Ctl(controller, logger, db);
    }

    private static string NewIraqiPhone() => "077" + Random.Shared.Next(10000000, 99999999);

    private static string NormalizedPhone(string local) => "+964" + local.Substring(1);

    private static CitizenRegisterRequest RegisterRequest(string phone) => new()
    {
        FullName = "مواطن اختبار",
        PhoneNumber = phone,
        Password = "P@ssw0rd-test",
        City = "بغداد",
    };

    private static (int status, JsonElement body) Unwrap(IActionResult result)
    {
        var obj = result as ObjectResult
                  ?? throw new Xunit.Sdk.XunitException($"Expected ObjectResult, got {result.GetType().Name}");
        var json = JsonSerializer.Serialize(obj.Value);
        return (obj.StatusCode ?? 200, JsonDocument.Parse(json).RootElement.Clone());
    }

    private Citizen LoadCitizen(string normalizedPhone)
    {
        using var ctx = _fx.CreateContext(PostgresFixture.SystemTenant);
        return ctx.Citizens.AsNoTracking().Single(c => c.PhoneNumber == normalizedPhone);
    }

    /// <summary>Moves the issue time of the current code back so the resend cooldown no longer applies.</summary>
    private void SkipResendCooldown(Guid citizenId)
    {
        using var ctx = _fx.CreateContext(PostgresFixture.SystemTenant);
        var expires = DateTime.UtcNow.Add(CitizenAuthController.OtpLifetime) - CitizenAuthController.OtpResendCooldown - TimeSpan.FromSeconds(5);
        ctx.Citizens.Where(c => c.Id == citizenId)
            .ExecuteUpdate(s => s.SetProperty(c => c.VerificationCodeExpiresAt, expires));
    }

    private static string WrongCode(string correct) => correct == "123456" ? "654321" : "123456";

    private async Task<(Guid id, string phone, string otp)> RegisterAsync()
    {
        var phone = NewIraqiPhone();
        using var c = Build();
        var (status, body) = Unwrap(await c.Controller.Register(RegisterRequest(phone)));
        Assert.Equal(200, status);
        var id = body.GetProperty("citizenId").GetGuid();
        var otp = LoadCitizen(NormalizedPhone(phone)).VerificationCode!;
        Assert.Matches("^[0-9]{6}$", otp);
        return (id, phone, otp);
    }

    private static void AssertNoOtpLeak(JsonElement body, string otp)
    {
        Assert.False(body.TryGetProperty("debugOtp", out _), "debugOtp must not be present in the response");
        Assert.DoesNotContain(otp, body.GetRawText());
    }

    private static void AssertOtpNotLogged(CapturingLogger<CitizenAuthController> logger, string otp) =>
        Assert.DoesNotContain(logger.Lines, l => l.Contains(otp, StringComparison.Ordinal));

    // ═══════ leak: responses + logs ═══════

    [SkippableTheory]
    [InlineData("Production", true)]   // flag set but not Development => still hidden
    [InlineData("Production", false)]
    [InlineData("Staging", true)]
    [InlineData("Development", false)] // Development without explicit flag => hidden
    public async Task Register_ResponseAndLogs_NeverContainOtp(string environment, bool flag)
    {
        _fx.SkipIfUnavailable();
        var phone = NewIraqiPhone();
        using var c = Build(environment, flag);

        var (status, body) = Unwrap(await c.Controller.Register(RegisterRequest(phone)));

        Assert.Equal(200, status);
        var otp = LoadCitizen(NormalizedPhone(phone)).VerificationCode!;
        Assert.False(string.IsNullOrEmpty(otp));
        AssertNoOtpLeak(body, otp);
        AssertOtpNotLogged(c.Logger, otp);
    }

    [SkippableFact]
    public async Task Register_DebugOtp_OnlyInDevelopmentWithExplicitFlag()
    {
        _fx.SkipIfUnavailable();
        var phone = NewIraqiPhone();
        using var c = Build("Development", exposeFlag: true);

        var (status, body) = Unwrap(await c.Controller.Register(RegisterRequest(phone)));

        Assert.Equal(200, status);
        var otp = LoadCitizen(NormalizedPhone(phone)).VerificationCode!;
        Assert.Equal(otp, body.GetProperty("debugOtp").GetString());
        AssertOtpNotLogged(c.Logger, otp); // even in dev the OTP is not logged
    }

    [SkippableFact]
    public async Task ResendOtp_And_ForgotPassword_DoNotReturnOrLogOtp()
    {
        _fx.SkipIfUnavailable();
        var (id, phone, _) = await RegisterAsync();

        SkipResendCooldown(id);
        using (var c = Build())
        {
            var (status, body) = Unwrap(await c.Controller.ResendOTP(new ResendOTPRequest { CitizenId = id }));
            Assert.Equal(200, status);
            var otp = LoadCitizen(NormalizedPhone(phone)).VerificationCode!;
            AssertNoOtpLeak(body, otp);
            AssertOtpNotLogged(c.Logger, otp);
        }

        SkipResendCooldown(id);
        using (var c = Build())
        {
            var (status, body) = Unwrap(await c.Controller.ForgotPassword(new ForgotPasswordRequest { PhoneNumber = phone }));
            Assert.Equal(200, status);
            var otp = LoadCitizen(NormalizedPhone(phone)).VerificationCode!;
            AssertNoOtpLeak(body, otp);
            AssertOtpNotLogged(c.Logger, otp);
        }
    }

    // ═══════ brute force ═══════

    [SkippableFact]
    public async Task VerifyPhone_WrongAttempts_AreLimited_ThenCodeIsBurned()
    {
        _fx.SkipIfUnavailable();
        var (id, phone, otp) = await RegisterAsync();
        var wrong = WrongCode(otp);

        for (var i = 1; i < CitizenAuthController.MaxOtpAttempts; i++)
        {
            using var c = Build();
            var (status, _) = Unwrap(await c.Controller.VerifyPhone(new VerifyPhoneRequest { CitizenId = id, Code = wrong }));
            Assert.Equal(400, status);
        }

        using (var c = Build())
        {
            var (status, _) = Unwrap(await c.Controller.VerifyPhone(new VerifyPhoneRequest { CitizenId = id, Code = wrong }));
            Assert.Equal(StatusCodes.Status429TooManyRequests, status);
        }

        // Locked: even the correct code is now refused, and the account stays unverified.
        using (var c = Build())
        {
            var (status, body) = Unwrap(await c.Controller.VerifyPhone(new VerifyPhoneRequest { CitizenId = id, Code = otp }));
            Assert.Equal(StatusCodes.Status429TooManyRequests, status);
            Assert.False(body.TryGetProperty("token", out _));
        }

        var citizen = LoadCitizen(NormalizedPhone(phone));
        Assert.False(citizen.IsPhoneVerified);
        Assert.Null(citizen.VerificationCode);
        Assert.True(citizen.LockoutEnd > DateTime.UtcNow);

        // Resend is refused while locked.
        using (var c = Build())
        {
            var (status, _) = Unwrap(await c.Controller.ResendOTP(new ResendOTPRequest { CitizenId = id }));
            Assert.Equal(StatusCodes.Status429TooManyRequests, status);
        }
    }

    [SkippableFact]
    public async Task VerifyPhone_ParallelWrongGuesses_NeverExceedMaxAttempts()
    {
        _fx.SkipIfUnavailable();
        var (id, phone, otp) = await RegisterAsync();
        var wrong = WrongCode(otp);

        const int parallel = 25;
        var tasks = Enumerable.Range(0, parallel).Select(async _ =>
        {
            using var c = Build();
            var (status, _) = Unwrap(await c.Controller.VerifyPhone(new VerifyPhoneRequest { CitizenId = id, Code = wrong }));
            return status;
        }).ToArray();
        var statuses = await Task.WhenAll(tasks);

        // Only MaxOtpAttempts guesses may ever be compared: at most Max-1 plain "invalid" answers,
        // everything else is rejected as locked / no active code.
        Assert.True(statuses.Count(s => s == 400) <= CitizenAuthController.MaxOtpAttempts - 1,
            $"compared guesses: {statuses.Count(s => s == 400)}");
        Assert.Contains(StatusCodes.Status429TooManyRequests, statuses);

        using var c2 = Build();
        var (finalStatus, _) = Unwrap(await c2.Controller.VerifyPhone(new VerifyPhoneRequest { CitizenId = id, Code = otp }));
        Assert.NotEqual(200, finalStatus);
        Assert.False(LoadCitizen(NormalizedPhone(phone)).IsPhoneVerified);
    }

    [SkippableFact]
    public async Task ResendOtp_DoesNotGrantFreshAttempts()
    {
        _fx.SkipIfUnavailable();
        var (id, phone, otp) = await RegisterAsync();

        for (var i = 1; i < CitizenAuthController.MaxOtpAttempts; i++)
        {
            using var c = Build();
            Unwrap(await c.Controller.VerifyPhone(new VerifyPhoneRequest { CitizenId = id, Code = WrongCode(otp) }));
        }

        SkipResendCooldown(id);
        using (var c = Build())
            Assert.Equal(200, Unwrap(await c.Controller.ResendOTP(new ResendOTPRequest { CitizenId = id })).status);

        var newOtp = LoadCitizen(NormalizedPhone(phone)).VerificationCode!;
        using (var c = Build())
        {
            var (status, _) = Unwrap(await c.Controller.VerifyPhone(new VerifyPhoneRequest { CitizenId = id, Code = WrongCode(newOtp) }));
            Assert.Equal(StatusCodes.Status429TooManyRequests, status);
        }
    }

    [SkippableFact]
    public async Task ResendOtp_WithinCooldown_IsRejected()
    {
        _fx.SkipIfUnavailable();
        var (id, _, _) = await RegisterAsync();

        using var c = Build();
        var (status, _) = Unwrap(await c.Controller.ResendOTP(new ResendOTPRequest { CitizenId = id }));
        Assert.Equal(StatusCodes.Status429TooManyRequests, status);
    }

    [SkippableFact]
    public async Task ReRegister_DoesNotResetLockout()
    {
        _fx.SkipIfUnavailable();
        var (id, phone, otp) = await RegisterAsync();

        for (var i = 0; i < CitizenAuthController.MaxOtpAttempts; i++)
        {
            using var c = Build();
            Unwrap(await c.Controller.VerifyPhone(new VerifyPhoneRequest { CitizenId = id, Code = WrongCode(otp) }));
        }

        using var c2 = Build();
        var (status, _) = Unwrap(await c2.Controller.Register(RegisterRequest(phone)));
        Assert.Equal(StatusCodes.Status429TooManyRequests, status);
    }

    [SkippableFact]
    public async Task ResetPassword_WrongAttempts_AreLimited()
    {
        _fx.SkipIfUnavailable();
        var (id, phone, _) = await RegisterAsync();

        SkipResendCooldown(id);
        using (var c = Build())
            Assert.Equal(200, Unwrap(await c.Controller.ForgotPassword(new ForgotPasswordRequest { PhoneNumber = phone })).status);
        var otp = LoadCitizen(NormalizedPhone(phone)).VerificationCode!;
        var hashBefore = LoadCitizen(NormalizedPhone(phone)).PasswordHash;

        var statuses = new List<int>();
        for (var i = 0; i < CitizenAuthController.MaxOtpAttempts + 2; i++)
        {
            using var c = Build();
            statuses.Add(Unwrap(await c.Controller.ResetPassword(new ResetPasswordRequest
            {
                CitizenId = id, Code = WrongCode(otp), NewPassword = "attacker-pass"
            })).status);
        }

        Assert.Equal(CitizenAuthController.MaxOtpAttempts - 1, statuses.Count(s => s == 400));
        Assert.All(statuses.Skip(CitizenAuthController.MaxOtpAttempts - 1),
            s => Assert.Equal(StatusCodes.Status429TooManyRequests, s));

        using (var c = Build())
        {
            var (status, _) = Unwrap(await c.Controller.ResetPassword(new ResetPasswordRequest
            {
                CitizenId = id, Code = otp, NewPassword = "attacker-pass"
            }));
            Assert.Equal(StatusCodes.Status429TooManyRequests, status);
        }
        Assert.Equal(hashBefore, LoadCitizen(NormalizedPhone(phone)).PasswordHash);
    }

    // ═══════ happy path + single use ═══════

    [SkippableFact]
    public async Task VerifyPhone_CorrectCode_SucceedsOnce()
    {
        _fx.SkipIfUnavailable();
        var (id, phone, otp) = await RegisterAsync();

        // One wrong guess first: success must reset the counter.
        using (var c = Build())
            Assert.Equal(400, Unwrap(await c.Controller.VerifyPhone(new VerifyPhoneRequest { CitizenId = id, Code = WrongCode(otp) })).status);

        using (var c = Build())
        {
            var (status, body) = Unwrap(await c.Controller.VerifyPhone(new VerifyPhoneRequest { CitizenId = id, Code = otp }));
            Assert.Equal(200, status);
            Assert.False(string.IsNullOrEmpty(body.GetProperty("token").GetString()));
        }

        var citizen = LoadCitizen(NormalizedPhone(phone));
        Assert.True(citizen.IsPhoneVerified);
        Assert.True(citizen.IsActive);
        Assert.Null(citizen.VerificationCode);
        Assert.Null(citizen.VerificationCodeExpiresAt);
        Assert.Equal(0, citizen.FailedLoginAttempts);

        // Second use of the same code is refused.
        using (var c = Build())
            Assert.Equal(400, Unwrap(await c.Controller.VerifyPhone(new VerifyPhoneRequest { CitizenId = id, Code = otp })).status);
    }

    [SkippableFact]
    public async Task ResetPassword_CorrectCode_IsSingleUse()
    {
        _fx.SkipIfUnavailable();
        var (id, phone, _) = await RegisterAsync();

        SkipResendCooldown(id);
        using (var c = Build())
            Unwrap(await c.Controller.ForgotPassword(new ForgotPasswordRequest { PhoneNumber = phone }));
        var otp = LoadCitizen(NormalizedPhone(phone)).VerificationCode!;
        var hashBefore = LoadCitizen(NormalizedPhone(phone)).PasswordHash;

        using (var c = Build())
            Assert.Equal(200, Unwrap(await c.Controller.ResetPassword(new ResetPasswordRequest { CitizenId = id, Code = otp, NewPassword = "new-pass-1" })).status);

        var hashAfter = LoadCitizen(NormalizedPhone(phone)).PasswordHash;
        Assert.NotEqual(hashBefore, hashAfter);

        using (var c = Build())
            Assert.Equal(400, Unwrap(await c.Controller.ResetPassword(new ResetPasswordRequest { CitizenId = id, Code = otp, NewPassword = "new-pass-2" })).status);
        Assert.Equal(hashAfter, LoadCitizen(NormalizedPhone(phone)).PasswordHash);
    }
}
