# AGENT_SKILLS_MATRIX — مصفوفة مهارات الوكلاء (29 وكيلاً)

مهارات كل وكيل ونطاقه وتعاوناته في منصة الصدارة. مرجع سريع مكمّل لـ `AGENT_REGISTRY.md`. يشمل 20 وكيل نواة + 9 وكلاء وحدة SAS (بادئة `sas-`).

| Agent | Main Skill | Secondary Skills | Allowed Scope | Forbidden Scope | Collaborates With |
|-------|-----------|------------------|---------------|-----------------|-------------------|
| 00-project-manager | تنسيق وحسم | تخطيط، أولويات | الذاكرة، توزيع المهام | تنفيذ كود مباشر | الكل |
| 01-agent-trainer-development-manager | تدريب/تطوير الوكلاء | حوكمة، تعريفات | `.claude/` تعريفات + ذاكرة | كود التطبيق، النشر | project-manager, knowledge-manager |
| 02-architecture-evolution-agent | تصميم معماري | أنماط، حدود الطبقات | تصميم `Application`/`Domain` | النشر، الأسرار | backend, database, refactor |
| 03-knowledge-manager-agent | إدارة الذاكرة | توثيق، فهرسة | `.claude/memory/` | كود التطبيق | documentation, project-manager |
| backend-agent | تطوير .NET | API design، خدمات | `Sadara.API/Application/Domain` | migration إنتاج، الأسرار | database, security, integration |
| frontend-agent | Flutter/PWA UI | ربط API | `alsadara-ftth`, `CitizenWeb` UI | backend logic، النشر | mobile, ui-ux, backend |
| mobile-agent | منصّات التطبيق | بناء، تحديث تلقائي | `alsadara-ftth` build | backend، الأسرار | frontend, release-manager, devops |
| database-postgres-agent | PostgreSQL/EF | فهارس، RLS، migrations | schema + migrations | تشغيل إنتاج بلا موافقة | backend, security, devops |
| security-auditor-agent | تدقيق أمني | Auth، secrets، tenancy | قراءة كل الكود + تقارير | تعطيل تحقق أمني، النشر | الكل (حسم أمني) |
| testing-qa-agent | اختبارات | تغطية، تكامل | `tests/` | منطق الإنتاج، النشر | backend, frontend, code-reviewer |
| devops-agent | CI/CD وبنية تحتية | Docker، VPS، SCP | workflows, docker, نشر | كود الأعمال، الأسرار بالكود | release-manager, database, security |
| documentation-agent | توثيق | كتابة فنية | ملفات `*.md` | كود التطبيق | knowledge-manager, الكل |
| ui-ux-agent | UX/UI | إمكانية وصول، أنماط | تصميم UI | backend، النشر | frontend, mobile |
| performance-agent | تحسين الأداء | profiling، فهارس | تحسينات عبر الطبقات | تغييرات وظيفية كبرى | backend, database, refactor |
| release-manager-agent | إدارة الإصدارات | versioning، installer | الإصدار + release notes | كود الأعمال، DB | devops, mobile, code-reviewer |
| code-reviewer-agent | مراجعة الكود | جودة، اكتشاف عيوب | قراءة diff + تقارير | تعديل بلا اتفاق | الكل |
| refactor-agent | إعادة هيكلة | تبسيط، تنظيف | الكود (بلا تغيير سلوك) | تغيير سلوك، النشر | architecture, backend, performance |
| integration-agent | تكاملات خارجية | FTTH، Cloudflare، FCM، SMTP | gateways + طبقة التكامل | الكتابة على FTTH الخارجي | backend, security, devops |
| product-analysis-agent | تحليل المنتج | متطلبات، أولويات | تحليل + roadmap | كود، نشر | project-manager, ui-ux |
| penetration-testing-agent | اختبار اختراق دفاعي | تحقّق Auth/authz، CORS، rate-limit، IDOR/tenant isolation، exposed endpoints | بيئة محلية/staging مصرّح بها + تقارير | استهداف خارجي/الإنتاج، destructive/DoS، طباعة/سحب أسرار، تعديل كود بلا طلب | security-auditor, testing-qa, backend, database-postgres, devops |
| sas-backend-agent | باكند FastAPI للوحدة | routers/services/schemas SAS، تمرير معزّز، أخطاء عربية | `modules/sas-agent/backend/app/{api,services,main,schemas,config}` | نواة .NET، models/migrations، عملاء SAS4، core/security، النشر | sas-database, sas-integration, sas-security, sas-testing, backend-agent |
| sas-database-agent | SQLModel + Alembic للوحدة | نماذج/هجرات، فهارس، عزل، تشفير أسرار | `modules/sas-agent/backend/{models.py,database.py,migrations,alembic.ini}` | مخطّط PostgreSQL للنواة، هجرات EF Core، منطق API، النشر | sas-backend, sas-security, sas-testing, database-postgres |
| sas-integration-agent | تكامل SAS4 | تشفير AES/OpenSSL، جلسات SAS، مهلات/أخطاء | `modules/sas-agent/backend/app/integrations/*` + مرجع SAS4 | نواة الصدارة، FTTH/Cloudflare/Firebase، routers/services، core/security | sas-backend, sas-security, sas-database, security-auditor |
| sas-security-agent | أمن الخدمة الداخلية للوحدة | X-Internal-Secret، عزل ثلاثي، منع تسريب اعتماد | `modules/sas-agent/backend/app/core/{security,auth}.py` + قراءة الوحدة | نموذج صلاحيات النواة، كشف الخدمة، عملاء SAS4، النشر | security-auditor (مظلة), sas-integration, sas-backend, sas-database |
| sas-flutter-ui-agent | واجهة الوحدة بثيم الصدارة | نقل شاشات، نمط FTTH، RTL، PermissionGate | `alsadara-ftth/lib/sas_agent/**` + مصدر النقل | باقي alsadara-ftth (عدا الإدماج)، طبقة الاتصال، الباكند، النشر | sas-flutter-apiclient, mobile-agent, ui-ux, security-auditor |
| sas-flutter-apiclient-agent | طبقة اتصال الوحدة | REST لبوّابة الصدارة، نماذج، JSON، أخطاء | `alsadara-ftth/lib/sas_agent/{services,models}` | الشاشات، اتصال الصدارة العام، مناداة Python مباشرة، النشر | sas-flutter-ui, sas-backend, backend-agent, security-auditor |
| sas-testing-agent | اختبارات الوحدة | pytest عزل/تسريب/تكامل SAS4، دخان Flutter | `modules/sas-agent/backend/tests/**` + دخان `lib/sas_agent` | منطق الوحدة، اختبارات نواة .NET، النشر | sas-backend, sas-database, sas-integration, sas-security, testing-qa |
| sas-devops-agent | بناء/تشغيل خدمة الساز | venv/Docker/Alembic/systemd sas-service (127.0.0.1)، دمج مع devops | ملفات بناء/تشغيل الوحدة (requirements/alembic.ini/entrypoint/systemd) | منطق الأعمال، نشر النواة، كشف الخدمة، الأسرار، migration إنتاج | devops-agent, sas-database, sas-security, release-manager |
| sas-olt-legacy-agent | وكيل خامل OLT/SNMP محفوظ | مرجعية/تحليل إحياء عند قرار صريح | قراءة فقط: طبقة OLT/SNMP المحفوظة بالوحدة | تفعيل/تعديل OLT، منطق SAS النشط، نواة الصدارة، النشر | project-manager, architecture, security-auditor, sas-backend |
