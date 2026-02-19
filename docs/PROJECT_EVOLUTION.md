# 📋 تطور مشروع منصة الصدارة
## Sadara Platform Evolution Plan

> 📅 تاريخ الإنشاء: 31 يناير 2026
> 📝 آخر تحديث: 31 يناير 2026

---

# 🗺️ خريطة المشروع الكاملة

```
┌─══════════════════════════════════════════════════════════════════════════════════════════════════════┐
│                                    🏗️ هيكلية المشروع الكاملة                                          │
└───────────────────────────────────────────────────────────────────────────────────────────────────────┘

                                    ┌─────────────────────────────┐
                                    │     🖥️ VPS Server           │
                                    │                             │
                                    │  ┌───────────────────────┐ │
                                    │  │  🗄️ PostgreSQL        │ │
                                    │  │  (قاعدة البيانات)     │ │
                                    │  └───────────────────────┘ │
                                    │            │               │
                                    │            ▼               │
                                    │  ┌───────────────────────┐ │
                                    │  │  🔷 .NET 9 API        │ │
                                    │  │  (Sadara.API)         │ │
                                    │  └───────────────────────┘ │
                                    │            │               │
                                    │            ▼               │
                                    │  ┌───────────────────────┐ │
                                    │  │  💳 بوابات الدفع      │ │
                                    │  │  ZainCash | FastPay   │ │
                                    │  │  Asia Hawala | NassPay│ │
                                    │  └───────────────────────┘ │
                                    └──────────────┬──────────────┘
                                                   │
                    ┌──────────────────────────────┼──────────────────────────────┐
                    │                              │                              │
                    ▼                              ▼                              ▼
     ┌──────────────────────────┐   ┌──────────────────────────┐   ┌──────────────────────────┐
     │  🌐 منصة الصدارة (ويب)   │   │  🏪 بوابة الوكيل (ويب)  │   │  🖥️ نظام الشركة         │
     │     sadara.iq            │   │   (نفس الموقع)          │   │    (Desktop)            │
     │                          │   │                          │   │                          │
     │  • Flutter Web           │   │  • Flutter Web           │   │  • Flutter Windows       │
     │  • PWA للموبايل          │   │                          │   │                          │
     └──────────────────────────┘   └──────────────────────────┘   └──────────────────────────┘
```

---

# 📊 المراحل التفصيلية

## 🔴 المرحلة 1: Backend (الأساس) - أسبوع 1-2

