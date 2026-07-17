# Incident Workflow — سير عمل الحوادث

الهدف: احتواء حادثة إنتاجية بأمان، إيقاف الضرر، إصلاح مؤقت ثم جذري، وكتابة postmortem.

## السلسلة
```
Incident
  → 00-project-manager
  → Identify Severity (تحديد الخطورة)
  → Stop Damage Safely (إيقاف الضرر بأمان)
  → Assign Correct Agent (تكليف الوكيل المناسب)
  → Temporary Fix (إصلاح مؤقت)
  → Root Cause (السبب الجذري)
  → Permanent Fix Plan (خطة الإصلاح الدائم)
  → Postmortem
  → Report
```

## الخطوات بالتفصيل
1. **00-project-manager**: يعلن الحادثة ويقود الاستجابة وينسّق الوكلاء. المخرجات: task-template + سجل زمني.
2. **Identify Severity**: تحديد الخطورة والأثر (مستخدمون متأثرون، خدمات معطّلة). المخرجات: تصنيف.
3. **Stop Damage Safely**: إجراءات احتواء آمنة وقابلة للعكس فقط (لا حذف بيانات). أي إجراء يمس الإنتاج يحتاج موافقة بشرية. المخرجات: احتواء.
4. **Assign Correct Agent**: تكليف الوكيل المختص (backend/database/devops/security). أي تغيير DB → database-postgres-agent؛ أي بُعد أمني → security-auditor-agent.
5. **Temporary Fix**: إصلاح مؤقت يعيد الخدمة بأقل مخاطرة، موثّق بوضوح كمؤقت. المخرجات: workaround.
6. **Root Cause**: تحليل السبب الجذري بالأدلة. المخرجات: تحليل RCA.
7. **Permanent Fix Plan**: خطة إصلاح دائم تمر على المسار المناسب (bugfix/security/database). المخرجات: خطة + decision-template عند الحاجة.
8. **Postmortem**: مراجعة بلا لوم تتضمّن الجدول الزمني والدروس والإجراءات الوقائية. المخرجات: postmortem.
9. **knowledge-manager-agent**: تحديث الذاكرة بالحادثة والدروس المستفادة.

## بوابات الموافقة البشرية
- موافقة بشرية صريحة قبل أي إجراء إنتاجي مدمّر أو غير قابل للعكس (restart خطر، rollback، migration، حذف).
- ممنوع تغيير secrets أو حذف ملفات دون موافقة.
- في الحوادث الحرجة: إخطار بشري فوري قبل أي تدخّل إنتاجي.

## المخرجات النهائية
- حادثة محتواة وخدمة مستعادة بإصلاح مؤقت.
- تحليل سبب جذري + خطة إصلاح دائم.
- postmortem + تقرير نهائي (report-template) + ذاكرة محدّثة.
