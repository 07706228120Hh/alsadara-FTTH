# إغلاق ثغرة عزل `recalculate-balances` + فحص السلامة المحاسبية — 2026-11-18

## الثغرة (قبل الإصلاح)
النقطة `POST /api/accounting/recalculate-balances` كانت:
- تُعيد حساب `CurrentBalance` لكل الحسابات النهائية **بلا فلتر `CompanyId`** ⇒ أي استدعاء يمسّ أرصدة **جميع الشركات**.
- محميّة بصلاحية **قراءة** فقط على مستوى الصنف (`[RequirePermission("accounting","view")]`)، بينما هي عملية **كتابة** على `CurrentBalance`.

الأثر: أي مستخدم يملك `accounting.view` في أي شركة كان بإمكانه إطلاق إعادة حساب عابرة للمستأجرين (كتابة على أرصدة شركات أخرى) — خرق عزل + تصعيد صلاحية ضمني.

السياق البنيوي: كيانات المحاسبة (`Account`/`JournalEntry`/`JournalEntryLine`) لا تحمل فلتر مستأجر عالمياً في `SadaraDbContext` (فقط `!IsDeleted`)؛ العزل يعتمد على فلترة كل Controller بـ`CompanyId` من التوكن. هذه النقطة كانت تُغفل ذلك.

## الإصلاح (منشور: deploy `20261118_182736`، main `805e7e2`)
في `AccountingController.RecalculateAllBalances`:
- `[Authorize(Policy = "CompanyAdminOrAbove")]` (رفع إلى صلاحية كتابة).
- معامل `[FromQuery] Guid? companyId` + تقييد النطاق بشركة التوكن:
  - غير SuperAdmin ⇒ `scopeCompanyId = _tenant.CompanyId` حصراً؛ `CompanyId == null` ⇒ **403**.
  - SuperAdmin ⇒ `companyId` الممرَّر صراحةً، أو الكل (صيانة مقصودة).
- الاستعلام يُقيَّد `.Where(a => a.CompanyId == scopeCompanyId.Value)`.

## التحقّق
- مراجعة الكود: APPROVE (بلا P1)؛ أكّدت أن الفلتر الصريح هو الحماية الفعلية وأن استعلام الأسطر الداخلي مقيّد بـ`AccountId` المُنطّق بالشركة ⇒ لا تسريب.
- اختبارات تكامل (`RecalculateBalancesScopeTests`):
  - `Recalc_AsCompanyAdmin_FixesOwnCompanyOnly_LeavesOtherTenantUntouched` — شركة أخرى تبقى دون مساس.
  - `Recalc_IsRejected_WhenNonSuperAdminHasNoCompany` — 403.

## نقطة فحص السلامة (جديدة، قراءة فقط)
`GET /api/accounting/integrity-check` (`CompanyAdminOrAbove`، مقيّدة بشركة التوكن، لا تعدّل بياناً):
- توازن الأستاذ (Σمدين=Σدائن على القيود المرحّلة).
- انزياح الأرصدة المعروضة عن المحسوب من السطور (عدد + إجمالي مطلق + صافي + أعلى 25).
- القيود المرحّلة غير المتوازنة بذاتها (عدد + صافي الفجوة + حتى 100).
اختبارات: `IntegrityCheckTests` (الأرقام المتوقّعة + عدم تغيّر الأرصدة + 403 بلا شركة).

## المتبقّي للمتابعة
- تمرير التغيير على `security-auditor-agent` (تأكيد إغلاق الثغرة — تحسين موثّق).
- (خارج النطاق) توحيد قفل الصفوف في مسارات العكس/التعديل (البند 3) لإيقاف انزياح `CurrentBalance` مستقبلاً.
