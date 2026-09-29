# تطبيق الوكلاء — مشروع مستقل

نسخة **مستقلة كاملة** من تطبيق الوكيل، مفصولة من مونوريبو `olt-manager` (منصّة العراق الرقمية) لتطويرها ونشرها باستقلالية.

يدخل به **وكيل الشركة** (Manager في نظام SAS، حساب بنطاق `scope_company_id + scope_agent`) ويرى: لوحته · مشتركيه · نظام SAS الخاص بمشتركيه · تذاكر مشتركيه · تصريحه الشهري (البلنك).

## البنية

```
تطبيق الوكلاء/
├── frontend/                 # تطبيق الوكيل (Flutter) — كان apps/agents_app في المونوريبو
├── backend/                  # باكند FastAPI كامل (يخدم التطبيق: مصادقة، بوابة وكيل، بروكسي SAS، تذاكر، بلنك)
└── packages/platform_core/   # الحزمة المشتركة (عميل API، الجلسة، نظام التصميم الموحّد، الودجات)
```

`frontend/pubspec.yaml` يشير إلى الحزمة عبر المسار النسبي `../packages/platform_core`.

## موقع المشروع

المشروع مُثبَّت على مسار لاتيني دائم: **`C:\AluklaaApp`**
(أداة فلاتر لسطح المكتب لا تبني/تشغّل من مسار فيه حروف عربية، فنُبقيه لاتينياً لتجنّب أي مشاكل).

## التشغيل كتطبيق ويندوز (الأسهل)

نقرة واحدة على اختصار **«تطبيق الوكلاء»** على سطح المكتب، أو:
```bat
C:\AluklaaApp\run_windows_app.bat
```
يشغّل الخادم المستقل (`backend.exe`) تلقائياً ثم يفتح نافذة التطبيق.

بيانات الدخول التجريبية: **المستخدم `wakil` · كلمة المرور `wakil123`**
(لاحقاً تُصدر شركتك حساب الوكيل الحقيقي من تبويب «الوكلاء».)

### مكوّنان بلا اعتمادات خارجية
- **الخادم**: `backend/dist/backend/backend.exe` — ملف تشغيلي مستقل مبني بـ PyInstaller،
  **لا يحتاج تثبيت بايثون** على الجهاز. قاعدة البيانات محليّة: `backend/iraq_digital_platform.db`.
- **الواجهة**: `frontend/build/windows/x64/runner/Release/agents_app.exe` — تطبيق ويندوز أصلي.

### النشر على كلاود بدل المحلي (اختياري — هوستنكر/Postgres)
غيّر سطراً واحداً في `backend/.env`:
```
DATABASE_URL=postgresql+psycopg://USER:PASSWORD@srvNNNN.hstgr.io:5432/DBNAME
```
(المحرّك `psycopg` مثبَّت مسبقاً في `requirements.txt`.)

## إعادة البناء (بعد تعديل الكود)

الخادم (بعد تعديل بايثون):
```bat
cd C:\AluklaaApp\backend
.venv\Scripts\pyinstaller backend.spec --noconfirm
```
التطبيق (بعد تعديل Flutter):
```bat
cd C:\AluklaaApp\frontend
flutter build windows --release --dart-define=API_BASE=http://127.0.0.1:8000
```

## التشغيل يدوياً / الويب

### 1) الباكند (وضع التطوير عبر بايثون)
```bat
start_backend.bat
```
يُشغّل النسخة المستقلّة إن وُجدت، وإلا عبر بايثون/venv على `http://127.0.0.1:8000`.
يبدأ في **وضع المحاكاة** (`USE_MOCK_OLT=true`) ويبذر بيانات تجريبية (`SEED_DEMO_DATA=true`).

### 2) تطبيق الوكيل (ويب للتطوير)
```bat
run_agent_app.bat
```
موبايل:
```bat
flutter run --dart-define=API_BASE=http://<IP-حاسوب-الباكند>:8000
```

عنوان الباكند يُمرَّر دائماً عبر `--dart-define=API_BASE=…` (بلا عنوان مضمّن في الكود؛ الافتراضي `http://127.0.0.1:8000`).

## حساب الدخول

حساب الوكيل يُصدره **تطبيق الشركات** من تبويب «الوكلاء» → زر المفتاح (يستدعي `POST /api/companies/{cid}/agents/{aid}/account`)، فيدخل الوكيل باسم المستخدم وكلمة المرور المُصدَرَين.

## علاقته بالمشروع الأصلي

- نُسخ (لم يُنقل) — `olt-manager` لم يتغيّر ولا يزال يحوي التطبيقات الأربعة والباكند المشترك.
- **الباكند الآن متفرّع**: أي إصلاح مشترك (أمان/SAS/نماذج) يجب تطبيقه يدوياً هنا وفي `olt-manager`.
- `agents`/`agent` في الكود = **دور** وليس اسم المشروع — لا يُعاد تسميتها.

## التحقّق
```bat
cd packages\platform_core && flutter pub get && flutter analyze
cd frontend && flutter pub get && flutter analyze
cd backend && pytest -q
```
