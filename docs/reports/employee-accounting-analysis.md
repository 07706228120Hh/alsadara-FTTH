# تقرير تفصيلي: النظام المحاسبي للموظفين (الفنيين) — الوضع الحالي وفرص التحسين

> تحقيق قراءة‑فقط في backend (.NET 9) + تطبيق Flutter. لا تعديل. التاريخ 2026-08-27.

## 0. الصورة الكبرى — نموذج بطبقتين
النظام يتتبّع أموال الموظف بطبقتين متوازيتين ضعيفتَي الترابط:
1. **ذاكرة مخبّأة على `User`** (`User.cs:79-85`): `TechTotalCharges` (إجمالي الأجور/الدين عليه)، `TechTotalPayments` (إجمالي ما سدّده)، `TechNetBalance = Payments − Charges` (**سالب = عليه دين للشركة**). تُحدَّث يدوياً من الـControllers.
2. **دفتر قيد مزدوج** (double-entry): لكل فني حساب فرعي `1140x` تحت الأب `1140 TechnicianReceivables`. **الأجور = مدين (debit)** على `1140x`؛ **التسديد = دائن (credit)**.

**قاعدة الاتجاه:** على حساب الفني `1140x`: `debit = أجور عليه`، `credit = تسديدات`. الرصيد يُشتق أحياناً من الذاكرة وأحياناً من الدفتر — وهذا مصدر تضارب (القسم 6).

### الكِيانات الأساسية
| الكِيان | الملف | الدور |
|--------|-------|------|
| `TechnicianTransaction` | `Accounting.cs:611-662` | سجل كل عملية أجور/تسديد على الفني |
| `TechnicianCollection` | `Accounting.cs:447-503` | مبالغ يحصّلها الفني من المواطنين (نقد بيده تحت التسليم) |
| `EmployeeSalary` | `Accounting.cs:228-318` | كشف راتب شهري لكل موظف |
| `SalaryPolicy` | `Accounting.cs:323-371` | قواعد الخصم/الإضافي لكل شركة |
| `EmployeeDeductionBonus` | `Accounting.cs:394-441` | خصم/مكافأة/بدل يدوي (وتُولَّد منه السلفة) |
| `WithdrawalRequest` | `AttendanceRecord.cs:350-387` | طلب سلفة (سحب أموال) |
| `DailySettlementReport` | `DailySettlementReport.cs:7-59` | تقرير تسليم يومي للمشغّل |
| `SubscriptionLog` | `SubscriptionLog.cs` | سجل التفعيل (نقطة الربط بالفني عبر `LinkedTechnicianId`) |
| `ServiceRequest` | `ServiceAndPermission.cs:256-364` | المهمة (نقطة ربط أجور المهام) |

**أكواد الحسابات** (`AccountCodes.cs`): `1110` نقد، `11104` صندوق الشركة، **`1140` ذمم الفنيين**، `1150` ذمم الوكلاء، `1160` ذمم المشغّلين، `1170` دفع إلكتروني، `2120` رواتب مستحقة، `4110` إيراد صيانة، `4120` إيراد خصم الشركة، `5100` مصروف رواتب، `5110` مصروف ترويج.

---

## 1. كيف تُضاف المبالغ على الموظف (أجور/دين)

### أ) من التفعيلات — نوع التحصيل «فني» (`CollectionType == "technician"`)
عند تفعيل/تجديد اشتراك «آجل على الفني»، يُنشأ **قيد محاسبي مزدوج + `TechnicianTransaction` + تحديث `User.Tech*`**.
- **المسار الأساسي**: `InternalDataController.cs:3221-3248` (`case "technician"`). ومكرّر في `FtthAccountingController.cs:359-391` و`SubscriptionLogsController.cs:274-300` (تكرار ثلاثي — القسم 6).
- **المبلغ المُحمَّل** = `collectedAmount = log.PlanPrice` (كامل ما يدفعه العميل).
- **الأثر**: `tech.TechTotalCharges += collectedAmount`؛ `TechNetBalance = Payments − Charges`؛ إدراج `TechnicianTransaction{Type=Charge, Category=Subscription, ReferenceNumber=log.Id}`.
- **القيد** (`JournalReferenceType.FtthSubscription`, ref=log.Id):

| الطرف | الحساب | المبلغ |
|------|--------|--------|
| **مدين** | `1140x` (ذمّة الفني) | `collectedAmount` |
| مدين | `5110` مصروف ترويج | `manualDiscount` (إن وُجد) |
| **دائن** | `11102` رصيد الصفحة | `netFromCompany` |
| دائن | `4110` إيراد صيانة | `maintenanceFee` |
| دائن | `4120` إيراد خصم الشركة | `companyDiscountProfit` |

