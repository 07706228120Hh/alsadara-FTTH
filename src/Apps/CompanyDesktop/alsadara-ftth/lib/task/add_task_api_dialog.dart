import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
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
    _selectedTechnician = widget.currentUsername;

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

    // عند شراء اشتراك: القسم = الحسابات تلقائياً + الفني = المستخدم الحالي
    if (_selectedTaskType == 'شراء اشتراك') {
      _selectedDepartment = 'الحسابات';
      _selectedTechnician = widget.currentUsername;
    }

    _loadDataFromApi();
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
          });
        }
      }

      // موظفين
      _parseStaffData(staffResult);
    } catch (e) {
      print('❌ خطأ في تحميل البيانات');
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

          // عند شراء اشتراك: أضف اسم الفني الحالي للقائمة إن لم يكن موجوداً
          if (_selectedTaskType == 'شراء اشتراك' &&
              widget.currentUsername.isNotEmpty &&
              !_technicians.contains(widget.currentUsername)) {
            _technicians.add(widget.currentUsername);
          }
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
      print('❌ خطأ في جلب الموظفين');
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
        // إرسال إشعار WhatsApp
        await _sendWhatsAppNotification();

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
      print('❌ خطأ في إنشاء المهمة');
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
        print('⚠️ لم يتم العثور على رقم هاتف $recipientType');
        return;
      }

      final message = _buildWhatsAppMessage(recipientType);
      final cleanPhone = _validateAndFormatPhone(targetPhone!);
      if (cleanPhone == null) return;

      await _sendViaWhatsApp(cleanPhone, message);
    } catch (e) {
      print('❌ خطأ في إرسال WhatsApp');
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
      print('❌ خطأ في فتح واتساب');
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
    return Dialog(
      child: Container(
        width: MediaQuery.of(context).size.width * 0.9,
        height: MediaQuery.of(context).size.height * 0.9,
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(children: [
                  Icon(Icons.add_task, color: Colors.blue.shade700),
                  const SizedBox(width: 8),
                  const Text('إضافة مهمة جديدة',
                      style:
                          TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                  const SizedBox(width: 8),
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
                              const SizedBox(height: 16),
                              Text(_errorMessage!,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(color: Colors.red)),
                              const SizedBox(height: 16),
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
    return Form(
      key: _formKey,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildDepartmentSection(),
            const SizedBox(height: 20),
            _buildCustomerSection(),
            const SizedBox(height: 20),
            _buildTechnicalSection(),
            const SizedBox(height: 20),
            if (_selectedTaskType == 'شراء اشتراك') ...[
              _buildSubscriptionSection(),
              const SizedBox(height: 20),
            ],
            _buildAdditionalSection(),
            const SizedBox(height: 30),
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
            const Text('معلومات القسم والفريق',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: DropdownButtonFormField<String>(
                    decoration: const InputDecoration(
                        labelText: 'القسم *', border: OutlineInputBorder()),
                    value: _departments.contains(_selectedDepartment)
                        ? _selectedDepartment
                        : null,
                    items: _departments
                        .map((d) => DropdownMenuItem(value: d, child: Text(d)))
                        .toList(),
                    onChanged: (v) {
                      if (v != null) _onDepartmentChanged(v);
                    },
                    validator: (v) =>
                        (v == null || v.isEmpty) ? 'يجب اختيار القسم' : null,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  flex: 2,
                  child: DropdownButtonFormField<String>(
                    decoration: const InputDecoration(
                        labelText: 'نوع المهمة *',
                        border: OutlineInputBorder()),
                    value: _selectedTaskType.isEmpty ? null : _selectedTaskType,
                    items: _getTaskTypeItems(),
                    onChanged: (v) {
                      setState(() {
                        _selectedTaskType = v ?? '';
                        if (_selectedTaskType == 'شراء اشتراك' &&
                            widget.currentUserRole == 'فني') {
                          _selectedTechnician = widget.currentUsername;
                          _updateSelectedUserPhone();
                        }
                      });
                    },
                    validator: (v) => (v == null || v.isEmpty)
                        ? 'يجب اختيار نوع المهمة'
                        : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    decoration: const InputDecoration(
                        labelText: 'القائد', border: OutlineInputBorder()),
                    value: _leaders.contains(_selectedLeader)
                        ? _selectedLeader
                        : null,
                    items: _leaders
                        .map((l) => DropdownMenuItem(value: l, child: Text(l)))
                        .toList(),
                    onChanged: (v) => setState(() => _selectedLeader = v ?? ''),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    decoration: const InputDecoration(
                        labelText: 'الفني', border: OutlineInputBorder()),
                    value: _technicians.contains(_selectedTechnician)
                        ? _selectedTechnician
                        : null,
                    items: _technicians
                        .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                        .toList(),
                    onChanged: (v) {
                      setState(() {
                        _selectedTechnician = v ?? '';
                        _updateSelectedUserPhone();
                      });
                    },
                    validator: (v) {
                      if (_selectedTaskType != 'شراء اشتراك' &&
                          (v == null || v.isEmpty)) {
                        return 'يجب اختيار فني';
                      }
                      return null;
                    },
                  ),
                ),
              ],
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
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('معلومات العميل',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(
                child: TextFormField(
                  controller: _usernameController,
                  decoration: const InputDecoration(
                      labelText: 'اسم العميل *', border: OutlineInputBorder()),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'يجب إدخال اسم العميل'
                      : null,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: TextFormField(
                  controller: _phoneController,
                  decoration: const InputDecoration(
                      labelText: 'رقم الهاتف *', border: OutlineInputBorder()),
                  keyboardType: TextInputType.phone,
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'يجب إدخال رقم الهاتف'
                      : null,
                ),
              ),
            ]),
            const SizedBox(height: 16),
            TextFormField(
              controller: _locationController,
              decoration: const InputDecoration(
                  labelText: 'الموقع *', border: OutlineInputBorder()),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'يجب إدخال الموقع' : null,
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
            const Text('المعلومات الفنية',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(
                child: _fbgOptions.isNotEmpty
                    ? DropdownButtonFormField<String>(
                        decoration: const InputDecoration(
                            labelText: 'FBG *', border: OutlineInputBorder()),
                        value: _fbgOptions.contains(_fbgController.text.trim())
                            ? _fbgController.text.trim()
                            : null,
                        items: _fbgOptions
                            .toSet()
                            .map((f) =>
                                DropdownMenuItem(value: f, child: Text(f)))
                            .toList(),
                        onChanged: (v) =>
                            setState(() => _fbgController.text = v ?? ''),
                        validator: (v) =>
                            (v == null || v.isEmpty) ? 'يجب اختيار FBG' : null,
                      )
                    : TextFormField(
                        controller: _fbgController,
                        decoration: const InputDecoration(
                            labelText: 'FBG *', border: OutlineInputBorder()),
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'يجب إدخال FBG'
                            : null,
                      ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: TextFormField(
                  controller: _fatController,
                  decoration: const InputDecoration(
                      labelText: 'FAT *', border: OutlineInputBorder()),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'يجب إدخال FAT' : null,
                ),
              ),
            ]),
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
            Row(children: [
              Icon(Icons.subscriptions,
                  color: Colors.purple.shade700, size: 20),
              const SizedBox(width: 8),
              const Text('معلومات الاشتراك',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ]),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  decoration: InputDecoration(
                    labelText: 'نوع الخدمة *',
                    border: const OutlineInputBorder(),
                    prefixIcon: Icon(Icons.speed, color: Colors.green.shade600),
                  ),
                  value: _selectedServiceType.isEmpty
                      ? null
                      : _selectedServiceType,
                  items: _serviceTypes
                      .map((s) => DropdownMenuItem(
                          value: s,
                          child: Row(children: [
                            Text(s,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold)),
                            const SizedBox(width: 8),
                            Text('FIBER',
                                style: TextStyle(
                                    color: Colors.grey.shade600, fontSize: 12)),
                          ])))
                      .toList(),
                  onChanged: (v) =>
                      setState(() => _selectedServiceType = v ?? ''),
                  validator: (v) => (_selectedTaskType == 'شراء اشتراك' &&
                          (v == null || v.isEmpty))
                      ? 'يجب اختيار نوع الخدمة'
                      : null,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: DropdownButtonFormField<String>(
                  decoration: InputDecoration(
                    labelText: 'مدة الالتزام *',
                    border: const OutlineInputBorder(),
                    prefixIcon:
                        Icon(Icons.schedule, color: Colors.blue.shade600),
                  ),
                  value: _selectedSubscriptionDuration.isEmpty
                      ? null
                      : _selectedSubscriptionDuration,
                  items: _subscriptionDurations
                      .map((d) => DropdownMenuItem(value: d, child: Text(d)))
                      .toList(),
                  onChanged: (v) =>
                      setState(() => _selectedSubscriptionDuration = v ?? ''),
                  validator: (v) => (_selectedTaskType == 'شراء اشتراك' &&
                          (v == null || v.isEmpty))
                      ? 'يجب اختيار مدة الالتزام'
                      : null,
                ),
              ),
            ]),
            const SizedBox(height: 16),
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
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('معلومات إضافية',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              decoration: const InputDecoration(
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
            const SizedBox(height: 16),
            TextFormField(
              controller: _notesController,
              decoration: const InputDecoration(
                  labelText: 'الملاحظات', border: OutlineInputBorder()),
              maxLines: 3,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _summaryController,
              decoration: const InputDecoration(
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
          child: const Text('إلغاء'),
        ),
        const SizedBox(width: 16),
        ElevatedButton.icon(
          onPressed: _isLoading ? null : _createTask,
          icon: _isLoading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.save),
          label: const Text('حفظ المهمة'),
        ),
      ],
    );
  }
}
