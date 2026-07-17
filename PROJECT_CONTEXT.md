# Project Context

سياق مشروع منصة الصدارة (Sadara Platform) — مرجع تقني شامل لكل الوكلاء. اقرأ هذا الملف قبل أي مهمة.

---

## 1. Project Identity

- **Project name**: منصة الصدارة (Sadara Platform).
- **Project type**: منصة FTTH/ISP (مزوّد خدمة إنترنت بالألياف الضوئية) + تجارة إلكترونية، بنظام multi-tenant معزول بـ Company.
- **Main goal**: إدارة كاملة لعمليات مزوّد خدمة FTTH (المشتركون، الاشتراكات، العمليات الميدانية، المحاسبة، الدعم الفني) مع طبقة تجارة إلكترونية، عبر تطبيق سطح مكتب/موبايل وتطبيق ويب للمواطنين.
- **Main users**: موظفو الشركات (Company staff) + المواطنون (Citizens) + مشغّلو FTTH (Field operators).

---

## 2. Technology Stack

- **Frontend**: Flutter Web / PWA — تطبيق `CitizenWeb` (README يذكر Blazor لكن الكود الفعلي Flutter — حالة Unknown تحتاج تأكيد).
- **Backend**: .NET 9 بمعمارية Clean Architecture، مع EF Core 9 و SignalR للوقت الحقيقي.
- **Mobile / Desktop**: Flutter — تطبيق `alsadara-ftth` يعمل على Windows desktop + Android + iOS.
- **Database**: PostgreSQL عبر Npgsql (`sadara_db`).
- **Authentication**: JWT Bearer + مصادقة مزدوجة (dual auth — مصادقة داخلية + ربط مع مزوّد FTTH الخارجي).
- **Authorization**: نظام صلاحيات مخصص (ServiceAndPermission) مطبّق عبر `RequirePermissionAttribute`.
- **Deployment**: SCP يدوي إلى VPS + systemd (`sadara-api`) للـ Backend؛ Inno Setup → GitHub Releases → auto-update للتطبيق.
- **Testing**: غير محدد بوضوح — مجلد `tests/` هزيل (يُرجّح xUnit لكن التغطية ضعيفة — Unknown).
- **DevOps**: Docker (`docker/Dockerfile` + `docker/docker-compose.yaml`)، GitHub Actions (`build-windows.yml`).

---

## 3. Current Architecture

- **Clean Architecture بأربع طبقات**:
  - `Sadara.API` — طبقة العرض (Controllers، SignalR Hubs، مصادقة JWT، فلاتر الصلاحيات).
  - `Sadara.Application` — منطق التطبيق (Use cases / Services).
  - `Sadara.Domain` — الكيانات والقواعد المجالية (37+ entity).
  - `Sadara.Infrastructure` — الوصول للبيانات (EF Core/Npgsql)، Identity، Repositories، Migrations.
- **Multi-tenant بـ Company**: عزل البيانات على مستوى الشركة؛ أي تغيير في منطق العزل حسّاس ويتطلب موافقة.
- **اعتماد خارجي على مزوّد FTTH**: قراءة بيانات FTTH من `api.ftth.iq` (`185.239.19.3`) خلف Cloudflare — قراءة فقط وليس ملكنا، ويشكّل نقطة هشاشة (challenge/blocking).
- **SignalR**: قنوات وقت حقيقي للإشعارات والتحديثات الحيّة.
- **Firebase FCM**: إشعارات الدفع (push notifications) للتطبيقات.

---

## 4. Important Directories

| Directory | Purpose | Responsible Agent | Notes |
|-----------|---------|-------------------|-------|
| `src/Backend/API/Sadara.API` | طبقة العرض: 57 controller، SignalR، JWT | backend-agent | تحتوي DatabaseAdmin/SuperAdmin controllers الحسّاسة |
| `src/Backend/Core/Sadara.Infrastructure/Data/Migrations` | 84 EF Core migration | database-postgres-agent | 84 migration مقابل إنتاج — حساس |
| `src/Apps/CompanyDesktop/alsadara-ftth` | التطبيق الرئيسي (Windows + Android + iOS) | mobile-agent | عربي RTL؛ يبني عبر `D:\flutter\flutter\bin\flutter.bat` |
| `src/Apps/CitizenWeb` | تطبيق المواطنين (Flutter Web / PWA) | frontend-agent | README يقول Blazor والكود Flutter — Unknown |
| `docker/` + `.github/` + `scripts/` + `deployment/` | الحاويات، CI، سكربتات، نشر | devops-agent | النشر على `72.61.183.61` فقط |
| `docs/` | توثيق المشروع | documentation-agent | — |
| `tests/` | الاختبارات | testing-qa-agent | تغطية ضعيفة — تحتاج تعزيز |
| `.claude/` | تعريفات الوكلاء والذاكرة المؤسسية | agent-trainer-development-manager | لا يُعدّل إلا عبر هذا الوكيل |

