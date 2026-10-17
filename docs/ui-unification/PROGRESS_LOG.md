# سجل ترحيل الواجهات

سطر لكل شاشة منتهية: التاريخ · الملف · ما تغيّر · نتيجة analyze · العروض المختبرة.

| التاريخ | الملف | ما تغيّر | analyze | العروض |
|---|---|---|---|---|
| 2026-10-16 | lib/frontend/ (جديد) | إنشاء نظام التصميم الموحّد والتجاوب والمعرض | لم يُشغَّل بعد | — |
| 2026-10-16 | lib/frontend/ (الموجة 1) | تشغيل flutter analyze lib/frontend عبر mobile-agent؛ لا تعديلات لزمت | No issues found! | معلّق: مراجعة المعرض بصرياً من المستخدم |
| 2026-10-16 | widgets/permissions_gate.dart (م2) | SdPage+SdCard+SdEmptyState+SdButton؛ حذف ألوان يدوية؛ المنطق/الأذونات/التنقّل بلا مساس | No issues found! | معلّق: مراجعة بصرية |
| 2026-10-16 | pages/login/premium_login_page.dart (م2) | SdTheme.scope+SdCard موحّدة+SdButton/SdStatusChip؛ حذف google_fonts والتدرّجات اليدوية؛ توحيد التخطيطات الثلاثة في بطاقة واحدة (حُذف hero المنقسم)؛ المصادقة/API/التنقّل بلا مساس | No issues found! | معلّق: مراجعة بصرية |
| 2026-10-16 | pages/home_page.dart (م2) | SdAppBar+بطاقة التعليمات+3 SdStatPedestal+SdFilterChips+SdTileGrid/SdMenuTile+رفّ جانبي مجسّم؛ خلفية سادة وإزالة الزخارف الباهتة؛ الشريط العائم والصلاحيات والعدّادات الحيّة والتنقّل بلا مساس؛ دوال/رسّامون قدامى باقون خاملين | No issues found! | معلّق: مراجعة بصرية |

| 2026-10-16 | ftth/core/home_page.dart (م3-E) | قشرة: SdAppBar+SdAppBarAction+خلفية سادة بدل Aurora؛ الجسم legacy؛ تحسينات الأداء محفوظة (لا تحريك مُعاد) | analyze نظيف | معلّق: مراجعة بصرية |
| 2026-10-16 | ftth/reports/agents_details_page.dart (م3-E) | قشرة: SdTheme.scope+SdAppBar؛ نقل بيانات المستخدم إلى subtitle؛ الجسم legacy | No issues found! | معلّق: مراجعة بصرية |
| 2026-10-16 | ftth/requests/customer_onboarding_page.dart (م3-E) | ترحيل أعمق: SdTheme.scope+استبدال كل hex محلي بألوان sd؛ الخطوات/OCR/OTP/التوقيع بلا مساس | No issues found! | معلّق: مراجعة بصرية |
| 2026-10-16 | ftth/transactions/transactions_page.dart (م3-E) | قشرة: SdAppBar+badge للفلاتر+خلفية سادة؛ الجسم legacy | No issues found! | معلّق: مراجعة بصرية |

| 2026-10-16 | ftth/subscriptions/expiring_soon_page.dart (م3-C) | ترحيل واجهة كامل: SdPage+SdAppBar+SdCard+SdStatusChip+SdEmptyState؛ حدّ خط 11.5؛ الجلب/التصدير/pagination بلا مساس | No issues found! | معلّق: مراجعة بصرية |
| 2026-10-16 | ftth/subscriptions/subscription_details_page.dart (م3-C) | قشرة+حالات (13k سطر)؛ SdAppBar للشاشات الثلاث+SdEmptyState؛ منطق التجديد/الباقات/bundles بلا مساس؛ الجسم العميق legacy | No issues found! | معلّق: مراجعة بصرية |
| 2026-10-16 | ftth/subscriptions/subscriptions_page.dart (م3-C) | قشرة+بطاقات+حالات بألوان sd؛ أبقى AppBar قديم (bottom فلاتر)؛ التصدير المحمي/الإرسال الجماعي بلا مساس | No issues found! | معلّق: مراجعة بصرية |

| 2026-10-16 | ftth/users/quick_search_users_page.dart (م3-B) | SdPage+SdAppBar+SdRaised+SdEmptyState؛ debounce/pagination/التنقّل بلا مساس | No issues found! | معلّق: مراجعة بصرية |
| 2026-10-16 | ftth/users/user_details_page.dart (م3-B) | قشرة SdAppBar + EditDevicePage كامل (5855 سطر)؛ منطق items[]/pill محفوظ؛ جسم البطاقات legacy (دَين) | No issues found! | معلّق: مراجعة بصرية |
| 2026-10-16 | ftth/users/users_page.dart (م3-B) | SdAppBar+SdAppBarAction؛ نقل شريط كلمة مرور التصدير من bottom للمحتوى؛ التصدير/الصلاحيات/الترقيم بلا مساس | No issues found! | معلّق: مراجعة بصرية |
| 2026-10-16 | pages/search_users_page.dart (م3-B) | SdPage+SdAppBar+SdButton؛ المدقّقات/البحث بلا مساس | No issues found! | معلّق: مراجعة بصرية |

| 2026-10-16 | ftth/tickets/create_ticket_page.dart (م3-A) | SdPage+SdAppBar+SdFilterChips+SdButton (نبرة comms)؛ الرفع/الإرسال/401 بلا مساس | No issues found! | معلّق: مراجعة بصرية |
| 2026-10-16 | ftth/tickets/tktat_details_page.dart (م3-A) | SdPage+SdAppBar+SdCard+SLA SdStatusChip؛ SLA الحيّ/التعليقات بلا مساس؛ أزرار التحميل بلا spinner (تعطيل+نص) | No issues found! | معلّق: مراجعة بصرية |
| 2026-10-16 | ftth/tickets/tktats_page.dart (م3-A) | SdPage+SdAppBar+SdFilterChips+SdRaised+SdEmptyState؛ fetch/401/FCM/الإخفاء المحلي بلا مساس؛ 3 حوارات ثانوية legacy | No issues found! | معلّق: مراجعة بصرية |

