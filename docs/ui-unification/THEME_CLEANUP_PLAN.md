# خطة التوحيد الكامل للثيم — إزالة الثيمات القديمة والألوان اليدوية

> المشروع: `src/Apps/CompanyDesktop/alsadara-ftth` — الفرع: `feature/ui-unification-sd`
> المرجع: `THEME_COMPLIANCE.md` (فحص 17-10-2026: 251 شاشة — 46 ملتزمة، 148 جزئية، 57 غير مرحّلة)
> الهدف: **صفر** ثيمات قديمة، **صفر** ألوان يدوية في الشاشات، كل شيء من `lib/frontend` (Sd) — **دون أي تغيير في سلوك التطبيق**.

---

## 0. قواعد الأمان (إلزامية في كل مرحلة)

1. **الواجهة فقط**: يُسمح بتغيير الألوان والخطوط والحواف والظلال وأغلفة الواجهة. **ممنوع** لمس: المنطق، الاستدعاءات (API/Firebase/VPS)، الحالة (state)، التنقّل، الصلاحيات، النماذج (models)، الخدمات، قواعد البيانات، `main.dart` (إلا بموافقة صريحة).
2. **دفعات صغيرة**: كل دفعة = وحدة واحدة أو ≤ 8 ملفات، وcommit مستقل باسم واضح، فيمكن التراجع عن دفعة واحدة دون غيرها (`git revert <commit>`).
3. **بوابة التحليل**: قبل كل دفعة وبعدها: `flutter analyze` — **ممنوع** أن يزيد عدد الأخطاء أو التحذيرات عن خط الأساس. أي زيادة = إصلاح فوري أو تراجع.
4. **بوابة البناء**: نهاية كل مرحلة: `flutter build windows --debug` + `flutter build apk --debug` ينجحان.
5. **بوابة الاختبار اليدوي**: قائمة الشاشات الحرجة (§9) تُفتح وتُجرَّب بعد كل مرحلة.
6. **أدوات آلية بوضع التجربة أولاً**: كل أداة تحويل تعمل أولاً `--dry-run` وتُخرج تقريراً بالتغييرات المقترحة، ثم التطبيق الفعلي بعد المراجعة.
7. **لا حذف ملفات** إلا في المرحلة 8 وبموافقة المالك على القائمة.
8. **لا push ولا deploy** دون موافقة المالك.
9. **مقاومة التراجع**: بعد المرحلة 7 يُمنع إضافة ألوان يدوية جديدة (فحص آلي).

---

## 1. خط الأساس — المرحلة 0 (يوم واحد)

| الخطوة | الأمر / الإجراء | المخرج |
|---|---|---|
| حفظ الحالة الحالية | `git add -A && git commit -m "chore: حفظ حالة ما قبل التنظيف"` ثم `git tag theme-cleanup-start` | نقطة رجوع مضمونة |
| خط أساس التحليل | `flutter analyze > docs/ui-unification/baseline_analyze.txt` | عدد الأخطاء/التحذيرات المرجعي |
| خط أساس الالتزام | `python3 docs/ui-unification/tools/theme_compliance.py` | `THEME_COMPLIANCE.md` المرجعي |
| لقطات مرجعية | لقطة شاشة لكل شاشة حرجة (§9) في `docs/ui-unification/screenshots/before/` | للمقارنة البصرية |
| بناء مرجعي | `flutter build windows --debug` | يجب أن ينجح |

---

## 2. المرحلة 1 — الخط: إزالة GoogleFonts (2,380 استدعاء)

**المشكلة**: الخط Cairo يُحمَّل من الإنترنت وقت التشغيل عبر `google_fonts` — بلا إنترنت يظهر خط احتياطي، وهو بطيء.

