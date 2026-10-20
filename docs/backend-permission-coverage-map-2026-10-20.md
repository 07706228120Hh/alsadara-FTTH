# تقرير تغطية صلاحيات الباكند — منصة الصدارة
**الفرع:** `security/expose-endpoints-hardening` · **المصدر:** خريطة 879 endpoint · **المُحلَّل فعلياً:** 848 سطراً (انظر ملاحظة الاقتطاع) · **التاريخ:** 2026-10-20

> **منهجية التصنيف المعتمدة:** «يحتاج إضافة `[RequirePermission]`» = كل endpoint ليس `require-permission` وليس `keep-anonymous`. فصلتُ نقاط `internal-key` (خادم-لخادم عبر X-Api-Key) في مسار حوكمة مستقل لأنها غير قابلة للوصول بتوكن موظف، فإضافة صلاحية موظف إليها بلا معنى قبل تحويلها عبر البوّابة. القائمة الأساسية في القسم 2 تغطي ما يصله **توكن الموظف**.

> **ملاحظة الاقتطاع (مهمة):** مُدخَل JSON انقطع داخل `CitizenPortalController` عند `UpdatePlan`. من الكود الفعلي: هذا المتحكّم فيه **17** endpoint (الثلاثة الأخيرة GetTickets/ReplyToTicket/CloseTicket كانت بعد نقطة القطع، كلها `authorize-only` + `citizen_portal`). المتحكّمات **الوحيدة الغائبة كلياً** عن الخريطة هي `AuthController` و`CitizenAuthController` و`UnifiedAuthController` (~31 نقطة = الفجوة حتى 879)، وكلها نقاط دخول/تحديث توكن/تسجيل **عامة `[AllowAnonymous]`** ⇒ `keep-anonymous` ولا تغيّر استنتاجات التقرير.

---

## 1) جدول ملخّص: عدد الـendpoints لكل متحكّم حسب نوع البوّابة

