import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'local_database_service.dart';
import 'sync_settings_service.dart';
import 'auth_service.dart';

/// تقدم المزامنة
class SyncProgress {
  final String stage; // المرحلة الحالية
  final int current; // التقدم الحالي
  final int total; // الإجمالي
  final String message; // رسالة للمستخدم
  final int fetchedCount; // عدد العناصر المجلوبة
  final List<Map<String, dynamic>>? newItems; // العناصر الجديدة

  SyncProgress({
    required this.stage,
    required this.current,
    required this.total,
    required this.message,
    this.fetchedCount = 0,
    this.newItems,
  });

  double get percentage => total > 0 ? (current / total) * 100 : 0;
}

/// نتيجة المزامنة
class SyncResult {
  final bool success;
  final String message;
  final int subscribersCount;
  final int phonesCount;
  final int addressesCount;
  final Duration duration;
  final String? error;

  SyncResult({
    required this.success,
    required this.message,
    this.subscribersCount = 0,
    this.phonesCount = 0,
    this.addressesCount = 0,
    this.duration = Duration.zero,
    this.error,
  });
}

/// خدمة مزامنة البيانات من API
class SyncService {
  static const String _baseUrl = 'https://admin.ftth.iq';
  static const String _clientApp = '53d57a7f-3f89-4e9d-873b-3d071bc6dd9f';
  static const String _userRole = '0';

  final LocalDatabaseService _db = LocalDatabaseService.instance;
  final SyncSettingsService _settings = SyncSettingsService.instance;

  /// إعدادات الاشتراكات
  int get _subscriptionsPageSize => _settings.subscriptionsSettings.pageSize;
  int get _subscriptionsParallelPages =>
      _settings.subscriptionsSettings.parallelPages;

  /// إعدادات المشتركين
  int get _usersPageSize => _settings.usersSettings.pageSize;
  int get _usersParallelPages => _settings.usersSettings.parallelPages;

  /// إعدادات العناوين
  int get _addressesPageSize => _settings.addressesSettings.pageSize;
  int get _addressesParallelPages => _settings.addressesSettings.parallelPages;

  bool _isCancelled = false;
  bool get isCancelled => _isCancelled;

  // قائمة المعرفات الفاشلة لإعادة المحاولة
  final List<String> _failedBatchIds = [];

  /// إلغاء المزامنة
  void cancelSync() {
    _isCancelled = true;
  }

  /// إعادة تعيين حالة الإلغاء
  void resetCancellation() {
    _isCancelled = false;
    _failedBatchIds.clear();
  }

  /// الهيدرات الأساسية للـ API
  Map<String, String> _getHeaders(String token) {
    return {
      'Authorization': 'Bearer $token',
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      'x-client-app': _clientApp,
      'x-user-role': _userRole,
    };
  }

  /// طلب HTTP مع إعادة المحاولة
  Future<http.Response> _httpGetWithRetry(
    Uri url,
    Map<String, String> headers, {
    int maxRetries = 5,
    Duration timeout = const Duration(seconds: 90),
  }) async {
    int attempt = 0;
    while (attempt < maxRetries) {
      try {
        attempt++;
        final response = await http.get(url, headers: headers).timeout(timeout);
        return response;
      } on TimeoutException {
        print('⏱️ انتهت المهلة للمحاولة $attempt من $maxRetries');
        if (attempt >= maxRetries) rethrow;
        await Future.delayed(Duration(seconds: attempt * 2)); // انتظار متزايد
      } on SocketException {
        print('🔌 خطأ اتصال في المحاولة $attempt');
        if (attempt >= maxRetries) rethrow;
        await Future.delayed(Duration(seconds: attempt * 2));
      } on http.ClientException {
        // هذا الخطأ يحدث عندما السيرفر يغلق الاتصال مبكراً
        print('📡 خطأ عميل في المحاولة $attempt');
        if (attempt >= maxRetries) rethrow;
        // انتظار أطول للسماح للسيرفر بالتعافي
        await Future.delayed(Duration(seconds: attempt * 3));
      } catch (e) {
        print('❌ خطأ غير متوقع في المحاولة $attempt');
        if (attempt >= maxRetries) rethrow;
        await Future.delayed(Duration(seconds: attempt * 2));
      }
    }
    throw Exception('فشل الاتصال بعد $maxRetries محاولات');
  }

  /// مزامنة كاملة للبيانات
  Future<SyncResult> fullSync({
    required String token,
    required Function(SyncProgress) onProgress,
    bool fetchSubscribers = true,
    bool fetchPhones = true,
    bool fetchAddresses = true,
  }) async {
    _isCancelled = false;
    final stopwatch = Stopwatch()..start();

    try {
      // التأكد من تهيئة قاعدة البيانات
      await _db.initialize();

      int subscribersResult = 0;
      int phonesCount = 0;
      int addressesCount = 0;
      List<String> customerIds = [];

      // المرحلة 1: جلب المشتركين
      if (fetchSubscribers) {
        onProgress(SyncProgress(
          stage: 'subscribers',
          current: 0,
          total: 1,
          message: 'جاري جلب بيانات المشتركين...',
        ));

        subscribersResult = await _fetchAllSubscribers(
          token: token,
          onProgress: (current, total, fetchedCount, items) {
            onProgress(SyncProgress(
              stage: 'subscribers',
              current: current,
              total: total,
              message:
                  'جلب المشتركين: صفحة $current من $total ($fetchedCount مشترك)',
              fetchedCount: fetchedCount,
              newItems: items,
            ));
          },
        );

        if (_isCancelled) {
          return SyncResult(
            success: false,
            message: 'تم إلغاء المزامنة',
            duration: stopwatch.elapsed,
          );
        }
      }

      // جلب معرفات العملاء للمراحل التالية
      if (fetchPhones || fetchAddresses) {
        customerIds = await _db.getAllCustomerIds();
      }

      // المرحلة 2: جلب أرقام الهواتف
      if (fetchPhones && customerIds.isNotEmpty) {
        final totalPhoneBatches = (customerIds.length / _usersPageSize).ceil();

        onProgress(SyncProgress(
          stage: 'phones',
          current: 0,
          total: totalPhoneBatches,
          message: 'جاري جلب أرقام الهواتف...',
        ));

        phonesCount = await _fetchCustomerPhones(
          token: token,
          customerIds: customerIds,
          onProgress: (current, total) {
            onProgress(SyncProgress(
              stage: 'phones',
              current: current,
              total: total,
              message: 'جلب الهواتف: دفعة $current من $total',
            ));
          },
        );

        if (_isCancelled) {
          return SyncResult(
            success: false,
            message: 'تم إلغاء المزامنة',
            subscribersCount: subscribersResult,
            duration: stopwatch.elapsed,
          );
        }
      }

      // المرحلة 3: جلب العناوين
      if (fetchAddresses && customerIds.isNotEmpty) {
        final totalAddressRequests = customerIds.length;

        onProgress(SyncProgress(
          stage: 'addresses',
          current: 0,
          total: totalAddressRequests,
          message: 'جاري جلب العناوين...',
        ));

        addressesCount = await _fetchAddresses(
          token: token,
          customerIds: customerIds,
          onProgress: (current, total) {
            onProgress(SyncProgress(
              stage: 'addresses',
              current: current,
              total: total,
              message: 'جلب العناوين: $current من $total',
            ));
          },
        );
      }

      if (_isCancelled) {
        return SyncResult(
          success: false,
          message: 'تم إلغاء المزامنة',
          subscribersCount: subscribersResult,
          phonesCount: phonesCount,
          duration: stopwatch.elapsed,
        );
      }

      stopwatch.stop();

      return SyncResult(
        success: true,
        message: 'تمت المزامنة بنجاح',
        subscribersCount: subscribersResult,
        phonesCount: phonesCount,
        addressesCount: addressesCount,
        duration: stopwatch.elapsed,
      );
    } catch (e) {
      stopwatch.stop();
      return SyncResult(
        success: false,
        message: 'فشلت المزامنة',
        error: e.toString(),
        duration: stopwatch.elapsed,
      );
    }
  }

