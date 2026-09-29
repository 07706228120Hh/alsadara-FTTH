# مصادر المعرفة — أدلة Huawei Access الرسمية

هذه الأدلة هي **المصدر الرسمي** الذي بُنيت عليه مكتبة الأوامر (`command_library.py`)،
محرك التزويد (`services/provisioning.py`)، قواعد التشخيص (`diagnosis_rules.json`)،
ومرجع الـ RAG (`commands_reference.md`). كل تسلسل أوامر في المشروع مُتحقَّق منه مقابل
«Configuration Reference» في هذه الأدلة.

## الملفات المُضافة للمشروع

| الملف | الصفحات | الحالة داخل المشروع |
|---|---|---|
| HCIA-Access V2.5 Lab Guide | 139 | ✅ PDF كامل + نص مُستخرَج (`text/`) |
| HCIP-Access V2.5 Lab Guide | 206 | ✅ PDF كامل + نص مُستخرَج (`text/`) |
| HCIA-Access V2.5 Training Material | 933 | ✅ نص كامل مُستخرَج (`text/`) — الـ PDF الأصلي 110MB مُرجَع، لا يُنسخ |
| HCIP-Access V2.5 Training Material | 1170 | ✅ نص كامل مُستخرَج (`text/`) — الـ PDF الأصلي 156MB مُرجَع، لا يُنسخ |

**لماذا لا تُنسخ الـ Training Material كـ PDF؟** حجمها (110MB + 156MB) يُثقل المستودع بلا
فائدة تقنية؛ **محتواها الكامل مُستخرَج نصياً** في `text/` وهو ما يُستعمل فعلياً كمعرفة قابلة
للبحث والاقتباس في الـ RAG. أما دليلا المختبر (Lab Guides) — وهما مصدر أوامر التهيئة الأهم —
فمحفوظان كـ PDF كامل + نص. لنسخ ملفات الـ Training الأصلية كـ PDF، فهي في:
`C:\Users\Msi-x88\Downloads\olt\`.

## الخرائط: أين طُبّق كل دليل

- **HCIA Lab Guide §3 (FTTH HSI)** → `provisioning.build_ftth_plan(service_type="hsi")`
  + `command_library` (dba/lineprofile/srvprofile/service-port). المرجع القياسي §3.4.1.
- **HCIP Lab Guide — SIP/H.248 VoIP** → `provisioning` (service_type="voip"/"triple")
  + `command_library.voip_*`.
- **HCIP Lab Guide — IPTV Multicast (BTV/IGMP)** → `provisioning` (service_type="iptv"/"triple")
  + `command_library.iptv_*`.
- **HCIA/HCIP — ONT states / optical / MOS** → `knowledge/diagnosis_rules.json`
  + `services/troubleshooting.py`.

## إعادة توليد النص المُستخرَج

```bash
# يتطلب PyMuPDF (أداة استخراج فقط، ليست من اعتمادات التشغيل)
pip install pymupdf
python tools/extract_guides.py   # إن أردت أتمتة الاستخراج مستقبلاً
```
