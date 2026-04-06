/// اسم الصفحة: البحث السريع للمستخدمين
/// وصف الصفحة: صفحة البحث السريع عن المستخدمين
/// المؤلف: تطبيق السدارة
/// تاريخ الإنشاء: 2024
library;

import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/services.dart';
import '../users/user_details_page.dart';
import '../auth/auth_error_handler.dart';
import '../../services/auth_service.dart';

class QuickSearchUsersPage extends StatefulWidget {
  final String authToken;
  final String activatedBy;
  final String? initialSearchQuery;
  final bool hasServerSavePermission;
  final bool hasWhatsAppPermission;
  final bool? isAdminFlag; // علم إداري صريح
  // قائمة الصلاحيات المهمة من نظام FTTH (مفلترة مسبقاً في الصفحة الرئيسية)
  final List<String>? importantFtthApiPermissions;
  // بيانات الوكيل من المهمة (لتعبئة تلقائية في صفحة التجديد)
  final String? taskAgentName;
  final String? taskAgentCode;

  const QuickSearchUsersPage({
    super.key,
    required this.authToken,
    required this.activatedBy,
    this.initialSearchQuery,
    this.hasServerSavePermission = false,
    this.hasWhatsAppPermission = false,
    this.isAdminFlag,
    this.importantFtthApiPermissions,
    this.taskAgentName,
    this.taskAgentCode,
  });

  @override
  State<QuickSearchUsersPage> createState() => _QuickSearchUsersPageState();
}

