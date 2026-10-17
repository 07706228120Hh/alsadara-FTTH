# خطة ترحيل الواجهات إلى الثيم الموحّد (lib/frontend)

حدّث المربعات `[x]` بعد إنهاء كل شاشة واجتياز `flutter analyze` واختبار العروض الأربعة (390/820/1180/1440). الترتيب داخل كل موجة: الأولوية العالية أولاً. سجّل كل شاشة منتهية في `PROGRESS_LOG.md`.

## الموجة 1 — التحضير

- [x] إنشاء `lib/frontend/` (رموز، ثيم، مكوّنات، تجاوب، معرض، README)
- [x] `flutter analyze lib/frontend` بلا أخطاء (وإصلاح ما يظهر داخل lib/frontend فقط) — 2026-10-16: No issues found، بلا تعديلات
- [ ] تشغيل المعرض: `flutter run -d windows -t lib/frontend/preview/gallery_main.dart` ومراجعة الأشكال على العروض الأربعة

## الموجة 2 — الانطباع الأول

- [x] `widgets/permissions_gate.dart` — السماح للتطبيق بالوصول للموقع (عالية) — 2026-10-16، analyze: No issues
- [x] `pages/login/premium_login_page.dart` — تسجيل الدخول (عالية) — 2026-10-16، analyze: No issues
- [x] `pages/home_page.dart` — رمز الصدارة (عالية) — 2026-10-16، analyze: No issues (ترحيل مرئي؛ دوال قديمة خاملة باقية)

## الموجة 3 — العمل الميداني اليومي

- [x] `ftth/core/home_page.dart` — لوحة التحكم (عالية) — 2026-10-16، قشرة (SdAppBar+خلفية سادة)؛ الجسم legacy (دَين)؛ analyze نظيف؛ تحسينات الأداء محفوظة
- [x] `ftth/reports/agents_details_page.dart` — تفاصيل الوكلاء (عالية) — 2026-10-16، قشرة (SdTheme.scope+SdAppBar)؛ الجسم legacy (دَين)؛ analyze: No issues
- [x] `ftth/requests/customer_onboarding_page.dart` — تسجيل مشترك جديد (عالية) — 2026-10-16، ترحيل أعمق (SdTheme.scope+ألوان sd)؛ analyze: No issues
- [x] `ftth/subscriptions/expiring_soon_page.dart` — الاشتراكات المنتهية قريباً / الاشتراكات التجريبية (عالية) — 2026-10-16، مُرحَّل بالكامل؛ analyze: No issues
- [x] `ftth/subscriptions/subscription_details_page.dart` — شراء اشتراك جديد / تجديد او تغيير الاشتراك (عالية) — 2026-10-16، قشرة+حالات (13k سطر؛ منطق التجديد/الباقات بلا مساس)؛ الجسم العميق legacy (دَين)؛ analyze: No issues
- [x] `ftth/subscriptions/subscriptions_page.dart` — المناطق / الاشتراكات (عالية) — 2026-10-16، قشرة+بطاقات+حالات؛ أبقى AppBar قديم لوجود bottom (شريط فلاتر) — SdAppBar يحتاج دعم bottom؛ analyze: No issues
- [x] `ftth/tickets/create_ticket_page.dart` — التبليغ عن مشكلة (عالية) — 2026-10-16، مُرحَّل (SdPage+SdAppBar+SdFilterChips+SdButton، نبرة comms)؛ analyze: No issues
- [x] `ftth/tickets/tktat_details_page.dart` — تفاصيل TKTAT (عالية) — 2026-10-16، مُرحَّل (SdPage+SdAppBar+SdCard+SLA SdStatusChip)؛ SLA الحيّ/التعليقات بلا مساس؛ analyze: No issues
- [x] `ftth/tickets/tktats_page.dart` — تطبيق FTTH (قائمة المهام/التذاكر) (عالية) — 2026-10-16، مُرحَّل (SdPage+SdAppBar+SdFilterChips+SdRaised+SdEmptyState)؛ 3 حوارات ثانوية legacy (دَين)؛ analyze: No issues
- [x] `ftth/transactions/transactions_page.dart` — التحويلات (عالية) — 2026-10-16، قشرة (SdAppBar+خلفية سادة)؛ الجسم legacy (دَين)؛ analyze: No issues
- [x] `ftth/users/quick_search_users_page.dart` — البحث السريع - المستخدمين (عالية) — 2026-10-16، مُرحَّل (SdPage+SdAppBar+SdRaised+SdEmptyState)؛ analyze: No issues
- [x] `ftth/users/user_details_page.dart` — تفاصيل المستخدم (عالية) — 2026-10-16، قشرة (SdAppBar) + EditDevicePage كامل (5855 سطر)؛ منطق items[]/pill محفوظ؛ جسم البطاقات legacy (دَين)؛ analyze: No issues
- [x] `ftth/users/users_page.dart` — المشتركين (عالية) — 2026-10-16، مُرحَّل؛ نُقل شريط كلمة مرور التصدير من AppBar.bottom إلى المحتوى؛ analyze: No issues
- [x] `pages/search_users_page.dart` — البحث عن المستخدمين (عالية) — 2026-10-16، مُرحَّل (SdPage+SdAppBar+SdButton)؛ analyze: No issues
- [x] `task/add_task_api_dialog.dart` — إضافة مهمة جديدة (عالية) — 2026-10-16، مُرحَّل (بقي Dialog؛ SdCard/SdButton/SdStatusChip)؛ التحقّق/الصرف/واتساب بلا مساس؛ analyze: No issues
- [x] `task/follow_up_page.dart` — المتابعة والتقييم (عالية) — 2026-10-16، مُرحَّل (SdPage+SdAppBar+SdCard+SdEmptyState)؛ التدقيق/النجوم/واتساب بلا مساس؛ analyze: No issues
- [x] `task/home_page_tasks.dart` — المهام (عالية) — 2026-10-16، شلّ موحّد + كنس ألوان شامل (3573 سطر)؛ بطاقات/أزرار اللوحة الداخلية بقيت موحّدة-الرموز لا SdCard/SdButton (دَين)؛ analyze: No issues
- [x] `task/task_list_screen.dart` — المهام (عالية) — 2026-10-16، منطقي أساساً (يغلّف HomePageTasks)؛ ألوان مؤشّر/SnackBar → SdColors؛ analyze: No issues

