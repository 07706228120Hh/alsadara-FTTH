# خطة مطابقة «فوترة الساس» لنظام FTTH

> الهدف: جعل تفعيل/تجديد مشترك **الساس** يُنتج نفس ما يُنتجه تفعيل **FTTH** من:
> **(1) محاسبة (قيد مزدوج) · (2) تخزين حركة · (3) طباعة إيصال حراري · (4) رسالة واتساب.**
> مبني على فحص دقيق للكود الفعلي (أكتوبر 2026).

---

## 1) الوضع الحالي — الفجوة (مؤكَّدة بالكود)

| الخط | FTTH | الساس (الآن) |
|---|---|---|
| المحاسبة | قيد يومية مزدوج كامل | **لا شيء** |
| تخزين الحركة | `SubscriptionLogs` + VPS | **لا شيء** (`agent_reports` للبلنك الشهري فقط) |
| الطباعة | `ThermalPrinterService` + قالب V2 + ESC/POS | **لا شيء** |
| الواتساب | تلقائي بعد التفعيل (app/server/api) | وحدة موجودة لكن **يدوية فقط** وقوالب فقيرة |

مسار الساس الحالي: `_doActivate/_doExtend/_doChangeProfile` → `userAction` → بوّابة `UserAction` → خدمة `/users/action` → SAS4، ثم **`_run()` ينتهي بـ `_toast` + `_loadMain` فقط** ([sas_subscriber_detail_page.dart:113]) — ولا كتابة لأي حركة خادمياً (`_exec_user_action` يمرّر ويعيد بلا تخزين).

---

## 2) كيف يعمل FTTH (المرجع الدقيق)

### 2.أ المحاسبة — القيد المزدوج
المعادلات (من `FtthAccountingController.CreateAccountingEntry`):
```
netFromCompany   = BasePrice − CompanyDiscount         // يُخصم من «رصيد الصفحة» (ثابت)
companyDiscountProfit = SystemDiscountEnabled ? 0 : CompanyDiscount
revenue          = MaintenanceFee + companyDiscountProfit
collectedAmount  = netFromCompany + revenue − ManualDiscount   // ما يدفعه العميل
```
أسطر القيد (Posted فوراً، متوازن جبرياً):

| الطرف | الحساب | الكود | المبلغ |
|---|---|---|---|
| مدين | حساب التحصيل حسب `CollectionType` | cash `1110x`/credit `1160x`/master `1170`/agent `1150x`/technician `1140x` | `collectedAmount` |
| مدين | مصاريف العروض | `5110` | `ManualDiscount` |
| دائن | **رصيد الصفحة** | `11102` | `netFromCompany` |
| دائن | إيراد الصيانة | `4110` | `MaintenanceFee` |
| دائن | إيراد خصم الشركة | `4120` | `companyDiscountProfit` |

- `agent`/`technician` تُحدّث رصيد الكيان (`TotalCharges`/`TechTotalCharges`) + تُنشئ `AgentTransaction`/`TechnicianTransaction`.
- الحسابات الفرعية تُنشأ تلقائياً `FindOrCreateSubAccount` (Description=personId).
- **العزل يدوي**: `companyId` من جسم الطلب يُمرَّر لكل helper (لا query filter تلقائي).
- **المنطق مكرّر ٣ مرّات** (`InternalDataController` / `SubscriptionLogsController` / `FtthAccountingController`) — سبب وجود `repair-accounting`.

### 2.ب التخزين
- كيان `SubscriptionLog` (BaseEntity<long>): CollectionType, BasePrice, CompanyDiscount, ManualDiscount, MaintenanceFee, SystemDiscountEnabled, PlanPrice, WalletBalanceBefore/After, FtthTransactionId, LinkedAgentId, LinkedTechnicianId, JournalEntryId, SessionId(منع تكرار), CompanyId, UserId…
- نقطة العميل الفعلية: `POST api/internal/subscriptionlogs` (مصادقة `X-Api-Key`) → تُنشئ السجل + القيد تلقائياً.
- الأغنى: `POST api/ftth-accounting/log-with-accounting` (JWT) — يستنتج BasePrice/الصيانة من `InternetPlans`/`ZoneMaintenanceFees`.