class _QuickSearchUsersPageState extends State<QuickSearchUsersPage>
    with SingleTickerProviderStateMixin {
  final List<dynamic> searchResults = [];
  final List<dynamic> zones = [];
  bool isLoading = false;
  bool isLoadingMore = false;
  String errorMessage = "";
  int currentPage = 1;
  int pageSize = 25;
  int totalUsers = 0;
  bool _hasSearched = false;
  bool _waitingDebounce = false; // لعرض مؤشر انتظار أثناء التأخير قبل البحث

  // أرقام الهواتف المجلوبة لكل مستخدم: userId → phone
  final Map<String, String> _fetchedPhones = {};
  final Map<String, bool> _fetchingPhones = {};

  // متغيرات البحث
  final TextEditingController nameController = TextEditingController();
  final TextEditingController phoneController = TextEditingController();
  String selectedZoneId = "";
  // إدارة الكتابة والطلبات
  int _searchSeq = 0; // يزيد مع كل طلب
  int _lastAppliedSeq = 0; // آخر استجابة تم تطبيقها
  final ScrollController _scrollController = ScrollController();
  Timer? _debounce; // تأخير التنفيذ حتى ينتهي المستخدم من الكتابة
  // متحرك خلفية الواجهة
  late final AnimationController _bgController;
  late final Animation<double> _bgAnim;
  // بيانات الثلوج
  final List<_Snowflake> _flakes = [];
  bool _snowInitialized = false;
  // تركيز حقل الاسم مباشرة عند فتح الصفحة
  late final FocusNode _nameFocus;

  @override
  void initState() {
    super.initState();
    // إعداد متحرك الخلفية
    _bgController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 16),
    )..repeat();
    _bgAnim = CurvedAnimation(parent: _bgController, curve: Curves.easeInOut);
    _fetchZones();
    // مستمع للتمرير للتحميل اللامتناهي
    _scrollController.addListener(_onScroll);
    if (widget.initialSearchQuery != null && widget.initialSearchQuery!.isNotEmpty) {
      final query = widget.initialSearchQuery!;
      // إذا القيمة أرقام → ضعها في حقل الهاتف، وإلا في حقل الاسم
      if (RegExp(r'^\d+$').hasMatch(query.replaceAll('+', ''))) {
        phoneController.text = query;
      } else {
        nameController.text = query;
      }
      // بحث تلقائي بعد بناء الإطار
      WidgetsBinding.instance.addPostFrameCallback((_) {
        setState(() { currentPage = 1; _hasSearched = true; });
        _performSearch();
      });
    }
    _nameFocus = FocusNode();
    // طلب التركيز بعد بناء الإطار الأول
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _nameFocus.requestFocus();
      // نقل المؤشر لنهاية النص إن كان هناك استعلام مبدئي
      nameController.selection = TextSelection.fromPosition(
        TextPosition(offset: nameController.text.length),
      );
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // تهيئة الثلوج مرة واحدة حسب حجم الشاشة
    if (!_snowInitialized) {
      final size = MediaQuery.sizeOf(context);
      final area = size.width * size.height;
      final count = area.isFinite ? area ~/ 20000 : 60; // كثافة معتدلة
      final clamped = count.clamp(40, 120);
      final rnd = math.Random();
      _flakes.clear();
      for (int i = 0; i < clamped; i++) {
        _flakes.add(
          _Snowflake(
            x: rnd.nextDouble(),
            baseY: rnd.nextDouble(),
            size: 4.0 + rnd.nextDouble() * 4.0, // 4.0–8.0 px
            speedFactor: 3 + rnd.nextInt(4), // 3..6 أسرع
            drift: 10 + rnd.nextDouble() * 18, // انحراف أفقي أكبر
            phase: rnd.nextDouble(),
          ),
        );
      }
      _snowInitialized = true;
    }
  }

  // تحويل الأرقام العربية/الفارسية إلى إنجليزية
  String _convertEasternToWesternDigits(String input) {
    const easternArabic = '٠١٢٣٤٥٦٧٨٩';
    const persian = '۰۱۲۳۴۵۶۷۸۹';
    final buffer = StringBuffer();
    for (final ch in input.split('')) {
      final idxEa = easternArabic.indexOf(ch);
      if (idxEa != -1) {
        buffer.write(idxEa);
        continue;
      }
      final idxPe = persian.indexOf(ch);
      if (idxPe != -1) {
        buffer.write(idxPe);
        continue;
      }
      buffer.write(ch);
    }
    return buffer.toString();
  }

  String _normalizeName(String input) {
    return _convertEasternToWesternDigits(input).trim();
  }

  String _normalizePhone(String input) {
    final s = _convertEasternToWesternDigits(input);
    final digitsOnly = s.replaceAll(RegExp(r'[^0-9+]'), '');
    return digitsOnly.trim();
  }

  // تنفيذ البحث بعد التوقف عن الكتابة
  void _onQueryChanged() {
    _debounce?.cancel();
    final nameQ = _normalizeName(nameController.text);
    final phoneQ = _normalizePhone(phoneController.text);

    // إذا كانت الحقول فارغة، لا نبحث ونعود لحالة البداية
    if (nameQ.isEmpty && phoneQ.isEmpty) {
      setState(() {
        currentPage = 1;
        _hasSearched = false;
        searchResults.clear();
        totalUsers = 0;
        errorMessage = "";
      });
      return;
    }

    setState(() => _waitingDebounce = true);
    _debounce = Timer(const Duration(milliseconds: 900), () {
      if (!mounted) return;
      setState(() {
        currentPage = 1;
        _hasSearched = true;
        _waitingDebounce = false;
      });
      _performSearch();
    });
  }

  void _onScroll() {
    if (!_hasSearched) return;
    if (isLoadingMore || isLoading) return;
    if ((currentPage * pageSize) >= totalUsers) return; // لا مزيد من الصفحات

    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      setState(() {
        currentPage += 1;
        isLoadingMore = true;
      });
      _performSearch(append: true);
    }
  }

  // إبراز النص المطابق للاستعلام
  Widget _buildHighlightedText(String full, String query, {TextStyle? style}) {
    if (query.isEmpty) {
      return Text(full, style: style);
    }
    final lowerFull = full.toLowerCase();
    final lowerQuery = query.toLowerCase();
    final idx = lowerFull.indexOf(lowerQuery);
    if (idx < 0) return Text(full, style: style);

    final before = full.substring(0, idx);
    final match = full.substring(idx, idx + query.length);
    final after = full.substring(idx + query.length);

    return RichText(
      text: TextSpan(
        children: [
          TextSpan(text: before, style: style),
          TextSpan(
            text: match,
            style: (style ?? const TextStyle()).copyWith(
              backgroundColor: const Color(0xFF4CAF50).withValues(alpha: 0.25),
              fontWeight: FontWeight.w700,
            ),
          ),
          TextSpan(text: after, style: style),
        ],
      ),
      overflow: TextOverflow.ellipsis,
      maxLines: 1,
    );
  }

  Future<void> _fetchPhoneForUser(String userId) async {
    if (_fetchingPhones[userId] == true) return;
    setState(() => _fetchingPhones[userId] = true);
    try {
      final r = await AuthService.instance.authenticatedRequest(
        'GET',
        'https://admin.ftth.iq/api/customers/$userId',
        headers: {'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 10));
      if (!mounted) return;
      if (r.statusCode == 200) {
        final data = jsonDecode(r.body);
        final model = data is Map ? data['model'] ?? data : null;
        String? phone;
        if (model is Map) {
          phone = model['primaryContact']?['mobile']?.toString().trim() ??
              model['phone']?.toString().trim() ??
              model['phoneNumber']?.toString().trim();
        }
        setState(() {
          _fetchingPhones[userId] = false;
          if (phone != null && phone.isNotEmpty) {
            _fetchedPhones[userId] = phone;
          } else {
            _fetchedPhones[userId] = '';
          }
        });
        if ((phone == null || phone.isEmpty) && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('رقم الهاتف غير مسجل في النظام'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 2),
          ));
        }
      } else if (r.statusCode == 401) {
        if (mounted) AuthErrorHandler.handle401Error(context);
        return;
      } else {
        if (mounted) setState(() => _fetchingPhones[userId] = false);
      }
    } catch (_) {
      if (mounted) setState(() => _fetchingPhones[userId] = false);
    }
  }

  void _copyToClipboard(String label, String value) {
    Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('تم نسخ $label'),
          duration: const Duration(milliseconds: 1200),
        ),
      );
  }

  // لصق من الحافظة في الحقول (الاسم أو الهاتف) ثم تشغيل البحث المؤجل
  Future<void> _pasteIntoField(TextEditingController controller,
      {required bool isPhone}) async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final raw = data?.text ?? '';
      if (raw.isEmpty) return;
      final processed = isPhone ? _normalizePhone(raw) : _normalizeName(raw);
      if (!mounted) return;
      setState(() {
        controller.text = processed;
        controller.selection = TextSelection.fromPosition(
          TextPosition(offset: controller.text.length),
        );
        currentPage = 1;
        _hasSearched = true; // اعتبر أن المستخدم يريد البحث مباشرة بعد اللصق
      });
      _onQueryChanged();
    } catch (_) {
      // تجاهل أي أخطاء في اللصق بصمت
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _scrollController.dispose();
    nameController.dispose();
    phoneController.dispose();
    _bgController.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  Future<void> _fetchZones() async {
    try {
      final response = await AuthService.instance.authenticatedRequest(
        'GET',
        'https://api.ftth.iq/api/locations/zones',
        headers: {'Accept': 'application/json'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        // نسخ العناصر ثم فرزها تصاعديًا بطريقة طبيعية (تراعي الأرقام)
        final items = List<dynamic>.from(data['items'] as List? ?? []);
        items.sort((a, b) {
          final sa = a['self']?['displayValue']?.toString().trim() ?? '';
          final sb = b['self']?['displayValue']?.toString().trim() ?? '';

          // تقسيم إلى جزء نصي سابق للأرقام + الرقم الأول إن وجد
          final re = RegExp(r'^(\D*)(\d+)?');
          final ma = re.firstMatch(sa);
          final mb = re.firstMatch(sb);

          final pa = (ma?.group(1) ?? '').toLowerCase();
          final pb = (mb?.group(1) ?? '').toLowerCase();
          final cmpPrefix = pa.compareTo(pb);
          if (cmpPrefix != 0) return cmpPrefix;

          final na = int.tryParse(ma?.group(2) ?? '');
          final nb = int.tryParse(mb?.group(2) ?? '');

          if (na != null && nb != null && na != nb) {
            return na.compareTo(nb); // تصاعدي حسب الرقم
          }

          // في حال عدم وجود أرقام أو تساويها، فرز أبجدي كامل
          return sa.toLowerCase().compareTo(sb.toLowerCase());
        });

        setState(() {
          zones
            ..clear()
            ..addAll(items);
        });
      } else if (response.statusCode == 401) {
        if (mounted) AuthErrorHandler.handle401Error(context);
        return;
      }
    } catch (e) {
      setState(() {
        errorMessage = "خطأ في جلب المناطق: $e";
      });
    }
  }

  Future<void> _performSearch({bool append = false}) async {
    final nameQuery = _normalizeName(nameController.text);
    final phoneQuery = _normalizePhone(phoneController.text);

    // لا تُجري أي بحث إذا كانت الحقول فارغة
    if (nameQuery.isEmpty && phoneQuery.isEmpty) {
      if (!append) {
        setState(() {
          searchResults.clear();
          totalUsers = 0;
          errorMessage = "";
        });
      }
      return;
    }

    // قيود الحد الأدنى قبل تنفيذ البحث لتقليل الإرباك أثناء الكتابة
    // الاسم: 3 أحرف على الأقل إذا لم يكن هناك رقم هاتف
    if (phoneQuery.isEmpty && nameQuery.isNotEmpty && nameQuery.length < 2) {
      return;
    }
    // الهاتف: 7 أرقام على الأقل إذا لم يكن هناك اسم
    final phoneDigits = phoneQuery.replaceAll(RegExp(r'[^0-9]'), '');
    if (nameQuery.isEmpty && phoneDigits.isNotEmpty && phoneDigits.length < 7) {
      return;
    }

    final seq = ++_searchSeq; // تتبع الطلبات لتجاهل القديم

    if (!append) {
      setState(() {
        isLoading = true;
        errorMessage = "";
        if (currentPage == 1) searchResults.clear();
      });
    }

    try {
      String url =
          'https://api.ftth.iq/api/customers?pageSize=$pageSize&pageNumber=$currentPage&sortCriteria.property=self.displayValue&sortCriteria.direction=asc';

      if (nameQuery.isNotEmpty) {
        url += '&name=${Uri.encodeQueryComponent(nameQuery)}';
      }
      if (phoneQuery.isNotEmpty) {
        url += '&phone=${Uri.encodeQueryComponent(phoneQuery)}';
      }
      if (selectedZoneId.isNotEmpty) {
        url += '&zoneId=$selectedZoneId';
      }

      final response = await AuthService.instance.authenticatedRequest(
        'GET',
        url,
        headers: {'Accept': 'application/json'},
      );

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final items = List<dynamic>.from(data['items'] as List? ?? []);
        final total = data['totalCount'] ?? 0;

        if (seq < _lastAppliedSeq) {
          return; // استجابة قديمة
        }

        setState(() {
          _lastAppliedSeq = seq;
          totalUsers = total;
          if (append) {
            searchResults.addAll(items);
          } else {
            searchResults
              ..clear()
              ..addAll(items);
          }
          errorMessage = "";
        });
      } else if (response.statusCode == 401) {
        if (mounted) AuthErrorHandler.handle401Error(context);
        return;
      } else {
        if (seq < _lastAppliedSeq) return;
        setState(() {
          errorMessage = "فشل البحث: ${response.statusCode}";
        });
      }
    } catch (e) {
      if (!mounted) return;
      if (seq < _lastAppliedSeq) return;
      setState(() {
        errorMessage = "حدث خطأ أثناء البحث: $e";
      });
    } finally {
      if (!mounted) return;
      setState(() {
        if (append) {
          isLoadingMore = false;
        } else {
          isLoading = false;
          _waitingDebounce = false;
        }
      });
    }
  }

  // تمت إزالة أزرار التنقل؛ أصبح هناك تمرير لامتنهي

  void _resetSearch() {
    setState(() {
      nameController.clear();
      phoneController.clear();
      selectedZoneId = "";
      currentPage = 1;
      searchResults.clear();
      totalUsers = 0;
      errorMessage = "";
      _hasSearched = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final isLargeScreen = screenSize.width > 600;
    // تكبير البطاقة ومحتوياتها بنسبة 20%
    final double uiScale = 1.2;

    final scaffold = Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A237E),
        elevation: 0,
        centerTitle: true,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF1A237E), Color(0xFF3949AB)],
            ),
          ),
        ),
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.person_search, color: Colors.white),
            SizedBox(width: 8),
            Text(
              'البحث السريع - المستخدمين',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Stack(
        children: [
          // خلفية ثابتة — نفس ثيم الواجهة الرئيسية
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFFF5F6FA),
                  Color(0xFFEEF1F8),
                  Color(0xFFF0F4FF),
                  Color(0xFFF5F6FA),
                ],
              ),
            ),
          ),
          // المحتوى
          Column(
            children: [
              // شريط البحث — صف واحد: [المنطقة | اسم المشترك | رقم الهاتف | مسح]
              Container(
                margin: const EdgeInsets.fromLTRB(12, 10, 12, 6),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.black, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: isLargeScreen ? Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    // المنطقة — مخفية على الهاتف
                    if (isLargeScreen) SizedBox(
                      width: 180,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4, right: 2),
                            child: Text('المنطقة', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.grey.shade800)),
                          ),
                          DropdownButtonFormField<String>(
                            value: selectedZoneId.isEmpty ? "" : selectedZoneId,
                            decoration: InputDecoration(
                              filled: true,
                              fillColor: Colors.white,
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: const BorderSide(color: Colors.black, width: 1.5),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: const BorderSide(color: Color(0xFF1A237E), width: 2),
                              ),
                            ),
                            items: [
                              const DropdownMenuItem(value: "", child: Text("كل المناطق", style: TextStyle(fontSize: 13))),
                              ...zones.map((zone) {
                                final zoneId = zone['self']?['id']?.toString() ?? '';
                                final zoneName = zone['self']?['displayValue'] ?? 'غير معروف';
                                return DropdownMenuItem(value: zoneId, child: Text(zoneName, style: const TextStyle(fontSize: 13)));
                              }),
                            ],
                            onChanged: (value) {
                              setState(() => selectedZoneId = value ?? "");
                              if (nameController.text.isNotEmpty || phoneController.text.isNotEmpty) {
                                _onQueryChanged();
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                    if (isLargeScreen) const SizedBox(width: 8),
                    // حقل اسم المشترك
                    Expanded(
                      flex: 3,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4, right: 2),
                            child: Text('اسم المشترك', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.grey.shade800)),
                          ),
                          TextField(
                            controller: nameController,
                            textDirection: TextDirection.rtl,
                            textAlign: TextAlign.right,
                            textInputAction: TextInputAction.search,
                            focusNode: _nameFocus,
                            onChanged: (_) {
                              setState(() {});
                              _onQueryChanged();
                            },
                            onSubmitted: (_) {
                              setState(() { currentPage = 1; _hasSearched = true; });
                              _performSearch();
                            },
                            decoration: InputDecoration(
                              filled: true,
                              fillColor: Colors.white,
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                              prefixIcon: const Icon(Icons.person_search, color: Color(0xFF1A237E), size: 20),
                              suffixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
                              suffixIcon: (isLoading && nameController.text.isNotEmpty)
                                  ? _InlineSpinner(size: 16)
                                  : _waitingDebounce
                                      ? const _InlineDots()
                                      : (nameController.text.isNotEmpty
                                          ? IconButton(
                                              tooltip: 'مسح',
                                              icon: const Icon(Icons.clear, size: 16, color: Colors.red),
                                              onPressed: _resetSearch,
                                              padding: EdgeInsets.zero,
                                              constraints: const BoxConstraints(),
                                            )
                                          : IconButton(
                                              tooltip: 'لصق',
                                              icon: const Icon(Icons.content_paste_go, size: 16, color: Color(0xFF1A237E)),
                                              onPressed: () => _pasteIntoField(nameController, isPhone: false),
                                              padding: EdgeInsets.zero,
                                              constraints: const BoxConstraints(),
                                            )),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: const BorderSide(color: Colors.black, width: 1.5),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: const BorderSide(color: Color(0xFF1A237E), width: 2),
                              ),
                            ),
                            style: const TextStyle(fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    // حقل رقم الهاتف
                    Expanded(
                      flex: 2,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4, right: 2),
                            child: Text('رقم الهاتف', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.grey.shade800)),
                          ),
                          TextField(
                            controller: phoneController,
                            keyboardType: TextInputType.phone,
                            textDirection: TextDirection.rtl,
                            textAlign: TextAlign.right,
                            onChanged: (_) {
                              setState(() {});
                              _onQueryChanged();
                            },
                            onSubmitted: (_) {
                              setState(() { currentPage = 1; _hasSearched = true; });
                              _performSearch();
                            },
                            decoration: InputDecoration(
                              filled: true,
                              fillColor: Colors.white,
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                              prefixIcon: const Icon(Icons.phone, color: Color(0xFF1A237E), size: 18),
                              suffixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
                              suffixIcon: (isLoading && phoneController.text.isNotEmpty)
                                  ? _InlineSpinner(size: 16)
                                  : (phoneController.text.isNotEmpty
                                      ? IconButton(
                                          tooltip: 'مسح',
                                          icon: const Icon(Icons.clear, size: 16, color: Colors.red),
                                          onPressed: _resetSearch,
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(),
                                        )
                                      : IconButton(
                                          tooltip: 'لصق',
                                          icon: const Icon(Icons.content_paste_go, size: 16, color: Color(0xFF1A237E)),
                                          onPressed: () => _pasteIntoField(phoneController, isPhone: true),
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(),
                                        )),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: const BorderSide(color: Colors.black, width: 1.5),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: const BorderSide(color: Color(0xFF1A237E), width: 2),
                              ),
                            ),
                            style: const TextStyle(fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    // زر مسح
                    if (nameController.text.isNotEmpty || phoneController.text.isNotEmpty || selectedZoneId.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: IconButton(
                          tooltip: 'مسح الكل',
                          icon: const Icon(Icons.clear_all, color: Colors.red, size: 22),
                          onPressed: _resetSearch,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                        ),
                      ),
                  ],
                )
                // ══ Mobile: عمودي ══
                : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // اسم المشترك
                    TextField(
                      controller: nameController,
                      textDirection: TextDirection.rtl,
                      textAlign: TextAlign.right,
                      textInputAction: TextInputAction.search,
                      focusNode: _nameFocus,
                      onChanged: (_) { setState(() {}); _onQueryChanged(); },
                      onSubmitted: (_) { setState(() { currentPage = 1; _hasSearched = true; }); _performSearch(); },
                      decoration: InputDecoration(
                        labelText: 'اسم المشترك',
                        filled: true, fillColor: Colors.white, isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                        prefixIcon: const Icon(Icons.person_search, color: Color(0xFF1A237E), size: 18),
                        suffixIcon: nameController.text.isNotEmpty
                            ? IconButton(icon: const Icon(Icons.clear, size: 16, color: Colors.red), onPressed: _resetSearch, padding: EdgeInsets.zero, constraints: const BoxConstraints())
                            : null,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.blue.shade300)),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF1A237E), width: 2)),
                      ),
                      style: const TextStyle(fontSize: 13),
                    ),
                    const SizedBox(height: 8),
                    // رقم الهاتف
                    TextField(
                      controller: phoneController,
                      keyboardType: TextInputType.phone,
                      textDirection: TextDirection.ltr,
                      textAlign: TextAlign.left,
                      onChanged: (_) { setState(() {}); _onQueryChanged(); },
                      onSubmitted: (_) { setState(() { currentPage = 1; _hasSearched = true; }); _performSearch(); },
                      decoration: InputDecoration(
                        labelText: 'رقم الهاتف',
                        filled: true, fillColor: Colors.white, isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                        prefixIcon: const Icon(Icons.phone, color: Color(0xFF1A237E), size: 18),
                        suffixIcon: phoneController.text.isNotEmpty
                            ? IconButton(icon: const Icon(Icons.clear, size: 16, color: Colors.red), onPressed: _resetSearch, padding: EdgeInsets.zero, constraints: const BoxConstraints())
                            : null,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.blue.shade300)),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF1A237E), width: 2)),
                      ),
                      style: const TextStyle(fontSize: 13),
                    ),
                  ],
                ),
              ),

              // النتائج
              if (isLoading)
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color:
                                const Color(0xFF1A237E).withValues(alpha: 0.9),
                            borderRadius: BorderRadius.circular(18),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.25),
                                blurRadius: 12,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: Column(
                            children: [
                              SizedBox(
                                width: 54,
                                height: 54,
                                child: CircularProgressIndicator(
                                  strokeWidth: 6,
                                  valueColor: const AlwaysStoppedAnimation(
                                      Color(0xFF4CAF50)),
                                  backgroundColor:
                                      Colors.white.withValues(alpha: 0.25),
                                ),
                              ),
                              const SizedBox(height: 16),
                              const Text(
                                'جاري جلب النتائج...',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 16,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                        const Text(
                          'يتم الاتصال بالخادم، يرجى الانتظار',
                          style:
                              TextStyle(color: Color(0xFF2C3E50), fontSize: 12),
                        )
                      ],
                    ),
                  ),
                )
              else if (errorMessage.isNotEmpty)
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.error_outline,
                            size: 64, color: Colors.red.shade400),
                        const SizedBox(height: 16),
                        Text(
                          'خطأ: $errorMessage',
                          style: TextStyle(
                              color: Colors.red.shade600, fontSize: 16),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: _performSearch,
                          icon: const Icon(Icons.refresh),
                          label: const Text('إعادة المحاولة'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF4CAF50),
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else if (!_hasSearched)
                const Expanded(child: SizedBox.shrink())
              else if (_hasSearched && searchResults.isEmpty)
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.search_off,
                            size: 64, color: Colors.grey.shade400),
                        const SizedBox(height: 16),
                        Text(
                          'لا توجد نتائج للبحث الحالي',
                          style: TextStyle(
                              color: Colors.grey.shade600, fontSize: 16),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'جرب البحث بكلمات مختلفة أو تغيير نوع البحث',
                          style: TextStyle(
                              color: Colors.grey.shade500, fontSize: 14),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                )
              else
                Expanded(
                  child: Column(
                    children: [
                      // عداد النتائج
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 12),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1A237E),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.manage_search, color: Colors.white, size: 18),
                            const SizedBox(width: 8),
                            Text(
                              '$totalUsers مستخدم',
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
                            ),
                            const Spacer(),
                            if (totalUsers > 0)
                              InkWell(
                                onTap: _resetSearch,
                                borderRadius: BorderRadius.circular(6),
                                child: const Padding(
                                  padding: EdgeInsets.all(4),
                                  child: Icon(Icons.refresh, color: Colors.white, size: 18),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),

                      // قائمة النتائج
                      Expanded(
                        child: ListView.builder(
                          controller: _scrollController,
                          padding: EdgeInsets.symmetric(
                              horizontal: isLargeScreen ? 16 : 12),
                          itemCount:
                              searchResults.length + (isLoadingMore ? 1 : 0),
                          itemBuilder: (context, index) {
                            if (isLoadingMore &&
                                index == searchResults.length) {
                              return Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 20),
                                child: Center(
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      SizedBox(
                                        width: 34,
                                        height: 34,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 5,
                                          valueColor:
                                              const AlwaysStoppedAnimation(
                                                  Color(0xFF1A237E)),
                                          backgroundColor:
                                              const Color(0xFF4CAF50)
                                                  .withValues(alpha: 0.25),
                                        ),
                                      ),
                                      const SizedBox(width: 14),
                                      const Text(
                                        'تحميل المزيد...',
                                        style: TextStyle(
                                          color: Color(0xFF1A237E),
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }
                            final user = searchResults[index];
                            final userName =
                                user['self']?['displayValue'] ?? 'غير متوفر';
                            final userPhone = user['primaryContact']
                                    ?['mobile'] ??
                                'غير متوفر';
                            final userId =
                                user['self']?['id']?.toString() ?? '';

                            // بطاقة النتيجة — تصميم أفقي مدمج
                            return Builder(builder: (_) {
                              final fetchedPhone = _fetchedPhones[userId];
                              final displayPhone = (fetchedPhone != null && fetchedPhone.isNotEmpty)
                                  ? fetchedPhone
                                  : (userPhone != 'غير متوفر' ? userPhone : '');
                              final isFetching = _fetchingPhones[userId] == true;

                              return Card(
                                margin: const EdgeInsets.only(bottom: 10),
                                elevation: 3,
                                shadowColor: Colors.black.withValues(alpha: 0.15),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  side: const BorderSide(
                                    color: Colors.black,
                                    width: 1.2,
                                  ),
                                ),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(14),
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => UserDetailsPage(
                                          authToken: widget.authToken,
                                          userId: userId,
                                          userName: userName,
                                          userPhone: userPhone,
                                          activatedBy: widget.activatedBy,
                                          hasServerSavePermission: widget.hasServerSavePermission,
                                          hasWhatsAppPermission: widget.hasWhatsAppPermission,
                                          isAdminFlag: widget.isAdminFlag,
                                          userRoleHeader: '0',
                                          clientAppHeader: '53d57a7f-3f89-4e9d-873b-3d071bc6dd9f',
                                          importantFtthApiPermissions: widget.importantFtthApiPermissions,
                                          taskAgentName: widget.taskAgentName,
                                          taskAgentCode: widget.taskAgentCode,
                                        ),
                                      ),
                                    );
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                                    child: Row(
                                      children: [
                                        // أيقونة المستخدم
                                        Container(
                                          width: 54,
                                          height: 54,
                                          decoration: BoxDecoration(
                                            gradient: const LinearGradient(
                                              begin: Alignment.topLeft,
                                              end: Alignment.bottomRight,
                                              colors: [Color(0xFF1A237E), Color(0xFF3949AB)],
                                            ),
                                            borderRadius: BorderRadius.circular(14),
                                            boxShadow: [
                                              BoxShadow(
                                                color: const Color(0xFF1A237E).withValues(alpha: 0.3),
                                                blurRadius: 6,
                                                offset: const Offset(0, 3),
                                              ),
                                            ],
                                          ),
                                          child: const Icon(Icons.person, color: Colors.white, size: 28),
                                        ),
                                        const SizedBox(width: 16),
                                        // المعلومات الرئيسية
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              // الاسم
                                              Row(
                                                children: [
                                                  Expanded(
                                                    child: _buildHighlightedText(
                                                      userName.toString(),
                                                      _normalizeName(nameController.text),
                                                      style: const TextStyle(
                                                        fontWeight: FontWeight.w700,
                                                        fontSize: 16,
                                                        color: Color(0xFF1A237E),
                                                      ),
                                                    ),
                                                  ),
                                                  InkWell(
                                                    onTap: () => _copyToClipboard('الاسم', userName),
                                                    borderRadius: BorderRadius.circular(4),
                                                    child: Padding(
                                                      padding: const EdgeInsets.all(4),
                                                      child: Icon(Icons.copy_rounded, size: 16, color: Colors.grey.shade500),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 10),
                                              // الهاتف + ID في صف واحد
                                              Row(
                                                children: [
                                                  // الهاتف
                                                  Icon(Icons.phone, size: 15, color: Colors.grey.shade500),
                                                  const SizedBox(width: 5),
                                                  if (isFetching)
                                                    const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 1.5))
                                                  else if (displayPhone.isNotEmpty)
                                                    InkWell(
                                                      onTap: () => _copyToClipboard('رقم الهاتف', displayPhone),
                                                      child: Text(displayPhone, style: TextStyle(fontSize: 14, color: Colors.grey.shade700, fontWeight: FontWeight.w500)),
                                                    )
                                                  else if (userId.isNotEmpty && _fetchedPhones[userId] == null)
                                                    InkWell(
                                                      onTap: () => _fetchPhoneForUser(userId),
                                                      child: Container(
                                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                                        decoration: BoxDecoration(
                                                          color: Colors.blue.shade50,
                                                          borderRadius: BorderRadius.circular(6),
                                                          border: Border.all(color: Colors.blue.shade200),
                                                        ),
                                                        child: Text('إظهار الرقم', style: TextStyle(fontSize: 12, color: Colors.blue.shade700, fontWeight: FontWeight.w600)),
                                                      ),
                                                    )
                                                  else
                                                    Text('غير متوفر', style: TextStyle(fontSize: 14, color: Colors.grey.shade400)),
                                                  const SizedBox(width: 20),
                                                  // ID
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                                    decoration: BoxDecoration(
                                                      color: Colors.grey.shade100,
                                                      borderRadius: BorderRadius.circular(6),
                                                    ),
                                                    child: InkWell(
                                                      onTap: userId.isEmpty ? null : () => _copyToClipboard('ID', userId),
                                                      child: Row(
                                                        mainAxisSize: MainAxisSize.min,
                                                        children: [
                                                          Text('ID: ', style: TextStyle(fontSize: 12, color: Colors.grey.shade500, fontWeight: FontWeight.w600)),
                                                          Text(
                                                            userId.isEmpty ? '-' : userId,
                                                            style: TextStyle(fontSize: 12, color: Colors.grey.shade700, fontWeight: FontWeight.w500),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        // سهم
                                        Container(
                                          padding: const EdgeInsets.all(6),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF1A237E).withValues(alpha: 0.08),
                                            shape: BoxShape.circle,
                                          ),
                                          child: const Icon(Icons.arrow_forward_ios, size: 14, color: Color(0xFF1A237E)),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            });
                          },
                        ),
                      ),
                      // التمرير اللامتناهي يعرض مؤشر تحميل أسفل القائمة
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
    return scaffold;
  }
}

// نموذج بيانات للثلج
class _Snowflake {
  _Snowflake({
    required this.x,
    required this.baseY,
    required this.size,
    required this.speedFactor,
    required this.drift,
    required this.phase,
  });

  final double x; // نسبة أفقية 0..1
  final double baseY; // نسبة ابتدائية 0..1
  final double size; // نصف القطر بالبكسل
  final int speedFactor; // يضاعف السرعة
  final double drift; // سعة الانحراف الأفقي بالبكسل
  final double phase; // طور مبدئي للموجة
}

// الرسّام المخصص للثلوج
class _SnowPainter extends CustomPainter {
  _SnowPainter({required this.flakes, required this.anim})
      : super(repaint: anim);

  final List<_Snowflake> flakes;
  final Animation<double> anim;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    final glow = Paint()
      ..color =
          const Color(0xFF90CAF9).withValues(alpha: 0.35) // أزرق فاتح كالهالة
      ..style = PaintingStyle.fill
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);

    final t = anim.value; // 0..1 متغيّر الزمن

    for (final f in flakes) {
      // سرعة أكبر: مسافة الهبوط لكل دورة تعتمد على ارتفاع الشاشة
      final travel = size.height * (1.0 + 0.8 * (f.speedFactor / 5.0));
      final y = (f.baseY * size.height + t * travel) % (size.height + 60) - 30;

      // انحراف أفقي بسيط على شكل موجة جيبية
      final xCenter =
          f.x * size.width + math.sin((t * 2 * math.pi) + f.phase) * f.drift;

      final center = Offset(xCenter, y);
      // هالة خفيفة لزيادة بروز الثلج
      canvas.drawCircle(center, f.size * 1.8, glow);
      // جسم الثلجة
      canvas.drawCircle(center, f.size, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _SnowPainter oldDelegate) {
    return oldDelegate.flakes != flakes || oldDelegate.anim != anim;
  }
}

// مؤشر تحميل صغير داخل حقل النص
class _InlineSpinner extends StatelessWidget {
  const _InlineSpinner({this.size = 18});
  final double size;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: SizedBox(
        width: size,
        height: size,
        child: CircularProgressIndicator(
          strokeWidth: 3,
          valueColor: const AlwaysStoppedAnimation(Color(0xFF1A237E)),
        ),
      ),
    );
  }
}

// نقاط نابضة أثناء الانتظار قبل تنفيذ البحث (debounce)
class _InlineDots extends StatefulWidget {
  const _InlineDots();
  @override
  State<_InlineDots> createState() => _InlineDotsState();
}

class _InlineDotsState extends State<_InlineDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  @override
  void initState() {
    super.initState();
    _c = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = _c.value; // 0..1
        // ثلاثة أوزان متفاوتة
        double s(int i) {
          final phase = (t + i / 3) % 1.0;
          return 0.4 + 0.6 * (1 - (phase - 0.5).abs() * 2); // ذروة في المنتصف
        }

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(
                3,
                (i) => Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: Container(
                        width: 6 * s(i),
                        height: 6 * s(i),
                        decoration: const BoxDecoration(
                          color: Color(0xFF4CAF50),
                          shape: BoxShape.circle,
                        ),
                      ),
                    )),
          ),
        );
      },
    );
  }
}
