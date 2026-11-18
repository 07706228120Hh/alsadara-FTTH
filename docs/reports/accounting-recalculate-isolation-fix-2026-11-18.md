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

## مراجعة security-auditor (2026-11-18) — الحكم: الثغرة مغلقة
أكّد المدقّق أن `recalculate-balances` و`integrity-check` تطبّقان فلترة `CompanyId` صريحة تُجبَر على `_tenant.CompanyId` لغير SuperAdmin وتتجاهل `companyId` الممرَّر ⇒ **عزل صامد مستقل عن علَم `EnforceIsolation`** (أقوى من بقية المتحكّم). لا IDOR، لا تصعيد صلاحية، لا كشف متقاطع. السياسة `CompanyAdminOrAbove` = دور قياسي (غير معرّض لعيب fail-open).

### ملاحظات المدقّق المُعالَجة في هذا الفرع
- **P3 (مُصلَح):** `RecalculateAllBalances` كان يُعيد `"خطأ داخلي: " + ex.Message` للعميل ⇒ أصبح رسالة عامة + تسجيل داخلي فقط.
- **P2 كامن (مُصلَح):** `GetTrialBalance` (`AccountingController.cs:4910`) كان يثق بـ`companyId` من العميل (حمايته الوحيدة الفلتر المركزي المرهون بعلَم `EnforceIsolation`؛ يصبح P1 لو أُطفئ). طُبِّق نفس نمط العزل الصريح + 403 بلا شركة. اختبار `TrialBalance_IgnoresClientCompanyId_ForNonSuperAdmin_AndRejectsWhenNoCompany`.

### متبقٍّ (خارج هذا الفرع)
- **P3:** إضافة سجل تدقيق «من شغّل `recalculate`» (العملية idempotent فالخطر منخفض).
- **تنبيه للتسجيل في RISKS:** `[RequirePermission("accounting","view")]` على مستوى الصنف دَين fail-open عام على المنصّة — لا يُضعف الدالتين المحميّتين بسياسة الدور، لكن يستحق تتبّعاً.
- (البند 3) توحيد قفل الصفوف في مسارات العكس/التعديل لإيقاف انزياح `CurrentBalance` مستقبلاً.
