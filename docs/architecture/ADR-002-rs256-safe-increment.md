# ADR-002 — أول زيادة آمنة: قدرة توقيع RS256 + نقطة JWKS خلف feature flag (يبدأ OFF)

- **الحالة (Status)**: مقترَح (Proposed) — تصميم فقط. بانتظار موافقة `project-manager` + المستخدم + مراجعة `security-auditor-agent` قبل بدء أي تنفيذ كود.
- **التاريخ**: 2026-08-02
- **الفرع**: `feature/distributed-identity-rs256`
- **المؤلّف**: architecture-evolution-agent (حارس البنية المعمارية).
- **المُراجِعون المطلوبون قبل التنفيذ**: `security-auditor-agent` (تغيير مصادقة — القاعدة 14، الكلمة النهائية في الأمن)، `project-manager` (توزيع + موافقة)، `backend-agent` (التنفيذ)، `testing-qa-agent` (تكافؤ سلوك OFF)، `devops-agent` (إدارة المفتاح/الإعداد).
- **يبني على**: `docs/architecture/ADR-001-distributed-multi-tenant.md` (المرحلة 1: CILA + RS256)، النموذج المُثبت في `poc/README.md` (بوابة هوية تُصدر RS256 + نقطة JWKS + عقدة تتحقّق ذاتياً — مثبت 2026-08-02).

> **تنويه القواعد الذهبية**: هذه الوثيقة **تصميم فقط**. لم يُعدَّل أي ملف داخل `src/` ولا أي schema. أي تنفيذ لاحق يمرّ عبر `project-manager` ثم `backend-agent` بموافقة صريحة، ويُراجَع أمنياً إلزامياً (القاعدة 14: تغيير المصادقة يمرّ على `security-auditor-agent`). لا نشر، لا push، لا تدوير مفاتيح ضمن هذه المذكّرة.

---

## 0. ملخّص تنفيذي (TL;DR)

نُدخل **قدرة** توقيع RS256 + نقطة JWKS **بجانب** HS256 الحالي، مخفية خلف مفتاح إعداد `Jwt:Algorithm` يبدأ افتراضياً `HS256` (أي **OFF**). عند `HS256` يكون السلوك **مطابقاً 100%** للإنتاج الحالي (نفس التوقيع، نفس التحقّق، لا نقطة JWKS مفعّلة عملياً). التبديل لـ `RS256` قرار تشغيلي لاحق بموافقة أمنية.

- **الخيار المختار**: **Strategy/Factory يُختار بإعداد `Jwt:Algorithm`** (وليس توسيع عقد `IJwtService`).
- **المستدعون الخمسة في `Services.cs` لا يُعدَّلون إطلاقاً** — يبقى عقد `IJwtService` الثلاثي كما هو حرفياً.
- **كل التعديلات إضافية (additive)**: ملفات جديدة + أسطر تسجيل جديدة في `Program.cs`. لا حذف ولا تغيير سلوك عند القيمة الافتراضية.

---

## 1. المشكلة: كيف نُدخل RS256 دون كسر عقد `IJwtService`؟

### 1.1 العقد الحالي (المصدر: `Sadara.Domain/Interfaces/Interfaces.cs:195-200`)

```csharp
public interface IJwtService
{
    string GenerateAccessToken(User user);
    string GenerateRefreshToken();
    bool ValidateToken(string token);
}
```

التنفيذ الوحيد اليوم `JwtService` في `Sadara.Infrastructure/Identity/IdentityServices.cs` يستخدم `SymmetricSecurityKey` + `HmacSha256` (HS256)، ويُحقن في `Program.cs:57-62` عبر `new JwtService(...)`.

### 1.2 المستدعون الخمسة (المصدر: `Sadara.Application/Services/Services.cs` — كلهم داخل `AuthService`)

| # | الدالة | السطر | الاستدعاء |
|---|--------|-------|-----------|
| 1 | `LoginAsync` | 87–88 | `GenerateAccessToken(user)` + `GenerateRefreshToken()` |
| 2 | `RegisterAsync` | 130–131 | `GenerateAccessToken(user)` + `GenerateRefreshToken()` |
| 3 | `RefreshTokenAsync` | 154–155 | `GenerateAccessToken(user)` + `GenerateRefreshToken()` |
| 4 | `AuthenticateWithFirebaseAsync` | 252–253 | `GenerateAccessToken(user)` + `GenerateRefreshToken()` |
| 5 | (نفس المجموعة عبر `_jwtService` المحقون في مُنشئ `AuthService`) | — | كل الاستدعاءات تمرّ عبر حقل `_jwtService` واحد |