```
📁 src/Backend/Core/Sadara.Domain/Entities/

   ┌─────────────────────────────────────────────────────────────────────────────────┐
   │  📦 الكيانات الجديدة (Entities)                                                 │
   ├─────────────────────────────────────────────────────────────────────────────────┤
   │                                                                                 │
   │  1️⃣ Agents/ (الوكلاء)                                                          │
   │     ├── Agent.cs                  → بيانات الوكيل                              │
   │     ├── AgentBalanceRequest.cs    → طلبات الرصيد                               │
   │     ├── AgentSubscription.cs      → طلبات تفعيل المشتركين                       │
   │     ├── AgentTransaction.cs       → حركات الحساب                               │
   │     └── AgentPayment.cs           → سداد المديونية                             │
   │                                                                                 │
   │  2️⃣ Citizens/ (المواطنين)                                                       │
   │     ├── Citizen.cs                → بيانات المواطن (موجود)                      │
   │     ├── CitizenRequest.cs         → طلبات الخدمات                              │
   │     └── CitizenAddress.cs         → عناوين المواطن + GPS                       │
   │                                                                                 │
   │  3️⃣ Services/ (الخدمات)                                                        │
   │     ├── InternetService.cs        → خدمات الإنترنت                             │
   │     ├── MasterCardService.cs      → خدمة الماستر                               │
   │     └── ServicePackage.cs         → باقات الخدمات                              │
   │                                                                                 │
   │  4️⃣ Store/ (المتجر)                                                            │
   │     ├── Product.cs                → المنتجات                                   │
   │     ├── ProductCategory.cs        → تصنيفات المنتجات                           │
   │     ├── StoreOrder.cs             → طلبات المتجر                               │
   │     ├── OrderItem.cs              → عناصر الطلب                                │
   │     └── CartItem.cs               → سلة المشتريات                              │
   │                                                                                 │
   │  5️⃣ Tasks/ (المهام)                                                            │
   │     ├── ServiceTask.cs            → المهام (بديل Google Sheets)                │
   │     ├── TaskAssignment.cs         → تعيين المهام للفرق                         │
   │     ├── TaskAudit.cs              → تدقيق المهام                               │
   │     └── TaskStatusHistory.cs      → سجل الحالات                                │
   │                                                                                 │
   │  6️⃣ Payments/ (المدفوعات)                                                       │
   │     ├── Payment.cs                → المدفوعات (موجود)                          │
   │     ├── PaymentGateway.cs         → بوابات الدفع                               │
   │     ├── PaymentTransaction.cs     → معاملات الدفع                              │
   │     └── Wallet.cs                 → محفظة المستخدم                             │
   │                                                                                 │
   │  7️⃣ Technicians/ (الفنيين)                                                     │
   │     ├── Technician.cs             → بيانات الفني                               │
   │     └── TechnicianLocation.cs     → موقع الفني (GPS متحرك)                     │
   │                                                                                 │
   └─────────────────────────────────────────────────────────────────────────────────┘

📁 src/Backend/API/Sadara.API/Controllers/

   ┌─────────────────────────────────────────────────────────────────────────────────┐
   │  🎮 Controllers الجديدة                                                         │
   ├─────────────────────────────────────────────────────────────────────────────────┤
   │                                                                                 │
   │  • AgentsController.cs            → إدارة الوكلاء                              │
   │  • AgentAuthController.cs         → تسجيل دخول الوكيل                          │
   │  • AgentBalanceController.cs      → طلبات الرصيد                               │
   │  • AgentSubscriptionsController.cs→ تفعيل المشتركين                            │
   │                                                                                 │
   │  • CitizenRequestsController.cs   → طلبات المواطن                              │
   │  • CitizenAuthController.cs       → تسجيل دخول المواطن                         │
   │                                                                                 │
   │  • InternetServicesController.cs  → خدمات الإنترنت                             │
   │  • MasterCardController.cs        → خدمة الماستر                               │
   │                                                                                 │
   │  • StoreController.cs             → المتجر الإلكتروني                          │
   │  • ProductsController.cs          → المنتجات                                   │
   │  • CartController.cs              → سلة المشتريات                              │
   │  • StoreOrdersController.cs       → طلبات المتجر                               │
   │                                                                                 │
   │  • TasksController.cs             → نظام المهام                                │
   │  • TaskAuditController.cs         → التدقيق والمتابعة                          │
   │  • TechniciansController.cs       → إدارة الفنيين                              │
   │                                                                                 │
   │  • PaymentGatewayController.cs    → بوابات الدفع                               │
   │  • WalletController.cs            → المحافظ الإلكترونية                        │
   │                                                                                 │
   └─────────────────────────────────────────────────────────────────────────────────┘
```

---

## 🟠 المرحلة 2: منصة الويب (المواطن + الوكيل) - أسبوع 2-4

