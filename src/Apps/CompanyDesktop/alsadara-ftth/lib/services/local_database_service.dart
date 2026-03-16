import 'package:path/path.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'dart:convert';

/// خدمة قاعدة البيانات المحلية للمشتركين
/// تستخدم JSON للتخزين لتجنب مشاكل SQLite على Windows
class LocalDatabaseService {
  static LocalDatabaseService? _instance;
  static LocalDatabaseService get instance =>
      _instance ??= LocalDatabaseService._internal();

  LocalDatabaseService._internal();

  // مجلد البيانات
  late Directory _dataDir;
  bool _initialized = false;

  // البيانات في الذاكرة
  List<Map<String, dynamic>> _subscribers = [];
  List<Map<String, dynamic>> _userPhones = [];
  List<Map<String, dynamic>> _addresses = [];

  /// تهيئة قاعدة البيانات
  Future<void> initialize() async {
    if (_initialized) return;

    final appDir = await getApplicationDocumentsDirectory();
    _dataDir = Directory(join(appDir.path, 'alsadara_local_db'));
    if (!await _dataDir.exists()) {
      await _dataDir.create(recursive: true);
    }

    // تحميل البيانات من الملفات
    await _loadAllData();

    _initialized = true;
  }

  /// تحميل جميع البيانات من الملفات
  Future<void> _loadAllData() async {
    _subscribers = await _loadJsonFile('subscribers.json');
    _userPhones = await _loadJsonFile('user_phones.json');
    _addresses = await _loadJsonFile('addresses.json');
    print(
        '📦 تم تحميل: ${_subscribers.length} مشترك, ${_userPhones.length} هاتف, ${_addresses.length} عنوان');
  }

  /// إعادة تحميل البيانات من الملفات (تحديث)
  Future<void> refresh() async {
    if (!_initialized) {
      await initialize();
      return;
    }
    await _loadAllData();
  }

  /// تحميل ملف JSON
  Future<List<Map<String, dynamic>>> _loadJsonFile(String fileName) async {
    final file = File(join(_dataDir.path, fileName));
    if (await file.exists()) {
      try {
        final content = await file.readAsString();
        final List<dynamic> data = json.decode(content);
        return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      } catch (e) {
        print('خطأ في قراءة $fileName');
        return [];
      }
    }
    return [];
  }

  /// حفظ ملف JSON
  Future<void> _saveJsonFile(
      String fileName, List<Map<String, dynamic>> data) async {
    final file = File(join(_dataDir.path, fileName));
    await file.writeAsString(json.encode(data));
  }

  /// حفظ المشتركين
  Future<void> _saveSubscribers() async {
    await _saveJsonFile('subscribers.json', _subscribers);
  }

  /// حفظ أرقام الهواتف
  Future<void> _saveUserPhones() async {
    await _saveJsonFile('user_phones.json', _userPhones);
  }

  /// حفظ العناوين
  Future<void> _saveAddresses() async {
    await _saveJsonFile('addresses.json', _addresses);
  }

  // =============== عمليات المشتركين ===============

  /// إدراج أو تحديث مشترك
  Future<void> upsertSubscriber(Map<String, dynamic> subscriber) async {
    if (!_initialized) await initialize();

    final customerId = subscriber['customerId']?.toString() ?? '';
    final existingIndex =
        _subscribers.indexWhere((s) => s['customer_id'] == customerId);

    final record = {
      'customer_id': customerId,
      'username': subscriber['username'] ?? '',
      'first_name': subscriber['firstName'] ?? '',
      'last_name': subscriber['lastName'] ?? '',
      'display_name': subscriber['displayName'] ?? '',
      'zone_id': subscriber['zoneId']?.toString() ?? '',
      'zone_name': subscriber['zoneName'] ?? '',
      'parent_zone_id': subscriber['parentZoneId']?.toString() ?? '',
      'parent_zone_name': subscriber['parentZoneName'] ?? '',
      'status': subscriber['status'] ?? '',
      'profile_name': subscriber['profileName'] ?? '',
      'download_speed': subscriber['downloadSpeed']?.toString() ?? '',
      'upload_speed': subscriber['uploadSpeed']?.toString() ?? '',
      'expires': subscriber['expires'] ?? '',
      'created_at': subscriber['createdAt'] ?? '',
      'updated_at': subscriber['updatedAt'] ?? '',
      'synced_at': DateTime.now().toIso8601String(),
    };

    if (existingIndex >= 0) {
      _subscribers[existingIndex] = record;
    } else {
      _subscribers.add(record);
    }

    await _saveSubscribers();
  }

