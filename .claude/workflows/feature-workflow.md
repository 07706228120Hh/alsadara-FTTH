# Feature Workflow — سير عمل الميزات الجديدة

الهدف: تنفيذ طلب ميزة جديدة من الفكرة حتى التوثيق وتحديث الذاكرة بأمان وجودة عالية.

## السلسلة
```
Feature Request
  → 00-project-manager
  → product-analysis-agent
  → architecture-evolution-agent (إن لزم)
  → backend-agent / frontend-agent / mobile-agent / database-postgres-agent (حسب الحاجة)
  → code-reviewer-agent
  → testing-qa-agent
  → security-auditor-agent (إن لزم)
  → documentation-agent
  → knowledge-manager-agent
  → Final Report
```

## الخطوات بالتفصيل
1. **00-project-manager**: يستقبل الطلب، يحدد النطاق والأولوية، ويوزّع المهام. المخرجات: ملف مهمة (task-template) لكل وكيل.
2. **product-analysis-agent**: يحلل قيمة الميزة وحالات الاستخدام ومعايير القبول (Done Criteria). المخرجات: مواصفات وظيفية.
3. **architecture-evolution-agent** (إن لزم): يراجع الأثر المعماري عند أي تغيير بنيوي. **بوابة**: أي تغيير معماري يمر هنا إلزامياً. المخرجات: decision-template.
4. **backend/frontend/mobile/database**: ينفّذ كل وكيل مختصّ جزءه ضمن النطاق المسموح فقط. أي تغيير DB يمر على database-postgres-agent. المخرجات: كود + ملاحظات.
5. **code-reviewer-agent**: مراجعة الجودة والاتساق. المخرجات: review-template.
6. **testing-qa-agent**: كتابة وتشغيل الاختبارات وتحليل الإخفاقات. المخرجات: نتائج الاختبارات.
7. **security-auditor-agent** (إن لزم): يراجع أي ميزة تمس المصادقة/الصلاحيات/البيانات الحساسة. المخرجات: risk-template عند وجود مخاطر.
8. **documentation-agent**: يوثّق الميزة بالاعتماد على الكود الفعلي فقط. المخرجات: توثيق محدّث.
9. **knowledge-manager-agent**: يحدّث `MEMORY.md` والملفات المرتبطة. المخرجات: ذاكرة محدّثة.

## بوابات الموافقة البشرية
- موافقة بشرية صريحة قبل أي migration على الإنتاج أو deploy أو push أو تغيير secrets أو حذف ملفات.
- موافقة بشرية على القرار المعماري قبل البدء بالتنفيذ.

## المخرجات النهائية
- ميزة مُنفّذة ومُختبرة ومُراجعة.
- توثيق محدّث + ذاكرة محدّثة.
- تقرير نهائي (report-template) يلخّص ما تم والمخاطر والخطوات التالية.
