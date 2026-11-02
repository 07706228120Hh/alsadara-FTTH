# ADR + خطة تنفيذ — ربط نظام المهام بـ«حساب مصدر» و«منطقة»

- **المعرّف**: ADR-2026-11-02-tasks-source-account-region
- **الحالة**: Proposed (بانتظار اعتماد project-manager + موافقة المالك على بوّابات الموافقة)
- **المؤلّف**: architecture-evolution-agent
- **التاريخ**: 2026-11-02
- **الفرع المرجعي للحقائق**: `release/v2.4.32` (v2.4.32+347)
- **النطاق**: نواة الصدارة فقط (ServiceRequest + FtthAccount/SasAccount + استهلاك `GET /api/sas-agent/regions` الموجود). **لا يمسّ** وحدة الساس المعزولة (`modules/sas-agent/**` ولا `lib/sas_agent/**`).

> هذه **وثيقة تصميم فقط** (مهمة تنظيمية). لا تُنشئ migration ولا تعدّل كوداً بناءً عليها قبل اعتماد project-manager وتوزيع العمل على وكلاء التنفيذ. كل اقتراحات المخطط/الهجرة/الـ endpoint هنا **مقترحات**.

---

## 1. الخلفية والهدف

نظام المهام الحالي (كيان `ServiceRequest`) يصف عملاً ميدانياً (صيانة/اشتراك/فحص) ويحمل مُسنَداً إليه وقسماً وحقلي `City`/`Area` نصّيين حرّين. لكنه **غير مربوط** بالحسابات المتعددة للشركة (`FtthAccount`/`SasAccount`) ولا بنظام مناطق الساس (`SasRegion`). النتيجة: لا يمكن معرفة «من أي حساب مصدر» نشأت المهمة، ولا ربطها بمنطقة جغرافية مُدارة لأغراض التقارير والتجميع لاحقاً.

**الهدف**: وسم كل مهمة (يدوياً) بـ«حساب مصدر» (FTTH أو ساس) و«منطقة»، مع احترام صارم لعزل المستأجر، وبأقل أثر ممكن على المخطط والـ API الحاليين، وبمسار مرحلي يؤجّل تعقيد زونات FTTH الحيّة.

### القرارات الستة المثبّتة (قرارات المالك)
1. **وسم يدوي فقط** — لا توليد تلقائي للمهام في هذه المرحلة.
2. مصدر الحسابات = **مجمّع حسابات الشركة كاملاً** (كل FTTH والساس داخل الشركة، لكل الموظفين) — لا حسابات الموظف الحالي فقط.
3. **المدير/الليدر** يختار الحساب ثم يُسند لموظف — نفس مسار الإنشاء الحالي + حقول جديدة.
4. **عمود حساب واحد** لكل مهمة — لا جدول ربط متعدد.
5. «الحساب» في FTTH = **الحساب المربوط + الشريك الرئيسي معاً** (نخزّن مرجع `FtthAccount` + اسم/معرّف الشريك مثل «مكتب 11»/«مدينة الصدر»). للساس = حساب الساس نفسه.
6. **المسار (أ) المرحلي** للمنطقة: الساس بربط كامل الآن (`SasRegion`)؛ FTTH حتى مستوى الشريك الآن + المنطقة يدوية/نصّية مؤقتاً، مع تأجيل زونات FTTH الحيّة لمرحلة لاحقة.

---

## 2. الحقائق المؤكَّدة من الشيفرة (أساس البناء)

تحقّقتُ من المسارات التالية على `release/v2.4.32`:

