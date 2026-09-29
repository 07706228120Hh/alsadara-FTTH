# SAS4 for developers — المرجع الكامل (مستخرج من Postman)

المصدر: https://documenter.getpostman.com/view/11765341/U16byA2y
تاريخ الاستخراج: 2026-09-27

## فهرس المجلدات

- Authorization (2)
- After Authorization Details (3)
- Dashboard (0)
- User Portal (user panel) (17)
- Users - List (17)
- Users - Form (9)
- Users - Online List (3)
- Managers (14)
- Profiles (1)

## المقدمة العامة

SASv4 is a complete billing system which offers a variety of different features to suit any ISP's needs also ISP's who want power and flexibility to meet the needs of their changing technical environment and growing user base, enabling ISP managers to take full control over their precious resources and network elements.
SASv4 is an AAA server is a server program that handles user requests to access computer resources, and for an enterprise, this server provides authentication, authorization, and accounting (AAA) services. The AAA server typically interacts with network access and gateway servers and with databases and directories containing user information.
SASv4 API specifications allow ISP to develop API endpoints that can then be accessed by API users (e.g., third-party developers) to build mobile and web applications for their customers.

### Authentication

Authentication to the SASv4 API is performed via JWT Bearer Authentication. Every endpoint requires authentication, so you will need to add the following header to each request:
Authorization: Bearer

### POST Request Encryption

SAS4 requires encryption for all POST request. The encryption method is AES and can be found in many libraries such as CryptoJS which is used in SAS4. The POST payload has be encapsulated into a single parameter called 'payload'. The 'payload' param will hold the actual encrypted payload. See the example of our SAS4 connector which is implemented in PHP on SAS4-connector the following expmale show this process through Node.js (you can check this script on GitHub for further info in NodeJs) :

```
const request = require('request');
const CryptoJS = require("crypto-js");
const form = {user: 'admin', password: 'snonosystems'};
const cypData = CryptoJS.AES.encrypt(JSON.stringify(form), 'abcdefghijuklmno0123456789012345');
const options = {
    url: 'http://demo4.sasradius.com/admin/api/index.php/api/login',
    json: true,
    body: {
        payload: cypData.toString();
    }
};
request.post(options, (err, res, body) => {
    if (err) {
        return console.log(err);
    }
    console.log(`Status: ${res.statusCode}`);
    console.log(body);
});
```

the obove code will generate encryption text of the form that will produce the following code :

```
{ 
   payload:   'U2FsdGVkX19TGvGsXp3eR8h/fVKdKbm4tzbrEmk7s0xsrhjKy6VybasH8b7xu6xYDcvDjNk6ulb/dVoq2J417uRhJozvbPuSfkSaXD/f644=' 
}
```

### Data Types

All of the Open Banking Nigeria API responses returned are in JSON format, with these data types defined below:

| Type | Description |

| string | A UTF-8 encoded string |

| number | An integer |

| datetime | An ISO8601 encoded DateTime. All datetimes are returned in UTC with offset +00:00 |

| decimal | All monetary values are returned with up to two decimal places and may be positive (20.78) or negative (-32.50) |

### Pagination

For section which include lists that provide several records, the response may be paged depending on the total number of records that the server can return at a time. This means that to retrieve the full set of items for a given resource you may be required to make several requests. For more info you can check Laravel Pagination

### URL Parameters

| Parameters | Description |

| page | number The page number you wish to retrieve |

| count | number The number of items to return in a request |

| sortBy | string A field name data will be sorted by |

| diraction | string Sort direction (asc/desc) |

| columns | array (optional) column names to retrieve |

### Response

| Field | Type |

| current_page | number |

| data | array |

| first_page_url | string |

| from | number |

| last_page | number |

| last_page_url | string |

| next_page_url | string |

| path | string |

| per_page | number |

| prev_page_url | string |

| to | number |

| total | number |

### Navigating through pages

- If you are on the first page, the "prev_page_url" link will not be present in the response.
- If you are at the final page, the "next_page_url" link will not be present in the response
- If there are no pages and all data is returned neither "prev_page_url" or "next_page_url" links will be present in the response

### Errors

Errors in SAS4 API are expressed as a combination of HTTP status codes and an accompanying JSON body providing required detail where possible. You should be able to rely on the HTTP status code alone to determine the cause of the problem.

### Error Response Fields

| Field | Type | Description |

| message | string | A human-readable message as to the specifics of the problem. For example, it may contain a detail description of what caused the problem |

| status | number | The HTTP status code used in the response |

### Error Response codes

| Status | Code | Description |

| 200 | -1 | Error |


---

## المجلد: Authorization

JWT uses access tokens for accessing APIs. A token represents a permission granted to a client to access some protected resources. The method to acquire a token is called grant.
There are different types of JWT grants. SAS4 for Developers uses the Client Credentials Grant.

### 1. Access Granted Client Credentials

**Method:** `POST`  
**URL:** `http://demo4.sasradius.com/admin/api/index.php/api/login`  
**Auth:** noauth

**الوصف (كما في التوثيق):**

To request an access token you need to send a POST request encrypted with CryptoJS for the following body parameters to the authorization server:

- "payload" it must be encrypt the following parameters in JSON format:
- user manager username.
- password manager password.
- language site language

decrypted payload JSON use in example : {"username":"admin","password":"snonosystems","language":"en"}

**Body (urlencoded):**
- `username` = `admin`
- `password` = `admin`

**مثال استجابة: Access Granted Client Credentials** — HTTP 200 OK
- Request URL: `http://demo4.sasradius.com/admin/api/index.php/api/login`
- Request body: `username=admin`, `password=admin`
- Content-Type: application/json
```json
{
    "status": 200,
    "token": "<JWT_TOKEN>"
}
```

### 2. Get Token Information

**Method:** `GET`  
**URL:** `http://{{IP-or-Domain}}/admin/api/index.php/api/auth`  
**Auth:** bearer

**الوصف (كما في التوثيق):**

Retrieves information about an existing token. The token is passed as Request Header parameter, for example:
authorization: Bearer {{access_token}}

**Body (urlencoded):**


**مثال استجابة: Get Token Information** — HTTP 200 OK
- Request URL: `http://demo4.sasradius.com/admin/api/index.php/api/auth`
- Content-Type: application/json
```json
{
    "status": 200,
    "client": {
        "id": 1,
        "username": "admin",
        "enabled": 1,
        "city": "Baghdad",
        "country": "Iraq",
        "firstname": "Administrator",
        "lastname": "Snono",
        "email": "admin@gmail.com",
        "phone": null,
        "company": null,
        "address": null,
        "balance": "0.000",
        "debt_limit": null,
        "subscriber_suffix": null,
        "subscriber_prefix": null,
        "notes": null,
        "manager_id": 1,
        "mobile_auth_secret": null,
        "max_users": null,
        "mikrotik_addresslist": null,
        "created_at": "2017-07-26 09:54:49",
        "updated_at": "2019-07-25 08:55:46",
        "deleted_at": null,
        "acl_group_id": 1,
        "site_id": null,
        "avatar": null,
        "parent_id": 0,
        "created_by": 0,
        "reward_points": 0,
        "discount_rate": "0.00",
        "avatar_data": ""
    },
    "permissions": [
        "prm_any",
        "prm_backup_create",
        "prm_backup_delete",
        "prm_backup_download",
        "prm_backup_restore",
        "prm_backup_upload",
        "prm_cards_change_owner",
        "prm_cards_delete",
        "prm_cards_designer",
        "prm_cards_download",
        "prm_cards_generate_refill",
        "prm_cards_generate_user",
        "prm_cards_index",
        "prm_cards_job_cancel",
        "prm_cards_list",
        "prm_cards_suspend_release",
        "prm_cards_verify",
        "prm_dashboard_manager",
        "prm_widget_factory",
        "prm_managers_change_self_password",
        "prm_managers_create",
        "prm_managers_delete",
        "prm_managers_deposit",
        "prm_managers_index",
        "prm_managers_invoice",
        "prm_managers_journal",
        "prm_managers_login_as",
        "prm_managers_receipt",
        "prm_managers_sysadmin",
        "prm_managers_update",
        "prm_managers_withdrawal",
        "prm_managers_export",
        "prm_managers_rename",
        "prm_nas_create",
        "prm_nas_delete",
        "prm_nas_index",
        "prm_nas_update",
        "prm_nas_export",
        "prm_profiles_create",
        "prm_profiles_delete",
        "prm_profiles_index",
        "prm_profiles_pricing",
        "prm_profiles_update",
        "prm_profiles_policy_manager",
        "prm_report_managers_invoices",
        "prm_report_managers_journal",
        "prm_report_syslog",
        "prm_report_user_auth_log",
        "prm_report_activations",
        "prm_settings",
        "prm_sites_management",
        "prm_users_activate",
        "prm_users_activate_card",
        "prm_users_activate_credit",
        "prm_users_activate_user_balance",
        "prm_users_advanced",
        "prm_users_cancel_profile_change",
        "prm_users_change_profile",
        "prm_users_create",
        "prm_users_delete",
        "prm_users_deposit",
        "prm_users_disconnect",
        "prm_users_history",
        "prm_users_index",
        "prm_users_index_all",
        "prm_users_invoice",
        "prm_users_journal",
        "prm_users_mac_lock",
        "prm_users_ping",
        "prm_users_rename",
        "prm_users_reset_quota",
        "prm_users_sessions_index",
        "prm_users_update",
        "prm_users_withdrawal",
        "prm_users_export",
        "prm_users_extend",
        "prm_tools_announcements",
        "prm_tools_import",
        "prm_billing",
        "prm_ucp_activate",
        "prm_ucp_auto_login",
        "prm_ucp_billing",
        "prm_ucp_browse_packages",
        "prm_ucp_change_info",
        "prm_ucp_change_password",
        "prm_ucp_change_profile",
        "prm_ucp_data_usage",
        "prm_ucp_extend",
        "prm_ucp_login",
        "prm_ucp_sessions",
        "prm_ucp_support",
        "prm_report_sessions",
        "prm_report_users",
        "prm_any"
    ],
    "features": [
        "sastrack",
        "freezone"
    ],
    "license_status": "1",
    "license_expiration": "2021-06-02 09:57:16"
}
```


---

## المجلد: After Authorization Details

After grant access token there is much detail to request in order to load the view.
SAS4 is permission based system wich mean that all it details come with permission given to manager through group of limitation permission that limit access.

### 3. Available Transulations

**Method:** `GET`  
**URL:** `http://{{IP-or-Domain}}/admin/api/index.php/api/resources/languages`  
**Auth:** bearer

**الوصف (كما في التوثيق):**

Retrieves all language that site can transulate for it.

**مثال استجابة: Available Transulation** — HTTP 200 OK
- Request URL: `http://demo4.sasradius.com/admin/api/index.php/api/resources/languages`
- Content-Type: application/json
```json
{
    "status": 200,
    "data": [
        {
            "id": "ar",
            "name": "Arabic",
            "direction": "rtl",
            "author": "hasanen@snono-systems.com",
            "font": "Arial"
        },
        {
            "id": "en",
            "name": "English",
            "direction": "ltr",
            "author": "hasanen@snono-systems.com",
            "font": "Arial"
        },
        {
            "id": "pt",
            "name": "Português",
            "direction": "ltr",
            "author": "renda@inforomba.net",
            "font": "Arial"
        },
        {
            "id": "tr",
            "name": "Turkish",
            "direction": "ltr",
            "author": "safa@teknobilgroup.com",
            "font": "Arial"
        }
    ]
}
```

### 4. Tansulation File

**Method:** `GET`  
**URL:** `http://{{IP-or-Domain}}/admin/api/index.php/api/resources/language/en`  
**Auth:** bearer

**الوصف (كما في التوثيق):**

Retrieves all site transulation that will apear in view, such as menu, table details names and form fields names .... etc