**ملاحظة معمارية حاسمة**: كل المستدعين يعتمدون فقط على التوقيع `GenerateAccessToken(User)` و`GenerateRefreshToken()` — لا يمرّرون اسم خوارزمية ولا مفتاحاً ولا أي شيء متعلّق بالتوقيع. لذلك **أي إستراتيجية توقيع يمكن حقنها خلف نفس الواجهة دون لمس أي سطر في `Services.cs`**. هذا القيد (عدم تعديل المستدعين الخمسة) هو المعيار الحاكم لاختيار الحل.

> تنويه: توجد مولّدات refresh token **مكرّرة ومحلية** داخل كنترولرات (`UnifiedAuthController`, `SuperAdminController`, `CompaniesController` — دوال `private static string GenerateRefreshToken()`). هذه **خارج نطاق ADR-002** (لا تمرّ عبر `IJwtService`)؛ يُنصَح لاحقاً بتوحيدها عبر الواجهة كتحسين منفصل (دَين معماري)، لكن لا يُلمس ضمن هذه الزيادة الآمنة.

---

## 2. مقارنة الخيارين

### الخيار (أ) — توسيع العقد (Extend `IJwtService`)

إضافة أعضاء للواجهة، مثل `GenerateAccessToken(User user, string algorithm)` أو خاصية `Algorithm`، أو دالة `GetJwks()`.

| البُعد | التقييم |
|--------|---------|
| أثر على المستدعين الخمسة | **سلبي محتمل**: أي عضو جديد بلا تنفيذ افتراضي يفرض تحديث المستدعين أو على الأقل مراجعتهم؛ يخالف قيد "دون تعديل". |
| نقاء العقد (Domain) | يلوّث عقد المجال بتفاصيل توقيع (algorithm/JWKS) — تسريب اهتمام بنية تحتية إلى `Domain`. |
| مبدأ ISP (فصل الواجهات) | ينتهكه: المستدعون لا يحتاجون معرفة الخوارزمية ولا JWKS. |
| مبدأ OCP (مفتوح للتوسعة/مغلق للتعديل) | ضعيف: نعدّل العقد نفسه لإضافة سلوك. |
| نقطة JWKS | لا تنتمي منطقياً لعقد إصدار توكن المستخدم؛ إقحامها في `IJwtService` خلط مسؤوليات. |
| المخاطرة على الإنتاج | أعلى: تغيير سطح API للعقد المستهلَك من طبقة التطبيق. |

### الخيار (ب) — Strategy/Factory يُختار بإعداد `Jwt:Algorithm` (**المختار**)

`IJwtService` يبقى كما هو حرفياً. نضيف تنفيذين للتوقيع خلف نفس الواجهة، ومصنعاً يختار بينهما حسب `Jwt:Algorithm`:

- `JwtService` الحالي (HS256) — **يبقى دون تغيير** (أو يُعاد تسميته داخلياً `Hs256JwtService` كتحسين اختياري لا يلمس السلوك؛ التوصية: إبقاؤه باسمه لتقليل الرقعة).
- `Rs256JwtService` (جديد) — ينفّذ نفس `IJwtService` لكن بـ `RsaSecurityKey` + `RS256`، ويضيف `kid` في رأس التوكن (لدعم التدوير عبر JWKS لاحقاً — ADR-001 §3.4).
- مصنع/تسجيل شرطي في `Program.cs`: إن كان `Jwt:Algorithm == "RS256"` يُحقن `Rs256JwtService`، وإلا (الافتراضي/غير مضبوط) يُحقن `JwtService` الحالي.
- نقطة JWKS تُسجَّل كـ endpoint مستقل (خارج `IJwtService` تماماً) وتُفعَّل منطقياً فقط في وضع RS256.