### 2.ج الطباعة
- `ThermalPrinterService.printFromReceiptTemplate({variableValues, conditions})` في **`lib/services/`** (مشتركة، ليست داخل ftth/ → **قابلة للاستيراد من الساس مباشرة**).
- قالب V2 (`ReceiptTemplateStorageV2`, SharedPreferences) + `ReceiptPdfBuilder` (يستبدل `{{var}}`) + عدّاد وصل + لوغو + قطع ESC/POS.
- المتغيّرات: operationType, customerName, customerPhone, totalPrice, currency, endDate, activatedBy, receiptNumber, selectedPlan, commitmentPeriod, basePrice, discount, paymentMethod, …

### 2.د الواتساب
- `_runBackgroundPostActivation`: (إغلاق مهمة) → (مهمة تحصيل) → **طباعة** → **واتساب** (كلٌّ في try/catch مستقل، خلفياً).
- `sendWhatsAppMessage()` يختار النظام (app/web/server/api) من `WhatsAppSystemSettingsService`؛ قالب نصّي غنيّ بالحقول؛ الرقم من API ثم `widget.userPhone`؛ تطبيع `964…`.

---

## 3) ما تملكه وحدة الساس + البيانات المتاحة لحظة التفعيل

| البيان | متاح؟ | المصدر |
|---|---|---|
| username/الاسم/الباقة/الانتهاء القديم | ✅ | `_detail`/`candidate`/`local_subscribers` |
| رقم الهاتف | ✅ | `local_subscribers.phone` / SAS4 `user/{id}.phone` |
| الانتهاء الجديد | ✅ بعد reload | `getUserDetail` بعد التنفيذ |
| **السعر/الكلفة + VAT + رصيد الوكيل** | ✅ (غير مُستهلَك حالياً) | **SAS4 `GET user/activationData/{id}`** → `n_required_amount`,`vat`,`manager_balance`,`user_balance` — **مسموح أصلاً في بروكسي GET** فيُجلب فوراً عبر `sasGet` بلا تعديل خادمي |
| هوية الوكيل/الشركة/الحساب | ✅ خادمياً | `account.CompanyId/OwnerUserId/Id` داخل `PassThroughWriteAsync` |
| معرّف عملية (idempotency) | ✅ | `_txn()` بالواجهة |

- **قيد مهم**: مسار **التمديد** `user/extensionData` **لا يعيد سعراً** (balance فقط) → للتمديد نأخذ السعر من `activationData` أو سعر الباقة (`Packages`).
- **طبقة واتساب الساس** (`lib/sas_agent/whatsapp/**`) أنظف (senders app/server/api + templates)، لكن: `api` مجرّد stub، والقوالب فقيرة الحقول (name/username/profile/expiration/days فقط)، ولا خطّاف تلقائي.
- **لا جدول حركات** في SQLite الخدمة (`agent_reports` للبلنك فقط).

---

## 4) المعمارية المستهدفة (قرار محوري: دفتر موحّد)

**التوصية: محاسبة موحّدة** — تفعيل الساس يُغذّي **نفس** دفتر الصدارة (`SubscriptionLogs` + `JournalEntries` + نفس شجرة الحسابات)، مع تمييز `Source = sas|ftth`. فائدته: تقارير/أرباح/أرصدة موحّدة عبر النظامين بلا منظومة موازية.

> البديل (مرفوض): محاسبة مستقلّة في SQLite الخدمة → ازدواج + تقارير منفصلة.

**تخطيط حقول الساس على `SubscriptionLog`:**
```
Source           = "sas"
SasAccountId     = account.Id
SubscriberUsername / SubscriberUid
PlanName         = اسم الباقة (من activationData/Packages)
BasePrice        = activationData.n_required_amount           // كلفة الوكيل = «رصيد الصفحة»
CompanyDiscount  = خصم الوكيل (discount_rate) إن وُجد
MaintenanceFee   = هامش/أجور يحدّده الوكيل (اختياري)
ManualDiscount   = خصم يدوي للعميل (اختياري)
PlanPrice        = collectedAmount (ما يُحصّل من العميل)
CollectionType   = cash | credit | agent
FtthTransactionId= transaction_id (idempotency عبر SessionId)
phone / CompanyId / UserId
```
هكذا ينطبق **نفس** منطق القيد المزدوج حرفياً (رصيد الصفحة 11102 = رصيد صفحة الوكيل لدى مزوّد الساس).

