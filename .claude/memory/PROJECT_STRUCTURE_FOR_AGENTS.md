# PROJECT_STRUCTURE_FOR_AGENTS — خريطة المشروع للوكلاء

خريطة بنيوية تفصيلية لمنصة الصدارة يستعملها الوكلاء لتحديد مكان العمل ومالكه.

## High-level map
```
Sadara Platform (Multi-tenant by CompanyId)
├── Backend (.NET 9, Clean Architecture)
│   API → Application → Domain ↔ Infrastructure → PostgreSQL
├── Apps (Flutter/Dart)
│   alsadara-ftth (مشغّلو FTTH) + CitizenWeb (المواطن) + screen_test_app
└── External: FTTH provider (api.ftth.iq, read-only, خلف Cloudflare)
```

## Directory map
| المسار | المحتوى |
|--------|---------|
| `src/Backend/API/Sadara.API` | 57 Controllers، Hubs (SignalR)، Authorization/RequirePermissionAttribute، DTOs، Services. JWT Bearer. |
| `src/Backend/Core/Sadara.Application` | Services، DTOs، Interfaces، Mapping، Validators. |
| `src/Backend/Core/Sadara.Domain` | 37+ Entities (BaseEntity, User, Company, Customer, Subscription, Accounting, Payment, Order, ServiceAndPermission, ISPSubscriber, IptvSubscriber, FtthSubscriberCache, FtthSyncLog, SupportTicket, Merchant, Product)، Enums، Interfaces. |
| `src/Backend/Core/Sadara.Infrastructure` | Data/Migrations (84)، Identity/IdentityServices.cs، Repositories، Services. EF Core 9 + Npgsql. |
| `src/Apps/CompanyDesktop/alsadara-ftth` | تطبيق FTTH الرئيسي. توزيع Inno Setup → GitHub Releases. |
| `src/Apps/CitizenWeb` | تطبيق المواطن PWA (Unknown: Blazor أم Flutter). |
| `src/Apps/screen_test_app` | تجريبي. |
| `tests/` | Sadara.API.Tests، Sadara.Domain.Tests، Sadara.Integration.Tests (هزيلة). |
| `.github/workflows/` | build-windows.yml (مثبّت Windows فقط). |
| `docker/` | Dockerfile + docker-compose.yaml. |

## Ownership map (أي وكيل يملك أي مجلد)
| المجلد | الوكيل المالك |
|--------|----------------|
| `Sadara.API` Controllers/Services | backend-agent |
| `Sadara.Application` / `Sadara.Domain` | backend-agent + architecture-evolution-agent |
| `Sadara.Infrastructure/Data/Migrations` | database-postgres-agent |
| `Identity/IdentityServices.cs` + Auth | security-auditor-agent + backend-agent |
| `alsadara-ftth` (Flutter) | mobile-agent + frontend-agent |
| `CitizenWeb` | frontend-agent |
| `tests/` | testing-qa-agent |
| `.github/workflows`, `docker/`, نشر VPS | devops-agent + release-manager-agent |

## Data flow
Client (Flutter/PWA) → JWT → API Controller → Application Service → Repository (Infrastructure/EF Core) → PostgreSQL. مزامنة FTTH: API → FtthCloudflareGateway → api.ftth.iq (قراءة) → FtthSubscriberCache.

## Authentication flow
1. تسجيل دخول → `AuthController`/`UnifiedAuthController`/`CitizenAuthController` يصدر JWT Bearer.
2. كل طلب يحمل JWT → middleware يتحقق.
3. الصلاحيات عبر `RequirePermissionAttribute` مقابل `ServiceAndPermission` (نظام صلاحيات مخصص).
4. تطبيق FTTH يستخدم مصادقة مزدوجة (`dual_auth_service.dart`).

## Critical paths
- إصدار/تحقق JWT (`IdentityServices.cs`).
- `DatabaseAdminController` + `SuperAdminController` (endpoints مميّزة).
- مزامنة FTTH + قيود المحاسبة (`FtthAccountingController`, `AccountingController`).
- عزل المستأجر (`CompanyId`) في كل استعلام.

## Unknown areas (تحتاج تحقق)
- `CitizenWeb`: README يقول Blazor WASM، الكود يبدو Flutter/Dart — **Unknown**.
- تغطية الاختبارات الفعلية — **Unknown**.
- وجود Row-Level Security (RLS) في PostgreSQL — **Unknown**.
