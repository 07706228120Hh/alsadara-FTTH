# Security Workflow — سير عمل المعالجة الأمنية

الهدف: معالجة مشكلة أمنية بتصنيف واضح وأدلة وخطة إصلاح آمنة وإعادة فحص.

## السلسلة
```
Security Issue
  → security-auditor-agent
  → Classify P0/P1/P2/P3 (تصنيف الخطورة)
  → Evidence (جمع الأدلة)
  → Safe Fix Plan (خطة إصلاح آمنة)
  → Specialized Agent (backend/frontend/mobile/database)
  → testing-qa-agent (Tests)
  → security-auditor-agent (Re-check إعادة فحص)
  → documentation-agent
  → Report
```

## الخطوات بالتفصيل
1. **security-auditor-agent**: يستلم البلاغ ويبدأ التقييم الأولي. المخرجات: risk-template.
2. **Classify P0/P1/P2/P3**: تصنيف الخطورة (P0 حرج فوري ← P3 منخفض). المخرجات: تصنيف موثّق بمبرر.
3. **Evidence**: جمع أدلة قابلة للتحقق (مسارات ملفات، سطور، سيناريو الاستغلال) دون كشف أسرار في التقارير. المخرجات: أدلة.
4. **Safe Fix Plan**: خطة إصلاح لا تكسر الإنتاج، مع خطة تراجع. المخرجات: خطة + decision-template عند الحاجة.
5. **Specialized Agent**: ينفّذ الوكيل المختص الإصلاح ضمن النطاق المسموح. أي تغيير DB يمر على database-postgres-agent.
6. **testing-qa-agent**: اختبارات تثبت إغلاق الثغرة دون انحدار. المخرجات: نتائج.
7. **security-auditor-agent (Re-check)**: إعادة فحص للتأكد من إغلاق الثغرة فعلياً. **بوابة**: لا يُغلق البند دون موافقة المدقق الأمني.
8. **documentation-agent**: توثيق المعالجة دون كشف أي سر. المخرجات: توثيق.
9. **knowledge-manager-agent**: تحديث الذاكرة بالثغرة والمعالجة.

## بوابات الموافقة البشرية
- موافقة بشرية صريحة قبل أي deploy/push/migration أو تغيير secrets أو حذف ملفات.
- كل تغيير أمني يمر على security-auditor قبل وبعد التنفيذ.
- في P0: إخطار بشري فوري قبل أي إجراء يمس الإنتاج.

## المخرجات النهائية
- ثغرة مُغلقة ومُعاد فحصها.
- أدلة + خطة تراجع موثّقة (دون أسرار).
- تقرير نهائي (report-template) + ذاكرة محدّثة.
