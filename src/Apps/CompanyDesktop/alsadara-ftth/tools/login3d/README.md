# مدينة الصدارة ثلاثية الأبعاد (خلفية تسجيل الدخول)

- `scene.js` — المشهد (Three.js r160): برج الصدارة الملتف، المدينة الممتدة، الألياف والنبضات، السيارات، المباني التفاعلية، Bloom.
- `template.html` — الغلاف (بطاقة التفاصيل، التسمية، التلميح) + مكان الإعدادات `/*SD_CONFIG*/`.
- `build.sh` — يحزّم كل شيء في `assets/login3d/city.html` (ملف واحد ~560KB، بلا إنترنت).
- الواجهة في Flutter: `lib/frontend/components/sd_login_3d.dart` (`SdLogin3DBackground`).

## الإعدادات التي يمرّرها Flutter
`window.SD_CFG = { shiftX, quality: 'high'|'low', interactive, logo }`

## تعديل المباني التفاعلية
عدّل `heroDefs` في `scene.js` (الاسم، النوع، الطوابق، المشتركين، المتصلين، الإشارة، FAT) ثم شغّل `bash build.sh`.
لاحقاً يمكن تمرير بيانات حقيقية عبر `SD_CFG`.