| البُعد | التقييم |
|--------|---------|
| أثر على المستدعين الخمسة | **صفر**: التوقيع لم يتغيّر؛ `Services.cs` لا يُلمس. |
| نقاء العقد (Domain) | محفوظ: لا تسريب تفاصيل توقيع إلى `Domain`. |
| مبدأ OCP | قوي: نُضيف تنفيذاً جديداً دون تعديل الموجود ولا العقد. |
| مبدأ DIP (Program يحقن التنفيذ) | يعزّزه: القرار في تكوين التركيب (composition root) وهو `Program.cs`. |
| نقطة JWKS | مسؤولية منفصلة (endpoint/خدمة نشر مفتاح عام) — فصل اهتمامات نظيف. |
| التشغيل المزدوج (ADR-001 R9) | يمهّد له: يمكن لاحقاً إضافة تحقّق يقبل HS256 القديم + RS256 الجديد خلف نفس نمط الإعداد بلا كسر. |
| قابلية الرجوع (rollback) | فوري وآمن: قلب `Jwt:Algorithm` لـ `HS256` يعيد السلوك الأصلي بلا إعادة نشر كود. |
| المخاطرة على الإنتاج عند flag=OFF | صفرية عملياً (نفس مسار الكود الحالي يُنفَّذ). |

### 2.1 القرار والتبرير

**نختار الخيار (ب) — Strategy/Factory بإعداد `Jwt:Algorithm`.**

الأسباب:
1. **يحقّق القيد الصارم**: المستدعون الخمسة في `Services.cs` **لا يُلمَسون** لأن توقيع `IJwtService` يبقى حرفياً كما هو.
2. **يحترم Clean Architecture**: تفاصيل التوقيع (algorithm/keys/JWKS) اهتمام بنية تحتية (Infrastructure/API)، لا يتسرّب إلى `Domain`. الخيار (أ) يلوّث العقد المجالي.
3. **OCP/OCP-friendly**: نُضيف تنفيذاً (`Rs256JwtService`) دون تعديل الموجود ولا العقد.
4. **أمان الانتقال**: يمنح تبديلاً وتراجعاً بإعداد واحد (لا إعادة نشر كود)، وهو المطلوب لـ"أول زيادة آمنة" ويمهّد للتشغيل المزدوج (ADR-001 §R9/§10 المرحلة 1).
5. **مطابقة النموذج المُثبت**: PoC (`poc/identity-gateway`) أثبت بالضبط هذا الفصل — توقيع RS256 + نشر JWKS كـ endpoint مستقل — دون أي عقد مشترك مع مستهلكي التوكن.

الخيار (أ) **مرفوض** لأنه يخاطر بلمس المستدعين، يلوّث عقد المجال، وينتهك ISP/OCP.

---

## 3. نقاط الحقن الدقيقة في `Program.cs` — "ما سيُضاف" (لا "ما سيُعدَّل")

المرجع: `src/Backend/API/Sadara.API/Program.cs`. الوضع الحالي: تسجيل التوقيع في الأسطر 57–62، وتسجيل التحقّق `AddJwtBearer` في 103–160.

> **مبدأ التصميم**: كل ما يلي **إضافات مشروطة**. عند غياب `Jwt:Algorithm` أو ضبطه `HS256` (الافتراضي) يُنفَّذ **بالضبط** مسار الكود الحالي. لا يُحذف ولا يُعاد كتابة أي سطر موجود؛ يُغلَّف الموجود داخل الفرع الافتراضي فقط.

### 3.1 نقطة التوقيع (حالياً 57–62)

**ما سيُضاف**: قراءة `var jwtAlgorithm = builder.Configuration["Jwt:Algorithm"] ?? "HS256";` ثم تسجيل شرطي:
- إذا `HS256` (الافتراضي) → **نفس** `new JwtService(...)` الحالي حرفياً (بلا تغيير الوسائط).
- إذا `RS256` → `new Rs256JwtService(...)` مع مسار المفتاح الخاص من إعداد/متغيّر بيئة (لا يُلتزم في git — القاعدتان 6/7).

**ضمان OFF**: الفرع الافتراضي هو السطر الحالي نفسه ⇒ سلوك مطابق 100%.

### 3.2 نقطة التحقّق `AddJwtBearer` (حالياً 103–160)

