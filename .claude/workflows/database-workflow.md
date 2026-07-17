# Database Workflow — سير عمل تغييرات قاعدة البيانات

الهدف: تنفيذ أي تغيير على قاعدة البيانات (PostgreSQL / EF migrations) بأمان وبموافقة بشرية إلزامية.

## السلسلة
```
Database Change
  → database-postgres-agent
  → Schema Analysis (تحليل البنية)
  → Migration Plan (خطة الهجرة)
  → Rollback Plan (خطة التراجع)
  → security-auditor-agent (Security Review)
  → Test Plan (خطة الاختبار)
  → Human Approval (موافقة بشرية إلزامية)
  → Implementation (التنفيذ)
  → Report
```

## الخطوات بالتفصيل
1. **database-postgres-agent**: يستلم طلب التغيير ويتحقق من السياق (db `sadara_db`، 84 EF migrations، VPS 72.61.183.61). المخرجات: task-template.
2. **Schema Analysis**: تحليل الجداول والعلاقات والفهارس المتأثرة وأثر الأداء. المخرجات: تحليل بنية.
3. **Migration Plan**: خطة migration متوافقة مع EF، تتجنّب القفل الطويل وفقدان البيانات. المخرجات: خطة + ملف migration مقترح.
4. **Rollback Plan**: خطة تراجع واضحة (down migration / snapshot). المخرجات: خطة تراجع.
5. **security-auditor-agent**: مراجعة أمنية للأثر على الصلاحيات والبيانات الحساسة. المخرجات: risk-template عند الحاجة.
6. **Test Plan**: خطة اختبار على بيئة غير إنتاجية أولاً. المخرجات: خطة اختبار + نتائج.
7. **Human Approval** — **بوابة إلزامية**: لا يُطبّق أي migration على الإنتاج دون موافقة بشرية صريحة.
8. **Implementation**: تطبيق التغيير بعد الموافقة فقط، مع نسخة احتياطية/snapshot قبل التنفيذ. المخرجات: تأكيد التطبيق.
9. **knowledge-manager-agent**: تحديث الذاكرة بعدد الـ migrations والتغيير.

## بوابات الموافقة البشرية
- **إلزامي**: موافقة بشرية صريحة قبل أي migration أو DDL على الإنتاج.
- موافقة بشرية قبل أي حذف بيانات أو تغيير secrets.
- أخذ snapshot/backup قبل التنفيذ شرط لا يُتجاوز.

## المخرجات النهائية
- تغيير قاعدة بيانات مُطبّق بأمان مع خطة تراجع جاهزة.
- مراجعة أمنية + خطة اختبار موثّقة.
- تقرير نهائي (report-template) + ذاكرة محدّثة.