1. **تضمين الخط محلياً** (ترخيص OFL مجاني): `assets/fonts/cairo/Cairo-{Regular,Medium,SemiBold,Bold,ExtraBold,Black}.ttf`، وإضافته في `pubspec.yaml`:
   ```yaml
   fonts:
     - family: Cairo
       fonts:
         - asset: assets/fonts/cairo/Cairo-Regular.ttf
         - asset: assets/fonts/cairo/Cairo-Medium.ttf
           weight: 500
         - asset: assets/fonts/cairo/Cairo-SemiBold.ttf
           weight: 600
         - asset: assets/fonts/cairo/Cairo-Bold.ttf
           weight: 700
         - asset: assets/fonts/cairo/Cairo-ExtraBold.ttf
           weight: 800
         - asset: assets/fonts/cairo/Cairo-Black.ttf
           weight: 900
   ```
2. **أداة تحويل** `docs/ui-unification/tools/fonts_codemod.py`:
   - `GoogleFonts.cairo(ARGS)` → `TextStyle(fontFamily: SdText.family, ARGS)` (نفس الوسائط حرفياً).
   - `GoogleFonts.cairo(textStyle: X, ...)` → يُعلَّم للمراجعة اليدوية (لا يُحوَّل آلياً).
   - `GoogleFonts.cairoTextTheme(...)` / `roboto` / `poppins` / `notoSans*` → قائمة مراجعة يدوية (≈ 25 حالة).
   - يضيف `import '../../frontend/frontend.dart';` بالمسار النسبي الصحيح إن لم يوجد، ويحذف import `google_fonts` إذا لم يبقَ استخدام.
3. التطبيق على دفعات حسب الوحدة (§8)، مع بوابة التحليل بعد كل دفعة.
4. بعد آخر دفعة: حذف `google_fonts` من `pubspec.yaml` **فقط** إذا كان العدد = 0 (ملاحظة: حزمة `printing` تستخدم `PdfGoogleFonts` بشكل مستقل — لا تتأثر).

**قبول المرحلة**: `GoogleFonts.` = 0 خارج ملفات PDF، والتطبيق يعرض Cairo بدون إنترنت.

---

## 3. المرحلة 2 — الثيمات القديمة

### 3.1 `AccountingTheme` (2,295 استدعاء) — `lib/theme/accounting_theme.dart`
الحالة الحالية: **كل ألوانه أصبحت أسماء بديلة لـ `SdColors`** (جسر قائم) — لذلك الاستبدال آمن بصرياً 100%.

1. أداة `theme_alias_codemod.py` تقرأ ملف الثيم وتبني جدول التحويل تلقائياً من التعريفات نفسها، مثال:
   | قديم | جديد |
   |---|---|
   | `AccountingTheme.bgPrimary` | `SdColors.ground` |
   | `AccountingTheme.bgCard` | `SdColors.surface` |
   | `AccountingTheme.textPrimary` / `textDark` | `SdColors.ink` |
   | `AccountingTheme.textSecondary` | `SdColors.muted` |
   | `AccountingTheme.neonBlue` / `primary` | `SdColors.primary` |
   | `AccountingTheme.neonGreen` / `success` | `SdColors.success` |
   | `AccountingTheme.danger` | `SdColors.danger` |
   | `AccountingTheme.borderColor` | `SdColors.divider` |
   | `AccountingTheme.radiusMedium` (12) | `SdRadius.sm` |
   | `AccountingTheme.radiusLarge` (16) | `SdRadius.md` |
   | التدرّجات `neon*Gradient` | تدرّجات جديدة في `SdColors` (تُضاف أولاً) |
2. ما ليس له مقابل في Sd (دوال، أنماط نصوص، `salaryStatusColors`، الاستجابة في `accounting_responsive.dart`) يُنقل أولاً إلى `lib/frontend/tokens/` بأسماء Sd (مثل `SdText.tableHeader`، `SdStatus.salary`)، ثم يُحوَّل.
3. بعد أن يصبح العدد = 0: يُترك الملف القديم فارغاً بتعليق «مهمل» لدفعة واحدة، ثم يُحذف في المرحلة 8.

### 3.2 `EnergyDashboardTheme` (355 استدعاء، 1,851 سطراً) — شاشات مدير النظام
- ألوانه موصولة جزئياً بـ Sd (41 مرجعاً، 8 ألوان يدوية متبقية) + يحوي ودجات (`GlowingButton`، `AnimatedGlowCard`).
1. إكمال الجسر: الألوان الـ8 المتبقية → رموز Sd.
2. نقل الودجات المستخدمة إلى `lib/frontend/components/` (`SdGlowButton`، `SdGlowCard`) أو استبدالها بـ `SdButton`/`SdCard` إن كانت متطابقة وظيفياً.
3. نفس أداة الأسماء البديلة لتحويل `EnergyDashboardTheme.x` → `SdColors.y`.
4. حذف الملف في المرحلة 8.

