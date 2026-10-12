/// مجدوِل التذكير التلقائي لوحدة «وكيل الساس» — جهة سطح المكتب فقط.
///
/// يرسل رسالة واتساب تذكيرية للمشتركين قرب الانتهاء في موعد يومي محدَّد،
/// **أثناء فتح التطبيق** (وحدة الساس مفتوحة). لا باكند، لا بنية تحتية — كل
/// الحالة محلية في SharedPreferences.
///
/// ضمانات الإرسال الخارجي للعملاء:
///  • الافتراضي **معطَّل** (`sas_auto_reminder_enabled=false`) — لا إرسال إلا
///    بتفعيل صريح من المستخدم.
///  • منع التكرار اليومي عبر `sas_auto_reminder_last_run` (YYYY-MM-DD).
///  • لا يُرسل إلا بنمط واتساب **آلي** جاهز (server): إن كان النمط يدوياً
///    (app) أو الخادم غير جاهز → يُسجَّل السبب ويُتخطّى (لا يرمي).
///
/// يعمل عبر `Timer.periodic` كل ~60 ثانية: يفحص التفعيل + بلوغ الموعد اليومي +
/// عدم التشغيل اليوم، ثم ينفّذ التذكير مرّة واحدة. العزل (شركة + مالك + صلاحية
/// `sas_agent`) يفرضه الخادم؛ لا نمرّر أي هوية هنا.
library;

import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/sas_account.dart';
import '../models/sas_renewal.dart';
import '../whatsapp/whatsapp.dart';
import 'sas_agent_api_service.dart';

/// إعدادات التذكير التلقائي المحفوظة محلياً (خاصة بالساس).
class SasAutoReminderSettings {
  /// هل التذكير التلقائي مفعَّل؟ (افتراضي معطَّل — ضمان).
  final bool enabled;

  /// ساعة التشغيل اليومي (0–23).
  final int hour;

  /// دقيقة التشغيل اليومي (0–59).
  final int minute;

  /// عدد الأيام N قبل الانتهاء (يُجلب المرشّحون بـ`days=N`).
  final int days;

  const SasAutoReminderSettings({
    this.enabled = false,
    this.hour = 10,
    this.minute = 0,
    this.days = 1,
  });

  SasAutoReminderSettings copyWith({
    bool? enabled,
    int? hour,
    int? minute,
    int? days,
  }) =>
      SasAutoReminderSettings(
        enabled: enabled ?? this.enabled,
        hour: hour ?? this.hour,
        minute: minute ?? this.minute,
        days: days ?? this.days,
      );

  /// نصّ الموعد اليومي (HH:MM بصفرَين).
  String get timeLabel =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
}

/// سجلّ نتيجة تشغيل واحد (للعرض والتشخيص).
class SasReminderRunLog {
  /// وقت التشغيل.
  final DateTime at;

  /// إجمالي المرشّحين المجلوبين.
  final int total;

  /// عدد من أُرسل لهم فعلاً.
  final int sent;

  /// عدد من فشل إرسالهم.
  final int failed;

  /// ملاحظة/سبب (نجاح، أو سبب التخطّي: نمط يدوي، خادم غير جاهز، خطأ…).
  final String note;

  const SasReminderRunLog({
    required this.at,
    required this.total,
    required this.sent,
    required this.failed,
    required this.note,
  });

  Map<String, dynamic> toJson() => {
        'at': at.toIso8601String(),
        'total': total,
        'sent': sent,
        'failed': failed,
        'note': note,
      };

  factory SasReminderRunLog.fromJson(Map<String, dynamic> j) =>
      SasReminderRunLog(
        at: DateTime.tryParse((j['at'] ?? '').toString()) ?? DateTime.now(),
        total: (j['total'] as num?)?.toInt() ?? 0,
        sent: (j['sent'] as num?)?.toInt() ?? 0,
        failed: (j['failed'] as num?)?.toInt() ?? 0,
        note: (j['note'] ?? '').toString(),
      );
}

/// مجدوِل التذكير التلقائي (Singleton).
class SasReminderScheduler {
  SasReminderScheduler._();
  static final SasReminderScheduler instance = SasReminderScheduler._();

  // ── مفاتيح SharedPreferences (خاصة بالساس) ──
  static const kEnabled = 'sas_auto_reminder_enabled';
  static const kHour = 'sas_auto_reminder_hour';
  static const kMinute = 'sas_auto_reminder_minute';
  static const kDays = 'sas_auto_reminder_days';
  static const kLastRun = 'sas_auto_reminder_last_run';
  static const kLog = 'sas_auto_reminder_log';

  /// أقصى عدد سجلّات تشغيل محفوظة.
  static const _maxLogs = 20;