```
📁 src/Apps/CitizenWeb/lib/

   ┌─────────────────────────────────────────────────────────────────────────────────┐
   │  🌐 هيكلية منصة الويب                                                           │
   ├─────────────────────────────────────────────────────────────────────────────────┤
   │                                                                                 │
   │  lib/                                                                           │
   │  ├── main.dart                    → نقطة البداية                               │
   │  │                                                                             │
   │  ├── config/                                                                   │
   │  │   ├── router.dart              → التوجيه                                    │
   │  │   ├── api_config.dart          → إعدادات API                                │
   │  │   └── theme.dart               → الثيم (الألوان والخطوط)                    │
   │  │                                                                             │
   │  ├── models/                                                                   │
   │  │   ├── citizen.dart             → نموذج المواطن                              │
   │  │   ├── agent.dart               → نموذج الوكيل                               │
   │  │   ├── service_request.dart     → طلب الخدمة                                 │
   │  │   ├── product.dart             → المنتج                                     │
   │  │   ├── cart_item.dart           → عنصر السلة                                 │
   │  │   └── payment.dart             → الدفع                                      │
   │  │                                                                             │
   │  ├── services/                                                                 │
   │  │   ├── api_service.dart         → خدمة الاتصال بـ API                        │
   │  │   ├── auth_service.dart        → المصادقة                                   │
   │  │   ├── location_service.dart    → خدمة الموقع GPS                            │
   │  │   └── payment_service.dart     → خدمة الدفع                                 │
   │  │                                                                             │
   │  ├── providers/                                                                │
   │  │   ├── auth_provider.dart       → حالة المصادقة                              │
   │  │   ├── cart_provider.dart       → حالة السلة                                 │
   │  │   └── location_provider.dart   → حالة الموقع                                │
   │  │                                                                             │
   │  └── pages/                                                                    │
   │      │                                                                         │
   │      ├── 🏠 home/                                                              │
   │      │   ├── landing_page.dart    → الصفحة الرئيسية (معلومات الشركة)           │
   │      │   └── company_info.dart    → معلومات ومواقع الشركة                       │
   │      │                                                                         │
   │      ├── 🔐 auth/                                                              │
   │      │   ├── login_selector.dart  → اختيار (مواطن أو وكيل)                     │
   │      │   ├── citizen_login.dart   → تسجيل دخول المواطن                         │
   │      │   ├── citizen_register.dart→ تسجيل مواطن جديد                          │
   │      │   ├── agent_login.dart     → تسجيل دخول الوكيل                          │
   │      │   └── verify_otp.dart      → التحقق من رقم الهاتف                       │
   │      │                                                                         │
   │      ├── 👤 citizen/              (بوابة المواطن)                              │
   │      │   ├── citizen_dashboard.dart → لوحة تحكم المواطن                        │
   │      │   ├── my_requests.dart     → طلباتي                                     │
   │      │   ├── track_technician.dart→ تتبع الفني                                 │
   │      │   │                                                                     │
   │      │   ├── internet/            (خدمات الإنترنت)                             │
   │      │   │   ├── internet_services.dart → قائمة خدمات الإنترنت                │
   │      │   │   ├── maintenance_request.dart → طلب صيانة                         │
   │      │   │   ├── renewal_request.dart → تجديد اشتراك                          │
   │      │   │   ├── upgrade_request.dart → ترقية الباقة                          │
   │      │   │   └── new_subscription.dart → اشتراك جديد                          │
   │      │   │                                                                     │
   │      │   ├── master/              (خدمة الماستر)                               │
   │      │   │   ├── master_services.dart → قائمة خدمات الماستر                   │
   │      │   │   ├── recharge_request.dart → طلب شحن رصيد                         │
   │      │   │   ├── new_card_request.dart → طلب بطاقة جديدة                      │
   │      │   │   └── delivery_request.dart → طلب توصيل                            │
   │      │   │                                                                     │
   │      │   └── store/               (المتجر الإلكتروني)                          │
   │      │       ├── store_home.dart  → الصفحة الرئيسية للمتجر                     │
   │      │       ├── products_list.dart → قائمة المنتجات                          │
   │      │       ├── product_details.dart → تفاصيل المنتج                         │
   │      │       ├── cart_page.dart   → سلة المشتريات                             │
   │      │       └── checkout_page.dart → إتمام الطلب والدفع                      │
   │      │                                                                         │
   │      ├── 🏪 agent/                (بوابة الوكيل)                               │
   │      │   ├── agent_dashboard.dart → لوحة تحكم الوكيل                          │
   │      │   ├── agent_profile.dart   → معلومات الوكيل                            │
   │      │   ├── balance_request.dart → طلب رصيد                                  │
   │      │   ├── activate_subscriber.dart → تفعيل مشترك                           │
   │      │   ├── my_transactions.dart → حركاتي المالية                            │
   │      │   ├── my_debt.dart         → مديونيتي                                  │
   │      │   └── pay_debt.dart        → سداد الدين                                │
   │      │                                                                         │
   │      └── 💳 payment/              (الدفع الإلكتروني)                           │
   │          ├── payment_methods.dart → طرق الدفع المتاحة                         │
   │          ├── zaincash_payment.dart→ دفع ZainCash                              │
   │          ├── fastpay_payment.dart → دفع FastPay                               │
   │          ├── asiahawala_payment.dart → دفع Asia Hawala                        │
   │          └── payment_success.dart → نجاح الدفع                                │
   │                                                                                 │
   └─────────────────────────────────────────────────────────────────────────────────┘
```

---

## 🟡 المرحلة 3: نظام الشركة (Desktop) - أسبوع 4-5