## الموجة 4 — الموظف والتواصل

- [x] `pages/attendance_page.dart` — نظام البصمة (عالية) — 2026-10-16، مُرحَّل (SdPage+SdAppBar+SdStatPedestal)؛ منطق البصمة/الموقع/السيلفي بلا مساس؛ أُزيلت AnimationControllers ميتة؛ analyze: No issues
- [x] `pages/chat/chat_conversation_page.dart` — المحادثة (اسم الغرفة) (عالية) — 2026-10-16، قشرة (2985 سطر؛ شريط مخصّص مُبقى للتفاعلات)؛ الفقاعات/stream/الإرسال بلا مساس؛ analyze: No issues
- [x] `pages/chat/chat_rooms_page.dart` — المحادثات (عالية) — 2026-10-16، مُرحَّل (SdPage+SdAppBar)؛ embeddedMode محفوظ؛ analyze: No issues
- [x] `pages/hr_hub_page.dart` — الموارد البشرية (عالية) — 2026-10-16، مُرحَّل (SdPage+SdAppBar+SdTileGrid/SdMenuTile admin)؛ التنقّل/العدّادات بلا مساس؛ analyze: No issues
- [~] `pages/kml_zones_map_page.dart` — خريطة الزونات (عالية) — ⛔ استثناء معتمد من صاحب المشروع (2026-10-16): شاشة خريطة غامرة داكنة ملء الشاشة × نظام sd فاتح؛ **تُترك كما هي** خارج نطاق التوحيد. (خيار إضافة لوحة داكنة لـ sd مسجَّل للمستقبل لو ظهرت شاشات غامرة أخرى.)
- [x] `pages/my_dashboard_page.dart` — شاشتي (عالية) — 2026-10-16، شلّ+توجيه ثوابت الألوان لـ SdColors (3428 سطر)؛ بنى داخلية عميقة GoogleFonts/hex (دَين)؛ الاستدعاءات بلا مساس؛ analyze: No issues
- [x] `pages/users_page_vps.dart` — إدارة الموظفين (عالية) — 2026-10-16، شلّ+توجيه ثوابت لـ SdColors (2203 سطر)؛ canAdd/الصلاحيات/useInternalKey بلا مساس؛ بطاقات/حوارات داخلية دَين؛ analyze: No issues
- [x] `pages/whatsapp_chat_page.dart` — محادثة واتساب (عالية) — 2026-10-16، قشرة؛ شريط نيلي + هوية واتساب للأفاتار فقط؛ الفقاعات/الإرسال بلا مساس؛ analyze: No issues
- [x] `pages/whatsapp_conversations_page.dart` — محادثات WhatsApp (عالية) — 2026-10-16، مُرحَّل (SdPage+SdAppBar)؛ الفلترة/التنظيف بلا مساس؛ analyze: No issues
- [x] `pages/announcements/announcements_page.dart` — الإعلانات والتبليغات (متوسطة) — 2026-10-16، مُرحَّل (comms؛ SdPage+SdAppBar+SdRaised+SdStatusChip+SdEmptyState)؛ الخدمات/الصلاحيات بلا مساس؛ analyze: No issues

## الموجة 5 — المحاسبة

