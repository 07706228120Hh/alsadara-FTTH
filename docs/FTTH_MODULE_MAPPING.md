# FTTH Module — Complete Technical Mapping

> **Module Path**: `src/Apps/CompanyDesktop/alsadara-ftth/lib/ftth/`  
> **Technology**: Flutter Desktop (Windows)  
> **External System**: FTTH ISP at `api.ftth.iq` / `admin.ftth.iq`  
> **Generated**: 2025

---

## Table of Contents

1. [Directory Structure](#1-directory-structure)
2. [Authentication System](#2-authentication-system)
3. [Core Module](#3-core-module)
4. [Subscriptions Module](#4-subscriptions-module)
5. [Transactions Module](#5-transactions-module)
6. [Reports Module](#6-reports-module)
7. [Users Module](#7-users-module)
8. [Tickets Module](#8-tickets-module)
9. [Widgets Module](#9-widgets-module)
10. [WhatsApp Module](#10-whatsapp-module)
11. [Data Models](#11-data-models)
12. [API Endpoints Catalog](#12-api-endpoints-catalog)
13. [Financial Flow](#13-financial-flow)

---

## 1. Directory Structure

```
lib/
├── config/
│   └── data_source_config.dart          # DataSource enum (firebase | vpsApi), currently vpsApi
├── services/
│   ├── auth_service.dart                # Singleton, OAuth2 login/refresh/authenticatedRequest (500 lines)
│   ├── api_service.dart                 # Singleton, wraps HTTP via AuthService (GET/POST/PUT/DELETE/PATCH)
│   └── ftth/
│       ├── ftth_cache_service.dart       # TTL-based cache (5min) for dashboard/wallet data
│       └── ftth_event_bus.dart           # Simple broadcast event bus (FtthEvents.forceRefresh)
├── ftth/
│   ├── auth/
│   │   ├── login_page.dart              # Login form + animated fiber-optic background (941 lines)
│   │   └── auth_error_handler.dart      # 401 → redirect to LoginPage, preserves System-1 credentials
│   ├── core/
│   │   ├── home_page.dart               # Main dashboard, wallet, navigation hub (4823 lines)
│   │   └── permissions_page.dart        # Grid permission management UI (565 lines)
│   ├── subscriptions/
│   │   ├── subscriptions_page.dart      # List/filter/export subscriptions (4516 lines)
│   │   ├── subscription_details_page.dart       # Detail + renewal + price calc (11568 lines)
│   │   ├── subscription_details_page.renewal.dart # 5-step renewal execution (956 lines)
│   │   ├── expiring_soon_page.dart      # Expiring soon list + trials (2466 lines)
│   │   ├── plans_bundles_page.dart      # Plan catalog (617 lines)
│   │   ├── all_subscriptions_details_page.dart  # Bulk fetch ALL subs (380 lines)
│   │   └── connections_list_page.dart   # Connections grouped by technician (2473 lines)
│   ├── transactions/
│   │   ├── transactions_page.dart       # 35+ transaction type filters (5489 lines)
│   │   ├── account_records_page.dart    # VPS subscription logs (3603 lines)
│   │   ├── account_stats_page.dart      # Purchase/renewal stats (624 lines)
│   │   ├── creator_amounts_page.dart    # Per-creator transaction grouping (1064 lines)
│   │   ├── creator_transactions_detail_page.dart # Creator detail view (2453 lines)
│   │   └── caounter_details_page.dart   # Audit log viewer (2628 lines)
│   ├── reports/
│   │   ├── zones_page.dart              # Zone listing (1222 lines)
│   │   ├── profits_page.dart            # Profit calc per plan (3346 lines)
│   │   ├── data_page.dart               # Tab container: agents + users data
│   │   ├── agents_details_page.dart     # Superset dashboard integration (2578 lines)
│   │   ├── export_page.dart             # Export buttons with animation (1290 lines)
│   │   └── audit_log_page.dart          # Per-customer audit log (1066 lines)
│   ├── users/
│   │   ├── users_page.dart              # User listing + zone filter (1775 lines)
│   │   ├── user_details_page.dart       # Customer subscription + device info (2423 lines)
│   │   ├── quick_search_users_page.dart # Debounced search + infinite scroll (1446 lines)
│   │   ├── users_data_page.dart         # Superset slice_id=48 data (899 lines)
│   │   ├── users_dashboard_webview.dart # WebView admin dashboard (352 lines)
│   │   ├── user_records_page.dart       # Per-user VPS subscription logs (1187 lines)
│   │   └── user_transactions_page.dart  # User transactions from legacy API (568 lines)
│   ├── tickets/
│   │   ├── tktats_page.dart             # Ticket list + auto-refresh + notifications (3016 lines)
│   │   ├── tktats_page_beautiful.dart   # Alternative ticket list UI (542 lines)
│   │   ├── tktat_details_page.dart      # Ticket detail + SLA + comments (1526 lines)
│   │   ├── tktat_raw_page.dart          # Raw JSON viewer for ticket (165 lines)
│   │   ├── customer_tickets_page.dart   # Per-customer tickets (373 lines)
│   │   ├── tickets_login_page.dart      # Ticket system login (494 lines)
│   │   ├── technicians_page.dart        # Local technician CRUD (SharedPreferences) (453 lines)
│   │   └── TKTAT.dart                   # Stub/placeholder ticket page (117 lines)
│   ├── widgets/
│   │   ├── notifications_page.dart      # FTTH notifications list + mark-as-read (733 lines)
│   │   ├── notification_filter.dart     # Smart notification filtering + display helpers (217 lines)
│   │   └── pikachu_overlay.dart         # Fun Pikachu Lottie following mouse cursor (252 lines)
│   └── whatsapp/
│       ├── whatsapp_bottom_window.dart       # Full-screen WhatsApp WebView overlay (1370 lines)
│       ├── whatsapp_bottom_window_fixed.dart  # Fixed version of WhatsApp overlay (1167 lines)
│       └── whatsapp_floating_window.dart      # Standalone floating WhatsApp window (413 lines)
```

**Total estimated lines**: ~65,000+

---

## 2. Authentication System

### 2.1 Auth Service (`services/auth_service.dart`)

**Singleton pattern** with `AuthService.instance`.

**Base URL**: `https://admin.ftth.iq/api/auth/Contractor`

#### Login Flow
```dart
// POST https://admin.ftth.iq/api/auth/Contractor/token
// Content-Type: application/x-www-form-urlencoded
// Headers:
//   x-client-app: 53d57a7f-3f89-4e9d-873b-3d071bc6dd9f
//   x-user-role: 0

body: {
  username: "...",
  password: "...",
  grant_type: "password",
  scope: "openid profile"
}

// Response → { access_token, refresh_token, expires_in }
```

#### Token Refresh
```dart
// POST https://admin.ftth.iq/api/auth/Contractor/refresh
// Body (form-encoded): { refresh_token }
```

#### Key Mechanisms
- **Proactive refresh**: Refreshes token when < 4 minutes remain before expiry
- **Single-flight pattern**: Prevents concurrent refresh calls via `_isRefreshing` flag + `Completer`
- **Auto-relogin**: Falls back to stored credentials in SharedPreferences if refresh fails
- **Token storage**: `SharedPreferences` keys: `ftth_access_token`, `ftth_refresh_token`, `ftth_token_expiry`, `ftth_username`, `ftth_password`
- **`authenticatedRequest(method, url, {body, headers})`**: Wraps all HTTP calls with automatic 401 retry

#### Login Page (`ftth/auth/login_page.dart`)
- Animated fiber-optic background with particle effects
- Remember-me with saved credentials
- After login → `PermissionManager.instance.loadPermissions()`
- Navigates to `HomePage` with merged permissions from System 1 (Sadara) + System 2 (FTTH)
- Admin detection via username pattern matching

#### Auth Error Handler (`ftth/auth/auth_error_handler.dart`)
- On 401 → redirects to `LoginPage`
- Preserves first-system (Sadara) credentials during redirect

### 2.2 Ticket System Login (`ftth/tickets/tickets_login_page.dart`)
- Separate login for ticket system using same `AuthService.instance.login()`
- Saved credentials under `tickets_username`, `tickets_password`, `tickets_remember_me`
- Auto-login if credentials are saved
- On success → navigates to `TKTATsPage` with `access_token`

---

## 3. Core Module

### 3.1 Home Page (`ftth/core/home_page.dart` — 4823 lines)

**Main dashboard and navigation hub**.

#### Dashboard Data
```dart
// GET https://admin.ftth.iq/api/auth/me → partnerId, partnerName, hierarchyLevel
// GET https://api.ftth.iq/api/partners/{partnerId}/wallets/balance
//   → model.balance (main wallet)
//   → model.teamMemberWallet.balance
//   → model.teamMemberWallet.hasWallet
//   → commission
```

#### Wallet Refresh
- Timer refreshes wallet every **60 seconds**
- Cached via `FtthCacheService` with 5-minute TTL

#### Permission Keys (~30+ permissions)
```
users, subscriptions, tasks, zones, accounts, tickets, reports,
audit_log, agents_details, profits, export, notifications,
plans_bundles, expiring_soon, connections_list, all_subscriptions,
technicians, users_dashboard, quick_search, account_stats,
creator_amounts, caounter_details, user_records, user_transactions,
users_data, whatsapp, pikachu ...
```

#### Navigation Targets
- Users pages (list, search, dashboard, data, records, transactions)
- Subscription pages (list, details, plans, expiring, connections, all)
- Transaction pages (list, records, stats, creator amounts, counter details)
- Report pages (zones, profits, agents, export, audit log)
- Ticket pages (list, technicians)
- Notifications page
- WhatsApp window

### 3.2 Permissions Page (`ftth/core/permissions_page.dart` — 565 lines)
- Grid-based permission management UI
- Toggles stored as JSON in user record
- Default password storage for second system
- Merge strategy: defaults ← overridden by user-specific permissions

---

## 4. Subscriptions Module

### 4.1 Subscriptions Page (`subscriptions_page.dart` — 4516 lines)

**Paginated subscription list with filtering**.

#### API Calls
```dart
// List subscriptions
GET https://admin.ftth.iq/api/subscriptions
  ?sortCriteria.property=expires
  &sortCriteria.direction=asc
  &hierarchyLevel=0
  &pageSize=...&pageNumber=...
  &status={Active|Expired|all}
  &zoneId=...
  &fromExpirationDate=...&toExpirationDate=...

// Device info per subscription
GET https://admin.ftth.iq/api/subscriptions/{id}/device
```

#### Features
- Status filters: All, Active, Expired
- Zone filtering via dropdown
- Date range filtering
- Batch detail/device fetching with concurrency control
- Password-protected Excel export

### 4.2 Subscription Details Page (`subscription_details_page.dart` — 11568 lines)

**The largest file in the module — handles subscription viewing, renewal, and financial operations**.

#### SubscriptionInfo Model
```dart
class SubscriptionInfo {
  String? zoneId, zoneDisplayValue, fbg, bundleId;
  String? customerId, customerName, partnerId, partnerName;
  String? deviceUsername, currentPlan, commitmentPeriod, status;
  String? services, deviceSerial, macAddress;
  String? gpsLatitude, gpsLongitude, deviceModel;
  String? subscriptionStartDate, salesType;
}
```

#### Available Plans
| Plan | Speed |
|------|-------|
| FIBER 35 | 35 Mbps |
| FIBER 50 | 50 Mbps |
| FIBER 75 | 75 Mbps |
| FIBER 150 | 150 Mbps |

#### Commitment Periods
1, 2, 3, 6, 12 months

#### Payment Methods
- `نقد` (Cash)
- `أجل` (Deferred)

#### Operation Types & IDs
| Operation | API enum | Type ID |
|-----------|----------|---------|
| Scheduled Change | ScheduledChange | 1 |
| Immediate Change | ImmediateChange | 2 |
| Scheduled Extend | ScheduledExtend | 4 |
| Immediate Extend | ImmediateExtend | 5 |
| Purchase From Trial | PurchaseFromTrial | 8 |
| Renew | Renew | 9 |

#### Price Calculation
```dart
GET https://admin.ftth.iq/api/subscriptions/calculate-price
  ?bundleId=...
  &commitmentPeriodValue=...
  &planOperationType={Extend|Change|PurchaseFromTrial}
  &subscriptionId=...
  &services={Base,VAS}
  &salesType=...
  &changeType=...
```

#### Allowed Actions
```dart
GET https://admin.ftth.iq/api/subscriptions/allowed-actions
  ?subscriptionIds=...&customerId=...
```

#### Plans & Bundles
```dart
GET https://admin.ftth.iq/api/plans/bundles
  ?includePrices=true&subscriptionId=...
```

#### Wallet Balance Queries
```dart
// Partner wallet
GET https://api.ftth.iq/api/partners/{partnerId}/wallets/balance

// Customer wallet
GET https://admin.ftth.iq/api/customers/{userId}/wallets/balance
```

### 4.3 Renewal Execution (`subscription_details_page.renewal.dart` — 956 lines)

**5-step sequential renewal process**:

```
Step 1: POST https://admin.ftth.iq/api/subscriptions/{id}/change
Step 2: Refresh page data (re-fetch subscription)
Step 3: Save to VPS server (POST to api.ramzalsadara.tech)
Step 4: Print receipt (thermal printer)
Step 5: Send WhatsApp message (if permission granted)
```

#### Change API Body
```json
{
  "simulatedPrice": { /* from price calculation */ },
  "bundleId": "...",
  "services": ["Base", "VAS"],
  "commitmentPeriodValue": 1,
  "salesType": 0,
  "paymentDetails": {
    "walletSource": "Partner",   // or "Customer"
    "paymentMethod": "Wallet"
  },
  "changeType": 1
}
```

#### Safety Mechanisms
- **Duplicate activation prevention**: Tracks same-day activations
- **Balance sufficiency check**: Verifies wallet before execution
- **Financial tracking fields**: `partnerWalletBalanceBefore`, `customerWalletBalanceBefore`, `isPrinted`, `isWhatsAppSent`

### 4.4 Expiring Soon Page (`expiring_soon_page.dart` — 2466 lines)

```dart
// Active subscriptions
GET https://admin.ftth.iq/api/subscriptions
  ?status=Active&hierarchyLevel=0
  &fromExpirationDate=...&toExpirationDate=...
  &zoneId=...&bundleName=...

// Trial subscriptions
GET https://admin.ftth.iq/api/subscriptions/trial
  ?status=Active&hierarchyLevel=0
  &fromExpirationDate=...&toExpirationDate=...
```

Quick date filters: Today, Tomorrow, 3 Days, Custom Range, All.

### 4.5 Plans & Bundles Page (`plans_bundles_page.dart` — 617 lines)
```dart
GET https://admin.ftth.iq/api/plans/bundles?includePrices=false
```
Groups plans by speed tier (FIBER 35, 50, 75, 100).

### 4.6 All Subscriptions Details (`all_subscriptions_details_page.dart` — 380 lines)
- Bulk fetches ALL subscriptions with progress indicator
- Enriches with customer summary:
```dart
GET https://api.ftth.iq/api/customers/summary?ids={comma-separated-ids}
```

### 4.7 Connections List (`connections_list_page.dart` — 2473 lines)
- Shows connections grouped by technician
- Data from VPS subscription logs service
- Filterable by date range and technician name

---

## 5. Transactions Module

### 5.1 Transaction Types (35+ types)
```dart
const transactionTypes = [
  'BAL_CARD_SELL', 'CASHBACK_COMMISSION', 'CASHOUT', 'HARDWARE_SELL',
  'MAINTENANCE_COMMISSION', 'PLAN_CHANGE', 'PLAN_PURCHASE', 'PLAN_RENEW',
  'PURCHASE_COMMISSION', 'SCHEDULE_CANCEL', 'SCHEDULE_CHANGE', 'TERMINATE',
  'TRIAL_PERIOD', 'WALLET_REFUND', 'WALLET_TOPUP', 'WALLET_TRANSFER',
  'PLAN_SCHEDULE', 'PURCH_COMM_REVERSAL', 'AUTO_RENEW',
  'TERMINATE_SUBSCRIPTION', 'PURCHASE_REVERSAL', 'HIER_COMM_REVERSAL',
  'HIERACHY_COMMISSION', 'WALLET_TRANSFER_COMMISSION', 'COMMISSION_TRANSFER',
  'RENEW_REVERSAL', 'MAINT_COMM_REVERSAL', 'WALLET_REVERSAL',
  'WALLET_TRANSFER_FEE', 'PLAN_EMI_RENEW', 'PLAN_SUSPEND', 'PLAN_REACTIVATE',
  'REFILL_TEAM_MEMBER_BALANCE', 'PurchaseSubscriptionFromTrial'
];
```

### 5.2 Filter Options
| Filter | Values |
|--------|--------|
| Wallet Types | Main, Secondary |
| Wallet Owner | partner, customer |
| Sales Types | 0=single payment, 1=monthly |
| Change Types | 0=scheduled, 1=immediate |
| Payment Methods | 0=cash, 1=credit card, 2=bank transfer, 3=e-wallet, 4=FastPay |

### 5.3 Transactions Page (`transactions_page.dart` — 5489 lines)
- Pagination with page sizes up to 5000
- Positive/negative sum tracking
- Creator-based grouping

### 5.4 Account Records (`account_records_page.dart` — 3603 lines)
```dart
// VPS subscription logs
GET https://api.ramzalsadara.tech/api/internal/subscriptionlogs
// Header: x-api-key: sadara-internal-2024-secure-key

// Filters: operationType (purchase/renewal), zone, executor,
//   subscriptionType, paymentType, printStatus, whatsAppStatus
```
Quick date filters: today, yesterday, today+yesterday.

### 5.5 Account Stats (`account_stats_page.dart` — 624 lines)
Summary statistics model:
```dart
purchaseCount, purchaseTotal
renewalCount, renewalTotal
cashCount, cashTotal
creditCount, creditTotal
// Per-user: UserAccountStat breakdown
```

### 5.6 Creator Amounts (`creator_amounts_page.dart` — 1064 lines)
Groups transactions by creator (username) into categories:
- تعبئة رصيد (Top-up)
- عمليات الشراء (Purchases)
- تجديد وتغيير ومجدول (Renewal/Change/Scheduled)
- أخرى (Other)

Total only counts: Purchases + Renewals (excludes top-ups).

### 5.7 Creator Transaction Details (`creator_transactions_detail_page.dart` — 2453 lines)
```dart
// Audit logs for specific customer
GET https://admin.ftth.iq/api/audit-logs
  ?customerId={id}&...
```

### 5.8 Counter Details (`caounter_details_page.dart` — 2628 lines)
```dart
// Current user info
GET https://admin.ftth.iq/api/auth/me → partnerId

// Audit logs with filters
GET https://admin.ftth.iq/api/audit-logs
  ?eventType={ChangeSubscription|ExtendSubscription|PurchaseSubscriptionFromTrial|...}

// Zones
GET https://api.ftth.iq/api/locations/zones
```

Event types tracked:
```
ChangeSubscription, ExtendSubscription, PurchaseSubscriptionFromTrial,
WALLET_TOPUP, WALLET_TRANSFER, RefillTeamMemberWallet
```

---

## 6. Reports Module

### 6.1 Zones Page (`zones_page.dart` — 1222 lines)
```dart
GET https://admin.ftth.iq/api/locations/zones?pageSize=1000&pageNumber=1
```
Displays zones with expandable detail cards.

### 6.2 Profits Page (`profits_page.dart` — 3346 lines)
Profit calculation per plan category:
| Category | Plans |
|----------|-------|
| FIBER 35 | 35 Mbps tier |
| FIBER 50 | 50 Mbps tier |
| FIBER 75 | 75 Mbps tier |
| FIBER 150 | 150 Mbps tier |

Per-type profits: `purchase`, `renewalFromPurchase`, `renewal`.

Profits are saved locally: `SharedPreferences` key `saved_category_profits`.

### 6.3 Data Page (`data_page.dart`)
Tab container with two tabs:
1. `AgentsDetailsPage` — agent statistics
2. `UsersDataPage` — user statistics

### 6.4 Agents Details (`agents_details_page.dart` — 2578 lines)
- Integrates with **Superset** dashboard at `https://dashboard.ftth.iq`
- Uses guest token authentication
- Fetches dashboard slices for statistics

### 6.5 Export Page (`export_page.dart` — 1290 lines)
- Animated export buttons for various data exports
- Supports Excel export with password protection

### 6.6 Audit Log (`audit_log_page.dart` — 1066 lines)
```dart
// Per-customer audit log
GET https://admin.ftth.iq/api/audit-logs?customerId={id}

// Audit log summary
GET https://admin.ftth.iq/api/audit-logs/summary?customerId={id}
// → totalAmount
```

---

## 7. Users Module

### 7.1 Users Page (`users_page.dart` — 1775 lines)
```dart
// Customer listing (via ApiService → api.ftth.iq)
GET https://api.ftth.iq/api/customers/...

// Zones for filter dropdown
GET https://api.ftth.iq/api/locations/zones
```
- Zone-based filtering
- Search by name/phone
- Excel export capability

### 7.2 User Details (`user_details_page.dart` — 2423 lines)
```dart
// Customer subscriptions
GET https://admin.ftth.iq/api/customers/subscriptions?customerId={id}

// Full subscription details
GET https://admin.ftth.iq/api/subscriptions/{id}

// Device ONT info
GET https://admin.ftth.iq/api/subscriptions/{id}/device
```
Navigation to: `SubscriptionDetailsPage`, `CustomerTicketsPage`, `AuditLogPage`.

### 7.3 Quick Search (`quick_search_users_page.dart` — 1446 lines)
- Debounced search (waits for typing to pause)
- Infinite scroll pagination
- Search fields: name, phone, zone

### 7.4 Users Data (`users_data_page.dart` — 899 lines)
- Fetches data from Superset dashboard slice_id=48
- Uses guest token auth for `dashboard.ftth.iq`
- Cloudflare bypass handling

### 7.5 Users Dashboard WebView (`users_dashboard_webview.dart` — 352 lines)
```dart
// WebView displaying
https://admin.ftth.iq/dashboard
```

### 7.6 User Records (`user_records_page.dart` — 1187 lines)
- Per-user filtered records from VPS subscription logs
- Same API as account_records but filtered by specific user

### 7.7 User Transactions (`user_transactions_page.dart` — 568 lines)
```dart
// Legacy API
GET https://alsadara-ftth-api.alsadara-cctv.com/transactions
  ?transactionUser={name}
```

---

## 8. Tickets Module

### 8.1 Tickets List (`tktats_page.dart` — 3016 lines)

**Main ticket management page with real-time updates**.

```dart
// Fetch tickets (open, page 50)
GET https://api.ftth.iq/api/support/tickets
  ?pageSize=50
  &pageNumber={page}
  &sortCriteria.property=createdAt
  &sortCriteria.direction=desc
  &status=0              // 0 = Open
  &hierarchyLevel=0
```

#### Auto-Refresh System
- Polls every **30 seconds** via `Timer.periodic`
- Single-flight pattern: `_fetchInProgress` prevents concurrent fetches
- UI updates suspended while detail page is open (`_uiUpdatesSuspended`)

#### Notification System
- **System notifications**: `flutter_local_notifications` (Android/iOS channels)
- **In-app notifications**: SnackBar with action button
- **New ticket detection**: Compares `seenTKTATIds` set against fetched IDs
- **Badge service**: `BadgeService.instance` for unread count
- **Connectivity check**: `connectivity_plus` package before each fetch

#### Filtering
- Ticket types: 'all', 'company', 'agent'
- Filter categories: zone, customer, status
- Text search

### 8.2 Beautiful Tickets (`tktats_page_beautiful.dart` — 542 lines)
Alternative UI for ticket list. Same API endpoint. Simpler implementation without badge/notification tracking.

### 8.3 Ticket Details (`tktat_details_page.dart` — 1526 lines)

#### Data Extraction Helpers
```dart
extractTitle(map)    → self.displayValue | title | subject | name
extractSummary(map)  → summary | description | details
extractCustomer(map) → customer.displayValue | customerName | clientName
extractZone(map)     → zone.displayValue | zone | region
```

#### SLA Tracking
- **Incident/Outage**: 4-hour SLA target
- **Other categories**: 24-hour SLA target
- Real-time countdown via `Timer.periodic(Duration(seconds: 1))`
- Visual: progress bar + elapsed/remaining time in Arabic numerals

#### Comments API
```dart
// Fetch comments
GET https://admin.ftth.iq/api/support/tickets/{ticketGuid}/comments
  ?pageSize=10&pageNumber=1

// Post comment
POST https://admin.ftth.iq/api/support/tickets/{ticketGuid}/comments
Body: { "body": "...", "ticketId": "{ticketGuid}" }
```
- Optimistic insert: adds comment to UI immediately after successful POST
- Comments sorted descending by `createdAt`

#### External Link
```dart
// Open in browser
https://admin.ftth.iq/tickets/details/{ticketGuid}
```

#### Task Integration
- Imports `AddTaskApiDialog` from `../../task/add_task_api_dialog.dart`
- Can create internal tasks from ticket data

### 8.4 Raw Ticket Data (`tktat_raw_page.dart` — 165 lines)
- Pretty-prints ticket JSON with `JsonEncoder.withIndent`
- Two tabs: sorted key-value pairs + raw JSON
- Copy-to-clipboard functionality

### 8.5 Customer Tickets (`customer_tickets_page.dart` — 373 lines)
```dart
// Per-customer tickets
GET https://admin.ftth.iq/api/support/tickets
  ?pageSize=40
  &pageNumber={page}
  &sortCriteria.property=UpdatedAt
  &sortCriteria.direction=desc
  &customerId={customerId}
```

Status localization:
| English | Arabic |
|---------|--------|
| Open | مفتوحة |
| Closed | مغلقة |
| In Progress / Processing | قيد المعالجة |
| Pending | معلقة |

### 8.6 Technicians Page (`technicians_page.dart` — 453 lines)
- **Fully local** — no API calls
- CRUD for technician records (name + phone)
- Storage: `SharedPreferences` key `local_technicians_list`
- JSON serialization: `[{"name": "...", "phone": "..."}]`
- Permission-gated via `PermissionChecker`

### 8.7 TKTAT Stub (`TKTAT.dart` — 117 lines)
- Placeholder/stub page with empty fetch logic
- `Future.delayed(1 second)` simulation
- Not connected to real API

---

## 9. Widgets Module

### 9.1 Notifications Page (`notifications_page.dart` — 733 lines)

```dart
// Fetch notifications
GET https://admin.ftth.iq/api/notifications
  ?onlyUnreadNotifications={true|false}
  &pageSize=20
  &pageNumber={page}

// Mark as read
POST https://admin.ftth.iq/api/notifications/{notificationId}/mark-as-read
```

#### Notification Categories (auto-detected from description)
| Description contains | Title | Icon |
|---------------------|-------|------|
| password | تم تحديث كلمة المرور | lock |
| Service request / approved | طلب خدمة / تم الموافقة | check_circle |
| wallet / debited | خصم من المحفظة | account_balance_wallet |
| updated | تم التحديث | update |
| (default) | إشعار | notifications |

#### Features
- Infinite scroll pagination
- Toggle: unread only vs. all
- Relative time formatting (Arabic)
- 401 handling via `AuthErrorHandler`

### 9.2 Notification Filter (`notification_filter.dart` — 217 lines)

**Smart notification display utility** used across FTTH pages.

```dart
// Blocked messages (silently suppressed)
static const String blockedMessage = 'لم يتم جلب الرصيد';

// Smart notification routing
ftthShowSmartNotification(context, message):
  - Contains 'تم|نجح|متاح|حفظ|مكتمل|إرسال|تسجيل الدخول' → green (success)
  - Contains 'خطأ|فشل|تعذر|غير متوفر|غير صحيح|يرجى|يجب' → red (error)
  - Otherwise → blue (info)
```

Helper functions:
- `ftthShowSuccessNotification()` — green overlay
- `ftthShowErrorNotification()` — red overlay, 4-second duration
- `ftthShowInfoNotification()` — blue overlay
- `ftthShowSnackBar()` — filtered SnackBar with copy button
- `_toCopyableSnackBar()` — adds copy icon button + SelectableText

### 9.3 Pikachu Overlay (`pikachu_overlay.dart` — 252 lines)

**Easter egg**: Animated Pikachu (Lottie) that follows the mouse cursor.

```dart
PikachuOverlay.init(context)      // Initialize + show if enabled
PikachuOverlay.updateTargetPosition(offset)  // Called from MouseRegion

// Smooth follow: lerp factor 0.08, 16ms timer (60fps)
// Auto-stops after 30 idle frames (~0.5s without movement)
// Direction flip based on movement direction
// Persisted setting: SharedPreferences key 'show_pikachu'
```

---

## 10. WhatsApp Module

### 10.1 Architecture

Three implementations of WhatsApp Web integration, all using **WebView** to load `https://web.whatsapp.com`:

| File | Approach | Lines |
|------|----------|-------|
| `whatsapp_bottom_window.dart` | Full-screen overlay (primary, with autoSend) | 1370 |
| `whatsapp_bottom_window_fixed.dart` | Full-screen overlay (fixed, no autoSend) | 1167 |
| `whatsapp_floating_window.dart` | Standalone window via window_manager | 413 |

### 10.2 WhatsApp Bottom Window (Primary)

**Full-screen overlay** using Flutter's `Overlay` system.

```dart
// URL pattern
https://web.whatsapp.com/send?phone={phone}&text={encodedMessage}

// Detection: logged in when URL contains 'web.whatsapp.com' but not '/auth'
```

#### State Management
- `_isShowing` — overlay is in the widget tree
- `_isHidden` — overlay is minimized (invisible but WebView preserved in memory)
- `_savedWindowContent` — cached widget for instant restore
- `_windowKey` — GlobalKey preserves State across show/hide

#### Key Methods
```dart
WhatsAppBottomWindow.showBottomWindow(context, phone, message, {autoSend})
WhatsAppBottomWindow.hideBottomWindow({clearContent})
WhatsAppBottomWindow.sendMessageToBottomWindow(phone, message, {autoSend})
WhatsAppBottomWindow.ensureFloatingButton(context)  // survive page navigation
WhatsAppBottomWindow.ensureGlobal(context)           // root overlay init
```

#### Feature: Minimize/Restore
- Minimize: sets `_isHidden=true`, `AnimatedOpacity(0)`, `IgnorePointer(ignoring:true)`
- Restore: sets `_isHidden=false` — no reload, WebView session preserved
- Floating Action Button (FAB) persists via `_fabGuardTimer`

#### Platform Support
- **Windows**: `webview_windows` package (`wvwin.WebviewController`)
- **Other**: `webview_flutter` package (`WebViewController`)

#### Conversation Tracking
- Integrates with `WhatsAppConversationService` for conversation history
- Floating conversations button (`_conversationsFabEntry`)

### 10.3 WhatsApp Floating Window (`whatsapp_floating_window.dart`)

**Standalone window** using `window_manager`:
```dart
WindowOptions(
  size: Size(400, 600),
  minimumSize: Size(350, 500),
  title: 'واتساب ويب',
  alwaysOnTop: true,
  position: Offset(50, 50)
)
```

- Login state persisted: `SharedPreferences` key `wa_web_logged_in`
- Status monitoring via periodic timer
- Can send to new phone numbers dynamically

---

## 11. Data Models

### 11.1 SubscriptionInfo
```dart
// Used in subscription_details_page.dart
{
  zoneId, zoneDisplayValue, fbg,
  bundleId, customerId, customerName,
  partnerId, partnerName,
  deviceUsername, currentPlan, commitmentPeriod, status,
  services, deviceSerial, macAddress,
  gpsLatitude, gpsLongitude, deviceModel,
  subscriptionStartDate, salesType
}
```

### 11.2 Wallet Balance Response
```dart
// GET /partners/{id}/wallets/balance
{
  "model": {
    "balance": 1000.0,
    "commission": 50.0,
    "teamMemberWallet": {
      "balance": 500.0,
      "hasWallet": true
    }
  }
}
```

### 11.3 Price Calculation Response
```dart
// GET /subscriptions/calculate-price
{
  "simulatedPrice": { /* pricing details */ },
  "totalPrice": 50000,
  // ... additional pricing breakdown
}
```

### 11.4 Ticket Model (from API response)
```dart
{
  "id": "guid",
  "displayId": "TICKET-001",
  "self": { "id": "guid", "displayValue": "..." },
  "title": "...",
  "summary": "...",
  "customer": { "id": "guid", "displayValue": "name" },
  "zone": { "displayValue": "zone-name" },
  "status": "Open|Closed|InProgress|Pending",
  "category": "incident|...",
  "createdAt": "2024-01-01T00:00:00Z",
  "updatedAt": "2024-01-01T00:00:00Z"
}
```

### 11.5 Notification Model
```dart
{
  "self": { "id": "notification-guid", "displayValue": "..." },
  "description": "...",
  "isRead": false,
  "readAt": null,
  "createdAt": "2024-01-01T00:00:00Z"
}
```

### 11.6 Account Record (VPS)
```dart
{
  "operationType": "purchase|renewal",
  "zone": "...",
  "executor": "...",
  "subscriptionType": "...",
  "paymentType": "cash|credit",
  "isPrinted": true,
  "isWhatsAppSent": false,
  "partnerWalletBalanceBefore": 1000.0,
  "customerWalletBalanceBefore": 500.0,
  // ... subscription details
}
```

---

## 12. API Endpoints Catalog

### 12.1 Authentication (`admin.ftth.iq`)
| Method | Endpoint | Purpose |
|--------|----------|---------|
| POST | `/api/auth/Contractor/token` | Login (OAuth2 password grant) |
| POST | `/api/auth/Contractor/refresh` | Refresh token |
| GET | `/api/auth/me` | Current user info → partnerId |

### 12.2 Subscriptions (`admin.ftth.iq`)
| Method | Endpoint | Purpose |
|--------|----------|---------|
| GET | `/api/subscriptions` | List subscriptions (paginated, filtered) |
| GET | `/api/subscriptions/{id}` | Single subscription detail |
| GET | `/api/subscriptions/{id}/device` | Device/ONT info |
| GET | `/api/subscriptions/trial/{id}` | Trial subscription info |
| GET | `/api/subscriptions/trial` | List trial subscriptions |
| GET | `/api/subscriptions/calculate-price` | Price calculation |
| GET | `/api/subscriptions/allowed-actions` | Allowed operations |
| POST | `/api/subscriptions/{id}/change` | Execute renewal/change/purchase |

### 12.3 Plans (`admin.ftth.iq`)
| Method | Endpoint | Purpose |
|--------|----------|---------|
| GET | `/api/plans/bundles` | List plans (optional `includePrices`) |

### 12.4 Customers (`api.ftth.iq` + `admin.ftth.iq`)
| Method | Endpoint | Base | Purpose |
|--------|----------|------|---------|
| GET | `/api/customers/subscriptions` | admin | Customer subscription list |
| GET | `/api/customers/summary` | api | Bulk customer info |
| GET | `/api/customers/{id}/wallets/balance` | admin | Customer wallet |
| GET | `/api/customers/...` | api | Customer listing/search |

### 12.5 Partners (`api.ftth.iq`)
| Method | Endpoint | Purpose |
|--------|----------|---------|
| GET | `/api/partners/{id}/wallets/balance` | Partner wallet + commission |

### 12.6 Locations (`api.ftth.iq` + `admin.ftth.iq`)
| Method | Endpoint | Purpose |
|--------|----------|---------|
| GET | `/api/locations/zones` | Zone listing (both bases) |

### 12.7 Audit Logs (`admin.ftth.iq`)
| Method | Endpoint | Purpose |
|--------|----------|---------|
| GET | `/api/audit-logs` | Filtered audit logs |
| GET | `/api/audit-logs/summary` | Customer total amount |

### 12.8 Support / Tickets (`api.ftth.iq` + `admin.ftth.iq`)
| Method | Endpoint | Base | Purpose |
|--------|----------|------|---------|
| GET | `/api/support/tickets` | api | All open tickets |
| GET | `/api/support/tickets` | admin | Customer-specific tickets |
| GET | `/api/support/tickets/{id}/comments` | admin | Ticket comments |
| POST | `/api/support/tickets/{id}/comments` | admin | Post comment |

### 12.9 Notifications (`admin.ftth.iq`)
| Method | Endpoint | Purpose |
|--------|----------|---------|
| GET | `/api/notifications` | List notifications |
| POST | `/api/notifications/{id}/mark-as-read` | Mark read |

### 12.10 VPS Internal API (`api.ramzalsadara.tech`)
| Method | Endpoint | Purpose |
|--------|----------|---------|
| GET | `/api/internal/subscriptionlogs` | Subscription operation logs |
| POST | `/api/internal/subscriptionlogs` | Save operation log |

**Header**: `x-api-key: sadara-internal-2024-secure-key`

### 12.11 Legacy API (`alsadara-ftth-api.alsadara-cctv.com`)
| Method | Endpoint | Purpose |
|--------|----------|---------|
| GET | `/transactions` | User transactions (legacy) |

### 12.12 Dashboard (`dashboard.ftth.iq`)
| Method | Endpoint | Purpose |
|--------|----------|---------|
| POST | `/api/v1/security/guest_token/` | Superset guest token |
| GET | `/api/v1/chart/data` | Dashboard slice data |

### 12.13 WhatsApp (web.whatsapp.com)
| URL Pattern | Purpose |
|-------------|---------|
| `https://web.whatsapp.com/send?phone={phone}&text={msg}` | Send message via WhatsApp Web |

---

## 13. Financial Flow

### 13.1 Renewal / Purchase Flow

```
┌─────────────────────┐
│  User selects plan   │
│  + commitment period │
└──────────┬──────────┘
           │
           ▼
┌─────────────────────────────┐
│  Calculate Price             │
│  GET /subscriptions/         │
│      calculate-price         │
│  → simulatedPrice object     │
└──────────┬──────────────────┘
           │
           ▼
┌─────────────────────────────┐
│  Check Wallet Balance        │
│  GET /partners/{id}/         │
│      wallets/balance         │
│  → verify sufficient funds   │
└──────────┬──────────────────┘
           │
           ▼
┌─────────────────────────────┐
│  Check Duplicate Activation  │
│  Same subscription + same    │
│  day → block                 │
└──────────┬──────────────────┘
           │
           ▼
┌─────────────────────────────┐
│  Execute Change              │
│  POST /subscriptions/        │
│       {id}/change            │
│  Body: {                     │
│    simulatedPrice,           │
│    bundleId,                 │
│    services: [Base, VAS],    │
│    commitmentPeriodValue,    │
│    salesType,                │
│    paymentDetails: {         │
│      walletSource: Partner,  │
│      paymentMethod: Wallet   │
│    },                        │
│    changeType: 1             │
│  }                           │
└──────────┬──────────────────┘
           │
           ▼
┌─────────────────────────────┐
│  Post-Execution (parallel)   │
│  1. Refresh subscription     │
│  2. Save to VPS logs         │
│     (api.ramzalsadara.tech)  │
│  3. Print thermal receipt    │
│  4. Send WhatsApp message    │
└─────────────────────────────┘
```

### 13.2 Wallet Types
| Wallet | Source | API |
|--------|--------|-----|
| Partner Main | Partner company | `/partners/{id}/wallets/balance` → `model.balance` |
| Partner Commission | Earned from sales | `model.commission` |
| Team Member | Sub-agent wallet | `model.teamMemberWallet.balance` |
| Customer | End-user wallet | `/customers/{id}/wallets/balance` |

### 13.3 Payment Sources
- **Partner Wallet**: Default — company pays from its balance
- **Customer Wallet**: Customer's stored balance in the ISP system
- **PaymentMethod**: Always "Wallet" (deducted from selected source)

### 13.4 Financial Tracking
Each operation records:
```dart
partnerWalletBalanceBefore   // Snapshot before deduction
customerWalletBalanceBefore  // Snapshot before deduction
isPrinted                    // Receipt printed?
isWhatsAppSent               // WhatsApp confirmation sent?
```

### 13.5 Profit Calculation
Per plan category (FIBER 35/50/75/150):
- **Purchase profit**: Revenue from new subscriptions
- **Renewal from purchase profit**: Revenue from renewals of purchased subs
- **Pure renewal profit**: Revenue from pure renewals
- Stored locally in `SharedPreferences` as `saved_category_profits`

---

## Architecture Notes

### External Systems Topology
```
┌──────────────────────────────────────────────────────────┐
│                    Flutter Desktop App                    │
│                 (CompanyDesktop/alsadara-ftth)            │
└──┬───────────┬────────────┬───────────┬──────────────────┘
   │           │            │           │
   ▼           ▼            ▼           ▼
┌──────┐  ┌─────────┐  ┌────────┐  ┌──────────────────┐
│admin.│  │api.ftth. │  │ VPS    │  │ dashboard.ftth.  │
│ftth. │  │   iq    │  │(sadara)│  │    iq (Superset) │
│iq    │  │         │  │        │  │                  │
├──────┤  ├─────────┤  ├────────┤  ├──────────────────┤
│Auth  │  │Partners │  │Sub logs│  │Guest token auth  │
│Subs  │  │Customers│  │Records │  │Dashboard slices  │
│Plans │  │Zones    │  │Stats   │  │Charts/Data       │
│Audit │  │Tickets  │  │        │  │                  │
│Notifs│  │         │  │        │  │                  │
│Tickets│  │         │  │        │  │                  │
└──────┘  └─────────┘  └────────┘  └──────────────────┘
   ↑                       ↑
   │  185.239.19.3         │  72.61.183.61
   │  (NOT ours)           │  (Our server)
   │                       │
```

### Data Flow Patterns
1. **Auth tokens** flow from `admin.ftth.iq` → stored in `SharedPreferences` → attached to all requests via `AuthService.authenticatedRequest()`
2. **Subscription operations** execute on `admin.ftth.iq` then **mirror** data to VPS (`api.ramzalsadara.tech`) for internal tracking
3. **Wallet balances** come from `api.ftth.iq` (partner) and `admin.ftth.iq` (customer)
4. **Dashboard data** comes from `dashboard.ftth.iq` Superset via guest token proxy
5. **WhatsApp messages** are sent via WebView → `web.whatsapp.com` (not an API, browser automation)
