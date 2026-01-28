/// اسم الصفحة: البحث عن المستخدمين
/// وصف الصفحة: صفحة البحث التقليدية عن المستخدمين والمشتركين
/// المؤلف: تطبيق السدارة
/// تاريخ الإنشاء: 2024
library;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:math';

class SearchUsersPage extends StatefulWidget {
  const SearchUsersPage({super.key});

  @override
  State<SearchUsersPage> createState() => _SearchUsersPageState();
}

class _SearchUsersPageState extends State<SearchUsersPage> {
  final String apiKey = 'AIzaSyDdwZK0D8uRoPSKS0axA5dQjwMCQJtF1BU';
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
  double similarityThreshold = 0.75; // حد التشابه المطلوب (75%)
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
        if (_isSmartMatch(searchPart, userPart, threshold: 0.75)) {
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
      // شيت المستخدمين - جلب المناطق من العمود الثاني
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
  Future<void> fetchUsers(String region) async {
    setState(() {
      isLoading = true;
      hasError = false;
      users.clear();
      matches.clear();
    });

    try {
      debugPrint('🔄 Loading users for region: $region with direct filtering');

      // جلب البيانات المحددة فقط - نحدد نطاق أصغر لتوفير البيانات
      final usersUrl =
          'https://sheets.googleapis.com/v4/spreadsheets/$spreadsheetId/values/users!A2:E?key=$apiKey';

      debugPrint('📡 Users URL: $usersUrl');
      debugPrint('🔍 Will filter for region: "$region"');

      final response = await http.get(Uri.parse(usersUrl));

      debugPrint('📊 Users Response Status: ${response.statusCode}');
      debugPrint('📊 Users Response Body: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final values = data['values'] as List?;

        debugPrint('📋 Found ${values?.length ?? 0} total rows in users sheet');

        if (values != null) {
          int matchedUsers = 0;
          for (int i = 0; i < values.length; i++) {
            var row = values[i];
            debugPrint('📋 User row $i: $row');

            if (row.isNotEmpty && row.length > 1) {
              final userRegion = row[1]?.toString() ?? '';

              // تطبيق التصفية هنا حيث أن Google Sheets API لا يدعم WHERE clause مباشرة
              if (userRegion == region) {
                matchedUsers++;
                users.add({
                  'name':
                      row[0]?.toString() ?? '', // العمود الأول: اسم المستخدم
                  'region': userRegion, // العمود الثاني: المنطقة
                  'agent': row[2]?.toString() ?? '', // العمود الثالث: الوكيل
                  'dash': row[3]?.toString() ?? '', // العمود الرابع: الداش
                  'mother': row[4]?.toString() ?? '', // العمود الخامس: اسم الأم
                });
                debugPrint('✅ Added user: ${row[0]?.toString() ?? ""}');
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
      debugPrint('❌ Error loading users: $e');
      setState(() {
        isLoading = false;
        hasError = true;
        errorMessage = 'خطأ في تحميل بيانات المستخدمين: $e';
      });
    }
  }

  //============================================================================
  // (3.1) جلب بيانات المستخدمين باستخدام Google Sheets Query API (التصفية المباشرة)
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

      // استخدام Google Visualization API للتصفية المباشرة
      final query =
          Uri.encodeComponent('SELECT A, B, C, D, E WHERE B = "$region"');
      final queryUrl =
          'https://docs.google.com/spreadsheets/d/$spreadsheetId/gviz/tq?tqx=out:json&tq=$query&sheet=users';

      debugPrint('📡 Query URL: $queryUrl');

      final response = await http.get(Uri.parse(queryUrl));

      debugPrint('📊 Query Response Status: ${response.statusCode}');
      debugPrint('📊 Query Response Body: ${response.body}');

      if (response.statusCode == 200) {
        // معالجة استجابة Google Visualization API
        String responseBody = response.body;

        // إزالة البادئة من الاستجابة
        if (responseBody
            .startsWith('/*O_o*/\ngoogle.visualization.Query.setResponse(')) {
          responseBody = responseBody.substring(
              '/*O_o*/\ngoogle.visualization.Query.setResponse('.length);
          responseBody =
              responseBody.substring(0, responseBody.length - 2); // إزالة ");"
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
                'name': cells[0]?['v']?.toString() ?? '', // اسم المستخدم
                'region': cells[1]?['v']?.toString() ?? '', // المنطقة
                'agent': cells[2]?['v']?.toString() ?? '', // الوكيل
                'dash': cells[3]?['v']?.toString() ?? '', // الداش
                'mother': cells[4]?['v']?.toString() ?? '', // اسم الأم
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
      // في حالة فشل Query API، استخدم الطريقة العادية
      await fetchUsers(region);
    }
  }

  //============================================================================
  // منطق العلاقات
  //============================================================================

  // التطابق التام (الشخص نفسه)
  bool _checkExactMatch4(List<String> my, List<String> other) {
    if (my.length < 4 || other.length < 3) return false;
    return my[0] == other[0] && my[1] == other[1] && my[2] == other[2];
  }

  // الأخ: (U1,U2,U3) == (O1,O2,O3) + اختلاف الاسم الأول
  bool _checkBrother4(List<String> my, List<String> other) {
    if (my.length < 4 || other.length < 3) return false;
    return (my[1] == other[0] &&
        my[2] == other[1] &&
        my[3] == other[2] &&
        my[0] != other[0]);
  }

  // العم: (U2,U3) == (O1,O2) + اختلاف (U0 != O0) أو (U1 != O1)
  bool _checkUncle4(List<String> my, List<String> other) {
    if (my.length < 4 || other.length < 3) return false;
    return (my[2] == other[1] &&
        my[3] == other[2] &&
        (my[0] != other[0] && my[1] != other[0]));
  }

  // الجد: (U2,U3) == (O0,O1) + اختلاف الأجزاء الأخرى
  bool _checkGrandpa4(List<String> my, List<String> other) {
    if (my.length < 4 || other.length < 3) return false;
    return (my[2] == other[0] &&
        my[3] == other[1] &&
        (my[0] != other[0] && my[1] != other[1]));
  }

  // الأب: (U1,U2,U3) == (O0,O1,O2) + (U0 != O0)
  bool _checkFather4(List<String> my, List<String> other) {
    if (my.length < 4 || other.length < 3) return false;
    return (my[1] == other[0] &&
        my[2] == other[1] &&
        my[3] == other[2] &&
        my[0] != other[0]);
  }

  //============================================================================
  // البحث المباشر في Google Sheets مع تحديد وجه القرابة
  //============================================================================
  Future<void> searchInSheetDirectly() async {
    if (!_formKey.currentState!.validate()) return;

    final newUserName = _nameController.text.trim();
    final myParts = newUserName.split(' ');

    // يشترط على الأقل 3 أسماء للبحث عن العلاقات
    if (myParts.length < 3) {
      _showError('يجب إدخال اسم ثلاثي أو رباعي للبحث عن العلاقات');
      return;
    }

    setState(() {
      isLoading = true;
      hasError = false;
      matches.clear();
    });

    try {
      debugPrint('🔍 بدء البحث المباشر في الشيت عن: "$newUserName"');
      debugPrint('📋 أجزاء الاسم: $myParts');

      // البحث عن التطابق المباشر أولاً
      await _searchDirectMatch(newUserName, myParts);

      // البحث عن الأقارب حسب المنطقة المحددة
      if (selectedRegion != null) {
        await _searchForRelatives(myParts, selectedRegion!);
      }

      // إذا لم نجد أي نتائج، نبحث في جميع المناطق
      if (matches.isEmpty) {
        debugPrint(
            '🔍 لم توجد نتائج في المنطقة المحددة، البحث في جميع المناطق...');
        await _searchForRelativesInAllRegions(myParts);
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

      setState(() {
        isLoading = false;
      });
    } catch (e) {
      debugPrint('❌ خطأ في البحث المباشر: $e');
      setState(() {
        isLoading = false;
        hasError = true;
        errorMessage = 'خطأ في البحث: $e';
      });
    }
  }

  //============================================================================
  // البحث عن التطابق المباشر بالاسم
  //============================================================================
  Future<void> _searchDirectMatch(
      String fullName, List<String> nameParts) async {
    try {
      debugPrint('🔍 البحث عن التطابق المباشر...');

      // البحث بالاسم الكامل أولاً
      String query = 'SELECT A, B, C, D, E WHERE A = "$fullName"';
      if (selectedRegion != null) {
        query += ' AND B = "$selectedRegion"';
      }

      await _executeQuery(query, 'الشخص نفسه (تطابق كامل)');

      // إذا لم نجد تطابق كامل، نبحث بأجزاء الاسم
      if (matches.isEmpty && enableSmartMatching) {
        await _searchWithSmartMatching(nameParts);
      }
    } catch (e) {
      debugPrint('❌ خطأ في البحث المباشر: $e');
    }
  }

  //============================================================================
  // البحث الذكي بالأجزاء
  //============================================================================
  Future<void> _searchWithSmartMatching(List<String> nameParts) async {
    try {
      debugPrint('🧠 البحث الذكي بأجزاء الاسم...');

      // البحث بأول 3 أجزاء من الاسم
      if (nameParts.length >= 3) {
        String searchPattern =
            '${nameParts[0]} ${nameParts[1]} ${nameParts[2]}';
        String query = 'SELECT A, B, C, D, E WHERE A LIKE "%$searchPattern%"';
        if (selectedRegion != null) {
          query += ' AND B = "$selectedRegion"';
        }

        List<Map<String, String>> results =
            await _executeQueryAndReturnData(query);

        // فلترة النتائج حسب نسبة التشابه 75% وما فوق
        for (var user in results) {
          String userName = user['name'] ?? '';
          if (userName.isNotEmpty) {
            double similarity =
                _calculateSimilarity(nameParts.join(' '), userName);
            if (similarity >= 0.75) {
              // تحقق من عدم وجود نفس الشخص مسبقاً
              bool alreadyExists =
                  matches.any((match) => match['name'] == userName);
              if (!alreadyExists) {
                matches.add({
                  'relation':
                      'الشخص نفسه (تطابق ذكي ${(similarity * 100).toStringAsFixed(1)}%)',
                  'name': userName,
                  'region': user['region'] ?? '',
                  'agent': user['agent'] ?? '',
                  'dash': user['dash'] ?? '',
                  'mother': user['mother'] ?? '',
                });
                debugPrint(
                    '✅ تم إضافة: $userName - تشابه ${(similarity * 100).toStringAsFixed(1)}%');
              } else {
                debugPrint('⚠️ تم تجاهل: $userName - موجود مسبقاً');
              }
            }
          }
        }
      }

      // البحث بالأجزاء المنفصلة
      for (int i = 0; i < nameParts.length && matches.length < 5; i++) {
        if (nameParts[i].length >= 3) {
          // تجاهل الأجزاء القصيرة
          String query =
              'SELECT A, B, C, D, E WHERE A LIKE "%${nameParts[i]}%" ';
          if (selectedRegion != null) {
            query += ' AND B = "$selectedRegion"';
          }

          List<Map<String, String>> results =
              await _executeQueryAndReturnData(query);

          // فلترة النتائج حسب نسبة التشابه 75% وما فوق
          for (var user in results) {
            String userName = user['name'] ?? '';
            if (userName.isNotEmpty) {
              double similarity =
                  _calculateSimilarity(nameParts.join(' '), userName);
              if (similarity >= 0.75) {
                bool alreadyExists =
                    matches.any((match) => match['name'] == userName);
                if (!alreadyExists) {
                  matches.add({
                    'relation':
                        'تطابق جزئي (${nameParts[i]}) - ${(similarity * 100).toStringAsFixed(1)}%',
                    'name': userName,
                    'region': user['region'] ?? '',
                    'agent': user['agent'] ?? '',
                    'dash': user['dash'] ?? '',
                    'mother': user['mother'] ?? '',
                  });
                  debugPrint(
                      '✅ تم إضافة: $userName - تطابق جزئي ${(similarity * 100).toStringAsFixed(1)}%');
                }
              }
            }
          }
        }
      }
    } catch (e) {
      debugPrint('❌ خطأ في البحث الذكي: $e');
    }
  }

  //============================================================================
  // البحث عن الأقارب في منطقة محددة
  //============================================================================
  Future<void> _searchForRelatives(List<String> myParts, String region) async {
    try {
      debugPrint('👨‍👩‍👧‍👦 البحث عن الأقارب في منطقة: $region');

      // جلب جميع المستخدمين في المنطقة للمقارنة
      String query = 'SELECT A, B, C, D, E WHERE B = "$region"';
      List<Map<String, String>> regionUsers =
          await _executeQueryAndReturnData(query);

      debugPrint('📋 تم جلب ${regionUsers.length} مستخدم من المنطقة للمقارنة');

      // فحص العلاقات مع كل مستخدم
      for (var user in regionUsers) {
        String userName = user['name'] ?? '';
        if (userName.isEmpty) continue;

        List<String> otherParts = userName.split(' ');
        if (otherParts.length < 3) continue;

        List<String> foundRelations =
            _determineRelationships(myParts, otherParts);

        for (String relation in foundRelations) {
          // تجنب إضافة نفس الشخص مرتين (فحص بالاسم فقط)
          bool alreadyExists =
              matches.any((match) => match['name'] == userName);

          if (!alreadyExists) {
            matches.add({
              'relation': relation,
              'name': userName,
              'region': user['region'] ?? '',
              'agent': user['agent'] ?? '',
              'dash': user['dash'] ?? '',
              'mother': user['mother'] ?? '',
            });
            debugPrint('✅ تم العثور على: $userName - $relation');
          } else {
            debugPrint('⚠️ تم تجاهل: $userName - $relation (موجود مسبقاً)');
          }
        }
      }
    } catch (e) {
      debugPrint('❌ خطأ في البحث عن الأقارب: $e');
    }
  }

  //============================================================================
  // البحث عن الأقارب في جميع المناطق
  //============================================================================
  Future<void> _searchForRelativesInAllRegions(List<String> myParts) async {
    try {
      debugPrint('🌍 البحث عن الأقارب في جميع المناطق...');

      // جلب عينة من البيانات للمقارنة (أول 1000 صف مثلاً)
      String query = 'SELECT A, B, C, D, E LIMIT 1000';
      List<Map<String, String>> allUsers =
          await _executeQueryAndReturnData(query);

      debugPrint(
          '📋 تم جلب ${allUsers.length} مستخدم من جميع المناطق للمقارنة');

      // فحص العلاقات مع كل مستخدم
      for (var user in allUsers) {
        String userName = user['name'] ?? '';
        if (userName.isEmpty) continue;

        List<String> otherParts = userName.split(' ');
        if (otherParts.length < 3) continue;

        List<String> foundRelations =
            _determineRelationships(myParts, otherParts);

        for (String relation in foundRelations) {
          bool alreadyExists =
              matches.any((match) => match['name'] == userName);

          if (!alreadyExists) {
            matches.add({
              'relation': relation,
              'name': userName,
              'region': user['region'] ?? '',
              'agent': user['agent'] ?? '',
              'dash': user['dash'] ?? '',
              'mother': user['mother'] ?? '',
            });
            debugPrint('✅ تم العثور على: $userName - $relation');
          } else {
            debugPrint('⚠️ تم تجاهل: $userName - $relation (موجود مسبقاً)');
          }
        }

        // توقف عند العثور على 20 نتيجة لتجنب البطء
        if (matches.length >= 20) break;
      }
    } catch (e) {
      debugPrint('❌ خطأ في البحث في جميع المناطق: $e');
    }
  }

  //============================================================================
  // تحديد نوع العلاقة بين اسمين
  //============================================================================
  List<String> _determineRelationships(
      List<String> myParts, List<String> otherParts) {
    List<String> relations = [];

    try {
      // استخدام الدوال المحسنة إذا كانت مفعلة
      if (enableSmartMatching) {
        if (_checkExactMatchEnhanced(myParts, otherParts)) {
          relations.add('الشخص نفسه (محسن)');
        }
        if (myParts.length >= 4 && _checkBrotherEnhanced(myParts, otherParts)) {
          relations.add('أخو (محسن)');
        }
        if (myParts.length >= 4 && _checkUncleEnhanced(myParts, otherParts)) {
          relations.add('العم (محسن)');
        }
        if (myParts.length >= 4 && _checkGrandpaEnhanced(myParts, otherParts)) {
          relations.add('الجد (محسن)');
        }
        if (myParts.length >= 4 && _checkFatherEnhanced(myParts, otherParts)) {
          relations.add('الأب (محسن)');
        }
      } else {
        // استخدام الدوال التقليدية
        if (myParts.length >= 4 && _checkExactMatch4(myParts, otherParts)) {
          relations.add('الشخص نفسه');
        }
        if (myParts.length >= 4 && _checkBrother4(myParts, otherParts)) {
          relations.add('أخو');
        }
        if (myParts.length >= 4 && _checkUncle4(myParts, otherParts)) {
          relations.add('العم');
        }
        if (myParts.length >= 4 && _checkGrandpa4(myParts, otherParts)) {
          relations.add('الجد');
        }
        if (myParts.length >= 4 && _checkFather4(myParts, otherParts)) {
          relations.add('الأب');
        }
      }

      // إذا لم توجد علاقة محددة لكن هناك تشابه، أضف كتطابق جزئي
      if (relations.isEmpty && enableSmartMatching) {
        String myName = myParts.join(' ');
        String otherName = otherParts.join(' ');

        double similarity = _calculateSimilarity(myName, otherName);

        // إظهار النتائج التي تشابهها 75% أو أكثر فقط
        if (similarity >= 0.75) {
          relations.add(
              'تشابه في الاسم (${(similarity * 100).toStringAsFixed(1)}%)');
        }
      }
    } catch (e) {
      debugPrint('❌ خطأ في تحديد العلاقة: $e');
    }

    return relations;
  }

  //============================================================================
  // تنفيذ استعلام Google Sheets
  //============================================================================
  Future<void> _executeQuery(String query, String relationType) async {
    try {
      debugPrint('📊 تنفيذ الاستعلام: $query');

      List<Map<String, String>> results =
          await _executeQueryAndReturnData(query);

      for (var user in results) {
        String userName = user['name'] ?? '';
        // تحقق من عدم وجود نفس الشخص مسبقاً
        bool alreadyExists = matches.any((match) => match['name'] == userName);

        if (!alreadyExists) {
          matches.add({
            'relation': relationType,
            'name': userName,
            'region': user['region'] ?? '',
            'agent': user['agent'] ?? '',
            'dash': user['dash'] ?? '',
            'mother': user['mother'] ?? '',
          });
          debugPrint('✅ تم إضافة: $userName - $relationType');
        } else {
          debugPrint('⚠️ تم تجاهل: $userName - $relationType (موجود مسبقاً)');
        }
      }
    } catch (e) {
      debugPrint('❌ خطأ في تنفيذ الاستعلام: $e');
    }
  }

  //============================================================================
  // تنفيذ استعلام وإرجاع البيانات
  //============================================================================
  Future<List<Map<String, String>>> _executeQueryAndReturnData(
      String query) async {
    List<Map<String, String>> results = [];

    try {
      final encodedQuery = Uri.encodeComponent(query);
      final queryUrl =
          'https://docs.google.com/spreadsheets/d/$spreadsheetId/gviz/tq?tqx=out:json&tq=$encodedQuery&sheet=users';

      debugPrint('📡 Query URL: $queryUrl');

      final response = await http.get(Uri.parse(queryUrl));

      if (response.statusCode == 200) {
        String responseBody = response.body;

        // إزالة البادئة من الاستجابة
        if (responseBody
            .startsWith('/*O_o*/\ngoogle.visualization.Query.setResponse(')) {
          responseBody = responseBody.substring(
              '/*O_o*/\ngoogle.visualization.Query.setResponse('.length);
          responseBody = responseBody.substring(0, responseBody.length - 2);
        }

        final data = json.decode(responseBody);

        // التحقق من وجود أخطاء في الاستعلام
        if (data['status'] == 'error') {
          debugPrint('❌ خطأ في الاستعلام: ${data['errors']}');
          return results;
        }

        final table = data['table'];
        final rows = table['rows'] as List?;

        debugPrint('📋 تم العثور على ${rows?.length ?? 0} نتيجة');

        if (rows != null) {
          for (var row in rows) {
            final cells = row['c'] as List?;
            if (cells != null && cells.isNotEmpty) {
              results.add({
                'name': cells[0]?['v']?.toString() ?? '',
                'region':
                    cells.length > 1 ? (cells[1]?['v']?.toString() ?? '') : '',
                'agent':
                    cells.length > 2 ? (cells[2]?['v']?.toString() ?? '') : '',
                'dash':
                    cells.length > 3 ? (cells[3]?['v']?.toString() ?? '') : '',
                'mother':
                    cells.length > 4 ? (cells[4]?['v']?.toString() ?? '') : '',
              });
            }
          }
        }
      } else {
        debugPrint('❌ فشل الاستعلام - Status: ${response.statusCode}');
        debugPrint('❌ Response: ${response.body}');
      }
    } catch (e) {
      debugPrint('❌ خطأ في تنفيذ الاستعلام: $e');
    }

    return results;
  }

  //============================================================================
  // عرض إعدادات البحث
  //============================================================================
  void _showSearchSettings() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.settings, color: Colors.blue),
                  SizedBox(width: 8),
                  Text('إعدادات البحث'),
                ],
              ),
              content: SizedBox(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Card(
                      color: Colors.blue.shade50,
                      child: Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SwitchListTile(
                              title: const Text('المطابقة الذكية'),
                              subtitle: Text(
                                  'دعم الأخطاء الإملائية - حد التشابه: ${(similarityThreshold * 100).toInt()}% (يُظهر النتائج 75% وما فوق)'),
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
                              title: const Text('البحث الجزئي'),
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
                              title: const Text('البحث المرن'),
                              subtitle: const Text(
                                  'السماح بالأخطاء الإملائية الطفيفة'),
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
                            const Divider(),
                            ListTile(
                              leading: const Icon(Icons.info_outline,
                                  color: Colors.blue),
                              title: const Text('معلومة مهمة'),
                              subtitle: const Text(
                                'يتم عرض النتائج بتشابه 75% وما فوق فقط لضمان جودة النتائج',
                                style: TextStyle(fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('إغلاق'),
                ),
                ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('تم حفظ الإعدادات'),
                        backgroundColor: Colors.green,
                        duration: Duration(seconds: 2),
                      ),
                    );
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

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  //============================================================================
  // (4) اختبار الاتصال بـ Google Sheets
  //============================================================================
  Future<void> testGoogleSheetsConnection() async {
    try {
      debugPrint('🔍 Testing connection to Google Sheets...');

      // اختبار الاتصال الأساسي
      final testUrl =
          'https://sheets.googleapis.com/v4/spreadsheets/$spreadsheetId?key=$apiKey';

      final response = await http.get(Uri.parse(testUrl));

      if (response.statusCode == 200) {
        debugPrint('✅ Basic connection successful!');

        // اختبار جلب المناطق
        final regionsUrl =
            'https://sheets.googleapis.com/v4/spreadsheets/$spreadsheetId/values/users!B2:B?key=$apiKey';

        final regionsResponse = await http.get(Uri.parse(regionsUrl));
        debugPrint('📊 Regions test - Status: ${regionsResponse.statusCode}');
        debugPrint('📊 Regions test - Body: ${regionsResponse.body}');

        // اختبار جلب المستخدمين
        final usersUrl =
            'https://sheets.googleapis.com/v4/spreadsheets/$spreadsheetId/values/users!A2:Z?key=$apiKey';

        final usersResponse = await http.get(Uri.parse(usersUrl));
        debugPrint('📊 Users test - Status: ${usersResponse.statusCode}');
        debugPrint('📊 Users test - Body: ${usersResponse.body}');

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'الاتصال ناجح! المناطق: ${regionsResponse.statusCode}, المستخدمين: ${usersResponse.statusCode}'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        debugPrint('❌ Connection failed. Status code: ${response.statusCode}');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'فشل الاتصال بـ Google Sheets. الكود: ${response.statusCode}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      debugPrint('❌ Error testing connection: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('خطأ أثناء اختبار الاتصال: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(' البحث عن المستخدمين '),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'إعدادات البحث',
            onPressed: _showSearchSettings,
          ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Form(
                key: _formKey,
                child: ListView(
                  children: [
                    if (hasError)
                      Card(
                        color: Colors.red[100],
                        child: Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Text(
                            errorMessage,
                            style: const TextStyle(color: Colors.red),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                    _buildRegionDropdown(),
                    const SizedBox(height: 16),
                    _buildNameField(),
                    const SizedBox(height: 16),
                    _buildMotherNameField(),
                    const SizedBox(height: 24),
                    _buildSearchButton(),
                    const SizedBox(height: 24),
                    if (matches.isNotEmpty) _buildMatchesList(),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildRegionDropdown() {
    return DropdownButtonFormField<String>(
      decoration: const InputDecoration(
        labelText: 'اختر المنطقة',
        border: OutlineInputBorder(),
      ),
      initialValue: selectedRegion,
      items: filteredRegions.map((region) {
        return DropdownMenuItem(
          value: region,
          child: Text(region),
        );
      }).toList(),
      validator: (value) {
        if (value == null || value.isEmpty) {
          return 'الرجاء اختيار المنطقة';
        }
        return null;
      },
      onChanged: (value) {
        setState(() => selectedRegion = value);
        if (value != null) {
          fetchUsersWithQuery(value); // استخدام التصفية المباشرة
        }
      },
    );
  }

  Widget _buildNameField() {
    return TextFormField(
      controller: _nameController,
      decoration: const InputDecoration(
        labelText: 'اسم المستخدم (رباعي)',
        border: OutlineInputBorder(),
      ),
      validator: (value) {
        if (value == null || value.isEmpty) {
          return 'الرجاء إدخال الاسم الرباعي';
        }
        final parts = value.split(' ');
        if (parts.length < 4) {
          return 'يجب إدخال 4 أسماء على الأقل.';
        }
        return null;
      },
    );
  }

  Widget _buildMotherNameField() {
    return TextFormField(
      controller: _motherNameController,
      decoration: const InputDecoration(
        labelText: 'اسم الأم',
        border: OutlineInputBorder(),
      ),
      validator: (value) {
        if (value == null || value.isEmpty) {
          return 'الرجاء إدخال اسم الأم';
        }
        return null;
      },
    );
  }

  Widget _buildSearchButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: isLoading ? null : searchInSheetDirectly,
        icon: const Icon(Icons.search),
        label: const Text('بحث مباشر في الشيت'),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.green,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
        ),
      ),
    );
  }

  Widget _buildMatchesList() {
    if (matches.length == 1 &&
        (matches[0]['relation'] ?? '').contains('لا يوجد مستخدم')) {
      return Card(
        color: Colors.blue[100],
        elevation: 2,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              const Icon(Icons.info_outline, size: 48, color: Colors.blue),
              const SizedBox(height: 8),
              Text(
                matches[0]['relation']!,
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                'جرب:\n• تغيير المنطقة\n• استخدام المطابقة الذكية\n• تقليل عدد أحرف الاسم',
                style: TextStyle(fontSize: 12, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // معلومات البحث
        Card(
          color: Colors.green.shade50,
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.check_circle, color: Colors.green),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'تم العثور على ${matches.length} نتيجة من البحث المباشر في الشيت',
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                const Text(
                  '📊 يتم عرض النتائج بتشابه 75% وما فوق فقط لضمان الجودة',
                  style: TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),

        // النتائج
        ...matches.map((match) {
          final relation = match['relation'] ?? '';
          final name = match['name'] ?? '';
          final region = match['region'] ?? '';
          final agent = match['agent'] ?? '';
          final dash = match['dash'] ?? '';
          final mother = match['mother'] ?? '';

          return Card(
            color: _getRelationCardColor(relation),
            margin: const EdgeInsets.only(bottom: 8),
            elevation: 2,
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: _getRelationColor(relation),
                child: Icon(
                  _getRelationIcon(relation),
                  color: Colors.white,
                  size: 20,
                ),
              ),
              title: Text(
                relation,
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (name.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      'الاسم: $name',
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 14),
                    ),
                  ],
                  if (region.isNotEmpty) Text('المنطقة: $region'),
                  if (agent.isNotEmpty) Text('الوكيل: $agent'),
                  if (dash.isNotEmpty) Text('الداش: $dash'),
                  if (mother.isNotEmpty) Text('اسم الأم: $mother'),
                  // إضافة مؤشر بصري لنسبة التشابه
                  if (relation.contains('%')) ...[
                    const SizedBox(height: 4),
                    _buildSimilarityIndicator(relation),
                  ],
                ],
              ),
              trailing: relation.contains('%')
                  ? Chip(
                      label: Text(
                        relation.substring(
                            relation.indexOf('(') + 1, relation.indexOf(')')),
                        style: const TextStyle(fontSize: 12),
                      ),
                      backgroundColor: Colors.blue.shade100,
                    )
                  : null,
            ),
          );
        }),
      ],
    );
  }

  /// بناء مؤشر بصري لنسبة التشابه
  Widget _buildSimilarityIndicator(String relation) {
    // استخراج النسبة المئوية من النص
    RegExp regExp = RegExp(r'(\d+\.?\d*)%');
    Match? match = regExp.firstMatch(relation);

    if (match == null) return const SizedBox.shrink();

    double percentage = double.tryParse(match.group(1) ?? '0') ?? 0;

    // تحديد اللون حسب النسبة
    Color indicatorColor;
    String qualityText;

    if (percentage >= 95) {
      indicatorColor = Colors.green;
      qualityText = 'ممتاز';
    } else if (percentage >= 85) {
      indicatorColor = Colors.lightGreen;
      qualityText = 'جيد جداً';
    } else if (percentage >= 75) {
      indicatorColor = Colors.orange;
      qualityText = 'جيد';
    } else {
      indicatorColor = Colors.red;
      qualityText = 'ضعيف';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: indicatorColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: indicatorColor.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.analytics,
            size: 14,
            color: indicatorColor,
          ),
          const SizedBox(width: 4),
          Text(
            'تشابه ${percentage.toStringAsFixed(1)}% - $qualityText',
            style: TextStyle(
              fontSize: 11,
              color: indicatorColor,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            width: 60,
            height: 4,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(2),
              color: Colors.grey.shade300,
            ),
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: percentage / 100,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(2),
                  color: indicatorColor,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _getRelationCardColor(String relation) {
    if (relation.contains('تطابق مباشر') || relation.contains('الشخص نفسه')) {
      return Colors.green.shade50;
    }
    if (relation.contains('أخو')) return Colors.blue.shade50;
    if (relation.contains('الأب')) return Colors.orange.shade50;
    if (relation.contains('العم')) return Colors.purple.shade50;
    if (relation.contains('الجد')) return Colors.brown.shade50;
    if (relation.contains('تشابه')) return Colors.amber.shade50;
    return Colors.grey.shade50;
  }

  Color _getRelationColor(String relation) {
    if (relation.contains('تطابق مباشر') || relation.contains('الشخص نفسه')) {
      return Colors.green;
    }
    if (relation.contains('أخو')) return Colors.blue;
    if (relation.contains('الأب')) return Colors.orange;
    if (relation.contains('العم')) return Colors.purple;
    if (relation.contains('الجد')) return Colors.brown;
    if (relation.contains('تشابه')) return Colors.amber;
    return Colors.grey;
  }

  IconData _getRelationIcon(String relation) {
    if (relation.contains('تطابق مباشر') || relation.contains('الشخص نفسه')) {
      return Icons.person;
    }
    if (relation.contains('أخو')) return Icons.people;
    if (relation.contains('الأب')) return Icons.family_restroom;
    if (relation.contains('العم') || relation.contains('الجد')) {
      return Icons.elderly;
    }
    if (relation.contains('تشابه')) return Icons.auto_awesome;
    return Icons.help;
  }
}
