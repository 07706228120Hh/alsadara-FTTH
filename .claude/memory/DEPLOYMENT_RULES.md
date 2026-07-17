# DEPLOYMENT_RULES — قواعد النشر

قواعد إلزامية لنشر منصة الصدارة. المالك: `devops-agent` + `release-manager-agent`. لا نشر دون موافقة صريحة.

## بيئة النشر
- **خادم الإنتاج الوحيد**: VPS رئيسي `72.61.183.61` (API + PostgreSQL). النشر دائماً هنا فقط.
- **خادم FTTH خارجي** `185.239.19.3`: ليس ملكنا، قراءة فقط، لا نشر إطلاقاً.

## نشر Backend (يدوي عبر SCP)
- الطريقة السريعة (DLLs المتغيرة فقط): `dotnet publish -c Release` → `scp` للـ DLLs الأربعة → `systemctl restart sadara-api`.
- الطريقة الكاملة (عند تغيير حزم NuGet): tar للحزمة كاملة → نقل → استبدال → restart.
- **كل نشر يحتاج موافقة صريحة من المستخدم** قبل التنفيذ.

## نشر التطبيق (Flutter FTTH)
- البناء: `D:\flutter\flutter\bin\flutter.bat build windows --release`.
- التغليف: Inno Setup (`installer.iss`) عبر `C:\Program Files (x86)\Inno Setup 6\ISCC.exe` → `Alsadara-Setup-v<ver>.exe`.
- النشر: GitHub Release على `07706228120Hh/alsadara-FTTH` → التطبيق يحدّث عبر `auto_update_service`.

## CI/CD
- GitHub Actions: `.github/workflows/build-windows.yml` يبني مثبّت Windows فقط.
- **لا يوجد CD مؤتمت للـ backend** — النشر يدوي. (خطر بشري — راجع `RISKS.md`).
- Docker: `docker/Dockerfile` + `docker/docker-compose.yaml` متاحة.

## ما يحتاج موافقة صريحة
- أي `scp`/`ssh`/`systemctl` على VPS الإنتاج.
- أي `git push` أو إنشاء GitHub Release.
- أي تغيير على إعدادات الإنتاج أو الأسرار.
- تطبيق migration على الإنتاج (راجع `DATABASE_RULES.md`).

## سلامة الإنتاج / Rollback
- خذ نسخة/snapshot قبل أي نشر يمسّ القاعدة.
- احتفظ بالـ DLLs/الحزمة السابقة للتراجع السريع.
- في حال فشل الخدمة بعد restart: راجع `journalctl -u sadara-api` واسترجع النسخة السابقة.

## Logs / Monitoring
- سجلات الخدمة عبر `systemctl`/`journalctl -u sadara-api` على VPS.
- مراقبة موارد VPS متاحة عبر Hostinger MCP (لا يدعم رفع ملفات — النشر يبقى SCP).

## ممنوعات
- لا push/deploy/release بدون موافقة صريحة. لا نشر على غير `72.61.183.61`. لا كتابة على خادم FTTH الخارجي. لا تخطّي hooks أو التوقيع.
