# وحدة «وكيل SAS» (تطبيق الوكلاء معزولاً داخل منصة الصدارة)

> هذا المجلد يحتوي **تطبيق الوكلاء (Aluklaa)** كاملاً ومعزولاً داخل مستودع الصدارة، ليكون مصدر الحقيقة لوحدة **«صفحة وكيل SAS»** التي ستُدمج في تطبيق الصدارة الرئيسي.
>
> نُسخ من: `C:\Users\Msi-x88\Desktop\تطبيق الوكلاء` بتاريخ 2026-09-30.
> نقطة العودة للمصدر: وسم git `checkpoint/pre-sas-extract-20260930` في مستودع تطبيق الوكلاء.
> خطة الدمج الكاملة: [../../docs/SAS_AGENT_INTEGRATION_PLAN.md](../../docs/SAS_AGENT_INTEGRATION_PLAN.md).

## لماذا معزول؟

- **صيانة أسهل**: كل كود الساس/الوكيل في مكان واحد لا يختلط بكود الصدارة (.NET/Flutter).
- **حدود واضحة**: يُدمج مع الصدارة عبر واجهات محدّدة فقط (بوّابة .NET → خدمة الساس Python)، لا استدعاءات مباشرة متشابكة.
- **قابلية الاستبدال**: يمكن تطوير/اختبار الوحدة مستقلّةً، ثم ربطها دون لمس بقية المشروع.

## البنية

```
modules/sas-agent/
├── README.md                 هذا الملف
├── backend/                  خدمة الساس (Python / FastAPI) — مصدر الـ sidecar الداخلي
│   ├── app/
│   │   ├── integrations/     sas_client.py · sas_user_client.py  (عملاء SAS4 + تشفير AES)
│   │   ├── api/              sas_panel.py · portal_sas.py · companies.py · …
│   │   ├── services/         sas_sync.py · expiry.py · tickets.py · …
│   │   ├── core/             auth · security  (+ طبقة OLT محفوظة غير مُفعَّلة)
│   │   ├── models.py         الكيانات (SasAccount · Subscriber · Ticket · …)
│   │   └── main.py
│   ├── migrations/           هجرات Alembic
│   ├── tests/                اختبارات pytest
│   └── knowledge/sas4/       مرجع SAS4 API
├── flutter/
│   ├── frontend/             تطبيق الوكيل (شاشات lib/screens)
│   └── platform_core/        الحزمة المشتركة (شاشات SAS/التذاكر + نظام التصميم + API)
└── docs/                     وثائق تطبيق الوكلاء الأصلية (README · ARCHITECTURE · DEPLOY · CLAUDE)
```

## ما استُبعد من النسخ (مخرجات قابلة لإعادة التوليد)

`.git` · `.venv/venv` · `build` · `dist` · `.dart_tool` · `__pycache__` · `node_modules` · `.gradle` · `*.db` · `*.exe` · أرشيفات ونُسخ احتياطية.

## كيف يُدمج مع الصدارة (ملخص — التفصيل في خطة الدمج)

1. **الباكند (.NET)**: كيانات `SasAccount`/`CompanySasSettings` بوسم `ITenantScoped` + بوّابة `SasAgentController` على `/api/sas-agent/*` محميّة بصلاحية `sas_agent`.
2. **خدمة الساس (Python)**: تُشتقّ من `backend/` هنا كخدمة داخلية على `127.0.0.1` تناديها الصدارة فقط (غير مكشوفة للإنترنت).
3. **الواجهة (Flutter)**: تُبنى وحدة `lib/sas_agent/` في `alsadara-ftth` تنقل شاشات `flutter/` هنا وتُعاد لثيم الصدارة، وتنادي `/api/sas-agent/*`.

## قواعد الصيانة

- عدّل كود الساس/الوكيل **هنا فقط**؛ لا تبعثر منطق الساس داخل كود الصدارة.
- أي تغيير يمسّ العزل/المصادقة/الهجرات يتطلب موافقة صريحة (قواعد الصدارة الذهبية).
- حافظ على حدود الوحدة: التكامل عبر البوّابة فقط.
