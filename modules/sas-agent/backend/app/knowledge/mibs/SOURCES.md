# مصادر ملفات MIB لأجهزة Huawei OLT

## أين تُحصل على الملفات الرسمية

ملفات MIB من Huawei **ملكية خاصة** ولا تُوزَّع علناً. يوفّرها المشغّل من إحدى المصادر التالية:
1. **دعم Huawei المحلي** (TAC / Account Manager) — اطلب حزمة MIB للموديل والإصدار.
2. **بوابة Huawei Support** (support.huawei.com) عبر حساب موثّق — قسم Software Downloads.
3. **مباشرة من الجهاز** عبر FTP/SFTP: بعض إصدارات VRP تحوي ملفات `.mib` في `/flash/mib/`.

## الملفات المطلوبة لكل موديل

| الملف | الموديل | المحتوى |
|---|---|---|
| `HUAWEI-MIB.mib` | الكل | OIDs أساسية Huawei Enterprise |
| `HUAWEI-DEVICE-MIB.mib` | الكل | CPU / ذاكرة / كروت / مراوح / طاقة |
| `HUAWEI-XPON-MIB.mib` | MA5800 / MA5680T / EA5800 | ONT / PON / DDM / traps XPON |
| `HUAWEI-IPDSLAM-GPONONU-MIB.mib` | MA5680T (قديم) | ONT info للجيل الأقدم |
| `HUAWEI-TRAP.mib` | الكل | تعريفات SNMP traps |

## كيف يستخدمها `mib_registry.py`

1. ضع الملفات في هذا المجلد: `backend/app/knowledge/mibs/`
2. عند إقلاع التطبيق يُحوّل `mib_registry` الملفات عبر **pysmi** إلى Python modules في `_mib_cache/`.
3. دالة `resolve(symbol_name)` تُرجع OID رقمياً من اسم رمزي مثل `hwGponOntOpticalDdmRxPower`.
4. يستعمل `snmp_collector` نتيجة `resolve()` بدلاً من OID الرقمي الثابت في ملف Adapter.

## ملاحظات على قيَم OID في ملفات Adapter

قيَم OID في `knowledge/adapters/*.json` هي **قيَم احتياطية** مستقاة من وثائق Huawei العلنية ومن مستخدمي منتدى SNMP/NMS. هي **تقديرات موثّقة** تعمل مع معظم إصدارات VRP، لكن:

- قد تتغيّر بين الإصدارات الكبيرة (مثل V100R014 مقابل V100R019).
- **دوماً دقّقها** مقابل ملفات MIB الرسمية للجهاز الفعلي قبل الإنتاج.
- عند توفّر ملفات MIB، يُعطي `mib_registry` الأولوية للـ OID المحلول من `symbol`.

## هيكل الدليل المتوقَّع

```
backend/app/knowledge/mibs/
├── SOURCES.md              ← هذا الملف
├── HUAWEI-MIB.mib          ← ضعه هنا (من Huawei)
├── HUAWEI-DEVICE-MIB.mib   ← ضعه هنا
├── HUAWEI-XPON-MIB.mib     ← ضعه هنا
├── HUAWEI-TRAP.mib         ← ضعه هنا (اختياري)
└── _mib_cache/             ← تُولَّد تلقائياً (لا تعدّلها)
```

## اختبار التحليل

```python
from app.core.mib_registry import registry
oid = registry.resolve("hwGponOntOpticalDdmRxPower")
print(oid)   # يطبع OID رقمياً إن وُجد الملف، أو None إن لم يُوجد
```
