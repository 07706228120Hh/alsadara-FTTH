# PROJECT_CONTEXT_FOR_AGENTS — سياق مختصر للوكلاء

نسخة مكثّفة يقرأها كل وكيل قبل العمل على منصة الصدارة (Sadara Platform).

## ما المشروع؟
منصة FTTH/ISP + تجارة إلكترونية، تخدم المواطنين والشركات في العراق. Multi-tenant: كل البيانات معزولة بحسب `CompanyId`.

## هدفه؟
- إدارة مشتركي FTTH (ISP) من قبل مشغّلين/شركات: تفعيل، اشتراكات، فوترة، محاسبة، تذاكر دعم.
- بوابة تجارة إلكترونية (Merchant, Product, Order, Payment) للمواطنين.
- محاسبة آلية (قيود FTTH) ومزامنة مع مزوّد FTTH خارجي.

## أجزاؤه؟
| الجزء | التقنية | المسار |
|------|---------|--------|
| Backend API | .NET 9 (Clean Arch) | `src/Backend/API/Sadara.API` |
| Application | .NET 9 | `src/Backend/Core/Sadara.Application` |
| Domain | .NET 9 | `src/Backend/Core/Sadara.Domain` |
| Infrastructure + DB | EF Core 9 + PostgreSQL | `src/Backend/Core/Sadara.Infrastructure` |
| تطبيق FTTH | Flutter (Win/Android/iOS) | `src/Apps/CompanyDesktop/alsadara-ftth` |
| تطبيق المواطن | PWA (Unknown: Blazor/Flutter) | `src/Apps/CitizenWeb` |

## بنية الخوادم
- **رئيسي (ملكنا)**: `72.61.183.61` — API + PostgreSQL + النشر. النشر دائماً هنا فقط.
- **FTTH خارجي (ليس ملكنا)**: `185.239.19.3` / `api.ftth.iq` — قراءة فقط، محجوب خلف Cloudflare.

## كيف يتعامل الوكلاء معه؟
1. اقرأ هذا الملف + `PROJECT_STRUCTURE_FOR_AGENTS.md` + قواعد مجالك (Security/Database/Deployment) قبل أي عمل.
2. التزم بحدود مجالك (Allowed/Forbidden Scope في `AGENT_REGISTRY.md`).
3. **لا** تنشر، **لا** تشغّل migration على الإنتاج، **لا** تضع أسراراً في الكود/التقارير — دون موافقة صريحة.
4. أبلغ عن المخاطر الأمنية فوراً واستدعِ `security-auditor`.
5. سجّل عملك في `TASK_HISTORY.md` والقرارات في `DECISIONS.md`.
6. عند الشك حول الحقائق: علّمها **Unknown** ولا تخترع.

## الإصدار الحالي
2.2.25+304 على branch `master`.