  /// إدراج مجموعة مشتركين
  Future<void> batchInsertSubscribers(
      List<Map<String, dynamic>> subscribers) async {
    if (!_initialized) await initialize();

    print('📥 استلام ${subscribers.length} مشترك للإدراج');

    for (final subscriber in subscribers) {
      final subscriptionId = subscriber['subscriptionId']?.toString() ?? '';
      final customerId = subscriber['customerId']?.toString() ?? subscriptionId;

      // تخطي العناصر بدون معرف
      if (subscriptionId.isEmpty) {
        print('⚠️ تخطي مشترك بدون معرف');
        continue;
      }

      final existingIndex = _subscribers
          .indexWhere((s) => s['subscription_id'] == subscriptionId);

      final record = {
        // المعرفات
        'subscription_id': subscriptionId,
        'customer_id': customerId,

        // بيانات الاشتراك الأساسية
        'username': subscriber['username'] ?? '',
        'status': subscriber['status'] ?? '',
        'auto_renew': subscriber['autoRenew'] ?? false,

        // بيانات العميل
        'display_name': subscriber['displayName'] ?? '',

        // الحزمة (المعرف فقط)
        'bundle_id': subscriber['bundleId'] ?? '',

        // المنطقة - المعرف والاسم
        'zone_id': subscriber['zoneId'] ?? '',
        'zone_name': subscriber['zoneName'] ?? '',

        // الخدمات
        'services': subscriber['services'] ?? [],
        'profile_name': subscriber['profileName'] ?? '',

        // التواريخ
        'started_at': subscriber['startedAt'] ?? '',
        'expires': subscriber['expires'] ?? '',
        'commitment_period': subscriber['commitmentPeriod'] ?? '',

        // بيانات الاتصال
        'locked_mac': subscriber['lockedMac'] ?? '',

        // حالات خاصة
        'is_suspended': subscriber['isSuspended'] ?? false,
        'suspension_reason': subscriber['suspensionReason'] ?? '',
        'is_quota_based': subscriber['isQuotaBased'] ?? false,
        'total_quota_in_bytes': subscriber['totalQuotaInBytes'] ?? '',

        // معلومات إضافية
        'self_display_value': subscriber['selfDisplayValue'] ?? '',
        'phone': subscriber['phone'] ?? '',

        // بيانات الشبكة (FDT/FAT/الجهاز)
        'user_id': subscriber['userId'] ?? '',
        'fdt_name': subscriber['fdtName'] ?? '',
        'fat_name': subscriber['fatName'] ?? '',
        'device_serial': subscriber['deviceSerial'] ?? '',
        'gps_lat': subscriber['gpsLat'] ?? '',
        'gps_lng': subscriber['gpsLng'] ?? '',

        // حالات إضافية
        'is_trial': subscriber['isTrial'] ?? false,
        'is_pending': subscriber['isPending'] ?? false,
        'details_fetched': subscriber['detailsFetched'] ?? false,
        'details_fetched_at': subscriber['detailsFetchedAt'] ?? '',

        'synced_at': DateTime.now().toIso8601String(),
      };

      if (existingIndex >= 0) {
        _subscribers[existingIndex] = record;
      } else {
        _subscribers.add(record);
      }
    }

    print('💾 حفظ ${_subscribers.length} مشترك للملف');
    await _saveSubscribers();
  }

