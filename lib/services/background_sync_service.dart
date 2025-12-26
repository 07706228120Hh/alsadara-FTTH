import 'dart:async';
import 'package:flutter/material.dart';
import 'sync_service.dart';
import 'local_database_service.dart';

/// حالة المزامنة في الخلفية
enum BackgroundSyncStatus {
  idle,
  syncing,
  completed,
  failed,
}

/// معلومات تقدم المزامنة
class BackgroundSyncProgress {
  final BackgroundSyncStatus status;
  final String stage;
  final int current;
  final int total;
  final String message;
  final int fetchedCount;
  final String? error;
  final DateTime? completedAt;

  BackgroundSyncProgress({
    required this.status,
    this.stage = '',
    this.current = 0,
    this.total = 0,
    this.message = '',
    this.fetchedCount = 0,
    this.error,
    this.completedAt,
  });

  double get percentage => total > 0 ? (current / total) * 100 : 0;

  BackgroundSyncProgress copyWith({
    BackgroundSyncStatus? status,
    String? stage,
    int? current,
    int? total,
    String? message,
    int? fetchedCount,
    String? error,
    DateTime? completedAt,
  }) {
    return BackgroundSyncProgress(
      status: status ?? this.status,
      stage: stage ?? this.stage,
      current: current ?? this.current,
      total: total ?? this.total,
      message: message ?? this.message,
      fetchedCount: fetchedCount ?? this.fetchedCount,
      error: error ?? this.error,
      completedAt: completedAt ?? this.completedAt,
    );
  }
}

/// خدمة المزامنة في الخلفية
class BackgroundSyncService extends ChangeNotifier {
  static final BackgroundSyncService _instance =
      BackgroundSyncService._internal();
  static BackgroundSyncService get instance => _instance;

  BackgroundSyncService._internal();

  final SyncService _syncService = SyncService();
  final LocalDatabaseService _db = LocalDatabaseService.instance;

  BackgroundSyncProgress _progress = BackgroundSyncProgress(
    status: BackgroundSyncStatus.idle,
  );

  BackgroundSyncProgress get progress => _progress;
  bool get isSyncing => _progress.status == BackgroundSyncStatus.syncing;
  bool get hasCompleted => _progress.status == BackgroundSyncStatus.completed;
  bool get hasFailed => _progress.status == BackgroundSyncStatus.failed;

  // Callback عند اكتمال المزامنة
  Function(bool success, String message)? onSyncComplete;

  /// بدء جلب البيانات في الخلفية
  Future<void> startSync({
    required String token,
    bool fetchSubscriptions = true,
    bool fetchDetails = false,
    bool fetchAddresses = false,
  }) async {
    if (isSyncing) {
      print('⚠️ المزامنة قيد التشغيل بالفعل');
      return;
    }

    _updateProgress(BackgroundSyncProgress(
      status: BackgroundSyncStatus.syncing,
      message: 'جاري بدء المزامنة...',
    ));

    try {
      await _db.initialize();

      if (fetchSubscriptions) {
        // جلب الاشتراكات
        final result = await _syncService.fullSync(
          token: token,
          onProgress: (syncProgress) {
            _updateProgress(_progress.copyWith(
              stage: syncProgress.stage,
              current: syncProgress.current,
              total: syncProgress.total,
              message: syncProgress.message,
              fetchedCount: syncProgress.fetchedCount,
            ));
          },
          fetchSubscribers: true,
          fetchPhones: false,
          fetchAddresses: false,
        );

        if (!result.success) {
          _handleFailure(result.error ?? result.message);
          return;
        }

        _updateProgress(_progress.copyWith(
          fetchedCount: result.subscribersCount,
        ));
      }

      if (fetchDetails) {
        // جلب أرقام الهواتف فقط
        final detailsResult = await _syncService.fetchPhoneNumbers(
          token: token,
          onProgress: (syncProgress) {
            _updateProgress(_progress.copyWith(
              stage: syncProgress.stage,
              current: syncProgress.current,
              total: syncProgress.total,
              message: syncProgress.message,
            ));
          },
        );

        if (!detailsResult.success) {
          _handleFailure(detailsResult.error ?? detailsResult.message);
          return;
        }
      }

      if (fetchAddresses) {
        // جلب تفاصيل الاشتراكات (FDT، FAT، MAC، IP)
        final addressesResult = await _syncService.fetchSubscriptionAddresses(
          token: token,
          onProgress: (syncProgress) {
            _updateProgress(_progress.copyWith(
              stage: syncProgress.stage,
              current: syncProgress.current,
              total: syncProgress.total,
              message: syncProgress.message,
            ));
          },
        );

        if (!addressesResult.success) {
          _handleFailure(addressesResult.error ?? addressesResult.message);
          return;
        }
      }

      // اكتمال بنجاح
      _updateProgress(BackgroundSyncProgress(
        status: BackgroundSyncStatus.completed,
        message: 'تم جلب البيانات بنجاح ✅',
        fetchedCount: _progress.fetchedCount,
        completedAt: DateTime.now(),
      ));

      onSyncComplete?.call(
          true, 'تم جلب ${_progress.fetchedCount} مشترك بنجاح');
    } catch (e) {
      _handleFailure(e.toString());
    }
  }

