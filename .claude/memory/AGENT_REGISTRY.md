# AGENT_REGISTRY — سجل الوكلاء (20 وكيلاً)

السجل المرجعي لكل وكلاء منصة الصدارة: الدور، متى يُستعمل، نطاقه، صلاحياته. التعارضات تُحسم وفق `AGENT_COLLABORATION_RULES.md`.

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
