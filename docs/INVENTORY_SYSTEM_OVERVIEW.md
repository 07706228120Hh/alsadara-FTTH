# نظام المخزون — نظرة عامة ومرجع تسليم

> مرجع تسليم موجز لنظام المخزون في منصة الصدارة. محدَّث حتى **v2.4.31** (2026-10-30).
> افتح به أي محادثة/مهمة تخص المخزون. اقرأ معه دائماً `CLAUDE.md` (القواعد الذهبية).

## الغرض
نظام مخزون/مبيعات/مشتريات متكامل داخل تطبيق الصدارة `alsadara-ftth`: مستودعات، مواد،
عملاء/موردون، فواتير بيع وشراء، صرف للفنيين من العُهدة، سندات قبض/صرف، مرتجعات، تقارير،
وربط محاسبي. multi-tenant مع عزل بـ `CompanyId` من التوكن.

## المعمارية
- **باكند** (.NET 9 Clean Architecture): كل المنطق في ملف واحد ضخم
  `src/Backend/API/Sadara.API/Controllers/InventoryController.cs` (~5445 سطراً).
  - الكيانات: `src/Backend/Core/Sadara.Domain/Entities/Inventory.cs`
  - منطق التسعير: `src/Backend/Core/Sadara.Application/Inventory/PricingCalculator.cs`
  - سياق EF: `src/Backend/Core/Sadara.Infrastructure/Data/SadaraDbContext.cs`
- **واجهة** (Flutter): `src/Apps/CompanyDesktop/alsadara-ftth/lib/inventory/`
  - نقطة الدخول: `inventory_page.dart` · الصفحات: `pages/` · الموديلات: `models/inventory_models.dart`
  - طبقة الاتصال: `services/inventory_api_service.dart`
  - إطار موحّد: `widgets/inv_frame.dart` (`InvCard`) · تنسيق: `utils/format_utils.dart`

## الكيانات (19)
`Warehouse` · `InventoryCategory` · `InventoryItem` · `InventoryCustomer` · `Supplier` ·
`PurchaseOrder/Item` · `SalesOrder/Item` · `TechnicianDispensing/Item` · `StockMovement` ·
`WarehouseStock` · `Invoice/Item` · `PaymentVoucher` · `ReturnOrder/Item` · `InventoryAccountMapping`.

نقاط مهمة:
- **`InventoryItem`**: `CostPrice` (كلفة) · `SellingPrice` (مفرد) · `WholesalePrice` (جملة) ·
  `BulkWholesalePrice` (جملة الجملة) + 3 هوامش%: `RetailMarginPercent` / `WholesaleMarginPercent` /
  `BulkWholesaleMarginPercent`.
- **`InventoryCustomer`**: `FullName` · `CustomerType` (نقدي=0 / آجل=1 / VIP=2 — نوع **دفع**) ·
  `PriceTier` (مفرد=0 / جملة=1 / جملة الجملة=2 — **شريحة سعر**، منفصلة عن نوع الدفع) · `CreditLimit`.
- **`WarehouseStock.AverageCost`**: المتوسط المرجّح للكلفة لكل (مستودع + مادة) = أساس COGS / CostAtSale.

## ميزة شرائح التسعير (الأحدث — v2.4.31)
- لكل مادة 3 أسعار + هامش% اختياري لكل شريحة. **هامش موجود ⇒**
  `السعر = round(الكلفة × (1 + الهامش/100), 2, AwayFromZero)` ويُعاد حسابه عند تغيّر الكلفة.
  لا هامش ⇒ سعر يدوي ثابت. المنطق: `PricingCalculator.RecomputeTierPrices`.
- **ربط الشراء بالكلفة** (3 نقاط تضبط `CostPrice = UnitPrice` ثم تعيد الاشتقاق):
  `CreatePurchaseOrder` · `ReceivePurchaseOrder` (`purchases/{id}/receive`) ·
  فرع الشراء في `ConfirmInvoice` (`invoices/{id}/confirm`).
