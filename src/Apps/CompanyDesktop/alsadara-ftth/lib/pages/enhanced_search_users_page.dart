/// اسم الصفحة: البحث المحسن عن المستخدمين
/// وصف الصفحة: صفحة البحث المتطورة مع خيارات فلترة متقدمة
/// المؤلف: تطبيق السدارة
/// تاريخ الإنشاء: 2024
library;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:math';
import '../config/app_secrets.dart';

class EnhancedSearchUsersPage extends StatefulWidget {
  const EnhancedSearchUsersPage({super.key});

  @override
  State<EnhancedSearchUsersPage> createState() =>
      _EnhancedSearchUsersPageState();
}

class _EnhancedSearchUsersPageState extends State<EnhancedSearchUsersPage> {
  // 🔒 تم نقل المفتاح إلى AppSecrets
  String get apiKey => appSecrets.googleSheetsApiKey;
  final String spreadsheetId = '1MGY8UhtHaUiRaUKbohEi3a74jgEh7NeOuTEHBQ83KZc';

  final _formKey = GlobalKey<FormState>();

  // الحقول النصية
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _regionSearchController = TextEditingController();
  final TextEditingController _motherNameController = TextEditingController();

  // بيانات المستخدمين
  List<Map<String, String>> users = [];

  // قائمة المناطق
  Set<String> uniqueRegions = {};
  List<String> filteredRegions = [];
  String? selectedRegion;

  // قائمة النتائج (العلاقة + بيانات المستخدم)
  List<Map<String, String>> matches = [];

  bool isLoading = false;
  bool hasError = false;
  String errorMessage = '';

  // إعدادات المطابقة الذكية
  bool enableSmartMatching = true;
  double similarityThreshold = 0.8; // حد التشابه المطلوب (80%)
  bool enablePartialMatching = true;
  bool enableFuzzyMatching = true;

  @override
  void initState() {
    super.initState();
    _loadRegions();
    _regionSearchController.addListener(_filterRegions);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _regionSearchController.dispose();
    _motherNameController.dispose();
    super.dispose();
  }

  //============================================================================
  // خوارزميات التشابه النصي والمطابقة الذكية
  //============================================================================

  /// حساب مسافة ليفنشتاين (Levenshtein Distance) لقياس التشابه بين النصوص
  int _levenshteinDistance(String s1, String s2) {
    if (s1.isEmpty) return s2.length;
    if (s2.isEmpty) return s1.length;

    List<List<int>> matrix = List.generate(
      s1.length + 1,
      (i) => List.generate(s2.length + 1, (j) => 0),
    );

    for (int i = 0; i <= s1.length; i++) {
      matrix[i][0] = i;
    }
    for (int j = 0; j <= s2.length; j++) {
      matrix[0][j] = j;
    }

    for (int i = 1; i <= s1.length; i++) {
      for (int j = 1; j <= s2.length; j++) {
        int cost = s1[i - 1] == s2[j - 1] ? 0 : 1;
        matrix[i][j] = [
          matrix[i - 1][j] + 1, // deletion
          matrix[i][j - 1] + 1, // insertion
          matrix[i - 1][j - 1] + cost, // substitution
        ].reduce(min);
      }
    }

    return matrix[s1.length][s2.length];
  }

  /// حساب نسبة التشابه بين نصين (0.0 - 1.0)
  double _calculateSimilarity(String s1, String s2) {
    if (s1.isEmpty && s2.isEmpty) return 1.0;
    if (s1.isEmpty || s2.isEmpty) return 0.0;

    // تطبيع النصوص (إزالة المسافات الزائدة وتوحيد الحالة)
    s1 = _normalizeText(s1);
    s2 = _normalizeText(s2);

    int maxLength = max(s1.length, s2.length);
    int distance = _levenshteinDistance(s1, s2);

    return 1.0 - (distance / maxLength);
  }

