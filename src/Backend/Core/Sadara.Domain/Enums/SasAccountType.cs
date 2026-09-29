namespace Sadara.Domain.Enums;

/// <summary>
/// نوع حساب الساس (SAS) المربوط بالموظف.
/// يحدّد طبيعة الحساب على خادم SAS4 ووجهة التوجيه في واجهة الوكيل.
/// </summary>
public enum SasAccountType
{
    /// <summary>«صفحة وكيل» — حساب مدير (Manager) في نظام الساس؛ يفتح لوحة الوكيل.</summary>
    SasManager = 0,

    /// <summary>«نظام الساس» — حساب مستخدم عادي في نظام الساس؛ يفتح واجهة نظام الساس.</summary>
    SasUser = 1
}
