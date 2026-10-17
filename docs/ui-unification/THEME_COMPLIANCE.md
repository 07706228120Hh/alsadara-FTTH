# تقرير التزام الشاشات بالثيم الموحّد

تاريخ الفحص: 2026-10-17 — عدد الشاشات: 251

| الحالة | العدد |
|---|---|
| ملتزمة بالكامل | 57 |
| مرحّلة جزئياً | 191 |
| غير مرحّلة | 3 |

إجمالي الألوان المكتوبة يدوياً: 435 Color(0x..) + 423 Colors.xxx — AppTheme: 2، AccountingTheme: 84، Energy: 31، GoogleFonts: 10، AppBar خام: 82، styleFrom: 559

## حسب الوحدة

| الوحدة | الشاشات | ملتزمة | جزئية | غير مرحّلة | ألوان يدوية |
|---|---|---|---|---|---|
| pages | 127 | 28 | 99 | 0 | 563 |
| ftth | 46 | 6 | 40 | 0 | 202 |
| network_quality | 11 | 2 | 9 | 0 | 43 |
| task | 8 | 2 | 6 | 0 | 30 |
| whatsapp | 3 | 0 | 3 | 0 | 11 |
| sas_agent | 25 | 10 | 15 | 0 | 7 |
| permissions | 1 | 0 | 1 | 0 | 2 |
| citizen_portal | 2 | 0 | 2 | 0 | 0 |
| widgets | 3 | 1 | 1 | 1 | 0 |
| (root) | 2 | 0 | 0 | 2 | 0 |
| inventory | 23 | 8 | 15 | 0 | 0 |

## كل الشاشات (الأسوأ أولاً)

