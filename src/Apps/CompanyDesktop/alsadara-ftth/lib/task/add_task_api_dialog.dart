import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:geolocator/geolocator.dart';
import '../services/task_api_service.dart';

/// حوار إضافة مهمة جديدة عبر API
class AddTaskApiDialog extends StatefulWidget {
  final String currentUsername;
  final String currentUserRole;
  final String currentUserDepartment;
  final Function(Map<String, dynamic>)? onTaskCreated;

  // قيم مبدئية اختيارية
  final String? initialCustomerName;
  final String? initialCustomerPhone;
  final String? initialCustomerLocation;
  final String? initialFBG;
  final String? initialFAT;
  final String? initialNotes;
  final String? initialTaskType;

  const AddTaskApiDialog({
    super.key,
    required this.currentUsername,
    required this.currentUserRole,
    required this.currentUserDepartment,
    this.onTaskCreated,
    this.initialCustomerName,
    this.initialCustomerPhone,
    this.initialCustomerLocation,
    this.initialFBG,
    this.initialFAT,
    this.initialNotes,
    this.initialTaskType,
  });

  @override
  State<AddTaskApiDialog> createState() => _AddTaskApiDialogState();
}

class _AddTaskApiDialogState extends State<AddTaskApiDialog> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _fbgController = TextEditingController();
  final _fatController = TextEditingController();
  final _locationController = TextEditingController();
  final _notesController = TextEditingController();
  final _summaryController = TextEditingController();
  final _subscriptionAmountController = TextEditingController();

  String _selectedDepartment = '';
  String _selectedLeader = '';
  String _selectedTechnician = '';
  String _selectedPriority = 'متوسط';
  String _selectedTaskType = '';
  String _selectedServiceType = '';
  String _selectedSubscriptionDuration = '';
  bool _isLoading = false;
  bool _isLoadingData = true;
  String? _errorMessage;
  int _currentStep = 0; // 0: القسم والفريق, 1: العميل, 2: الفني + ملاحظات
  static const int _totalSteps = 3;

  final List<String> _priorities = ['منخفض', 'متوسط', 'عالي', 'عاجل'];
  final List<String> _serviceTypes = ['35', '50', '75', '150'];
  final List<String> _subscriptionDurations = [
    'شهر',
    'شهرين',
    'ثلاث أشهر',
    '6 أشهر',
    'سنة'
  ];

  // بيانات من API (الأقسام والمستخدمين وFBG)
  List<String> _departments = [];
  List<String> _leaders = [];
  List<String> _technicians = [];
  List<String> _fbgOptions = [];
  Map<String, String> _userPhones = {};
  Map<String, List<String>> _departmentTasks = {};
  String _currentSelectedPhone = '';

  @override
  void initState() {
    super.initState();
    _selectedDepartment = 'الصيانة';
    _selectedLeader = 'رسول';
    _selectedTechnician = '';

    if (widget.initialCustomerName?.isNotEmpty == true) {
      _usernameController.text = widget.initialCustomerName!;
    }
    if (widget.initialCustomerPhone?.isNotEmpty == true) {
      _phoneController.text = widget.initialCustomerPhone!;
    }
    if (widget.initialCustomerLocation?.isNotEmpty == true) {
      _locationController.text = widget.initialCustomerLocation!;
    }
    if (widget.initialFBG?.isNotEmpty == true) {
      _fbgController.text = widget.initialFBG!;
    }
    if (widget.initialFAT?.isNotEmpty == true) {
      _fatController.text = widget.initialFAT!;
    }
    if (widget.initialNotes?.isNotEmpty == true) {
      _notesController.text = widget.initialNotes!;
    }
    if (widget.initialTaskType?.isNotEmpty == true) {
      _selectedTaskType = widget.initialTaskType!;
    }

    // عند شراء اشتراك: القسم = الحسابات + نوع المهمة ثابت + الفني يُختار من الحسابات
    if (_selectedTaskType == 'شراء اشتراك') {
      _selectedDepartment = 'الحسابات';
      _selectedLeader = '';
      _selectedTechnician = '';
    }

    _loadDataFromApi();
  }

  Future<void> _fetchDeviceLocation() async {
    try {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        await Geolocator.requestPermission();
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      if (mounted) {
        _locationController.text = '${pos.latitude}, ${pos.longitude}';
      }
    } catch (_) {
      // تجاهل — المستخدم يدخل الموقع يدوياً
    }
  }

  Future<void> _loadDataFromApi() async {
    try {
      setState(() => _isLoadingData = true);

      // جلب بيانات القوائم المنسدلة والموظفين بالتوازي
      final results = await Future.wait([
        TaskApiService.instance.getTaskLookupData(),
        TaskApiService.instance.getTaskStaff(department: _selectedDepartment),
      ]);

      final lookupResult = results[0];
      final staffResult = results[1];

      if (lookupResult['success'] == true && lookupResult['data'] != null) {
        final data = lookupResult['data'];

        // أقسام
        final deptsList = data['departments'] as List? ?? [];
        final deptNames = deptsList
            .map((d) => d['nameAr']?.toString() ?? '')
            .where((n) => n.isNotEmpty)
            .toList();

        // مهام كل قسم
        final deptTasksMap =
            data['departmentTasks'] as Map<String, dynamic>? ?? {};
        Map<String, List<String>> parsedDeptTasks = {};
        for (final entry in deptTasksMap.entries) {
          final tasks =
              (entry.value as List?)?.map((t) => t.toString()).toList() ?? [];
          if (tasks.isNotEmpty) parsedDeptTasks[entry.key] = tasks;
        }

        // خيارات FBG
        final fbgList =
            (data['fbgOptions'] as List?)?.map((f) => f.toString()).toList() ??
                [];

        if (mounted) {
          setState(() {
            _departments = deptNames;
            _departmentTasks = parsedDeptTasks;
            _fbgOptions = fbgList;
            // ضبط القسم تلقائياً عند شراء اشتراك بعد تحميل القائمة
            if (_selectedTaskType == 'شراء اشتراك') {
              if (!deptNames.contains('الحسابات')) {
                _departments.add('الحسابات');
              }
              _selectedDepartment = 'الحسابات';
            }
          });
        }
      }

      // موظفين
      _parseStaffData(staffResult);
    } catch (e) {
      debugPrint('❌ خطأ في تحميل البيانات');
      _errorMessage = 'فشل في تحميل البيانات';
    } finally {
      if (mounted) {
        setState(() => _isLoadingData = false);
      }
    }
  }

  void _parseStaffData(Map<String, dynamic> staffResult) {
    if (staffResult['success'] == true && staffResult['data'] != null) {
      final data = staffResult['data'];
      final leadersList = data['leaders'] as List? ?? [];
      final techniciansList = data['technicians'] as List? ?? [];

      List<String> leaders = [];
      List<String> technicians = [];
      Map<String, String> phones = {};

      for (var leader in leadersList) {
        final name = leader['Name']?.toString() ?? '';
        final phone = leader['PhoneNumber']?.toString() ?? '';
        if (name.isNotEmpty) {
          if (!leaders.contains(name)) leaders.add(name);
          if (phone.isNotEmpty) phones[name] = phone;
        }
      }

      for (var tech in techniciansList) {
        final name = tech['Name']?.toString() ?? '';
        final phone = tech['PhoneNumber']?.toString() ?? '';
        if (name.isNotEmpty) {
          if (!technicians.contains(name)) technicians.add(name);
          if (phone.isNotEmpty) phones[name] = phone;
        }
      }

      if (mounted) {
        setState(() {
          _leaders = leaders;
          _technicians = technicians;
          _userPhones = phones;

          // عند شراء اشتراك: الفني يُختار من قسم الحسابات فقط (لا نضيف الفني الحالي)
        });
        _updateSelectedUserPhone();
      }
    }
  }

  Future<void> _fetchStaffByDepartment(String department) async {
    try {
      final result =
          await TaskApiService.instance.getTaskStaff(department: department);
      _parseStaffData(result);
    } catch (e) {
      debugPrint('❌ خطأ في جلب الموظفين');
    }
  }

  void _updateSelectedUserPhone() {
    if (_selectedTechnician.isNotEmpty &&
        _userPhones.containsKey(_selectedTechnician)) {
      _currentSelectedPhone = _userPhones[_selectedTechnician]!;
    } else {
      _currentSelectedPhone = '';
    }
  }

  void _onDepartmentChanged(String newDepartment) {
    setState(() {
      _selectedDepartment = newDepartment;
      if (newDepartment == 'الصيانة') {
        _selectedLeader = 'رسول';
        _selectedTechnician = widget.currentUsername;
      } else {
        _selectedLeader = '';
        _selectedTechnician = '';
      }
      _selectedTaskType = '';
      _currentSelectedPhone = '';
    });
    _fetchStaffByDepartment(newDepartment);
  }

  List<DropdownMenuItem<String>> _getTaskTypeItems() {
    List<DropdownMenuItem<String>> items = [];

    // "شراء اشتراك" يظهر فقط لقسم الحسابات
    if (_selectedDepartment == 'الحسابات' || _selectedDepartment.isEmpty) {
      items.add(const DropdownMenuItem(
        value: 'شراء اشتراك',
        child: Row(children: [
          Icon(Icons.shopping_cart, size: 16, color: Colors.purple),
          SizedBox(width: 8),
          Text('شراء اشتراك', style: TextStyle(fontWeight: FontWeight.bold)),
        ]),
      ));

      items.add(const DropdownMenuItem(
        value: '',
        enabled: false,
        child: Divider(height: 1),
      ));
    }

    if (_selectedDepartment.isNotEmpty &&
        _departmentTasks.containsKey(_selectedDepartment)) {
      for (String task in _departmentTasks[_selectedDepartment] ?? []) {
        if (task.isNotEmpty && task != 'شراء اشتراك') {
          items.add(DropdownMenuItem(value: task, child: Text(task)));
        }
      }
    }

    return items;
  }

  // ═══════ إنشاء المهمة عبر API ═══════

  Future<void> _createTask() async {
    if (!_formKey.currentState!.validate()) return;

    if (_selectedTaskType != 'شراء اشتراك' && _selectedTechnician.isEmpty) {
      _showError('يجب اختيار فني لتنفيذ المهمة');
      return;
    }

    setState(() => _isLoading = true);

    try {
      _updateSelectedUserPhone();

      // تحديد القسم حسب نوع المهمة
      final department =
          _selectedTaskType == 'شراء اشتراك' ? 'الحسابات' : _selectedDepartment;

      final result = await TaskApiService.instance.createTask(
        taskType:
            _selectedTaskType.isNotEmpty ? _selectedTaskType : 'مهمة جديدة',
        customerName: _usernameController.text.trim(),
        customerPhone: _phoneController.text.trim(),
        department: department,
        leader: _selectedLeader,
        technician:
            _selectedTechnician.isNotEmpty ? _selectedTechnician : 'غير محدد',
        technicianPhone: _currentSelectedPhone,
        fbg: _fbgController.text.trim(),
        fat: _fatController.text.trim(),
        location: _locationController.text.trim(),
        notes: _notesController.text.trim(),
        summary: _summaryController.text.trim(),
        priority: _selectedPriority,
        serviceType:
            _selectedServiceType.isNotEmpty ? _selectedServiceType : null,
        subscriptionDuration: _selectedSubscriptionDuration.isNotEmpty
            ? _selectedSubscriptionDuration
            : null,
        subscriptionAmount: _subscriptionAmountController.text.trim().isNotEmpty
            ? double.tryParse(_subscriptionAmountController.text.trim())
            : null,
      );

      if (result['success'] == true) {
        // إرسال إشعار WhatsApp — معطّل مؤقتاً
        // await _sendWhatsAppNotification();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('تمت إضافة المهمة بنجاح!'),
                      Text(
                        'رقم الطلب: ${result['data']?['RequestNumber'] ?? ''}',
                        style: const TextStyle(fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ]),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 3),
            ),
          );

          widget.onTaskCreated?.call(result['data'] ?? {});
          Navigator.pop(context);
        }
      } else {
        _showError(result['message'] ?? 'فشل في إنشاء المهمة');
      }
    } catch (e) {
      debugPrint('❌ خطأ في إنشاء المهمة');
      _showError('خطأ أثناء إنشاء المهمة');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ═══════ WhatsApp ═══════

  Future<void> _sendWhatsAppNotification() async {
    try {
      String? targetPhone;
      String recipientType;

      if (_selectedTaskType == 'شراء اشتراك') {
        targetPhone = _userPhones['رسول'];
        recipientType = 'القائد';
      } else {
        targetPhone = _currentSelectedPhone;
        recipientType = 'الفني';
      }

      if (targetPhone?.trim().isEmpty ?? true) {
        debugPrint('⚠️ لم يتم العثور على رقم هاتف $recipientType');
        return;
      }

      final message = _buildWhatsAppMessage(recipientType);
      final cleanPhone = _validateAndFormatPhone(targetPhone!);
      if (cleanPhone == null) return;

      await _sendViaWhatsApp(cleanPhone, message);
    } catch (e) {
      debugPrint('❌ خطأ في إرسال WhatsApp');
    }
  }

  String _buildWhatsAppMessage(String recipientType) {
    String customerName = _usernameController.text.trim();
    String customerPhone = _phoneController.text.trim();
    String assignedUser =
        _selectedTechnician.isNotEmpty ? _selectedTechnician : _selectedLeader;
    String message = '';

    if (_selectedTaskType == 'شراء اشتراك') {
      message = '🔔 مهمة جديدة: طلب اشتراك جديد\n';
      message += '════════════════════════\n\n';
      message += '👤 معلومات العميل:\n';
      message += '• الاسم: $customerName\n';
      if (customerPhone.isNotEmpty) message += '• الهاتف: $customerPhone\n';
      message +=
          '• القسم: ${_selectedTaskType == 'شراء اشتراك' ? 'الحسابات' : _selectedDepartment}\n';
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
      if (_locationController.text.trim().isNotEmpty) {
        message += '\n🌐 المعلومات التقنية:\n';
        message += '• الموقع: ${_locationController.text.trim()}\n';
        if (_fbgController.text.trim().isNotEmpty) {
          message += '• FBG: ${_fbgController.text.trim()}\n';
        }
        if (_fatController.text.trim().isNotEmpty) {
          message += '• FAT: ${_fatController.text.trim()}\n';
        }
      }
      message += '• الأولوية: $_selectedPriority\n';
      message += '• المكلف بالتنفيذ: $assignedUser\n';
    } else {
      message += '🔧 مهمة جديدة: $_selectedTaskType\n';
      message += '════════════════════════\n\n';
      message += '👤 معلومات العميل:\n';
      message += '• الاسم: $customerName\n';
      if (customerPhone.isNotEmpty) message += '• الهاتف: $customerPhone\n';
      message += '• القسم: $_selectedDepartment\n';
      message += '\n🔧 تفاصيل المهمة:\n';
      message += '• نوع المهمة: $_selectedTaskType\n';
      message += '• الفني المكلف: $assignedUser\n';
      message += '• الأولوية: $_selectedPriority\n';
      if (_locationController.text.trim().isNotEmpty ||
          _fbgController.text.trim().isNotEmpty) {
        message += '\n🌐 المعلومات التقنية:\n';
        if (_locationController.text.trim().isNotEmpty) {
          message += '• الموقع: ${_locationController.text.trim()}\n';
        }
        if (_fbgController.text.trim().isNotEmpty) {
          message += '• FBG: ${_fbgController.text.trim()}\n';
        }
        if (_fatController.text.trim().isNotEmpty) {
          message += '• FAT: ${_fatController.text.trim()}\n';
        }
      }
    }

    if (_notesController.text.trim().isNotEmpty) {
      message += '\n📝 ملاحظات إضافية:\n${_notesController.text.trim()}\n';
    }

    message += '\n────────────────────────\n';
    message += '⏰ تاريخ الإنشاء: ${DateTime.now().toString().split('.')[0]}\n';
    message += '👨‍💼 تم الإنشاء بواسطة: ${widget.currentUsername}\n';
    message += '\n🚀 يرجى البدء في تنفيذ المهمة';

    return message;
  }

  String? _validateAndFormatPhone(String phone) {
    final cleanPhone = phone.replaceAll(RegExp(r'[^0-9]'), '');
    if (cleanPhone.length < 8) return null;
    if (!cleanPhone.startsWith('964')) return '964$cleanPhone';
    return cleanPhone;
  }

  Future<void> _sendViaWhatsApp(String phone, String message) async {
    try {
      String cleanMessage =
          message.replaceAll('&', 'و').replaceAll('+', 'زائد');
      final encodedMessage = Uri.encodeComponent(cleanMessage);

      final urls = [
        'whatsapp://send?phone=$phone&text=$encodedMessage',
        'https://web.whatsapp.com/send?phone=$phone&text=$encodedMessage',
        'https://wa.me/$phone?text=$encodedMessage',
      ];

      for (int i = 0; i < urls.length; i++) {
        try {
          final uri = Uri.parse(urls[i]);
          if (await canLaunchUrl(uri)) {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('✅ تم فتح واتساب لإرسال الرسالة'),
                  backgroundColor: Colors.green,
                  duration: Duration(seconds: 3),
                ),
              );
            }
            return;
          }
        } catch (e) {
          continue;
        }
      }
    } catch (e) {
      debugPrint('❌ خطأ في فتح واتساب');
    }
  }

  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: Colors.red),
      );
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
    super.dispose();
  }

  // ═══════ BUILD ═══════

  @override
  Widget build(BuildContext context) {
    final screenW = MediaQuery.of(context).size.width;
    final isMobile = screenW < 600;
    final isSmall = screenW < 420;
    // على الموبايل الصغير: شاشة كاملة لسهولة الاستخدام
    if (isSmall) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('إضافة مهمة جديدة', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          backgroundColor: Colors.blue.shade700,
          foregroundColor: Colors.white,
          leading: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
        ),
        body: Container(
          padding: const EdgeInsets.all(10),
          child: _isLoadingData
              ? const Center(child: CircularProgressIndicator())
              : _errorMessage != null
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.error_outline, size: 64, color: Colors.red),
                          const SizedBox(height: 6),
                          Text(_errorMessage!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.red)),
                          const SizedBox(height: 6),
                          ElevatedButton(
                            onPressed: () { setState(() => _errorMessage = null); _loadDataFromApi(); },
                            child: const Text('إعادة المحاولة'),
                          ),
                        ],
                      ),
                    )
                  : _buildTaskForm(),
        ),
      );
    }
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
    final availableHeight = MediaQuery.of(context).size.height - keyboardHeight;
    return Dialog(
      insetPadding: EdgeInsets.symmetric(horizontal: isMobile ? 8 : 40, vertical: isMobile ? 12 : 24),
      child: Container(
        width: isMobile ? screenW - 16 : screenW * 0.9,
        height: availableHeight * (isMobile ? 0.93 : 0.9),
        padding: EdgeInsets.all(isMobile ? 12 : 20),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(children: [
                  Icon(Icons.add_task, color: Colors.blue.shade700, size: isSmall ? 18 : 24),
                  SizedBox(width: isSmall ? 4 : 8),
                  Text('إضافة مهمة جديدة',
                      style:
                          TextStyle(fontSize: isSmall ? 13 : (isMobile ? 16 : 24), fontWeight: FontWeight.bold)),
                  SizedBox(width: isSmall ? 4 : 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.blue.shade200),
                    ),
                    child: Text('API',
                        style: TextStyle(
                            fontSize: 10,
                            color: Colors.blue.shade700,
                            fontWeight: FontWeight.bold)),
                  ),
                ]),
                IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context)),
              ],
            ),
            const Divider(thickness: 2),
            Expanded(
              child: _isLoadingData
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
                              const Icon(Icons.error_outline,
                                  size: 64, color: Colors.red),
                              SizedBox(height: _isNarrow ? 3 : 6),
                              Text(_errorMessage!,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(color: Colors.red)),
                              SizedBox(height: _isNarrow ? 3 : 6),
                              ElevatedButton(
                                onPressed: () {
                                  setState(() => _errorMessage = null);
                                  _loadDataFromApi();
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
    final isMobile = MediaQuery.of(context).size.width < 500;

    // على الموبايل: wizard متعدد الخطوات
    if (isMobile) {
      return Form(
        key: _formKey,
        child: Column(
          children: [
            // شريط التقدم
            _buildStepIndicator(),
            const SizedBox(height: 12),

            // محتوى الخطوة الحالية
            Expanded(
              child: SingleChildScrollView(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: _buildCurrentStep(),
                ),
              ),
            ),

            // أزرار التنقل (ثابتة في الأسفل)
            _buildStepNavigation(),
          ],
        ),
      );
    }

    // على الديسكتوب: النموذج الكامل كما كان
    return Form(
      key: _formKey,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildDepartmentSection(),
            const SizedBox(height: 6),
            _buildCustomerSection(),
            const SizedBox(height: 6),
            _buildTechnicalSection(),
            const SizedBox(height: 6),
            if (_selectedTaskType == 'شراء اشتراك') ...[
              _buildSubscriptionSection(),
              const SizedBox(height: 6),
            ],
            _buildAdditionalSection(),
            const SizedBox(height: 6),
            _buildActionButtons(),
          ],
        ),
      ),
    );
  }

  /// شريط تقدم الخطوات
  Widget _buildStepIndicator() {
    final steps = ['القسم والفريق', 'معلومات العميل', 'التفاصيل والملاحظات'];
    return Row(
      children: List.generate(steps.length, (i) {
        final isActive = i == _currentStep;
        final isDone = i < _currentStep;
        return Expanded(
          child: GestureDetector(
            onTap: isDone ? () => setState(() => _currentStep = i) : null,
            child: Column(
              children: [
                Row(
                  children: [
                    if (i > 0) Expanded(child: Container(height: 2, color: isDone ? const Color(0xFF4CAF50) : Colors.grey.shade300)),
                    Container(
                      width: 28, height: 28,
                      decoration: BoxDecoration(
                        color: isActive ? const Color(0xFF1A237E) : isDone ? const Color(0xFF4CAF50) : Colors.grey.shade300,
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: isDone
                            ? const Icon(Icons.check, size: 16, color: Colors.white)
                            : Text('${i + 1}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: isActive ? Colors.white : Colors.grey.shade600)),
                      ),
                    ),
                    if (i < steps.length - 1) Expanded(child: Container(height: 2, color: isDone ? const Color(0xFF4CAF50) : Colors.grey.shade300)),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  steps[i],
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                    color: isActive ? const Color(0xFF1A237E) : Colors.grey.shade500,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        );
      }),
    );
  }

  /// محتوى الخطوة الحالية
  Widget _buildCurrentStep() {
    switch (_currentStep) {
      case 0:
        return Column(
          key: const ValueKey(0),
          children: [
            _buildDepartmentSection(),
          ],
        );
      case 1:
        return Column(
          key: const ValueKey(1),
          children: [
            _buildCustomerSection(),
            const SizedBox(height: 8),
            _buildTechnicalSection(),
          ],
        );
      case 2:
        return Column(
          key: const ValueKey(2),
          children: [
            if (_selectedTaskType == 'شراء اشتراك') ...[
              _buildSubscriptionSection(),
              const SizedBox(height: 8),
            ],
            _buildAdditionalSection(),
          ],
        );
      default:
        return const SizedBox.shrink();
    }
  }

  /// تحقق من صحة الخطوة الحالية قبل الانتقال
  bool _validateCurrentStep() {
    switch (_currentStep) {
      case 0:
        if (_selectedDepartment.isEmpty) { _showError('يجب اختيار القسم'); return false; }
        if (_selectedTaskType.isEmpty) { _showError('يجب اختيار نوع المهمة'); return false; }
        if (_selectedTaskType != 'شراء اشتراك' && _selectedTechnician.isEmpty) { _showError('يجب اختيار فني'); return false; }
        return true;
      case 1:
        if (_usernameController.text.trim().isEmpty) { _showError('يجب إدخال اسم العميل'); return false; }
        if (_phoneController.text.trim().isEmpty) { _showError('يجب إدخال رقم الهاتف'); return false; }
        return true;
      case 2:
        return true; // الأولوية لها قيمة افتراضية
      default:
        return true;
    }
  }

  /// أزرار التنقل بين الخطوات (ثابتة في الأسفل)
  Widget _buildStepNavigation() {
    final isLast = _currentStep == _totalSteps - 1;
    final isFirst = _currentStep == 0;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Row(
        children: [
          // زر السابق
          if (!isFirst)
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => setState(() => _currentStep--),
                icon: const Icon(Icons.arrow_forward, size: 18),
                label: const Text('السابق'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            )
          else
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: const Text('إلغاء'),
              ),
            ),

          const SizedBox(width: 12),

          // زر التالي / حفظ
          Expanded(
            flex: 2,
            child: ElevatedButton.icon(
              onPressed: _isLoading ? null : () {
                if (isLast) {
                  if (_formKey.currentState?.validate() ?? false) {
                    _createTask();
                  }
                } else {
                  if (_validateCurrentStep()) {
                    setState(() => _currentStep++);
                  }
                }
              },
              icon: _isLoading
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Icon(isLast ? Icons.check_rounded : Icons.arrow_back, size: 20),
              label: Text(isLast ? 'حفظ المهمة' : 'التالي'),
              style: ElevatedButton.styleFrom(
                backgroundColor: isLast ? const Color(0xFF4CAF50) : const Color(0xFF1A237E),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDepartmentSection() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.blue.shade50.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.blue.shade200, width: 1.2),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 4, offset: const Offset(0, 2))],
      ),
      padding: EdgeInsets.symmetric(horizontal: MediaQuery.of(context).size.width < 420 ? 8 : 12, vertical: MediaQuery.of(context).size.width < 420 ? 6 : 10),
      child: Padding(
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('معلومات القسم والفريق',
                style: TextStyle(fontSize: MediaQuery.of(context).size.width < 420 ? 12 : 15, fontWeight: FontWeight.bold)),
            SizedBox(height: _isNarrow ? 3 : 6),
            _adaptiveRow(
              // القسم — ثابت عند شراء اشتراك
              _selectedTaskType == 'شراء اشتراك'
                  ? TextFormField(
                      initialValue: 'الحسابات',
                      readOnly: true,
                      decoration: InputDecoration(
                          labelText: 'القسم *', border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          isDense: true, filled: true, fillColor: Colors.grey.shade100,
                          suffixIcon: const Icon(Icons.lock_outline, size: 16, color: Colors.grey)),
                    )
                  : DropdownButtonFormField<String>(
                      key: ValueKey('dept_${_selectedDepartment}_${_departments.length}'),
                      decoration: InputDecoration(
                          labelText: 'القسم *', border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), isDense: true, filled: true, fillColor: Colors.white),
                      value: _departments.contains(_selectedDepartment)
                          ? _selectedDepartment
                          : null,
                      items: _departments
                          .map((d) => DropdownMenuItem(value: d, child: Text(d, style: const TextStyle(fontSize: 13))))
                          .toList(),
                      onChanged: (v) {
                        if (v != null) _onDepartmentChanged(v);
                      },
                      validator: (v) =>
                          (v == null || v.isEmpty) ? 'يجب اختيار القسم' : null,
                    ),
              // نوع المهمة — ثابت عند شراء اشتراك
              _selectedTaskType == 'شراء اشتراك'
                  ? TextFormField(
                      initialValue: 'شراء اشتراك',
                      readOnly: true,
                      decoration: InputDecoration(
                          labelText: 'نوع المهمة *', border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          isDense: true, filled: true, fillColor: Colors.grey.shade100,
                          suffixIcon: const Icon(Icons.lock_outline, size: 16, color: Colors.grey)),
                    )
                  : DropdownButtonFormField<String>(
                      decoration: InputDecoration(
                          labelText: 'نوع المهمة *',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), isDense: true, filled: true, fillColor: Colors.white),
                      value: _selectedTaskType.isEmpty ? null : _selectedTaskType,
                      items: _getTaskTypeItems(),
                      onChanged: (v) {
                        setState(() {
                          _selectedTaskType = v ?? '';
                          if (_selectedTaskType == 'شراء اشتراك') {
                            if (!_departments.contains('الحسابات')) {
                              _departments.add('الحسابات');
                            }
                            _selectedDepartment = 'الحسابات';
                            _selectedTechnician = '';
                            _selectedLeader = '';
                            _fetchStaffByDepartment('الحسابات');
                          }
                        });
                      },
                      validator: (v) => (v == null || v.isEmpty)
                          ? 'يجب اختيار نوع المهمة'
                          : null,
                    ),
            ),
            SizedBox(height: _isNarrow ? 3 : 6),
            _adaptiveRow(
              DropdownButtonFormField<String>(
                decoration: InputDecoration(
                    labelText: 'القائد', border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), isDense: true, filled: true, fillColor: Colors.white),
                value: _leaders.contains(_selectedLeader) ? _selectedLeader : null,
                items: _leaders.map((l) => DropdownMenuItem(value: l, child: Text(l, style: const TextStyle(fontSize: 13)))).toList(),
                onChanged: (v) => setState(() => _selectedLeader = v ?? ''),
              ),
              DropdownButtonFormField<String>(
                key: ValueKey('tech_${_selectedTechnician}_${_technicians.length}'),
                decoration: InputDecoration(
                    labelText: 'الفني', border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), isDense: true, filled: true, fillColor: Colors.white),
                value: _technicians.contains(_selectedTechnician) ? _selectedTechnician : null,
                items: _technicians.map((t) => DropdownMenuItem(value: t, child: Text(t, style: const TextStyle(fontSize: 13)))).toList(),
                onChanged: (v) { setState(() { _selectedTechnician = v ?? ''; _updateSelectedUserPhone(); }); },
                validator: (v) { if (_selectedTaskType != 'شراء اشتراك' && (v == null || v.isEmpty)) return 'يجب اختيار فني'; return null; },
              ),
            ),
            if (_currentSelectedPhone.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  border: Border.all(color: Colors.green.shade300),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(children: [
                  const Icon(Icons.phone, size: 16, color: Colors.green),
                  const SizedBox(width: 8),
                  Text('رقم هاتف الفني: $_currentSelectedPhone',
                      style:
                          const TextStyle(fontSize: 12, color: Colors.green)),
                ]),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCustomerSection() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.blue.shade50.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.blue.shade200, width: 1.2),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 4, offset: const Offset(0, 2))],
      ),
      padding: EdgeInsets.symmetric(horizontal: MediaQuery.of(context).size.width < 420 ? 8 : 12, vertical: MediaQuery.of(context).size.width < 420 ? 6 : 10),
      child: Padding(
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('معلومات العميل',
                style: TextStyle(fontSize: MediaQuery.of(context).size.width < 420 ? 12 : 15, fontWeight: FontWeight.bold)),
            SizedBox(height: _isNarrow ? 3 : 6),
            _adaptiveRow(
              TextFormField(
                controller: _usernameController,
                decoration: InputDecoration(
                    labelText: 'اسم العميل *', border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), isDense: true, filled: true, fillColor: Colors.white),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'يجب إدخال اسم العميل' : null,
              ),
              TextFormField(
                controller: _phoneController,
                decoration: InputDecoration(
                    labelText: 'رقم الهاتف *', border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), isDense: true, filled: true, fillColor: Colors.white),
                keyboardType: TextInputType.phone,
                validator: (v) => (v == null || v.trim().isEmpty) ? 'يجب إدخال رقم الهاتف' : null,
              ),
            ),
            SizedBox(height: _isNarrow ? 3 : 6),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _locationController,
                    decoration: InputDecoration(
                        labelText: 'الموقع *', border: OutlineInputBorder()),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'يجب إدخال الموقع' : null,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _fetchDeviceLocation,
                  icon: const Icon(Icons.my_location_rounded),
                  tooltip: 'تحديد الموقع من الجهاز',
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.blue.withOpacity(0.1),
                    foregroundColor: Colors.blue,
                    padding: const EdgeInsets.all(12),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTechnicalSection() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.blue.shade50.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.blue.shade200, width: 1.2),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 4, offset: const Offset(0, 2))],
      ),
      padding: EdgeInsets.symmetric(horizontal: MediaQuery.of(context).size.width < 420 ? 8 : 12, vertical: MediaQuery.of(context).size.width < 420 ? 6 : 10),
      child: Padding(
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('المعلومات الفنية',
                style: TextStyle(fontSize: MediaQuery.of(context).size.width < 420 ? 12 : 15, fontWeight: FontWeight.bold)),
            SizedBox(height: _isNarrow ? 3 : 6),
            _adaptiveRow(
              // FBG — مربع بحث مع تصفية تلقائية
              _fbgOptions.isNotEmpty
                  ? Autocomplete<String>(
                      optionsBuilder: (textEditingValue) {
                        if (textEditingValue.text.isEmpty) return _fbgOptions.toSet();
                        return _fbgOptions.toSet().where((f) =>
                            f.toLowerCase().contains(textEditingValue.text.toLowerCase()));
                      },
                      initialValue: TextEditingValue(text: _fbgController.text),
                      onSelected: (v) => setState(() => _fbgController.text = v),
                      fieldViewBuilder: (ctx, controller, focusNode, onSubmitted) {
                        return TextFormField(
                          controller: controller,
                          focusNode: focusNode,
                          decoration: InputDecoration(
                            labelText: 'FBG *',
                            hintText: 'ابحث عن FBG...',
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            isDense: true, filled: true, fillColor: Colors.white,
                            prefixIcon: const Icon(Icons.search, size: 18),
                            suffixIcon: controller.text.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear, size: 16),
                                    onPressed: () { controller.clear(); setState(() => _fbgController.text = ''); },
                                  )
                                : null,
                          ),
                          onChanged: (v) => _fbgController.text = v,
                          validator: (_) => _fbgController.text.trim().isEmpty ? 'يجب إدخال FBG' : null,
                        );
                      },
                      optionsViewBuilder: (ctx, onSelected, options) {
                        return Align(
                          alignment: Alignment.topRight,
                          child: Material(
                            elevation: 4,
                            borderRadius: BorderRadius.circular(8),
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxHeight: 200),
                              child: ListView.builder(
                                padding: EdgeInsets.zero,
                                shrinkWrap: true,
                                itemCount: options.length,
                                itemBuilder: (ctx, i) {
                                  final option = options.elementAt(i);
                                  return ListTile(
                                    dense: true,
                                    title: Text(option, style: const TextStyle(fontSize: 13)),
                                    onTap: () => onSelected(option),
                                  );
                                },
                              ),
                            ),
                          ),
                        );
                      },
                    )
                  : TextFormField(
                      controller: _fbgController,
                      decoration: InputDecoration(labelText: 'FBG *', hintText: 'أدخل FBG...', border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), isDense: true, filled: true, fillColor: Colors.white),
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'يجب إدخال FBG' : null,
                    ),
              TextFormField(
                controller: _fatController,
                decoration: InputDecoration(labelText: 'FAT *', border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), isDense: true, filled: true, fillColor: Colors.white),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'يجب إدخال FAT' : null,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSubscriptionSection() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.blue.shade50.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.blue.shade200, width: 1.2),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 4, offset: const Offset(0, 2))],
      ),
      padding: EdgeInsets.symmetric(horizontal: MediaQuery.of(context).size.width < 420 ? 8 : 12, vertical: MediaQuery.of(context).size.width < 420 ? 6 : 10),
      child: Padding(
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.subscriptions,
                  color: Colors.purple.shade700, size: 20),
              const SizedBox(width: 8),
              Text('معلومات الاشتراك',
                  style: TextStyle(fontSize: MediaQuery.of(context).size.width < 420 ? 12 : 15, fontWeight: FontWeight.bold)),
            ]),
            SizedBox(height: _isNarrow ? 3 : 6),
            _adaptiveRow(
              DropdownButtonFormField<String>(
                decoration: InputDecoration(
                  labelText: 'نوع الخدمة *', border: const OutlineInputBorder(), isDense: true,
                  prefixIcon: Icon(Icons.speed, color: Colors.green.shade600, size: 18),
                ),
                value: _selectedServiceType.isEmpty ? null : _selectedServiceType,
                items: _serviceTypes.map((s) => DropdownMenuItem(value: s, child: Text(s, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)))).toList(),
                onChanged: (v) => setState(() => _selectedServiceType = v ?? ''),
                validator: (v) => (_selectedTaskType == 'شراء اشتراك' && (v == null || v.isEmpty)) ? 'يجب اختيار نوع الخدمة' : null,
              ),
              DropdownButtonFormField<String>(
                decoration: InputDecoration(
                  labelText: 'مدة الالتزام *', border: const OutlineInputBorder(), isDense: true,
                  prefixIcon: Icon(Icons.schedule, color: Colors.blue.shade600, size: 18),
                ),
                value: _selectedSubscriptionDuration.isEmpty ? null : _selectedSubscriptionDuration,
                items: _subscriptionDurations.map((d) => DropdownMenuItem(value: d, child: Text(d, style: const TextStyle(fontSize: 13)))).toList(),
                onChanged: (v) => setState(() => _selectedSubscriptionDuration = v ?? ''),
                validator: (v) => (_selectedTaskType == 'شراء اشتراك' && (v == null || v.isEmpty)) ? 'يجب اختيار مدة الالتزام' : null,
              ),
            ),
            SizedBox(height: _isNarrow ? 3 : 6),
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
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              validator: (v) {
                if (_selectedTaskType == 'شراء اشتراك') {
                  if (v == null || v.trim().isEmpty) return 'يجب إدخال المبلغ';
                  final amount = int.tryParse(v.trim());
                  if (amount == null || amount <= 0) return 'مبلغ غير صحيح';
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
    return Container(
      decoration: BoxDecoration(
        color: Colors.blue.shade50.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.blue.shade200, width: 1.2),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 4, offset: const Offset(0, 2))],
      ),
      padding: EdgeInsets.symmetric(horizontal: MediaQuery.of(context).size.width < 420 ? 8 : 12, vertical: MediaQuery.of(context).size.width < 420 ? 6 : 10),
      child: Padding(
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('معلومات إضافية',
                style: TextStyle(fontSize: MediaQuery.of(context).size.width < 420 ? 12 : 15, fontWeight: FontWeight.bold)),
            SizedBox(height: _isNarrow ? 3 : 6),
            DropdownButtonFormField<String>(
              decoration: InputDecoration(
                  labelText: 'الأولوية *', border: OutlineInputBorder()),
              value: _selectedPriority.isEmpty ? null : _selectedPriority,
              items: _priorities
                  .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                  .toList(),
              onChanged: (v) =>
                  setState(() => _selectedPriority = v ?? 'متوسط'),
              validator: (v) =>
                  (v == null || v.isEmpty) ? 'يجب اختيار الأولوية' : null,
            ),
            SizedBox(height: _isNarrow ? 3 : 6),
            TextFormField(
              controller: _notesController,
              decoration: InputDecoration(
                  labelText: 'الملاحظات', border: OutlineInputBorder()),
              maxLines: 3,
            ),
            SizedBox(height: _isNarrow ? 3 : 6),
            TextFormField(
              controller: _summaryController,
              decoration: InputDecoration(
                  labelText: 'ملخص المهمة', border: OutlineInputBorder()),
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
          style: OutlinedButton.styleFrom(
            padding: EdgeInsets.symmetric(horizontal: _isNarrow ? 12 : 16, vertical: _isNarrow ? 6 : 10),
            textStyle: TextStyle(fontSize: _isNarrow ? 12 : 14),
          ),
          child: const Text('إلغاء'),
        ),
        SizedBox(width: _isNarrow ? 6 : 16),
        ElevatedButton.icon(
          onPressed: _isLoading ? null : _createTask,
          style: ElevatedButton.styleFrom(
            padding: EdgeInsets.symmetric(horizontal: _isNarrow ? 12 : 16, vertical: _isNarrow ? 6 : 10),
            textStyle: TextStyle(fontSize: _isNarrow ? 12 : 14),
          ),
          icon: _isLoading
              ? SizedBox(
                  width: _isNarrow ? 14 : 18,
                  height: _isNarrow ? 14 : 18,
                  child: const CircularProgressIndicator(strokeWidth: 2))
              : Icon(Icons.save, size: _isNarrow ? 16 : 20),
          label: const Text('حفظ المهمة'),
        ),
      ],
    );
  }

  /// Row على Desktop، Column على الهاتف — لمنع التداخل
  bool get _isNarrow => MediaQuery.of(context).size.width < 500;

  Widget _adaptiveRow(Widget child1, Widget child2, {double? gap}) {
    final g = gap ?? (_isNarrow ? 4 : 8);
    if (_isNarrow) {
      return Column(children: [child1, SizedBox(height: g), child2]);
    }
    return Row(children: [
      Expanded(child: child1),
      SizedBox(width: g),
      Expanded(child: child2),
    ]);
  }
}
