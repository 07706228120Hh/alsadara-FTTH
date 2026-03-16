import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'vps_auth_service.dart';

/// خدمة إقفال الفترات المحاسبية
/// التخزين: SharedPreferences بمفتاح closed_periods_{companyId}
class PeriodClosingService {
  PeriodClosingService._internal();
  static PeriodClosingService? _instance;
  static PeriodClosingService get instance =>
      _instance ??= PeriodClosingService._internal();

  /// الفترات المقفلة لكل شركة: companyId -> Set<"YYYY-MM">
  final Map<String, Set<String>> _closedPeriods = {};

  String _key(String companyId) => 'closed_periods_$companyId';

  String _periodKey(int year, int month) =>
      '$year-${month.toString().padLeft(2, '0')}';

  // ─── تحميل ───
  Future<void> loadClosedPeriods(String companyId) async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_key(companyId));
    if (json != null) {
      final List<dynamic> list = jsonDecode(json);
      _closedPeriods[companyId] = list.map((e) => e.toString()).toSet();
    } else {
      _closedPeriods[companyId] = {};
    }
  }

  // ─── حفظ ───
  Future<void> _save(String companyId) async {
    final prefs = await SharedPreferences.getInstance();
    final set = _closedPeriods[companyId] ?? {};
    await prefs.setString(_key(companyId), jsonEncode(set.toList()));
  }

  // ─── فحص ───
  bool isPeriodClosed(String companyId, int year, int month) {
    final set = _closedPeriods[companyId];
    if (set == null) return false;
    return set.contains(_periodKey(year, month));
  }

  bool isDateInClosedPeriod(String companyId, DateTime date) {
    return isPeriodClosed(companyId, date.year, date.month);
  }

  // ─── إقفال ───
  Future<bool> closePeriod(String companyId, int year, int month) async {
    _closedPeriods.putIfAbsent(companyId, () => {});
    _closedPeriods[companyId]!.add(_periodKey(year, month));
    await _save(companyId);
    return true;
  }

  // ─── إعادة فتح ───
  Future<bool> reopenPeriod(String companyId, int year, int month) async {
    _closedPeriods[companyId]?.remove(_periodKey(year, month));
    await _save(companyId);
    return true;
  }

  // ─── جلب كل الفترات المقفلة ───
  Set<String> getClosedPeriods(String companyId) {
    return _closedPeriods[companyId] ?? {};
  }

  // ═══════════════════════════════════════════════════════════════
  //  فحص + تحذير — يُستدعى من كل الصفحات قبل أي عملية
  // ═══════════════════════════════════════════════════════════════
  /// يعيد true إذا يمكن المتابعة، false إذا يجب الإلغاء
  static Future<bool> checkAndWarnIfClosed(
    BuildContext context, {
    required DateTime date,
    required String companyId,
  }) async {
    final svc = PeriodClosingService.instance;

    // تحميل إذا لم تُحمّل بعد
    if (!svc._closedPeriods.containsKey(companyId)) {
      await svc.loadClosedPeriods(companyId);
    }

    if (!svc.isDateInClosedPeriod(companyId, date)) {
      return true; // الفترة مفتوحة
    }

    final isAdmin =
        VpsAuthService.instance.currentUser?.isAdmin ?? false;

    if (!isAdmin) {
      // موظف عادي — منع
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'لا يمكن تنفيذ هذه العملية — الفترة ${date.year}/${date.month} مقفلة',
              style: GoogleFonts.cairo(),
            ),
            backgroundColor: const Color(0xFFE74C3C),
          ),
        );
      }
      return false;
    }

    // مدير الشركة — تحذير مع خيار المتابعة
    if (!context.mounted) return false;
    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: const Color(0xFF1E1E2E),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: Row(
            children: [
              const Icon(Icons.warning_amber_rounded,
                  color: Color(0xFFFF9800), size: 24),
              const SizedBox(width: 8),
              Text('فترة مقفلة',
                  style: GoogleFonts.cairo(
                      color: Colors.white, fontWeight: FontWeight.bold)),
            ],
          ),
          content: Text(
            'الفترة ${date.year}/${date.month} مقفلة.\n\n'
            'بصفتك مدير الشركة، يمكنك المتابعة.\nهل تريد الاستمرار؟',
            style: GoogleFonts.cairo(
                color: Colors.white70, fontSize: 14, height: 1.6),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('إلغاء',
                  style: GoogleFonts.cairo(color: Colors.white54)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF9800),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('متابعة',
                  style: GoogleFonts.cairo(
                      color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
    return proceed ?? false;
  }
}
