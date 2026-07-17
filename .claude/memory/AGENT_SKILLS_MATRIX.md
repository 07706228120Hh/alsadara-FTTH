# AGENT_SKILLS_MATRIX — مصفوفة مهارات الوكلاء

مهارات كل وكيل ونطاقه وتعاوناته في منصة الصدارة. مرجع سريع مكمّل لـ `AGENT_REGISTRY.md`.

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
