# تقرير النظام المحاسبي — منصة الصدارة

- **التاريخ:** 2026-10-22
- **النوع:** استكشاف + تدقيق أمني (قراءة فقط — لم يُعدّل أي ملف تطبيقي)
- **الفرع:** `feature/login-manual-update-button`
- **الطلب:** (1) استكشاف النظام المحاسبي كاملاً + تقرير، (2) الثغرات والمشاكل المتوقعة، (3) خطة التطوير والتحسين، (4) ميزة: إظهار اسم المستخدم/المشترك الذي جُدِّد اشتراكه (أو أي عملية مرتبطة بالقيد).

> ملاحظة منهجية: هذا تقرير تحليلي ثابت (static) من قراءة الكود. قيمة علَم `Tenancy:EnforceIsolation` على الإنتاج تُغيّر تصنيف عدة بنود أمنية ويجب حسمها بشرياً (الذاكرة تقول رُفع `=true` بتاريخ 2026-10-19، بينما موجز أقدم يقول OFF — ملف `appsettings.Production.json` على الـ VPS وخارج الشجرة).

---

## 1. نظرة عامة على البنية

النظام المحاسبي = دفتر أستاذ مزدوج القيد (double-entry) داخل نواة الصدارة .NET 9، معزول بالشركة (`CompanyId`).

### الكيانات (Domain) — `src/Backend/Core/Sadara.Domain/Entities/Accounting.cs`
| الكيان | الدور | حقول مفتاحية |
|--------|------|-------------|
| `Account` | شجرة الحسابات | `Code`, `Name`, `AccountType`, `ParentAccountId`, `CurrentBalance`, `CompanyId`, **`Description` = مفتاح ربط حساب الشخص الفرعي (يُخزَّن فيه `personId`!)** |
| `JournalEntry` | رأس القيد | `EntryNumber` (`JE-2026-xxxxx`), `EntryDate`, **`Description` (البيان الكامل)**, `TotalDebit/Credit`, `ReferenceType`, `ReferenceId`, `Status`, **`CreatedById` (المنفّذ)**, `ApprovedById` |
| `JournalEntryLine` | سطر القيد | `AccountId`, `DebitAmount`, `CreditAmount`, **`Description` (وصف السطر المختصر)**, `CompanyId?`, `EntityType/EntityId` |
| `CashBox`, `CashTransaction`, `EmployeeSalary`, `EmployeeDeductionBonus`, `TechnicianCollection`, `TechnicianTransaction`, `AgentTransaction`, `Expense`, `FixedExpense`, `ClosedPeriod` | كيانات الحركات والرواتب والمصاريف | أغلبها فيه `JournalEntryId` + `CompanyId` + `CreatedById` |

### أكواد الحسابات — `src/Backend/API/Sadara.API/Constants/AccountCodes.cs`
صندوق نقد `1110` · رصيد الصفحة `11102` · ذمم الفنيين `1140` · الوكلاء `1150` · المشغّلون `1160` · الدفع الإلكتروني `1170` · مواطنو SAS `1180` · إيراد صيانة `4110` · إيراد خصم الشركة `4120` · مصاريف عروض `5110`.

### المتحكّمات الرئيسية
| المتحكّم | المسار | الحماية | العزل |
|---------|--------|---------|-------|
| `AccountingController` | `api/accounting` | `[Authorize]` + `[RequirePermission("accounting","view")]` على **مستوى الصنف فقط** | `GuardCompanyAccess`/`ResolveReadScope` موجودان لكن لا يُستدعيان إلا في `salaries/generate` |
| `FtthAccountingController` | `api/ftth-accounting` | `[Authorize]` + صلاحية على بعض النقاط | **يأخذ `CompanyId`/`UserId` من جسم الطلب** |
| `TechnicianTransactionsController` | `api/techniciantransactions` | أدوار + صلاحيات | هوية المنفّذ من **التوكن** (سليم) |
| `SasAgentController` | `api/sas-agent` | صلاحية `sas_agent` + failClosed | **مختوم خادمياً بالكامل** (الأنظف) |
| `InternalDataController` | `api/internal` | `[AllowAnonymous]` + `X-Api-Key` | داخلي |

---

