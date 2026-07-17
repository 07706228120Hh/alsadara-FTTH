# Bugfix Workflow — سير عمل إصلاح الأخطاء

الهدف: إصلاح خطأ مُبلَّغ عنه بأقل تغيير ممكن مع اختبار يمنع تكراره.

## السلسلة
```
Bug Report
  → 00-project-manager
  → Reproduce (إعادة الإنتاج)
  → Identify Affected Area (تحديد المنطقة المتأثرة)
  → Assign Specialized Agent (backend/frontend/mobile/database)
  → Minimal Fix (إصلاح أدنى)
  → testing-qa-agent (Tests)
  → code-reviewer-agent (Review)
  → knowledge-manager-agent (Memory Update)
  → Report
```

## الخطوات بالتفصيل
1. **00-project-manager**: يسجّل البلاغ ويحدد الشدّة والأولوية. المخرجات: ملف مهمة (task-template).
2. **Reproduce**: الوكيل المختص يعيد إنتاج الخطأ بخطوات واضحة. المخرجات: خطوات إعادة إنتاج موثّقة. إن تعذّر الإنتاج → إعادة للـ project-manager.
3. **Identify Affected Area**: تحديد الملفات/الطبقة المتأثرة (Backend .NET / Flutter / PostgreSQL). المخرجات: قائمة ملفات.
4. **Assign Specialized Agent**: يوزّع المدير المهمة للوكيل المناسب. أي تغيير DB يمر على database-postgres-agent.
5. **Minimal Fix**: إصلاح بأقل نطاق ممكن دون gold-plating ودون لمس ملفات خارج النطاق. المخرجات: patch.
6. **testing-qa-agent**: يضيف اختبار انحدار (regression test) يثبت الإصلاح ويشغّل الاختبارات. المخرجات: نتائج.
7. **code-reviewer-agent**: مراجعة الإصلاح والتأكد أنه أدنى وآمن. المخرجات: review-template.
8. **security-auditor-agent** (إن لزم): إذا مسّ الخطأ المصادقة أو البيانات الحساسة. المخرجات: risk-template.
9. **knowledge-manager-agent**: يحدّث الذاكرة بالسبب الجذري والإصلاح. المخرجات: ذاكرة محدّثة.

## بوابات الموافقة البشرية
- موافقة بشرية قبل أي deploy/push للإنتاج أو migration أو تغيير secrets.
- موافقة بشرية إذا تطلّب الإصلاح تغييراً في schema قاعدة البيانات.

## المخرجات النهائية
- إصلاح أدنى مُختبَر ومُراجَع.
- اختبار انحدار يمنع التكرار.
- تقرير نهائي (report-template) + ذاكرة محدّثة.
