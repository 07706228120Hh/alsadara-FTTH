import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/app_theme.dart';
import '../models/sas_account.dart';
import '../models/sas_subscriber.dart';
import '../models/sas_subscriber_summary.dart';
import '../services/sas_agent_api_service.dart';
import '../widgets/sas_metrics.dart';
import '../widgets/sas_refresh_bus.dart';
import '../widgets/sas_ring_metric.dart';
import '../widgets/sas_state_views.dart';
import 'sas_subscriber_detail_page.dart';

// ─────────────────────── الهوية البصرية المحلية للوحة ───────────────────────
// ثوابت لون خاصّة بهذه اللوحة فقط — **لا تمسّ ثيم التطبيق العام** (AppTheme).
// تعتمد لوحة الصدارة المطلوبة: أزرق مضيء للأزرار/التحديد، نص كحلي داكن، نص
// ثانوي رمادي، وخلفية صفحة فاتحة هادئة.
const Color _kAccent = Color(0xFF3563F6); // أزرق الصدارة المضيء (أزرار/تحديد)
const Color _kInk = Color(0xFF14213D); // النص الرئيسي
const Color _kMuted = Color(0xFF64748B); // النص الثانوي
const Color _kPageBg = Color(0xFFF5F7FA); // خلفية الصفحة

/// تبويب «لوحة» — لوحة الوكيل المبسّطة للحساب المحدد بثيم منصّة الصدارة.
///
/// ## بنية اللوحة (من الأعلى للأسفل)
/// 1. **صف العدّادات الحلقية الأربعة** يملأ أعلى الشاشة بالتساوي:
///    الإجمالي · الأشتراكات النشطة · متصل الآن · الأشتراكات المنتهية.
///    (رقم بارز + قوس تقدّم بنسبة صادقة للنشط/المتصل/المنتهي نسبةً للإجمالي؛
///    الإجمالي مرجع ممتلئ 100% بلا نسبة). «متصل الآن» مستقلّ عن «النشط».
/// 2. **حقل البحث + الفلاتر + منطقة النتائج**.
///
/// (أُزيلت بطاقة ترويسة «نظرة عامة»؛ زر المزامنة اليدوية انتقل إلى شريط الشل
/// العلوي [AppBar] كزرّ تحديث مستقل.)
///
/// ## مصدر الأرقام (موثوق)
/// العدّادات تُملأ من [SasAgentApiService.getSubscribersSummary] — **الملخّص
/// المحلّي الموثوق** (قاعدة الصدارة بعد المزامنة) لا من لوحة الساس الحيّة. لذا
/// لا تُعرَض «-» أبداً: رقم فعلي أو 0.
///
/// ## المزامنة والتحديث
/// - **المزامنة الكاملة** [SasAgentApiService.syncAccount] ثقيلة (تضرب SAS4):
///   تُنفَّذ فقط (أ) عند أول تحميل إن لم توجد بيانات محلية (`last_sync == null`)،
///   (ب) بزر «تحديث» اليدوي في شريط الشل العلوي (يبثّ عبر الناقل فتعيد اللوحة
///   التحميل الخفيف). **لا تُستدعى في المؤقّت إطلاقاً.**
/// - **تحديث تلقائي خفيف** كل 45 ثانية: الملخّص الموثوق فقط (بلا مزامنة).
class SasDashboardTab extends StatefulWidget {
  final SasAccount account;

  /// ينتقل لتبويب «مشتركون» مفلترًا على نافذة الانتهاء المطلوبة
  /// (overdue/today/soon3/soon7). يُمرَّر من شل الوحدة (محفوظ للتوافق).
  final void Function(String expiring)? onOpenExpiring;

  const SasDashboardTab({
    super.key,
    required this.account,
    this.onOpenExpiring,
  });

  @override
  State<SasDashboardTab> createState() => _SasDashboardTabState();
}

class _SasDashboardTabState extends State<SasDashboardTab> {
  final _api = SasAgentApiService.instance;

  /// فترة التحديث التلقائي الخفيف.
  static const _autoRefreshEvery = Duration(seconds: 45);

  // المصدر الوحيد الموثوق: الملخّص المحلّي (إن فشل أوّل تحميل تُعرَض حالة خطأ).
  SasSubscriberSummary? _summary;
  bool _loading = true;
  String? _error;

  bool _autoRefreshing = false; // تحديث خفيف دوري جارٍ (مؤشّر لطيف)

  Timer? _timer;

  /// اشتراك ناقل التحديث المشترك — يعيد تحميلاً خفيفاً عند أي عملية/مزامنة.
  StreamSubscription<SasRefreshEvent>? _busSub;

  // ─────────────────── حالة البحث الشامل (مستقلّة عن العدّادات) ───────────────────
  // بحث نصّي شامل يضرب الخادم بـ`search=` عبر getLocalSubscribers. مستقلّ تماماً
  // عن مزامنة العدّادات (_load/_refreshLight) فلا يؤثّر فشله عليها.
  final _searchCtrl = TextEditingController();
  Timer? _searchDebounce;

  /// آخر استعلام نُفّذ فعلياً (نحمي من سباقات الطلبات المتأخّرة بمطابقته).
  String _searchQuery = '';
  List<SasSubscriber> _searchResults = [];
  bool _searchLoading = false;
  String? _searchError;

  // ─────────────────── فلاتر الحالة والباقة (البند 4) ───────────────────
  // فلتر الحالة: null = الكل · 'active' = نشط · 'expired' = منتهٍ.
  String? _statusFilter;

