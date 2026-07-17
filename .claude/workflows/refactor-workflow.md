# Refactor Workflow — سير عمل إعادة الهيكلة

الهدف: إعادة هيكلة الكود دون تغيير السلوك، ضمن نطاق محدد بدقة، مع اختبارات قبل وبعد.

## السلسلة
```
Refactor Request
  → 00-project-manager
  → architecture-evolution-agent
  → refactor-agent
  → Define Exact Scope (تحديد النطاق بدقة)
  → testing-qa-agent (Tests Before)
  → Refactor (إعادة الهيكلة)
  → testing-qa-agent (Tests After)
  → code-reviewer-agent (Code Review)
  → Report
```

## الخطوات بالتفصيل
1. **00-project-manager**: يستلم الطلب ويحدد الهدف من إعادة الهيكلة. المخرجات: task-template.
2. **architecture-evolution-agent**: يتحقق من توافق إعادة الهيكلة مع البنية (Clean Architecture). **بوابة**: أي أثر معماري يُوثّق بـ decision-template.
3. **refactor-agent**: يتولّى التنفيذ.
4. **Define Exact Scope**: تحديد الملفات والحدود بدقة، مع قسم Out of Scope صريح. المخرجات: نطاق محدد.
5. **testing-qa-agent (Tests Before)**: تثبيت سلوك مرجعي عبر اختبارات قبل التغيير. المخرجات: نتائج أساس.
6. **Refactor**: إعادة الهيكلة دون تغيير السلوك الخارجي ودون لمس ملفات خارج النطاق. المخرجات: كود مُعاد هيكلته.
7. **testing-qa-agent (Tests After)**: تشغيل نفس الاختبارات للتأكد من تطابق السلوك. المخرجات: نتائج بعدية مطابقة.
8. **code-reviewer-agent**: مراجعة الجودة وعدم تغيّر السلوك. المخرجات: review-template.
9. **knowledge-manager-agent**: تحديث الذاكرة بالهيكلة الجديدة.

## بوابات الموافقة البشرية
- موافقة بشرية قبل أي deploy/push/migration أو تغيير secrets أو حذف ملفات.
- موافقة بشرية على أي تغيير معماري قبل التنفيذ.

## المخرجات النهائية
- كود مُعاد هيكلته بسلوك مطابق (Tests Before == Tests After).
- مراجعة كود مكتملة.
- تقرير نهائي (report-template) + ذاكرة محدّثة.
