/// نافذة التحديث التلقائي
/// تبدأ تحميل وتثبيت التحديث تلقائياً عند اكتشاف إصدار جديد
library;

import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/auto_update_service.dart';

/// نافذة التحديث التلقائي - تبدأ التحميل فوراً
class UpdateDialog extends StatefulWidget {
  final UpdateInfo updateInfo;
  final String currentVersion;

  const UpdateDialog({
    super.key,
    required this.updateInfo,
    required this.currentVersion,
  });

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();

  /// عرض نافذة التحديث
  static Future<void> show(
      BuildContext context, UpdateInfo updateInfo, String currentVersion) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => PopScope(
        canPop: false,
        child: UpdateDialog(
          updateInfo: updateInfo,
          currentVersion: currentVersion,
        ),
      ),
    );
  }

  /// تخطي عرض التحديث وإغلاق الحوار
  static Future<void> _skipUpdate(
      BuildContext context, String version) async {
    await AutoUpdateService.instance.snoozeUpdate(version);
    if (context.mounted) Navigator.of(context).pop();
  }
}

class _UpdateDialogState extends State<UpdateDialog>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  double _downloadProgress = 0.0;
  _UpdatePhase _phase = _UpdatePhase.preparing;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();

    // ⚡ بدء التحميل والتثبيت تلقائياً
    Future.delayed(const Duration(milliseconds: 500), _startAutoUpdate);
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  /// بدء التحديث التلقائي (تحميل ← تثبيت)
  Future<void> _startAutoUpdate() async {
    // --- المرحلة 1: التحميل ---
    setState(() => _phase = _UpdatePhase.downloading);

    final filePath = await AutoUpdateService.instance.downloadUpdate(
      widget.updateInfo,
      onProgress: (progress) {
        if (mounted) setState(() => _downloadProgress = progress);
      },
    );

    if (filePath == null) {
      if (mounted) {
        setState(() {
          _phase = _UpdatePhase.error;
          _errorMessage = 'فشل في تحميل التحديث. تحقق من اتصال الإنترنت.';
        });
      }
      return;
    }

    // --- المرحلة 2: التثبيت ---
    if (mounted) setState(() => _phase = _UpdatePhase.installing);
    await Future.delayed(const Duration(seconds: 1));

    // سجّل محاولة التثبيت قبل exit(0) لمنع حلقة التحديث
    await AutoUpdateService.instance
        .markUpdateAttempted(widget.updateInfo.version);

    final success = await AutoUpdateService.instance.installUpdate(filePath);
    if (!success && mounted) {
      setState(() {
        _phase = _UpdatePhase.error;
        _errorMessage = Platform.isAndroid
            ? 'فشل في فتح ملف التحديث. تأكد من تفعيل "التثبيت من مصادر غير معروفة".'
            : 'فشل في تثبيت التحديث.';
      });
    } else if (Platform.isAndroid && mounted) {
      // على Android، المثبّت يفتح كنافذة خارجية - نغلق الحوار
      Navigator.pop(context);
    }
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String get _phaseTitle {
    switch (_phase) {
      case _UpdatePhase.preparing:
        return 'جاري التحضير...';
      case _UpdatePhase.downloading:
        return 'جاري تحميل التحديث';
      case _UpdatePhase.installing:
        return 'جاري تثبيت التحديث...';
      case _UpdatePhase.error:
        return 'حدث خطأ';
    }
  }

  IconData get _phaseIcon {
    switch (_phase) {
      case _UpdatePhase.preparing:
        return Icons.hourglass_top_rounded;
      case _UpdatePhase.downloading:
        return Icons.cloud_download_rounded;
      case _UpdatePhase.installing:
        return Platform.isAndroid
            ? Icons.install_mobile_rounded
            : Icons.install_desktop_rounded;
      case _UpdatePhase.error:
        return Icons.error_outline_rounded;
    }
  }

  Color get _phaseColor {
    switch (_phase) {
      case _UpdatePhase.preparing:
      case _UpdatePhase.downloading:
        return const Color(0xFF00E5FF);
      case _UpdatePhase.installing:
        return const Color(0xFF00E676);
      case _UpdatePhase.error:
        return const Color(0xFFFF5252);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Container(
        width: 420,
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0D1B2A), Color(0xFF1B263B)],
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // أيقونة المرحلة
            AnimatedBuilder(
              animation: _animationController,
              builder: (context, child) {
                return Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [
                        _phaseColor.withValues(alpha: 0.3),
                        _phaseColor.withValues(alpha: 0.1),
                      ],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: _phaseColor.withValues(
                            alpha: 0.2 + (_animationController.value * 0.15)),
                        blurRadius: 20,
                        spreadRadius: 3,
                      ),
                    ],
                  ),
                  child: Icon(_phaseIcon, color: _phaseColor, size: 36),
                );
              },
            ),
            const SizedBox(height: 20),

            // العنوان
            Text(
              _phaseTitle,
              style: GoogleFonts.cairo(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),

            // معلومات الإصدار
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('v${widget.currentVersion}',
                      style: GoogleFonts.cairo(
                          color: Colors.grey[400], fontSize: 13)),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Icon(Icons.arrow_forward_rounded,
                        color: Color(0xFF00E5FF), size: 16),
                  ),
                  Text(
                    'v${widget.updateInfo.version}',
                    style: GoogleFonts.cairo(
                      color: const Color(0xFF00E5FF),
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // --- محتوى حسب المرحلة ---

            if (_phase == _UpdatePhase.downloading) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: _downloadProgress,
                  backgroundColor: Colors.white.withValues(alpha: 0.1),
                  valueColor: const AlwaysStoppedAnimation(Color(0xFF00E5FF)),
                  minHeight: 8,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${(_downloadProgress * 100).toStringAsFixed(0)}%',
                    style: GoogleFonts.cairo(
                        color: const Color(0xFF00E5FF),
                        fontSize: 13,
                        fontWeight: FontWeight.bold),
                  ),
                  if (widget.updateInfo.downloadSize > 0)
                    Text(
                      _formatSize(widget.updateInfo.downloadSize),
                      style: GoogleFonts.cairo(
                          color: Colors.grey[500], fontSize: 12),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'لا تغلق التطبيق أثناء التحميل',
                style: GoogleFonts.cairo(color: Colors.grey[500], fontSize: 11),
              ),
              const SizedBox(height: 14),
              TextButton(
                onPressed: () => UpdateDialog._skipUpdate(
                    context, widget.updateInfo.version),
                child: Text('تخطي الآن (تذكيري لاحقاً)',
                    style: GoogleFonts.cairo(
                        color: Colors.grey[600], fontSize: 11)),
              ),
            ] else if (_phase == _UpdatePhase.preparing ||
                _phase == _UpdatePhase.installing) ...[
              const SizedBox(
                width: 32,
                height: 32,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  valueColor: AlwaysStoppedAnimation(Color(0xFF00E5FF)),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                _phase == _UpdatePhase.installing
                    ? (Platform.isAndroid
                        ? 'جاري فتح مثبّت التحديث...'
                        : 'سيتم إعادة تشغيل التطبيق تلقائياً...')
                    : 'جاري التحضير...',
                style: GoogleFonts.cairo(color: Colors.grey[400], fontSize: 12),
              ),
              if (_phase == _UpdatePhase.preparing) ...[
                const SizedBox(height: 14),
                TextButton(
                  onPressed: () => UpdateDialog._skipUpdate(
                      context, widget.updateInfo.version),
                  child: Text('تخطي الآن (تذكيري لاحقاً)',
                      style: GoogleFonts.cairo(
                          color: Colors.grey[600], fontSize: 11)),
                ),
              ],
            ] else if (_phase == _UpdatePhase.error) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF5252).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: const Color(0xFFFF5252).withValues(alpha: 0.3)),
                ),
                child: Text(
                  _errorMessage,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.cairo(
                      color: const Color(0xFFFF9E9E), fontSize: 13),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                          side: BorderSide(
                              color: Colors.white.withValues(alpha: 0.2)),
                        ),
                      ),
                      child: Text('تخطي',
                          style: GoogleFonts.cairo(
                              color: Colors.grey[400],
                              fontWeight: FontWeight.w600)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        setState(() {
                          _phase = _UpdatePhase.preparing;
                          _downloadProgress = 0;
                        });
                        _startAutoUpdate();
                      },
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      label: Text('إعادة المحاولة',
                          style:
                              GoogleFonts.cairo(fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00E5FF),
                        foregroundColor: const Color(0xFF0D1B2A),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                        elevation: 0,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

enum _UpdatePhase { preparing, downloading, installing, error }

/// مدير التحديثات - يُفحص ويُحدّث تلقائياً عند بدء التطبيق
class UpdateManager {
  static Future<void> checkAndShowUpdateDialog(BuildContext context) async {
    // التحديث التلقائي يعمل على Windows فقط
    // Android: التحديث يكون يدوياً عبر APK — تجنب حظر الواجهة
    if (!Platform.isWindows) return;
    try {
      final updateInfo = await AutoUpdateService.instance.checkForUpdate();

      if (updateInfo != null &&
          updateInfo.downloadUrl.isNotEmpty &&
          context.mounted) {
        final currentVersion =
            await AutoUpdateService.instance.getCurrentVersion();
        await UpdateDialog.show(context, updateInfo, currentVersion);
      }
    } catch (e) {
      debugPrint('❌ خطأ في التحقق من التحديثات: $e');
    }
  }
}
