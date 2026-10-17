# تقرير التزام الشاشات بالثيم الموحّد

تاريخ الفحص: 2026-10-17 — عدد الشاشات: 251

| الحالة | العدد |
|---|---|
| ملتزمة بالكامل | 46 |
| مرحّلة جزئياً | 148 |
| غير مرحّلة | 57 |

إجمالي الألوان المكتوبة يدوياً: 1490 Color(0x..) + 4523 Colors.xxx — AppTheme: 2، AccountingTheme: 2295، Energy: 355، GoogleFonts: 1833، AppBar خام: 82، styleFrom: 559

## حسب الوحدة

| الوحدة | الشاشات | ملتزمة | جزئية | غير مرحّلة | ألوان يدوية |
|---|---|---|---|---|---|
| pages | 127 | 21 | 82 | 24 | 3593 |
| ftth | 46 | 6 | 22 | 18 | 1633 |
| sas_agent | 25 | 7 | 18 | 0 | 233 |
| task | 8 | 2 | 2 | 4 | 204 |
| whatsapp | 3 | 0 | 0 | 3 | 180 |
| network_quality | 11 | 1 | 9 | 1 | 115 |
| citizen_portal | 2 | 0 | 0 | 2 | 43 |
| widgets | 3 | 1 | 0 | 2 | 6 |
| permissions | 1 | 0 | 0 | 1 | 6 |
| (root) | 2 | 0 | 0 | 2 | 0 |
| inventory | 23 | 8 | 15 | 0 | 0 |

## كل الشاشات (الأسوأ أولاً)

