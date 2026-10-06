# الساز: إسناد العمليات/الذمم (البند 2) + دراسة ربط نظام المهام (البند 3)

> تاريخ: 2026-10-06 · تدقيق + خطة. (إصلاح ×1000 للباكند **منشور**؛ هذه الوثيقة للبندين التاليين.)

---

## البند 2 — أعمدة الإسناد (مَن فعّل / على مَن الذمّة / الفني) مثل FTTH

### الحقائق (كل البنية موجودة — لا migration لازم)
`SubscriptionLog` يملك أصلاً: `ActivatedBy`(مَن فعّل) · `UserId` · `CollectionType` · `LinkedAgentId` · **`LinkedTechnicianId`** · `TechnicianName` · `JournalEntryId`.
المحرّك المشترك `SubscriptionAccountingService.RecordAsync` **يعالج كل الأنواع** cash/credit/master/**agent**/**technician**/**citizen** (سطر 207–310): «technician» → مدين `1140` (TechnicianReceivables) + `TechnicianTransaction`(Charge/Subscription) + تحديث `User.TechNetBalance`. `TechnicianTransaction` + حقول الفني في `User` موجودة.

### الفجوة في الساز
- التفعيل في `ActivateBilledCore` يملأ `UserId` فقط؛ **لا يملأ `ActivatedBy`** (اسم المشغّل) ولا يدعم «technician».
- أنواع تحصيل الساز في الواجهة: cash/credit/agent/citizen — **بلا «فني»**، وبلا **منتقي** للوكيل/الفني (LinkedAgentId/LinkedTechnicianId لا يُجمعان من الواجهة).
- شاشة حركات الساز لا تعرض أعمدة الإسناد.

### خطة البند 2
**الباكند (SasAgentController):**
1. أضِف `LinkedTechnicianId` إلى `ActivateBilledRequest` DTO (بجانب `LinkedAgentId`).
2. تحقّق: `collectionType=="technician"` ⇒ `LinkedTechnicianId` مطلوب (كـ agent).
3. في `ActivateBilledCore`: املأ `log.ActivatedBy`(اسم المشغّل من User) · `log.LinkedTechnicianId` · `log.TechnicianName`(من User) · ومرّر `LinkedTechnicianId` لمدخل `RecordAsync`.
4. نقطة لجلب الفنيّين للمنتقي: إعادة استخدام منطق `GET /api/service-requests/task-staff` عبر نقطة سaz-agent معزولة `GET accounts/{id}/technicians` (موظفو الشركة بدور فني/قائد).
5. (اختياري) منتقي الوكيل أيضاً (الوكلاء موجودون في agents-list) لإكمال «agent».

**Flutter (sas_subscriber_detail_page + transactions):**
1. أضِف شريحة «فني» + منتقي الفني (وربما الوكيل) في حوار التحصيل الموحّد ⇒ يُرجَع ضمن `_SasCollection`.
2. مرّر `linkedTechnicianId` في `activateBilled`.
3. شاشة حركات الساز (`sas_transactions_page`): أعمدة **المُنفِّذ (ActivatedBy)** · **نوع التحصيل** · **على مَن (الوكيل/المواطن/الفني باسمه)**.

**لا migration.** يحتاج: نشر باكند + إصدار تطبيق (ضمن v2.4.1 مع ×1000 UI).

---

## البند 3 — دراسة ربط الساز بنظام المهام (توجيه صيانة/ديلفري/تفعيل لفني)

### نظام المهام الحالي (FTTH)
- **الكيان:** `ServiceRequest` (`ServiceAndPermission.cs:256`) — `RequestNumber` · `ServiceId`(9=FTTH) · `OperationTypeId` · `CitizenId`/`AgentId`/`CompanyId` · **`TechnicianId`/`AssignedToId`** · `Department` · `TechnicianName` · `Status`(Pending→Assigned→InProgress→Completed) · `Priority` · `Details`(JSON مرن) · العنوان/الهاتف/التكلفة.
- **الإنشاء:** `POST /api/service-requests/create-task` (`ServiceRequestsController:1600`) — DTO يحوي taskType/department/technician/customer/FBG/FAT/priority/مبلغ.
- **التوجيه التلقائي:** يُطابَق الفني بالاسم (`FullName`) ⇒ `TechnicianId`+`AssignedToId`+`Status=Assigned`+إشعار (FCM) + SignalR (`TaskHub`). نقطة ثانية `PATCH .../assign-task`.
- **جلب الفنيّين:** `GET /api/service-requests/task-staff` (موظفون نشطون غير مواطنين، مع تمييز القادة).
- **أنواع المهام:** `DepartmentTask` لكل قسم (صيانة: تركيب/إصلاح/صيانة/فحص/طوارئ؛ حسابات: شراء/تجديد اشتراك…).
- **الحالة الراهنة:** تفعيل FTTH **لا يُنشئ مهمة تلقائياً** (تُنشأ يدوياً غالباً).

### آلية الربط المقترحة للساز
عند الحاجة (تفعيل/تجديد مشترك ساز، أو طلب صيانة/ديلفري لمشترك ساز)، تُنشئ وحدة الساز **`ServiceRequest`** بإعادة استخدام نفس النظام:
- دالة helper في `SasAgentController`: `CreateTaskForSasSubscriberAsync(...)`.
- `Details` JSON يحمل: `source:"sas"` · `sasAccountId` · `sasSubscriberUid`/الاسم/الهاتف (من `SasSubscriberProfile`) · المنطقة/الإحداثيات (من `SasRegion`/الملف) · taskType(تفعيل/تجديد/صيانة/ديلفري ساز) · المبلغ.
- القسم: تفعيل/تجديد→«الحسابات»؛ صيانة/فحص→«الصيانة».
- اختيار الفني: من موظفي **نفس الشركة** (عزل بـ`SasAccount.CompanyId`) بدور فني/قسم مطابق، مع موازنة حمل (أقل مهام نشطة)، وإلا يبقى `Pending` أو يُسنَد لقائد القسم.
- ربط المحاسبة: عند الإكمال تُستخدم نفس آلية `TechnicianTransaction` (البند 2) ويُربط بـ`SubscriptionLog(Source=Sas)`.

### العقبات والحلول
| العقبة | الحل |
|-------|------|
| الساز بلا `CitizenId` | `OperationTypeId`/`ServiceId` جديد للساز + `CitizenId=null` + تعريف المشترك عبر `Details`/`SubscriberUid` |
| العزل بين الشركات | ختم `CompanyId` من `SasAccount` على المهمة + فلترة الفنيّين بالشركة |
| لا فني متاح | إسناد لقائد القسم (Manager/TechnicalLeader) أو إبقاء Pending |
| تمييز مهام الساز في الواجهة | علَم `source:"sas"` في Details + فلتر/شارة في شاشة المهام |
| إشعارات/تدقيق | إعادة استخدام `TaskHub` + FCM + `TaskAudit` |

### خطة البند 3 (مراحل)
- **م1:** تعريف `ServiceId`/`OperationType` للساز + دالة `CreateTaskForSasSubscriberAsync`.
- **م2:** زرّ/تدفّق في واجهة الساز: «توجيه صيانة/ديلفري/تفعيل لفني» من تفاصيل المشترك (يستدعي إنشاء المهمة).
- **م3:** إظهار مهام الساز في شاشة المهام (شارة المصدر) ورؤية الفني لها.
- **م4:** ربط إكمال المهمة بمحاسبة الفني (البند 2).

> موافقات: البند 2 مالي (تحصيل الفني) ⇒ مراجعة محاسبية/أمنية. البند 3 يمسّ workflow + عزل ⇒ architecture + security. كلاهما يحتاج نشر باكند + إصدار تطبيق.
