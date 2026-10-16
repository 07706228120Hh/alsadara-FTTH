# برومبت Claude Code — ترحيل واجهات الصدارة إلى الثيم الموحّد

انسخ ما بين الخطّين والصقه في Claude Code داخل VS Code (من جذر المستودع C:\SadaraPlatform).

---

أنت تعمل على تطبيق Flutter «الصدارة» في `src/Apps/CompanyDesktop/alsadara-ftth`. المهمة: توحيد ثيم التطبيق وتحويل واجهاته إلى نمط ثلاثي الأبعاد (بطاقات وأزرار بارزة بحافّة سفلية، أيقونات مكعّبة، عدّادات على أعمدة مجسّمة) ومتجاوبة مع الهاتف والآيباد وسطح المكتب — شاشةً بعد شاشة، دون المساس بمنطق المشروع.

## اقرأ أولاً (إلزامي، بالترتيب)
1. `CLAUDE.md` في الجذر، وملفات `.claude/memory/` التي يطلبها، والتزم بقواعده الذهبية ونموذج الوكلاء (project-manager → الوكيل المختص → code-reviewer-agent → testing-qa-agent → documentation-agent). المختص بالواجهات: ui-ux-agent وmobile-agent؛ وحدة `lib/network_quality` يملكها network-quality-agent؛ وحدة `lib/sas_agent` يملكها وكلاء `sas-*`.
2. `docs/ui-unification/README.md` ثم `MIGRATION_PLAN.md` (الخطة والترتيب والمربعات) ثم `AUDIT.md` (تدقيق 249 شاشة) و`screens_audit.json`، والتصميم المرجعي للرئيسية `docs/ui-unification/design/home_3d_reference.html`.
3. `src/Apps/CompanyDesktop/alsadara-ftth/lib/frontend/README.md` — نظام التصميم الجديد (البادئة `Sd`): الرموز، الثيم، المكوّنات، قواعد التجاوب.

## ما هو موجود الآن
- `lib/frontend/` جديد ومستقل: `frontend.dart` (استيراد واحد)، `tokens/` (SdColors، SdGroup/SdStatus، SdSpace/SdRadius/SdDepth/SdMotion، SdText، sd_responsive: `context.sd`، SdAdaptive، SdTwoPane)، `theme/sd_theme.dart` (SdTheme.light() و SdTheme.scope)، `components/` (SdPage، SdAppBar، SdAppBarAction، SdMenuTile، SdTileGrid، SdIconCube، SdStatPedestal، SdCard، SdButton، SdRaised، SdFilterChips، SdToggle، SdStatusChip، SdBadge، SdSectionHeader، SdInfoRow، SdEmptyState)، `preview/` (معرض + نقطة تشغيل مستقلة).
- لم يُشغَّل عليه `flutter analyze` بعد، ولا يستورده أي ملف قديم.
- وحدة `lib/network_quality` مُعاد تصميمها مسبقاً بنمط 3D (`widgets/depth_3d.dart`) — هي المرجع البصري.

## القواعد (لا استثناء)
- **الواجهة فقط**: لا تغيّر المنطق، الخدمات، الصلاحيات (`permissionKey`/`PermissionManager`/`RequirePermission`)، التنقّل، استدعاءات API، أسماء الكلاسات العامة أو تواقيع البناء (constructors) التي تستدعيها ملفات أخرى.
- **ممنوع بدون موافقتي الصريحة**: تعديل `main.dart` أو `pubspec.yaml`، حذف أي ملف، تعديل AppTheme/AccountingTheme/EnergyDashboardTheme، تقسيم الملفات الضخمة، أي commit أو push أو tag أو نشر. توجد تعديلات غير محفوظة في المستودع ليست من عملك (مثل CLAUDE.md وpubspec.lock وproperty_detail_page.dart) — لا تلمسها.
- **لا ألوان مكتوبة يدوياً** في الشاشات المرحَّلة: استخدم `SdColors` و`SdGroup.x.tone` و`SdStatus.x.tone`. لون ناقص؟ أضفه في `lib/frontend/tokens/sd_colors.dart`.
- **لون لكل مجموعة لا لكل زر**: الميدان تركوازي، الإدارة نيلي، التواصل برتقالي، المنصّات بنفسجي، الأدوات رمادي.
- **أصغر خط 11.5**، أهداف لمس ≥ 48 على الأجهزة اللمسية، كل النصوص عربية RTL، المعرّفات والتعليقات الجديدة بالإنجليزية.
- **التجاوب إلزامي**: `context.sd` بدل الأرقام الثابتة؛ الجداول العريضة تتحوّل لبطاقات على الهاتف؛ اختبر كل شاشة على 390 و820 و1180 و1440.
- الملفات الضخمة (أكثر من 3000 سطر): رحّل الأجزاء المرئية تدريجياً (الشريط، البطاقات، الأزرار، الحوارات) دون إعادة كتابة الملف أو نقل منطقه.
- لا تُرحِّل الملفات المصنّفة «ميتة» في الخطة — اعرضها عليّ للحذف فقط.
- Flutter: `D:\flutter\flutter\bin\flutter.bat`.

## طريقة العمل لكل شاشة
1. اقرأ الملف كاملاً وحدّد: الشريط، البطاقات، الأزرار، الحوارات، الألوان والخطوط اليدوية، الأجزاء غير المتجاوبة.
2. اكتب خطة قصيرة (5–10 أسطر) بما سيتغيّر.
3. نفّذ: `SdPage` + `SdAppBar` بدل Scaffold/AppBar، `SdCard`/`SdButton`/`SdStatusChip`/`SdMenuTile`… بدل المكافئات المحلية، احذف ثوابت الألوان المحلية وما يقابلها من hex، طبّق `context.sd` للتجاوب.
4. تحقّق: `flutter analyze` على الملف (بلا أخطاء جديدة، والتحذيرات القديمة لا تزيد)، وراجع بالعين على العروض الأربعة إن أمكن التشغيل.
5. حدّث `docs/ui-unification/MIGRATION_PLAN.md` (`[x]`) وأضف سطراً في `PROGRESS_LOG.md`.
6. اعرض لي ملخصاً: ما تغيّر، ما لم يتغيّر، ونتيجة analyze — ثم انتقل للشاشة التالية في نفس الموجة. **توقّف وانتظر موافقتي في نهاية كل موجة.**

## ابدأ الآن بهذا الترتيب
1. الموجة 1: شغّل `flutter analyze lib/frontend` وأصلح أي خطأ داخل `lib/frontend` فقط، ثم شغّل المعرض: `D:\flutter\flutter\bin\flutter.bat run -d windows -t lib/frontend/preview/gallery_main.dart` وأخبرني لأراجعه.
2. بعد موافقتي: الموجة 2 بالترتيب — `widgets/permissions_gate.dart` ← `pages/login/premium_login_page.dart` ← `pages/home_page.dart` (اتبع «مواصفات الواجهة الرئيسية الجديدة» في MIGRATION_PLAN.md حرفياً).
3. ثم بقية الموجات كما في الخطة.

إن واجهت شيئاً غير واضح أو قراراً من قائمة «تحتاج موافقة»، توقّف واسألني بدل التخمين.

---