---

## 5) الخطة التفصيلية — الأعمدة الأربعة

### 5.١ توحيد المحاسبة (أولاً — أساس البقية)
1. **استخراج helper مشترك** `SubscriptionAccountingService` من النسخ الثلاث المكرّرة (مرجع أدقّ: `FtthAccountingController.CreateAccountingEntry`) — لإنهاء الازدواج ومنع الانحراف.
2. إضافة عمود `Source` (enum: Ftth=0, Sas=1) + حقول الساس الاختيارية إلى `SubscriptionLog` (+ migration إضافية بحتة؛ لا تمسّ الإنتاج حتى الموافقة).
3. نقطة خادمية جديدة في البوّابة: `POST api/sas-agent/accounts/{id}/users/{uid}/activate-billed` (manage, failClosed) — تُنفّذ: (أ) جلب `activationData` للسعر، (ب) `UserActionAsync('activate'|'extend'|'changeProfile')` على SAS4، (ج) عند النجاح `SubscriptionAccountingService.record(log{Source=Sas,…})`, (د) ترجع {نجاح + بيانات الإيصال + القيد}. الهوية والعزل مختومان خادمياً (`account.CompanyId/OwnerUserId`).

### 5.٢ تخزين الحركة
- السجل الأساسي = `SubscriptionLog` الموحّد (الخطوة 5.1). 
- **+ (اختياري) جدول محلي للخدمة** `sas_transactions` (SQLite، معزول بـ `account_id`) لسجلّ سريع للوكيل داخل تبويب الساس (history/تقارير) بلا نداء الباكند: أعمدة `account_id, sub_id, username, action, profile_name, months, old_exp, new_exp, price_n, currency, manager_balance_after, phone, transaction_id, status, created_at`. يُضاف بنمط DDL الحالي (`CREATE TABLE IF NOT EXISTS`).
- منع التكرار: `SessionId/transaction_id` (كما FTTH).

### 5.٣ الطباعة الحرارية (إعادة استخدام مباشر — أقل جهد)
- `ThermalPrinterService` + القالب + PDF builder + ESC/POS **في `lib/services/` (مشتركة)** → الساس يستوردها مباشرة بلا نقل.
- المطلوب فقط: دالة `_buildSasReceiptVars()` تملأ متغيّرات القالب من بيانات تفعيل الساس (operationType="تم تفعيل اشتراك"/"تم التجديد"، customerName, phone, selectedPlan, totalPrice, endDate الجديد, activatedBy, paymentMethod…)، ثم `printFromReceiptTemplate(vars, conds)`.
- ملاحظة: القالب V2 الحالي مصمّم لحقول FTTH (FBG/FAT/MAC…) — تُترك فارغة أو يُضاف `conditionVariable` لإخفائها للساس (أو قالب ساس مستقل بنفس المحرّك).

### 5.٤ الواتساب (إثراء وحدة الساس + خطّاف تلقائي)
- إبقاء طبقة الساس (أنظف) مع: **(أ)** إثراء `WaTemplate` والمتغيّرات لتشمل {plan, price, months, endDate, paymentMethod, activatedBy, phone} لمطابقة محتوى FTTH؛ **(ب)** إضافة قالب «تم التفعيل/التجديد» غنيّ؛ **(ج)** تنفيذ `api` sender (Meta/n8n) إن رُغب، وإلا الاكتفاء بـ app/server.
- **خطّاف تلقائي**: بعد نجاح التفعيل (في الواجهة) → طباعة ثم `WaSender.sendOne(...)` (خلفياً، try/catch مستقل)، مشروطاً بصلاحية/إعداد كما FTTH.

---