```
📁 src/Apps/CompanyDesktop/alsadara-ftth/lib/

   ┌─────────────────────────────────────────────────────────────────────────────────┐
   │  📂 الصفحات الجديدة                                                             │
   ├─────────────────────────────────────────────────────────────────────────────────┤
   │                                                                                 │
   │  pages/                                                                         │
   │  │                                                                             │
   │  ├── 🏪 agents_management/        (إدارة الوكلاء)                               │
   │  │   ├── agents_list_page.dart    → قائمة الوكلاء                              │
   │  │   ├── agent_details_page.dart  → تفاصيل الوكيل                              │
   │  │   ├── add_agent_page.dart      → إضافة وكيل جديد                            │
   │  │   ├── balance_requests_page.dart → طلبات الرصيد                             │
   │  │   ├── subscription_requests_page.dart → طلبات التفعيل                       │
   │  │   ├── agent_transactions_page.dart → حركات الوكيل                           │
   │  │   └── agent_payments_page.dart → سداد المديونيات                            │
   │  │                                                                             │
   │  ├── 👤 citizen_requests/         (طلبات المواطنين)                            │
   │  │   ├── all_requests_page.dart   → جميع الطلبات                              │
   │  │   ├── internet_requests_page.dart → طلبات الإنترنت                         │
   │  │   ├── master_requests_page.dart → طلبات الماستر                            │
   │  │   ├── store_orders_page.dart   → طلبات المتجر                              │
   │  │   └── convert_to_task_dialog.dart → تحويل لمهمة                            │
   │  │                                                                             │
   │  ├── 📋 tasks_management/         (إدارة المهام - بديل Google Sheets)          │
   │  │   ├── tasks_dashboard.dart     → لوحة المهام                                │
   │  │   ├── tasks_by_status.dart     → المهام حسب الحالة                          │
   │  │   ├── tasks_by_team.dart       → المهام حسب الفريق                          │
   │  │   ├── add_task_page.dart       → إضافة مهمة                                 │
   │  │   ├── task_details_page.dart   → تفاصيل المهمة                              │
   │  │   └── assign_task_dialog.dart  → تعيين المهمة                               │
   │  │                                                                             │
   │  ├── 📞 audit/                    (التدقيق والمتابعة)                          │
   │  │   ├── audit_dashboard.dart     → لوحة التدقيق                               │
   │  │   ├── pending_audit_page.dart  → مهام بانتظار التدقيق                       │
   │  │   ├── audit_form.dart          → نموذج التدقيق                              │
   │  │   └── audit_reports_page.dart  → تقارير التدقيق                             │
   │  │                                                                             │
   │  ├── 🛒 store_management/         (إدارة المتجر)                               │
   │  │   ├── products_page.dart       → إدارة المنتجات                             │
   │  │   ├── add_product_page.dart    → إضافة منتج                                 │
   │  │   ├── categories_page.dart     → التصنيفات                                  │
   │  │   ├── store_orders_page.dart   → طلبات المتجر                               │
   │  │   └── inventory_page.dart      → المخزون                                    │
   │  │                                                                             │
   │  ├── 💳 payments_management/      (إدارة المدفوعات)                            │
   │  │   ├── payments_dashboard.dart  → لوحة المدفوعات                             │
   │  │   ├── payment_transactions.dart→ المعاملات                                  │
   │  │   └── payment_reports.dart     → تقارير المدفوعات                           │
   │  │                                                                             │
   │  └── 📊 reports/                  (التقارير)                                   │
   │      ├── agents_reports.dart      → تقارير الوكلاء                             │
   │      ├── citizens_reports.dart    → تقارير المواطنين                           │
   │      ├── tasks_reports.dart       → تقارير المهام                              │
   │      ├── financial_reports.dart   → التقارير المالية                           │
   │      └── performance_reports.dart → تقارير الأداء (الفنيين)                    │
   │                                                                                 │
   └─────────────────────────────────────────────────────────────────────────────────┘
```

---

## 🟢 المرحلة 4: بوابات الدفع - أسبوع 5-6