| المتحكّم | الإجمالي | require-perm | authorize-only | policy | anonymous | none | internal-key |
|---|---:|---:|---:|---:|---:|---:|---:|
| AccountingController | 79 | 79 | — | — | — | — | — |
| InventoryController | 77 | 77 | — | — | — | — | — |
| SasAgentController | 74 | 74 | — | — | — | — | — |
| InternalDataController | 62 | — | — | — | 1 | — | 61 |
| SuperAdminController | 38 | — | — | 29 | 2 | — | 7 |
| PropertiesController | 33 | 33 | — | — | — | — | — |
| FtthAccountingController | 31 | — | 22 | 8 | — | — | 1 |
| Chat​Controller | 24 | — | 24 | — | — | — | — |
| AttendanceController | 20 | 20 | — | — | — | — | — |
| CompaniesController | 20 | — | — | 16 | 4 | — | — |
| AgentsController | 21 | 9 | 11 | — | 1 | — | — |
| ServiceRequestsController | 21 | — | 14 | 6 | 1 | — | — |
| CitizenPortalController | 17 | — | 17 | — | — | — | — |
| DatabaseAdminController | 16 | — | — | — | — | — | 16 |
| ServerController | 14 | — | — | 14 | — | — | — |
| CompanyFtthSettingsController | 14 | — | — | — | — | — | 14 |
| LinkedAccountsController | 12 | 12 | — | — | — | — | — |
| WhatsAppController | 12 | — | — | — | — | — | 12 |
| SubscriptionLogsController | 11 | — | 11 | — | — | — | — |
| LeaveController | 10 | — | — | 10 | — | — | — |
| DepartmentsController | 10 | — | — | 10 | — | — | — |
| AnnouncementsController | 9 | — | 9 | — | — | — | — |
| HrReportsController | 9 | 9 | — | — | — | — | — |
| EmployeeLocationController | 9 | — | — | — | — | — | 9 |
| CitizenStoreController | 9 | — | 5 | — | — | 4 | — |
| WithdrawalRequestController | 8 | — | — | 8 | — | — | — |
| ISPSubscribersController | 8 | — | 8 | — | — | — | — |
| NotificationsController | 8 | — | 7 | 1 | — | — | — |
| SettingsController | 8 | — | — | 6 | 2 | — | — |
| MerchantsController | 8 | — | 2 | 6 | — | — | — |
| TechnicianTransactionsController | 7 | — | — | 7 | — | — | — |
| UsersController | 7 | — | 3 | 3 | — | 1 | — |
| DashboardController | 7 | — | — | 7 | — | — | — |
| ZoneStatisticsController | 7 | — | — | — | — | — | 7 |
| CitiesController | 7 | — | 3 | — | — | 4 | — |
| SupportTicketsController | 7 | — | 7 | — | — | — | — |
| CouponsController | 7 | — | 1 | 6 | — | — | — |
| CategoriesController | 7 | — | — | 3 | — | 4 | — |
| ProductsController | 7 | — | — | 3 | — | 4 | — |
| ReviewsController | 7 | — | 3 | 2 | 2 | — | — |
| CitizenSubscriptionsController | 7 | — | 7 | — | — | — | — |
| CartController | 7 | — | 7 | — | — | — | — |
| ZoneMaintenanceFeesController | 6 | — | 5 | — | 1 | — | — |
| WishlistController | 6 | — | 6 | — | — | — | — |
| AddressesController | 6 | — | 6 | — | — | — | — |
| PaymentsController | 6 | — | 3 | 2 | — | 1 | — |
| ReminderController | 5 | — | — | — | — | — | 5 |
| IptvSubscribersController | 5 | — | — | — | — | — | 5 |
| InternetPlansController | 5 | — | 1 | — | — | 4 | — |
| TaskAuditsController | 5 | — | 5 | — | — | — | — |
| CustomersController | 5 | — | 5 | — | — | — | — |
| AdvertisingsController | 5 | — | 2 | — | — | 3 | — |
| CompanyCentersController | 4 | — | — | 4 | — | — | — |
| OrdersController | 4 | — | 4 | — | — | — | — |
| SubscriberCacheController | 4 | — | — | — | — | — | 4 |
| OcrController | 2 | — | 2 | — | — | — | — |
| FcmTokensController | 2 | — | 2 | — | — | — | — |
| AppVersionsController | 2 | — | — | — | — | 2 | — |
| **الإجمالي (848)** | **848** | **313** | **202** | **151** | **14** | **27** | **141** |

---

## 2) الـendpoints التي تحتاج إضافة `[RequirePermission]` (ليست require-permission وليست keep-anonymous)

مجمّعة حسب المتحكّم. ⚠️ = خطر مرتفع (مالي/حذف/يتجاوز العزل/IDOR). القوائم كاملة غير مختصرة.

### 2-أ: مصادَق بلا بوّابة صلاحيات (currentGate = authorize-only) — أخطر فئة

**ISPSubscribersController** — كلها بلا عزل CompanyId من التوكن ⚠️
| endpoint | المقترح |
|---|---|
| GetAll | users.view ⚠️ |
| GetRegions | users.view ⚠️ |
| KinshipSearch | users.view ⚠️ |
| GetByRegion | users.view ⚠️ |
| Create | users.add ⚠️ (CompanyId من الجسم) |
| BulkCreate | users.add ⚠️ |
| Update | users.edit ⚠️ |
| Delete | users.delete ⚠️ |

