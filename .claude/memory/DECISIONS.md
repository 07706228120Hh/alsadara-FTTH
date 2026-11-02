# DECISIONS — سجل القرارات المعمارية والتشغيلية

سجل القرارات المهمة في منصة الصدارة. كل قرار يُضاف كصف جديد ولا يُحذف القديم (سجل تاريخي).

| Date | Decision | Reason | Status | Related Files |
|------|----------|--------|--------|---------------|
| 2026-06-25 | تأسيس نظام الوكلاء (19 وكيلاً) وذاكرة مشتركة تحت `.claude/memory/` | الحاجة إلى عمل منظّم متعدد التخصصات بحدود واضحة وموافقات صريحة على العمليات الحساسة | Active | كل ملفات `.claude/memory/*.md` |
| 2026-11-02 | وسم المهام بحساب مصدر ومنطقة يكون **يدوياً** (المدير/الليدر يختار) لا اشتقاقاً تلقائياً | تجنّب مطابقة هشّة/غموض في الربط التلقائي؛ ستّة قرارات للمالك موثّقة في `docs/design/TASKS_SOURCE_ACCOUNT_REGION.md` | Active | `docs/design/TASKS_SOURCE_ACCOUNT_REGION.md`, ServiceRequest, endpoint `/api/tasks/source-pool` |
| 2026-11-02 | اللقطات (snapshots) للحساب المصدر/الشريك/المنطقة تُختَم **خادمياً** مع تحقّق ملكية، والعزل من التوكن لا من العميل | منع تلاعب العميل وضمان عزل الشركة؛ متوافق مع قاعدة العزل الذهبية | Active | ServiceRequest، `TaskSourceAccountType`، `/api/tasks/source-pool` |
| 2026-11-02 | تنفيذ الميزة على **مرحلتين**: المرحلة 1 (أ) = مناطق الساس كاملة + FTTH حتى الشريك/منطقة نصّية؛ المرحلة 2 = زونات FTTH الحيّة | المرحلة 2 تعتمد على فرع `feature/ftth-credentials-unification` المحجوز لترخيص `linked_accounts` + موافقة | Phase 1 done (unshipped); Phase 2 deferred | `feature/tasks-source-account-region`, `feature/ftth-credentials-unification` |