**مثال استجابة: Tansulation File** — HTTP 200 OK
- Request URL: `http://demo4.sasradius.com/admin/api/index.php/api/resources/language/en`
- Content-Type: text/html; charset=UTF-8
```json
{
  "info": {
    "id": "en",
    "name": "English",
    "direction": "ltr",
    "author": "hasanen@snono-systems.com",
    "font": "Arial"
  },
  "words": {

    "global_all": "Any",
    "global_username":  "Username",
    "global_expiration":  "Expiration",
    "global_profile":  "Profile",
    "global_firstname": "First Name",
    "global_lastname": "Last Name",
    "global_available_balance": "Available Balance",
    "global_total": "Total",
    "global_reload": "Reload",
    "global_download": "Download",
    "global_date": "Date",
    "global_manager": "Manager",
    "global_price": "Price",
    "global_filter_from_date": "From Date",
    "global_filter_to_date": "To Date",
    "global_ip": "IP",
    "global_description": "Description",
    "global_comment": "Comment",
    "global_filter_all_managers": "All Managers",
    "global_filter_daily": "Daily",
    "global_filter_monthly": "Monthly",
    "global_filter_paid": "Paid",
    "global_filter_unpaid": "Unpaid",

    "label_about": "Company",
    "label_about_hardware": "Hardware",
    "label_snono_messages": "Vendor Messages",
    "label_welcome_screen_header": "Announcement",

    "menu_dashboard": "Dashboard",
    "menu_settings": "Settings",
    "menu_managers":  "Managers",
    "menu_settings_general": "general settings",
    "menu_settings_acl": "permission groups",
    "menu_settings_ucp": "user portal",
    "menu_users": "Users",
    "menu_users_list": "Users List",
    "menu_users_online": "Online Users",
    "menu_users_tickets": "Support Tickets",
    "menu_nas": "NAS",
    "menu_profiles": "Profiles",
    "menu_profiles_list": "Profiles List",
    "menu_profiles_pricing": "Pricing List",
    "menu_profiles_usage_notifications": "Usage Notifications",
    "menu_cards": "Cards System",
    "menu_settings_sites": "sites",
    "menu_reports": "Reports",
    "menu_reports_syslog": "System Log",
    "menu_reports_managers_journal": "Managers Journal",
    "menu_reports_managers_invoices": "Managers Invoices",
    "menu_reports_managers_receipts": "Managers Receipts",
    "menu_reports_user_auth_log": "User Auth Log",
    "menu_reports_activations": "Activations",
    "menu_reports_activations_stats": "Activation Statistics",
    "menu_reports_profits": "Profits",
    "menu_reports_sessions": "Sessions",
    "menu_report_users": "Users",
    "menu_reports_traffic": "Traffic",
    "menu_reports_online": "Online History",
    "menu_reports_money_transfer": "Money Transfers",
    "menu_reports_cards_usage": "Cards Usage",
    "menu_reports_radius_log": "Radius Log",
    "menu_tools": "Tools",
    "menu_tools_backup": "Backup",
    "menu_tools_dashboard_manager": "Dashboard Manager",
    "menu_tools_widget_factory":  "Widget Factory",
    "menu_tools_system_services": "System Services",
    "menu_tools_system_update": "System Update",
    "menu_tools_maintenance": "Maintenance",
    "menu_tools_announcements": "Announcements",
    "menu_tools_export": "Export",
    "menu_tools_import": "Import Data",
    "menu_tools_bulk_changes": "Bulk Changes",
    "menu_settings_freezone": "free zone",
    "menu_settings_sms": "sms",
    "menu_settings_email": "email",
    "menu_settings_email_template": "email templates",
    "menu_settings_backup": "backup",
    "menu_settings_license": "license",
    "menu_settings_notifications": "notifications",
    "menu_settings_network": "network",
    "menu_settings_advanced": "advanced",
    "menu_settings_portal": "web",
    "menu_settings_sastrack": "sastrack",
    "menu_settings_payment_gateways": "payment gateways",
    "menu_settings_billing": "postpaid billing",
    "menu_settings_telegram": "telegram",
    "menu_settings_usage_notifications": "data usage notifications",
    "menu_billing": "Billing",
    "menu_billing_user_invoices": "User Invoices",
    "menu_billing_user_invoice_issue": "Issue Invoice",
    "menu_ip_pools": "IP Pools",
    "menu_about": "About",
    "menu_bandwidth_controller": "Bandwidth Controller",

    "managers_table_title": "Managers List",
    "managers_table_balance": "Balance",
    "managers_table_group": "Group",
    "managers_table_parent": "Parent",
    "managers_table_city": "City",
    "managers_table_creation_date": "Creation Date",
    "managers_table_users_count": "Users",
    "managers_table_reward_points": "Reward Points",

    "users_table_online_title": "Online Users",
    "users_table_title": "Users Table",
    "users_table_status": "Status",
    "users_table_username": "Username",
    "users_table_firstname": "First Name",
    "users_table_lastname": "Last Name",
    "users_table_expiration": "Expiration",
    "users_table_parent": "Parent",
    "users_table_profile": "Profile",
    "users_table_balance": "Balance",
    "users_table_daily_traffic" : "Daily Traffic",
    "users_table_city": "City",
    "users_table_static_ip": "Static IP",
    "users_table_notes": "Notes",
    "users_table_last_online": "Last Online",
    "users_table_dl": "Download",
    "users_table_ul": "Upload",
    "users_table_daily_usage": "Daily Quota",
    "users_table_uptime": "Uptime",
    "users_table_hardware": "Device",
    "users_table_service_name": "Service",
    "users_table_simultaneous_sessions": "Simultaneous Sessions",
    "users_table_company": "Company",
    "users_table_used_traffic": "Used Traffic",
    "users_table_phone": "Phone",
    "users_table_address": "Address",
    "users_tab_freezone_traffic": "FreeZone Traffic",

    "users_action_activate": "Activate",
    "users_action_change_profile": "Change Profile",
    "users_action_disconnect": "Disconnect",
    "users_action_issue_invoice": "Issue Invoice",
    "users_action_view": "Overview",
    "users_action_lock_mac": "Lock MAC",
    "users_action_ping": "Ping",
    "users_action_extend": "Extend Service",
    "users_action_cancel": "Cancel Service",

    "users_filter_status": "Status",
    "users_filter_connection": "Connection",
    "users_filter_profile": "Profile",
    "users_filter_profile_active": "Active Profile",
    "users_filter_parent": "Parent",
    "users_filter_sub_users": "Sub-Users",

    "users_status_active": "Active",
    "users_status_expired": "Expired",
    "users_status_expiring_soon": "Expiring Soon",
    "users_status_expiring_today": "Expiring Today",
    "users_status_online": "Online",
    "users_status_disabled": "Disabled",
    "users_status_traffic_depleted": "Depleted",
    "users_status_offline": "Offline",

    "users_tab_overview": "Overview",
    "users_tab_edit": "Edit",
    "users_tab_traffic": "Traffic",
    "users_tab_sessions": "Sessions",
    "users_tab_invoices": "Invoices",
    "users_tab_payments": "Payments",
    "users_tab_history": "History",
    "users_tab_documents": "Documents",
    "users_tab_radius": "RADIUS",
    "users_tab_journal": "Journal",

    "user_depodrawal_form_title_withdrawal": "Deduct Amount",
    "user_depodrawal_form_title_deposit": "Deposit Amount",
    "user_depodrawal_form_username": "Username",
    "user_depodrawal_form_amount": "Amount",
    "user_depodrawal_form_comment": "Comment",

    "user_ping_dialog_title": "Ping User",


    "user_form_label": "User Form",
    "user_form_label_basic_information": "Basic Information",
    "user_form_label_username": "Username",
    "user_form_label_enabled": "Enabled",
    "user_form_label_password": "Password",
    "user_form_label_password_confirm": "Confirm Password",
    "user_form_label_profile": "Service Profile",
    "user_form_label_parent": "Parent",
    "user_form_label_site": "Site",
    "user_form_label_mac_lock": "MAC Lock",
    "user_form_label_firstname": "First Name",
    "user_form_label_lastname": "Last Name",
    "user_form_label_company": "Company",
    "user_form_label_email": "Email",
    "user_form_label_phone": "Phone",
    "user_form_label_city": "City",
    "user_form_label_address": "Address",
    "user_form_label_apartment": "Apartment",
    "user_form_label_street": "Street",
    "user_form_label_contract": "Contract ID",
    "user_form_label_national_id": "National ID",
    "user_form_label_notes": "Notes",
    "user_form_label_expiration": "Expiration",
    "user_form_label_user_type": "User Type",
    "user_form_label_personnel_information": "Personnel Information",
    "user_form_label_advanced": "Advanced Details",
    "user_form_label_mac_list": "Allowed MACs",

    "user_mac_dialog_title": "Allowed MACs",
    "user_mac_dialog_no_records": "No Records Found",

    "user_rename_form_title": "Rename User",
    "user_rename_form_current_username": "Current Username",
    "user_rename_form_new_username": "New Username",

    "user_overview_owner": "Owner",
    "user_overview_profile": "Profile",
    "user_overview_expiration": "Expiration",
    "user_overview_pin_tries": "Incorrect PIN tries",
    "user_overview_status": "Status",
    "user_overview_last_login": "Last Login",
    "user_overview_remaining_download": "Remaining Download",
    "user_overview_remaining_upload": "Remaining Upload",
    "user_overview_remaining_traffic": "Remaining Traffic",
    "user_overview_remaining_uptime": "Remaining Uptime",
    "user_overview_purchases": "Total Purchases",
    "user_overview_created_on": "Created On",
    "user_overview_created_by": "Created By",

    "user_activate_title": "Activation Information",
    "user_activate_username": "Username",
    "user_activate_price": "Unit Price",
    "user_activate_profile": "Profile",
    "user_activate_duration": "Duration",
    "user_activate_expiration": "Expiration",
    "user_activate_download": "Download (MB)",
    "user_activate_upload": "Upload (MB)",
    "user_activate_balance": "Available Balance",
    "user_activate_user_balance": "User's Balance",
    "user_activate_traffic": "Total Traffic",
    "user_activate_money_collected": "Money Collected",
    "user_activate_method": "Activation Method",
    "user_activate_profile_description": "Profile Description",
    "user_activate_card_number": "Card Number",
    "user_activate_vat": "VAT",
    "user_activate_required_amount": "Required Amount",
    "user_activate_total_required_amount": "Total Price",
    "user_activate_success_activation": "Users Activated",
    "user_activate_fail_activation": "Users Failed To Activated",
    "user_activate_reward_points_given": "Rewarded Points",
    "user_activate_reward_points_required": "Points Required",
    "user_activate_reward_points_balance": "Reward Points Balance",
    "user_activate_rewards_title": "Reward Points",
    "user_activation_confirm_title": "Confirm Activation",
    "user_activation_issue_invoice_confirm": "Issue an invoice for the user",
    "user_activation_issue_invoice_note": "Invoice will be available in user invoices page.",

    "user_cancellation_form_title": "Cancel Service",
    "user_cancellation_title": "Cancellation Details",
    "user_cancellation_last_price": "Last Activation Price",
    "user_cancellation_activated_at": "Activation Date",
    "user_cancellation_remaining_days": "Remaining Days",
    "user_cancellation_refund_amount": "Refund Amount",

    "user_extend_form_title": "Extend Service",
    "user_extend_form_select_extension": "Select Extension",
    "user_extension_method": "Extend Using",

    "user_change_profile_title": "Change User Profile",
    "user_change_profile_expires_on": "Expires On",
    "user_change_profile_new": "New Profile",
    "user_change_profile_current": "Current Profile",
    "user_change_type": "When to Change",
    "user_change_warning1": "User already active. Profile change will be applied on next expiration date",
    "user_change_warning2": "User already active. Changing profile will terminate current service and resets the user",
    "user_change_option_immediate": "Immediate",
    "user_change_option_schedule": "On Next Expiration",

    "user_session_table_started": "Started On",
    "user_session_table_ended": "Ended On",
    "user_session_table_ip": "IP",
    "user_session_table_download": "Download",
    "user_session_table_upload": "Upload",
    "user_session_table_mac": "MAC",
    "user_session_table_profile": "Profile",
    "user_session_table_service": "Service",
    "user_session_table_protocol": "Protocol",

    "user_invoice_table_number": "Invoice No",
    "user_invoice_table_date": "Date",
    "user_invoice_table_type": "Type",
    "user_invoice_table_amount": "Amount",
    "user_invoice_table_description": "Description",
    "user_invoice_table_username": "Username",
    "user_invoice_table_created_by": "Created By",
    "user_invoice_table_method": "Payment Method",
    "user_invoice_table_paid": "Paid",

    "user_receipt_table_no": "Receipt No",
    "user_receipt_table_date": "Date",
    "user_receipt_table_type": "Type",
    "user_receipt_table_amount": "Amount",
    "user_receipt_table_description": "Description",
    "user_receipt_table_created_by": "Created By",

    "user_document_table_name": "Document Name",
    "user_document_table_size": "Size",
    "user_document_table_date": "Date",

    "user_history_table_date": "Date",
    "user_history_table_action": "Action",
    "user_history_table_description": "Description",
    "user_history_table_created_by": "Created By",

    "user_journal_table_date": "Date",
    "user_journal_table_cr": "CR",
    "user_journal_table_dr": "DR",
    "user_journal_table_amount": "Amount",
    "user_journal_table_balance": "Balance",
    "user_journal_table_operation": "Operation",
    "user_journal_table_description": "Description",

    "nas_form_label1": "Basic Information",
    "nas_form_name": "Name",
    "nas_form_enabled": "Enabled",
    "nas_form_ip_address": "IP Address",
    "nas_form_secret": "Shared Secret",
    "nas_form_type": "Type",
    "nas_form_version": "Version",
    "nas_form_api_username": "API Username",
    "nas_form_api_password": "API Password",
    "nas_form_coa_port": "Incoming (COA) Port",
    "nas_form_site": "Site",
    "nas_form_ip_accounting": "IP Accounting",
    "nas_form_http_port": "HTTP Port",
    "nas_form_pool": "Pool Name (optional)",
    "nas_form_description": "Description",
    "nas_form_api_port": "API Port",
    "nas_form_monitor": "Monitor (ping)",
    "nas_form_snmp_community": "SNMP Community",

    "manager_form_label1": "Basic Information",
    "manager_form_username": "Username",
    "manager_form_enabled": "Enabled",
    "manager_form_password": "Password",
    "manager_form_password_confirm": "Confirm Password",
    "manager_form_security_group": "Security Group",
    "manager_form_parent": "Parent",
    "manager_form_label2": "Personnel Information",
    "manager_form_firstname": "First Name",
    "manager_form_lastname": "Last Name",
    "manager_form_company": "Company",
    "manager_form_email": "Email",
    "manager_form_phone": "Phone",
    "manager_form_city": "City",
    "manager_form_address": "Address",
    "manager_form_notes": "Notes",
    "manager_form_label3": "Advanced Information",
    "manager_form_prefix": "Subscribers Prefix",
    "manager_form_suffix": "Subscribers Suffix",
    "manager_form_max_users": "Max number of users",
    "manager_form_site": "Site",
    "manager_form_deb_limit": "Debt Limit",
    "manager_form_discount_rate": "Discount Rate (%)",
    "manager_form_label_allowed_ppp_services": "Allowed PPP Services",
    "manager_form_admin_notes": "Admin Notes",
    "manager_ppp_dialog_title": "Allowed PPP Services",
    "manager_form_label4": "Manager Limits",
    "manager_form_limit_delete": "Limit Deletes",
    "manager_form_limit_rename": "Limit Renames",
    "manager_form_limit_profile_change": "Limit Profiles Changes",
    "manager_form_limit_delete_count": "Monthly Deletes",
    "manager_form_limit_rename_count": "Monthly Renames",
    "manager_form_limit_profile_change_count": "Monthly Profile Changes",
    "manager_form_limit_mac_change": "Limit MAC changes",
    "manager_form_limit_mac_change_count": "Monthly MAC Changes",

    "managers_tab_overview": "Overview",
    "managers_tab_edit": "Edit",
    "managers_tab_invoices": "Invoices",
    "managers_tab_payments": "Receipts",
    "managers_tab_journal": "Journal",

    "manager_overview_balance": "Balance",
    "manager_overview_owner": "Owner",
    "manager_overview_acl_group": "ACL Group",
    "manager_overview_status": "Status",
    "manager_overview_total_users": "Total Users",
    "manager_overview_active_users": "Active Users",
    "manager_overview_expired_users": "Expired Users",
    "manager_overview_submanagers": "Sub-Managers",
    "manager_overview_created_on": "Created On",
    "manager_overview_created_by": "Created By",

    "manager_invoice_table_title": "Managers Invoices",
    "manager_invoice_table_number": "Invoice No",
    "manager_invoice_table_date": "Date",
    "manager_invoice_table_type": "Type",
    "manager_invoice_table_amount": "Amount",
    "manager_invoice_table_description": "Description",
    "manager_invoice_table_username": "Username",
    "manager_invoice_table_created_by": "Issued By",
    "manager_invoice_table_method": "Payment Method",
    "manager_invoice_table_paid": "Paid",
    "manager_invoice_filter_status": "Invoice Status",
    "manager_invoice_action_pay": "Pay Invoice",
    "prompt_invoices_pay": "Mark selected invoice as paid ?",

    "manager_receipt_table_no": "Receipt No",
    "manager_receipt_table_date": "Date",
    "manager_receipt_table_type": "Type",
    "manager_receipt_table_amount": "Amount",
    "manager_receipt_table_description": "Description",
    "manager_receipt_table_created_by": "Created By",

    "manager_journal_table_date": "Date",
    "manager_journal_table_cr": "CR",
    "manager_journal_table_dr": "DR",
    "manager_journal_table_amount": "Amount",
    "manager_journal_table_balance": "Balance",
    "manager_journal_table_operation": "Operation",
    "manager_journal_table_description": "Description",

    "manager_depodrawal_form_title_withdrawal": "Deduct Amount",
    "manager_depodrawal_form_title_deposit": "Deposit Amount",
    "manager_depodrawal_form_username": "Username",
    "manager_depodrawal_form_amount": "Amount",
    "manager_depodrawal_form_comment": "Comment",

    "mangers_tree_title": "Managers Tree",

    "manager_rename_form_title": "Rename Manager",
    "manager_rename_form_current_username": "Current Username",
    "manager_rename_form_new_username": "New Username",

    "manager_profile_label_account": "Account Information",
    "manager_profile_label_image": "Profile Image",
    "manager_profile_btn_password": "Change Password",
    "manager_profile_placeholder_new_password": "new password",
    "manager_profile_placeholder_confirm_password": "confirm password",
    "manager_profile_image_change": "change",

    "manager_actions_add_reward_points": "Add Reward Points",
    "manager_actions_deduct_reward_points": "Deduct Reward Points",

    "prm_any": "Dummy Permission",
    "prm_backup_create": "Backup - Create",
    "prm_backup_delete": "Backup - Delete",
    "prm_backup_download": "Backup - Download",
    "prm_backup_restore": "Backup - Restore",
    "prm_backup_upload": "Backup - Upload",

    "prm_billing": "Billing",
    "prm_cards_change_owner": "Cards - Change Owner",
    "prm_cards_delete": "Cards - Delete",
    "prm_cards_designer": "Cards - Designer",
    "prm_cards_download": "Cards - Download",
    "prm_cards_generate_refill": "Cards - Generate Refill Cards",
    "prm_cards_generate_user": "Cards - Generate Prepaid User Cards",
    "prm_cards_job_cancel": "Cards - Cancel Generator",
    "prm_cards_index": "Cards - Series Index",
    "prm_cards_suspend_release": "Cards - Suspend & Release",
    "prm_cards_list": "Cards - List PINs",
    "prm_cards_verify": "Cards - Verify Cards",
    
    "prm_dashboard_manager": "Dashboard - Manage",
    "prm_managers_change_self_password": "Managers - Change Self Password",
    "prm_managers_create": "Managers - Create",
    "prm_managers_delete": "Managers - Delete",
    "prm_managers_deposit": "Managers - Deposit Money",
    "prm_managers_index": "Managers - Index",
    "prm_managers_index_all": "Managers - Index (All Managers)",
    "prm_managers_invoice": "Managers - Show Invoices",
    "prm_managers_journal": "Managers - Show Journal",
    "prm_managers_login_as": "Managers - Login As (Dangerous!)",
    "prm_managers_receipt": "Managers - Show Receipts",
    "prm_managers_sysadmin": "Managers - System Administrator",
    "prm_managers_update": "Managers - Edit / Update",
    "prm_managers_withdrawal": "Managers - Withdraw Money",
    "prm_managers_export": "Managers - Export to Excel",
    "prm_managers_rename": "Managers - Rename",
    "prm_nas_create": "NAS - Create",
    "prm_nas_delete": "NAS - Delete",
    "prm_nas_index": "NAS - Index",
    "prm_nas_update": "NAS - Update",
    "prm_nas_export": "NAS - Export",
    "prm_profiles_create": "Profiles - Create",
    "prm_profiles_delete": "Profiles - Delete",
    "prm_profiles_index": "Profiles - Index",
    "prm_profiles_policy_manager": "Profiles - Policy Manager",
    "prm_profiles_pricing": "Profiles - Pricing Management",
    "prm_profiles_update": "Profiles - Update",
    "prm_report_managers_invoices": "Reports - Managers Invoices",
    "prm_report_managers_journal": "Reports - Managers Journal",
    "prm_report_syslog": "Reports - System Log",
    "prm_journal_export": "Reports - Export Journal",
    "prm_report_manager_auth_log": "Report - User Auth Log",
    "prm_report_activations": "Report - Activations",
    "prm_report_sessions": "Report - Sessions",
    "prm_report_users": "Report - Users",
    "prm_report_cards_usage": "Report - Cards Usage",
    "prm_settings": "Settings - System Settings",
    "prm_sites_management": "Settings - Sites Management",
    "prm_tools_announcements": "Tools - Announcements",
    "prm_tools_bandwidth_control": "Tools -> Bandwidth Control",
    "prm_ucp_activate": "User Control Panel - Activate",
    "prm_ucp_auto_login": "User Control Panel - Auto Login",
    "prm_ucp_billing": "User Control Panel - Billing",
    "prm_ucp_browse_packages": "User Control Panel - Show Packages",
    "prm_ucp_cancel": "User Control Panel - Cancel Subscription",
    "prm_ucp_change_info": "User Control Panel - Change User Info",
    "prm_ucp_change_password": "User Control Panel - Change Password",
    "prm_ucp_change_profile": "User Control Panel - Change Profile",
    "prm_ucp_data_usage": "User Control Panel - Show Data Usage",
    "prm_ucp_login": "User Control Panel - Allow Login",
    "prm_ucp_sessions": "User Control Panel - Show Sessions",
    "prm_ucp_support": "User Control Panel - Submit Support Tickets",
    "prm_ucp_extend": "User Control Panel - Extend Users",
    "prm_ucp_docs_show": "User Control Panel - Show Documents",
    "prm_ucp_docs_upload": "User Control Panel - Upload Documents",
    "prm_ucp_docs_delete" : "User Control Panel - Delete Documents",
    "prm_ucp_auto_renew": "User Control Panel - Enable/Disable Auto-Renew",

    "prm_users_activate": "Users - Activate",
    "prm_users_activate_card": "Users - Activate using voucher",
    "prm_users_activate_credit": "Users - Activate using manager balance",
    "prm_users_activate_trial": "Users - Activate Test Account",
    "prm_users_activate_user_balance": "Users - Activate using user balance",
    "prm_users_advanced": "Users - Edit Advanced Fields (dangerous!)",
    "prm_users_cancel_profile_change": "Users - Cancel Scheduled Profile Change",
    "prm_users_change_profile": "Users - Change Profile",
    "prm_users_change_profile_active": "Users - Change Profile of Active Users",
    "prm_users_create": "Users - Create",
    "prm_users_delete": "Users - Delete",
    "prm_users_deposit": "Users - Deposit Money",
    "prm_users_disconnect": "Users - Disconnect",
    "prm_users_history": "Users - Show User History",
    "prm_users_index": "Users - Index",
    "prm_users_index_all": "Users - List All Users",
    "prm_users_invoice": "Users - Show Users Invoices",
    "prm_users_journal": "Users - Show Users Journal",
    "prm_users_mac_lock": "Users - MAC Lock User",
    "prm_users_ping": "Users - Ping",
    "prm_users_rename": "Users - Rename",
    "prm_users_reset_quota": "Users - Reset Daily Quota",
    "prm_users_sessions_index": "Users - Show Sessions",
    "prm_users_update": "Users - Update",
    "prm_users_withdrawal": "Users - Withdraw Money",
    "prm_users_export": "Users - Export to Excel",
    "prm_users_extend": "Users - Extend Service",
    "prm_users_cancel": "Users - Cancel Subscription",
    "prm_users_reward_points": "Users - Reward Points System",
    "prm_users_pos": "Users - POS",
    "prm_users_live_traffic": "Users - Live Traffic Monitor",
    "prm_users_delete_active": "Users - Delete Active Users",
    "prm_users_tickets": "Users - Show Support Tickets",
    "prm_users_freezone_traffic": "Users - Show Freezones Traffic",
    "prm_users_show_password": "Users - Show Password",
    "prm_users_mac_add": "Users - Edit MAC addresses",
    "prm_widget_factory": "Dashboard - Widgets Factory",
    "prm_tools_import": "Tools - Import Data",


    "widget_title_total_users": "Total Users",
    "widget_description_total_users": "Registered Users",
    "widget_title_managers": "Managers",
    "widget_description_managers": " ",
    "widget_title_online_users": "Online Users",
    "widget_description_online_users": "Connected Users",
    "widget_title_active_users": "Active Users",
    "widget_description_active_users": " ",
    "widget_title_expired_users": "Expired Users",
    "widget_description_expired_users": " ",
    "widget_title_about_expire": "About to Expire",
    "widget_description_about_expire": "Users expiring in 3 days",
    "widget_title_balance": "Balance",
    "widget_description_balance": " ",
    "widget_title_system_version": "System Version",
    "widget_description_system_version": "SAS version",
    "widget_title_uptime": "System Uptime",
    "widget_description_uptime": " ",
    "widget_title_memory": "System Memory",
    "widget_description_memory": "Used Memory",
    "widget_title_disk": "System Disk",
    "widget_description_disk": "Used System Disk",
    "widget_title_ping": "Network",
    "widget_description_ping": "Ping on Snono Systems",
    "widget_title_ping_dns": "DNS Ping",
    "widget_description_ping_dns": "Ping on 1.1.1.1",
    "widget_title_ping_google": "Google Ping",
    "widget_description_ping_google": "Ping on Google.com",
    "widget_title_reward_points": "Reward Points",
    "widget_description_reward_points": " ",
    "widget_title_fup_online": "Online FUP",
    "widget_description_fup_online": " ",
    "widget_title_system_time": "System Time",
    "widget_description_system_time": " ",

    "user_activate_form_title": "Activate User",
    "user_activate_option_manager_balance": "Manager Balance",
    "user_activate_option_user_balance": "User Balance",
    "user_activate_option_user_card": "Prepaid Card",
    "user_activate_option_reward_points": "Reward Points",

    "ippool_form_title": "Add / Edit Pool",
    "ippool_form_name": "Pool Name",
    "ippool_form_start_ip": "Start IP",
    "ippool_form_end_ip": "End IP",
    "ippool_form_lease_time": "Lease Time (hours)",

    "report_users_per_manager_title": "Users Per Manager",
    "report_users_per_profile_title": "Users Per Profile",
    "report_users_registrations_title": "Registrations",
    "report_users_registrations_per_month": "Registration per Month",

    "header_account": "Account",
    "header_profile": "Profile",
    "header_login_as":  "Login As...",
    "header_logout": "Logout",
    "header_self_deposit": "Self Deposit",

    "global_actions_new": "New",
    "global_actions_live_traffic": "Live Traffic",
    "global_actions_edit": "Edit",
    "global_actions_edit_new_tab": "Edit (New Tab)",
    "global_actions_rename": "Rename",
    "global_actions_deposit": "Deposit",
    "global_actions_withdrawal": "Withdrawal",
    "global_actions_delete": "Delete",
    "global_table_actions": "Actions",
    "global_table_label_found": "Found",
    "global_table_label_records": "record(s)",
    "global_label_username" : "Username",
    "global_label_password": "Password",
    "global_label_balance": "Balance",
    "global_label_advanced_filter": "Advanced Filter",
    "global_label_profile": "Profile",

    "global_button_dismiss": "Dismiss",
    "global_button_submit": "Submit",
    "global_button_activate": "Activate",
    "global_button_search": "Search",
    "global_button_refund": "Refund",
    "global_button_cancel": "Cancel",

    "global_label_download": "Download",
    "global_label_upload": "Upload",
    "global_label_rename": "Rename",
    "global_label_delete": "Delete",

    "global_user_control_panel": "User Control Panel",

    "user_invoice_title_action": "Invoice Designer",

    "placeholder_search": "Search...",

    "rsp_save_success": "Saved Successfully",
    "rsp_success":  "Changes Applied Successfully",
    "rsp_update_success": "Updated Successfully",
    "rsp_insufficient_balance": "Insufficient Balance",
    "rsp_amount_deducted": "Amount Deducted",
    "rsp_amount_added": "Amount Added",
    "rsp_exceeded_max_users": "Exceeded Users Limit",
    "rsp_user_exists": "User Already Exists",
    "rsp_profile_changed": "Profile Changed",
    "rsp_profile_change_scheduled": "Profile Change Scheduled",

    "msg_manager_activate_success": "User Activated Successfully",
    "msg_wait": "Please Wait...",
    "msg_update_success": "User Updated Successfully",
    "msg_manager_rename_success": "Manager Renamed",
    "msg_manager_rename_error": "Unable to rename manager",
    "msg_manager_delete_success": "Manager Deleted",
    "msg_manager_delete_warning": "Unable to delete some managers",
    "msg_user_rename_success": "User Renamed",
    "msg_user_rename_error": "Unable to rename user",
    "msg_user_delete_success": "Users Deleted",
    "msg_user_delete_warning": "Unable to delete some users",
    "msg_user_not_online": "User Not Online",
    "msg_invoice_already_paid": "Invoice already paid",
    "msg_user_activate_success": "User Activated",
    "msg_user_already_active": "User is active, not permitted to change profile",
    "msg_row_is_full": "Row is full",
    "prompt_delete_manager": "Delete selected manager(s)?",
    "prompt_delete_user": "Delete selected user(s)?",
    "prompt_disconnect_user": "Disconnect Selected User ?",
    "prompt_lock_mac": "Lock user on current MAC ?",

    "report_activations_title": "Activations Report",
    "report_activations_chart_title": "Activations Chart",
    "report_activations_old_expiration": "Old Expiration",
    "report_activations_new_expiration": "New Expiration",

    "report_syslog_title": "System Log",
    "report_syslog_event": "Event",
    "report_user_auth_log_title": "Users Authentication Log",

    "report_journal_manager_title": "Managers Journal",
    "report_journal_cr": "Credit",
    "report_journal_dr": "Debit",
    "report_journal_amount": "Amount",
    "report_journal_balance": "Balance",
    "report_profits_title": "Profits Chart",

    "user_live_traffic_chart_title": "Live Traffic",

    "tickets_action_close": "Close Ticket",
    "self_deposit_method": "Payment Method",
    "self_deposit_select_method": "Select Payment Method",
    "self_deposit_amount": "Deposit Amount",
    "self_deposit_deposit_button": "Deposit",
    "self_deposit_no_payment_method": "No Payment Methods Available",
    "self_deposit_kushok_voucher": "Voucher PIN",

    "invoice_type_activate": "Activation",
    "invoice_type_deposit": "Deposit",
    "invoice_type_commission": "Commission",
    "invoice_type_transfer_deposit": "User Deposit",
    "invoice_type_transfer_withdrawal": "User Withdrawal",
    "invoice_type_withdrawal": "Withdrawal",

    "aboard_label_subscribers": "Subscribers",
    "aboard_label_online_users": "Online Users",
    "aboard_label_finance": "Finance & Sales",
    "aboard_label_system_health": "System Health",
    "aboard_label_cpu": "CPU Load",
    "aboard_label_memory": "Memory Usage",
    "aboard_label_disk": "Disk Usage",
    "aboard_label_db_time": "Database Time",
    "aboard_label_timezone": "Time Zone",

    "aboard_activations_today": "Activations Today",
    "aboard_registrations_today": "Registrations Today",
    "aboard_server_uptime": "Uptime",
    "aboard_backup": "Backup Disk",
    "aboard_network_status": "Network Status",
    "aboard_license_status": "License Status"

  }
}


```

### 5. Menus

**Method:** `GET`  
**URL:** `http://{{IP-or-Domain}}/admin/api/index.php/api/resources/menu`  
**Auth:** bearer

**الوصف (كما في التوثيق):**

Retrieves all menu available for a given access token

