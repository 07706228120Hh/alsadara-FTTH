# خطة: نظام الساس محاسبي كامل (على نمط FTTH)

> توسيع وحدة وكيل الساس لتصبح نظاماً محاسبياً كاملاً: تسعير باقات + أرباح · تسجيل آجل بذمم مواطنين · مزامنة عند الطلب/العملية · حقول مواطن موسّعة. القرارات محسومة (أكتوبر 2026).

## القرارات المعتمدة
- **التسعير/الأرباح**: جدول أسعار لكل باقة (كلفة + سعر بيع → ربح)، يُدار من واجهة — كـ FTTH `InternetPlans`.
- **الآجل**: دفتر ذمم مواطنين كامل (ذمة لكل مواطن + كشف حساب + تسديدات + رصيد مستحق).
- **المزامنة**: عند دخول التبويب + زر تحديث + **بعد كل عملية** → تحديث كل شيء (مشتركون + حسابات). لا خدمة خلفية دائمة.
- **حقول المواطن الإضافية (~11)**: 
  - هوية: `NationalId` · `FullNameQuad` · `BirthDate` · `Gender`
  - تواصل: `AltPhone` · `WhatsappNumber` · `Email`
  - موقع/عقار: `AddressDetail` · `Latitude` · `Longitude` · `PropertyType` · `Landmark`

---

## المراحل

### المرحلة 1 — الأساس (نموذج البيانات) ⬅️ نبدأ بها
1. **كيان `SasPackagePrice`** (Postgres، ITenantScoped): `CompanyId, SasAccountId?, ProfileId, ProfileName, Cost, SellingPrice, IsActive, Notes, timestamps`. فهرس فريد (CompanyId+SasAccountId+ProfileId). الربح = `SellingPrice − Cost`.
2. **كيان `SasSubscriberProfile`** (Postgres): `CompanyId, SasAccountId, SubscriberUid, SubscriberUsername` + الحقول الـ11 أعلاه + timestamps. فهرس فريد (CompanyId+SasAccountId+SubscriberUid). **منفصل عن `local_subscribers`** (يبقى عبر المزامنة؛ بيانات أدخلها الوكيل لا SAS4).
3. **Migration** إضافي (جدولان) — توليد فقط، لا تطبيق على الإنتاج.
4. نقاط CRUD: 
   - `GET/PUT /api/sas-agent/accounts/{id}/package-prices` (قائمة + تحديث؛ auto-populate من `getPackages`).
   - `GET/PUT /api/sas-agent/accounts/{id}/users/{uid}/profile` (جلب/حفظ حقول المواطن).

### المرحلة 2 — الفوترة بالتسعير والأرباح
- `activate-billed` يقرأ `SasPackagePrice` للباقة: `BasePrice=Cost`، `revenue=SellingPrice−Cost` (ربح)، `collected=SellingPrice` (+صيانة/خصم اختياري). القيد: مدين تحصيل = دائن رصيد الصفحة(Cost) + إيراد ربح(SellingPrice−Cost).
- تبويب «نظام الساس» في الحسابات: إضافة **الأرباح** (إجمالي/حسب الباقة/حسب الوكيل).

### المرحلة 3 — التسجيل الآجل (دفتر ذمم المواطنين)
- نوع تحصيل `citizen` (آجل): القيد يدين **ذمة المواطن** (حساب فرعي تحت «ذمم المواطنين» عبر `FindOrCreateSubAccount` بمفتاح SubscriberUid) بدل الصندوق.
- **كشف حساب المواطن**: قائمة شحنات + تسديدات + رصيد مستحق.
- نقطة **تسديد**: `POST citizen-payment` (يدين الصندوق، يدائن ذمة المواطن) + حركة.
- واجهة: كشف المواطن + زر تسديد + قائمة المدينين.

### المرحلة 4 — المزامنة عند الطلب/العملية
- واجهة: عند دخول تبويبات الساس/الحسابات + زر تحديث + **بعد كل عملية مفوترة** → `syncAccount` (سحب SAS4→محلي) ثم إعادة تحميل كل شيء (ملخّص + مشتركون + حسابات الساس + كشوف).
- مؤشّر «آخر مزامنة» + منع تكرار المزامنة المتزامنة.

### المرحلة 5 — واجهة الإدارة + التقارير
- صفحة «أسعار الباقات» (إدارة الكلفة/سعر البيع لكل باقة).
- نموذج «معلومات المواطن الموسّعة» في صفحة تفاصيل المشترك.
- تقارير: الأرباح · الذمم (المدينون) · المحصّل حسب النوع.

### المرحلة 6 — اختبارات + تحقّق + تحديث قائمة النشر.

---

## ملاحظات معمارية
- كل الكيانات الجديدة في Postgres (الصدارة) — تتكامل مع المحاسبة الموحّدة (`SubscriptionLog`/`JournalEntry`) والذمم.
- العزل: CompanyId + ملكية الحساب (نمط `GetOwnedAccountAsync`).
- `SasSubscriberProfile` منفصل عن `local_subscribers` ليبقى عبر المزامنة.
- التسعير يغذّي الفوترة؛ الفوترة تغذّي المحاسبة؛ الذمم فرع من المحاسبة — سلسلة واحدة.
- قبل الإنتاج: راجع `PRE_DEPLOY_CHECKLIST.md` (migrations + علامات isProduction + حذف SasDevController).