### 3.3 `AppTheme` (2 استدعاء) و`themes.dart`
- يبقى `AppTheme.lightTheme` مؤقتاً لأنه مربوط في `main.dart`، ويُستبدل في المرحلة 7 بـ `SdTheme.light()` (بموافقة صريحة).

**قبول المرحلة**: `AccountingTheme.` = 0، `EnergyDashboardTheme.` = 0، والتحليل غير أسوأ من خط الأساس.

---

## 4. المرحلة 3 — الألوان اليدوية (4,523 `Colors.x` + 1,490 `Color(0x..)`)

### 4.1 توسيع الرموز أولاً (قبل أي تحويل)
إضافة ما ينقص في `sd_colors.dart` حتى يكون لكل استخدام دلالي رمز:
- درجات الحالات الأربع: `success/warning/danger/info` × (`base`, `edge`, `tint`, `tintEdge`, `text`) — موجودة.
- **مضاف**: `SdColors.inkSoft` (رمادي 700)، `SdColors.disabled`، `SdColors.overlay` (ظل الحوارات)، ألوان العلامات الخارجية (`whatsapp`، `telegram`، `excel`) للشعارات فقط.

### 4.2 جدول التحويل الدلالي (`color_codemod.py`)
| الأصل | الرمز الجديد | ملاحظة |
|---|---|---|
| `Colors.red`, `.shade600–900`, `0xFFE74C3C`, `0xFFF44336`, `0xFFD32F2F` | `SdColors.danger` | |
| `Colors.red.shade50/100` | `SdColors.dangerTint` | |
| `Colors.red.shade200/300` | `SdColors.dangerTintEdge` | |
| `Colors.green`, `.shade600–900`, `0xFF2E7D32`, `0xFF4CAF50`, `0xFF27AE60` | `SdColors.success` | |
| `Colors.green.shade50/100` | `SdColors.successTint` | |
| `Colors.orange`, `amber`, `deepOrange`, `0xFFFF9800` | `SdColors.warning` | نص برتقالي → `SdColors.warningText` |
| `Colors.orange.shade50/100` | `SdColors.warningTint` | |
| `Colors.blue`, `lightBlue`, `0xFF1565C0`, `0xFF1976D2`, `0xFF3498DB` | `SdColors.info` | داخل زر/شريط → `SdColors.primary` (مراجعة) |
| `Colors.indigo`, `0xFF1A237E`, `0xFF283593` | `SdColors.primary` | |
| `Colors.teal`, `cyan` | `SdColors.accent` | |
| `Colors.purple`, `deepPurple`, `pink`, `0xFF8E44AD`, `0xFF9C27B0` | `SdColors.platformBase` | |
| `Colors.grey.shade50` | `SdColors.surfaceAlt` | |
| `Colors.grey.shade100` | `SdColors.groundAlt` | |
| `Colors.grey.shade200` | `SdColors.divider` | |
| `Colors.grey.shade300` | `SdColors.edge` | |
| `Colors.grey`, `.shade400/500` | `SdColors.faint` | |
| `Colors.grey.shade600/700`, `grey[600/700]` | `SdColors.muted` | |
| `Colors.grey.shade800/900`, `0xFF2C3E50`, `0xFF1A1A2E`, `0xFF333333` | `SdColors.ink` | |
| `Colors.blueGrey` | `SdGroup.neutral.tone.base` | |
| `0xFF25D366` | `SdColors.whatsapp` | شعار فقط |
| `Colors.white`, `Colors.black`, `Colors.transparent` | **تبقى** | ليست ألواناً «هوية» |
| `.withOpacity(x)` / `.withValues(alpha:)` | تُحفظ كما هي على الرمز الجديد | |

