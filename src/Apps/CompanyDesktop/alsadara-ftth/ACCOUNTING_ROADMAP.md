# خطة تطوير نظام الحسابات — Alsadara FTTH

## الحالة الحالية
النظام يغطي العمليات اليومية (قيود، مصروفات، تحصيلات، رواتب، صناديق) لكنه ليس نظام محاسبي متكامل.

---

## المشاكل المكتشفة

### 1. مشاكل محاسبية
- [ ] لا يوجد صفحة ميزان مراجعة (Trial Balance) رغم وجود API
- [ ] لا يوجد قائمة دخل (Income Statement)
- [ ] لا يوجد ميزانية عمومية (Balance Sheet)
- [ ] لا يوجد تقرير تدفقات نقدية (Cash Flow)
- [ ] لا يوجد تقرير أعمار ديون
- [ ] لا يوجد إقفال فترات محاسبية
- [ ] القيود لا تُرحَّل تلقائياً دائماً

### 2. مشاكل معمارية
- [ ] لا يوجد طبقة Models — البيانات كلها Map<String, dynamic>
- [ ] عدم اتساق استدعاء API (بعض الصفحات تستدعي HTTP مباشرة)
- [ ] غياب State Management (كل صفحة setState مباشرة)
- [ ] تكرار كود (Toolbar, Error State, Loading) في كل صفحة
- [ ] قيم ثابتة (Magic Values) في الكود

### 3. مشاكل أمنية
- [ ] لا يوجد سجل تدقيق (Audit Trail)
- [ ] URL و API Key مكشوفين في الكود
- [ ] لا يوجد تحكم صلاحيات على مستوى صفحات المحاسبة
- [ ] يمكن حذف قيود مرحّلة بدون قيود

### 4. مشاكل أداء
- [ ] withdrawal_requests_page يحمّل 1000 عنصر للإحصائيات
- [ ] لا يوجد Pagination في القيود والمصروفات
- [ ] أخطاء صامتة catch(_) {} في عدة صفحات

---

## خطة التنفيذ

### المرحلة 1: التقارير المحاسبية الأساسية ✅ قيد التنفيذ
**الهدف:** إضافة التقارير المالية الثلاثة الأساسية التي يحتاجها أي نظام محاسبي

| المهمة | الملف | الحالة |
|--------|-------|--------|
| صفحة ميزان المراجعة | `trial_balance_page.dart` | ⬜ |
| صفحة قائمة الدخل | `income_statement_page.dart` | ⬜ |
| صفحة الميزانية العمومية | `balance_sheet_page.dart` | ⬜ |
| إضافة التقارير للوحة التحكم | `accounting_dashboard_page.dart` | ⬜ |

**التفاصيل:**
- ميزان المراجعة: جدول بكل الحسابات + رصيد مدين/دائن + التحقق من التوازن
- قائمة الدخل: إيرادات − مصروفات = صافي ربح/خسارة (مع فلتر تاريخ)
- الميزانية العمومية: أصول = التزامات + حقوق ملكية (بتاريخ محدد)

---

### المرحلة 2: طبقة Models
**الهدف:** إنشاء models بدلاً من Map<String, dynamic> لتقليل أخطاء runtime

| المهمة | الملف | الحالة |
|--------|-------|--------|
| Account model | `models/account.dart` | ⬜ |
| JournalEntry model | `models/journal_entry.dart` | ⬜ |
| Expense model | `models/expense.dart` | ⬜ |
| Salary model | `models/salary.dart` | ⬜ |
| Collection model | `models/collection.dart` | ⬜ |
| CashBox model | `models/cash_box.dart` | ⬜ |
| تحديث AccountingService | `accounting_service.dart` | ⬜ |

---

### المرحلة 3: سلامة البيانات والأمان
**الهدف:** حماية البيانات المحاسبية من التلاعب

| المهمة | الملف | الحالة |
|--------|-------|--------|
| إقفال الفترات المحاسبية (API + UI) | `period_closing_page.dart` | ⬜ |
| سجل تدقيق (Audit Log) | `audit_log_page.dart` | ⬜ |
| نقل URLs و API Keys لملف config | `config/api_config.dart` | ⬜ |
| صلاحيات صفحات المحاسبة | `accounting_permissions.dart` | ⬜ |
| منع حذف القيود المرحّلة | `journal_entries_page.dart` | ⬜ |

---

### المرحلة 4: توحيد API وتحسين الأداء
**الهدف:** توحيد كل استدعاءات API وإضافة Pagination

| المهمة | الملف | الحالة |
|--------|-------|--------|
| نقل HTTP المباشر في ftth_operator_account_page | `accounting_service.dart` | ⬜ |
| نقل AuthService في ftth_operator_linking_page | `accounting_service.dart` | ⬜ |
| إضافة Pagination للقيود | `journal_entries_page.dart` | ⬜ |
| إضافة Pagination للمصروفات | `expenses_page.dart` | ⬜ |
| إصلاح تحميل 1000 عنصر | `withdrawal_requests_page.dart` | ⬜ |
| إصلاح catch(_) {} الصامتة | ملفات متعددة | ⬜ |

---

### المرحلة 5: تقارير متقدمة
**الهدف:** تقارير إضافية للتحليل المالي

| المهمة | الملف | الحالة |
|--------|-------|--------|
| تقرير التدفقات النقدية | `cash_flow_page.dart` | ⬜ |
| تقرير أعمار الديون | `aging_report_page.dart` | ⬜ |
| مقارنة شهرية | `monthly_comparison_page.dart` | ⬜ |
| تصدير Excel/PDF لكل التقارير | widgets مشتركة | ⬜ |

---

### المرحلة 6: تحسينات UX
**الهدف:** تحسين تجربة المستخدم

| المهمة | الملف | الحالة |
|--------|-------|--------|
| قوالب قيود جاهزة | `journal_templates.dart` | ⬜ |
| تنبيهات (تحصيلات متأخرة، رواتب) | `accounting_alerts.dart` | ⬜ |
| Widgets مشتركة (Toolbar, Error, Loading) | `widgets/accounting_shared.dart` | ⬜ |
| بحث شامل في كل المعاملات | `accounting_search_page.dart` | ⬜ |

---

## ملاحظات
- كل مرحلة مستقلة ويمكن نشرها بشكل منفصل
- المراحل 1-3 هي الأهم لتحويل النظام لنظام محاسبي متكامل
- المراحل 4-6 تحسينات نوعية يمكن تنفيذها تدريجياً
- التعديلات على الـ Backend (API) تُذكر عند الحاجة في كل مرحلة
