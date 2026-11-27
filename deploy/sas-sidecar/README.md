# حزمة معالجة خدمة الساز (SAS sidecar) — P0-1 + خطة P0-2

نتجت عن فحص وحدة «وكيل SAS» (فرع `fix/sas-agent-safe-hardening`). كل ما هنا **جاهز للتطبيق بموافقتك** — لم يُطبَّق على الإنتاج.

---

## 1) التحقّق التشغيلي (للقراءة فقط — ابدأ بهذا)

```bash
ssh root@72.61.183.61 'bash -s' < deploy/sas-sidecar/verify-sidecar.sh
```

يخبرك: هل الخدمة مُشغَّلة/مُفعَّلة؟ هل 8100 يستمع؟ صحّتها؟ السرّ مضبوط؟ النسخ الاحتياطي يغطّي `sas.db`؟
لا يغيّر شيئاً ولا يطبع أي سرّ.

---

## 2) P0-1 — تثبيت الخدمة كـsystemd (يحتاج موافقة: تغيير بنية تحتية)

> **الخطر الأصلي:** الخدمة كانت تُشغَّل يدوياً وليست ضمن `deploy-backend.sh` ⇒ بعد أي reboot تتعطّل الوحدة صامتةً (كل `/api/sas-agent/*` تُرجع 503).

**قبل التطبيق:** تأكّد من المسارات الفعلية (`WorkingDirectory`, `ExecStart`, `EnvironmentFile`) في [sadara-sas-sidecar.service](sadara-sas-sidecar.service) — المثال يفترض `/srv/sas-service`.

```bash
# 1) تأكّد أن السرّ الداخلي مضبوط (نفس قيمة الباكند SADARA_SAS_INTERNAL_SECRET):
sudo install -d -m 750 /etc/sadara
sudo test -f /etc/sadara/sas-sidecar.env || echo "SADARA_SAS_INTERNAL_SECRET=<نفس سرّ الباكند>" | sudo tee /etc/sadara/sas-sidecar.env >/dev/null
sudo chmod 640 /etc/sadara/sas-sidecar.env

# 2) ثبّت الوحدة وفعّلها:
sudo cp deploy/sas-sidecar/sadara-sas-sidecar.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now sadara-sas-sidecar

# 3) تحقّق:
bash deploy/sas-sidecar/verify-sidecar.sh
```

**تراجع:** `sudo systemctl disable --now sadara-sas-sidecar` (الزر يُخفى بالصلاحية في الواجهة، فلا أثر للمستخدم).

**بعد التثبيت:** أضِف فحص صحّة الـsidecar إلى runbook النشر، وتنبيهاً عند 503 المتكرّر على `/api/sas-agent/*`.

---

## 3) P0-2 — تسريب `sas.db` (PII) في Git (يحتاج موافقة صريحة: يمسّ تاريخ main المدفوع)

> **الخطر:** `modules/sas-agent/service/data/sas.db` (619 صفّ مشترك حقيقي) و`data/media/premises/1/house.jpg` مُتعقَّبان في git رغم أن `.gitignore` يتجاهل `*.db` (أُضيفا قبل القاعدة).

### الخطوة الآمنة (بلا إعادة كتابة تاريخ) — إيقاف التتبّع من الآن:
```bash
git rm --cached modules/sas-agent/service/data/sas.db
git rm --cached modules/sas-agent/service/data/media/premises/1/house.jpg
git commit -m "chore(sas): إيقاف تتبّع قاعدة الساز المحلية ووسائطها (PII)"
```
هذا يمنع التسريب المستقبلي لكنه **لا يحذف الملفين من التاريخ** (يبقيان في اللقطات القديمة).

### التطهير الكامل من التاريخ (مدمّر — يحتاج force-push + تنسيق الفريق):
```bash
# نسخة احتياطية أولاً، ثم:
git filter-repo --path modules/sas-agent/service/data/sas.db \
                --path modules/sas-agent/service/data/media/premises/1/house.jpg --invert-paths
git push --force-with-lease origin main        # ← يحتاج موافقتك الصريحة
```
> ⚠️ **لا تُنفَّذ الخطوة المدمّرة إلا بموافقة صريحة منك.** `force push` على `main` عملية خطرة (قاعدة ذهبية #9) وتتطلّب تنسيق كل من يعمل على المستودع.
> واعتبر بيانات الـ619 مشتركاً مكشوفةً تاريخياً ⇒ قيّم الحاجة لإشعار/تدوير أي اعتماد مرتبط.

---

## ملخّص الحالة

| البند | الحالة |
|------|--------|
| P0-1 تثبيت systemd | ✅ جاهز للتطبيق (قسم 2) — يحتاج موافقة |
| P0-2 إيقاف التتبّع | ✅ أوامر جاهزة (قسم 3) — يحتاج موافقة |
| P0-2 تطهير التاريخ | ⛔ موثّق فقط — لا يُنفَّذ بلا موافقة صريحة (force push) |
| فحص تشغيلي | ✅ سكربت جاهز (قسم 1) |