- [x] `pages/accounting/accounting_dashboard_page.dart` — الحسابات (عالية) — 2026-10-16، قشرة (SdPage+SdAppBar)؛ _formatCurrency/البطاقات/الدرج بلا مساس؛ analyze: No issues
- [x] `pages/accounting/chart_of_accounts_page.dart` — شجرة الحسابات (عالية) — 2026-10-16، قشرة؛ AccountingTheme لم يُلمَس؛ analyze: No issues
- [x] `pages/accounting/client_accounts_page.dart` — كشف الحسابات (عالية) — 2026-10-16، قشرة (Scaffold+SdAppBar)؛ الجداول/الأرصدة بلا مساس؛ AccountingTheme سليم؛ analyze: No issues
- [x] `pages/accounting/collections_page.dart` — تحصيلات الفنيين (عالية) — 2026-10-16، قشرة؛ SdEmptyState؛ الجداول/الملخّصات بلا مساس؛ analyze: No issues
- [x] `pages/accounting/compound_journal_entry_page.dart` — قيد مركب (عالية) — 2026-10-16، قشرة؛ منطق التوازن/الحفظ/الترحيل بلا مساس؛ ملاحظة ui-ux: أزرار الحفظ صارت SdAppBarAction أقل بروزاً؛ analyze: No issues
- [x] `pages/accounting/expenses_page.dart` — المصروفات (عالية) — 2026-10-16، قشرة (SdAppBar+SdEmptyState)؛ الإجماليات/الصيغ بلا مساس؛ analyze: No issues
- [~] `pages/accounting/ftth_operators_dashboard_page.dart` — لوحة المشغلين (عالية) — ⏸️ مؤجّلة: 14k سطر، شريطها يحتضن تبويبات+فلتر تاريخ (SdAppBar لا يدعمها) ومبنية على AccountingTheme؛ تحتاج قرار (توسيع نطاق AccountingTheme أو دعم SdAppBar.bottom/tabs)
- [x] `pages/accounting/funds_overview_page.dart` — مراقبة الأموال (عالية) — 2026-10-16، مُرحَّلة (SdPage+SdAppBar+SdEmptyState)؛ ترميز ألوان الصناديق محفوظ؛ الأرصدة/getFundsOverview بلا مساس؛ analyze: No issues
- [x] `pages/accounting/journal_entries_page.dart` — القيود المحاسبية (عالية) — 2026-10-16، قشرة؛ منطق الترحيل/الحذف/الصلاحيات بلا مساس؛ AccountingTheme سليم؛ analyze: No issues
- [x] `pages/accounting/revenue_page.dart` — الإيرادات (عالية) — 2026-10-16، قشرة؛ بطاقة hero success؛ صيغ القيد/الترحيل بلا مساس؛ analyze: No issues
- [x] `pages/accounting/salaries_page.dart` — الرواتب (عالية) — 2026-10-16، قشرة؛ صيغة earnedByDays والحسابات بلا مساس؛ خلايا الجدول المالية legacy بخط accR.small (دَين — قد يقلّ عن 11.5)؛ analyze: No issues
- [~] `pages/accounting/settlement_reports_page.dart` — تقارير التسديدات اليومية (عالية) — ⏸️ مؤجّلة: الهيكل مبني كلياً على AccountingTheme (bgPrimary/bgCard/borderColor)؛ لا يمكن توحيد الهيكل دون لمس AccountingTheme؛ تحتاج قرار
- [x] `pages/accounting/wallet_transactions_page.dart` — عمليات المحفظة (عالية) — 2026-10-16، قشرة؛ SdEmptyState؛ الفلاتر/الجدول/الأرصدة بلا مساس؛ analyze: No issues
- [x] `pages/accounting/activation_profitability_page.dart` — تقرير ربحية التفعيلات (متوسطة) — 2026-10-16، قشرة؛ _fmt/profitability/الأرباح بلا مساس؛ analyze: No issues
- [x] `pages/accounting/aging_report_page.dart` — أعمار الديون (متوسطة) — 2026-10-16، قشرة؛ بطاقات الملخّص/الجدول بلا مساس؛ analyze: No issues
- [x] `pages/accounting/balance_sheet_page.dart` — الميزانية العمومية (متوسطة) — 2026-10-16، قشرة؛ المعادلة/الإجماليات/التصدير بلا مساس؛ analyze: No issues
- [x] `pages/accounting/cash_flow_page.dart` — التدفقات النقدية (متوسطة) — 2026-10-16، قشرة؛ ترميز الأقسام/الإشارات محفوظ؛ الإجماليات بلا مساس؛ analyze: No issues
- [x] `pages/accounting/employee_adjustments_page.dart` — الخصومات والمكافآت (متوسطة) — 2026-10-16، قشرة؛ SdFilterChips للنوع؛ المبالغ/الصيغ بلا مساس؛ analyze: No issues
- [x] `pages/accounting/fixed_expenses_page.dart` — المصاريف الثابتة (متوسطة) — 2026-10-16، قشرة؛ hex العلامة → sd؛ ترميز الفئات محفوظ؛ analyze: No issues
- [x] `pages/accounting/ftth_operator_transactions_page.dart` — عمليات: {اسم المشغل} (متوسطة) — 2026-10-16، مُرحَّلة (SdPage+SdAppBar+SdEmptyState)؛ الجدول/المنطق/تنسيق المبالغ بلا مساس؛ analyze: No issues
- [x] `pages/accounting/income_statement_page.dart` — قائمة الدخل (متوسطة) — 2026-10-16، قشرة؛ فلتر التاريخ لشريط body؛ النسب/الهامش بلا مساس؛ analyze: No issues
- [x] `pages/accounting/sas_accounting_page.dart` — نظام الساس — الحسابات (متوسطة) — 2026-10-16، قشرة؛ المحصّل/التوزيع/المصادقة بلا مساس؛ analyze: No issues
- [x] `pages/accounting/statistics_page.dart` — الإحصائيات (متوسطة) — 2026-10-16، قشرة؛ _MiniRingPainter/shouldRepaint/المخططات بلا مساس؛ analyze: No issues
- [x] `pages/accounting/trial_balance_page.dart` — ميزان المراجعة (متوسطة) — 2026-10-16، قشرة كاملة نظيفة؛ الإجماليات/التوازن/التصدير بلا مساس؛ analyze: No issues
- [x] `pages/accounting/withdrawal_requests_page.dart` — طلبات سحب الأموال (متوسطة) — 2026-10-16، قشرة؛ بطاقات الإحصائيات/الموافقة بلا مساس؛ analyze: No issues
- [x] `pages/accounting/audit_trail_page.dart` — سجل التدقيق (منخفضة) — 2026-10-16، مُرحَّل (SdAppBar+SdFilterChips+SdEmptyState)؛ حُذف كل hex وAccountingTheme من الملف؛ analyze: No issues
- [x] `pages/accounting/budget_page.dart` — الميزانية التقديرية (منخفضة) — 2026-10-16، قشرة؛ جداول المخطط/الفعلي/الانحراف بلا مساس؛ ملاحظة: زر تبديل الانحراف فقد تمييز الحالة النشطة؛ analyze: No issues
- [x] `pages/accounting/financial_ratios_page.dart` — النسب المالية (منخفضة) — 2026-10-16، قشرة؛ النسب السبع/المخطط بلا مساس؛ analyze: No issues
- [x] `pages/accounting/ftth_operator_linking_page.dart` — ربط المشغلين ({العدد} مشغل) (منخفضة) — 2026-10-16، مُرحَّلة (SdPage+SdAppBar+SdStatusChip)؛ جدول LTR محفوظ؛ منطق الربط بلا مساس؛ analyze: No issues
- [x] `pages/accounting/hr_reports_page.dart` — تقارير الموارد البشرية (منخفضة) — 2026-10-16، مُرحَّل (SdAppBar+جداول موحّدة)؛ الأرقام/النسب/الاستدعاءات بلا مساس؛ analyze: No issues
- [x] `pages/accounting/monthly_comparison_page.dart` — المقارنة الشهرية (منخفضة) — 2026-10-16، قشرة؛ شرائح الأشهر لشريط فلتر؛ القيم/النسب بلا مساس؛ ألوان الرسوم → sd دلالية (قابل للعكس)؛ analyze: No issues
- [x] `pages/accounting/period_closing_page.dart` — إقفال الفترات (منخفضة) — 2026-10-16، هيكل فقط؛ منطق _togglePeriod/الإقفال/إعادة الفتح محفوظ حرفياً؛ analyze: No issues
- [x] `pages/accounting/salary_policy_page.dart` — سياسات الرواتب (منخفضة) — 2026-10-16، قشرة؛ قيم السياسة/الحوارات بلا مساس؛ analyze: No issues
- [x] `pages/accounting/system_audit_page.dart` — التدقيق المحاسبي الشامل (منخفضة) — 2026-10-16، مُرحَّل؛ حُذف كل hex؛ منطق _runAudit/العرض بلا مساس؛ analyze: No issues
- [x] `pages/accounting/year_comparison_page.dart` — المقارنة السنوية (منخفضة) — 2026-10-16، قشرة؛ اختيار السنتين لشريط فلتر؛ منطق المقارنة/النسب بلا مساس؛ ألوان الرسوم → sd دلالية (قابل للعكس)؛ analyze: No issues
- [x] `pages/accounting/zone_maintenance_fees_page.dart` — أجور صيانة الزونات (منخفضة) — 2026-10-16، هيكل فقط؛ حوارات/منطق المبالغ محفوظ على AccountingTheme؛ analyze: No issues

