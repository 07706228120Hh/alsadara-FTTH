# AGENT_REGISTRY — سجل الوكلاء (29 وكيلاً: 20 نواة الصدارة + 9 وحدة SAS)

السجل المرجعي لكل وكلاء منصة الصدارة: الدور، متى يُستعمل، نطاقه، صلاحياته. التعارضات تُحسم وفق `AGENT_COLLABORATION_RULES.md`.

> **حدّ الملكية الأساسي:** وكلاء **نواة الصدارة** يملكون `src/**` (.NET + Flutter alsadara-ftth + CitizenWeb) و`.claude/**` و`.github/**` وغيرها؛ **لا يلمسون** `modules/sas-agent/**`. وكلاء **وحدة SAS** (بادئة `sas-`) يملكون **حصراً** `modules/sas-agent/**` و`src/Apps/CompanyDesktop/alsadara-ftth/lib/sas_agent/**`؛ **لا يلمسون** نواة الصدارة. التكامل بينهما عبر بوّابة `/api/sas-agent/*` فقط، بتنسيق عبر `00-project-manager`.

| Agent | Role | When to Use | Allowed Scope | Forbidden Scope | Can Edit Code? | Needs Approval? |
|-------|------|-------------|---------------|-----------------|----------------|-----------------|
| 00-project-manager | تنسيق وحسم التعارض العام وتوزيع المهام | بداية كل مهمة معقدة/متعددة التخصصات | كل الذاكرة، توزيع المهام، الحسم | تنفيذ كود مباشر بنفسه | لا | نعم لأي عملية حساسة |
| 01-agent-trainer-development-manager | تطوير وتدريب الوكلاء وتعديل تعريفاتهم | إنشاء/تعديل وكيل أو قواعده | `.claude/` تعريفات الوكلاء والذاكرة | كود التطبيق، النشر | لا (كود التطبيق) | نعم لتغيير الوكلاء |
| 02-architecture-evolution-agent | تطوّر البنية المعمارية وحسم خلافاتها | قرارات بنيوية، تقسيم طبقات | تصميم معماري، `Application`/`Domain` design | النشر، الأسرار | محدود (هيكلة) | نعم |
| 03-knowledge-manager-agent | إدارة الذاكرة والتوثيق المعرفي | تحديث `.claude/memory/`، حفظ الدروس | كل ملفات الذاكرة | كود التطبيق، النشر | لا | لا |
| backend-agent | تطوير .NET (API/Application/Domain) | مهام backend | `Sadara.API/Application/Domain`، Infrastructure (تنسيق مع DB agent) | Migrations الإنتاج، الأسرار، النشر | نعم | نعم للنشر/DB |
| frontend-agent | واجهات Flutter/PWA | مهام واجهة المستخدم | `alsadara-ftth`, `CitizenWeb` UI | backend logic، النشر | نعم | لا (إلا النشر) |
| mobile-agent | تطبيق FTTH (Win/Android/iOS) | مهام منصّات التطبيق والبناء | `alsadara-ftth` build/platform | backend، الأسرار | نعم | نعم للإصدار |
| database-postgres-agent | قاعدة PostgreSQL والـ migrations | تصميم/تعديل المخطط، فهارس، RLS | `Infrastructure/Data/Migrations`، schema | تشغيل migration على الإنتاج بلا موافقة | نعم (migrations) | نعم للإنتاج |
| security-auditor-agent | تدقيق أمني وحسم قضايا الأمن | أي مسّ بـ Auth/secrets/admin | كل الكود للقراءة، تقارير أمنية | نشر، تعطيل تحقق أمني | محدود (إصلاحات أمنية) | نعم |
| testing-qa-agent | الاختبارات والجودة | كتابة/تشغيل اختبارات | `tests/`، اختبارات الوحدات/التكامل | كود الإنتاج المنطقي، النشر | نعم (tests) | لا |
| devops-agent | البنية التحتية والنشر | CI/CD، VPS، Docker | `.github/workflows`, `docker/`, نشر VPS | كود الأعمال، الأسرار بالكود | محدود | نعم للنشر |
| documentation-agent | التوثيق | كتابة/تحديث الوثائق | ملفات `*.md` التوثيقية | كود التطبيق | لا | لا |
| ui-ux-agent | تصميم تجربة/واجهة المستخدم | مراجعة/تحسين UX | تصميم UI، أنماط التفاعل | backend، النشر | محدود (UI) | لا |
| performance-agent | الأداء والتحسين | بطء/استهلاك موارد | profiling، تحسينات أداء عبر الطبقات | تغييرات وظيفية كبرى، النشر | نعم (تحسين) | نعم للنشر |
| release-manager-agent | إدارة الإصدارات | bump إصدار، GitHub Release | الإصدار، installer، release notes | كود الأعمال، DB | محدود | نعم |
| code-reviewer-agent | مراجعة الكود | قبل دمج/إصدار | قراءة diff، تقارير مراجعة | تعديل تلقائي بلا اتفاق | لا (مراجعة) | لا |
| refactor-agent | إعادة الهيكلة | تنظيف/تبسيط بلا تغيير سلوك | كل الكود (هيكلة) | تغيير سلوك، النشر | نعم | لا (إلا تغييرات واسعة) |
| integration-agent | التكاملات الخارجية | FTTH/Cloudflare/Firebase/SMTP | طبقة التكامل، gateways | الكتابة على FTTH الخارجي، الأسرار | نعم | نعم |
| product-analysis-agent | تحليل المنتج والمتطلبات | فهم احتياج/أولوية | تحليل، roadmap، متطلبات | كود، نشر | لا | لا |
| penetration-testing-agent | اختبار اختراق دفاعي تطبيقي ضمن بيئة مصرّح بها | تحقّق عملي من Auth/authz/CORS/rate-limit/admin routes/tenant isolation | بيئة محلية/staging مصرّح بها، قراءة الكود، تقارير في `.claude/reports/` | استهداف خارجي، الإنتاج، destructive/DoS، سحب/طباعة أسرار | لا (إلا بطلب project-manager) | نعم لأي أداة تدخّلية وللبيئة |
| **— وكلاء وحدة SAS (بادئة `sas-`) — ملكية حصرية في `modules/sas-agent/**` + `alsadara-ftth/lib/sas_agent/**`** | | | | | | |
| sas-backend-agent | باكند وحدة SAS (Python/FastAPI) — routers/services/schemas/main | تطوير منطق خدمة الساز (SAS) داخل الوحدة | `modules/sas-agent/backend/app/{api,services,main.py,schemas.py,config.py}` (منطق SAS لا OLT الخامل) | نواة الصدارة .NET، models/migrations، عملاء SAS4، core/security، النشر | نعم (Python الوحدة) | نعم للنشر/عقد البوّابة |
| sas-database-agent | بيانات وحدة SAS (SQLModel + Alembic) | نماذج/هجرات الوحدة، عزل، تشفير أسرار | `modules/sas-agent/backend/{app/models.py,app/database.py,migrations,alembic.ini}` | مخطّط PostgreSQL للنواة، هجرات EF Core، منطق API، النشر | نعم (models/migrations الوحدة) | نعم لأي تنفيذ إنتاج |
| sas-integration-agent | تكامل SAS4 + تشفير AES متوافق OpenSSL | عملاء الساز، مصادقة/جلسات SAS4 | `modules/sas-agent/backend/app/integrations/{sas_client.py,sas_user_client.py}` + مرجع SAS4 | نواة الصدارة، تكاملات FTTH/Cloudflare/Firebase، routers/services، core/security، النشر | نعم (عملاء SAS4) | نعم لتغيير التشفير |
| sas-security-agent | أمن وعزل الوحدة (خدمة داخلية) | X-Internal-Secret، تشفير، عزل ثلاثي داخل الوحدة | `modules/sas-agent/backend/app/core/{security.py,auth.py}` + قراءة كل الوحدة | نموذج صلاحيات النواة، كشف الخدمة للإنترنت، عملاء SAS4، النشر | محدود (تقوية أمنية للوحدة) | نعم؛ الكلمة الأمنية النهائية لـ security-auditor-agent |
| sas-flutter-ui-agent | واجهة وحدة SAS بثيم الصدارة (Cairo/screenutil/app_theme) | نقل شاشات + نمط FTTH + RTL | `alsadara-ftth/lib/sas_agent/**` + `modules/sas-agent/flutter/frontend/lib/screens/**` (مصدر نقل) | باقي alsadara-ftth (عدا نقطة الإدماج)، طبقة الاتصال، الباكند، النشر | نعم (شاشات الوحدة) | لا (إلا نقطة الإدماج بتنسيق) |
| sas-flutter-apiclient-agent | طبقة اتصال الوحدة (تنادي بوّابة الصدارة فقط) | عميل REST + نماذج + JSON | `alsadara-ftth/lib/sas_agent/{services,models}/**` | الشاشات، طبقة اتصال الصدارة العامة، مناداة خدمة Python مباشرة، النشر | نعم (خدمة اتصال الوحدة) | لا (إلا تغيير عقد البوّابة) |
| sas-testing-agent | اختبارات الوحدة (pytest + دخان Flutter) | عزل/تسريب/تكامل SAS4، دخان الإقلاع/البناء | `modules/sas-agent/backend/tests/**` + دخان `lib/sas_agent` | منطق الوحدة، اختبارات نواة الصدارة .NET، النشر | نعم (tests الوحدة) | لا |
| sas-devops-agent | بناء/تشغيل خدمة الساز (sidecar) | venv/Docker/Alembic/systemd `sas-service` على 127.0.0.1، دمج مسار النشر مع devops-agent | ملفات بناء/تشغيل الوحدة (`requirements*`, `alembic.ini`, `docker-entrypoint.sh`, `.dockerignore`, systemd الوحدة) | منطق الأعمال، نشر النواة (devops يقود)، كشف الخدمة للإنترنت، الأسرار، migration إنتاج | محدود (ملفات بناء/تشغيل) | نعم للنشر/الإنتاج |
| sas-olt-legacy-agent | وكيل خامل (محفوظ) لطبقة OLT/SNMP المؤجّلة | مرجعية/تحليل إحياء عند قرار صريح فقط | قراءة فقط: طبقة OLT/SNMP المحفوظة في `modules/sas-agent/backend/**` | تفعيل/تعديل أي مسار OLT، منطق SAS النشط، نواة الصدارة، النشر | لا (خامل، قراءة فقط) | نعم لأي إحياء |
