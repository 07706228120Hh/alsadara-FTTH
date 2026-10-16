# خطة تنسيق الباكند تدريجياً وبأمان (dotnet format)

الهدف: توحيد تنسيق كود .NET دون أي خطر على المشروع. المبدأ: **لا تغيير سلوك — تنسيق فقط**، على دفعات صغيرة
قابلة للمراجعة، مع بناء واختبار وموافقة بعد كل دفعة. أي شكّ ⇒ توقّف واطلب موافقة.

## القواعد الذهبية لهذه العملية
1. **فرع منفصل فقط** (مثل `chore/dotnet-format`) — لا على `main` ولا على فرع إصدار.
2. **لا تلمس أبداً** مجلد `src/Backend/Core/Sadara.Infrastructure/Data/Migrations/**` — تعديل أي migration ممنوع
   (قاعدة CLAUDE.md). يُستثنى بـ `--exclude`.
3. **دفعة = مشروع واحد** (الأصغر أولاً) + **نوع تنسيق واحد** (مسافات، ثم نمط، ثم analyzers) + **commit مستقل**.
4. بعد كل دفعة: `dotnet build` + `dotnet test tests/Sadara.Integration.Tests` يجب أن ينجحا قبل الـ commit.
5. راجع الـ diff بصرياً قبل كل commit؛ إن ظهر أي تغيير غير تنسيقي (منطق/سلوك) ⇒ ألغِ الدفعة (`git restore`).
6. لا نشر ولا دمج في `main` إلا بموافقة صريحة ومرور `code-reviewer-agent`.

## الخطوة 0 — تثبيت القواعد أولاً (`.editorconfig`)
بدون `.editorconfig` يطبّق `dotnet format` افتراضاته، فتختلف النتيجة بين الأجهزة. نضيف ملفاً واحداً في جذر المستودع
يحدّد القواعد بوضوح (مسافات/أقواس/using/إلخ). هذا الملف نفسه **لا يغيّر كوداً** — إنما يجعل التنسيق حتمياً.
يُراجع ويُعتمد قبل أي تنسيق فعلي.

## الترتيب (الأصغر → الأكبر لتقليل حجم كل diff)
| الدفعة | المشروع | عدد ملفات `.cs` | ملاحظة |
|--------|---------|------------------|--------|
| 1 | `Sadara.Application` | ~12 | الأصغر — نبدأ به لاختبار العملية كاملة |
| 2 | `Sadara.Domain` | ~62 | كيانات — راجع أنها تنسيق فقط |
| 3 | `Sadara.API` | ~75 | controllers — راجع عدم تغيّر توجيهات/سمات |
| 4 | `Sadara.Infrastructure` | ~131 | **مع استثناء مجلد Migrations** |

## أنواع التنسيق (الأخفّ أولاً، كلٌّ في commit مستقل)
1. **المسافات فقط** (الأأمن، لا يغيّر رموزاً): `dotnet format whitespace`
2. **النمط** (style: using/تنسيق تعابير): `dotnet format style`
3. **المحلّلات** (analyzers — الأكثر تأثيراً، اختياري): `dotnet format analyzers`

نكتفي بـ 1 و2 ابتداءً، ونؤجّل 3 لقرار لاحق.

## الأوامر (مثال للدفعة 1 — مسافات فقط)
```bash
git switch -c chore/dotnet-format                       # مرة واحدة
# معاينة بلا تعديل (ماذا سيتغيّر؟)
dotnet format whitespace src/Backend/Core/Sadara.Application/Sadara.Application.csproj --verify-no-changes -v diag
# التطبيق الفعلي على مشروع واحد
dotnet format whitespace src/Backend/Core/Sadara.Application/Sadara.Application.csproj
git diff --stat                                         # راجع
dotnet build SadaraPlatform.sln && dotnet test tests/Sadara.Integration.Tests
git add -A && git commit -m "style(application): dotnet format whitespace"
```
للدفعة 4 (Infrastructure) أضف استثناء الهجرات:
```bash
dotnet format whitespace src/Backend/Core/Sadara.Infrastructure/Sadara.Infrastructure.csproj \
  --exclude "**/Data/Migrations/**"
```

## التراجع
- دفعة لم تُحفظ بعد: `git restore .`
- دفعة مُرتكبة: `git revert <commit>` (تبقى على الفرع، لا على `main`).
- لا شيء يصل الإنتاج: النشر عبر `deploy/deploy-backend.sh` بموافقة منفصلة فقط.

## لماذا هذا آمن
`dotnet format` لا يغيّر منطق التنفيذ — فقط المسافات/الأقواس/ترتيب using. البناء + الاختبارات + مراجعة الـ diff بعد
كل دفعة صغيرة يكشفان أي شذوذ فوراً، واستثناء الهجرات يحمي أخطر جزء. كل دفعة قابلة للتراجع وحدها.