| 2026-10-16 | task/add_task_api_dialog.dart (م3-D) | حوار موحّد (SdCard/SdButton/SdStatusChip)؛ مسار الهاتف Scaffold+SdAppBar؛ التحقّق/الصرف/واتساب بلا مساس | No issues found! | معلّق: مراجعة بصرية |
| 2026-10-16 | task/follow_up_page.dart (م3-D) | SdPage+SdAppBar+SdCard+SdEmptyState؛ رفع الخطوط ≥11.5؛ التدقيق/النجوم بلا مساس | No issues found! | معلّق: مراجعة بصرية |
| 2026-10-16 | task/home_page_tasks.dart (م3-D) | شلّ موحّد+كنس ألوان شامل (3573 سطر، 240 موضع)؛ بطاقات/أزرار اللوحة الداخلية موحّدة-الرموز لا SdCard/SdButton (دَين) | No issues found! | معلّق: مراجعة بصرية |
| 2026-10-16 | task/task_list_screen.dart (م3-D) | ألوان المؤشّر/SnackBar → SdColors؛ لا منطق ممسوس | No issues found! | معلّق: مراجعة بصرية |

| 2026-10-16 | pages/chat/chat_conversation_page.dart (م4-F) | قشرة (2985 سطر)؛ شريط نيلي+خلفية ground+حقول sd؛ شريط مخصّص مُبقى للتفاعلات؛ الفقاعات/stream/الإرسال بلا مساس | No issues found! | معلّق: مراجعة بصرية |
| 2026-10-16 | pages/chat/chat_rooms_page.dart (م4-F) | SdPage+SdAppBar؛ embeddedMode محفوظ؛ ألوان النوع/الشارات → sd | No issues found! | معلّق: مراجعة بصرية |
| 2026-10-16 | pages/whatsapp_chat_page.dart (م4-F) | قشرة؛ شريط نيلي + هوية واتساب للأفاتار فقط + زر إرسال comms؛ الفقاعات/الإرسال بلا مساس | No issues found! | معلّق: مراجعة بصرية |
| 2026-10-16 | pages/whatsapp_conversations_page.dart (م4-F) | SdPage+SdAppBar؛ الفلترة/التنظيف/العدّاد بلا مساس | No issues found! | معلّق: مراجعة بصرية |
| 2026-10-16 | lib/frontend/tokens/sd_colors.dart (م4-F) | إضافة SdColors.whatsappEdge=0xFF128C7E (لون ناقص لحافّة شعار واتساب) — مسموح | No issues found! | — |
| 2026-10-16 | pages/attendance_page.dart (م4-G) | SdPage+SdAppBar+SdStatPedestal؛ منطق البصمة/الموقع/السيلفي بلا مساس؛ أُزيلت AnimationControllers ميتة؛ شاشة الكاميرا داكنة عمداً | No issues found! | معلّق: مراجعة بصرية |
| 2026-10-16 | pages/hr_hub_page.dart (م4-G) | SdPage+SdAppBar+SdTileGrid/SdMenuTile (admin)؛ التنقّل/العدّادات بلا مساس | No issues found! | معلّق: مراجعة بصرية |
| 2026-10-16 | pages/my_dashboard_page.dart (م4-G) | شلّ موحّد+توجيه ثوابت الألوان لـ SdColors (3428 سطر)؛ الاستدعاءات/الحوارات بلا مساس؛ بنى عميقة GoogleFonts/hex (دَين) | No issues found! | معلّق: مراجعة بصرية |
| 2026-10-16 | pages/users_page_vps.dart (م4-G) | شلّ+توجيه ثوابت لـ SdColors (2203 سطر)؛ canAdd/useInternalKey/الصلاحيات بلا مساس؛ بطاقات/حوارات داخلية دَين | No issues found! | معلّق: مراجعة بصرية |
| 2026-10-16 | pages/announcements/announcements_page.dart (م4-H) | comms؛ SdPage+SdAppBar+SdRaised+SdStatusChip+SdEmptyState؛ الخدمات/الصلاحيات/الاستهداف بلا مساس | No issues found! | معلّق: مراجعة بصرية |
| 2026-10-16 | pages/kml_zones_map_page.dart (م4-H) | ⏸️ لم يُنفَّذ — تضارب: خريطة غامرة داكنة ملء الشاشة × نظام sd فاتح؛ يحتاج قرار تصميم؛ تُركت سليمة | baseline نظيف | بانتظار قرار صاحب المشروع |

| 2026-10-16 | accounting/accounting_dashboard_page.dart (م5-I) | قشرة (SdPage+SdAppBar)؛ العملة/البطاقات/الدرج بلا مساس؛ AccountingTheme غير مستورد | No issues found! | معلّق: مراجعة بصرية |
| 2026-10-16 | accounting/chart_of_accounts_page.dart (م5-I) | قشرة؛ البحث نُقل لجسم الصفحة؛ AccountingTheme سليم | No issues found! | معلّق: مراجعة بصرية |
| 2026-10-16 | accounting/journal_entries_page.dart (م5-I) | قشرة؛ عمليات جماعية/ترحيل/صلاحيات بلا مساس؛ AccountingTheme سليم | No issues found! | معلّق: مراجعة بصرية |
| 2026-10-16 | accounting/compound_journal_entry_page.dart (م5-I) | قشرة (2993 سطر)؛ التوازن/الحفظ/الترحيل بلا مساس؛ أزرار الحفظ → SdAppBarAction (ملاحظة ui-ux) | No issues found! | معلّق: مراجعة بصرية |
| 2026-10-16 | accounting/trial_balance_page.dart (م5-I) | قشرة كاملة نظيفة؛ الإجماليات/التوازن/التصدير بلا مساس | No issues found! | معلّق: مراجعة بصرية |

| 2026-10-16 | accounting/client_accounts..withdrawal_requests (م5-J ×5) | قشرة (Scaffold+SdColors.ground+SdAppBar+SdEmptyState)؛ كل المحتوى المالي/AccountingTheme بلا مساس | No issues found! | معلّق: مراجعة بصرية |
| 2026-10-16 | accounting/operator_transactions+linking+funds_overview (م5-L ×3) | مُرحَّلة (SdPage/Scaffold+SdAppBar+SdEmptyState)؛ الجداول/الأرصدة/ترميز الألوان بلا مساس | No issues found! | معلّق: مراجعة بصرية |
| 2026-10-16 | accounting/ftth_operators_dashboard + settlement_reports (م5-L) | ⏸️ مؤجّلتان: مبنيّتان على AccountingTheme + شريط تبويبات/فلتر؛ تحتاجان قراراً | baseline نظيف | بانتظار قرار |