## 6) تدفّق التفعيل الجديد (مطابق لـ FTTH)

```
[ضغط «تفعيل»/«تجديد»]
   → جلب activationData (السعر + رصيد الوكيل + VAT) عبر sasGet          (كـ calculate-price في FTTH)
   → حوار تأكيد: الباقة/المدة/السعر/رصيد الوكيل/طريقة التحصيل(نقد|أجل|وكيل)  (كـ FTTH)
   → فحص كفاية الرصيد + منع تكرار (transaction_id)
   → POST activate-billed  →  [خادم] SAS4 activate → عند النجاح: SubscriptionLog(Source=sas)+قيد مزدوج
   → reload (تاريخ انتهاء جديد)
   → حوار نجاح
   → خلفياً: طباعة إيصال → رسالة واتساب → (+ سجل محلي sas_transactions)
```

---

## 7) المراحل والترتيب

| م | المرحلة | المخرج | يعتمد على |
|---|---|---|---|
| 1 | توحيد helper المحاسبة + `Source` + migration | محاسبة قابلة لإعادة الاستخدام بلا ازدواج | — |
| 2 | نقطة `activate-billed` + جلب activationData + ختم القيد | محاسبة + تخزين الساس (مشترك واحد) | 1 |
| 3 | واجهة: حوار السعر/التحصيل + استدعاء النقطة الجديدة | تجربة تفعيل مطابقة لـ FTTH | 2 |
| 4 | الطباعة: `_buildSasReceiptVars` + استدعاء `ThermalPrinterService` | إيصال حراري | 3 |
| 5 | الواتساب: إثراء القوالب + خطّاف تلقائي | رسالة تأكيد | 3 |
| 6 | التجديد الجماعي: نفس الخط للناجحين + جدول `sas_transactions` | مطابقة كاملة + سجل محلي | 2 |
| 7 | اختبارات (محاسبة/عزل/idempotency) + تقارير الساس المالية | جودة + رؤية | كل ما سبق |

---

## 8) القرارات (محسومة — أكتوبر 2026)
1. **دفتر المحاسبة**: ✅ **موحّد مع FTTH** (`Source=sas` على `SubscriptionLog`، نفس شجرة الحسابات/القيد).
2. **نموذج التحصيل**: ✅ **مطابق لـ FTTH** (نقد/أجل/وكيل + أجور صيانة + خصم يدوي).
3. **الطباعة/الواتساب التلقائيان**: ✅ **لكل العمليات** (تفعيل + تمديد + تغيير باقة + التجديد الجماعي).
4. **الواتساب**: ✅ **إثراء طبقة الساس** (قوالب أغنى + خطّاف تلقائي؛ `api` اختياري).
5. **قالب الإيصال**: إعادة استخدام محرّك FTTH مع إخفاء حقول الشبكة غير المعنيّة (قالب ساس بنفس المحرّك).

> تنفيذ: لتفادي انحدار FTTH، نُنشئ `SubscriptionAccountingService` مشتركاً (منقول من منطق `FtthAccountingController` الأدق) ونربط الساس به **دون تعديل نقاط FTTH القائمة**؛ توحيد FTTH عليه لاحقاً (دَين مؤجّل).

---

## 9) المخاطر والعزل
- **العزل**: كل محاسبة تُختم خادمياً بـ `account.CompanyId/OwnerUserId` (لا من العميل) — نفس نمط `SubmitReport`.
- **idempotency**: `transaction_id`/`SessionId` يمنع تفعيلاً/قيداً مزدوجاً (كـ FTTH؛ ملاحظة أمان: لا إعادة محاولة تلقائية على 401/403 لنداء التنفيذ).
- **التمديد بلا سعر**: `extensionData` لا يعيد سعراً → استخدم `activationData`/سعر الباقة.
- **السحب/الفشل**: فشل القيد لا يُسقط السجل (try/catch)؛ توفير `repair`/حذف عكسي كـ FTTH.
- **الإنتاج**: كل التغييرات (migration/نقاط) إضافية؛ لا تُطبَّق على الإنتاج إلا بموافقة صريحة.