  /// تحديث رقم هاتف مشترك
  Future<void> updateSubscriberPhone(String customerId, String phone) async {
    if (!_initialized) await initialize();

    bool updated = false;
    for (int i = 0; i < _subscribers.length; i++) {
      if (_subscribers[i]['customer_id']?.toString() == customerId) {
        _subscribers[i]['phone'] = phone;
        updated = true;
        // لا نخرج من الحلقة لأنه قد يكون هناك أكثر من اشتراك لنفس العميل
      }
    }

    if (updated) {
      await _saveSubscribers();
    }
  }

  /// تحديث أرقام الهواتف بشكل دفعي
  Future<int> batchUpdatePhones(List<Map<String, String>> phones) async {
    if (!_initialized) await initialize();

    int updatedCount = 0;
    for (final phoneData in phones) {
      final customerId = phoneData['customerId'] ?? '';
      final phone = phoneData['phone'] ?? '';

      if (customerId.isEmpty || phone.isEmpty) continue;

      for (int i = 0; i < _subscribers.length; i++) {
        if (_subscribers[i]['customer_id']?.toString() == customerId) {
          _subscribers[i]['phone'] = phone;
          updatedCount++;
        }
      }
    }

    if (updatedCount > 0) {
      await _saveSubscribers();
    }

    return updatedCount;
  }

  /// تحديث بيانات العملاء الكاملة بشكل دفعي
  Future<int> batchUpdateCustomerDetails(
      List<Map<String, dynamic>> customers) async {
    if (!_initialized) await initialize();

    int updatedCount = 0;
    for (final customerData in customers) {
      final customerId = customerData['customerId']?.toString() ?? '';
      if (customerId.isEmpty) continue;

      for (int i = 0; i < _subscribers.length; i++) {
        if (_subscribers[i]['customer_id']?.toString() == customerId) {
          // تحديث جميع الحقول المتوفرة
          customerData.forEach((key, value) {
            if (key != 'customerId' &&
                value != null &&
                value.toString().isNotEmpty) {
              _subscribers[i][key] = value;
            }
          });
          updatedCount++;
        }
      }
    }

    if (updatedCount > 0) {
      await _saveSubscribers();
    }

    return updatedCount;
  }

  /// تحديث بيانات الاشتراكات من /api/addresses بشكل دفعي
  Future<int> batchUpdateSubscriptionAddresses(
      List<Map<String, dynamic>> addresses) async {
    if (!_initialized) await initialize();

    print('💾 محاولة تخزين ${addresses.length} عنوان');

    // طباعة بعض المعرفات للمقارنة
    if (addresses.isNotEmpty) {
      print('🔍 أول customerId في addresses: ${addresses.first['customerId']}');
    }
    if (_subscribers.isNotEmpty) {
      print(
          '🔍 أول customer_id في subscribers: ${_subscribers.first['customer_id']}');
    }

    int updatedCount = 0;
    int notFoundCount = 0;

    for (final addressData in addresses) {
      final customerId = addressData['customerId']?.toString() ?? '';
      if (customerId.isEmpty) continue;

      bool found = false;
      for (int i = 0; i < _subscribers.length; i++) {
        if (_subscribers[i]['customer_id']?.toString() == customerId) {
          // تحديث جميع الحقول - حتى الفارغة لضمان الاتساق
          addressData.forEach((key, value) {
            if (key != 'customerId') {
              // تحديث القيمة حتى لو كانت فارغة (لمسح البيانات القديمة الخاطئة)
              _subscribers[i][key] = value;
            }
          });
          updatedCount++;
          found = true;
          break;
        }
      }

      if (!found) {
        notFoundCount++;
      }
    }

    print('✅ تم تحديث $updatedCount | ❌ لم يوجد $notFoundCount');

    if (updatedCount > 0) {
      await _saveSubscribers();
      print('💾 تم حفظ الملف');
    }

    return updatedCount;
  }