| 2026-10-16 | accounting/expenses..employee_adjustments (م5-K ×6) | قشرة (SdTheme.scope+Scaffold ground+SdAppBar+SdEmptyState/SdFilterChips)؛ كل الأرقام/الصيغ/AccountingTheme بلا مساس؛ حوارات+خلايا رواتب legacy (دَين) | No issues found! | معلّق: مراجعة بصرية |

| 2026-10-16 | accounting/activation_profitability..year_comparison (م5-N ×5) | قشرة (Scaffold ground+SdAppBar+SdEmptyState)؛ المخططات/الرسّامون/القيم/النسب بلا مساس؛ ألوان رسوم المقارنة → sd دلالية (قابل للعكس)؛ AccountingTheme سليم | No issues found! | معلّق: مراجعة بصرية |

| 2026-10-16 | accounting/balance_sheet..budget (م5-M ×5) | قشرة (SdPage/Scaffold+SdAppBar)؛ شريط الحالة/التاريخ منقول للـbody؛ الجداول/النسب/التصدير/AccountingTheme بلا مساس | No issues found! | معلّق: مراجعة بصرية |

| 2026-10-16 | accounting/audit_trail..zone_maintenance_fees (م5-O ×5) | مُرحَّل (SdAppBar+SdFilterChips)؛ منطق إقفال الفترات محفوظ حرفياً؛ الأرقام/الصيغ بلا مساس | No issues found! | معلّق: مراجعة بصرية |
| 2026-10-16 | ⚠️ ملاحظة أمنية قديمة (ليست من الترحيل) | zone_maintenance_fees_page: X-Api-Key مضمّن في الكود داخل _fetchZoneNames — موجود أصلاً؛ يستحق مراجعة security-auditor لاحقاً | — | — |

| 2026-10-16 | ftth/requests/customer_hub_page.dart (م6) | ترحيل كامل: SdPage+SdAppBar+SdMenuTile (field)؛ التنقّل/التوكن بلا مساس | No issues found! | معلّق: مراجعة بصرية |
| 2026-10-16 | ftth/subscriptions/connections_list_page.dart (م6) | قشرة+حالات: SdTheme.scope+SdAppBar+SdAppBarAction+SdEmptyState؛ منطق التسديد/الفلاتر/الأرقام بلا مساس؛ جسم البطاقات/الفلاتر legacy (دَين) | No issues found! | معلّق: مراجعة بصرية |
| 2026-10-16 | ftth/tasks/ftth_tasks_page.dart (م6) | ترحيل جسم: SdAppBar+SdFilterChips(الحالة)+SdRaised+SdStatusChip+SdEmptyState؛ حدّ خط 11.5؛ الجلب/الفلاتر/pagination بلا مساس | No issues found! | معلّق: مراجعة بصرية |
| 2026-10-16 | ftth/tasks/ftth_connect_form.dart (م6) | ترحيل جسم: SdAppBar+SdCard+SdInfoRow+SdButton؛ حدّ خط 11.5؛ التحقّق/connectCustomer/dropdowns بلا مساس | No issues found! | معلّق: مراجعة بصرية |
| 2026-10-16 | ftth/tasks/customer_search_connect_page.dart (م6) | ترحيل جسم (ويزارد 4 خطوات): SdAppBar+SdCard+SdButton+مؤشّر خطوات/حقول sd؛ حدّ خط 11.5؛ البحث/التوصيل/الحفظ المحلي/حوار المهمة بلا مساس | No issues found! | معلّق: مراجعة بصرية |
| 2026-10-16 | ftth/tickets/customer_tickets_page.dart (م6) | ترحيل كامل: SdAppBar+SdRaised+SdStatusChip+SdEmptyState؛ ألوان الحالة→SdStatus؛ الجلب/401/البحث بلا مساس | No issues found! | معلّق: مراجعة بصرية |
| 2026-10-16 | ftth/reports/zones_page.dart (م6) | قشرة+قائمة+حالات: SdAppBar+SdAppBarAction+SdRaised+SdEmptyState؛ حذف smart_text_color؛ التصدير VPS/الجلب بلا مساس؛ حوارات التفاصيل legacy (دَين) | No issues found! | معلّق: مراجعة بصرية |
| 2026-10-16 | ftth/reports/profits_page.dart (م6) | قشرة فقط (3363 سطر): SdAppBar+خلفية ground+حالة تحميل sd؛ **كل** منطق/أرقام الأرباح وجدول الفئات الملوّن بلا أي مساس (دَين مقصود) | No issues found! | معلّق: مراجعة بصرية |
| 2026-10-16 | ftth/reports/audit_log_page.dart (م6) | قشرة: SdAppBar+SdEmptyState+خلفية ground+شريط ملخّص/فارغ بألوان sd؛ بطاقات الأحداث بألوانها الدلالية + الأنيميشن legacy (دَين) | No issues found! | معلّق: مراجعة بصرية |
| 2026-10-16 | ftth/transactions/daily_settlement_page.dart (م6) | قشرة: SdTheme.scope+خلفية ground+شريط نيلي؛ منطق التسديدات/المقارنة/الأرقام بلا مساس؛ جسم التبويبات legacy (دَين). ⚠️ _vpsApiKey مضمّن في الكود أصلاً — يستحق مراجعة security-auditor | No issues found! | معلّق: مراجعة بصرية |
| 2026-10-16 | ftth/transactions/account_records_page.dart (م6) | قشرة دنيا (4314 سطر): خلفية ground+شريط نيلي؛ كل الجداول/الأرقام/الفلاتر بلا مساس (دَين كبير) | No issues found! | معلّق: مراجعة بصرية |
| 2026-10-16 | ftth/users/users_data_page.dart (م6 اختياري) | قشرة: SdAppBar+خلفية ground؛ Cloudflare/الجلب بلا مساس؛ جسم legacy (دَين) | No issues found! | معلّق: مراجعة بصرية |
| 2026-10-16 | ftth/users/user_records_page.dart (م6 اختياري) | قشرة: SdAppBar+خلفية ground؛ الإحصائيات/الفلاتر/الأرقام بلا مساس؛ جسم legacy (دَين) | No issues found! | معلّق: مراجعة بصرية |
| 2026-10-16 | ftth/auth/login_page.dart (م6) | ⏸️ لم يُرحَّل — يعتمد AnimationControllers + خلفية مرسومة (fiber-optic)؛ الترحيل الكامل محفوف بكسر سلوك الدخول؛ يحتاج قراراً | baseline نظيف | — |