**ما سيُضاف**: تحديد `IssuerSigningKey`/`TokenValidationParameters` بشكل مشروط على `jwtAlgorithm`:
- إذا `HS256` → **نفس** `new SymmetricSecurityKey(key)` + نفس بارامترات التحقّق الحالية (109–117) حرفياً، **ونفس** `JwtBearerEvents` (`OnMessageReceived` لـ SignalR في 122–131، و`OnTokenValidated` لإثراء `company_id` في 135–158) **دون أي تغيير**.
- إذا `RS256` → `IssuerSigningKey` من المفتاح العام (`RsaSecurityKey`)، أو `IssuerSigningKeyResolver`/`ConfigurationManager` يقرأ JWKS محلياً، مع `ValidAlgorithms = ["RS256"]`. **نفس** `JwtBearerEvents` تُعاد استخدامها كما هي (منطق SignalR وإثراء `company_id` مستقل عن الخوارزمية).

**ضمان OFF**: بارامترات التحقّق للـ HS256 هي الأسطر الحالية نفسها ⇒ التوكنات الحالية تُقبل تماماً كما اليوم.

### 3.3 نقطة نشر JWKS (`/.well-known/jwks.json`) — جديدة كلياً

**ما سيُضاف**: تسجيل endpoint بعد `app.MapControllers()` (بجوار 333–337) ينشر المفتاح العام (JWK Set) — بنمط PoC (`poc/identity-gateway`). التفعيل المنطقي مشروط: في وضع `HS256` يُعيد إمّا 404/تعطيل أو مجموعة فارغة (لا مفتاح عام يُنشَر لأن HS256 سرّي متماثل)؛ في وضع `RS256` يُعيد المفتاح العام فقط.

**ضمان OFF**: في وضع HS256 لا يُنشَر أي مفتاح، ولا يُغيَّر أي مسار قائم ⇒ لا أثر على الإنتاج الحالي.

### 3.4 مصفوفة تكافؤ السلوك عند `Jwt:Algorithm = HS256` (أو غير مضبوط)

| السلوك | الحالي | بعد الزيادة (flag=OFF) | مطابق؟ |
|--------|--------|------------------------|--------|
| خوارزمية التوقيع | HS256 (Symmetric) | HS256 (نفس المسار) | ✅ |
| مفتاح/سرّ التوقيع | `Jwt:Secret` | نفسه | ✅ |
| بارامترات التحقّق | 109–117 | نفسها | ✅ |
| `OnMessageReceived` (SignalR) | 122–131 | نفسها | ✅ |
| `OnTokenValidated` (إثراء company_id) | 135–158 | نفسه | ✅ |
| نقطة JWKS | غير موجودة | معطّلة/فارغة | ✅ (لا أثر) |
| عقد `IJwtService` | ثلاثي | ثلاثي (بلا تغيير) | ✅ |
| `Services.cs` (المستدعون الخمسة) | كما هو | كما هو | ✅ |

---

## 4. حدود سياق الهوية (كيانات المجموعة أ حسب ADR-001) — بلا كود

ADR-002 يمسّ فقط **آلية توقيع/تحقّق التوكن**، وهي جزء من **سياق الهوية والترخيص (Identity/Licensing Context)** المعرّف في ADR-001 §4. لأغراض هذه الزيادة الآمنة، حدود السياق ذات الصلة (كيانات المجموعة أ — تبقى مركزية):

- **الهوية والمصادقة**: `User` (سجل الهوية المصدري — بيانات الاعتماد/الدور/`CompanyId`/حالة النشاط). التوقيع RS256 يخدم إصدار هوية هذا الكيان.
- **الشركات والترخيص**: `Company`, `CompanyService`, `CompanyFtthSettings` (سجل الشركة + حالة الترخيص — مصدر `company_id`/`license_exp` مستقبلاً).
- **الصلاحيات (ServiceAndPermission)**: `Permission`, `UserPermission`, `Service`, `OperationType`, `ServiceOperation` (تعريفات مرجعية عابرة للشركات).

**قيد معماري لـ ADR-002**: لا نُدخل في هذه الزيادة أي claim جديد يغيّر عقد التوكن الوظيفي (لا `node_id`/`license_exp` بعد — تلك مرحلة لاحقة في ADR-001). ADR-002 يقتصر على **آلية التوقيع** مع إبقاء **محتوى الـ claims الحالي كما هو** (نفس claims `JwtService` الحالية: `sub`, `jti`, `NameIdentifier`, `Name`, `MobilePhone`, `Role`, `MerchantId`, `company_id`). إضافة `kid` تكون في **رأس** التوكن (header) لا في الحمولة، ولا تؤثر على المستهلكين. هذا يحافظ على تكافؤ سلوك المصادقة تماماً ويحصر التغيير في التوقيع فقط.

