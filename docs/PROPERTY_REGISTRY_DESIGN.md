# تصميم: سجل العقارات المستقل (محوره QR، محايد الخدمة) — نواة الصدارة

> تاريخ: 2026-10-06 · تصميم + خطة (لم يُنفَّذ بعد). قرار المالك: النواة PostgreSQL + إعادة استخدام Citizen.

---

## الرؤية
العقار (المنزل) نظام **مستقل** محوره **QR دائم**. الـQR يشير للعقار (هوية ثابتة لا تتغيّر)، يُربط به **المواطن**، ثم **خدمات متعدّدة** (إنترنت الآن، ماستر/أي خدمة مستقبلاً). الخدمات تتغيّر، العقار والـQR يبقيان.

```
[ QR دائم ] ──► [ العقار ] ──┬──► [ مواطن (Citizen) ]  مالك/مستأجر/ساكن
 NPN+IqPin+موقع+صورة          ├──► [ خدمة: إنترنت (ساز/FTTH) ]
                              ├──► [ خدمة: ماستر ]
                              └──► [ … أي خدمة مستقبلية ]
```

---

## نموذج البيانات (نواة الصدارة — PostgreSQL، معزول بالشركة ITenantScoped)

### 1) `Property` — العقار (النواة المحايدة)
`Id`(Guid) · `CompanyId` · `CreatedByUserId` · **`QrToken`**(نصّي فريد دائم) · `Npn`/`NpnDisplay` · `IqPin`/`IqPinDisplay` · `GovCode` · `Governorate`/`Area`/`District`/`Landmark`/`AddressDetails` · `Latitude`/`Longitude` · `PropertyType`(residential/commercial) · `Ownership`(owned/rent) · `PhotoPath` · `Notes` · timestamps.

### 2) `PropertyResident` — ربط المواطن (إعادة استخدام Citizen)
`Id` · `PropertyId`(FK) · **`CitizenId`(FK → Citizen الموجود)** · `Relationship`(Owner/Tenant/Resident) · `IsPrimary` · timestamps. (عقار قد يضمّ أكثر من مواطن؛ مواطن قد يرتبط بأكثر من عقار.)

### 3) `PropertyService` — موصّل الخدمة العام (قابل للتوسّع)
`Id` · `PropertyId`(FK) · **`ServiceType`**(enum: Internet/Master/Iptv/Other — أو FK لكتالوج `Service` الموجود) · `ProviderType`(Sas/Ftth/External) · `ProviderRefId`(نصّي: SasAccountId+Uid للإنترنت-ساز، أو CitizenSubscriptionId لـFTTH، أو حرّ لماستر) · `SubscriberRef` · `Status`(Active/Suspended/Ended) · `StartDate`/`EndDate` · `Notes` · timestamps.
> إضافة خدمة جديدة (ماستر…) = صفّ `ServiceType` جديد، **بلا إعادة هيكلة**.

### 4) `PropertyNpnCounter` — تخصيص NPN الذرّي
`GovCode`(PK) · `LastSeq`. التخصيص داخل معاملة قاعدة (row-lock) بدل قفل الذاكرة (أدقّ في بيئة متعدّدة العمليات).

---

## تصميم الـQR (دائم، محايد)
- `QrToken` = رمز فريد دائم (مثل Base32 لـGuid، أو NPN نفسه). يُشفَّر في الـQR كـ`SADARA|P:<QrToken>`.
- **لا يحمل الـQR بيانات خدمة** (تتغيّر) — يشير للعقار فقط.
- حلّ الـQR: `GET /api/properties/by-qr/{token}` → العقار + المواطنون + كل الخدمات (لقطة حيّة). دائم مهما تغيّرت الخدمات.

---

## نقاط النهاية (بوّابة .NET — معزولة بالشركة + صلاحية)
- `Property`: `POST/GET/PUT/DELETE /api/properties` + `GET /api/properties/by-qr/{token}` + رفع صورة.
- تخصيص NPN ذرّي (معاملة) لكل محافظة.
- `Residents`: `POST/DELETE /api/properties/{id}/residents` (ربط/فكّ مواطن).
- `Services`: `POST/PUT/DELETE /api/properties/{id}/services` (إضافة/تعديل/إنهاء خدمة؛ الإنترنت-ساز يربط حساب ساز+uid).
- صلاحية جديدة `property_registry` (مسجّلة، قابلة للمنح عبر HR مثل بقية الخدمات).

---

## واجهة Flutter
- شاشات سجل العقارات (قائمة/تفاصيل/نموذج) — تُرفع من واجهة الساز الحالية لكن تنادي بوّابة النواة `/api/properties/*`.
- تفاصيل العقار = **QR + NPN + المواطنون (Citizen) + الخدمات** (إنترنت/ماستر…) مع تدفّق «إضافة خدمة».
- **مسح QR** → حلّ → لوحة العقار (المواطن + كل خدماته + حالتها).

---

## الهجرة من النظام الحالي (عقارات الساز في SQLite)
استيراد لمرّة واحدة: عقارات الساز (sidecar) → `Property` في النواة؛ و`premises_subscribers` (ربط إنترنت-ساز) → `PropertyService{ServiceType=Internet, ProviderType=Sas}`. مع إبقاء النظام الحالي عاملاً أثناء الانتقال.

---

## الخطة المرحلية
| مرحلة | المحتوى | المالك |
|------|---------|--------|
| **م1** | كيانات النواة (`Property`/`Resident`/`Service`/`NpnCounter`) + migration + CRUD العقار + تخصيص NPN + QrToken + حلّ QR | database + backend |
| **م2** | ربط المواطن (Citizen) + موصّل الخدمة (إنترنت-ساز) + صلاحية `property_registry` | backend + security |
| **م3** | واجهة Flutter (قائمة/تفاصيل/نموذج + QR + إضافة خدمة + مسح QR) + طباعة لصاقة | sas-flutter-ui |
| **م4** | «ماستر» وأي خدمة (توسّع ServiceType) + هجرة بيانات الساز + ربط بنظام المهام (توجيه فني لعقار) + المحاسبة | backend + flutter |

> موافقات: كيانات/هجرات ⇒ database-postgres-agent؛ صلاحية جديدة ⇒ security-auditor؛ تغيير معماري ⇒ architecture-evolution. نشر عبر `deploy/deploy-backend.sh` + إصدار تطبيق.
