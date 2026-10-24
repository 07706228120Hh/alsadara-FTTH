# دفعة النشر المعلّقة — FTTH الشركاء (غير منشورة بعد)

> المستخدم يجمّع تعديلات ليُنشرها دفعةً واحدة لاحقاً. **كل شيء ملتزَم (commits) وبناؤه أخضر — لم يُنشر/يُصدَر بعد.** هذا الملف يتتبّع ما ينتظر النشر حتى لا يضيع.

**آخر ما نُشر فعلاً**: v2.4.24 (الباكند deploy `20261024_210513` + تطبيق v2.4.24). كل ما بعده ينتظر.

## معلّق — الباكند (فرع `feature/ftth-credentials-unification`)
| commit (تقريبي) | التغيير |
|------|------|
| فلتر الشريك | `operators-dashboard` يقبل `partnerId` ويفلتر العمليات بالشريك (يحلّ معرّف الكيان→PartnerAccountId) |
| حقول العمليات | `GET /api/internal/subscriptionlogs` يُعيد `PartnerId` + `OperatorUsername` (لحلّ اسم الشريك بالواجهة) |

نشرها: `git checkout feature/ftth-credentials-unification && bash deploy/deploy-backend.sh` (بموافقة).

## معلّق — التطبيق (فرع `release/v2.4.25`، الإصدار v2.4.25+340، مبنيّ)
- فلتر «الشريك» في تبويب «خادمنا» (قائمة من getPartners → `&partnerId=` للباكند).
- عمود «الشريك» في شاشة «كل العمليات» (يحلّ `partnerId` معرّف FTTH → اسمك عبر خريطة PartnerAccountId).
- الملفّات مبنيّة: `build/installer/Alsadara-Setup-v2.4.25.exe` + `build/app/outputs/flutter-apk/app-release.apk`.

إصداره: دفع `release/v2.4.25` + `gh release create v2.4.25 --latest ...` (بموافقة؛ وسم يصل كل الأجهزة).

## مؤجَّل — لم يُنفَّذ بعد
- **#7 القيود (JournalEntry)**: إظهار الشريك في القيود — يحتاج ربط `SubscriptionLog` (حيث `JournalEntryId==entry.Id`) لجلب `PartnerName`، + عمود بالواجهة في `journal_entries_page.dart`. (المشغّل ظاهر أصلاً في وصف القيد.)
- **#4 تنظيف الحسابات المكرّرة** (`07807065068` ×3، `hnwnly277` ×2) — يتولّاه المالك.
- **#8 sajar** (كلمة مرور خاطئة/Invalid) — يتولّاه المالك.
- أي نتائج فحص تشغيلي محلّي (تُضاف هنا).

## بعد النشر (إلزامي للتحقّق)
- **إعادة مزامنة «كل الشركاء»** لتملأ `OperatorUsername` (كان 0) وتوحّد الشريك على العمليات.
- التحقّق من المطابقة (شريك+مشغّل → الموظف) والافتراض الحرج (هل الرئيسي يرى كل الفروع؟).
