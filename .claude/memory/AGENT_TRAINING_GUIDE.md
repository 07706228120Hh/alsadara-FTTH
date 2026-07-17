# AGENT_TRAINING_GUIDE — دليل تدريب الوكلاء

دليل شامل يُدرَّب عليه كل وكيل قبل العمل على منصة الصدارة. المالك: `01-agent-trainer-development-manager`.

## Project overview
منصة الصدارة: FTTH/ISP + تجارة إلكترونية، Multi-tenant بحسب `CompanyId`. الإصدار 2.2.25+304، branch `master`. خادم إنتاج وحيد `72.61.183.61`؛ مزوّد FTTH خارجي `185.239.19.3` قراءة فقط خلف Cloudflare.

## Architecture
Clean Architecture: `Sadara.API → Application → Domain ↔ Infrastructure → PostgreSQL`. التبعيات نحو الداخل، Domain بلا تبعيات. تفاصيل في `ARCHITECTURE.md`.

## Tech stack
.NET 9، EF Core 9 + Npgsql، PostgreSQL، Flutter/Dart، JWT Bearer + نظام صلاحيات مخصص، Firebase FCM، SignalR، GitHub Actions (Windows فقط)، Inno Setup، Docker.

## Directory ownership
راجع `PROJECT_STRUCTURE_FOR_AGENTS.md` (Ownership map) و`AGENT_REGISTRY.md`. لا تعمل خارج نطاقك المسموح.

## How agents SHOULD work
1. اقرأ الذاكرة ذات الصلة قبل البدء (Context + Structure + قواعد مجالك).
2. ابقَ ضمن Allowed Scope. عند تجاوز الحدود، نسّق مع المالك أو صعّد لـ project-manager.
3. اطلب موافقة صريحة قبل: النشر، تشغيل migration على الإنتاج، push/release، أي مسّ بالأسرار.
4. سجّل العمل في `TASK_HISTORY.md`، القرارات في `DECISIONS.md`، تحسينات الوكلاء في `AGENT_IMPROVEMENT_LOG.md`.
5. علّم الحقائق غير المؤكدة **Unknown** ولا تخترع.
6. قدّم تقريراً موجزاً بالنتائج والمسارات المطلقة المتأثرة.

## How agents should NOT work
- لا تنشر/تشغّل migration إنتاج/تدفع كوداً دون موافقة.
- لا تضع أسراراً في الكود/التقارير/الـ logs.
- لا تكتب على خادم FTTH الخارجي.
- لا تتجاوز عزل `CompanyId`.
- لا تنشئ ملفات توثيق غير مطلوبة، ولا تترك المهمة نصف منجزة.

## Approval rules
عمليات تحتاج موافقة صريحة: نشر VPS، migration إنتاج، git push/release، تعديل تعريفات الوكلاء (agent-trainer)، أي تغيير أمني حسّاس.

## Security rules
راجع `SECURITY_RULES.md`. تذكير P0: `.env`/`secrets/`/`.secrets/` في الشجرة — تحقق و لا تطبع قيمها واستدعِ security-auditor عند الشك.

## Database rules
راجع `DATABASE_RULES.md`. PostgreSQL، 84 migration، لا تشغيل إنتاج بلا موافقة، فلترة `CompanyId` دائماً، نسخة احتياطية قبل التغيير.

## Testing rules
راجع `testing-qa-agent`. التغطية حالياً هزيلة — أولوية للمسارات الحرجة (Auth, Accounting, Tenant isolation). أضف اختبارات مع كل إصلاح حرج.

## Documentation rules
حدّث الذاكرة (`knowledge-manager`/`documentation-agent`) عند أي قرار أو تغيير مهم. لا تنشئ ملفات `*.md` جديدة دون حاجة. الكتابة بالعربية + مصطلحات تقنية إنجليزية.
