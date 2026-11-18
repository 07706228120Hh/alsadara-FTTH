# تقرير الجاهزية — تحصين النظام المحاسبي (الصدارة) — 2026-11-18

> **لا دمج ولا نشر ولا تعديل بيانات إنتاج تلقائياً.** كل ما يلي كود/تحليل على فروع مستقلة، جاهز لمراجعتك وموافقتك الصريحة عند بوّابة الدمج/النشر النهائية.

## 1) جميع التغييرات المنجزة

### منشور فعلاً على الإنتاج (مُوافَق سابقاً)
- **`fix/accounting-balance-guards`** (مدموج main `805e7e2`، deploy `20261118_182736`): حارس توازن مركزي `AssertBalanced` لكل مسارات الترحيل + عزل `recalculate-balances` بشركة التوكن. مُراجَع (APPROVE) + مُختبَر. (انهيار عابر `BadImageFormatException` بعد النشر تعافى ذاتياً عبر systemd.)

### جاهز غير مدموج/غير منشور (فروع مستقلة)
| الفرع | المحتوى | المراجعة | الاختبارات |
|---|---|---|---|
| `feat/accounting-integrity-check` (A1) | `GET /accounting/integrity-check` (قراءة فقط، معزول) + توثيق + إصلاح P3 تسريب خطأ + P2 عزل `GetTrialBalance` | أمن: **الثغرة مغلقة** | 3 ✅ |
| `refactor/accounting-reversal-locking-c1` (C1) | عكس حذف التفعيل (`SubscriptionLogsController.Delete`) بمعاملة ذرّية + قفل صفوف + نقطة تسلسل موحّدة (قفل صف السجل) + `ScopedLogs` | كود + أمن: **آمن للدمج** | 6 ✅ |
| `refactor/accounting-reversal-locking-c2` (مكدّس على C1) | عكس إلغاء طلبات الخدمة (`ServiceRequestsController`) بمعاملة + `VoidJournalEntryAsync` (idempotent + قفل صف القيد) + إعادة بدائية قفل القيد + تحليل مالي + تجهيز CHECK/AccountType + اختبارات أمن الصلاحيات | كود: **Approve w/changes** · أمن: **آمن للدمج** | 3+7 ✅ |

**الدوال المحاسبية المشتركة المستحدثة** (تُعاد لبقية الدفعات): `AssertBalanced` · `PostingDelta` · `ReverseJournalBalancesAsync` (قفل حسابات) · `VoidJournalEntryAsync` (idempotent + قفل قيد) · `LockAndRefreshAccountBalancesAsync` · `LockJournalEntryForUpdateAsync` · `LockSubscriptionLogForUpdateAsync`.

## 2) نتائج اختبارات PostgreSQL والتزامن
- **الحزمة الكاملة: 300 ناجح / 4 فشل قديم معروف** (SasAgentActivateBilled ×2، ServiceRequestsSummary ×2 — سابقة لهذا العمل).
- اختبارات تزامن فعلية على PostgreSQL (Testcontainers، لا InMemory): حذف/إلغاء متزامن ⇒ **عكس مرة واحدة بالضبط**؛ idempotency؛ تراجع؛ `PostingDelta` لكل أنواع الحسابات؛ عزل `recalculate`/`trial-balance`؛ fail-closed للصلاحيات.

## 3) نتائج المراجعة الأمنية
- **A1**: عزل `recalculate-balances` و`integrity-check` صريح ومستقل عن علَم `EnforceIsolation` — لا IDOR ولا تصعيد ولا كشف متقاطع. أُغلقت P3 (تسريب `ex.Message`) وP2 (`GetTrialBalance`).
- **C1**: آمن للدمج — لا TOCTOU (فحص تحت القفل)، ذرّية، لا حقن SQL، أثر تدقيق محفوظ.
- **C2**: آمن للدمج — إبطال idempotent تحت قفل صف القيد، ذرّية، لا حقن SQL (FormattableString مُعامَل).
- **خطر fail-open للصلاحيات (الجزء الرابع)**: موثّق + خطة + اختبارات (أدناه، §5).

## 4) مطابقة الأرصدة والقيود المحاسبية (تحليل — لا تنفيذ)
تفصيل كامل: `docs/reports/accounting-financial-analysis-2026-11-18.md` + `C:\Users\Msi-x88\Desktop\تدقيق_النظام_المحاسبي_2026-11-18.xlsx`.
- **المعروض ≠ الأستاذ بـ+95,405,832** (الإيرادات مُبخَّسة ~94M). أكبرها `4200` (مخزّن −23.8M ‖ أستاذ +67M)؛ **الجذر = قيد يدوي `JE-2026-42896` «ترقيع ميزان» بـ4.6B حُذفت سطوره ناعماً**.
- **الأستاذ غير متوازن بـ−294,000** من **26 قيد تفعيل** (قبل الحارس المركزي؛ صفر بعده).
- التصحيح (recalculate + تسوية الـ26) **معلّق لمحاسب + موافقتك**.