**SubscriptionLogsController** — بلا فلتر CompanyId + قيود محاسبية تلقائية ⚠️
| endpoint | المقترح |
|---|---|
| GetAll | subscriptions.view ⚠️ |
| GetById | subscriptions.view |
| Create | subscriptions.add ⚠️ (CompanyId من الجسم + قيد تلقائي) |
| Update | subscriptions.edit |
| Delete | subscriptions.delete ⚠️ (يعكس أرصدة + يلغي قيد) |
| RepairAccounting | accounting.audit_trail.edit ⚠️⚠️ (تسوية مجمّعة منذ 2026-06-08) |
| GetBySubscription | subscriptions.view |
| GetStats | accounting.statistics.view |
| GetConnections | accounting.ftth_operators.view |
| UpdatePaymentStatus | accounting.ftth_operators.edit |
| BulkUpdatePaymentStatus | accounting.ftth_operators.edit ⚠️ |

**FtthAccountingController** (authorize-only)
| endpoint | المقترح |
|---|---|
| LogWithAccounting | accounting.ftth_operators.add ⚠️ (قيود + CompanyId من العميل) |
| GetFtthCredentials | hr.ftth_info.view ⚠️ (يكشف اعتماد FTTH) |
| GetOperatorSummary | accounting.ftth_operators.view |
| GetOperatorsDashboard | accounting.ftth_operators.view |
| DeliverCash | accounting.ftth_operators.edit |
| GetCreditCustomers | accounting.ftth_operators.view |
| SetRenewalCycle | accounting.ftth_operators.edit |
| UpdateSubscriptionLog | accounting.ftth_operators.edit |
| CollectRenewalMonth | accounting.ftth_operators.edit |
| CollectCredit | accounting.ftth_operators.edit |
| LinkFtthAccount | hr.ftth_info.edit |
| GetAgentsList | agents.view |
| GetTechniciansList | technicians.view |
| GetOperatorsLinking | accounting.ftth_operators.view |
| GetExistingFtthIds | accounting.ftth_operators.view |
| SyncFtthTransactions | accounting.ftth_operators.edit |
| FixBasePrices | accounting.ftth_operators.edit |
| MergeDuplicate | accounting.ftth_operators.edit |
| MergeDuplicatesBatch | accounting.ftth_operators.edit |
| QuickDeliver | accounting.ftth_operators.edit |
| QuickCollect | accounting.ftth_operators.edit |
| GetFundsOverview | accounting.funds_overview.view |

**ChatController** (24 — كلها authorize-only بلا مفتاح)
| endpoint | المقترح |
|---|---|
| GetMyRooms | chat.view |
| GetAllCompanyRooms | chat.view (+حارس أدمن) |
| CreateRoom | chat.create_group.add |
| GetRoomMembers | chat.view |
| GetMessages | chat.view |
| DeleteRoom | chat.manage_members.delete |
| DeleteMessage | chat.delete_messages.delete |
| SendMessage | chat.send_text.add |
| UploadAttachment | chat.send_file.add |
| GetAttachment | chat.view (نظّف filePath) |
| GetUnreadCount | chat.view |
| SearchMessages | chat.search.view |
| GetProfileCard | chat.view_profile.view |
| GetAvailableUsers | chat.view |
| GetAvailableDepartments | chat.create_department.view |
| MarkAsRead | chat.view (تفضيل شخصي) |
| ToggleReaction | chat.send_text.add |
| GetReactions | chat.view |
| LeaveRoom | chat.view (ذاتي) |
| UpdateRoomName | chat.manage_members.edit |
| TogglePin | chat.view (شخصي) |
| ToggleMute | chat.view (شخصي) |
| AddMembers | chat.manage_members.add |
| RemoveMember | chat.manage_members.delete |

**AnnouncementsController** (9 — بلا حارس دور، أي مستخدم يُنشئ إعلاناً) ⚠️
| endpoint | المقترح |
|---|---|
| GetMyAnnouncements | announcements.view |
| MarkAsRead | announcements.view |
| GetUnreadCount | announcements.view |
| GetReadReport | announcements.manage.view |
| GetAll | announcements.manage.view |
| Create | announcements.manage.add ⚠️ |
| Update | announcements.manage.edit ⚠️ |
| Delete | announcements.manage.delete ⚠️ |
| UploadImage | announcements.manage.add |

