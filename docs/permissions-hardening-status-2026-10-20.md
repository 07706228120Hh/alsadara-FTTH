# حوكمة الصلاحيات وعزل المستأجرين — الحالة والكشف الكامل

> مرجع موحّد (2026-10-18 → 2026-10-20). العمل على فرع `security/expose-endpoints-hardening`. الذاكرة التشغيلية في `.claude/memory/permissions-isolation-audit-2026-10-18.md` و`RISKS.md`.

---

## 1. ما هو حيّ على الإنتاج (منشور ومتحقَّق)

| البند | التفاصيل |
|------|----------|
| عزل الشركات — حُرّاس المتحكّمات | نمط `ScopeCompanyId`/`_tenant` على: HrReports، Departments، CompanyCenters، Users، ServiceRequests، Accounting(reads) |
| عزل الشركات — الفلتر المركزي | `Tenancy:EnforceIsolation=true` مرفوع؛ يعزل كل الكيانات المستأجرة على مستوى القاعدة |
| استثناءات الفلتر | PermissionTemplate, InternetPlan, EmployeeLocationLog, WhatsAppBatchReport, WhatsAppConversation (عابرة بالتصميم عبر n8n/المفتاح الداخلي) |
| ردم `CompanyId` | 78,119 صفاً (JournalEntryLines/Notifications/DailySettlement/EmployeeLocations/Logs/ReminderExecutionLogs) |
| migration | `IptvSubscriber.CompanyId` نص→Guid |
| إغلاق نقاط مكشوفة | CompaniesController.by-code (PII)، Notifications IDOR، Merchants [Authorize]، OCR [Authorize]+توكن، ZainCash callback معطّل خلف علَم |
| **backfill منح V2** | منح الأدوار مفاتيحها (hr/accounting للمستخدمين الفعليين؛ routers/company_dashboard/audit_dashboard/dashboard_project للأدمن؛ zones للفنيين) — يمنع الإقفال عند نشر حوكمة الواجهة |

**النسخ الاحتياطية**: `/root/backups/` (قبل كل تغيير) + `C:\SadaraBackups` + `E:\New folder (2)`.

**أوامر التراجع:**
- علَم العزل: `cp /root/backups/appsettings.Production.json.pre_iso_20261019_012657 /var/www/sadara-api/appsettings.Production.json && systemctl restart sadara-api`
- منح V2 / IPTV: استعادة `/root/backups/db_pre_grant_20261020_002929.dump` أو `db_pre_isolation_20261018_222557.dump`.

---

## 2. جاهز على الفرع (غير منشور) — حوكمة الواجهة + بنية الباكند

| الدفعة | commit |
|--------|--------|
| حوكمة HR + «مشترك جديد» | ed9b0c2 |
| حوكمة أزرار الحركات المالية (9 ملفات) | 194c607 |
| إضافة المفاتيح الناقصة للسجل | 92ec096 |
| ربط الشاشات بالمفاتيح (GenieACS/صفحة الشركة/محاسبة/FTTH) | 609def8 |
| بنية `Authz:FailClosed` (deny-by-default خلف علَم، محايد OFF) | 341b280 |
| تغطية RequirePermission — دفعة 1: 10 متحكّمات authorize-only + 3 إصلاحات مراجعة | 13549e5 |
| تغطية RequirePermission — دفعة 2: 6 متحكّمات policy بمفاتيح موجودة (46 سمة) | 49b3ef9 |

**تغطية الباكند بعد الدفعتين**: غُطّيت كل الفئة `authorize-only` الأخطر (ISPSubscribers, SubscriptionLogs, FtthAccounting, Chat, Announcements, Notifications, TaskAudits, ServiceRequests, ZoneMaintenanceFees) + فئة `policy→مفتاح موجود` (Leave, Departments, CompanyCenters, WithdrawalRequest, TechnicianTransactions, Dashboard). كلها إضافية (لا استبدال لأي [Authorize])، مُراجَعة مزدوجاً (لا P0)، بناء 0 أخطاء، على الفرع فقط.

**إصلاحات أمنية ضمن دفعة 1** (من المراجعة): حارس ملكية `CanAccessUser` على `Notifications.Delete/MarkAsRead` (سدّ IDOR عابر للمستأجر — الكيان غير ITenantScoped)؛ فعل `ZoneMaintenanceFees.Delete` من `delete`→`edit` (منع إقفال عند النشر)؛ إرجاع `OcrController` إلى `[Authorize]` فقط (تدفّق تسجيل المشترك غير محكوم بمفتاح بعد).