## الموجة 6 — الوحدات وبقية FTTH والمهام

- [ ] `inventory/inventory_page.dart` — المخازن (عالية)
- [ ] `network_quality/pages/device_detail_page.dart` — تفاصيل الجهاز (اسم الجهاز) (عالية)
- [ ] `sas_agent/pages/sas_subscriber_detail_page.dart` — تفاصيل المشترك (عالية)
- [ ] `sas_agent/pages/sas_subscriber_form_page.dart` — مشترك جديد / تعديل المشترك (عالية)
- [ ] `sas_agent/sas_agent_page.dart` — وكيل الساس (عالية)
- [ ] `citizen_portal/pages/citizen_portal_dashboard_page.dart` — بوابة المواطن (متوسطة)
- [ ] `citizen_portal/pages/companies_management_page.dart` — إدارة الشركات (متوسطة)
- [ ] `ftth/auth/login_page.dart` — تسجيل الدخول (FTTH) (متوسطة)
- [ ] `ftth/reports/audit_log_page.dart` — سجل التدقيق - {اسم المشترك} (متوسطة)
- [ ] `ftth/reports/profits_page.dart` — حساب الأرباح (متوسطة)
- [ ] `ftth/reports/zones_page.dart` — الزونات (متوسطة)
- [ ] `ftth/requests/customer_hub_page.dart` — مشترك جديد (متوسطة)
- [ ] `ftth/subscriptions/connections_list_page.dart` — جميع الوصولات / وصولات المستخدم / وصولات الفني (متوسطة)
- [ ] `ftth/tasks/customer_search_connect_page.dart` — بحث / المنطقة / الجهاز / التثبيت (متوسطة)
- [ ] `ftth/tasks/ftth_connect_form.dart` — توصيل مشترك (متوسطة)
- [ ] `ftth/tasks/ftth_tasks_page.dart` — مهام التوصيل — FTTH (متوسطة)
- [ ] `ftth/tickets/customer_tickets_page.dart` — تذاكر المشترك (متوسطة)
- [ ] `ftth/transactions/account_records_page.dart` — سجلات الحسابات (متوسطة)
- [ ] `ftth/transactions/caounter_details_page.dart` — تفاصيل البيانات - {المستخدم} (متوسطة)
- [ ] `ftth/transactions/creator_transactions_detail_page.dart` — تفاصيل معاملات (متوسطة)
- [ ] `ftth/transactions/daily_settlement_page.dart` — التسديدات اليومية (متوسطة)
- [ ] `inventory/pages/customer_details_page.dart` — تفاصيل العميل (متوسطة)
- [ ] `inventory/pages/customers_page.dart` — العملاء (متوسطة)
- [ ] `inventory/pages/dispensing_page.dart` — صرف الفنيين (متوسطة)
- [ ] `inventory/pages/invoice_form_page.dart` — فاتورة بيع جديدة / فاتورة شراء جديدة (متوسطة)
- [ ] `inventory/pages/invoices_page.dart` — الفواتير (متوسطة)
- [ ] `inventory/pages/materials_page.dart` — المواد والأصناف (متوسطة)
- [ ] `inventory/pages/stock_levels_page.dart` — مستويات المخزون (متوسطة)
- [ ] `network_quality/pages/quality_results_page.dart` — نتيجة فحص الجودة (متوسطة)
- [ ] `network_quality/pages/router_wifi_edit_page.dart` — تعديل WiFi الراوتر (متوسطة)
- [ ] `permissions/permission_gate.dart` — غير مصرح (أو اسم الصفحة) (متوسطة)
- [ ] `sas_agent/pages/sas_bulk_import_page.dart` — استيراد جماعي (متوسطة)
- [ ] `sas_agent/pages/sas_bulk_message_page.dart` — إرسال جماعي (متوسطة)
- [ ] `sas_agent/pages/sas_package_prices_page.dart` — أسعار الباقات (متوسطة)
- [ ] `sas_agent/pages/sas_reminders_page.dart` — الإشعارات والتذكير (متوسطة)
- [ ] `sas_agent/pages/sas_reports_page.dart` — التقارير المجمّعة (متوسطة)
- [ ] `sas_agent/pages/sas_reports_tab.dart` — التقارير (متوسطة)
- [ ] `sas_agent/pages/sas_settings_tab.dart` — الإعدادات (متوسطة)
- [ ] `sas_agent/pages/sas_ticket_detail_page.dart` — تذكرة # (متوسطة)
- [ ] `sas_agent/pages/sas_transactions_page.dart` — سجل الحركات (متوسطة)
- [ ] `sas_agent/whatsapp/ui/wa_settings_screen.dart` — إعدادات واتساب (متوسطة)
- [ ] `sas_agent/widgets/sas_citizen_statement.dart` — كشف: <اسم المشترك> (متوسطة)
- [ ] `task/audit_dashboard_page.dart` — لوحة تحكم التدقيق (متوسطة)
- [ ] `task/reports_page.dart` — التقارير / لوحة التحكم (متوسطة)
- [ ] `task/technician_performance_page.dart` — أداء الفنيين (متوسطة)
- [ ] `whatsapp/pages/whatsapp_server_settings_page.dart` — إعدادات WhatsApp Server (متوسطة)
- [ ] `whatsapp/pages/whatsapp_settings_hub_page.dart` — إعدادات الواتساب (متوسطة)
- [ ] `widgets/platform_webview.dart` — (عنوان ديناميكي) (متوسطة)
- [ ] `ftth/reports/export_page.dart` — تصدير البيانات (منخفضة)
- [ ] `ftth/transactions/account_stats_page.dart` — إحصائيات السجلات (منخفضة)
- [ ] `ftth/transactions/creator_amounts_page.dart` — مبالغ المنشئين (محمية بكلمة مرور) (منخفضة)
- [ ] `ftth/users/user_records_page.dart` — سجلات {اسم المستخدم} (منخفضة)
- [ ] `ftth/users/users_data_page.dart` — بيانات المستخدمين (منخفضة)
- [ ] `inventory/pages/customer_form_page.dart` — إضافة عميل / تعديل عميل (منخفضة)
- [ ] `inventory/pages/dispensing_form_page.dart` — صرف مواد (منخفضة)
- [ ] `inventory/pages/inventory_reports_page.dart` — تقارير المخزون (منخفضة)
- [ ] `inventory/pages/invoice_details_page.dart` — تفاصيل الفاتورة (منخفضة)
- [ ] `inventory/pages/movements_page.dart` — حركات المخزون (منخفضة)
- [ ] `inventory/pages/return_form_page.dart` — مرتجع مبيعات / مرتجع مشتريات (منخفضة)
- [ ] `inventory/pages/returns_page.dart` — المرتجعات (منخفضة)
- [ ] `inventory/pages/suppliers_page.dart` — الموردين (منخفضة)
- [ ] `inventory/pages/voucher_form_page.dart` — سند قبض / سند صرف (منخفضة)
- [ ] `inventory/pages/vouchers_page.dart` — سندات القبض والصرف (منخفضة)
- [ ] `inventory/pages/warehouses_page.dart` — المستودعات (منخفضة)
- [ ] `network_quality/network_quality_home_page.dart` — أدوات الراوتر والشبكة (منخفضة)
- [ ] `network_quality/pages/advanced_tools_page.dart` — فحص متقدم (منخفضة)
- [ ] `network_quality/pages/dns_benchmark_page.dart` — اختبار ومقارنة DNS (منخفضة)
- [ ] `network_quality/pages/history_trend_page.dart` — السجلّ والاتجاه (منخفضة)
- [ ] `network_quality/pages/live_monitor_page.dart` — المراقبة الحيّة (منخفضة)
- [ ] `network_quality/pages/quality_scan_page.dart` — فحص جودة الإنترنت (منخفضة)
- [ ] `network_quality/pages/wifi_channel_analyzer_page.dart` — محلّل قنوات WiFi (منخفضة)
- [ ] `sas_agent/pages/sas_admin_agents_page.dart` — إدارة الوكلاء (منخفضة)
- [ ] `sas_agent/pages/sas_debtors_page.dart` — المدينون (منخفضة)
- [ ] `sas_agent/pages/sas_explorer_page.dart` — مستكشف الساس المتقدّم (منخفضة)
- [ ] `sas_agent/pages/sas_license_page.dart` — الترخيص والصلاحيات (منخفضة)
- [ ] `sas_agent/pages/sas_profits_page.dart` — تقرير الأرباح (منخفضة)
- [ ] `sas_agent/pages/sas_regions_page.dart` — المناطق وأجور الصيانة (منخفضة)
- [ ] `sas_agent/pages/sas_test_message_page.dart` — إرسال رسالة تجريبية (منخفضة)
- [ ] `sas_agent/premises/ui/premises_detail_screen.dart` — تفاصيل العقار (منخفضة)
- [ ] `sas_agent/premises/ui/premises_form_screen.dart` — عقار جديد / تعديل عقار (منخفضة)
- [ ] `sas_agent/premises/ui/premises_list_screen.dart` — العقارات (منخفضة)
- [ ] `sas_agent/whatsapp/ui/wa_templates_screen.dart` — قوالب الرسائل (منخفضة)
- [ ] `whatsapp/pages/whatsapp_system_settings_page.dart` — نظام الواتساب (منخفضة)