  /// الحصول على جميع المشتركين
  Future<List<Map<String, dynamic>>> getAllSubscribers() async {
    if (!_initialized) await initialize();
    // ترتيب حسب الاسم
    final sorted = List<Map<String, dynamic>>.from(_subscribers);
    sorted.sort((a, b) => (a['display_name'] ?? '')
        .toString()
        .compareTo((b['display_name'] ?? '').toString()));
    return sorted;
  }

  /// الحصول على المشتركين الذين لم تُجلب تفاصيلهم
  Future<List<String>> getSubscribersWithoutDetails() async {
    if (!_initialized) await initialize();
    final missing = <String>[];
    for (final sub in _subscribers) {
      if (sub['details_fetched'] != true) {
        final customerId = sub['customer_id']?.toString() ?? '';
        if (customerId.isNotEmpty) {
          missing.add(customerId);
        }
      }
    }
    return missing;
  }

  /// الحصول على إحصائيات التفاصيل المجلوبة
  Future<Map<String, int>> getDetailsStats() async {
    if (!_initialized) await initialize();
    int withDetails = 0;
    int withoutDetails = 0;
    for (final sub in _subscribers) {
      if (sub['details_fetched'] == true) {
        withDetails++;
      } else {
        withoutDetails++;
      }
    }
    return {
      'with_details': withDetails,
      'without_details': withoutDetails,
      'total': _subscribers.length,
    };
  }

  /// الحصول على عدد المشتركين
  Future<int> getSubscribersCount() async {
    if (!_initialized) await initialize();
    return _subscribers.length;
  }

  /// البحث عن مشتركين
  Future<List<Map<String, dynamic>>> searchSubscribers({
    String? query,
    String? zone,
    String? fat,
    String? status,
    String? sortBy,
    bool ascending = true,
  }) async {
    if (!_initialized) await initialize();

    var result = List<Map<String, dynamic>>.from(_subscribers);

    // البحث بالاسم أو الهاتف أو معرف العميل
    if (query != null && query.isNotEmpty) {
      final searchLower = query.toLowerCase();
      result = result.where((s) {
        final displayName = (s['display_name'] ?? '').toString().toLowerCase();
        final username = (s['username'] ?? '').toString().toLowerCase();
        final customerId = (s['customer_id'] ?? '').toString().toLowerCase();
        return displayName.contains(searchLower) ||
            username.contains(searchLower) ||
            customerId.contains(searchLower);
      }).toList();
    }

    // فلترة بالمنطقة
    if (zone != null && zone.isNotEmpty) {
      result = result.where((s) => s['zone_name'] == zone).toList();
    }

    // فلترة بالحالة
    if (status != null && status.isNotEmpty) {
      result = result.where((s) => s['status'] == status).toList();
    }

    // فلترة بـ FAT
    if (fat != null && fat.isNotEmpty) {
      final customerIdsWithFat = _addresses
          .where((a) => a['fat_name'] == fat)
          .map((a) => a['customer_id'])
          .toSet();
      result = result
          .where((s) => customerIdsWithFat.contains(s['customer_id']))
          .toList();
    }

    // الترتيب
    String sortField = 'display_name';
    if (sortBy != null) {
      switch (sortBy) {
        case 'expires':
          sortField = 'expires';
          break;
        case 'zone':
          sortField = 'zone_name';
          break;
        case 'status':
          sortField = 'status';
          break;
        case 'name':
        default:
          sortField = 'display_name';
      }
    }

    result.sort((a, b) {
      final aVal = (a[sortField] ?? '').toString();
      final bVal = (b[sortField] ?? '').toString();
      return ascending ? aVal.compareTo(bVal) : bVal.compareTo(aVal);
    });

    return result;
  }