  /// فاصل فحص المؤقّت الدوري.
  static const _tickInterval = Duration(seconds: 60);

  final _api = SasAgentApiService.instance;

  Timer? _timer;
  SasAccount? _account;

  /// حارس ضدّ تداخل التنفيذ (إن تجاوز تشغيلٌ فاصلَ الفحص).
  bool _running = false;

  // ─────────────────────────── تحميل/حفظ الإعدادات ───────────────────────────

  /// يحمّل الإعدادات من SharedPreferences (بقيم افتراضية آمنة عند الغياب).
  Future<SasAutoReminderSettings> loadSettings() async {
    try {
      final sp = await SharedPreferences.getInstance();
      return SasAutoReminderSettings(
        enabled: sp.getBool(kEnabled) ?? false,
        hour: _clampInt(sp.getInt(kHour), 0, 23, 10),
        minute: _clampInt(sp.getInt(kMinute), 0, 59, 0),
        days: _clampInt(sp.getInt(kDays), 1, 365, 1),
      );
    } catch (_) {
      return const SasAutoReminderSettings();
    }
  }

  /// يحفظ الإعدادات ثم يعيد ضبط المؤقّت فوراً وفق الحالة الجديدة.
  Future<void> saveSettings(SasAutoReminderSettings s) async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setBool(kEnabled, s.enabled);
      await sp.setInt(kHour, s.hour);
      await sp.setInt(kMinute, s.minute);
      await sp.setInt(kDays, s.days);
    } catch (_) {
      // تفضيل محلي — فشله غير حرج.
    }
    // أعد تشغيل المؤقّت للحساب الحالي ليلتقط الإعدادات الجديدة فوراً.
    final acc = _account;
    if (acc != null) {
      start(acc);
    }
  }

  // ─────────────────────────── دورة الحياة ───────────────────────────

  /// يبدأ المجدوِل للحساب المعطى. آمن للاستدعاء المتكرّر (يُلغي المؤقّت السابق).
  void start(SasAccount account) {
    _account = account;
    _timer?.cancel();
    _timer = Timer.periodic(_tickInterval, (_) => _tick());
    // فحص فوري عند البدء (لا ننتظر دقيقة كاملة لو حان الموعد).
    _tick();
  }

  /// يوقف المجدوِل ويحرّر المؤقّت. لا يمسّ الإعدادات المحفوظة.
  void stop() {
    _timer?.cancel();
    _timer = null;
    _account = null;
  }

  // ─────────────────────────── سجلّ التشغيل ───────────────────────────

  /// يقرأ سجلّ آخر عمليات التشغيل (الأحدث أولاً).
  Future<List<SasReminderRunLog>> loadLog() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getString(kLog);
      if (raw == null || raw.isEmpty) return const [];
      final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
      return list.map(SasReminderRunLog.fromJson).toList();
    } catch (_) {
      return const [];
    }
  }

  /// تاريخ آخر تشغيل (YYYY-MM-DD) أو null إن لم يُشغَّل بعد.
  Future<String?> lastRunDate() async {
    try {
      final sp = await SharedPreferences.getInstance();
      return sp.getString(kLastRun);
    } catch (_) {
      return null;
    }
  }

  // ─────────────────────────── منطق المؤقّت ───────────────────────────

  Future<void> _tick() async {
    if (_running) return;
    final acc = _account;
    if (acc == null) return;

    _running = true;
    try {
      final settings = await loadSettings();
      if (!settings.enabled) return;

      final now = DateTime.now();
      final today = _dateKey(now);

      // بلوغ الموعد اليومي؟
      final due = DateTime(now.year, now.month, now.day, settings.hour,
          settings.minute);
      if (now.isBefore(due)) return;

      // أُشغِّل اليوم؟
      final last = await lastRunDate();
      if (last == today) return;

      // نثبّت الختم أولاً (منع التكرار اليومي حتى لو تعثّر الإرسال).
      await _setLastRun(today);
      await _execute(acc, settings, now);
    } catch (_) {
      // كل الأخطاء تُبتلع — المجدوِل لا يُسقط التطبيق أبداً.
    } finally {
      _running = false;
    }
  }

  /// ينفّذ التذكير: يجلب المرشّحين → يبني الرسائل → يُرسل آلياً إن كان النمط
  /// جاهزاً، وإلا يسجّل سبب التخطّي. يسجّل النتيجة في كل الحالات.
  Future<void> _execute(
    SasAccount acc,
    SasAutoReminderSettings settings,
    DateTime at,
  ) async {
    // 1) جلب المرشّحين قرب الانتهاء.
    List<SasRenewalCandidate> candidates;
    try {
      candidates = await _api.getRenewalCandidates(acc.id, days: settings.days);
    } catch (e) {
      await _appendLog(SasReminderRunLog(
        at: at,
        total: 0,
        sent: 0,
        failed: 0,
        note: 'تعذّر جلب المرشّحين: ${_clean(e)}',
      ));
      return;
    }

    if (candidates.isEmpty) {
      await _appendLog(SasReminderRunLog(
        at: at,
        total: 0,
        sent: 0,
        failed: 0,
        note: 'لا مشتركون قرب الانتهاء ضمن ${settings.days} يوم',
      ));
      return;
    }

    // 2) بناء الرسائل من قالب «تذكير قرب الانتهاء» لكل مستلِم ذي رقم صالح.
    final tpl = await LocalTemplateStore().byId(WaTemplateIds.reminder);
    if (tpl == null) {
      await _appendLog(SasReminderRunLog(
        at: at,
        total: candidates.length,
        sent: 0,
        failed: 0,
        note: 'لا قالب رسالة (reminder) — لم يُرسَل',
      ));
      return;
    }

    final messages = <WaOutgoing>[];
    for (final c in candidates) {
      final recipient = _recipientOf(c, settings.days);
      if (!recipient.sendable) continue; // رقم غير صالح — يُتخطّى.
      messages.add(WaOutgoing(
        recipient: recipient,
        text: tpl.render(recipient.templateVars),
      ));
    }

    if (messages.isEmpty) {
      await _appendLog(SasReminderRunLog(
        at: at,
        total: candidates.length,
        sent: 0,
        failed: 0,
        note: 'لا أرقام صالحة لواتساب',
      ));
      return;
    }

    // 3) الإرسال الآلي الصامت — فقط بنمط آلي جاهز.
    final sender = (await WaSettingsStore().load()).buildSender();
    try {
      if (!sender.capabilities.automated) {
        await _appendLog(SasReminderRunLog(
          at: at,
          total: candidates.length,
          sent: 0,
          failed: 0,
          note: 'النمط يدوي — الإرسال التلقائي لا يعمل (بدّله لـ«خادم»)',
        ));
        return;
      }
      final status = await sender.status();
      if (!status.ready) {
        await _appendLog(SasReminderRunLog(
          at: at,
          total: candidates.length,
          sent: 0,
          failed: 0,
          note: 'خادم واتساب غير جاهز — لم يُرسَل',
        ));
        return;
      }

      // إرسال جماعي صامت (بلا واجهة تفاعلية) — نستهلك البثّ حتى النهاية.
      WaBatchProgress? lastProgress;
      await for (final p in sender.sendBulk(messages)) {
        lastProgress = p;
      }
      final sent = lastProgress?.sent ?? 0;
      final failed = lastProgress?.failed ?? 0;
      await _appendLog(SasReminderRunLog(
        at: at,
        total: candidates.length,
        sent: sent,
        failed: failed,
        note: 'أُرسل تلقائياً عبر الخادم',
      ));
    } catch (e) {
      await _appendLog(SasReminderRunLog(
        at: at,
        total: candidates.length,
        sent: 0,
        failed: 0,
        note: 'فشل الإرسال: ${_clean(e)}',
      ));
    } finally {
      sender.dispose();
    }
  }

  /// يبني مستلِم واتساب من مرشّح تجديد (نفس نمط `sas_reminders_page._recipientOf`).
  WaRecipient _recipientOf(SasRenewalCandidate c, int days) => WaRecipient(
        name: c.displayName,
        rawPhone: c.phone ?? '',
        vars: {
          'username': c.username,
          if (c.profile != null) 'profile': c.profile!,
          if (c.expiry != null) 'expiration': (c.expiry ?? '').split(' ').first,
          'days': '$days',
        },
      );

  // ─────────────────────────── مساعدون ───────────────────────────

  Future<void> _setLastRun(String dateKey) async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(kLastRun, dateKey);
    } catch (_) {
      // فشل غير حرج — سيُعاد المحاولة عند الدورة التالية.
    }
  }

  /// يُضيف سجلّ تشغيل (الأحدث أولاً) ويقصّ القائمة على [_maxLogs].
  Future<void> _appendLog(SasReminderRunLog entry) async {
    try {
      final current = await loadLog();
      final updated = [entry, ...current].take(_maxLogs).toList();
      final sp = await SharedPreferences.getInstance();
      await sp.setString(
          kLog, jsonEncode(updated.map((e) => e.toJson()).toList()));
    } catch (_) {
      // سجلّ محلي — فشله غير حرج.
    }
  }

  String _dateKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  int _clampInt(int? v, int min, int max, int fallback) {
    if (v == null) return fallback;
    if (v < min) return min;
    if (v > max) return max;
    return v;
  }

  String _clean(Object e) =>
      e.toString().replaceFirst('Exception: ', '').trim();
}