  /// جلب جميع المشتركين - جلب متوازي سريع
  Future<int> _fetchAllSubscribers({
    required String token,
    required Function(int current, int total, int fetchedCount,
            List<Map<String, dynamic>>? items)
        onProgress,
  }) async {
    // تهيئة الإعدادات
    await _settings.initialize();

    // طباعة الإعدادات الحالية للتأكد
    print(
        '⚙️ إعدادات الاشتراكات: $_subscriptionsPageSize/صفحة، $_subscriptionsParallelPages متوازي');

    int totalCount = 0;
    int totalPages = 1;

    // أولاً: جلب الصفحة الأولى لمعرفة إجمالي الصفحات
    final firstPageUrl = Uri.parse(
        '$_baseUrl/api/subscriptions?sortCriteria.property=expires&sortCriteria.direction=asc&hierarchyLevel=0&pageNumber=1&pageSize=$_subscriptionsPageSize');

    final firstResponse = await _httpGetWithRetry(
      firstPageUrl,
      _getHeaders(token),
      maxRetries: 3,
      timeout: const Duration(seconds: 60),
    );

    if (firstResponse.statusCode == 401) {
      throw Exception('انتهت صلاحية الجلسة - يرجى تسجيل الدخول مرة أخرى');
    }

    if (firstResponse.statusCode != 200) {
      throw Exception('فشل جلب المشتركين: ${firstResponse.statusCode}');
    }

    final firstData = json.decode(firstResponse.body);
    final List<dynamic> firstItems = firstData['items'] ?? [];

    if (firstData['totalCount'] != null) {
      final totalItems = firstData['totalCount'] as int;
      totalPages = (totalItems / _subscriptionsPageSize).ceil();
      if (totalPages == 0) totalPages = 1;
      print(
          '📊 إجمالي العناصر: $totalItems, الصفحات: $totalPages ($_subscriptionsPageSize/صفحة، $_subscriptionsParallelPages متوازي)');
    }

    // معالجة الصفحة الأولى
    final firstConverted = _convertSubscribers(firstItems);
    await _db.batchInsertSubscribers(firstConverted);
    totalCount += firstItems.length;
    onProgress(1, totalPages, totalCount, firstConverted);

    if (totalPages <= 1 || _isCancelled) {
      return totalCount;
    }

    // جلب باقي الصفحات بشكل متوازي
    int currentPage = 2;
    while (currentPage <= totalPages && !_isCancelled) {
      final endPage = (currentPage + _subscriptionsParallelPages - 1)
          .clamp(currentPage, totalPages);
      final pagesToFetch =
          List.generate(endPage - currentPage + 1, (i) => currentPage + i);

      print('🚀 جلب متوازي: صفحات $currentPage إلى $endPage');

      // جلب جميع الصفحات في الدفعة معاً مع التتبع
      final Map<int, List<dynamic>> successfulPages = {};
      List<int> failedPages = List.from(pagesToFetch);

      // محاولات متعددة لجلب جميع الصفحات
      int retryAttempt = 0;
      const maxBatchRetries = 3;

      while (failedPages.isNotEmpty &&
          retryAttempt < maxBatchRetries &&
          !_isCancelled) {
        if (retryAttempt > 0) {
          print(
              '🔄 إعادة محاولة ${failedPages.length} صفحة فاشلة (المحاولة ${retryAttempt + 1})');
          await Future.delayed(
              Duration(seconds: retryAttempt * 2)); // انتظار متزايد
        }

        final futures = failedPages.map((pageNum) async {
          final items = await _fetchSinglePage(token, pageNum);
          return MapEntry(pageNum, items);
        });

        final results = await Future.wait(futures);

        // فصل الناجحة عن الفاشلة
        failedPages = [];
        for (final result in results) {
          if (result.value.isNotEmpty) {
            successfulPages[result.key] = result.value;
          } else {
            failedPages.add(result.key);
          }
        }

        retryAttempt++;
      }

      // تحذير إذا بقيت صفحات فاشلة
      if (failedPages.isNotEmpty) {
        print('⚠️ تعذر جلب ${failedPages.length} صفحة: $failedPages');
      }

      // معالجة النتائج الناجحة بالترتيب
      final sortedPages = successfulPages.keys.toList()..sort();
      for (final pageNum in sortedPages) {
        if (_isCancelled) break;

        final items = successfulPages[pageNum]!;
        final converted = _convertSubscribers(items);
        await _db.batchInsertSubscribers(converted);
        totalCount += items.length;
        onProgress(pageNum, totalPages, totalCount, converted);
      }

      currentPage = endPage + 1;

      // تأخير بسيط بين الدفعات لتجنب الحظر
      if (currentPage <= totalPages && !_isCancelled) {
        await Future.delayed(const Duration(milliseconds: 300));
      }
    }

    return totalCount;
  }

  /// جلب صفحة واحدة من الاشتراكات
  Future<List<dynamic>> _fetchSinglePage(String token, int pageNum) async {
    try {
      final url = Uri.parse(
          '$_baseUrl/api/subscriptions?sortCriteria.property=expires&sortCriteria.direction=asc&hierarchyLevel=0&pageNumber=$pageNum&pageSize=$_subscriptionsPageSize');

      final response = await _httpGetWithRetry(
        url,
        _getHeaders(token),
        maxRetries: 3,
        timeout: const Duration(seconds: 60),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        print('📄 صفحة $pageNum: ${(data['items'] ?? []).length} عنصر');
        return data['items'] ?? [];
      } else {
        print('⚠️ خطأ HTTP في صفحة $pageNum: ${response.statusCode}');
      }
    } catch (e) {
      print('⚠️ خطأ في صفحة $pageNum');
    }
    return [];
  }