**مثال استجابة: Menus Example** — HTTP 200 OK
- Request URL: `http://demo4.sasradius.com/admin/api/index.php/api/resources/menu`
- Content-Type: application/json
```json
[
    {
        "name": "dashboard",
        "title": "menu_dashboard",
        "icon": "fas fa-tachometer-alt",
        "link": "/dashboard",
        "weight": 0,
        "parent": "root",
        "acl": "any"
    },
    {
        "name": "users",
        "title": "menu_users",
        "icon": "fa fa-users",
        "link": "users",
        "weight": 2,
        "parent": "root",
        "acl": "prm_users_index"
    },
    {
        "name": "users",
        "title": "menu_users_list",
        "#icon": "fa fa-list",
        "link": "/users/index",
        "weight": 2,
        "parent": "users",
        "acl": "prm_users_index"
    },
    {
        "name": "users",
        "title": "menu_users_online",
        "#icon": "fa fa-link",
        "link": "/users/online",
        "weight": 1,
        "parent": "users",
        "acl": "prm_users_index"
    },
    {
        "name": "managers",
        "title": "menu_managers",
        "icon": "fa fa-user-secret",
        "link": "/managers/index",
        "weight": 3,
        "parent": "root",
        "acl": "prm_managers_index"
    },
    {
        "name": "nas",
        "title": "menu_nas",
        "icon": "fa fa-server",
        "link": "/nas/index",
        "weight": 4,
        "parent": "root",
        "acl": "prm_nas_index"
    },
    {
        "name": "profiles_list",
        "title": "menu_profiles_list",
        "#icon": "fa fa-list",
        "link": "/profiles/index",
        "weight": 1,
        "parent": "profiles",
        "acl": "prm_profiles_index"
    },
    {
        "name": "profiles_pricing",
        "title": "menu_profiles_pricing",
        "#icon": "fa fa-money-bill",
        "link": "/profiles/pricing",
        "weight": 2,
        "parent": "profiles",
        "acl": "prm_profiles_pricing"
    },
    {
        "name": "profiles_usage_notifications",
        "title": "menu_profiles_usage_notifications",
        "link": "/profiles/notifications",
        "weight": 3,
        "parent": "profiles",
        "acl": "prm_managers_sysadmin"
    },
    {
        "name": "profiles",
        "title": "menu_profiles",
        "icon": "fa fa-puzzle-piece",
        "link": "profiles",
        "weight": 5,
        "parent": "root",
        "acl": "prm_profiles_index|prm_profiles_pricing"
    },
    {
        "name": "cards",
        "title": "menu_cards",
        "icon": "fa fa-credit-card",
        "link": "/cards/index",
        "weight": 5,
        "parent": "root",
        "acl": "prm_cards_index"
    },
    {
        "name": "billing",
        "title": "menu_billing",
        "icon": "fa fa-file-invoice-dollar",
        "link": "billing",
        "weight": 6,
        "parent": "root",
        "acl": "prm_billing"
    },
    {
        "name": "user_invoices",
        "title": "menu_billing_user_invoices",
        "link": "/billing/invoices/index",
        "weight": 2,
        "parent": "billing",
        "acl": "prm_billing"
    },
    {
        "name": "user_issue_invoice",
        "title": "menu_billing_user_invoice_issue",
        "link": "/billing/userInvoiceForm",
        "weight": 1,
        "parent": "billing",
        "acl": "prm_billing"
    },
    {
        "name": "reports",
        "title": "menu_reports",
        "icon": "fas fa-chart-bar",
        "link": "reports",
        "weight": 7,
        "parent": "root",
        "acl": "any"
    },
    {
        "name": "reports",
        "title": "menu_reports_syslog",
        "#icon": "fas fa-user-secret",
        "link": "/report/syslog",
        "weight": 7,
        "parent": "reports",
        "acl": "prm_report_syslog"
    },
    {
        "name": "reports",
        "title": "menu_reports_managers_journal",
        "#icon": "fas fa-book",
        "link": "/report/journal/managers",
        "weight": 7,
        "parent": "reports",
        "acl": "prm_report_managers_journal"
    },
    {
        "name": "reports",
        "title": "menu_reports_managers_invoices",
        "#icon": "fa fa-file-invoice-dollar",
        "link": "/report/invoice/managers",
        "weight": 7,
        "parent": "reports",
        "acl": "prm_report_managers_invoices"
    },
    {
        "name": "reports",
        "title": "menu_reports_managers_receipts",
        "#icon": "fa fa-file-invoice-dollar",
        "link": "/report/receipts/managers",
        "weight": 7,
        "parent": "reports",
        "acl": "prm_managers_receipt"
    },
    {
        "name": "reports",
        "title": "menu_reports_user_auth_log",
        "#icon": "fas fa-server",
        "link": "/report/userauthlog",
        "weight": 8,
        "parent": "reports",
        "acl": "prm_report_activations"
    },
    {
        "name": "reports",
        "title": "menu_reports_activations",
        "#icon": "fas fa-server",
        "link": "/report/activations",
        "weight": 8,
        "parent": "reports",
        "acl": "prm_any"
    },
    {
        "name": "reports",
        "title": "menu_reports_activations_stats",
        "link": "/report/activations_statistics",
        "weight": 6,
        "parent": "reports",
        "acl": "prm_any"
    },
    {
        "name": "reports",
        "title": "menu_reports_profits",
        "link": "/report/profits",
        "weight": 7,
        "parent": "reports",
        "acl": "prm_any"
    },
    {
        "name": "reports",
        "title": "menu_reports_sessions",
        "link": "/report/sessions",
        "weight": 7,
        "parent": "reports",
        "acl": "prm_report_sessions"
    },
    {
        "name": "reports",
        "title": "menu_report_users",
        "link": "/report/users",
        "weight": 8,
        "parent": "reports",
        "acl": "prm_report_users"
    },
    {
        "name": "reports",
        "title": "menu_reports_traffic",
        "link": "/report/traffic",
        "weight": 9,
        "parent": "reports",
        "acl": "prm_managers_sysadmin"
    },
    {
        "name": "reports",
        "title": "menu_reports_money_transfer",
        "link": "/report/money_transfer",
        "weight": 7,
        "parent": "reports",
        "acl": "prm_managers_sysadmin"
    },
    {
        "name": "reports",
        "title": "menu_reports_online",
        "link": "/report/online",
        "weight": 7,
        "parent": "reports",
        "acl": "prm_managers_sysadmin"
    },
    {
        "name": "tools",
        "title": "menu_tools",
        "icon": "fal fa-wrench",
        "link": "tools",
        "weight": 8,
        "parent": "root",
        "acl": "any"
    },
    {
        "name": "dashboard_manager",
        "title": "menu_tools_dashboard_manager",
        "#icon": "fas fa-th",
        "link": "/tools/dashboard-manager",
        "weight": 1,
        "parent": "tools",
        "acl": "prm_dashboard_manager"
    },
    {
        "name": "ippool",
        "title": "menu_ip_pools",
        "icon": "fal fa-cabinet-filing",
        "link": "/ippool/index",
        "weight": 8,
        "parent": "root",
        "acl": "prm_managers_sysadmin"
    },
    {
        "name": "backup",
        "title": "menu_tools_backup",
        "#icon": "fas fa-hdd",
        "link": "/backup/index",
        "weight": 3,
        "parent": "tools",
        "acl": "prm_backup_download"
    },
    {
        "name": "dashboard_manager",
        "title": "menu_tools_widget_factory",
        "#icon": "fa fa-square",
        "link": "/tools/widget-factory",
        "weight": 1,
        "parent": "tools",
        "acl": "prm_widget_factory"
    },
    {
        "name": "system_services",
        "title": "menu_tools_system_services",
        "#icon": "fa fa-cogs",
        "link": "/tools/systemServices",
        "weight": 4,
        "parent": "tools",
        "acl": "prm_managers_sysadmin"
    },
    {
        "name": "system_update",
        "title": "menu_tools_system_update",
        "#icon": "fa fa-sync",
        "link": "/tools/systemUpdate",
        "weight": 5,
        "parent": "tools",
        "acl": "prm_managers_sysadmin"
    },
    {
        "name": "system_maintenance",
        "title": "menu_tools_maintenance",
        "#icon": "fa fa-briefcase-medical",
        "link": "/tools/maintenance",
        "weight": 5,
        "parent": "tools",
        "acl": "prm_managers_sysadmin"
    },
    {
        "name": "announcements",
        "title": "menu_tools_announcements",
        "link": "/tools/announcements",
        "weight": 6,
        "parent": "tools",
        "acl": "prm_tools_announcements"
    },
    {
        "name": "import",
        "title": "menu_tools_import",
        "link": "/tools/import",
        "weight": 7,
        "parent": "tools",
        "acl": "prm_tools_import"
    },
    {
        "name": "bulk_changes",
        "title": "menu_tools_bulk_changes",
        "link": "/tools/bulk-changes",
        "weight": 8,
        "parent": "tools",
        "acl": "prm_managers_sysadmin"
    },
    {
        "name": "bandwidth_controller",
        "title": "menu_bandwidth_controller",
        "link": "/tools/bandwidthcontroller",
        "weight": 8,
        "parent": "tools",
        "acl": "prm_managers_sysadmin"
    },
    {
        "name": "about",
        "title": "menu_about",
        "icon": "fa fa-info",
        "link": "/about",
        "weight": 1000,
        "parent": "root",
        "acl": "prm_any"
    },
    {
        "name": "settings",
        "title": "menu_settings",
        "icon": "fa fa-cog",
        "link": "/settings",
        "weight": 90,
        "parent": "root",
        "acl": "prm_settings"
    },
    {
        "name": "acl",
        "title": "menu_settings_advanced",
        "#icon": "fa fa-cog",
        "link": "/settings/advanced",
        "weight": 96,
        "parent": "settings",
        "acl": "prm_settings"
    },
    {
        "name": "site",
        "title": "menu_settings_backup",
        "#icon": "fa fa-hdd",
        "link": "/settings/backup",
        "weight": 8,
        "parent": "settings",
        "acl": "prm_settings"
    },
    {
        "name": "site",
        "title": "menu_settings_email",
        "#icon": "fa fa-envelope",
        "link": "/settings/email",
        "weight": 95,
        "parent": "settings",
        "acl": "prm_settings"
    },
    {
        "name": "site",
        "title": "menu_settings_email_template",
        "#icon": "fa fa-envelope",
        "link": "/settings/emailTemplates",
        "weight": 95,
        "parent": "settings",
        "acl": "prm_settings"
    },
    {
        "name": "site",
        "title": "menu_settings_freezone",
        "#icon": "fa fa-asterisk",
        "link": "/settings/freezone",
        "weight": 94,
        "parent": "settings",
        "acl": "prm_settings"
    },
    {
        "name": "acl",
        "title": "menu_settings_general",
        "#icon": "fa fa-cogs",
        "link": "/settings/general",
        "weight": 91,
        "parent": "settings",
        "acl": "prm_settings"
    },
    {
        "name": "site",
        "title": "menu_settings_license",
        "#icon": "fa fa-certificate",
        "link": "/settings/license",
        "weight": 20,
        "parent": "settings",
        "acl": "prm_managers_sysadmin"
    },
    {
        "name": "acl",
        "title": "menu_settings_network",
        "#icon": "fa fa-plug",
        "link": "/settings/network",
        "weight": 91,
        "parent": "settings",
        "acl": "prm_settings"
    },
    {
        "name": "site",
        "title": "menu_settings_notifications",
        "#icon": "fa fa-bell",
        "link": "/settings/notifications",
        "weight": 20,
        "parent": "settings",
        "acl": "prm_settings"
    },
    {
        "name": "acl",
        "title": "menu_settings_acl",
        "#icon": "fa fa-lock",
        "link": "/settings/acl",
        "weight": 92,
        "parent": "settings",
        "acl": "prm_settings"
    },
    {
        "name": "site",
        "title": "menu_settings_payment_gateways",
        "link": "/settings/paymentgateways",
        "weight": 96,
        "parent": "settings",
        "acl": "prm_settings"
    },
    {
        "name": "site",
        "title": "menu_settings_billing",
        "link": "/settings/billing",
        "weight": 96,
        "parent": "settings",
        "acl": "prm_settings"
    },
    {
        "name": "sites",
        "title": "menu_settings_sites",
        "#icon": "fa fa-building",
        "link": "/settings/sites",
        "weight": 93,
        "parent": "settings",
        "acl": "prm_settings"
    },
    {
        "name": "site",
        "title": "menu_settings_sms",
        "link": "/settings/sms",
        "weight": 94,
        "parent": "settings",
        "acl": "prm_settings"
    },
    {
        "name": "acl",
        "title": "menu_settings_sastrack",
        "#icon": "fa fa-cog",
        "link": "/settings/sastrack",
        "weight": 96,
        "parent": "settings",
        "acl": "prm_settings"
    },
    {
        "name": "site",
        "title": "menu_settings_telegram",
        "link": "/settings/telegram",
        "weight": 96,
        "parent": "settings",
        "acl": "prm_settings"
    },
    {
        "name": "site",
        "title": "menu_settings_ucp",
        "link": "/settings/ucp",
        "weight": 95,
        "parent": "settings",
        "acl": "prm_settings"
    },
    {
        "name": "acl",
        "title": "menu_settings_portal",
        "#icon": "fa fa-link",
        "link": "/settings/portal",
        "weight": 95,
        "parent": "settings",
        "acl": "prm_settings"
    }
]
```


---

## المجلد: Dashboard

_(المجلد فارغ — لا طلبات)_


---

## المجلد: User Portal (user panel)

/user/api/index.php/api/

### 6. Login

**Method:** `POST`  
**URL:** `http://{{IP-or-Domain}}/user/api/index.php/api/auth/login`  
**Auth:** (غير محدد — يحتاج Bearer عملياً)

**الوصف (كما في التوثيق):**

Authenticates through SAS4 and returns cookies/token 
encoded params:

```
{"username":"Example","password":"Example","language":"en"}
```

**Body (urlencoded):**
- `payload` = `<text encrypted by CryptoJS>`

**مثال استجابة: Login Example** — HTTP 200 OK
- Request URL: `http://{{IP_OR_}}/user/api/index.php/api/auth/login`
- Request body: `payload=<text encrypted by CryptoJS>`
- Content-Type: application/json
```json
{
    "status": 200,
    "token": "<JWT_TOKEN>"
}
```

### 7. Register

**Method:** `POST`  
**URL:** `http://{{IP-or-Domain}}/user/api/index.php/api/register`  
**Auth:** (غير محدد — يحتاج Bearer عملياً)

**الوصف (كما في التوثيق):**

Registers a user and returns 200 on success

```
{
"username":"Example",
"email":"Example@gmail.com"
,"mobile":"07813370000"
,"password":"Example",
"confirm_password":"Example",
"firstname":"Example",
"lastname":"Example"
}
```

**Body (urlencoded):**
- `payload` = `<text encrypted by CryptoJS>`

**مثال استجابة: Register Example** — HTTP 200 OK
- Request URL: `http://{{IP_OR_WEBSITE}}:{{PORT}}/user/api/index.php/api/register`
- Request body: `payload=<text encrypted by CryptoJS>`
- Content-Type: application/json
```json
{
    "status": 200,
    "message": "rsp_save_success",
    "token": "<JWT_TOKEN>"
}
```

### 8. invoices

**Method:** `POST`  
**URL:** `http://{{IP-or-Domain}}/user/api/index.php/api/index/invoice`  
**Auth:** bearer

**الوصف (كما في التوثيق):**

Get invoices from user portal
body: 

```
{"page":1,"count":10,"sortBy":"id","direction":"desc"}
```

**Body (urlencoded):**
- `payload` = `<text encrypted by CryptoJS>`

**مثال استجابة: invoices Example** — HTTP 200 OK
- Request URL: `http://{{IP-or-Domain}}/user/api/index.php/api/index/invoice`
- Request body: `payload=<text encrypted by CryptoJS>`
- Content-Type: application/json
```json
{
    "current_page": 1,
    "data": [
        {
            "id": 2,
            "invoice_number": "2020-1-2",
            "type": "custom",
            "amount": "0.00",
            "description": null,
            "paid": 0,
            "created_by": 1,
            "created_at": "2020-09-24 11:21:45",
            "payment_method": null,
            "due_date": "2020-09-24 11:21:45"
        }
    ],
    "first_page_url": "http://192.168.240.122/user/api/index.php/api/index/invoice?page=1",
    "from": 1,
    "last_page": 1,
    "last_page_url": "http://192.168.240.122/user/api/index.php/api/index/invoice?page=1",
    "next_page_url": null,
    "path": "http://192.168.240.122/user/api/index.php/api/index/invoice",
    "per_page": 10,
    "prev_page_url": null,
    "to": 1,
    "total": 1
}
```

### 9. Change Subscription

**Method:** `POST`  
**URL:** `http://{{IP-or-Domain}}/user/api/index.php/api/service`  
**Auth:** bearer

**الوصف (كما في التوثيق):**

Changes subscription of the user 
encoded param:

```
{"new_service":"2","current_password":true}
```

Note: If the subscription is changed to the same subscription id, the response will be empty with a 200 Request code

**Body (urlencoded):**
- `payload` = `<text encrypted by CryptoJS>`

**مثال استجابة: Change Subscription Example** — HTTP 200 OK
- Request URL: `http://{{IP-or-Domain}}/user/api/index.php/api/service`
- Request body: `payload=<text encrypted by CryptoJS>`
- Content-Type: application/json
```json
{
    "status": 200,
    "message": "rsp_service_change_success"
}
```

### 10. User sessions

**Method:** `POST`  
**URL:** `http://{{IP-or-Domain}}/user/api/index.php/api/index/session`  
**Auth:** bearer

**الوصف (كما في التوثيق):**

Returns a list of user active sessions 
encoded payload: 

```
{"page":1,"count":10,"sortBy":"radacctid","direction":"desc"}
```

**Body (urlencoded):**
- `payload` = `<text encrypted by CryptoJS>`

**مثال استجابة: User sessions Example** — HTTP 200 OK
- Request URL: `http://{{IP-or-Domain}}/user/api/index.php/api/index/session`
- Request body: `payload=<text encrypted by CryptoJS>`
- Content-Type: application/json
```json
{
    "current_page": 1,
    "data": [],
    "first_page_url": "http://192.168.240.122/user/api/index.php/api/index/session?page=1",
    "from": null,
    "last_page": 1,
    "last_page_url": "http://192.168.240.122/user/api/index.php/api/index/session?page=1",
    "next_page_url": null,
    "path": "http://192.168.240.122/user/api/index.php/api/index/session",
    "per_page": 10,
    "prev_page_url": null,
    "to": null,
    "total": 0
}
```

### 11. User traffic

**Method:** `POST`  
**URL:** `http://{{IP-or-Domain}}/user/api/index.php/api/traffic`  
**Auth:** bearer

**الوصف (كما في التوثيق):**

Returns user traffic over the last 30 days, each day traffic is given in rx,tx with 30 values, each value for each day. 
encoded params:

```
{"report_type":"daily","month":9,"year":2020,"user_id":null}
```

**Body (urlencoded):**
- `payload` = `<text encrypted by CryptoJS>`

**مثال استجابة: User traffic example** — HTTP 200 OK
- Request URL: `http://{{IP-or-Domain}}/user/api/index.php/api/traffic`
- Request body: `payload=<text encrypted by CryptoJS>`
- Content-Type: application/json
```json
{
    "status": 200,
    "data": {
        "rx": [
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0
        ],
        "tx": [
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0
        ],
        "total": [
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0
        ],
        "total_real": [
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0
        ],
        "free_traffic": [
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0
        ]
    }
}
```

### 12. Redeem code

**Method:** `POST`  
**URL:** `http://{{IP-or-Domain}}/user/api/index.php/api/redeem`  
**Auth:** bearer

**الوصف (كما في التوثيق):**

Get the available subscriptions from SAS4
encoded parameters: 

```
{"pin":"136154"}
```

**Body (urlencoded):**
- `payload` = `<text encrypted by CryptoJS>`

**مثال استجابة: Redeem code Example** — HTTP 200 OK
- Request URL: `http://{{IP-or-Domain}}/user/api/index.php/api/redeem`
- Request body: `payload=<text encrypted by CryptoJS>`
- Content-Type: application/json
```json
{
    "status": 200,
    "message": "rsp_success"
}
```

### 13. Activate user subscription

**Method:** `POST`  
**URL:** `http://{{IP-or-Domain}}/user/api/index.php/api/user/activate`  
**Auth:** bearer

**الوصف (كما في التوثيق):**

Activate user subscription and deduct from balance
encoded params:

```
{"uuid":"edad62f6-d324-7510-8c6a-90a9b4a3fee2","current_password":true}
```

The uuid is a rate-limit mechanism generated from client-side using uuid/guid functions at the load time of client-side interface so that if a user clicks activate multiple times it would all be sent using
the same uuid and thus wouldn't activate multiple times.

**Body (urlencoded):**
- `payload` = `<text encrypted by CryptoJS>`

**مثال استجابة: Activate user subscription Example** — HTTP 200 OK
- Request URL: `http://{{IP-or-Domain}}/user/api/index.php/api/redeem`
- Request body: `payload=<text encrypted by CryptoJS>`
- Content-Type: application/json
```json
{
    "status": 200,
    "message": "rsp_success"
}
```

### 14. Activate Subscription Extension

**Method:** `POST`  
**URL:** `http://{{IP-or-Domain}}/user/api/index.php/api/user/extend`  
**Auth:** bearer

**الوصف (كما في التوثيق):**

Adds an extension to the user extension from the available extensions and returns 200 on success
encoded params:

```
{"profile_id":"3","current_password":true}
```

**Body (urlencoded):**
- `payload` = `<text encrypted by CryptoJS>`
- `` = ``

**مثال استجابة: Activate Subscription Extension Example** — HTTP 200 OK
- Request URL: `http://{{IP-or-Domain}}/user/api/index.php/api/user/extend`
- Request body: `payload=<text encrypted by CryptoJS>`, `=`
- Content-Type: application/json
```json
{
    "status": 200,
    "message": "rsp_success"
}
```

### 15. Change password

**Method:** `POST`  
**URL:** `http://{{IP-or-Domain}}/user/api/index.php/api/user`  
**Auth:** bearer

**الوصف (كما في التوثيق):**

NOTE: The functionality is bugged and a quick fix is incoming the next patch
Changes the password 
encoded params:

```
{"key":"password","value":"1234","current_password":true}
```

where value is the new password.

**Body (urlencoded):**
- `payload` = `<text encrypted by CryptoJS>`

**مثال استجابة: Change password Example** — HTTP 200 OK
- Request URL: `http://{{IP-or-Domain}}/user/api/index.php/api/user`
- Request body: `payload=<text encrypted by CryptoJS>`
- Content-Type: application/json
```json
{
    "status": 200
}
```

### 16. Language keywords

**Method:** `GET`  
**URL:** `http://{{IP-or-Domain}}/user/api/index.php/api/resources/language/ar`  
**Auth:** bearer

**مثال استجابة: Language keywords en** — HTTP 200 OK
- Request URL: `http://{{IP-or-Domain}}/user/api/index.php/api/resources/language/en`
- Content-Type: text/html; charset=UTF-8
```json
{
    "info": {
        "id": "en",
        "name": "English",
        "direction": "ltr",
        "author": "hasanen@snono-systems.com",
        "font": "Arial"
    },
    "words": {
        "menu_account": "Account",
        "menu_billing": "Billing",
        "menu_invoices": "Invoices",
        "menu_payments": "Payments",
        "menu_data_usage": "Data Usage",
        "menu_sessions": "Sessions",
        "menu_packages": "Packages",
        "menu_support": "Support",
        "menu_journal": "Journal",
        "menu_documents": "Documents",

        "global_table_actions": "Actions",
        "global_label_download": "Download",
        "global_label_upload": "Upload",
        "global_label_rename": "Rename",
        "global_label_delete": "Delete",


        "header_user_portal": "User Portal",

        "user_document_table_name": "Document Name",
        "user_document_table_size": "Size",
        "user_document_table_date": "Date",

        "session_table_started": "Started On",
        "session_table_ended": "Ended On",
        "session_table_ip": "IP",
        "session_table_download": "Download",
        "session_table_upload": "Upload",
        "session_table_mac": "MAC",
        "session_table_profile": "Profile",

        "invoices_table_no": "Invoice No",
        "invoices_table_date": "Date",
        "invoices_table_amount": "Amount",
        "invoices_table_description": "Description",
        "invoices_table_due_date": "Due Date",
        "invoices_table_is_paid": "Paid",
        "invoices_table_paid": "Paid",
        "invoices_table_unpaid": "Unpaid",

        "payment_table_no": "Receipt No",
        "payment_table_date": "Date",
        "payment_table_type": "Type",
        "payment_table_amount": "Amount",
        "payment_table_description": "Description",
        "payment_table_created_by": "Created By",

        "user_journal_table_date": "Date",
        "user_journal_table_cr": "CR",
        "user_journal_table_dr": "DR",
        "user_journal_table_amount": "Amount",
        "user_journal_table_balance": "Balance",
        "user_journal_table_operation": "Operation",
        "user_journal_table_description": "Description",


        "header_logout": "Logout",
        "breadcrumb_account": "Account Information",
        "breadcrumb_invoices": "Invoices",
        "breadcrumb_sessions": "Login Sessions",
        "breadcrumb_journal": "Balance Journal",
        "breadcrumb_payments": "Payments",
        "breadcrumb_usage": "Data Usage",
        "breadcrumb_packages": "Available Packages",
        "breadcrumb_activate_renew": "Purchase Service",
        "breadcrumb_change_service": "Change Service",
        "breadcrumb_activate_extend": "Extend Service",
        "breadcrumb_support_tickets": "Support Tickets",
        "breadcrumb_user_documents": "User Documents",


        "account_label_days": "day(s)",
        "account_label_remaining_days": "Remaining days",
        "account_label_remaining_traffic": "Remaining Traffic",
        "account_label_balance": "Account Balance",
        "account_label_unpaid_invoices": "Unpaid Invoices",
        "account_label_remaining_uptime": "Remaining Uptime",
        "account_label_customer_information": "Customer Information",
        "account_label_id": "ID",
        "account_label_name": "Customer Name",
        "account_label_username": "Username",
        "account_label_email": "Email",
        "account_label_phone": "Phone",
        "account_label_address": "Address",
        "account_label_company": "Company",
        "account_label_created_on": "Registered On",

        "account_label_redeem": "Redeem Code",
        "account_label_redeem_card_number": "Enter Card Number",

        "account_label_service_info": "Service Information",
        "account_label_current_service": "Current Service",
        "account_label_service_description": "Service Description",
        "account_label_service_subscription": "Subscription",
        "account_label_expiration": "Expiration",
        "account_label_status": "Status",
        "account_label_service_price": "Service Price",
        "account_label_traffic_usage": "Remaining Traffic",
        "account_label_traffic_dl": "Remaining Traffic (Download)",
        "account_label_traffic_ul": "Remaining Traffic (Upload)",
        "account_label_static_ip": "Static IP",
        "account_label_auto_renew": "Auto Renew",
        "account_label_prompt_new_password" : "New Password",
        "account_prompt_current_password": "Current Password",

        "account_label_loan": "You have a loan of ",
        "account_label_deduction": "will be deducted from your account on next activation.",

        "account_action_extend": "Extend Service",
        "account_action_activate": "Activate Account",
        "account_action_change_service": "Change Service",
        "account_action_change_password": "Change Password",

        "activate_label_service": "Active Service",
        "activate_label_description": "Service Description",
        "activate_label_subscription": "Subscription",
        "activate_label_expiration": "Expiration",
        "activate_label_price": "Service Price",
        "activate_label_balance": "Balance",
        "activate_label_use_balance": "Use Available Balance",
        "activate_label_insufficient_balance": "Insufficient Balance",
        "activate_action_activate": "Activate",
        "activate_label_payment_method": "Choose Payment Method",
        "activate_label_no_method": "No Payment Method Available",
        "activate_label_service_activate": "Service Activated",
        "activate_label_unknown_error": "Unknown Error Occurred",
        "activate_label_contact_support": "Please report this error to support department",
        "activate_label_already_active": "Your service is already active",

        "extend_label_select_extension": "Select Service Extension",
        "extend_label_days": "day(s)",
        "extend_label_months": "month(s)",
        "extend_label_traffic": "of Data Traffic",
        "extend_label_traffic_dl": "of Download Traffic",
        "extend_label_traffic_ul": "of Upload Traffic",
        "extend_label_minutes": "minutes(s)",
        "extend_label_hours": "hour(s)",
        "extend_label_purchase": "Purchase",
        "extend_label_service_extended": "Service Extended",
        "extend_label_unknown_error": "Unknown Error Occurred",
        "extend_label_contact_support": "Please report this error to support department",

        "packages_no_description": "No description available",

        "activation_confirmation_message": "Activate Your Account ?",

        "rsp_service_change_success": "Service changed successfully",
        "rsp_service_change_invalid_service": "Invalid service selected !",
        "rsp_service_change_user_active": "User already active",
        "rsp_error": "Error occurred",
        "rsp_user_exists" : "User exists, try another username",

        "msg_invalid_current_password": "Incorrect password"
    }
}

```