## 🔧 تصغير مركزي للأحجام (2026-10-16، بطلب المستخدم: بلاطات/أيقونات أصغر وتمرير أقل)
يسري على كل الشاشات المُرحَّلة (تغيير أحجام/حشو فقط، بلا منطق). مؤكّد بالتشغيل: 0 أخطاء تخطيط/تجاوز.
- **sd_responsive.dart**: cubeSize 44/50/52→32/36/40 · gridGap 12/16/18→10/12/14 · sectionGap 18/22/28→12/14/18 · gutter 14/20/24→12/16/20.
- **sd_menu_tile.dart**: minHeight أفقي 84→66 (هاتف 72→58)، عمودي 120→96 · حشو أقل · عنوان أفقي 16→14.5، عمودي 14→12.5 · minTileWidth 250→210.
- **sd_stat_pedestal.dart**: عمود سطح المكتب 96×120→76×96 (هاتف 64×80→54×70) · الرقم 36/28→25/22 · إصلاح تجاوز 1px (FittedBox+maxLines).

## 🧩 ترحيل الأجسام الكامل لنمط sd (2026-10-16، بطلب المستخدم: «تغيّر الشريط فقط»)
ترحيل **جسم** الشاشات (لا القشرة فقط) إلى sd المجسّم — واجهة فقط، analyze نظيف، بلا مساس أرقام/منطق/صلاحيات. (قرار المستخدم: الأجسام غير المحاسبية نعم؛ المحاسبة تبقى على AccountingTheme.)
- `task/home_page_tasks.dart` — بطاقات إحصائية → SdRaised، جدول الفنيين بنمط sd، أزرار سفلية مجسّمة.
- `ftth/core/home_page.dart` — بطاقات إحصائية/محفظة → SdRaised، أزرار سريعة، بحث/شريط جانبي/درج بألوان sd (أداء محفوظ).
- `ftth/users/user_details_page.dart` — بطاقات → SdCard، أزرار → SdButton، منتقي الاشتراكات المتعددة بنبرات sd (منطقه محفوظ).
- `ftth/transactions/transactions_page.dart` — بطاقات الملخّص/المعاملات → SdRaised، حوارات/شريط سفلي → sd.
- `pages/my_dashboard_page.dart` + `pages/users_page_vps.dart` — بطاقات/شرائح/أزرار/حوارات → sd؛ حذف GoogleFonts.
- **مؤجّل**: `subscription_details` (13k، جسم عميق) + شاشات المحادثة (فقاعاتها صحيحة أصلاً).

## 🔧 إحكام الرئيسية بلا تمرير (2026-10-16، بطلب المستخدم)
- حذف شريط الفلاتر (كل الأقسام تظهر دائماً بالصلاحيات).
- بطاقة التعليمات قابلة للطيّ، مطوية افتراضياً (شريط رفيع) — نقر الجسم يطوي/يوسّع، وزر «عرض التعليمات» يفتح النافذة.
- شبكة الرئيسية: maxColumns 6، minTileWidth 185 (عند مواضع استدعاء الرئيسية فقط).
- SdStatPedestal (عام): عمود سطح المكتب 96×76→74×68 (هاتف 70×54→62×52)، حشو أقل.
- sd_menu_tile minHeight أفقي 66→62 (عام). فجوات الرئيسية الرأسية قُلّصت (أقسام 18→12 محلياً).
- النتيجة: ارتفاع محتوى ≈610px < 800px ⇒ يتّسع بلا تمرير على 1440×900. مؤكّد run = 0 أخطاء تخطيط.

## 🔴 انحدار تشغيلي اكتُشف وأُصلح (2026-10-16)
- **العطل**: التطبيق يتوقّف على «جاري التحميل...» بعد الدخول. السبب: في `pages/home_page.dart` صفّ العدّادات `_buildCountersRow()` (سطح المكتب) كان `Row(crossAxisAlignment: stretch)` داخل `SingleChildScrollView` عمودي ⇒ `BoxConstraints forces an infinite height` يتكرّر كل إطار فلا يُرسم الجسم.
- **الإصلاح**: لفّ الصفّ بـ `IntrinsicHeight` (تخطيط بحت، بلا مساس منطق). analyze + build release نجحا.
- **تحقّق حيّ (flutter run)**: الخطأ اللانهائي = **0**، التطبيق تجاوز الدخول ورسم الرئيسية (جلب الإحصائيات/الصلاحيات/العدّادات نجح). ✅ مؤكّد.
- متبقٍّ تجميلي غير حاجب: `RenderFlex overflowed by 1.00px on the bottom` (مكوّن sd داخلي — SdStatPedestal/SdMenuTile) — يُعالَج في فحص الدخان.
- **الدرس الحاسم**: `flutter analyze` **لا يكشف أخطاء التخطيط وقت التشغيل** (الارتفاع اللانهائي). الاعتماد على analyze وحده غير كافٍ ⇒ **كل الشاشات المُرحَّلة تحتاج تشغيلاً فعلياً (build+run) للتحقّق**، لا analyze فقط. يُضاف فحص تشغيل دخان لبقية الشاشات.

## اعتماد الموجة 5 (2026-10-16)
- **مراجعة مالية مستقلّة + تحقّق git**: اعتماد — لا P0/P1/P2. المنطق المالي محقّق سطراً بسطر (توازن القيد _isBalanced، الترحيل postJournalEntry، الإقفال _togglePeriod، فحوص الفترة، الصلاحيات canEdit/canAdd، معادلة الميزانية، النسب المحمية من القسمة على صفر). AccountingTheme لم يُعدَّل. 65 ملف .dart، لا main.dart/pubspec.
- P3 تجميلي (تنظيف لاحق): withOpacity→withValues + hex داخل محتوى compound mobile (موروث).

## ملاحظات معمارية على نظام sd (من الموجة 5)