| # | الملف | الحالة | أسطر | Color(0x) | Colors.x | ثيمات قديمة | AppBar خام | styleFrom | هيكل Sd | نقاط |
|---|---|---|---|---|---|---|---|---|---|---|
| 1 | `pages/accounting/ftth_operators_dashboard_page.dart` | مرحّلة جزئياً | 14398 | 3 | 191 | 0 | 5 | 33 | ✗ | 549 |
| 2 | `ftth/subscriptions/subscription_details_page.dart` | مرحّلة جزئياً | 12937 | 1 | 87 | 0 | 0 | 21 | ✗ | 264 |
| 3 | `pages/super_admin/company_details_page.dart` | مرحّلة جزئياً | 3815 | 28 | 0 | 10 | 1 | 12 | ✓ | 109 |
| 4 | `pages/super_admin/super_admin_dashboard.dart` | مرحّلة جزئياً | 2781 | 23 | 0 | 10 | 1 | 8 | ✗ | 100 |
| 5 | `pages/accounting/ftth_operator_account_page.dart` | مرحّلة جزئياً | 2399 | 7 | 22 | 0 | 1 | 5 | ✗ | 97 |
| 6 | `pages/login/premium_login_page.dart` | مرحّلة جزئياً | 1868 | 47 | 0 | 0 | 0 | 0 | ✓ | 94 |
| 7 | `pages/ftth_advanced_system.dart` | مرحّلة جزئياً | 1904 | 3 | 19 | 0 | 2 | 4 | ✗ | 93 |
| 8 | `ftth/core/home_page.dart` | مرحّلة جزئياً | 5620 | 7 | 21 | 0 | 1 | 3 | ✗ | 87 |
| 9 | `pages/super_admin/unified_companies_page.dart` | مرحّلة جزئياً | 2869 | 17 | 0 | 4 | 0 | 14 | ✓ | 80 |
| 10 | `pages/accounting/client_accounts_page.dart` | مرحّلة جزئياً | 3791 | 23 | 0 | 0 | 0 | 4 | ✗ | 73 |
| 11 | `pages/company_settings_page.dart` | مرحّلة جزئياً | 4011 | 9 | 0 | 0 | 2 | 14 | ✓ | 70 |
| 12 | `ftth/subscriptions/subscriptions_page.dart` | مرحّلة جزئياً | 5063 | 1 | 0 | 0 | 1 | 14 | ✗ | 66 |
| 13 | `pages/settings/ftth_sync_settings_page.dart` | مرحّلة جزئياً | 1998 | 0 | 0 | 0 | 0 | 13 | ✓ | 61 |
| 14 | `whatsapp/pages/whatsapp_server_settings_page.dart` | مرحّلة جزئياً | 1982 | 0 | 0 | 0 | 1 | 9 | ✗ | 61 |
| 15 | `ftth/transactions/account_records_page.dart` | مرحّلة جزئياً | 4317 | 10 | 0 | 0 | 1 | 6 | ✗ | 60 |
| 16 | `ftth/transactions/account_stats_page.dart` | مرحّلة جزئياً | 657 | 0 | 19 | 0 | 1 | 0 | ✗ | 60 |
| 17 | `pages/server_data_page.dart` | مرحّلة جزئياً | 4091 | 7 | 0 | 0 | 0 | 2 | ✓ | 60 |
| 18 | `pages/local_storage_page.dart` | مرحّلة جزئياً | 3910 | 0 | 0 | 0 | 1 | 15 | ✓ | 58 |
| 19 | `ftth/auth/login_page.dart` | مرحّلة جزئياً | 896 | 15 | 0 | 0 | 1 | 2 | ✗ | 56 |
| 20 | `pages/kml_zones_map_page.dart` | مرحّلة جزئياً | 2608 | 14 | 0 | 0 | 0 | 4 | ✗ | 55 |
| 21 | `task/audit_dashboard_page.dart` | مرحّلة جزئياً | 1979 | 20 | 0 | 0 | 0 | 0 | ✗ | 55 |
| 22 | `ftth/users/user_details_page.dart` | مرحّلة جزئياً | 5582 | 0 | 0 | 0 | 0 | 17 | ✓ | 51 |
| 23 | `pages/properties/property_qr_batches_page.dart` | مرحّلة جزئياً | 1117 | 0 | 0 | 2 | 2 | 8 | ✗ | 51 |
| 24 | `pages/accounting/collections_page.dart` | مرحّلة جزئياً | 2539 | 0 | 0 | 2 | 0 | 11 | ✗ | 50 |
| 25 | `ftth/transactions/creator_amounts_page.dart` | مرحّلة جزئياً | 1074 | 0 | 11 | 0 | 1 | 0 | ✗ | 44 |
| 26 | `pages/accounting/funds_overview_page.dart` | مرحّلة جزئياً | 567 | 0 | 19 | 0 | 0 | 0 | ✓ | 44 |
| 27 | `pages/whatsapp_templates_page.dart` | مرحّلة جزئياً | 1282 | 9 | 0 | 6 | 0 | 6 | ✓ | 42 |
| 28 | `pages/properties/property_detail_page.dart` | مرحّلة جزئياً | 2180 | 0 | 0 | 0 | 0 | 9 | ✗ | 42 |
| 29 | `sas_agent/pages/sas_subscriber_detail_page.dart` | مرحّلة جزئياً | 2600 | 3 | 0 | 0 | 0 | 7 | ✗ | 42 |
| 30 | `pages/admin/organizations_management_page.dart` | مرحّلة جزئياً | 1211 | 0 | 0 | 0 | 2 | 4 | ✗ | 41 |
| 31 | `ftth/transactions/transactions_page.dart` | مرحّلة جزئياً | 4911 | 4 | 0 | 0 | 0 | 5 | ✗ | 40 |
| 32 | `pages/home_page.dart` | مرحّلة جزئياً | 3481 | 12 | 2 | 0 | 0 | 4 | ✓ | 40 |
| 33 | `pages/accounting/cashbox_page.dart` | مرحّلة جزئياً | 902 | 0 | 0 | 1 | 0 | 8 | ✗ | 40 |
| 34 | `pages/chat/chat_conversation_page.dart` | مرحّلة جزئياً | 2997 | 1 | 0 | 0 | 2 | 4 | ✗ | 39 |
| 35 | `whatsapp/pages/whatsapp_settings_hub_page.dart` | مرحّلة جزئياً | 667 | 9 | 0 | 0 | 0 | 2 | ✗ | 39 |
| 36 | `ftth/reports/export_page.dart` | مرحّلة جزئياً | 1314 | 5 | 0 | 0 | 2 | 1 | ✗ | 38 |
| 37 | `pages/accounting/journal_entries_page.dart` | مرحّلة جزئياً | 2608 | 1 | 0 | 0 | 0 | 12 | ✓ | 38 |
| 38 | `pages/accounting/accounting_dashboard_page.dart` | مرحّلة جزئياً | 1454 | 17 | 0 | 0 | 0 | 1 | ✓ | 37 |
| 39 | `ftth/transactions/caounter_details_page.dart` | مرحّلة جزئياً | 2647 | 0 | 0 | 0 | 1 | 4 | ✗ | 36 |
| 40 | `pages/vps_tenant_login_page.dart` | مرحّلة جزئياً | 951 | 8 | 0 | 2 | 0 | 1 | ✗ | 36 |
| 41 | `pages/settings/device_permissions_page.dart` | مرحّلة جزئياً | 757 | 0 | 0 | 0 | 1 | 4 | ✗ | 36 |
| 42 | `pages/super_admin/agents_management_page.dart` | مرحّلة جزئياً | 2832 | 0 | 0 | 3 | 0 | 11 | ✓ | 36 |
| 43 | `pages/super_admin/permissions_management_v2_page.dart` | مرحّلة جزئياً | 1889 | 2 | 13 | 0 | 0 | 2 | ✓ | 36 |
| 44 | `pages/super_admin/vps_data_manager_page.dart` | مرحّلة جزئياً | 1278 | 3 | 0 | 7 | 1 | 6 | ✓ | 36 |
| 45 | `task/home_page_tasks.dart` | مرحّلة جزئياً | 3444 | 0 | 0 | 0 | 0 | 7 | ✗ | 36 |
| 46 | `citizen_portal/pages/citizen_portal_dashboard_page.dart` | مرحّلة جزئياً | 342 | 0 | 0 | 0 | 3 | 0 | ✗ | 34 |
| 47 | `ftth/users/user_records_page.dart` | مرحّلة جزئياً | 1307 | 0 | 7 | 0 | 0 | 1 | ✗ | 34 |
| 48 | `pages/enhanced_search_users_page.dart` | مرحّلة جزئياً | 960 | 0 | 0 | 0 | 1 | 2 | ✗ | 34 |
| 49 | `pages/super_admin/sadara_portal_page.dart` | مرحّلة جزئياً | 3084 | 4 | 0 | 0 | 0 | 8 | ✓ | 34 |
| 50 | `pages/settings/company_firebase_settings_page.dart` | مرحّلة جزئياً | 292 | 3 | 0 | 0 | 1 | 1 | ✗ | 33 |
| 51 | `ftth/requests/customer_onboarding_page.dart` | مرحّلة جزئياً | 1107 | 0 | 0 | 0 | 0 | 10 | ✓ | 32 |
| 52 | `task/technician_performance_page.dart` | مرحّلة جزئياً | 743 | 6 | 0 | 0 | 1 | 0 | ✗ | 32 |
| 53 | `task/technician_transactions_page.dart` | مرحّلة جزئياً | 711 | 4 | 0 | 0 | 0 | 3 | ✗ | 32 |
| 54 | `ftth/core/permissions_page.dart` | مرحّلة جزئياً | 577 | 0 | 0 | 0 | 1 | 3 | ✗ | 31 |
| 55 | `ftth/tickets/technicians_page.dart` | مرحّلة جزئياً | 455 | 0 | 0 | 0 | 1 | 3 | ✗ | 31 |
| 56 | `pages/whatsapp_bulk_sender_page.dart` | مرحّلة جزئياً | 1049 | 0 | 0 | 0 | 0 | 5 | ✓ | 31 |
| 57 | `pages/accounting/budget_page.dart` | مرحّلة جزئياً | 1024 | 0 | 0 | 24 | 0 | 2 | ✓ | 30 |
| 58 | `pages/super_admin/tenant_whatsapp_permissions_page.dart` | مرحّلة جزئياً | 417 | 2 | 0 | 0 | 1 | 2 | ✗ | 30 |
| 59 | `ftth/users/users_page.dart` | مرحّلة جزئياً | 1680 | 0 | 0 | 0 | 0 | 4 | ✗ | 29 |
| 60 | `pages/agents_page.dart` | مرحّلة جزئياً | 562 | 0 | 0 | 0 | 1 | 1 | ✗ | 29 |
| 61 | `pages/enhanced_home_page.dart` | مرحّلة جزئياً | 468 | 0 | 0 | 0 | 1 | 1 | ✗ | 29 |
| 62 | `citizen_portal/pages/companies_management_page.dart` | مرحّلة جزئياً | 392 | 0 | 0 | 0 | 1 | 2 | ✗ | 28 |
| 63 | `ftth/users/users_dashboard_webview.dart` | مرحّلة جزئياً | 359 | 0 | 0 | 0 | 2 | 1 | ✗ | 28 |
| 64 | `ftth/whatsapp/whatsapp_floating_window.dart` | مرحّلة جزئياً | 414 | 0 | 4 | 0 | 1 | 0 | ✗ | 28 |
| 65 | `sas_agent/pages/sas_explorer_page.dart` | مرحّلة جزئياً | 1543 | 2 | 0 | 0 | 0 | 3 | ✗ | 28 |
| 66 | `ftth/diagnostic/diagnostic_page.dart` | مرحّلة جزئياً | 1003 | 2 | 0 | 0 | 1 | 1 | ✗ | 27 |
| 67 | `ftth/users/user_transactions_page.dart` | مرحّلة جزئياً | 577 | 0 | 0 | 0 | 1 | 1 | ✗ | 27 |
| 68 | `network_quality/pages/optical_webview_page.dart` | مرحّلة جزئياً | 487 | 2 | 0 | 0 | 1 | 1 | ✗ | 27 |
| 69 | `pages/properties/location_master_page.dart` | مرحّلة جزئياً | 1075 | 0 | 0 | 0 | 0 | 4 | ✗ | 27 |
| 70 | `permissions/permission_gate.dart` | مرحّلة جزئياً | 233 | 2 | 0 | 0 | 1 | 1 | ✗ | 27 |
| 71 | `sas_agent/premises/ui/premises_detail_screen.dart` | مرحّلة جزئياً | 815 | 0 | 0 | 0 | 0 | 4 | ✗ | 27 |
| 72 | `whatsapp/pages/whatsapp_system_settings_page.dart` | مرحّلة جزئياً | 519 | 2 | 0 | 0 | 1 | 1 | ✗ | 27 |
| 73 | `ftth/reports/agents_details_page.dart` | مرحّلة جزئياً | 2546 | 0 | 0 | 0 | 1 | 3 | ✓ | 26 |
| 74 | `network_quality/pages/quality_results_page.dart` | مرحّلة جزئياً | 1443 | 13 | 0 | 0 | 0 | 0 | ✓ | 26 |
| 75 | `pages/firebase_data_viewer.dart` | مرحّلة جزئياً | 298 | 2 | 0 | 0 | 1 | 0 | ✗ | 26 |
| 76 | `pages/modern_home_page.dart` | مرحّلة جزئياً | 900 | 4 | 0 | 0 | 0 | 1 | ✗ | 26 |
| 77 | `pages/offline_router_setup_page.dart` | مرحّلة جزئياً | 1486 | 0 | 0 | 0 | 1 | 7 | ✓ | 26 |
| 78 | `pages/user_whatsapp_permissions_page.dart` | مرحّلة جزئياً | 583 | 0 | 0 | 0 | 1 | 2 | ✗ | 26 |
| 79 | `pages/properties/property_qr_scanner.dart` | مرحّلة جزئياً | 244 | 0 | 0 | 0 | 1 | 2 | ✗ | 26 |
| 80 | `task/reports_page.dart` | مرحّلة جزئياً | 2542 | 0 | 0 | 0 | 1 | 0 | ✗ | 26 |
| 81 | `widgets/platform_webview.dart` | مرحّلة جزئياً | 293 | 0 | 0 | 0 | 1 | 2 | ✗ | 26 |
| 82 | `ftth/subscriptions/connections_list_page.dart` | مرحّلة جزئياً | 2198 | 0 | 0 | 0 | 0 | 7 | ✓ | 25 |
| 83 | `ftth/users/users_data_page.dart` | مرحّلة جزئياً | 901 | 0 | 0 | 0 | 0 | 2 | ✗ | 25 |
| 84 | `ftth/widgets/notifications_page.dart` | مرحّلة جزئياً | 736 | 0 | 0 | 0 | 1 | 1 | ✗ | 25 |
| 85 | `pages/permission_reset_page.dart` | مرحّلة جزئياً | 217 | 0 | 0 | 0 | 1 | 1 | ✗ | 25 |
| 86 | `pages/users_page_firebase.dart` | مرحّلة جزئياً | 913 | 0 | 0 | 0 | 1 | 1 | ✗ | 25 |
| 87 | `ftth/transactions/creator_transactions_detail_page.dart` | مرحّلة جزئياً | 2384 | 0 | 0 | 0 | 1 | 0 | ✗ | 24 |
| 88 | `pages/search_comparison_page.dart` | مرحّلة جزئياً | 413 | 0 | 0 | 0 | 1 | 0 | ✗ | 24 |
| 89 | `pages/accounting/settlement_reports_page.dart` | مرحّلة جزئياً | 956 | 3 | 0 | 0 | 0 | 1 | ✗ | 24 |
| 90 | `ftth/tickets/tickets_login_page.dart` | مرحّلة جزئياً | 546 | 0 | 0 | 0 | 0 | 2 | ✗ | 23 |
| 91 | `ftth/tickets/tktats_page_beautiful.dart` | مرحّلة جزئياً | 549 | 0 | 0 | 0 | 1 | 1 | ✗ | 23 |
| 92 | `pages/dashboard_page.dart` | مرحّلة جزئياً | 64 | 0 | 0 | 0 | 1 | 1 | ✗ | 23 |
| 93 | `pages/accounting/chart_of_accounts_page.dart` | مرحّلة جزئياً | 1607 | 2 | 0 | 1 | 0 | 6 | ✓ | 23 |
| 94 | `pages/accounting/compound_journal_entry_page.dart` | مرحّلة جزئياً | 2941 | 7 | 0 | 9 | 0 | 0 | ✓ | 23 |
| 95 | `pages/accounting/statistics_page.dart` | مرحّلة جزئياً | 1557 | 3 | 0 | 2 | 0 | 0 | ✗ | 23 |
| 96 | `pages/accounting/withdrawal_requests_page.dart` | مرحّلة جزئياً | 976 | 1 | 0 | 0 | 0 | 2 | ✗ | 23 |
| 97 | `ftth/subscriptions/all_subscriptions_details_page.dart` | مرحّلة جزئياً | 398 | 0 | 0 | 0 | 1 | 0 | ✗ | 22 |
| 98 | `ftth/subscriptions/plans_bundles_page.dart` | مرحّلة جزئياً | 620 | 0 | 0 | 0 | 1 | 0 | ✗ | 22 |
| 99 | `ftth/tickets/TKTAT.dart` | مرحّلة جزئياً | 129 | 0 | 0 | 0 | 1 | 0 | ✗ | 22 |
| 100 | `ftth/tickets/tktat_raw_page.dart` | مرحّلة جزئياً | 177 | 0 | 0 | 0 | 1 | 0 | ✗ | 22 |
| 101 | `ftth/transactions/daily_settlement_page.dart` | مرحّلة جزئياً | 1779 | 6 | 0 | 0 | 1 | 1 | ✓ | 22 |
| 102 | `network_quality/pages/advanced_tools_page.dart` | مرحّلة جزئياً | 248 | 11 | 0 | 0 | 0 | 0 | ✓ | 22 |
| 103 | `pages/users_page.dart` | مرحّلة جزئياً | 383 | 0 | 0 | 0 | 1 | 0 | ✗ | 22 |
| 104 | `ftth/reports/zones_page.dart` | مرحّلة جزئياً | 1373 | 1 | 0 | 0 | 3 | 0 | ✓ | 21 |
| 105 | `pages/salary_management_page.dart` | مرحّلة جزئياً | 1391 | 0 | 0 | 0 | 0 | 7 | ✓ | 21 |
| 106 | `pages/accounting/aging_report_page.dart` | مرحّلة جزئياً | 762 | 0 | 0 | 6 | 0 | 0 | ✗ | 21 |
| 107 | `pages/properties/properties_list_page.dart` | مرحّلة جزئياً | 613 | 0 | 0 | 0 | 0 | 2 | ✗ | 21 |
| 108 | `pages/properties/property_form_page.dart` | مرحّلة جزئياً | 934 | 0 | 0 | 0 | 0 | 2 | ✗ | 21 |
| 109 | `sas_agent/premises/ui/premises_form_screen.dart` | مرحّلة جزئياً | 396 | 0 | 0 | 0 | 0 | 2 | ✗ | 21 |
| 110 | `test_pop.dart` | غير مرحّلة | 34 | 0 | 0 | 0 | 1 | 0 | ✗ | 20 |
| 111 | `ftth/reports/data_page.dart` | مرحّلة جزئياً | 123 | 0 | 0 | 0 | 1 | 0 | ✗ | 20 |
| 112 | `pages/super_admin_login_page.dart` | مرحّلة جزئياً | 269 | 0 | 0 | 0 | 0 | 1 | ✗ | 20 |
| 113 | `pages/vps_super_admin_login_page.dart` | مرحّلة جزئياً | 317 | 0 | 0 | 0 | 0 | 1 | ✗ | 20 |
| 114 | `pages/whatsapp_chat_page.dart` | مرحّلة جزئياً | 1050 | 0 | 0 | 0 | 1 | 0 | ✗ | 20 |
| 115 | `pages/accounting/monthly_comparison_page.dart` | مرحّلة جزئياً | 1045 | 1 | 0 | 3 | 0 | 0 | ✗ | 20 |
| 116 | `pages/accounting/plan_profits_page.dart` | مرحّلة جزئياً | 553 | 0 | 0 | 0 | 1 | 0 | ✗ | 20 |
| 117 | `pages/accounting/year_comparison_page.dart` | مرحّلة جزئياً | 1180 | 1 | 0 | 3 | 0 | 0 | ✗ | 20 |
| 118 | `pages/accounting/activation_profitability_page.dart` | مرحّلة جزئياً | 272 | 0 | 0 | 0 | 0 | 1 | ✗ | 18 |
| 119 | `pages/accounting/salaries_page.dart` | مرحّلة جزئياً | 1358 | 0 | 0 | 0 | 0 | 6 | ✓ | 18 |
| 120 | `pages/accounting/sas_accounting_page.dart` | مرحّلة جزئياً | 596 | 0 | 0 | 3 | 0 | 0 | ✗ | 18 |
| 121 | `sas_agent/pages/sas_bulk_import_page.dart` | مرحّلة جزئياً | 1279 | 0 | 0 | 0 | 0 | 6 | ✓ | 18 |
| 122 | `sas_agent/pages/sas_settings_tab.dart` | مرحّلة جزئياً | 901 | 0 | 0 | 0 | 0 | 1 | ✗ | 18 |
| 123 | `task/add_task_api_dialog.dart` | مرحّلة جزئياً | 1673 | 0 | 0 | 0 | 0 | 1 | ✗ | 18 |
| 124 | `main.dart` | غير مرحّلة | 482 | 0 | 0 | 2 | 0 | 0 | ✗ | 17 |
| 125 | `pages/company_diagnostics_page.dart` | مرحّلة جزئياً | 1359 | 0 | 0 | 0 | 0 | 5 | ✓ | 17 |
| 126 | `pages/whatsapp_business_config_page.dart` | مرحّلة جزئياً | 1205 | 0 | 0 | 0 | 0 | 5 | ✓ | 17 |
| 127 | `pages/accounting/fixed_expenses_page.dart` | مرحّلة جزئياً | 976 | 0 | 0 | 0 | 0 | 5 | ✓ | 17 |
| 128 | `pages/hr/employee_profile_page.dart` | مرحّلة جزئياً | 934 | 4 | 0 | 0 | 0 | 3 | ✓ | 17 |
| 129 | `pages/accounting/ftth_operator_transactions_page.dart` | مرحّلة جزئياً | 1086 | 0 | 8 | 0 | 0 | 0 | ✓ | 16 |
| 130 | `inventory/pages/materials_page.dart` | مرحّلة جزئياً | 827 | 0 | 0 | 0 | 0 | 5 | ✓ | 15 |
| 131 | `pages/receipt_template_editor_page.dart` | ملتزمة بالكامل | 1504 | 0 | 0 | 0 | 0 | 0 | ✗ | 15 |
| 132 | `pages/accounting/wallet_transactions_page.dart` | ملتزمة بالكامل | 1339 | 0 | 0 | 0 | 0 | 0 | ✗ | 15 |
| 133 | `sas_agent/pages/sas_reports_page.dart` | ملتزمة بالكامل | 840 | 0 | 0 | 0 | 0 | 0 | ✗ | 15 |
| 134 | `sas_agent/whatsapp/ui/wa_templates_screen.dart` | ملتزمة بالكامل | 395 | 0 | 0 | 0 | 0 | 0 | ✗ | 15 |
| 135 | `task/task_list_screen.dart` | ملتزمة بالكامل | 401 | 0 | 0 | 0 | 0 | 0 | ✗ | 15 |
| 136 | `widgets/auth_guard.dart` | غير مرحّلة | 109 | 0 | 0 | 0 | 0 | 0 | ✗ | 15 |
| 137 | `pages/hr_reports_page.dart` | مرحّلة جزئياً | 1852 | 0 | 0 | 0 | 0 | 2 | ✓ | 14 |
| 138 | `pages/track_users_map_page.dart` | مرحّلة جزئياً | 1101 | 3 | 0 | 0 | 1 | 1 | ✓ | 14 |
| 139 | `pages/employee_tracking_report_page.dart` | مرحّلة جزئياً | 1016 | 5 | 0 | 0 | 0 | 1 | ✓ | 13 |
| 140 | `pages/ftth/fetch_server_data_page.dart` | مرحّلة جزئياً | 2955 | 0 | 0 | 0 | 1 | 1 | ✓ | 12 |
| 141 | `network_quality/pages/wifi_channel_analyzer_page.dart` | مرحّلة جزئياً | 408 | 5 | 0 | 0 | 0 | 0 | ✓ | 10 |
| 142 | `pages/accounting/cash_flow_page.dart` | مرحّلة جزئياً | 681 | 4 | 0 | 2 | 0 | 0 | ✓ | 10 |
| 143 | `inventory/pages/returns_page.dart` | مرحّلة جزئياً | 415 | 0 | 0 | 0 | 0 | 3 | ✓ | 9 |
| 144 | `pages/analysis_page.dart` | مرحّلة جزئياً | 669 | 2 | 0 | 0 | 0 | 1 | ✓ | 9 |
| 145 | `pages/deductions_bonuses_page.dart` | مرحّلة جزئياً | 821 | 0 | 0 | 0 | 0 | 3 | ✓ | 9 |
| 146 | `pages/whatsapp_excel_sender_page.dart` | مرحّلة جزئياً | 456 | 0 | 0 | 0 | 0 | 3 | ✓ | 9 |
| 147 | `pages/accounting/balance_sheet_page.dart` | مرحّلة جزئياً | 687 | 0 | 0 | 9 | 0 | 0 | ✓ | 9 |
| 148 | `pages/accounting/employee_adjustments_page.dart` | مرحّلة جزئياً | 835 | 0 | 0 | 0 | 0 | 3 | ✓ | 9 |
| 149 | `pages/accounting/expenses_page.dart` | مرحّلة جزئياً | 825 | 0 | 0 | 0 | 0 | 3 | ✓ | 9 |
| 150 | `pages/accounting/ftth_operator_linking_page.dart` | مرحّلة جزئياً | 759 | 0 | 0 | 0 | 0 | 3 | ✓ | 9 |
| 151 | `pages/accounting/revenue_page.dart` | مرحّلة جزئياً | 1167 | 0 | 0 | 0 | 0 | 3 | ✓ | 9 |
| 152 | `pages/accounting/zone_maintenance_fees_page.dart` | مرحّلة جزئياً | 575 | 0 | 0 | 0 | 0 | 3 | ✓ | 9 |
| 153 | `sas_agent/pages/sas_reminders_page.dart` | مرحّلة جزئياً | 820 | 0 | 0 | 0 | 0 | 3 | ✓ | 9 |
| 154 | `sas_agent/whatsapp/ui/wa_settings_screen.dart` | مرحّلة جزئياً | 505 | 0 | 0 | 0 | 0 | 3 | ✓ | 9 |
| 155 | `ftth/tickets/tktats_page.dart` | مرحّلة جزئياً | 2293 | 0 | 0 | 0 | 0 | 2 | ✓ | 8 |
| 156 | `network_quality/pages/history_trend_page.dart` | مرحّلة جزئياً | 492 | 4 | 0 | 0 | 0 | 0 | ✓ | 8 |
| 157 | `pages/search_users_page.dart` | ملتزمة بالكامل | 1274 | 0 | 0 | 0 | 0 | 0 | ✓ | 8 |
| 158 | `pages/accounting/trial_balance_page.dart` | مرحّلة جزئياً | 616 | 2 | 0 | 4 | 0 | 0 | ✓ | 8 |
| 159 | `pages/diagnostics/system_diagnostics_page.dart` | مرحّلة جزئياً | 851 | 0 | 0 | 0 | 0 | 2 | ✓ | 8 |
| 160 | `ftth/reports/profits_page.dart` | مرحّلة جزئياً | 3538 | 0 | 0 | 0 | 0 | 2 | ✓ | 6 |
| 161 | `ftth/tickets/create_ticket_page.dart` | مرحّلة جزئياً | 793 | 0 | 0 | 0 | 0 | 2 | ✓ | 6 |
| 162 | `inventory/pages/dispensing_page.dart` | مرحّلة جزئياً | 742 | 0 | 0 | 0 | 0 | 2 | ✓ | 6 |
| 163 | `inventory/pages/invoices_page.dart` | مرحّلة جزئياً | 748 | 0 | 0 | 0 | 0 | 2 | ✓ | 6 |
| 164 | `inventory/pages/purchases_page.dart` | مرحّلة جزئياً | 648 | 0 | 0 | 0 | 0 | 2 | ✓ | 6 |
| 165 | `inventory/pages/stock_levels_page.dart` | مرحّلة جزئياً | 417 | 0 | 0 | 0 | 0 | 2 | ✓ | 6 |
| 166 | `inventory/pages/suppliers_page.dart` | مرحّلة جزئياً | 387 | 0 | 0 | 0 | 0 | 2 | ✓ | 6 |
| 167 | `inventory/pages/warehouses_page.dart` | مرحّلة جزئياً | 346 | 0 | 0 | 0 | 0 | 2 | ✓ | 6 |
| 168 | `network_quality/network_quality_home_page.dart` | مرحّلة جزئياً | 169 | 3 | 0 | 0 | 0 | 0 | ✓ | 6 |
| 169 | `pages/accounting/income_statement_page.dart` | مرحّلة جزئياً | 551 | 1 | 0 | 4 | 0 | 0 | ✓ | 6 |
| 170 | `pages/accounting/period_closing_page.dart` | مرحّلة جزئياً | 376 | 0 | 0 | 3 | 0 | 1 | ✓ | 6 |
| 171 | `pages/accounting/salary_policy_page.dart` | مرحّلة جزئياً | 490 | 0 | 0 | 0 | 0 | 2 | ✓ | 6 |
| 172 | `pages/iptv/iptv_subscribers_page.dart` | مرحّلة جزئياً | 1128 | 0 | 0 | 0 | 0 | 2 | ✓ | 6 |
| 173 | `sas_agent/pages/sas_regions_page.dart` | مرحّلة جزئياً | 482 | 0 | 0 | 0 | 0 | 2 | ✓ | 6 |
| 174 | `pages/accounting/financial_ratios_page.dart` | مرحّلة جزئياً | 636 | 0 | 0 | 5 | 0 | 0 | ✓ | 5 |
| 175 | `pages/citizen_portal/citizen_portal_dashboard.dart` | مرحّلة جزئياً | 391 | 0 | 0 | 0 | 1 | 0 | ✓ | 5 |
| 176 | `sas_agent/sas_agent_page.dart` | مرحّلة جزئياً | 751 | 0 | 0 | 0 | 1 | 0 | ✓ | 5 |
| 177 | `sas_agent/pages/sas_test_message_page.dart` | مرحّلة جزئياً | 728 | 1 | 0 | 0 | 0 | 1 | ✓ | 5 |
| 178 | `network_quality/pages/live_monitor_page.dart` | مرحّلة جزئياً | 376 | 2 | 0 | 0 | 0 | 0 | ✓ | 4 |
| 179 | `network_quality/pages/quality_scan_page.dart` | مرحّلة جزئياً | 441 | 2 | 0 | 0 | 0 | 0 | ✓ | 4 |
| 180 | `ftth/reports/audit_log_page.dart` | مرحّلة جزئياً | 1042 | 0 | 0 | 0 | 0 | 1 | ✓ | 3 |
| 181 | `ftth/subscriptions/expiring_soon_page.dart` | مرحّلة جزئياً | 2540 | 0 | 0 | 0 | 0 | 1 | ✓ | 3 |
| 182 | `inventory/pages/customers_page.dart` | مرحّلة جزئياً | 515 | 0 | 0 | 0 | 0 | 1 | ✓ | 3 |
| 183 | `inventory/pages/dispensing_form_page.dart` | مرحّلة جزئياً | 497 | 0 | 0 | 0 | 0 | 1 | ✓ | 3 |
| 184 | `inventory/pages/invoice_details_page.dart` | مرحّلة جزئياً | 538 | 0 | 0 | 0 | 0 | 1 | ✓ | 3 |
| 185 | `inventory/pages/invoice_form_page.dart` | مرحّلة جزئياً | 1029 | 0 | 0 | 0 | 0 | 1 | ✓ | 3 |
| 186 | `inventory/pages/purchase_form_page.dart` | مرحّلة جزئياً | 627 | 0 | 0 | 0 | 0 | 1 | ✓ | 3 |
| 187 | `inventory/pages/sales_page.dart` | مرحّلة جزئياً | 539 | 0 | 0 | 0 | 0 | 1 | ✓ | 3 |
| 188 | `inventory/pages/vouchers_page.dart` | مرحّلة جزئياً | 331 | 0 | 0 | 0 | 0 | 1 | ✓ | 3 |
| 189 | `pages/leave_management_page.dart` | مرحّلة جزئياً | 864 | 0 | 0 | 0 | 0 | 1 | ✓ | 3 |
| 190 | `pages/whatsapp_batch_reports_page.dart` | مرحّلة جزئياً | 555 | 0 | 0 | 0 | 0 | 1 | ✓ | 3 |
| 191 | `pages/work_schedules_page.dart` | مرحّلة جزئياً | 471 | 0 | 0 | 0 | 0 | 1 | ✓ | 3 |
| 192 | `pages/citizen_portal/citizen_details_page.dart` | مرحّلة جزئياً | 777 | 0 | 0 | 0 | 0 | 1 | ✓ | 3 |
| 193 | `pages/super_admin/add_company_page.dart` | مرحّلة جزئياً | 540 | 0 | 0 | 0 | 0 | 1 | ✓ | 3 |
| 194 | `sas_agent/pages/sas_bulk_message_page.dart` | مرحّلة جزئياً | 753 | 0 | 0 | 0 | 0 | 1 | ✓ | 3 |
| 195 | `sas_agent/premises/ui/premises_list_screen.dart` | مرحّلة جزئياً | 370 | 0 | 0 | 0 | 0 | 1 | ✓ | 3 |
| 196 | `sas_agent/widgets/sas_citizen_statement.dart` | مرحّلة جزئياً | 519 | 0 | 0 | 0 | 0 | 1 | ✓ | 3 |
| 197 | `ftth/users/quick_search_users_page.dart` | مرحّلة جزئياً | 1295 | 1 | 0 | 0 | 0 | 0 | ✓ | 2 |
| 198 | `network_quality/pages/dns_benchmark_page.dart` | مرحّلة جزئياً | 321 | 1 | 0 | 0 | 0 | 0 | ✓ | 2 |
| 199 | `pages/account/account_info_page.dart` | مرحّلة جزئياً | 741 | 1 | 0 | 0 | 0 | 0 | ✓ | 2 |
| 200 | `sas_agent/pages/sas_profits_page.dart` | مرحّلة جزئياً | 341 | 1 | 0 | 0 | 0 | 0 | ✓ | 2 |
| 201 | `ftth/requests/customer_hub_page.dart` | ملتزمة بالكامل | 53 | 0 | 0 | 0 | 0 | 0 | ✓ | 0 |
| 202 | `ftth/tasks/customer_search_connect_page.dart` | ملتزمة بالكامل | 682 | 0 | 0 | 0 | 0 | 0 | ✓ | 0 |
| 203 | `ftth/tasks/ftth_connect_form.dart` | ملتزمة بالكامل | 610 | 0 | 0 | 0 | 0 | 0 | ✓ | 0 |
| 204 | `ftth/tasks/ftth_tasks_page.dart` | ملتزمة بالكامل | 474 | 0 | 0 | 0 | 0 | 0 | ✓ | 0 |
| 205 | `ftth/tickets/customer_tickets_page.dart` | ملتزمة بالكامل | 314 | 0 | 0 | 0 | 0 | 0 | ✓ | 0 |
| 206 | `ftth/tickets/tktat_details_page.dart` | ملتزمة بالكامل | 1236 | 0 | 0 | 0 | 0 | 0 | ✓ | 0 |
| 207 | `inventory/inventory_page.dart` | ملتزمة بالكامل | 451 | 0 | 0 | 0 | 0 | 0 | ✓ | 0 |
| 208 | `inventory/pages/customer_details_page.dart` | ملتزمة بالكامل | 590 | 0 | 0 | 0 | 0 | 0 | ✓ | 0 |
| 209 | `inventory/pages/customer_form_page.dart` | ملتزمة بالكامل | 365 | 0 | 0 | 0 | 0 | 0 | ✓ | 0 |
| 210 | `inventory/pages/inventory_reports_page.dart` | ملتزمة بالكامل | 497 | 0 | 0 | 0 | 0 | 0 | ✓ | 0 |
| 211 | `inventory/pages/movements_page.dart` | ملتزمة بالكامل | 479 | 0 | 0 | 0 | 0 | 0 | ✓ | 0 |
| 212 | `inventory/pages/return_form_page.dart` | ملتزمة بالكامل | 543 | 0 | 0 | 0 | 0 | 0 | ✓ | 0 |
| 213 | `inventory/pages/sale_form_page.dart` | ملتزمة بالكامل | 630 | 0 | 0 | 0 | 0 | 0 | ✓ | 0 |
| 214 | `inventory/pages/voucher_form_page.dart` | ملتزمة بالكامل | 394 | 0 | 0 | 0 | 0 | 0 | ✓ | 0 |
| 215 | `network_quality/pages/device_detail_page.dart` | ملتزمة بالكامل | 486 | 0 | 0 | 0 | 0 | 0 | ✓ | 0 |
| 216 | `network_quality/pages/router_wifi_edit_page.dart` | ملتزمة بالكامل | 517 | 0 | 0 | 0 | 0 | 0 | ✓ | 0 |
| 217 | `pages/aria_page.dart` | ملتزمة بالكامل | 174 | 0 | 0 | 0 | 0 | 0 | ✓ | 0 |
| 218 | `pages/attendance_page.dart` | ملتزمة بالكامل | 798 | 0 | 0 | 0 | 0 | 0 | ✓ | 0 |
| 219 | `pages/charts_page.dart` | ملتزمة بالكامل | 201 | 0 | 0 | 0 | 0 | 0 | ✓ | 0 |
| 220 | `pages/client_setup_page.dart` | ملتزمة بالكامل | 376 | 0 | 0 | 0 | 0 | 0 | ✓ | 0 |
| 221 | `pages/google_drive_files_page.dart` | ملتزمة بالكامل | 235 | 0 | 0 | 0 | 0 | 0 | ✓ | 0 |
| 222 | `pages/hr_hub_page.dart` | ملتزمة بالكامل | 241 | 0 | 0 | 0 | 0 | 0 | ✓ | 0 |
| 223 | `pages/local_subscriber_details_page.dart` | ملتزمة بالكامل | 856 | 0 | 0 | 0 | 0 | 0 | ✓ | 0 |
| 224 | `pages/my_dashboard_page.dart` | ملتزمة بالكامل | 3177 | 0 | 0 | 0 | 0 | 0 | ✓ | 0 |
| 225 | `pages/printer_settings_page.dart` | ملتزمة بالكامل | 226 | 0 | 0 | 0 | 0 | 0 | ✓ | 0 |
| 226 | `pages/reminder_reports_page.dart` | ملتزمة بالكامل | 179 | 0 | 0 | 0 | 0 | 0 | ✓ | 0 |
| 227 | `pages/settings_page.dart` | ملتزمة بالكامل | 239 | 0 | 0 | 0 | 0 | 0 | ✓ | 0 |
| 228 | `pages/settings_text_scale_page.dart` | ملتزمة بالكامل | 146 | 0 | 0 | 0 | 0 | 0 | ✓ | 0 |
| 229 | `pages/statistics_page.dart` | ملتزمة بالكامل | 667 | 0 | 0 | 0 | 0 | 0 | ✓ | 0 |
| 230 | `pages/users_page_vps.dart` | ملتزمة بالكامل | 1961 | 0 | 0 | 0 | 0 | 0 | ✓ | 0 |
| 231 | `pages/user_details_page.dart` | ملتزمة بالكامل | 761 | 0 | 0 | 0 | 0 | 0 | ✓ | 0 |
| 232 | `pages/whatsapp_conversations_page.dart` | ملتزمة بالكامل | 725 | 0 | 0 | 0 | 0 | 0 | ✓ | 0 |
| 233 | `pages/accounting/audit_trail_page.dart` | ملتزمة بالكامل | 435 | 0 | 0 | 0 | 0 | 0 | ✓ | 0 |
| 234 | `pages/accounting/hr_reports_page.dart` | ملتزمة بالكامل | 856 | 0 | 0 | 0 | 0 | 0 | ✓ | 0 |
| 235 | `pages/accounting/system_audit_page.dart` | ملتزمة بالكامل | 613 | 0 | 0 | 0 | 0 | 0 | ✓ | 0 |
| 236 | `pages/announcements/announcements_page.dart` | ملتزمة بالكامل | 932 | 0 | 0 | 0 | 0 | 0 | ✓ | 0 |
| 237 | `pages/chat/chat_rooms_page.dart` | ملتزمة بالكامل | 1464 | 0 | 0 | 0 | 0 | 0 | ✓ | 0 |
| 238 | `pages/diagnostics/permissions_diagnostics_page.dart` | ملتزمة بالكامل | 898 | 0 | 0 | 0 | 0 | 0 | ✓ | 0 |
| 239 | `pages/ftth/ftth_company_page.dart` | ملتزمة بالكامل | 385 | 0 | 0 | 0 | 0 | 0 | ✓ | 0 |
| 240 | `pages/super_admin/edit_company_page.dart` | ملتزمة بالكامل | 571 | 0 | 0 | 0 | 0 | 0 | ✓ | 0 |
| 241 | `pages/super_admin/tenant_features_page.dart` | ملتزمة بالكامل | 363 | 0 | 0 | 0 | 0 | 0 | ✓ | 0 |
| 242 | `sas_agent/pages/sas_admin_agents_page.dart` | ملتزمة بالكامل | 473 | 0 | 0 | 0 | 0 | 0 | ✓ | 0 |
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