**مثال استجابة: Language keywords ar** — HTTP 200 OK
- Request URL: `http://{{IP-or-Domain}}/user/api/index.php/api/resources/language/ar`
- Content-Type: text/html; charset=UTF-8
```json
{
    "info": {
        "id": "ar",
        "name": "Arabic",
        "direction": "ltr",
        "author": "hasanen@snono-systems.com",
        "font": "Arial"
    },
    "words": {
        "menu_account": "معلومات عامة",
        "menu_billing": "الحسابات",
        "menu_invoices": "الفواتير",
        "menu_payments": "الايصالات",
        "menu_data_usage": "بيانات الاستهلاك",
        "menu_sessions": "الجلسات",
        "menu_packages": "الباقات",
        "menu_support": "الدعم الفني",
        "menu_journal": "سجل الحسابات",
        "menu_documents": "وثائق شخصية",

        "global_table_actions": "العمليات",
        "global_label_download": "تحميل",
        "global_label_upload": "رفع",
        "global_label_delete": "حذف",


        "header_user_portal": "صفحة العميل",

        "user_document_table_name": "اسم الوثيقة",
        "user_document_table_size": "الحجم",
        "user_document_table_date": "تأريخ الرفع",


        "session_table_started": "وقت البدئ",
        "session_table_ended": "وقت النهاية",
        "session_table_ip": "IP",
        "session_table_download": "التحميل",
        "session_table_upload": "الرفع",
        "session_table_mac": "MAC",
        "session_table_profile": "الخدمة",

        "invoices_table_no": "رقم الفاتورة",
        "invoices_table_date": "تأريخ",
        "invoices_table_amount": "المبلغ",
        "invoices_table_description": "تفاصيل",
        "invoices_table_due_date": "تأريخ الاستحقاق",
        "invoices_table_is_paid": "مدفوعة",
        "invoices_table_paid": "مدفوعة",
        "invoices_table_unpaid": "غير مدفوعة",

        "payment_table_no": "رقم الايصال",
        "payment_table_date": "التأريخ",
        "payment_table_type": "النوع",
        "payment_table_amount": "المبلغ",
        "payment_table_description": "تفاصيل",
        "payment_table_created_by": "اصدر من قبل",

        "user_journal_table_date": "التأريخ",
        "user_journal_table_cr": "دائن",
        "user_journal_table_dr": "مدين",
        "user_journal_table_amount": "المبلغ",
        "user_journal_table_balance": "الرصيد",
        "user_journal_table_operation": "العملية",
        "user_journal_table_description": "تفاصيل",


        "header_logout": "خروج",
        "breadcrumb_account": "معلومات الحساب",
        "breadcrumb_invoices": "الفواتير",
        "breadcrumb_sessions": "جلسات الدخول",
        "breadcrumb_journal": "سجل الحسابات",
        "breadcrumb_payments": "الايصالات",
        "breadcrumb_usage": "استهلاك البيانات",
        "breadcrumb_packages": "الباقات المتوفرة",
        "breadcrumb_activate_renew": "شراء باقة",
        "breadcrumb_change_service": "تغيير الخدمة",
        "breadcrumb_activate_extend": "تمديد الخدمة",
        "breadcrumb_user_documents": "الوثائق الشخصية",

        "account_label_days": "يوم",
        "account_label_remaining_days": "الايام المتبقية",
        "account_label_remaining_traffic": "البيانات المتبقية",
        "account_label_balance": "رصيد الحساب",
        "account_label_unpaid_invoices": "الفواتير المستحقة",
        "account_label_remaining_uptime": "الوقت المتبقي",
        "account_label_customer_information": "معلومات العميل",
        "account_label_id": "الرمز",
        "account_label_name": "الاسم",
        "account_label_username": "اسم الدخول",
        "account_label_email": "البريد الالكتروني",
        "account_label_phone": "الهاتف",
        "account_label_address": "العنوان",
        "account_label_company": "الشركة",
        "account_label_created_on": "سجل بتأريخ",

        "account_label_redeem": "تعبئة بطاقة",
        "account_label_redeem_card_number": "ادخل رقم البطاقة",

        "account_label_service_info": "معلومات الاشتراك",
        "account_label_current_service": "الخدمة الحالية",
        "account_label_service_description": "تفاصيل الخدمة",
        "account_label_service_subscription": "حالة الاشتراك",
        "account_label_expiration": "تأريخ الانتهاء",
        "account_label_status": "الحالة",
        "account_label_service_price": "سعر الخدمة",
        "account_label_traffic_usage": "البيانات المتبقية",
        "account_label_traffic_dl": "البيانات المتبقية - التحميل",
        "account_label_traffic_ul": "البيانات المتبقية - الرفع",
        "account_label_static_ip": "عنوان انترنت ثابت",
        "account_label_auto_renew": "تجديد تلقائي",
        "account_label_prompt_new_password" : "كلمة السر الجديدة",
        "account_prompt_current_password": "كلمة السر الحالية",

        "account_action_extend": "تمديد الخدمة",
        "account_action_activate": "تفعيل الحساب",
        "account_action_change_service": "تغيير الخدمة",
        "account_action_change_password": "تغيير كلمة السر",

        "activate_label_service": "الخدمة الفعال",
        "activate_label_description": "تفاصيل الخدمة",
        "activate_label_subscription": "حالة الاشتراك",
        "activate_label_expiration": "تأريخ الانتهاء",
        "activate_label_price": "سعر الخدمة",
        "activate_label_balance": "الرصيد المتوفر",
        "activate_label_use_balance": "استخدام الراصيد المتوفر",
        "activate_label_insufficient_balance": "الرصيد غير كافي",
        "activate_action_activate": "تفعيل",
        "activate_label_payment_method": "اختر وسيلة الدفع",
        "activate_label_no_method": "وسائل الدفع غير متوفرة",
        "activate_label_service_activate": "تم تفعيل الخدمة",
        "activate_label_unknown_error": "حصل خطأ غير متوقع",
        "activate_label_contact_support": "الرجاء تبليغ قسم الدعم الفني بالمشكلة",
        "activate_label_already_active": "الاشتراك مازال فعال",

        "account_label_loan": "لديك قرض ب  ",
        "account_label_deduction": "سيتم استقطاعه من حسابك عند التفعيل القادم.",


        "extend_label_select_extension": "اختر باقة التمديد",
        "extend_label_days": "يوم",
        "extend_label_months": "شهر",
        "extend_label_traffic": "من البيانات",
        "extend_label_traffic_dl": "من بيانات التحميل",
        "extend_label_traffic_ul": "من بيانات الرفع",
        "extend_label_minutes": "دقيقة",
        "extend_label_hours": "ساعة",
        "extend_label_purchase": "شراء",
        "extend_label_service_extended": "تم تمديد الخدمة",
        "extend_label_unknown_error": "حصل خطأ غير متوقع",
        "extend_label_contact_support": "الرجاء تبليغ قسم الدعم الفني بالمشكلة",

        "packages_no_description": "لا يوجد تفاصيل لهذه الباقة",

        "activation_confirmation_message": "هل تود تفعيل حسابك ؟",


        "rsp_service_change_success": "تم تغيير الباقة",
        "rsp_service_change_invalid_service": "الباقة المختارة غير صحيحة",
        "rsp_service_change_user_active": "الاشتراك مازال فعال",
        "rsp_error": "حصل خطأ في النظام",
        "msg_invalid_current_password": "كلمة السر القديمة غير صحيحة"

    }
}

```

### 17. User Details & Permissions

**Method:** `GET`  
**URL:** `http://{{IP-or-Domain}}/user/api/index.php/api/user`  
**Auth:** bearer

**مثال استجابة: user** — HTTP 200 OK
- Request URL: `http://{{IP-or-Domain}}/user/api/index.php/api/user`
- Content-Type: application/json
```json
{
    "status": 200,
    "data": {
        "username": "Example1",
        "firstname": null,
        "lastname": null,
        "name": null,
        "email": "Example1@gmail.com",
        "phone": "07813370000",
        "address": null,
        "company": null,
        "registered_on": {
            "date": "2020-09-24 13:48:34.000000",
            "timezone_type": 3,
            "timezone": "Europe/Moscow"
        },
        "id": 6,
        "static_ip": null,
        "balance": 0,
        "auto_renew": 0,
        "profile_id": 1
    },
    "permissions": [
        "prm_ucp_activate",
        "prm_ucp_auto_login",
        "prm_ucp_billing",
        "prm_ucp_browse_packages",
        "prm_ucp_change_info",
        "prm_ucp_change_password",
        "prm_ucp_change_profile",
        "prm_ucp_data_usage",
        "prm_ucp_extend",
        "prm_ucp_login",
        "prm_ucp_sessions",
        "prm_ucp_support"
    ]
}
```

### 18. Balance Info

**Method:** `GET`  
**URL:** `http://{{IP-or-Domain}}/user/api/index.php/api/dashboard`  
**Auth:** bearer

**مثال استجابة: Balance Info Request example** — HTTP 200 OK
- Request URL: `http://{{IP-or-Domain}}/user/api/index.php/api/dashboard`
- Content-Type: application/json
```json
{
    "status": 200,
    "data": {
        "remaining_days": 0,
        "remaining_traffic": "_",
        "remaining_uptime": "_",
        "balance": "0.00",
        "unpaid_invoices": 1,
        "loan": {
            "rx_mb": null,
            "tx_mb": null,
            "rxtx_mb": null,
            "days": null
        }
    }
}
```

### 19. Profiles / Services

**Method:** `GET`  
**URL:** `http://{{IP-or-Domain}}/user/api/index.php/api/service`  
**Auth:** bearer

**مثال استجابة: Profiles response Example** — HTTP 200 OK
- Request URL: `http://{{IP-or-Domain}}/user/api/index.php/api/service`
- Content-Type: application/json
```json
{
    "status": 200,
    "data": {
        "profile_name": "default-2Mbit-1Month",
        "description": null,
        "expiration": "2020-09-24 13:48:34",
        "profile_id": 1,
        "status": false,
        "price": 20,
        "subscription_status": {
            "status": false,
            "traffic": true,
            "expiration": false,
            "uptime": true
        },
        "limits": {
            "rx_bytes": null,
            "tx_bytes": null,
            "rxtx_bytes": null,
            "uptime_seconds": null
        }
    }
}
```

### 20. Packages

**Method:** `GET`  
**URL:** `http://{{IP-or-Domain}}/user/api/index.php/api/packages`  
**Auth:** bearer

**الوصف (كما في التوثيق):**

Get the available subscriptions

**مثال استجابة: Packages ** — HTTP 200 OK
- Request URL: `http://{{IP-Or-Domain}}/user/api/index.php/api/packages`
- Content-Type: application/json
```json
{
    "status": 200,
    "data": [
        {
            "id": 1,
            "name": "default-2Mbit-1Month",
            "description": null,
            "price": 20
        },
        {
            "id": 2,
            "name": "band_1",
            "description": null,
            "price": 10
        }
    ]
}
```

### 21. Menus

**Method:** `GET`  
**URL:** `http://{{IP-or-Domain}}/user/api/index.php/api/resources/menu`  
**Auth:** bearer

**الوصف (كما في التوثيق):**

Returns menus and their respective links for web-based UIs

**مثال استجابة: Menus Example** — HTTP 200 OK
- Request URL: `http://{{IP-or-Domain}}/user/api/index.php/api/resources/menu`
- Content-Type: application/json
```json
[
    {
        "name": "account",
        "title": "menu_account",
        "icon": "fas fa-user",
        "link": "/account",
        "weight": 0,
        "parent": "root",
        "acl": "any"
    },
    {
        "name": "billing",
        "title": "menu_billing",
        "icon": "fas fa-book-open",
        "link": "billing",
        "weight": 0,
        "parent": "root",
        "acl": "prm_ucp_billing"
    },
    {
        "name": "invoices",
        "title": "menu_invoices",
        "icon": "fas fa-none",
        "link": "/invoices",
        "weight": 0,
        "parent": "billing",
        "acl": "prm_ucp_billing"
    },
    {
        "name": "payments",
        "title": "menu_payments",
        "icon": "fas fa-none",
        "link": "/payments",
        "weight": 0,
        "parent": "billing",
        "acl": "prm_ucp_billing"
    },
    {
        "name": "journal",
        "title": "menu_journal",
        "icon": "fas fa-none",
        "link": "/journal",
        "weight": 0,
        "parent": "billing",
        "acl": "prm_ucp_billing"
    },
    {
        "name": "date_usage",
        "title": "menu_data_usage",
        "icon": "fas fa-chart-area",
        "link": "/data",
        "weight": 4,
        "parent": "root",
        "acl": "prm_ucp_data_usage"
    },
    {
        "name": "sessions",
        "title": "menu_sessions",
        "icon": "fas fa-list",
        "link": "/sessions",
        "weight": 4,
        "parent": "root",
        "acl": "prm_ucp_sessions"
    },
    {
        "name": "packages",
        "title": "menu_packages",
        "icon": "fas fa-puzzle-piece",
        "link": "/packages",
        "weight": 5,
        "parent": "root",
        "acl": "prm_ucp_browse_packages"
    },
    {
        "name": "support",
        "title": "menu_support",
        "icon": "fas fa-life-ring",
        "link": "/support",
        "weight": 9,
        "parent": "root",
        "acl": "prm_ucp_support"
    }
]
```

### 22. Get Extensions

**Method:** `GET`  
**URL:** `http://{{IP-or-Domain}}/user/api/index.php/api/extensions/2`  
**Auth:** bearer

**الوصف (كما في التوثيق):**

Returns a full list of the available subscriptions extensions

**مثال استجابة: Get Extensions Example** — HTTP 200 OK
- Request URL: `http://{{IP-or-Domain}}/user/api/index.php/api/extensions/2`
- Content-Type: application/json
```json
{
    "status": 200,
    "data": [
        {
            "name": "extension test",
            "id": 3,
            "price": 10
        },
        {
            "name": "Extension test 2",
            "id": 4,
            "price": 100
        }
    ]
}
```


---

## المجلد: Users - List

This interface lists all users belonging to you and to your sub-managers

### 23. Users List

**Method:** `POST`  
**URL:** `http://{{IP-or-Domain}}/admin/api/index.php/api/index/user`  
**Auth:** bearer

**الوصف (كما في التوثيق):**

show all users and basic info about users status, the following body parameters to reteive user list data:

### "payload" it must be encrypt the following parameters which must be a  JSON format:

```
- "page" for pagination of list (number).
- "count" number of data in single page (number).
- "sortBy" sort data due to selected field.
- "diraction" diraction of selected field sort (asc/desc).
- "columns" show the select field inside this array :
        -"n_row",
        -"id",
        -"username"
        -"firstname"
        -"lastname"
        -"expiration"
        -"parent_username"
        -"name"
        -"balance"
        -"traffic"
        -"city"
        -"static_ip"
        -"notes"
        -"last_online"
        -"company"
        -"simultaneous_sessions"
        -"used_traffic"
        -"phone"
        -"address"
        -"contract_id"
```

### decrypted payload JSON use in example :

```
{
    page : 1,
    count : 10,
    sortBy : "username",
    direction : "asc",
    search : "",
    columns : [
        "id",
        "username",
        "firstname",
        "lastname",
        "expiration",
        "parent_username",
        "name",
        "traffic"
        ]
}
```

**Body (urlencoded):**
- `payload` = `<text encrypted by CryptoJS>`

**مثال استجابة: Users List** — HTTP 200 OK
- Request URL: `http://demo4.sasradius.com/admin/api/index.php/api/index/user`
- Request body: `payload=U2FsdGVkX1+ouOJqSPKqZq8Siky9o9jNv8qK+XQutKJVOat3NCiDqGTX8OUAm7pyhF97fQtgdqIR5HuTttzdXMkGJFrpwDIW5iscky00Ko4lFl408/nLaIGJVeaKjSYjKbmhI7LBh3bdB+zSHMmr9KWJkozEqDGWRG0BIrozQ0xsApc3Eoa8PYDB8Sz90ClqK8tRyasennw/dD3ZAW/xGUXEOonsItMtqCwU68HwDXWSipPWPZcZlOTibGlJhc/qhdAmAPi8ztq6PPckWYpgQdTL8YLWky+0OZcIj2Ir2LLJUM3I5I7TcJOm8CH6YDBsiMayms9w2Pnm3xDzyVSwPDOOYWJYR+gRxg6C5GV0z+J2Qqz5YDV7d0Rg02mXbWYvWK9g/2p6jZ2AzO4bgsOk/jbZNuyuzKJJlWYf0LGEwGB4kf5yoWO/ufM6x9laQTwE`
- Content-Type: application/json
```json
{
    "current_page": 1,
    "data": [
        {
            "id": 2,
            "username": "snono",
            "firstname": "Snono",
            "lastname": "Test",
            "city": null,
            "phone": "1111111111",
            "profile_id": 1,
            "balance": "0.00",
            "expiration": "2020-07-15 14:56:55",
            "last_online": null,
            "parent_id": 2,
            "email": "test@test.com",
            "static_ip": null,
            "enabled": 1,
            "company": "Snono Systems",
            "notes": null,
            "simultaneous_sessions": 1,
            "address": null,
            "contract_id": null,
            "created_at": "2020-07-15 11:57:56",
            "n_row": 1,
            "status": {
                "status": true,
                "traffic": true,
                "expiration": true,
                "uptime": true
            },
            "online_status": 0,
            "used_traffic": 0,
            "parent_username": "manager1",
            "profile_details": {
                "id": 1,
                "name": "default-2Mbit-1Month",
                "type": 0
            },
            "daily_traffic_details": null
        },
        {
            "id": 1,
            "username": "user1",
            "firstname": "user",
            "lastname": "1",
            "city": null,
            "phone": null,
            "profile_id": 1,
            "balance": "-20.00",
            "expiration": "2019-09-28 14:19:33",
            "last_online": null,
            "parent_id": 2,
            "email": null,
            "static_ip": null,
            "enabled": 1,
            "company": null,
            "notes": null,
            "simultaneous_sessions": 1,
            "address": null,
            "contract_id": null,
            "created_at": "2019-07-25 09:01:39",
            "n_row": 2,
            "status": {
                "status": false,
                "traffic": true,
                "expiration": false,
                "uptime": true
            },
            "online_status": 0,
            "used_traffic": 0,
            "parent_username": "manager1",
            "profile_details": {
                "id": 1,
                "name": "default-2Mbit-1Month",
                "type": 0
            },
            "daily_traffic_details": null
        }
    ],
    "first_page_url": "http://demo4.sasradius.com/admin/api/index.php/api/index/user?page=1",
    "from": 1,
    "last_page": 1,
    "last_page_url": "http://demo4.sasradius.com/admin/api/index.php/api/index/user?page=1",
    "next_page_url": null,
    "path": "http://demo4.sasradius.com/admin/api/index.php/api/index/user",
    "per_page": 10,
    "prev_page_url": null,
    "to": 2,
    "total": 2
}
```

### 24. Users List - with search

**Method:** `POST`  
**URL:** `http://demo4.sasradius.com/admin/api/index.php/api/index/user`  
**Auth:** bearer

**الوصف (كما في التوثيق):**

show all users and basic info about users status, the following body parameters to reteive user list data:

- "payload" it must be encrypt the following parameters which must be a  JSON format:
- "page" for pagination of list (number).
- "count" number of data in single page (number).
- "sortBy" sort data due to selected field.
- "diraction" diraction of selected field sort (asc/desc).
- "columns" show the select field inside this array :
  -"n_row",
  -"id",
  -"username"
  -"firstname"
  -"lastname"
  -"expiration"
  -"parent_username"
  -"name"
  -"balance"
  -"traffic"
  -"city"
  -"static_ip"
  -"notes"
  -"last_online"
  -"company"
  -"simultaneous_sessions"
  -"used_traffic"
  -"phone"
  -"address"
  -"contract_id"

decrypted payload JSON use in example : 
{
    page : 1,
    count : 10,
    sortBy : "username",
    direction : "asc",
    search : "",
    columns : [
        "id",
        "username",
        "firstname",
        "lastname",
        "expiration",
        "parent_username",
        "name",
        "traffic"
        ]
}

**Body (urlencoded):**
- `payload` = `<text encrypted by CryptoJS>`

**مثال استجابة: Users List** — HTTP 200 OK
- Request URL: `http://demo4.sasradius.com/admin/api/index.php/api/index/user`
- Request body: `payload=U2FsdGVkX1+ouOJqSPKqZq8Siky9o9jNv8qK+XQutKJVOat3NCiDqGTX8OUAm7pyhF97fQtgdqIR5HuTttzdXMkGJFrpwDIW5iscky00Ko4lFl408/nLaIGJVeaKjSYjKbmhI7LBh3bdB+zSHMmr9KWJkozEqDGWRG0BIrozQ0xsApc3Eoa8PYDB8Sz90ClqK8tRyasennw/dD3ZAW/xGUXEOonsItMtqCwU68HwDXWSipPWPZcZlOTibGlJhc/qhdAmAPi8ztq6PPckWYpgQdTL8YLWky+0OZcIj2Ir2LLJUM3I5I7TcJOm8CH6YDBsiMayms9w2Pnm3xDzyVSwPDOOYWJYR+gRxg6C5GV0z+J2Qqz5YDV7d0Rg02mXbWYvWK9g/2p6jZ2AzO4bgsOk/jbZNuyuzKJJlWYf0LGEwGB4kf5yoWO/ufM6x9laQTwE`
- Content-Type: application/json
```json
{
    "current_page": 1,
    "data": [
        {
            "id": 2,
            "username": "snono",
            "firstname": "Snono",
            "lastname": "Test",
            "city": null,
            "phone": "1111111111",
            "profile_id": 1,
            "balance": "0.00",
            "expiration": "2020-07-15 14:56:55",
            "last_online": null,
            "parent_id": 2,
            "email": "test@test.com",
            "static_ip": null,
            "enabled": 1,
            "company": "Snono Systems",
            "notes": null,
            "simultaneous_sessions": 1,
            "address": null,
            "contract_id": null,
            "created_at": "2020-07-15 11:57:56",
            "n_row": 1,
            "status": {
                "status": true,
                "traffic": true,
                "expiration": true,
                "uptime": true
            },
            "online_status": 0,
            "used_traffic": 0,
            "parent_username": "manager1",
            "profile_details": {
                "id": 1,
                "name": "default-2Mbit-1Month",
                "type": 0
            },
            "daily_traffic_details": null
        },
        {
            "id": 1,
            "username": "user1",
            "firstname": "user",
            "lastname": "1",
            "city": null,
            "phone": null,
            "profile_id": 1,
            "balance": "-20.00",
            "expiration": "2019-09-28 14:19:33",
            "last_online": null,
            "parent_id": 2,
            "email": null,
            "static_ip": null,
            "enabled": 1,
            "company": null,
            "notes": null,
            "simultaneous_sessions": 1,
            "address": null,
            "contract_id": null,
            "created_at": "2019-07-25 09:01:39",
            "n_row": 2,
            "status": {
                "status": false,
                "traffic": true,
                "expiration": false,
                "uptime": true
            },
            "online_status": 0,
            "used_traffic": 0,
            "parent_username": "manager1",
            "profile_details": {
                "id": 1,
                "name": "default-2Mbit-1Month",
                "type": 0
            },
            "daily_traffic_details": null
        }
    ],
    "first_page_url": "http://demo4.sasradius.com/admin/api/index.php/api/index/user?page=1",
    "from": 1,
    "last_page": 1,
    "last_page_url": "http://demo4.sasradius.com/admin/api/index.php/api/index/user?page=1",
    "next_page_url": null,
    "path": "http://demo4.sasradius.com/admin/api/index.php/api/index/user",
    "per_page": 10,
    "prev_page_url": null,
    "to": 2,
    "total": 2
}
```

