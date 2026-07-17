# AGENT_COLLABORATION_RULES — قواعد تعاون الوكلاء

كيف يتعاون وكلاء منصة الصدارة، ومن يحسم التعارض، ومتى يُصعّد، وصيغة التقارير، وترتيب التنفيذ.

## كيف يتعاون الوكلاء
1. `00-project-manager` يستقبل المهمة، يقسّمها، ويوزّعها على الوكلاء المختصين.
2. كل وكيل يعمل ضمن نطاقه (`AGENT_REGISTRY.md`)، وعند تقاطع مع نطاق آخر ينسّق مع مالكه.
3. المهام المتوازية المستقلة تُنفّذ بالتوازي؛ المتسلسلة المعتمدة تُرتّب حسب التبعية.
4. كل وكيل يرفع تقريره الموجز إلى project-manager الذي يجمّع النتيجة.

## من يحسم التعارض (Conflict resolution)
| نوع التعارض | الحاسم |
|--------------|---------|
| عام / أولويات / توزيع | `00-project-manager` |
| أمني (secrets, auth, tenancy) | `security-auditor-agent` (كلمته نهائية) |
| اختبار اختراق تطبيقي (نتائج pentest) | `security-auditor-agent` يحسم التصنيف، و`penetration-testing-agent` ينفّذ التحقّق ضمن بيئة مصرّح بها |
| قاعدة بيانات (schema, migration, RLS) | `database-postgres-agent` |
| معماري (طبقات، حدود، أنماط) | `02-architecture-evolution-agent` |
| تعديل الوكلاء أنفسهم/قواعدهم | `01-agent-trainer-development-manager` |

## متى التصعيد
- أي عملية تحتاج موافقة (نشر، migration إنتاج، push/release، مسّ أسرار) → تُصعّد لطلب موافقة المستخدم عبر project-manager.
- اكتشاف خطر أمني (P0/P1) → تصعيد فوري لـ security-auditor + إيقاف العمل المتأثر.
- تعارض لا يُحَل بين وكيلين في نطاقين → project-manager، وإن كان أمنياً فـ security-auditor.

## قاعدة خاصة باختبار الاختراق (Penetration testing)

- `penetration-testing-agent` يعمل **حصراً** في بيئة محلية أو staging مصرّح بها كتابةً؛ ممنوع لمس الإنتاج (`72.61.183.61`) أو أي نظام خارجي (`api.ftth.iq`).
- علاقته بـ `security-auditor-agent` تكاملية: المدقّق تحليلي بالقراءة ويحسم التصنيف، والمختبِر يتحقّق تطبيقياً (غير مدمّر) ضمن البيئة المعتمدة. أي تعارض في تصنيف خطر → الكلمة النهائية لـ `security-auditor-agent`.
- أي أداة تدخّلية/فحص قد يسبب أثراً → موافقة بشرية صريحة عبر `project-manager` قبل التشغيل.

## صيغة التقرير (Report format)
كل وكيل يُرجع: (1) ما أُنجز، (2) الملفات المتأثرة بمسارات مطلقة، (3) مخاطر/Unknowns، (4) ما يحتاج موافقة، (5) الخطوة التالية المقترحة. موجز، بلا إغراق بمحتوى الملفات.

## ترتيب تنفيذ المهام (Operating Model)
1. **Plan**: product-analysis/architecture يحددان النطاق والأثر.
2. **Guard**: security + database يراجعان المخاطر قبل التنفيذ إن لزم.
3. **Build**: backend/frontend/mobile/integration ينفّذون.
4. **Verify**: testing-qa + code-reviewer.
5. **Ship**: release-manager + devops بعد موافقة صريحة.
6. **Record**: knowledge-manager يحدّث الذاكرة (`TASK_HISTORY`, `DECISIONS`, `AGENT_IMPROVEMENT_LOG`).

## مبادئ
- الموافقة الصريحة شرط لأي عملية إنتاج/نشر/أسرار.
- لا وكيل يتجاوز Forbidden Scope الخاص به.
- التوثيق وتحديث الذاكرة جزء من إنهاء أي مهمة مهمة.
