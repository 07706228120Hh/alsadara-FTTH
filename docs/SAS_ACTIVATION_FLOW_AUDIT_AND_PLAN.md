# تدقيق تدفّق «تفعيل اشتراك SAS» + خطة التطوير والتحسين

> تاريخ التدقيق: 2026-10-04 · الفرع: `feature/sas-agent-integration`
> النطاق: وحدة SAS داخل منصّة الصدارة (واجهة Flutter + بوّابة .NET + خدمة Python + SAS4).
> الحالة: **تدقيق + خطة — لم يُنفَّذ أي تعديل كود بعد (بانتظار الموافقة).**

---

## 1) خريطة التدفّق الحالي (كما هو فعلاً)

```
[المستخدم يضغط «تفعيل»]  sas_subscriber_detail_page.dart:736 _doActivate()
        │
        ▼
النافذة 1: «تفعيل الاشتراك» (عدد الأشهر)        _askMonths → _InputDialog<int>  (1488–1545)
        │  متابعة
        ▼
جلب بيانات التسعير (معزول)                      _api.sasGet('user/activationData/{uid}')  (839)
        │
        ▼
النافذة 2: «تأكيد التحصيل — تم تفعيل اشتراك»     _showCollectionDialog()  (1157–1330)
   (نوع التحصيل + أجور صيانة + خصم يدوي + رصيد الوكيل)
        │  تأكيد وتحصيل
        ▼
التفعيل الفعلي (طلب واحد موحّد)                  _api.activateBilled()  (878–891)
   └─ POST /api/sas-agent/accounts/{id}/users/{uid}/activate-billed
      └─ .NET: SasAgentController.ActivateBilled()  (1863)
         ├─ SAS4: POST user/activate (عبر خدمة Python 127.0.0.1:8100)
         ├─ PostgreSQL (Hostinger): SubscriptionLogs + JournalEntries (قيد مزدوج)
         │                          + SasCitizenPayment (إن آجل) + SasSubscriberProfile
        │
        ▼
الطباعة + واتساب (معزول، بعد النجاح)             SasBillingPostActions.run()  (903)
   ├─ ThermalPrinterService.printFromReceiptTemplate()  →  Printing.layoutPdf()  (thermal:1661)  ⟵ حوار ويندوز (حجب)
   └─ _sendWhatsApp()  (billing_post_actions:173)  ⟵ صامت، بلا تغذية راجعة
```

**ملاحظة مهمة:** العنوان «تأكيد التحصيل — **تم تفعيل اشتراك**» مُضلِّل؛ التفعيل الفعلي يحدث **بعد** هذه النافذة (السطر 878)، لا قبلها. `operationType='تم تفعيل اشتراك'` مجرّد تسمية.

---

## 2) إجابات مباشرة على أسئلة المالك

### أ) أين تُحفظ البيانات؟ محليًا على الجهاز، أم هوستنكر، أم الاثنان؟
ثلاث جهات تخزين — **ولا شيء دائم يُحفظ على جهاز ويندوز نفسه**:

| الجهة | ماذا يُحفظ | المكان الفعلي |
|------|-----------|---------------|
| **SAS4 (خارجي، ليس ملكنا)** | حالة الاشتراك الحقيقية (التفعيل/التمديد) — مصدر الحقيقة | خادم المزوّد |
| **PostgreSQL الصدارة (هوستنكر/VPS `72.61.183.61`)** ✅ | **القيد المالي والمحاسبي**: `SubscriptionLogs`(Source=Sas) + `JournalEntries` (قيد مزدوج) + `SasCitizenPayment` + `SasSubscriberProfile` + `SasPackagePrice` | قاعدة `sadara_db` على هوستنكر |
| **SQLite خدمة Python (`service/data/sas.db`)** | **مرآة قراءة فقط**: مشتركون مزامَنون + تصاريح وكلاء + عقارات + تذاكر. **لا تُسجَّل عملية التفعيل/التحصيل المالية هنا** | ملف محلي على خادم الخدمة (ليس جهاز الوكيل) |
| **جهاز ويندوز (التطبيق)** | SharedPreferences فقط: عدّاد الإيصال + قوالب الطباعة + إعدادات واتساب. **لا سجل عمليات** | الجهاز |

