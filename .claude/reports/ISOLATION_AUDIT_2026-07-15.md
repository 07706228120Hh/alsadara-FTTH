# تدقيق العزل التام متعدد الشركات (Multi-Tenant Isolation) — منصة الصدارة

> تاريخ: 2026-07-15 · الفرع: `feature/phase1-security` · النطاق: عمليات FTTH فقط (المتجر/بوابة المواطن تبقى لرمز الصدارة)
> الحالة: تحليل مُتحقَّق (قراءة فقط). لا migration مُنفّذ، لا نشر، لا تعديل بيانات.
> المصدر: تدقيقان متوازيان (database-postgres-agent لجرد الكيانات + security-auditor-agent لجرد نقاط النهاية)، كل ادعاء بـ file:line من قراءة فعلية.

---

## 0) الخلاصة التنفيذية

- **الجذر**: لا يوجد أي فلتر شركة مركزي على مستوى قاعدة البيانات. الفلاتر العامة الوحيدة في `SadaraDbContext.cs:184-266` هي لـ `IsDeleted` فقط. السياسات في `Program.cs:136-161` **دور فقط وليست مقيّدة بالشركة**. لذا الحاجز الوحيد بين شركة وأخرى اليوم هو شرط `.Where(x => x.CompanyId == companyId)` اليدوي، و`companyId` يأتي **من العميل** في الغالبية — أي عزل يعتمد على الثقة بمدخلات العميل.
- **اكتشاف حرج يغيّر الأولويات**: الـ commit `fe0e2dd` عالج أسرار Program.cs فقط، لكن **أسرار توقيع JWT ومفاتيح داخلية ما زالت مضمّنة نصّياً (fallback) داخل ~10 controllers**. طالما بقيت، يمكن تزوير توكن `role=SuperAdmin` بأي `company_id` → **تجاوز الفلتر المركزي نفسه**. لذا يجب أن تسبق إزالتُها تفعيلَ الفلتر.
- **قاعدة السلامة**: لا يُفعَّل الفلتر على أي كيان قبل أن يملك `CompanyId` مملوءاً (NOT NULL فعلياً). تفعيله على كيان `Guid?` فيه صفوف NULL أو على `string` = اختفاء بيانات إنتاج حيّة.

---

## 1) جرد الكيانات (130 كلاس عبر 38 ملف في `Sadara.Domain/Entities`)

- 79 كياناً يحمل `CompanyId`: منها **1 من نوع `string`** (خطر)، و~24 من نوع `Guid?` (خطر nullable)، والباقي `Guid`.
- ~30 كياناً ابناً (child) بلا عمود — يُفلتر عبر الأب (EF Core لا يورّث الفلتر تلقائياً؛ يجب تعريفه صراحةً عبر التنقل).
- ~13 كياناً يُستثنى (متجر مركزي/كتالوج/نظامي).

### أ) كيانات FTTH بلا عمود CompanyId صالح — تمنع تفعيل الفلتر (إجراء مطلوب)
| الكيان | الملف:السطر | المعالجة المقترحة |
|---|---|---|
| EmployeeLocationLog | EmployeeLocation.cs:39 | إضافة `Guid? CompanyId` مباشرة (UserId نصّي، لا FK للاشتقاق) |
| WhatsAppBatchReport | WhatsAppBatchReport.cs:6 | إضافة `Guid? CompanyId` مباشرة (تقرير على مستوى الشركة) |
| ReminderSettings | ReminderSettings.cs:6 | يستخدم `string TenantId` — توحيد إلى `Guid CompanyId` + backfill |
| ReminderExecutionLog | ReminderSettings.cs:18 | يستخدم `string TenantId` — نفس التوحيد |

### ب) عدم اتساق النوع (الأخطر عند التفعيل)
- **IptvSubscriber.CompanyId — `IptvSubscriber.cs:12` — النوع `string`** (افتراضي `string.Empty`). مؤكَّد. يلزم تحويله إلى `Guid?` عبر عمود مؤقت + backfill + تبديل (لا `ALTER TYPE` مباشر).
- **الكيانات `Guid?` الحرجة (FTTH-OPS)** — يجب تشغيل `COUNT(*) WHERE CompanyId IS NULL` لكلٍّ قبل التفعيل، وأخطرها بيانات تشغيلية أساسية:
  - **SubscriptionLog** (SubscriptionLog.cs:50) — سجل التفعيلات المحوري.
  - **ServiceRequest** (ServiceAndPermission.cs:279) — التعليق في الكود يذكر أنه قد يكون null.
  - ISPSubscriber, ZoneStatistic, DailySettlementReport, TaskAudit, EmployeeLocation, AttendanceRecord (+\u200FAuditLog/WorkSchedule/WorkCenter/LeaveRequest/LeaveBalance/WithdrawalRequest), WhatsAppConversation, Notification.