### 4.3 قواعد الأداة
- تعمل على ملف/وحدة محددة فقط، تتجاهل التعليقات والنصوص.
- `Color(0x..)` بلا تطابق في الجدول: تُطابَق بأقرب رمز (فرق لوني ΔE < 6)، وإلا تُعلَّم **للمراجعة اليدوية** ولا تُلمس.
- لا تحوّل متغيرات من نوع `MaterialColor` أو استدعاءات `colorScheme`.
- تُخرج تقرير `color_codemod_<module>.md`: كل تغيير (سطر قبل/بعد) + قائمة الحالات المتروكة.
- تضيف import الـ frontend تلقائياً.

**قبول المرحلة**: `Colors.x` الدلالية = 0، `Color(0x..)` = 0 خارج `lib/frontend/tokens/` وملفات الشعارات/PDF المستثناة صراحة.

---

## 5. المرحلة 4 — المكوّنات الخام

| العنصر | العدد | البديل | الأسلوب |
|---|---|---|---|
| `AppBar(` | 82 | `SdAppBar` | يدوي موجّه (العنوان/الإجراءات/الرجوع) |
| `.styleFrom(` في الأزرار | 559 | حذف الألوان من `styleFrom` (يأخذها الثيم) أو `SdButton` | آلي للألوان فقط + يدوي للشكل |
| `Card(` | — | `SdCard` أو `Card` بالثيم الموحّد | يدوي |
| `TextStyle(fontSize: N)` خام | — | `SdText.*` حيث يتطابق الحجم | آلي بجدول (11.5→caption، 12–13→bodySm، 14→body، 16→titleSm، 18+→title) |
| `BoxDecoration` لبطاقات/حقول | — | `SdCard`/`SdRaised`/`inputDecorationTheme` | يدوي |
| كل صفحة | 205 بلا غلاف | `SdPage` أو `SdNavShell` أو `SdTheme.scope` | يدوي |

---

## 6. المرحلة 5 — موجات الترحيل حسب الوحدة

كل موجة تمرّ بالمراحل 1→4 على ملفاتها، ثم بوابات (§0). الترتيب من الأقل خطراً للأعلى:

| الموجة | الوحدة | ملفات رئيسية | السبب |
|---|---|---|---|
| A | `inventory` (23) | — | مرحّلة تقريباً، صفر ألوان — تجربة الأدوات |
| B | `network_quality`، `widgets`، `permissions` | 15 شاشة | صغيرة |
| C | `sas_agent` (25) | — | ألوان قليلة (233) |
| D | `whatsapp` + `task` | `whatsapp_server_settings_page`، `reports_page`، `technician_performance_page` | غير مرحّلة |
| E | `citizen_portal` + `pages/super_admin` | `super_admin_dashboard`، `company_details_page`، `unified_companies_page`، `sadara_portal_page` | Energy theme |
| F | `pages/accounting` | `client_accounts_page`، `journal_entries_page`، `compound_journal_entry_page`، `collections_page`، `cashbox_page` | AccountingTheme |
| G | `ftth` (46) | `subscriptions_page`، `user_details_page`، `subscription_details_page` | أكثر استخداماً — بحذر |
| H | الشاشات العملاقة | `ftth_operators_dashboard_page` (14,326 سطراً)، `subscription_details_page` (12,937) | تُقسَّم أولاً إلى ملفات أجزاء (widgets) دون تغيير السلوك، ثم تُرحَّل |
| I | `pages` المتبقية | `company_settings_page`، `server_data_page`، `local_storage_page`… | |

---

## 7. المرحلة 6 — الثيم العام

1. استبدال `AppTheme.lightTheme` بـ `SdTheme.light()` في `main.dart` (**بموافقة صريحة**)، مع الإبقاء على `AppTypography` كامتداد.
2. إزالة `SdTheme.scope` المكرّر من الصفحات (يصبح غير لازم).
3. وضع الثيم الداكن: يُصمَّم لاحقاً (`SdTheme.dark()`) — خارج النطاق الحالي.

---

## 8. المرحلة 7 — الحذف والحماية من التراجع

