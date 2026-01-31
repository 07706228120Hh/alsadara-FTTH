# 📚 الدرس #0: هيكل المشروع الكامل

## 🗂️ نظرة عامة على الجذر

```
C:\SadaraPlatform\
│
├── 📄 .env                  ← متغيرات البيئة (سري)
├── 📄 .env.example          ← قالب المتغيرات
├── 📄 .gitignore            ← ملفات يتجاهلها Git
├── 📄 README.md             ← وصف المشروع
├── 📄 SadaraPlatform.sln    ← ملف Solution
│
├── 📁 .github/              ← إعدادات GitHub
├── 📁 .vscode/              ← إعدادات VS Code
├── 📁 deployment/           ← ملفات النشر
├── 📁 docker/               ← Docker
├── 📁 docs/                 ← التوثيق
├── 📁 scripts/              ← السكربتات
├── 📁 secrets/              ← الملفات السرية
├── 📁 src/                  ← الكود المصدري ⭐
└── 📁 tests/                ← الاختبارات
```

---

## 📄 الملفات في الجذر

### 1️⃣ `.env` - متغيرات البيئة

**ما هو؟** ملف يحتوي على الإعدادات السرية (كلمات المرور، مفاتيح API).

**لماذا مهم؟** يفصل الإعدادات عن الكود، فيمكنك تغيير كلمة مرور بدون تعديل الكود.

**⚠️ تحذير:** هذا الملف **لا يُرفع على Git** لأنه يحتوي أسرار!

**المحتوى النموذجي:**
```env
# قاعدة البيانات
POSTGRES_PASSWORD=كلمة_مرور_سرية

# JWT للمصادقة
JWT_SECRET_KEY=مفتاح_سري_32_حرف_على_الأقل

# Firebase
FIREBASE_API_KEY=مفتاح_firebase

# الخادم
VPS_HOST=72.61.183.61
VPS_PASSWORD=كلمة_مرور_الخادم
```

**💡 نصيحة:** انسخ `.env.example` إلى `.env` واملأ القيم.

---

### 2️⃣ `.env.example` - قالب المتغيرات

**ما هو؟** نسخة من `.env` لكن **بدون القيم الحقيقية**.

**لماذا موجود؟** ليعرف المطور الجديد ما هي المتغيرات المطلوبة.

**هل يُرفع على Git؟** ✅ نعم، لأنه لا يحتوي أسرار.

---

### 3️⃣ `.gitignore` - ملفات يتجاهلها Git

**ما هو؟** قائمة بالملفات التي لا يجب رفعها على Git.

**محتوياته الرئيسية:**
```gitignore
# ملفات سرية
.env
secrets/
*.pem
*.key

# ملفات بناء (تُولّد تلقائياً)
bin/
obj/
publish/

# سجلات
logs/
*.log

# قواعد بيانات محلية
*.db
*.sqlite
```

**💡 تشبيه:** مثل قائمة "لا تحزم هذه الأشياء" عند السفر.

---

### 4️⃣ `README.md` - الملف التعريفي

**ما هو؟** أول ملف يراه أي شخص عند فتح المشروع.

**ماذا يحتوي؟**
- وصف المشروع
- كيفية التثبيت
- كيفية التشغيل
- المتطلبات

**💡 نصيحة:** اجعله واضحاً ومختصراً.

---

### 5️⃣ `SadaraPlatform.sln` - ملف Solution

**ما هو؟** ملف يجمع كل مشاريع .NET معاً.

**ماذا يفعل؟** يُخبر Visual Studio بالمشاريع الموجودة وكيفية بنائها.

**المشاريع المسجلة:**
```
SadaraPlatform.sln
├── Sadara.Domain        ← الكيانات (Entities)
├── Sadara.Application   ← منطق العمل (Services)
├── Sadara.Infrastructure← قاعدة البيانات
└── Sadara.API           ← نقطة الدخول (Controllers)
```

**💡 تشبيه:** مثل "جدول المحتويات" لكتاب - يُخبرك بالفصول الموجودة.

**كيف تفتحه؟**
```powershell
# من VS Code
code SadaraPlatform.sln

# من Visual Studio
start SadaraPlatform.sln
```

---

## 📁 المجلدات الرئيسية

### 📁 `src/` - الكود المصدري ⭐

**أهم مجلد!** يحتوي كل الكود الفعلي.

```
src/
├── Backend/           ← خادم .NET API
│   ├── API/          ← Controllers (نقطة الدخول)
│   └── Core/         ← Domain, Application, Infrastructure
└── Apps/             ← التطبيقات
    ├── CitizenWeb/   ← تطبيق المواطن (Blazor)
    └── CompanyDesktop/← تطبيق الشركة (Flutter)
```

---

### 📁 `docs/` - التوثيق

```
docs/
├── learning/         ← 📚 دروس التعلم (أنت هنا!)
├── guides/           ← أدلة الإعداد
├── archive/          ← توثيق قديم
├── ARCHITECTURE.md   ← شرح البنية
└── DATABASE.md       ← شرح قاعدة البيانات
```

---

### 📁 `scripts/` - السكربتات

```
scripts/
├── database/         ← ملفات SQL
├── deployment/       ← سكربتات النشر
├── testing/          ← سكربتات الاختبار
├── setup-dev.ps1     ← إعداد بيئة التطوير
└── backup.ps1        ← نسخ احتياطي
```

---

### 📁 `docker/` - Docker

```
docker/
├── docker-compose.yaml  ← تشغيل PostgreSQL + pgAdmin
└── Dockerfile           ← بناء صورة API
```

**للتشغيل:**
```powershell
cd docker
docker-compose up -d
```

---

### 📁 `secrets/` - الملفات السرية

```
secrets/
├── firebase-service-account.json  ← مفتاح Firebase
└── README.md                      ← تعليمات
```

**⚠️ هذا المجلد لا يُرفع على Git!**

---

### 📁 `tests/` - الاختبارات

```
tests/
├── Sadara.API.Tests/         ← اختبارات API
├── Sadara.Domain.Tests/      ← اختبارات الكيانات
└── Sadara.Integration.Tests/ ← اختبارات التكامل
```

---

## 🎯 ملخص

| الملف/المجلد | الوظيفة | مهم للتعلم؟ |
|--------------|---------|-------------|
| `.env` | إعدادات سرية | ⚠️ للإعداد فقط |
| `.gitignore` | تجاهل ملفات | ❌ لا |
| `README.md` | وصف المشروع | ✅ اقرأه |
| `SadaraPlatform.sln` | ربط المشاريع | ⚠️ للفتح فقط |
| `src/` | **الكود** | ⭐ **الأهم!** |
| `docs/` | التوثيق | ✅ للقراءة |
| `scripts/` | سكربتات | ⚠️ عند الحاجة |

---

## 🔗 الدرس التالي

[01_Program.cs.md](./01_Program.cs.md) - نقطة بداية التطبيق