```
   ┌─────────────────────────────────────────────────────────────────────────────────┐
   │  💳 بوابات الدفع المدعومة                                                       │
   ├─────────────────────────────────────────────────────────────────────────────────┤
   │                                                                                 │
   │  ┌───────────────┐  ┌───────────────┐  ┌───────────────┐  ┌───────────────┐   │
   │  │   ZainCash    │  │   FastPay     │  │ Asia Hawala   │  │   NassPay     │   │
   │  │               │  │               │  │               │  │               │   │
   │  │  📱 محفظة     │  │  📱 محفظة     │  │  🏦 حوالة     │  │  💳 بطاقات   │   │
   │  │  زين كاش     │  │  فاست باي    │  │  آسيا         │  │  ناس باي     │   │
   │  └───────────────┘  └───────────────┘  └───────────────┘  └───────────────┘   │
   │                                                                                 │
   │  الاستخدامات:                                                                  │
   │  ├── 👤 المواطن يدفع:                                                          │
   │  │   • تجديد اشتراك الإنترنت                                                  │
   │  │   • شراء من المتجر                                                         │
   │  │   • شحن رصيد الماستر                                                       │
   │  │                                                                             │
   │  └── 🏪 الوكيل يدفع:                                                           │
   │      • سداد المديونية                                                          │
   │      • شراء رصيد مسبق                                                          │
   │                                                                                 │
   └─────────────────────────────────────────────────────────────────────────────────┘

📁 Backend - Payment Gateway Integration

   src/Backend/Core/Sadara.Infrastructure/Services/Payments/
   │
   ├── IPaymentGateway.cs              → واجهة بوابة الدفع
   ├── PaymentGatewayFactory.cs        → مصنع البوابات
   │
   ├── ZainCash/
   │   ├── ZainCashService.cs          → خدمة ZainCash
   │   ├── ZainCashModels.cs           → النماذج
   │   └── ZainCashConfig.cs           → الإعدادات
   │
   ├── FastPay/
   │   ├── FastPayService.cs           → خدمة FastPay
   │   ├── FastPayModels.cs            → النماذج
   │   └── FastPayConfig.cs            → الإعدادات
   │
   ├── AsiaHawala/
   │   ├── AsiaHawalaService.cs        → خدمة Asia Hawala
   │   └── AsiaHawalaModels.cs         → النماذج
   │
   └── NassPay/
       ├── NassPayService.cs           → خدمة NassPay
       └── NassPayModels.cs            → النماذج
```

---

## 🔵 المرحلة 5: الاختبار والنشر - أسبوع 6-7

```
   ┌─────────────────────────────────────────────────────────────────────────────────┐
   │  ✅ قائمة الاختبار                                                              │
   ├─────────────────────────────────────────────────────────────────────────────────┤
   │                                                                                 │
   │  1️⃣ اختبار API:                                                                │
   │     □ جميع Controllers تعمل                                                    │
   │     □ المصادقة والصلاحيات                                                      │
   │     □ بوابات الدفع                                                             │
   │                                                                                 │
   │  2️⃣ اختبار منصة الويب:                                                         │
   │     □ تسجيل وتسجيل دخول المواطن                                               │
   │     □ تسجيل دخول الوكيل                                                       │
   │     □ جميع الخدمات (إنترنت، ماستر، متجر)                                      │
   │     □ الدفع الإلكتروني                                                        │
   │     □ تتبع الفني GPS                                                          │
   │                                                                                 │
   │  3️⃣ اختبار نظام الشركة:                                                        │
   │     □ إدارة الوكلاء                                                           │
   │     □ إدارة طلبات المواطنين                                                   │
   │     □ نظام المهام                                                             │
   │     □ التدقيق والمتابعة                                                       │
   │                                                                                 │
   └─────────────────────────────────────────────────────────────────────────────────┘

   ┌─────────────────────────────────────────────────────────────────────────────────┐
   │  🚀 النشر                                                                       │
   ├─────────────────────────────────────────────────────────────────────────────────┤
   │                                                                                 │
   │  VPS Setup:                                                                     │
   │  ├── PostgreSQL Database                                                        │
   │  ├── .NET 9 API (Docker)                                                        │
   │  ├── Nginx (Reverse Proxy + SSL)                                                │
   │  └── Flutter Web (Static Files)                                                 │
   │                                                                                 │
   │  Domains:                                                                       │
   │  ├── api.sadara.iq        → Backend API                                         │
   │  ├── sadara.iq            → منصة الويب                                          │
   │  └── admin.sadara.iq      → (اختياري) لوحة تحكم ويب                             │
   │                                                                                 │
   └─────────────────────────────────────────────────────────────────────────────────┘
```

---

# 📊 قاعدة البيانات (PostgreSQL)