**NotificationsController**
| endpoint | المقترح |
|---|---|
| GetMyNotifications | notifications.view |
| GetMyUnreadCount | notifications.view |
| GetByUser | notifications.view ⚠️ (IDOR: userId من العميل) |
| GetUnreadCount | notifications.view ⚠️ (IDOR) |
| MarkAsRead | notifications.edit (توسيع السجل) |
| MarkAllAsRead | notifications.edit ⚠️ (IDOR) |
| Delete | needs-new-key.delete (أو سياسة Admin) |
| Send | notifications.add (محمي بـAdmin أصلاً) |

**TaskAuditsController** (5 — أضعف تحكم: `[Authorize]` فقط)
| endpoint | المقترح |
|---|---|
| GetAll | tasks.audit.view |
| GetByRequestNumber | tasks.audit.view |
| GetBulk | tasks.audit.view |
| SaveAudit | tasks.audit.edit |
| SaveBulk | tasks.audit.edit |

**ServiceRequestsController** (authorize-only منها)
| endpoint | المقترح |
|---|---|
| GetAll | tasks.view |
| GetSummary | tasks.view |
| GetById | tasks.view |
| GetByNumber | tasks.view |
| Create | tasks.add |
| UpdateStatus | tasks.edit |
| AssignToEmployee | tasks.assign.edit |
| AddComment | tasks.edit |
| GetComments | tasks.view |
| AddAttachment | tasks.edit (نظّف اسم الملف) |
| GetAttachments | tasks.view |
| GetStatistics | tasks.view |
| GetMyAssigned | my_dashboard.view (شخصي) |
| DeleteRequest | tasks.delete |

**UsersController** (authorize-only منها)
| endpoint | المقترح |
|---|---|
| GetById | users.view |
| Update | users.edit |
| ChangePassword | users.edit ⚠️ (لا يفحص العزل؛ أي مصادَق يغيّر كلمة مرور أي id إن عرف الحالية) |

**AgentsController** (authorize-only بلا RequirePermission)
| endpoint | المقترح |
|---|---|
| Delete | accounting.agent_transactions.delete (SuperAdmin حالياً) |
| UpdateTransaction | accounting.agent_transactions.edit ⚠️ (يعيد حساب الأرصدة) |
| DeleteTransaction | accounting.agent_transactions.delete ⚠️ (حذف صلب + عكس رصيد) |

**ZoneMaintenanceFeesController**
| endpoint | المقترح |
|---|---|
| GetAll | accounting.ftth_operators.view |
| Create | accounting.ftth_operators.edit |
| BulkCreate | accounting.ftth_operators.edit |
| Update | accounting.ftth_operators.edit |
| Delete | accounting.ftth_operators.delete |

**OcrController**
| endpoint | المقترح |
|---|---|
| ExtractIdCard | users.add (أو الإبقاء authorize-only) |
| ExtractIdCardBoth | users.add |

### 2-ب: محمي بسياسة خشنة (policy) — يُضاف مفتاح صلاحية للحوكمة الدقيقة

**LeaveController** (10 → hr.leaves): SubmitLeaveRequest·add، GetLeaveRequests·view، GetLeaveRequest·view، CancelLeaveRequest·edit، ApproveLeaveRequest·edit، RejectLeaveRequest·edit، GetLeaveBalances·view، SetLeaveBalance·edit، BulkSetLeaveBalances·edit، GetLeaveSummary·view.

**DepartmentsController** (10 → hr.departments): GetAll·view، Create·add، Update·edit، Delete·delete، CreateTask·edit، UpdateTask·edit، DeleteTask·edit، SeedDefaults·add، GetUserDepartments·view، SetUserDepartments·edit.

**CompanyCentersController** (4 → attendance، يُفضَّل مفتاح مخصّص): GetAll·view، Create·add، Update·edit، Delete·delete.

