# خطة ترحيل الواجهات إلى الثيم الموحّد (lib/frontend)

حدّث المربعات `[x]` بعد إنهاء كل شاشة واجتياز `flutter analyze` واختبار العروض الأربعة (390/820/1180/1440). الترتيب داخل كل موجة: الأولوية العالية أولاً. سجّل كل شاشة منتهية في `PROGRESS_LOG.md`.

## الموجة 1 — التحضير

- [x] إنشاء `lib/frontend/` (رموز، ثيم، مكوّنات، تجاوب، معرض، README)
- [ ] `flutter analyze lib/frontend` بلا أخطاء (وإصلاح ما يظهر داخل lib/frontend فقط)
- [ ] تشغيل المعرض: `flutter run -d windows -t lib/frontend/preview/gallery_main.dart` ومراجعة الأشكال على العروض الأربعة

## الموجة 2 — الانطباع الأول

- [ ] `widgets/permissions_gate.dart` — السماح للتطبيق بالوصول للموقع (عالية)
- [ ] `pages/login/premium_login_page.dart` — تسجيل الدخول (عالية)
- [ ] `pages/home_page.dart` — رمز الصدارة (عالية)

## الموجة 3 — العمل الميداني اليومي

- [ ] `ftth/core/home_page.dart` — لوحة التحكم (عالية)
- [ ] `ftth/reports/agents_details_page.dart` — تفاصيل الوكلاء (عالية)
- [ ] `ftth/requests/customer_onboarding_page.dart` — تسجيل مشترك جديد (عالية)
- [ ] `ftth/subscriptions/expiring_soon_page.dart` — الاشتراكات المنتهية قريباً / الاشتراكات التجريبية (عالية)
- [ ] `ftth/subscriptions/subscription_details_page.dart` — شراء اشتراك جديد / تجديد او تغيير الاشتراك (عالية)
- [ ] `ftth/subscriptions/subscriptions_page.dart` — المناطق / الاشتراكات (عالية)
- [ ] `ftth/tickets/create_ticket_page.dart` — التبليغ عن مشكلة (عالية)
- [ ] `ftth/tickets/tktat_details_page.dart` — تفاصيل TKTAT (عالية)
- [ ] `ftth/tickets/tktats_page.dart` — تطبيق FTTH (قائمة المهام/التذاكر) (عالية)
- [ ] `ftth/transactions/transactions_page.dart` — التحويلات (عالية)
- [ ] `ftth/users/quick_search_users_page.dart` — البحث السريع - المستخدمين (عالية)
- [ ] `ftth/users/user_details_page.dart` — تفاصيل المستخدم (عالية)
- [ ] `ftth/users/users_page.dart` — المشتركين (عالية)
- [ ] `pages/search_users_page.dart` — البحث عن المستخدمين (عالية)
- [ ] `task/add_task_api_dialog.dart` — إضافة مهمة جديدة (عالية)
- [ ] `task/follow_up_page.dart` — المتابعة والتقييم (عالية)
- [ ] `task/home_page_tasks.dart` — المهام (عالية)
- [ ] `task/task_list_screen.dart` — المهام (عالية)

## الموجة 4 — الموظف والتواصل

- [ ] `pages/attendance_page.dart` — نظام البصمة (عالية)
- [ ] `pages/chat/chat_conversation_page.dart` — المحادثة (اسم الغرفة) (عالية)
- [ ] `pages/chat/chat_rooms_page.dart` — المحادثات (عالية)
- [ ] `pages/hr_hub_page.dart` — الموارد البشرية (عالية)
- [ ] `pages/kml_zones_map_page.dart` — خريطة الزونات (عالية)
- [ ] `pages/my_dashboard_page.dart` — شاشتي (عالية)
- [ ] `pages/users_page_vps.dart` — إدارة الموظفين (عالية)
- [ ] `pages/whatsapp_chat_page.dart` — محادثة واتساب (عالية)
- [ ] `pages/whatsapp_conversations_page.dart` — محادثات WhatsApp (عالية)
- [ ] `pages/announcements/announcements_page.dart` — الإعلانات والتبليغات (متوسطة)

