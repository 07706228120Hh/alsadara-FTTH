/// نافذة التحديث التلقائي
/// تعرض معلومات التحديث الجديد مع خيارات التحميل والتثبيت
library;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/auto_update_service.dart';

/// نافذة إشعار التحديث
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
      builder: (context) => UpdateDialog(
        updateInfo: updateInfo,
        currentVersion: currentVersion,
      ),
    );
  }
}

class _UpdateDialogState extends State<UpdateDialog>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  bool _isDownloading = false;
  bool _isInstalling = false;
  double _downloadProgress = 0.0;
  String _statusMessage = '';

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _downloadAndInstall() async {
    setState(() {
      _isDownloading = true;
      _statusMessage = 'جاري تحميل التحديث...';
    });

    final filePath = await AutoUpdateService.instance.downloadUpdate(
      widget.updateInfo,
      onProgress: (progress) {
        setState(() {
          _downloadProgress = progress;
          _statusMessage =
              'جاري التحميل... ${(progress * 100).toStringAsFixed(0)}%';
        });
      },
    );

    if (filePath != null) {
      setState(() {
        _isDownloading = false;
        _isInstalling = true;
        _statusMessage = 'جاري تثبيت التحديث...';
      });

      await AutoUpdateService.instance.installUpdate(filePath);
    } else {
      setState(() {
        _isDownloading = false;
        _statusMessage = 'فشل في تحميل التحديث';
      });
    }
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Container(
        width: 450,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF0D1B2A),
              Color(0xFF1B263B),
            ],
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // أيقونة التحديث المتحركة
            AnimatedBuilder(
              animation: _animationController,
              builder: (context, child) {
                return Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [
                        const Color(0xFF00E5FF).withValues(alpha: 0.3),
                        const Color(0xFF00E5FF).withValues(alpha: 0.1),
                      ],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF00E5FF).withValues(
                            alpha: 0.3 + (_animationController.value * 0.2)),
                        blurRadius: 20,
                        spreadRadius: 5,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.system_update_rounded,
                    color: Color(0xFF00E5FF),
                    size: 40,
                  ),
                );
              },
            ),
            const SizedBox(height: 20),

            // العنوان
            Text(
              '🎉 تحديث جديد متاح!',
              style: GoogleFonts.cairo(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),

            // معلومات الإصدار
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'v${widget.currentVersion}',
                    style: GoogleFonts.cairo(
                      color: Colors.grey[400],
                      fontSize: 14,
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Icon(Icons.arrow_forward,
                        color: Color(0xFF00E5FF), size: 16),
                  ),
                  Text(
                    'v${widget.updateInfo.version}',
                    style: GoogleFonts.cairo(
                      color: const Color(0xFF00E5FF),
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // حجم التحميل
            if (widget.updateInfo.downloadSize > 0)
              Text(
                'حجم التحديث: ${_formatSize(widget.updateInfo.downloadSize)}',
                style: GoogleFonts.cairo(
                  color: Colors.grey[400],
                  fontSize: 12,
                ),
              ),
            const SizedBox(height: 16),

            // ملاحظات الإصدار
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
              ),
              constraints: const BoxConstraints(maxHeight: 150),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '📝 ما الجديد:',
                      style: GoogleFonts.cairo(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      widget.updateInfo.releaseNotes,
                      style: GoogleFonts.cairo(
                        color: Colors.grey[300],
                        fontSize: 13,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // شريط التقدم أثناء التحميل
            if (_isDownloading || _isInstalling) ...[
              Column(
                children: [
                  LinearProgressIndicator(
                    value: _isInstalling ? null : _downloadProgress,
                    backgroundColor: Colors.white.withValues(alpha: 0.1),
                    valueColor:
                        const AlwaysStoppedAnimation<Color>(Color(0xFF00E5FF)),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _statusMessage,
                    style: GoogleFonts.cairo(
                      color: Colors.grey[400],
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ] else ...[
              // أزرار الإجراء
              Row(
                children: [
                  // زر التخطي
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                              color: Colors.white.withValues(alpha: 0.2)),
                        ),
                      ),
                      child: Text(
                        'لاحقاً',
                        style: GoogleFonts.cairo(
                          color: Colors.grey[400],
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // زر التحديث
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: widget.updateInfo.downloadUrl.isNotEmpty
                          ? _downloadAndInstall
                          : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00E5FF),
                        foregroundColor: const Color(0xFF0D1B2A),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.download_rounded, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            'تحديث الآن',
                            style: GoogleFonts.cairo(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                        ],
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

/// مدير التحديثات - للتحقق عند بدء التطبيق
class UpdateManager {
  static Future<void> checkAndShowUpdateDialog(BuildContext context) async {
    try {
      final updateInfo = await AutoUpdateService.instance.checkForUpdate();

      if (updateInfo != null && context.mounted) {
        final currentVersion =
            await AutoUpdateService.instance.getCurrentVersion();
        await UpdateDialog.show(context, updateInfo, currentVersion);
      }
    } catch (e) {
      debugPrint('❌ خطأ في التحقق من التحديثات: $e');
    }
  }
}