  /// تطبيع النص (إزالة المسافات الزائدة، توحيد الحالة، إزالة الرموز)
  String _normalizeText(String text) {
    return text
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), ' ') // توحيد المسافات
        .replaceAll(RegExp(r'[^\u0600-\u06FF\u0750-\u077F\s]'),
            '') // إبقاء العربية والمسافات فقط
        .trim();
  }

  /// فحص التطابق الذكي بين اسمين
  bool _isSmartMatch(String name1, String name2, {double? threshold}) {
    threshold ??= similarityThreshold;

    // التطابق التام أولاً
    if (_normalizeText(name1) == _normalizeText(name2)) {
      return true;
    }

    // حساب التشابه
    double similarity = _calculateSimilarity(name1, name2);
    debugPrint(
        '🔍 Similarity between "$name1" and "$name2": ${(similarity * 100).toStringAsFixed(1)}%');

    return similarity >= threshold;
  }

  /// فحص التطابق الجزئي
  bool _isPartialMatch(String searchName, String userName) {
    if (!enablePartialMatching) return false;

    String normalizedSearch = _normalizeText(searchName);
    String normalizedUser = _normalizeText(userName);

    // فحص احتواء كامل
    if (normalizedUser.contains(normalizedSearch) ||
        normalizedSearch.contains(normalizedUser)) {
      return true;
    }

    // فحص احتواء أجزاء الاسم
    List<String> searchParts = normalizedSearch.split(' ');
    List<String> userParts = normalizedUser.split(' ');

    int matchedParts = 0;
    for (String searchPart in searchParts) {
      if (searchPart.length < 2) continue; // تجاهل الأجزاء القصيرة جداً

      for (String userPart in userParts) {
        if (_isSmartMatch(searchPart, userPart, threshold: 0.7)) {
          matchedParts++;
          break;
        }
      }
    }

    // يجب أن يتطابق على الأقل نصف الأجزاء
    return matchedParts >= (searchParts.length / 2).ceil();
  }

  /// المطابقة المحسنة للأسماء مع دعم التشابه والبحث الجزئي
  bool _enhancedNameMatch(List<String> myParts, List<String> otherParts,
      List<int> myIndices, List<int> otherIndices) {
    if (myIndices.length != otherIndices.length) return false;

    for (int i = 0; i < myIndices.length; i++) {
      int myIndex = myIndices[i];
      int otherIndex = otherIndices[i];

      if (myIndex >= myParts.length || otherIndex >= otherParts.length) {
        return false;
      }

      String myName = myParts[myIndex];
      String otherName = otherParts[otherIndex];

      // استخدام المطابقة الذكية
      if (enableSmartMatching) {
        if (!_isSmartMatch(myName, otherName)) {
          if (enableFuzzyMatching && !_isPartialMatch(myName, otherName)) {
            return false;
          } else if (!enableFuzzyMatching) {
            return false;
          }
        }
      } else {
        // المطابقة التقليدية (حرفية)
        if (_normalizeText(myName) != _normalizeText(otherName)) {
          return false;
        }
      }
    }

    return true;
  }

  /// فحص عدم التطابق المحسن
  bool _enhancedNameMismatch(List<String> myParts, List<String> otherParts,
      List<int> myIndices, List<int> otherIndices) {
    for (int i = 0; i < myIndices.length; i++) {
      int myIndex = myIndices[i];
      int otherIndex = otherIndices[i];

      if (myIndex >= myParts.length || otherIndex >= otherParts.length) {
        continue;
      }

      String myName = myParts[myIndex];
      String otherName = otherParts[otherIndex];

      if (enableSmartMatching) {
        if (_isSmartMatch(myName, otherName)) {
          return false; // وجد تطابق، لذا ليس عدم تطابق
        }
      } else {
        if (_normalizeText(myName) == _normalizeText(otherName)) {
          return false;
        }
      }
    }

    return true; // جميع الأجزاء مختلفة
  }

  //============================================================================
  // دوال فحص العلاقات المحسنة
  //============================================================================

  /// التطابق التام المحسن (الشخص نفسه)
  bool _checkExactMatchEnhanced(List<String> my, List<String> other) {
    if (my.length < 3 || other.length < 3) return false;

    return _enhancedNameMatch(my, other, [0, 1, 2], [0, 1, 2]);
  }

  /// فحص الأخ المحسن
  bool _checkBrotherEnhanced(List<String> my, List<String> other) {
    if (my.length < 4 || other.length < 3) return false;

    // تطابق اسم الأب والجد وعدم تطابق الاسم الأول
    return _enhancedNameMatch(my, other, [1, 2, 3], [0, 1, 2]) &&
        _enhancedNameMismatch(my, other, [0], [0]);
  }

  /// فحص العم المحسن
  bool _checkUncleEnhanced(List<String> my, List<String> other) {
    if (my.length < 4 || other.length < 3) return false;

    // تطابق اسم الجد وعدم تطابق الباقي
    return _enhancedNameMatch(my, other, [2, 3], [1, 2]) &&
        _enhancedNameMismatch(my, other, [0, 1], [0, 0]);
  }

  /// فحص الجد المحسن
  bool _checkGrandpaEnhanced(List<String> my, List<String> other) {
    if (my.length < 4 || other.length < 3) return false;

    return _enhancedNameMatch(my, other, [2, 3], [0, 1]) &&
        _enhancedNameMismatch(my, other, [0, 1], [0, 1]);
  }

  /// فحص الأب المحسن
  bool _checkFatherEnhanced(List<String> my, List<String> other) {
    if (my.length < 4 || other.length < 3) return false;

    return _enhancedNameMatch(my, other, [1, 2, 3], [0, 1, 2]) &&
        _enhancedNameMismatch(my, other, [0], [0]);
  }

  /// البحث الذكي بالاسم الكامل (بحث مرن)
  List<Map<String, String>> _smartFullNameSearch(String searchName) {
    List<Map<String, String>> results = [];

    for (var user in users) {
      String userName = user['name'] ?? '';
      if (userName.isEmpty) continue;

      double similarity = _calculateSimilarity(searchName, userName);
      bool isPartialMatch = _isPartialMatch(searchName, userName);

      if (similarity >= (similarityThreshold - 0.1) || isPartialMatch) {
        results.add({
          'relation': 'تطابق مباشر (${(similarity * 100).toStringAsFixed(1)}%)',
          'name': userName,
          'region': user['region'] ?? '',
          'agent': user['agent'] ?? '',
          'dash': user['dash'] ?? '',
          'mother': user['mother'] ?? '',
          'similarity': (similarity * 100).toStringAsFixed(1),
        });
      }
    }

    // ترتيب النتائج حسب نسبة التشابه
    results.sort((a, b) => double.parse(b['similarity'] ?? '0')
        .compareTo(double.parse(a['similarity'] ?? '0')));

    return results;
  }

  //============================================================================
  // دوال العلاقات التقليدية (للمقارنة)
  //============================================================================

  /// التطابق التام (الشخص نفسه)
  bool _checkExactMatch4(List<String> my, List<String> other) {
    if (my.length < 4 || other.length < 3) return false;
    return my[0] == other[0] && my[1] == other[1] && my[2] == other[2];
  }

  /// الأخ: (U1,U2,U3) == (O1,O2,O3) + اختلاف الاسم الأول
  bool _checkBrother4(List<String> my, List<String> other) {
    if (my.length < 4 || other.length < 3) return false;
    return (my[1] == other[0] &&
        my[2] == other[1] &&
        my[3] == other[2] &&
        my[0] != other[0]);
  }

  /// العم: (U2,U3) == (O1,O2) + اختلاف (U0 != O0) أو (U1 != O1)
  bool _checkUncle4(List<String> my, List<String> other) {
    if (my.length < 4 || other.length < 3) return false;
    return (my[2] == other[1] &&
        my[3] == other[2] &&
        (my[0] != other[0] && my[1] != other[0]));
  }

  /// الجد: (U2,U3) == (O0,O1) + اختلاف الأجزاء الأخرى
  bool _checkGrandpa4(List<String> my, List<String> other) {
    if (my.length < 4 || other.length < 3) return false;
    return (my[2] == other[0] &&
        my[3] == other[1] &&
        (my[0] != other[0] && my[1] != other[1]));
  }

  /// الأب: (U1,U2,U3) == (O0,O1,O2) + (U0 != O0)
  bool _checkFather4(List<String> my, List<String> other) {
    if (my.length < 4 || other.length < 3) return false;
    return (my[1] == other[0] &&
        my[2] == other[1] &&
        my[3] == other[2] &&
        my[0] != other[0]);
  }

  //============================================================================
  // (1) تحميل المناطق
  //============================================================================
  Future<void> _loadRegions() async {
    setState(() {
      isLoading = true;
      hasError = false;
    });

    try {
      debugPrint('🔄 Loading regions from Google Sheets...');
      final regionsUrl =
          'https://sheets.googleapis.com/v4/spreadsheets/$spreadsheetId/values/users!B2:B?key=$apiKey';

      debugPrint('📡 Regions URL: $regionsUrl');
      final response = await http.get(Uri.parse(regionsUrl));

      debugPrint('📊 Regions Response Status: ${response.statusCode}');
      debugPrint('📊 Regions Response Body: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        debugPrint('📋 Parsed data: $data');

        final values = data['values'] as List?;
        debugPrint('📋 Values from sheet: $values');

        if (values != null) {
          debugPrint('📋 Processing ${values.length} rows');
          for (int i = 0; i < values.length; i++) {
            var row = values[i];
            debugPrint('📋 Row $i: $row');
            if (row.isNotEmpty) {
              String region = row[0]?.toString() ?? '';
              debugPrint('📋 Adding region: "$region"');
              if (region.isNotEmpty) {
                uniqueRegions.add(region);
              }
            }
          }
        } else {
          debugPrint('⚠️ No values found in response');
        }

        debugPrint('✅ Loaded ${uniqueRegions.length} regions successfully');
        debugPrint('📋 All regions: ${uniqueRegions.toList()}');
        setState(() {
          filteredRegions = uniqueRegions.toList()..sort();
          isLoading = false;
        });
      } else {
        throw Exception('Failed to load regions');
      }
    } catch (e) {
      debugPrint('❌ Error loading regions: $e');
      setState(() {
        isLoading = false;
        hasError = true;
        errorMessage = 'خطأ في تحميل البيانات: $e';
      });
    }
  }

  //============================================================================
  // (2) تصفية المناطق عند البحث
  //============================================================================
  void _filterRegions() {
    final query = _regionSearchController.text.toLowerCase();
    setState(() {
      filteredRegions = uniqueRegions
          .where((region) => region.toLowerCase().contains(query))
          .toList()
        ..sort();
    });
  }

  //============================================================================
  // (3) جلب بيانات المستخدمين للمنطقة المحددة مع التصفية المباشرة
  //============================================================================
  Future<void> fetchUsersWithQuery(String region) async {
    setState(() {
      isLoading = true;
      hasError = false;
      users.clear();
      matches.clear();
    });

    try {
      debugPrint('🔄 Loading users for region: $region using Query API');

      final query =
          Uri.encodeComponent('SELECT A, B, C, D, E WHERE B = "$region"');
      final queryUrl =
          'https://docs.google.com/spreadsheets/d/$spreadsheetId/gviz/tq?tqx=out:json&tq=$query&sheet=users';

      debugPrint('📡 Query URL: $queryUrl');

      final response = await http.get(Uri.parse(queryUrl));

      debugPrint('📊 Query Response Status: ${response.statusCode}');
      debugPrint('📊 Query Response Body: ${response.body}');

      if (response.statusCode == 200) {
        String responseBody = response.body;

        if (responseBody
            .startsWith('/*O_o*/\ngoogle.visualization.Query.setResponse(')) {
          responseBody = responseBody.substring(
              '/*O_o*/\ngoogle.visualization.Query.setResponse('.length);
          responseBody = responseBody.substring(0, responseBody.length - 2);
        }

        final data = json.decode(responseBody);
        final table = data['table'];
        final rows = table['rows'] as List?;

        debugPrint(
            '📋 Found ${rows?.length ?? 0} filtered rows for region "$region"');

        if (rows != null) {
          for (int i = 0; i < rows.length; i++) {
            final row = rows[i];
            final cells = row['c'] as List?;

            if (cells != null && cells.length >= 5) {
              users.add({
                'name': cells[0]?['v']?.toString() ?? '',
                'region': cells[1]?['v']?.toString() ?? '',
                'agent': cells[2]?['v']?.toString() ?? '',
                'dash': cells[3]?['v']?.toString() ?? '',
                'mother': cells[4]?['v']?.toString() ?? '',
              });
              debugPrint('✅ Added user: ${cells[0]?['v']?.toString() ?? ""}');
            }
          }
          debugPrint(
              '✅ Loaded ${users.length} users for region "$region" using direct filtering');
        }

        setState(() => isLoading = false);
      } else {
        throw Exception('Failed to load users with query');
      }
    } catch (e) {
      debugPrint('❌ Error loading users with query: $e');
      debugPrint('📋 Falling back to regular method...');
      await _fetchUsersRegular(region);
    }
  }

  //============================================================================
  // (3.1) الطريقة العادية لجلب المستخدمين (fallback)
  //============================================================================
  Future<void> _fetchUsersRegular(String region) async {
    try {
      debugPrint('🔄 Loading users for region: $region with regular method');

      final usersUrl =
          'https://sheets.googleapis.com/v4/spreadsheets/$spreadsheetId/values/users!A2:E?key=$apiKey';

      debugPrint('📡 Users URL: $usersUrl');
      final response = await http.get(Uri.parse(usersUrl));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final values = data['values'] as List?;

        if (values != null) {
          int matchedUsers = 0;
          for (int i = 0; i < values.length; i++) {
            var row = values[i];

            if (row.isNotEmpty && row.length > 1) {
              final userRegion = row[1]?.toString() ?? '';

              if (userRegion == region) {
                matchedUsers++;
                users.add({
                  'name': row[0]?.toString() ?? '',
                  'region': userRegion,
                  'agent': row[2]?.toString() ?? '',
                  'dash': row[3]?.toString() ?? '',
                  'mother': row[4]?.toString() ?? '',
                });
              }
            }
          }
          debugPrint('✅ Found $matchedUsers users for region "$region"');
        }

        setState(() => isLoading = false);
      } else {
        throw Exception('Failed to load users');
      }
    } catch (e) {
      debugPrint('❌ Error in regular fetch: $e');
      setState(() {
        isLoading = false;
        hasError = true;
        errorMessage = 'خطأ في تحميل بيانات المستخدمين: $e';
      });
    }
  }

  //============================================================================
  // البحث المحسن عن العلاقة
  //============================================================================
  void findRelationEnhanced() {
    if (!_formKey.currentState!.validate()) return;

    final newUserName = _nameController.text.trim();
    final myParts = newUserName.split(' ');

    setState(() {
      matches.clear();
    });

    // البحث المباشر بالاسم الكامل أولاً
    if (enableSmartMatching || enablePartialMatching) {
      var directMatches = _smartFullNameSearch(newUserName);
      matches.addAll(directMatches);
    }

    // البحث عن العلاقات العائلية إذا كان الاسم رباعي
    if (myParts.length >= 4) {
      for (var user in users) {
        final otherParts = (user['name'] ?? '').split(' ');
        if (otherParts.length < 3) continue;

        final foundRelations = <String>[];

        // استخدام الدوال المحسنة أو التقليدية حسب الإعدادات
        if (enableSmartMatching) {
          // فحص العلاقات المحسنة
          if (_checkExactMatchEnhanced(myParts, otherParts)) {
            foundRelations.add('الشخص نفسه (محسن)');
          }
          if (_checkBrotherEnhanced(myParts, otherParts)) {
            foundRelations.add('أخو (محسن)');
          }
          if (_checkUncleEnhanced(myParts, otherParts)) {
            foundRelations.add('العم (محسن)');
          }
          if (_checkGrandpaEnhanced(myParts, otherParts)) {
            foundRelations.add('الجد (محسن)');
          }
          if (_checkFatherEnhanced(myParts, otherParts)) {
            foundRelations.add('الأب (محسن)');
          }
        } else {
          // فحص العلاقات التقليدية
          if (_checkExactMatch4(myParts, otherParts)) {
            foundRelations.add('الشخص نفسه');
          }
          if (_checkBrother4(myParts, otherParts)) {
            foundRelations.add('أخو');
          }
          if (_checkUncle4(myParts, otherParts)) {
            foundRelations.add('العم');
          }
          if (_checkGrandpa4(myParts, otherParts)) {
            foundRelations.add('الجد');
          }
          if (_checkFather4(myParts, otherParts)) {
            foundRelations.add('الأب');
          }
        }

        // إضافة المعلومات إن وجدت علاقة/علاقات
        if (foundRelations.isNotEmpty) {
          for (var rel in foundRelations) {
            // تجنب التكرار من البحث المباشر
            bool alreadyExists = matches.any((match) =>
                match['name'] == user['name'] &&
                match['relation']!.contains('تطابق مباشر'));

            if (!alreadyExists) {
              matches.add({
                'relation': rel,
                'name': user['name'] ?? '',
                'region': user['region'] ?? '',
                'agent': user['agent'] ?? '',
                'dash': user['dash'] ?? '',
                'mother': user['mother'] ?? '',
              });
            }
          }
        }
      }
    } else if (myParts.length < 3) {
      _showError('يُفضل إدخال اسم ثلاثي أو رباعي لجودة النتائج');
    }

    if (matches.isEmpty) {
      matches.add({
        'relation': 'لا يوجد مستخدم من الأقارب في المشروع الوطني',
        'name': '',
        'region': '',
        'agent': '',
        'dash': '',
        'mother': '',
      });
    }

    setState(() {});
  }

  //============================================================================
  // اختبار الاتصال بـ Google Sheets
  //============================================================================
  Future<void> _testGoogleSheetsConnection() async {
    setState(() {
      isLoading = true;
      hasError = false;
    });

    try {
      debugPrint('🧪 Testing Google Sheets connection...');

      final testUrl =
          'https://sheets.googleapis.com/v4/spreadsheets/$spreadsheetId/values/users!A1:E1?key=$apiKey';

      debugPrint('📡 Test URL: $testUrl');
      final response = await http.get(Uri.parse(testUrl));

      debugPrint('📊 Test Response Status: ${response.statusCode}');
      debugPrint('📊 Test Response Body: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final values = data['values'] as List?;

        if (values != null && values.isNotEmpty) {
          debugPrint('✅ Connection successful! Headers: ${values[0]}');
          _showSuccess('تم الاتصال بنجاح مع Google Sheets');
        } else {
          _showError('تم الاتصال ولكن لا توجد بيانات');
        }
      } else {
        throw Exception('HTTP ${response.statusCode}: ${response.body}');
      }

      setState(() => isLoading = false);
    } catch (e) {
      debugPrint('❌ Connection test failed: $e');
      setState(() {
        isLoading = false;
        hasError = true;
        errorMessage = 'فشل الاتصال: $e';
      });
      _showError('فشل الاتصال مع Google Sheets: $e');
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.green),
    );
  }

  //============================================================================
  // واجهة المستخدم
  //============================================================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('البحث المحسن عن المستخدمين'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: _showSettingsDialog,
            tooltip: 'إعدادات المطابقة',
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              // إعدادات المطابقة
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'إعدادات المطابقة الذكية',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: SwitchListTile(
                              title: const Text('المطابقة الذكية'),
                              subtitle: Text(
                                  'حد التشابه: ${(similarityThreshold * 100).toInt()}%'),
                              value: enableSmartMatching,
                              onChanged: (value) {
                                setState(() {
                                  enableSmartMatching = value;
                                });
                              },
                            ),
                          ),
                          Expanded(
                            child: SwitchListTile(
                              title: const Text('البحث الجزئي'),
                              value: enablePartialMatching,
                              onChanged: (value) {
                                setState(() {
                                  enablePartialMatching = value;
                                });
                              },
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // حقل إدخال الاسم
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'أدخل الاسم للبحث عن الأقارب',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.person_search),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'يرجى إدخال الاسم';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // قائمة المناطق
              if (uniqueRegions.isNotEmpty) ...[
                TextFormField(
                  controller: _regionSearchController,
                  decoration: const InputDecoration(
                    labelText: 'ابحث عن المنطقة',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.search),
                  ),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: selectedRegion,
                  decoration: const InputDecoration(
                    labelText: 'اختر المنطقة',
                    border: OutlineInputBorder(),
                  ),
                  items: filteredRegions.map((region) {
                    return DropdownMenuItem(
                      value: region,
                      child: Text(region),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setState(() {
                      selectedRegion = value;
                    });
                    if (value != null) {
                      fetchUsersWithQuery(value);
                    }
                  },
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'يرجى اختيار المنطقة';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
              ],

              // أزرار العمليات
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: isLoading ? null : findRelationEnhanced,
                      icon: const Icon(Icons.search),
                      label: const Text('البحث المحسن'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: isLoading ? null : _testGoogleSheetsConnection,
                    icon: const Icon(Icons.cloud_sync),
                    label: const Text('اختبار الاتصال'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // عرض حالة التحميل أو الأخطاء
              if (isLoading)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Row(
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(width: 16),
                        Text('جاري التحميل...'),
                      ],
                    ),
                  ),
                ),

              if (hasError && !isLoading)
                Card(
                  color: Colors.red.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      children: [
                        Icon(Icons.error, color: Colors.red),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Text(
                            errorMessage,
                            style: TextStyle(color: Colors.red.shade700),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              // عرض النتائج
              Expanded(
                child: matches.isNotEmpty
                    ? ListView.builder(
                        itemCount: matches.length,
                        itemBuilder: (context, index) {
                          final match = matches[index];
                          return Card(
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor:
                                    _getRelationColor(match['relation'] ?? ''),
                                child: Icon(
                                  _getRelationIcon(match['relation'] ?? ''),
                                  color: Colors.white,
                                ),
                              ),
                              title: Text(
                                match['relation'] ?? '',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (match['name']?.isNotEmpty ?? false)
                                    Text('الاسم: ${match['name']}'),
                                  if (match['region']?.isNotEmpty ?? false)
                                    Text('المنطقة: ${match['region']}'),
                                  if (match['agent']?.isNotEmpty ?? false)
                                    Text('الوكيل: ${match['agent']}'),
                                  if (match['dash']?.isNotEmpty ?? false)
                                    Text('الداش: ${match['dash']}'),
                                  if (match['mother']?.isNotEmpty ?? false)
                                    Text('اسم الأم: ${match['mother']}'),
                                ],
                              ),
                              trailing: match['similarity'] != null
                                  ? Chip(
                                      label: Text('${match['similarity']}%'),
                                      backgroundColor: Colors.blue.shade100,
                                    )
                                  : null,
                            ),
                          );
                        },
                      )
                    : const Center(
                        child: Text(
                          'لا توجد نتائج بعد\nاختر المنطقة وابدأ البحث',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey,
                          ),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _getRelationColor(String relation) {
    if (relation.contains('تطابق مباشر')) return Colors.green;
    if (relation.contains('الشخص نفسه')) return Colors.purple;
    if (relation.contains('أخو')) return Colors.blue;
    if (relation.contains('الأب')) return Colors.orange;
    if (relation.contains('العم')) return Colors.teal;
    if (relation.contains('الجد')) return Colors.brown;
    return Colors.grey;
  }

  IconData _getRelationIcon(String relation) {
    if (relation.contains('تطابق مباشر')) return Icons.verified;
    if (relation.contains('الشخص نفسه')) return Icons.person;
    if (relation.contains('أخو')) return Icons.people;
    if (relation.contains('الأب')) return Icons.family_restroom;
    if (relation.contains('العم') || relation.contains('الجد')) {
      return Icons.elderly;
    }
    return Icons.help;
  }

  void _showSettingsDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('إعدادات المطابقة الذكية'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SwitchListTile(
                    title: const Text('تفعيل المطابقة الذكية'),
                    subtitle: const Text('استخدام خوارزميات التشابه النصي'),
                    value: enableSmartMatching,
                    onChanged: (value) {
                      setDialogState(() {
                        enableSmartMatching = value;
                      });
                      setState(() {
                        enableSmartMatching = value;
                      });
                    },
                  ),
                  SwitchListTile(
                    title: const Text('تفعيل البحث الجزئي'),
                    subtitle: const Text('البحث في أجزاء الاسم'),
                    value: enablePartialMatching,
                    onChanged: (value) {
                      setDialogState(() {
                        enablePartialMatching = value;
                      });
                      setState(() {
                        enablePartialMatching = value;
                      });
                    },
                  ),
                  SwitchListTile(
                    title: const Text('تفعيل البحث المرن'),
                    subtitle: const Text('تجاهل الأخطاء الإملائية البسيطة'),
                    value: enableFuzzyMatching,
                    onChanged: (value) {
                      setDialogState(() {
                        enableFuzzyMatching = value;
                      });
                      setState(() {
                        enableFuzzyMatching = value;
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                  Text('حد التشابه: ${(similarityThreshold * 100).toInt()}%'),
                  Slider(
                    value: similarityThreshold,
                    min: 0.5,
                    max: 1.0,
                    divisions: 10,
                    label: '${(similarityThreshold * 100).toInt()}%',
                    onChanged: (value) {
                      setDialogState(() {
                        similarityThreshold = value;
                      });
                      setState(() {
                        similarityThreshold = value;
                      });
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('إغلاق'),
                ),
                ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    _showSuccess('تم حفظ الإعدادات');
                  },
                  child: const Text('حفظ'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