## الموجة 5 — المحاسبة

- [ ] `pages/accounting/accounting_dashboard_page.dart` — الحسابات (عالية)
- [ ] `pages/accounting/chart_of_accounts_page.dart` — شجرة الحسابات (عالية)
- [ ] `pages/accounting/client_accounts_page.dart` — كشف الحسابات (عالية)
- [ ] `pages/accounting/collections_page.dart` — تحصيلات الفنيين (عالية)
- [ ] `pages/accounting/compound_journal_entry_page.dart` — قيد مركب (عالية)
- [ ] `pages/accounting/expenses_page.dart` — المصروفات (عالية)
- [ ] `pages/accounting/ftth_operators_dashboard_page.dart` — لوحة المشغلين (خادمنا / FTTH / المقارنة) (عالية)
- [ ] `pages/accounting/funds_overview_page.dart` — مراقبة الأموال (عالية)
- [ ] `pages/accounting/journal_entries_page.dart` — القيود المحاسبية (عالية)
- [ ] `pages/accounting/revenue_page.dart` — الإيرادات (عالية)
- [ ] `pages/accounting/salaries_page.dart` — الرواتب (عالية)
- [ ] `pages/accounting/settlement_reports_page.dart` — تقارير التسديدات اليومية (عالية)
- [ ] `pages/accounting/wallet_transactions_page.dart` — عمليات المحفظة (عالية)
- [ ] `pages/accounting/activation_profitability_page.dart` — تقرير ربحية التفعيلات (متوسطة)
- [ ] `pages/accounting/aging_report_page.dart` — أعمار الديون (متوسطة)
- [ ] `pages/accounting/balance_sheet_page.dart` — الميزانية العمومية (متوسطة)
- [ ] `pages/accounting/cash_flow_page.dart` — التدفقات النقدية (متوسطة)
- [ ] `pages/accounting/employee_adjustments_page.dart` — الخصومات والمكافآت (متوسطة)
- [ ] `pages/accounting/fixed_expenses_page.dart` — المصاريف الثابتة (متوسطة)
- [ ] `pages/accounting/ftth_operator_transactions_page.dart` — عمليات: {اسم المشغل} (متوسطة)
- [ ] `pages/accounting/income_statement_page.dart` — قائمة الدخل (متوسطة)
- [ ] `pages/accounting/sas_accounting_page.dart` — نظام الساس — الحسابات (متوسطة)
- [ ] `pages/accounting/statistics_page.dart` — الإحصائيات (متوسطة)
- [ ] `pages/accounting/trial_balance_page.dart` — ميزان المراجعة (متوسطة)
- [ ] `pages/accounting/withdrawal_requests_page.dart` — طلبات سحب الأموال (متوسطة)
- [ ] `pages/accounting/audit_trail_page.dart` — سجل التدقيق (منخفضة)
- [ ] `pages/accounting/budget_page.dart` — الميزانية التقديرية (منخفضة)
- [ ] `pages/accounting/financial_ratios_page.dart` — النسب المالية (منخفضة)
- [ ] `pages/accounting/ftth_operator_linking_page.dart` — ربط المشغلين ({العدد} مشغل) (منخفضة)
- [ ] `pages/accounting/hr_reports_page.dart` — تقارير الموارد البشرية (منخفضة)
- [ ] `pages/accounting/monthly_comparison_page.dart` — المقارنة الشهرية (منخفضة)
- [ ] `pages/accounting/period_closing_page.dart` — إقفال الفترات (منخفضة)
- [ ] `pages/accounting/salary_policy_page.dart` — سياسات الرواتب (منخفضة)
- [ ] `pages/accounting/system_audit_page.dart` — التدقيق المحاسبي الشامل (منخفضة)
- [ ] `pages/accounting/year_comparison_page.dart` — المقارنة السنوية (منخفضة)
- [ ] `pages/accounting/zone_maintenance_fees_page.dart` — أجور صيانة الزونات (منخفضة)

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
- [ ] `pages/company_settings_page.dart` — إعدادات الشركة (متوسطة)
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
- [ ] `pages/settings/ftth_sync_settings_page.dart` — مزامنة FTTH (متوسطة)
- [ ] `pages/statistics_page.dart` — الإحصائيات (متوسطة)
- [ ] `pages/super_admin/agents_management_page.dart` — إدارة الوكلاء (متوسطة)
- [ ] `pages/super_admin/permissions_management_v2_page.dart` — صلاحيات الموظف/الشركة (V2) (متوسطة)
- [ ] `pages/super_admin/sadara_portal_page.dart` — منصة الصدارة (متوسطة)
- [ ] `pages/super_admin/super_admin_dashboard.dart` — لوحة تحكم مدير النظام (متوسطة)
- [ ] `pages/super_admin/unified_companies_page.dart` — إدارة الشركات (متوسطة)
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
- [ ] `pages/printer_settings_page.dart` — إعدادات طابعة الإيصالات (منخفضة)
- [ ] `pages/properties/location_master_page.dart` — المناطق والعناوين (منخفضة)
- [ ] `pages/properties/property_qr_batches_page.dart` — دفعات QR (منخفضة)
- [ ] `pages/properties/property_qr_scanner.dart` — مسح رمز QR بالكاميرا (منخفضة)
- [ ] `pages/receipt_template_editor_page.dart` — محرر قالب الوصل (منخفضة)
- [ ] `pages/reminder_reports_page.dart` — تقارير التذكير التلقائي (منخفضة)
- [ ] `pages/settings_page.dart` — الإعدادات (منخفضة)
- [ ] `pages/settings_text_scale_page.dart` — حجم النص (منخفضة)
- [ ] `pages/super_admin/add_company_page.dart` — إضافة شركة جديدة (منخفضة)
- [ ] `pages/super_admin/company_details_page.dart` — تفاصيل الشركة (منخفضة)
- [ ] `pages/super_admin/edit_company_page.dart` — تعديل الشركة (منخفضة)
- [ ] `pages/super_admin/tenant_features_page.dart` — إدارة ميزات الشركة (منخفضة)
- [ ] `pages/super_admin/vps_data_manager_page.dart` — إدارة بيانات VPS (منخفضة)
- [ ] `pages/whatsapp_business_config_page.dart` — إعدادات WhatsApp Business API (منخفضة)
- [ ] `pages/whatsapp_excel_sender_page.dart` — إرسال جماعي من Excel (منخفضة)
- [ ] `pages/work_schedules_page.dart` — جداول الدوام (منخفضة)