```sql
-- ═══════════════════════════════════════════════════════════════════════════
--                         📊 جداول قاعدة البيانات الكاملة
-- ═══════════════════════════════════════════════════════════════════════════

-- 🏪 الوكلاء
CREATE TABLE Agents (
    Id UUID PRIMARY KEY,
    Code VARCHAR(20) UNIQUE,      -- كود الوكيل
    Name VARCHAR(200),
    Phone VARCHAR(20) UNIQUE,
    PasswordHash VARCHAR(500),
    Province VARCHAR(100),        -- المحافظة
    City VARCHAR(100),            -- المدينة
    Address TEXT,
    PageId VARCHAR(100),          -- معرف صفحة الفيسبوك
    AvailableBalance DECIMAL(15,2) DEFAULT 0,
    TotalDebt DECIMAL(15,2) DEFAULT 0,
    CompanyId UUID REFERENCES Companies(Id),
    IsActive BOOLEAN DEFAULT TRUE,
    CreatedAt TIMESTAMP DEFAULT NOW()
);

-- 💰 طلبات رصيد الوكيل
CREATE TABLE AgentBalanceRequests (
    Id UUID PRIMARY KEY,
    AgentId UUID REFERENCES Agents(Id),
    Amount DECIMAL(15,2),
    Status VARCHAR(50),           -- new | approved | rejected | in_progress | completed
    Notes TEXT,
    RequestedAt TIMESTAMP DEFAULT NOW(),
    ApprovedAt TIMESTAMP,
    ApprovedBy UUID,
    CompletedAt TIMESTAMP,
    CompanyId UUID REFERENCES Companies(Id)
);

-- 📱 طلبات تفعيل المشتركين
CREATE TABLE AgentSubscriptions (
    Id UUID PRIMARY KEY,
    AgentId UUID REFERENCES Agents(Id),
    SubscriberPhone VARCHAR(20),
    SubscriberName VARCHAR(200),
    PackageType VARCHAR(50),      -- 10MB | 20MB | 50MB | 100MB
    MonthsCount INT,
    Amount DECIMAL(15,2),
    Status VARCHAR(50),
    RequestedAt TIMESTAMP DEFAULT NOW(),
    ApprovedAt TIMESTAMP,
    CompletedAt TIMESTAMP,
    CompanyId UUID REFERENCES Companies(Id)
);

-- 💳 حركات الوكيل
CREATE TABLE AgentTransactions (
    Id UUID PRIMARY KEY,
    AgentId UUID REFERENCES Agents(Id),
    Type VARCHAR(50),             -- credit | debit | payment
    Amount DECIMAL(15,2),
    BalanceBefore DECIMAL(15,2),
    BalanceAfter DECIMAL(15,2),
    DebtBefore DECIMAL(15,2),
    DebtAfter DECIMAL(15,2),
    Description TEXT,
    RelatedRequestId UUID,
    CreatedAt TIMESTAMP DEFAULT NOW(),
    CreatedBy UUID
);

-- 👤 طلبات المواطن
CREATE TABLE CitizenRequests (
    Id UUID PRIMARY KEY,
    CitizenId UUID REFERENCES Citizens(Id),
    ServiceType VARCHAR(50),      -- internet | master | store
    RequestType VARCHAR(100),     -- maintenance | renewal | upgrade | recharge | delivery
    Description TEXT,
    Status VARCHAR(50),           -- new | assigned | in_progress | completed | audited
    
    -- الموقع
    Latitude DECIMAL(10,8),
    Longitude DECIMAL(11,8),
    Address TEXT,
    
    -- التعيين
    AssignedTeam VARCHAR(50),
    AssignedTo UUID,
    ConvertedToTaskId UUID,
    
    -- التدقيق
    AuditStatus VARCHAR(50),
    AuditedBy UUID,
    AuditedAt TIMESTAMP,
    CitizenRating INT,
    AuditorNotes TEXT,
    HasComplaint BOOLEAN DEFAULT FALSE,
    
    CompanyId UUID REFERENCES Companies(Id),
    RequestedAt TIMESTAMP DEFAULT NOW(),
    CompletedAt TIMESTAMP
);

-- 🛒 منتجات المتجر
CREATE TABLE Products (
    Id UUID PRIMARY KEY,
    Name VARCHAR(200),
    Description TEXT,
    CategoryId UUID REFERENCES ProductCategories(Id),
    Price DECIMAL(15,2),
    DiscountPrice DECIMAL(15,2),
    Stock INT DEFAULT 0,
    ImageUrl VARCHAR(500),
    IsActive BOOLEAN DEFAULT TRUE,
    CompanyId UUID REFERENCES Companies(Id),
    CreatedAt TIMESTAMP DEFAULT NOW()
);

-- 📦 طلبات المتجر
CREATE TABLE StoreOrders (
    Id UUID PRIMARY KEY,
    CitizenId UUID REFERENCES Citizens(Id),
    TotalAmount DECIMAL(15,2),
    Status VARCHAR(50),           -- pending | confirmed | shipped | delivered | cancelled
    ShippingAddress TEXT,
    Latitude DECIMAL(10,8),
    Longitude DECIMAL(11,8),
    PaymentStatus VARCHAR(50),
    PaymentMethod VARCHAR(50),
    PaymentTransactionId UUID,
    CompanyId UUID REFERENCES Companies(Id),
    OrderedAt TIMESTAMP DEFAULT NOW(),
    DeliveredAt TIMESTAMP
);

-- 📋 المهام (بديل Google Sheets)
CREATE TABLE ServiceTasks (
    Id UUID PRIMARY KEY,
    Title VARCHAR(200),
    Status VARCHAR(50),           -- open | in_progress | completed | cancelled
    Department VARCHAR(100),
    TeamLeader VARCHAR(100),
    Technician VARCHAR(100),
    TechnicianId UUID,
    
    -- بيانات العميل
    CustomerName VARCHAR(200),
    CustomerPhone VARCHAR(20),
    CustomerAddress TEXT,
    CustomerLatitude DECIMAL(10,8),
    CustomerLongitude DECIMAL(11,8),
    
    -- بيانات الشبكة
    FBG VARCHAR(50),
    FAT VARCHAR(50),
    
    -- التفاصيل
    Notes TEXT,
    Summary TEXT,
    Priority VARCHAR(20),
    Amount DECIMAL(15,2),
    
    -- المصدر
    SourceType VARCHAR(20),       -- citizen | agent | manual
    SourceId UUID,
    
    -- موقع الفني
    TechnicianLatitude DECIMAL(10,8),
    TechnicianLongitude DECIMAL(11,8),
    TechnicianETA INT,
    
    -- التدقيق
    AuditStatus VARCHAR(50),
    AuditedBy UUID,
    AuditedAt TIMESTAMP,
    CustomerRating INT,
    AuditorNotes TEXT,
    HasComplaint BOOLEAN DEFAULT FALSE,
    
    CompanyId UUID REFERENCES Companies(Id),
    CreatedBy UUID,
    CreatedAt TIMESTAMP DEFAULT NOW(),
    ClosedAt TIMESTAMP
);

-- 💳 معاملات الدفع
CREATE TABLE PaymentTransactions (
    Id UUID PRIMARY KEY,
    UserId UUID,
    UserType VARCHAR(20),         -- citizen | agent
    Amount DECIMAL(15,2),
    Gateway VARCHAR(50),          -- zaincash | fastpay | asiahawala | nasspay
    GatewayTransactionId VARCHAR(200),
    Status VARCHAR(50),           -- pending | success | failed | refunded
    Purpose VARCHAR(100),         -- subscription | store | debt_payment | recharge
    RelatedId UUID,
    CompanyId UUID REFERENCES Companies(Id),
    CreatedAt TIMESTAMP DEFAULT NOW(),
    CompletedAt TIMESTAMP
);
```

---

# ✅ ملخص الجدول الزمني

| الترتيب | المهمة | المدة |
|---------|--------|-------|
| **1** | 🔴 **Backend Entities + API** | 1-2 أسبوع |
| **2** | 🟠 **منصة الويب (المواطن + الوكيل)** | 2 أسبوع |
| **3** | 🟡 **شاشات نظام الشركة** | 1 أسبوع |
| **4** | 🟢 **بوابات الدفع** | 1 أسبوع |
| **5** | 🔵 **الاختبار والنشر** | 1 أسبوع |

---

# 📝 ملاحظات مهمة

1. **كل البيانات على VPS** - لا Google Sheets
2. **بوابات دفع متعددة** - ZainCash, FastPay, Asia Hawala, NassPay
3. **GPS للتتبع** - موقع المواطن + موقع الفني
4. **نظام التدقيق** - متابعة جودة الخدمة
5. **المتجر الإلكتروني** - منتجات + سلة + دفع
6. **خدمة الماستر** - شحن + بطاقات + توصيل