| الحقيقة | الموقع المؤكَّد |
|---------|----------------|
| كيان `ServiceRequest` (BaseEntity<Guid>) — يحمل `CompanyId Guid?`، `City`/`Area` نصّيان حرّان (nullable)، أعمدة مطبّعة `Department`/`TechnicianName`، تفاصيل مرنة `Details` (JSON) | `src/Backend/Core/Sadara.Domain/Entities/ServiceAndPermission.cs:256` (الحقول 279، 302–315، 299–300) |
| إنشاء المهمة `[HttpPost("create-task")]` — يختم `CompanyId = ResolveWriteCompanyId(null)` **صراحةً من التوكن** (مستقل عن العلَم المركزي)، ويكتب Details JSON + العمودين المطبّعين (dual-write) | `ServiceRequestsController.cs:1694`, الختم `:1807`, dual-write `:1810-1811` |
| تعديل المهمة — DTOها `UpdateTaskDto` (`:2923`)، وإنشاؤها `CreateTaskDto` (`:2860`)؛ لا حقول حساب/منطقة فيهما حالياً | نفس الملف |
| `FtthAccount` — `ITenantScoped` بـ `CompanyId` + `OwnerUserId`، `PasswordEncrypted` **لا يُعاد أبداً** | `src/Backend/Core/Sadara.Domain/Entities/FtthAccount.cs:12` |
| `SasAccount` — `ITenantScoped` بـ `CompanyId` + `OwnerUserId`، `PasswordEncrypted` لا يُعاد (استثناء reveal المعتمد فقط) | `src/Backend/Core/Sadara.Domain/Entities/SasAccount.cs:11` |
| `SasRegion` — `ITenantScoped` بـ `CompanyId`، فريد (CompanyId+Name)، المشترك يرتبط عبر `SasSubscriberProfile.RegionId` | `src/Backend/Core/Sadara.Domain/Entities/SasRegion.cs:11` |
| **مناطق الساس جاهزة**: `GET /api/sas-agent/regions` يُرجع مناطق الشركة (معزولة بـ CompanyId من التوكن) بصلاحية `sas_agent/view` failClosed | `SasAgentController.cs:785` |
| قائمة الحسابات الحالية `GET /api/linked-accounts` — تُرجع حسابات **موظف واحد فقط** (`OwnerUserId == targetUserId`)، لا مجمّع شركة | `LinkedAccountsController.cs:263-310` |
| الأدمن يصل لحسابات شركته عبر `IsCompanyAdminOrAbove()` (العزل بـ CompanyId من التوكن) | `LinkedAccountsController.cs:212-237` |

**القيد الحاسم للمسار (أ)**: لا يوجد على `release/v2.4.32` أي ربط مُخزَّن بين `FtthAccount` والشريك الرئيسي، ولا جلب حيّ للزونات. الشركاء يُحمَلون كـ `PartnerName`/`PartnerId` على `SubscriptionLog` وسجلّات `FtthAccountingController` فقط (`PartnerId` = معرّف عضو FTTH). قائمة الشركاء/الزونات الحيّة موجودة على فرع `feature/ftth-credentials-unification` **غير المدموج** (محجوز لترخيص `linked_accounts`). لذا الربط الحيّ للزونات مؤجَّل للمرحلة 2.

---

## 3. نموذج البيانات (مقترح)

### 3.1 الأعمدة الجديدة على `ServiceRequest`

تُضاف سبعة أعمدة **كلها nullable** (توافق خلفي كامل مع المهام القائمة)، في `ServiceAndPermission.cs`:

| العمود | النوع المقترح | الدلالة |
|--------|---------------|---------|
| `SourceAccountType` | enum `TaskSourceAccountType` (`None=0, Ftth=1, Sas=2`) | نوع الحساب المصدر؛ افتراضي `None` للمهام بلا وسم |
| `SourceAccountId` | `Guid?` | مرجع إلى `FtthAccount.Id` أو `SasAccount.Id` حسب النوع |
| `SourceAccountLabel` | `string?` | لقطة (snapshot) لاسم/تسمية الحساب وقت الوسم (عرض مستقر حتى لو تغيّر الحساب لاحقاً) |
| `PartnerId` | `string?` | معرّف عضو FTTH للشريك الرئيسي (لـ FTTH فقط)؛ نصّي لأنه معرّف FTTH لا GUID |
| `PartnerName` | `string?` | اسم الشريك («مكتب 11»/«مدينة الصدر») — لقطة للعرض |
| `RegionRef` | `string?` | مرجع المنطقة: يحتوي **Guid منطقة الساس كنص** (المسار الكامل)، أو لاحقاً ZoneId زون FTTH النصّي، أو منطقة نصّية يدوية حرّة في المرحلة 1 لـ FTTH |
| `RegionName` | `string?` | اسم المنطقة المعروض (لقطة) |

**ملاحظة enum**: يُعرَّف `TaskSourceAccountType` في `Sadara.Domain/Enums` (نفس مكان بقية enums المجال). النوع المخزَّن في القاعدة = `int`.

