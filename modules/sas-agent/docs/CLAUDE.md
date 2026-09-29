# CLAUDE.md — دليل مشروع «تطبيق الوكلاء» (Aluklaa) لـ Claude Code

> **منتج مستقل بالكامل.** فُصل عن مونوريبو «منصة العراق الرقمية» (olt-manager) ليُطوَّر ويُوزَّع باستقلالية:
> ملف تنصيب ويندوز (`AluklaaSetup.exe`) — وربما تطبيق هاتف (أندرويد/iOS) لاحقاً.
> لا يعتمد على تطبيقات المنصّة الأخرى (الوزارة/الشركات/المشتركون) في التشغيل.

## نظرة عامة

تطبيق **Flutter** لإدارة عمل الوكيل عبر نظام **SAS** الخاص بمزوّده، مع باكند **FastAPI** واحد يخدمه.
- **الوكيل** يدخل بحسابه فيرى: لوحته · مشتركيه (من SAS) · نظام SAS · تذاكر مشتركيه · تصريحه الشهري (البلنك) · الإعدادات.
- **الأدمن المبيّت** (حساب بدور `admin`/`operator`) يدخل نفس التطبيق فيرى: إدارة الوكلاء وإصدار حساباتهم · التذاكر · الإعدادات.

> **مهم:** المسار يجب أن يكون **لاتينياً** (`C:\AluklaaApp`) لبناء/تشغيل تطبيق ويندوز — أداة فلاتر (MSBuild/CMake) لا تتعامل مع الحروف العربية في المسار، وملفات `.bat` يجب أن تبقى **ASCII فقط**.

## أوامر التشغيل

```bat
:: تشغيل بنقرة واحدة (يبدأ الخادم ثم يفتح التطبيق)
run_windows_app.bat

:: الباكند يدوياً (تطوير)
cd backend && start_backend.bat          :: http://127.0.0.1:8000  ·  التوثيق: /docs
::   وضع محلي افتراضي: USE_MOCK_OLT=true · SEED_DEMO_DATA=true (بذرة وكيل تجريبي)

:: بناء تطبيق ويندوز
cd frontend && flutter build windows --release --dart-define=API_BASE=http://127.0.0.1:8000

:: إعادة بناء الخادم المستقل (PyInstaller)
cd backend && .venv\Scripts\pyinstaller backend.spec --noconfirm
```

**الدخول التجريبي:** الوكيل `wakil`/`wakil123` · الأدمن `admin`/`admin` (غيّرها في الإنتاج).

## المعمارية والملفات المفتاحية

```
AluklaaApp/
├── frontend/                       تطبيق الوكيل (Flutter)
│   └── lib/
│       ├── main.dart               التوجيه: وكيل → واجهة الوكيل · أدمن → واجهة الأدمن
│       └── screens/                dashboard · subscribers · report · settings · admin_agents
├── packages/platform_core/         الحزمة المشتركة (نظام التصميم + API + الجلسة + شاشات SAS/التذاكر/الدخول)
│   └── lib/src/{api,auth,screens,theme,widgets,shell}/
├── backend/                        FastAPI — باكند واحد
│   └── app/
│       ├── main.py                 نقطة الدخول + الحلقات الخلفية
│       ├── config.py               الإعدادات (يدعم ALUKLAA_DATA_DIR لقاعدة قابلة للكتابة)
│       ├── api/                    auth · companies(SAS) · portal · subscriber · tickets · agents · … (+ راوترات OLT محفوظة)
│       ├── services/               sas_sync · otp · tickets · agents · … (+ خدمات OLT محفوظة)
│       ├── integrations/sas_client.py   عميل SAS4
│       └── knowledge/sas4_api_reference.md   مرجع SAS4 (66 نقطة)
├── installer/aluklaa.iss           سكربت Inno Setup → AluklaaSetup.exe
└── .claude/agents/                 منظومة الوكلاء المتخصّصين (25 + المدير)
```

**ميزات OLT/المنصّة محفوظة لا محذوفة**: كل كود إدارة أجهزة OLT/المراقبة/التزويد/SNMP/التشخيص باقٍ في الباكند، لكنه **غير مُفعَّل في واجهة الوكيل** ويُعرَض كمداخل مؤجّلة في تبويب «الإعدادات → متقدّم» للاستفادة لاحقاً.

## المصادقة والنطاقات

- الباكند يشتقّ نوع الحساب (`kind`) من النطاق: `agent` (له نطاق وكيل) · `company` (له شركة) · `regulator` (بلا نطاق). و«أدمن» **دور** فوقها.
- شاشة الدخول (`StaffLoginScreen`) بلا `expected` → تقبل الوكيل والأدمن؛ التوجيه في `main.dart` حسب النوع والدور.
- SAS: الوكيل يتصل بحساب المدير الخاص به (اسم مستخدم + كلمة مرور)؛ عنوان الخادم موروث من إعداد شركته.

## النشر الهجين

| الهدف | الخادم | قاعدة البيانات | العنوان في التطبيق |
|---|---|---|---|
| ويندوز محلي | `backend.exe` مضمّن | SQLite في `%LOCALAPPDATA%\Aluklaa` (عبر `ALUKLAA_DATA_DIR`) | `API_BASE=http://127.0.0.1:8000` |
| سحابي/هاتف | مستضاف | Postgres (`DATABASE_URL=postgresql+psycopg://…`) | `API_BASE=https://api.<domain>` |

## منظومة الوكلاء المتخصّصين

`.claude/agents/` يحوي **مديراً + 24 وكيلاً**. ابدأ المهام الكبيرة بـ `project-manager`. لا يعمل وكيلان على نفس الملف بالتوازي. أي كود يُكتب يُتحقَّق منه فوراً (`code-reviewer` + وكيل اختبار).

## الأعراف

- توافق ويندوز: مسار لاتيني · `.bat` بـ ASCII فقط · عنوان الخادم عبر `--dart-define=API_BASE=` (لا عنوان مضمّن).
- نماذج الذكاء: `claude-sonnet-4-6` (افتراضي) — يُضبط عبر `AI_MODEL`.
- التحقّق: `cd packages/platform_core && flutter analyze` · `cd frontend && flutter analyze` · `cd backend && pytest -q`.