**WithdrawalRequestController** (8 → accounting.withdrawals): SubmitWithdrawalRequest·add، GetWithdrawalRequests·view، GetMyWithdrawalRequests·view، ApproveWithdrawalRequest·edit، GetMaxWithdrawal·view، PayWithdrawalRequest·edit، RejectWithdrawalRequest·edit، CancelWithdrawalRequest·edit.

**TechnicianTransactionsController** (7 → technicians): GetMyTransactions·view، GetByTechnician·view، GetAllTechnicianDues·view، RecordPayment·edit، UpdateTransaction·edit، DeleteTransaction·edit، RecalculateAllBalances·edit.

**ServiceRequestsController** (policy منها): CreateTask·tasks.add، AssignTask·tasks.assign.edit، UpdateTask·tasks.edit، GetTaskLookupData·tasks.view، GetTaskStaff·tasks.view، GetMyDepartments·my_dashboard.view.

**FtthAccountingController** (policy → accounting.settings.edit): FixJournalEntryDates ⚠️، RecalculateAccountBalances، RetryMissingEntries، FixMissingUserIds، AssignUnknownRecords، FixMissingAccounting، FixOrphanRecords ⚠️ (targetCompanyId من العميل)، FixActivatedByNames.

**CompaniesController** (16): GetAll·superadmin.companies.view، GetById·superadmin.companies.view، Create·superadmin.companies.add، Update·superadmin.companies.edit، RenewSubscription·superadmin.subscriptions.edit، ToggleStatus·superadmin.companies.edit، Delete·superadmin.companies.delete، GetEmployees·hr.employees.view، AddEmployee·hr.employees.add، GetEmployeeById·hr.employees.view، UpdateEmployee·hr.employees.edit، UpdateEmployeePermissions·hr.permissions.edit، UpdateEmployeePermissionsV2·hr.permissions.edit، DeleteEmployee·hr.employees.delete، GetStatistics·superadmin.companies.view، GetExpiringSoon·superadmin.subscriptions.view.

**SuperAdminController** (29، policy:SuperAdmin أصلاً → مفاتيح superadmin.*): Logout، GetCompanyById، CreateCompany، UpdateCompany، ToggleCompanyStatus، RenewSubscription، DeleteCompany، GetFirebaseStatus، GetFirebaseUsers ⚠️(يتجاوز العزل)، UpdateFirebaseUser، SendPushNotification(notifications.add)، DeleteFirebaseUser، RestartVpsService، GetVpsLogs، ExecuteVpsCommand ⚠️، TriggerBackup، GetBackups، GetDatabaseStats، RunDatabaseMaintenance ⚠️، GetAuditLogs، GetAlerts، AcknowledgeAlert، GetSystemSettings، UpdateSystemSettings، SetMaintenanceMode، GetPlans(plans_bundles)، CreatePlan، UpdatePlan، DeletePlan. (المفاتيح: superadmin.companies / superadmin.subscriptions / superadmin.system_health / superadmin.database / superadmin.audit / superadmin.permissions / superadmin.financial / plans_bundles / notifications).

**ServerController** (14، policy:SuperAdminOnly → superadmin.system_health / superadmin): GetServerHealth، GetDiskUsage، GetNetworkStats، GetTopProcesses، GetServiceStatus، RestartApiService ⚠️، GetLogs، GetFirebaseUser، DisableFirebaseUser، EnableFirebaseUser، DeleteFirebaseUser، GetFirebaseStats، ExecuteCommand ⚠️⚠️ (تنفيذ أوامر مع sudo)، GetDashboardSummary.

**DashboardController** (7 → dashboard_project.view): GetStats، GetOrdersChart، GetRevenueChart، GetTopMerchants، GetTopProducts، GetRecentOrders، GetRecentUsers.

**SettingsController** (6 → needs-new-key): GetAll·view، GetByCategory·view، Create·add، Update·edit، BulkUpdate·edit، Delete·delete.

### 2-ج: متجر إلكتروني (needs-new-key) قابل بتوكن مستخدم