### 3.2 الفهارس المقترحة
- فهرس على `(CompanyId, SourceAccountType, SourceAccountId)` — لفلترة المهام حسب الحساب ضمن الشركة بكفاءة.
- فهرس على `(CompanyId, RegionRef)` — لتجميع/تصفية المهام حسب المنطقة.
- (اختياري) فهرس على `(CompanyId, PartnerId)` إن احتاجت تقارير الشريك ذلك لاحقاً — يُؤجَّل حتى يثبت نمط الاستعلام.

### 3.3 البدائل المدروسة والمقايضات

| البديل | القرار | السبب |
|--------|--------|-------|
| **جدول ربط many-to-many** (TaskSourceAccounts) | **مرفوض** | قرار المالك #4 = حساب واحد لكل مهمة؛ الجدول يضيف تعقيد JOIN وصيانة بلا حاجة فعلية. الترقية لاحقاً ممكنة بإضافة جدول دون كسر العمود الواحد. |
| **`RegionId Guid?`** (مفتاح أجنبي لـ `SasRegion`) | **مرفوض كحقل وحيد** | زون FTTH معرّفه **نصّي** (ZoneId من FTTH) لا GUID؛ ومنطقة المرحلة 1 لـ FTTH **يدوية نصّية**. حقل Guid وحيد لا يستوعب الحالتين. |
| **`RegionRef string?`** (نصّي عام) + `RegionName` | **معتمد** | يستوعب: Guid الساس (كنص)، ZoneId FTTH (مرحلة 2)، والنص اليدوي (مرحلة 1 FTTH). التحقّق من ملكية منطقة الساس يتم بتحويل النص إلى Guid والتأكد أنها ضمن الشركة. **المقايضة**: فقدان قيد المفتاح الأجنبي على مستوى القاعدة ⇒ يُعوَّض بتحقّق صريح في الـ Controller (انظر §5). |
| **تخزين المرجع فقط بلا snapshot (بلا Label/PartnerName/RegionName)** | **مرفوض** | المهمة سجلّ تاريخي؛ تغيير/حذف الحساب أو المنطقة لاحقاً يجب ألا يُفسد عرض المهمة القديمة. اللقطات تحفظ وضوح التقارير. |
| **إعادة استخدام `City`/`Area` الحرّين للمنطقة** | **مرفوض** | حقلان دلالتهما «عنوان العميل» لا «منطقة مُدارة»؛ خلطهما يفسد التقارير. نبقيهما كما هما. |