  // فلتر الباقة: null = كل الباقات · اسم الباقة تماماً (exact).
  String? _profileFilter;

  /// قائمة الباقات المتاحة للقائمة المنسدلة — مشتقّة (distinct) من نتائج البحث،
  /// وتُحدَّث **فقط عندما يكون فلتر الباقة = الكل** كيلا تنكمش لباقة واحدة عند
  /// التصفية بها. لا نستدعي أي نقطة جديدة؛ نشتقّها من النتائج الحالية.
  List<String> _profileOptions = [];

  /// هل أيّ فلتر (حالة/باقة) نشط؟ يستخدمه منطق الجلب وحالة «اكتب للبحث».
  bool get _hasActiveFilter => _statusFilter != null || _profileFilter != null;

  @override
  void initState() {
    super.initState();
    _load();
    _busSub = SasRefreshBus.instance.stream.listen(_onBusEvent);
  }

  /// عند إشعار الناقل الخاص بحساب هذه اللوحة: تحديث خفيف موضعي (بلا مزامنة ثقيلة
  /// ولا وميض) — المزامنة تمّت عند مصدر الحدث (العملية/الشل/الزر).
  void _onBusEvent(SasRefreshEvent e) {
    if (!mounted) return;
    if (!e.matches(widget.account.id)) return;
    _refreshLight();
  }

  @override
  void didUpdateWidget(covariant SasDashboardTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    // عند تبديل الحساب: أوقِف المؤقّت، صفّر الحالة، وأعِد التحميل من الصفر.
    if (oldWidget.account.id != widget.account.id) {
      _stopTimer();
      _summary = null;
      // صفّر حالة البحث عند تبديل الحساب (نتائج حساب آخر لا تخصّ الجديد):
      // النصّ + الفلاتر (حالة/باقة) + قائمة الباقات + النتائج.
      _searchDebounce?.cancel();
      _searchCtrl.clear();
      _searchQuery = '';
      _searchResults = [];
      _searchLoading = false;
      _searchError = null;
      _statusFilter = null;
      _profileFilter = null;
      _profileOptions = [];
      _load();
    }
  }

  @override
  void dispose() {
    _busSub?.cancel();
    _stopTimer();
    _searchDebounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  String _clean(Object e) =>
      e.toString().replaceFirst('Exception: ', '').trim();

  // ─────────────────────────── التحميل والتحديث ───────────────────────────

  /// المؤقّت الدوري الخفيف (يُعاد ضبطه بأمان — يلغي أيّ مؤقّت سابق أولاً).
  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(_autoRefreshEvery, (_) => _refreshLight());
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  /// تحميل أوّلي كامل:
  /// - يجلب الملخّص المحلّي الموثوق (المصدر الوحيد).
  /// - إن لم توجد بيانات محلية (`last_sync == null`) يُشغّل مزامنة كاملة مرّة
  ///   واحدة ثم يعيد قراءة الملخّص.
  /// - يُشغّل المؤقّت الدوري الخفيف في النهاية.
  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final id = widget.account.id;

    // المصدر الموثوق: الملخّص المحلّي.
    try {
      var s = await _api.getSubscribersSummary(id);
      // لا بيانات محلية بعد؟ مزامنة كاملة مرّة واحدة (أول تحميل فقط) ثم إعادة قراءة.
      if (s.lastSync == null) {
        try {
          await _api.syncAccount(id);
          if (!mounted) return;
          s = await _api.getSubscribersSummary(id);
        } catch (_) {
          // فشل المزامنة الأولى لا يُسقط اللوحة — نعرض الملخّص كما هو (أصفار).
        }
      }
      if (!mounted) return;
      setState(() => _summary = s);
    } catch (e) {
      if (mounted) setState(() => _error = _clean(e));
    }

    if (!mounted) return;
    setState(() => _loading = false);

    // شغّل التحديث التلقائي الدوري بعد اكتمال أوّل تحميل.
    _startTimer();
  }

