/// اسم الصفحة: البحث السريع للمستخدمين
/// وصف الصفحة: صفحة البحث السريع عن المستخدمين
/// المؤلف: تطبيق السدارة
/// تاريخ الإنشاء: 2024
library;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/services.dart';
import '../users/user_details_page.dart';

class QuickSearchUsersPage extends StatefulWidget {
  final String authToken;
  final String activatedBy;
  final String? initialSearchQuery;
  final bool hasServerSavePermission;
  final bool hasWhatsAppPermission;
  final String? firstSystemPermissions; // صلاحيات النظام الأول
  final bool? isAdminFlag; // علم إداري صريح
  // قائمة الصلاحيات المهمة من نظام FTTH (مفلترة مسبقاً في الصفحة الرئيسية)
  final List<String>? importantFtthApiPermissions;

  const QuickSearchUsersPage({
    super.key,
    required this.authToken,
    required this.activatedBy,
    this.initialSearchQuery,
    this.hasServerSavePermission = false,
    this.hasWhatsAppPermission = false,
    this.firstSystemPermissions,
    this.isAdminFlag,
    this.importantFtthApiPermissions,
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
    if (widget.initialSearchQuery != null) {
      nameController.text = widget.initialSearchQuery!;
      // لا يتم البحث تلقائيًا؛ سيتم البحث عند الضغط على زر "بحث"
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
      final response = await http.get(
        Uri.parse('https://api.ftth.iq/api/locations/zones'),
        headers: {
          'Authorization': 'Bearer ${widget.authToken}',
          'Accept': 'application/json',
        },
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

      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Authorization': 'Bearer ${widget.authToken}',
          'Accept': 'application/json',
        },
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
          // خلفية سماوية ثابتة
          IgnorePointer(
            ignoring: true,
            child: Container(color: const Color.fromARGB(255, 17, 116, 162)),
          ),
          // طبقة الثلوج
          if (_flakes.isNotEmpty)
            IgnorePointer(
              ignoring: true,
              child: CustomPaint(
                painter: _SnowPainter(flakes: _flakes, anim: _bgAnim),
                size: Size.infinite,
              ),
            ),
          // المحتوى
          Column(
            children: [
              // شريط البحث والفلاتر الجديد
              Container(
                margin: EdgeInsets.all(isLargeScreen ? 16 : 10),
                padding: EdgeInsets.all(isLargeScreen ? 14 : 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.green.withValues(alpha: 0.07),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue:
                                selectedZoneId.isEmpty ? null : selectedZoneId,
                            decoration: InputDecoration(
                              labelText: 'المنطقة',
                              filled: true,
                              fillColor: Colors.teal.shade50,
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(
                                  color: Colors.teal.shade200,
                                  width: 1.5,
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(
                                  color: Colors.teal.shade400,
                                  width: 2,
                                ),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 10),
                            ),
                            hint: const Text("كل المناطق"),
                            items: [
                              const DropdownMenuItem(
                                  value: "", child: Text("كل المناطق")),
                              ...zones.map((zone) {
                                final zoneId =
                                    zone['self']?['id']?.toString() ?? '';
                                final zoneName = zone['self']
                                        ?['displayValue'] ??
                                    'غير معروف';
                                return DropdownMenuItem(
                                  value: zoneId,
                                  child: Text(zoneName),
                                );
                              }),
                            ],
                            onChanged: (value) {
                              setState(() {
                                selectedZoneId = value ?? "";
                              });
                              // نفذ البحث بعد التوقف عن الكتابة إذا كان هناك استعلام
                              if (nameController.text.isNotEmpty ||
                                  phoneController.text.isNotEmpty) {
                                _onQueryChanged();
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    // حقلا البحث: الاسم ثم الهاتف أسفلهما في كل الأحجام
                    Column(
                      children: [
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            onPressed: _resetSearch,
                            icon: const Icon(Icons.clear_all,
                                color: Color(0xFF4CAF50)),
                            label: const Text('مسح',
                                style: TextStyle(color: Color(0xFF4CAF50))),
                          ),
                        ),
                        Container(
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.green, width: 2),
                            borderRadius: BorderRadius.circular(12),
                            color: Colors.white,
                          ),
                          child: TextField(
                            controller: nameController,
                            // جعل الاتجاه افتراضياً من اليمين لليسار لدعم العربية
                            textDirection: TextDirection.rtl,
                            textAlign: TextAlign.right,
                            textInputAction: TextInputAction.search,
                            focusNode: _nameFocus,
                            // البحث يتم بعد التوقف عن الكتابة
                            onChanged: (_) {
                              setState(() {}); // لتحديث زر/أيقونة المسح
                              _onQueryChanged();
                            },
                            onSubmitted: (_) {
                              setState(() {
                                currentPage = 1;
                                _hasSearched = true;
                              });
                              _performSearch();
                            },
                            decoration: InputDecoration(
                              hintText: 'أسم المشترك',
                              border: InputBorder.none,
                              prefixIcon: Icon(Icons.search_rounded,
                                  color: Colors.green[700], size: 26),
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 10),
                              suffixIconConstraints: const BoxConstraints(
                                  minWidth: 0, minHeight: 0),
                              suffixIcon: isLoading
                                  ? _InlineSpinner()
                                  : _waitingDebounce
                                      ? const _InlineDots()
                                      : Padding(
                                          padding:
                                              const EdgeInsetsDirectional.only(
                                                  end: 4),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              IconButton(
                                                tooltip: 'لصق',
                                                icon: const Icon(
                                                    Icons.content_paste_go,
                                                    size: 20,
                                                    color: Color(0xFF1A237E)),
                                                onPressed: () =>
                                                    _pasteIntoField(
                                                        nameController,
                                                        isPhone: false),
                                              ),
                                              if (nameController
                                                  .text.isNotEmpty)
                                                IconButton(
                                                  tooltip: 'مسح',
                                                  icon: const Icon(Icons.clear,
                                                      size: 20,
                                                      color: Colors.red),
                                                  onPressed: _resetSearch,
                                                ),
                                            ],
                                          ),
                                        ),
                            ),
                            style: TextStyle(fontSize: isLargeScreen ? 16 : 14),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.green, width: 2),
                            borderRadius: BorderRadius.circular(12),
                            color: Colors.white,
                          ),
                          child: TextField(
                            controller: phoneController,
                            keyboardType: TextInputType.phone,
                            textDirection: TextDirection.rtl,
                            textAlign: TextAlign.right,
                            // البحث يتم بعد التوقف عن الكتابة
                            onChanged: (_) {
                              setState(() {});
                              _onQueryChanged();
                            },
                            onSubmitted: (_) {
                              setState(() {
                                currentPage = 1;
                                _hasSearched = true;
                              });
                              _performSearch();
                            },
                            decoration: InputDecoration(
                              hintText: 'رقم الهاتف',
                              border: InputBorder.none,
                              prefixIcon: Icon(Icons.phone,
                                  color: Colors.green[700], size: 20),
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 10),
                              suffixIconConstraints: const BoxConstraints(
                                  minWidth: 0, minHeight: 0),
                              suffixIcon: isLoading
                                  ? _InlineSpinner(size: 16)
                                  : _waitingDebounce
                                      ? const _InlineDots()
                                      : Padding(
                                          padding:
                                              const EdgeInsetsDirectional.only(
                                                  end: 4),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              IconButton(
                                                tooltip: 'لصق',
                                                icon: const Icon(
                                                    Icons.content_paste_go,
                                                    size: 18,
                                                    color: Color(0xFF1A237E)),
                                                onPressed: () =>
                                                    _pasteIntoField(
                                                        phoneController,
                                                        isPhone: true),
                                              ),
                                              if (phoneController
                                                  .text.isNotEmpty)
                                                IconButton(
                                                  tooltip: 'مسح',
                                                  icon: const Icon(Icons.clear,
                                                      size: 18,
                                                      color: Colors.red),
                                                  onPressed: _resetSearch,
                                                ),
                                            ],
                                          ),
                                        ),
                            ),
                            style: TextStyle(fontSize: isLargeScreen ? 16 : 14),
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],
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
                      // عداد النتائج (تصميم أوضح)
                      Container(
                        margin: EdgeInsets.symmetric(
                            horizontal: isLargeScreen ? 16 : 12),
                        padding: EdgeInsets.symmetric(
                          horizontal: isLargeScreen ? 14 : 10,
                          vertical: isLargeScreen ? 6 : 5,
                        ),
                        constraints: const BoxConstraints(minHeight: 40),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF1B5E20), Color(0xFF2E7D32)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.12),
                              blurRadius: 6,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.18),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.manage_search,
                                color: Colors.white,
                                size: isLargeScreen ? 18 : 16,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: RichText(
                                text: TextSpan(
                                  style: TextStyle(
                                    fontFamily: 'Cairo',
                                    color: Colors.white,
                                    fontSize: isLargeScreen ? 12.5 : 11.5,
                                    height: 1.2,
                                  ),
                                  children: [
                                    const TextSpan(
                                      text: 'النتائج: ',
                                      style: TextStyle(
                                          fontWeight: FontWeight.w600),
                                    ),
                                    WidgetSpan(
                                      alignment: PlaceholderAlignment.middle,
                                      child: AnimatedContainer(
                                        duration:
                                            const Duration(milliseconds: 300),
                                        curve: Curves.easeOut,
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 2),
                                        margin:
                                            const EdgeInsetsDirectional.only(
                                                start: 3),
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius:
                                              BorderRadius.circular(16),
                                        ),
                                        child: Text(
                                          '$totalUsers',
                                          style: TextStyle(
                                            color: const Color(0xFF1B5E20),
                                            fontWeight: FontWeight.w700,
                                            fontSize: isLargeScreen ? 13 : 11.5,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const TextSpan(
                                      text: ' مستخدم',
                                      style: TextStyle(
                                          fontWeight: FontWeight.w500),
                                    ),
                                  ],
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (totalUsers > 0)
                              IconButton(
                                onPressed: _resetSearch,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                splashRadius: 18,
                                icon: const Icon(Icons.refresh,
                                    color: Colors.white, size: 18),
                                tooltip: 'مسح',
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),

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

                            return Card(
                              margin: EdgeInsets.only(bottom: 6 * uiScale),
                              elevation: 1.5,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: BorderSide(
                                  color: const Color(0xFF4CAF50)
                                      .withValues(alpha: 0.18),
                                  width: 1,
                                ),
                              ),
                              child: Stack(
                                children: [
                                  // محتوى البطاقة
                                  ListTile(
                                    contentPadding: EdgeInsets.symmetric(
                                      horizontal:
                                          (isLargeScreen ? 14.0 : 10.0) *
                                              uiScale,
                                      vertical: (isLargeScreen ? 12.0 : 10.0) *
                                          uiScale,
                                    ),
                                    title: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              Icons.person_outline,
                                              size: (isLargeScreen
                                                      ? 20.0
                                                      : 18.0) *
                                                  uiScale,
                                              color: Color(0xFF1A237E),
                                            ),
                                            SizedBox(width: 6 * uiScale),
                                            Text(
                                              'معلومات المستخدم',
                                              style: TextStyle(
                                                fontSize: (isLargeScreen
                                                        ? 14.0
                                                        : 12.0) *
                                                    uiScale,
                                                fontWeight: FontWeight.w700,
                                                color: Color(0xFF1A237E),
                                              ),
                                            ),
                                          ],
                                        ),
                                        SizedBox(height: 6 * uiScale),
                                        // Box: الاسم
                                        Container(
                                          padding: EdgeInsets.symmetric(
                                            horizontal: 8 * uiScale,
                                            vertical:
                                                (isLargeScreen ? 6.0 : 5.0) *
                                                    uiScale,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.green.shade50,
                                            border: Border.all(
                                                color: Colors.green.shade200),
                                            borderRadius:
                                                BorderRadius.circular(8),
                                          ),
                                          child: Row(
                                            children: [
                                              Icon(
                                                Icons.person,
                                                size: (isLargeScreen
                                                        ? 18.0
                                                        : 16.0) *
                                                    uiScale,
                                                color: Colors.green.shade700,
                                              ),
                                              SizedBox(width: 6 * uiScale),
                                              Expanded(
                                                child: _buildHighlightedText(
                                                  userName.toString(),
                                                  _normalizeName(
                                                      nameController.text),
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.w700,
                                                    fontSize: (isLargeScreen
                                                            ? 14.0
                                                            : 13.0) *
                                                        uiScale,
                                                    color:
                                                        const Color(0xFF2C3E50),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        SizedBox(height: 4 * uiScale),
                                        // Box: الهاتف
                                        Container(
                                          padding: EdgeInsets.symmetric(
                                            horizontal: 8 * uiScale,
                                            vertical:
                                                (isLargeScreen ? 6.0 : 5.0) *
                                                    uiScale,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.blue.shade50,
                                            border: Border.all(
                                                color: Colors.blue.shade200),
                                            borderRadius:
                                                BorderRadius.circular(8),
                                          ),
                                          child: Row(
                                            children: [
                                              Icon(
                                                Icons.phone,
                                                size: (isLargeScreen
                                                        ? 16.0
                                                        : 14.0) *
                                                    uiScale,
                                                color: Colors.blue.shade700,
                                              ),
                                              SizedBox(width: 6 * uiScale),
                                              Expanded(
                                                child: _buildHighlightedText(
                                                  userPhone.toString(),
                                                  _normalizePhone(
                                                      phoneController.text),
                                                  style: TextStyle(
                                                    fontSize: (isLargeScreen
                                                            ? 13.0
                                                            : 11.0) *
                                                        uiScale,
                                                    color:
                                                        const Color(0xFF2C3E50),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        SizedBox(height: 4 * uiScale),
                                        // Box: المعرف + زر النسخ
                                        Container(
                                          padding: EdgeInsets.symmetric(
                                            horizontal: 8 * uiScale,
                                            vertical:
                                                (isLargeScreen ? 6.0 : 5.0) *
                                                    uiScale,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.indigo.shade50,
                                            border: Border.all(
                                                color: Colors.indigo.shade200),
                                            borderRadius:
                                                BorderRadius.circular(8),
                                          ),
                                          child: Row(
                                            children: [
                                              Icon(
                                                Icons.badge,
                                                size: (isLargeScreen
                                                        ? 16.0
                                                        : 14.0) *
                                                    uiScale,
                                                color: Colors.indigo.shade700,
                                              ),
                                              SizedBox(width: 6 * uiScale),
                                              Text(
                                                'ID:',
                                                style: TextStyle(
                                                  fontWeight: FontWeight.w700,
                                                  color: Colors.indigo.shade700,
                                                  fontSize: (isLargeScreen
                                                          ? 13.0
                                                          : 11.0) *
                                                      uiScale,
                                                ),
                                              ),
                                              SizedBox(width: 6 * uiScale),
                                              Expanded(
                                                child: Text(
                                                  userId.isEmpty
                                                      ? 'غير متوفر'
                                                      : userId,
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.w600,
                                                    color:
                                                        const Color(0xFF2C3E50),
                                                    fontSize: (isLargeScreen
                                                            ? 13.0
                                                            : 11.0) *
                                                        uiScale,
                                                  ),
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ),
                                              IconButton(
                                                tooltip: 'نسخ ID',
                                                icon: Icon(Icons.copy,
                                                    size: 24 * uiScale),
                                                padding:
                                                    EdgeInsets.all(4 * uiScale),
                                                constraints: BoxConstraints(
                                                  minWidth: 40 * uiScale,
                                                  minHeight: 40 * uiScale,
                                                ),
                                                splashRadius: 22 * uiScale,
                                                onPressed: userId.isEmpty
                                                    ? null
                                                    : () => _copyToClipboard(
                                                        'ID', userId),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                    trailing: Icon(
                                      Icons.arrow_forward_ios,
                                      color: const Color(0xFF4CAF50),
                                      size: (isLargeScreen ? 18.0 : 14.0) *
                                          uiScale,
                                    ),
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
                                            hasServerSavePermission:
                                                widget.hasServerSavePermission,
                                            hasWhatsAppPermission:
                                                widget.hasWhatsAppPermission,
                                            firstSystemPermissions:
                                                widget.firstSystemPermissions,
                                            isAdminFlag: widget.isAdminFlag,
                                            userRoleHeader: '0',
                                            clientAppHeader:
                                                '53d57a7f-3f89-4e9d-873b-3d071bc6dd9f',
                                            importantFtthApiPermissions: widget
                                                .importantFtthApiPermissions,
                                          ),
                                        ),
                                      );
                                    },
                                  ),

                                  // تمت إزالة الشارة العلوية - الأيقونة أصبحت بجانب الاسم
                                ],
                              ),
                            );
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