  /// تحويل البيانات لصيغة التخزين المحلي
  List<Map<String, dynamic>> _convertSubscribers(List<dynamic> items) {
    final List<Map<String, dynamic>> convertedItems = [];

    for (final item in items) {
      final customer = item['customer'] ?? {};
      final zone = item['zone'] ?? {};
      final selfData = item['self'] ?? {};
      final deviceDetails = item['deviceDetails'] ?? {};

      // معرف العميل (customer.id) - هذا يُستخدم للربط مع customers/summary
      final customerId = customer['id']?.toString() ?? '';
      // معرف الاشتراك (self.id) - المعرف الفريد للاشتراك
      final subscriptionId = selfData['id']?.toString() ?? customerId;

      // استخراج جميع الخدمات
      final services = item['services'] as List? ?? [];
      final servicesList = services
          .map((s) => {
                'id': s['id']?.toString() ?? '',
                'displayValue': s['displayValue']?.toString() ?? '',
                'type': s['type']?['displayValue']?.toString() ?? '',
                'productType':
                    s['productType']?['displayValue']?.toString() ?? '',
              })
          .toList();

      convertedItems.add({
        // المعرفات
        'subscriptionId': subscriptionId,
        'customerId': customerId,

        // بيانات الاشتراك الأساسية
        'username': deviceDetails['username'] ?? item['username'] ?? '',
        'status': item['status'] ?? '',
        'autoRenew': item['autoRenew'] ?? false,

        // بيانات العميل
        'displayName': customer['displayValue'] ?? '',

        // الحزمة (المعرف فقط)
        'bundleId': item['bundleId'] ?? '',

        // المنطقة - المعرف والاسم
        'zoneId': zone['id']?.toString() ?? '',
        'zoneName': zone['displayValue']?.toString() ?? '',

        // الخدمات
        'services': servicesList,
        'profileName': _getFirstServiceName(item),

        // التواريخ
        'startedAt': item['startedAt'] ?? '',
        'expires': item['expires'] ?? '',
        'commitmentPeriod': item['commitmentPeriod']?.toString() ?? '',

        // حالات خاصة
        'isSuspended': item['isSuspended'] ?? false,
        'suspensionReason': item['suspensionReason'] ?? '',
        'isQuotaBased': item['isQuotaBased'] ?? false,
        'totalQuotaInBytes': item['totalQuotaInBytes']?.toString() ?? '',

        // معلومات إضافية
        'selfDisplayValue': selfData['displayValue'] ?? '',
        'phone': item['customerSummary']?['primaryPhone'] ??
            customer['mobile'] ??
            '',
      });
    }

    return convertedItems;
  }

  /// استخراج اسم الخدمة الأولى
  String _getFirstServiceName(Map<String, dynamic> subscription) {
    final services = subscription['services'];
    if (services is List && services.isNotEmpty) {
      final first = services.first;
      if (first is Map) {
        return first['displayValue']?.toString() ??
            first['name']?.toString() ??
            '';
      }
    }
    return '';
  }

  /// جلب بيانات المستخدمين من customers/summary (نفس طريقة صفحة الاشتراكات)
  /// جلب بيانات المشتركين من API الجديد مع pagination
  /// https://admin.ftth.iq/api/customers/summary?partnersAndLOBAgnostic=false&pageSize=X&pageNumber=Y
  Future<int> _fetchCustomerPhones({
    required String token,
    required List<String> customerIds, // لم نعد نحتاجها، لكن نبقيها للتوافق
    required Function(int current, int total) onProgress,
  }) async {
    // تهيئة الإعدادات
    await _settings.initialize();

    print(
        '⚙️ إعدادات المشتركين: $_usersPageSize/صفحة، $_usersParallelPages متوازي');

    int totalCount = 0;
    int totalPages = 1;
    int processedCount = 0;

    // أولاً: جلب الصفحة الأولى لمعرفة إجمالي الصفحات
    final firstPageUrl = Uri.parse(
        '$_baseUrl/api/customers/summary?partnersAndLOBAgnostic=false&pageSize=$_usersPageSize&pageNumber=1');

    final firstResponse = await _httpGetWithRetry(
      firstPageUrl,
      _getHeaders(token),
      maxRetries: 5,
      timeout: const Duration(seconds: 120),
    );

    if (firstResponse.statusCode == 401) {
      throw Exception('انتهت صلاحية الجلسة - يرجى تسجيل الدخول مرة أخرى');
    }

    if (firstResponse.statusCode != 200) {
      throw Exception('فشل جلب المشتركين: ${firstResponse.statusCode}');
    }

    final firstData = json.decode(firstResponse.body);
    final List<dynamic> firstItems = firstData['items'] ?? [];

    if (firstData['totalCount'] != null) {
      totalCount = firstData['totalCount'] as int;
      totalPages = (totalCount / _usersPageSize).ceil();
      if (totalPages == 0) totalPages = 1;
      print(
          '📊 إجمالي المشتركين: $totalCount, الصفحات: $totalPages ($_usersPageSize/صفحة)');
    }

    // معالجة الصفحة الأولى
    await _linkCustomerSummaryToSubscribers(firstItems);
    processedCount += firstItems.length;
    onProgress(1, totalPages);

    if (totalPages <= 1 || _isCancelled) {
      return processedCount;
    }

    // جلب باقي الصفحات بشكل متوازي (بحد أقصى 5 في المرة للمشتركين)
    int currentPage = 2;
    final maxParallel =
        _usersParallelPages.clamp(1, 5); // حد أقصى 5 متوازي للمشتركين

    while (currentPage <= totalPages && !_isCancelled) {
      final endPage =
          (currentPage + maxParallel - 1).clamp(currentPage, totalPages);
      final pagesToFetch =
          List.generate(endPage - currentPage + 1, (i) => currentPage + i);

      print('🚀 جلب متوازي للمشتركين: صفحات $currentPage إلى $endPage');

      // جلب جميع الصفحات في الدفعة معاً
      final futures = pagesToFetch
          .map((pageNum) => _fetchSingleCustomerPage(token, pageNum));
      final results = await Future.wait(futures);

      // معالجة النتائج
      for (int i = 0; i < results.length; i++) {
        if (_isCancelled) break;

        final items = results[i];
        if (items.isNotEmpty) {
          await _linkCustomerSummaryToSubscribers(items);
          processedCount += items.length;
          onProgress(pagesToFetch[i], totalPages);
        }
      }

      currentPage = endPage + 1;

      // تأخير بين الدفعات لتخفيف الضغط على السيرفر
      if (currentPage <= totalPages && !_isCancelled) {
        await Future.delayed(const Duration(milliseconds: 500));
      }
    }

    return processedCount;
  }

  /// جلب صفحة واحدة من المشتركين
  Future<List<dynamic>> _fetchSingleCustomerPage(
      String token, int pageNum) async {
    try {
      final url = Uri.parse(
          '$_baseUrl/api/customers/summary?partnersAndLOBAgnostic=false&pageSize=$_usersPageSize&pageNumber=$pageNum');

      final response = await _httpGetWithRetry(
        url,
        _getHeaders(token),
        maxRetries: 5,
        timeout: const Duration(seconds: 120),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return (data['items'] as List?) ?? [];
      }
    } catch (e) {
      print('⚠️ خطأ في جلب صفحة المشتركين $pageNum');
    }
    return [];
  }

  /// ربط بيانات العملاء مع المشتركين باستخدام customer_id
  Future<void> _linkCustomerSummaryToSubscribers(
      List<dynamic> summaryItems) async {
    final userPhones = <Map<String, dynamic>>[];
    int phonesFound = 0;

    for (final item in summaryItems) {
      // الـ id مباشرة من الـ API الجديد
      final customerId = item['id']?.toString() ?? '';
      final userName = item['displayValue'] ?? '';
      final userPhone = item['primaryPhone']?.toString() ?? '';

      // طباعة أول 3 عناصر للتشخيص
      if (userPhones.length < 3) {
        print(
            '🔍 Customer: id=$customerId, name=$userName, phone=${userPhone.isEmpty ? "فارغ" : userPhone}');
      }

      if (userPhone.isNotEmpty && userPhone != 'null') phonesFound++;
      if (customerId.isEmpty) continue;

      userPhones.add({
        'customerId': customerId,
        'userName': userName,
        'phone': userPhone.isEmpty || userPhone == 'null' ? '' : userPhone,
      });
    }

    print('📊 إجمالي: ${summaryItems.length} عميل، $phonesFound لديهم هاتف');

    if (userPhones.isNotEmpty) {
      await _db.linkCustomerDataToSubscribers(userPhones);
    }
  }