- **حالة خاصة — `InternetPlan.CompanyId` `Guid?`** (Subscription.cs:11): `null = باقة عامة`. الفلتر يجب أن يسمح بـ `CompanyId == current || CompanyId == null`، وإلا تختفي الباقات العامة.
- **حالة خاصة — `User.CompanyId` `Guid?`** (User.cs:30): المواطنون بلا شركة عمداً؛ الفلتر يجب ألا يحذفهم.

### ج) كيانات تُستثنى من الفلتر
- متجر الصدارة (Merchant-based): Merchant, Customer, Product, Order/OrderItem, Payment, Wallet, Category, Review, Cart/Wishlist, Coupon, Address, Setting, Advertising.
- مرجعي/نظامي: City, Area, AuditLog, AppVersion.
- كتالوج RBAC مشترك: PermissionGroup, Permission, Service, OperationType, ServiceOperation, PermissionTemplate/TemplatePermission (UserPermission يُفلتر عبر User).
- حدّية (قرار بنيوي لاحق): STORE/CITIZEN (Citizen, CitizenPayment, StoreProduct/Order, SupportTicket, CitizenSubscription, InternetPlan) — تحمل CompanyId لكنها ليست عمليات FTTH داخلية.

---

## 2) جرد نقاط النهاية (58 controller) — ثغرات العزل

### P0 — حرجة (أسرار مضمّنة / تجاوز كامل للعزل)
- **P0-1** `InternalDataController.cs:55` — مفتاح داخلي مضمّن `"sadara-internal-2024-secure-key"` fallback؛ ~60 endpoint `[AllowAnonymous]` (إنشاء/حذف شركات وموظفين وكلمات مرور، `GetSubscriptionLogs` بلا companyId = كل الشركات `:1748`).
- **P0-2** `CompanyFtthSettingsController.cs:40` — نفس المفتاح؛ endpoints تدميرية بـ `{companyId}` من المسار: ClearData `:548`, TriggerSync `:262`, DeleteAllSyncLogs `:388`.
- **P0-3** `FtthAccountingController.cs:2757` — `RecalculateSyncRevenues` `[AllowAnonymous]` بحارس مقارنة نصّية للمفتاح المضمّن؛ يعيد إنشاء القيود لأي شركة. **(ملاحظة: هذا هو الـ endpoint الذي أجّلناه — التطبيق يستدعيه عبر accounting_service.dart:861)**.
- **P0-4** أسرار JWT مضمّنة `"YourSuperSecretKeyThatIsAtLeast32CharactersLong!"` في: UnifiedAuthController.cs:1069, CitizenAuthController.cs:723, CompaniesController.cs:236, AgentsController.cs:1780. ومفتاح داخلي أيضاً في WhatsAppController.cs:42, SubscriberCacheController.cs:40, IptvSubscribersController.cs:29. **`fe0e2dd` لم يمسّها.** توكن مزوّر بـ SuperAdmin = انهيار العزل كله.
- **P0-5** `AccountingController` — IDOR شامل على المحاسبة: `companyId` من العميل في GetAccounts `:37`, GetJournalEntries `:375`, GetCashBoxes `:807`, GetSalaries `:1223`, Dashboard `:4195`, TrialBalance `:4687`... وكتابة عبر `dto.CompanyId` (`:224,:549,:883`). عند null = كل الشركات.