### ب) من المهام — أجور إنجاز المهمة (`deliveryFee`)
عند تعليم `ServiceRequest` كـ`Completed` ووجود `deliveryFee` في `Details`: تُضاف أجور على الفني — **لكن بلا قيد محاسبي** (فرق جوهري).
- المسار: `ServiceRequestsController.cs:808-1099`؛ الدالة **`RegisterFeeOnUser`** (`:889-920`): `user.TechTotalCharges += amount` + إدراج `TechnicianTransaction(Charge, category, ServiceRequestId=id)` — و**`JournalEntryId` يبقى null** (لا يُستدعى `CreateAndPostJournalEntry`).
- تصنيف الفئة عند الإكمال (`:928-978`): صيانة⇒`Maintenance`، شراء⇒`InstallationFee` (على المُنشئ `createdById`)، تجديد⇒`OtherFee`، تحصيل⇒`DeliveryFee`.
- الاسترجاع عند الإلغاء (`:979-1094`) يحاول إبطال قيد **لم يُنشأ أصلاً**.

> **⚠️ اللاتماثل الأهم:** أجور التفعيلات تُنشئ قيداً محاسبياً؛ أجور المهام **لا**. فتظهر أجور المهام في `TechnicianTransaction`/`User.Tech*` فقط، ولا تظهر في رصيد الدفتر `1140x` الذي تعتمده لوحة المشغّلين ⇒ تضارب داخلي.

---

## 2. كيف تُسدَّد/تُدفع المبالغ للموظف

### أ) تسديد الفني (تحصيل منه) — `TechnicianTransactionsController.cs:534-635`
- `POST /api/techniciantransactions/record-payment` (`CompanyAdminOrAbove`). DTO: `TechnicianId, Amount>0, Description?, Notes?, TransactionDate?`.
- الأثر: `TechTotalPayments += Amount`؛ إعادة حساب `TechNetBalance`؛ `TechnicianTransaction{Payment, CashPayment}`.
- **القيد**: **مدين `11104` صندوق الشركة** / **دائن `1140x` ذمّة الفني** (ينقص دينه).

### ب) خصم الدين من الراتب — `AccountingController.cs:1816-1834`
عند صرف الراتب مع `DeductTechDues=true` و`TechNetBalance<0`: يُنشأ `TechnicianTransaction{Payment, SalaryDeduction}` وتُخصم القيمة من صافي الراتب النقدي، والقيد: دائن `1140` (الدين) + دائن `1110` نقد (الصافي الفعلي).

---

## 3. الرواتب والخصومات والسلف

### أ) توليد الرواتب (استحقاق) — `AccountingController.cs:1315-1683`
- `POST /api/accounting/salaries/generate`. نموذج «الأيام المكتسبة»:
  `earnedSalary = (أيام الحضور + إجازات مدفوعة) × الراتب اليومي` (نصف يوم=0.5)، ناقص خصم التأخير (مسقوف بنسبة)، خصم الخروج المبكر، زائد مكافأة الإضافي، ± الخصومات/المكافآت/البدلات اليدوية. **الغياب والإجازة غير المدفوعة لا يُخصمان** (نموذج مكتسب).
- **القيد (استحقاق)**: **مدين `5100` مصروف رواتب / دائن `2120` رواتب مستحقة** بإجمالي الصافي.

### ب) صرف راتب — `AccountingController.cs:1793-1938`
- `POST /api/accounting/salaries/{id}/pay`. القيد: مدين `2120` / دائن `1110` نقد (وإن خُصم الدين: دائن `1140` + دائن `1110`). صرف جماعي `pay-all` (`:1940-2028`).

### ج) خصومات/مكافآت يدوية — `AccountingController.cs:2388-2558`
`EmployeeDeductionBonus` (خصم/مكافأة/بدل/سلفة). **لا قيد محاسبي** — تؤثّر فقط في راتب الشهر التالي.

### د) السلف (سحب الأموال) — `WithdrawalRequestController.cs`
- تقديم/موافقة/رفض/إلغاء + `GET max-withdrawal/{userId}` (سقف من الأيام المكتسبة ناقص السلف القائمة).
- **`POST requests/{id}/pay`** (`:292-377`): يضبط الحالة Paid و**يُنشئ `EmployeeDeductionBonus{Deduction, "سلفة", IsApplied=false}`** — و**لا قيد ولا `CashTransaction`**. النقد يخرج فعلياً لكن الدفتر لا يراه حتى راتب الشهر التالي (أخطر فجوة محاسبية).

---

