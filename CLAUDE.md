# CLAUDE.md

هذا المشروع يعمل بنظام وكلاء ذكاء اصطناعي متخصصين موجودين في `.claude/agents`.

هذا الملف هو المرجع الأعلى (Top-level guide) لأي وكيل أو مساعد ذكاء اصطناعي يعمل على منصة الصدارة (Sadara Platform). يجب قراءته أولاً قبل تنفيذ أي مهمة.

---

## Golden Rules

القواعد الذهبية العشرون — إلزامية ولا يجوز تجاوزها:

1. افهم قبل أن تعدّل.
2. اقرأ PROJECT_CONTEXT.md قبل أي مهمة.
3. اقرأ .claude/memory/PROJECT_STATE.md قبل أي تغيير مهم.
4. اقرأ .claude/memory/PROJECT_STRUCTURE_FOR_AGENTS.md قبل أي تعديل.
5. لا تحذف أي ملف بدون سبب واضح وتقرير.
6. لا تغيّر secrets أو tokens أو passwords.
7. لا تطبع secrets في التقارير.
8. لا تعمل deploy بدون موافقة صريحة من المستخدم.
9. لا تعمل push إلى remote بدون موافقة صريحة.
10. لا تشغل migration خطرة بدون خطة rollback وموافقة.
11. لا تعدّل قاعدة بيانات production.
12. لا تعدّل أكثر من نطاق كبير في نفس المهمة.
13. لا تتجاوز الصلاحيات الخاصة بكل وكيل.
14. أي تغيير أمني يجب أن يمر على security-auditor-agent.
15. أي تغيير في قاعدة البيانات يجب أن يمر على database-postgres-agent.
16. أي تغيير معماري يجب أن يمر على architecture-evolution-agent.
17. أي تغيير كبير يجب أن يمر على testing-qa-agent.
18. أي تعديل على الوكلاء يجب أن يمر على agent-trainer-development-manager.
19. أي مهمة كبيرة يجب أن تبدأ من project-manager.
20. عند الشك، اكتب تقريرًا ولا تنفذ تعديلًا خطرًا.

---

## Operating Model

النموذج التشغيلي لتدفق أي طلب عبر فريق الوكلاء:

```
User Request
  → project-manager
  → task breakdown
  → agent assignment
  → specialized agent execution
  → code-reviewer-agent
  → testing-qa-agent
  → security-auditor-agent (if needed)
  → documentation-agent
  → knowledge-manager-agent
  → final report
```

أي مهمة كبيرة تبدأ من `project-manager` الذي يقسّمها ويسندها للوكيل المختص، ثم تمر بمراجعة الكود والاختبار والأمن (عند الحاجة)، ثم التوثيق وتحديث الذاكرة، وأخيرًا التقرير النهائي.

---

## Human Approval Required

العمليات التالية تتطلب موافقة بشرية صريحة قبل التنفيذ — لا استثناءات:

- production deploy
- database migration
- deleting files
- changing secrets
- changing authentication system
- changing authorization model
- changing tenant isolation
- changing payment logic
- changing infrastructure
- force push
- destructive git operations
- disabling tests
- disabling security checks

---

## Agent Roster

فريق الوكلاء التسعة عشر ومسؤولية كل منهم (ملفات التعريف في `.claude/agents/...`):

| Agent | المسؤولية | الملف |
|-------|-----------|-------|
| project-manager | تقسيم المهام وإسنادها وتنسيق الفريق وبدء أي مهمة كبيرة | `.claude/agents/project-manager.md` |
| backend-agent | تطوير وصيانة Backend .NET 9 (Controllers / Application / Domain) | `.claude/agents/backend-agent.md` |
| frontend-agent | تطبيق المواطنين CitizenWeb (Flutter Web / PWA) | `.claude/agents/frontend-agent.md` |
| mobile-agent | تطبيق alsadara-ftth (Windows + Android + iOS) | `.claude/agents/mobile-agent.md` |
| database-postgres-agent | قاعدة PostgreSQL، الـ Migrations، EF Core، أي تغيير في البيانات | `.claude/agents/database-postgres-agent.md` |
| devops-agent | Docker، GitHub Actions، النشر SCP/systemd، البنية التحتية | `.claude/agents/devops-agent.md` |
| security-auditor-agent | مراجعة أي تغيير أمني (Auth، Secrets، الصلاحيات) | `.claude/agents/security-auditor-agent.md` |
| architecture-evolution-agent | القرارات والتغييرات المعمارية (طبقات Clean Architecture) | `.claude/agents/architecture-evolution-agent.md` |
| testing-qa-agent | الاختبارات وضمان الجودة لأي تغيير كبير | `.claude/agents/testing-qa-agent.md` |
| code-reviewer-agent | مراجعة الكود قبل الدمج | `.claude/agents/code-reviewer-agent.md` |
| documentation-agent | توثيق المشروع وتحديث ملفات docs/ | `.claude/agents/documentation-agent.md` |
| knowledge-manager-agent | إدارة الذاكرة المؤسسية وتحديث ملفات .claude/memory | `.claude/agents/knowledge-manager-agent.md` |
| integration-agent | التكاملات الخارجية (api.ftth.iq، Cloudflare، Firebase FCM) | `.claude/agents/integration-agent.md` |
| agent-trainer-development-manager | تدريب وتطوير الوكلاء وأي تعديل على تعريفاتهم | `.claude/agents/agent-trainer-development-manager.md` |
| accounting-agent | منطق المحاسبة والقيود المالية FTTH | `.claude/agents/accounting-agent.md` |
| performance-agent | تحسين الأداء (Frontend/Backend/Flutter) | `.claude/agents/performance-agent.md` |
| api-integration-tester-agent | اختبار واجهات API الداخلية والخارجية | `.claude/agents/api-integration-tester-agent.md` |
| ui-ux-agent | تجربة المستخدم والواجهات العربية RTL | `.claude/agents/ui-ux-agent.md` |
| release-manager-agent | إدارة الإصدارات (Inno Setup، GitHub Releases، auto-update) | `.claude/agents/release-manager-agent.md` |