- **البيع**: `invoice_form_page.dart` يملأ السعر حسب `PriceTier` للعميل المختار (ويُعاد عند تبديله)
  مع السماح بالتعديل اليدوي.
- **أساس الكلفة للاشتقاق = آخر سعر شراء** (قرار المالك)؛ بينما COGS يبقى المتوسط المرجّح.
  ⚠️ تأكيد محاسبي معلّق.

## عقد الـAPI (حاسم للواجهة)
- الباكند يُرجع **PascalCase** (`PropertyNamingPolicy = null`). الواجهة تقرأ عبر helper `_v(map, key)`
  الذي يجرّب `Pascal` ثم `camel`. الإدخال **case-insensitive** (يقبل camelCase).
- النجاح: `{ success: true, data, total? }` · الفشل: `{ success: false, message: "عربي" }` بكود HTTP صحيح.
- ⚠️ **مصائد عقد متكرّرة**:
  - العميل يُقرأ في الواجهة بمفتاح `name` بينما الكيان `FullName` — حُلّ بمرادف باكند
    `Name = FullName` في `GetCustomers` / `GetCustomerDetails`.
  - أي `decimal` **غير قابل للnull** في Create DTO يفشل إن أرسلت الواجهة `null`
    (حدث مع `CreditLimit` للعميل النقدي — صار `decimal?` مع `?? 0`).

## مجموعات نقاط الـAPI (البادئة `/api/inventory`)
warehouses · categories · items (+`items/low-stock`) · suppliers ·
purchases (+approve / receive / cancel) · sales (+confirm / cancel) ·
dispensing (+approve / return / use-from-holdings / technician) · stock (+adjust / transfer) ·
movements · **reports** (summary / valuation / technician-holdings / profit-loss / customer-aging /
supplier-aging / top-selling / slow-moving / item-ledger / daily-sales) · accounts/mappings ·
customers (+statement) · invoices (+confirm / cancel) · vouchers · returns (+confirm / cancel).

## حالة النشر
- **منشور على الإنتاج** (72.61.183.61): كل باكند المخزون + ميزة التسعير + الهجرة
  `AddInventoryPriceTiers`. التطبيق v2.4.31 Latest على كل الأجهزة.
- الفرع `release/v2.4.31`. تراجع التطبيق: `gh release edit v2.4.30 --latest`.

## ديون/مخاطر معروفة (لم تُعالَج)
1. **عزل P2 (الأهم)**: `UpdateItem` / `UpdateCustomer` / `GetCustomerDetails` تحمّل بالـId بلا فلتر
   `CompanyId`؛ نقاط الشراء بلا حارس token-vs-CompanyId على الكيان الأب. المرجع الصحيح للحارس:
   `TechnicianDispensing` (~سطر 2664+). أي تغيير يمرّ على security-auditor + database-postgres.
2. تأكيد محاسبي لأساس الكلفة (آخر شراء) مقابل COGS (متوسط مرجّح).
3. لا اختبارات وحدة لـ `PricingCalculator`.
4. `use-from-holdings` كان معطّلاً سابقاً وأُصلح؛ تحقّق تشغيلي مستحسن.

## ملفات للقراءة أولاً
`InventoryController.cs` · `Inventory.cs` · `PricingCalculator.cs` ·
`lib/inventory/pages/{materials,customer_form,invoice_form}_page.dart` ·
`lib/inventory/services/inventory_api_service.dart` · `CLAUDE.md`.

## قواعد إلزامية (من CLAUDE.md)
- لا نشر إنتاج / لا push / لا رفع tag `v*` / لا هجرة إنتاج بلا **موافقة بشرية صريحة**.
- افلتر دائماً بـ `CompanyId` من التوكن، لا تثق بأي `companyId` من العميل.
- لا تعدّل/تحذف هجرة قائمة — أضف جديدة. الصلاحيات تُثبَّت صراحةً عند الحفظ.