  /// جلب العناوين للعملاء
  Future<int> _fetchAddresses({
    required String token,
    required List<String> customerIds,
    required Function(int current, int total) onProgress,
  }) async {
    int totalAddresses = 0;
    // جلب عنوان مستخدم واحد في كل طلب
    final totalCustomers = customerIds.length;

    for (int i = 0; i < customerIds.length && !_isCancelled; i++) {
      final customerId = customerIds[i];
      onProgress(i + 1, totalCustomers);

      final url = Uri.parse('$_baseUrl/api/addresses?accountIds=$customerId');

      try {
        final response = await http.get(url, headers: _getHeaders(token));

        if (response.statusCode == 401) {
          throw Exception('انتهت صلاحية الجلسة');
        }

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          final List<dynamic> items =
              data is List ? data : (data['items'] ?? []);

          if (items.isNotEmpty) {
            await _db.batchInsertAddresses(items.cast<Map<String, dynamic>>());
            totalAddresses += items.length;
          }
        }
      } catch (e) {
        // تخطي الأخطاء والاستمرار
        print('خطأ في جلب العناوين للمستخدم ${i + 1}');
      }

      // تأخير بسيط
      await Future.delayed(const Duration(milliseconds: 50));
    }

    return totalAddresses;
  }

  /// تقسيم القائمة إلى دفعات
  List<List<String>> _splitIntoBatches(List<String> list, int batchSize) {
    final batches = <List<String>>[];
    for (int i = 0; i < list.length; i += batchSize) {
      final end = (i + batchSize < list.length) ? i + batchSize : list.length;
      batches.add(list.sublist(i, end));
    }
    return batches;
  }

  /// مزامنة المشتركين فقط (سريعة)
  Future<SyncResult> syncSubscribersOnly({
    required String token,
    required Function(SyncProgress) onProgress,
  }) async {
    _isCancelled = false;
    final stopwatch = Stopwatch()..start();

    try {
      await _db.initialize();

      final count = await _fetchAllSubscribers(
        token: token,
        onProgress: (current, total, fetchedCount, items) {
          onProgress(SyncProgress(
            stage: 'subscribers',
            current: current,
            total: total,
            message:
                'جلب المشتركين: صفحة $current من $total ($fetchedCount مشترك)',
            fetchedCount: fetchedCount,
            newItems: items,
          ));
        },
      );

      stopwatch.stop();

      return SyncResult(
        success: !_isCancelled,
        message: _isCancelled ? 'تم إلغاء المزامنة' : 'تمت مزامنة المشتركين',
        subscribersCount: count,
        duration: stopwatch.elapsed,
      );
    } catch (e) {
      stopwatch.stop();
      return SyncResult(
        success: false,
        message: 'فشلت المزامنة',
        error: e.toString(),
        duration: stopwatch.elapsed,
      );
    }
  }

  /// جلب أرقام الهواتف من /api/customers/{id} بشكل متوازي
  /// يمكن تمرير قائمة customerIds محددة، أو سيجلب فقط للمشتركين بدون أرقام
  Future<SyncResult> fetchPhoneNumbers({
    required String token,
    required Function(SyncProgress) onProgress,
    List<String>? specificCustomerIds,
    bool onlyWithoutPhone = true,
  }) async {
    _isCancelled = false;
    final stopwatch = Stopwatch()..start();

    try {
      await _db.initialize();

      List<String> customerIds;

      if (specificCustomerIds != null && specificCustomerIds.isNotEmpty) {
        // استخدام القائمة المحددة
        customerIds = specificCustomerIds;
      } else {
        // جلب المشتركين من قاعدة البيانات
        final subscribers = await _db.getAllSubscribers();

        if (onlyWithoutPhone) {
          // فقط المشتركين بدون رقم هاتف
          customerIds = subscribers
              .where((s) {
                final phone = s['phone']?.toString() ?? '';
                return phone.isEmpty;
              })
              .map((s) => s['customer_id']?.toString() ?? '')
              .where((id) => id.isNotEmpty)
              .toSet()
              .toList();
        } else {
          // كل المشتركين
          customerIds = subscribers
              .map((s) => s['customer_id']?.toString() ?? '')
              .where((id) => id.isNotEmpty)
              .toSet()
              .toList();
        }
      }

      if (customerIds.isEmpty) {
        return SyncResult(
          success: true,
          message: onlyWithoutPhone
              ? 'جميع المشتركين لديهم أرقام هواتف ✅'
              : 'لا توجد اشتراكات - يرجى جلب الاشتراكات أولاً',
          duration: stopwatch.elapsed,
        );
      }

      print(
          '⚡ جلب أرقام الهواتف لـ ${customerIds.length} مشترك ${onlyWithoutPhone ? "(بدون أرقام فقط)" : ""}');

      int totalFetched = 0;
      int dataFound = 0;

      // استخدام قيمة الإعدادات للطلبات المتوازية في كل دفعة
      final int parallelRequests = _usersParallelPages.clamp(1, 500);
      // عدد الدفعات قبل التخزين (10 دفعات ثم تخزين)
      const int batchesBeforeSave = 10;
      // عدد محاولات إعادة الجلب للطلبات الفاشلة
      const int maxRetries = 3;

      print(
          '⚙️ إعدادات الهاتف: $parallelRequests طلب متوازي، تخزين كل $batchesBeforeSave دفعات');

      final List<Map<String, dynamic>> customersToUpdate = [];

      // حساب المجموعات الكبيرة (كل مجموعة = 10 دفعات)
      final totalBatches = (customerIds.length / parallelRequests).ceil();
      final totalSaveGroups = (totalBatches / batchesBeforeSave).ceil();

      // حساب نقاط تجديد التوكن (كل 10%)
      final refreshInterval = (totalSaveGroups / 10).ceil();
      int lastRefreshAt = 0;
      String currentToken = token;

      int currentIndex = 0;
      int batchNum = 0;
      int saveGroupNum = 0;

      while (currentIndex < customerIds.length && !_isCancelled) {
        saveGroupNum++;

        // 🔄 تجديد التوكن كل 10%
        if (saveGroupNum - lastRefreshAt >= refreshInterval &&
            saveGroupNum > 1) {
          print(
              '🔄 تجديد التوكن عند المجموعة $saveGroupNum من $totalSaveGroups');
          try {
            final newToken = await AuthService.instance.getAccessToken();
            if (newToken != null && newToken.isNotEmpty) {
              currentToken = newToken;
              lastRefreshAt = saveGroupNum;
              print('✅ تم تجديد التوكن بنجاح');
            }
          } catch (e) {
            print('⚠️ فشل تجديد التوكن');
          }
        }

        // جلب 10 دفعات متوازية قبل التخزين
        for (int b = 0;
            b < batchesBeforeSave &&
                currentIndex < customerIds.length &&
                !_isCancelled;
            b++) {
          batchNum++;

          // جلب دفعة واحدة من الطلبات المتوازية
          final endIndex =
              (currentIndex + parallelRequests).clamp(0, customerIds.length);
          final batch = customerIds.sublist(currentIndex, endIndex);

          onProgress(SyncProgress(
            stage: 'phones',
            current: saveGroupNum,
            total: totalSaveGroups,
            message:
                '📱 جلب أرقام الهواتف: مجموعة $saveGroupNum/$totalSaveGroups - دفعة ${b + 1}/$batchesBeforeSave ($dataFound رقم)',
            fetchedCount: totalFetched,
          ));

          print('🚀 دفعة $batchNum: جلب ${batch.length} طلب متوازي');

          // 📱 جلب متوازي مع تتبع الفاشلة
          final Map<String, Map<String, dynamic>> successfulResults = {};
          List<String> failedIds = List.from(batch);

          int retryAttempt = 0;
          while (failedIds.isNotEmpty &&
              retryAttempt < maxRetries &&
              !_isCancelled) {
            if (retryAttempt > 0) {
              print(
                  '🔄 إعادة محاولة ${failedIds.length} طلب فاشل (المحاولة ${retryAttempt + 1})');
              await Future.delayed(Duration(seconds: retryAttempt * 2));
            }

            final futures = failedIds.map((customerId) async {
              final result = await _fetchPhoneOnly(currentToken, customerId);
              return MapEntry(customerId, result);
            });

            final results = await Future.wait(futures);

            // فصل الناجحة عن الفاشلة
            failedIds = [];
            for (final entry in results) {
              if (entry.value != null && entry.value!.isNotEmpty) {
                successfulResults[entry.key] = entry.value!;
              } else {
                failedIds.add(entry.key);
              }
            }

            retryAttempt++;
          }

          // تحذير إذا بقيت طلبات فاشلة
          if (failedIds.isNotEmpty) {
            print(
                '⚠️ تعذر جلب ${failedIds.length} رقم بعد $maxRetries محاولات');
          }

          // تجميع النتائج الناجحة
          for (final result in successfulResults.values) {
            dataFound++;
            customersToUpdate.add(result);
          }
          totalFetched += batch.length;

          print('✅ نجح ${successfulResults.length}/${batch.length} طلب');

          currentIndex = endIndex;
        }

        print(
            '✅ اكتمال $batchesBeforeSave دفعات (وجد $dataFound رقم حتى الآن)');

        // 💾 تخزين بعد كل 10 دفعات
        if (customersToUpdate.isNotEmpty) {
          print('💾 تخزين ${customersToUpdate.length} سجل...');
          await _db.batchUpdateCustomerDetails(customersToUpdate);
          customersToUpdate.clear();
        }

        // ⏳ انتظار بين مجموعات التخزين
        if (currentIndex < customerIds.length && !_isCancelled) {
          print('⏳ انتظار 3 ثواني قبل المجموعة التالية...');
          await Future.delayed(const Duration(seconds: 3));
        }
      }

      stopwatch.stop();

      return SyncResult(
        success: !_isCancelled,
        message: _isCancelled
            ? 'تم إلغاء الجلب'
            : 'تم جلب $dataFound رقم هاتف من $totalFetched عميل',
        phonesCount: dataFound,
        duration: stopwatch.elapsed,
      );
    } catch (e) {
      stopwatch.stop();
      return SyncResult(
        success: false,
        message: 'فشل جلب البيانات',
        error: e.toString(),
        duration: stopwatch.elapsed,
      );
    }
  }

  /// جلب بيانات الاشتراكات من /api/addresses بشكل مجمع (150 ID في طلب واحد)
  /// يمكن تمرير onlyWithoutDetails = true لجلب فقط للمشتركين بدون تفاصيل
  Future<SyncResult> fetchSubscriptionAddresses({
    required String token,
    required Function(SyncProgress) onProgress,
    bool onlyWithoutDetails = true,
  }) async {
    _isCancelled = false;
    final stopwatch = Stopwatch()..start();

    try {
      await _db.initialize();
      await _settings.initialize();

      // جلب جميع المشتركين
      final subscribers = await _db.getAllSubscribers();

      List<String> customerIds;

      if (onlyWithoutDetails) {
        // فقط المشتركين بدون تفاصيل - استخدام حقل details_fetched للتحقق الدقيق
        customerIds = subscribers
            .where((s) {
              // التحقق من حقل details_fetched - الطريقة الأدق
              if (s['details_fetched'] != true) {
                return true; // لم يتم جلب التفاصيل بنجاح
              }
              return false; // تم جلب التفاصيل
            })
            .map((s) => s['customer_id']?.toString() ?? '')
            .where((id) => id.isNotEmpty)
            .toSet()
            .toList();
      } else {
        // كل المشتركين
        customerIds = subscribers
            .map((s) => s['customer_id']?.toString() ?? '')
            .where((id) => id.isNotEmpty)
            .toSet()
            .toList();
      }

      if (customerIds.isEmpty) {
        return SyncResult(
          success: true,
          message: onlyWithoutDetails
              ? 'جميع المشتركين لديهم تفاصيل ✅'
              : 'لا توجد اشتراكات - يرجى جلب الاشتراكات أولاً',
          duration: stopwatch.elapsed,
        );
      }

      print(
          '📍 جلب بيانات الاشتراكات لـ ${customerIds.length} عميل ${onlyWithoutDetails ? "(بدون تفاصيل فقط)" : ""} (طريقة سريعة)');

      int dataFound = 0;

      // إعدادات الجلب من الإعدادات المحفوظة
      final int idsPerRequest = _addressesPageSize; // عدد IDs في كل طلب
      final int parallelRequests =
          _addressesParallelPages; // عدد الطلبات المتوازية

      print('📊 إعدادات: $idsPerRequest ID/طلب، $parallelRequests طلب متوازي');

      // تقسيم IDs إلى مجموعات (batches)
      final List<List<String>> idBatches = [];
      for (int i = 0; i < customerIds.length; i += idsPerRequest) {
        idBatches.add(customerIds.sublist(
            i, (i + idsPerRequest).clamp(0, customerIds.length)));
      }

      final totalBatches = idBatches.length;
      print('📦 إجمالي الدفعات: $totalBatches ($parallelRequests متوازي)');

      // حساب نقاط تجديد التوكن (كل 10%)
      final refreshInterval = (totalBatches / 10).ceil();
      int lastRefreshAt = 0;
      String currentToken = token;

      // جلب بشكل متوازي - مثل طريقة الاشتراكات (تخزين فوري بعد كل دفعة)
      int currentBatch = 0;

      while (currentBatch < totalBatches && !_isCancelled) {
        final endBatch =
            (currentBatch + parallelRequests).clamp(0, totalBatches);
        final batchIndicesToFetch =
            List.generate(endBatch - currentBatch, (i) => currentBatch + i);

        print(
            '🚀 جلب متوازي: دفعات ${currentBatch + 1} إلى $endBatch من $totalBatches');

        // 🔄 تجديد التوكن كل 10%
        if (currentBatch - lastRefreshAt >= refreshInterval &&
            currentBatch > 0) {
          print('🔄 تجديد التوكن عند الدفعة $currentBatch');
          try {
            final newToken = await AuthService.instance.getAccessToken();
            if (newToken != null && newToken.isNotEmpty) {
              currentToken = newToken;
              lastRefreshAt = currentBatch;
              print('✅ تم تجديد التوكن بنجاح');
            }
          } catch (e) {
            print('⚠️ فشل تجديد التوكن');
          }
        }

        onProgress(SyncProgress(
          stage: 'addresses',
          current: currentBatch + 1,
          total: totalBatches,
          message:
              '📍 جلب التفاصيل: دفعة ${currentBatch + 1} من $totalBatches ($dataFound سجل)',
          fetchedCount: dataFound,
        ));

        // جلب جميع الدفعات في المجموعة معاً مع التتبع
        final Map<int, List<Map<String, dynamic>>> successfulBatches = {};
        List<int> failedBatchIndices = List.from(batchIndicesToFetch);

        // محاولات متعددة لجلب جميع الدفعات
        int retryAttempt = 0;
        const maxBatchRetries = 3;

        while (failedBatchIndices.isNotEmpty &&
            retryAttempt < maxBatchRetries &&
            !_isCancelled) {
          if (retryAttempt > 0) {
            print(
                '🔄 إعادة محاولة ${failedBatchIndices.length} دفعة فاشلة (المحاولة ${retryAttempt + 1})');
            await Future.delayed(Duration(seconds: retryAttempt * 2));
          }

          final futures = failedBatchIndices.map((batchIdx) async {
            final items = await _fetchAddressesBatchWithRetry(
                currentToken, idBatches[batchIdx]);
            return MapEntry(batchIdx, items);
          });

          final results = await Future.wait(futures);

          // فصل الناجحة عن الفاشلة
          failedBatchIndices = [];
          for (final result in results) {
            if (result.value != null && result.value!.isNotEmpty) {
              successfulBatches[result.key] = result.value!;
            } else {
              failedBatchIndices.add(result.key);
            }
          }

          retryAttempt++;
        }

        // تحذير إذا بقيت دفعات فاشلة
        if (failedBatchIndices.isNotEmpty) {
          print(
              '⚠️ تعذر جلب ${failedBatchIndices.length} دفعة: $failedBatchIndices');
          // حفظ الدفعات الفاشلة للمحاولة النهائية
          for (final batchIdx in failedBatchIndices) {
            _failedBatchIds.addAll(idBatches[batchIdx]);
          }
        }

        // 💾 معالجة وتخزين النتائج الناجحة فوراً - مثل طريقة الاشتراكات
        final sortedBatches = successfulBatches.keys.toList()..sort();
        for (final batchIdx in sortedBatches) {
          if (_isCancelled) break;

          final items = successfulBatches[batchIdx]!;
          await _db.batchUpdateSubscriptionAddresses(items);
          dataFound += items.length;

          onProgress(SyncProgress(
            stage: 'addresses',
            current: batchIdx + 1,
            total: totalBatches,
            message:
                '📍 جلب التفاصيل: دفعة ${batchIdx + 1} من $totalBatches ($dataFound سجل)',
            fetchedCount: dataFound,
          ));
        }

        print(
            '✅ تم تخزين ${successfulBatches.length} دفعة (الإجمالي: $dataFound سجل)');

        currentBatch = endBatch;

        // تأخير بسيط بين الدفعات لتجنب الحظر
        if (currentBatch < totalBatches && !_isCancelled) {
          await Future.delayed(const Duration(milliseconds: 300));
        }
      }

      // 🔄 محاولة نهائية للدفعات الفاشلة
      if (_failedBatchIds.isNotEmpty && !_isCancelled) {
        print('🔄 محاولة نهائية لـ ${_failedBatchIds.length} معرف فاشل...');
        onProgress(SyncProgress(
          stage: 'addresses_retry',
          current: 1,
          total: 1,
          message: '🔄 محاولة نهائية لـ ${_failedBatchIds.length} معرف فاشل...',
          fetchedCount: dataFound,
        ));

        await Future.delayed(
            const Duration(seconds: 10)); // انتظار أطول قبل المحاولة النهائية

        // تقسيم الفاشلة إلى دفعات صغيرة (5 فقط لكل دفعة)
        final failedBatches = <List<String>>[];
        for (int i = 0; i < _failedBatchIds.length; i += 5) {
          failedBatches.add(_failedBatchIds.sublist(
              i, (i + 5).clamp(0, _failedBatchIds.length)));
        }

        int finalRetrySuccess = 0;
        for (int i = 0; i < failedBatches.length && !_isCancelled; i++) {
          final batch = failedBatches[i];
          print(
              '🔄 محاولة ${i + 1}/${failedBatches.length}: ${batch.length} معرف');

          final result =
              await _fetchAddressesBatchWithRetry(currentToken, batch);
          if (result != null && result.isNotEmpty) {
            await _db.batchUpdateSubscriptionAddresses(result);
            dataFound += result.length;
            finalRetrySuccess += result.length;
            print('✅ نجح جلب ${result.length} سجل');
          }

          // انتظار بين كل محاولة
          if (i < failedBatches.length - 1) {
            await Future.delayed(const Duration(seconds: 3));
          }
        }

        print(
            '✅ المحاولة النهائية: نجح $finalRetrySuccess من ${_failedBatchIds.length}');
        _failedBatchIds.clear();
      }

      stopwatch.stop();

      return SyncResult(
        success: !_isCancelled,
        message: _isCancelled
            ? 'تم إلغاء الجلب'
            : 'تم جلب $dataFound سجل من ${customerIds.length} عميل',
        addressesCount: dataFound,
        duration: stopwatch.elapsed,
      );
    } catch (e) {
      stopwatch.stop();
      return SyncResult(
        success: false,
        message: 'فشل جلب بيانات الاشتراكات',
        error: e.toString(),
        duration: stopwatch.elapsed,
      );
    }
  }

  /// جلب بيانات مجموعة من العملاء من /api/addresses
  Future<List<Map<String, dynamic>>?> _fetchAddressesBatch(
      String token, List<String> customerIds) async {
    try {
      // بناء الـ URL مع accountIds متعددة
      final queryParams = customerIds.map((id) => 'accountIds=$id').join('&');
      final url = Uri.parse('$_baseUrl/api/addresses?$queryParams');

      print('🌐 طلب: ${customerIds.length} IDs');

      final response = await http
          .get(url, headers: _getHeaders(token))
          .timeout(const Duration(seconds: 30));

      print('📡 الرد: ${response.statusCode}');

      if (response.statusCode == 200) {
        final List<dynamic> items = json.decode(response.body);
        print('✅ استلام ${items.length} سجل');
        final List<Map<String, dynamic>> results = [];

        for (final item in items) {
          final customerId = item['accountId']?.toString() ?? '';
          if (customerId.isEmpty) continue;

          final device = item['deviceDetails'] ?? {};
          final gps = item['gpsCoordinate'] ?? {};

          results.add({
            'customerId': customerId,
            // علامة أن التفاصيل تم جلبها
            'details_fetched': true,
            'details_fetched_at': DateTime.now().toIso8601String(),
            // بيانات الجهاز
            'device_serial': device['serial']?.toString() ?? '',
            'fdt_name': device['fdt']?['displayValue']?.toString() ?? '',
            'fat_name': device['fat']?['displayValue']?.toString() ?? '',
            // بيانات العنوان
            'gps_lat': gps['latitude']?.toString() ?? '',
            'gps_lng': gps['longitude']?.toString() ?? '',
            // بيانات إضافية
            'is_trial': item['isTrial'] == true,
            'is_pending': item['isPending'] == true,
          });
        }

        return results;
      } else {
        print(
            '❌ خطأ HTTP: ${response.statusCode} - ${response.body.substring(0, (response.body.length).clamp(0, 200))}');
      }
    } catch (e) {
      print('⚠️ خطأ في جلب addresses batch');
    }
    return null;
  }

  /// جلب بيانات مجموعة من العملاء مع إعادة المحاولة
  Future<List<Map<String, dynamic>>?> _fetchAddressesBatchWithRetry(
      String token, List<String> customerIds) async {
    try {
      // بناء الـ URL مع accountIds متعددة
      final queryParams = customerIds.map((id) => 'accountIds=$id').join('&');
      final url = Uri.parse('$_baseUrl/api/addresses?$queryParams');

      print('🌐 طلب (مع retry): ${customerIds.length} IDs');
      // طباعة بعض المعرفات المرسلة
      if (customerIds.isNotEmpty) {
        print('📤 IDs مرسلة (أول 3): ${customerIds.take(3).toList()}');
      }

      // استخدام _httpGetWithRetry بدلاً من http.get مباشرة
      final response = await _httpGetWithRetry(
        url,
        _getHeaders(token),
        maxRetries: 5,
        timeout: const Duration(seconds: 90),
      );

      print('📡 الرد: ${response.statusCode}');

      if (response.statusCode == 200) {
        final decoded = json.decode(response.body);

        // التعامل مع الاستجابة سواء كانت List أو Map
        List<dynamic> items;
        if (decoded is List) {
          items = decoded;
        } else if (decoded is Map && decoded.containsKey('items')) {
          items = decoded['items'] as List? ?? [];
        } else if (decoded is Map) {
          // إذا كان Map واحد، نحوله لقائمة
          items = [decoded];
        } else {
          items = [];
        }

        print('✅ استلام ${items.length} سجل');

        // طباعة أول عنصر لمعرفة شكل البيانات
        if (items.isNotEmpty) {
          final first = items.first as Map;
          print('🔍 مفاتيح أول عنصر: ${first.keys.toList()}');
          // طباعة customer لمعرفة شكله
          if (first['customer'] != null) {
            print('👤 customer: ${first['customer']}');
          }
        }

        final List<Map<String, dynamic>> results = [];

        for (final item in items) {
          // استخراج customerId من حقل customer
          final customer = item['customer'];
          String customerId = '';

          if (customer is Map) {
            customerId = customer['id']?.toString() ?? '';
          } else if (customer != null) {
            customerId = customer.toString();
          }

          // إذا لم يوجد في customer، جرب الحقول الأخرى
          if (customerId.isEmpty) {
            customerId = item['accountId']?.toString() ??
                item['customerId']?.toString() ??
                '';
          }

          if (customerId.isEmpty) {
            print('⚠️ لم يتم العثور على customerId في العنصر');
            continue;
          }

          // طباعة أول معرف مستلم
          if (results.isEmpty) {
            print('📥 أول customerId مستلم: $customerId');
          }

          final device = item['deviceDetails'] ?? {};
          final gps = item['gpsCoordinate'] ?? {};

          results.add({
            'customerId': customerId,
            // علامة أن التفاصيل تم جلبها
            'details_fetched': true,
            'details_fetched_at': DateTime.now().toIso8601String(),
            // بيانات الجهاز
            'device_serial': device['serial']?.toString() ?? '',
            'fdt_name': device['fdt']?['displayValue']?.toString() ?? '',
            'fat_name': device['fat']?['displayValue']?.toString() ?? '',
            // بيانات العنوان
            'gps_lat': gps['latitude']?.toString() ?? '',
            'gps_lng': gps['longitude']?.toString() ?? '',
            // بيانات إضافية
            'is_trial': item['isTrial'] == true,
            'is_pending': item['isPending'] == true,
          });
        }

        return results;
      } else if (response.statusCode == 429) {
        // Too Many Requests - انتظار ثم إعادة المحاولة
        print('⚠️ خطأ 429 - كثرة الطلبات، انتظار 10 ثواني...');
        await Future.delayed(const Duration(seconds: 10));
        // إعادة المحاولة مرة واحدة
        final retryResponse = await _httpGetWithRetry(
          Uri.parse(
              '$_baseUrl/api/addresses?${customerIds.map((id) => 'accountIds=$id').join('&')}'),
          _getHeaders(token),
          maxRetries: 2,
          timeout: const Duration(seconds: 60),
        );
        if (retryResponse.statusCode == 200) {
          final decoded = json.decode(retryResponse.body);
          List<dynamic> items;
          if (decoded is List) {
            items = decoded;
          } else if (decoded is Map && decoded.containsKey('items')) {
            items = decoded['items'] as List? ?? [];
          } else if (decoded is Map) {
            items = [decoded];
          } else {
            items = [];
          }
          // معالجة البيانات (نفس الكود أعلاه)
          final List<Map<String, dynamic>> results = [];
          for (final item in items) {
            final customer = item['customer'];
            String customerId = '';
            if (customer is Map) {
              customerId = customer['id']?.toString() ?? '';
            }
            if (customerId.isEmpty) continue;
            final device = item['deviceDetails'] ?? {};
            final gps = item['gpsCoordinate'] ?? {};
            results.add({
              'customerId': customerId,
              'details_fetched': true,
              'details_fetched_at': DateTime.now().toIso8601String(),
              'fdt_name': device['fdt']?['displayValue']?.toString() ?? '',
              'fat_name': device['fat']?['displayValue']?.toString() ?? '',
              'gps_lat': gps['latitude']?.toString() ?? '',
              'gps_lng': gps['longitude']?.toString() ?? '',
            });
          }
          print('✅ استلام ${results.length} سجل بعد إعادة المحاولة');
          return results;
        }
        return null;
      } else {
        print(
            '❌ خطأ HTTP: ${response.statusCode} - ${response.body.substring(0, (response.body.length).clamp(0, 200))}');
        return null;
      }
    } catch (e) {
      print('⚠️ خطأ في جلب addresses batch with retry');
      return null;
    }
  }

  /// 📱 جلب رقم الهاتف فقط - سريع جداً!
  Future<Map<String, dynamic>?> _fetchPhoneOnly(
      String token, String customerId) async {
    try {
      final response = await http
          .get(Uri.parse('$_baseUrl/api/customers/$customerId'),
              headers: _getHeaders(token))
          .timeout(const Duration(seconds: 3));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final model = data['model'] ?? {};

        final phone = model['primaryContact']?['mobile']?.toString() ?? '';

        // فقط إرجاع البيانات إذا كان هناك رقم هاتف
        if (phone.isNotEmpty) {
          return {
            'customerId': customerId,
            'phone': phone,
          };
        }
      }
    } catch (e) {
      // تجاهل الأخطاء للسرعة
    }
    return null;
  }

  /// ⚡ جلب سريع - رابط واحد فقط!
  Future<Map<String, dynamic>?> _fetchCustomerDataFast(
      String token, String customerId) async {
    try {
      final response = await http
          .get(Uri.parse('$_baseUrl/api/customers/$customerId'),
              headers: _getHeaders(token))
          .timeout(const Duration(seconds: 3));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final model = data['model'] ?? {};

        return {
          'customerId': customerId,
          'phone': model['primaryContact']?['mobile']?.toString() ?? '',
          'email': model['primaryContact']?['email']?.toString() ?? '',
          'secondary_phone':
              model['primaryContact']?['secondaryPhone']?.toString() ?? '',
          'mother_name': model['motherName']?.toString() ?? '',
          'national_id_number':
              model['nationalIdCard']?['idNumber']?.toString() ?? '',
          'national_id_family_number':
              model['nationalIdCard']?['familyNumber']?.toString() ?? '',
          'national_id_place':
              model['nationalIdCard']?['placeOfIssue']?.toString() ?? '',
          'national_id_date':
              model['nationalIdCard']?['issuedAt']?.toString() ?? '',
          'customer_type':
              model['customerType']?['displayValue']?.toString() ?? '',
          'referral_code': model['usrReferralCode']?.toString() ?? '',
          'gps_lat': (model['addresses'] as List?)
                  ?.firstOrNull?['gpsCoordinate']?['latitude']
                  ?.toString() ??
              '',
          'gps_lng': (model['addresses'] as List?)
                  ?.firstOrNull?['gpsCoordinate']?['longitude']
                  ?.toString() ??
              '',
        };
      }
    } catch (e) {
      // تجاهل الأخطاء للسرعة
    }
    return null;
  }

  /// ⚡ جلب سريع للرابطين معاً
  Future<Map<String, dynamic>?> _fetchFullCustomerDataFast(
      String token, String customerId) async {
    try {
      // جلب الرابطين بالتوازي مع timeout قصير
      final responses = await Future.wait([
        http
            .get(Uri.parse('$_baseUrl/api/customers/$customerId'),
                headers: _getHeaders(token))
            .timeout(const Duration(seconds: 4)),
        http
            .get(
                Uri.parse(
                    '$_baseUrl/api/customers/subscriptions?customerId=$customerId'),
                headers: _getHeaders(token))
            .timeout(const Duration(seconds: 4)),
      ]);

      final Map<String, dynamic> result = {'customerId': customerId};

      // معالجة بيانات العميل
      if (responses[0].statusCode == 200) {
        final model = json.decode(responses[0].body)['model'] ?? {};

        result['phone'] = model['primaryContact']?['mobile']?.toString() ?? '';
        result['email'] = model['primaryContact']?['email']?.toString() ?? '';
        result['secondary_phone'] =
            model['primaryContact']?['secondaryPhone']?.toString() ?? '';
        result['mother_name'] = model['motherName']?.toString() ?? '';
        result['national_id_number'] =
            model['nationalIdCard']?['idNumber']?.toString() ?? '';
        result['national_id_family_number'] =
            model['nationalIdCard']?['familyNumber']?.toString() ?? '';
        result['national_id_place'] =
            model['nationalIdCard']?['placeOfIssue']?.toString() ?? '';
        result['national_id_date'] =
            model['nationalIdCard']?['issuedAt']?.toString() ?? '';
        result['customer_type'] =
            model['customerType']?['displayValue']?.toString() ?? '';
        result['referral_code'] = model['usrReferralCode']?.toString() ?? '';

        final addr = (model['addresses'] as List?)?.firstOrNull;
        if (addr != null) {
          result['gps_lat'] =
              addr['gpsCoordinate']?['latitude']?.toString() ?? '';
          result['gps_lng'] =
              addr['gpsCoordinate']?['longitude']?.toString() ?? '';
        }
      }

      // معالجة بيانات الاشتراكات
      if (responses[1].statusCode == 200) {
        final items = (json.decode(responses[1].body)['items'] as List?) ?? [];
        if (items.isNotEmpty) {
          final sub = items[0];
          final device = sub['deviceDetails'] ?? {};
          final session = sub['activeSession'] ?? {};

          result['device_serial'] = device['serial']?.toString() ?? '';
          result['fdt_name'] = device['fdt']?['displayValue']?.toString() ?? '';
          result['fat_name'] = device['fat']?['displayValue']?.toString() ?? '';
          result['session_time_seconds'] =
              session['sessionTimeInSeconds']?.toString() ?? '';
          result['is_trial'] = sub['isTrial'] == true;
          result['is_pending'] = sub['isPending'] == true;
        }
      }

      return result;
    } catch (e) {
      // تجاهل الأخطاء للسرعة
    }
    return null;
  }

  /// جلب بيانات العميل الكاملة من /api/customers/{id} و /api/customers/subscriptions
  Future<Map<String, dynamic>?> _fetchFullCustomerData(
      String token, String customerId) async {
    try {
      // ⚡ جلب الرابطين بالتوازي مع timeout قصير
      final customerFuture = http
          .get(Uri.parse('$_baseUrl/api/customers/$customerId'),
              headers: _getHeaders(token))
          .timeout(const Duration(seconds: 5));

      final subscriptionsFuture = http
          .get(
              Uri.parse(
                  '$_baseUrl/api/customers/subscriptions?customerId=$customerId'),
              headers: _getHeaders(token))
          .timeout(const Duration(seconds: 5));

      final responses =
          await Future.wait([customerFuture, subscriptionsFuture]);

      final customerResponse = responses[0];
      final subscriptionsResponse = responses[1];

      final Map<String, dynamic> result = {'customerId': customerId};

      // معالجة بيانات العميل
      if (customerResponse.statusCode == 200) {
        final customerData = json.decode(customerResponse.body);
        final model = customerData['model'] ?? {};

        // رقم الهاتف
        result['phone'] = model['primaryContact']?['mobile']?.toString() ?? '';
        result['email'] = model['primaryContact']?['email']?.toString() ?? '';
        result['secondary_phone'] =
            model['primaryContact']?['secondaryPhone']?.toString() ?? '';

        // اسم الأم
        result['mother_name'] = model['motherName']?.toString() ?? '';

        // الهوية الوطنية
        final nationalId = model['nationalIdCard'] ?? {};
        result['national_id_number'] = nationalId['idNumber']?.toString() ?? '';
        result['national_id_family_number'] =
            nationalId['familyNumber']?.toString() ?? '';
        result['national_id_place'] =
            nationalId['placeOfIssue']?.toString() ?? '';
        result['national_id_date'] = nationalId['issuedAt']?.toString() ?? '';

        // بطاقة السكن
        final residencyId = model['residencyIdCard'] ?? {};
        result['residency_id_number'] =
            residencyId['idNumber']?.toString() ?? '';
        result['residency_id_place'] =
            residencyId['placeOfIssue']?.toString() ?? '';

        // نوع العميل
        result['customer_type'] =
            model['customerType']?['displayValue']?.toString() ?? '';

        // كود الإحالة
        result['referral_code'] = model['usrReferralCode']?.toString() ?? '';

        // العناوين (من بيانات العميل)
        final addresses = model['addresses'] as List? ?? [];
        if (addresses.isNotEmpty) {
          final addr = addresses[0];
          result['apartment'] = addr['apartment']?.toString() ?? '';
          result['nearest_point'] = addr['nearestPoint']?.toString() ?? '';
          result['gps_lat'] =
              addr['gpsCoordinate']?['latitude']?.toString() ?? '';
          result['gps_lng'] =
              addr['gpsCoordinate']?['longitude']?.toString() ?? '';
        }
      }

      // معالجة بيانات الاشتراكات
      if (subscriptionsResponse.statusCode == 200) {
        final subsData = json.decode(subscriptionsResponse.body);
        final items = subsData['items'] as List? ?? [];

        if (items.isNotEmpty) {
          final sub = items[0]; // أول اشتراك

          // معلومات الجهاز
          final device = sub['deviceDetails'] ?? {};
          result['device_serial'] = device['serial']?.toString() ?? '';
          result['fdt_name'] = device['fdt']?['displayValue']?.toString() ?? '';
          result['fdt_id'] = device['fdt']?['id']?.toString() ?? '';
          result['fat_name'] = device['fat']?['displayValue']?.toString() ?? '';
          result['fat_id'] = device['fat']?['id']?.toString() ?? '';

          // الجلسة النشطة
          final session = sub['activeSession'] ?? {};
          result['session_time_seconds'] =
              session['sessionTimeInSeconds']?.toString() ?? '';

          // معلومات إضافية من الاشتراك
          result['is_trial'] = sub['isTrial'] == true;
          result['is_pending'] = sub['isPending'] == true;
          result['has_different_billing'] =
              sub['hasDifferentBillingPrice'] == true;
        }
      }

      return result;
    } catch (e) {
      print('⚠️ خطأ في جلب بيانات العميل $customerId');
      return null;
    }
  }
}