### 25. User - Create

**Method:** `POST`  
**URL:** `http://{{IP-or-Domain}}/admin/api/index.php/api/user`  
**Auth:** bearer

**الوصف (كما في التوثيق):**

- "payload" it must be encrypt the following parameters which must be a  JSON format:

### decrypted payload JSON use in example :

| Field | Type | Description |

| username | string | Required A login name by which the user will dial-up |

| enabled | number | Required 1 for enable, 0 for disable user login |

| password | string | Required login password to be used for dial-up |

| confirm_password | string |  |

| profile_id | number | Required profile associated with the user |

| parent_id | number | Required The owner of this user |

| site_id | string | Required |

| password | string | Required |

| password | string | Required |

| password | string | Required |

| password | string | Required |

| password | string | Required |

| password | string | Required |

```
{
    "username":"test",
    "enabled":1,
    "password":"1111",
    "confirm_password":"1111",
    "profile_id":1,
    "parent_id":2,
    "site_id":0,
    "mac_auth":0,
    "allowed_macs":null,
    "firstname":"Test",
    "lastname":"API",
    "company":"Snono Systems",
    "email":"test@test.com",
    "phone":null,
    "city":null,
    "address":null,
    "apartment":null,
    "street":null,
    "contract_id":null,
    "national_id":null,
    "notes":null,
    "expiration":"2020-07-15 15:04:24",
    "simultaneous_sessions":1,
    "static_ip":null,
    "mikrotik_winbox_group":null,
    "mikrotik_framed_route":null,
    "mikrotik_addresslist":null,
    "mikrotik_ipv6_prefix":null,
    "auto_renew":0,
    "user_type":"0"
    }
```

**Body (urlencoded):**
- `payload` = `<text encrypted by CryptoJS>`

**مثال استجابة: User - Create** — HTTP 200 OK
- Request URL: `http://demo4.sasradius.com/admin/api/index.php/api/user`
- Request body: `payload=U2FsdGVkX1+xzyDfJmQlRtCZFDW04VSbOd2syBxtQS2FiPcilfOWmaKm5tdkIXM2bFk/idrhqaHmO32/5DzDYd23kki3bfVSBiCZorn++KR8JG5Cr8ctF8dlbjOXom5YC3pjdT5YKM1meVRBoy+CykibFPLSxkGzjA1jpnmT1xBaQKvrlK6/hsIfmmQkwHdC/YDA7m6fMhhIPRkeoGLSbhOqnbJkzhHqisEeDi8ve3pG7cCedxWASO4zdRY41iLOqaXJO6NXqonPnKFyUKDTAyAm1SMiHCJu2bm5bJwWt3YUJF8mMKz2h6enevTX+WXK9rkAxGo7UU9tnjSQQPVRwFdI1ewxKwGk5QoT1tcrFRm+blLVQ9kdewzHuwc3oLatGhclmNw3KHpVOuwjCAegjSujvC5M++eb0aillqiLt6xHmhGqh9otVUtXpnMMxQuRSYnY/Uz6bNCiD3WhcpFWjQ2dxhH+g3Cu421naO1lA0qzwVMgMHMw9z6UtxI2ucjqJIm5HDPuvN+sBkYhQQvXvh2O4kWmxE/DEiDQ3obpeeJ/eFSFh61+MiRDhSutoJODmcz34AZAFMZggy+FgFJh9VEuWhzasvvwSV2NJVGwcc4UcOWKF09vOS+WweQ/S5qw13nJyAKl8/Am1XrPT8RpDAXihRNGIv713OE03vZ7Z2MuX/HTffor/1Ag6O8VA5Gf9p5QTRbybaMlLxSs0rDo07btMTokJ8DB/qZ9oxRtBdxQAzREYGC8Yh7rRdZQJFBNiNlZ1RZksx86apWxUDC85u0KiRyWjxGVv07scvwm+mA=`
- Content-Type: application/json
```json
{
    "status": 200,
    "message": "rsp_save_success"
}
```

### 26. User - All Data

**Method:** `GET`  
**URL:** `http://demo4.sasradius.com/admin/api/index.php/api/user/2`  
**Auth:** bearer

**الوصف (كما في التوثيق):**

Retrieve data necessary for activation

**Body (raw):**
```

```

**مثال استجابة: User - All Data** — HTTP 200 OK
- Request URL: `http://demo4.sasradius.com/admin/api/index.php/api/user/2`
- Content-Type: application/json
```json
{
    "status": 200,
    "data": {
        "id": 2,
        "username": "snonoactivate",
        "profile_id": 1,
        "enabled": 1,
        "expiration": "2020-07-29 11:00:35",
        "address": null,
        "city": null,
        "country": null,
        "mac_auth": 0,
        "static_ip": null,
        "group_id": null,
        "service": null,
        "firstname": null,
        "lastname": null,
        "email": null,
        "phone": null,
        "company": null,
        "apartment": null,
        "street": null,
        "contract_id": null,
        "parent_id": 1,
        "created_at": "2020-07-29 08:00:44",
        "updated_at": "2020-07-29 08:00:44",
        "deleted_at": null,
        "last_ip_address": null,
        "last_online": null,
        "user_type": 0,
        "created_by": "1",
        "national_id": null,
        "simultaneous_sessions": 1,
        "mikrotik_winbox_group": null,
        "mikrotik_framed_route": null,
        "mikrotik_addresslist": null,
        "mikrotik_ipv6_prefix": null,
        "balance": "0.00",
        "notes": null,
        "picture": null,
        "pin_tries": 0,
        "site_id": null,
        "gps_lat": null,
        "gps_lng": null,
        "last_profile_id": null,
        "auto_renew": 0,
        "profile_name": "default-2Mbit-1Month",
        "status": {
            "status": true,
            "traffic": true,
            "expiration": true,
            "uptime": true
        },
        "profileChange": false,
        "parent_username": "admin"
    }
}
```

### 27. User - Rename

**Method:** `POST`  
**URL:** `http://{{IP-or-Domain}}/admin/api/index.php/api/user/rename/{{user_id}}`  
**Auth:** bearer

**الوصف (كما في التوثيق):**

- user_id target user
- new_username the new username

### decrypted payload JSON use in example :

```
{
    "new_username": <new new_username from input field>
}
```

**Body (urlencoded):**
- `payload` = `<text encrypted by CryptoJS>`

**مثال استجابة: User - Rename** — HTTP 200 OK
- Request URL: `http://demo4.sasradius.com/admin/api/index.php/api/user/rename/2`
- Request body: `payload=U2FsdGVkX1/KADbwU/Gnuovl9o9REIKum8Ox9SqZNvQRj8CNmg4Omenn00OJW8i1`
- Content-Type: application/json
```json
{
    "status": 200
}
```

### 28. User - Activation Data

**Method:** `GET`  
**URL:** `http://{{IP-or-Domain}}/admin/api/index.php/api/user/activationData/{{user_id}}`  
**Auth:** bearer

**الوصف (كما في التوثيق):**

Retrieve data necessary for activation

**Body (raw):**
```

```

**مثال استجابة: User - Activation Data** — HTTP 200 OK
- Request URL: `http://demo4.sasradius.com/admin/api/index.php/api/user/activationData/2`
- Content-Type: application/json
```json
{
    "data": {
        "username": "snonoactivate",
        "profile_name": "default-2Mbit-1Month",
        "profile_id": 1,
        "manager_balance": "$ 20.00",
        "user_balance": "$ 0.00",
        "user_expiration": "2020-07-27 14:26:46",
        "unit_price": "$ 20.00",
        "profile_duration": "1 month(s)",
        "profile_traffic": "0 B",
        "profile_dl_traffic": "0 B",
        "profile_ul_traffic": "0 B",
        "profile_description": null,
        "vat": "$ 0.00",
        "units": 1,
        "required_amount": "$ 20.00",
        "n_required_amount": 20,
        "reward_points": 0,
        "required_points": 0,
        "reward_points_balance": 0
    },
    "status": 200
}
```

### 29. User - Activation Service

**Method:** `POST`  
**URL:** `http://demo4.sasradius.com/admin/api/index.php/api/user/activate`  
**Auth:** bearer

**الوصف (كما في التوثيق):**

- user_id target user
- new_username the new username

### decrypted payload JSON use in example :

```
{"method":"credit","pin":"","user_id":"3","money_collected":true,"comments":"Activation comment goes here!","issue_invoice":true,"transaction_id":"4c0c2dfe-7530-ae94-2796-7e18029f1363"}
```

**Body (urlencoded):**
- `payload` = `U2FsdGVkX1+YmKrbRbd614PGm9Wcpu6VtnmGG/KGCsqTpxxfWy+zQwIqUM2VEkpZijHFsqIPGYMOPpZ4rfuNTUiHOQzVNTjBosSroiBEnjApVm/o+cTnoDiaXoStc/MN8iHoqEwXUARjmCmqu3wDjVMPIPFM9OKPt4Nud1y+0+bEdu7w8rUI/Osa0/2fjAAum47wlczGAZt3Rvje5H4msCMQ0OneApjxpBwirLXSH+SG1UPAbkyu+u1VPJ4lTBf9Ann8T4LgX4C/tngDc/x+Og==`

**مثال استجابة: User - Activation** — HTTP 200 OK
- Request URL: `http://demo4.sasradius.com/admin/api/index.php/api/user/activate`
- Request body: `payload=U2FsdGVkX1+YmKrbRbd614PGm9Wcpu6VtnmGG/KGCsqTpxxfWy+zQwIqUM2VEkpZijHFsqIPGYMOPpZ4rfuNTUiHOQzVNTjBosSroiBEnjApVm/o+cTnoDiaXoStc/MN8iHoqEwXUARjmCmqu3wDjVMPIPFM9OKPt4Nud1y+0+bEdu7w8rUI/Osa0/2fjAAum47wlczGAZt3Rvje5H4msCMQ0OneApjxpBwirLXSH+SG1UPAbkyu+u1VPJ4lTBf9Ann8T4LgX4C/tngDc/x+Og==`
- Content-Type: text/html; charset=UTF-8
```json
(فارغ)
```

### 30. User - Add Traffic

**Method:** `POST`  
**URL:** `http://demo4.sasradius.com/admin/api/index.php/api/user/addTraffic`  
**Auth:** bearer

**الوصف (كما في التوثيق):**

- user_id target user
- username the username
- amount the amount of traffic in MB
- target the is:
- rxtx_mbytes download + upload traffic
- rx_mbytes download traffic only
- tx_mbytes upload traffic only

### decrypted payload JSON use in example :

```
{"user_id":1,"username":"ahmed@shl","amount":1024,"comment":"add traffic to user","transaction_id":"a5b2d74f-d5bd-60da-0f12-95be2c80a470","target":"rxtx_mbytes"}
```

**Body (urlencoded):**
- `payload` = `U2FsdGVkX18ITHulA7h8MOmzCAbz1FeRJXXuZHHd+lgwpyhT/kEDcCbq+irK7CVJV+2BOhu2btAxWD1cDhpt558DO/SN2TKZz9yAHcraHRDBVHs/WqF0KqiLAUq6Hruj/pdWTEXpX5DIKINQopaXwGc8HUoFJSrwBtCpuBf4tag/NUM/RhgwDHVVbRT/Bl2qUlZPbVPjaFomR/8d7kG8fQ==`

### 31. User - Extension Data

**Method:** `GET`  
**URL:** `http://demo4.sasradius.com/admin/api/index.php/api/user/extensionData/3`  
**Auth:** bearer

**الوصف (كما في التوثيق):**

Retrieve data necessary for activation

**Body (raw):**
```

```

**مثال استجابة: User - Extension Data** — HTTP 200 OK
- Request URL: `http://demo4.sasradius.com/admin/api/index.php/api/user/extensionData/3`
- Content-Type: application/json
```json
{
    "status": 200,
    "data": {
        "remaining_rxtx": "0 B",
        "remaining_rx": "0 B",
        "remaining_tx": "0 B",
        "remaining_uptime": null,
        "expiration": "2020-06-29 10:34:31",
        "profile_name": "default-2Mbit-1Month",
        "profile_id": 1,
        "username": "snonoactivate",
        "balance": "$ 20.00",
        "reward_points_balance": 0,
        "reward_points": null,
        "required_points": null
    }
}
```

### 32. User - Extension Profiles

**Method:** `GET`  
**URL:** `http://demo4.sasradius.com/admin/api/index.php/api/allowedExtensions/{{profile_id}}`  
**Auth:** bearer

**الوصف (كما في التوثيق):**

Retrieve data necessary for activation

**Body (raw):**
```

```

**مثال استجابة: User - Extension Profiles** — HTTP 200 OK
- Request URL: `http://demo4.sasradius.com/admin/api/index.php/api/allowedExtensions/1`
- Content-Type: application/json
```json
{
    "0": 200,
    "status": 200,
    "data": [
        {
            "id": 2,
            "name": "default-2Mbit-1Month_EXT"
        },
        {
            "id": 3,
            "name": "default-2Mbit-1Month_EXT_BOOST"
        }
    ]
}
```

### 33. User - Extend Service

**Method:** `POST`  
**URL:** `http://demo4.sasradius.com/admin/api/index.php/api/user/extend`  
**Auth:** bearer

**الوصف (كما في التوثيق):**

- user_id target user
- new_username the new username

two method to pay thorugh it credit, reward_points

### decrypted payload JSON use in example :

```
{"user_id":"2","profile_id":"2","method":"reward_points","transaction_id":"e6ad8a4e-2e94-64dd-8f76-f06de53614f2"}
```

**Body (urlencoded):**
- `payload` = `U2FsdGVkX1/Edtc9rU5XMRHspGrib0pLJVc+5xE+yP2FPAGEm7tcGwZeUds6s3b3e+1Vn8gB2bmXMXopxzwXy9My2DcHMebTBag7/YuwVKnlv1B0Eui3eq+RJD+SeIJbjAgTdXKdu0bMM9720MGrsN4afVnTqtZb/PzAMtsTRx+9005vNS/S4U7ATYYlAwSa`

**مثال استجابة: User - Extend Service** — HTTP 200 OK
- Request URL: `http://demo4.sasradius.com/admin/api/index.php/api/user/extend`
- Request body: `payload=U2FsdGVkX1/Edtc9rU5XMRHspGrib0pLJVc+5xE+yP2FPAGEm7tcGwZeUds6s3b3e+1Vn8gB2bmXMXopxzwXy9My2DcHMebTBag7/YuwVKnlv1B0Eui3eq+RJD+SeIJbjAgTdXKdu0bMM9720MGrsN4afVnTqtZb/PzAMtsTRx+9005vNS/S4U7ATYYlAwSa`
- Content-Type: text/html; charset=UTF-8
```json
(فارغ)
```

### 34. User - Change Profile

**Method:** `POST`  
**URL:** `http://demo4.sasradius.com/admin/api/index.php/api/user/changeProfile`  
**Auth:** bearer

**الوصف (كما في التوثيق):**

note : User already active. Profile change will be applied on next expiration date
two method to pay thorugh it credit, reward_points
this request need all profiles request 

### decrypted payload JSON use in example :

```
{"user_id":"2","profile_id":"2","method":"reward_points","transaction_id":"e6ad8a4e-2e94-64dd-8f76-f06de53614f2"}
```

**Body (urlencoded):**
- `payload` = `U2FsdGVkX1+ePB41HPbmYDeg3rJ2tvjIAPMSG6pIn/3PPjRDmYaEn4+uPblJNPx2EJFv7bvSH2eucyfCSbqxvWXTQPYKEVN4RUw3PaVSA9I=`

**مثال استجابة: User - Extend Service** — HTTP 200 OK
- Request URL: `http://demo4.sasradius.com/admin/api/index.php/api/user/extend`
- Request body: `payload=U2FsdGVkX1/Edtc9rU5XMRHspGrib0pLJVc+5xE+yP2FPAGEm7tcGwZeUds6s3b3e+1Vn8gB2bmXMXopxzwXy9My2DcHMebTBag7/YuwVKnlv1B0Eui3eq+RJD+SeIJbjAgTdXKdu0bMM9720MGrsN4afVnTqtZb/PzAMtsTRx+9005vNS/S4U7ATYYlAwSa`
- Content-Type: text/html; charset=UTF-8
```json
(فارغ)
```

### 35. User - Deposit

**Method:** `POST`  
**URL:** `http://demo4.sasradius.com/admin/api/index.php/api/user/deposit`  
**Auth:** bearer

**الوصف (كما في التوثيق):**

### decrypted payload JSON use in example :

```
{"user_id":2,"user_username":"snonoactivate","amount":10,"comment":"deposit comment goes here!","transaction_id":"e1366ad4-3b92-3276-6839-018a0e6c04af"}
```

**Body (urlencoded):**
- `payload` = `U2FsdGVkX18ZxnAmHj0qBlGIH7FbMf8W4RVMz/1Z0l1eahUFAs4tbNkeQtFm0p0jk7qojg2J2IlxWmeDULJxeOaQnjJd/EYEIjaQTOq+6o0hGCvaRrdhUQSheZwiBKOynLa4vLUoyLN8kOTsjTs+OtNtpUDIDUC+y9gkczw2y8i/Yi8Nrx/Qt7uFXR4Qe+pzEDEECFxD7M+K5HEGYlhr2SPkot73Ue+uTmm0j5t+pkA=`

**مثال استجابة: User - Deposit** — HTTP 200 OK
- Request URL: `http://demo4.sasradius.com/admin/api/index.php/api/user/deposit`
- Request body: `payload=U2FsdGVkX18ZxnAmHj0qBlGIH7FbMf8W4RVMz/1Z0l1eahUFAs4tbNkeQtFm0p0jk7qojg2J2IlxWmeDULJxeOaQnjJd/EYEIjaQTOq+6o0hGCvaRrdhUQSheZwiBKOynLa4vLUoyLN8kOTsjTs+OtNtpUDIDUC+y9gkczw2y8i/Yi8Nrx/Qt7uFXR4Qe+pzEDEECFxD7M+K5HEGYlhr2SPkot73Ue+uTmm0j5t+pkA=`
- Content-Type: text/html; charset=UTF-8
```json
(فارغ)
```

### 36. User - Withdraw

**Method:** `POST`  
**URL:** `http://demo4.sasradius.com/admin/api/index.php/api/user/withdraw`  
**Auth:** bearer

**الوصف (كما في التوثيق):**

### decrypted payload JSON use in example :

```
{"user_id":2,"user_username":"snonoactivate","amount":10,"comment":"","transaction_id":"eec7f5bf-2379-5cdd-a63e-32308ad2adc2"}
```

**Body (urlencoded):**
- `payload` = `U2FsdGVkX18QYU98dWITd5ACD46zfwFDxuruH5VN1+kScvYXtO+wgq0nUCF3xNp7jnBKu5P2PA3rFduqLcCFoTuklZYkfK4Rw2vMytwY4TSB4VvNjY7XIeCqRRhZlhRnN01MIYizL6QtvO1kMQXk1/ZDCEa1W6pg8uGCskgox43QySS/kPR5I29lU3umV1zb`

**مثال استجابة: User - Withdraw** — HTTP 200 OK
- Request URL: `http://demo4.sasradius.com/admin/api/index.php/api/user/withdraw`
- Request body: `payload=U2FsdGVkX18QYU98dWITd5ACD46zfwFDxuruH5VN1+kScvYXtO+wgq0nUCF3xNp7jnBKu5P2PA3rFduqLcCFoTuklZYkfK4Rw2vMytwY4TSB4VvNjY7XIeCqRRhZlhRnN01MIYizL6QtvO1kMQXk1/ZDCEa1W6pg8uGCskgox43QySS/kPR5I29lU3umV1zb`
- Content-Type: application/json
```json
{
    "status": 200,
    "message": "rsp_amount_deducted"
}
```

### 37. User - Cancel Data

**Method:** `GET`  
**URL:** `http://demo4.sasradius.com/admin/api/index.php/api/user/refundData/2`  
**Auth:** bearer

**الوصف (كما في التوثيق):**

Retrieve data necessary for activation

**Body (raw):**
```

```

**مثال استجابة: User - Cancel Data** — HTTP 200 OK
- Request URL: `http://demo4.sasradius.com/admin/api/index.php/api/user/refundData/2`
- Content-Type: application/json
```json
{
    "status": 200,
    "data": {
        "id": 2,
        "username": "snonoactivate",
        "expiration": "2020-08-29 11:00:35",
        "created_at": "2020-07-29 09:23:55",
        "old_expiration": "2020-07-29 11:00:35",
        "remaining_days": "31 day",
        "profile_name": "default-2Mbit-1Month",
        "transaction": "6FHCxI1bk5dot88",
        "price": "$ 20.00",
        "manager_name": "admin",
        "manager_id": 1,
        "refund_amount": "$ 20"
    }
}
```

### 38. User - Cancel Service

**Method:** `GET`  
**URL:** `http://demo4.sasradius.com/admin/api/index.php/api/user/refund/2`  
**Auth:** bearer

**الوصف (كما في التوثيق):**

Retrieve data necessary for activation

**Body (raw):**
```

```

**مثال استجابة: User - Cancel Service** — HTTP 200 OK
- Request URL: `http://demo4.sasradius.com/admin/api/index.php/api/user/refund/2`
- Content-Type: application/json
```json
{
    "status": 200
}
```

### 39. User - Delete

**Method:** `DELETE`  
**URL:** `http://demo4.sasradius.com/admin/api/index.php/api/user/2`  
**Auth:** bearer

**الوصف (كما في التوثيق):**

Retrieve data necessary for activation

**Body (raw):**
```

```

**مثال استجابة: User - Delete** — HTTP 200 OK
- Request URL: `http://demo4.sasradius.com/admin/api/index.php/api/user/2`
- Content-Type: application/json
```json
{
    "status": 200,
    "message": "rsp_user_deleted"
}
```


---

## المجلد: Users - Form

### 40. User - Overview

**Method:** `GET`  
**URL:** `http://demo4.sasradius.com/admin/api/index.php/api/user/overview/2`  
**Auth:** bearer

**الوصف (كما في التوثيق):**

require a managers simple list

**مثال استجابة: User - Overview** — HTTP 200 OK
- Request URL: `http://demo4.sasradius.com/admin/api/index.php/api/user/overview/2`
- Content-Type: application/json
```json
{
    "data": {
        "username": "snonoactivate",
        "parent_username": "admin",
        "profile_name": "default-2Mbit-1Month",
        "profile_id": 1,
        "expiration": "2020-07-29 11:00:35",
        "status": false,
        "created_at": "29 Jul 2020 - 08:00:44",
        "created_by": "admin",
        "balance": 0,
        "password": "1111",
        "firstname": "Snono",
        "lastname": "Test",
        "phone": "+964 7700 826 164",
        "address": "Al Resafah",
        "city": "Baghdad",
        "email": "info@snono-systems.com",
        "remaining_rx": null,
        "remaining_tx": null,
        "remaining_rxtx": null,
        "remaining_uptime": null,
        "next_profile_change": false,
        "pin_tries": 0,
        "last_online": null
    },
    "status": 200
}
```

### 41. User - MAC

**Method:** `GET`  
**URL:** `http://demo4.sasradius.com/admin/api/index.php/api/mac/2`  
**Auth:** bearer

**مثال استجابة: User - MAC** — HTTP 200 OK
- Request URL: `http://demo4.sasradius.com/admin/api/index.php/api/mac/2`
- Content-Type: application/json
```json
{
    "status": 200,
    "data": []
}
```

### 42. User - Custom Radius Attribute

**Method:** `GET`  
**URL:** `http://demo4.sasradius.com/admin/api/index.php/api/customRadiusAttribute/user/2`  
**Auth:** bearer

**مثال استجابة: User - Custom Radius Attribute** — HTTP 200 OK
- Request URL: `http://demo4.sasradius.com/admin/api/index.php/api/customRadiusAttribute/user/2`
- Content-Type: application/json
```json
{
    "status": 200,
    "data": []
}
```