| # | الملف | الحالة | أسطر | Color(0x) | Colors.x | ثيمات قديمة | AppBar خام | styleFrom | هيكل Sd | نقاط |
|---|---|---|---|---|---|---|---|---|---|---|
| 1 | `pages/accounting/ftth_operators_dashboard_page.dart` | غير مرحّلة | 14326 | 31 | 743 | 229 | 5 | 33 | ✗ | 1938 |
| 2 | `ftth/subscriptions/subscription_details_page.dart` | مرحّلة جزئياً | 12937 | 2 | 374 | 0 | 0 | 21 | ✗ | 840 |
| 3 | `pages/accounting/client_accounts_page.dart` | مرحّلة جزئياً | 3753 | 140 | 15 | 371 | 0 | 4 | ✗ | 708 |
| 4 | `ftth/users/user_details_page.dart` | مرحّلة جزئياً | 5582 | 0 | 221 | 0 | 0 | 17 | ✓ | 493 |
| 5 | `pages/company_settings_page.dart` | مرحّلة جزئياً | 3956 | 20 | 122 | 138 | 2 | 14 | ✓ | 474 |
| 6 | `pages/accounting/ftth_operator_account_page.dart` | غير مرحّلة | 2394 | 36 | 126 | 70 | 1 | 5 | ✗ | 433 |
| 7 | `pages/server_data_page.dart` | مرحّلة جزئياً | 4061 | 68 | 88 | 43 | 0 | 2 | ✓ | 401 |
| 8 | `pages/super_admin/company_details_page.dart` | مرحّلة جزئياً | 3815 | 74 | 72 | 60 | 1 | 12 | ✓ | 395 |
| 9 | `whatsapp/pages/whatsapp_server_settings_page.dart` | غير مرحّلة | 1968 | 6 | 121 | 74 | 1 | 9 | ✗ | 389 |
| 10 | `pages/settings/ftth_sync_settings_page.dart` | مرحّلة جزئياً | 1998 | 0 | 160 | 0 | 0 | 13 | ✓ | 381 |
| 11 | `pages/accounting/journal_entries_page.dart` | مرحّلة جزئياً | 2579 | 5 | 0 | 301 | 0 | 12 | ✓ | 347 |
| 12 | `ftth/subscriptions/subscriptions_page.dart` | مرحّلة جزئياً | 5063 | 2 | 139 | 0 | 1 | 14 | ✗ | 346 |
| 13 | `pages/accounting/compound_journal_entry_page.dart` | مرحّلة جزئياً | 2888 | 25 | 1 | 274 | 0 | 0 | ✓ | 326 |
| 14 | `pages/local_storage_page.dart` | مرحّلة جزئياً | 3910 | 39 | 93 | 0 | 1 | 15 | ✓ | 322 |
| 15 | `pages/super_admin/sadara_portal_page.dart` | مرحّلة جزئياً | 3085 | 31 | 46 | 137 | 0 | 8 | ✓ | 317 |
| 16 | `pages/super_admin/unified_companies_page.dart` | مرحّلة جزئياً | 2869 | 27 | 66 | 73 | 0 | 14 | ✓ | 301 |
| 17 | `pages/accounting/collections_page.dart` | مرحّلة جزئياً | 2527 | 0 | 4 | 229 | 0 | 11 | ✗ | 285 |
| 18 | `pages/super_admin/super_admin_dashboard.dart` | مرحّلة جزئياً | 2775 | 24 | 25 | 143 | 1 | 8 | ✗ | 285 |
| 19 | `pages/super_admin/agents_management_page.dart` | مرحّلة جزئياً | 2832 | 3 | 23 | 177 | 0 | 11 | ✓ | 262 |
| 20 | `task/reports_page.dart` | غير مرحّلة | 2541 | 0 | 115 | 0 | 1 | 0 | ✗ | 256 |
| 21 | `pages/accounting/settlement_reports_page.dart` | غير مرحّلة | 956 | 18 | 69 | 63 | 0 | 1 | ✗ | 255 |
| 22 | `ftth/requests/customer_onboarding_page.dart` | مرحّلة جزئياً | 1107 | 0 | 93 | 0 | 0 | 10 | ✓ | 218 |
| 23 | `ftth/core/home_page.dart` | مرحّلة جزئياً | 5620 | 24 | 67 | 0 | 1 | 3 | ✗ | 213 |
| 24 | `pages/super_admin/permissions_management_v2_page.dart` | مرحّلة جزئياً | 1877 | 59 | 29 | 19 | 0 | 2 | ✓ | 201 |
| 25 | `pages/properties/property_detail_page.dart` | مرحّلة جزئياً | 2143 | 5 | 34 | 75 | 0 | 9 | ✗ | 195 |
| 26 | `pages/accounting/chart_of_accounts_page.dart` | مرحّلة جزئياً | 1571 | 2 | 0 | 170 | 0 | 6 | ✓ | 192 |
| 27 | `pages/admin/organizations_management_page.dart` | غير مرحّلة | 1207 | 3 | 43 | 58 | 2 | 4 | ✗ | 191 |
| 28 | `pages/ftth_advanced_system.dart` | غير مرحّلة | 1903 | 29 | 39 | 0 | 2 | 4 | ✗ | 185 |
| 29 | `ftth/reports/agents_details_page.dart` | مرحّلة جزئياً | 2546 | 3 | 68 | 0 | 1 | 3 | ✓ | 168 |
| 30 | `ftth/reports/profits_page.dart` | مرحّلة جزئياً | 3538 | 20 | 61 | 0 | 0 | 2 | ✓ | 168 |
| 31 | `ftth/transactions/creator_amounts_page.dart` | غير مرحّلة | 1073 | 9 | 56 | 0 | 1 | 0 | ✗ | 152 |
| 32 | `pages/accounting/statistics_page.dart` | مرحّلة جزئياً | 1525 | 5 | 0 | 127 | 0 | 0 | ✗ | 152 |
| 33 | `pages/ftth/fetch_server_data_page.dart` | مرحّلة جزئياً | 2955 | 0 | 70 | 0 | 1 | 1 | ✓ | 152 |
| 34 | `pages/kml_zones_map_page.dart` | مرحّلة جزئياً | 2585 | 29 | 8 | 41 | 0 | 4 | ✗ | 142 |
| 35 | `pages/accounting/cashbox_page.dart` | غير مرحّلة | 899 | 0 | 1 | 98 | 0 | 8 | ✗ | 139 |
| 36 | `pages/accounting/wallet_transactions_page.dart` | مرحّلة جزئياً | 1334 | 10 | 38 | 28 | 0 | 0 | ✗ | 139 |
| 37 | `pages/home_page.dart` | مرحّلة جزئياً | 3481 | 27 | 36 | 0 | 0 | 4 | ✓ | 138 |
| 38 | `pages/accounting/accounting_dashboard_page.dart` | مرحّلة جزئياً | 1443 | 61 | 0 | 13 | 0 | 1 | ✓ | 138 |
| 39 | `pages/super_admin/vps_data_manager_page.dart` | مرحّلة جزئياً | 1278 | 5 | 9 | 86 | 1 | 6 | ✓ | 137 |
| 40 | `pages/hr_reports_page.dart` | مرحّلة جزئياً | 1852 | 0 | 60 | 0 | 0 | 2 | ✓ | 134 |
| 41 | `sas_agent/pages/sas_subscriber_detail_page.dart` | مرحّلة جزئياً | 2600 | 13 | 36 | 0 | 0 | 7 | ✗ | 134 |
| 42 | `pages/accounting/salaries_page.dart` | مرحّلة جزئياً | 1359 | 11 | 0 | 92 | 0 | 6 | ✓ | 132 |
| 43 | `pages/accounting/budget_page.dart` | مرحّلة جزئياً | 1002 | 1 | 0 | 121 | 0 | 2 | ✓ | 129 |
| 44 | `pages/users_page_firebase.dart` | غير مرحّلة | 908 | 1 | 20 | 56 | 1 | 1 | ✗ | 123 |
| 45 | `pages/chat/chat_conversation_page.dart` | مرحّلة جزئياً | 2997 | 1 | 42 | 0 | 2 | 4 | ✗ | 123 |
| 46 | `pages/user_whatsapp_permissions_page.dart` | غير مرحّلة | 567 | 4 | 33 | 21 | 1 | 2 | ✗ | 121 |
| 47 | `task/technician_performance_page.dart` | غير مرحّلة | 742 | 25 | 25 | 0 | 1 | 0 | ✗ | 120 |
| 48 | `network_quality/pages/quality_results_page.dart` | مرحّلة جزئياً | 1443 | 34 | 21 | 0 | 0 | 0 | ✓ | 110 |
| 49 | `pages/vps_tenant_login_page.dart` | غير مرحّلة | 941 | 33 | 6 | 12 | 0 | 1 | ✗ | 108 |
| 50 | `pages/properties/property_qr_batches_page.dart` | مرحّلة جزئياً | 1102 | 0 | 5 | 49 | 2 | 8 | ✗ | 108 |
| 51 | `pages/settings/device_permissions_page.dart` | غير مرحّلة | 756 | 1 | 35 | 0 | 1 | 4 | ✗ | 108 |
| 52 | `ftth/transactions/account_stats_page.dart` | غير مرحّلة | 656 | 0 | 40 | 0 | 1 | 0 | ✗ | 102 |
| 53 | `pages/whatsapp_templates_page.dart` | مرحّلة جزئياً | 1268 | 23 | 0 | 34 | 0 | 6 | ✓ | 98 |
| 54 | `ftth/tickets/tktats_page.dart` | مرحّلة جزئياً | 2293 | 3 | 41 | 0 | 0 | 2 | ✓ | 96 |
| 55 | `ftth/transactions/account_records_page.dart` | مرحّلة جزئياً | 4317 | 28 | 0 | 0 | 1 | 6 | ✗ | 96 |
| 56 | `ftth/auth/login_page.dart` | غير مرحّلة | 895 | 29 | 4 | 0 | 1 | 2 | ✗ | 92 |
| 57 | `pages/search_comparison_page.dart` | غير مرحّلة | 412 | 0 | 33 | 0 | 1 | 0 | ✗ | 90 |
| 58 | `pages/hr/employee_profile_page.dart` | مرحّلة جزئياً | 931 | 21 | 9 | 21 | 0 | 3 | ✓ | 90 |
| 59 | `pages/super_admin/tenant_whatsapp_permissions_page.dart` | غير مرحّلة | 408 | 10 | 15 | 13 | 1 | 2 | ✗ | 89 |
| 60 | `whatsapp/pages/whatsapp_settings_hub_page.dart` | غير مرحّلة | 656 | 23 | 4 | 11 | 0 | 2 | ✗ | 86 |
| 61 | `whatsapp/pages/whatsapp_system_settings_page.dart` | غير مرحّلة | 511 | 4 | 22 | 11 | 1 | 1 | ✗ | 86 |
| 62 | `ftth/tickets/technicians_page.dart` | غير مرحّلة | 454 | 6 | 20 | 0 | 1 | 3 | ✗ | 83 |
| 63 | `ftth/users/users_data_page.dart` | مرحّلة جزئياً | 901 | 0 | 29 | 0 | 0 | 2 | ✗ | 83 |
| 64 | `ftth/users/user_transactions_page.dart` | غير مرحّلة | 576 | 0 | 28 | 0 | 1 | 1 | ✗ | 83 |
| 65 | `pages/login/premium_login_page.dart` | مرحّلة جزئياً | 1836 | 41 | 0 | 0 | 0 | 0 | ✓ | 82 |
| 66 | `ftth/users/user_records_page.dart` | مرحّلة جزئياً | 1307 | 0 | 30 | 0 | 0 | 1 | ✗ | 80 |
| 67 | `pages/accounting/withdrawal_requests_page.dart` | مرحّلة جزئياً | 955 | 12 | 0 | 35 | 0 | 2 | ✗ | 80 |
| 68 | `ftth/core/permissions_page.dart` | غير مرحّلة | 576 | 2 | 22 | 0 | 1 | 3 | ✗ | 79 |
| 69 | `pages/accounting/balance_sheet_page.dart` | مرحّلة جزئياً | 668 | 0 | 4 | 71 | 0 | 0 | ✓ | 79 |
| 70 | `pages/accounting/plan_profits_page.dart` | غير مرحّلة | 533 | 0 | 0 | 59 | 1 | 0 | ✗ | 79 |
| 71 | `ftth/tickets/tickets_login_page.dart` | غير مرحّلة | 545 | 15 | 12 | 0 | 0 | 2 | ✗ | 77 |
| 72 | `citizen_portal/pages/companies_management_page.dart` | غير مرحّلة | 391 | 0 | 24 | 0 | 1 | 2 | ✗ | 76 |
| 73 | `pages/agents_page.dart` | غير مرحّلة | 561 | 0 | 22 | 0 | 1 | 1 | ✗ | 73 |
| 74 | `pages/properties/property_form_page.dart` | مرحّلة جزئياً | 925 | 1 | 9 | 32 | 0 | 2 | ✗ | 73 |
| 75 | `citizen_portal/pages/citizen_portal_dashboard_page.dart` | غير مرحّلة | 341 | 0 | 19 | 0 | 3 | 0 | ✗ | 72 |
| 76 | `pages/modern_home_page.dart` | غير مرحّلة | 899 | 14 | 13 | 0 | 0 | 1 | ✗ | 72 |
| 77 | `task/technician_transactions_page.dart` | غير مرحّلة | 702 | 15 | 0 | 18 | 0 | 3 | ✗ | 72 |
| 78 | `ftth/widgets/notifications_page.dart` | غير مرحّلة | 735 | 9 | 14 | 0 | 1 | 1 | ✗ | 71 |
| 79 | `pages/accounting/aging_report_page.dart` | مرحّلة جزئياً | 746 | 4 | 0 | 48 | 0 | 0 | ✗ | 71 |
| 80 | `ftth/subscriptions/plans_bundles_page.dart` | غير مرحّلة | 619 | 0 | 23 | 0 | 1 | 0 | ✗ | 68 |
| 81 | `pages/enhanced_search_users_page.dart` | غير مرحّلة | 959 | 0 | 17 | 0 | 1 | 2 | ✗ | 68 |
| 82 | `pages/accounting/cash_flow_page.dart` | مرحّلة جزئياً | 668 | 17 | 0 | 34 | 0 | 0 | ✓ | 68 |
| 83 | `pages/accounting/ftth_operator_transactions_page.dart` | مرحّلة جزئياً | 1086 | 0 | 34 | 0 | 0 | 0 | ✓ | 68 |
| 84 | `pages/track_users_map_page.dart` | مرحّلة جزئياً | 1098 | 3 | 20 | 13 | 1 | 1 | ✓ | 67 |
| 85 | `pages/accounting/trial_balance_page.dart` | مرحّلة جزئياً | 601 | 2 | 0 | 63 | 0 | 0 | ✓ | 67 |
| 86 | `pages/accounting/zone_maintenance_fees_page.dart` | مرحّلة جزئياً | 578 | 0 | 0 | 58 | 0 | 3 | ✓ | 67 |
| 87 | `sas_agent/premises/ui/premises_detail_screen.dart` | مرحّلة جزئياً | 815 | 6 | 14 | 0 | 0 | 4 | ✗ | 67 |
| 88 | `pages/offline_router_setup_page.dart` | مرحّلة جزئياً | 1486 | 20 | 0 | 0 | 1 | 7 | ✓ | 66 |
| 89 | `sas_agent/pages/sas_bulk_import_page.dart` | مرحّلة جزئياً | 1279 | 6 | 18 | 0 | 0 | 6 | ✓ | 66 |
| 90 | `pages/enhanced_home_page.dart` | غير مرحّلة | 467 | 0 | 18 | 0 | 1 | 1 | ✗ | 65 |
| 91 | `pages/vps_super_admin_login_page.dart` | غير مرحّلة | 313 | 0 | 18 | 8 | 0 | 1 | ✗ | 64 |
| 92 | `pages/accounting/monthly_comparison_page.dart` | مرحّلة جزئياً | 1026 | 1 | 0 | 47 | 0 | 0 | ✗ | 64 |
| 93 | `pages/properties/location_master_page.dart` | مرحّلة جزئياً | 1073 | 0 | 6 | 25 | 0 | 4 | ✗ | 64 |
| 94 | `task/audit_dashboard_page.dart` | غير مرحّلة | 1978 | 24 | 0 | 0 | 0 | 0 | ✗ | 63 |
| 95 | `pages/accounting/year_comparison_page.dart` | مرحّلة جزئياً | 1158 | 1 | 0 | 45 | 0 | 0 | ✗ | 62 |
| 96 | `pages/accounting/funds_overview_page.dart` | مرحّلة جزئياً | 561 | 0 | 23 | 7 | 0 | 0 | ✓ | 59 |
| 97 | `ftth/transactions/daily_settlement_page.dart` | مرحّلة جزئياً | 1779 | 24 | 0 | 0 | 1 | 1 | ✓ | 58 |
| 98 | `ftth/diagnostic/diagnostic_page.dart` | غير مرحّلة | 1002 | 3 | 14 | 0 | 1 | 1 | ✗ | 57 |
| 99 | `ftth/tickets/tktats_page_beautiful.dart` | غير مرحّلة | 548 | 0 | 17 | 0 | 1 | 1 | ✗ | 57 |
| 100 | `pages/accounting/sas_accounting_page.dart` | مرحّلة جزئياً | 587 | 0 | 0 | 42 | 0 | 0 | ✗ | 57 |
| 101 | `pages/accounting/employee_adjustments_page.dart` | مرحّلة جزئياً | 836 | 0 | 0 | 47 | 0 | 3 | ✓ | 56 |
| 102 | `pages/properties/properties_list_page.dart` | مرحّلة جزئياً | 609 | 1 | 7 | 19 | 0 | 2 | ✗ | 56 |
| 103 | `pages/accounting/ftth_operator_linking_page.dart` | مرحّلة جزئياً | 756 | 0 | 21 | 4 | 0 | 3 | ✓ | 55 |
| 104 | `ftth/reports/export_page.dart` | غير مرحّلة | 1313 | 9 | 4 | 0 | 2 | 1 | ✗ | 54 |
| 105 | `pages/accounting/revenue_page.dart` | مرحّلة جزئياً | 1168 | 0 | 0 | 45 | 0 | 3 | ✓ | 54 |
| 106 | `pages/employee_tracking_report_page.dart` | مرحّلة جزئياً | 1016 | 8 | 17 | 0 | 0 | 1 | ✓ | 53 |
| 107 | `pages/firebase_data_viewer.dart` | غير مرحّلة | 294 | 2 | 10 | 7 | 1 | 0 | ✗ | 53 |
| 108 | `pages/super_admin_login_page.dart` | غير مرحّلة | 266 | 0 | 13 | 7 | 0 | 1 | ✗ | 53 |
| 109 | `pages/accounting/fixed_expenses_page.dart` | مرحّلة جزئياً | 976 | 6 | 12 | 0 | 0 | 5 | ✓ | 53 |
| 110 | `sas_agent/pages/sas_explorer_page.dart` | مرحّلة جزئياً | 1543 | 2 | 12 | 0 | 0 | 3 | ✗ | 52 |
| 111 | `sas_agent/pages/sas_settings_tab.dart` | مرحّلة جزئياً | 901 | 1 | 16 | 0 | 0 | 1 | ✗ | 52 |
| 112 | `pages/settings/company_firebase_settings_page.dart` | غير مرحّلة | 291 | 3 | 9 | 0 | 1 | 1 | ✗ | 51 |
| 113 | `pages/accounting/activation_profitability_page.dart` | مرحّلة جزئياً | 274 | 0 | 2 | 27 | 0 | 1 | ✗ | 49 |
| 114 | `pages/accounting/financial_ratios_page.dart` | مرحّلة جزئياً | 628 | 0 | 0 | 49 | 0 | 0 | ✓ | 49 |
| 115 | `ftth/users/users_dashboard_webview.dart` | غير مرحّلة | 358 | 0 | 10 | 0 | 2 | 1 | ✗ | 48 |
| 116 | `pages/accounting/income_statement_page.dart` | مرحّلة جزئياً | 539 | 6 | 0 | 34 | 0 | 0 | ✓ | 46 |
| 117 | `pages/user_details_page.dart` | مرحّلة جزئياً | 758 | 0 | 5 | 33 | 0 | 0 | ✓ | 43 |
| 118 | `ftth/subscriptions/all_subscriptions_details_page.dart` | غير مرحّلة | 397 | 3 | 7 | 0 | 1 | 0 | ✗ | 42 |
| 119 | `pages/permission_reset_page.dart` | غير مرحّلة | 216 | 0 | 8 | 0 | 1 | 1 | ✗ | 41 |
| 120 | `sas_agent/pages/sas_reminders_page.dart` | مرحّلة جزئياً | 820 | 3 | 13 | 0 | 0 | 3 | ✓ | 41 |
| 121 | `sas_agent/pages/sas_reports_page.dart` | مرحّلة جزئياً | 840 | 3 | 10 | 0 | 0 | 0 | ✗ | 41 |
| 122 | `ftth/transactions/transactions_page.dart` | مرحّلة جزئياً | 4911 | 4 | 0 | 0 | 0 | 5 | ✗ | 40 |
| 123 | `pages/accounting/expenses_page.dart` | مرحّلة جزئياً | 826 | 0 | 0 | 31 | 0 | 3 | ✓ | 40 |
| 124 | `ftth/subscriptions/expiring_soon_page.dart` | مرحّلة جزئياً | 2540 | 0 | 18 | 0 | 0 | 1 | ✓ | 39 |
| 125 | `widgets/platform_webview.dart` | غير مرحّلة | 292 | 0 | 6 | 0 | 1 | 2 | ✗ | 38 |
| 126 | `sas_agent/pages/sas_bulk_message_page.dart` | مرحّلة جزئياً | 753 | 3 | 14 | 0 | 0 | 1 | ✓ | 37 |
| 127 | `ftth/transactions/caounter_details_page.dart` | مرحّلة جزئياً | 2647 | 0 | 0 | 0 | 1 | 4 | ✗ | 36 |
| 128 | `ftth/transactions/creator_transactions_detail_page.dart` | مرحّلة جزئياً | 2384 | 6 | 0 | 0 | 1 | 0 | ✗ | 36 |
| 129 | `task/home_page_tasks.dart` | مرحّلة جزئياً | 3444 | 0 | 0 | 0 | 0 | 7 | ✗ | 36 |
| 130 | `pages/analysis_page.dart` | مرحّلة جزئياً | 669 | 2 | 13 | 0 | 0 | 1 | ✓ | 35 |
| 131 | `permissions/permission_gate.dart` | غير مرحّلة | 232 | 3 | 3 | 0 | 1 | 1 | ✗ | 35 |
| 132 | `sas_agent/premises/ui/premises_form_screen.dart` | مرحّلة جزئياً | 396 | 3 | 4 | 0 | 0 | 2 | ✗ | 35 |
| 133 | `sas_agent/whatsapp/ui/wa_settings_screen.dart` | مرحّلة جزئياً | 505 | 3 | 10 | 0 | 0 | 3 | ✓ | 35 |
| 134 | `ftth/tickets/tktat_raw_page.dart` | غير مرحّلة | 176 | 3 | 3 | 0 | 1 | 0 | ✗ | 34 |
| 135 | `pages/users_page.dart` | غير مرحّلة | 382 | 0 | 6 | 0 | 1 | 0 | ✗ | 34 |
| 136 | `ftth/whatsapp/whatsapp_floating_window.dart` | غير مرحّلة | 413 | 2 | 4 | 0 | 1 | 0 | ✗ | 32 |
| 137 | `network_quality/pages/optical_webview_page.dart` | غير مرحّلة | 486 | 3 | 1 | 0 | 1 | 1 | ✗ | 31 |
| 138 | `pages/whatsapp_bulk_sender_page.dart` | مرحّلة جزئياً | 1049 | 0 | 0 | 0 | 0 | 5 | ✓ | 31 |
| 139 | `pages/properties/property_qr_scanner.dart` | مرحّلة جزئياً | 240 | 0 | 0 | 5 | 1 | 2 | ✗ | 31 |
| 140 | `sas_agent/pages/sas_test_message_page.dart` | مرحّلة جزئياً | 728 | 10 | 4 | 0 | 0 | 1 | ✓ | 31 |
| 141 | `network_quality/pages/advanced_tools_page.dart` | مرحّلة جزئياً | 248 | 15 | 0 | 0 | 0 | 0 | ✓ | 30 |
| 142 | `sas_agent/pages/sas_admin_agents_page.dart` | مرحّلة جزئياً | 473 | 2 | 13 | 0 | 0 | 0 | ✓ | 30 |
| 143 | `ftth/users/users_page.dart` | مرحّلة جزئياً | 1680 | 0 | 0 | 0 | 0 | 4 | ✗ | 29 |
| 144 | `network_quality/pages/wifi_channel_analyzer_page.dart` | مرحّلة جزئياً | 408 | 14 | 0 | 0 | 0 | 0 | ✓ | 28 |
| 145 | `pages/dashboard_page.dart` | غير مرحّلة | 63 | 0 | 2 | 0 | 1 | 1 | ✗ | 27 |
| 146 | `pages/accounting/salary_policy_page.dart` | مرحّلة جزئياً | 491 | 0 | 0 | 21 | 0 | 2 | ✓ | 27 |
| 147 | `ftth/reports/data_page.dart` | غير مرحّلة | 122 | 3 | 0 | 0 | 1 | 0 | ✗ | 26 |
| 148 | `ftth/tickets/TKTAT.dart` | غير مرحّلة | 128 | 0 | 2 | 0 | 1 | 0 | ✗ | 26 |
| 149 | `ftth/subscriptions/connections_list_page.dart` | مرحّلة جزئياً | 2198 | 0 | 0 | 0 | 0 | 7 | ✓ | 25 |
| 150 | `sas_agent/whatsapp/ui/wa_templates_screen.dart` | مرحّلة جزئياً | 395 | 2 | 3 | 0 | 0 | 0 | ✗ | 25 |
| 151 | `pages/receipt_template_editor_page.dart` | مرحّلة جزئياً | 1504 | 0 | 4 | 0 | 0 | 0 | ✗ | 23 |
| 152 | `ftth/reports/zones_page.dart` | مرحّلة جزئياً | 1373 | 1 | 0 | 0 | 3 | 0 | ✓ | 21 |
| 153 | `pages/company_diagnostics_page.dart` | مرحّلة جزئياً | 1359 | 0 | 1 | 2 | 0 | 5 | ✓ | 21 |
| 154 | `pages/salary_management_page.dart` | مرحّلة جزئياً | 1391 | 0 | 0 | 0 | 0 | 7 | ✓ | 21 |
| 155 | `pages/citizen_portal/citizen_portal_dashboard.dart` | مرحّلة جزئياً | 391 | 0 | 8 | 0 | 1 | 0 | ✓ | 21 |
| 156 | `test_pop.dart` | غير مرحّلة | 34 | 0 | 0 | 0 | 1 | 0 | ✗ | 20 |
| 157 | `pages/whatsapp_chat_page.dart` | مرحّلة جزئياً | 1050 | 0 | 0 | 0 | 1 | 0 | ✗ | 20 |
| 158 | `pages/leave_management_page.dart` | مرحّلة جزئياً | 864 | 0 | 8 | 0 | 0 | 1 | ✓ | 19 |
| 159 | `sas_agent/premises/ui/premises_list_screen.dart` | مرحّلة جزئياً | 370 | 2 | 6 | 0 | 0 | 1 | ✓ | 19 |
| 160 | `network_quality/pages/history_trend_page.dart` | مرحّلة جزئياً | 492 | 8 | 1 | 0 | 0 | 0 | ✓ | 18 |
| 161 | `task/add_task_api_dialog.dart` | مرحّلة جزئياً | 1673 | 0 | 0 | 0 | 0 | 1 | ✗ | 18 |
| 162 | `main.dart` | غير مرحّلة | 482 | 0 | 0 | 2 | 0 | 0 | ✗ | 17 |
| 163 | `pages/whatsapp_business_config_page.dart` | مرحّلة جزئياً | 1205 | 0 | 0 | 0 | 0 | 5 | ✓ | 17 |
| 164 | `network_quality/pages/live_monitor_page.dart` | مرحّلة جزئياً | 376 | 7 | 1 | 0 | 0 | 0 | ✓ | 16 |
| 165 | `inventory/pages/materials_page.dart` | مرحّلة جزئياً | 827 | 0 | 0 | 0 | 0 | 5 | ✓ | 15 |
| 166 | `task/task_list_screen.dart` | ملتزمة بالكامل | 401 | 0 | 0 | 0 | 0 | 0 | ✗ | 15 |
| 167 | `widgets/auth_guard.dart` | غير مرحّلة | 109 | 0 | 0 | 0 | 0 | 0 | ✗ | 15 |
| 168 | `pages/accounting/period_closing_page.dart` | مرحّلة جزئياً | 376 | 0 | 0 | 8 | 0 | 1 | ✓ | 11 |
| 169 | `pages/charts_page.dart` | مرحّلة جزئياً | 201 | 0 | 5 | 0 | 0 | 0 | ✓ | 10 |
| 170 | `pages/local_subscriber_details_page.dart` | مرحّلة جزئياً | 856 | 0 | 5 | 0 | 0 | 0 | ✓ | 10 |
| 171 | `inventory/pages/returns_page.dart` | مرحّلة جزئياً | 415 | 0 | 0 | 0 | 0 | 3 | ✓ | 9 |
| 172 | `pages/deductions_bonuses_page.dart` | مرحّلة جزئياً | 821 | 0 | 0 | 0 | 0 | 3 | ✓ | 9 |
| 173 | `pages/whatsapp_excel_sender_page.dart` | مرحّلة جزئياً | 456 | 0 | 0 | 0 | 0 | 3 | ✓ | 9 |
| 174 | `network_quality/pages/dns_benchmark_page.dart` | مرحّلة جزئياً | 321 | 4 | 0 | 0 | 0 | 0 | ✓ | 8 |
| 175 | `pages/search_users_page.dart` | ملتزمة بالكامل | 1274 | 0 | 0 | 0 | 0 | 0 | ✓ | 8 |
| 176 | `pages/diagnostics/system_diagnostics_page.dart` | مرحّلة جزئياً | 851 | 0 | 0 | 0 | 0 | 2 | ✓ | 8 |
| 177 | `pages/whatsapp_batch_reports_page.dart` | مرحّلة جزئياً | 555 | 0 | 2 | 0 | 0 | 1 | ✓ | 7 |
| 178 | `ftth/tickets/create_ticket_page.dart` | مرحّلة جزئياً | 793 | 0 | 0 | 0 | 0 | 2 | ✓ | 6 |
| 179 | `inventory/pages/dispensing_page.dart` | مرحّلة جزئياً | 742 | 0 | 0 | 0 | 0 | 2 | ✓ | 6 |
| 180 | `inventory/pages/invoices_page.dart` | مرحّلة جزئياً | 748 | 0 | 0 | 0 | 0 | 2 | ✓ | 6 |
| 181 | `inventory/pages/purchases_page.dart` | مرحّلة جزئياً | 648 | 0 | 0 | 0 | 0 | 2 | ✓ | 6 |
| 182 | `inventory/pages/stock_levels_page.dart` | مرحّلة جزئياً | 417 | 0 | 0 | 0 | 0 | 2 | ✓ | 6 |
| 183 | `inventory/pages/suppliers_page.dart` | مرحّلة جزئياً | 387 | 0 | 0 | 0 | 0 | 2 | ✓ | 6 |
| 184 | `inventory/pages/warehouses_page.dart` | مرحّلة جزئياً | 346 | 0 | 0 | 0 | 0 | 2 | ✓ | 6 |
| 185 | `network_quality/network_quality_home_page.dart` | مرحّلة جزئياً | 169 | 3 | 0 | 0 | 0 | 0 | ✓ | 6 |
| 186 | `pages/account/account_info_page.dart` | مرحّلة جزئياً | 741 | 3 | 0 | 0 | 0 | 0 | ✓ | 6 |
| 187 | `pages/iptv/iptv_subscribers_page.dart` | مرحّلة جزئياً | 1128 | 0 | 0 | 0 | 0 | 2 | ✓ | 6 |
| 188 | `sas_agent/pages/sas_regions_page.dart` | مرحّلة جزئياً | 482 | 0 | 0 | 0 | 0 | 2 | ✓ | 6 |
| 189 | `pages/work_schedules_page.dart` | مرحّلة جزئياً | 471 | 0 | 1 | 0 | 0 | 1 | ✓ | 5 |
| 190 | `pages/super_admin/add_company_page.dart` | مرحّلة جزئياً | 540 | 0 | 1 | 0 | 0 | 1 | ✓ | 5 |
| 191 | `sas_agent/sas_agent_page.dart` | مرحّلة جزئياً | 751 | 0 | 0 | 0 | 1 | 0 | ✓ | 5 |
| 192 | `ftth/users/quick_search_users_page.dart` | مرحّلة جزئياً | 1295 | 1 | 1 | 0 | 0 | 0 | ✓ | 4 |
| 193 | `network_quality/pages/quality_scan_page.dart` | مرحّلة جزئياً | 441 | 2 | 0 | 0 | 0 | 0 | ✓ | 4 |
| 194 | `pages/client_setup_page.dart` | مرحّلة جزئياً | 376 | 0 | 2 | 0 | 0 | 0 | ✓ | 4 |
| 195 | `ftth/reports/audit_log_page.dart` | مرحّلة جزئياً | 1042 | 0 | 0 | 0 | 0 | 1 | ✓ | 3 |
| 196 | `inventory/pages/customers_page.dart` | مرحّلة جزئياً | 515 | 0 | 0 | 0 | 0 | 1 | ✓ | 3 |
| 197 | `inventory/pages/dispensing_form_page.dart` | مرحّلة جزئياً | 497 | 0 | 0 | 0 | 0 | 1 | ✓ | 3 |
| 198 | `inventory/pages/invoice_details_page.dart` | مرحّلة جزئياً | 538 | 0 | 0 | 0 | 0 | 1 | ✓ | 3 |
| 199 | `inventory/pages/invoice_form_page.dart` | مرحّلة جزئياً | 1029 | 0 | 0 | 0 | 0 | 1 | ✓ | 3 |
| 200 | `inventory/pages/purchase_form_page.dart` | مرحّلة جزئياً | 627 | 0 | 0 | 0 | 0 | 1 | ✓ | 3 |
| 201 | `inventory/pages/sales_page.dart` | مرحّلة جزئياً | 539 | 0 | 0 | 0 | 0 | 1 | ✓ | 3 |
| 202 | `inventory/pages/vouchers_page.dart` | مرحّلة جزئياً | 331 | 0 | 0 | 0 | 0 | 1 | ✓ | 3 |
| 203 | `pages/citizen_portal/citizen_details_page.dart` | مرحّلة جزئياً | 777 | 0 | 0 | 0 | 0 | 1 | ✓ | 3 |
| 204 | `sas_agent/widgets/sas_citizen_statement.dart` | مرحّلة جزئياً | 519 | 0 | 0 | 0 | 0 | 1 | ✓ | 3 |
| 205 | `network_quality/pages/device_detail_page.dart` | مرحّلة جزئياً | 486 | 0 | 1 | 0 | 0 | 0 | ✓ | 2 |
| 206 | `sas_agent/pages/sas_profits_page.dart` | مرحّلة جزئياً | 341 | 1 | 0 | 0 | 0 | 0 | ✓ | 2 |
| 207 | `pages/diagnostics/permissions_diagnostics_page.dart` | مرحّلة جزئياً | 898 | 0 | 0 | 1 | 0 | 0 | ✓ | 1 |
| 208 | `ftth/requests/customer_hub_page.dart` | ملتزمة بالكامل | 53 | 0 | 0 | 0 | 0 | 0 | ✓ | 0 |
| 209 | `ftth/tasks/customer_search_connect_page.dart` | ملتزمة بالكامل | 682 | 0 | 0 | 0 | 0 | 0 | ✓ | 0 |
| 210 | `ftth/tasks/ftth_connect_form.dart` | ملتزمة بالكامل | 610 | 0 | 0 | 0 | 0 | 0 | ✓ | 0 |
| 211 | `ftth/tasks/ftth_tasks_page.dart` | ملتزمة بالكامل | 474 | 0 | 0 | 0 | 0 | 0 | ✓ | 0 |
| 212 | `ftth/tickets/customer_tickets_page.dart` | ملتزمة بالكامل | 314 | 0 | 0 | 0 | 0 | 0 | ✓ | 0 |
| 213 | `ftth/tickets/tktat_details_page.dart` | ملتزمة بالكامل | 1236 | 0 | 0 | 0 | 0 | 0 | ✓ | 0 |
| 214 | `inventory/inventory_page.dart` | ملتزمة بالكامل | 451 | 0 | 0 | 0 | 0 | 0 | ✓ | 0 |
| 215 | `inventory/pages/customer_details_page.dart` | ملتزمة بالكامل | 590 | 0 | 0 | 0 | 0 | 0 | ✓ | 0 |
| 216 | `inventory/pages/customer_form_page.dart` | ملتزمة بالكامل | 365 | 0 | 0 | 0 | 0 | 0 | ✓ | 0 |
| 217 | `inventory/pages/inventory_reports_page.dart` | ملتزمة بالكامل | 497 | 0 | 0 | 0 | 0 | 0 | ✓ | 0 |
| 218 | `inventory/pages/movements_page.dart` | ملتزمة بالكامل | 479 | 0 | 0 | 0 | 0 | 0 | ✓ | 0 |
| 219 | `inventory/pages/return_form_page.dart` | ملتزمة بالكامل | 543 | 0 | 0 | 0 | 0 | 0 | ✓ | 0 |
| 220 | `inventory/pages/sale_form_page.dart` | ملتزمة بالكامل | 630 | 0 | 0 | 0 | 0 | 0 | ✓ | 0 |
| 221 | `inventory/pages/voucher_form_page.dart` | ملتزمة بالكامل | 394 | 0 | 0 | 0 | 0 | 0 | ✓ | 0 |
| 222 | `network_quality/pages/router_wifi_edit_page.dart` | ملتزمة بالكامل | 517 | 0 | 0 | 0 | 0 | 0 | ✓ | 0 |
| 223 | `pages/aria_page.dart` | ملتزمة بالكامل | 174 | 0 | 0 | 0 | 0 | 0 | ✓ | 0 |
| 224 | `pages/attendance_page.dart` | ملتزمة بالكامل | 798 | 0 | 0 | 0 | 0 | 0 | ✓ | 0 |
| 225 | `pages/google_drive_files_page.dart` | ملتزمة بالكامل | 235 | 0 | 0 | 0 | 0 | 0 | ✓ | 0 |
| 226 | `pages/hr_hub_page.dart` | ملتزمة بالكامل | 241 | 0 | 0 | 0 | 0 | 0 | ✓ | 0 |
| 227 | `pages/my_dashboard_page.dart` | ملتزمة بالكامل | 3177 | 0 | 0 | 0 | 0 | 0 | ✓ | 0 |
| 228 | `pages/printer_settings_page.dart` | ملتزمة بالكامل | 226 | 0 | 0 | 0 | 0 | 0 | ✓ | 0 |
| 229 | `pages/reminder_reports_page.dart` | ملتزمة بالكامل | 179 | 0 | 0 | 0 | 0 | 0 | ✓ | 0 |
| 230 | `pages/settings_page.dart` | ملتزمة بالكامل | 239 | 0 | 0 | 0 | 0 | 0 | ✓ | 0 |
| 231 | `pages/settings_text_scale_page.dart` | ملتزمة بالكامل | 146 | 0 | 0 | 0 | 0 | 0 | ✓ | 0 |
| 232 | `pages/statistics_page.dart` | ملتزمة بالكامل | 667 | 0 | 0 | 0 | 0 | 0 | ✓ | 0 |
| 233 | `pages/users_page_vps.dart` | ملتزمة بالكامل | 1961 | 0 | 0 | 0 | 0 | 0 | ✓ | 0 |
| 234 | `pages/whatsapp_conversations_page.dart` | ملتزمة بالكامل | 725 | 0 | 0 | 0 | 0 | 0 | ✓ | 0 |
| 235 | `pages/accounting/audit_trail_page.dart` | ملتزمة بالكامل | 435 | 0 | 0 | 0 | 0 | 0 | ✓ | 0 |
| 236 | `pages/accounting/hr_reports_page.dart` | ملتزمة بالكامل | 856 | 0 | 0 | 0 | 0 | 0 | ✓ | 0 |
| 237 | `pages/accounting/system_audit_page.dart` | ملتزمة بالكامل | 613 | 0 | 0 | 0 | 0 | 0 | ✓ | 0 |
| 238 | `pages/announcements/announcements_page.dart` | ملتزمة بالكامل | 932 | 0 | 0 | 0 | 0 | 0 | ✓ | 0 |
| 239 | `pages/chat/chat_rooms_page.dart` | ملتزمة بالكامل | 1464 | 0 | 0 | 0 | 0 | 0 | ✓ | 0 |
| 240 | `pages/ftth/ftth_company_page.dart` | ملتزمة بالكامل | 385 | 0 | 0 | 0 | 0 | 0 | ✓ | 0 |
| 241 | `pages/super_admin/edit_company_page.dart` | ملتزمة بالكامل | 571 | 0 | 0 | 0 | 0 | 0 | ✓ | 0 |
| 242 | `pages/super_admin/tenant_features_page.dart` | ملتزمة بالكامل | 363 | 0 | 0 | 0 | 0 | 0 | ✓ | 0 |
| 243 | `sas_agent/pages/sas_debtors_page.dart` | ملتزمة بالكامل | 260 | 0 | 0 | 0 | 0 | 0 | ✓ | 0 |
| 244 | `sas_agent/pages/sas_license_page.dart` | ملتزمة بالكامل | 159 | 0 | 0 | 0 | 0 | 0 | ✓ | 0 |
| 245 | `sas_agent/pages/sas_package_prices_page.dart` | ملتزمة بالكامل | 378 | 0 | 0 | 0 | 0 | 0 | ✓ | 0 |
| 246 | `sas_agent/pages/sas_reports_tab.dart` | ملتزمة بالكامل | 268 | 0 | 0 | 0 | 0 | 0 | ✓ | 0 |
| 247 | `sas_agent/pages/sas_subscriber_form_page.dart` | ملتزمة بالكامل | 477 | 0 | 0 | 0 | 0 | 0 | ✓ | 0 |
| 248 | `sas_agent/pages/sas_ticket_detail_page.dart` | ملتزمة بالكامل | 558 | 0 | 0 | 0 | 0 | 0 | ✓ | 0 |
| 249 | `sas_agent/pages/sas_transactions_page.dart` | ملتزمة بالكامل | 376 | 0 | 0 | 0 | 0 | 0 | ✓ | 0 |
| 250 | `task/follow_up_page.dart` | ملتزمة بالكامل | 1026 | 0 | 0 | 0 | 0 | 0 | ✓ | 0 |
| 251 | `widgets/permissions_gate.dart` | ملتزمة بالكامل | 83 | 0 | 0 | 0 | 0 | 0 | ✓ | 0 |

**النقاط** = Color×2 + Colors×2 + ثيمات قديمة + AppBar خام×5 + Card خام×2 + styleFrom×3 + 15 إن لم يُلفّ بـ SdTheme/SdPage/SdNavShell.