---

## 5. تأكيد عدم كسر اتجاه تبعيات Clean Architecture

الاتجاه الحاكم: `API → Application → Domain ← Infrastructure` (التبعيات نحو الداخل؛ `Domain` بلا تبعيات خارجية؛ `Infrastructure` ينفّذ واجهات `Domain`).

| العنصر | الطبقة | الاتجاه | الحكم |
|--------|--------|---------|-------|
| `IJwtService` (بلا تغيير) | Domain | مصدر العقد | ✅ سليم — لم يُلمس |
| `Rs256JwtService` (جديد) | Infrastructure | ينفّذ `IJwtService` من Domain | ✅ سليم — Infrastructure→Domain (نحو الداخل) |
| `JwtService` الحالي | Infrastructure | كما هو | ✅ سليم |
| مصنع/تسجيل شرطي | API (`Program.cs` = composition root) | يحقن تنفيذاً من Infrastructure | ✅ سليم — التركيب مكان طبيعي لقرار DI |
| endpoint JWKS | API | ينشر مفتاحاً عاماً | ✅ سليم — اهتمام عرض/بنية تحتية في طبقة API |
| `AuthService` (المستدعون) | Application | يعتمد على `IJwtService` (Domain) | ✅ سليم — لم يُلمس |

**النتيجة**: لا تبعية عكسية، لا تسريب منطق مجال إلى API، لا اعتماد لـ `Domain` على `Infrastructure`. الاهتمام الجديد (توقيع RS256/JWKS) يقع كله في `Infrastructure` (التنفيذ) و`API` (التركيب + نقطة النشر) — وهو موضعه الصحيح. الخيار (أ) كان سيخاطر بتسريب تفاصيل توقيع إلى عقد `Domain`؛ الخيار (ب) يتفاداه.

---

## 6. قائمة الملفات المتأثرة (مسارات مطلقة)

> جميع التعديلات على الملفات القائمة **إضافية فقط (additive)**: تغليف الموجود داخل فرع افتراضي دون حذف/إعادة كتابة سلوك، بحيث يبقى المسار الافتراضي (`HS256`) مطابقاً 100%.

| # | الملف (مسار مطلق) | الوسم | ما يحدث |
|---|--------------------|-------|---------|
| 1 | `C:\SadaraPlatform\src\Backend\Core\Sadara.Infrastructure\Identity\Rs256JwtService.cs` | **يُضاف جديد** | تنفيذ `IJwtService` بـ `RsaSecurityKey`/`RS256` + `kid` في الرأس. |
| 2 | `C:\SadaraPlatform\src\Backend\Core\Sadara.Infrastructure\Identity\JwksService.cs` (أو مساوٍ) | **يُضاف جديد** | تحميل/إتاحة المفتاح العام كـ JWK Set لنقطة JWKS. |
| 3 | `C:\SadaraPlatform\src\Backend\API\Sadara.API\Program.cs` | **يُعدَّل — إضافي فقط** | (3.1) تسجيل توقيع شرطي على `Jwt:Algorithm`؛ (3.2) `AddJwtBearer` شرطي مع إبقاء `JwtBearerEvents` كما هي؛ (3.3) تسجيل endpoint JWKS. الفرع الافتراضي = الأسطر الحالية حرفياً. |
| 4 | `C:\SadaraPlatform\src\Backend\API\Sadara.API\appsettings.json` | **يُعدَّل — إضافي فقط** | إضافة مفتاح `Jwt:Algorithm` بقيمة `"HS256"` (افتراضي OFF) + مسار/إشارة مفتاح RS256 عبر env (لا قيمة سرّية في الملف — القاعدة 6). |
| 5 | `C:\SadaraPlatform\src\Backend\Core\Sadara.Domain\Interfaces\Interfaces.cs` | **لا يُعدَّل** (توثيق سلبي) | عقد `IJwtService` يبقى ثلاثياً حرفياً — تأكيد صريح. |
| 6 | `C:\SadaraPlatform\src\Backend\Core\Sadara.Application\Services\Services.cs` | **لا يُعدَّل** (توثيق سلبي) | المستدعون الخمسة يبقون كما هم — تأكيد صريح. |
| 7 | `C:\SadaraPlatform\src\Backend\Core\Sadara.Infrastructure\Identity\IdentityServices.cs` (`JwtService` الحالي) | **لا يُعدَّل** (توصية) | يُترك كما هو لتقليل الرقعة؛ إعادة التسمية `Hs256JwtService` اختيارية ومؤجَّلة. |