### 43. User - Site

**Method:** `GET`  
**URL:** `http://demo4.sasradius.com/admin/api/index.php/api/site`  
**Auth:** bearer

**مثال استجابة: User - Site** — HTTP 200 OK
- Request URL: `http://demo4.sasradius.com/admin/api/index.php/api/site`
- Content-Type: application/json
```json
{
    "data": [
        {
            "id": 0,
            "name": "_default",
            "status": 1
        }
    ],
    "status": 200
}
```

### 44. User - List Profiles

**Method:** `GET`  
**URL:** `http://demo4.sasradius.com/admin/api/index.php/api/list/profile/5`  
**Auth:** bearer

**مثال استجابة: User - List Profiles** — HTTP 200 OK
- Request URL: `http://demo4.sasradius.com/admin/api/index.php/api/list/profile/5`
- Content-Type: application/json
```json
{
    "0": 200,
    "status": 200,
    "data": [
        {
            "id": 1,
            "name": "default-2Mbit-1Month"
        },
        {
            "id": 4,
            "name": "10Mbit-1Month"
        },
        {
            "id": 5,
            "name": "20Mbit-1Month"
        }
    ]
}
```

### 45. User - History

**Method:** `POST`  
**URL:** `http://demo4.sasradius.com/admin/api/index.php/api/index/UserHistory/2`  
**Auth:** bearer

**Body (urlencoded):**
- `payload` = `U2FsdGVkX18ruZpDdaqlCrji9+sSH65R3XCWy3vHuZ6fva9R3Si2XawkPPq/muEDY0JFt1P1r/buDg0st72TTPvUDbHzvwT14yEDa2JhXLsujMW1N3q8YZ7kJ60dWjcMqmfKjovH88IRImFZ/1awdxFmtvE0mAW1+WEEKH5t8mAPLH8rWeuSEUJRnzf7ajW9mm+y8Tn59eU+8XPYd06CxQ==`

**مثال استجابة: User - History** — HTTP 200 OK
- Request URL: `http://demo4.sasradius.com/admin/api/index.php/api/index/UserHistory/2`
- Request body: `payload=U2FsdGVkX18ruZpDdaqlCrji9+sSH65R3XCWy3vHuZ6fva9R3Si2XawkPPq/muEDY0JFt1P1r/buDg0st72TTPvUDbHzvwT14yEDa2JhXLsujMW1N3q8YZ7kJ60dWjcMqmfKjovH88IRImFZ/1awdxFmtvE0mAW1+WEEKH5t8mAPLH8rWeuSEUJRnzf7ajW9mm+y8Tn59eU+8XPYd06CxQ==`
- Content-Type: application/json
```json
{
    "current_page": 1,
    "data": [
        {
            "id": 4,
            "event": "used updated",
            "description": "manager updated user data",
            "created_by_manager_id": 1,
            "created_at": "2020-07-30 10:34:21",
            "manager_details": {
                "id": 1,
                "username": "admin",
                "firstname": "Administrator",
                "lastname": "Snono"
            },
            "user_details": null
        },
        {
            "id": 3,
            "event": "user_created",
            "description": "user created: snonoactivate",
            "created_by_manager_id": 1,
            "created_at": "2020-07-29 08:00:44",
            "manager_details": {
                "id": 1,
                "username": "admin",
                "firstname": "Administrator",
                "lastname": "Snono"
            },
            "user_details": null
        }
    ],
    "first_page_url": "http://demo4.sasradius.com/admin/api/index.php/api/index/UserHistory/2?page=1",
    "from": 1,
    "last_page": 1,
    "last_page_url": "http://demo4.sasradius.com/admin/api/index.php/api/index/UserHistory/2?page=1",
    "next_page_url": null,
    "path": "http://demo4.sasradius.com/admin/api/index.php/api/index/UserHistory/2",
    "per_page": 10,
    "prev_page_url": null,
    "to": 2,
    "total": 2
}
```

### 46. User - Journal

**Method:** `POST`  
**URL:** `http://demo4.sasradius.com/admin/api/index.php/api/index/UserJournal/2`  
**Auth:** bearer

**Body (urlencoded):**
- `payload` = `U2FsdGVkX19oQ/dwpGz2xg7EYPWPHM9huJFHgwtwPXwax34LlCJCYj46cn7BI05EHPeGbtn3CL+FZ1Td5GgcY74IhgFPcTNjC3JmtqwA1/ZdvoX01bZBd8ZIFYY/MASHvVLYlkNP3BKvZTDjwMGUx/F4lTaT6FhjbBgwOowvDW49dvrNlKZTij+VNj+6mITqMPhAoZtviKlzVAocIdrM1jzO3gGfUOQs7LrHqesKrYI=`

**مثال استجابة: User - Journal** — HTTP 200 OK
- Request URL: `http://demo4.sasradius.com/admin/api/index.php/api/index/UserJournal/2`
- Request body: `payload=U2FsdGVkX19oQ/dwpGz2xg7EYPWPHM9huJFHgwtwPXwax34LlCJCYj46cn7BI05EHPeGbtn3CL+FZ1Td5GgcY74IhgFPcTNjC3JmtqwA1/ZdvoX01bZBd8ZIFYY/MASHvVLYlkNP3BKvZTDjwMGUx/F4lTaT6FhjbBgwOowvDW49dvrNlKZTij+VNj+6mITqMPhAoZtviKlzVAocIdrM1jzO3gGfUOQs7LrHqesKrYI=`
- Content-Type: application/json
```json
{
    "data": [],
    "current_page": 1,
    "total": 0
}
```

### 47. User - Network Traffic

**Method:** `POST`  
**URL:** `http://demo4.sasradius.com/admin/api/index.php/api/userNetworksTraffic`  
**Auth:** bearer

**Body (urlencoded):**
- `payload` = `U2FsdGVkX1/Lxy4PUgoCe3BwM/lw38W0ZqNVJGJwOR67gZ6fzJj1VXRPmaVXiI0cXoPd9B3QR+PZnucbfdluXL/F/U9qFV/4B29bKXbWrTqo306kleVagMrPvmjQASmt`

**مثال استجابة: User - Network Traffic** — HTTP 200 OK
- Request URL: `http://demo4.sasradius.com/admin/api/index.php/api/userNetworksTraffic`
- Request body: `payload=U2FsdGVkX1/Lxy4PUgoCe3BwM/lw38W0ZqNVJGJwOR67gZ6fzJj1VXRPmaVXiI0cXoPd9B3QR+PZnucbfdluXL/F/U9qFV/4B29bKXbWrTqo306kleVagMrPvmjQASmt`
- Content-Type: application/json
```json
{
    "status": 200,
    "data": {
        "rx": [
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0
        ],
        "tx": [
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0
        ],
        "total": [
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0
        ]
    }
}
```

### 48. User - Traffic

**Method:** `POST`  
**URL:** `http://demo4.sasradius.com/admin/api/index.php/api/user/traffic`  
**Auth:** bearer

**Body (urlencoded):**
- `payload` = `U2FsdGVkX1/RSOpk2ylaUZcv36LzRfF0YPYxrJKoHOtTJH4oVHJ4vMncqw0RpvkjXeW54fo/d8j1HVpS/Lmuo03brJIW8tLoBiD++W+TOVo=`

**مثال استجابة: User - Traffic** — HTTP 200 OK
- Request URL: `http://demo4.sasradius.com/admin/api/index.php/api/user/traffic`
- Request body: `payload=U2FsdGVkX1/RSOpk2ylaUZcv36LzRfF0YPYxrJKoHOtTJH4oVHJ4vMncqw0RpvkjXeW54fo/d8j1HVpS/Lmuo03brJIW8tLoBiD++W+TOVo=`
- Content-Type: application/json
```json
{
    "status": 200,
    "data": {
        "rx": [
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0
        ],
        "tx": [
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0
        ],
        "total": [
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0
        ],
        "total_real": [
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0
        ],
        "free_traffic": [
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0
        ]
    }
}
```


---

## المجلد: Users - Online List

### 49. Online Users List

**Method:** `POST`  
**URL:** `http://185.95.184.10/admin/api/index.php/api/index/online`  
**Auth:** bearer

**الوصف (كما في التوثيق):**

show all users and basic info about users status, the following body parameters to reteive user list data:

### "payload" it must be encrypt the following parameters which must be a  JSON format:

```
- "page" for pagination of list (number).
- "count" number of data in single page (number).
- "sortBy" sort data due to selected field.
- "diraction" diraction of selected field sort (asc/desc).
- "columns" show the select field inside this array :
        -"n_row",
        -"id",
        -"username"
        -"firstname"
        -"lastname"
        -"expiration"
        -"parent_username"
        -"name"
        -"balance"
        -"traffic"
        -"city"
        -"static_ip"
        -"notes"
        -"last_online"
        -"company"
        -"simultaneous_sessions"
        -"used_traffic"
        -"phone"
        -"address"
        -"contract_id"
```

### decrypted payload JSON use in example :

```
{"page":1,"count":10,"sortBy":null,"direction":"asc","search":"","columns":["id","username","acctoutputoctets","acctinputoctets","user_profile_name","framedipaddress","callingstationid","acctsessiontime","oui"]}
```

**Body (urlencoded):**
- `payload` = `U2FsdGVkX19au+9Oqm4lKZbAUYhwr5cRmyqVmqmBnINETlSAQ0bZAq+UBd8VTA4k+CJQE4Sp1qtW2jwHv+VvV+AOwrTBTcGHglwYhIKgjiYjCXFLeWNuzjEIUdS0qOI9jQFWA8NHfZPKWcHnfcqytiny23eNInJG24jMWPc//loJfmSCAlbARPqAX7Y3gxl41HAbu0rxZojNiqvduBBS4RanYrCZxPX9Ey3ESACjYuDUvh6vgaGqpU3ueFUfXcqjWhxUeWyQElsSY6vdf8F6Tz2u4JObWGujh98Q96feQwRAVGxkJFI4bq6ey8+BFYXa`

**مثال استجابة: Online Users List** — HTTP 200 OK
- Request URL: `http://185.95.184.10/admin/api/index.php/api/index/online`
- Request body: `payload=U2FsdGVkX19au+9Oqm4lKZbAUYhwr5cRmyqVmqmBnINETlSAQ0bZAq+UBd8VTA4k+CJQE4Sp1qtW2jwHv+VvV+AOwrTBTcGHglwYhIKgjiYjCXFLeWNuzjEIUdS0qOI9jQFWA8NHfZPKWcHnfcqytiny23eNInJG24jMWPc//loJfmSCAlbARPqAX7Y3gxl41HAbu0rxZojNiqvduBBS4RanYrCZxPX9Ey3ESACjYuDUvh6vgaGqpU3ueFUfXcqjWhxUeWyQElsSY6vdf8F6Tz2u4JObWGujh98Q96feQwRAVGxkJFI4bq6ey8+BFYXa`
- Content-Type: application/json
```json
{
    "current_page": 1,
    "data": [
        {
            "radacctid": 362618,
            "nasipaddress": "172.16.26.2",
            "framedipaddress": "10.26.255.168",
            "profile_id": 9,
            "framedprotocol": "PPP",
            "acctsessiontime": 4598181,
            "acctstarttime": "2020-06-06 08:08:27",
            "acctinputoctets": 138320331,
            "acctoutputoctets": 70897674,
            "username": "862gpl",
            "callingstationid": "CC:2D:E0:33:89:41",
            "calledstationid": "Kurdsat2VLAN-66",
            "fup": 1,
            "user_profile_name": "Pro-33000",
            "user_profile_id": 8,
            "status": {
                "status": false,
                "traffic": true,
                "expiration": false,
                "uptime": true
            },
            "oui": "Routerboard.com",
            "daily_usage_percentage": 0,
            "nas_details": {
                "id": 27,
                "nasname": "172.16.26.2",
                "shortname": "Kurdsat2",
                "type": 1,
                "secret": "12345",
                "api_username": "SAS4_API",
                "api_password": "46$73!9",
                "coa_port": 1700,
                "version": "mikrtik_6.36",
                "description": "RADIUS Client",
                "server": null,
                "enabled": 1,
                "site_id": null,
                "http_port": 7318,
                "monitor": 1,
                "ping_time": 4,
                "ping_loss": 0,
                "ip_accounting_enabled": 1,
                "pool_name": null,
                "api_port": 8728,
                "snmp_community": "NEXTujsdahfowqNET",
                "created_at": "2020-04-29 09:27:14",
                "created_by": null,
                "updated_at": "2020-05-04 12:28:19"
            },
            "user_details": {
                "id": 3019,
                "username": "862gpl",
                "firstname": "هاوکار احمد فرج",
                "lastname": "",
                "profile_id": 8,
                "expiration": "2019-05-20 18:43:57",
                "parent_username": null,
                "profile_details": {
                    "id": 8,
                    "name": "Pro-33000",
                    "type": 0
                }
            }
        },
        {
            "radacctid": 434659,
            "nasipaddress": "172.16.26.2",
            "framedipaddress": "10.26.255.120",
            "profile_id": 9,
            "framedprotocol": "PPP",
            "acctsessiontime": 4019411,
            "acctstarttime": "2020-06-13 00:54:00",
            "acctinputoctets": 46654413,
            "acctoutputoctets": 3494,
            "username": "813gct",
            "callingstationid": "64:D1:54:77:4C:BD",
            "calledstationid": "Kurdsat2Eth-6",
            "fup": 1,
            "user_profile_name": "Pro-33000",
            "user_profile_id": 8,
            "status": {
                "status": false,
                "traffic": true,
                "expiration": false,
                "uptime": true
            },
            "oui": "Routerboard.com",
            "daily_usage_percentage": 0,
            "nas_details": {
                "id": 27,
                "nasname": "172.16.26.2",
                "shortname": "Kurdsat2",
                "type": 1,
                "secret": "12345",
                "api_username": "SAS4_API",
                "api_password": "46$73!9",
                "coa_port": 1700,
                "version": "mikrtik_6.36",
                "description": "RADIUS Client",
                "server": null,
                "enabled": 1,
                "site_id": null,
                "http_port": 7318,
                "monitor": 1,
                "ping_time": 4,
                "ping_loss": 0,
                "ip_accounting_enabled": 1,
                "pool_name": null,
                "api_port": 8728,
                "snmp_community": "NEXTujsdahfowqNET",
                "created_at": "2020-04-29 09:27:14",
                "created_by": null,
                "updated_at": "2020-05-04 12:28:19"
            },
            "user_details": {
                "id": 335,
                "username": "813gct",
                "firstname": "محمد حسن احمد",
                "lastname": "",
                "profile_id": 8,
                "expiration": "2019-05-09 21:18:53",
                "parent_username": null,
                "profile_details": {
                    "id": 8,
                    "name": "Pro-33000",
                    "type": 0
                }
            }
        },
        {
            "radacctid": 434688,
            "nasipaddress": "172.16.39.2",
            "framedipaddress": "10.39.21.226",
            "profile_id": 5,
            "framedprotocol": "PPP",
            "acctsessiontime": 4018767,
            "acctstarttime": "2020-06-13 01:03:20",
            "acctinputoctets": 23130261461,
            "acctoutputoctets": 95479855657,
            "username": "422dnp",
            "callingstationid": "64:EE:B7:20:EF:6B",
            "calledstationid": "Raparin2-Vlan35",
            "fup": 0,
            "user_profile_name": "Free",
            "user_profile_id": 5,
            "status": {
                "status": true,
                "traffic": true,
                "expiration": true,
                "uptime": true
            },
            "oui": "Netcore Technology Inc",
            "daily_usage_percentage": 0,
            "nas_details": {
                "id": 40,
                "nasname": "172.16.39.2",
                "shortname": "Raparin2",
                "type": 1,
                "secret": "12345",
                "api_username": "SAS4_API",
                "api_password": "46$73!9",
                "coa_port": 1700,
                "version": "mikrtik_6.36",
                "description": "RADIUS Client",
                "server": null,
                "enabled": 1,
                "site_id": null,
                "http_port": 7318,
                "monitor": 1,
                "ping_time": 3,
                "ping_loss": 0,
                "ip_accounting_enabled": 1,
                "pool_name": null,
                "api_port": 8728,
                "snmp_community": "NEXTujsdahfowqNET",
                "created_at": "2020-04-29 09:27:14",
                "created_by": null,
                "updated_at": "2020-05-04 12:30:10"
            },
            "user_details": {
                "id": 38,
                "username": "422dnp",
                "firstname": "سایتی شاری نمونەیی -جەلال",
                "lastname": "",
                "profile_id": 5,
                "expiration": "2019-05-14 18:24:17",
                "parent_username": null,
                "profile_details": {
                    "id": 5,
                    "name": "Free",
                    "type": 0
                }
            }
        },
        {
            "radacctid": 624920,
            "nasipaddress": "172.16.25.2",
            "framedipaddress": "10.25.31.219",
            "profile_id": 5,
            "framedprotocol": "PPP",
            "acctsessiontime": 2584471,
            "acctstarttime": "2020-06-29 15:27:24",
            "acctinputoctets": 21608712473,
            "acctoutputoctets": 79009490914,
            "username": "414yus",
            "callingstationid": "6C:3B:6B:9B:FE:C2",
            "calledstationid": "Kaziwa-Eth-2",
            "fup": 0,
            "user_profile_name": "Free",
            "user_profile_id": 5,
            "status": {
                "status": true,
                "traffic": true,
                "expiration": true,
                "uptime": true
            },
            "oui": "Routerboard.com",
            "daily_usage_percentage": 0,
            "nas_details": {
                "id": 26,
                "nasname": "172.16.25.2",
                "shortname": "Kaziwa",
                "type": 1,
                "secret": "12345",
                "api_username": "SAS4_API",
                "api_password": "46$73!9",
                "coa_port": 1700,
                "version": "mikrtik_6.36",
                "description": "RADIUS Client",
                "server": null,
                "enabled": 1,
                "site_id": null,
                "http_port": 7318,
                "monitor": 1,
                "ping_time": 5,
                "ping_loss": 0,
                "ip_accounting_enabled": 1,
                "pool_name": null,
                "api_port": 8728,
                "snmp_community": "NEXTujsdahfowqNET",
                "created_at": "2020-04-29 09:27:14",
                "created_by": null,
                "updated_at": "2020-05-04 12:28:11"
            },
            "user_details": {
                "id": 20,
                "username": "414yus",
                "firstname": "ڕادیۆی کۆمەڵ",
                "lastname": "",
                "profile_id": 5,
                "expiration": "2019-12-22 16:52:37",
                "parent_username": null,
                "profile_details": {
                    "id": 5,
                    "name": "Free",
                    "type": 0
                }
            }
        },
        {
            "radacctid": 641522,
            "nasipaddress": "172.16.32.2",
            "framedipaddress": "185.95.186.147",
            "profile_id": 15,
            "framedprotocol": "PPP",
            "acctsessiontime": 2477669,
            "acctstarttime": "2020-06-30 21:07:48",
            "acctinputoctets": 20454918313,
            "acctoutputoctets": 235455672071,
            "username": "860mfx",
            "callingstationid": "04:8D:39:55:71:BC",
            "calledstationid": "KhabatEth-3",
            "fup": 0,
            "user_profile_name": "Business-70-PTP",
            "user_profile_id": 15,
            "status": {
                "status": true,
                "traffic": true,
                "expiration": true,
                "uptime": true
            },
            "oui": "unknown",
            "daily_usage_percentage": 0,
            "nas_details": {
                "id": 33,
                "nasname": "172.16.32.2",
                "shortname": "Khabat",
                "type": 1,
                "secret": "12345",
                "api_username": "SAS4_API",
                "api_password": "46$73!9",
                "coa_port": 1700,
                "version": "mikrtik_6.36",
                "description": "RADIUS Client",
                "server": null,
                "enabled": 1,
                "site_id": null,
                "http_port": 7318,
                "monitor": 1,
                "ping_time": 3,
                "ping_loss": 0,
                "ip_accounting_enabled": 1,
                "pool_name": null,
                "api_port": 8728,
                "snmp_community": "NEXTujsdahfowqNET",
                "created_at": "2020-04-29 09:27:14",
                "created_by": null,
                "updated_at": "2020-05-04 12:29:02"
            },
            "user_details": {
                "id": 2925,
                "username": "860mfx",
                "firstname": "کۆمپانیای پشوو",
                "lastname": "",
                "profile_id": 15,
                "expiration": "2020-08-29 22:02:54",
                "parent_username": null,
                "profile_details": {
                    "id": 15,
                    "name": "Business-70-PTP",
                    "type": 0
                }
            }
        },
        {
            "radacctid": 656003,
            "nasipaddress": "172.16.22.2",
            "framedipaddress": "10.22.29.193",
            "profile_id": 8,
            "framedprotocol": "PPP",
            "acctsessiontime": 2383340,
            "acctstarttime": "2020-07-01 23:20:48",
            "acctinputoctets": 41774132122,
            "acctoutputoctets": 356344228535,
            "username": "852vgy",
            "callingstationid": "E4:8D:8C:56:0B:31",
            "calledstationid": "Taslwja-VLAN2",
            "fup": 0,
            "user_profile_name": "Pro-33000",
            "user_profile_id": 8,
            "status": {
                "status": true,
                "traffic": true,
                "expiration": true,
                "uptime": true
            },
            "oui": "Routerboard.com",
            "daily_usage_percentage": 0,
            "nas_details": {
                "id": 23,
                "nasname": "172.16.22.2",
                "shortname": "Taslwja",
                "type": 1,
                "secret": "12345",
                "api_username": "SAS4_API",
                "api_password": "46$73!9",
                "coa_port": 1700,
                "version": "mikrtik_6.36",
                "description": "RADIUS Client",
                "server": null,
                "enabled": 1,
                "site_id": null,
                "http_port": 7318,
                "monitor": 1,
                "ping_time": 2,
                "ping_loss": 0,
                "ip_accounting_enabled": 1,
                "pool_name": null,
                "api_port": 8728,
                "snmp_community": "NEXTujsdahfowqNET",
                "created_at": "2020-04-29 09:27:14",
                "created_by": null,
                "updated_at": "2020-05-04 12:27:42"
            },
            "user_details": {
                "id": 2505,
                "username": "852vgy",
                "firstname": "به ختيار مولود محمد",
                "lastname": "",
                "profile_id": 8,
                "expiration": "2020-07-31 23:20:37",
                "parent_username": null,
                "profile_details": {
                    "id": 8,
                    "name": "Pro-33000",
                    "type": 0
                }
            }
        },
        {
            "radacctid": 664494,
            "nasipaddress": "172.16.13.2",
            "framedipaddress": "10.13.18.122",
            "profile_id": 8,
            "framedprotocol": "PPP",
            "acctsessiontime": 2312786,
            "acctstarttime": "2020-07-02 18:55:50",
            "acctinputoctets": 32024691053,
            "acctoutputoctets": 323012253421,
            "username": "852bet",
            "callingstationid": "E4:8D:8C:8F:58:05",
            "calledstationid": "HawkaryVlan-8",
            "fup": 0,
            "user_profile_name": "Pro-33000",
            "user_profile_id": 8,
            "status": {
                "status": true,
                "traffic": true,
                "expiration": true,
                "uptime": true
            },
            "oui": "Routerboard.com",
            "daily_usage_percentage": 0,
            "nas_details": {
                "id": 14,
                "nasname": "172.16.13.2",
                "shortname": "Hawkary",
                "type": 1,
                "secret": "12345",
                "api_username": "SAS4_API",
                "api_password": "46$73!9",
                "coa_port": 1700,
                "version": "mikrtik_6.36",
                "description": "RADIUS Client",
                "server": null,
                "enabled": 1,
                "site_id": null,
                "http_port": 7318,
                "monitor": 1,
                "ping_time": 2,
                "ping_loss": 0,
                "ip_accounting_enabled": 1,
                "pool_name": null,
                "api_port": 8728,
                "snmp_community": "NEXTujsdahfowqNET",
                "created_at": "2020-04-29 09:27:14",
                "created_by": null,
                "updated_at": "2020-05-04 12:26:31"
            },
            "user_details": {
                "id": 2460,
                "username": "852bet",
                "firstname": "احمد خلیل حسن",
                "lastname": "",
                "profile_id": 8,
                "expiration": "2020-08-01 18:55:39",
                "parent_username": null,
                "profile_details": {
                    "id": 8,
                    "name": "Pro-33000",
                    "type": 0
                }
            }
        },
        {
            "radacctid": 667989,
            "nasipaddress": "172.16.5.2",
            "framedipaddress": "10.5.27.60",
            "profile_id": 8,
            "framedprotocol": "PPP",
            "acctsessiontime": 2300175,
            "acctstarttime": "2020-07-02 22:26:20",
            "acctinputoctets": 48657841425,
            "acctoutputoctets": 447518791953,
            "username": "896yyt",
            "callingstationid": "E4:8D:8C:8E:59:51",
            "calledstationid": "SarwaryEth-2",
            "fup": 0,
            "user_profile_name": "Pro-33000",
            "user_profile_id": 8,
            "status": {
                "status": true,
                "traffic": true,
                "expiration": true,
                "uptime": true
            },
            "oui": "Routerboard.com",
            "daily_usage_percentage": 0,
            "nas_details": {
                "id": 6,
                "nasname": "172.16.5.2",
                "shortname": "Sarwary",
                "type": 1,
                "secret": "12345",
                "api_username": "SAS4_API",
                "api_password": "46$73!9",
                "coa_port": 1700,
                "version": "mikrtik_6.36",
                "description": "RADIUS Client",
                "server": null,
                "enabled": 1,
                "site_id": null,
                "http_port": 7318,
                "monitor": 1,
                "ping_time": 2,
                "ping_loss": 0,
                "ip_accounting_enabled": 1,
                "pool_name": null,
                "api_port": 8728,
                "snmp_community": "NEXTujsdahfowqNET",
                "created_at": "2020-04-29 09:27:14",
                "created_by": null,
                "updated_at": "2020-05-04 12:25:34"
            },
            "user_details": {
                "id": 4811,
                "username": "896yyt",
                "firstname": "ئیقبال عباس",
                "lastname": "",
                "profile_id": 8,
                "expiration": "2020-07-31 22:26:09",
                "parent_username": null,
                "profile_details": {
                    "id": 8,
                    "name": "Pro-33000",
                    "type": 0
                }
            }
        },
        {
            "radacctid": 670628,
            "nasipaddress": "172.16.27.2",
            "framedipaddress": "10.27.16.68",
            "profile_id": 8,
            "framedprotocol": "PPP",
            "acctsessiontime": 2267850,
            "acctstarttime": "2020-07-03 07:25:02",
            "acctinputoctets": 16177824247,
            "acctoutputoctets": 185861621776,
            "username": "814ihl",
            "callingstationid": "74:4D:28:D3:16:9F",
            "calledstationid": "KanakawaEth-9",
            "fup": 0,
            "user_profile_name": "Pro-33000",
            "user_profile_id": 8,
            "status": {
                "status": true,
                "traffic": true,
                "expiration": true,
                "uptime": true
            },
            "oui": "unknown",
            "daily_usage_percentage": 0,
            "nas_details": {
                "id": 28,
                "nasname": "172.16.27.2",
                "shortname": "Kanakawa",
                "type": 1,
                "secret": "12345",
                "api_username": "SAS4_API",
                "api_password": "46$73!9",
                "coa_port": 1700,
                "version": "mikrtik_6.36",
                "description": "RADIUS Client",
                "server": null,
                "enabled": 1,
                "site_id": null,
                "http_port": 7318,
                "monitor": 1,
                "ping_time": 4,
                "ping_loss": 0,
                "ip_accounting_enabled": 1,
                "pool_name": null,
                "api_port": 8728,
                "snmp_community": "NEXTujsdahfowqNET",
                "created_at": "2020-04-29 09:27:14",
                "created_by": null,
                "updated_at": "2020-05-04 12:28:26"
            },
            "user_details": {
                "id": 394,
                "username": "814ihl",
                "firstname": "رابه ر صالح جلا ل",
                "lastname": "",
                "profile_id": 8,
                "expiration": "2020-09-27 22:05:44",
                "parent_username": null,
                "profile_details": {
                    "id": 8,
                    "name": "Pro-33000",
                    "type": 0
                }
            }
        },
        {
            "radacctid": 677055,
            "nasipaddress": "172.16.12.2",
            "framedipaddress": "10.12.21.6",
            "profile_id": 8,
            "framedprotocol": "PPP",
            "acctsessiontime": 2231177,
            "acctstarttime": "2020-07-03 17:36:31",
            "acctinputoctets": 17464545994,
            "acctoutputoctets": 329543632153,
            "username": "899wla",
            "callingstationid": "64:D1:54:72:75:B3",
            "calledstationid": "RaparinEth-7",
            "fup": 0,
            "user_profile_name": "Pro-33000",
            "user_profile_id": 8,
            "status": {
                "status": true,
                "traffic": true,
                "expiration": true,
                "uptime": true
            },
            "oui": "Routerboard.com",
            "daily_usage_percentage": 0,
            "nas_details": {
                "id": 13,
                "nasname": "172.16.12.2",
                "shortname": "Raparin",
                "type": 1,
                "secret": "12345",
                "api_username": "SAS4_API",
                "api_password": "46$73!9",
                "coa_port": 1700,
                "version": "mikrtik_6.36",
                "description": "RADIUS Client",
                "server": null,
                "enabled": 1,
                "site_id": null,
                "http_port": 7318,
                "monitor": 1,
                "ping_time": 4,
                "ping_loss": 0,
                "ip_accounting_enabled": 1,
                "pool_name": null,
                "api_port": 8728,
                "snmp_community": "NEXTujsdahfowqNET",
                "created_at": "2020-04-29 09:27:14",
                "created_by": null,
                "updated_at": "2020-05-04 12:26:23"
            },
            "user_details": {
                "id": 4975,
                "username": "899wla",
                "firstname": "ئامانج بورهان مردان",
                "lastname": "",
                "profile_id": 8,
                "expiration": "2020-08-02 17:34:04",
                "parent_username": null,
                "profile_details": {
                    "id": 8,
                    "name": "Pro-33000",
                    "type": 0
                }
            }
        }
    ],
    "first_page_url": "http://185.95.184.10/admin/api/index.php/api/index/online?page=1",
    "from": 1,
    "last_page": 348,
    "last_page_url": "http://185.95.184.10/admin/api/index.php/api/index/online?page=348",
    "next_page_url": "http://185.95.184.10/admin/api/index.php/api/index/online?page=2",
    "path": "http://185.95.184.10/admin/api/index.php/api/index/online",
    "per_page": 10,
    "prev_page_url": null,
    "to": 10,
    "total": 3476
}
```