- **CustomersController** (5 → store.customers): GetAll·view، GetById·view، Create·add، Update·edit، Delete·delete.
- **OrdersController** (4 → store.orders): GetAll·view، GetById·view، Create·add، UpdateStatus·edit.
- **PaymentsController** (5 → store.payments) ⚠️ مالي: GetAll·view، GetById·view ⚠️(IDOR)، GetByOrder·view ⚠️(IDOR)، InitiatePayment·add، Refund·edit ⚠️.
- **CouponsController** (6 → store.coupons): GetAll·view، GetById·view، Create·add، Update·edit، Delete·delete، ToggleActive·edit.
- **CategoriesController** (3 → store.catalog): Create·add، Update·edit، Delete·delete.
- **ProductsController** (3 → store.products) ⚠️IDOR: Create·add، Update·edit، Delete·delete.
- **MerchantsController** (8 → merchants) ⚠️IDOR: GetAll·view، GetById·view، GetByUserId·view، Create·add، Update·edit ⚠️، Verify·edit، UpdateSubscription·edit، GetStats·view.
- **ReviewsController** (5 → needs-new-key «marketplace/reviews»): Create·add، Update·edit، Delete·delete، Approve·edit، GetPendingReviews·view.
- **CitiesController** (3 → needs-new-key «reference-admin»): Create·add، Update·edit، Delete·delete.
- **CitizenPortalController** (17 → citizen_portal، بوّابة موظفي المواطنين) ⚠️ تضم نقاطاً مالية: GetDashboardStats·view، GetCitizens·view، GetCitizenDetails·view، CreateCitizen·add، UpdateCitizen·edit، GetSubscriptions·view، CreateSubscription·add، ActivateSubscription·edit، CancelSubscription·edit، GetPayments·view ⚠️، RecordPayment·add ⚠️، GetPlans·view، CreatePlan·add، UpdatePlan·edit، GetTickets·view، ReplyToTicket·edit، CloseTicket·edit.

### 2-د: مسار internal-key (خادم-لخادم، X-Api-Key) — حوكمة بالبوّابة لا بصلاحية موظف
لا تُضاف `[RequirePermission]` مباشرة؛ تبقى عبر X-Api-Key وتُنقل عند الحاجة خلف البوّابة بالمفتاح المقترح. (141 نقطة): `InternalDataController` 61، `DatabaseAdminController` 16 (→ superadmin.database، كلها تتجاوز العزل) ⚠️، `CompanyFtthSettingsController` 14 (تكشف ftthPassword) ⚠️، `WhatsAppController` 12 (keep-anonymous)، `EmployeeLocationController` 9 (tracking، بلا عزل شركة)، `SuperAdminController` 7 (AllowAnonymous+ApiKeyOrJwt — تتجاوز العزل) ⚠️، `ZoneStatisticsController` 7 (zones، بلا عزل)، `ReminderController` 5، `IptvSubscribersController` 5 (iptv/iptv.manage)، `SubscriberCacheController` 4 (users)، `FtthAccountingController` RecalculateSyncRevenues 1.

---

## 3) قائمة needs-new-key (مفاتيح سجل جديدة مطلوبة) — ~104 نقطة

| المفتاح المقترح | النطاق | النقاط التقريبية |
|---|---|---|
| `store.customers` | عملاء المتجر | 5 |
| `store.orders` | طلبات المتجر | 4 |
| `store.payments` ⚠️ | دفعات المتجر (مالي) | 5 |
| `store.coupons` | كوبونات | 6 |
| `store.catalog` | تصنيفات | 3 |
| `store.products` | منتجات التاجر | 3 |
| `merchants` | إدارة التجّار | 8 |
| `reviews` (marketplace) | مراجعات المتجر | 5 |
| `citizen_portal` | بوّابة موظفي المواطنين | 17 |
| `reference-admin` (مدن/جغرافيا) | بيانات مرجعية | 3 (Cities) + مرايا InternalData |
| `settings` (إعدادات النظام) | SettingsController | 6 |
| `notifications.delete` (توسيع إجراء) | حذف إشعار | 1 |
| مرايا internal (e-commerce/citizens/ftth-settings) | InternalData 21 + CompanyFtthSettings 13 + Reminder 4 | ~38 |