  /// تحديث تلقائي **خفيف** (يستدعيه المؤقّت كل 45 ثانية):
  /// الملخّص المحلّي فقط. **لا مزامنة.**
  Future<void> _refreshLight() async {
    if (!mounted || _autoRefreshing) return;
    setState(() => _autoRefreshing = true);
    final id = widget.account.id;
    try {
      final s = await _api
          .getSubscribersSummary(id)
          .then<SasSubscriberSummary?>((v) => v)
          .catchError((_) => null);
      if (!mounted) return;
      if (s != null) setState(() => _summary = s);
    } finally {
      if (mounted) setState(() => _autoRefreshing = false);
    }
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content:
          Text(msg, style: GoogleFonts.cairo(fontWeight: FontWeight.w600)),
      backgroundColor: error ? AppTheme.errorColor : AppTheme.successColor,
      behavior: SnackBarBehavior.floating,
    ));
  }

  // ─────────────────────────── البحث الشامل ───────────────────────────

  /// تغيّر نصّ البحث: إلغاء أي مؤقّت سابق وجدولة بحث بعد ~450ms (debounce).
  /// نُحدّث الحالة فوراً لإظهار/إخفاء زر المسح وبطاقة الإرشاد قبل الكتابة.
  void _onSearchChanged(String _) {
    setState(() {}); // تحديث زر المسح وحالة «قبل الكتابة» بلا جلب
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 450), _runSearch);
  }

  /// مسح نصّ البحث (زر المسح في الحقل): يُلغي المؤقّت ويفرّغ النصّ. إن بقي فلتر
  /// (حالة/باقة) نشطاً نعيد تشغيل البحث فوراً (قد تبقى نتائج فلتر بلا نصّ)؛ وإلا
  /// نعود لحالة الإرشاد بلا جلب.
  void _clearSearch() {
    _searchDebounce?.cancel();
    _searchCtrl.clear();
    if (_hasActiveFilter) {
      _runSearch();
      return;
    }
    setState(() {
      _searchQuery = '';
      _searchResults = [];
      _searchLoading = false;
      _searchError = null;
    });
  }

  /// تغيّر شريحة الحالة (الكل/نشط/منتهٍ): يحدّث الفلتر ويعيد تشغيل البحث فوراً.
  void _onStatusFilterChanged(String? status) {
    if (_statusFilter == status) return;
    setState(() => _statusFilter = status);
    _searchDebounce?.cancel();
    _runSearch();
  }

  /// تغيّر قائمة الباقة (كل الباقات/باقة محددة): يحدّث الفلتر ويعيد تشغيل البحث.
  void _onProfileFilterChanged(String? profile) {
    if (_profileFilter == profile) return;
    setState(() => _profileFilter = profile);
    _searchDebounce?.cancel();
    _runSearch();
  }

  /// تنفيذ البحث الفعلي عبر الملخّص المحلّي السريع (`getLocalSubscribers`) مع
  /// `search=`/`status=`/`profile=`. نجلب إذا كان **النصّ غير فارغ أو أيّ فلتر
  /// (حالة/باقة) نشطاً** — فيصبح بالإمكان عرض «كل المنتهين» أو «كل باقة X» بلا
  /// نصّ. غير ذلك (نصّ فارغ ولا فلتر) ⇒ حالة الإرشاد (لا نجلب كل المشتركين).
  /// الفشل معزول تماماً عن العدّادات. نحمي من سباق الطلبات المتأخّرة بمطابقة
  /// النصّ + الفلترين الحاليين عند عودة الاستجابة.
  Future<void> _runSearch() async {
    final q = _searchCtrl.text.trim();
    final status = _statusFilter;
    final profile = _profileFilter;

    // لا نصّ ولا فلتر ⇒ حالة الإرشاد (بلا جلب).
    if (q.isEmpty && status == null && profile == null) {
      setState(() {
        _searchQuery = '';
        _searchResults = [];
        _searchLoading = false;
        _searchError = null;
      });
      return;
    }

    setState(() {
      _searchQuery = q;
      _searchLoading = true;
      _searchError = null;
    });

    try {
      final page = await _api.getLocalSubscribers(
        widget.account.id,
        search: q.isEmpty ? null : q,
        status: status,
        profile: profile,
        count: 60,
      );
      if (!mounted) return;
      // تجاهل استجابة قديمة إن تغيّر النصّ/الفلتر بعد إطلاقها.
      if (q != _searchCtrl.text.trim() ||
          status != _statusFilter ||
          profile != _profileFilter) {
        return;
      }
      final results = page.subscribers.map(SasSubscriber.fromJson).toList();
      setState(() {
        _searchResults = results;
        _searchLoading = false;
        // حدّث قائمة الباقات (distinct) **فقط** حين لا تصفية بالباقة، كيلا
        // تنكمش القائمة لباقة واحدة عند التصفية بها.
        if (profile == null) {
          _profileOptions = _distinctProfiles(results);
        }
      });
    } catch (e) {
      if (!mounted) return;
      if (q != _searchCtrl.text.trim() ||
          status != _statusFilter ||
          profile != _profileFilter) {
        return;
      }
      setState(() {
        _searchError = _clean(e);
        _searchLoading = false;
      });
    }
  }

  /// يستخرج أسماء الباقات المميّزة (distinct) من نتائج، مرتّبةً أبجديّاً. نتجاهل
  /// التسمية الفارغة/النائبة ('-').
  List<String> _distinctProfiles(List<SasSubscriber> results) {
    final set = <String>{};
    for (final s in results) {
      final p = s.profile.trim();
      if (p.isNotEmpty) set.add(p);
    }
    final list = set.toList()..sort();
    return list;
  }

  /// فتح صفحة تفاصيل مشترك من نتيجة بحث (يتطلّب معرّف ساس صالحاً).
  Future<void> _openSubscriber(SasSubscriber s) async {
    if (s.id.isEmpty) {
      _snack('تعذّر فتح المشترك: معرّف غير متاح', error: true);
      return;
    }
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => SasSubscriberDetailPage(
          account: widget.account,
          userId: s.id,
          username: s.username,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _summary == null) {
      return const ColoredBox(
        color: _kPageBg,
        child: SasLoadingView(message: 'جاري جلب اللوحة…'),
      );
    }
    if (_error != null && _summary == null) {
      return ColoredBox(
        color: _kPageBg,
        child: SasErrorView(message: _error!, onRetry: _load),
      );
    }

    final s = _summary ?? SasSubscriberSummary.empty;

    // قرار التخطيط عبر [LayoutBuilder]: على سطح المكتب الطبيعي (عريض وطويل بما
    // يكفي) نبني **شاشة واحدة تملأ الارتفاع بلا تمرير**: ترويسة مضغوطة + منطقة
    // عدّادات [Expanded] تملأ ما تبقّى (أربعة عدّادات في صفّ موزّع بالتساوي،
    // متمركزة عمودياً). على النوافذ الصغيرة/القصيرة (أو الموبايل الضيّق) نتحوّل
    // إلى تمرير رأسي آمن (خطة أمان) لمنع أي overflow.
    return ColoredBox(
      color: _kPageBg,
      child: LayoutBuilder(
        builder: (context, c) {
          final wide = c.maxWidth >= 1040;
          final tall = c.maxHeight >= 600;
          final sidePad = wide ? 28.0 : (c.maxWidth >= 640 ? 22.0 : 16.0);

          // شاشة واحدة بلا تمرير: عريض + طويل بما يكفي.
          if (wide && tall) {
            return _singleScreen(s, sidePad);
          }

          // خطة الأمان: تدفّق قابل للتمرير للنوافذ الصغيرة/القصيرة/الموبايل —
          // الترويسة + العدّادات + حقل البحث + منطقة النتائج (بارتفاع مقيّد كي
          // تُمرَّر مع الصفحة بدل تمرير داخلي مزدوج).
          return RefreshIndicator(
            onRefresh: _refreshLight,
            child: ListView(
              padding: EdgeInsets.fromLTRB(sidePad.w, sidePad.h, sidePad.w, 28.h),
              children: [
                _countersStrip(s),
                SizedBox(height: 20.h),
                _searchBox(),
                SizedBox(height: 10.h),
                _filtersRow(),
                SizedBox(height: 12.h),
                SizedBox(
                  height: (c.maxHeight * 0.6).clamp(260.0, 520.0),
                  child: _searchResultsArea(),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// تخطيط **الشاشة الواحدة** (سطح المكتب): [Column] يملأ الارتفاع الكامل بلا
  /// تمرير للصفحة —
  /// (1) صف العدّادات الأربعة **بارتفاع مقيّد** (يصعد لأعلى بعد إزالة الترويسة) —
  ///     الحلقات موزّعة بالتساوي، قطرها مقيَّد بهذا الارتفاع فلا overflow،
  /// (2) حقل البحث الشامل + صفّ الفلاتر،
  /// (3) منطقة النتائج في [Expanded] **تُمرَّر داخليّاً** (القائمة وحدها تُمرَّر،
  ///     لا الصفحة كلها).
  Widget _singleScreen(SasSubscriberSummary s, double sidePad) {
    // ارتفاع مقيّد لصف العدّادات: مربّع بطاقة مريح لكنه أصغر من قبل كي يبقى
    // متّسع وافٍ لحقل البحث ومنطقة النتائج تحته.
    final countersH = 224.0.h;
    return Padding(
      padding: EdgeInsets.fromLTRB(sidePad.w, 18.h, sidePad.w, 18.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1) صف العدّادات بارتفاع مقيّد (يُقيّد قطر الحلقات تلقائياً) — يصعد
          //    لأعلى بعد إزالة بطاقة الترويسة.
          SizedBox(height: countersH, child: _countersStrip(s, fill: true)),
          SizedBox(height: 18.h),
          // 3) حقل البحث الشامل + صفّ الفلاتر المضغوط تحته مباشرةً.
          _searchBox(),
          SizedBox(height: 10.h),
          _filtersRow(),
          SizedBox(height: 12.h),
          // 4) منطقة النتائج تملأ ما تبقّى وتُمرَّر داخليّاً.
          Expanded(child: _searchResultsArea()),
        ],
      ),
    );
  }

  // ─────────────────── صف العدّادات (المشتركون) ───────────────────

  /// صفّ العدّادات: **عدّادات حلقية فاخرة** تمتد بعرض الصفحة أسفل الترويسة. كلّ
  /// عدّاد داخل بطاقة بيضاء فسيحة (حواف 18px + حدّ خفيف + ظل ناعم): حلقة بقطر
  /// مريح (مسار خافت فاتح + قوس تقدّم بلون المقياس بأطراف مستديرة، بلا بروز
  /// ثلاثي أبعاد)، مركزها أيقونة صغيرة + رقم بارز ملوّن (tabular ضمن LTR) +
  /// نسبة مئوية حيث تنطبق، ثم عنوان العدّاد كحلي أسفل الحلقة. أربعة عناصر
  /// (RTL يمين→يسار): الإجمالي (مرجع ممتلئ 100% بلا نسبة) · النشط · متصل الآن ·
  /// المنتهية.
  ///
  /// [fill] (تخطيط الشاشة الواحدة): العدّادات في **صفّ واحد** يمتد بعرض الشاشة
  /// كاملاً (أربعة [Expanded] بالتساوي) ومتمركز عمودياً داخل المساحة المتاحة؛
  /// يُقيَّد قطر الحلقة بأصغر بُعد للخلية (عرضاً وارتفاعاً) فلا overflow. غير ذلك
  /// (التمرير): شبكة ملتفّة متساوية الأعمدة بلا تداخل.
  Widget _countersStrip(SasSubscriberSummary s, {bool fill = false}) {
    final total = s.total;

    final cells = <_RingCounterDef>[
      _RingCounterDef(
        title: 'إجمالي المشتركين',
        value: s.total,
        // الإجمالي مرجع ⇒ حلقة ممتلئة 100% بلا نسبة.
        max: null,
        showPercent: false,
        color: _kAccent, // أزرق الصدارة.
        icon: Icons.groups_rounded,
      ),
      _RingCounterDef(
        title: 'الأشتراكات النشطة',
        value: s.active,
        // النسبة = active/total (حماية من القسمة على صفر).
        max: total > 0 ? total : null,
        showPercent: total > 0,
        color: AppTheme.successColor, // أخضر.
        icon: Icons.check_circle_rounded,
      ),
      _RingCounterDef(
        title: 'متصل الآن',
        value: s.online,
        // النسبة = online/total — مستقلّة عن النشط.
        max: total > 0 ? total : null,
        showPercent: total > 0,
        color: AppTheme.infoColor, // أزرق فاتح.
        icon: Icons.wifi_rounded,
      ),
      _RingCounterDef(
        title: 'الأشتراكات المنتهية',
        value: s.expired,
        // النسبة = expired/total.
        max: total > 0 ? total : null,
        showPercent: total > 0,
        color: AppTheme.errorColor, // أحمر.
        icon: Icons.timer_off_rounded,
      ),
    ];

    const double gap = 18.0; // فاصل منطقي ثابت (يُحوَّل .w/.h عند الاستخدام)
    const double minCardW = 240.0; // أدنى عرض مريح للبطاقة الواحدة

    return LayoutBuilder(
      builder: (context, c) {
        final avail = c.maxWidth;
        final gapW = gap.w;

        // تخطيط الشاشة الواحدة: صفّ واحد يمتد بعرض الشاشة كاملاً — الأعمدة
        // الأربعة موزّعة بالتساوي عبر [Expanded]، ومتمركزة عمودياً داخل المساحة
        // المتاحة (لا تُمطّط): نحجز للحلقة قطراً فاخراً مريحاً بحدٍّ أقصى معقول،
        // مقيَّداً بأصغر بُعد للخلية فلا overflow.
        if (fill) {
          final cellW = (avail - gapW * (cells.length - 1)) / cells.length;
          // سقف قطر إضافي من الارتفاع المتاح: ارتفاع البطاقة ≈ القطر + حشوات
          // رأسية + فجوة + سطر العنوان (نحجز ~74 منطقيّة). عند توفّر ارتفاع
          // محدود (الصف المقيّد في الشاشة الواحدة) نمنع فيضاناً رأسياً.
          final hCap = c.maxHeight.isFinite
              ? (c.maxHeight - 74.0.h).clamp(0.0, double.infinity)
              : double.infinity;
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              for (var i = 0; i < cells.length; i++) ...[
                if (i > 0) SizedBox(width: gapW),
                Expanded(
                  child: Center(
                      child: _ringCounterCard(cells[i], cellW,
                          maxDiameter: hCap)),
                ),
              ],
            ],
          );
        }

        // خطة الأمان (تمرير): شبكة ملتفّة متساوية الأعمدة بلا تداخل — نختار عدد
        // الأعمدة بناءً على عرض بطاقة أدنى مريح، ونثبّت عرض كل بطاقة.
        int cols = ((avail + gapW) / (minCardW.w + gapW)).floor();
        cols = cols.clamp(1, cells.length);

        // عرض الخلية المحسوب = (المتاح − مجموع الفواصل) / الأعمدة. نطرح 0.5px
        // احترازياً لأخطاء التقريب كي لا يتجاوز مجموع الصفّ العرض المتاح أبداً.
        final itemW =
            ((avail - gapW * (cols - 1)) / cols - 0.5).clamp(0.0, avail);

        return Wrap(
          spacing: gapW,
          runSpacing: gap.h,
          children: [
            for (final d in cells)
              SizedBox(
                width: itemW,
                child: _ringCounterCard(d, itemW),
              ),
          ],
        );
      },
    );
  }

  /// بطاقة عدّاد حلقية فاخرة بعرض مثبَّت [cardW]: بطاقة بيضاء فسيحة (حواف 18px +
  /// حدّ خفيف + ظل ناعم) بحشوة مريحة، تضمّ الحلقة الفاخرة **بقطر مقيَّد** فلا
  /// تتجاوز حدودها، ثم **عنوان العدّاد** كحلي بارز أسفلها — موضع موحّد بين كل
  /// البطاقات.
  ///
  /// تقييد القطر: `diameter = (cardW − الحشوة الأفقية) محدوداً بـ[ringMax]`، ثم
  /// نحجز للحلقة مربّعاً بهذا الضلع فيبقى `SasRingMetric` داخل بطاقته (القطر =
  /// أصغر بُعد ⇒ لا فيضان أفقي). التسمية الداخلية للحلقة فارغة عمداً
  /// (`label: ''`) فلا يتكرّر النص؛ العنوان الكحلي أسفلها هو العنوان الوحيد.
  Widget _ringCounterCard(_RingCounterDef d, double cardW,
      {double maxDiameter = double.infinity}) {
    // الحشوة الأفقية للبطاقة (يمين+يسار) = 20.w × 2؛ نطرحها من عرض البطاقة
    // لنحصل على الفراغ الداخلي المتاح للحلقة، ثم نقيّده بحدٍّ أقصى معقول.
    const double hPadLogical = 20.0;
    const double ringMax = 220.0; // أقصى قطر فاخر مريح للحلقة
    final vPadTop = 22.0.h;
    final vPadBot = 18.0.h;
    final titleGap = 14.0.h;

    final innerW = (cardW - hPadLogical.w * 2).clamp(0.0, double.infinity);
    // القطر = أصغر من (العرض الداخلي، الحدّ الأقصى الفاخر، سقف الارتفاع المتاح).
    var diameter = innerW < ringMax.w ? innerW : ringMax.w;
    if (diameter > maxDiameter) diameter = maxDiameter;
    if (diameter < 0) diameter = 0;

    final ring = SizedBox(
      width: diameter,
      height: diameter,
      child: SasRingMetric.premium(
        value: d.value,
        max: d.max,
        showPercent: d.showPercent,
        label: '',
        color: d.color,
        icon: d.icon,
      ),
    );

    final title = Text(
      d.title,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.center,
      style: GoogleFonts.cairo(
        fontSize: 13.sp,
        fontWeight: FontWeight.w800,
        color: _kInk,
      ),
    );

    return Container(
      padding: EdgeInsets.fromLTRB(hPadLogical.w, vPadTop, hPadLogical.w, vPadBot),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18.r),
        border: Border.all(color: d.color.withValues(alpha: 0.10)),
        boxShadow: [
          // طبقة 1: ظل ملوّن خفيف جداً بلون المقياس ⇒ لمسة فخامة هادئة.
          BoxShadow(
            color: d.color.withValues(alpha: 0.10),
            blurRadius: 20,
            spreadRadius: -6,
            offset: const Offset(0, 10),
          ),
          // طبقة 2: ظل رمادي ناعم أعمق قليلاً للعمق الاحترافي.
          BoxShadow(
            color: const Color(0xFF0B1B3A).withValues(alpha: 0.08),
            blurRadius: 14,
            spreadRadius: -8,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      // ارتفاع طبيعي (البطاقة تلتفّ حول محتواها): الحلقة ثم العنوان أسفلها.
      // في الشاشة الواحدة تُلفّ بـ Center فتتمركز عمودياً داخل الخلية المرنة.
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ring,
          SizedBox(height: titleGap),
          title,
        ],
      ),
    );
  }

  // ─────────────────── حقل البحث الشامل ───────────────────

  /// حقل بحث أنيق بهوية الصدارة: بطاقة بيضاء (حواف 16px + ظل ناعم)، أيقونة بحث
  /// أمامية، نصّ إرشادي، وزر مسح يظهر عند وجود نصّ. تحديث فوري مع debounce.
  Widget _searchBox() {
    final hasText = _searchCtrl.text.isNotEmpty;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16.r),
        boxShadow: [
          BoxShadow(
            color: _kAccent.withValues(alpha: 0.06),
            blurRadius: 16,
            spreadRadius: -6,
            offset: const Offset(0, 6),
          ),
          BoxShadow(
            color: const Color(0xFF0B1B3A).withValues(alpha: 0.05),
            blurRadius: 10,
            spreadRadius: -6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: TextField(
        controller: _searchCtrl,
        onChanged: _onSearchChanged,
        onSubmitted: (_) => _runSearch(),
        textInputAction: TextInputAction.search,
        style: GoogleFonts.cairo(
          fontWeight: FontWeight.w600,
          fontSize: 13.sp,
          color: _kInk,
        ),
        decoration: InputDecoration(
          hintText: 'ابحث عن مشترك بأي معلومة: اسم، اسم مستخدم، هاتف، باقة…',
          hintStyle: GoogleFonts.cairo(
            color: _kMuted,
            fontSize: 12.5.sp,
            fontWeight: FontWeight.w600,
          ),
          filled: true,
          fillColor: Colors.white,
          prefixIcon: Icon(Icons.search_rounded, color: _kAccent, size: 21.sp),
          suffixIcon: hasText
              ? IconButton(
                  tooltip: 'مسح',
                  icon: Icon(Icons.clear_rounded, color: _kMuted, size: 19.sp),
                  onPressed: _clearSearch,
                )
              : null,
          contentPadding: EdgeInsets.symmetric(vertical: 14.h),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16.r),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16.r),
            borderSide: BorderSide(color: _kAccent.withValues(alpha: 0.14)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16.r),
            borderSide: BorderSide(color: _kAccent, width: 1.6),
          ),
        ),
      ),
    );
  }

  // ─────────────────── صفّ الفلاتر (الحالة + الباقة) ───────────────────

  /// صفّ فلاتر مضغوط أسفل حقل البحث مباشرةً: شرائح الحالة (الكل/نشط/منتهٍ) على
  /// اليمين وقائمة الباقة على اليسار. يلتفّ عبر [Wrap] بلا overflow على العروض
  /// الضيّقة (شرائح الحالة تنتقل لسطر، ثم قائمة الباقة تحتها).
  Widget _filtersRow() {
    return Wrap(
      spacing: 8.w,
      runSpacing: 8.h,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _statusChip(label: 'الكل', value: null),
        _statusChip(label: 'نشط', value: 'active'),
        _statusChip(label: 'منتهٍ', value: 'expired'),
        _profileDropdown(),
      ],
    );
  }

  /// شريحة حالة أنيقة (chip): المحدّدة بخلفية زرقاء الصدارة ونصّ أبيض؛ غير
  /// المحدّدة بخلفية بيضاء وحدّ خفيف. الضغط يعيّن [_statusFilter] ويعيد البحث.
  Widget _statusChip({required String label, required String? value}) {
    final selected = _statusFilter == value;
    return Material(
      color: selected ? _kAccent : Colors.white,
      borderRadius: BorderRadius.circular(11.r),
      child: InkWell(
        borderRadius: BorderRadius.circular(11.r),
        onTap: () => _onStatusFilterChanged(value),
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 8.h),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(11.r),
            border: Border.all(
              color: selected
                  ? _kAccent
                  : _kMuted.withValues(alpha: 0.22),
            ),
          ),
          child: Text(
            label,
            style: GoogleFonts.cairo(
              fontSize: 12.sp,
              fontWeight: FontWeight.w800,
              color: selected ? Colors.white : _kInk,
            ),
          ),
        ),
      ),
    );
  }

  /// قائمة الباقة المنسدلة: «كل الباقات» + الباقات المميّزة المشتقّة من النتائج
  /// (`_profileOptions`). تُعطَّل بلطف إن لم تتوفّر باقات بعد (لا نتائج). اختيار
  /// عنصر يعيّن [_profileFilter] ويعيد البحث.
  Widget _profileDropdown() {
    final enabled = _profileOptions.isNotEmpty || _profileFilter != null;
    // نضمن أن القيمة المحدّدة ضمن عناصر القائمة (قد يبقى فلتر باقة بينما
    // انكمشت options مؤقّتاً أثناء التصفية بها).
    final items = <String>[
      if (_profileFilter != null && !_profileOptions.contains(_profileFilter))
        _profileFilter!,
      ..._profileOptions,
    ];
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 2.h),
      decoration: BoxDecoration(
        color: _profileFilter != null ? _kAccent : Colors.white,
        borderRadius: BorderRadius.circular(11.r),
        border: Border.all(
          color: _profileFilter != null
              ? _kAccent
              : _kMuted.withValues(alpha: 0.22),
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String?>(
          value: _profileFilter,
          isDense: true,
          borderRadius: BorderRadius.circular(12.r),
          icon: Icon(
            Icons.keyboard_arrow_down_rounded,
            size: 18.sp,
            color: _profileFilter != null ? Colors.white : _kMuted,
          ),
          dropdownColor: Colors.white,
          onChanged: enabled ? _onProfileFilterChanged : null,
          items: [
            DropdownMenuItem<String?>(
              value: null,
              child: Text(
                'كل الباقات',
                style: GoogleFonts.cairo(
                  fontSize: 12.sp,
                  fontWeight: FontWeight.w700,
                  color: _kInk,
                ),
              ),
            ),
            for (final p in items)
              DropdownMenuItem<String?>(
                value: p,
                child: Text(
                  p,
                  style: GoogleFonts.cairo(
                    fontSize: 12.sp,
                    fontWeight: FontWeight.w700,
                    color: _kInk,
                  ),
                ),
              ),
          ],
          // نعرض القيمة المحدّدة بلون مناسب للخلفية (أبيض عند التحديد).
          selectedItemBuilder: (context) {
            Widget sel(String text) => Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    text,
                    style: GoogleFonts.cairo(
                      fontSize: 12.sp,
                      fontWeight: FontWeight.w800,
                      color: _profileFilter != null ? Colors.white : _kInk,
                    ),
                  ),
                );
            return [
              sel('كل الباقات'),
              for (final p in items) sel(p),
            ];
          },
        ),
      ),
    );
  }

  // ─────────────────── منطقة نتائج البحث ───────────────────

  /// منطقة النتائج أسفل الحقل — تملأ المساحة المتاحة وتُمرَّر داخليّاً:
  /// استعلام فارغ ⇒ حالة إرشاد هادئة · تحميل ⇒ مؤشّر خفيف · خطأ ⇒ إعادة محاولة ·
  /// فراغ ⇒ لا مطابقين · نتائج ⇒ قائمة بطاقات مضغوطة قابلة للتمرير.
  Widget _searchResultsArea() {
    // حالة الإرشاد تظهر فقط حين لا نصّ **ولا** فلتر نشط (لا نجلب كل المشتركين).
    if (_searchQuery.isEmpty && !_hasActiveFilter) {
      return _searchHint();
    }
    if (_searchLoading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 30.w,
              height: 30.w,
              child: CircularProgressIndicator(strokeWidth: 2.6, color: _kAccent),
            ),
            SizedBox(height: 14.h),
            Text(
              'جاري البحث…',
              style: GoogleFonts.cairo(
                fontSize: 12.5.sp,
                fontWeight: FontWeight.w700,
                color: _kMuted,
              ),
            ),
          ],
        ),
      );
    }
    if (_searchError != null) {
      return SasErrorView(message: _searchError!, onRetry: _runSearch);
    }
    if (_searchResults.isEmpty) {
      return _searchEmpty();
    }
    return _searchResultsList();
  }

  /// حالة الإرشاد قبل الكتابة (أيقونة + نص هادئ).
  Widget _searchHint() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72.w,
            height: 72.w,
            decoration: BoxDecoration(
              color: _kAccent.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.manage_search_rounded,
                size: 36.sp, color: _kAccent),
          ),
          SizedBox(height: 16.h),
          Text(
            'اكتب للبحث عن مشترك',
            style: GoogleFonts.cairo(
              fontSize: 15.sp,
              fontWeight: FontWeight.w800,
              color: _kInk,
            ),
          ),
          SizedBox(height: 6.h),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 32.w),
            child: Text(
              'ابحث بالاسم أو اسم المستخدم أو الهاتف — تظهر النتائج هنا فوراً',
              textAlign: TextAlign.center,
              style: GoogleFonts.cairo(
                fontSize: 12.sp,
                fontWeight: FontWeight.w600,
                color: _kMuted,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// حالة لا نتائج مطابقة.
  Widget _searchEmpty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72.w,
            height: 72.w,
            decoration: BoxDecoration(
              color: _kMuted.withValues(alpha: 0.10),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.search_off_rounded, size: 36.sp, color: _kMuted),
          ),
          SizedBox(height: 16.h),
          Text(
            'لا مشتركون مطابقون للبحث/الفلتر',
            style: GoogleFonts.cairo(
              fontSize: 14.sp,
              fontWeight: FontWeight.w800,
              color: _kInk,
            ),
          ),
          SizedBox(height: 6.h),
          Text(
            'جرّب كلمة بحث أخرى أو عدّل فلتر الحالة/الباقة',
            textAlign: TextAlign.center,
            style: GoogleFonts.cairo(
              fontSize: 12.sp,
              fontWeight: FontWeight.w600,
              color: _kMuted,
            ),
          ),
        ],
      ),
    );
  }

  /// قائمة نتائج قابلة للتمرير داخليّاً ببطاقات مشترك مضغوطة.
  Widget _searchResultsList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.only(bottom: 8.h, right: 2.w, left: 2.w),
          child: Text(
            'نتائج مطابقة: ${_searchResults.length}',
            style: GoogleFonts.cairo(
              fontSize: 11.5.sp,
              fontWeight: FontWeight.w700,
              color: _kMuted,
            ),
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: EdgeInsets.only(bottom: 8.h),
            itemCount: _searchResults.length,
            separatorBuilder: (_, __) => SizedBox(height: 8.h),
            itemBuilder: (_, i) => _resultCard(_searchResults[i]),
          ),
        ),
      ],
    );
  }

  /// بطاقة نتيجة مشترك مضغوطة أنيقة: أفاتار بحالة + اسم/اسم مستخدم + شارة
  /// نشط/موقوف، وأسفلها شرائح (الباقة · الانتهاء · الهاتف · متصل). الضغط يفتح
  /// صفحة التفاصيل.
  Widget _resultCard(SasSubscriber s) {
    final statusColor =
        s.isActive ? AppTheme.successColor : AppTheme.errorColor;
    final phone = _phoneOf(s);
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(14.r),
      child: InkWell(
        borderRadius: BorderRadius.circular(14.r),
        onTap: () => _openSubscriber(s),
        child: Container(
          padding: EdgeInsets.all(12.w),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14.r),
            border: Border.all(color: _kAccent.withValues(alpha: 0.08)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF0B1B3A).withValues(alpha: 0.05),
                blurRadius: 10,
                spreadRadius: -6,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        width: 42.w,
                        height: 42.w,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              statusColor.withValues(alpha: 0.18),
                              statusColor.withValues(alpha: 0.08),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: statusColor.withValues(alpha: 0.22)),
                        ),
                        child: Icon(Icons.person_rounded,
                            color: statusColor, size: 20.sp),
                      ),
                      if (s.online)
                        Positioned(
                          right: -1,
                          bottom: -1,
                          child: Container(
                            width: 12.w,
                            height: 12.w,
                            decoration: BoxDecoration(
                              color: AppTheme.successColor,
                              shape: BoxShape.circle,
                              border:
                                  Border.all(color: Colors.white, width: 2.2),
                            ),
                          ),
                        ),
                    ],
                  ),
                  SizedBox(width: 12.w),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          s.username.isEmpty ? '-' : s.username,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.robotoMono(
                            fontSize: 13.sp,
                            fontWeight: FontWeight.w800,
                            color: _kInk,
                          ),
                        ),
                        if (s.fullName.isNotEmpty) ...[
                          SizedBox(height: 2.h),
                          Text(
                            s.fullName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.cairo(
                              fontSize: 12.sp,
                              color: _kMuted,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  SizedBox(width: 8.w),
                  SasStatusBadge(
                    label: s.isActive ? 'نشط' : 'موقوف',
                    color: statusColor,
                  ),
                ],
              ),
              SizedBox(height: 10.h),
              Wrap(
                spacing: 7.w,
                runSpacing: 6.h,
                children: [
                  _infoChip(Icons.inventory_2_rounded, s.profileLabel,
                      AppTheme.infoColor),
                  if (s.expiration != null && s.expiration!.trim().isNotEmpty)
                    _infoChip(Icons.event_busy_rounded, s.expiration!,
                        AppTheme.warningColor),
                  if (phone.isNotEmpty)
                    _infoChip(Icons.phone_rounded, phone,
                        AppTheme.successColor,
                        ltr: true),
                  if (s.online)
                    _infoChip(
                        Icons.wifi_rounded, 'متصل', AppTheme.successColor),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// رقم هاتف المشترك من الحقول الخام (إن توفّر).
  String _phoneOf(SasSubscriber s) =>
      (s.raw['phone'] ?? s.raw['phone_norm'] ?? s.raw['mobile'] ?? '')
          .toString()
          .trim();

  /// شريحة حقل صغيرة (أيقونة + نص) بلون موحّد. النص داخل سياق LTR عند احتوائه
  /// أرقاماً (هاتف) لمنع انقلاب ترتيبها في RTL.
  Widget _infoChip(IconData icon, String text, Color color,
      {bool ltr = false}) {
    final label = Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: GoogleFonts.cairo(
          fontSize: 10.5.sp, fontWeight: FontWeight.w700, color: color),
    );
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 9.w, vertical: 4.5.h),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8.r),
        border: Border.all(color: color.withValues(alpha: 0.20)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12.sp, color: color),
          SizedBox(width: 4.w),
          ltr
              ? Directionality(textDirection: TextDirection.ltr, child: label)
              : label,
        ],
      ),
    );
  }

}

/// تعريف عدّاد حلقي علوي:
/// عنوان + القيمة العددية + الحدّ الأقصى للنسبة (`null` ⇒ حلقة مرجعية ممتلئة بلا
/// نسبة، مثل الإجمالي) + علَم إظهار النسبة + لون المقياس + الأيقونة.
class _RingCounterDef {
  final String title;

  /// القيمة العددية (يصعد نحوها العدّاد).
  final num value;

  /// الحدّ الأقصى للنسبة؛ `null` ⇒ حلقة مرجعية ممتلئة (الإجمالي).
  final num? max;

  /// إظهار النسبة المئوية داخل الحلقة (عندما تكون ذات دلالة).
  final bool showPercent;

  final Color color;
  final IconData icon;

  const _RingCounterDef({
    required this.title,
    required this.value,
    required this.max,
    required this.showPercent,
    required this.color,
    required this.icon,
  });
}
