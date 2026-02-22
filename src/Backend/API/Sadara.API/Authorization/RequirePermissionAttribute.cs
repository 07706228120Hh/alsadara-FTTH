using System.Text.Json;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.Filters;
using Sadara.Domain.Interfaces;

namespace Sadara.API.Authorization;

/// <summary>
/// V3: فلتر صلاحيات يتحقق من صلاحيات V2 المخزنة في قاعدة البيانات.
/// يدعم المفاتيح الهرمية (مثال: accounting.journals)
/// القاعدة: إذا الأب مغلق → جميع الأبناء مغلقة
/// </summary>
[AttributeUsage(AttributeTargets.Class | AttributeTargets.Method, AllowMultiple = true)]
public class RequirePermissionAttribute : Attribute, IAsyncAuthorizationFilter
{
    private readonly string _permissionKey;
    private readonly string _action;
    private readonly PermissionSystem _system;

    /// <param name="permissionKey">المفتاح (مثل "accounting.journals" أو "hr.salaries")</param>
    /// <param name="action">الإجراء المطلوب (view, add, edit, delete, export, import, print, send)</param>
    /// <param name="system">النظام (First أو Second)</param>
    public RequirePermissionAttribute(
        string permissionKey,
        string action = "view",
        PermissionSystem system = PermissionSystem.First)
    {
        _permissionKey = permissionKey;
        _action = action;
        _system = system;
    }

    public async Task OnAuthorizationAsync(AuthorizationFilterContext context)
    {
        // السماح للـ AllowAnonymous
        if (context.ActionDescriptor.EndpointMetadata
            .Any(m => m is Microsoft.AspNetCore.Authorization.AllowAnonymousAttribute))
        {
            return;
        }

        var user = context.HttpContext.User;
        if (!user.Identity?.IsAuthenticated ?? true)
        {
            context.Result = new UnauthorizedResult();
            return;
        }

        // SuperAdmin يتجاوز جميع الفحوصات
        var roleClaim = user.FindFirst(System.Security.Claims.ClaimTypes.Role)?.Value 
                     ?? user.FindFirst("role")?.Value;
        if (roleClaim == "SuperAdmin")
        {
            return;
        }

        // جلب userId
        var userIdClaim = user.FindFirst(System.Security.Claims.ClaimTypes.NameIdentifier)?.Value
                       ?? user.FindFirst("sub")?.Value
                       ?? user.FindFirst("nameid")?.Value;

        if (string.IsNullOrEmpty(userIdClaim) || !Guid.TryParse(userIdClaim, out var userId))
        {
            context.Result = new ForbidResult();
            return;
        }

        // جلب UnitOfWork من DI
        var unitOfWork = context.HttpContext.RequestServices.GetService<IUnitOfWork>();
        if (unitOfWork == null)
        {
            context.Result = new StatusCodeResult(500);
            return;
        }

        var dbUser = await unitOfWork.Users.FirstOrDefaultAsync(u => u.Id == userId);
        if (dbUser == null)
        {
            context.Result = new ForbidResult();
            return;
        }

        // اختيار JSON المناسب
        var permJson = _system == PermissionSystem.First
            ? dbUser.FirstSystemPermissionsV2
            : dbUser.SecondSystemPermissionsV2;

        if (HasPermission(permJson, _permissionKey, _action))
        {
            return; // مسموح
        }

        // محظور
        context.Result = new ObjectResult(new
        {
            error = "لا تملك صلاحية كافية",
            permission = _permissionKey,
            action = _action,
        })
        {
            StatusCode = 403
        };
    }

    /// <summary>
    /// فحص هرمي: يدعم parent.child وينظر للأب إذا الابن غير موجود
    /// </summary>
    public static bool HasPermission(string? jsonPermissions, string key, string action)
    {
        if (string.IsNullOrEmpty(jsonPermissions)) return false;

        try
        {
            var perms = JsonSerializer.Deserialize<Dictionary<string, Dictionary<string, JsonElement>>>(
                jsonPermissions, new JsonSerializerOptions { PropertyNameCaseInsensitive = true });

            if (perms == null) return false;

            // 1. فحص المفتاح المباشر
            if (perms.TryGetValue(key, out var actions))
            {
                if (actions.TryGetValue(action, out var val) && GetBool(val))
                    return true;
            }

            // 2. إذا كان مفتاح فرعي (مثل accounting.journals)، فحص الأب
            if (key.Contains('.'))
            {
                var parentKey = key.Substring(0, key.IndexOf('.'));

                // إذا الأب مغلق → الابن مغلق
                if (perms.TryGetValue(parentKey, out var parentActions))
                {
                    if (parentActions.TryGetValue(action, out var parentVal) && !GetBool(parentVal))
                        return false;

                    // الأب مفتوح + الابن غير موجود → يرث
                    if (!perms.ContainsKey(key) && GetBool(parentVal))
                        return true;
                }
            }

            return false;
        }
        catch
        {
            return false;
        }
    }

    private static bool GetBool(JsonElement el)
    {
        return el.ValueKind switch
        {
            JsonValueKind.True => true,
            JsonValueKind.False => false,
            JsonValueKind.String => bool.TryParse(el.GetString(), out var b) && b,
            _ => false
        };
    }
}

public enum PermissionSystem
{
    First,
    Second
}