## 4. تسوية المشغّل اليومية (تسديد) — `InternalDataController.cs`
نقاط التسوية `[AllowAnonymous]` محمية بمفتاح API (تكامل FTTH): `settlement-reports` (قائمة/حفظ/تعديل/فحص) + **`accountant-post`** (`:3624-3764`) هو خطوة تحريك المال: يضبط `ReceivedAmount`، يُبطل أي قيد سابق، ثم يقيّد **مدين صندوق الشركة `1110x` / دائن صندوق المشغّل `1110x`**. تفصيل `SystemTechTotal`/`SystemAgentTotal` **معلوماتي فقط** ولا يُقيَّد على ذمم الفنيين/الوكلاء.

---

## 5. لوحة المشغّلين/الفنيين (تجميع) — `FtthAccountingController.cs:720-1316`
- **صفوف الفنيين** (`:1049-1201`): تجميع `SubscriptionLog` بـ`LinkedTechnicianId` حيث `CollectionType=="technician"`.
  - `technicianAmount` = إجمالي مبالغ التفعيلات.
  - `deliveredCash` = دائن `1140x` (تسديدات الفني، من القيود المرحّلة).
  - `netOwed` = مدين − دائن على `1140x` (الرصيد الحيّ).
  - `techRevenue` = مجموع `TechnicianTransaction.Amount` لفئات الأجور (Maintenance/InstallationFee/DeliveryFee/OtherFee) — دخل أجور المهام.

---

## 6. شاشة «شاشتي» (`my_dashboard`) — `my_dashboard_page.dart`
تُفتح من `home_page.dart:2663` (وصف: «البصمة والمعاملات والراتب»)، ممنوحة للجميع افتراضياً (`permission_registry.dart:1391`).

| القسم | المصدر (endpoint) | ما يُعرض |
|------|-------------------|---------|
| الملخص المالي | `GET /techniciantransactions/my-transactions` → `summary` | إجمالي الأجور، إجمالي التسديدات، الرصيد الصافي (مشتق من دفتر `1140`) |
| الراتب والاستحقاقات | `GET /hr-reports/my-report` → `Salary` | الأساسي/البدلات/المكافآت/الخصومات/السلف/الصافي + الحالة + تفصيل الخصومات |
| الخصومات/السلف (حوار) | `GET /accounting/employee-adjustments` | الفئة/المبلغ/الوصف/من أنشأ/متكرر/مُطبّق |
| طلبات الإجازة | `GET /leave/requests?userId=` | الحالة/النوع/الأيام/التواريخ/سبب/المراجِع |
| طلبات السحب | `GET /withdrawalrequest/my-requests` | الحالة/المبلغ/السبب/المراجِع |
| سقف السحب (حوار) | `GET /withdrawalrequest/max-withdrawal/{id}` | المتاح/المكتسب/السلف القائمة/أيام الحضور |
| الحضور اليومي | `my-report` → `Attendance.DailyRecords` | التاريخ/دخول/خروج/الحالة/دقائق التأخير والإضافي |
| المعاملات المالية | `my-transactions` → `transactions` | النوع/الفئة/المبلغ الموقّع/العميل/نوع المهمة/الرصيد بعد/رقم القيد/الملاحظات |

**عرض الرصيد**: أجور=أحمر (بادج «أجور»، مبلغ بسالب)، تسديد=أخضر («تسديد»، بموجب). الصافي يُعرض بقيمة مطلقة `.abs()`، والإشارة تُفهم من اللون + كلمة «مدين» فقط.

**شاشات موظف أخرى**: «معاملاتي المالية» (`technician_transactions_page.dart` — نسخة مكرّرة غير موصولة)، «البصمة» (`attendance_page.dart`)، «مهامي» (تحت `lib/task/`، بصلاحية `tasks` منفصلة)، «التبليغات». **لا توجد شاشة «تفعيلاتي»**، و«شاشتي» لا تعرض المهام رغم وصفها.

---

## 7. النواقص وفرص التحسين (مرتّبة بالأولوية)