### P1 — عالية (IDOR / غياب فلترة)
- **P1-1** HrReports: `companyId` إلزامي من العميل + تصدير CSV لرواتب/حضور أي شركة (`:33,:107,:181,:259,:649`).
- **P1-2** ISPSubscribers: **لا فلتر شركة إطلاقاً** رغم وجود العمود — PII لكل المشتركين (`:16 GetAll`, `:59 KinshipSearch`).
- **P1-3** FtthAccounting: `companyId` من العميل + شرط `|| l.CompanyId == null` يسرّب السجلات القديمة للجميع (`:508,:710`)؛ كتابة عبر `dto.CompanyId`.
- **P1-4** Agents: IDOR على الوكلاء ومعاملاتهم المالية (`:122,:384,:792`).
- **P1-5** Attendance: `companyId` من العميل على الحضور/المراكز/الأجهزة (`:547,:567,:605,:1059`).
- **P1-6** CompanyCenters: `{companyId}` من المسار مصدر ثقة للكتابة/الحذف (`:13,:48,:99,:139`).
- **P1-7** CompanyFtthSettings: قراءة عابرة (إعدادات/سجلات/حالة مزامنة أي شركة).
- **P1-8** IptvSubscribers: `companyId` من العميل + مفتاح مشترك.
- **P1-9** EmployeeLocation: مواقع GPS لكل الشركات `[AllowAnonymous]`+مفتاح (`:277,:316,:372,:425`) + Purge تدميري `:719`.
- **P1-10** SubscriberCache / **P1-11** WhatsApp: مفاتيح مشتركة مضمّنة.

### P2 — متوسطة
- ServiceRequests.GetAll (`:45` companyId من العميل)، SubscriptionLogs (قوائم بسياسة Admin)، DatabaseAdminController (مسار المفتاح المشترك يمنح إدارة DB كاملة لغير SuperAdmin `:16-48`)، وامتداد قوائم AccountingController/HrReports، وDepartments/Zone/Leave/Chat (تحتاج تدقيقاً فردياً).

### أثر الفلتر المركزي
- **يُغلق تلقائياً** (~13–15 مجموعة قراءة على كيانات مستأجرة عند null/بلا فلتر): P0-5 قراءات، P1-2, P1-3 قراءات, P1-4, P1-5, P2-1, P2-2.
- **يحتاج إصلاحاً يدوياً** (~15–18 مجموعة): كل P0 (أسرار مضمّنة/AllowAnonymous لا يمسّها الفلتر)، كتابات `dto.CompanyId`، P1-1/P1-6 (companyId من المسار)، ومسارات المفتاح المشترك.

---

## 3) الترتيب الآمن المقترح (لا يُنفَّذ إلا بموافقة عند كل بوابة)

1. **الأساس** ✅ (منجز، commit `a9c3886`): `ICurrentTenant` + `CurrentTenant` + claim `company_id` في توكن الدخول الرئيسي.
2. **إزالة الأسرار المضمّنة (P0-4 وأخواتها)** — كود فقط، يجعل الفلتر غير قابل للتجاوز. **تدوير المفتاحين `Jwt:Secret` و`Security:InternalApiKey` يحتاج موافقتك (تغيير أسرار).**
3. **ربط Program.cs**: تسجيل `ICurrentTenant` + `IHttpContextAccessor` في DI + إثراء التوكنات القديمة عبر `OnTokenValidated` (آمن، إضافي).
4. **Migrations (بوابة موافقة + اختبار)**: إضافة CompanyId للكيانات الأربعة الناقصة، توحيد IptvSubscriber (string→Guid)، backfill لكل صفوف NULL بشركة رمز الصدارة، ثم (اختياري) NOT NULL. **لا تُشغَّل على الإنتاج بلا نسخة احتياطية + اختبار.**
5. **تفعيل الفلتر المركزي** كياناً كياناً بعد اجتياز اختبار الامتلاء (مع استثناء المتجر/الكتالوج، ومراعاة `null = عام` في InternetPlan، والمواطنين في User).
6. **إصلاح يدوي**: إزالة `companyId` من مدخلات العميل + منع الكتابة عبر `dto.CompanyId` + التحقق من `{companyId}` مقابل التوكن.
7. **اختبار بشركتين على staging** ثم نشر متحكَّم.

---

## 4) ملفات مرجعية عالية المخاطر
`IptvSubscriber.cs`, `ReminderSettings.cs`, `WhatsAppBatchReport.cs`, `EmployeeLocation.cs`, `SubscriptionLog.cs`, `ServiceAndPermission.cs` (ServiceRequest), `WhatsAppData.cs`,
`InternalDataController.cs`, `CompanyFtthSettingsController.cs`, `FtthAccountingController.cs`, `AccountingController.cs`, `HrReportsController.cs`, `ISPSubscribersController.cs`, `Program.cs` (136-161), `SadaraDbContext.cs` (184-266).
