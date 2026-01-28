import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:googleapis/sheets/v4.dart' as sheets;
import 'package:googleapis_auth/auth_io.dart';
import '../models/task.dart';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

class AddTaskDialog extends StatefulWidget {
  final String currentUsername;
  final String currentUserRole;
  final String currentUserDepartment;
  final Function(Task) onTaskAdded;
  // قيم مبدئية اختيارية لبيانات العميل
  final String? initialCustomerName;
  final String? initialCustomerPhone;
  final String? initialCustomerLocation;
  final String? initialFBG; // FBG مبدئي
  final String? initialFAT; // FAT مبدئي
  final String? initialNotes; // ملاحظات مبدئية (مثال: حالة الاشتراك، الجهاز...)
  final String? initialTaskType; // نوع المهمة المبدئي

  const AddTaskDialog({
    super.key,
    required this.currentUsername,
    required this.currentUserRole,
    required this.currentUserDepartment,
    required this.onTaskAdded,
    this.initialCustomerName,
    this.initialCustomerPhone,
    this.initialCustomerLocation,
    this.initialFBG,
    this.initialFAT,
    this.initialNotes,
    this.initialTaskType,
  });

  @override
  State<AddTaskDialog> createState() => _AddTaskDialogState();
}

class _AddTaskDialogState extends State<AddTaskDialog> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _fbgController = TextEditingController();
  final _fatController = TextEditingController();
  final _locationController = TextEditingController();
  final _notesController = TextEditingController();
  final _summaryController = TextEditingController();
  final _subscriptionAmountController =
      TextEditingController(); // مبلغ الاشتراك

  String _selectedDepartment = ''; // بدء فارغ
  String _selectedLeader = ''; // بدء فارغ
  String _selectedTechnician = ''; // بدء فارغ
  String _selectedPriority = 'متوسط'; // الحالة الافتراضية للأولوية الآن 'متوسط'
  String _selectedTaskType = ''; // نوع المهمة المختار من ALKSM
  String _selectedServiceType = ''; // نوع الخدمة (35, 50, 75, 150)
  String _selectedSubscriptionDuration = ''; // مدة الالتزام
  final String _defaultStatus = 'مفتوحة'; // حالة المهمة الافتراضية
  bool _isLoading = false;
  String? _errorMessage;

  final List<String> _priorities = ['منخفض', 'متوسط', 'عالي', 'عاجل'];
  final List<String> _serviceTypes = ['35', '50', '75', '150']; // أنواع الخدمة
  final List<String> _subscriptionDurations = [
    'شهر',
    'شهرين',
    'ثلاث أشهر',
    '6 أشهر',
    'سنة'
  ]; // مدد الالتزام
  List<String> _departments = [];
  List<String> _leaders = [];
  List<String> _technicians = [];
  List<String> _fbgOptions = []; // قائمة FBG من Sheet1
  Map<String, String> _userPhones = {}; // خريطة أسماء المستخدمين وأرقام هواتفهم
  Map<String, List<String>> _departmentTasks =
      {}; // خريطة الأقسام ومهامها من ALKSM

  sheets.SheetsApi? _sheetsApi;
  AuthClient? _client;
  final String spreadsheetId = '1MGY8UhtHaUiRaUKbohEi3a74jgEh7NeOuTEHBQ83KZc';

  // إضافة متغير لتتبع رقم الهاتف المحدد
  String _currentSelectedPhone = '';

  // دالة لإنشاء ID بسيط متتالي
  Future<String> _generateSimpleTaskId() async {
    try {
      // جلب آخر ID من Google Sheets لتحديد الرقم التالي
      const possibleTaskRanges = [
        'tasks!A:A',
        'المهام!A:A',
        'Tasks!A:A',
        'مهام!A:A',
        'Sheet4!A:A'
      ];

      int lastId = 0;

      for (String range in possibleTaskRanges) {
        try {
          final response =
              await _sheetsApi!.spreadsheets.values.get(spreadsheetId, range);
          if (response.values != null && response.values!.isNotEmpty) {
            // البحث عن أكبر رقم ID موجود
            for (var row in response.values!) {
              if (row.isNotEmpty && row[0] != null) {
                final cellValue = row[0].toString().trim();
                // تحقق من أن القيمة رقم صحيح
                final id = int.tryParse(cellValue);
                if (id != null && id > lastId) {
                  lastId = id;
                }
              }
            }
            break;
          }
        } catch (e) {
          print('❌ فشل في جلب IDs من $range: $e');
          continue;
        }
      }

      // الرقم التالي
      final nextId = lastId + 1;
      print('✅ تم إنشاء ID جديد: $nextId');
      return nextId.toString();
    } catch (e) {
      print('❌ خطأ في إنشاء ID: $e');
      // في حالة الخطأ، استخدم timestamp كبديل
      return DateTime.now().millisecondsSinceEpoch.toString();
    }
  }

  @override
  void initState() {
    super.initState();

    // تعيين القيم الافتراضية
    _selectedDepartment = 'الصيانة'; // القسم الافتراضي
    _selectedLeader = 'رسول'; // القائد الافتراضي
    _selectedTechnician =
        widget.currentUsername; // الفني الافتراضي هو المستخدم الحالي

    // تعبئة الحقول المبدئية في حال تم تمريرها
    if (widget.initialCustomerName != null &&
        widget.initialCustomerName!.isNotEmpty) {
      _usernameController.text = widget.initialCustomerName!;
    }
    if (widget.initialCustomerPhone != null &&
        widget.initialCustomerPhone!.isNotEmpty) {
      _phoneController.text = widget.initialCustomerPhone!;
    }
    if (widget.initialCustomerLocation != null &&
        widget.initialCustomerLocation!.isNotEmpty) {
      _locationController.text = widget.initialCustomerLocation!;
    }
    if (widget.initialFBG != null && widget.initialFBG!.isNotEmpty) {
      _fbgController.text = widget.initialFBG!;
    }
    if (widget.initialFAT != null && widget.initialFAT!.isNotEmpty) {
      _fatController.text = widget.initialFAT!;
    }
    if (widget.initialNotes != null && widget.initialNotes!.isNotEmpty) {
      _notesController.text = widget.initialNotes!;
    }
    if (widget.initialTaskType != null && widget.initialTaskType!.isNotEmpty) {
      _selectedTaskType = widget.initialTaskType!;
      // إذا كان نوع المهمة شراء اشتراك، تحقق من تعيين الفني الحالي تلقائياً
      _checkAndSetCurrentTechnicianForSubscription();
    }

    _initializeSheetsAPI();

    // تحديث رقم هاتف الفني المُعيَّن مسبقاً بعد تحميل البيانات
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _selectedTechnician.isNotEmpty) {
        _updateSelectedUserPhone();
      }
      // اختبار رقم رسول
      _testRasoulPhoneDebug();
    });
  }

  // دالة حفظ رقم رسول سريعاً (للتطوير)
  Future<void> _showQuickRasoulPhoneDialog() async {
    final controller = TextEditingController();

    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('حفظ رقم رسول'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('أدخل رقم هاتف رسول:'),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                hintText: '07801234567',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.phone,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () async {
              final phone = controller.text.trim();
              if (phone.isNotEmpty) {
                final prefs = await SharedPreferences.getInstance();
                await prefs.setString('rasoul_phone_number', phone);
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('✅ تم حفظ رقم رسول: $phone'),
                    backgroundColor: Colors.green,
                  ),
                );
              }
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
  }

  // دالة اختبار رقم رسول في الإعدادات (للتطوير)
  Future<void> _testRasoulPhoneDebug() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final rasoulPhone = prefs.getString('rasoul_phone_number');
      print('🔍 Debug: فحص رقم رسول في الإعدادات: "$rasoulPhone"');
      if (rasoulPhone == null || rasoulPhone.trim().isEmpty) {
        print('⚠️ Debug: رقم رسول غير موجود أو فارغ!');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('⚠️ رقم رسول غير موجود في الإعدادات!'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 3),
            ),
          );
        }
      } else {
        print('✅ Debug: رقم رسول موجود: $rasoulPhone');
      }
    } catch (e) {
      print('❌ Debug: خطأ في فحص رقم رسول: $e');
    }
  }

  Future<void> _initializeSheetsAPI() async {
    if (!mounted) return;

    if (mounted) {
      // فحص mounted قبل تحديث الحالة
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    try {
      final jsonString =
          await rootBundle.loadString('assets/service_account.json');
      final accountCredentials =
          ServiceAccountCredentials.fromJson(jsonDecode(jsonString));
      final scopes = [sheets.SheetsApi.spreadsheetsScope];
      _client = await clientViaServiceAccount(accountCredentials, scopes);
      _sheetsApi = sheets.SheetsApi(_client!);

      await _fetchAllData();
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'خطأ أثناء تهيئة Google Sheets API: ${e.toString()}';
          _isLoading = false;
        });
        _showErrorMessage(_errorMessage!);
      }
    }
  }

  Future<void> _fetchAllData() async {
    if (_sheetsApi == null || !mounted) return;

    try {
      await Future.wait([
        _fetchDepartments(),
        _fetchUsers(),
        _fetchFBGOptions(), // جلب خيارات FBG من Sheet1
        _fetchDepartmentTasks(), // جلب مهام الأقسام من ALKSM
      ]);

      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'خطأ في جلب البيانات: ${e.toString()}';
          _isLoading = false;
        });
        _showErrorMessage(_errorMessage!);
      }
    }
  }

  Future<void> _fetchDepartments() async {
    if (_sheetsApi == null) return;

    try {
      // جلب الأقسام من صفحة ALKSM بدلاً من صفحة المستخدمين
      const possibleALKSMRanges = [
        'ALKSM!A2:K', // النطاق الرئيسي من صفحة ALKSM
        'ALKSM!A1:K', // في حالة كان الصف الأول يحتوي على بيانات
        'الاقسام!A2:K', // اسم ورقة بديل باللغة العربية
        'اقسام!A2:K', // بدون ال التعريف
        'Departments!A2:K', // اسم ورقة بالإنجليزية
        'Sheet3!A2:K' // احتياطي
      ];

      sheets.ValueRange? response;

      for (String range in possibleALKSMRanges) {
        try {
          response =
              await _sheetsApi!.spreadsheets.values.get(spreadsheetId, range);
          if (response.values != null && response.values!.isNotEmpty) {
            print('✅ تم جلب بيانات الأقسام من ALKSM من $range');
            break;
          }
        } catch (e) {
          print('❌ فشل في جلب البيانات من $range: $e');
          continue;
        }
      }

      if (response != null &&
          response.values != null &&
          response.values!.isNotEmpty &&
          mounted) {
        // استخراج الأقسام من العمود الأول في ALKSM
        Set<String> departmentsSet = {};

        for (var row in response.values!) {
          if (row.isNotEmpty) {
            final department = row[0]?.toString().trim() ?? '';

            // تخطي الصفوف الفارغة أو التي تحتوي على عناوين
            if (department.isNotEmpty &&
                !department.toLowerCase().contains('اقسام') &&
                !department.toLowerCase().contains('departments') &&
                !department.toLowerCase().contains('المهمه')) {
              departmentsSet.add(department);
            }
          }
        }

        final departments = departmentsSet.toList();

        // التأكد من وجود قسم "الصيانة" الافتراضي
        if (!departments.contains('الصيانة')) {
          departments.insert(0, 'الصيانة');
          print('➕ تم إضافة القسم الافتراضي: الصيانة');
        }

        print('تم جلب ${departments.length} أقسام من ALKSM: $departments');

        setState(() {
          _departments = departments;
          // الاحتفاظ بالقسم الافتراضي المُعيَّن مسبقاً
          if (_selectedDepartment.isEmpty) {
            _selectedDepartment = 'الصيانة';
          }
        });
      } else {
        // في حالة فشل جلب الأقسام من ALKSM، استخدم قيم افتراضية
        print('فشل جلب الأقسام من ALKSM، استخدام قيم افتراضية');
        setState(() {
          _departments = [
            'الصيانة', // القسم الافتراضي أولاً
            'الحسابات',
            'الفنيين',
            'الوكلاء',
            'الاتصالات',
            'اللحام'
          ];
          // الاحتفاظ بالقسم الافتراضي
          if (_selectedDepartment.isEmpty) {
            _selectedDepartment = 'الصيانة';
          }
        });
      }
    } catch (e) {
      print('خطأ في جلب الأقسام من ALKSM: $e');
      // استخدام قيم افتراضية في حالة الخطأ
      if (mounted) {
        setState(() {
          _departments = [
            'الصيانة', // القسم الافتراضي أولاً
            'الحسابات',
            'الفنيين',
            'الوكلاء',
            'الاتصالات',
            'اللحام'
          ];
          // الاحتفاظ بالقسم الافتراضي
          if (_selectedDepartment.isEmpty) {
            _selectedDepartment = 'الصيانة';
          }
        });
      }
      rethrow;
    }
  }

  Future<void> _fetchUsers() async {
    if (_sheetsApi == null) return;

    try {
      // جلب البيانات من صفحة المستخدمين مع التأكد من النطاق الصحيح
      const possibleUsersRanges = [
        'المستخدمين!A2:H', // المحاولة الأولى مع النطاق الكامل
        'users!A2:H',
        'Users!A2:H',
        'مستخدمين!A2:H',
        'Sheet2!A2:H'
      ];

      sheets.ValueRange? response;

      for (String range in possibleUsersRanges) {
        try {
          response =
              await _sheetsApi!.spreadsheets.values.get(spreadsheetId, range);
          print('تم جلب بيانات المستخدمين من $range');
          break;
        } catch (e) {
          print('فشل في جلب المستخدمين من $range: $e');
          continue;
        }
      }

      List<String> technicians = [];
      List<String> leaders = [];

      if (response != null &&
          response.values != null &&
          response.values!.isNotEmpty) {
        print('تم جلب ${response.values!.length} صف من البيانات');

        // استخدام Set لتجنب التكرار
        Set<String> techniciansSet = {};
        Set<String> leadersSet = {};
        Map<String, String> userPhones = {};

        for (var row in response.values!) {
          // التأكد من وجود البيانات الأساسية (اسم المستخدم، الصلاحيات، القسم)
          if (row.length >= 4) {
            final username = row[0]?.toString().trim() ?? '';
            // تم إزالة المتغيرات غير المستخدمة
            final role = row[2]?.toString().trim() ?? ''; // الصلاحيات
            final department = row[3]?.toString().trim() ?? ''; // القسم
            final phone = row.length > 7
                ? row[7]?.toString().trim() ?? ''
                : ''; // رقم الهاتف

            print(
                'معالجة المستخدم: $username، الدور: $role، القسم: $department، الهاتف: $phone');

            // حفظ رقم الهاتف للمستخدم (تجنب التكرار)
            if (username.isNotEmpty && phone.isNotEmpty) {
              userPhones[username] = phone;
            }

            // فلترة المستخدمين حسب القسم المحدد فقط مع تجنب التكرار
            if (username.isNotEmpty && department == _selectedDepartment) {
              if (role == 'فني') {
                techniciansSet.add(username);
                print('✅ تم إضافة فني: $username للقسم: $department');
              } else if (role == 'ليدر') {
                leadersSet.add(username);
                print('✅ تم إضافة ليدر: $username للقسم: $department');
              }
            }
          }
        }

        // تحويل Set إلى List مع ضمان عدم وجود تكرار وترتيب النتائج
        technicians = techniciansSet.toList()..sort();
        leaders = leadersSet.toList()..sort();

        // حفظ أرقام الهواتف
        _userPhones = userPhones;
        print('تم حفظ ${userPhones.length} رقم هاتف للمستخدمين');
        print(
            'النتيجة النهائية: ${technicians.length} فنيين و ${leaders.length} قادة للقسم: $_selectedDepartment');
      }

      // في حالة عدم وجود مستخدمين للقسم المحدد، لا نستخدم بيانات من أقسام أخرى
      if (technicians.isEmpty) {
        print('⚠️ لم يتم العثور على فنيين للقسم: $_selectedDepartment');
        // يمكن إضافة رسالة تحذيرية للمستخدم
      }

      if (leaders.isEmpty) {
        print('⚠️ لم يتم العثور على قادة للقسم: $_selectedDepartment');
      }

      if (mounted) {
        setState(() {
          _technicians = technicians;
          _leaders = leaders;

          // الحفاظ على القيم الافتراضية المُعيَّنة مسبقاً
          // إضافة القائد الافتراضي "رسول" إذا لم يكن موجوداً في القائمة
          if (!_leaders.contains('رسول')) {
            _leaders.insert(0, 'رسول');
            print('➕ تم إضافة القائد الافتراضي: رسول');
          }

          // إضافة المستخدم الحالي كفني إذا لم يكن موجوداً في القائمة
          if (!_technicians.contains(widget.currentUsername)) {
            _technicians.insert(0, widget.currentUsername);
            print('➕ تم إضافة الفني الافتراضي: ${widget.currentUsername}');
          }

          // التحقق من صحة القيم المختارة حالياً وإعادة تعيينها إذا لزم الأمر
          if (_selectedTechnician.isNotEmpty &&
              !_technicians.contains(_selectedTechnician)) {
            print(
                '⚠️ الفني المختار غير موجود في القائمة الجديدة: $_selectedTechnician - سيتم الاحتفاظ به كقيمة افتراضية');
            // لا نمسح القيمة الافتراضية، نضيفها للقائمة بدلاً من ذلك
            _technicians.insert(0, _selectedTechnician);
          }

          if (_selectedLeader.isNotEmpty &&
              !_leaders.contains(_selectedLeader)) {
            print(
                '⚠️ القائد المختار غير موجود في القائمة الجديدة: $_selectedLeader - سيتم الاحتفاظ به كقيمة افتراضية');
            // لا نمسح القيمة الافتراضية، نضيفها للقائمة بدلاً من ذلك
            _leaders.insert(0, _selectedLeader);
          }

          // إعادة تطبيق التعيين التلقائي للفني في حالة شراء الاشتراك
          _checkAndSetCurrentTechnicianForSubscription();

          // تحديث رقم هاتف الفني المُعيَّن
          _updateSelectedUserPhone();
        });
        print(
            'تم تحديث الواجهة: ${_technicians.length} فنيين، ${_leaders.length} قادة للقسم: $_selectedDepartment');
      }
    } catch (e) {
      print('خطأ في جلب المستخدمين: $e');

      if (mounted) {
        setState(() {
          _errorMessage = 'خطأ في جلب بيانات المستخدمين: ${e.toString()}';
        });
      }
      rethrow;
    }
  }

  Future<void> _fetchFBGOptions() async {
    if (_sheetsApi == null) {
      print('❌ _sheetsApi is null، لم يتم تهيئة API بعد');
      return;
    }

    print('🚀 بدء محاولة جلب بيانات FBG من Google Sheets...');
    print('📋 معرف الملف: $spreadsheetId');

    try {
      // أولاً، جلب قائمة الصفحات المتاحة للتأكد من وجود Sheet1
      try {
        print('🔍 جلب قائمة الصفحات المتاحة في الملف...');
        final spreadsheet = await _sheetsApi!.spreadsheets.get(spreadsheetId);
        print('📋 الصفحات المتاحة في الملف:');
        for (var sheet in spreadsheet.sheets!) {
          print(
              '   - ${sheet.properties!.title} (ID: ${sheet.properties!.sheetId})');
        }
      } catch (e) {
        print('❌ فشل في جلب قائمة الصفحات: $e');
        return;
      }

      // محاولة جلب بيانات FBG من العمود الأول في صفحة Sheet1
      const possibleFBGRanges = [
        'Sheet1!A:A', // العمود الكامل أولاً
        'Sheet1!A2:A1000', // نطاق محدود
        'Sheet1!A1:A1000', // من الصف الأول
        'Sheet1!A2:A', // النطاق الرئيسي
        'FBG!A:A', // اسم ورقة بديل
        'DataSheet!A:A', // اسم ورقة احتياطية
      ];

      sheets.ValueRange? response;
      String usedRange = '';
      String errorLog = '';

      for (String range in possibleFBGRanges) {
        try {
          print('🔍 محاولة جلب البيانات من: $range');
          response =
              await _sheetsApi!.spreadsheets.values.get(spreadsheetId, range);

          if (response.values != null && response.values!.isNotEmpty) {
            usedRange = range;
            print('✅ تم جلب بيانات من $range');
            print('📊 عدد الصفوف المجلبة: ${response.values!.length}');

            // طباعة أول 3 صفوف للتحقق
            print('📝 أول 3 صفوف من البيانات:');
            for (int i = 0; i < response.values!.length && i < 3; i++) {
              print('   الصف ${i + 1}: ${response.values![i]}');
            }
            break;
          } else {
            print('⚠️ النطاق $range فارغ أو لا يحتوي على بيانات');
            print('   response values: ${response.values}');
          }
        } catch (e) {
          String error = '❌ فشل في جلب بيانات من $range: $e';
          print(error);
          errorLog += '$error\n';
          continue;
        }
      }

      if (response != null &&
          response.values != null &&
          response.values!.isNotEmpty &&
          mounted) {
        List<String> fbgOptions = [];

        print('🔄 بدء معالجة بيانات FBG...');

        for (int rowIndex = 0; rowIndex < response.values!.length; rowIndex++) {
          var row = response.values![rowIndex];

          if (row.isNotEmpty && row[0] != null) {
            final fbgValue = row[0].toString().trim();

            print('   معالجة الصف ${rowIndex + 1}: "$fbgValue"');

            // تخطي الصفوف الفارغة والعناوين فقط (عنوان FBG وحده)
            if (fbgValue.isNotEmpty &&
                fbgValue.toLowerCase() != 'fbg' && // تخطي العنوان "FBG" فقط
                !fbgValue.toLowerCase().contains('code') &&
                !fbgValue.toLowerCase().contains('عنوان') &&
                !fbgValue.toLowerCase().contains('header') &&
                fbgValue.length > 2) {
              // التأكد من أن القيمة ليست مجرد حرف أو حرفين

              fbgOptions.add(fbgValue);
              print('✅ تم إضافة FBG: $fbgValue');
            } else {
              print('⏭️ تم تخطي القيمة: "$fbgValue" (عنوان أو قيمة غير صالحة)');
            }
          } else {
            print('⏭️ تم تخطي الصف ${rowIndex + 1}: فارغ أو null');
          }
        }

        // إزالة التكرارات مع الحفاظ على الترتيب
        final List<String> uniqueOptions = [];
        final Set<String> seen = {};
        for (final opt in fbgOptions) {
          final normalized = opt.trim();
          if (!seen.contains(normalized)) {
            seen.add(normalized);
            uniqueOptions.add(normalized);
          } else {
            print('♻️ تم تجاهل FBG مكرر: $normalized');
          }
        }

        // إذا كان هناك قيمة مبدئية (من خلال initialFBG) وغير موجودة في الخيارات، نضيفها في البداية
        if (_fbgController.text.isNotEmpty &&
            !uniqueOptions.contains(_fbgController.text.trim())) {
          print(
              '➕ إضافة قيمة FBG المبدئية غير الموجودة في القائمة: ${_fbgController.text.trim()}');
          uniqueOptions.insert(0, _fbgController.text.trim());
        }

        if (mounted) {
          setState(() {
            _fbgOptions = uniqueOptions;
          });
        }

        print(
            '🎉 انتهت المعالجة: تم جلب ${fbgOptions.length} خيار FBG من $usedRange');

        // طباعة جميع الخيارات المجلبة
        if (fbgOptions.isNotEmpty) {
          print('📊 جميع خيارات FBG المجلبة:');
          for (int i = 0; i < fbgOptions.length; i++) {
            print('   ${i + 1}. "${fbgOptions[i]}"');
          }
        } else {
          print('⚠️ لم يتم العثور على أي خيارات FBG صالحة بعد المعالجة!');
          print('💡 تحقق من أن البيانات في العمود A تحتوي على قيم FBG حقيقية');
        }
      } else {
        print('❌ فشل جلب بيانات FBG من جميع ال��طاقات المحددة');
        print('📋 تفاصيل الأخطاء:');
        print(errorLog);
        print('🔧 الحلول المقترحة:');
        print('1. تأكد من وجود صفحة باسم "Sheet1" في الملف');
        print('2. تأكد من وجود بيانات FBG في العمود A');
        print('3. تحقق من صلاحيات service account للوصول ل��ملف');
        print('4. تأكد من معرف الملف: $spreadsheetId');
      }
    } catch (e) {
      print('💥 خطأ عام في جلب بيانات FBG: $e');
      print('📚 Stack trace: ${StackTrace.current}');
      print('🔧 اقتراحات للإصلاح:');
      print('1. تحقق من صحة ملف service_account.json');
      print('2. تأكد من صحة معرف الملف');
      print('3. تحقق من صلاحيات الوصول للملف في Google Sheets');
      print('4. تأكد من تفعيل Google Sheets API');
    }
  }

  Future<void> _addTaskToGoogleSheets(Task task) async {
    try {
      // محاولة أسماء مختلفة لصفحة المهام
      const possibleTaskRanges = [
        'tasks!A2:W', // تم توسيع النطاق لاستيعاب العمودين U، V، و W
        'المهام!A2:W',
        'Tasks!A2:W',
        'مهام!A2:W',
        'Sheet4!A2:W'
      ];

      // ترتيب البيانات بناءً على المتطلبات الجديدة:
      // A=ID, B=Status, C=Department, D=TaskType(نوع المهمة), E=Leader, F=Technician,
      // G=Username, H=Phone(User), I=FBG, J=FAT, K=Location, L=Notes,
      // M=CreatedAt, N=ClosedAt, O=Summary, P=Priority, Q=CreatedBy,
      // R=Reserved(فارغ), S=Reserved, T=TechnicianPhone, U=ServiceType, V=SubscriptionDuration, W=SubscriptionAmount
      final values = [
        [
          task.id, // A - ID البسيط المتتالي (1، 2، 3...)
          task.status, // B - الحالة
          task.department, // C - القسم
          _selectedTaskType.isNotEmpty
              ? _selectedTaskType
              : 'غير محدد', // D - نوع المهمة
          task.leader, // E - القائد
          task.technician, // F - الفني
          task.username, // G - اسم المستخدم
          task.phone, // H - رقم هاتف المستخدم (للواتساب)
          task.fbg, // I - FBG
          task.fat, // J - FAT
          task.location, // K - الموقع
          task.notes, // L - الملاحظات
          task.createdAt.toIso8601String(), // M - تاريخ الإنشاء
          task.closedAt?.toIso8601String() ?? '', // N - تاريخ الإغلاق
          task.summary, // O - الملخص
          task.priority, // P - الأولوية
          task.createdBy, // Q - منشئ المهمة
          '', // R - فارغ (محجوز)
          '', // S - محجوز
          _currentSelectedPhone, // T - رقم هاتف الفني (للإشعارات)
          _selectedServiceType, // U - نوع الخدمة (35, 50, 75, 150)
          _selectedSubscriptionDuration, // V - مدة الالتزام
          _subscriptionAmountController.text.trim(), // W - مبلغ الاشتراك
        ]
      ];

      final valueRange = sheets.ValueRange(values: values);

      bool taskAdded = false;
      String usedRange = '';

      for (String range in possibleTaskRanges) {
        try {
          await _sheetsApi!.spreadsheets.values.append(
            valueRange,
            spreadsheetId,
            range,
            valueInputOption: 'USER_ENTERED',
            insertDataOption: 'INSERT_ROWS',
          );

          usedRange = range;
          taskAdded = true;
          print('✅ تم إضافة المهمة إلى $range');
          print('📋 ID المهمة: ${values[0][0]}');
          print('📱 رقم المستخدم (H): ${values[0][7]}');
          print('📞 رقم الفني (T): ${values[0][19]}');
          break;
        } catch (e) {
          print('❌ فشل في إضافة المهمة إلى $range: $e');
          continue;
        }
      }

      if (!taskAdded) {
        throw Exception(
            'فشل في إضافة المهمة إلى أي من صفحات Google Sheets المتاحة');
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('تمت إضافة المهمة بنجاح!'),
                      Text(
                        'ID: ${values[0][0]} | تم الحفظ في: $usedRange',
                        style: const TextStyle(fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
        Navigator.pop(context);
        widget.onTaskAdded(task);
      }
    } catch (e) {
      print('خطأ في إضافة المهمة: $e');
      _showErrorMessage('خطأ أثناء إضافة المهمة: ${e.toString()}');
    }
  }

  void _showErrorMessage(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // دالة محدثة لجلب رقم الهاتف للفني فقط
  void _updateSelectedUserPhone() {
    // جلب رقم الفني فقط، لا نجلب رقم القائد
    if (_selectedTechnician.isNotEmpty &&
        _userPhones.containsKey(_selectedTechnician)) {
      _currentSelectedPhone = _userPhones[_selectedTechnician]!;
      print(
          '✅ تم جلب رقم الهاتف للفني $_selectedTechnician: $_currentSelectedPhone');
    } else {
      _currentSelectedPhone = '';
      print('⚠️ لم يتم العثور على رقم هاتف للفني: $_selectedTechnician');
    }
  }

  /// تحقق من إمكانية تعيين المستخدم الحالي كفني لمهام شراء الاشتراك
  void _checkAndSetCurrentTechnicianForSubscription() {
    // تحقق من أن نوع المهمة شراء اشتراك والمستخدم الحالي فني
    if (_selectedTaskType == 'شراء اشتراك' && widget.currentUserRole == 'فني') {
      // تعيين المستخدم الحالي كفني مختار
      _selectedTechnician = widget.currentUsername;

      // تحديث رقم الهاتف المختار
      _updateSelectedUserPhone();

      print(
          '✅ تم تعيين المستخدم الحالي تلقائياً كفني لشراء الاشتراك: ${widget.currentUsername}');
    } else if (_selectedTaskType != 'شراء اشتراك') {
      // إذا تم تغيير نوع المهمة من شراء اشتراك إلى شيء آخر، امسح الفني المحدد
      // فقط إذا كان الفني المحدد هو المستخدم الحالي (تم تعيينه تلقائياً)
      if (_selectedTechnician == widget.currentUsername &&
          widget.currentUserRole == 'فني') {
        _selectedTechnician = '';
        _currentSelectedPhone = '';
        print(
            '🔄 تم مسح تعيين الفني التلقائي لأن نوع المهمة لم يعد شراء اشتراك');
      }
    }
  }

  // دالة إرسال إشعار WhatsApp للقائد رسول
  // دالة إرسال إشعار WhatsApp للقائد رسول أو الفني
  Future<void> _sendWhatsAppNotification(Task task) async {
    try {
      print('🔍 Debug: بدء إرسال إشعار WhatsApp...');
      print('🔍 Debug: نوع المهمة المختار: "$_selectedTaskType"');

      // تحديد المستقبل بناءً على نوع المهمة
      String? targetPhone;
      String recipientType;

      if (_selectedTaskType == 'شراء اشتراك') {
        // للاشتراكات: إرسال للقائد رسول
        print('🔍 Debug: تم اكتشاف مهمة اشتراك - البحث عن رقم رسول...');
        final prefs = await SharedPreferences.getInstance();
        targetPhone = prefs.getString('rasoul_phone_number');
        recipientType = 'للقائد رسول';
        print('🔍 Debug: رقم رسول من الإعدادات: "$targetPhone"');
      } else {
        // للمهام العادية: إرسال للفني
        print('🔍 Debug: مهمة عادية - البحث عن رقم الفني...');
        targetPhone = _currentSelectedPhone;
        recipientType = 'للفني';
        print('🔍 Debug: رقم الفني: "$targetPhone"');
      }

      if (targetPhone?.trim().isEmpty ?? true) {
        print('❌ Debug: لم يتم العثور على رقم هاتف $recipientType');
        if (mounted) {
          if (recipientType.contains('رسول')) {
            // إذا كان المشكلة مع رقم رسول، اعرض dialog سريع
            _showQuickRasoulPhoneDialog();
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                    'يرجى تعيين رقم هاتف $recipientType في الإعدادات أولاً'),
                backgroundColor: Colors.orange,
                duration: const Duration(seconds: 4),
              ),
            );
          }
        }
        return;
      }

      print('✅ Debug: تم العثور على رقم هاتف $recipientType: $targetPhone');
      print(
          '🚀 Debug: محاولة إرسال إشعار WhatsApp إلى $recipientType: $targetPhone');

      // إنشاء الرسالة وإرسالها باستخدام آلية subscription_details_page.dart
      final whatsappMsg = _buildWhatsAppMessage(task, recipientType);
      print('📝 Debug: تم إنشاء الرسالة، الطول: ${whatsappMsg.length}');

      await _sendWhatsAppMessage(targetPhone!, whatsappMsg, recipientType);
    } catch (e) {
      print('❌ Debug: خطأ في إرسال إشعار الواتساب: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ خطأ في إرسال الإشعار: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  // دالة لفتح تطبيق WhatsApp Desktop المثبت على الحاسوب

  // دالة جلب مهام الأقسام من صفحة ALKSM
  Future<void> _fetchDepartmentTasks() async {
    if (_sheetsApi == null) return;

    try {
      print('🚀 بدء جلب مهام الأقسام من صفحة ALKSM...');

      const possibleALKSMRanges = [
        'ALKSM!A2:K', // النطاق الرئيسي
        'ALKSM!A1:K', // في حالة كان الصف الأول يحتوي على بيانات
        'الاقسام!A2:K', // اسم ورقة بديل باللغة العربية
        'اقسام!A2:K', // بدون ال التعريف
        'Departments!A2:K', // اسم ورقة بالإنجليزية
        'Sheet3!A2:K' // احتياط��
      ];

      sheets.ValueRange? response;

      for (String range in possibleALKSMRanges) {
        try {
          response =
              await _sheetsApi!.spreadsheets.values.get(spreadsheetId, range);
          if (response.values != null && response.values!.isNotEmpty) {
            print('✅ تم جلب بيانات ALKSM من $range');
            break;
          }
        } catch (e) {
          print('❌ فشل في جلب البيانات من $range: $e');
          continue;
        }
      }

      Map<String, List<String>> departmentTasks = {};

      if (response != null &&
          response.values != null &&
          response.values!.isNotEmpty) {
        print('🔄 بدء معالجة بيانات مهام الأقسام...');

        for (var row in response.values!) {
          if (row.isNotEmpty) {
            final department = row[0]?.toString().trim() ?? '';

            if (department.isNotEmpty &&
                !department.toLowerCase().contains('اقسام') &&
                !department.toLowerCase().contains('departments') &&
                !department.toLowerCase().contains('المهمه')) {
              // جمع جميع المهام من الأعمدة B إلى K
              List<String> tasks = [];
              for (int i = 1; i < row.length && i <= 10; i++) {
                // من العمود B إلى K
                final task = row[i]?.toString().trim() ?? '';
                if (task.isNotEmpty && task != 'null') {
                  tasks.add(task);
                }
              }

              if (tasks.isNotEmpty) {
                departmentTasks[department] = tasks;
                print('✅ تم جلب ${tasks.length} مهام للقسم: $department');
              }
            }
          }
        }

        if (mounted) {
          setState(() {
            _departmentTasks = departmentTasks;
          });
        }

        print('🎉 تم جلب مهام ${departmentTasks.length} أقسام من ALKSM');
      } else {
        print('⚠️ لم يتم العثور على بيانات في صفحة ALKSM');
      }
    } catch (e) {
      print('❌ خطأ في جلب مهام الأقسام: $e');
    }
  }

  /// بناء قائمة أنواع المهام مع إضافة "شراء اشتراك" كخيار عام
  List<DropdownMenuItem<String>> _getTaskTypeItems() {
    List<DropdownMenuItem<String>> items = [];

    // إضافة "شراء اشتراك" كخيار أول للجميع
    items.add(
      const DropdownMenuItem(
        value: 'شراء اشتراك',
        child: Row(
          children: [
            Icon(Icons.shopping_cart, size: 16, color: Colors.purple),
            SizedBox(width: 8),
            Text('شراء اشتراك', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );

    // إضافة فاصل
    items.add(
      const DropdownMenuItem(
        value: '',
        enabled: false,
        child: Divider(height: 1),
      ),
    );

    // إضافة مهام القسم المحدد (إن وجدت)
    if (_selectedDepartment.isNotEmpty &&
        _departmentTasks.containsKey(_selectedDepartment)) {
      final departmentTaskTypes = _departmentTasks[_selectedDepartment] ?? [];
      for (String task in departmentTaskTypes) {
        if (task.isNotEmpty && task != 'شراء اشتراك') {
          // تجنب التكرار
          items.add(
            DropdownMenuItem(
              value: task,
              child: Text(task),
            ),
          );
        }
      }
    }

    return items;
  }

  // دالة لتحديث المستخدمين عند تغيير القسم
  void _onDepartmentChanged(String newDepartment) {
    setState(() {
      _selectedDepartment = newDepartment;

      // إذا كان القسم الجديد هو "الصيانة"، احتفظ بالقيم الافتراضية
      if (newDepartment == 'الصيانة') {
        _selectedLeader = 'رسول';
        _selectedTechnician = widget.currentUsername;
      } else {
        // لأقسام أخرى، امسح القيم ليختار المستخدم
        _selectedLeader = '';
        _selectedTechnician = '';
      }

      _selectedTaskType = '';
      _currentSelectedPhone = '';
    });

    // إعادة جلب المستخدمين للقسم الجديد
    _fetchUsers();
  }

  // دالة إنشاء المهمة وحفظها
  Future<void> _createTask() async {
    print('🔍 Debug: بدء إنشاء المهمة...');
    print('🔍 Debug: نوع المهمة: "$_selectedTaskType"');

    if (!_formKey.currentState!.validate()) return;

    // التحقق من اختيار فني (إلا في حالة شراء الاشتراك)
    if (_selectedTaskType != 'شراء اشتراك' && _selectedTechnician.isEmpty) {
      _showErrorMessage('يجب اختيار فني لتنفيذ المهمة');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // تحديث رقم هاتف الفني المحدد
      _updateSelectedUserPhone();

      // إنشاء ID بسيط متتالي
      final taskId = await _generateSimpleTaskId();

      // إنشاء كائن المهمة
      final task = Task(
        id: taskId, // استخدام ID البسيط المتتالي
        title: _selectedTaskType.isNotEmpty ? _selectedTaskType : 'مهمة جديدة',
        department: _selectedTaskType == 'شراء اشتراك'
            ? 'الحسابات' // تعيين قسم الحسابات تلقائياً لمهام شراء الاشتراك
            : _selectedDepartment,
        leader: _selectedLeader,
        technician:
            _selectedTechnician.isNotEmpty ? _selectedTechnician : 'غير محدد',
        username: _usernameController.text.trim(),
        phone: _phoneController.text.trim(),
        fbg: _fbgController.text.trim(),
        fat: _fatController.text.trim(),
        location: _locationController.text.trim(),
        notes: _notesController.text.trim(),
        summary: _summaryController.text.trim(),
        priority: _selectedPriority,
        status: _defaultStatus, // استخدام الحالة الافتراضية "مفتوحة"
        createdAt: DateTime.now(),
        createdBy: widget.currentUsername,
        agents: [], // قائمة فارغة للوكلاء
        statusHistory: [], // قائمة فارغة لتا��يخ الحالات
      );

      // حفظ المهمة في Google Sheets
      print('💾 Debug: حفظ المهمة في Google Sheets...');
      await _addTaskToGoogleSheets(task);

      // إرسال إشعار WhatsApp للقائد رسول
      print('📞 Debug: إرسال إشعار WhatsApp...');
      await _sendWhatsAppNotification(task);
      print('✅ Debug: تم الانتهاء من عملية إنشاء المهمة');
    } catch (e) {
      print('خطأ في إنشاء المهمة: $e');
      _showErrorMessage('خ��أ أثناء إنشاء المهمة: ${e.toString()}');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _phoneController.dispose();
    _fbgController.dispose();
    _fatController.dispose();
    _locationController.dispose();
    _notesController.dispose();
    _summaryController.dispose();
    _subscriptionAmountController.dispose();
    _client?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        width: MediaQuery.of(context).size.width * 0.9,
        height: MediaQuery.of(context).size.height * 0.9,
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // عنوان الحوار
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'إضافة مهمة جديدة',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const Divider(thickness: 2),

            // محتوى الحوار
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 16),
                          Text('جاري تحميل البيانات...'),
                        ],
                      ),
                    )
                  : _errorMessage != null
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.error_outline,
                                size: 64,
                                color: Colors.red,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                _errorMessage!,
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: Colors.red),
                              ),
                              const SizedBox(height: 16),
                              ElevatedButton(
                                onPressed: () {
                                  setState(() {
                                    _errorMessage = null;
                                  });
                                  _initializeSheetsAPI();
                                },
                                child: const Text('إعادة المحاولة'),
                              ),
                            ],
                          ),
                        )
                      : _buildTaskForm(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTaskForm() {
    return Form(
      key: _formKey,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // معلومات القسم والمستخدمين
            _buildDepartmentSection(),
            const SizedBox(height: 20),

            // معلومات العميل
            _buildCustomerSection(),
            const SizedBox(height: 20),

            // معلومات فنية
            _buildTechnicalSection(),
            const SizedBox(height: 20),

            // معلومات الاشتراك (تظهر فقط لمهام شراء الاشتراك)
            if (_selectedTaskType == 'شراء اشتراك') ...[
              _buildSubscriptionSection(),
              const SizedBox(height: 20),
            ],

            // معلومات إضافية
            _buildAdditionalSection(),
            const SizedBox(height: 30),

            // أزرار الحفظ والإلغاء
            _buildActionButtons(),
          ],
        ),
      ),
    );
  }

  Widget _buildDepartmentSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'معلومات القسم والفريق',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),

            // اختيار القسم
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: DropdownButtonFormField<String>(
                    decoration: const InputDecoration(
                      labelText: 'القسم *',
                      border: OutlineInputBorder(),
                    ),
                    initialValue: _selectedDepartment.isEmpty
                        ? null
                        : _selectedDepartment,
                    items: _departments.map((dept) {
                      return DropdownMenuItem(
                        value: dept,
                        child: Text(dept),
                      );
                    }).toList(),
                    onChanged: (value) {
                      if (value != null) {
                        _onDepartmentChanged(value);
                      }
                    },
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'يجب اختيار القسم';
                      }
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: 16),

                // اختيار نوع المهمة
                Expanded(
                  flex: 2,
                  child: DropdownButtonFormField<String>(
                    decoration: const InputDecoration(
                      labelText: 'نوع المهمة *',
                      border: OutlineInputBorder(),
                    ),
                    initialValue:
                        _selectedTaskType.isEmpty ? null : _selectedTaskType,
                    items: _getTaskTypeItems(),
                    onChanged: (value) {
                      setState(() {
                        _selectedTaskType = value ?? '';
                        // إذا تم اختيار "شراء اشتراك" والمستخدم الحالي فني، قم بتعيينه تلقائياً
                        _checkAndSetCurrentTechnicianForSubscription();
                      });
                    },
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'يجب اختيار نوع المهمة';
                      }
                      return null;
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // رسالة توضيحية لمهام شراء الاشتراك
            if (_selectedTaskType == 'شراء اشتراك') const SizedBox(height: 16),

            // اختيار القائد والفني
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    decoration: const InputDecoration(
                      labelText: 'القائد',
                      border: OutlineInputBorder(),
                    ),
                    initialValue: () {
                      // التحقق من أن القيمة المختارة موجودة في القائمة ومرة واحدة فقط
                      if (_selectedLeader.isEmpty) return null;
                      final matches = _leaders
                          .where((leader) => leader == _selectedLeader)
                          .length;
                      if (matches == 1) {
                        return _selectedLeader;
                      } else {
                        print(
                            '⚠️ قيمة القائد غير صحيحة أو مكررة: $_selectedLeader (تكرارات: $matches)');
                        return null;
                      }
                    }(),
                    items: _leaders.map((leader) {
                      return DropdownMenuItem(
                        value: leader,
                        child: Text(leader),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setState(() {
                        _selectedLeader = value ?? '';
                      });
                    },
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    decoration: const InputDecoration(
                      labelText: 'الفني',
                      border: OutlineInputBorder(),
                    ),
                    initialValue: () {
                      // التحقق من أن القيمة المختارة موجودة في القائمة ومرة واحدة فقط
                      if (_selectedTechnician.isEmpty) return null;
                      final matches = _technicians
                          .where((tech) => tech == _selectedTechnician)
                          .length;
                      if (matches == 1) {
                        return _selectedTechnician;
                      } else {
                        print(
                            '⚠️ قيمة الفني غير صحيحة أو مكررة: $_selectedTechnician (تكرارات: $matches)');
                        return null;
                      }
                    }(),
                    items: _technicians.map((tech) {
                      return DropdownMenuItem(
                        value: tech,
                        child: Text(tech),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setState(() {
                        _selectedTechnician = value ?? '';
                        _updateSelectedUserPhone();
                      });
                    },
                    validator: (value) {
                      // الفني اختياري لمهام شراء الاشتراك
                      if (_selectedTaskType != 'شراء اشتراك' &&
                          (value == null || value.isEmpty)) {
                        return 'يجب اختيار فني';
                      }
                      return null;
                    },
                  ),
                ),
              ],
            ),

            // عرض رقم هاتف الفني المحدد
            if (_currentSelectedPhone.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  border: Border.all(color: Colors.green.shade300),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.phone, size: 16, color: Colors.green),
                    const SizedBox(width: 8),
                    Text(
                      'رقم هاتف الفني: $_currentSelectedPhone',
                      style: const TextStyle(fontSize: 12, color: Colors.green),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCustomerSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'معلومات العميل',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _usernameController,
                    decoration: const InputDecoration(
                      labelText: 'اسم العميل *',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'يجب إدخال اسم العميل';
                      }
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextFormField(
                    controller: _phoneController,
                    decoration: const InputDecoration(
                      labelText: 'رقم الهاتف *',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.phone,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'يجب إدخال رقم الهاتف';
                      }
                      return null;
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _locationController,
              decoration: const InputDecoration(
                labelText: 'الموقع *',
                border: OutlineInputBorder(),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'يجب إدخال الموقع';
                }
                return null;
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTechnicalSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'المعلومات الفنية',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _fbgOptions.isNotEmpty
                      ? DropdownButtonFormField<String>(
                          decoration: const InputDecoration(
                            labelText: 'FBG *',
                            border: OutlineInputBorder(),
                          ),
                          // ضمان أن القيمة الحالية موجودة مرة واحدة فقط داخل القائمة وإلا نعيدها إلى null لتفادي Assertion
                          initialValue: () {
                            final current = _fbgController.text.trim();
                            if (current.isEmpty) return null;
                            // احصاء عدد التكرارات للقيمة الحالية
                            final matches =
                                _fbgOptions.where((e) => e == current).length;
                            if (matches == 1) {
                              return current;
                            } else if (matches > 1) {
                              print(
                                  '⚠️ قيمة FBG مكررة داخل القائمة: $current (تكرارات: $matches) سيتم استخدام أول واحدة فقط');
                              // إزالة التكرارات فوراً للحفاظ على سلامة القائمة مستقبلاً
                              final firstIndex = _fbgOptions.indexOf(current);
                              final cleaned = <String>[];
                              final seenLocal = <String>{};
                              for (int i = 0; i < _fbgOptions.length; i++) {
                                final v = _fbgOptions[i];
                                if (v == current) {
                                  if (i == firstIndex) {
                                    cleaned.add(v);
                                  } else {
                                    print('🗑️ إزالة تكرار زائد للقيمة: $v');
                                  }
                                } else if (!seenLocal.contains(v)) {
                                  cleaned.add(v);
                                  seenLocal.add(v);
                                }
                              }
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                if (mounted) {
                                  setState(() {
                                    _fbgOptions = cleaned;
                                  });
                                }
                              });
                              return current;
                            } else {
                              print(
                                  '⚠️ القيمة الحالية غير موجودة داخل الخيارات بعد الجلب: $current سيتم تعيينها null');
                              return null;
                            }
                          }(),
                          items: _fbgOptions.map((fbg) {
                            return DropdownMenuItem(
                              value: fbg,
                              child: Text(fbg),
                            );
                          }).toList(),
                          onChanged: (value) {
                            setState(() {
                              _fbgController.text = value ?? '';
                            });
                          },
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'يجب اختيار FBG';
                            }
                            return null;
                          },
                        )
                      : TextFormField(
                          controller: _fbgController,
                          decoration: const InputDecoration(
                            labelText: 'FBG *',
                            border: OutlineInputBorder(),
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'يجب إدخال FBG';
                            }
                            return null;
                          },
                        ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextFormField(
                    controller: _fatController,
                    decoration: const InputDecoration(
                      labelText: 'FAT *',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'يجب إدخال FAT';
                      }
                      return null;
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSubscriptionSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.subscriptions,
                    color: Colors.purple.shade700, size: 20),
                const SizedBox(width: 8),
                const Text(
                  'معلومات الاشتراك',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                // نوع الخدمة
                Expanded(
                  child: DropdownButtonFormField<String>(
                    decoration: InputDecoration(
                      labelText: 'نوع الخدمة *',
                      border: const OutlineInputBorder(),
                      prefixIcon:
                          Icon(Icons.speed, color: Colors.green.shade600),
                    ),
                    initialValue: _selectedServiceType.isEmpty
                        ? null
                        : _selectedServiceType,
                    items: _serviceTypes.map((serviceType) {
                      return DropdownMenuItem(
                        value: serviceType,
                        child: Row(
                          children: [
                            Text(serviceType,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold)),
                            const SizedBox(width: 8),
                            Text('FIBER',
                                style: TextStyle(
                                    color: Colors.grey.shade600, fontSize: 12)),
                          ],
                        ),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setState(() {
                        _selectedServiceType = value ?? '';
                      });
                    },
                    validator: (value) {
                      if (_selectedTaskType == 'شراء اشتراك' &&
                          (value == null || value.isEmpty)) {
                        return 'يجب اختيار نوع الخدمة';
                      }
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: 16),
                // مدة الالتزام
                Expanded(
                  child: DropdownButtonFormField<String>(
                    decoration: InputDecoration(
                      labelText: 'مدة الالتزام *',
                      border: const OutlineInputBorder(),
                      prefixIcon:
                          Icon(Icons.schedule, color: Colors.blue.shade600),
                    ),
                    initialValue: _selectedSubscriptionDuration.isEmpty
                        ? null
                        : _selectedSubscriptionDuration,
                    items: _subscriptionDurations.map((duration) {
                      return DropdownMenuItem(
                        value: duration,
                        child: Text(duration),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setState(() {
                        _selectedSubscriptionDuration = value ?? '';
                      });
                    },
                    validator: (value) {
                      if (_selectedTaskType == 'شراء اشتراك' &&
                          (value == null || value.isEmpty)) {
                        return 'يجب اختيار مدة الالتزام';
                      }
                      return null;
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // مبلغ الاشتراك
            TextFormField(
              controller: _subscriptionAmountController,
              decoration: InputDecoration(
                labelText: 'مبلغ الاشتراك *',
                border: const OutlineInputBorder(),
                prefixIcon:
                    Icon(Icons.attach_money, color: Colors.orange.shade600),
                suffixText: 'دينار',
              ),
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
              ],
              validator: (value) {
                if (_selectedTaskType == 'شراء اشتراك') {
                  if (value == null || value.trim().isEmpty) {
                    return 'يجب إدخال مبلغ الاشتراك';
                  }
                  final amount = int.tryParse(value.trim());
                  if (amount == null || amount <= 0) {
                    return 'يجب إدخال مبلغ صحيح أكبر من صفر';
                  }
                }
                return null;
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAdditionalSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'معلومات إضافية',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),

            // اختيار الأولوية
            DropdownButtonFormField<String>(
              decoration: const InputDecoration(
                labelText: 'الأولوية *',
                border: OutlineInputBorder(),
              ),
              initialValue:
                  _selectedPriority.isEmpty ? null : _selectedPriority,
              items: _priorities.map((priority) {
                return DropdownMenuItem(
                  value: priority,
                  child: Text(priority),
                );
              }).toList(),
              onChanged: (value) {
                setState(() {
                  _selectedPriority = value ?? '';
                });
              },
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'يجب اختيار الأولوية';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            // الملاحظات
            TextFormField(
              controller: _notesController,
              decoration: const InputDecoration(
                labelText: 'الملاحظات',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 16),

            // الملخص
            TextFormField(
              controller: _summaryController,
              decoration: const InputDecoration(
                labelText: 'ملخص المهمة',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        OutlinedButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
        const SizedBox(width: 16),
        ElevatedButton(
          onPressed: _isLoading ? null : _createTask,
          child: _isLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('حفظ المهمة'),
        ),
      ],
    );
  }

  // التحقق من صحة رقم الهاتف وتنسيقه (مطابق لـ subscription_details_page.dart)
  String? _validateAndFormatPhone(String phone) {
    // إزالة كل شيء عدا الأرقام
    final cleanPhone = phone.replaceAll(RegExp(r'[^0-9]'), '');

    // التحقق من طول الرقم
    if (cleanPhone.length < 8) {
      return null;
    }

    // إضافة رمز العراق إذا لم يكن موجوداً
    if (!cleanPhone.startsWith('964')) {
      return '964$cleanPhone';
    }

    return cleanPhone;
  }

  // إرسال عبر تطبيق واتساب الخارجي (سطح المكتب أو الهاتف)
  Future<bool> _sendViaWhatsAppApp(String phone, String message) async {
    try {
      print('🔄 Debug: محاولة فتح تطبيق واتساب...');
      print('📱 Debug: الرسالة: $message');

      // تنظيف الرسالة من الرموز المشكلة (بدون تشفير مسبق)
      String cleanMessage = message
          .replaceAll('&', 'و') // استبدال الأمبرساند
          .replaceAll('+', 'زائد'); // استبدال العلامة الزائد

      // تشفير الرسالة للـ URL (سيتم تشفير \n تلقائياً إلى %0A)
      final encodedMessage = Uri.encodeComponent(cleanMessage);

      // قائمة URLs للمحاولة بالترتيب
      final List<String> whatsappUrls = [
        // تطبيق واتساب سطح المكتب (Windows/Mac/Linux)
        'whatsapp://send?phone=$phone&text=$encodedMessage',

        // واتساب ويب كبديل
        'https://web.whatsapp.com/send?phone=$phone&text=$encodedMessage',

        // واتساب للهاتف (Android/iOS)
        'https://wa.me/$phone?text=$encodedMessage',
      ];

      bool success = false;
      String successMethod = '';

      // محاولة فتح التطبيقات بالترتيب
      for (int i = 0; i < whatsappUrls.length; i++) {
        try {
          final String url = whatsappUrls[i];
          final Uri uri = Uri.parse(url);

          print('🔄 Debug: محاولة ${i + 1}: $url');

          if (await canLaunchUrl(uri)) {
            await launchUrl(
              uri,
              mode: LaunchMode.externalApplication, // فتح في تطبيق خارجي
            );

            success = true;
            switch (i) {
              case 0:
                successMethod = 'تطبيق واتساب سطح المكتب';
                break;
              case 1:
                successMethod = 'واتساب ويب';
                break;
              case 2:
                successMethod = 'واتساب للهاتف';
                break;
            }

            print('✅ Debug: نجح الإرسال عبر: $successMethod');
            break;
          } else {
            print('⚠️ Debug: لا يمكن فتح: $url');
          }
        } catch (e) {
          print('❌ Debug: فشل في المحاولة ${i + 1}: $e');
          continue;
        }
      }

      // إظهار نتيجة الإرسال للمستخدم
      if (mounted) {
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✅ تم فتح $successMethod لإرسال الرسالة'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 4),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content:
                  Text('⚠️ لم يتم العثور على تطبيق واتساب. تأكد من تثبيته.'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 5),
            ),
          );
        }
      }

      return success;
    } catch (e) {
      print('❌ Debug: خطأ في فتح واتساب: $e');
      return false;
    }
  }

  // بناء رسالة الواتساب
  String _buildWhatsAppMessage(Task task, String recipientType) {
    String assignedUser =
        _selectedTechnician.isNotEmpty ? _selectedTechnician : _selectedLeader;
    String taskTitle =
        _selectedTaskType.isNotEmpty ? _selectedTaskType : 'مهمة جديدة';
    String customerName = _usernameController.text.trim();
    String customerPhone = _phoneController.text.trim();

    // بناء رسالة منسقة وجميلة مع أيقونات
    String message = '';

    if (_selectedTaskType == 'شراء اشتراك') {
      // رسالة خاصة للاشتراكات مع تفاصيل كاملة
      message = '🔔 مهمة جديدة: طلب اشتراك جديد\n';
      message += '════════════════════════\n\n';
      // معلومات العميل
      message += '👤 معلومات العميل:\n';
      message += '• الاسم: $customerName\n';
      if (customerPhone.isNotEmpty) {
        message += '• الهاتف: $customerPhone\n';
      }
      message += '• القسم: ${task.department}\n';
      message += '\n🔗 تفاصيل الاشتراك:\n';

      if (_selectedServiceType.isNotEmpty) {
        message += '• نوع الخدمة: $_selectedServiceType\n';
      }
      if (_selectedSubscriptionDuration.isNotEmpty) {
        message += '• مدة الاشتراك: $_selectedSubscriptionDuration\n';
      }
      if (_subscriptionAmountController.text.trim().isNotEmpty) {
        message +=
            '• المبلغ المطلوب: ${_subscriptionAmountController.text.trim()} دينار\n';
      }

      // معلومات تقنية للاشتراك
      if (task.location.isNotEmpty) {
        message += '\n🌐 المعلومات التقنية:\n';
        message += '• الموقع: ${task.location}\n';
        if (task.fbg.isNotEmpty) {
          message += '• FBG: ${task.fbg}\n';
        }
        if (task.fat.isNotEmpty) {
          message += '• FAT: ${task.fat}\n';
        }
      }

      message += '• الأولوية: ${task.priority}\n';
      message += '• المكلف بالتنفيذ: $assignedUser\n';
    } else {
      // رسالة عادية للمهام الأخرى
      message = '🔧 مهمة جديدة: $taskTitle\n';
      message += '════════════════════════\n\n';

      message += '👤 معلومات العميل:\n';
      message += '• الاسم: $customerName\n';
      if (customerPhone.isNotEmpty) {
        message += '• الهاتف: $customerPhone\n';
      }
      message += '• القسم: ${task.department}\n';

      message += '\n🔧 تفاصيل المهمة:\n';
      message += '• نوع المهمة: $taskTitle\n';
      message += '• الفني المكلف: $assignedUser\n';
      message += '• الأولوية: ${task.priority}\n';

      if (task.location.isNotEmpty ||
          task.fbg.isNotEmpty ||
          task.fat.isNotEmpty) {
        message += '\n🌐 المعلومات التقنية:\n';
        if (task.location.isNotEmpty) {
          message += '• الموقع: ${task.location}\n';
        }
        if (task.fbg.isNotEmpty) {
          message += '• FBG: ${task.fbg}\n';
        }
        if (task.fat.isNotEmpty) {
          message += '• FAT: ${task.fat}\n';
        }
      }
    }

    if (task.notes.isNotEmpty) {
      message += '\n📝 ملاحظات إضافية:\n';
      message += '${task.notes}\n';
    }

    // معلومات الإنشاء
    message += '\n────────────────────────\n';
    message +=
        '⏰ تاريخ الإنشاء: ${task.createdAt.toString().split('.')[0].replaceAll('T', ' في ')}\n';
    message += '👨‍💼 تم الإنشاء بواسطة: ${task.createdBy}\n';
    message += '\n🚀 يرجى البدء في تنفيذ المهمة';

    return message;
  }

  // إرسال رسالة واتساب باستخدام آلية subscription_details_page.dart
  Future<void> _sendWhatsAppMessage(
      String phone, String message, String recipientType) async {
    try {
      // التحقق من صحة رقم الهاتف وتنسيقه
      final cleanPhone = _validateAndFormatPhone(phone);
      if (cleanPhone == null) {
        print('❌ رقم الهاتف غير صحيح: $phone');
        return;
      }

      print('📱 Debug: إرسال واتساب إلى $recipientType: رقم=$cleanPhone');

      // إرسال الرسالة عبر تطبيق واتساب الخارجي
      final sent = await _sendViaWhatsAppApp(cleanPhone, message);

      if (sent && mounted) {
        print('✅ Debug: تم فتح تطبيق واتساب بنجاح');
      }
    } catch (e) {
      print('❌ خطأ في إرسال واتساب إلى $recipientType: $e');
    }
  }
}