### 50. Online Users List - with search

**Method:** `POST`  
**URL:** `http://185.95.184.10/admin/api/index.php/api/index/online`  
**Auth:** bearer

**الوصف (كما في التوثيق):**

show all users and basic info about users status, the following body parameters to reteive user list data:

### "payload" it must be encrypt the following parameters which must be a  JSON format:

```
- "page" for pagination of list (number).
- "count" number of data in single page (number).
- "sortBy" sort data due to selected field.
- "diraction" diraction of selected field sort (asc/desc).
- "columns" show the select field inside this array :
        -"n_row",
        -"id",
        -"username"
        -"firstname"
        -"lastname"
        -"expiration"
        -"parent_username"
        -"name"
        -"balance"
        -"traffic"
        -"city"
        -"static_ip"
        -"notes"
        -"last_online"
        -"company"
        -"simultaneous_sessions"
        -"used_traffic"
        -"phone"
        -"address"
        -"contract_id"
```

### decrypted payload JSON use in example :

```
{"page":1,"count":10,"sortBy":null,"direction":"asc","search":"","columns":["id","username","acctoutputoctets","acctinputoctets","user_profile_name","framedipaddress","callingstationid","acctsessiontime","oui"]}
```

**Body (urlencoded):**
- `payload` = `U2FsdGVkX19au+9Oqm4lKZbAUYhwr5cRmyqVmqmBnINETlSAQ0bZAq+UBd8VTA4k+CJQE4Sp1qtW2jwHv+VvV+AOwrTBTcGHglwYhIKgjiYjCXFLeWNuzjEIUdS0qOI9jQFWA8NHfZPKWcHnfcqytiny23eNInJG24jMWPc//loJfmSCAlbARPqAX7Y3gxl41HAbu0rxZojNiqvduBBS4RanYrCZxPX9Ey3ESACjYuDUvh6vgaGqpU3ueFUfXcqjWhxUeWyQElsSY6vdf8F6Tz2u4JObWGujh98Q96feQwRAVGxkJFI4bq6ey8+BFYXa`

**مثال استجابة: Online Users List** — HTTP 200 OK
- Request URL: `http://185.95.184.10/admin/api/index.php/api/index/online`
- Request body: `payload=U2FsdGVkX19au+9Oqm4lKZbAUYhwr5cRmyqVmqmBnINETlSAQ0bZAq+UBd8VTA4k+CJQE4Sp1qtW2jwHv+VvV+AOwrTBTcGHglwYhIKgjiYjCXFLeWNuzjEIUdS0qOI9jQFWA8NHfZPKWcHnfcqytiny23eNInJG24jMWPc//loJfmSCAlbARPqAX7Y3gxl41HAbu0rxZojNiqvduBBS4RanYrCZxPX9Ey3ESACjYuDUvh6vgaGqpU3ueFUfXcqjWhxUeWyQElsSY6vdf8F6Tz2u4JObWGujh98Q96feQwRAVGxkJFI4bq6ey8+BFYXa`
- Content-Type: application/json
```json
{
    "current_page": 1,
    "data": [
        {
            "radacctid": 362618,
            "nasipaddress": "172.16.26.2",
            "framedipaddress": "10.26.255.168",
            "profile_id": 9,
            "framedprotocol": "PPP",
            "acctsessiontime": 4598181,
            "acctstarttime": "2020-06-06 08:08:27",
            "acctinputoctets": 138320331,
            "acctoutputoctets": 70897674,
            "username": "862gpl",
            "callingstationid": "CC:2D:E0:33:89:41",
            "calledstationid": "Kurdsat2VLAN-66",
            "fup": 1,
            "user_profile_name": "Pro-33000",
            "user_profile_id": 8,
            "status": {
                "status": false,
                "traffic": true,
                "expiration": false,
                "uptime": true
            },
            "oui": "Routerboard.com",
            "daily_usage_percentage": 0,
            "nas_details": {
                "id": 27,
                "nasname": "172.16.26.2",
                "shortname": "Kurdsat2",
                "type": 1,
                "secret": "12345",
                "api_username": "SAS4_API",
                "api_password": "46$73!9",
                "coa_port": 1700,
                "version": "mikrtik_6.36",
                "description": "RADIUS Client",
                "server": null,
                "enabled": 1,
                "site_id": null,
                "http_port": 7318,
                "monitor": 1,
                "ping_time": 4,
                "ping_loss": 0,
                "ip_accounting_enabled": 1,
                "pool_name": null,
                "api_port": 8728,
                "snmp_community": "NEXTujsdahfowqNET",
                "created_at": "2020-04-29 09:27:14",
                "created_by": null,
                "updated_at": "2020-05-04 12:28:19"
            },
            "user_details": {
                "id": 3019,
                "username": "862gpl",
                "firstname": "هاوکار احمد فرج",
                "lastname": "",
                "profile_id": 8,
                "expiration": "2019-05-20 18:43:57",
                "parent_username": null,
                "profile_details": {
                    "id": 8,
                    "name": "Pro-33000",
                    "type": 0
                }
            }
        },
        {
            "radacctid": 434659,
            "nasipaddress": "172.16.26.2",
            "framedipaddress": "10.26.255.120",
            "profile_id": 9,
            "framedprotocol": "PPP",
            "acctsessiontime": 4019411,
            "acctstarttime": "2020-06-13 00:54:00",
            "acctinputoctets": 46654413,
            "acctoutputoctets": 3494,
            "username": "813gct",
            "callingstationid": "64:D1:54:77:4C:BD",
            "calledstationid": "Kurdsat2Eth-6",
            "fup": 1,
            "user_profile_name": "Pro-33000",
            "user_profile_id": 8,
            "status": {
                "status": false,
                "traffic": true,
                "expiration": false,
                "uptime": true
            },
            "oui": "Routerboard.com",
            "daily_usage_percentage": 0,
            "nas_details": {
                "id": 27,
                "nasname": "172.16.26.2",
                "shortname": "Kurdsat2",
                "type": 1,
                "secret": "12345",
                "api_username": "SAS4_API",
                "api_password": "46$73!9",
                "coa_port": 1700,
                "version": "mikrtik_6.36",
                "description": "RADIUS Client",
                "server": null,
                "enabled": 1,
                "site_id": null,
                "http_port": 7318,
                "monitor": 1,
                "ping_time": 4,
                "ping_loss": 0,
                "ip_accounting_enabled": 1,
                "pool_name": null,
                "api_port": 8728,
                "snmp_community": "NEXTujsdahfowqNET",
                "created_at": "2020-04-29 09:27:14",
                "created_by": null,
                "updated_at": "2020-05-04 12:28:19"
            },
            "user_details": {
                "id": 335,
                "username": "813gct",
                "firstname": "محمد حسن احمد",
                "lastname": "",
                "profile_id": 8,
                "expiration": "2019-05-09 21:18:53",
                "parent_username": null,
                "profile_details": {
                    "id": 8,
                    "name": "Pro-33000",
                    "type": 0
                }
            }
        },
        {
            "radacctid": 434688,
            "nasipaddress": "172.16.39.2",
            "framedipaddress": "10.39.21.226",
            "profile_id": 5,
            "framedprotocol": "PPP",
            "acctsessiontime": 4018767,
            "acctstarttime": "2020-06-13 01:03:20",
            "acctinputoctets": 23130261461,
            "acctoutputoctets": 95479855657,
            "username": "422dnp",
            "callingstationid": "64:EE:B7:20:EF:6B",
            "calledstationid": "Raparin2-Vlan35",
            "fup": 0,
            "user_profile_name": "Free",
            "user_profile_id": 5,
            "status": {
                "status": true,
                "traffic": true,
                "expiration": true,
                "uptime": true
            },
            "oui": "Netcore Technology Inc",
            "daily_usage_percentage": 0,
            "nas_details": {
                "id": 40,
                "nasname": "172.16.39.2",
                "shortname": "Raparin2",
                "type": 1,
                "secret": "12345",
                "api_username": "SAS4_API",
                "api_password": "46$73!9",
                "coa_port": 1700,
                "version": "mikrtik_6.36",
                "description": "RADIUS Client",
                "server": null,
                "enabled": 1,
                "site_id": null,
                "http_port": 7318,
                "monitor": 1,
                "ping_time": 3,
                "ping_loss": 0,
                "ip_accounting_enabled": 1,
                "pool_name": null,
                "api_port": 8728,
                "snmp_community": "NEXTujsdahfowqNET",
                "created_at": "2020-04-29 09:27:14",
                "created_by": null,
                "updated_at": "2020-05-04 12:30:10"
            },
            "user_details": {
                "id": 38,
                "username": "422dnp",
                "firstname": "سایتی شاری نمونەیی -جەلال",
                "lastname": "",
                "profile_id": 5,
                "expiration": "2019-05-14 18:24:17",
                "parent_username": null,
                "profile_details": {
                    "id": 5,
                    "name": "Free",
                    "type": 0
                }
            }
        },
        {
            "radacctid": 624920,
            "nasipaddress": "172.16.25.2",
            "framedipaddress": "10.25.31.219",
            "profile_id": 5,
            "framedprotocol": "PPP",
            "acctsessiontime": 2584471,
            "acctstarttime": "2020-06-29 15:27:24",
            "acctinputoctets": 21608712473,
            "acctoutputoctets": 79009490914,
            "username": "414yus",
            "callingstationid": "6C:3B:6B:9B:FE:C2",
            "calledstationid": "Kaziwa-Eth-2",
            "fup": 0,
            "user_profile_name": "Free",
            "user_profile_id": 5,
            "status": {
                "status": true,
                "traffic": true,
                "expiration": true,
                "uptime": true
            },
            "oui": "Routerboard.com",
            "daily_usage_percentage": 0,
            "nas_details": {
                "id": 26,
                "nasname": "172.16.25.2",
                "shortname": "Kaziwa",
                "type": 1,
                "secret": "12345",
                "api_username": "SAS4_API",
                "api_password": "46$73!9",
                "coa_port": 1700,
                "version": "mikrtik_6.36",
                "description": "RADIUS Client",
                "server": null,
                "enabled": 1,
                "site_id": null,
                "http_port": 7318,
                "monitor": 1,
                "ping_time": 5,
                "ping_loss": 0,
                "ip_accounting_enabled": 1,
                "pool_name": null,
                "api_port": 8728,
                "snmp_community": "NEXTujsdahfowqNET",
                "created_at": "2020-04-29 09:27:14",
                "created_by": null,
                "updated_at": "2020-05-04 12:28:11"
            },
            "user_details": {
                "id": 20,
                "username": "414yus",
                "firstname": "ڕادیۆی کۆمەڵ",
                "lastname": "",
                "profile_id": 5,
                "expiration": "2019-12-22 16:52:37",
                "parent_username": null,
                "profile_details": {
                    "id": 5,
                    "name": "Free",
                    "type": 0
                }
            }
        },
        {
            "radacctid": 641522,
            "nasipaddress": "172.16.32.2",
            "framedipaddress": "185.95.186.147",
            "profile_id": 15,
            "framedprotocol": "PPP",
            "acctsessiontime": 2477669,
            "acctstarttime": "2020-06-30 21:07:48",
            "acctinputoctets": 20454918313,
            "acctoutputoctets": 235455672071,
            "username": "860mfx",
            "callingstationid": "04:8D:39:55:71:BC",
            "calledstationid": "KhabatEth-3",
            "fup": 0,
            "user_profile_name": "Business-70-PTP",
            "user_profile_id": 15,
            "status": {
                "status": true,
                "traffic": true,
                "expiration": true,
                "uptime": true
            },
            "oui": "unknown",
            "daily_usage_percentage": 0,
            "nas_details": {
                "id": 33,
                "nasname": "172.16.32.2",
                "shortname": "Khabat",
                "type": 1,
                "secret": "12345",
                "api_username": "SAS4_API",
                "api_password": "46$73!9",
                "coa_port": 1700,
                "version": "mikrtik_6.36",
                "description": "RADIUS Client",
                "server": null,
                "enabled": 1,
                "site_id": null,
                "http_port": 7318,
                "monitor": 1,
                "ping_time": 3,
                "ping_loss": 0,
                "ip_accounting_enabled": 1,
                "pool_name": null,
                "api_port": 8728,
                "snmp_community": "NEXTujsdahfowqNET",
                "created_at": "2020-04-29 09:27:14",
                "created_by": null,
                "updated_at": "2020-05-04 12:29:02"
            },
            "user_details": {
                "id": 2925,
                "username": "860mfx",
                "firstname": "کۆمپانیای پشوو",
                "lastname": "",
                "profile_id": 15,
                "expiration": "2020-08-29 22:02:54",
                "parent_username": null,
                "profile_details": {
                    "id": 15,
                    "name": "Business-70-PTP",
                    "type": 0
                }
            }
        },
        {
            "radacctid": 656003,
            "nasipaddress": "172.16.22.2",
            "framedipaddress": "10.22.29.193",
            "profile_id": 8,
            "framedprotocol": "PPP",
            "acctsessiontime": 2383340,
            "acctstarttime": "2020-07-01 23:20:48",
            "acctinputoctets": 41774132122,
            "acctoutputoctets": 356344228535,
            "username": "852vgy",
            "callingstationid": "E4:8D:8C:56:0B:31",
            "calledstationid": "Taslwja-VLAN2",
            "fup": 0,
            "user_profile_name": "Pro-33000",
            "user_profile_id": 8,
            "status": {
                "status": true,
                "traffic": true,
                "expiration": true,
                "uptime": true
            },
            "oui": "Routerboard.com",
            "daily_usage_percentage": 0,
            "nas_details": {
                "id": 23,
                "nasname": "172.16.22.2",
                "shortname": "Taslwja",
                "type": 1,
                "secret": "12345",
                "api_username": "SAS4_API",
                "api_password": "46$73!9",
                "coa_port": 1700,
                "version": "mikrtik_6.36",
                "description": "RADIUS Client",
                "server": null,
                "enabled": 1,
                "site_id": null,
                "http_port": 7318,
                "monitor": 1,
                "ping_time": 2,
                "ping_loss": 0,
                "ip_accounting_enabled": 1,
                "pool_name": null,
                "api_port": 8728,
                "snmp_community": "NEXTujsdahfowqNET",
                "created_at": "2020-04-29 09:27:14",
                "created_by": null,
                "updated_at": "2020-05-04 12:27:42"
            },
            "user_details": {
                "id": 2505,
                "username": "852vgy",
                "firstname": "به ختيار مولود محمد",
                "lastname": "",
                "profile_id": 8,
                "expiration": "2020-07-31 23:20:37",
                "parent_username": null,
                "profile_details": {
                    "id": 8,
                    "name": "Pro-33000",
                    "type": 0
                }
            }
        },
        {
            "radacctid": 664494,
            "nasipaddress": "172.16.13.2",
            "framedipaddress": "10.13.18.122",
            "profile_id": 8,
            "framedprotocol": "PPP",
            "acctsessiontime": 2312786,
            "acctstarttime": "2020-07-02 18:55:50",
            "acctinputoctets": 32024691053,
            "acctoutputoctets": 323012253421,
            "username": "852bet",
            "callingstationid": "E4:8D:8C:8F:58:05",
            "calledstationid": "HawkaryVlan-8",
            "fup": 0,
            "user_profile_name": "Pro-33000",
            "user_profile_id": 8,
            "status": {
                "status": true,
                "traffic": true,
                "expiration": true,
                "uptime": true
            },
            "oui": "Routerboard.com",
            "daily_usage_percentage": 0,
            "nas_details": {
                "id": 14,
                "nasname": "172.16.13.2",
                "shortname": "Hawkary",
                "type": 1,
                "secret": "12345",
                "api_username": "SAS4_API",
                "api_password": "46$73!9",
                "coa_port": 1700,
                "version": "mikrtik_6.36",
                "description": "RADIUS Client",
                "server": null,
                "enabled": 1,
                "site_id": null,
                "http_port": 7318,
                "monitor": 1,
                "ping_time": 2,
                "ping_loss": 0,
                "ip_accounting_enabled": 1,
                "pool_name": null,
                "api_port": 8728,
                "snmp_community": "NEXTujsdahfowqNET",
                "created_at": "2020-04-29 09:27:14",
                "created_by": null,
                "updated_at": "2020-05-04 12:26:31"
            },
            "user_details": {
                "id": 2460,
                "username": "852bet",
                "firstname": "احمد خلیل حسن",
                "lastname": "",
                "profile_id": 8,
                "expiration": "2020-08-01 18:55:39",
                "parent_username": null,
                "profile_details": {
                    "id": 8,
                    "name": "Pro-33000",
                    "type": 0
                }
            }
        },
        {
            "radacctid": 667989,
            "nasipaddress": "172.16.5.2",
            "framedipaddress": "10.5.27.60",
            "profile_id": 8,
            "framedprotocol": "PPP",
            "acctsessiontime": 2300175,
            "acctstarttime": "2020-07-02 22:26:20",
            "acctinputoctets": 48657841425,
            "acctoutputoctets": 447518791953,
            "username": "896yyt",
            "callingstationid": "E4:8D:8C:8E:59:51",
            "calledstationid": "SarwaryEth-2",
            "fup": 0,
            "user_profile_name": "Pro-33000",
            "user_profile_id": 8,
            "status": {
                "status": true,
                "traffic": true,
                "expiration": true,
                "uptime": true
            },
            "oui": "Routerboard.com",
            "daily_usage_percentage": 0,
            "nas_details": {
                "id": 6,
                "nasname": "172.16.5.2",
                "shortname": "Sarwary",
                "type": 1,
                "secret": "12345",
                "api_username": "SAS4_API",
                "api_password": "46$73!9",
                "coa_port": 1700,
                "version": "mikrtik_6.36",
                "description": "RADIUS Client",
                "server": null,
                "enabled": 1,
                "site_id": null,
                "http_port": 7318,
                "monitor": 1,
                "ping_time": 2,
                "ping_loss": 0,
                "ip_accounting_enabled": 1,
                "pool_name": null,
                "api_port": 8728,
                "snmp_community": "NEXTujsdahfowqNET",
                "created_at": "2020-04-29 09:27:14",
                "created_by": null,
                "updated_at": "2020-05-04 12:25:34"
            },
            "user_details": {
                "id": 4811,
                "username": "896yyt",
                "firstname": "ئیقبال عباس",
                "lastname": "",
                "profile_id": 8,
                "expiration": "2020-07-31 22:26:09",
                "parent_username": null,
                "profile_details": {
                    "id": 8,
                    "name": "Pro-33000",
                    "type": 0
                }
            }
        },
        {
            "radacctid": 670628,
            "nasipaddress": "172.16.27.2",
            "framedipaddress": "10.27.16.68",
            "profile_id": 8,
            "framedprotocol": "PPP",
            "acctsessiontime": 2267850,
            "acctstarttime": "2020-07-03 07:25:02",
            "acctinputoctets": 16177824247,
            "acctoutputoctets": 185861621776,
            "username": "814ihl",
            "callingstationid": "74:4D:28:D3:16:9F",
            "calledstationid": "KanakawaEth-9",
            "fup": 0,
            "user_profile_name": "Pro-33000",
            "user_profile_id": 8,
            "status": {
                "status": true,
                "traffic": true,
                "expiration": true,
                "uptime": true
            },
            "oui": "unknown",
            "daily_usage_percentage": 0,
            "nas_details": {
                "id": 28,
                "nasname": "172.16.27.2",
                "shortname": "Kanakawa",
                "type": 1,
                "secret": "12345",
                "api_username": "SAS4_API",
                "api_password": "46$73!9",
                "coa_port": 1700,
                "version": "mikrtik_6.36",
                "description": "RADIUS Client",
                "server": null,
                "enabled": 1,
                "site_id": null,
                "http_port": 7318,
                "monitor": 1,
                "ping_time": 4,
                "ping_loss": 0,
                "ip_accounting_enabled": 1,
                "pool_name": null,
                "api_port": 8728,
                "snmp_community": "NEXTujsdahfowqNET",
                "created_at": "2020-04-29 09:27:14",
                "created_by": null,
                "updated_at": "2020-05-04 12:28:26"
            },
            "user_details": {
                "id": 394,
                "username": "814ihl",
                "firstname": "رابه ر صالح جلا ل",
                "lastname": "",
                "profile_id": 8,
                "expiration": "2020-09-27 22:05:44",
                "parent_username": null,
                "profile_details": {
                    "id": 8,
                    "name": "Pro-33000",
                    "type": 0
                }
            }
        },
        {
            "radacctid": 677055,
            "nasipaddress": "172.16.12.2",
            "framedipaddress": "10.12.21.6",
            "profile_id": 8,
            "framedprotocol": "PPP",
            "acctsessiontime": 2231177,
            "acctstarttime": "2020-07-03 17:36:31",
            "acctinputoctets": 17464545994,
            "acctoutputoctets": 329543632153,
            "username": "899wla",
            "callingstationid": "64:D1:54:72:75:B3",
            "calledstationid": "RaparinEth-7",
            "fup": 0,
            "user_profile_name": "Pro-33000",
            "user_profile_id": 8,
            "status": {
                "status": true,
                "traffic": true,
                "expiration": true,
                "uptime": true
            },
            "oui": "Routerboard.com",
            "daily_usage_percentage": 0,
            "nas_details": {
                "id": 13,
                "nasname": "172.16.12.2",
                "shortname": "Raparin",
                "type": 1,
                "secret": "12345",
                "api_username": "SAS4_API",
                "api_password": "46$73!9",
                "coa_port": 1700,
                "version": "mikrtik_6.36",
                "description": "RADIUS Client",
                "server": null,
                "enabled": 1,
                "site_id": null,
                "http_port": 7318,
                "monitor": 1,
                "ping_time": 4,
                "ping_loss": 0,
                "ip_accounting_enabled": 1,
                "pool_name": null,
                "api_port": 8728,
                "snmp_community": "NEXTujsdahfowqNET",
                "created_at": "2020-04-29 09:27:14",
                "created_by": null,
                "updated_at": "2020-05-04 12:26:23"
            },
            "user_details": {
                "id": 4975,
                "username": "899wla",
                "firstname": "ئامانج بورهان مردان",
                "lastname": "",
                "profile_id": 8,
                "expiration": "2020-08-02 17:34:04",
                "parent_username": null,
                "profile_details": {
                    "id": 8,
                    "name": "Pro-33000",
                    "type": 0
                }
            }
        }
    ],
    "first_page_url": "http://185.95.184.10/admin/api/index.php/api/index/online?page=1",
    "from": 1,
    "last_page": 348,
    "last_page_url": "http://185.95.184.10/admin/api/index.php/api/index/online?page=348",
    "next_page_url": "http://185.95.184.10/admin/api/index.php/api/index/online?page=2",
    "path": "http://185.95.184.10/admin/api/index.php/api/index/online",
    "per_page": 10,
    "prev_page_url": null,
    "to": 10,
    "total": 3476
}
```