## 5) المخاطر المتبقية (مسجّلة في `.claude/memory/RISKS.md`)
| الخطر | المستوى | الحالة |
|---|---|---|
| أعمدة ذمم الفني/الوكيل المُلخّصة تُحدَّث بلا قفل صف (الأستاذ محميّ؛ القيم مشتقّة) | P2 | مفتوح — دفعة توحيد قفل لاحقة |
| `RequirePermission` fail-open افتراضياً (الإصلاح: backfill V2 + رفع علَم `Authz:FailClosed` بموافقة) | P2 | مفتوح — اختبارات fail-closed مثبّتة |
| best-effort: تغيّر الحالة يُحفظ قبل العكس المالي (قد تُلغى مهمة بفشل استرداد) — سابق، C2 حسّنه بالذرّية | P3 | مفتوح |
| بيانات: قيد `JE-2026-42896` المعطوب (رأس حيّ/سطور محذوفة) + حساب `111013` بـ`AccountType=0` | P2/P3 | يحتاج قرار محاسب |

## 6) المتبقّي من دفعات الكود (C3–C6) — نمط مثبّت، لم يُطبَّق بعد
المواقع محدّدة؛ الحل = تطبيق الدوال المشتركة أعلاه (كل موقع: معاملة + قفل + `VoidJournalEntryAsync`/عكس، باختبار تزامن ومراجعة):
- **C3** `FtthAccountingController`: void نظيف (`VoidAndDeleteJournalEntry` ~3310 → يفوّض لـ`VoidJournalEntryAsync`) + مساري تعديل (reverse-then-reapply ~1718/1813، ~3422) — يحتاج ربط معاملة لكل مُستدعٍ.
- **C4** `AccountingController`: إلغاء/تعديل/حذف قيد (~751، ~3092، ~3164، ~3256، ~3371).
- **C5** `TechnicianTransactionsController` (~920) + `InventoryController` (~4189).
- **C6** `InternalDataController` (تسوية أدمِن ~2372/2555/2774/2879/3787/3933) + `SubscriptionLogsController.RepairAccounting`.
> لم تُنفَّذ لأن مساري التعديل (reverse+reapply) ومعالجات الأدمِن تحتاج فحص معاملة لكل مُستدعٍ؛ أُجّلت لتفادي خطر مرتفع على مسار مالي (حسب بروتوكول «أوقف المسار الخطر ووثّق»).

## 7) خطة الدمج والنشر التدريجي (بموافقتك فقط)
ترتيب الدمج المقترح (فروع مستقلة، تُدمج تِباعاً، كلٌّ بمراجعته):
1. **A1** (`feat/accounting-integrity-check`) → main.
2. **C1** (`refactor/...c1`) → main.
3. **C2** (`refactor/...c2`، مكدّس على C1) → main بعد C1.
4. نشر كود فقط: `bash deploy/deploy-backend.sh` (بلا هجرات؛ A1/C1/C2 كود فقط).
5. لاحقاً: C3–C6 دفعةً دفعة بنفس البوّابة.
6. **منفصل تماماً بموافقة محاسب**: هجرة CHECK (آمنة، 0 مخالفات) + تصحيح `AccountType=0` + `recalculate` + تسوية الـ26 + معالجة `JE-2026-42896`.

## 8) النسخ الاحتياطي والتراجع والتحقّق بعد كل نشر
- **نسخ احتياطي**: `deploy-backend.sh` يأخذ `pg_dump` + كل DLLs تلقائياً قبل أي تغيير (`/root/backups/{dll_<TS>, db_<TS>.sql.gz}`).
- **التراجع**: كود فقط ⇒ `cp /root/backups/dll_<TS>/*.dll /var/www/sadara-api/ && systemctl restart sadara-api`. لا هجرات ⇒ لا تراجع مخطط.
- **التحقّق بعد النشر**: (أ) `systemctl is-active` + `/health=200` + صفر أخطاء في السجل 45ث؛ (ب) **`GET /api/accounting/integrity-check`** (الأداة الجديدة): تأكيد أن توازن الأستاذ والانحراف لم يسوآ؛ (ج) مراقبة `BadImageFormat`/`Unhandled` دقيقتين (درس النشر الأخير)؛ (د) لأي تنفيذ بيانات لاحق: ميزان مراجعة قبل/بعد + قيد عكسي جاهز.

---
### الخلاصة
منجز وآمن ومُراجَع: الحارس المركزي (منشور) + A1 + C1 + C2 (جاهزة للدمج) + التحليل المالي + تجهيز سلامة القاعدة + خطة أمن الصلاحيات. المتبقّي: دفعات C3–C6 (نمط مثبّت) وتنفيذ البيانات (محاسب). **لا شيء يُدمَج أو يُنشَر أو يمسّ بيانات الإنتاج إلا بموافقتك الصريحة عند البوّابة.**
