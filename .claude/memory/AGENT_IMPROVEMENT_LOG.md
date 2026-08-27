# AGENT_IMPROVEMENT_LOG — سجل تحسين الوكلاء

سجل كل تغيير يطرأ على تعريفات/قواعد/سلوك الوكلاء في منصة الصدارة. المالك: `01-agent-trainer-development-manager`.

| Date | Agent | Change | Reason | Files Updated | Result |
|------|-------|--------|--------|---------------|--------|
| 2026-06-25 | الكل (19 وكيلاً) | تأسيس نظام الوكلاء وذاكرتهم المشتركة لأول مرة | الانطلاق بنظام عمل منظّم متعدد التخصصات بحدود وموافقات | كل ملفات `.claude/memory/*.md` | تم |
| 2026-08-26 | 13 وكيلاً (backend, database-postgres, devops, security-auditor, penetration-testing, architecture-evolution, testing-qa, code-reviewer, mobile, integration, performance, release-manager, documentation, knowledge-manager) | إضافة قسم «تحديثات الإصدار / معرفة حالية (v2.3.4)» لكل وكيل حسب دوره (مزامنة معرفة بعد إصدار v2.3.4 المنشور: تطبيق+باكند) | توجيه من project-manager لمزامنة وعي الوكلاء بحالة النظام بعد v2.3.4 (إصلاح /summary، علَم عزل EnforceIsolation=OFF نشط، بوابات تفعيل العزل، درس EF vs psql، نشر مزدوج) | `.claude/agents/{backend,database-postgres,devops,security-auditor,penetration-testing,code-reviewer,mobile,integration,performance,release-manager,documentation}-agent.md` + `02-architecture-evolution-agent.md` + `03-knowledge-manager-agent.md` + `testing-qa-agent.md` | تم — لا تداخل نطاقات جديد ولا صلاحيات خطرة (لم تُعدَّل أي `tools:` frontend/ui-ux/product-analysis بلا تحديث جوهري؛ توجيهات accounting و api-integration-tester أُدمجت في backend و penetration-testing لغياب ملفَّيهما) |