ملاحظات توسيع السجل: `notifications` يحتاج إجراء `edit`/`delete` (حالياً view/add/send)؛ `salaries` و`collections` و`vouchers` تفتقد إجراء `delete` (حُقنت مؤقتاً كـ`edit` — يُفضَّل إضافة `delete`)؛ `agents` يُفضَّل فصل `add/edit` بدل استخدام `view` لعمليات الكتابة.

---

## 4) keep-anonymous (يجب أن تبقى عامة) — 106 نقطة + مبرّراتها

| المجموعة | النقاط | المبرّر |
|---|---|---|
| مصادقة (Companies/SuperAdmin/Agents Login+Refresh) | 7 | دخول/تحديث توكن قبل المصادقة |
| كتالوج المتجر العام (Products/Categories/Advertisings GET + CitizenStore تصفّح) | ~22 | تصفّح عام قبل الدخول |
| باقات/مدن/إصدارات مرجعية (InternetPlans، Cities GET، AppVersions) | ~10 | بيانات مرجعية عامة + فحص auto-update قبل الدخول |
| خدمة ذاتية للعميل/المواطن (Cart، Wishlist، Addresses، SupportTickets، CitizenSubscriptions، CitizenStore orders، Agents «me») | ~48 | توكن مواطن/عميل/وكيل (CitizenJwt/توكن وكيل) خارج صلاحيات الموظف؛ معزولة بـUserId/MerchantId/CitizenId |
| بنية تحتية (FcmTokens register/unregister) | 2 | تسجيل جهاز للمستخدم الحالي |
| جسر whatsapp-server (WhatsAppController) | 12 | خدمة داخلية machine-to-machine بـX-Api-Key/WebhookSecret |
| ويبهوك/داخلي صريح (FtthAccounting.RecalculateSyncRevenues، InternalData.Ping، ServiceRequests.GetServices، Settings public/by-key) | ~5 | فحوص صحة/كتالوج/إعدادات عامة أو مفتاح داخلي |

**تحذيرات داخل keep-anonymous (قرار صريح مطلوب — تبقى عامة لكنها تكشف بيانات):**
- `UsersController.GetByPhone` ⚠️ — تعداد حسابات (تكشف exists/isActive لأي رقم بلا مصادقة ولا عزل).
- `ZoneMaintenanceFeesController.CheckZone` ⚠️ — تكشف مبلغ أجور الزون بلا مصادقة.
- `PaymentsController.ZainCashCallback` ⚠️ — لا توقيع/تحقق HMAC من زين كاش (محروس بعلَم OFF).

---

## 5) إحصاء التغطية

- **إجمالي مُخرَّط فعلياً:** 848 (من 879؛ الفارق ~31 = متحكّمات المصادقة الثلاثة + ذيل CitizenPortal، كلها anonymous/keep-anonymous).
- **محكوم بـ `[RequirePermission]` حالياً:** **313** → تغطية **36.9%** من الإجمالي.
- **بعد استبعاد keep-anonymous (106):** القابل للحوكمة = 742 ⇒ التغطية الفعلية **42.2%** (313/742).
- **يحتاج إضافة `[RequirePermission]` بتوكن موظف:** **~301** = 150 `authorize-only` (بلا أي بوّابة عدا `[Authorize]` — الفجوة الحقيقية) + 151 `policy` (محمي خشناً، يُضاف مفتاح للحوكمة الدقيقة).
- **مسار internal-key (حوكمة بالبوّابة):** 141 (128 بمفاتيح مقترحة + 13 keep-anonymous).
- **needs-new-key:** ~104 نقطة عبر ~12 مفتاح/نطاق جديد.