> ملاحظة: الملفات 5–7 مذكورة لتوثيق أنها **لن** تتغيّر (وضوح النطاق)، وليست ضمن التعديلات الفعلية.

---

## 7. المخاطر والحسم المطلوب

| # | البند | الحاسم | الحالة |
|---|-------|--------|--------|
| Q1 | توليد/تخزين المفتاح الخاص RS256 (مكان، صلاحيات 600، عدم الالتزام في git، تدوير عبر `kid`) — ADR-001 §3.4/R2 | `security-auditor-agent` | مفتوح — يجب حسمه قبل تنفيذ RS256 (لا يلزم لتفعيل الزيادة OFF). |
| Q2 | سلامة (integrity) نقطة JWKS (HTTPS إلزامي، احتمال TLS pinning، منع MITM يستبدل المفتاح) | `security-auditor-agent` | مفتوح. |
| Q3 | سياسة التشغيل المزدوج (هل يقبل التحقّق HS256+RS256 معاً في نافذة انتقال؟ ADR-001 R9) | `security-auditor-agent` | مفتوح — تصميم لاحق؛ ADR-002 لا يفعّله. |
| Q4 | توحيد مولّدات `GenerateRefreshToken` المكرّرة في الكنترولرات عبر `IJwtService` | `architecture` + `security-auditor` | دَين معماري خارج نطاق ADR-002. |
| Q5 | إدارة `Jwt:Algorithm` والمفتاح عبر env/secret store في الإنتاج (لا في appsettings) | `devops-agent` + `security-auditor-agent` | مفتوح. |

**بوابة أمنية إلزامية (القاعدة 14)**: أي انتقال فعلي لـ `Jwt:Algorithm = RS256` = **تغيير نظام مصادقة** → يتطلب موافقة `security-auditor-agent` + المستخدم صراحةً. تفعيل الزيادة بوضع OFF (إدخال الكود مع بقاء `HS256`) لا يغيّر سلوك المصادقة لكنه يظل يمرّ على `security-auditor` لأنه يمسّ ملفات المصادقة.

---

## 8. القرار (Decision Record)

نعتمد **الخيار (ب): Strategy/Factory بإعداد `Jwt:Algorithm`** لإدخال قدرة RS256 + نقطة JWKS كزيادة آمنة إضافية خلف flag يبدأ OFF (`HS256`)، مع:
- إبقاء عقد `IJwtService` الثلاثي حرفياً، وعدم لمس المستدعين الخمسة في `Services.cs`.
- حصر التغيير في `Infrastructure` (تنفيذ RS256/JWKS) و`API` (تركيب شرطي + نقطة نشر).
- ضمان تكافؤ سلوك 100% عند القيمة الافتراضية.
- عدم إدخال claims وظيفية جديدة في هذه الزيادة (يقتصر على آلية التوقيع).

**الحالة "مقترَح" حتى موافقة `project-manager` + المستخدم ومراجعة `security-auditor-agent`. لا كود يُكتب داخل `src/` قبل ذلك.**

---

## 9. مراجع

- `docs/architecture/ADR-001-distributed-multi-tenant.md` — الإطار الأشمل (المرحلة 1: CILA + RS256 + JWKS + التشغيل المزدوج).
- `poc/README.md` + `poc/identity-gateway/` + `poc/company-node/` — النموذج المُثبت (RS256 + JWKS + تحقّق ذاتي، 2026-08-02).
- `src/Backend/Core/Sadara.Domain/Interfaces/Interfaces.cs` (`IJwtService` §195–200) — العقد المحفوظ.
- `src/Backend/Core/Sadara.Infrastructure/Identity/IdentityServices.cs` (`JwtService` HS256) — التنفيذ الحالي.
- `src/Backend/API/Sadara.API/Program.cs` (§57–62 التوقيع، §103–160 التحقّق) — نقاط الحقن.
- `src/Backend/Core/Sadara.Application/Services/Services.cs` (§87، 130، 154، 252) — المستدعون الخمسة (بلا تعديل).
- `.claude/memory/ARCHITECTURE.md`، `.claude/memory/DECISIONS.md`.