- **SdPage يلفّ المحتوى بـ Center** (يفكّ قيد الارتفاع) ⇒ يكسر جداول Expanded كاملة الارتفاع؛ البديل المعتمد للشاشات ذات الجداول الطويلة: `Scaffold + SdColors.ground + SdAppBar` (بلا SdPage). يُقترح إضافة وضع `SdPage(stretch/fill)` لاحقاً.
- **شاشات AccountingTheme-native**: بعض شاشات المحاسبة مبنية كلياً على AccountingTheme (خلفية/بطاقات/شريط)؛ تحت حارس «لا تلمس AccountingTheme» لا يمكن توحيد هيكلها ⇒ تُؤجَّل وتُجمَّع لقرار واحد.

## بنود P3 تجميلية (مراجعة الموجة 4 — اختيارية، موجة تنظيف)

- whatsapp_chat_page.dart:391/446/572 — استبدال `Color(0xFF25D366)` بـ `SdColors.whatsapp` (توكن موجود بنفس القيمة).
- users_page_vps.dart:1186/1188 — استبدال `0xFFFFF3E0`/`0xFFFFE0B2` بـ `SdColors.warningTint`/`warningTintEdge`.
- دوال خاملة قديمة (ليست من هذه الموجة): attendance `_getCenterLocation`/`_isWithinAllowedDistance`، hr_hub `_parsePermissions`.
- استكمال كنس hex البنى العميقة: my_dashboard (50) · users_page_vps (19) · chat_conversation (11) — دَين مُسجَّل.

## تحسينات مطلوبة على نظام التصميم sd (من الموجة 3)

- **SdAppBar يحتاج دعم `bottom` اختياري** (PreferredSize) ليحمل شريط فلاتر/تبويبات تحته — ظهر في subscriptions_page/users_page؛ قرار لمالك lib/frontend عبر project-manager.
- **SdButton يحتاج حالة تحميل (spinner/isLoading)** — حالياً الأزرار أثناء التنفيذ تُعطَّل وتغيّر النص بلا مؤشّر دوّار (ظهر في tktat_details)؛ تحسين على نظام التصميم. (PreferredSize) ليحمل شريط فلاتر/تبويبات تحته — ظهر في subscriptions_page؛ قرار لمالك lib/frontend عبر project-manager.

## دَين متبقٍّ من الموجة 2 (مراجعة code-reviewer-agent 2026-10-16 — لا أثر وظيفي، مؤجّل لموجة تنظيف)

- **home_page.dart**: الترحيل جزئي (القشرة + الأقسام العلوية بـ sd)؛ الدرج ولوحة الإشعارات وبعض بطاقات الجسم ما زالت legacy (ألوان hex يدوية + context.responsive + withOpacity المهجور). كود خامل: `_buildFiberBeam`/`_buildPhoton`/`_fiberColor` (لا يُنتج تحذيراً بسبب unused_element: ignore).
- **premium_login_page.dart**: خطّان بحجم 10/11 (أحرف أفاتار الحسابات المحفوظة) تحت حدّ 11.5؛ زر حذف الحساب المحفوظ هدف لمسه قد يقل عن 48.
- جرد أمني: لا P0/P1، لا مخالفة نطاق، لا مساس بالباكند/sas. النطاق مؤكّد: 3 ملفات فقط تغيّرت.

## الموجة 7 — مدير النظام والإعدادات (2026-10-16)

مُرحَّل بالكامل (SdPage/SdAppBar/SdCard/SdButton/SdInfoRow/SdFilterChips/SdEmptyState):
- `settings_page.dart` · `settings_text_scale_page.dart` · `printer_settings_page.dart` — نماذج/إعدادات صغيرة؛ المنطق (AppTextScale/الطابعة/رقم رسول) بلا مساس.
- `super_admin/edit_company_page.dart` — ترحيل أعمق (استبدال EnergyDashboardTheme ببطاقات sd + SdButton)؛ **put/useInternalKey/العزل بلا أي مساس**.
- `super_admin/tenant_features_page.dart` — SdTheme.scope + شريط نيلي + TabBar موحّد + SdButton/SdCard (استبدال GoogleFonts/EnergyDashboardTheme)؛ **مفاتيح الميزات + حفظ Firestore بلا أي مساس**.

شلّ (SdTheme.scope/SdAppBar + خلفية SdColors.ground + كنس ألوان؛ الجسم العميق legacy — دَين):
- `super_admin/add_company_page.dart` (أُبقي Stepper) · `super_admin/unified_companies_page.dart` · `super_admin/company_details_page.dart` · `super_admin/agents_management_page.dart` (فروع build الثلاثة) · `super_admin/sadara_portal_page.dart` · `super_admin/vps_data_manager_page.dart` · `super_admin/permissions_management_v2_page.dart` · `settings/ftth_sync_settings_page.dart` · `company_settings_page.dart` (ثوابت الثيم الداخلية → sd).
- **كلها شاشات SuperAdmin/DatabaseAdmin حسّاسة: لم يُمَسّ أي منطق تجاوز عزل / إدارة شركات / صلاحيات / مصادقة / استدعاء API / تنقّل — واجهة فقط (ألوان/قشرة).**

استثناء:
- `super_admin/super_admin_dashboard.dart` — ⛔ **غير مُرحَّل**: تصميم Energy Dashboard غامر داكن (تدرّج أسود + نيون + Glassmorphism) يتعارض مع نظام sd الفاتح، تماماً كشاشة `kml_zones_map_page` المستثناة؛ يحتاج قرار صاحب المشروع (لوحة sd داكنة أو إبقاؤه). لم يُلمس.

ملاحظات على نظام التصميم (مكرّرة من موجات سابقة، تظهر هنا بقوة):
- شاشات AccountingTheme/EnergyDashboardTheme الفاتحة (agents_management/sadara_portal/unified_companies/company_details/vps_data_manager) تبقى بجسمها الأصلي تحت حارس «لا تلمس الثيمات المشتركة»؛ التوحيد الكامل يحتاج قرار توجيه AccountingTheme/EnergyDashboardTheme → sd.
- SdAppBar ما زال لا يدعم `bottom` (TabBar)؛ لذا ftth_sync/permissions_v2/tenant_features أبقت AppBar مُنسّق يدوياً بلون sd بدل SdAppBar.

analyze: كل الملفات الأربعة عشر المُرحَّلة = No issues found (مجمّعة).

