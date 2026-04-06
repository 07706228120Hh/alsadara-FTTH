/// صفحة التخزين المحلي للمشتركين
/// تتيح للمستخدم استيراد وإدارة بيانات المشتركين محلياً باستخدام SQLite
library;

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import '../services/local_database_service.dart';
import '../services/sync_service.dart';
import '../services/sync_settings_service.dart';
import '../services/auth_service.dart';
import '../services/background_sync_service.dart';
import '../services/vps_sync_service.dart';
import '../permissions/permissions.dart';
import 'local_subscriber_details_page.dart';

class LocalStoragePage extends StatefulWidget {
  final String? authToken;

  const LocalStoragePage({
    super.key,
    this.authToken,
  });

  @override
  State<LocalStoragePage> createState() => _LocalStoragePageState();
}

class _LocalStoragePageState extends State<LocalStoragePage> {
  final LocalDatabaseService _db = LocalDatabaseService.instance;
  final SyncService _syncService = SyncService();
  final SyncSettingsService _settingsService = SyncSettingsService.instance;
  final BackgroundSyncService _backgroundSync = BackgroundSyncService.instance;
  final VpsSyncService _vpsSyncService = VpsSyncService.instance;

  bool _isLoading = false;
  bool _isSyncing = false;
  bool _isVpsSyncing = false;

  // إحصائيات
  int _subscribersCount = 0;
  int _phonesCount = 0;
  int _addressesCount = 0;
  int _subscribersWithoutDetails = 0;
  DateTime? _lastSyncTime;

  // بيانات المزامنة
  String _syncStage = '';
  int _syncCurrent = 0;
  int _syncTotal = 0;
  String _syncMessage = '';

  // خيارات الجلب
  final bool _fetchSubscribers = true;
  final bool _fetchPhones = false; // يُجلب عبر زر "رقم الهاتف"
  final bool _fetchAddresses = false; // يُجلب عبر زر "رقم الهاتف"

  // قائمة المشتركين
  List<Map<String, dynamic>> _subscribers = [];
  List<Map<String, dynamic>> _filteredSubscribers = [];

  // البحث والفلترة
  final TextEditingController _searchController = TextEditingController();
  String? _selectedZone;
  String? _selectedStatus;
  String _sortBy = 'name';
  bool _sortAscending = true;
  bool _showFilter = false; // إظهار/إخفاء بطاقة الفلترة
  bool _showOnlyWithoutPhone = false; // عرض فقط بدون أرقام
  bool _showOnlyWithoutDetails = false; // عرض فقط بدون تفاصيل
  bool _showImportCard = false; // إظهار/إخفاء بطاقة الاستيراد
  bool _hasImportPermission = false; // صلاحية زر الاستيراد

  // فلاتر الجدول المباشرة
  final TextEditingController _nameFilterController = TextEditingController();
  final TextEditingController _phoneFilterController = TextEditingController();
  final TextEditingController _usernameFilterController =
      TextEditingController();

  // فلاتر المنطقة و FAT - تحديد متعدد
  final Set<String> _selectedZones = {};
  final Set<String> _selectedFATs = {};
  List<String> _availableFATs = [];

  // فلاتر الحالة والباقة - تحديد متعدد
  final Set<String> _selectedStatuses = {};
  final Set<String> _selectedProfiles = {};
  List<String> _availableStatuses = [];
  List<String> _availableProfiles = [];

  // فلتر التاريخ - من وإلى
  DateTime? _dateFrom;
  DateTime? _dateTo;

  // الترتيب حسب العمود
  String _tableSortColumn = 'name'; // العمود المحدد للترتيب
  bool _tableSortAscending = true; // ترتيب تصاعدي أو تنازلي

  // قوائم الفلترة
  List<String> _zones = [];
  final List<String> _statuses = ['active', 'inactive', 'expired', 'suspended'];

  // متغيرات التحديد والحذف
  bool _isSelectionMode = false;
  final Set<String> _selectedIds = {};

  @override
  void initState() {
    super.initState();
    _vpsSyncService.addListener(_onVpsSyncChanged);
    _initializeAndLoad();
    _loadPermissions();
  }

  @override
  void dispose() {
    _vpsSyncService.removeListener(_onVpsSyncChanged);
    _searchController.dispose();
    _nameFilterController.dispose();
    _phoneFilterController.dispose();
    _usernameFilterController.dispose();
    super.dispose();
  }

  /// يُستدعى عند تغيّر حالة VpsSyncService
  void _onVpsSyncChanged() {
    if (!mounted) return;
    final wasSyncing = _isVpsSyncing;
    final nowSyncing = _vpsSyncService.isSyncing;

    setState(() => _isVpsSyncing = nowSyncing);

    // عند انتهاء المزامنة بنجاح — إعادة تحميل البيانات
    if (wasSyncing && !nowSyncing && _vpsSyncService.lastResult?.success == true) {
      _refreshAfterVpsSync();
    }
  }

  /// إعادة تحميل البيانات بعد مزامنة VPS ناجحة
  Future<void> _refreshAfterVpsSync() async {
    await _db.refresh();
    if (!mounted) return;
    await _loadStatistics();
    await _loadSubscribers();
    await _loadFilters();
  }