1. **حذف الثيمات القديمة** (بعد أن تصبح استدعاءاتها 0 وبموافقة): `accounting_theme.dart`، `energy_dashboard_theme.dart`، `themes.dart`، ثم `app_theme.dart` بعد المرحلة 6. يبقى `accounting_responsive.dart` إلى أن تُنقل وظائفه لـ `sd_responsive.dart`.
2. **الشاشات الميتة** (43 مرشحاً في `AUDIT.md`، منها: `modern_home_page`، `enhanced_home_page`، `tktats_page_beautiful`، `test_pop.dart`، `dashboard_page`): التحقق بـ grep أنها غير مستوردة → عرض القائمة على المالك → حذف بموافقة.
3. **فحص آلي يمنع التراجع**: `theme_compliance.py --check` يفشل إذا ظهر `Color(0x` أو `Colors.<لون>` أو `GoogleFonts.` أو ثيم قديم خارج `lib/frontend/tokens`. يُضاف كـ pre-commit hook وخطوة CI.
4. **قاعدة في `CLAUDE.md`**: «كل لون من SdColors، كل خط من SdText، كل صفحة بـ SdPage/SdNavShell».

---

## 9. الشاشات الحرجة للاختبار اليدوي بعد كل مرحلة

تسجيل الدخول (موظف/مدير) • الرئيسية • رئيسية FTTH • البحث عن مشترك • تفاصيل المشترك (تجديد، تعليق، الجلسات، التحكم بالراوتر) • تفاصيل الاشتراك + PDF • المهام • التذاكر • الحسابات (قيود، صندوق، تحصيل) • لوحة مدير النظام • إدارة الشركات • الواتساب • فحص جودة الإنترنت • الإعدادات • تسجيل الخروج.
لكل شاشة: تفتح بلا خطأ، الأزرار تعمل، النصوص مقروءة (تباين ≥ 4.5:1)، لا تجاوز (overflow) على 360px و1440px.

---

## 10. مؤشرات التقدّم (تُحدَّث بعد كل موجة من `theme_compliance.py`)

| المؤشر | البداية | بعد المراحل 1–3 (17-10) | الهدف |
|---|---|---|---|
| شاشات ملتزمة بالكامل | 46 / 251 | 57 | 251 (أو المتبقي بعد حذف الميت) |
| `Color(0x..)` في الشاشات | 1,490 | 435 | 0 |
| `Colors.<لون>` | 4,523 | 423 | 0 |
| `GoogleFonts.` | 2,380 | 10 | 0 |
| `AccountingTheme.` | 2,295 | 84 | 0 |
| `EnergyDashboardTheme.` | 355 | 31 | 0 |
| `AppBar(` خام | 82 | 82 | 0 |
| ألوان في `styleFrom` | 559 | 559 | 0 |
| أخطاء `flutter analyze` | خط الأساس | يُنتظر | ≤ خط الأساس |

---

## 11. التقدير الزمني

| المرحلة | الجهد التقريبي |
|---|---|
| 0 — خط الأساس | يوم |
| 1 — الخط | 1–2 يوم (آلي + مراجعة) |
| 2 — الثيمات القديمة | 2–3 أيام |
| 3–4 — الألوان والمكوّنات (الموجات A→I) | 2–3 أسابيع |
| 6 — الثيم العام | يوم |
| 7 — الحذف والحماية | 1–2 يوم |

---

## 12. أمر التنفيذ لـ Claude Code (مرحلة بمرحلة)

> نفّذ `docs/ui-unification/THEME_CLEANUP_PLAN.md` **مرحلة واحدة في كل جلسة**. ابدأ بالمرحلة 0.
> التزم بقواعد §0 حرفياً: تغييرات واجهة فقط، دفعات صغيرة بـ commit لكل دفعة، `flutter analyze` قبل/بعد (لا زيادة عن خط الأساس)، الأدوات بوضع `--dry-run` أولاً مع تقرير، ولا حذف/push/deploy/تعديل `main.dart` دون موافقتي.
> في نهاية كل مرحلة: شغّل `theme_compliance.py`، حدّث جدول §10 و`PROGRESS_LOG.md`، واعرض عليّ الملخص وانتظر موافقتي قبل المرحلة التالية.