## 2026-10-17 — مشهد تسجيل الدخول ثلاثي الأبعاد التفاعلي
- استُبدل `lib/frontend/components/sd_login_scene.dart` بمحرّك 3D برمجي (منظور + إضاءة + ترتيب عمق) — نفس الواجهة `SdLoginScene(maxWidth:)`.
- تفاعل: ميلان مع الفأرة، سحب للتدوير، عجلة/قرص للتكبير، ضغط على مبنى = دخول (سقف يرتفع، جدران زجاجية، طوابق ونقاط مشتركين) + بطاقة تفاصيل، Esc للعودة.
- نسخة احتياطية من الملف السابق: `_backups/login-scene-2026-10-17/`.
- النموذج التجريبي: `design/login/login_3d_interactive.html`.
- مطلوب: `flutter analyze lib/frontend/components/sd_login_scene.dart` ثم تجربة على ويندوز وأندرويد.

## 2026-10-17 — إطار أسود موحّد
- قرار المالك: كل الحقول والبطاقات والأزرار بإطار أسود.
- الرموز: `SdColors.outline` (#000000) و `SdOutline` (عرض 1.5، تركيز 2.2) في `sd_metrics.dart`.
- مطبّق في: SdTheme (حقول، قوائم منسدلة، بطاقات، أزرار، شرائح، مربعات اختيار، مفاتيح)، AppTheme العام، SdRaised/SdButton/SdFilterChips، SdCard، SdMenuTile، SdSegmented، SdToggle، أزرار الشريط العلوي، وصفحة تسجيل الدخول.
- قاعدة للترحيل: أي Container يمثّل حقلاً/بطاقة/زراً يضيف `border: SdOutline.all`.
- نسخة احتياطية: `_backups/black-outline-2026-10-17/`.

## 2026-10-17 — القائمة الجانبية الموحّدة (SdSideNav)
- مكوّن جديد `lib/frontend/components/sd_side_nav.dart`: SdNavItem/SdNavSection/SdSideNav/SdNavShell. هاتف=درج، آيباد=شريط مطوي 80، سطح مكتب=لوحة 272 قابلة للطي (حالة مشتركة).
- SdAppBar: زر قائمة موحّد تلقائي عند وجود درج (مكان الرجوع في الصفحة الجذرية، أو آخر الإجراءات إن أمكن الرجوع).
- مُرحَّل: pages/home_page، ftth/core/home_page، super_admin_dashboard (+ بوابة المواطن)، agents_management، accounting_dashboard، task/home_page_tasks، local_storage (endDrawer)، user_details (endDrawer)، subscription_details (endDrawer)، chat_rooms (مظهر اللوحة فقط).
- لم يُغيَّر: employee_tracking_report (فلتر + قائمة موظفين)، database_admin (قائمة جداول بثيم داكن).
- نسخ احتياطية: `_backups/side-nav-2026-10-17/`.

## 2026-10-17 — SdSideNav v2
- أزرار مستقلة ملوّنة ثلاثية الأبعاد (تدرّج + حافة + إطار أسود + مكعّب أيقونة أبيض، ارتفاع/ضغط).
- إخفاء تلقائي: شريط أيقونات 84 دائماً، والقائمة الكاملة 272 تنبثق فوق المحتوى عند اقتراب الماوس (تأخير 140ms) وتختفي عند الإبعاد (260ms). زر تثبيت 📌 مشترك بين الصفحات (`SdSideNav.pinned`).
- النسخة السابقة: `_backups/side-nav-2026-10-17/sd_side_nav.v1.dart`.
- v3: عرض 224 (مطوية 72)، التوسّع يدفع الصفحة بدل التغطية، تفاعل أقوى مع المؤشّر (رفع + تكبير + سطوع + ميلان المكعّب).

## 2026-10-17 — تنعيم الإطار
- الإطار صار كحلياً رمادياً #3D4466 بعرض 1.2 بدل الأسود 1.5، والتركيز باللون الأساسي #1A237E بعرض 2.

## 2026-10-17 — هوية «كوبالت ناعم» (حسب مرجع المالك)
- الألوان: أساسي #2346D8، خلفية #EEF1FA، نص #0F1B4C، مجموعات بدرجات الأزرق (سماوي/كوبالت/إنديغو/كحلي/رمادي)، الإطار #D9E0F7 بعرض 1.
- العمق: ظلال ناعمة منتشرة بدل الحواف الصلبة (SdDepth.raised، SdRaised، SdMenuTile، SdSideNav)، زوايا أكبر (18/24/28).
- الشريط العلوي تدرّج كوبالت مع ظل متلاشٍ.
- AppTheme: نفس الهوية (primary، خلفية، بطاقات، حقول، تدرّج).
- تسجيل الدخول: ظلال البطاقة والحقول ناعمة.
- معاينة: design/cobalt/home_cobalt_preview.png — نسخة احتياطية: _backups/cobalt-theme-2026-10-17/

## 2026-10-17 — هوية «كحلي ملكي وذهبي» (اختيار المالك F2)
- أساسي كحلي #132A5E (حافة #0B1B3F)، ذهبي #C9A44C/#E6C67A، خلفية رمادية مزرقة #F1F4F9، نص #0B1B3F، إطار #E3E8F1.
- الأقسام بألوان أحجار كريمة: زمرّد (ميداني)، ياقوت أزرق (إدارة)، ياقوت أحمر (تواصل)، جمشت (منصات)، حجري (أدوات).
- الشريط العلوي كحلي بعنوان شمبانيا وخط ذهبي سفلي، ومكعبات الأيقونات بحلقة ذهبية.
- AppTheme بنفس الهوية. نسخة احتياطية: _backups/royal-navy-theme-2026-10-17/

## 2026-10-17 — خلفية دخول ثلاثية الأبعاد حقيقية (Three.js)
- `SdLogin3DBackground` (lib/frontend/components/sd_login_3d.dart): WebView (ويندوز: webview_windows، أندرويد/iOS: webview_flutter) يحمّل `assets/login3d/city.html` بلا إنترنت؛ بديل تلقائي SdLoginScene عند الفشل.
- المشهد: مدينة ليلية تملأ الشاشة (ضباب بلا حواف)، برج الصدارة الملتف + الشعار العائم، ألياف بنبضات، سيارات، إضاءة فيزيائية، ظلال، Bloom، 8 مبانٍ تفاعلية (مرور + دخول + بطاقة تفاصيل)، جودة تكيّفية.
- صفحة الدخول: الخلفية صارت المشهد الكامل؛ أزيلت SdLoginScene من التخطيطات و_buildOrb.
- pubspec: أُضيف `assets/login3d/`. المصدر وأداة البناء: tools/login3d/.
- v3 المدينة: إضاءة أقوى (تعريض 1.4، نوافذ أكثر إضاءة، أرض وشوارع مضيئة)، برج 20 طابقاً، شعار أكبر يواجه الكاميرا، وعرض مبهر عند الضغط على البرج (موجة ضوء ذهبية، ألعاب نارية، أقواس بيانات، موجات صدمة، دوران سينمائي، بطاقة مركز الشبكة).
- بطاقة الدخول: زجاج داكن شفاف (BackdropFilter blur 16 + تدرّج كحلي 55–70%)، أصغر (عرض 380، حقول 48، مسافات أقل)، نصوص بيضاء، أيقونات ذهبية، زر دخول ذهبي (accent)، SdSegmented بخيار glass. نسخة احتياطية: _backups/glass-login-2026-10-17/

## 2026-10-17 — إزالة الذهبي من الأزرار + تقرير الالتزام
- accent صار سماوياً بترولياً #0E7490 (حافة #155E75، فاتح #06B6D4)؛ الذهبي (gold/goldLight) للزخارف فقط. AppTheme.accentColor = #0E7490.
- أداة جديدة: docs/ui-unification/tools/theme_compliance.py → THEME_COMPLIANCE.md + theme_compliance.json (251 شاشة: 46 ملتزمة، 148 جزئية، 57 غير مرحّلة).

## 2026-10-17 — خطة التنظيف الشامل
- `THEME_CLEANUP_PLAN.md`: 8 مراحل (خط أساس، الخط المحلي بدل GoogleFonts، إزالة AccountingTheme/Energy، تحويل الألوان اليدوية بجدول دلالي، المكوّنات الخام، موجات A→I، الثيم العام، الحذف والحماية) + قواعد أمان + مؤشرات + أمر تنفيذ لـ Claude Code.

## 2026-10-17 — تنفيذ المراحل 0–3 (آلياً، بلا تغيير منطق)
- المرحلة 0: نسخة كاملة من lib + pubspec في _backups/theme-cleanup-start-2026-10-17/، وخط أساس THEME_COMPLIANCE.baseline.md.
- المرحلة 1: خط Cairo مضمّن (assets/fonts/cairo، 7 أوزان، OFL) + قسم fonts في pubspec؛ GoogleFonts.cairo → TextStyle(fontFamily: Cairo) في 82 ملفاً (2,355 استبدالاً، أزيل 80 import). بقي roboto/poppins (10) عمداً.
- المرحلة 2: AccountingTheme.<لون> → SdColors (2,384) و EnergyDashboardTheme.<لون> → SdColors (930). بقيت الدوال/التدرجات/الظلال (~115 استدعاء) لنقلها لاحقاً.
- المرحلة 3: الألوان اليدوية: Colors.x.shade/[N] (3,057) + Colors.x (2,007) + Color(0x..) معروفة (1,312) → SdColors في 216 ملفاً. تُركت للمراجعة اليدوية: Colors.x المجرّدة في 13 ملفاً تستخدم MaterialColor، و496 لون hex غير مصنّف.
- تحقق آلي: توازن الأقواس مطابق للأصل في كل الملفات المعدّلة (242)، لا imports مكررة، كل ملف يستخدم SdColors يستورده.
- النتيجة: ملتزمة 46→57، غير مرحّلة 57→3، Color(0x) 1,490→435، Colors.x 4,523→423، GoogleFonts 2,380→10، AccountingTheme 2,295→84، Energy 355→31.
- مطلوب من المالك: flutter analyze (لا يتوفر Flutter في بيئة Claude).
- إصلاح: حُذف import أُضيف آلياً داخل ملف part (subscription_details_page.renewal.dart) — كان الخطأ الوحيد في analyze. الأب يستورد SdColors. الأدوات صارت تتجاهل ملفات part of.

## 2026-10-17 — المرحلة 2ب + 4 (آلياً)
- نقل مساعدات الثيمين القديمين إلى frontend: SdUiKit (sd_ui_kit.dart) و SdDashKit (sd_dash_kit.dart، مع SdGlowButton/SdGlowCard)، وتحويل كل الاستدعاءات (147 في 28 ملفاً). الثيمان القديمان لم يعودا مستخدمين (مُعلَّمان «مهمل»، الحذف في المرحلة 7 بموافقة).
- ألوان hex المتبقية → أقرب رمز SdColors بفرق ΔE<16: 307 استبدالاً في 66 ملفاً. بقي 188 لوناً مميّزاً للمراجعة.
- AppBar البسيطة → SdAppBar: 63 في 53 ملفاً (تُركت 22 معقّدة: عنوان غير نصي/flexibleSpace).
- تحقق: توازن الأقواس، ترتيب الـ imports، ملفات part، الآباء — كلها سليمة.
- النتيجة: ملتزمة 57→76، غير مرحّلة 3→2، Color(0x) 435→222، AccountingTheme/Energy → 0، AppBar خام 82→21.
- نسخة احتياطية قبل المرحلة: _backups/theme-cleanup-phase4-start/

## 2026-10-17 — المرحلة 5 (أ): Colors.x المجرّدة في ملفات MaterialColor
- حُذف import غير مستخدم في ftth/reports/data_page.dart (التحذير الوحيد في analyze بعد المرحلة 4).
- أداة color_codemod_risky.py: تحويل Colors.<لون> فقط حين يكون قيمة وسيط Color مسمّى (color:, backgroundColor: …) داخل استدعاء مسمّى، مع تخطّي أي دالة/صنف في نفس الملف يصرّح بمعامل MaterialColor، وتخطّي records/maps.
- 207 استبدالاً في 12 ملفاً؛ تُخطّي 6 (‏_buildInlineWhatsAppIcon، _squareTile تأخذ MaterialColor). كل الدوال المستقبِلة الأخرى تم التحقق يدوياً أن نوعها Color.
- تحقق: توازن الأقواس مطابق للنسخة الاحتياطية، لا ملفات part معدّلة، كل ملف يستخدم SdColors يستورده.
- النتيجة: Colors.x 421→214.

## 2026-10-17 — المرحلة 5 (ب): ألوان hex المتبقية + AppBar بعنوان وسطر ثانوي
- analyze بعد 5أ: 0 أخطاء، 0 تحذيرات، 29 info.
- نسخة احتياطية: _backups/theme-cleanup-phase5b-start/ (lib كاملة).
- sd_colors.dart (إضافة فقط): successLight, warningLight, dangerLight, infoLight, platformMid, fieldBase/Light, commsBase/Edge/Light, neutralBase/Light — مطابقة لنبرات SdGroup/SdStatus الموجودة.
- hex_semantic_codemod.py: 129 لوناً في 45 ملفاً → أقرب رمز من نفس العائلة (ΔE<30 وفرق hue<28°، الرمادي→رمادي)، مع منع تحوّل تدرّج إلى لونين متطابقين. مستثنى: شاشة الدخول الزجاجية، depth_3d، خريطة KML، ألوان العلامات (فيسبوك/واتساب) والميداليات. بقي 13 لوناً عمداً.
- appbar_codemod2.py: 3 AppBar بعنوان Column[نص، نص] → SdAppBar(title, subtitle). بقي 19 AppBar مخصّصة (عناوين تفاعلية/بحث/تخطيط خاص) تحتاج تصميماً يدوياً لكل شاشة.
- تحقق: توازن الأقواس، الـ imports، لا ملفات part، كل رموز SdColors المستخدمة معرّفة.

## 2026-10-17 — المرحلة 7 (جزئياً): نقل الثيمات القديمة الميتة
- analyze بعد 5ب: 0 أخطاء، 0 تحذيرات، 29 info (مطابق لـ 5أ).
- تَحقّق: لا أي import/export للملفات الثلاثة في lib (باستثناء تعليقات توثيقية).
- نُقلت خارج lib إلى: src/Apps/CompanyDesktop/alsadara-ftth/_to_delete_theme_cleanup_2026-10-17/theme/ (لا يترجمها Flutter):
  - accounting_theme.dart (بُدّل بـ frontend/SdUiKit)
  - energy_dashboard_theme.dart (بُدّل بـ frontend/SdDashKit)
  - themes.dart (ملف تصدير ميت؛ كان يُصدّر app_theme + energy؛ لا أحد يستورده)
- أُبقي theme/app_theme.dart (يستخدمه main.dart — المرحلة 6 قيد الموافقة) و theme/accounting_responsive.dart (مساعد responsive، يستخدمه 33 ملفاً).
- الحذف النهائي لمجلد _to_delete يتركه المالك.

## 2026-10-17 — توحيد الأشرطة العلوية يدوياً (بحذر)
- analyze بعد النقل (المرحلة 7): الكود الحيّ في lib/ نظيف 0 أخطاء/0 تحذيرات/29 info؛ أخطاء مجلد _to_delete ذاتية الاحتواء.
- أُضيف _to_delete_theme_cleanup_2026-10-17/** إلى analyzer.exclude في analysis_options.yaml (غير مدمّر؛ الحذف النهائي للمالك).
- نسخة احتياطية قبل الأشرطة: _backups/theme-cleanup-appbars-start/
- اكتُشف أن ResponsiveAppBar (utils/responsive_app_bar.dart) و AppTheme.appBarGradient كلاهما غير مستخدم (كود ميت).
- حُوّلت 8 أشرطة عنوان قياسية إلى SdAppBar (العنوان/الإجراءات محفوظة؛ التدرّجات/الشارات الزخرفية أُسقطت لصالح الشريط الموحّد):
  technicians, export (reports), company_settings, users_page, users_page_firebase, tktats_page_beautiful, local_storage (العدّاد الحيّ → subtitle), tenant_whatsapp_permissions (title+subtitle).
- أُبقيت 10 أشرطة مخصّصة عمداً لأن الشريط نفسه يحمل محتوى وظيفياً/تفاعلياً أو تصميماً فاتحاً مميّزاً لا يعيد SdAppBar إنتاجه بأمان (خطر نص داكن على خلفية كحلية لا يلتقطه analyze):
  subscriptions_page (شريط تصفية كامل بلا عنوان)، ftth_operators_dashboard (أزرار تاريخ تفاعلية)، creator_amounts (إجمالي حيّ في العنوان)، vps_data_manager + company_details (رأس فاتح مفصّل مع bottom)، sas_agent_page، whatsapp_chat، chat_conversation (رأس محادثة)، ftth/auth/login (رأس شفاف)، إضافة لأي شريط فيه titleSpacing/تخطيط خاص. تحتاج مراجعة بصرية فردية.
- النتيجة: ملتزمة 82→83، AppBar خام (حسب الأداة) 18→10.

## 2026-10-17 — المرحلة 6: الثيم العام الموحّد في main.dart (بموافقة صريحة)
- نسخة احتياطية: _backups/theme-cleanup-phase6-start/main.dart
- main.dart: theme: AppTheme.lightTheme → SdTheme.light().copyWith(extensions:[AppTypography.build(...), const SdTokens()]).
  - دُمج الامتدادان: AppTypography (الطباعة) + SdTokens (رموز Sd) حتى لا تفقد أي شاشة امتدادها.
  - تحقق: context.sd = SdLayout (مستقل عن الثيم)؛ .typography بلا مستخدمين؛ قارئ SdTokens واحد. لا كسر متوقع.
- darkTheme أُبقي AppTheme.darkTheme (ميت؛ themeMode.light مفروض) — لذا app_theme.dart يبقى مستورداً ولا يُحذف في المرحلة 7.
- كلا الثيمين Material 3 بنفس seed (#132A5E) → التحول تفصيلي (إطارات switch/chip/dropdown، ألوان حالة أعمق قليلاً)، لا قفزة إصدار.
- النتيجة: غير مرحّلة 2→1 (بقيت شاشة واحدة: قيد المتابعة).

## 2026-10-17 — قرار الأشرطة الـ10 المخصّصة
- القرار (المالك): تُترك كما هي (الخيار أ) للعشرة جميعاً. التوحيد الجوهري اكتمل بالمرحلة 6؛ هذه رؤوس وظيفية/مقصودة (تصفية، أزرار تاريخ، إجمالي حيّ، رؤوس محادثة، رأس دخول شفاف، رأسان فاتحان في super_admin)، وتحويلها الآلي يخاطر بتباين نص على خلفية كحلية لا يلتقطه analyze.
- جدول المراجعة: docs/ui-unification/مراجعة_الأشرطة_المخصّصة.xlsx (الوضع/الخيارات/التوصية/القرار).
