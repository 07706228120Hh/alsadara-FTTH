# تقرير التزام الشاشات بالثيم الموحّد

تاريخ الفحص: 2026-10-17 — عدد الشاشات: 251

| الحالة | العدد |
|---|---|
| ملتزمة بالكامل | 76 |
| مرحّلة جزئياً | 173 |
| غير مرحّلة | 2 |

إجمالي الألوان المكتوبة يدوياً: 222 Color(0x..) + 421 Colors.xxx — AppTheme: 2، AccountingTheme: 0، Energy: 0، GoogleFonts: 10، AppBar خام: 21، styleFrom: 559

## حسب الوحدة

| الوحدة | الشاشات | ملتزمة | جزئية | غير مرحّلة | ألوان يدوية |
|---|---|---|---|---|---|
| pages | 127 | 37 | 90 | 0 | 407 |
| ftth | 46 | 12 | 34 | 0 | 178 |
| network_quality | 11 | 2 | 9 | 0 | 30 |
| task | 8 | 3 | 5 | 0 | 16 |
| whatsapp | 3 | 0 | 3 | 0 | 9 |
| permissions | 1 | 0 | 1 | 0 | 2 |
| sas_agent | 25 | 11 | 14 | 0 | 1 |
| citizen_portal | 2 | 1 | 1 | 0 | 0 |
| widgets | 3 | 1 | 1 | 1 | 0 |
| (root) | 2 | 1 | 0 | 1 | 0 |
| inventory | 23 | 8 | 15 | 0 | 0 |

## كل الشاشات (الأسوأ أولاً)

