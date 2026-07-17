# Release Workflow — سير عمل تحضير الإصدار

الهدف: تحضير إصدار جاهز للنشر مع ملاحظات إصدار وخطة تراجع — دون أي deploy بلا موافقة.

## السلسلة
```
Release Preparation
  → release-manager-agent
  → Collect Changes (جمع التغييرات)
  → testing-qa-agent (Run Tests)
  → security-auditor-agent (Security Review)
  → documentation-agent (Docs Review)
  → Rollback Plan (خطة التراجع)
  → Release Notes (ملاحظات الإصدار)
  → Human Approval → (NO deploy without approval)
  → Report
```

## الخطوات بالتفصيل
1. **release-manager-agent**: يحدد نطاق الإصدار ورقم النسخة (مثال 2.2.x+y). المخرجات: task-template.
2. **Collect Changes**: جمع كل الـ commits/الميزات/الإصلاحات منذ آخر إصدار. المخرجات: قائمة تغييرات.
3. **testing-qa-agent**: تشغيل حزمة الاختبارات الكاملة وتحليل أي إخفاق. المخرجات: نتائج اختبارات.
4. **security-auditor-agent**: مراجعة أمنية للإصدار (لا أسرار مكشوفة، لا ثغرات مفتوحة). المخرجات: risk-template عند الحاجة.
5. **documentation-agent**: مراجعة توثيق الإصدار ومطابقته للكود الفعلي. المخرجات: توثيق محدّث.
6. **Rollback Plan**: خطة تراجع (إصدار سابق على GitHub Releases + استعادة DLLs/snapshot). المخرجات: خطة تراجع.
7. **Release Notes**: ملاحظات إصدار واضحة (ميزات/إصلاحات/مخاطر). المخرجات: release notes.
8. **Human Approval** — **بوابة**: لا deploy (SCP + systemctl restart) ولا push ولا نشر GitHub Release دون موافقة بشرية صريحة.
9. **knowledge-manager-agent**: تحديث الذاكرة برقم الإصدار والحالة بعد الموافقة.

## بوابات الموافقة البشرية
- **NO deploy without approval**: ممنوع أي SCP/systemctl restart/push/GitHub Release دون موافقة.
- موافقة بشرية قبل أي migration مصاحب للإصدار أو تغيير secrets.

## المخرجات النهائية
- حزمة إصدار جاهزة مع release notes وخطة تراجع.
- اختبارات + مراجعة أمنية + توثيق مكتمل.
- تقرير نهائي (report-template) ينتظر موافقة النشر.
