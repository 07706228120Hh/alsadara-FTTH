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
    private readonly bool _failClosed;

    /// <param name="permissionKey">المفتاح (مثل "accounting.journals" أو "hr.salaries")</param>
    /// <param name="action">الإجراء المطلوب (view, add, edit, delete, export, import, print, send)</param>
    /// <param name="system">النظام (First أو Second)</param>
    /// <param name="failClosed">
    /// عند true: إذا كان عمود صلاحيات V2 فارغاً ⇒ يُرفَض الوصول (fail-closed).
    /// عند false (الافتراضي): يُبقى السلوك القديم fail-open (سماح عند فراغ الصلاحيات) لعدم حظر المستخدمين القدامى.
    /// يُستخدم failClosed:true للميزات الحسّاسة فقط (مثل sas_agent) بلا أثر على بقية المنصّة.
    /// </param>
    public RequirePermissionAttribute(
        string permissionKey,
        string action = "view",
        PermissionSystem system = PermissionSystem.First,
        bool failClosed = false)
    {
        _permissionKey = permissionKey;
        _action = action;
        _system = system;
        _failClosed = failClosed;
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

        if (HasPermission(permJson, _permissionKey, _action, _failClosed))
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
    /// <param name="failClosed">
    /// عند true: فراغ صلاحيات V2 ⇒ رفض (false). عند false (الافتراضي): فراغها ⇒ سماح (السلوك القديم fail-open).
    /// المعامل اختياري في النهاية حفاظاً على توافق كل الاستدعاءات القائمة بثلاثة معاملات.
    /// </param>
    public static bool HasPermission(string? jsonPermissions, string key, string action, bool failClosed = false)
    {
        // إذا لم يتم تعيين صلاحيات V2 بعد:
        //  - failClosed=false ⇒ السماح (سلوك قديم لعدم حظر المستخدمين القدامى في بقية الميزات).
        //  - failClosed=true  ⇒ الرفض (بوابة حسّاسة كـ sas_agent يجب ألا تُفتح عند فراغ الصلاحيات).
        if (string.IsNullOrEmpty(jsonPermissions)) return !failClosed;

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

                // الإجراء "manage" (مستخدَم حصراً في بوّابة الساز للكتابة) يُكافئ قدرة
                // الكتابة: يُلبّى بأي من add/edit/delete — لأن نظام الصلاحيات يمنح
                // add/edit/delete ولا يملك مفتاح "manage" (بحسب تصميم السجل والتعليق فيه).
                // محصور بإجراء "manage" فقط ⇒ لا أثر على بقية الميزات (view/add/edit/delete...).
                if (action == "manage")
                {
                    if ((actions.TryGetValue("add", out var addVal) && GetBool(addVal)) ||
                        (actions.TryGetValue("edit", out var editVal) && GetBool(editVal)) ||
                        (actions.TryGetValue("delete", out var delVal) && GetBool(delVal)))
                        return true;
                }
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