## الموجة 7 — مدير النظام والإعدادات والأدوات والبقية

- [ ] `pages/account/account_info_page.dart` — معلومات الحساب / حسابي (متوسطة)
- [ ] `pages/analysis_page.dart` — تحليل المعلومات (متوسطة)
- [ ] `pages/citizen_portal/citizen_details_page.dart` — تفاصيل المواطن (متوسطة)
- [ ] `pages/citizen_portal/citizen_portal_dashboard.dart` — نظام المواطن (متوسطة)
- [x] `pages/company_settings_page.dart` — إعدادات الشركة (متوسطة) — 2026-10-16، شلّ (SdTheme.scope + ثوابت الثيم الداخلية → sd: شريط نيلي/خلفية ground/لون مرافق)؛ منطق الإعدادات/الحفظ بلا مساس؛ analyze: No issues
- [ ] `pages/deductions_bonuses_page.dart` — الخصومات والمكافآت (متوسطة)
- [ ] `pages/employee_tracking_report_page.dart` — تقارير تتبع الموظفين (متوسطة)
- [ ] `pages/ftth/fetch_server_data_page.dart` — جلب بيانات الموقع (متوسطة)
- [ ] `pages/ftth/ftth_company_page.dart` — صفحة الشركة (متوسطة)
- [ ] `pages/hr/employee_profile_page.dart` — بيانات HR / ملف الموظف (متوسطة)
- [ ] `pages/hr_reports_page.dart` — تقارير الموارد البشرية (متوسطة)
- [ ] `pages/iptv/iptv_subscribers_page.dart` — مشتركي IPTV (متوسطة)
- [ ] `pages/leave_management_page.dart` — إدارة الإجازات (متوسطة)
- [ ] `pages/local_storage_page.dart` — التخزين المحلي (متوسطة)
- [ ] `pages/local_subscriber_details_page.dart` — {اسم المشترك} (متوسطة)
- [ ] `pages/offline_router_setup_page.dart` — إعداد الراوتر / واجهة الراوتر (متوسطة)
- [ ] `pages/properties/properties_list_page.dart` — سجل العقارات (متوسطة)
- [ ] `pages/properties/property_detail_page.dart` — تفاصيل العقار (متوسطة)
- [ ] `pages/properties/property_form_page.dart` — إضافة/تعديل عقار (متوسطة)
- [ ] `pages/salary_management_page.dart` — إدارة الرواتب (متوسطة)
- [ ] `pages/server_data_page.dart` — تحليلات Dashboard (متوسطة)
- [x] `pages/settings/ftth_sync_settings_page.dart` — مزامنة FTTH (متوسطة) — 2026-10-16، شلّ (SdTheme.scope + شريط نيلي + TabBar موحّد + خلفية ground)؛ منطق المزامنة/المصادقة بلا مساس؛ analyze: No issues
- [ ] `pages/statistics_page.dart` — الإحصائيات (متوسطة)
- [x] `pages/super_admin/agents_management_page.dart` — إدارة الوكلاء (متوسطة) — 2026-10-16، شلّ (SdTheme.scope + خلفية ground على فروع build الثلاثة)؛ جسم AccountingTheme (دَين)؛ منطق العمولات/العزل بلا مساس؛ analyze: No issues
- [x] `pages/super_admin/permissions_management_v2_page.dart` — صلاحيات الموظف/الشركة (V2) (متوسطة) — 2026-10-16، شلّ (SdTheme.scope + خلفية ground + كنس ألوان SnackBar)؛ **منطق الصلاحيات/الحفظ/التبويبات بلا أي مساس**؛ الجسم legacy (دَين)؛ analyze: No issues
- [x] `pages/super_admin/sadara_portal_page.dart` — منصة الصدارة (متوسطة) — 2026-10-16، شلّ (SdTheme.scope + خلفية ground)؛ جسم AccountingTheme (دَين)؛ منطق الطلبات بلا مساس؛ analyze: No issues
- [~] `pages/super_admin/super_admin_dashboard.dart` — لوحة تحكم مدير النظام (متوسطة) — ⛔ استثناء (2026-10-16): تصميم Energy Dashboard غامر داكن (تدرّج أسود/نيون) × نظام sd فاتح؛ يُترك كما هو كشاشة kml_zones الغامرة حتى قرار صاحب المشروع. لم يُلمس (شاشة SuperAdmin حسّاسة).
- [x] `pages/super_admin/unified_companies_page.dart` — إدارة الشركات (متوسطة) — 2026-10-16، شلّ (SdTheme.scope + خلفية ground)؛ جسم EnergyDashboardTheme الفاتح (دَين)؛ **منطق إدارة الشركات/العزل بلا أي مساس**؛ analyze: No issues
- [ ] `pages/track_users_map_page.dart` — تتبع الكادر (متوسطة)
- [ ] `pages/user_details_page.dart` — تفاصيل المستخدم: {الاسم} (متوسطة)
- [ ] `pages/whatsapp_batch_reports_page.dart` — 📊 تقارير الإرسال الجماعي (متوسطة)
- [ ] `pages/whatsapp_bulk_sender_page.dart` — إرسال رسائل WhatsApp جماعية (متوسطة)
- [ ] `pages/whatsapp_templates_page.dart` — قوالب الرسائل (متوسطة)
- [ ] `pages/aria_page.dart` — لوحة التحكم الرئيسية (أريا) (منخفضة)
- [ ] `pages/charts_page.dart` — المخططات (منخفضة)
- [ ] `pages/client_setup_page.dart` — إعداد التطبيق (منخفضة)
- [ ] `pages/company_diagnostics_page.dart` — 🔧 تشخيص النظام (منخفضة)
- [ ] `pages/diagnostics/permissions_diagnostics_page.dart` — تشخيص الصلاحيات (منخفضة)
- [ ] `pages/diagnostics/system_diagnostics_page.dart` — تشخيص النظام (منخفضة)
- [ ] `pages/google_drive_files_page.dart` — ملفات Google Drive (منخفضة)
- [x] `pages/printer_settings_page.dart` — إعدادات طابعة الإيصالات (منخفضة) — 2026-10-16، مُرحَّل بالكامل (SdPage+SdAppBar+SdCard+SdButton+SdEmptyState)؛ منطق اختيار/تجربة الطابعة بلا مساس؛ analyze: No issues
- [ ] `pages/properties/location_master_page.dart` — المناطق والعناوين (منخفضة)
- [ ] `pages/properties/property_qr_batches_page.dart` — دفعات QR (منخفضة)
- [ ] `pages/properties/property_qr_scanner.dart` — مسح رمز QR بالكاميرا (منخفضة)
- [ ] `pages/receipt_template_editor_page.dart` — محرر قالب الوصل (منخفضة)
- [ ] `pages/reminder_reports_page.dart` — تقارير التذكير التلقائي (منخفضة)
- [x] `pages/settings_page.dart` — الإعدادات (منخفضة) — 2026-10-16، مُرحَّل بالكامل (SdPage+SdAppBar+SdCard+SdInfoRow+SdButton)؛ تحقّق/حفظ رقم رسول بلا مساس؛ analyze: No issues
- [x] `pages/settings_text_scale_page.dart` — حجم النص (منخفضة) — 2026-10-16، مُرحَّل بالكامل (SdPage+SdAppBar+SdCard+SdFilterChips+SdButton)؛ منطق AppTextScale بلا مساس؛ analyze: No issues
- [x] `pages/super_admin/add_company_page.dart` — إضافة شركة جديدة (منخفضة) — 2026-10-16، شلّ (SdPage+SdAppBar + كنس ألوان؛ أُبقي Stepper)؛ **منطق createTenantWithAdmin/التحقّق بلا أي مساس**؛ analyze: No issues
- [x] `pages/super_admin/company_details_page.dart` — تفاصيل الشركة (منخفضة) — 2026-10-16، شلّ (SdTheme.scope + خلفية ground)؛ جسم EnergyDashboardTheme (دَين)؛ منطق التفاصيل/الحالة بلا مساس؛ analyze: No issues
- [x] `pages/super_admin/edit_company_page.dart` — تعديل الشركة (منخفضة) — 2026-10-16، مُرحَّل أعمق (SdPage+SdAppBar+بطاقات sd+SdButton؛ استبدال EnergyDashboardTheme)؛ **منطق put/useInternalKey/العزل بلا أي مساس**؛ analyze: No issues
- [x] `pages/super_admin/tenant_features_page.dart` — إدارة ميزات الشركة (منخفضة) — 2026-10-16، مُرحَّل (SdTheme.scope+شريط نيلي+TabBar+SdButton+SdCard؛ استبدال GoogleFonts/EnergyDashboardTheme)؛ **مفاتيح الميزات/حفظ Firestore بلا أي مساس**؛ analyze: No issues
- [x] `pages/super_admin/vps_data_manager_page.dart` — إدارة بيانات VPS (منخفضة) — 2026-10-16، شلّ (SdTheme.scope + خلفية ground + كنس SnackBar)؛ جسم EnergyDashboardTheme (دَين، شاشة DatabaseAdmin حسّاسة)؛ منطق CRUD بلا مساس؛ analyze: No issues
- [ ] `pages/whatsapp_business_config_page.dart` — إعدادات WhatsApp Business API (منخفضة)
- [ ] `pages/whatsapp_excel_sender_page.dart` — إرسال جماعي من Excel (منخفضة)
- [ ] `pages/work_schedules_page.dart` — جداول الدوام (منخفضة)