  /// تنسيق وقت المزامنة
  String _formatSyncTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);
    if (diff.inMinutes < 1) return 'الآن';
    if (diff.inMinutes < 60) return 'منذ ${diff.inMinutes} دقيقة';
    if (diff.inHours < 24) return 'منذ ${diff.inHours} ساعة';
    return '${time.day}/${time.month} ${time.hour}:${time.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _loadPermissions() async {
    // V2: استخدام PermissionManager مباشرة
    final hasV2Import = PermissionManager.instance.canImport('local_storage');
    if (mounted) {
      setState(() {
        _hasImportPermission = hasV2Import;
      });
    }
  }

  Future<void> _initializeAndLoad() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      await _db.initialize();
      if (!mounted) return;
      await _loadStatistics();
      await _loadSubscribers();
      await _loadFilters();
    } catch (e) {
      debugPrint('❌ خطأ في التهيئة');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }

    // مزامنة تلقائية من VPS عند فتح الصفحة (إذا مرّ وقت كافٍ)
    _vpsSyncService.syncIfNeeded();
  }

  Future<void> _loadStatistics() async {
    final stats = await _db.getStatistics();
    final lastSync = await _db.getLastSyncTime();
    final detailsStats = await _db.getDetailsStats();
    if (!mounted) return;

    setState(() {
      _subscribersCount = stats['subscribers'] ?? 0;
      _phonesCount = stats['phones'] ?? 0;
      _addressesCount = stats['addresses'] ?? 0;
      _subscribersWithoutDetails = detailsStats['without_details'] ?? 0;
      _lastSyncTime = lastSync;
    });
  }

  Future<void> _loadSubscribers() async {
    final subscribers = await _db.searchSubscribers(
      query: _searchController.text,
      zone: _selectedZone,
      status: _selectedStatus,
      sortBy: _sortBy,
      ascending: _sortAscending,
    );
    if (!mounted) return;

    setState(() {
      _subscribers = subscribers;
      // تطبيق الفلاتر
      var filtered = subscribers;

      // فلتر بدون رقم هاتف
      if (_showOnlyWithoutPhone) {
        filtered = filtered.where((sub) {
          final phone = sub['phone']?.toString() ?? '';
          return phone.isEmpty;
        }).toList();
      }

      // فلتر بدون تفاصيل - استخدام حقل details_fetched
      if (_showOnlyWithoutDetails) {
        filtered = filtered.where((sub) {
          return sub['details_fetched'] != true;
        }).toList();
      }

      // فلتر الاسم من الجدول
      final nameFilter = _nameFilterController.text.trim().toLowerCase();
      if (nameFilter.isNotEmpty) {
        filtered = filtered.where((sub) {
          final name = (sub['display_name'] ?? sub['username'] ?? '')
              .toString()
              .toLowerCase();
          return name.contains(nameFilter);
        }).toList();
      }

      // فلتر الهاتف من الجدول
      final phoneFilter = _phoneFilterController.text.trim();
      if (phoneFilter.isNotEmpty) {
        filtered = filtered.where((sub) {
          final phone = (sub['phone'] ?? '').toString();
          return phone.contains(phoneFilter);
        }).toList();
      }

      // فلتر المنطقة - تحديد متعدد
      if (_selectedZones.isNotEmpty) {
        filtered = filtered.where((sub) {
          final zone = (sub['zone_name'] ?? '').toString();
          return _selectedZones.contains(zone);
        }).toList();
      }

      // فلتر FAT - تحديد متعدد
      if (_selectedFATs.isNotEmpty) {
        filtered = filtered.where((sub) {
          final fat = (sub['fat_name'] ?? '').toString();
          return _selectedFATs.contains(fat);
        }).toList();
      }

      // فلتر الحالة - تحديد متعدد
      if (_selectedStatuses.isNotEmpty) {
        filtered = filtered.where((sub) {
          final status = (sub['status'] ?? '').toString();
          return _selectedStatuses.contains(status);
        }).toList();
      }

      // فلتر الباقة - تحديد متعدد
      if (_selectedProfiles.isNotEmpty) {
        filtered = filtered.where((sub) {
          final profile = (sub['profile_name'] ?? '').toString();
          return _selectedProfiles.contains(profile);
        }).toList();
      }

      // فلتر التاريخ - من وإلى
      if (_dateFrom != null || _dateTo != null) {
        filtered = filtered.where((sub) {
          final expiresStr = (sub['expires'] ?? '').toString();
          if (expiresStr.isEmpty) return false;
          try {
            final expiresDate = DateTime.parse(expiresStr);
            if (_dateFrom != null && expiresDate.isBefore(_dateFrom!)) {
              return false;
            }
            if (_dateTo != null &&
                expiresDate.isAfter(_dateTo!.add(const Duration(days: 1)))) {
              return false;
            }
            return true;
          } catch (_) {
            return false;
          }
        }).toList();
      }

      // فلتر اسم المستخدم من الجدول
      final usernameFilter =
          _usernameFilterController.text.trim().toLowerCase();
      if (usernameFilter.isNotEmpty) {
        filtered = filtered.where((sub) {
          final username = (sub['username'] ?? '').toString().toLowerCase();
          return username.contains(usernameFilter);
        }).toList();
      }

      // تطبيق الترتيب حسب العمود المحدد
      _applySorting(filtered);

      _filteredSubscribers = filtered;
    });
  }

  /// تطبيق الترتيب على القائمة
  void _applySorting(List<Map<String, dynamic>> list) {
    list.sort((a, b) {
      int result = 0;
      switch (_tableSortColumn) {
        case 'name':
          final nameA = (a['display_name'] ?? a['username'] ?? '')
              .toString()
              .toLowerCase();
          final nameB = (b['display_name'] ?? b['username'] ?? '')
              .toString()
              .toLowerCase();
          result = nameA.compareTo(nameB);
          break;
        case 'phone':
          final phoneA = (a['phone'] ?? '').toString();
          final phoneB = (b['phone'] ?? '').toString();
          result = phoneA.compareTo(phoneB);
          break;
        case 'zone':
          final zoneA = (a['zone_name'] ?? '').toString().toLowerCase();
          final zoneB = (b['zone_name'] ?? '').toString().toLowerCase();
          result = zoneA.compareTo(zoneB);
          break;
        case 'fat':
          final fatA = (a['fat_name'] ?? '').toString().toLowerCase();
          final fatB = (b['fat_name'] ?? '').toString().toLowerCase();
          result = fatA.compareTo(fatB);
          break;
        case 'status':
          final statusA = (a['status'] ?? '').toString();
          final statusB = (b['status'] ?? '').toString();
          result = statusA.compareTo(statusB);
          break;
        case 'expires':
          final expiresA = a['expires']?.toString() ?? '';
          final expiresB = b['expires']?.toString() ?? '';
          result = expiresA.compareTo(expiresB);
          break;
        case 'profile':
          final profileA = (a['profile_name'] ?? '').toString().toLowerCase();
          final profileB = (b['profile_name'] ?? '').toString().toLowerCase();
          result = profileA.compareTo(profileB);
          break;
        case 'username':
          final userA = (a['username'] ?? '').toString().toLowerCase();
          final userB = (b['username'] ?? '').toString().toLowerCase();
          result = userA.compareTo(userB);
          break;
        default:
          result = 0;
      }
      return _tableSortAscending ? result : -result;
    });
  }

  /// تغيير ترتيب العمود
  void _toggleSort(String column) {
    setState(() {
      if (_tableSortColumn == column) {
        _tableSortAscending = !_tableSortAscending;
      } else {
        _tableSortColumn = column;
        _tableSortAscending = true;
      }
    });
    _loadSubscribers();
  }

  /// تطبيق الفلاتر
  void _applyFilters() {
    _loadSubscribers();
  }

  Future<void> _loadFilters() async {
    final zones = await _db.getDistinctZones();
    final fats = await _db.getDistinctFATs();
    final statuses = await _db.getDistinctStatuses();
    final profiles = await _db.getDistinctProfiles();
    if (!mounted) return;
    setState(() {
      _zones = zones;
      _availableFATs = fats;
      _availableStatuses = statuses;
      _availableProfiles = profiles;
    });
  }

  /// بدء المزامنة الكاملة
  Future<void> _startFullSync() async {
    // التحقق من التوكن
    String? token = widget.authToken;
    if (token == null || token.isEmpty) {
      token = await AuthService.instance.getAccessToken();
    }

    if (token == null || token.isEmpty) {
      _showMessage('يرجى تسجيل الدخول أولاً', isError: true);
      return;
    }

    // التحقق من اختيار شيء واحد على الأقل
    if (!_fetchSubscribers && !_fetchPhones && !_fetchAddresses) {
      _showMessage('يرجى اختيار نوع بيانات واحد على الأقل', isError: true);
      return;
    }

    setState(() {
      _isSyncing = true;
      _syncStage = '';
      _syncCurrent = 0;
      _syncTotal = 0;
      _syncMessage = 'جاري البدء...';
      // مسح القائمة للبدء من جديد
      _filteredSubscribers = [];
    });

    final result = await _syncService.fullSync(
      token: token,
      fetchSubscribers: _fetchSubscribers,
      fetchPhones: _fetchPhones,
      fetchAddresses: _fetchAddresses,
      onProgress: (progress) {
        if (!mounted) return;
        setState(() {
          _syncStage = progress.stage;
          _syncCurrent = progress.current;
          _syncTotal = progress.total;
          _syncMessage = progress.message;

          // عرض البيانات الجديدة مباشرة أثناء الجلب
          if (progress.newItems != null && progress.newItems!.isNotEmpty) {
            // البيانات جاهزة بالصيغة المطلوبة من sync_service
            for (final item in progress.newItems!) {
              _filteredSubscribers.add({
                'customer_id': item['customerId']?.toString() ?? '',
                'username': item['username'] ?? '',
                'first_name': item['firstName'] ?? '',
                'last_name': item['lastName'] ?? '',
                'display_name': item['displayName'] ?? '',
                'zone_id': item['zoneId']?.toString() ?? '',
                'zone_name': item['zoneName'] ?? '',
                'parent_zone_id': item['parentZoneId']?.toString() ?? '',
                'parent_zone_name': item['parentZoneName'] ?? '',
                'status': item['status'] ?? '',
                'profile_name': item['profileName'] ?? '',
                'download_speed': item['downloadSpeed']?.toString() ?? '',
                'upload_speed': item['uploadSpeed']?.toString() ?? '',
                'expires': item['expires'] ?? '',
                'created_at': item['createdAt'] ?? '',
                'updated_at': item['updatedAt'] ?? '',
                'phone': item['phone'] ?? '',
              });
            }
            // تحديث عدد المشتركين
            _subscribersCount = _filteredSubscribers.length;
          }
        });
      },
    );

    if (!mounted) return;
    setState(() => _isSyncing = false);

    if (result.success) {
      _showMessage(
        'تمت المزامنة ✅\n'
        'المشتركين: ${result.subscribersCount}\n'
        'الهواتف: ${result.phonesCount}\n'
        'العناوين: ${result.addressesCount}\n'
        'المدة: ${result.duration.inSeconds} ثانية',
      );
      // إعادة تحميل البيانات من الملفات
      await _db.refresh();
      if (!mounted) return;
      await _loadStatistics();
      await _loadSubscribers();
      await _loadFilters();
    } else {
      _showErrorDialog(
        'فشلت المزامنة',
        result.error ?? result.message,
      );
    }
  }

  /// إلغاء المزامنة
  void _cancelSync() {
    _syncService.cancelSync();
    _showMessage('جاري إلغاء المزامنة...');
  }

  /// بدء الجلب في الخلفية
  Future<void> _startBackgroundSync({
    bool fetchSubscriptions = false,
    bool fetchDetails = false,
    bool fetchAddresses = false,
  }) async {
    // التحقق من التوكن
    String? token = widget.authToken;
    if (token == null || token.isEmpty) {
      token = await AuthService.instance.getAccessToken();
    }

    if (token == null || token.isEmpty) {
      _showMessage('يرجى تسجيل الدخول أولاً', isError: true);
      return;
    }

    if ((fetchDetails || fetchAddresses) && _subscribersCount == 0) {
      _showMessage('يرجى جلب الاشتراكات أولاً', isError: true);
      return;
    }

    // إعداد callback للإشعار عند الاكتمال
    _backgroundSync.onSyncComplete = (success, message) {
      // إعادة تحميل البيانات
      _db.refresh().then((_) {
        _loadStatistics();
        _loadSubscribers();
        _loadFilters();
      });
    };

    // بدء الجلب
    _backgroundSync.startSync(
      token: token,
      fetchSubscriptions: fetchSubscriptions,
      fetchDetails: fetchDetails,
      fetchAddresses: fetchAddresses,
    );

    // عرض رسالة
    String msg = 'بدأ الجلب في الخلفية - يمكنك متابعة العمل';
    if (fetchSubscriptions) msg = 'بدأ جلب الاشتراكات في الخلفية';
    if (fetchAddresses) msg = 'بدأ جلب تفاصيل الاشتراكات في الخلفية';
    if (fetchDetails) msg = 'بدأ جلب أرقام الهواتف في الخلفية';
    _showMessage(msg);

    // الرجوع للصفحة السابقة
    if (mounted) {
      Navigator.pop(context);
    }
  }

  /// جلب أرقام الهواتف
  Future<void> _startFetchPhones() async {
    // التحقق من التوكن
    String? token = widget.authToken;
    if (token == null || token.isEmpty) {
      token = await AuthService.instance.getAccessToken();
    }

    if (token == null || token.isEmpty) {
      _showMessage('يرجى تسجيل الدخول أولاً', isError: true);
      return;
    }

    if (_subscribersCount == 0) {
      _showMessage('يرجى جلب الاشتراكات أولاً', isError: true);
      return;
    }

    // حساب عدد المشتركين بدون أرقام
    final withoutPhone = _subscribers.where((s) {
      final phone = s['phone']?.toString() ?? '';
      return phone.isEmpty;
    }).length;

    if (withoutPhone == 0) {
      _showMessage('جميع المشتركين لديهم أرقام هواتف ✅');
      return;
    }

    setState(() {
      _isSyncing = true;
      _syncStage = 'phones';
      _syncCurrent = 0;
      _syncTotal = 0;
      _syncMessage = 'جاري جلب أرقام الهواتف ($withoutPhone مشترك بدون رقم)...';
    });

    final result = await _syncService.fetchPhoneNumbers(
      token: token,
      onlyWithoutPhone: true, // دائماً جلب فقط للذين بدون أرقام
      onProgress: (progress) {
        if (!mounted) return;
        setState(() {
          _syncStage = progress.stage;
          _syncCurrent = progress.current;
          _syncTotal = progress.total;
          _syncMessage = progress.message;
        });
      },
    );

    if (!mounted) return;
    setState(() => _isSyncing = false);

    if (result.success) {
      _showMessage(
        'تم جلب أرقام الهواتف ✅\n'
        '${result.message}\n'
        'المدة: ${result.duration.inSeconds} ثانية',
      );
      // إعادة تحميل البيانات
      await _db.refresh();
      if (!mounted) return;
      await _loadSubscribers();
    } else {
      _showErrorDialog(
        'فشل جلب أرقام الهواتف',
        result.error ?? result.message,
      );
    }
  }

  /// جلب بيانات الاشتراكات (FDT، FAT، MAC، IP، GPS) بطريقة مجمعة
  /// onlyWithoutDetails = true: جلب فقط للمشتركين بدون تفاصيل
  Future<void> _startFetchSubscriptionAddresses(
      {bool onlyWithoutDetails = true}) async {
    // التحقق من التوكن
    String? token = widget.authToken;
    if (token == null || token.isEmpty) {
      token = await AuthService.instance.getAccessToken();
    }

    if (token == null || token.isEmpty) {
      _showMessage('يرجى تسجيل الدخول أولاً', isError: true);
      return;
    }

    if (_subscribersCount == 0) {
      _showMessage('يرجى جلب الاشتراكات أولاً', isError: true);
      return;
    }

    setState(() {
      _isSyncing = true;
      _syncStage = 'addresses';
      _syncCurrent = 0;
      _syncTotal = 0;
      _syncMessage = 'جاري جلب بيانات الاشتراكات...';
    });

    final result = await _syncService.fetchSubscriptionAddresses(
      token: token,
      onlyWithoutDetails: onlyWithoutDetails,
      onProgress: (progress) {
        if (!mounted) return;
        setState(() {
          _syncStage = progress.stage;
          _syncCurrent = progress.current;
          _syncTotal = progress.total;
          _syncMessage = progress.message;
        });
      },
    );

    if (!mounted) return;
    setState(() => _isSyncing = false);

    if (result.success) {
      _showMessage(
        'تم جلب بيانات الاشتراكات ✅\n'
        '${result.message}\n'
        'المدة: ${result.duration.inSeconds} ثانية',
      );
      // إعادة تحميل البيانات
      await _db.refresh();
      if (!mounted) return;
      await _loadSubscribers();
    } else {
      _showErrorDialog(
        'فشل جلب بيانات الاشتراكات',
        result.error ?? result.message,
      );
    }
  }

  /// عرض خيارات المسح
  Future<void> _showClearOptions() async {
    final option = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.delete_outline, color: Colors.red),
            SizedBox(width: 8),
            Text('خيارات المسح'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.people_outline, color: Colors.blue),
              title: const Text('مسح الاشتراكات'),
              subtitle: const Text('حذف قائمة المشتركين فقط'),
              onTap: () => Navigator.pop(context, 'subscriptions'),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.router_outlined, color: Colors.purple),
              title: const Text('مسح تفاصيل الاشتراكات'),
              subtitle: const Text('FDT، FAT، MAC، IP، GPS'),
              onTap: () => Navigator.pop(context, 'addresses'),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.phone_disabled, color: Colors.green),
              title: const Text('مسح أرقام الهواتف'),
              subtitle: const Text('إزالة أرقام الهواتف فقط'),
              onTap: () => Navigator.pop(context, 'phones'),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.delete_forever, color: Colors.red),
              title: const Text('مسح الكل'),
              subtitle: const Text('حذف جميع البيانات'),
              onTap: () => Navigator.pop(context, 'all'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
        ],
      ),
    );

    if (option == null) return;

    // تأكيد المسح
    String title = '';
    String message = '';
    switch (option) {
      case 'subscriptions':
        title = 'مسح الاشتراكات';
        message = 'سيتم حذف قائمة المشتركين وجميع البيانات المرتبطة.';
        break;
      case 'addresses':
        title = 'مسح تفاصيل الاشتراكات';
        message = 'سيتم حذف FDT، FAT، MAC، IP، GPS فقط.';
        break;
      case 'phones':
        title = 'مسح أرقام الهواتف';
        message = 'سيتم إزالة جميع أرقام الهواتف.';
        break;
      case 'all':
        title = 'مسح الكل';
        message =
            'سيتم حذف جميع البيانات المحفوظة.\nلا يمكن التراجع عن هذا الإجراء.';
        break;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.warning, color: Colors.orange),
            const SizedBox(width: 8),
            Text(title),
          ],
        ),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('مسح', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    // تنفيذ المسح
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      switch (option) {
        case 'subscriptions':
          await _db.clearAllData();
          break;
        case 'addresses':
          await _db.clearAddressesData();
          break;
        case 'phones':
          await _db.clearPhonesData();
          break;
        case 'all':
          await _db.clearAllData();
          break;
      }
      _showMessage('تم المسح بنجاح ✅');
      if (!mounted) return;
      await _loadStatistics();
      await _loadSubscribers();
      if (option == 'subscriptions' || option == 'all') {
        if (!mounted) return;
        setState(() {
          _zones = [];
          _selectedZone = null;
          _selectedStatus = null;
        });
      }
    } catch (e) {
      _showMessage('خطأ في المسح', isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// مسح جميع البيانات
  Future<void> _clearAllData() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning, color: Colors.orange),
            SizedBox(width: 8),
            Text('تأكيد المسح'),
          ],
        ),
        content: const Text('هل أنت متأكد من مسح جميع البيانات المحفوظة؟\n'
            'لا يمكن التراجع عن هذا الإجراء.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('مسح', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      if (!mounted) return;
      setState(() => _isLoading = true);
      try {
        await _db.clearAllData();
        _showMessage('تم مسح جميع البيانات ✅');
        if (!mounted) return;
        await _loadStatistics();
        await _loadSubscribers();
        if (!mounted) return;
        setState(() {
          _zones = [];
          _selectedZone = null;
          _selectedStatus = null;
        });
      } catch (e) {
        _showMessage('خطأ في المسح', isError: true);
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  /// تصدير البيانات إلى Excel
  Future<void> _exportToExcel() async {
    if (_subscribersCount == 0) {
      _showMessage('لا توجد بيانات للتصدير', isError: true);
      return;
    }

    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      // إنشاء ملف Excel جديد
      final excel = Excel.createExcel();

      // حذف الشيت الافتراضي وإنشاء شيت جديد
      excel.delete('Sheet1');
      final sheet = excel['المشتركين'];

      // تنسيق العناوين
      final headerStyle = CellStyle(
        backgroundColorHex: ExcelColor.fromHexString('#1A237E'),
        fontColorHex: ExcelColor.white,
        bold: true,
        horizontalAlign: HorizontalAlign.Center,
      );

      // إضافة العناوين - الحقول المتاحة فعلاً
      final headers = [
        'معرف الاشتراك',
        'معرف العميل',
        'اسم المستخدم',
        'الاسم الكامل',
        'الحالة',
        'معرف المنطقة',
        'معرف الباقة',
        'تاريخ البدء',
        'تاريخ الانتهاء',
        'فترة الالتزام',
        'التجديد التلقائي',
        'رقم الهاتف',
        'FDT',
        'FAT',
        'السيريال',
        'GPS',
        'موقوف',
        'سبب الإيقاف',
        'البروفايل',
        'آخر تحديث',
      ];

      for (int i = 0; i < headers.length; i++) {
        final cell =
            sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0));
        cell.value = TextCellValue(headers[i]);
        cell.cellStyle = headerStyle;
      }

      // جلب جميع البيانات
      final allSubscribers = await _db.getAllSubscribers();

      // إضافة البيانات - جميع الحقول
      for (int row = 0; row < allSubscribers.length; row++) {
        final sub = allSubscribers[row];

        // GPS: دمج lat و lng
        String gpsLocation = '';
        final lat = sub['gps_lat']?.toString() ?? '';
        final lng = sub['gps_lng']?.toString() ?? '';
        if (lat.isNotEmpty && lng.isNotEmpty) {
          gpsLocation = '$lat, $lng';
        }

        final rowData = [
          sub['subscription_id'] ?? '',
          sub['customer_id'] ?? '',
          sub['username'] ?? '',
          sub['display_name'] ?? '',
          _getStatusArabic(sub['status'] ?? ''),
          sub['zone_id'] ?? '',
          sub['bundle_id'] ?? '',
          sub['started_at'] ?? '',
          sub['expires'] ?? '',
          sub['commitment_period'] ?? '',
          (sub['auto_renew'] == true) ? 'نعم' : 'لا',
          sub['phone'] ?? '',
          sub['fdt_name'] ?? '',
          sub['fat_name'] ?? '',
          sub['device_serial'] ?? '',
          gpsLocation,
          (sub['is_suspended'] == true) ? 'نعم' : 'لا',
          sub['suspension_reason'] ?? '',
          sub['profile_name'] ?? '',
          sub['synced_at'] ?? '',
        ];

        for (int col = 0; col < rowData.length; col++) {
          final cell = sheet.cell(
              CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row + 1));
          cell.value = TextCellValue(rowData[col].toString());
        }
      }

      // تعيين عرض الأعمدة
      for (int i = 0; i < headers.length; i++) {
        sheet.setColumnWidth(i, 15);
      }
      sheet.setColumnWidth(2, 20); // اسم المستخدم
      sheet.setColumnWidth(3, 25); // الاسم الكامل

      // حفظ الملف
      final documentsDir = await getApplicationDocumentsDirectory();
      final fileName =
          'المشتركين_${DateTime.now().millisecondsSinceEpoch}.xlsx';
      final filePath = '${documentsDir.path}/$fileName';

      final fileBytes = excel.save();
      if (fileBytes != null) {
        final file = File(filePath);
        await file.writeAsBytes(fileBytes);

        if (mounted) setState(() => _isLoading = false);

        // عرض dialog للنجاح مع خيار الفتح
        if (mounted) {
          final shouldOpen = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.green),
                  SizedBox(width: 8),
                  Text('تم التصدير بنجاح'),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('تم تصدير ${allSubscribers.length} مشترك'),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: SelectableText(
                      filePath,
                      style: const TextStyle(
                          fontSize: 12, fontFamily: 'monospace'),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('إغلاق'),
                ),
                ElevatedButton.icon(
                  onPressed: () => Navigator.pop(context, true),
                  icon: const Icon(Icons.folder_open),
                  label: const Text('فتح الملف'),
                ),
              ],
            ),
          );

          if (shouldOpen == true) {
            await OpenFilex.open(filePath);
          }
        }
      }
    } catch (e) {
      _showMessage('خطأ في التصدير', isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// عرض البيانات الخام
  Future<void> _showRawDataDialog() async {
    final allSubscribers = await _db.getAllSubscribers();

    if (!mounted) return;

    // الحصول على جميع المفاتيح الفريدة
    final allKeys = <String>{};
    for (final sub in allSubscribers) {
      allKeys.addAll(sub.keys);
    }
    final sortedKeys = allKeys.toList()..sort();

    await showDialog(
      context: context,
      builder: (context) => Dialog(
        child: Container(
          width: MediaQuery.of(context).size.width * 0.95,
          height: MediaQuery.of(context).size.height * 0.85,
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                children: [
                  const Icon(Icons.data_object, color: Colors.purple),
                  const SizedBox(width: 8),
                  Text(
                    'البيانات الخام (${allSubscribers.length} سجل، ${sortedKeys.length} حقل)',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const Divider(),
              // عرض الحقول المتاحة
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'الحقول المتاحة:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: sortedKeys
                          .map((key) => Chip(
                                label: Text(key,
                                    style: const TextStyle(fontSize: 10)),
                                padding: EdgeInsets.zero,
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                              ))
                          .toList(),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              // جدول البيانات
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SingleChildScrollView(
                    child: DataTable(
                      columnSpacing: 12,
                      headingRowColor:
                          WidgetStateProperty.all(Colors.purple[50]),
                      columns: sortedKeys
                          .map((key) => DataColumn(
                                label: Text(
                                  key,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 11,
                                  ),
                                ),
                              ))
                          .toList(),
                      rows: allSubscribers
                          .take(100)
                          .map((sub) => DataRow(
                                cells: sortedKeys.map((key) {
                                  final value = sub[key];
                                  String displayValue = '';
                                  if (value == null) {
                                    displayValue = '';
                                  } else if (value is List) {
                                    displayValue = '[${value.length}]';
                                  } else if (value is Map) {
                                    displayValue = '{...}';
                                  } else {
                                    displayValue = value.toString();
                                    if (displayValue.length > 30) {
                                      displayValue =
                                          '${displayValue.substring(0, 30)}...';
                                    }
                                  }
                                  return DataCell(
                                    Text(
                                      displayValue,
                                      style: const TextStyle(fontSize: 10),
                                    ),
                                  );
                                }).toList(),
                              ))
                          .toList(),
                    ),
                  ),
                ),
              ),
              if (allSubscribers.length > 100)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'يتم عرض أول 100 سجل فقط من ${allSubscribers.length}',
                    style: TextStyle(color: Colors.grey[600], fontSize: 12),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// تحويل الحالة للعربية
  String _getStatusArabic(String status) {
    switch (status.toLowerCase()) {
      case 'active':
        return 'فعال';
      case 'inactive':
        return 'غير فعال';
      case 'expired':
        return 'منتهي';
      case 'suspended':
        return 'موقوف';
      default:
        return status;
    }
  }

  /// البحث
  void _onSearchChanged(String query) {
    _loadSubscribers();
  }

  /// عرض تفاصيل مشترك
  void _showSubscriberDetails(Map<String, dynamic> subscriber) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => LocalSubscriberDetailsPage(
          subscriber: subscriber,
        ),
      ),
    );
  }

  /// تفعيل/إلغاء وضع التحديد
  void _toggleSelectionMode() {
    setState(() {
      _isSelectionMode = !_isSelectionMode;
      if (!_isSelectionMode) {
        _selectedIds.clear();
      }
    });
  }

  /// تحديد/إلغاء تحديد مشترك
  void _toggleSelection(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  /// تحديد الكل
  void _selectAll() {
    setState(() {
      _selectedIds.clear();
      for (final sub in _filteredSubscribers) {
        final id = sub['subscription_id']?.toString() ??
            sub['customer_id']?.toString() ??
            '';
        if (id.isNotEmpty) {
          _selectedIds.add(id);
        }
      }
    });
  }

  /// إلغاء تحديد الكل
  void _deselectAll() {
    setState(() {
      _selectedIds.clear();
    });
  }

  /// حذف المحددين
  Future<void> _deleteSelected() async {
    if (_selectedIds.isEmpty) {
      _showMessage('يرجى تحديد اشتراكات للحذف', isError: true);
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.delete_forever, color: Colors.red),
            SizedBox(width: 8),
            Text('تأكيد الحذف'),
          ],
        ),
        content: Text(
          'هل أنت متأكد من حذف ${_selectedIds.length} اشتراك؟\n'
          'لا يمكن التراجع عن هذا الإجراء.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('حذف', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    setState(() => _isLoading = true);
    try {
      // حذف الاشتراكات المحددة
      await _db.deleteSubscribers(_selectedIds.toList());
      _showMessage('تم حذف ${_selectedIds.length} اشتراك بنجاح ✅');
      _selectedIds.clear();
      _isSelectionMode = false;
      if (!mounted) return;
      await _loadStatistics();
      await _loadSubscribers();
    } catch (e) {
      _showMessage('خطأ في الحذف', isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// عرض dialog الإعدادات
  Future<void> _showSettingsDialog() async {
    await _settingsService.initialize();

    // إعدادات الاشتراكات (جلب البيانات)
    int subPageSize = _settingsService.subscriptionsSettings.pageSize;
    int subParallel = _settingsService.subscriptionsSettings.parallelPages;

    // إعدادات جلب رقم الهاتف
    int detailsParallel = _settingsService.usersSettings.parallelPages;

    // إعدادات جلب الاشتراكات (addresses)
    int addressesPageSize = _settingsService.addressesSettings.pageSize;
    int addressesParallel = _settingsService.addressesSettings.parallelPages;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Row(
              children: [
                const Icon(Icons.settings, color: Color(0xFF1A237E)),
                const SizedBox(width: 8),
                const Text('إعدادات الجلب'),
              ],
            ),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ===== إعدادات جلب البيانات (الاشتراكات) =====
                    _buildSettingsSection(
                      title: '📋 جلب البيانات (الاشتراكات)',
                      color: Colors.blue,
                      pageSize: subPageSize,
                      parallelPages: subParallel,
                      onPageSizeChanged: (v) =>
                          setDialogState(() => subPageSize = v),
                      onParallelChanged: (v) =>
                          setDialogState(() => subParallel = v),
                    ),
                    const Divider(height: 24),

                    // ===== إعدادات جلب رقم الهاتف =====
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.green.shade200),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.phone,
                                  color: Colors.green.shade700, size: 20),
                              const SizedBox(width: 8),
                              Text(
                                'جلب رقم الهاتف',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green.shade700,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'عدد الطلبات المتوازية: $detailsParallel',
                            style: const TextStyle(fontSize: 13),
                          ),
                          Slider(
                            value: detailsParallel.toDouble(),
                            min: 1,
                            max: 500,
                            divisions: 499,
                            label: '$detailsParallel طلب',
                            activeColor: Colors.green,
                            onChanged: (v) => setDialogState(
                                () => detailsParallel = v.toInt()),
                          ),
                          Text(
                            'القيمة الأعلى = سرعة أكبر (قد تستهلك موارد أكثر)',
                            style: TextStyle(
                                fontSize: 11, color: Colors.grey[600]),
                          ),
                        ],
                      ),
                    ),

                    const Divider(height: 24),

                    // ===== إعدادات جلب الاشتراكات (addresses) =====
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.purple.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.purple.shade200),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.router,
                                  color: Colors.purple.shade700, size: 20),
                              const SizedBox(width: 8),
                              Text(
                                'جلب الاشتراكات (FDT، FAT، MAC)',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.purple.shade700,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'عدد المشتركين في كل طلب: $addressesPageSize',
                            style: const TextStyle(fontSize: 13),
                          ),
                          Slider(
                            value: addressesPageSize.toDouble(),
                            min: 50,
                            max: 200,
                            divisions: 15,
                            label: '$addressesPageSize مشترك',
                            activeColor: Colors.purple,
                            onChanged: (v) => setDialogState(
                                () => addressesPageSize = v.toInt()),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'عدد الطلبات المتوازية: $addressesParallel',
                            style: const TextStyle(fontSize: 13),
                          ),
                          Slider(
                            value: addressesParallel.toDouble(),
                            min: 1,
                            max: 20,
                            divisions: 19,
                            label: '$addressesParallel طلب',
                            activeColor: Colors.purple,
                            onChanged: (v) => setDialogState(
                                () => addressesParallel = v.toInt()),
                          ),
                          Text(
                            '⚡ هذه الطريقة أسرع: 150 مشترك في طلب واحد!',
                            style: TextStyle(
                                fontSize: 11, color: Colors.purple.shade700),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),
                    // ملاحظة
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline,
                              color: Colors.blue.shade700, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'زيادة القيم تسرع الجلب لكن قد تستهلك موارد أكثر',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.blue.shade700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () async {
                  await _settingsService.resetToDefaults();
                  Navigator.of(context).pop(true);
                  _showMessage('تم إعادة الإعدادات للقيم الافتراضية');
                },
                child: const Text('افتراضي'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('إلغاء'),
              ),
              ElevatedButton(
                onPressed: () async {
                  await _settingsService.updateSubscriptionsSettings(
                    pageSize: subPageSize,
                    parallelPages: subParallel,
                  );
                  await _settingsService.updateUsersSettings(
                    pageSize: 100,
                    parallelPages: detailsParallel,
                  );
                  await _settingsService.updateAddressesSettings(
                    pageSize: addressesPageSize,
                    parallelPages: addressesParallel,
                  );
                  Navigator.of(context).pop(true);
                },
                child: const Text('حفظ'),
              ),
            ],
          );
        },
      ),
    );

    if (result == true) {
      _showMessage('تم حفظ الإعدادات بنجاح');
    }
  }

  /// بناء قسم إعدادات
  Widget _buildSettingsSection({
    required String title,
    required Color color,
    required int pageSize,
    required int parallelPages,
    required Function(int) onPageSizeChanged,
    required Function(int) onParallelChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 14,
            color: color,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('عناصر/صفحة', style: TextStyle(fontSize: 12)),
                  const SizedBox(height: 4),
                  TextFormField(
                    initialValue: pageSize.toString(),
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 8),
                      isDense: true,
                      focusedBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: color),
                      ),
                    ),
                    onChanged: (value) {
                      final parsed = int.tryParse(value);
                      if (parsed != null) {
                        onPageSizeChanged(parsed.clamp(
                          SyncSettingsService.minPageSize,
                          SyncSettingsService.maxPageSize,
                        ));
                      }
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('صفحات متوازية', style: TextStyle(fontSize: 12)),
                  const SizedBox(height: 4),
                  TextFormField(
                    initialValue: parallelPages.toString(),
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 8),
                      isDense: true,
                      focusedBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: color),
                      ),
                    ),
                    onChanged: (value) {
                      final parsed = int.tryParse(value);
                      if (parsed != null) {
                        onParallelChanged(parsed.clamp(
                          SyncSettingsService.minParallelPages,
                          SyncSettingsService.maxParallelPages,
                        ));
                      }
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// بناء القائمة الجانبية
  Widget _buildEndDrawer() {
    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            // رأس القائمة
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF1A237E), Color(0xFF3949AB)],
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.menu, color: Colors.white, size: 32),
                  const SizedBox(height: 8),
                  const Text(
                    'خيارات إضافية',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    '$_subscribersCount مشترك محفوظ',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.8),
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
            // العناصر
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  // تصدير Excel
                  ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade100,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(Icons.file_download,
                          color: Colors.orange.shade700),
                    ),
                    title: const Text('تصدير إلى Excel'),
                    subtitle: const Text('تصدير جميع البيانات لملف Excel'),
                    enabled: !_isSyncing &&
                        _subscribersCount > 0 &&
                        PermissionManager.instance.canExport('local_storage'),
                    onTap: () {
                      Navigator.pop(context); // إغلاق القائمة
                      _exportToExcel();
                    },
                  ),
                  const Divider(),
                  // عرض البيانات الخام
                  ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.purple.shade100,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(Icons.data_object,
                          color: Colors.purple.shade700),
                    ),
                    title: const Text('عرض البيانات الخام'),
                    subtitle: const Text('عرض جميع الحقول المخزنة'),
                    enabled: !_isSyncing && _subscribersCount > 0,
                    onTap: () {
                      Navigator.pop(context); // إغلاق القائمة
                      _showRawDataDialog();
                    },
                  ),
                  const Divider(),
                  // الإعدادات
                  ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.blueGrey.shade100,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child:
                          Icon(Icons.settings, color: Colors.blueGrey.shade700),
                    ),
                    title: const Text('إعدادات المزامنة'),
                    subtitle: const Text('تعديل سرعة الجلب والإعدادات'),
                    enabled: !_isSyncing,
                    onTap: () {
                      Navigator.pop(context); // إغلاق القائمة
                      _showSettingsDialog();
                    },
                  ),
                ],
              ),
            ),
            // تذييل
            Container(
              padding: const EdgeInsets.all(16),
              child: Text(
                'آخر تحديث: ${_lastSyncTime != null ? _formatDate(_lastSyncTime!) : "لم يتم"}',
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showMessage(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  /// عرض dialog للخطأ مع إمكانية النسخ
  void _showErrorDialog(String title, String errorMessage) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.red),
            const SizedBox(width: 8),
            Expanded(child: Text(title)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'تفاصيل الخطأ:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey[300]!),
              ),
              constraints: const BoxConstraints(maxHeight: 200),
              child: SingleChildScrollView(
                child: SelectableText(
                  errorMessage,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: errorMessage));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('تم نسخ الخطأ'),
                  backgroundColor: Colors.green,
                  duration: Duration(seconds: 1),
                ),
              );
            },
            icon: const Icon(Icons.copy),
            label: const Text('نسخ'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('التخزين المحلي'),
            if (_subscribersCount > 0) ...[
              const SizedBox(width: 10),
              // عدد المشتركين
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.amber,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.people, size: 16, color: Colors.black87),
                    const SizedBox(width: 4),
                    Text(
                      '$_subscribersCount',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                  ],
                ),
              ),
              // عدد الهواتف
              if (_phonesCount > 0) ...[
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.green.shade400,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.phone, size: 14, color: Colors.white),
                      const SizedBox(width: 3),
                      Text(
                        '$_phonesCount',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ],
        ),
        backgroundColor: const Color(0xFF1A237E),
        foregroundColor: Colors.white,
        actions: [
          // زر الاستيراد - يظهر فقط عند وجود الصلاحية
          if (!_isSyncing && _hasImportPermission)
            TextButton.icon(
              onPressed: () {
                setState(() => _showImportCard = !_showImportCard);
              },
              icon: Icon(
                _showImportCard ? Icons.cloud_off : Icons.cloud_download,
                color: _showImportCard ? Colors.amber : Colors.white,
                size: 20,
              ),
              label: Text(
                'استيراد',
                style: TextStyle(
                  color: _showImportCard ? Colors.amber : Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              style: TextButton.styleFrom(
                backgroundColor: _showImportCard
                    ? Colors.white.withValues(alpha: 0.2)
                    : Colors.transparent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          // مؤشر مزامنة VPS
          if (_isVpsSyncing)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 16, height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: const AlwaysStoppedAnimation<Color>(Colors.amber),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'جاري المزامنة...',
                    style: const TextStyle(fontSize: 11, color: Colors.amber),
                  ),
                ],
              ),
            )
          else if (_vpsSyncService.lastSuccessfulSync != null)
            Tooltip(
              message: 'آخر مزامنة: ${_formatSyncTime(_vpsSyncService.lastSuccessfulSync!)}',
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Icon(Icons.cloud_done, size: 20, color: Colors.greenAccent.shade200),
              ),
            ),
          // زر التصفية
          if (!_isSyncing && _subscribersCount > 0)
            IconButton(
              icon: Icon(_showFilter ? Icons.filter_alt_off : Icons.filter_alt),
              onPressed: () {
                setState(() => _showFilter = !_showFilter);
              },
              tooltip: _showFilter ? 'إخفاء التصفية' : 'إظهار التصفية',
            ),
          if (!_isSyncing)
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _initializeAndLoad,
              tooltip: 'تحديث',
            ),
          // زر القائمة الجانبية
          Builder(
            builder: (context) => IconButton(
              icon: const Icon(Icons.more_vert),
              onPressed: () => Scaffold.of(context).openEndDrawer(),
              tooltip: 'خيارات إضافية',
            ),
          ),
        ],
      ),
      endDrawer: _buildEndDrawer(),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // شريط التقدم أثناء المزامنة
                if (_isSyncing) _buildSyncProgress(),

                // أزرار المزامنة والفلترة (فقط عند الحاجة)
                if (_showImportCard || _isSyncing || _showFilter)
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_showImportCard || _isSyncing) _buildSyncActions(),
                        if (!_isSyncing && _showFilter) ...[
                          const SizedBox(height: 8),
                          _buildSearchAndFilter(),
                        ],
                      ],
                    ),
                  ),

                // قائمة المشتركين تأخذ كل المساحة المتبقية - بدون padding علوي
                Expanded(
                  child: _subscribersCount > 0 ||
                          _filteredSubscribers.isNotEmpty ||
                          _isSyncing
                      ? Padding(
                          padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                          child: _buildSubscribersList(),
                        )
                      : _buildEmptyState(),
                ),
              ],
            ),
    );
  }

  Widget _buildSyncProgress() {
    final percentage = _syncTotal > 0 ? (_syncCurrent / _syncTotal * 100) : 0.0;

    return Container(
      color: const Color(0xFF1A237E).withValues(alpha: 0.1),
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _syncMessage,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              TextButton(
                onPressed: _cancelSync,
                child: const Text('إلغاء', style: TextStyle(color: Colors.red)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: _syncTotal > 0 ? _syncCurrent / _syncTotal : null,
            backgroundColor: Colors.grey[300],
            valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF1A237E)),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _getStageName(_syncStage),
                style: TextStyle(color: Colors.grey[600], fontSize: 12),
              ),
              Text(
                '${percentage.toStringAsFixed(0)}%',
                style: TextStyle(color: Colors.grey[600], fontSize: 12),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _getStageName(String stage) {
    switch (stage) {
      case 'subscribers':
        return 'الاشتراكات';
      case 'phones':
        return 'المشتركين';
      case 'addresses':
        return 'معلومات المشترك';
      default:
        return 'جاري التحميل...';
    }
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }

  Widget _buildSyncActions() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.blue.shade300, width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // صف أزرار التصفية (بدون هاتف / بدون تفاصيل / مسح)
            if (!_isSyncing && _subscribersCount > 0)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    // زر بدون رقم هاتف
                    Expanded(
                      child: InkWell(
                        onTap: () {
                          setState(() {
                            _showOnlyWithoutPhone = !_showOnlyWithoutPhone;
                            _applyFilters();
                          });
                        },
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 10),
                          decoration: BoxDecoration(
                            color: _showOnlyWithoutPhone
                                ? Colors.orange.withValues(alpha: 0.2)
                                : Colors.orange.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: _showOnlyWithoutPhone
                                  ? Colors.orange
                                  : Colors.orange.shade300,
                              width: _showOnlyWithoutPhone ? 2.5 : 1.5,
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                _showOnlyWithoutPhone
                                    ? Icons.phone_disabled
                                    : Icons.no_cell,
                                size: 16,
                                color: _showOnlyWithoutPhone
                                    ? Colors.orange.shade800
                                    : Colors.orange.shade400,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'بدون هاتف',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    // زر بدون تفاصيل
                    Expanded(
                      child: InkWell(
                        onTap: () {
                          setState(() {
                            _showOnlyWithoutDetails = !_showOnlyWithoutDetails;
                            _applyFilters();
                          });
                        },
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 10),
                          decoration: BoxDecoration(
                            color: _showOnlyWithoutDetails
                                ? Colors.purple.withValues(alpha: 0.2)
                                : Colors.purple.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: _showOnlyWithoutDetails
                                  ? Colors.purple
                                  : Colors.purple.shade300,
                              width: _showOnlyWithoutDetails ? 2.5 : 1.5,
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                _showOnlyWithoutDetails
                                    ? Icons.info
                                    : Icons.info_outline,
                                size: 16,
                                color: _showOnlyWithoutDetails
                                    ? Colors.purple.shade800
                                    : Colors.purple.shade400,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'بدون تفاصيل',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    // زر مسح البيانات
                    Expanded(
                      child: InkWell(
                        onTap: _showClearOptions,
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 10),
                          decoration: BoxDecoration(
                            color: Colors.red.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: Colors.red.shade400,
                              width: 1.5,
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.delete_forever,
                                size: 16,
                                color: Colors.red.shade600,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'مسح',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            // زر المزامنة من VPS (الطريقة الأساسية — يجلب كل البيانات)
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: ElevatedButton.icon(
                    onPressed: (_isSyncing || _isVpsSyncing)
                        ? null
                        : () => _vpsSyncService.syncFromVps(),
                    icon: Icon(
                      _isVpsSyncing ? Icons.sync : Icons.cloud_sync,
                      size: 18,
                    ),
                    label: Text(_isVpsSyncing
                        ? _vpsSyncService.statusMessage
                        : 'مزامنة من السيرفر'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.teal,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: Colors.teal.shade200,
                      disabledForegroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: (_isSyncing || _isVpsSyncing)
                      ? null
                      : () => _vpsSyncService.forceFullSync(),
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('كامل'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.teal.shade700,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.grey,
                    padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
                  ),
                ),
              ],
            ),
            if (_isVpsSyncing)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: LinearProgressIndicator(
                  value: _vpsSyncService.progress > 0 ? _vpsSyncService.progress : null,
                  backgroundColor: Colors.teal.shade100,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.teal.shade600),
                ),
              ),
            const SizedBox(height: 8),
            // أزرار الاستيراد المباشر (احتياطي)
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text(
                'استيراد مباشر من FTTH (متقدم)',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _isSyncing ? null : _startFullSync,
                        icon: const Icon(Icons.cloud_download, size: 16),
                        label: const Text('الاشتراكات', style: TextStyle(fontSize: 11)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1A237E),
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: Colors.grey,
                          padding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _isSyncing || _subscribersCount == 0
                            ? null
                            : _startFetchSubscriptionAddresses,
                        icon: const Icon(Icons.router, size: 16),
                        label: const Text('التفاصيل', style: TextStyle(fontSize: 11)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.purple,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: Colors.grey,
                          padding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _isSyncing || _subscribersCount == 0
                            ? null
                            : _startFetchPhones,
                        icon: const Icon(Icons.phone, size: 16),
                        label: const Text('الهاتف', style: TextStyle(fontSize: 11)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: Colors.grey,
                          padding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            // صف ثالث - الجلب في الخلفية
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.cyan.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.cyan.shade400, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: Colors.cyan.withValues(alpha: 0.2),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.cloud_sync,
                          color: Colors.cyan.shade700, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        'جلب في الخلفية (يمكنك متابعة العمل)',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.cyan.shade700,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      // زر الاشتراكات
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: (_isSyncing || _backgroundSync.isSyncing)
                              ? null
                              : () => _startBackgroundSync(
                                  fetchSubscriptions: true),
                          icon: const Icon(Icons.cloud_download, size: 16),
                          label: const Text('الاشتراكات',
                              style: TextStyle(fontSize: 11)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1A237E),
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: Colors.grey,
                            padding: const EdgeInsets.symmetric(vertical: 10),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      // زر تفاصيل الاشتراكات
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: (_isSyncing ||
                                  _backgroundSync.isSyncing ||
                                  _subscribersCount == 0)
                              ? null
                              : () =>
                                  _startBackgroundSync(fetchAddresses: true),
                          icon: const Icon(Icons.router, size: 16),
                          label: const Text('تفاصيل الاشتراكات',
                              style: TextStyle(fontSize: 10)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.purple,
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: Colors.grey,
                            padding: const EdgeInsets.symmetric(vertical: 10),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      // زر رقم الهاتف
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: (_isSyncing ||
                                  _backgroundSync.isSyncing ||
                                  _subscribersCount == 0)
                              ? null
                              : () => _startBackgroundSync(fetchDetails: true),
                          icon: const Icon(Icons.phone, size: 16),
                          label: const Text('رقم الهاتف',
                              style: TextStyle(fontSize: 11)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: Colors.grey,
                            padding: const EdgeInsets.symmetric(vertical: 10),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // عرض حالة المزامنة في الخلفية
            if (_backgroundSync.isSyncing)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: ListenableBuilder(
                  listenable: _backgroundSync,
                  builder: (context, _) {
                    final progress = _backgroundSync.progress;
                    return Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              progress.message,
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                          Text(
                            '${progress.percentage.toStringAsFixed(0)}%',
                            style: const TextStyle(
                                fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchAndFilter() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // حقل البحث
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'بحث بالاسم أو معرف العميل...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          _loadSubscribers();
                        },
                      )
                    : null,
              ),
              onChanged: _onSearchChanged,
            ),
            const SizedBox(height: 12),

            // الفلاتر
            Row(
              children: [
                // فلتر المنطقة
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _selectedZone,
                    decoration: InputDecoration(
                      labelText: 'المنطقة',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                    ),
                    items: [
                      const DropdownMenuItem(
                        value: null,
                        child: Text('الكل'),
                      ),
                      ..._zones.map((zone) => DropdownMenuItem(
                            value: zone,
                            child: Text(
                              zone,
                              overflow: TextOverflow.ellipsis,
                            ),
                          )),
                    ],
                    onChanged: (value) {
                      setState(() => _selectedZone = value);
                      _loadSubscribers();
                    },
                  ),
                ),
                const SizedBox(width: 8),

                // فلتر الحالة
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _selectedStatus,
                    decoration: InputDecoration(
                      labelText: 'الحالة',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                    ),
                    items: [
                      const DropdownMenuItem(
                        value: null,
                        child: Text('الكل'),
                      ),
                      ..._statuses.map((status) => DropdownMenuItem(
                            value: status,
                            child: Text(_getStatusName(status)),
                          )),
                    ],
                    onChanged: (value) {
                      setState(() => _selectedStatus = value);
                      _loadSubscribers();
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // الترتيب
            Row(
              children: [
                const Text('ترتيب حسب: '),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('الاسم'),
                  selected: _sortBy == 'name',
                  onSelected: (selected) {
                    setState(() => _sortBy = 'name');
                    _loadSubscribers();
                  },
                ),
                const SizedBox(width: 4),
                ChoiceChip(
                  label: const Text('تاريخ الانتهاء'),
                  selected: _sortBy == 'expires',
                  onSelected: (selected) {
                    setState(() => _sortBy = 'expires');
                    _loadSubscribers();
                  },
                ),
                const SizedBox(width: 4),
                ChoiceChip(
                  label: const Text('المنطقة'),
                  selected: _sortBy == 'zone',
                  onSelected: (selected) {
                    setState(() => _sortBy = 'zone');
                    _loadSubscribers();
                  },
                ),
                const Spacer(),
                IconButton(
                  icon: Icon(
                    _sortAscending ? Icons.arrow_upward : Icons.arrow_downward,
                  ),
                  onPressed: () {
                    setState(() => _sortAscending = !_sortAscending);
                    _loadSubscribers();
                  },
                  tooltip: _sortAscending ? 'تصاعدي' : 'تنازلي',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _getStatusName(String status) {
    switch (status) {
      case 'active':
        return 'نشط';
      case 'inactive':
        return 'غير نشط';
      case 'expired':
        return 'منتهي';
      case 'suspended':
        return 'موقوف';
      default:
        return status;
    }
  }

  Color _getStatusColor(String? status) {
    switch (status?.toLowerCase()) {
      case 'active':
        return Colors.green;
      case 'inactive':
        return Colors.orange;
      case 'expired':
        return Colors.red;
      case 'suspended':
        return Colors.grey;
      default:
        return Colors.blue;
    }
  }

  Widget _buildSubscribersList() {
    final allSelected = _filteredSubscribers.isNotEmpty &&
        _filteredSubscribers.every((sub) {
          final id = sub['subscription_id']?.toString() ??
              sub['customer_id']?.toString() ??
              '';
          return _selectedIds.contains(id);
        });

    return Card(
      elevation: 2,
      margin: EdgeInsets.zero, // إزالة الهوامش
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // شريط أدوات التحديد فقط عند التفعيل
          if (_isSelectionMode)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF1A237E).withValues(alpha: 0.1),
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(8)),
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.red),
                    onPressed: _toggleSelectionMode,
                    tooltip: 'إلغاء التحديد',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                  const SizedBox(width: 8),
                  Checkbox(
                    value: allSelected && _filteredSubscribers.isNotEmpty,
                    tristate: _selectedIds.isNotEmpty && !allSelected,
                    onChanged: (value) {
                      if (allSelected) {
                        _deselectAll();
                      } else {
                        _selectAll();
                      }
                    },
                    activeColor: const Color(0xFF1A237E),
                  ),
                  Text(
                    'محدد (${_selectedIds.length})',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1A237E),
                    ),
                  ),
                  const Spacer(),
                  if (_selectedIds.isNotEmpty &&
                      PermissionManager.instance.canDelete('local_storage'))
                    ElevatedButton.icon(
                      onPressed: _deleteSelected,
                      icon: const Icon(Icons.delete, size: 16),
                      label: Text('حذف (${_selectedIds.length})'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                      ),
                    ),
                ],
              ),
            ),
          // رأس الجدول الثابت - صف العناوين
          Container(
            color: const Color(0xFF1A237E),
            child: Row(
              children: [
                // مربع التحديد
                if (_isSelectionMode)
                  SizedBox(
                    width: 50,
                    child: Checkbox(
                      value:
                          _selectedIds.length == _filteredSubscribers.length &&
                              _filteredSubscribers.isNotEmpty,
                      onChanged: (value) {
                        setState(() {
                          if (value == true) {
                            _selectedIds.addAll(_filteredSubscribers.map((s) =>
                                s['subscription_id']?.toString() ??
                                s['customer_id']?.toString() ??
                                ''));
                          } else {
                            _selectedIds.clear();
                          }
                        });
                      },
                      checkColor: const Color(0xFF1A237E),
                      fillColor: WidgetStateProperty.all(Colors.white),
                    ),
                  )
                else
                  const SizedBox(
                      width: 40,
                      child: Center(
                          child: Text('#',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold)))),
                _buildSortableHeaderCell('الاسم', 'name', flex: 3),
                _buildSortableHeaderCell('الهاتف', 'phone', flex: 2),
                _buildSortableHeaderCell('المنطقة', 'zone', flex: 2),
                _buildSortableHeaderCell('FAT', 'fat', flex: 2),
                _buildSortableHeaderCell('الحالة', 'status', flex: 1),
                _buildSortableHeaderCell('الانتهاء', 'expires', flex: 2),
                _buildSortableHeaderCell('الباقة', 'profile', flex: 2),
                _buildSortableHeaderCell('المستخدم', 'username', flex: 2),
              ],
            ),
          ),
          // صف الفلاتر
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                  color: const Color(0xFF1A237E).withValues(alpha: 0.3),
                  width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
            child: Row(
              children: [
                // مسافة للترقيم
                const SizedBox(width: 36),
                // فلتر الاسم
                _buildFilterTextField(_nameFilterController, 'بحث الاسم...',
                    flex: 3),
                // فلتر الهاتف
                _buildFilterTextField(_phoneFilterController, 'بحث الهاتف...',
                    flex: 2),
                // فلتر المنطقة - تحديد متعدد
                _buildMultiSelectFilter('المنطقة', _zones, _selectedZones,
                    flex: 2),
                // فلتر FAT - تحديد متعدد
                _buildMultiSelectFilter('FAT', _availableFATs, _selectedFATs,
                    flex: 2),
                // فلتر الحالة - تحديد متعدد
                _buildMultiSelectFilter(
                    'الحالة', _availableStatuses, _selectedStatuses,
                    flex: 1),
                // فلتر التاريخ من/إلى
                _buildDateRangeFilter(flex: 2),
                // فلتر الباقة - تحديد متعدد
                _buildMultiSelectFilter(
                    'الباقة', _availableProfiles, _selectedProfiles,
                    flex: 2),
                // فلتر المستخدم
                _buildFilterTextField(
                    _usernameFilterController, 'بحث المستخدم...',
                    flex: 2),
              ],
            ),
          ),
          // شريط عداد النتائج
          Container(
            color: const Color(0xFF1A237E).withValues(alpha: 0.05),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Icon(Icons.analytics_outlined,
                    size: 18, color: const Color(0xFF1A237E)),
                const SizedBox(width: 8),
                Text(
                  'عدد النتائج: ',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade700,
                  ),
                ),
                Text(
                  '${_filteredSubscribers.length}',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1A237E),
                  ),
                ),
                if (_filteredSubscribers.length != _subscribers.length) ...[
                  Text(
                    ' من ${_subscribers.length}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(width: 12),
                  InkWell(
                    onTap: () {
                      setState(() {
                        _nameFilterController.clear();
                        _phoneFilterController.clear();
                        _usernameFilterController.clear();
                        _selectedZones.clear();
                        _selectedFATs.clear();
                        _selectedStatuses.clear();
                        _selectedProfiles.clear();
                        _dateFrom = null;
                        _dateTo = null;
                      });
                      _loadSubscribers();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade100,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.orange.shade300),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.clear_all,
                              size: 14, color: Colors.orange.shade800),
                          const SizedBox(width: 4),
                          Text(
                            'مسح الفلاتر',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.orange.shade800,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            child: _filteredSubscribers.isEmpty
                ? Center(
                    child: _isSyncing
                        ? const Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              CircularProgressIndicator(),
                              SizedBox(height: 16),
                              Text(
                                'جاري جلب البيانات...',
                                style: TextStyle(color: Colors.grey),
                              ),
                            ],
                          )
                        : const Text(
                            'لا توجد نتائج',
                            style: TextStyle(color: Colors.grey),
                          ),
                  )
                : ListView.builder(
                    itemCount: _filteredSubscribers.length,
                    itemExtent: 56, // ارتفاع صف الجدول
                    cacheExtent: 500,
                    itemBuilder: (context, index) {
                      final sub = _filteredSubscribers[index];
                      return _buildTableRow(sub, index);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  /// بناء خلية رأس الجدول
  Widget _buildHeaderCell(String text, {int flex = 1}) {
    return Expanded(
      flex: flex,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 14),
        child: Text(
          text,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
          textAlign: TextAlign.center,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  /// بناء خلية رأس قابلة للترتيب
  Widget _buildSortableHeaderCell(String text, String columnKey,
      {int flex = 1}) {
    final isCurrentSort = _tableSortColumn == columnKey;
    return Expanded(
      flex: flex,
      child: InkWell(
        onTap: () => _toggleSort(columnKey),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  text,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 2),
              Icon(
                isCurrentSort
                    ? (_tableSortAscending
                        ? Icons.arrow_upward
                        : Icons.arrow_downward)
                    : Icons.unfold_more,
                color: isCurrentSort ? Colors.amber : Colors.white70,
                size: 14,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// بناء مربع نص للفلترة
  Widget _buildFilterTextField(TextEditingController controller, String hint,
      {int flex = 1}) {
    return Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Container(
          height: 34,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 3,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: TextField(
            controller: controller,
            style: const TextStyle(fontSize: 12, color: Colors.black),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(fontSize: 11, color: Colors.grey.shade500),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
              isDense: true,
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(
                    color: const Color(0xFF1A237E).withValues(alpha: 0.4),
                    width: 1.5),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(
                    color: const Color(0xFF1A237E).withValues(alpha: 0.3),
                    width: 1),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide:
                    const BorderSide(color: Color(0xFF1A237E), width: 2),
              ),
              suffixIcon: controller.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 16),
                      padding: EdgeInsets.zero,
                      onPressed: () {
                        controller.clear();
                        _loadSubscribers();
                      },
                    )
                  : const Icon(Icons.search, size: 16, color: Colors.grey),
            ),
            onChanged: (value) {
              _loadSubscribers();
            },
          ),
        ),
      ),
    );
  }

  /// بناء زر تحديد متعدد للفلترة (FDT/FAT)
  Widget _buildMultiSelectFilter(
      String label, List<String> options, Set<String> selected,
      {int flex = 1}) {
    final hasSelection = selected.isNotEmpty;
    return Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Container(
          height: 34,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: hasSelection
                    ? const Color(0xFF1A237E).withValues(alpha: 0.15)
                    : Colors.black.withValues(alpha: 0.08),
                blurRadius: 3,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: InkWell(
            onTap: () => _showMultiSelectDialog(label, options, selected),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              decoration: BoxDecoration(
                color: hasSelection
                    ? const Color(0xFF1A237E).withValues(alpha: 0.1)
                    : Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: hasSelection
                      ? const Color(0xFF1A237E)
                      : const Color(0xFF1A237E).withValues(alpha: 0.3),
                  width: hasSelection ? 2 : 1,
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      hasSelection ? '${selected.length} محدد' : label,
                      style: TextStyle(
                        fontSize: 11,
                        color: hasSelection
                            ? const Color(0xFF1A237E)
                            : Colors.black87,
                        fontWeight:
                            hasSelection ? FontWeight.bold : FontWeight.normal,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (hasSelection)
                    InkWell(
                      onTap: () {
                        setState(() => selected.clear());
                        _loadSubscribers();
                      },
                      child: const Icon(Icons.clear,
                          size: 14, color: Color(0xFF1A237E)),
                    )
                  else
                    const Icon(Icons.arrow_drop_down,
                        size: 18, color: Colors.black54),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// عرض نافذة التحديد المتعدد
  void _showMultiSelectDialog(
      String title, List<String> options, Set<String> selected) {
    if (options.isEmpty) {
      _showMessage('لا توجد خيارات متاحة - جلب التفاصيل أولاً', isError: true);
      return;
    }

    final tempSelected = Set<String>.from(selected);
    final searchController = TextEditingController();
    List<String> filteredOptions = List.from(options);

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Row(
            children: [
              Text('اختر $title', style: const TextStyle(fontSize: 16)),
              const Spacer(),
              TextButton(
                onPressed: () {
                  setDialogState(() {
                    if (tempSelected.length == options.length) {
                      tempSelected.clear();
                    } else {
                      tempSelected.addAll(options);
                    }
                  });
                },
                child: Text(
                  tempSelected.length == options.length
                      ? 'إلغاء الكل'
                      : 'تحديد الكل',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 300,
            height: 400,
            child: Column(
              children: [
                // مربع البحث
                TextField(
                  controller: searchController,
                  decoration: InputDecoration(
                    hintText: 'بحث...',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onChanged: (value) {
                    setDialogState(() {
                      filteredOptions = options
                          .where((o) =>
                              o.toLowerCase().contains(value.toLowerCase()))
                          .toList();
                    });
                  },
                ),
                const SizedBox(height: 8),
                // عدد المحدد
                Container(
                  padding:
                      const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'محدد: ${tempSelected.length} من ${options.length}',
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(height: 8),
                // قائمة الخيارات
                Expanded(
                  child: ListView.builder(
                    itemCount: filteredOptions.length,
                    itemBuilder: (context, index) {
                      final option = filteredOptions[index];
                      final isSelected = tempSelected.contains(option);
                      return CheckboxListTile(
                        dense: true,
                        title:
                            Text(option, style: const TextStyle(fontSize: 13)),
                        value: isSelected,
                        onChanged: (value) {
                          setDialogState(() {
                            if (value == true) {
                              tempSelected.add(option);
                            } else {
                              tempSelected.remove(option);
                            }
                          });
                        },
                        activeColor: const Color(0xFF1A237E),
                        controlAffinity: ListTileControlAffinity.leading,
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  selected.clear();
                  selected.addAll(tempSelected);
                });
                _loadSubscribers();
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1A237E),
              ),
              child: const Text('تطبيق', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  /// بناء فلتر نطاق التاريخ
  Widget _buildDateRangeFilter({int flex = 2}) {
    final hasFilter = _dateFrom != null || _dateTo != null;
    String displayText = 'التاريخ';

    if (_dateFrom != null && _dateTo != null) {
      displayText =
          '${_formatDateShort(_dateFrom!)} - ${_formatDateShort(_dateTo!)}';
    } else if (_dateFrom != null) {
      displayText = 'من ${_formatDateShort(_dateFrom!)}';
    } else if (_dateTo != null) {
      displayText = 'إلى ${_formatDateShort(_dateTo!)}';
    }

    return Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Container(
          height: 34,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: hasFilter
                    ? const Color(0xFF1A237E).withValues(alpha: 0.15)
                    : Colors.black.withValues(alpha: 0.08),
                blurRadius: 3,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: InkWell(
            onTap: () => _showDateRangeDialog(),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              decoration: BoxDecoration(
                color: hasFilter
                    ? const Color(0xFF1A237E).withValues(alpha: 0.1)
                    : Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: hasFilter
                      ? const Color(0xFF1A237E)
                      : const Color(0xFF1A237E).withValues(alpha: 0.3),
                  width: hasFilter ? 2 : 1,
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  Icon(Icons.date_range,
                      size: 14,
                      color:
                          hasFilter ? const Color(0xFF1A237E) : Colors.black54),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      displayText,
                      style: TextStyle(
                        fontSize: 10,
                        color: hasFilter
                            ? const Color(0xFF1A237E)
                            : Colors.black87,
                        fontWeight:
                            hasFilter ? FontWeight.bold : FontWeight.normal,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (hasFilter)
                    InkWell(
                      onTap: () {
                        setState(() {
                          _dateFrom = null;
                          _dateTo = null;
                        });
                        _loadSubscribers();
                      },
                      child: const Icon(Icons.clear,
                          size: 14, color: Color(0xFF1A237E)),
                    )
                  else
                    Icon(Icons.arrow_drop_down,
                        size: 18, color: Colors.grey.shade600),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// تنسيق التاريخ بشكل مختصر
  String _formatDateShort(DateTime date) {
    return '${date.day}/${date.month}';
  }

  /// عرض نافذة اختيار نطاق التاريخ
  void _showDateRangeDialog() {
    DateTime? tempFrom = _dateFrom;
    DateTime? tempTo = _dateTo;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.date_range, color: Color(0xFF1A237E)),
              const SizedBox(width: 8),
              const Text('فلتر تاريخ الانتهاء', style: TextStyle(fontSize: 16)),
            ],
          ),
          content: SizedBox(
            width: 320,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // من تاريخ
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.calendar_today, size: 20),
                  title: const Text('من تاريخ', style: TextStyle(fontSize: 14)),
                  subtitle: Text(
                    tempFrom != null
                        ? '${tempFrom!.day}/${tempFrom!.month}/${tempFrom!.year}'
                        : 'غير محدد',
                    style: TextStyle(
                      color: tempFrom != null
                          ? const Color(0xFF1A237E)
                          : Colors.grey,
                      fontWeight: tempFrom != null
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit_calendar, size: 20),
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: tempFrom ?? DateTime.now(),
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2030),
                            locale: const Locale('ar'),
                          );
                          if (picked != null) {
                            setDialogState(() => tempFrom = picked);
                          }
                        },
                      ),
                      if (tempFrom != null)
                        IconButton(
                          icon: const Icon(Icons.clear,
                              size: 18, color: Colors.red),
                          onPressed: () =>
                              setDialogState(() => tempFrom = null),
                        ),
                    ],
                  ),
                ),
                const Divider(),
                // إلى تاريخ
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.event, size: 20),
                  title:
                      const Text('إلى تاريخ', style: TextStyle(fontSize: 14)),
                  subtitle: Text(
                    tempTo != null
                        ? '${tempTo!.day}/${tempTo!.month}/${tempTo!.year}'
                        : 'غير محدد',
                    style: TextStyle(
                      color: tempTo != null
                          ? const Color(0xFF1A237E)
                          : Colors.grey,
                      fontWeight:
                          tempTo != null ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit_calendar, size: 20),
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: tempTo ?? DateTime.now(),
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2030),
                            locale: const Locale('ar'),
                          );
                          if (picked != null) {
                            setDialogState(() => tempTo = picked);
                          }
                        },
                      ),
                      if (tempTo != null)
                        IconButton(
                          icon: const Icon(Icons.clear,
                              size: 18, color: Colors.red),
                          onPressed: () => setDialogState(() => tempTo = null),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                // اختصارات سريعة
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _buildQuickDateChip('اليوم', () {
                      final now = DateTime.now();
                      final today = DateTime(now.year, now.month, now.day);
                      setDialogState(() {
                        tempFrom = today;
                        tempTo = today;
                      });
                    }),
                    _buildQuickDateChip('هذا الأسبوع', () {
                      final now = DateTime.now();
                      final today = DateTime(now.year, now.month, now.day);
                      setDialogState(() {
                        tempFrom = today;
                        tempTo = today.add(const Duration(days: 7));
                      });
                    }),
                    _buildQuickDateChip('هذا الشهر', () {
                      final now = DateTime.now();
                      setDialogState(() {
                        tempFrom = DateTime(now.year, now.month, 1);
                        tempTo = DateTime(now.year, now.month + 1, 0);
                      });
                    }),
                    _buildQuickDateChip('الشهر القادم', () {
                      final now = DateTime.now();
                      setDialogState(() {
                        tempFrom = DateTime(now.year, now.month + 1, 1);
                        tempTo = DateTime(now.year, now.month + 2, 0);
                      });
                    }),
                    _buildQuickDateChip('منتهي', () {
                      final now = DateTime.now();
                      final today = DateTime(now.year, now.month, now.day);
                      setDialogState(() {
                        tempFrom = DateTime(2020);
                        tempTo = today.subtract(const Duration(days: 1));
                      });
                    }),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                setState(() {
                  _dateFrom = null;
                  _dateTo = null;
                });
                _loadSubscribers();
                Navigator.pop(context);
              },
              child: const Text('مسح الفلتر',
                  style: TextStyle(color: Colors.orange)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _dateFrom = tempFrom;
                  _dateTo = tempTo;
                });
                _loadSubscribers();
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1A237E),
              ),
              child: const Text('تطبيق', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  /// بناء زر اختصار سريع للتاريخ
  Widget _buildQuickDateChip(String label, VoidCallback onTap) {
    return ActionChip(
      label: Text(label, style: const TextStyle(fontSize: 11)),
      onPressed: onTap,
      backgroundColor: Colors.grey.shade100,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      visualDensity: VisualDensity.compact,
    );
  }

  /// بناء صف في الجدول
  Widget _buildTableRow(Map<String, dynamic> sub, int index) {
    final displayName = sub['display_name'] ?? sub['username'] ?? 'غير معروف';
    final phone = sub['phone']?.toString() ?? '';
    final zoneName = sub['zone_name']?.toString() ?? '';
    final fatName = sub['fat_name']?.toString() ?? '';
    final status = sub['status']?.toString() ?? '';
    final expires = sub['expires']?.toString() ?? '';
    final profileName = sub['profile_name']?.toString() ?? '';
    final username = sub['username']?.toString() ?? '';
    final subscriptionId = sub['subscription_id']?.toString() ??
        sub['customer_id']?.toString() ??
        '';
    final statusColor = _getStatusColor(status);
    final isSelected = _selectedIds.contains(subscriptionId);

    return Material(
      color: isSelected
          ? const Color(0xFF1A237E).withValues(alpha: 0.15)
          : (index.isEven ? Colors.grey.shade50 : Colors.white),
      child: InkWell(
        onTap: () {
          if (_isSelectionMode) {
            _toggleSelection(subscriptionId);
          } else {
            _showSubscriberDetails(sub);
          }
        },
        onLongPress: () {
          if (!_isSelectionMode) {
            _toggleSelectionMode();
            _toggleSelection(subscriptionId);
          }
        },
        child: Container(
          height: 56,
          decoration: BoxDecoration(
            border: Border(
                bottom: BorderSide(color: Colors.grey.shade300, width: 1)),
          ),
          child: Row(
            children: [
              // مربع التحديد أو الرقم
              if (_isSelectionMode)
                SizedBox(
                  width: 50,
                  child: Checkbox(
                    value: isSelected,
                    onChanged: (value) => _toggleSelection(subscriptionId),
                    activeColor: const Color(0xFF1A237E),
                  ),
                )
              else
                SizedBox(
                  width: 40,
                  child: Center(
                    child: Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Center(
                        child: Text(
                          '${index + 1}',
                          style: TextStyle(
                              fontSize: 10,
                              color: statusColor,
                              fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ),
                ),
              // الاسم
              _buildTableCell(displayName, flex: 3, isBold: true),
              // الهاتف
              _buildTableCell(phone.isNotEmpty ? phone : '-',
                  flex: 2, color: phone.isEmpty ? Colors.grey : null),
              // المنطقة
              _buildTableCell(zoneName.isNotEmpty ? zoneName : '-',
                  flex: 2,
                  color: zoneName.isEmpty ? Colors.grey : Colors.blue.shade700),
              // FAT
              _buildTableCell(fatName.isNotEmpty ? fatName : '-',
                  flex: 2,
                  color:
                      fatName.isEmpty ? Colors.grey : Colors.purple.shade700),
              // الحالة
              Expanded(
                flex: 1,
                child: Center(
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _getStatusShortName(status),
                      style: TextStyle(
                          fontSize: 11,
                          color: statusColor,
                          fontWeight: FontWeight.bold),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ),
              // تاريخ الانتهاء
              _buildTableCell(_formatExpiryDate(expires),
                  flex: 2, color: _getExpiryColor(expires)),
              // الباقة
              _buildTableCell(profileName.isNotEmpty ? profileName : '-',
                  flex: 2, color: profileName.isEmpty ? Colors.grey : null),
              // اسم المستخدم
              _buildTableCell(username.isNotEmpty ? username : '-',
                  flex: 2,
                  color: username.isEmpty ? Colors.grey : Colors.teal.shade700),
            ],
          ),
        ),
      ),
    );
  }

  /// بناء خلية في الجدول
  Widget _buildTableCell(String text,
      {int flex = 1, bool isBold = false, Color? color}) {
    return Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700, // خط عريض جداً
            color: Colors.black, // أسود دائماً
          ),
          overflow: TextOverflow.ellipsis,
          maxLines: 2,
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  /// اسم الحالة مختصر
  String _getStatusShortName(String? status) {
    switch (status?.toLowerCase()) {
      case 'active':
        return 'نشط';
      case 'inactive':
        return 'متوقف';
      case 'expired':
        return 'منتهي';
      case 'suspended':
        return 'معلق';
      default:
        return status ?? '-';
    }
  }

  /// تنسيق تاريخ الانتهاء
  String _formatExpiryDate(String? expires) {
    if (expires == null || expires.isEmpty) return '-';
    try {
      final date = DateTime.parse(expires);
      final now = DateTime.now();
      final diff = date.difference(now).inDays;

      // عرض التاريخ بشكل مختصر
      final day = date.day.toString().padLeft(2, '0');
      final month = date.month.toString().padLeft(2, '0');

      if (diff < 0) {
        return '$day/$month (${diff.abs()}-)'; // منتهي
      } else if (diff == 0) {
        return '$day/$month (اليوم)';
      } else if (diff <= 7) {
        return '$day/$month ($diff)';
      } else {
        return '$day/$month';
      }
    } catch (e) {
      return '-';
    }
  }

  /// لون تاريخ الانتهاء
  Color _getExpiryColor(String? expires) {
    if (expires == null || expires.isEmpty) return Colors.grey;
    try {
      final date = DateTime.parse(expires);
      final now = DateTime.now();
      final diff = date.difference(now).inDays;

      if (diff < 0) return Colors.red.shade700; // منتهي
      if (diff <= 3) return Colors.orange.shade700; // قريب جداً
      if (diff <= 7) return Colors.amber.shade700; // قريب
      return Colors.green.shade700; // آمن
    } catch (e) {
      return Colors.grey;
    }
  }

  String _formatExpires(String expires) {
    try {
      final date = DateTime.parse(expires);
      final now = DateTime.now();
      final diff = date.difference(now);

      if (diff.isNegative) {
        return 'منتهي منذ ${diff.inDays.abs()} يوم';
      } else if (diff.inDays == 0) {
        return 'ينتهي اليوم';
      } else if (diff.inDays == 1) {
        return 'ينتهي غداً';
      } else {
        return 'ينتهي بعد ${diff.inDays} يوم';
      }
    } catch (e) {
      return expires;
    }
  }

  void _copyCustomerId(String customerId) {
    Clipboard.setData(ClipboardData(text: customerId));
    _showMessage('تم نسخ معرف العميل: $customerId');
  }

  Widget _buildEmptyState() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.cloud_download,
              size: 80,
              color: Colors.grey[300],
            ),
            const SizedBox(height: 16),
            Text(
              'لا توجد بيانات محفوظة',
              style: TextStyle(
                fontSize: 18,
                color: Colors.grey[600],
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'اضغط على "جلب البيانات" في الأعلى',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[500],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