| # | الملف | الحالة | أسطر | Color(0x) | Colors.x | ثيمات قديمة | AppBar خام | styleFrom | هيكل Sd | نقاط |
|---|---|---|---|---|---|---|---|---|---|---|
| 1 | `pages/accounting/ftth_operators_dashboard_page.dart` | مرحّلة جزئياً | 14356 | 2 | 191 | 0 | 1 | 33 | ✗ | 527 |
| 2 | `ftth/subscriptions/subscription_details_page.dart` | مرحّلة جزئياً | 12937 | 0 | 87 | 0 | 0 | 21 | ✗ | 262 |
| 3 | `pages/accounting/ftth_operator_account_page.dart` | مرحّلة جزئياً | 2387 | 2 | 22 | 0 | 0 | 5 | ✗ | 82 |
| 4 | `pages/ftth_advanced_system.dart` | مرحّلة جزئياً | 1876 | 2 | 19 | 0 | 0 | 4 | ✗ | 81 |
| 5 | `ftth/core/home_page.dart` | مرحّلة جزئياً | 5615 | 4 | 20 | 0 | 0 | 3 | ✗ | 74 |
| 6 | `pages/super_admin/company_details_page.dart` | مرحّلة جزئياً | 3815 | 11 | 0 | 0 | 1 | 12 | ✓ | 65 |
| 7 | `ftth/subscriptions/subscriptions_page.dart` | مرحّلة جزئياً | 5063 | 0 | 0 | 0 | 1 | 14 | ✗ | 64 |
| 8 | `pages/super_admin/unified_companies_page.dart` | مرحّلة جزئياً | 2869 | 10 | 0 | 0 | 0 | 14 | ✓ | 62 |
| 9 | `pages/settings/ftth_sync_settings_page.dart` | مرحّلة جزئياً | 1998 | 0 | 0 | 0 | 0 | 13 | ✓ | 61 |
| 10 | `pages/local_storage_page.dart` | مرحّلة جزئياً | 3910 | 0 | 0 | 0 | 1 | 15 | ✓ | 58 |
| 11 | `pages/super_admin/super_admin_dashboard.dart` | مرحّلة جزئياً | 2776 | 9 | 0 | 0 | 0 | 8 | ✗ | 57 |
| 12 | `pages/login/premium_login_page.dart` | مرحّلة جزئياً | 1868 | 28 | 0 | 0 | 0 | 0 | ✓ | 56 |
| 13 | `whatsapp/pages/whatsapp_server_settings_page.dart` | مرحّلة جزئياً | 1975 | 0 | 0 | 0 | 0 | 9 | ✗ | 56 |
| 14 | `ftth/transactions/account_stats_page.dart` | مرحّلة جزئياً | 652 | 0 | 18 | 0 | 0 | 0 | ✗ | 53 |
| 15 | `pages/company_settings_page.dart` | مرحّلة جزئياً | 3994 | 3 | 0 | 0 | 1 | 14 | ✓ | 53 |
| 16 | `ftth/users/user_details_page.dart` | مرحّلة جزئياً | 5582 | 0 | 0 | 0 | 0 | 17 | ✓ | 51 |
| 17 | `pages/accounting/collections_page.dart` | مرحّلة جزئياً | 2539 | 0 | 0 | 0 | 0 | 11 | ✗ | 48 |
| 18 | `ftth/transactions/account_records_page.dart` | مرحّلة جزئياً | 4310 | 6 | 0 | 0 | 0 | 6 | ✗ | 47 |
| 19 | `pages/kml_zones_map_page.dart` | مرحّلة جزئياً | 2608 | 10 | 0 | 0 | 0 | 4 | ✗ | 47 |
| 20 | `pages/server_data_page.dart` | مرحّلة جزئياً | 4091 | 0 | 0 | 0 | 0 | 2 | ✓ | 46 |
| 21 | `ftth/transactions/creator_amounts_page.dart` | مرحّلة جزئياً | 1074 | 0 | 11 | 0 | 1 | 0 | ✗ | 44 |
| 22 | `pages/accounting/funds_overview_page.dart` | مرحّلة جزئياً | 567 | 0 | 19 | 0 | 0 | 0 | ✓ | 44 |
| 23 | `pages/properties/property_detail_page.dart` | مرحّلة جزئياً | 2180 | 0 | 0 | 0 | 0 | 9 | ✗ | 42 |
| 24 | `pages/properties/property_qr_batches_page.dart` | مرحّلة جزئياً | 1104 | 0 | 0 | 2 | 0 | 8 | ✗ | 41 |
| 25 | `ftth/transactions/transactions_page.dart` | مرحّلة جزئياً | 4911 | 4 | 0 | 0 | 0 | 5 | ✗ | 40 |
| 26 | `pages/accounting/cashbox_page.dart` | مرحّلة جزئياً | 902 | 0 | 0 | 0 | 0 | 8 | ✗ | 39 |
| 27 | `pages/chat/chat_conversation_page.dart` | مرحّلة جزئياً | 2997 | 1 | 0 | 0 | 2 | 4 | ✗ | 39 |
| 28 | `task/audit_dashboard_page.dart` | مرحّلة جزئياً | 1979 | 12 | 0 | 0 | 0 | 0 | ✗ | 39 |
| 29 | `sas_agent/pages/sas_subscriber_detail_page.dart` | مرحّلة جزئياً | 2600 | 1 | 0 | 0 | 0 | 7 | ✗ | 38 |
| 30 | `whatsapp/pages/whatsapp_settings_hub_page.dart` | مرحّلة جزئياً | 667 | 8 | 0 | 0 | 0 | 2 | ✗ | 37 |
| 31 | `ftth/auth/login_page.dart` | مرحّلة جزئياً | 896 | 5 | 0 | 0 | 1 | 2 | ✗ | 36 |
| 32 | `pages/accounting/journal_entries_page.dart` | مرحّلة جزئياً | 2608 | 0 | 0 | 0 | 0 | 12 | ✓ | 36 |
| 33 | `task/home_page_tasks.dart` | مرحّلة جزئياً | 3444 | 0 | 0 | 0 | 0 | 7 | ✗ | 36 |
| 34 | `pages/accounting/client_accounts_page.dart` | مرحّلة جزئياً | 3791 | 4 | 0 | 0 | 0 | 4 | ✗ | 35 |
| 35 | `ftth/users/user_records_page.dart` | مرحّلة جزئياً | 1307 | 0 | 7 | 0 | 0 | 1 | ✗ | 34 |
| 36 | `pages/super_admin/permissions_management_v2_page.dart` | مرحّلة جزئياً | 1889 | 1 | 13 | 0 | 0 | 2 | ✓ | 34 |
| 37 | `ftth/reports/export_page.dart` | مرحّلة جزئياً | 1296 | 5 | 0 | 0 | 1 | 1 | ✗ | 33 |
| 38 | `pages/super_admin/agents_management_page.dart` | مرحّلة جزئياً | 2832 | 0 | 0 | 0 | 0 | 11 | ✓ | 33 |
| 39 | `ftth/requests/customer_onboarding_page.dart` | مرحّلة جزئياً | 1107 | 0 | 0 | 0 | 0 | 10 | ✓ | 32 |
| 40 | `ftth/tickets/technicians_page.dart` | مرحّلة جزئياً | 455 | 0 | 0 | 0 | 1 | 3 | ✗ | 31 |
| 41 | `ftth/transactions/caounter_details_page.dart` | مرحّلة جزئياً | 2642 | 0 | 0 | 0 | 0 | 4 | ✗ | 31 |
| 42 | `pages/whatsapp_bulk_sender_page.dart` | مرحّلة جزئياً | 1049 | 0 | 0 | 0 | 0 | 5 | ✓ | 31 |
| 43 | `pages/admin/organizations_management_page.dart` | مرحّلة جزئياً | 1188 | 0 | 0 | 0 | 0 | 4 | ✗ | 31 |
| 44 | `pages/settings/device_permissions_page.dart` | مرحّلة جزئياً | 748 | 0 | 0 | 0 | 0 | 4 | ✗ | 31 |
| 45 | `pages/home_page.dart` | مرحّلة جزئياً | 3481 | 7 | 2 | 0 | 0 | 4 | ✓ | 30 |
| 46 | `pages/whatsapp_templates_page.dart` | مرحّلة جزئياً | 1282 | 3 | 0 | 6 | 0 | 6 | ✓ | 30 |
| 47 | `pages/super_admin/tenant_whatsapp_permissions_page.dart` | مرحّلة جزئياً | 417 | 2 | 0 | 0 | 1 | 2 | ✗ | 30 |
| 48 | `ftth/users/users_page.dart` | مرحّلة جزئياً | 1680 | 0 | 0 | 0 | 0 | 4 | ✗ | 29 |
| 49 | `pages/enhanced_search_users_page.dart` | مرحّلة جزئياً | 956 | 0 | 0 | 0 | 0 | 2 | ✗ | 29 |
| 50 | `pages/super_admin/sadara_portal_page.dart` | مرحّلة جزئياً | 3084 | 1 | 0 | 0 | 0 | 8 | ✓ | 28 |
| 51 | `task/technician_transactions_page.dart` | مرحّلة جزئياً | 711 | 2 | 0 | 0 | 0 | 3 | ✗ | 28 |
| 52 | `pages/properties/location_master_page.dart` | مرحّلة جزئياً | 1075 | 0 | 0 | 0 | 0 | 4 | ✗ | 27 |
| 53 | `sas_agent/premises/ui/premises_detail_screen.dart` | مرحّلة جزئياً | 815 | 0 | 0 | 0 | 0 | 4 | ✗ | 27 |
| 54 | `ftth/core/permissions_page.dart` | مرحّلة جزئياً | 563 | 0 | 0 | 0 | 0 | 3 | ✗ | 26 |
| 55 | `pages/user_whatsapp_permissions_page.dart` | مرحّلة جزئياً | 583 | 0 | 0 | 0 | 1 | 2 | ✗ | 26 |
| 56 | `ftth/subscriptions/connections_list_page.dart` | مرحّلة جزئياً | 2198 | 0 | 0 | 0 | 0 | 7 | ✓ | 25 |
| 57 | `ftth/users/users_data_page.dart` | مرحّلة جزئياً | 901 | 0 | 0 | 0 | 0 | 2 | ✗ | 25 |
| 58 | `pages/users_page_firebase.dart` | مرحّلة جزئياً | 913 | 0 | 0 | 0 | 1 | 1 | ✗ | 25 |
| 59 | `pages/super_admin/vps_data_manager_page.dart` | مرحّلة جزئياً | 1278 | 1 | 0 | 0 | 1 | 6 | ✓ | 25 |
| 60 | `ftth/transactions/creator_transactions_detail_page.dart` | مرحّلة جزئياً | 2384 | 0 | 0 | 0 | 1 | 0 | ✗ | 24 |
| 61 | `pages/agents_page.dart` | مرحّلة جزئياً | 538 | 0 | 0 | 0 | 0 | 1 | ✗ | 24 |
| 62 | `pages/enhanced_home_page.dart` | مرحّلة جزئياً | 464 | 0 | 0 | 0 | 0 | 1 | ✗ | 24 |
| 63 | `pages/accounting/settlement_reports_page.dart` | مرحّلة جزئياً | 956 | 3 | 0 | 0 | 0 | 1 | ✗ | 24 |
| 64 | `sas_agent/pages/sas_explorer_page.dart` | مرحّلة جزئياً | 1543 | 0 | 0 | 0 | 0 | 3 | ✗ | 24 |
| 65 | `citizen_portal/pages/companies_management_page.dart` | مرحّلة جزئياً | 389 | 0 | 0 | 0 | 0 | 2 | ✗ | 23 |
| 66 | `ftth/tickets/tickets_login_page.dart` | مرحّلة جزئياً | 546 | 0 | 0 | 0 | 0 | 2 | ✗ | 23 |
| 67 | `ftth/tickets/tktats_page_beautiful.dart` | مرحّلة جزئياً | 549 | 0 | 0 | 0 | 1 | 1 | ✗ | 23 |
| 68 | `ftth/users/users_dashboard_webview.dart` | مرحّلة جزئياً | 356 | 0 | 0 | 0 | 1 | 1 | ✗ | 23 |
| 69 | `ftth/whatsapp/whatsapp_floating_window.dart` | مرحّلة جزئياً | 408 | 0 | 4 | 0 | 0 | 0 | ✗ | 23 |
| 70 | `ftth/users/user_transactions_page.dart` | مرحّلة جزئياً | 570 | 0 | 0 | 0 | 0 | 1 | ✗ | 22 |
| 71 | `pages/users_page.dart` | مرحّلة جزئياً | 383 | 0 | 0 | 0 | 1 | 0 | ✗ | 22 |
| 72 | `pages/vps_tenant_login_page.dart` | مرحّلة جزئياً | 951 | 1 | 0 | 2 | 0 | 1 | ✗ | 22 |
| 73 | `pages/accounting/chart_of_accounts_page.dart` | مرحّلة جزئياً | 1607 | 2 | 0 | 0 | 0 | 6 | ✓ | 22 |
| 74 | `pages/settings/company_firebase_settings_page.dart` | مرحّلة جزئياً | 285 | 0 | 0 | 0 | 0 | 1 | ✗ | 22 |
| 75 | `permissions/permission_gate.dart` | مرحّلة جزئياً | 230 | 2 | 0 | 0 | 0 | 1 | ✗ | 22 |
| 76 | `ftth/reports/agents_details_page.dart` | مرحّلة جزئياً | 2529 | 0 | 0 | 0 | 0 | 3 | ✓ | 21 |
| 77 | `pages/offline_router_setup_page.dart` | مرحّلة جزئياً | 1476 | 0 | 0 | 0 | 0 | 7 | ✓ | 21 |
| 78 | `pages/salary_management_page.dart` | مرحّلة جزئياً | 1391 | 0 | 0 | 0 | 0 | 7 | ✓ | 21 |
| 79 | `pages/accounting/accounting_dashboard_page.dart` | مرحّلة جزئياً | 1454 | 9 | 0 | 0 | 0 | 1 | ✓ | 21 |
| 80 | `pages/accounting/withdrawal_requests_page.dart` | مرحّلة جزئياً | 976 | 0 | 0 | 0 | 0 | 2 | ✗ | 21 |
| 81 | `pages/properties/properties_list_page.dart` | مرحّلة جزئياً | 613 | 0 | 0 | 0 | 0 | 2 | ✗ | 21 |
| 82 | `pages/properties/property_form_page.dart` | مرحّلة جزئياً | 934 | 0 | 0 | 0 | 0 | 2 | ✗ | 21 |
| 83 | `pages/properties/property_qr_scanner.dart` | مرحّلة جزئياً | 238 | 0 | 0 | 0 | 0 | 2 | ✗ | 21 |
| 84 | `sas_agent/premises/ui/premises_form_screen.dart` | مرحّلة جزئياً | 396 | 0 | 0 | 0 | 0 | 2 | ✗ | 21 |
| 85 | `task/reports_page.dart` | ملتزمة بالكامل | 2520 | 0 | 0 | 0 | 0 | 0 | ✗ | 21 |
| 86 | `widgets/platform_webview.dart` | مرحّلة جزئياً | 289 | 0 | 0 | 0 | 0 | 2 | ✗ | 21 |
| 87 | `ftth/widgets/notifications_page.dart` | مرحّلة جزئياً | 725 | 0 | 0 | 0 | 0 | 1 | ✗ | 20 |
| 88 | `pages/modern_home_page.dart` | مرحّلة جزئياً | 900 | 1 | 0 | 0 | 0 | 1 | ✗ | 20 |
| 89 | `pages/permission_reset_page.dart` | مرحّلة جزئياً | 214 | 0 | 0 | 0 | 0 | 1 | ✗ | 20 |
| 90 | `pages/super_admin_login_page.dart` | مرحّلة جزئياً | 269 | 0 | 0 | 0 | 0 | 1 | ✗ | 20 |
| 91 | `pages/vps_super_admin_login_page.dart` | مرحّلة جزئياً | 317 | 0 | 0 | 0 | 0 | 1 | ✗ | 20 |
| 92 | `pages/whatsapp_chat_page.dart` | مرحّلة جزئياً | 1050 | 0 | 0 | 0 | 1 | 0 | ✗ | 20 |
| 93 | `whatsapp/pages/whatsapp_system_settings_page.dart` | مرحّلة جزئياً | 512 | 1 | 0 | 0 | 0 | 1 | ✗ | 20 |
| 94 | `citizen_portal/pages/citizen_portal_dashboard_page.dart` | ملتزمة بالكامل | 333 | 0 | 0 | 0 | 0 | 0 | ✗ | 19 |
| 95 | `pages/search_comparison_page.dart` | ملتزمة بالكامل | 410 | 0 | 0 | 0 | 0 | 0 | ✗ | 19 |
| 96 | `pages/accounting/statistics_page.dart` | مرحّلة جزئياً | 1557 | 2 | 0 | 0 | 0 | 0 | ✗ | 19 |
| 97 | `task/technician_performance_page.dart` | مرحّلة جزئياً | 738 | 2 | 0 | 0 | 0 | 0 | ✗ | 19 |
| 98 | `ftth/diagnostic/diagnostic_page.dart` | مرحّلة جزئياً | 998 | 0 | 0 | 0 | 0 | 1 | ✗ | 18 |
| 99 | `network_quality/pages/optical_webview_page.dart` | مرحّلة جزئياً | 482 | 0 | 0 | 0 | 0 | 1 | ✗ | 18 |
| 100 | `pages/dashboard_page.dart` | مرحّلة جزئياً | 62 | 0 | 0 | 0 | 0 | 1 | ✗ | 18 |
| 101 | `pages/accounting/activation_profitability_page.dart` | مرحّلة جزئياً | 272 | 0 | 0 | 0 | 0 | 1 | ✗ | 18 |
| 102 | `pages/accounting/salaries_page.dart` | مرحّلة جزئياً | 1358 | 0 | 0 | 0 | 0 | 6 | ✓ | 18 |
| 103 | `sas_agent/pages/sas_bulk_import_page.dart` | مرحّلة جزئياً | 1279 | 0 | 0 | 0 | 0 | 6 | ✓ | 18 |
| 104 | `sas_agent/pages/sas_settings_tab.dart` | مرحّلة جزئياً | 901 | 0 | 0 | 0 | 0 | 1 | ✗ | 18 |
| 105 | `task/add_task_api_dialog.dart` | مرحّلة جزئياً | 1673 | 0 | 0 | 0 | 0 | 1 | ✗ | 18 |
| 106 | `main.dart` | غير مرحّلة | 482 | 0 | 0 | 2 | 0 | 0 | ✗ | 17 |
| 107 | `ftth/subscriptions/all_subscriptions_details_page.dart` | ملتزمة بالكامل | 385 | 0 | 0 | 0 | 0 | 0 | ✗ | 17 |
| 108 | `ftth/subscriptions/plans_bundles_page.dart` | ملتزمة بالكامل | 614 | 0 | 0 | 0 | 0 | 0 | ✗ | 17 |
| 109 | `ftth/tickets/TKTAT.dart` | ملتزمة بالكامل | 123 | 0 | 0 | 0 | 0 | 0 | ✗ | 17 |
| 110 | `ftth/tickets/tktat_raw_page.dart` | ملتزمة بالكامل | 163 | 0 | 0 | 0 | 0 | 0 | ✗ | 17 |
| 111 | `ftth/transactions/daily_settlement_page.dart` | مرحّلة جزئياً | 1772 | 6 | 0 | 0 | 0 | 1 | ✓ | 17 |
| 112 | `pages/company_diagnostics_page.dart` | مرحّلة جزئياً | 1359 | 0 | 0 | 0 | 0 | 5 | ✓ | 17 |
| 113 | `pages/firebase_data_viewer.dart` | ملتزمة بالكامل | 294 | 0 | 0 | 0 | 0 | 0 | ✗ | 17 |
| 114 | `pages/whatsapp_business_config_page.dart` | مرحّلة جزئياً | 1205 | 0 | 0 | 0 | 0 | 5 | ✓ | 17 |
| 115 | `pages/accounting/fixed_expenses_page.dart` | مرحّلة جزئياً | 976 | 0 | 0 | 0 | 0 | 5 | ✓ | 17 |
| 116 | `pages/accounting/monthly_comparison_page.dart` | مرحّلة جزئياً | 1045 | 1 | 0 | 0 | 0 | 0 | ✗ | 17 |
| 117 | `pages/accounting/year_comparison_page.dart` | مرحّلة جزئياً | 1180 | 1 | 0 | 0 | 0 | 0 | ✗ | 17 |
| 118 | `network_quality/pages/advanced_tools_page.dart` | مرحّلة جزئياً | 248 | 8 | 0 | 0 | 0 | 0 | ✓ | 16 |
| 119 | `pages/accounting/ftth_operator_transactions_page.dart` | مرحّلة جزئياً | 1086 | 0 | 8 | 0 | 0 | 0 | ✓ | 16 |
| 120 | `test_pop.dart` | ملتزمة بالكامل | 35 | 0 | 0 | 0 | 0 | 0 | ✗ | 15 |
| 121 | `ftth/reports/data_page.dart` | ملتزمة بالكامل | 99 | 0 | 0 | 0 | 0 | 0 | ✗ | 15 |
| 122 | `inventory/pages/materials_page.dart` | مرحّلة جزئياً | 827 | 0 | 0 | 0 | 0 | 5 | ✓ | 15 |
| 123 | `pages/receipt_template_editor_page.dart` | ملتزمة بالكامل | 1504 | 0 | 0 | 0 | 0 | 0 | ✗ | 15 |
| 124 | `pages/accounting/aging_report_page.dart` | ملتزمة بالكامل | 762 | 0 | 0 | 0 | 0 | 0 | ✗ | 15 |
| 125 | `pages/accounting/plan_profits_page.dart` | ملتزمة بالكامل | 540 | 0 | 0 | 0 | 0 | 0 | ✗ | 15 |
| 126 | `pages/accounting/sas_accounting_page.dart` | ملتزمة بالكامل | 596 | 0 | 0 | 0 | 0 | 0 | ✗ | 15 |
| 127 | `pages/accounting/wallet_transactions_page.dart` | ملتزمة بالكامل | 1339 | 0 | 0 | 0 | 0 | 0 | ✗ | 15 |
| 128 | `pages/hr/employee_profile_page.dart` | مرحّلة جزئياً | 934 | 3 | 0 | 0 | 0 | 3 | ✓ | 15 |
| 129 | `sas_agent/pages/sas_reports_page.dart` | ملتزمة بالكامل | 840 | 0 | 0 | 0 | 0 | 0 | ✗ | 15 |
| 130 | `sas_agent/whatsapp/ui/wa_templates_screen.dart` | ملتزمة بالكامل | 395 | 0 | 0 | 0 | 0 | 0 | ✗ | 15 |
| 131 | `task/task_list_screen.dart` | ملتزمة بالكامل | 401 | 0 | 0 | 0 | 0 | 0 | ✗ | 15 |
| 132 | `widgets/auth_guard.dart` | غير مرحّلة | 109 | 0 | 0 | 0 | 0 | 0 | ✗ | 15 |
| 133 | `pages/hr_reports_page.dart` | مرحّلة جزئياً | 1852 | 0 | 0 | 0 | 0 | 2 | ✓ | 14 |
| 134 | `network_quality/pages/quality_results_page.dart` | مرحّلة جزئياً | 1443 | 6 | 0 | 0 | 0 | 0 | ✓ | 12 |
| 135 | `pages/employee_tracking_report_page.dart` | مرحّلة جزئياً | 1016 | 4 | 0 | 0 | 0 | 1 | ✓ | 11 |
| 136 | `network_quality/pages/wifi_channel_analyzer_page.dart` | مرحّلة جزئياً | 408 | 5 | 0 | 0 | 0 | 0 | ✓ | 10 |
| 137 | `inventory/pages/returns_page.dart` | مرحّلة جزئياً | 415 | 0 | 0 | 0 | 0 | 3 | ✓ | 9 |
| 138 | `pages/analysis_page.dart` | مرحّلة جزئياً | 669 | 2 | 0 | 0 | 0 | 1 | ✓ | 9 |
| 139 | `pages/deductions_bonuses_page.dart` | مرحّلة جزئياً | 821 | 0 | 0 | 0 | 0 | 3 | ✓ | 9 |
| 140 | `pages/whatsapp_excel_sender_page.dart` | مرحّلة جزئياً | 456 | 0 | 0 | 0 | 0 | 3 | ✓ | 9 |
| 141 | `pages/accounting/employee_adjustments_page.dart` | مرحّلة جزئياً | 835 | 0 | 0 | 0 | 0 | 3 | ✓ | 9 |
| 142 | `pages/accounting/expenses_page.dart` | مرحّلة جزئياً | 825 | 0 | 0 | 0 | 0 | 3 | ✓ | 9 |
| 143 | `pages/accounting/ftth_operator_linking_page.dart` | مرحّلة جزئياً | 759 | 0 | 0 | 0 | 0 | 3 | ✓ | 9 |
| 144 | `pages/accounting/revenue_page.dart` | مرحّلة جزئياً | 1167 | 0 | 0 | 0 | 0 | 3 | ✓ | 9 |
| 145 | `pages/accounting/zone_maintenance_fees_page.dart` | مرحّلة جزئياً | 575 | 0 | 0 | 0 | 0 | 3 | ✓ | 9 |
| 146 | `sas_agent/pages/sas_reminders_page.dart` | مرحّلة جزئياً | 820 | 0 | 0 | 0 | 0 | 3 | ✓ | 9 |
| 147 | `sas_agent/whatsapp/ui/wa_settings_screen.dart` | مرحّلة جزئياً | 505 | 0 | 0 | 0 | 0 | 3 | ✓ | 9 |
| 148 | `ftth/tickets/tktats_page.dart` | مرحّلة جزئياً | 2293 | 0 | 0 | 0 | 0 | 2 | ✓ | 8 |
| 149 | `network_quality/pages/history_trend_page.dart` | مرحّلة جزئياً | 492 | 4 | 0 | 0 | 0 | 0 | ✓ | 8 |
| 150 | `pages/search_users_page.dart` | ملتزمة بالكامل | 1274 | 0 | 0 | 0 | 0 | 0 | ✓ | 8 |
| 151 | `pages/diagnostics/system_diagnostics_page.dart` | مرحّلة جزئياً | 851 | 0 | 0 | 0 | 0 | 2 | ✓ | 8 |
| 152 | `pages/ftth/fetch_server_data_page.dart` | مرحّلة جزئياً | 2950 | 0 | 0 | 0 | 0 | 1 | ✓ | 7 |
| 153 | `ftth/reports/profits_page.dart` | مرحّلة جزئياً | 3538 | 0 | 0 | 0 | 0 | 2 | ✓ | 6 |
| 154 | `ftth/tickets/create_ticket_page.dart` | مرحّلة جزئياً | 793 | 0 | 0 | 0 | 0 | 2 | ✓ | 6 |
| 155 | `inventory/pages/dispensing_page.dart` | مرحّلة جزئياً | 742 | 0 | 0 | 0 | 0 | 2 | ✓ | 6 |
| 156 | `inventory/pages/invoices_page.dart` | مرحّلة جزئياً | 748 | 0 | 0 | 0 | 0 | 2 | ✓ | 6 |
| 157 | `inventory/pages/purchases_page.dart` | مرحّلة جزئياً | 648 | 0 | 0 | 0 | 0 | 2 | ✓ | 6 |
| 158 | `inventory/pages/stock_levels_page.dart` | مرحّلة جزئياً | 417 | 0 | 0 | 0 | 0 | 2 | ✓ | 6 |
| 159 | `inventory/pages/suppliers_page.dart` | مرحّلة جزئياً | 387 | 0 | 0 | 0 | 0 | 2 | ✓ | 6 |
| 160 | `inventory/pages/warehouses_page.dart` | مرحّلة جزئياً | 346 | 0 | 0 | 0 | 0 | 2 | ✓ | 6 |
| 161 | `pages/accounting/budget_page.dart` | مرحّلة جزئياً | 1024 | 0 | 0 | 0 | 0 | 2 | ✓ | 6 |
| 162 | `pages/accounting/salary_policy_page.dart` | مرحّلة جزئياً | 490 | 0 | 0 | 0 | 0 | 2 | ✓ | 6 |
| 163 | `pages/iptv/iptv_subscribers_page.dart` | مرحّلة جزئياً | 1128 | 0 | 0 | 0 | 0 | 2 | ✓ | 6 |
| 164 | `sas_agent/pages/sas_regions_page.dart` | مرحّلة جزئياً | 482 | 0 | 0 | 0 | 0 | 2 | ✓ | 6 |
| 165 | `pages/track_users_map_page.dart` | مرحّلة جزئياً | 1086 | 1 | 0 | 0 | 0 | 1 | ✓ | 5 |
| 166 | `sas_agent/sas_agent_page.dart` | مرحّلة جزئياً | 751 | 0 | 0 | 0 | 1 | 0 | ✓ | 5 |
| 167 | `ftth/reports/zones_page.dart` | ملتزمة بالكامل | 1346 | 0 | 0 | 0 | 0 | 0 | ✓ | 4 |
| 168 | `network_quality/network_quality_home_page.dart` | مرحّلة جزئياً | 169 | 2 | 0 | 0 | 0 | 0 | ✓ | 4 |
| 169 | `network_quality/pages/live_monitor_page.dart` | مرحّلة جزئياً | 376 | 2 | 0 | 0 | 0 | 0 | ✓ | 4 |
| 170 | `network_quality/pages/quality_scan_page.dart` | مرحّلة جزئياً | 441 | 2 | 0 | 0 | 0 | 0 | ✓ | 4 |
| 171 | `pages/accounting/compound_journal_entry_page.dart` | مرحّلة جزئياً | 2941 | 2 | 0 | 0 | 0 | 0 | ✓ | 4 |
| 172 | `pages/accounting/trial_balance_page.dart` | مرحّلة جزئياً | 616 | 2 | 0 | 0 | 0 | 0 | ✓ | 4 |
| 173 | `ftth/reports/audit_log_page.dart` | مرحّلة جزئياً | 1042 | 0 | 0 | 0 | 0 | 1 | ✓ | 3 |
| 174 | `ftth/subscriptions/expiring_soon_page.dart` | مرحّلة جزئياً | 2540 | 0 | 0 | 0 | 0 | 1 | ✓ | 3 |
| 175 | `inventory/pages/customers_page.dart` | مرحّلة جزئياً | 515 | 0 | 0 | 0 | 0 | 1 | ✓ | 3 |
| 176 | `inventory/pages/dispensing_form_page.dart` | مرحّلة جزئياً | 497 | 0 | 0 | 0 | 0 | 1 | ✓ | 3 |
| 177 | `inventory/pages/invoice_details_page.dart` | مرحّلة جزئياً | 538 | 0 | 0 | 0 | 0 | 1 | ✓ | 3 |
| 178 | `inventory/pages/invoice_form_page.dart` | مرحّلة جزئياً | 1029 | 0 | 0 | 0 | 0 | 1 | ✓ | 3 |
| 179 | `inventory/pages/purchase_form_page.dart` | مرحّلة جزئياً | 627 | 0 | 0 | 0 | 0 | 1 | ✓ | 3 |
| 180 | `inventory/pages/sales_page.dart` | مرحّلة جزئياً | 539 | 0 | 0 | 0 | 0 | 1 | ✓ | 3 |
| 181 | `inventory/pages/vouchers_page.dart` | مرحّلة جزئياً | 331 | 0 | 0 | 0 | 0 | 1 | ✓ | 3 |
| 182 | `pages/leave_management_page.dart` | مرحّلة جزئياً | 864 | 0 | 0 | 0 | 0 | 1 | ✓ | 3 |
| 183 | `pages/whatsapp_batch_reports_page.dart` | مرحّلة جزئياً | 555 | 0 | 0 | 0 | 0 | 1 | ✓ | 3 |
| 184 | `pages/work_schedules_page.dart` | مرحّلة جزئياً | 471 | 0 | 0 | 0 | 0 | 1 | ✓ | 3 |
| 185 | `pages/accounting/period_closing_page.dart` | مرحّلة جزئياً | 376 | 0 | 0 | 0 | 0 | 1 | ✓ | 3 |
| 186 | `pages/citizen_portal/citizen_details_page.dart` | مرحّلة جزئياً | 777 | 0 | 0 | 0 | 0 | 1 | ✓ | 3 |
| 187 | `pages/super_admin/add_company_page.dart` | مرحّلة جزئياً | 540 | 0 | 0 | 0 | 0 | 1 | ✓ | 3 |
| 188 | `sas_agent/pages/sas_bulk_message_page.dart` | مرحّلة جزئياً | 753 | 0 | 0 | 0 | 0 | 1 | ✓ | 3 |
| 189 | `sas_agent/pages/sas_test_message_page.dart` | مرحّلة جزئياً | 728 | 0 | 0 | 0 | 0 | 1 | ✓ | 3 |
| 190 | `sas_agent/premises/ui/premises_list_screen.dart` | مرحّلة جزئياً | 370 | 0 | 0 | 0 | 0 | 1 | ✓ | 3 |
| 191 | `sas_agent/widgets/sas_citizen_statement.dart` | مرحّلة جزئياً | 519 | 0 | 0 | 0 | 0 | 1 | ✓ | 3 |
| 192 | `ftth/users/quick_search_users_page.dart` | مرحّلة جزئياً | 1295 | 1 | 0 | 0 | 0 | 0 | ✓ | 2 |
| 193 | `network_quality/pages/dns_benchmark_page.dart` | مرحّلة جزئياً | 321 | 1 | 0 | 0 | 0 | 0 | ✓ | 2 |
| 194 | `pages/account/account_info_page.dart` | مرحّلة جزئياً | 741 | 1 | 0 | 0 | 0 | 0 | ✓ | 2 |
| 195 | `pages/accounting/cash_flow_page.dart` | مرحّلة جزئياً | 681 | 1 | 0 | 0 | 0 | 0 | ✓ | 2 |
| 196 | `ftth/requests/customer_hub_page.dart` | ملتزمة بالكامل | 53 | 0 | 0 | 0 | 0 | 0 | ✓ | 0 |
| 197 | `ftth/tasks/customer_search_connect_page.dart` | ملتزمة بالكامل | 682 | 0 | 0 | 0 | 0 | 0 | ✓ | 0 |
| 198 | `ftth/tasks/ftth_connect_form.dart` | ملتزمة بالكامل | 610 | 0 | 0 | 0 | 0 | 0 | ✓ | 0 |
| 199 | `ftth/tasks/ftth_tasks_page.dart` | ملتزمة بالكامل | 474 | 0 | 0 | 0 | 0 | 0 | ✓ | 0 |
| 200 | `ftth/tickets/customer_tickets_page.dart` | ملتزمة بالكامل | 314 | 0 | 0 | 0 | 0 | 0 | ✓ | 0 |
| 201 | `ftth/tickets/tktat_details_page.dart` | ملتزمة بالكامل | 1236 | 0 | 0 | 0 | 0 | 0 | ✓ | 0 |
| 202 | `inventory/inventory_page.dart` | ملتزمة بالكامل | 451 | 0 | 0 | 0 | 0 | 0 | ✓ | 0 |
| 203 | `inventory/pages/customer_details_page.dart` | ملتزمة بالكامل | 590 | 0 | 0 | 0 | 0 | 0 | ✓ | 0 |
| 204 | `inventory/pages/customer_form_page.dart` | ملتزمة بالكامل | 365 | 0 | 0 | 0 | 0 | 0 | ✓ | 0 |
| 205 | `inventory/pages/inventory_reports_page.dart` | ملتزمة بالكامل | 497 | 0 | 0 | 0 | 0 | 0 | ✓ | 0 |
| 206 | `inventory/pages/movements_page.dart` | ملتزمة بالكامل | 479 | 0 | 0 | 0 | 0 | 0 | ✓ | 0 |
| 207 | `inventory/pages/return_form_page.dart` | ملتزمة بالكامل | 543 | 0 | 0 | 0 | 0 | 0 | ✓ | 0 |
| 208 | `inventory/pages/sale_form_page.dart` | ملتزمة بالكامل | 630 | 0 | 0 | 0 | 0 | 0 | ✓ | 0 |
| 209 | `inventory/pages/voucher_form_page.dart` | ملتزمة بالكامل | 394 | 0 | 0 | 0 | 0 | 0 | ✓ | 0 |
| 210 | `network_quality/pages/device_detail_page.dart` | ملتزمة بالكامل | 486 | 0 | 0 | 0 | 0 | 0 | ✓ | 0 |
| 211 | `network_quality/pages/router_wifi_edit_page.dart` | ملتزمة بالكامل | 517 | 0 | 0 | 0 | 0 | 0 | ✓ | 0 |
| 212 | `pages/aria_page.dart` | ملتزمة بالكامل | 174 | 0 | 0 | 0 | 0 | 0 | ✓ | 0 |
| 213 | `pages/attendance_page.dart` | ملتزمة بالكامل | 798 | 0 | 0 | 0 | 0 | 0 | ✓ | 0 |
| 214 | `pages/charts_page.dart` | ملتزمة بالكامل | 201 | 0 | 0 | 0 | 0 | 0 | ✓ | 0 |
| 215 | `pages/client_setup_page.dart` | ملتزمة بالكامل | 376 | 0 | 0 | 0 | 0 | 0 | ✓ | 0 |
| 216 | `pages/google_drive_files_page.dart` | ملتزمة بالكامل | 235 | 0 | 0 | 0 | 0 | 0 | ✓ | 0 |
| 217 | `pages/hr_hub_page.dart` | ملتزمة بالكامل | 241 | 0 | 0 | 0 | 0 | 0 | ✓ | 0 |
| 218 | `pages/local_subscriber_details_page.dart` | ملتزمة بالكامل | 856 | 0 | 0 | 0 | 0 | 0 | ✓ | 0 |
| 219 | `pages/my_dashboard_page.dart` | ملتزمة بالكامل | 3177 | 0 | 0 | 0 | 0 | 0 | ✓ | 0 |
| 220 | `pages/printer_settings_page.dart` | ملتزمة بالكامل | 226 | 0 | 0 | 0 | 0 | 0 | ✓ | 0 |
| 221 | `pages/reminder_reports_page.dart` | ملتزمة بالكامل | 179 | 0 | 0 | 0 | 0 | 0 | ✓ | 0 |
| 222 | `pages/settings_page.dart` | ملتزمة بالكامل | 239 | 0 | 0 | 0 | 0 | 0 | ✓ | 0 |
| 223 | `pages/settings_text_scale_page.dart` | ملتزمة بالكامل | 146 | 0 | 0 | 0 | 0 | 0 | ✓ | 0 |
| 224 | `pages/statistics_page.dart` | ملتزمة بالكامل | 667 | 0 | 0 | 0 | 0 | 0 | ✓ | 0 |
| 225 | `pages/users_page_vps.dart` | ملتزمة بالكامل | 1961 | 0 | 0 | 0 | 0 | 0 | ✓ | 0 |
| 226 | `pages/user_details_page.dart` | ملتزمة بالكامل | 761 | 0 | 0 | 0 | 0 | 0 | ✓ | 0 |
| 227 | `pages/whatsapp_conversations_page.dart` | ملتزمة بالكامل | 725 | 0 | 0 | 0 | 0 | 0 | ✓ | 0 |
| 228 | `pages/accounting/audit_trail_page.dart` | ملتزمة بالكامل | 435 | 0 | 0 | 0 | 0 | 0 | ✓ | 0 |
| 229 | `pages/accounting/balance_sheet_page.dart` | ملتزمة بالكامل | 687 | 0 | 0 | 0 | 0 | 0 | ✓ | 0 |
| 230 | `pages/accounting/financial_ratios_page.dart` | ملتزمة بالكامل | 636 | 0 | 0 | 0 | 0 | 0 | ✓ | 0 |
| 231 | `pages/accounting/hr_reports_page.dart` | ملتزمة بالكامل | 856 | 0 | 0 | 0 | 0 | 0 | ✓ | 0 |
| 232 | `pages/accounting/income_statement_page.dart` | ملتزمة بالكامل | 551 | 0 | 0 | 0 | 0 | 0 | ✓ | 0 |
| 233 | `pages/accounting/system_audit_page.dart` | ملتزمة بالكامل | 613 | 0 | 0 | 0 | 0 | 0 | ✓ | 0 |
| 234 | `pages/announcements/announcements_page.dart` | ملتزمة بالكامل | 932 | 0 | 0 | 0 | 0 | 0 | ✓ | 0 |
| 235 | `pages/chat/chat_rooms_page.dart` | ملتزمة بالكامل | 1464 | 0 | 0 | 0 | 0 | 0 | ✓ | 0 |
| 236 | `pages/citizen_portal/citizen_portal_dashboard.dart` | ملتزمة بالكامل | 384 | 0 | 0 | 0 | 0 | 0 | ✓ | 0 |
| 237 | `pages/diagnostics/permissions_diagnostics_page.dart` | ملتزمة بالكامل | 898 | 0 | 0 | 0 | 0 | 0 | ✓ | 0 |
| 238 | `pages/ftth/ftth_company_page.dart` | ملتزمة بالكامل | 385 | 0 | 0 | 0 | 0 | 0 | ✓ | 0 |
| 239 | `pages/super_admin/edit_company_page.dart` | ملتزمة بالكامل | 571 | 0 | 0 | 0 | 0 | 0 | ✓ | 0 |
| 240 | `pages/super_admin/tenant_features_page.dart` | ملتزمة بالكامل | 363 | 0 | 0 | 0 | 0 | 0 | ✓ | 0 |
| 241 | `sas_agent/pages/sas_admin_agents_page.dart` | ملتزمة بالكامل | 473 | 0 | 0 | 0 | 0 | 0 | ✓ | 0 |
| 242 | `sas_agent/pages/sas_debtors_page.dart` | ملتزمة بالكامل | 260 | 0 | 0 | 0 | 0 | 0 | ✓ | 0 |
| 243 | `sas_agent/pages/sas_license_page.dart` | ملتزمة بالكامل | 159 | 0 | 0 | 0 | 0 | 0 | ✓ | 0 |
| 244 | `sas_agent/pages/sas_package_prices_page.dart` | ملتزمة بالكامل | 378 | 0 | 0 | 0 | 0 | 0 | ✓ | 0 |
| 245 | `sas_agent/pages/sas_profits_page.dart` | ملتزمة بالكامل | 341 | 0 | 0 | 0 | 0 | 0 | ✓ | 0 |
| 246 | `sas_agent/pages/sas_reports_tab.dart` | ملتزمة بالكامل | 268 | 0 | 0 | 0 | 0 | 0 | ✓ | 0 |
| 247 | `sas_agent/pages/sas_subscriber_form_page.dart` | ملتزمة بالكامل | 477 | 0 | 0 | 0 | 0 | 0 | ✓ | 0 |
| 248 | `sas_agent/pages/sas_ticket_detail_page.dart` | ملتزمة بالكامل | 558 | 0 | 0 | 0 | 0 | 0 | ✓ | 0 |
| 249 | `sas_agent/pages/sas_transactions_page.dart` | ملتزمة بالكامل | 376 | 0 | 0 | 0 | 0 | 0 | ✓ | 0 |
| 250 | `task/follow_up_page.dart` | ملتزمة بالكامل | 1026 | 0 | 0 | 0 | 0 | 0 | ✓ | 0 |
| 251 | `widgets/permissions_gate.dart` | ملتزمة بالكامل | 83 | 0 | 0 | 0 | 0 | 0 | ✓ | 0 |

**النقاط** = Color×2 + Colors×2 + ثيمات قديمة + AppBar خام×5 + Card خام×2 + styleFrom×3 + 15 إن لم يُلفّ بـ SdTheme/SdPage/SdNavShell.