  /// إلغاء المزامنة
  void cancelSync() {
    _syncService.cancelSync();
    _updateProgress(BackgroundSyncProgress(
      status: BackgroundSyncStatus.idle,
      message: 'تم إلغاء المزامنة',
    ));
  }

  /// إعادة تعيين الحالة
  void reset() {
    _updateProgress(BackgroundSyncProgress(
      status: BackgroundSyncStatus.idle,
    ));
  }

  void _handleFailure(String error) {
    _updateProgress(BackgroundSyncProgress(
      status: BackgroundSyncStatus.failed,
      message: 'فشل الجلب',
      error: error,
    ));
    onSyncComplete?.call(false, error);
  }

  void _updateProgress(BackgroundSyncProgress newProgress) {
    _progress = newProgress;
    notifyListeners();
  }
}

/// Widget لعرض حالة المزامنة في أي مكان
class BackgroundSyncIndicator extends StatelessWidget {
  final bool showOnlyWhenSyncing;
  final bool mini;

  const BackgroundSyncIndicator({
    super.key,
    this.showOnlyWhenSyncing = true,
    this.mini = false,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: BackgroundSyncService.instance,
      builder: (context, _) {
        final progress = BackgroundSyncService.instance.progress;

        if (showOnlyWhenSyncing &&
            progress.status != BackgroundSyncStatus.syncing) {
          return const SizedBox.shrink();
        }

        if (mini) {
          return _buildMiniIndicator(progress);
        }

        return _buildFullIndicator(context, progress);
      },
    );
  }

  Widget _buildMiniIndicator(BackgroundSyncProgress progress) {
    if (progress.status != BackgroundSyncStatus.syncing) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.blue.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 6),
          Text(
            '${progress.percentage.toStringAsFixed(0)}%',
            style: const TextStyle(fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _buildFullIndicator(
      BuildContext context, BackgroundSyncProgress progress) {
    Color statusColor;
    IconData statusIcon;

    switch (progress.status) {
      case BackgroundSyncStatus.syncing:
        statusColor = Colors.blue;
        statusIcon = Icons.sync;
        break;
      case BackgroundSyncStatus.completed:
        statusColor = Colors.green;
        statusIcon = Icons.check_circle;
        break;
      case BackgroundSyncStatus.failed:
        statusColor = Colors.red;
        statusIcon = Icons.error;
        break;
      case BackgroundSyncStatus.idle:
        statusColor = Colors.grey;
        statusIcon = Icons.cloud_off;
    }

    return Card(
      color: statusColor.withValues(alpha: 0.1),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(statusIcon, color: statusColor, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    progress.message,
                    style: TextStyle(color: statusColor),
                  ),
                ),
                if (progress.status == BackgroundSyncStatus.syncing)
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () =>
                        BackgroundSyncService.instance.cancelSync(),
                    tooltip: 'إلغاء',
                  ),
              ],
            ),
            if (progress.status == BackgroundSyncStatus.syncing) ...[
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: progress.total > 0
                    ? progress.current / progress.total
                    : null,
                backgroundColor: Colors.grey[300],
                valueColor: AlwaysStoppedAnimation<Color>(statusColor),
              ),
              const SizedBox(height: 4),
              Text(
                '${progress.percentage.toStringAsFixed(0)}%',
                style: TextStyle(fontSize: 12, color: statusColor),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