  /// الحصول على مشترك بمعرفه
  Future<Map<String, dynamic>?> getSubscriberById(String customerId) async {
    if (!_initialized) await initialize();
    try {
      return _subscribers.firstWhere((s) => s['customer_id'] == customerId);
    } catch (_) {
      return null;
    }
  }

  /// الحصول على قائمة المناطق الفريدة
  Future<List<String>> getDistinctZones() async {
    if (!_initialized) await initialize();
    final zones = _subscribers
        .map((s) => s['zone_name']?.toString() ?? '')
        .where((z) => z.isNotEmpty)
        .toSet()
        .toList();
    zones.sort();
    return zones;
  }

  /// الحصول على قائمة FDT الفريدة
  Future<List<String>> getDistinctFDTs() async {
    if (!_initialized) await initialize();
    final fdts = _subscribers
        .map((s) => s['fdt_name']?.toString() ?? '')
        .where((f) => f.isNotEmpty)
        .toSet()
        .toList();
    fdts.sort();
    return fdts;
  }

  /// الحصول على قائمة FAT الفريدة
  Future<List<String>> getDistinctFATs() async {
    if (!_initialized) await initialize();
    final fats = _subscribers
        .map((s) => s['fat_name']?.toString() ?? '')
        .where((f) => f.isNotEmpty)
        .toSet()
        .toList();
    fats.sort();
    return fats;
  }

  /// الحصول على قائمة FAT الفريدة (للتوافق)
  Future<List<String>> getDistinctFats() async {
    return getDistinctFATs();
  }

  /// الحصول على قائمة الحالات الفريدة
  Future<List<String>> getDistinctStatuses() async {
    if (!_initialized) await initialize();
    final statuses = _subscribers
        .map((s) => s['status']?.toString() ?? '')
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList();
    statuses.sort();
    return statuses;
  }

  /// الحصول على قائمة الباقات الفريدة
  Future<List<String>> getDistinctProfiles() async {
    if (!_initialized) await initialize();
    final profiles = _subscribers
        .map((s) => s['profile_name']?.toString() ?? '')
        .where((p) => p.isNotEmpty)
        .toSet()
        .toList();
    profiles.sort();
    return profiles;
  }