> ملاحظة: المسارات أعلاه قياسية ضمن `.claude/agents/`؛ تحقق من الأسماء الفعلية للملفات قبل الإسناد إن لم تكن موجودة بالضبط.

---

## Project Snapshot

ملخص الحقائق الأساسية للمشروع:

- **الهوية**: منصة الصدارة (Sadara Platform) — منصة FTTH/ISP + تجارة إلكترونية، multi-tenant بـ Company. الإصدار `v2.2.25+304`، الفرع `master`.
- **Backend**: .NET 9 Clean Architecture بأربع طبقات:
  - `src/Backend/API/Sadara.API` — 57 controller، SignalR Hubs، JWT، RequirePermissionAttribute
  - `Sadara.Application` — منطق التطبيق
  - `Sadara.Domain` — 37+ entity
  - `Sadara.Infrastructure` — Data/Migrations (84)، Identity، Repositories
  - EF Core 9 + Npgsql على PostgreSQL (`sadara_db` على VPS `72.61.183.61`)
- **التطبيقات (Flutter)**:
  - `src/Apps/CompanyDesktop/alsadara-ftth` — التطبيق الرئيسي (Windows + Android + iOS)
  - `src/Apps/CitizenWeb` — PWA (README يقول Blazor لكن الكود Flutter — Unknown)
  - `src/Apps/screen_test_app`
  - Flutter: `D:\flutter\flutter\bin\flutter.bat`
- **المصادقة والصلاحيات**: JWT Bearer + نظام صلاحيات مخصص (ServiceAndPermission) + RequirePermissionAttribute. Firebase FCM.
- **اعتماد خارجي**: `api.ftth.iq` (`185.239.19.3`، قراءة فقط، خلف Cloudflare).
- **النشر**: SCP يدوي إلى VPS `72.61.183.61` + `systemctl restart sadara-api`؛ التطبيق عبر Inno Setup → GitHub Releases (`07706228120Hh/alsadara-FTTH`) → auto-update.
- **CI/DevOps**: `.github/workflows/build-windows.yml`، Docker (`docker/Dockerfile` + `docker/docker-compose.yaml`).
- **الأسرار**: `.env` (قيم حقيقية)، `secrets/`، `.secrets/`.

---

## Required Reading For Every Agent

قبل أي مهمة، يجب على كل وكيل قراءة:

1. `CLAUDE.md` (هذا الملف)
2. `PROJECT_CONTEXT.md`
3. `.claude/memory/PROJECT_STATE.md`
4. `.claude/memory/PROJECT_STRUCTURE_FOR_AGENTS.md`
5. `.claude/memory/AGENT_COLLABORATION_RULES.md`
6. ملف الذاكرة المتخصص الخاص بمجال الوكيل (ضمن `.claude/memory/`).

---

## Safety Notes

- ضمن مهام البناء التنظيمي (التوثيق، الذاكرة، تعريف الوكلاء) **لا تعدّل كود التطبيق** — اكتفِ بالملفات التنظيمية.
- احترم الأسرار: لا تقرأها بصوت عالٍ، لا تطبعها، ولا تنسخها إلى ملفات غير مؤمّنة.
- خادم النشر الوحيد هو `72.61.183.61` — لا تنشر على أي خادم آخر. الخادم الخارجي `185.239.19.3` (api.ftth.iq) للقراءة فقط وليس ملكنا.
- عند الشك في خطورة عملية، اكتب تقريرًا واطلب موافقة بشرية بدل التنفيذ.