## مواصفات الواجهة الرئيسية الجديدة (pages/home_page.dart) — معتمدة من صاحب المشروع

التصميم المرجعي المرئي: `docs/ui-unification/design/home_3d_reference.html` (افتحه بالمتصفح وطابقه). للمقارنة مع الحالي: `screenshots/home_before_2026-10-16.jpg`.

- الشريط العلوي `SdAppBar`: العنوان «رمز الصدارة» + سطر حالة «FTTH متصل · رقم الهاتف» بنقطة خضراء؛ أزرار `SdAppBarAction` بأسماء: «تتبّع الكادر»، «الإشعارات» (بشارة)، وزر حالة الموقع: عند التوقف `danger: true` بنص «الموقع متوقف — تفعيل».
- بطاقة «التعليمات الجديدة» بارزة بمكعّب برتقالي + نص التعليمة + زر «عرض التعليمات» (بدل أيقونة المعلومات الصغيرة).
- العدّادات الثلاثة `SdStatPedestal` (max = أكبر الثلاثة): طلبات الوكلاء (field)، المهام المفتوحة (admin)، طلبات الموظفين (platform)؛ قابلة للضغط لفتح القائمة المعنية.
- ~~فلاتر `SdFilterChips`~~ **أُزيلت بطلب صاحب المشروع (2026-10-16)**: لا شريط تصفية؛ كل الأقسام تظهر دائماً (محكومة بالصلاحيات فقط).
- الأقسام بـ `SdSectionHeader` + `SdTileGrid` + `SdMenuTile` (بدون سهم داخل البلاطة):
  - العمليات الميدانية (field): صفحة الوكيل (شارة طلبات الوكلاء)، المهام (شارة)، الزونات، خريطة الزونات، مشترك جديد، مشتركي IPTV، صفحة وكيل الساس.
  - الإدارة والموارد (admin) + التواصل (comms) في قسم واحد بعنوان «الإدارة والموارد · التواصل»: HR، شاشتي، المتابعة، المخازن، الحسابات، صفحة الشركة، ثم المحادثة (شارة) والتبليغات — زرّا التواصل يملآن الصف الثاني بلونهما البرتقالي.
  - المنصّات والبيانات (platform): منصة الصدارة، سجل العقارات، البحث بالذكاء الاصطناعي.