### 3.4 الهجرة (مقترح فقط — لا تُنشأ الآن)
- **الاسم المقترح**: `AddServiceRequestSourceAccountRegion`.
- **المشروع**: `src/Backend/Core/Sadara.Infrastructure` (startup: `src/Backend/API/Sadara.API`).
- **الطبيعة**: إضافة سبعة أعمدة nullable + 2–3 فهارس. **صفر تحويل بيانات** (كل القديم يبقى `None`/NULL). idempotent وآمن rollback (حذف الأعمدة/الفهارس).
- **بوّابة موافقة**: إنشاء/تشغيل الهجرة = تغيير مخطط ⇒ **يمرّ على database-postgres-agent + موافقة بشرية صريحة** (قاعدة الصدارة الذهبية #10/#15). لا يُنشأ ملف الهجرة ضمن هذه الوثيقة.

---

## 4. الباكند (مقترح)

### 4.1 endpoint مجمّع الحسابات على مستوى الشركة
الحاجة: القرار #2 يتطلب **كل** حسابات الشركة؛ `GET /api/linked-accounts` الحالي يُرجع موظفاً واحداً فقط. لا نوسّع ذلك الـ endpoint (دلالته «حسابات موظف»)، بل نضيف endpoint مخصّص للمهام.

**المقترح**: `GET /api/tasks/source-pool` (ضمن `ServiceRequestsController` أو controller مهام مخصّص).

- **الصلاحية**: تُحسم مع security-auditor-agent. مرشّح أوّلي: صلاحية إنشاء/تعديل المهام الحالية (نفس حارس `create-task`) لأن المُستهلِك هو مدير/ليدر ينشئ المهمة؛ **بشرط** ألا يكشف المجمّع أي كلمة مرور. (بديل: صلاحية `linked_accounts/view` — لكنها دلالياً «إدارة حسابات» لا «قائمة اختيار للمهمة»؛ القرار النهائي لـ security + project-manager.)
- **العزل**: `CompanyId` **من التوكن** حصراً (عبر `_tenant.CompanyId` / `ResolveWriteCompanyId`)؛ تجاهل أي `companyId` من العميل.
- **ما يُرجِعه** (بلا أي سرّ):
  - `ftthAccounts[]`: `{ id, label, username, serverUrl, ownerName }` — من `_db.FtthAccounts.Where(CompanyId == tokenCompany && !IsDeleted)`. **بلا `PasswordEncrypted`**.
  - `sasAccounts[]`: `{ id, label, username, serverUrl, accountType, ownerName }` — من `_db.SasAccounts` بنفس العزل. **بلا `PasswordEncrypted`**.
  - `partners[]`: `{ partnerId, partnerName }` DISTINCT من سجلّات المحاسبة (`SubscriptionLog`/مصدر `FtthAccountingController`) **المعزولة بـ CompanyId**. (مرحلة 1 حتى مستوى الشريك.)
  - `sasRegions[]`: يُستهلَك من `GET /api/sas-agent/regions` الموجود (لا نكرّر منطقه) — أو يُعاد تجميعه هنا من `_db.SasRegions.Where(CompanyId == tokenCompany)` إن فُضّل تقليل نداءات الواجهة. القرار بين الاستهلاك والتجميع المحلي = تفصيل تنفيذ لـ backend-agent بلا أثر معماري.
- **الصيغة**: القياسية `{ success: true, data: { ftthAccounts, sasAccounts, partners, sasRegions } }`؛ الفشل `{ success: false, message: "<عربي>" }` بكود HTTP صحيح.
- **الأداء**: استعلامات `AsNoTracking` + `Select` مُسقَط (projection) لتفادي جلب الأعمدة الحسّاسة أصلاً؛ DISTINCT للشركاء على مستوى القاعدة. متوافق مع مقياس ~2000 شركة (الاستعلام دائماً مُقيَّد بشركة واحدة).

### 4.2 تعديلات إنشاء/تعديل المهمة
- توسيع `CreateTaskDto` (`:2860`) و`UpdateTaskDto` (`:2923`) بحقول: `SourceAccountType`, `SourceAccountId`, `PartnerId`, `PartnerName`, `RegionRef`, `RegionName`. (الـ `Label` تُشتَق خادمياً من الحساب المُتحقَّق لا من العميل — لقطة موثوقة.)
- في `create-task` (`:1800`) و مسار التعديل:
  - **تحقّق ملكية الحساب**: إن `SourceAccountType == Ftth` تأكّد أن `SourceAccountId` موجود في `_db.FtthAccounts` **ضمن شركة التوكن**؛ وإن `Sas` في `_db.SasAccounts` ضمن الشركة. غير ذلك ⇒ 400/404. لا نثق بـ Label من العميل — نقرأه من الصف المُتحقَّق.
  - **تحقّق المنطقة**: إن كانت منطقة ساس (Guid)، تأكّد أن `SasRegion` ضمن الشركة قبل ختم `RegionName`. المنطقة النصّية اليدوية (FTTH مرحلة 1) تُقبل كنص حرّ بعد تنظيف أساسي.
  - **ختم `CompanyId`** يبقى عبر `ResolveWriteCompanyId(null)` كما هو (مستقل عن العلَم).
- كتابة الحقول الجديدة على الأعمدة المطبّعة مباشرةً (ليست ضمن Details JSON) لتماثل نمط `Department`/`TechnicianName` وتتيح الفلترة بكفاءة.

### 4.3 القراءة/الفلترة
- إضافة الحقول السبعة إلى `ServiceRequestResponse`/`ServiceRequestDetailResponse` (الإسقاطات عند `:183`, `:2648`, `:2680`).
- إضافة فلاتر اختيارية في قائمة المهام: حسب `SourceAccountId` / `SourceAccountType` / `RegionRef` — مبنية على الفهارس في §3.2.

---

## 5. الأمن والعزل (نقاط مراجعة security-auditor-agent)

1. **المجمّع على مستوى الشركة**: القرار #2 يوسّع الكشف من «حسابات الموظف» إلى «كل حسابات الشركة». يجب أن يراجع security-auditor-agent:
   - أن الـ endpoint يُعيد **تعريفات فقط** (id/label/username/serverUrl) **بلا أي `PasswordEncrypted`** لأي نوع — يُضمَن ببنية الـ projection لا بالاعتماد على DTO.
   - مستوى الصلاحية المناسب (مدير/ليدر فقط؟ أم أي منشئ مهام؟) وهل يكفي حارس إنشاء المهام.
2. **تحقّق الملكية عند الكتابة**: الحساب/المنطقة المُوسَم بهما **يجب** أن يكونا ضمن `CompanyId` التوكن — لا الثقة بأي معرّف من العميل (منع IDOR عبر الشركات).
3. **فقدان FK على `RegionRef`**: لأن المرجع نصّي، التحقّق يقع على التطبيق لا القاعدة ⇒ يجب تغطيته باختبار عزل صريح (testing-qa).
4. **لا مساس بوحدة الساس**: لا نفكّ تشفير أي اعتماد ساس ولا ننادي خدمة Python؛ نقرأ `SasRegion`/`SasAccount` عبر DbContext النواة فقط (قراءة).
5. **اللقطات (snapshots)** لا تحمل أسراراً (أسماء/تسميات فقط).

> أي تغيير يمسّ صلاحية جديدة أو يوسّع كشف بيانات عبر الشركة = **يمرّ على security-auditor-agent** قبل التنفيذ.

---

## 6. الواجهة (Flutter — alsadara-ftth)

بثيم الصدارة العام (Cairo + `flutter_screenutil` + `lib/theme/app_theme`)، عربي RTL.

- **موديل** `lib/models/task.dart`: إضافة حقول `sourceAccountType`, `sourceAccountId`, `sourceAccountLabel`, `partnerId`, `partnerName`, `regionRef`, `regionName` (كلها اختيارية بقيم افتراضية فارغة للتوافق مع `fromJson` القديم).
- **طبقة الاتصال** `lib/services/task_api_service.dart`: دالة `fetchSourcePool()` تنادي `GET /api/tasks/source-pool`، وتمرير الحقول الجديدة في إنشاء/تعديل المهمة.
- **حوار إنشاء المهمة**: منسدلات متتالية (cascading):
  1. نوع الحساب (FTTH / ساس).
  2. الحساب (من المجمّع، label + username).
  3. إن FTTH: الشريك الرئيسي (من `partners[]`).
  4. المنطقة: إن ساس = منسدلة `sasRegions[]`؛ إن FTTH = حقل نصّي يدوي (مرحلة 1).
- **البطاقة/التفاصيل**: عرض `sourceAccountLabel` + `partnerName` + `regionName` (لقطات) بشكل مدمج يحترم تفضيل الواجهة المدمجة (بلاطات صغيرة، تمرير أقل).
- **الفلتر**: إضافة تصفية حسب الحساب/المنطقة في شاشة قائمة المهام.
- **حدّ الملكية**: كل هذا في `lib/` النواة (ملكية mobile-agent) — **ليس** في `lib/sas_agent/**` (وحدة الساس المعزولة). الاستهلاك عبر بوّابة الصدارة فقط.

---

## 7. خطة التنفيذ المرحلية

### Phase 1 (الآن) — الساس كامل + FTTH حتى الشريك + منطقة نصّية
1. **database-postgres-agent** (بموافقة): migration `AddServiceRequestSourceAccountRegion` (7 أعمدة nullable + فهارس).
2. **backend-agent**: enum `TaskSourceAccountType`، حقول الكيان، `GET /api/tasks/source-pool`، توسيع DTOs + تحقّق الملكية في create/update + الإسقاطات والفلاتر.
3. **security-auditor-agent**: مراجعة كشف المجمّع + تحقّق الملكية + الصلاحية (§5).
4. **mobile-agent**: الموديل + الاتصال + المنسدلات المتتالية + البطاقة/الفلتر (§6).
5. **testing-qa-agent**: اختبار عزل (حساب/منطقة شركة أخرى تُرفض) + اختبار صيغة الاستجابة + عدم تسرّب كلمة المرور.
6. **code-reviewer** ثم **documentation/knowledge-manager**.

**مخرجات Phase 1**: منطقة الساس مربوطة بالكامل (Guid مُتحقَّق)؛ FTTH حتى الشريك + منطقة نصّية يدوية.

### Phase 2 (لاحقاً) — زونات FTTH الحيّة
- نقل endpoint مناطق/زونات الشريك الحيّة من فرع `feature/ftth-credentials-unification` **بعد** مراجعته ودمجه (محجوز حالياً لترخيص `linked_accounts`).
- عندها يصبح `RegionRef` لـ FTTH = ZoneId نصّي من FTTH بدل النص اليدوي، وتتحوّل منسدلة منطقة FTTH من حقل حرّ إلى منسدلة حيّة.
- **درس تشغيلي مثبّت** يجب احترامه: نداء `locations/zones` في FTTH يُحجب 403 مع `pageSize`/`pageNumber` (WAF/Cloudflare) ⇒ نادِه بلا query params، والجلب الحيّ من الخادم لا العميل.
- بما أن `RegionRef` نصّي عام، **لا migration إضافية** مطلوبة للانتقال من المرحلة 1 إلى 2 (ميزة التصميم).

### ما يحتاج موافقة بشرية صريحة
- **تشغيل الهجرة** (تغيير مخطط) — عبر database-postgres-agent + موافقة.
- **أي نشر** على الإنتاج `72.61.183.61`.
- دمج فرع `feature/ftth-credentials-unification` (Phase 2) — مرتبط بترخيص `linked_accounts` وقرار المالك.

---

## 8. المخاطر والـ Unknowns

| البند | النوع | الوصف / التخفيف |
|-------|-------|-----------------|
| فقدان FK على `RegionRef` | مخاطرة | التحقّق على التطبيق لا القاعدة ⇒ خطر صفوف بمرجع يتيم؛ يُغطّى باختبار عزل + تحقّق ملكية صارم عند الكتابة. |
| تضخّم أعمدة `ServiceRequest` | مخاطرة منخفضة | 7 أعمدة nullable؛ أثر مساحي ضئيل، صفر تحويل بيانات. |
| مصدر الشركاء (`partners[]`) | Unknown جزئي | مشتق من `SubscriptionLog`/`FtthAccountingController` (`PartnerId` = معرّف عضو FTTH)؛ **يجب على backend-agent تأكيد الاستعلام الدقيق والـ DISTINCT المعزول بالشركة** قبل التنفيذ. لا جدول شركاء مستقل على `release/v2.4.32`. |
| صلاحية `source-pool` | قرار معلّق | المستوى المناسب (منشئ مهام مقابل `linked_accounts/view`) يحسمه security-auditor + project-manager. |
| توسيع الكشف عبر الشركة | أمني | القرار #2 يكشف كل حسابات الشركة (تعريفات فقط) لمنشئ المهمة؛ يحتاج إقرار security-auditor. |
| تداخل منطقة `SasRegion` مع وحدة الساس | حدّ ملكية | نقرأ `SasRegion` عبر DbContext النواة فقط (كيان نواة ITenantScoped)؛ لا نلمس `modules/sas-agent/**`. مؤكَّد أنها كيان نواة لا وحدة. |
| ملفات الذاكرة قديمة | ملاحظة | `PROJECT_STATE.md` يذكر v2.2.25 بينما الواقع v2.4.32؛ اعتمدتُ الشيفرة الفعلية على `release/v2.4.32` لا الذاكرة. يُستحسن أن يحدّث knowledge-manager الحالة. |

---

## 9. خلاصة القرار المعماري

- **عمود واحد + 7 حقول لقطة/مرجع على `ServiceRequest`** بدل جدول ربط — أبسط وأوفى لقرار المالك #4، قابل للترقية لاحقاً.
- **`RegionRef` نصّي عام** (لا `RegionId Guid`) ليستوعب Guid الساس وZoneId FTTH والنص اليدوي بلا migration ثانية بين المرحلتين — مقابل التنازل عن قيد FK (يُعوَّض بتحقّق تطبيقي + اختبار).
- **endpoint مجمّع جديد `/api/tasks/source-pool`** معزول بـ CompanyId من التوكن يُعيد تعريفات بلا أسرار — لا توسيع لـ `linked-accounts` (دلالة مختلفة).
- **المسار (أ) المرحلي**: الساس بربط كامل الآن؛ FTTH حتى الشريك + منطقة نصّية، وزونات FTTH الحيّة في Phase 2 عبر فرع الاعتماد بعد مراجعته.