## 2. تدفّق التجديد → القيد → «البيان» (جوهر الميزة المطلوبة)

عند تجديد اشتراك FTTH من تطبيق Flutter:

1. التطبيق ينفّذ التجديد على مزوّد FTTH الخارجي، ثم يرسل `POST /api/ftth-accounting/log-with-accounting`.
2. `FtthAccountingController.CreateAccountingEntry` ([FtthAccountingController.cs:227](../../src/Backend/API/Sadara.API/Controllers/FtthAccountingController.cs#L227)) يبني القيد:
   - **اسم المشغّل المنفّذ:** `operatorName = User.FullName (بـ userId) ?? dto.ActivatedBy ?? "مشغل"`.
   - **اسم المشترك:** `customerName = dto.CustomerName ?? "عميل"`.
   - **نوع العملية:** `opType = (purchase ? "شراء" : "تجديد")`.
3. **البيان الكامل للقيد** (رأس القيد `JournalEntry.Description`) — [السطر 311](../../src/Backend/API/Sadara.API/Controllers/FtthAccountingController.cs#L311):
   ```
   "تجديد BASIC - {اسم المشترك} - نقد عبر {اسم المشغّل}"
   ```
   **يحتوي اسم المشترك + المنفّذ.** ✅
4. **وصف سطر المدين** (`JournalEntryLine.Description`) — [السطر 406](../../src/Backend/API/Sadara.API/Controllers/FtthAccountingController.cs#L406):
   ```
   "صندوق {اسم المشغّل} - تجديد BASIC"   →   مثل «صندوق علي صالح - تجديد BASIC»
   ```
   **بلا اسم المشترك.** ❌ وهذا بالضبط ما يظهر في صورة كشف الحسابات.

### لماذا لا يظهر الاسم في الواجهة؟
- endpoint كشف الحساب ([AccountingController.cs:4642](../../src/Backend/API/Sadara.API/Controllers/AccountingController.cs#L4642) و[person/statement:4736](../../src/Backend/API/Sadara.API/Controllers/AccountingController.cs#L4736)) يُرجع **حقلين لكل سطر**: `EntryDescription` (البيان الكامل) و`Description` (وصف السطر المختصر). **لا يُرجع اسم المنفّذ (`CreatedBy.FullName`) إطلاقاً.**
- واجهة Flutter ([client_accounts_page.dart:2767](../../src/Apps/CompanyDesktop/alsadara-ftth/lib/pages/accounting/client_accounts_page.dart#L2767)) تعرض:
  ```dart
  final desc = (line['Description']?.isNotEmpty == true ? line['Description'] : line['EntryDescription']);
  ```
  أي **تفضّل وصف السطر المختصر** (بلا مشترك) وتتجاهل البيان الكامل الذي يحوي الاسم.

**الخلاصة: المعلومة مخزّنة أصلاً في قاعدة البيانات — المشكلة عرضية فقط.**

---

## 3. الثغرات والمشاكل المتوقعة

### أ. ثغرات أمنية (تدقيق دفاعي، قراءة فقط)

| # | التصنيف | المشكلة | الدليل |
|---|---------|---------|--------|
| 1 | **P0 (إرثي)** | المفتاح الداخلي `Security:InternalApiKey` مسرَّب/غير مُدوَّر ويحرس نقاط محاسبة داخلية (`backfill`, `accountant-post`, قيد الاشتراك) | `InternalDataController.cs` — كل النقاط `[AllowAnonymous]+X-Api-Key` (صار fail-closed، لكن المفتاح نفسه يحتاج تدويراً) |
| 2 | **P1** | صلاحية `view` وحدها تمنح **كل** عمليات الكتابة المالية (إنشاء/ترحيل/تعديل/حذف قيد، دفع رواتب وعمولات) — لا فصل بين قراءة/تعديل/حذف | `AccountingController.cs:19` صلاحية الصنف الوحيدة؛ نقاط `:537/:617/:682/:3306/:3514/...` بلا سمة فعل |
| 3 | **P1** | **منفّذ العملية يؤخذ من جسم الطلب لا من التوكن** ⇒ يمكن نسب عملية مالية لمستخدم آخر (ينكسر عدم الإنكار) | `CreatedById = dto.CreatedById` (`AccountingController.cs:583`)، `userId = dto.UserId` (`FtthAccountingController.cs:230`). المقابل السليم: `VoidJournalEntry` يأخذها من التوكن (`:732`) |
| 4 | **P1** | عزل الكتابة: `CompanyId` من جسم الطلب بلا حارس في معظم النقاط ⇒ حقن قيود في شركة أخرى (إذا العلَم OFF) | `GuardCompanyAccess` لا يُستدعى إلا في `salaries/generate` |
| 5 | **P1** | **غياب idempotency** في تسجيل التجديد/التفعيل ⇒ ضغط مزدوج = سجلّان + قيدان + تحصيل/شحن مضاعف | `LogWithAccounting` ينشئ `log.Id` جديداً كل نداء، بلا فهرس فريد على المرجع |
| 6 | **P2** | القيد يُنشأ بناءً على **بلاغ العميل** بنجاح التجديد الخارجي — بلا تحقّق خادمي من `FtthTransactionId` | `FtthAccountingController.cs:70-171` |
| 7 | **P2** | تعديل/حذف قيود **مُرحّلة (Posted)** ممكن بصلاحية قراءة ودون تسجيل «من حذف» | `UpdateJournalEntry:3306`, `DeleteJournalEntry:3514` |
| 8 | **P2** | IDOR على معاملات الفنيين (اعتماد كلي على الفلتر المركزي بدل فحص شركة صريح) | `TechnicianTransactionsController` — `Update/Delete/RecordPayment` يجلبون بـ `Id` فقط |
| 9 | **P2** | **ازدواج مصدر الحقيقة**: رصيد الفني (`TechTotal*`) يُحدَّث أولاً، ثم القيد داخل `try/catch` لا يُفشل العملية ⇒ رصيد بلا قيد عند الفشل | `RecordPayment:552-621`, `FtthAccountingController.cs:191-194` |
| 10 | **P3** | الدالة المركزية `CreateAndPostJournalEntry` **بلا تأكيد توازن (مدين=دائن)** — الفحص موجود في المسارين اليدوي وFTTH لكن غائب عن المشترك | `ServiceRequestsController.cs:3236-3278` |

> بند إضافي رصدته مباشرة: `GET accounts/{id}/statement` ([:4642](../../src/Backend/API/Sadara.API/Controllers/AccountingController.cs#L4642)) يجلب الحساب بـ `GetByIdAsync(id)` **دون فحص `CompanyId`** ⇒ احتمال IDOR لقراءة كشف حساب شركة أخرى بمعرفته (مخفَّف فقط إذا العلَم ON). يجب استدعاء `GuardCompanyAccess(account.CompanyId)`.

### ب. مشاكل سلامة بيانات (محاسبية) موثّقة سابقاً وتستحق المتابعة
- **تباين أرصدة الفنيين:** دفتر `1140x` = 77.1M مقابل `SUM(TechTotalCharges-TechTotalPayments)` = 39.2M (فرق ~38M) — يحتاج قرار المصدر المرجعي + مراجعة محاسبية.
- **دفتر غير متوازن بـ 2,165,000** من قيود قديمة (ليست من العمل الأخير).
- أخطاء رواتب سابقة: إعادة التوليد تُسقط السلف، الحذف+التوليد يضاعف المتكرّر، تعديل الراتب يعيده للأساس الكامل، السلفة بعد الإغلاق لا تُخصم.
- تقارير مالية مبنية على 20 صفاً (pageSize افتراضي) و`toDate` يستثني آخر يوم.

---

## 4. الميزة المطلوبة: إظهار اسم المشترك/المنفّذ في كشف الحسابات

المعلومة مخزّنة أصلاً، فالتنفيذ سهل وآمن. ثلاثة خيارات:

### الخيار 1 — واجهة فقط (الأسرع، يشمل القيود القديمة) ✅ موصى به كبداية
في [client_accounts_page.dart:2767](../../src/Apps/CompanyDesktop/alsadara-ftth/lib/pages/accounting/client_accounts_page.dart#L2767) اعرض **البيان الكامل** `EntryDescription` بدل وصف السطر المختصر (أو ادمجهما). البيان الكامل يحتوي أصلاً «تجديد BASIC - {المشترك} - نقد عبر {المشغّل}».
- **المزايا:** تغيير سطر واحد تقريباً، يعمل فوراً على **كل القيود القديمة**، لا يحتاج نشر باكند ولا migration.
- **القيد:** المنفّذ المعروض = المشغّل المذكور في النص (على مسار FTTH = المنفّذ غالباً)، وليس بالضرورة `CreatedById` الموثّق.

### الخيار 2 — باكند + واجهة (الأمتن للتدقيق)
أضف `CreatedByName` (join على `CreatedBy.FullName`) في إسقاط endpoint كشف الحساب، واعرض عموداً/سطراً «المنفّذ: X».
- **المزايا:** يُظهر المنفّذ الحقيقي الموثّق بمعزل عن نص البيان.
- **القيد:** على مسار FTTH الـ `CreatedById` يأتي من العميل (ثغرة P1 #3) فقد لا يكون موثوقاً حتى يُختم من التوكن.

### الخيار 3 — إثراء وصف السطر (للجديد فقط)
عدّل [السطر 406](../../src/Backend/API/Sadara.API/Controllers/FtthAccountingController.cs#L406) ليضيف اسم المشترك: `$"{debitAccount.Name} - {opType} {planName} - {customerName}"`.
- يحسّن **القيود الجديدة فقط** (لا يلمس القديمة).

**التوصية:** الخيار 1 الآن (كسب فوري للقديم والجديد ويجيب طلبك حرفياً «اسم المشترك المجدَّد») + لاحقاً الخيار 2 مقترناً بإصلاح P1 #3 (ختم `CreatedById` من التوكن) لإظهار منفّذ موثوق.

---

## 5. خطة التطوير والتحسين (مراحل)

**المرحلة 0 — الميزة المطلوبة (سريعة، منخفضة الخطر):** تنفيذ الخيار 1 على فرع + فحص دخان.

**المرحلة 1 — إغلاق ثغرات الأمان الحرجة (تحتاج موافقة + مراجعة security-auditor + نشر):**
1. ختم `CreatedById`/`ApprovedById`/`CompanyId` من التوكن حصراً (P1 #3،#4).
2. فصل صلاحيات المحاسبة: `edit` للكتابة، `delete` للحذف، ورفع `accounting` إلى fail-closed بعد ختم V2 (P1 #2).
3. idempotency للتجديد: فهرس فريد على مرجع العملية + فحص تكرار قبل الإنشاء (P1 #5).
4. منع تعديل/حذف القيود المُرحّلة؛ التصحيح بقيد عكسي فقط (P2 #7).
5. تدوير `Security:InternalApiKey` (P0 — قرار مالك + devops).

**المرحلة 2 — سلامة محاسبية:**
1. تأكيد توازن مركزي داخل `CreateAndPostJournalEntry` (P3 #10).
2. لفّ تحديث الرصيد + القيد في معاملة ذرّية واحدة (P2 #9).
3. حسم مصدر الحقيقة لأرصدة الفنيين (دفتر vs مخزّن) + تسوية الـ 2.165M غير المتوازن.
4. ربط القيد بـ `FtthTransactionId` مؤكّد من المزوّد قبل الترحيل (P2 #6).

**المرحلة 3 — تطوير وظيفي:**
- عمود/فلتر «المنفّذ» في كشف الحسابات (كما في `account_records_page.dart` لسجلات FTTH).
- تصحيح pagination التقارير المالية و`toDate`.
- سجلّ تدقيق (audit log) غير قابل للتعديل لكل عملية مالية (من/متى/IP/قبل-بعد).

---

## ملاحقّ — مراجع الكود
- باكند المحاسبة: `AccountingController.cs`, `FtthAccountingController.cs`, `TechnicianTransactionsController.cs`, `SasAgentController.cs`, `InternalDataController.cs`.
- الدالة المركزية: `ServiceRequestsController.cs:3236` (`CreateAndPostJournalEntry`).
- الخدمة الموحّدة: `Services/SubscriptionAccountingService.cs`.
- واجهة كشف الحسابات: `lib/pages/accounting/client_accounts_page.dart`.
- نموذج القيد: `lib/models/accounting/journal_entry.dart`.