- القائمة الجانبية (سطح المكتب/الآيباد): أزرار مجسّمة بأسماء ظاهرة: إدارة المستخدمين، تشخيص النظام، إعدادات الشركة، مزامنة FTTH، وتسجيل الخروج مفصول بلون أحمر فاتح. على الهاتف تبقى في الدرج (Drawer).
- الهاتف: بلاطات عمودية بعمودين، العدّادات عمود واحد، الفلاتر صف يُمرَّر أفقياً.
- الخلفية سادة `SdColors.ground` — تُحذف زخرفة الأيقونات الباهتة (_InternetIconsBgPainter/_HomeRadialWavePainter) من الواجهة.
- الشريط العائم أسفل اليمين: يُسأل صاحب المشروع قبل إزالته أو دمجه.
- تبقى كما هي حرفياً: الصلاحيات (permissionKey / PermissionManager)، العدّادات الحيّة، دوال التنقّل، مشاركة الموقع، التبليغات العاجلة، الإشعارات.

## ملفات مشتبه أنها ميتة (لا تُرحَّل — تُعرض للحذف بموافقة صريحة فقط)

- `ftth/core/permissions_page.dart` — إدارة الصلاحيات
- `ftth/diagnostic/diagnostic_page.dart` — 🔧 تشخيص التطبيق
- `ftth/reports/data_page.dart` — بيانات
- `ftth/subscriptions/all_subscriptions_details_page.dart` — كل الاشتراكات (تفاصيل كاملة)
- `ftth/subscriptions/plans_bundles_page.dart` — الباقات و العروض
- `ftth/tickets/TKTAT.dart` — TKTATs
- `ftth/tickets/technicians_page.dart` — فني التوصيل
- `ftth/tickets/tickets_login_page.dart` — نظام التذاكر
- `ftth/tickets/tktat_raw_page.dart` — الحقول الخام للتذكرة
- `ftth/tickets/tktats_page_beautiful.dart` — TKTATs (نسخة بديلة)
- `ftth/users/user_transactions_page.dart` — معاملات: {اسم المستخدم}
- `ftth/users/users_dashboard_webview.dart` — بيانات المستخدمين
- `ftth/whatsapp/whatsapp_floating_window.dart` — واتساب ويب
- `ftth/widgets/notifications_page.dart` — الإشعارات
- `inventory/pages/purchase_form_page.dart` — أمر شراء جديد / تعديل أمر شراء
- `inventory/pages/purchases_page.dart` — أوامر الشراء
- `inventory/pages/sale_form_page.dart` — بيع جديد
- `inventory/pages/sales_page.dart` — المبيعات
- `network_quality/pages/optical_webview_page.dart` — قراءة البصريات عبر المتصفح
- `pages/accounting/cashbox_page.dart` — الصناديق النقدية
- `pages/accounting/ftth_operator_account_page.dart` — كشف حساب: {اسم المشغل}
- `pages/accounting/plan_profits_page.dart` — 💰 أرباح الباقات
- `pages/admin/organizations_management_page.dart` — إدارة المنظمات/الشركات
- `pages/agents_page.dart` — وكلاء {المجموعة}
- `pages/dashboard_page.dart` — مرحبًا {اسم المستخدم}
- `pages/enhanced_home_page.dart` — الصفحة الرئيسية المحسنة
- `pages/enhanced_search_users_page.dart` — البحث المحسن عن المستخدمين
- `pages/firebase_data_viewer.dart` — عرض بيانات Firebase
- `pages/ftth_advanced_system.dart` — النظام المتقدم - لوحة التحكم
- `pages/modern_home_page.dart` — رمز الصدارة
- `pages/permission_reset_page.dart` — إعادة تعيين الصلاحيات
- `pages/search_comparison_page.dart` — مقارنة أنظمة البحث
- `pages/settings/company_firebase_settings_page.dart` — إعدادات الشركة
- `pages/settings/device_permissions_page.dart` — صلاحيات الأجهزة
- `pages/super_admin/tenant_whatsapp_permissions_page.dart` — صلاحيات الواتساب
- `pages/super_admin_login_page.dart` — مدير النظام
- `pages/user_whatsapp_permissions_page.dart` — صلاحيات الواتساب
- `pages/users_page.dart` — إدارة المستخدمين
- `pages/users_page_firebase.dart` — إدارة المستخدمين
- `pages/vps_super_admin_login_page.dart` — مدير النظام
- `pages/vps_tenant_login_page.dart` — تسجيل الدخول
- `task/technician_transactions_page.dart` — معاملاتي المالية
- `widgets/auth_guard.dart` — جاري التحقق من الجلسة...

## قرارات تحتاج موافقة صاحب المشروع قبل التنفيذ

- ربط `SdTheme.light()` في main.dart بدل AppTheme.
- توجيه ثوابت AccountingTheme / EnergyDashboardTheme / SasUi / Nq3d إلى ألوان Sd (يغيّر شاشات كثيرة دفعة واحدة).
- حذف أو أرشفة أي ملف من قائمة الملفات الميتة.
- تقسيم الملفات الضخمة (أكثر من 3000 سطر) إلى ملفات/ودجتات.
- إزالة الشريط العائم من الرئيسية.
- أي commit أو push أو إصدار.
