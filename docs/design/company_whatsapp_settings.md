# Design: CompanyWhatsAppSettings — إعدادات واتساب لكل شركة في PostgreSQL

> **حالة الوثيقة:** مقترح تصميم فقط (DESIGN-ONLY).
> **ممنوع** تطبيق أي migration على أي قاعدة بيانات (قواعد ذهبية #10/#11). لا psql ولا `dotnet ef` ضد قاعدة حقيقية.
> **الفرع:** `feature/phase1-security` (موضوعه عزل المستأجرين multi-tenant عبر `CompanyId`).
> **المالك:** database-postgres-agent. **يتطلب مراجعة:** security-auditor-agent (بسبب أسرار at-rest) + backend-agent (شكل الكيان والـ endpoint) + موافقة بشرية قبل أي تطبيق.

---

## 0. المشكلة والهدف

- **الوضع الحالي:** إعدادات واتساب لكل شركة تُخزَّن محلياً على كل جهاز في `SharedPreferences` وتُدخَل يدوياً.
  - أدلة من كود التطبيق:
    - `src/Apps/CompanyDesktop/alsadara-ftth/lib/whatsapp/services/whatsapp_system_settings_service.dart:21` → `whatsapp_renewal_system`
    - نفس الملف `:22` → `whatsapp_bulk_system`
    - نفس الملف `:143` → `whatsapp_server_url`
    - مفاتيح أخرى مستخدمة في: `lib/services/whatsapp_bulk_sender_service.dart`, `lib/services/whatsapp_business_service.dart`, `lib/whatsapp/services/whatsapp_server_service.dart`.
  - النتيجة: أخطاء إدخال يدوي + فقدان الإعدادات عند كل تثبيت جديد.
- **الهدف:** تخزين هذه الإعدادات في PostgreSQL لكل شركة (سجل واحد لكل `CompanyId`)، يجلبها التطبيق تلقائياً عند تسجيل الدخول عبر endpoint محمي، مع حماية الأسرار at-rest.

### الحقول المطلوبة (مستخرجة من كود التطبيق)

| مفتاح التطبيق (SharedPreferences) | حسّاس؟ | إلزامي؟ | ملاحظات |
|---|---|---|---|
| `whatsapp_user_token` | **نعم (سرّ)** | نعم لأنظمة api/web | Access Token لـ Meta Graph API |
| `whatsapp_phone_number_id` | لا | نعم لأنظمة api/web | معرّف رقم الهاتف في Meta |
| `whatsapp_business_account_id` | لا | اختياري | WABA id |
| `n8n_webhook_url` | لا (URL) | حسب النظام | نقطة n8n للإرسال/الاستقبال |
| `whatsapp_webhook_verify_token` | **نعم (سرّ)** | اختياري | verify token لبوابة webhook |
| `whatsapp_renewal_system` | لا | نعم | قيم: `app` / `web` / `server` / `api` |
| `whatsapp_bulk_system` | لا | نعم | قيم: `server` / `api` |
| `whatsapp_server_url` | لا (URL) | اختياري | لنظام السيرفر فقط |

---

## 1. فحص أنماط الكود الحالية (بالأدلة)

### 1.1 الكيان الأساسي (BaseEntity)
`src/Backend/Core/Sadara.Domain/Entities/BaseEntity.cs`
```
abstract class BaseEntity        → CreatedAt (UtcNow default), UpdatedAt?, IsDeleted (=false), DeletedAt?
abstract class BaseEntity<TId>   → Id
```
- أعمدة التدقيق (CreatedAt/UpdatedAt) و soft-delete (IsDeleted/DeletedAt) موروثة تلقائياً — **لا نضيفها يدوياً**.

### 1.2 القالب الأمثل: كيان إعدادات لكل شركة موجود فعلاً
`src/Backend/Core/Sadara.Domain/Entities/CompanyFtthSettings.cs` — هذا هو القالب الأقرب تماماً لحالتنا:
- `class CompanyFtthSettings : BaseEntity<Guid>` مع `public Guid CompanyId { get; set; }` (سطر 10).
- علاقة 1-إلى-1 مع الشركة عبر `public virtual Company Company { get; set; }` (سطر 68).
- يخزّن سرّاً (`FtthPassword`, سطر 15-16) — **لكن انتبه للتحذير في §3**.

تكوينه في `src/Backend/Core/Sadara.Infrastructure/Data/SadaraDbContext.cs:378-382`:
```
modelBuilder.Entity<CompanyFtthSettings>().HasQueryFilter(x => !x.IsDeleted);
modelBuilder.Entity<CompanyFtthSettings>().HasIndex(x => x.CompanyId).IsUnique();   // ← يفرض 1:1
modelBuilder.Entity<CompanyFtthSettings>().HasOne(x => x.Company).WithMany()
    .HasForeignKey(x => x.CompanyId).OnDelete(DeleteBehavior.Cascade);
```
و `DbSet` معرّف في `SadaraDbContext.cs:159`.

### 1.3 آلية عزل المستأجرين المركزية (اكتشاف حاسم)
`src/Backend/Core/Sadara.Infrastructure/Data/SadaraDbContext.cs:1638-1673` — يوجد **فلتر عزل مركزي تلقائي**:
```csharp
foreach (var entityType in modelBuilder.Model.GetEntityTypes())
{
    var clrType = entityType.ClrType;
    if (!typeof(BaseEntity).IsAssignableFrom(clrType)) continue;
    if (TenantFilterExclusions.Contains(clrType.Name)) continue;
    var companyProp = entityType.FindProperty("CompanyId");
    if (companyProp != null && (companyProp.ClrType == typeof(Guid) || companyProp.ClrType == typeof(Guid?)))
        SetTenantFilterMethod.MakeGenericMethod(clrType).Invoke(this, new object[] { modelBuilder });
}
// SetTenantFilter (سطر 1668-1673):
//   !e.IsDeleted && (_tenant.BypassTenantFilter || EF.Property<Guid?>(e,"CompanyId") == _tenant.CompanyId)
```
**النتيجة العملية:** أي كيان يرث `BaseEntity` **وله خاصية `CompanyId` من نوع `Guid`/`Guid?`** يحصل تلقائياً على فلتر العزل — **بلا أي تسجيل يدوي**. (ملاحظة: هذا الفلتر التلقائي يفوز على أي `HasQueryFilter` صريح سابق لأنه يُطبَّق آخراً؛ الفلتر الصريح لـ CompanyFtthSettings في سطر 378 مكرَّر لكنه غير ضار.)

بالإضافة، `ApplyTenantAndAudit()` (`SadaraDbContext.cs:1691-1726`):
- عند الإدراج (`Added`): يضبط `CreatedAt=UtcNow`، ويفرض `CompanyId = _tenant.CompanyId` لأي مستخدم مُصادَق غير-متجاوز → **يمنع مركزياً حقن سجل في شركة أخرى** حتى لو حدّد الطلب CompanyId مختلفاً (سطر 1706-1711).
- عند التعديل (`Modified`): يضبط `UpdatedAt=UtcNow` تلقائياً (سطر 1721-1723).

واجهة السياق: `src/Backend/Core/Sadara.Application/Interfaces/ICurrentTenant.cs` → `CompanyId`, `IsSuperAdmin`, `BypassTenantFilter`, `DefaultCompanyId`.

### 1.4 نمط الـ Migrations
- المجلد: `src/Backend/Core/Sadara.Infrastructure/Data/Migrations` (84 migration).
- **آخر migration (رأس السلسلة):** `20260717223916_AddCompanyIdToAccountingChildren` (أعلى prefix رقمي).
- نمط CreateTable الكامل (مع FK إلى `Companies` و index فريد على `CompanyId`) موثّق في `20260406100000_AddFtthSyncSystem.cs:20-48` — هذا قالبنا المباشر.
- يوجد نمط بديل «يدوي» عبر ملفات `.sql` مطبّقة يدوياً مع تسجيل في `__EFMigrationsHistory` (مثال `Migrations/manual_whatsapp_tables.sql`) — نوثّقه كخيار طوارئ لكن **المسار المفضّل هو EF migration مُولّدة**.

### 1.5 موجود مسبقاً: controller ومحادثات واتساب (تمييز مهم)
- `src/Backend/API/Sadara.API/Controllers/CompanyFtthSettingsController.cs` موجود — نمط endpoint إعدادات لكل شركة (سنحاكيه لكن **بلا** تسريب السرّ، §3).
- `WhatsAppConversation` / `WhatsAppMessage` (`Sadara.Domain/Entities/WhatsAppData.cs`) كيانات **محادثات** واتساب، لا علاقة لها بالإعدادات — لتجنب الالتباس، اسم كياننا سيكون `CompanyWhatsAppSettings` (بادئة `Company`) تمييزاً واتساقاً مع `CompanyFtthSettings`.

---

## 2. تصميم الكيان `CompanyWhatsAppSettings`

**المسار المقترح:** `src/Backend/Core/Sadara.Domain/Entities/CompanyWhatsAppSettings.cs`

```csharp
namespace Sadara.Domain.Entities;

/// <summary>
/// إعدادات تكامل واتساب لكل شركة (سجل واحد لكل CompanyId).
/// تحلّ محل التخزين المحلي في SharedPreferences على أجهزة التطبيق.
/// الأسرار (UserTokenEnc / WebhookVerifyTokenEnc) مخزّنة **مشفّرة** (انظر §3) — لا نص صريح.
/// </summary>
public class CompanyWhatsAppSettings : BaseEntity<Guid>
{
    /// <summary>معرف الشركة — مفتاح العزل (1:1 مع الشركة).</summary>
    public Guid CompanyId { get; set; }

    // ── أسرار (مخزّنة مشفّرة at-rest — القيمة هنا هي ciphertext) ──
    /// <summary>Access Token لـ Meta (مشفّر). null = غير مضبوط.</summary>
    public string? UserTokenEnc { get; set; }

    /// <summary>verify token لبوابة الـ webhook (مشفّر، اختياري).</summary>
    public string? WebhookVerifyTokenEnc { get; set; }

    // ── معرّفات/روابط غير سرّية (نص صريح) ──
    public string? PhoneNumberId { get; set; }
    public string? BusinessAccountId { get; set; }
    public string? N8nWebhookUrl { get; set; }
    public string? ServerUrl { get; set; }

    // ── اختيارات النظام (قيم مقيّدة) ──
    /// <summary>نظام التجديد: app | web | server | api.</summary>
    public string RenewalSystem { get; set; } = "app";

    /// <summary>نظام الإرسال الجماعي: server | api.</summary>
    public string BulkSystem { get; set; } = "server";

    // ── العلاقة ──
    public virtual Company Company { get; set; } = null!;

    // ملاحظة: CreatedAt/UpdatedAt/IsDeleted/DeletedAt موروثة من BaseEntity — لا تُضاف يدوياً.
}
```

### تكوين EF المقترح (يُضاف داخل `OnModelCreating` في `SadaraDbContext.cs`)
> يُوضع بجوار كتلة FTTH Sync (بعد سطر 404) للاتساق. **لا حاجة لإضافة `HasQueryFilter` للعزل** — الفلتر المركزي (§1.3) يطبّقه تلقائياً لأن الكيان يرث `BaseEntity` وله `Guid CompanyId`.

```csharp
// ==================== WhatsApp Settings (إعدادات واتساب لكل شركة) ====================
modelBuilder.Entity<CompanyWhatsAppSettings>()
    .HasIndex(x => x.CompanyId).IsUnique();                 // يفرض 1:1
modelBuilder.Entity<CompanyWhatsAppSettings>()
    .HasOne(x => x.Company).WithMany().HasForeignKey(x => x.CompanyId)
    .OnDelete(DeleteBehavior.Cascade);
modelBuilder.Entity<CompanyWhatsAppSettings>()
    .Property(x => x.RenewalSystem).HasMaxLength(20).IsRequired();
modelBuilder.Entity<CompanyWhatsAppSettings>()
    .Property(x => x.BulkSystem).HasMaxLength(20).IsRequired();
modelBuilder.Entity<CompanyWhatsAppSettings>()
    .Property(x => x.PhoneNumberId).HasMaxLength(100);
modelBuilder.Entity<CompanyWhatsAppSettings>()
    .Property(x => x.BusinessAccountId).HasMaxLength(100);
modelBuilder.Entity<CompanyWhatsAppSettings>()
    .Property(x => x.N8nWebhookUrl).HasMaxLength(500);
modelBuilder.Entity<CompanyWhatsAppSettings>()
    .Property(x => x.ServerUrl).HasMaxLength(500);
modelBuilder.Entity<CompanyWhatsAppSettings>()
    .Property(x => x.UserTokenEnc).HasMaxLength(2000);      // ciphertext مُوسّع (Base64)
modelBuilder.Entity<CompanyWhatsAppSettings>()
    .Property(x => x.WebhookVerifyTokenEnc).HasMaxLength(2000);
```
و `DbSet`:
```csharp
public DbSet<CompanyWhatsAppSettings> CompanyWhatsAppSettings => Set<CompanyWhatsAppSettings>();
```

**قرار مفتوح — اختيار قيمة `RenewalSystem`/`BulkSystem`:** الاعتماد على `HasMaxLength` + تحقّق في طبقة التطبيق (متسق مع نمط المشروع الذي يخزّن الحالات كنصوص، مثل `TriggerSource`). بديل أقوى: `CHECK constraint`. مقترح: نبدأ بالتحقق في التطبيق (`app|web|server|api` و `server|api`) ونؤجّل الـ CHECK لتفادي مخاطر ترحيل بيانات قديمة غير مطابقة.

---

## 3. تشفير الأسرار at-rest (بند حرج — يتطلب security-auditor)

### تحذير من سابقة موجودة (يجب عدم تكرارها)
- `CompanyFtthSettings.FtthPassword` موصوف بأنه «مشفّر» في التعليق (`CompanyFtthSettings.cs:15`)، **لكن الكود الفعلي يخزّنه نصاً صريحاً**: `CompanyFtthSettingsController.cs:102` و`:118` يُسنِدان `request.FtthPassword` كما هو، وعمود الـ migration `character varying(500)` بلا أي تشفير (`AddFtthSyncSystem.cs:27`). **هذه سابقة خاطئة — لا نكرّرها لتوكن واتساب.**
- **لا يوجد** في الباك-إند أي خدمة تشفير قابلة للاسترجاع (reversible). الموجود فقط:
  - BCrypt (تجزئة أحادية الاتجاه) في `IdentityServices.cs:13-20` — غير صالح لتوكن يجب إرساله لاحقاً لـ Meta.
  - MD5 (استخدام غير تشفيري) في `InternalDataController.cs:3679`.
- `.env` يذكر مفتاحي `ENCRYPTION_KEY` / `ENCRYPTION_IV` (حسب `SECURITY_RULES.md:14`) لكنهما **غير موصولين بأي كود تشفير حالياً** (لم يُعثر على AES/IDataProtector في الباك-إند).

### القرار المقترح (تشفير على مستوى التطبيق قبل التخزين)
نخزّن `UserTokenEnc` و`WebhookVerifyTokenEnc` كـ **ciphertext** (Base64) لا كنص صريح. خياران:

- **الخيار A (مفضّل): ASP.NET Core Data Protection API.**
  - مزايا: مدمج في .NET، لا نعيد اختراع تشفير، يدير المفاتيح ودورانها.
  - يُنشأ `IEncryptionService` رقيق يلفّ `IDataProtector` بغرض ثابت `"CompanyWhatsAppSettings.Secrets"`.
  - **متطلب حرج للإنتاج:** تثبيت مخزن مفاتيح Data Protection على قرص دائم على VPS (`PersistKeysToFileSystem` على مسار خارج مجلد النشر) — وإلا فإن إعادة النشر تُدوّر المفتاح وتُفشل فكّ التشفير للأسرار القديمة. **بوابة موافقة بشرية + تنسيق مع devops-agent.**

- **الخيار B: AES-256-GCM يدوي بمفتاح من البيئة (`ENCRYPTION_KEY`).**
  - يعيد استخدام مفتاح `.env` الموجود اسمياً، لكن يتطلب إدارة IV/nonce يدوياً وكتابة تشفير مخصص (سطح خطأ أعلى) ويحتاج مراجعة security-auditor أدق.
  - **يمرّ حتماً على security-auditor-agent قبل أي تنفيذ.**

**عناصر ثابتة مهما كان الخيار:**
1. لا يُخزَّن أي سرّ نصاً صريحاً في القاعدة أو في migration أو في التقارير/اللوج.
2. **العمود لا يُعاد أبداً في استجابة الـ GET.** الـ endpoint يُرجع فقط `HasUserToken: bool` (هل مضبوط؟)، لا القيمة ولا الـ ciphertext. (هذا يخالف عمداً سابقة FtthPassword في `CompanyFtthSettingsController.cs:71` التي تُعيد كلمة المرور — لا نكررها.)
3. الكتابة فقط عبر endpoint محمي (JWT + صلاحية إدارية)، والقيمة تُشفَّر في طبقة التطبيق **قبل** الوصول لـ `SaveChanges`.
4. مفتاح التشفير سرّ P0: من `.env`/متغيرات البيئة/مخزن أسرار فقط — لا في الكود ولا في الريبو (SECURITY_RULES).
5. تدوير المفتاح (rotation): يتطلب خطة إعادة تشفير للأعمدة القائمة — يوثّقها security-auditor عند التنفيذ.

> **القرار النهائي بين A و B متروك لـ security-auditor-agent + موافقة بشرية.** الأثر على schema **صفر** (كلاهما يخزّن سلسلة ciphertext في نفس العمودين).

---

## 4. Impact Analysis (تحليل الأثر)

| البُعد | الأثر |
|---|---|
| **جداول جديدة** | جدول واحد فقط: `CompanyWhatsAppSettings`. |
| **جداول قائمة** | **لا تعديل** على أي جدول قائم. لا أعمدة تُضاف/تُحذف. |
| **بيانات قائمة** | **لا مساس** بأي بيانات إنتاجية. الجدول يبدأ فارغاً. |
| **العلاقات** | FK جديد `CompanyWhatsAppSettings.CompanyId → Companies.Id` (Cascade). لا يؤثر على الشركات القائمة. |
| **الفهارس** | index فريد واحد على `CompanyId` (يفرض 1:1 ويسرّع الجلب عند الدخول). |
| **العزل** | يُطبَّق تلقائياً عبر الفلتر المركزي (§1.3) — لا كود عزل إضافي. |
| **الكود المتأثر** | إضافة: ملف كيان + `DbSet` + كتلة تكوين في `OnModelCreating` + migration. لاحقاً (خارج نطاق database-agent): endpoints في controller + قراءة التطبيق. |
| **من يتأثر** | backend-agent (endpoint/DTO)، mobile-agent (استبدال قراءة SharedPreferences بجلب من API)، security-auditor (تشفير)، devops-agent (مخزن مفاتيح Data Protection إن اختير الخيار A). |
| **المخاطر** | منخفضة على schema (جدول جديد معزول). الخطر الحقيقي في **إدارة مفتاح التشفير** (تسريب مفتاح = كشف كل التوكنات) وفي **ثبات مخزن المفاتيح** عبر عمليات النشر. |
| **الأداء** | ضئيل: قراءة سطر واحد بـ index فريد عند الدخول لكل شركة. |

**عدد الـ migrations بعد التطبيق:** 84 → 85.

---

## 5. Migration Plan (خطة الترحيل عبر EF Core)

> **DESIGN-ONLY. لا تُنفَّذ الآن. الأوامر أدناه للتوثيق فقط وتُشغَّل محلياً عند الموافقة، ثم تُراجَع Up/Down يدوياً.**

### 5.1 توليد الـ migration (محلياً فقط، لا اتصال بالإنتاج)
```bash
# من جذر المشروع، بيئة تطوير محلية فقط:
dotnet ef migrations add AddCompanyWhatsAppSettings \
  --project src/Backend/Core/Sadara.Infrastructure \
  --startup-project src/Backend/API/Sadara.API
```
سيُنشئ: `Migrations/<timestamp>_AddCompanyWhatsAppSettings.cs` (+ `.Designer.cs`) ويحدّث `SadaraDbContextModelSnapshot.cs`. الـ timestamp يجب أن يكون **أحدث** من `20260717223916` (رأس السلسلة الحالي).

### 5.2 شكل `Up` المتوقّع (يُراجَع يدوياً بعد التوليد — قالب من `AddFtthSyncSystem.cs`)
```csharp
migrationBuilder.CreateTable(
    name: "CompanyWhatsAppSettings",
    columns: table => new
    {
        Id = table.Column<Guid>(type: "uuid", nullable: false),
        CompanyId = table.Column<Guid>(type: "uuid", nullable: false),
        UserTokenEnc = table.Column<string>(type: "character varying(2000)", maxLength: 2000, nullable: true),
        WebhookVerifyTokenEnc = table.Column<string>(type: "character varying(2000)", maxLength: 2000, nullable: true),
        PhoneNumberId = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: true),
        BusinessAccountId = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: true),
        N8nWebhookUrl = table.Column<string>(type: "character varying(500)", maxLength: 500, nullable: true),
        ServerUrl = table.Column<string>(type: "character varying(500)", maxLength: 500, nullable: true),
        RenewalSystem = table.Column<string>(type: "character varying(20)", maxLength: 20, nullable: false, defaultValue: "app"),
        BulkSystem = table.Column<string>(type: "character varying(20)", maxLength: 20, nullable: false, defaultValue: "server"),
        CreatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
        UpdatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
        IsDeleted = table.Column<bool>(type: "boolean", nullable: false, defaultValue: false),
        DeletedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
    },
    constraints: table =>
    {
        table.PrimaryKey("PK_CompanyWhatsAppSettings", x => x.Id);
        table.ForeignKey("FK_CompanyWhatsAppSettings_Companies_CompanyId",
            x => x.CompanyId, "Companies", "Id", onDelete: ReferentialAction.Cascade);
    });

migrationBuilder.CreateIndex(
    "IX_CompanyWhatsAppSettings_CompanyId", "CompanyWhatsAppSettings", "CompanyId", unique: true);
```

### 5.3 SQL المكافئ (توثيق — يطابق ما يولّده EF على PostgreSQL)
```sql
CREATE TABLE "CompanyWhatsAppSettings" (
    "Id"                    uuid NOT NULL,
    "CompanyId"             uuid NOT NULL,
    "UserTokenEnc"          character varying(2000),
    "WebhookVerifyTokenEnc" character varying(2000),
    "PhoneNumberId"         character varying(100),
    "BusinessAccountId"     character varying(100),
    "N8nWebhookUrl"         character varying(500),
    "ServerUrl"             character varying(500),
    "RenewalSystem"         character varying(20)  NOT NULL DEFAULT 'app',
    "BulkSystem"            character varying(20)  NOT NULL DEFAULT 'server',
    "CreatedAt"             timestamp with time zone NOT NULL,
    "UpdatedAt"             timestamp with time zone,
    "IsDeleted"             boolean NOT NULL DEFAULT false,
    "DeletedAt"             timestamp with time zone,
    CONSTRAINT "PK_CompanyWhatsAppSettings" PRIMARY KEY ("Id"),
    CONSTRAINT "FK_CompanyWhatsAppSettings_Companies_CompanyId"
        FOREIGN KEY ("CompanyId") REFERENCES "Companies" ("Id") ON DELETE CASCADE
);

CREATE UNIQUE INDEX "IX_CompanyWhatsAppSettings_CompanyId"
    ON "CompanyWhatsAppSettings" ("CompanyId");
```

### 5.4 التطبيق على الإنتاج (بعد موافقة بشرية صريحة فقط)
- ممنوع auto-migrate عند الإقلاع (DATABASE_RULES:37).
- الخطوات عند الموافقة: (1) نسخة احتياطية للقاعدة، (2) تطبيق عبر `dotnet ef database update` مُراجَع **أو** SQL مُراجَع من §5.3، (3) تحقّق أن الجدول أُنشئ وفارغ. النشر يبقى على `72.61.183.61` فقط.
- هذا الجدول **إضافة غير مدمّرة** (جدول جديد فقط) → أقل الفئات خطورة، لكن يبقى تحت بند "database migration" الذي يتطلب موافقة.

---

## 6. Rollback Plan (خطة التراجع)

### 6.1 عبر EF (المفضّل)
```bash
# التراجع إلى الـ migration السابقة (رأس السلسلة الحالي):
dotnet ef database update 20260717223916_AddCompanyIdToAccountingChildren \
  --project src/Backend/Core/Sadara.Infrastructure \
  --startup-project src/Backend/API/Sadara.API
```
`Down` المتوقّعة:
```csharp
migrationBuilder.DropTable(name: "CompanyWhatsAppSettings");
```

### 6.2 SQL مكافئ للتراجع (طوارئ)
```sql
DROP INDEX IF EXISTS "IX_CompanyWhatsAppSettings_CompanyId";
DROP TABLE IF EXISTS "CompanyWhatsAppSettings";
DELETE FROM "__EFMigrationsHistory"
  WHERE "MigrationId" LIKE '%_AddCompanyWhatsAppSettings';
```

### 6.3 ملاحظات أمان التراجع
- التراجع يُسقط الجدول → **يفقد الأسرار المخزّنة فيه**. لأن هذه إعدادات لكل شركة، يُفضّل قبل الإسقاط أخذ نسخة احتياطية إن كان الجدول مأهولاً. في بيئة الاختبار الجدول عادةً فارغ فالإسقاط آمن.
- `DROP TABLE` عملية مدمّرة → على الإنتاج تتطلب موافقة بشرية صريحة (لكن هنا سياق rollback مخطّط له، وليس حذف بيانات عشوائي).
- لا يمسّ التراجع أي جدول قائم آخر (لا FK وارد من غير هذا الجدول).

---

## 7. Test Plan (على بيئة غير إنتاجية حصراً)

1. **بناء:** `dotnet build` للحل → 0 errors بعد إضافة الكيان/DbSet/التكوين/الـ migration.
2. **توليد الـ migration محلياً** والتأكد أن `Up`/`Down` مطابقان لـ §5.2/§6.1 وأن `SadaraDbContextModelSnapshot.cs` تحدّث.
3. **قاعدة اختبار محلية** (Postgres محلي/حاوية Docker، ليست الإنتاج):
   - `database update` → التحقق من إنشاء الجدول والـ index الفريد والـ FK.
   - إدراج سجل لشركة A، ومحاولة إدراج ثانٍ بنفس `CompanyId` → يجب أن يفشل بسبب unique index (يثبت 1:1).
4. **اختبار العزل (الأهم):**
   - سياق مستخدم شركة A (`_tenant.CompanyId = A`, `BypassTenantFilter=false`): استعلام `CompanyWhatsAppSettings` يُرجع سجل A فقط، ولا يُرجع سجل شركة B.
   - محاولة إدراج بـ `CompanyId = B` من سياق مستخدم A → `ApplyTenantAndAudit` يُعيد كتابته إلى A (يثبت منع الحقن عبر الحدود، `SadaraDbContext.cs:1706-1711`).
   - سياق SuperAdmin (`BypassTenantFilter=true`): يرى كل السجلات.
5. **اختبار التشفير:**
   - كتابة توكن → القيمة المخزّنة في العمود ≠ النص الصريح (ciphertext).
   - قراءة/فكّ التشفير في طبقة التطبيق تُعيد الأصل.
   - استجابة الـ GET **لا تحتوي** التوكن ولا الـ ciphertext (فقط `HasUserToken`).
6. **اختبار Rollback:** تنفيذ `Down` على قاعدة الاختبار والتأكد من إسقاط الجدول ونظافة `__EFMigrationsHistory`.
7. **API (لاحقاً، api-integration-tester-agent):** GET/PUT للـ endpoint بتوكن شركتين مختلفتين للتأكد أن كل شركة ترى/تكتب إعداداتها فقط (403/عزل عند تجاوز الحدود).

---

## 8. Security Considerations (اعتبارات الأمن)

1. **عزل المستأجرين:** مضمون تلقائياً بالفلتر المركزي (§1.3) لأن الكيان `BaseEntity` وله `Guid CompanyId`. لا يوجد استعلام يعبر الحدود. الإدراج مختوم مركزياً بشركة المستخدم. **لا يُضاف الكيان إلى `TenantFilterExclusions`** (`SadaraDbContext.cs:1661`).
2. **أسرار at-rest:** التوكن وverify token يُخزَّنان مشفّرين فقط (§3). لا نص صريح في القاعدة/الـ migration/التقارير. لا نكرّر سابقة `FtthPassword` الخاطئة.
3. **عدم تسريب السرّ في القراءة:** الـ GET لا يُرجع القيم السرّية، فقط أعلام وجود (`HasUserToken`). هذا يخالف عمداً سابقة `CompanyFtthSettingsController.cs:71`.
4. **التفويض:** endpoints الكتابة/القراءة محمية بـ JWT + صلاحية إدارية عبر `RequirePermissionAttribute` (SECURITY_RULES:19). لا `AllowAnonymous`.
5. **مفتاح التشفير:** سرّ P0 من البيئة فقط؛ تسريبه = كشف كل توكنات كل الشركات. تدويره يحتاج خطة إعادة تشفير (security-auditor).
6. **FK Cascade:** حذف شركة يحذف إعداداتها (سلوك متسق مع `CompanyFtthSettings`).
7. **RLS:** وجود RLS فعلياً على القاعدة Unknown (DATABASE_RULES:26-27). العزل هنا يعتمد على الفلتر المركزي في طبقة الكود. إن فُعِّل RLS مستقبلاً كطبقة دفاع ثانية، يُضاف هذا الجدول ضمن سياسة `CompanyId = current_setting(...)` — خارج نطاق هذا التغيير ويتطلب تنسيق security-auditor.

---

## 9. القرارات المفتوحة (تحتاج حسماً بشرياً/تنسيقاً)

| # | القرار | التوصية | من يحسم |
|---|---|---|---|
| D1 | خيار التشفير: Data Protection API (A) أم AES-256-GCM يدوي (B) | A (مدمج، أقل سطح خطأ) بشرط تثبيت مخزن مفاتيح دائم | security-auditor + human |
| D2 | ثبات مخزن مفاتيح Data Protection عبر النشر (حرج للخيار A) | `PersistKeysToFileSystem` على مسار دائم خارج مجلد النشر | devops-agent + human |
| D3 | اسم الجدول/الكيان | `CompanyWhatsAppSettings` (اتساقاً مع `CompanyFtthSettings`، وتمييزاً عن `WhatsAppConversation`) | database + backend |
| D4 | تقييد قيم `RenewalSystem`/`BulkSystem` | تحقّق في طبقة التطبيق الآن؛ تأجيل CHECK constraint | database + backend |
| D5 | استراتيجية الترحيل الأولي للبيانات | لا backfill تلقائي؛ التطبيق يرفع إعدادات SharedPreferences مرة واحدة عبر PUT عند أول دخول بعد النشر (منطق تطبيق، خارج نطاق database) | mobile + backend |

---

## 10. بوابات الموافقة البشرية (Human Approval Gates)

- تطبيق الـ migration على أي قاعدة (خصوصاً الإنتاج `72.61.183.61`) → **موافقة بشرية صريحة** (قواعد ذهبية #10/#11، PROJECT_CONTEXT §8).
- اختيار وتنفيذ آلية التشفير (تغيير يمسّ الأسرار) → مرور على **security-auditor-agent** + موافقة بشرية.
- تثبيت مخزن مفاتيح Data Protection على VPS (بنية تحتية) → **devops-agent** + موافقة بشرية.
- النشر يبقى عبر SCP على `72.61.183.61` فقط.

---

## 11. حدود هذه الوثيقة (Scope)

- **ضمن النطاق (database-postgres-agent):** الكيان، تكوين EF، الـ migration، خطة الترحيل/التراجع، العزل، ملاحظات التشفير على مستوى الـ schema.
- **خارج النطاق (يُسنَد لوكلاء آخرين):** كتابة الـ controller/DTO والـ endpoints (backend-agent)، تنفيذ خدمة التشفير الفعلية (backend + security-auditor)، استبدال قراءة SharedPreferences في التطبيق بجلب من API (mobile-agent)، تثبيت مخزن المفاتيح (devops-agent).
- **لم يُنفَّذ أي شيء على أي قاعدة بيانات. لا كود طُبِّق. هذه وثيقة تصميم فقط.**