  /// الحصول على جميع معرفات الاشتراكات
  Future<List<String>> getAllSubscriptionIds() async {
    if (!_initialized) await initialize();
    return _subscribers
        .map((s) => s['subscription_id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toList();
  }

  /// للتوافق مع الكود القديم
  Future<List<String>> getAllCustomerIds() async {
    return getAllSubscriptionIds();
  }

  // =============== عمليات أرقام الهواتف ===============

  /// إدراج أو تحديث رقم هاتف
  Future<void> upsertUserPhone(Map<String, dynamic> userPhone) async {
    if (!_initialized) await initialize();

    final userId =
        userPhone['userId']?.toString() ?? userPhone['id']?.toString() ?? '';
    final existingIndex = _userPhones.indexWhere((p) => p['user_id'] == userId);

    final record = {
      'user_id': userId,
      'user_name': userPhone['userName'] ?? userPhone['name'] ?? '',
      'phone_number': userPhone['phoneNumber'] ?? userPhone['phone'] ?? '',
    };

    if (existingIndex >= 0) {
      _userPhones[existingIndex] = record;
    } else {
      _userPhones.add(record);
    }

    await _saveUserPhones();
  }

  /// إدراج مجموعة أرقام هواتف وربطها بالمشتركين
  Future<void> batchInsertUserPhones(List<Map<String, dynamic>> phones) async {
    if (!_initialized) await initialize();

    for (final phone in phones) {
      final subscriptionId = phone['subscriptionId']?.toString() ??
          phone['customerId']?.toString() ??
          '';
      final userId =
          phone['userId']?.toString() ?? phone['id']?.toString() ?? '';
      final existingIndex =
          _userPhones.indexWhere((p) => p['user_id'] == userId);

      final record = {
        'user_id': userId,
        'subscription_id': subscriptionId,
        'user_name': phone['userName'] ?? phone['name'] ?? '',
        'phone_number': phone['phoneNumber'] ??
            phone['phone'] ??
            phone['primaryPhone'] ??
            '',
      };

      if (existingIndex >= 0) {
        _userPhones[existingIndex] = record;
      } else {
        _userPhones.add(record);
      }

      // ربط user_id بالمشترك في subscribers
      if (subscriptionId.isNotEmpty && userId.isNotEmpty) {
        final subIndex = _subscribers
            .indexWhere((s) => s['subscription_id'] == subscriptionId);
        if (subIndex >= 0) {
          _subscribers[subIndex]['user_id'] = userId;
        }
      }
    }

    await _saveUserPhones();
    await _saveSubscribers(); // حفظ التغييرات على المشتركين
  }

  /// إدراج مجموعة مستخدمين وربطهم بالمشتركين عن طريق الاسم
  Future<void> batchInsertUserPhonesAndMatchByName(
      List<Map<String, dynamic>> users) async {
    if (!_initialized) await initialize();

    int matchedCount = 0;
    int totalCount = users.length;

    for (final user in users) {
      final userId = user['userId']?.toString() ?? '';
      final userName = (user['userName'] ?? '').toString().trim();
      final userPhone = user['phone'] ?? '';

      if (userId.isEmpty) continue;

      // حفظ بيانات المستخدم
      final existingIndex =
          _userPhones.indexWhere((p) => p['user_id'] == userId);

      final record = {
        'user_id': userId,
        'user_name': userName,
        'phone_number': userPhone,
      };

      if (existingIndex >= 0) {
        _userPhones[existingIndex] = record;
      } else {
        _userPhones.add(record);
      }

      // البحث عن المشترك بنفس الاسم
      if (userName.isNotEmpty) {
        for (int i = 0; i < _subscribers.length; i++) {
          final subName =
              (_subscribers[i]['display_name'] ?? '').toString().trim();
          if (subName == userName) {
            _subscribers[i]['user_id'] = userId;
            matchedCount++;
            break; // نأخذ أول تطابق فقط
          }
        }
      }
    }

    print('✅ تم ربط $matchedCount من $totalCount مستخدم بالاشتراكات (بالاسم)');

    await _saveUserPhones();
    await _saveSubscribers();
  }

  /// ربط بيانات العملاء بالاشتراكات عن طريق customer_id
  Future<void> linkCustomerDataToSubscribers(
      List<Map<String, dynamic>> customerData) async {
    if (!_initialized) await initialize();

    int linkedCount = 0;
    int totalCount = customerData.length;

    for (final customer in customerData) {
      final customerId = customer['customerId']?.toString() ?? '';
      final userName = (customer['userName'] ?? '').toString().trim();
      final userPhone = customer['phone'] ?? '';

      if (customerId.isEmpty) continue;

      // البحث عن الاشتراك بنفس الـ customer_id
      for (int i = 0; i < _subscribers.length; i++) {
        // محاولة المطابقة مع customer_id أولاً، ثم subscription_id
        final subCustomerId =
            (_subscribers[i]['customer_id'] ?? '').toString().trim();
        final subId =
            (_subscribers[i]['subscription_id'] ?? '').toString().trim();

        if (subCustomerId == customerId || subId == customerId) {
          // تحديث بيانات المشترك مباشرة
          _subscribers[i]['user_id'] = customerId;
          if (userPhone.isNotEmpty &&
              (_subscribers[i]['phone'] ?? '').toString().isEmpty) {
            _subscribers[i]['phone'] = userPhone;
          }
          // تحديث اسم العرض إذا كان فارغاً
          if (userName.isNotEmpty &&
              (_subscribers[i]['display_name'] ?? '').toString().isEmpty) {
            _subscribers[i]['display_name'] = userName;
          }
          linkedCount++;
          break;
        }
      }

      // حفظ في قائمة الهواتف أيضاً
      final existingIndex =
          _userPhones.indexWhere((p) => p['user_id'] == customerId);

      final record = {
        'user_id': customerId,
        'user_name': userName,
        'phone_number': userPhone,
      };

      if (existingIndex >= 0) {
        _userPhones[existingIndex] = record;
      } else {
        _userPhones.add(record);
      }
    }

    print(
        '✅ تم ربط $linkedCount من $totalCount عميل بالاشتراكات (بـ customer_id)');

    await _saveUserPhones();
    await _saveSubscribers();
  }

  /// الحصول على رقم هاتف مستخدم
  Future<String?> getUserPhone(String customerId) async {
    if (!_initialized) await initialize();
    try {
      final phone = _userPhones.firstWhere((p) => p['user_id'] == customerId);
      return phone['phone_number'] as String?;
    } catch (_) {
      return null;
    }
  }

  /// الحصول على عدد أرقام الهواتف
  Future<int> getUserPhonesCount() async {
    if (!_initialized) await initialize();
    return _userPhones.length;
  }

  // =============== عمليات العناوين ===============

  /// إدراج أو تحديث عنوان
  Future<void> upsertAddress(Map<String, dynamic> address) async {
    if (!_initialized) await initialize();

    final customerId = address['customerId']?.toString() ??
        address['accountId']?.toString() ??
        '';
    final addressId =
        address['addressId']?.toString() ?? address['id']?.toString() ?? '';

    final existingIndex = _addresses.indexWhere(
        (a) => a['customer_id'] == customerId && a['address_id'] == addressId);

    final record = {
      'customer_id': customerId,
      'address_id': addressId,
      'zone_id': address['zoneId']?.toString() ?? '',
      'zone_name': address['zoneName'] ?? '',
      'fat_id': address['fatId']?.toString() ?? '',
      'fat_name': address['fatName'] ?? '',
      'gps_lat': address['gpsLat']?.toString() ??
          address['latitude']?.toString() ??
          '',
      'gps_lng': address['gpsLng']?.toString() ??
          address['longitude']?.toString() ??
          '',
      'full_address': address['fullAddress'] ?? address['address'] ?? '',
    };

    if (existingIndex >= 0) {
      _addresses[existingIndex] = record;
    } else {
      _addresses.add(record);
    }

    await _saveAddresses();
  }

  /// إدراج مجموعة عناوين
  Future<void> batchInsertAddresses(
      List<Map<String, dynamic>> addresses) async {
    if (!_initialized) await initialize();

    for (final address in addresses) {
      final customerId = address['customerId']?.toString() ??
          address['accountId']?.toString() ??
          '';
      final addressId =
          address['addressId']?.toString() ?? address['id']?.toString() ?? '';

      final existingIndex = _addresses.indexWhere((a) =>
          a['customer_id'] == customerId && a['address_id'] == addressId);

      final record = {
        'customer_id': customerId,
        'address_id': addressId,
        'zone_id': address['zoneId']?.toString() ?? '',
        'zone_name': address['zoneName'] ?? '',
        'fat_id': address['fatId']?.toString() ?? '',
        'fat_name': address['fatName'] ?? '',
        'gps_lat': address['gpsLat']?.toString() ??
            address['latitude']?.toString() ??
            '',
        'gps_lng': address['gpsLng']?.toString() ??
            address['longitude']?.toString() ??
            '',
        'full_address': address['fullAddress'] ?? address['address'] ?? '',
      };

      if (existingIndex >= 0) {
        _addresses[existingIndex] = record;
      } else {
        _addresses.add(record);
      }
    }

    await _saveAddresses();
  }

  /// الحصول على عناوين مشترك
  Future<List<Map<String, dynamic>>> getAddressesForCustomer(
      String customerId) async {
    if (!_initialized) await initialize();
    return _addresses.where((a) => a['customer_id'] == customerId).toList();
  }

  /// الحصول على عدد العناوين
  Future<int> getAddressesCount() async {
    if (!_initialized) await initialize();
    return _addresses.length;
  }

  // =============== عمليات عامة ===============

  /// حذف اشتراكات محددة
  Future<void> deleteSubscribers(List<String> subscriptionIds) async {
    if (!_initialized) await initialize();
    if (subscriptionIds.isEmpty) return;

    final idsSet = subscriptionIds.toSet();
    final initialCount = _subscribers.length;

    // حذف من قائمة المشتركين
    _subscribers.removeWhere((sub) {
      final subId = sub['subscription_id']?.toString() ??
          sub['customer_id']?.toString() ??
          '';
      return idsSet.contains(subId);
    });

    // حذف من العناوين المرتبطة
    _addresses.removeWhere((addr) {
      final customerId = addr['customer_id']?.toString() ?? '';
      return idsSet.contains(customerId);
    });

    // حذف من أرقام الهواتف المرتبطة
    _userPhones.removeWhere((phone) {
      final customerId = phone['customer_id']?.toString() ?? '';
      return idsSet.contains(customerId);
    });

    // حفظ التغييرات
    await _saveSubscribers();
    await _saveAddresses();
    await _saveUserPhones();

    print('✅ تم حذف ${initialCount - _subscribers.length} اشتراك');
  }

  /// مسح جميع البيانات
  Future<void> clearAllData() async {
    if (!_initialized) await initialize();
    _subscribers = [];
    _userPhones = [];
    _addresses = [];
    await _saveSubscribers();
    await _saveUserPhones();
    await _saveAddresses();
  }

  /// مسح تفاصيل الاشتراكات فقط (FDT، FAT، MAC، IP، GPS)
  Future<void> clearAddressesData() async {
    if (!_initialized) await initialize();
    _addresses = [];
    await _saveAddresses();

    // أيضاً مسح حقول العناوين من المشتركين
    for (var sub in _subscribers) {
      // حقول الجهاز
      sub['fdt_name'] = '';
      sub['fat_name'] = '';
      sub['device_serial'] = '';
      // حقول العنوان
      sub['gps_lat'] = '';
      sub['gps_lng'] = '';
      // حقول إضافية
      sub['is_trial'] = false;
      sub['is_pending'] = false;
      // مسح علامة جلب التفاصيل - مهم!
      sub['details_fetched'] = false;
      sub['details_fetched_at'] = '';
    }
    await _saveSubscribers();
    print('✅ تم مسح تفاصيل الاشتراكات من ${_subscribers.length} مشترك');
  }

  /// مسح أرقام الهواتف فقط
  Future<void> clearPhonesData() async {
    if (!_initialized) await initialize();
    _userPhones = [];
    await _saveUserPhones();

    // أيضاً مسح حقل الهاتف من المشتركين
    for (var sub in _subscribers) {
      sub['phone'] = '';
    }
    await _saveSubscribers();
  }

  /// الحصول على إحصائيات القاعدة
  Future<Map<String, int>> getStatistics() async {
    if (!_initialized) await initialize();
    return {
      'subscribers': _subscribers.length,
      'phones': _userPhones.length,
      'addresses': _addresses.length,
    };
  }

  /// الحصول على آخر وقت مزامنة
  Future<DateTime?> getLastSyncTime() async {
    if (!_initialized) await initialize();
    if (_subscribers.isEmpty) return null;

    DateTime? lastSync;
    for (final subscriber in _subscribers) {
      final syncedAt = subscriber['synced_at'];
      if (syncedAt != null) {
        final dt = DateTime.tryParse(syncedAt.toString());
        if (dt != null && (lastSync == null || dt.isAfter(lastSync))) {
          lastSync = dt;
        }
      }
    }
    return lastSync;
  }

  /// إغلاق قاعدة البيانات (للتوافق)
  Future<void> close() async {
    // لا حاجة لإغلاق أي شيء مع JSON
    _initialized = false;
  }
}