**ديون عزل قائمة رُصدت أثناء الدفعتين** (خارج نطاق إضافة السمات، للمعالجة لاحقاً بموافقة): `DashboardController` يحسب كل الإحصاءات عبر كل الشركات بلا فلتر CompanyId ⚠️؛ `Leave`/`Withdrawal`/`TechnicianTransactions` تقبل `companyId` من العميل في بعض القراءات/التعديلات.

**لم يُطبَّق (يتطلّب مفاتيح سجل جديدة + إصدار تطبيق + منح — بوّابة مالك)**: needs-new-key (store.*, merchants, citizen_portal, reviews, settings, cities ≈ 104 نقطة).
**مُستبعَد عمداً**: SuperAdminController/ServerController (policy:SuperAdmin أصلاً + SuperAdmin يتجاوز RequirePermission كلياً + تتضمّن تنفيذ أوامر — لا فائدة تنفيذية من السمة).

**معلّق**: 4 ملفات محاسبة مختلطة (تعديلات المستخدم + الحجب): `budget_page` · `chart_of_accounts_page` · `collections_page` · `compound_journal_entry_page`.

---

## 3. الكشف — ما كان لا يخضع للصلاحيات (تدقيق 2026-10-19)

> 150 عنصراً عبر 5 أبعاد. (بُعد الباكند أُعيد مسحه لاحقاً عبر خريطة التغطية.)

### 3.1 عناصر تنقّل/بطاقات بلا فحص (21) — عولج معظمها
أبرزها: بطاقتا «مشترك جديد»/«صفحة الشركة» `permissionKey:''`؛ مركز HR كاملاً (الرواتب/الخصومات/المستخدمين)؛ GenieACS؛ مهام التوصيل/بحث/تسجيل؛ خريطة الزونات؛ Superset.

### 3.2 أزرار إجراءات بلا `can(action)` (31 شاشة) — عولج معظمها
محاسبة (chart/collections/budget/cashbox إيداع-سحب/revenue/fixed_expenses/client_accounts/compound) · ساس (إيداع رصيد/دفعي) · تحويلات (إدخال يدوي/حذف تسوية) · super_admin.

### 3.3 شاشات بلا مفتاح سجل (~37) — عولجت الإضافة
وحدة network_quality (كانت قبل الدخول) · لوحة super_admin · إعدادات/تشخيص · مفاتيح محاسبة فرعية · تبويبات الساس الـ8 (مؤجّلة للتنسيق).

### 3.4 منطق مثبّت (hardcoded) (~37 موضعاً) — لم يُستبدَل بعد
- كواشف أدمن نصّية: `_isAdminUser=contains('مدير'/'admin')` (home_page.dart:227) · ftth login/core · daily_settlement · account_records.
- أكواد سحرية: كود الشركة `'1'`/`'ADMIN'`/`'SUPER'` (vps_tenant_login:688، premium_login:363، vps_auth_service:316).
- `grantAll`/`grantAllSystems` (permission_manager.dart:302/314).
- باكند: `User.IsInRole`/`IsCompanyAdminOrAbove` بدل مفاتيح (DatabaseAdmin:40، Reviews:214، Settings:62، Chat:133، LinkedAccounts:170، Sas:272، ...).
- سرّ مضمّن: مفتاح API داخلي (account_records_page.dart:174) — P0.

---

## 4. المتبقّي (خارطة طريق)

| البند | الحجم | البوّابة |
|------|-------|---------|
| تطبيق `RequirePermission` على كل endpoint باكند | كبير | خريطة التغطية (قيد الإنجاز) + grant-readiness |
| رفع علَم `Authz:FailClosed` على الإنتاج | خطير | ختم V2 شاملاً + وضع تسجيل-فقط + موافقة |
| **إصدار تطبيق Flutter** (ليصل حوكمة الواجهة للأجهزة) | كبير | tag `v*` = موافقة المالك |
| استبدال المنطق المثبّت (3.4) | متوسط | مراجعة أمنية |
| فرعيات الساس الـ8 | صغير | تنسيق وكلاء sas |
| تدوير `Security:InternalApiKey` (P0) | — | مؤجّل بقرار المالك + تنسيق n8n |
| 4 ملفات محاسبة مختلطة | صغير | قرار المستخدم |

---

## 5. البوّابات الإنتاجية (لا تُنفَّذ بلا موافقة صريحة لكل منها)
1. إصدار تطبيق Flutter (tag `v*`، auto-update لكل الأجهزة).
2. رفع علَم `Authz:FailClosed` (deny-by-default) على الإنتاج.
3. تدوير المفتاح الداخلي.
4. أي migration/تطبيق على قاعدة الإنتاج.