---

## 5. Critical Files

| File | Importance | Risk |
|------|-----------|------|
| `.env` | أسرار حقيقية (DB، JWT، مفاتيح خارجية) | P0 — لا يُطبع، لا يُنسخ، لا يُرفع |
| `Sadara.Infrastructure/Identity/IdentityServices.cs` (أو ما يماثله) | منطق المصادقة والهوية | عالٍ — أي تغيير يمر على security-auditor |
| `RequirePermissionAttribute.cs` | تطبيق نظام الصلاحيات المخصص | عالٍ — تغييره يؤثر على authorization كله |
| `DatabaseAdminController.cs` | تحكم إداري مباشر بقاعدة البيانات | حرج — وصول واسع، يتطلب تدقيق أمني |
| `SuperAdminController.cs` | صلاحيات خارقة على مستوى المنصة | حرج — يتجاوز عزل tenant |
| `Data/Migrations/*` | 84 migration تشكّل مخطط الإنتاج | عالٍ — أي migration على إنتاج يتطلب rollback plan |
| `docker/docker-compose.yaml` | تعريف خدمات الحاويات | متوسط/عالٍ — يحوي إعدادات بيئة |
| `.github/workflows/build-windows.yml` | بناء الإصدار وإنتاج المثبّت | متوسط — تغييره يؤثر على سلسلة الإصدار |

---

## 6. Known Risks

| Risk | Level | Description | Recommended Agent |
|------|-------|-------------|-------------------|
| أسرار بالشجرة | P0 | `.env` + `secrets/` + `.secrets/` تحتوي قيمًا حقيقية ضمن الريبو | security-auditor-agent |
| ملفات مؤقتة وثنائيات بالريبو | P1 | `tmp_*.json` + binaries + `node_modules` في الجذر تلوّث الشجرة وتضخّمها | devops-agent |
| اختبارات ضعيفة | P2 | مجلد `tests/` هزيل وتغطية منخفضة، مخاطرة انحدار صامتة | testing-qa-agent |
| هشاشة Cloudflare | P1 | الاعتماد على `api.ftth.iq` خلف Cloudflare عرضة للحجب/التحدّي (human-in-the-loop) | integration-agent |
| 84 migration مقابل إنتاج | P1 | عدد كبير من الـ migrations مقابل قاعدة إنتاج حيّة بلا rollback واضح | database-postgres-agent |
| controllers إدارية واسعة الصلاحية | P1 | `DatabaseAdminController` / `SuperAdminController` يتيحان وصولًا حساسًا | security-auditor-agent |

---

## 7. Development Rules

- احترم طبقات Clean Architecture: لا تجعل `Domain` يعتمد على `Infrastructure`؛ المنطق المجالي في `Domain`/`Application` لا في `API`.
- لا secrets في الكود إطلاقًا — القيم الحسّاسة عبر `.env`/متغيرات البيئة فقط.
- النشر على `72.61.183.61` فقط؛ الخادم الخارجي `185.239.19.3` للقراءة فقط.
- التطبيق عربي RTL — احترم اتجاه الواجهة والمحاذاة والترجمة في أي تعديل UI.
- احترم عزل multi-tenant بـ Company في أي استعلام أو endpoint جديد.
- أي migration يُختبر محليًا ويصاحبه خطة rollback قبل أي اقتراب من الإنتاج.
- التزم بالنموذج التشغيلي: ابدأ من project-manager للمهام الكبيرة ومرّ بالمراجعات المطلوبة.

---

## 8. Human Approval Required

نفس قائمة CLAUDE.md — العمليات التالية تتطلب موافقة بشرية صريحة:

- production deploy
- database migration
- deleting files
- changing secrets
- changing authentication system
- changing authorization model
- changing tenant isolation
- changing payment logic
- changing infrastructure
- force push
- destructive git operations
- disabling tests
- disabling security checks

---

## 9. Agent Operating Model

- أي مهمة كبيرة تبدأ من `project-manager`، الذي يقسّمها (task breakdown) ويسندها للوكيل المختص.
- التنفيذ المتخصص يمر عبر سلسلة المراجعة: `code-reviewer-agent` → `testing-qa-agent` → `security-auditor-agent` (عند الحاجة) → `documentation-agent` → `knowledge-manager-agent`.
- **التصعيد (Escalation)**: أي تغيير أمني → security-auditor؛ قاعدة بيانات → database-postgres؛ معماري → architecture-evolution؛ تعديل الوكلاء → agent-trainer-development-manager.
- **تحديث الذاكرة**: بعد إنجاز المهمة، يحدّث `knowledge-manager-agent` ملفات `.claude/memory` (PROJECT_STATE وما يلزم) لتبقى الذاكرة المؤسسية متزامنة.
- **التقرير النهائي**: تُختتم كل مهمة بتقرير موجز يوضّح ما نُفّذ والمخاطر والخطوات التالية، مع طلب الموافقة البشرية حيثما لزم.