### 51. Ping User

**Method:** `POST`  
**URL:** `http://185.95.184.10/admin/api/index.php/api/user/ping`  
**Auth:** bearer

**الوصف (كما في التوثيق):**

### decrypted payload JSON use in example :

```
{"radacctid":1005910,"username":"846iop"}
```

**Body (urlencoded):**
- `payload` = `U2FsdGVkX1+0SrtOPofiDu67i30PDXyZ0Yt7WyYQpDi0j9dCl3qcrib7bn0O44BJBESLlFnGWIrHlqYzWTIihA==
`

**مثال استجابة: User - Withdraw** — HTTP 200 OK
- Request URL: `http://demo4.sasradius.com/admin/api/index.php/api/user/withdraw`
- Request body: `payload=U2FsdGVkX18QYU98dWITd5ACD46zfwFDxuruH5VN1+kScvYXtO+wgq0nUCF3xNp7jnBKu5P2PA3rFduqLcCFoTuklZYkfK4Rw2vMytwY4TSB4VvNjY7XIeCqRRhZlhRnN01MIYizL6QtvO1kMQXk1/ZDCEa1W6pg8uGCskgox43QySS/kPR5I29lU3umV1zb`
- Content-Type: application/json
```json
{
    "status": 200,
    "message": "rsp_amount_deducted"
}
```

**مثال استجابة: Ping User** — HTTP 200 OK
- Request URL: `http://185.95.184.10/admin/api/index.php/api/user/ping`
- Request body: `payload=U2FsdGVkX1+0SrtOPofiDu67i30PDXyZ0Yt7WyYQpDi0j9dCl3qcrib7bn0O44BJBESLlFnGWIrHlqYzWTIihA==
`
- Content-Type: application/json
```json
{
    "status": 200,
    "data": {
        "seq": "0",
        "host": "10.8.24.207",
        "size": "56",
        "ttl": "64",
        "time": "4ms",
        "sent": "1",
        "received": "1",
        "packet-loss": "0",
        "min-rtt": "4ms",
        "avg-rtt": "4ms",
        "max-rtt": "4ms",
        "status": "0",
        "avg": "4ms",
        "loss": "0"
    }
}
```


---

## المجلد: Managers

### 52. Managers - Simple List

**Method:** `GET`  
**URL:** `http://demo4.sasradius.com/admin/api/index.php/api/index/manager`  
**Auth:** bearer

**مثال استجابة: Managers - Simple List** — HTTP 200 OK
- Request URL: `http://demo4.sasradius.com/admin/api/index.php/api/index/manager`
- Content-Type: application/json
```json
{
    "0": 200,
    "data": [
        {
            "id": 1,
            "username": "admin"
        },
        {
            "id": 2,
            "username": "manager1"
        }
    ]
}
```

### 53. Managers - Tree

**Method:** `GET`  
**URL:** `http://demo4.sasradius.com/admin/api/index.php/api/manager/tree`  
**Auth:** bearer

**مثال استجابة: Managers - Tree** — HTTP 200 OK
- Request URL: `http://demo4.sasradius.com/admin/api/index.php/api/manager/tree`
- Content-Type: application/json
```json
[
    {
        "id": 2,
        "parent_id": 1,
        "username": "manager1"
    },
    {
        "id": 1,
        "username": "admin",
        "parent": null
    }
]
```

### 54. Managers - List

**Method:** `POST`  
**URL:** `http://demo4.sasradius.com/admin/api/index.php/api/index/manager`  
**Auth:** bearer

**Body (urlencoded):**
- `payload` = `U2FsdGVkX19/352bPxa5ionTsULecMZBjqrA9gLMca3o3SPf6qQCIqEGdocFDnesPq5nH77l6iLyg/B6jHy+MUJANO2oWy367CjSFmh/GFxHmRlJAOHo11DYWMvrr/51sltZtvVsg0fmNzJUQDVCqnLFtBGhkwHQhtd6F9E9QkSkIOvPMr6M62FAtjfN2rB0Qg48OsN0Wti2efRDhY7498soqd4as3oSElOtcYWUlkFlwjqR+Nee2I+ojtOmZu3WIW4MGpOJzePQbSQPpVQugQ==
`

**مثال استجابة: Managers - List** — HTTP 200 OK
- Request URL: `http://demo4.sasradius.com/admin/api/index.php/api/index/manager`
- Request body: `payload=U2FsdGVkX1801CL6AB42hvMeELo50y4mTdUgwvX9IaguCcoGZOwfUIg2ll72mMVdj3YYtqrW3gM0w23jAyqgaDOQq4UjMIS6ID+b7Y3aja/SNjwburht9QPdYjyaEndNxx9bYP52yuZQsZQlpe0Uq5CT9IPfXZrReISprQyTueRBAbBuXnRshE2tWn2AEQt3g+7yQZNmoHxsqcfDpwct2mZtEwkHiYsm9RxBku7EOjU=`
- Content-Type: application/json
```json
{
    "current_page": 1,
    "data": [
        {
            "id": 2,
            "username": "manager1",
            "firstname": "manager",
            "lastname": " ",
            "city": null,
            "phone": null,
            "acl_group_id": 21,
            "balance": null,
            "parent_id": 1,
            "enabled": 1,
            "reward_points": 0,
            "created_at": "2019-07-25 09:00:34",
            "discount_rate": "0.00",
            "users_count": 1,
            "acl_group_details": {
                "id": 21,
                "name": "Normal Reseller",
                "dashboard_id": 2
            },
            "parent_details": {
                "id": 1,
                "username": "admin"
            }
        }
    ],
    "first_page_url": "http://demo4.sasradius.com/admin/api/index.php/api/index/manager?page=1",
    "from": 1,
    "last_page": 1,
    "last_page_url": "http://demo4.sasradius.com/admin/api/index.php/api/index/manager?page=1",
    "next_page_url": null,
    "path": "http://demo4.sasradius.com/admin/api/index.php/api/index/manager",
    "per_page": 10,
    "prev_page_url": null,
    "to": 1,
    "total": 1
}
```

### 55. Add Manager

**Method:** `POST`  
**URL:** `http://demo4.sasradius.com/admin/api/index.php/api/manager`  
**Auth:** bearer

**الوصف (كما في التوثيق):**

Adding a manager to SAS4

**Body (raw):**
```
{"username":"example_manager","enabled":1,"password":"123123","confirm_password":"123123","acl_group_id":21,"parent_id":1,"firstname":"first_name_param","lastname":"last_name_param","company":null,"email":null,"phone":null,"city":null,"address":null,"notes":null,"subscriber_prefix":null,"subscriber_suffix":null,"max_users":"0","site_id":null,"debt_limit":"0","discount_rate":"0","mikrotik_addresslist":null,"allowed_ppp_services":null,"allowed_nases":[],"requires_2fa":0,"admin_notes":null,"limit_delete":0,"limit_delete_count":"0","limit_rename":0,"limit_rename_count":"0","limit_profile_change":0,"limit_profile_change_count":"0","limit_mac_change":0,"limit_mac_change_count":"0"}

```

**مثال استجابة: Add Manager** — HTTP 200 OK
- Request URL: `http://demo4.sasradius.com/admin/api/index.php/api/manager`
- Request body:
```
{"username":"example_manager","enabled":1,"password":"123123","confirm_password":"123123","acl_group_id":21,"parent_id":1,"firstname":"first_name_param","lastname":"last_name_param","company":null,"email":null,"phone":null,"city":null,"address":null,"notes":null,"subscriber_prefix":null,"subscriber_suffix":null,"max_users":"0","site_id":null,"debt_limit":"0","discount_rate":"0","mikrotik_addresslist":null,"allowed_ppp_services":null,"allowed_nases":[],"requires_2fa":0,"admin_notes":null,"limit_delete":0,"limit_delete_count":"0","limit_rename":0,"limit_rename_count":"0","limit_profile_change":0,"limit_profile_change_count":"0","limit_mac_change":0,"limit_mac_change_count":"0"}

```
- Content-Type: application/json
```json
{
    "status": 200
}
```

### 56. Delete Manager

**Method:** `DELETE`  
**URL:** `http://demo4.sasradius.com/admin/api/index.php/api/manager/{{ manager_id }}`  
**Auth:** (غير محدد — يحتاج Bearer عملياً)

### 57. Update Manager

**Method:** `POST`  
**URL:** `http://demo4.sasradius.com/admin/api/index.php/api/manager/{{ manager_id }}`  
**Auth:** (غير محدد — يحتاج Bearer عملياً)

**الوصف (كما في التوثيق):**

```
{"username":"example_manager","enabled":1,"password":"123123","confirm_password":"123123","acl_group_id":21,"parent_id":1,"firstname":"first_name_param","lastname":"last_name_param","company":null,"email":null,"phone":null,"city":null,"address":null,"notes":null,"subscriber_prefix":null,"subscriber_suffix":null,"max_users":"0","site_id":null,"debt_limit":"0","discount_rate":"0","mikrotik_addresslist":null,"allowed_ppp_services":null,"allowed_nases":[],"requires_2fa":0,"admin_notes":null,"limit_delete":0,"limit_delete_count":"0","limit_rename":0,"limit_rename_count":"0","limit_profile_change":0,"limit_profile_change_count":"0","limit_mac_change":0,"limit_mac_change_count":"0"}
```

**Body (urlencoded):**
- `payload` = `U2FsdGVkX1/jRrYLqaQJDu/nC5ouE0Bkj73YG3euTnbamoQmKPUwcb6r81GFj9SjMsqsEuLvSLCMQHsa2tQ/+s4GMR2YdMrWKKMJSAjQmuc8n1fLu2RcLtsvKqp+U0BEy6lk1xAAJXjx6QecHCUPyc8RyKsvu/+w5a4ILMozT6L7YsRdBwi7qiquzhbWbFOB0ul47g2dPuOXiVJzHLZX0NIT2IUHJb2tU3RGupVisMuDH3NDW0s2hLW+Z1AXhPuxcODGOTXMsRZDPwC6xgPifywUuVbe7T3HESOQhCBgyoETIwC0WWCMrqHjL30StdzcSxxNAFJPsD4JOyvLt5u2sncirsUG2PnVvjxlyL7SiE2Lk7XWVzDg6ZMdNxHPhxzMeXrGUPkYhYNF/WTmkmeVwBOmxEnYuHUY1JfiWy4Hz7MSiO5J04hUlHkhKHO1d86bP89JjSeT2g8QqqnFo4SfDOYGWEOmmSswzft62fbvNZN2OjESh8IDOW4J+hzkvWtNZyKwvg/p1qiFMBFvqVW2c1NfMY6ZHgw55YJSG5aFrZ22ACy0y1Y77SmXMSIADY+e16z6kwYXLgDfUT08pNEgCj9YkDJ6WfF888kVgNYLSxHPR6tg5Cy94N4G6FgNkx0c15l3IX4XMedRDTHIz294jGwv1+4d02H6VnfGL5HKMncNWHfGKLrw6xNYYP6Oq9IhstnD1sN96/HzkV8FSOyzY40Hlsn4Gq8Ovjg+5xriiA3DgO380eGbPnJ+8b52HNKZVpW0Icrf+ZCRn1cEgz2CMMyZaLkU9iouVsPa4kFWZZ7fH6cVev66VBXsDyObsHYPCzMmXs638zqQdd3hoBiic34/LnyjmrQWft+pFo+1pSyDxBPxduD24+w0Ula0kx6u`

### 58. Rename Manager

**Method:** `POST`  
**URL:** `http://demo4.sasradius.com/admin/api/index.php/api/manager/{{ manager_id }}`  
**Auth:** (غير محدد — يحتاج Bearer عملياً)

**الوصف (كما في التوثيق):**

```
{"username":"manager_example_rename"}
```

**Body (urlencoded):**
- `payload` = `"U2FsdGVkX1/U+dDabYr16zroiR39EmLgqAiU+4w2At2I/SqwpYXARmR/eZF3oDnMS/KChuWnnlDd842Pq2li4g=="`

### 59. Manager Deposit

**Method:** `POST`  
**URL:** `http://demo4.sasradius.com/admin/api/index.php/api/manager/deposit`  
**Auth:** (غير محدد — يحتاج Bearer عملياً)

**الوصف (كما في التوثيق):**

```
{"page":1,"count":10,"sortBy":"username","direction":"asc","search":"","columns":["username","firstname","lastname","balance","loan_balance","name","username","users_count"]}
```

**Body (urlencoded):**
- `payload` = `U2FsdGVkX19UgUdCWnyGBXHPmPTpVD5A3rlkRWrIBeX0hl5dF8l8BVw6n8BEYP4n0K/P1mld383uGKVnl5QS8k4mTl7+W7Tvq6rm26xqTtR2LfVDqOczy2ALMJRWlOzIRQPe+5Dbc9uQqZM/ZbhZurTIOBTOJ9mqVWYw6V3jUH602loxCFvWeGnI0iZOpW8yfu4M91H0N+jET8CIMDT4Mp5WwJhkxg2HEV+CFYpqbsToDAPdTz7P+8LDMo1cBFkF3es+pgpVgZwZiiJvtxawMA==

`

### 60. Manager - Deposit Loans

**Method:** `POST`  
**URL:** `http://demo4.sasradius.com/admin/api/index.php/api/manager/deposit`  
**Auth:** (غير محدد — يحتاج Bearer عملياً)

**الوصف (كما في التوثيق):**

```
{"manager_id":5,"manager_username":"Manager_4","amount":24,"comment":"deposit_example_2_loans","transaction_id":"ac06844b-1471-80ca-f19e-7c90ecd1dcb8","is_loan":true,"balance":null}
```

**Body (urlencoded):**
- `payload` = `U2FsdGVkX18QMM6+kSZgG3ZHwUEsNaIzqLDR/jLVVBGKijxMy80osETcLLal92sHIrTLsJsy/axU+y9Ln18bYd2K1PRaffN2A1g8TFYPbSivtA9paKkNMWQCurtBb5ONCmkyq4UuhdeXiLzaFlKXyGPhdVurJD+qhCHijLl/WGNBR0/lQOeumlEhQF9mnaoNGKsGzFyoqsW2juzGYAuE2aeJcMTS0ZpkMHGALh9/MCDcMGpxuPCavtNHzSNuZ/va9J32X5SNXghtm/+MtSMWog==`

### 61. Managers - withdraw

**Method:** `POST`  
**URL:** `http://demo4.sasradius.com:/admin/api/index.php/api/manager/withdraw`  
**Auth:** (غير محدد — يحتاج Bearer عملياً)

**الوصف (كما في التوثيق):**

http://demo4.sasradius.com:/admin/api/index.php/api/manager/withdraw  
```json
{"manager_id":2,"manager_username":"manager_example_rename","amount":24,"comment":"withdraw_example","transaction_id":"ce5ceae0-49f0-6b57-72ea-fd5cc4430a45","balance":985}
```json
U2FsdGVkX18P0Td5Y0mwkI/oTb6ZQWzPHXshFp5QIk2Ld/UKo6aVLnHrdlK0DylJC3jN1kSUnEn7aSxmNS/Hexu4dhZw1azg2DTKY3SFfWCG2xwRh0MDrzT4rO/EZpv+eXXvx+amABL1SScpv3Phc2LuV027boyEZqGDrxxImMqaVFowYaJn/gI3DQEk2QEFfolxWCgSaP3CKHjSVRKL5CFwze6omhUKvYJhx256wzRkTNDskFwlV8M/kz+h02m0

**Body (urlencoded):**
- `payload` = `U2FsdGVkX18P0Td5Y0mwkI/oTb6ZQWzPHXshFp5QIk2Ld/UKo6aVLnHrdlK0DylJC3jN1kSUnEn7aSxmNS/Hexu4dhZw1azg2DTKY3SFfWCG2xwRh0MDrzT4rO/EZpv+eXXvx+amABL1SScpv3Phc2LuV027boyEZqGDrxxImMqaVFowYaJn/gI3DQEk2QEFfolxWCgSaP3CKHjSVRKL5CFwze6omhUKvYJhx256wzRkTNDskFwlV8M/kz+h02m0`

### 62. Managers - Add Reward Points

**Method:** `GET`  
**URL:** `(بدون URL)`  
**Auth:** (غير محدد — يحتاج Bearer عملياً)

**الوصف (كما في التوثيق):**

http://demo4.sasradius.com/admin/api/index.php/api/manager/addRewardPoints
U2FsdGVkX18StZ5ptyjY2w56GiiT+OXy0QwDGMJekoNt1oMQt129C8/0Z3tQfkYF

```
{"manager_id":2,"amount":23}
```

### 63. Managers - Add Reward Points

**Method:** `POST`  
**URL:** `http://demo4.sasradius.com/admin/api/index.php/api/manager/addRewardPoints`  
**Auth:** (غير محدد — يحتاج Bearer عملياً)

**الوصف (كما في التوثيق):**

http://demo4.sasradius.com/admin/api/index.php/api/manager/addRewardPoints
U2FsdGVkX18StZ5ptyjY2w56GiiT+OXy0QwDGMJekoNt1oMQt129C8/0Z3tQfkYF

```
{"manager_id":2,"amount":23}
```

**Body (urlencoded):**
- `payload` = `U2FsdGVkX18StZ5ptyjY2w56GiiT+OXy0QwDGMJekoNt1oMQt129C8/0Z3tQfkYF`

### 64. Managers - Deduct Managers points

**Method:** `POST`  
**URL:** `http://demo4.sasradius.com:/admin/api/index.php/api/manager/deductRewardPoints`  
**Auth:** (غير محدد — يحتاج Bearer عملياً)

**الوصف (كما في التوثيق):**

```
{"manager_id":5,"amount":1}
```

**Body (urlencoded):**
- `payload` = `U2FsdGVkX18StZ5ptyjY2w56GiiT+OXy0QwDGMJekoNt1oMQt129C8/0Z3tQfkYF`

### 65. Manager - Pay debt

**Method:** `POST`  
**URL:** `http://demo4.sasradius.com/admin/api/index.php/api/manager/payDebt`  
**Auth:** (غير محدد — يحتاج Bearer عملياً)

**الوصف (كما في التوثيق):**

A simple request to pay the debt for a manager

**Body (urlencoded):**
- `payload` = `U2FsdGVkX1+ArkjrtaKHIvAAl9taZPHejHSGTCjT3LKv4QkN5RZEqTZ0chH8W48dye7RKiiX7BdeRRqLS6Y+pv57um7wbHwQ3pMwzFEY9B5wuGwPowFNtmnyabQaPCl8t2Goy+MgFtzAudmDj+m3JpKKeSpI2I0eG4T9Xa7kmGIWkzshDeOsFzLZ+xeTCp+EVfsTaTD8ltcf4aV2oXwisuQkAQluBsMVWvKvZ8kdhtc=`


---

## المجلد: Profiles

### 66. Profiles - Simple List

**Method:** `GET`  
**URL:** `http://demo4.sasradius.com/admin/api/index.php/api/list/profile/0`  
**Auth:** bearer

**الوصف (كما في التوثيق):**

Retrieve data necessary for activation

**Body (raw):**
```

```

**مثال استجابة: Profiles - Simple List** — HTTP 200 OK
- Request URL: `http://demo4.sasradius.com/admin/api/index.php/api/list/profile/0`
- Content-Type: application/json
```json
{
    "0": 200,
    "status": 200,
    "data": [
        {
            "id": 1,
            "name": "default-2Mbit-1Month"
        },
        {
            "id": 4,
            "name": "10Mbit-1Month"
        },
        {
            "id": 5,
            "name": "20Mbit-1Month"
        }
    ]
}
```

