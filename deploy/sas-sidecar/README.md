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

**المسارات الفعلية على الإنتاج (مُتحقَّقة 2026-11-27):** الخدمة في `/opt/sadara/sas/service`، الـvenv في `/opt/sadara/sas/venv`، قاعدة `sas.db` في `/opt/sadara/sas/service/data/`، EnvFile `/etc/sadara/sas-sidecar.env` (السرّ مضبوط)، المستخدم `www-data`. الوحدة الحيّة محفوظة في [sadara-sas-sidecar.service](sadara-sas-sidecar.service) — **الخدمة مُثبَّتة ومُفعَّلة أصلاً (active + enabled)**، فهذا القسم مرجعي/للتعافي لا للتثبيت الأولي.

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

## 3) P0-2 — وسائط عقار متعقَّبة في Git (خطورة منخفضة بعد التصحيح)

> **تصحيح مهم:** `sas.db` (قاعدة الـ619 مشتركاً) **غير متعقَّب في git إطلاقاً** — تجاهُل `*.db` يعمل، والقاعدة على القرص فقط. المتعقَّب الوحيد هو صورة عقار واحدة: `modules/sas-agent/service/data/media/premises/1/house.jpg`.

### الإصلاح المطبَّق على هذا الفرع (آمن، بلا إعادة كتابة تاريخ):
- إيقاف تتبّع `house.jpg` (يبقى على القرص).
- توسيع `data/.gitignore` ليشمل `media/` فمستقبلاً لا تُتعقَّب أي وسائط مرفوعة.

### (اختياري) تطهير الصورة من التاريخ — فقط إن اعتبرتها حسّاسة:
```bash
# نسخة احتياطية أولاً، ثم:
git filter-repo --path modules/sas-agent/service/data/media/premises/1/house.jpg --invert-paths
git push --force-with-lease origin main        # ← يحتاج موافقتك الصريحة (force push = قاعدة ذهبية)
```
> ⚠️ صورة واحدة فقط ⇒ الخطورة منخفضة؛ `force push` على `main` قد لا يستحقّ العناء — قرارك.

---

## ملخّص الحالة

| البند | الحالة |
|------|--------|
| P0-1 تثبيت systemd | ✅ جاهز للتطبيق (قسم 2) — يحتاج موافقة |
| P0-2 إيقاف التتبّع | ✅ أوامر جاهزة (قسم 3) — يحتاج موافقة |
| P0-2 تطهير التاريخ | ⛔ موثّق فقط — لا يُنفَّذ بلا موافقة صريحة (force push) |
| فحص تشغيلي | ✅ سكربت جاهز (قسم 1) |
