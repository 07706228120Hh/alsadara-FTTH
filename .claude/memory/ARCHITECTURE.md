# ARCHITECTURE — بنية منصة الصدارة

شرح معماري للـ Backend (.NET 9 Clean Architecture) وعلاقته بالـ Frontend والقاعدة وتطبيقات Flutter.

## النمط: Clean Architecture
```
            ┌──────────────────────────────┐
            │   Sadara.API (Presentation)  │  57 Controllers, Hubs, JWT, Authorization
            └──────────────┬───────────────┘
                           │ depends on
            ┌──────────────▼───────────────┐
            │  Sadara.Application (Use Cases)│ Services, DTOs, Interfaces, Validators, Mapping
            └──────────────┬───────────────┘
                           │ depends on
            ┌──────────────▼───────────────┐
            │     Sadara.Domain (Core)     │ 37+ Entities, Enums, Interfaces (لا تبعيات خارجية)
            └──────────────▲───────────────┘
                           │ implements interfaces
            ┌──────────────┴───────────────┐
            │  Sadara.Infrastructure       │ EF Core 9 + Npgsql, Repositories, Identity, Migrations
            └──────────────┬───────────────┘
                           │
                     ┌─────▼─────┐
                     │PostgreSQL │  sadara_db @ 72.61.183.61
                     └───────────┘
```
القاعدة: التبعيات تتجه نحو الداخل (Domain لا يعتمد على شيء). Infrastructure ينفّذ الواجهات المعرّفة في Domain/Application.

## علاقة Frontend / Backend / Database / Apps
- **تطبيقات Flutter** (`alsadara-ftth`, `CitizenWeb`) → HTTP/JWT → **Sadara.API** → **Application** → **Infrastructure** → **PostgreSQL**.
- **SignalR Hubs** للتحديثات الحية (إشعارات).
- **Firebase FCM** للإشعارات الدفعية (UserFcmToken).
- **مزوّد FTTH خارجي** (api.ftth.iq) — قراءة فقط عبر `FtthCloudflareGateway`، يغذّي `FtthSubscriberCache`.

## مناطق القوة
- فصل طبقات واضح (Clean Architecture) يسهّل الاختبار والصيانة.
- نظام صلاحيات مخصص دقيق (`RequirePermissionAttribute` + `ServiceAndPermission`).
- Multi-tenancy عبر `CompanyId`.
- نمط نشر سريع موثّق (DLLs فقط).

## مناطق الضعف
- تغطية اختبارات شبه معدومة مقابل 57 controller (P2).
- لا CD مؤتمت للـ backend → نشر يدوي عرضة للخطأ البشري (P2).
- اعتماد كامل على مزوّد FTTH خارجي خلف Cloudflare → هشاشة تشغيلية (P1).
- أسرار حقيقية + مجلدات secrets داخل الشجرة (P0).
- وحدات تحكم إدارية فائقة الصلاحية تحتاج تدقيق (`DatabaseAdminController`, `SuperAdminController`).

## توصيات معمارية
1. أتمتة CD آمن للـ backend مع gates للموافقة.
2. فصل/تجريد طبقة تكامل FTTH خلف واجهة قابلة للاستبدال + حل Cloudflare الجذري (whitelist IP).
3. فرض عزل `CompanyId` على مستوى المستودعات/RLS لتقليل خطأ النسيان.
4. رفع تغطية الاختبارات للمسارات الحرجة (Auth, Accounting, Tenant isolation).
5. توحيد توثيق البناء وإزالة التكرار.
