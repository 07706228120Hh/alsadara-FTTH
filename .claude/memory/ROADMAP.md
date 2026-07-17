# ROADMAP — خارطة الطريق

أولويات وخطط منصة الصدارة مبنية على `RISKS.md`. تُراجَع دورياً مع `product-analysis-agent` و`project-manager`.

## P0 — Critical (فوري)
- تأمين الأسرار: التحقق من `.gitignore`/تاريخ git لـ `.env`/`secrets/`/`.secrets/`، وتدوير أي مفتاح مكشوف.
- تدقيق صلاحيات `DatabaseAdminController` + `SuperAdminController`.

## P1 — High
- فحص وإزالة `tmp_*.json` من الريبو والتاريخ إن احتوت بيانات.
- تنظيف الريبو من binaries الضخمة + `node_modules` + ملف `NUL`.
- حل Cloudflare الجذري للـ FTTH (whitelist IP) بدل الجسر المؤقت.

## P2 — Medium
- رفع تغطية الاختبارات للمسارات الحرجة.
- أتمتة نشر backend آمن (CD مع gates ونسخ احتياطية).
- توثيق طبيعة `CitizenWeb` (Blazor vs Flutter) وحسم التعارض.

## P3 — Low
- توحيد وثائق/أدلة البناء وإزالة التكرار.
- مراجعة الفهارس وخطط الاستعلام.

## Suggested phases
1. **Phase 0 — Secure**: P0 كاملاً (أسرار + admin endpoints).
2. **Phase 1 — Clean & Stabilize**: P1 (تنظيف الريبو + تثبيت Cloudflare).
3. **Phase 2 — Quality & Automation**: P2 (اختبارات + CD + توثيق CitizenWeb).
4. **Phase 3 — Polish**: P3 (توحيد التوثيق + تحسينات الأداء/الفهارس).

## First 10 recommended tasks
1. فحص `.gitignore` وتاريخ git لتأكيد عدم تسريب `.env`/secrets، وتدوير المفاتيح إن لزم. (security-auditor)
2. مراجعة صلاحيات كل endpoint في `DatabaseAdminController`. (security-auditor + backend)
3. مراجعة صلاحيات كل endpoint في `SuperAdminController`. (security-auditor + backend)
4. فحص محتوى `tmp_*.json` وإزالتها من الريبو/التاريخ. (devops + security)
5. تنظيف binaries/`node_modules`/`NUL` من الريبو وضبط `.gitignore`. (devops)
6. تنفيذ حل Cloudflare الجذري (whitelist IP) للـ FTTH. (integration + devops)
7. كتابة اختبارات للمسار الأمني: إصدار/تحقق JWT وعزل `CompanyId`. (testing-qa + security)
8. كتابة اختبارات لمنطق المحاسبة (قيود FTTH). (testing-qa + backend)
9. تصميم CD آمن للـ backend مع نسخ احتياطية وموافقة. (devops + release-manager)
10. تحقيق وتوثيق طبيعة `CitizenWeb` وتحديث الذاكرة. (frontend + documentation)