## مواصفات الواجهة الرئيسية الجديدة (pages/home_page.dart) — معتمدة من صاحب المشروع

التصميم المرجعي المرئي: `docs/ui-unification/design/home_3d_reference.html` (افتحه بالمتصفح وطابقه). للمقارنة مع الحالي: `screenshots/home_before_2026-10-16.jpg`.

- الشريط العلوي `SdAppBar`: العنوان «رمز الصدارة» + سطر حالة «FTTH متصل · رقم الهاتف» بنقطة خضراء؛ أزرار `SdAppBarAction` بأسماء: «تتبّع الكادر»، «الإشعارات» (بشارة)، وزر حالة الموقع: عند التوقف `danger: true` بنص «الموقع متوقف — تفعيل».
- بطاقة «التعليمات الجديدة» بارزة بمكعّب برتقالي + نص التعليمة + زر «عرض التعليمات» (بدل أيقونة المعلومات الصغيرة).
- العدّادات الثلاثة `SdStatPedestal` (max = أكبر الثلاثة): طلبات الوكلاء (field)، المهام المفتوحة (admin)، طلبات الموظفين (platform)؛ قابلة للضغط لفتح القائمة المعنية.
- فلاتر `SdFilterChips`: الكل / العمليات الميدانية / الإدارة والموارد / التواصل / المنصّات والبيانات.
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
