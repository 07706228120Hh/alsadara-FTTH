# RISKS — سجل المخاطر

سجل المخاطر المرصودة في منصة الصدارة مرتّبة بالأولوية. يُحدَّث عند اكتشاف/معالجة أي خطر.

| Risk | Level | Area | Impact | Recommendation | Status |
|------|-------|------|--------|----------------|--------|
| **سلسلة استغلال**: مفتاح API داخلي ثابت كـ fallback (`DatabaseAdminController.cs:26`) ونفسه مسرّب في ملفات n8n متتبَّعة | P0 | Security/Auth+Secrets | أي نشر بلا ضبط `SADARA_INTERNAL_API_KEY` يجعل المفتاح المعروف عالمياً صالحاً → سيطرة إدارية كاملة | إزالة الـ fallback (فشل-آمن)، تدوير المفتاح، نقله لـ Credentials في n8n | **Partially Mitigated (2026-06-26)**: أُزيل fallback الكود في `DatabaseAdminController` (المرحلة 1) — لكن **القيمة نفسها ما زالت في `appsettings.json:42`** فالسلسلة لم تُغلق بعد |
| **حرج مكتشَف بالمراجعة**: القيم المسرّبة (Jwt:Secret، InternalApiKey) مكتوبة نصّاً في `appsettings.json` (سطر 20، 42) — ملف يُحتمل تتبّعه في git | P0 | Security/Secrets | إزالة fallback الكود وحده «dead branch»؛ السلسلة تبقى مفتوحة ما دام appsettings يحوي القيمة المسرّبة | المرحلة 1c (بموافقة): إزالة القيم من appsettings وحقنها من env/secret store + تدوير | Open (محقّق 2026-06-26) |
| نمط fallback ثابت منتشر في 11+ موضعاً (`Program.cs:54,91`, `FtthAccountingController:2768` يقارن بالثابت مباشرة, +9 controllers) | P1 | Security/Auth | إغلاق DatabaseAdmin وحده لا يغلق السطح الكامل | المرحلة 2: إزالة الـ fallbacks وتوحيد مصدر السرّ (توليد/تحقق) | Open (محقّق 2026-06-26) |
| `DatabaseAdminController` endpoints تدميرية (حذف/تحديث أي جدول، cleanup، تصدير كامل) بلا عزل مستأجر — `IgnoreQueryFilters` ×106 | P0 | Security/Auth+Tenancy | تسريب المفتاح = حذف/تصدير بيانات **كل الشركات** | `[Authorize(Policy=SuperAdmin)]` على الـ class + إزالة fallback + تدقيق + تقييد cleanup | Open (محقّق) |
| `SuperAdminController` يحوي 9 مواضع `[AllowAnonymous]` تتجاوز policy الـ class على مسارات حسّاسة (الشركات/الـ dashboards/VPS/health) | P0 | Security/Auth | كشف بيانات كل الشركات + حالة البنية التحتية بالمفتاح المسرّب فقط | إزالة `[AllowAnonymous]` والاعتماد على policy الـ class | Open (محقّق) |
| أسرار تشغيلية مسرّبة نصّاً في ملفات n8n المتتبَّعة: WhatsApp `verify_token`، `X-Webhook-Secret`، username حساب FTTH | P0 | Security/Secrets | انتحال webhook واتساب + كشف نصف بيانات دخول FTTH | تدوير الأسرار في مصادرها (Meta/n8n) + نقلها لـ Credentials + إزالتها من المصدر | Open (محقّق) |
| JWT secret كـ fallback ثابت (`SuperAdminController.cs:227`) | P1 | Security/Auth | تزوير توكنات SuperAdmin إن لم يُضبط `Jwt:Secret` | إزالة الـ fallback (فشل-آمن) | Open (محقّق) |
| CORS سياسة واحدة `AllowAll` (AllowAnyOrigin) لكل البيئات | P2 | Security/Config | Origin مفتوح؛ يتفاقم لو أُضيف AllowCredentials | قائمة Origins صريحة لبيئات غير التطوير | Open (محقّق) |
| لا rate limit مشدّد على مسارات المصادقة (`*/login`) — حدّ عام 600/د/IP فقط | P2 | Security/Config | سطح أوسع لتخمين كلمات المرور | سياسة rate limit منفصلة أشدّ على المصادقة | Open (محقّق) |
| ملاحظة إيجابية: `.env`/`secrets/`/`.secrets/` متجاهَلة وغير متتبَّعة و`.env` لم يُلتزم أبداً؛ `.env.example` placeholders؛ `accessToken` في ملف CREDENTIALS مجرد مرجع | Info | Security/Secrets | لا تسريب من هذه المصادر | لا إجراء (إبقاء `.gitignore` كما هو) | Verified Clean |
| ملفات `tmp_*.json` بالجذر (مثل `tmp_exec_detail.json` ~1.6MB، `tmp_n8n*.json`) | P1 | Data leak | قد تحوي بيانات/أسرار حقيقية ملتزمة بالريبو | فحص المحتوى، إزالتها من الريبو والتاريخ إن لزم | Open |
| binaries ضخمة (zip 30-44MB) + `node_modules` ملتزمة بالريبو + ملف `NUL` غريب | P1 | Repo hygiene | تضخّم الريبو وبطء وعمليات هشّة | تنظيف الريبو، `.gitignore`, git-lfs/إزالة | Open |
| اعتماد كامل على مزوّد FTTH خارجي (`api.ftth.iq`) خلف Cloudflare | P1 | Integration | انقطاع المزامنة عند حجب Cloudflare → توقف وظائف FTTH | حل جذري whitelist IP بدل جسر `FtthCloudflareGateway` المؤقت | Open |
| تغطية اختبارات شبه معدومة مقابل 57 controller | P2 | Testing/QA | انحدارات غير مكتشفة، هشاشة عند التغيير | رفع التغطية للمسارات الحرجة (Auth, Accounting, Tenancy) | Open |
| 84 migration مقابل DB إنتاج بلا CD مؤتمت | P2 | Deployment/DB | خطأ بشري عند النشر اليدوي → فقدان/تلف بيانات | أتمتة نشر آمن + نسخ احتياطية + gates موافقة | Open |
| تعارض توصيف `CitizenWeb` (README Blazor vs كود Flutter) | P2 | Docs/Frontend | لبس معماري يربك الصيانة والتطوير | تحقق وتوثيق الطبيعة الفعلية للتطبيق | Open |
| تكرار وثائق/أدلة بناء متعددة في الجذر | P3 | Docs | تشتت وتعارض إرشادات | توحيد التوثيق وإزالة المكرر | Open |