### سلامة محاسبية
1. **السلفة لا تدخل الدفتر** (`WithdrawalRequestController.cs:292-377`): نقد يخرج بلا قيد/`CashTransaction`؛ لا حساب ذمم سلف موظفين. لو ترك الموظف قبل الراتب لا أثر محاسبي. **أهم إصلاح.**
2. **أجور المهام بلا قيد** (`ServiceRequestsController.cs:889-920`): تخالف أجور التفعيلات؛ لوحة المشغّلين (المعتمِدة على `1140x`) لا تراها ⇒ تضارب `netOwed` مع `TechNetBalance`.
3. **مصادر رصيد متعددة متضاربة**: `all-dues` (دفتر) vs `my-transactions`/`by-technician` (SubscriptionLogs+Tx) vs `recalculate-balances` (Tx فقط) vs ذاكرة `User.*`. تشغيلها بترتيب مختلف يعطي أرصدة مختلفة. **توحيدها على الدفتر مصدراً وحيداً.**
4. **مطابقة الحساب بالاسم** (`TechnicianTransactionsController` all-dues `:445-451`، و`ServiceRequestsController:833-834`): `FullName` مكرّر/مُعاد التسمية يُخطئ الإسناد. استخدم Guid الفني في `Details`.
5. **صرف الراتب يرجع لحساب `5100` عند غياب `2120`** (`AccountingController.cs:1888`) ⇒ ازدواج مصروف (استُحقّ مسبقاً).
6. **تعديل راتب Pending لا يعدّل قيد الاستحقاق** (`:1708`) ⇒ عدم تطابق الصافي مع الدفتر.

### مخطط/بيانات
7. **`TechnicianTransaction` بلا إعداد EF** (`SadaraDbContext.cs:232`): لا `HasPrecision`، لا فهارس على `TechnicianId/CompanyId/CreatedAt`، لا FK — جدول عالي الحجم باستعلامات مالية غير مفهرسة.
8. **`DailySettlementReport`/`WithdrawalRequest` بلا دقّة أرقام ولا FK/عزل شركة** (مطابقة heuristic بـMD5 في accountant-post — خطر عبر المستأجرين).
9. **حقول ميتة**: `EmployeeSalary.AbsentDeduction/UnpaidLeaveDeduction` و`SalaryPolicy.AbsentDayMultiplier/UnpaidLeaveDayMultiplier` (غير مستخدمة).

### أمان
10. **نقاط التسوية `[AllowAnonymous]`** بمفتاح API فقط، و`accountant-post` يحرّك المال ⇒ تسريب المفتاح = قيود عشوائية.
11. **`PaySalaryDto.PaidById` و`CreateAdjustmentDto.CreatedById` من العميل** لا من التوكن ⇒ انتحال هوية الفاعل.

### كتابات غير ذرّية
12. تحديث الذاكرة يُحفظ ثم يُنشأ القيد داخل `try/catch` يسجّل فقط (`TechnicianTransactionsController.cs:576-617`) ⇒ فشل القيد يترك `User.*` محدّثاً بلا قيد (commit جزئي بلا transaction).

### شاشة الموظف (تجربة/شفافية)
13. **الرصيد الصافي غامض**: قيمة مطلقة + لون + «مدين» فقط؛ لا «لك/عليك X» صريحة، وإشارة الأجور بالسالب تربك.
14. **لا فلتر تاريخ** في «شاشتي» رغم دعم backend لـ`from/to`.
15. **راتب الشهر تقديري بلا وسم واضح** قبل الترحيل.
16. **لا مهام ولا «تفعيلاتي»**: الموظف لا يرى إنتاجيته (عدد التفعيلات/المهام) ولا تقييماته (`TaskAudits` إدارية فقط).
17. **لا رصيد إجازات** (رغم توفّر `GET /leave/balances/{id}`)، **لا اختيار شهر** (مقفول على الحالي)، **لا كشف راتب PDF**.
18. **تكرار كود**: `technician_transactions_page.dart` نسخة ثانية من قسم المعاملات — خطر صيانة.

---

## 8. حزم تحسين مقترحة (للتنفيذ لاحقاً بموافقتك)
- **حزمة أ (سلامة الدفتر):** قيد للسلفة (مدين ذمم سلف / دائن نقد) + قيد لأجور المهام (مدين `1140x` / دائن إيراد) + توحيد مصدر الرصيد على الدفتر.
- **حزمة ب (المخطط):** إعداد EF كامل لـ`TechnicianTransaction` (دقّة + فهارس + FK) + دقّة أرقام + عزل شركة لتقارير التسوية والسحب.
- **حزمة ج (الأمان):** اشتقاق `PaidById`/`CreatedById` من التوكن + تقييد/تدوير مفتاح التسوية + لف الكتابات في transaction.
- **حزمة د (شاشتي):** توضيح الصافي («لك/عليك») + فلتر تاريخ + اختيار شهر + رصيد إجازات + قسم «تفعيلاتي/إنتاجيتي» + كشف راتب قابل للطباعة + إزالة الشاشة المكرّرة.
- **حزمة هـ (توحيد):** استخراج منطق `case "technician"` المكرّر ثلاثياً إلى خدمة واحدة في `Sadara.Application`.