> خلاصة: نحو **ثلثي** الـendpoints القابلة للحوكمة ما تزال خارج `[RequirePermission]`، وأخطرها فئة الـ150 `authorize-only`.

---

## 6) الأولويات: أخطر الـendpoints غير المحكومة (مالية/حذف/كتابة/تتجاوز العزل)

**P0 — عبور عزل المستأجر (الخطر الأول):**
1. `ISPSubscribersController` (الثماني كلها) — قراءة/إنشاء/تعديل/حذف مشتركي **كل الشركات**؛ CompanyId من الجسم لا التوكن.
2. `SubscriptionLogsController.GetAll/GetStats/GetConnections/Create/Delete/RepairAccounting` — بلا فلتر CompanyId + قيود محاسبية تلقائية.
3. `FtthAccountingController.LogWithAccounting` و`FixOrphanRecords` — يختمان/ينقلان CompanyId من **العميل** ⇒ قيود عبر الشركات.
4. `DatabaseAdminController` كامل + `SuperAdminController` (الـ7 internal-key) + `ZoneStatisticsController` + `EmployeeLocationController` — تتجاوز العزل عبر X-Api-Key (تأمين المفتاح/البوّابة أولوية مستقلة).

**P0 — كشف اعتماد حسّاس:**
5. `FtthAccountingController.GetFtthCredentials` و`InternalDataController.GetCompanyEmployeeById` و`CompanyFtthSettingsController.GetSettings` — تُعيد كلمات مرور/اعتماد FTTH.

**P1 — مالي/حذف صلب:**
6. `SubscriptionLogsController.RepairAccounting` و`Delete` — عكس/إعادة كل القيود وعكس أرصدة.
7. `AgentsController.DeleteTransaction/UpdateTransaction` — حذف صلب + عكس رصيد.
8. `PaymentsController.Refund/InitiatePayment/GetById/GetByOrder` — استرداد + IDOR على الدفعات.
9. `ServerController.ExecuteCommand` و`SuperAdminController.ExecuteVpsCommand/RunDatabaseMaintenance` — تنفيذ أوامر/صيانة قاعدة.

**P1 — ثغرة صلاحيات مباشرة:**
10. `AnnouncementsController.Create/Update/Delete` — **أي مستخدم مصادَق** يُنشئ/يحذف إعلاناً على مستوى الشركة (بلا حارس دور).
11. `UsersController.ChangePassword` — بلا فحص عزل؛ تغيير كلمة مرور أي id عند معرفة الحالية.
12. `TaskAuditsController` (SaveAudit/SaveBulk) — أضعف تحكم (`[Authorize]` فقط) على كتابة تدقيق المهام.

**P2 — IDOR في المتجر/الإشعارات:**
13. `ProductsController`/`MerchantsController` Update/Delete — بلا تحقق ملكية التاجر.
14. `NotificationsController.GetByUser/GetUnreadCount/MarkAllAsRead` — userId من العميل.

**مراجعة قرار (keep-anonymous كاشفة):** `UsersController.GetByPhone` (تعداد حسابات)، `ZoneMaintenanceFees.CheckZone` (كشف أجور)، `Payments.ZainCashCallback` (بلا HMAC).

---

**تنبيهات تنفيذ (قواعد الصدارة):** أي تطبيق لهذه الصلاحيات يمر على `security-auditor-agent`؛ فعل العلَم `Authz:FailClosed` deny-by-default يحتاج تزامناً مع ترخيص المفاتيح عبر permissions-v2 لتجنّب إقفال شاشات؛ وختم `CompanyId` من التوكن عند الكتابة يجب أن يسبق أو يرافق إضافة `[RequirePermission]` في نقاط P0 (العزل أخطر من غياب المفتاح). لم يُعدَّل أي كود في هذه المهمة (تقرير قراءة فقط).