**الخلاصة:** العملية تُنفَّذ على SAS4 وتُسجَّل محاسبيًا على **هوستنكر (قاعدة الصدارة)**. الجهاز لا يحتفظ بأي سجل للعملية، وخدمة Python SQLite لا تسجّل الجانب المالي. لا توجد نسخة محلية على جهاز الوكيل تحميه إن سقط الاتصال.

### ب) هل يُرسَل الواتساب؟ وهل تظهر حالته؟
- **لا توجد أي تغذية راجعة** عن الإرسال (نجاح/فشل/تخطّي).
- الوضع الافتراضي `WaMode.app` (يدوي) ⇒ **لا يُرسل شيئًا تلقائيًا** — يخرج صامتًا (`capabilities.automated=false`).
- حتى في وضع `server` (127.0.0.1:3100)، نتيجة `WaSendResult` (نجاح/فشل) **تُبتلع** ولا تُعرض.
- الباكند يملك علَم `SubscriptionLog.IsWhatsAppSent` لكنه **لا يُحدَّث أبدًا** (لا إرسال من الخادم).
- النتيجة: المستخدم لا يعرف إطلاقًا هل وصلت الرسالة.

### ج) لماذا يتوقّف النظام ويأخذ وقتًا قبل الطباعة؟
- `Printing.layoutPdf()` في [thermal_printer_service.dart:1661](src/Apps/CompanyDesktop/alsadara-ftth/lib/services/thermal_printer_service.dart#L1661) يفتح **حوار الطباعة الأصلي في ويندوز** بشكل متزامن (حجب). هذا بالضبط ما يظهر كـ «Waiting for printer connection…» ثم «Print Setup».
- لا يوجد timeout، ولا طباعة صامتة، ولا رسالة «جارٍ الطباعة».
- طابعة Brother تعرض «Error; 1 documents waiting» ⇒ يفاقم التأخير.
- **الحل موجود أصلًا في نفس الملف**: `Printing.directPrintPdf(printer: defaultPrinter)` + `Printing.listPrinters()` (مستخدمة في التشخيص عند 1094/1168) تطبع **صامتًا** على طابعة محفوظة دون حوار.

---

## 3) المشاكل المرصودة (مرتّبة حسب الأثر)

| # | المشكلة | الموقع | الأثر |
|---|---------|--------|------|
| P1 | حوار طباعة ويندوز حاجب بدل الطباعة الصامتة | thermal:1661 | توقّف/تأخير + تجربة سيئة |
| P2 | لا تغذية راجعة لإرسال واتساب (fire-and-forget + نتيجة مبتلَعة) | billing_post_actions:173–221 | المستخدم لا يعرف هل أُرسل |
| P3 | نافذتان منفصلتان لعملية واحدة + عنوان مضلِّل | detail_page:738 ثم 1157 | احتكاك + لبس |
| P4 | معلومات ناقصة في نافذة التأكيد (لا ربح/تاريخ انتهاء جديد/صافي بوضوح) | _showCollectionDialog | قرار ناقص |
| P5 | لا سجل محلي على الجهاز للعملية (لا offline/retry لو سقط النت أثناء التفعيل) | — | خطر فقدان/ازدواج |
| P6 | `IsWhatsAppSent` لا يُحدَّث؛ لا مصدر حقيقة لحالة الإرسال | SubscriptionLog | لا تقارير إرسال |
| P7 | لا «جارٍ المعالجة» أثناء `activateBilled` (قد يبدو معلّقًا) | detail_page:875 | لبس |

---

## 4) خطة التطوير — مراحل متسلسلة بإسناد الوكلاء

> كل مرحلة تمرّ على `code-reviewer-agent` + `testing-qa-agent`، والأمني/المحاسبي عند الحاجة، حسب قواعد CLAUDE.md. البدء من `project-manager`.

### المرحلة 0 — تثبيت الأساس (تشخيص موثّق) ✅ (هذه الوثيقة)
- **knowledge-manager-agent**: تثبيت النتائج (منجز هنا).

### المرحلة 1 — الطباعة الصامتة + تغذية راجعة (أعلى أولوية، أثر فوري)
- **المالك: sas-flutter-ui-agent** (بالتنسيق مع mobile-agent لخدمة الطباعة المشتركة).
- استبدال مسار الإيصال من `layoutPdf` إلى `directPrintPdf` على طابعة محفوظة (إعداد «الطابعة الافتراضية للإيصالات» في printer_settings_page).
- Fallback: إن لا طابعة محفوظة/متاحة ⇒ إظهار اختيار مرة واحدة ثم حفظها، لا حوار كل مرة.
- إضافة مؤشر «جارٍ الطباعة…» + نتيجة واضحة (طُبع/فشل + سبب)، مع timeout.
- **مراجعة:** code-reviewer-agent، testing-qa-agent.

### المرحلة 2 — دمج النافذتين في نافذة واحدة غنية
- **المالك: sas-flutter-ui-agent** (+ app-design-specialist للمواصفة البصرية RTL).
- نافذة واحدة: عدد الأشهر + (الباقة، السعر، VAT، صافي من الشركة، الربح، تاريخ الانتهاء الجديد، رصيد الوكيل) + نوع التحصيل + أجور صيانة + خصم يدوي.
- زر واحد «تفعيل وتحصيل». إزالة العنوان المضلِّل. حالة «جارٍ التفعيل…» أثناء الطلب.
- لا تغيير في عقد `activateBilled` (نفس البارامترات) ⇒ لا لمس للباكند في هذه المرحلة.
- **مراجعة:** ui-ux-agent، code-reviewer-agent، testing-qa-agent.

### المرحلة 3 — حالة واتساب حقيقية + تغذية راجعة
- **المالك: sas-flutter-ui-agent + sas-flutter-apiclient-agent** (واجهة)، **sas-backend-agent + backend-agent** (مصدر الحقيقة).
- عرض حالة الإرسال في نافذة النتيجة: (أُرسل / فشل + سبب / الوضع يدوي — افتح واتساب / غير مُهيّأ).
- عدم ابتلاع `WaSendResult`؛ تمريرها للعرض.
- تحديث `SubscriptionLog.IsWhatsAppSent` (عبر نقطة نهاية `/api/sas-agent/.../whatsapp-status` أو ضمن رد التفعيل) ليصبح مصدر حقيقة قابلًا للتقرير.
- **موافقة/مراجعة:** security-auditor-agent (نقطة نهاية جديدة)، database-postgres-agent (إن تغيّر حقل)، code-reviewer-agent، testing-qa-agent.

### المرحلة 4 — متانة العملية (offline/idempotency/سجل محلي) — اختياري لاحق
- **المالك: sas-backend-agent + sas-database-agent + backend-agent.**
- سجل عملية محلي خفيف (device) + إعادة محاولة آمنة بالاعتماد على `transactionId` (idempotency موجود أصلًا في الباكند 1987–1990).
- **موافقة:** architecture-evolution-agent + database-postgres-agent (قواعد الصدارة الذهبية: أي تغيير بيانات/عزل يحتاج موافقة بشرية).

---

## 5) مراجع الكود (نقاط الدخول)

| الطبقة | ملف:سطر |
|--------|---------|
| واجهة — دخول التفعيل | sas_subscriber_detail_page.dart:736 `_doActivate` |
| واجهة — نافذة الأشهر | sas_subscriber_detail_page.dart:1488 `_InputDialog` |
| واجهة — نافذة التحصيل | sas_subscriber_detail_page.dart:1157 `_showCollectionDialog` |
| واجهة — التفعيل الفعلي | sas_subscriber_detail_page.dart:878 `activateBilled` |
| واجهة — طباعة+واتساب | sas_billing_post_actions.dart:65 `run`، :173 `_sendWhatsApp` |
| واجهة — الطباعة الحاجبة | thermal_printer_service.dart:1661 `layoutPdf` |
| واجهة — الطباعة الصامتة (متاحة) | thermal_printer_service.dart:1094 `listPrinters`، :1168 `directPrintPdf` |
| بوّابة — التفعيل المفوتر | SasAgentController.cs:1863 `ActivateBilled` |
| بوّابة — عميل Python | SasServiceClient.cs (127.0.0.1:8100 + X-Internal-Secret) |
| بوّابة — المحاسبة | SubscriptionAccountingService.cs:144–177 |
| خدمة Python — تفعيل SAS4 | service/app.py:734 `/users/action` → sas_client `user/activate` |
| خدمة Python — تخزين محلي | service/app.py:90 `_init_db` (SQLite؛ لا جانب مالي) |
