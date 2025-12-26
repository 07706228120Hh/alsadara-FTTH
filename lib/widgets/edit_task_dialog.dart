import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'package:googleapis/sheets/v4.dart' as sheets;
import 'package:googleapis_auth/auth_io.dart';
import '../models/task.dart';
import '../services/google_sheets_service.dart';

/// نافذة تعديل المهمة الشاملة - جميع الحقول قابلة للتعديل
class EditTaskDialog extends StatefulWidget {
  final Task task;
  final Function(Task) onTaskUpdated;

  const EditTaskDialog({
    super.key,
    required this.task,
    required this.onTaskUpdated,
  });

  @override
  State<EditTaskDialog> createState() => _EditTaskDialogState();
}

class _EditTaskDialogState extends State<EditTaskDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _titleController;
  late TextEditingController _usernameController;
  late TextEditingController _phoneController;
  late TextEditingController _fatController;
  late TextEditingController _locationController;
  late TextEditingController _notesController;
  late TextEditingController _summaryController;
  late TextEditingController _amountController;

  String _selectedStatus = '';
  String _selectedPriority = '';
  String _selectedDepartment = '';
  String _selectedLeader = '';
  String _selectedTechnician = '';
  String _selectedFBG = '';
  bool _isLoading = false;
  bool _isDataLoading = true;

  final List<String> _statuses = ['مفتوحة', 'قيد التنفيذ', 'مكتملة', 'ملغية'];
  final List<String> _priorities = ['منخفض', 'متوسط', 'عالي', 'عاجل'];

  // قوائم البيانات من Google Sheets
  List<String> _departments = [];
  List<String> _leaders = [];
  List<String> _technicians = [];
  List<String> _fbgOptions = [];

  // متغيرات Google Sheets API
  sheets.SheetsApi? _sheetsApi;
  AuthClient? _client;
  final String spreadsheetId = '1MGY8UhtHaUiRaUKbohEi3a74jgEh7NeOuTEHBQ83KZc';

  @override
  void initState() {
    super.initState();
    _initializeControllers();
    _fetchDataFromGoogleSheets();
  }

  void _initializeControllers() {
    _titleController = TextEditingController(text: widget.task.title);
    _usernameController = TextEditingController(text: widget.task.username);
    _phoneController = TextEditingController(text: widget.task.phone);
    _fatController = TextEditingController(text: widget.task.fat);
    _locationController = TextEditingController(text: widget.task.location);
    _notesController = TextEditingController(text: widget.task.notes);
    _summaryController = TextEditingController(text: widget.task.summary);
    _amountController = TextEditingController(text: widget.task.amount);

    _selectedStatus = widget.task.status;
    _selectedPriority = widget.task.priority;
    _selectedDepartment = widget.task.department;
    _selectedLeader = widget.task.leader;
    _selectedTechnician = widget.task.technician;
    _selectedFBG = widget.task.fbg;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _usernameController.dispose();
    _phoneController.dispose();
    _fatController.dispose();
    _locationController.dispose();
    _notesController.dispose();
    _summaryController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _fetchDataFromGoogleSheets() async {
    try {
      if (!mounted) return; // فحص mounted قبل بدء العملية
      setState(() => _isDataLoading = true);

      // تهيئة Google Sheets API
      await _initializeSheetsAPI();

      // جلب جميع البيانات المطلوبة
      await Future.wait([
        _fetchDepartments(),
        _fetchUsers(),
        _fetchFBGOptions(),
      ]);

      if (mounted) {
        // فحص mounted قبل تحديث الحالة
        setState(() => _isDataLoading = false);
      }
    } catch (e) {
      if (mounted) {
        // فحص mounted قبل تحديث الحالة
        setState(() => _isDataLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في تحميل البيانات: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _initializeSheetsAPI() async {
    if (_sheetsApi != null) return;

    try {
      final jsonString =
          await rootBundle.loadString('assets/service_account.json');
      final accountCredentials =
          ServiceAccountCredentials.fromJson(jsonDecode(jsonString));
      final scopes = [sheets.SheetsApi.spreadsheetsScope];
      _client = await clientViaServiceAccount(accountCredentials, scopes);
      _sheetsApi = sheets.SheetsApi(_client!);
    } catch (e) {
      throw 'فشل في تهيئة Google Sheets API: $e';
    }
  }

  Future<void> _fetchDepartments() async {
    if (_sheetsApi == null) return;

    try {
      const possibleALKSMRanges = [
        'ALKSM!A2:K',
        'ALKSM!A1:K',
        'الاقسام!A2:K',
        'اقسام!A2:K',
        'Departments!A2:K',
        'Sheet3!A2:K'
      ];

      sheets.ValueRange? response;

      for (String range in possibleALKSMRanges) {
        try {
          response =
              await _sheetsApi!.spreadsheets.values.get(spreadsheetId, range);
          if (response.values != null && response.values!.isNotEmpty) {
            break;
          }
        } catch (e) {
          continue;
        }
      }

      if (response != null &&
          response.values != null &&
          response.values!.isNotEmpty) {
        Set<String> departmentsSet = {};

        for (var row in response.values!) {
          if (row.isNotEmpty) {
            final department = row[0]?.toString().trim() ?? '';
            if (department.isNotEmpty &&
                !department.toLowerCase().contains('اقسام') &&
                !department.toLowerCase().contains('departments') &&
                !department.toLowerCase().contains('المهمه')) {
              departmentsSet.add(department);
            }
          }
        }

        if (mounted) {
          // فحص mounted قبل تحديث الحالة
          setState(() {
            _departments = departmentsSet.toList();
            // التأكد من أن القسم الحالي موجود في القائمة
            if (!_departments.contains(_selectedDepartment) &&
                _departments.isNotEmpty) {
              _departments.add(_selectedDepartment);
            }
          });
        }
      } else {
        // قيم افتراضية في حالة فشل الجلب
        if (mounted) {
          // فحص mounted قبل تحديث الحالة
          setState(() {
            _departments = [
              'الحسابات',
              'الفنيين',
              'الوكلاء',
              'الاتصالات',
              'اللحام',
              'الصيانة'
            ];
            if (!_departments.contains(_selectedDepartment)) {
              _departments.add(_selectedDepartment);
            }
          });
        }
      }
    } catch (e) {
      print('خطأ في جلب الأقسام: $e');
      if (mounted) {
        // فحص mounted قبل تحديث الحالة
        setState(() {
          _departments = [
            'الحسابات',
            'الفنيين',
            'الوكلاء',
            'الاتصالات',
            'اللحام',
            'الصيانة'
          ];
          if (!_departments.contains(_selectedDepartment)) {
            _departments.add(_selectedDepartment);
          }
        });
      }
    }
  }

  Future<void> _fetchUsers() async {
    if (_sheetsApi == null) return;

    try {
      const possibleUsersRanges = [
        'المستخدمين!A2:H',
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
          if (response.values != null && response.values!.isNotEmpty) {
            break;
          }
        } catch (e) {
          continue;
        }
      }

      List<String> technicians = [];
      List<String> leaders = [];

      if (response != null &&
          response.values != null &&
          response.values!.isNotEmpty) {
        for (var row in response.values!) {
          if (row.length >= 4) {
            final username = row[0]?.toString().trim() ?? '';
            final role = row[2]?.toString().trim() ?? '';

            if (username.isNotEmpty) {
              if (role == 'فني') {
                technicians.add(username);
              } else if (role == 'ليدر') {
                leaders.add(username);
              }
            }
          }
        }
      }

      if (mounted) {
        // فحص mounted قبل تحديث الحالة
        setState(() {
          _technicians = technicians;
          _leaders = leaders;

          // التأكد من أن القيم الحالية موجودة في القوائم
          if (!_technicians.contains(_selectedTechnician) &&
              _selectedTechnician.isNotEmpty) {
            _technicians.add(_selectedTechnician);
          }
          if (!_leaders.contains(_selectedLeader) &&
              _selectedLeader.isNotEmpty) {
            _leaders.add(_selectedLeader);
          }
        });
      }
    } catch (e) {
      print('خطأ في جلب المستخدمين: $e');
      // الحفاظ على القيم الحالية في حالة الخطأ
      if (mounted) {
        // فحص mounted قبل تحديث الحالة
        setState(() {
          _technicians =
              _selectedTechnician.isNotEmpty ? [_selectedTechnician] : [];
          _leaders = _selectedLeader.isNotEmpty ? [_selectedLeader] : [];
        });
      }
    }
  }

  Future<void> _fetchFBGOptions() async {
    if (_sheetsApi == null) return;

    try {
      const possibleFBGRanges = [
        'Sheet1!A:A',
        'Sheet1!A2:A1000',
        'Sheet1!A1:A1000',
        'Sheet1!A2:A',
        'FBG!A:A',
        'DataSheet!A:A',
      ];

      sheets.ValueRange? response;

      for (String range in possibleFBGRanges) {
        try {
          response =
              await _sheetsApi!.spreadsheets.values.get(spreadsheetId, range);
          if (response.values != null && response.values!.isNotEmpty) {
            break;
          }
        } catch (e) {
          continue;
        }
      }

      if (response != null &&
          response.values != null &&
          response.values!.isNotEmpty) {
        List<String> fbgOptions = [];

        for (var row in response.values!) {
          if (row.isNotEmpty && row[0] != null) {
            final fbgValue = row[0].toString().trim();

            if (fbgValue.isNotEmpty &&
                fbgValue.toLowerCase() != 'fbg' &&
                !fbgValue.toLowerCase().contains('code') &&
                !fbgValue.toLowerCase().contains('عنوان') &&
                !fbgValue.toLowerCase().contains('header') &&
                fbgValue.length > 2) {
              fbgOptions.add(fbgValue);
            }
          }
        }

        if (mounted) {
          // فحص mounted قبل تحديث الحالة
          setState(() {
            _fbgOptions = fbgOptions;
            // التأكد من أن القيمة الحالية موجودة في القائمة
            if (!_fbgOptions.contains(_selectedFBG) &&
                _selectedFBG.isNotEmpty) {
              _fbgOptions.add(_selectedFBG);
            }
          });
        }
      } else {
        // الحفاظ على القيمة الحالية في حالة فشل الجلب
        if (mounted) {
          // فحص mounted قبل تحديث الحالة
          setState(() {
            _fbgOptions = _selectedFBG.isNotEmpty ? [_selectedFBG] : [];
          });
        }
      }
    } catch (e) {
      print('خطأ في جلب خيارات FBG: $e');
      if (mounted) {
        // فحص mounted قبل تحديث الحالة
        setState(() {
          _fbgOptions = _selectedFBG.isNotEmpty ? [_selectedFBG] : [];
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: SizedBox(
        width: double.maxFinite,
        height: MediaQuery.of(context).size.height * 0.9,
        child: Column(
          children: [
            // شريط العنوان
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue.shade700,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(12),
                  topRight: Radius.circular(12),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.edit, color: Colors.white),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'تعديل المهمة',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: Colors.white),
                  ),
                ],
              ),
            ),

            // محتوى النموذج
            Expanded(
              child: _isDataLoading
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
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          children: [
                            // معلومات المهمة الأساسية
                            _buildSectionTitle('معلومات المهمة الأساسية'),
                            const SizedBox(height: 12),

                            _buildTextFormField(
                              controller: _titleController,
                              label: 'عنوان المهمة',
                              icon: Icons.title,
                              required: true,
                            ),
                            const SizedBox(height: 12),

                            _buildDropdownField(
                              value: _selectedStatus,
                              items: _statuses,
                              label: 'حالة المهمة',
                              icon: Icons.flag,
                              onChanged: (value) =>
                                  setState(() => _selectedStatus = value!),
                            ),
                            const SizedBox(height: 12),

                            _buildDropdownField(
                              value: _selectedPriority,
                              items: _priorities,
                              label: 'أولوية المهمة',
                              icon: Icons.priority_high,
                              onChanged: (value) =>
                                  setState(() => _selectedPriority = value!),
                            ),
                            const SizedBox(height: 20),

                            // معلومات القسم والمسؤولين
                            _buildSectionTitle('معلومات القسم والمسؤولين'),
                            const SizedBox(height: 12),

                            _buildDropdownField(
                              value: _selectedDepartment,
                              items: _departments.isEmpty
                                  ? [_selectedDepartment]
                                  : _departments,
                              label: 'القسم',
                              icon: Icons.business,
                              onChanged: (value) =>
                                  setState(() => _selectedDepartment = value!),
                            ),
                            const SizedBox(height: 12),

                            _buildDropdownField(
                              value: _selectedLeader,
                              items: _leaders.isEmpty
                                  ? [_selectedLeader]
                                  : _leaders,
                              label: 'الليدر المسؤول',
                              icon: Icons.supervisor_account,
                              onChanged: (value) =>
                                  setState(() => _selectedLeader = value!),
                            ),
                            const SizedBox(height: 12),

                            _buildDropdownField(
                              value: _selectedTechnician,
                              items: _technicians.isEmpty
                                  ? [_selectedTechnician]
                                  : _technicians,
                              label: 'الفني المسؤول',
                              icon: Icons.engineering,
                              onChanged: (value) =>
                                  setState(() => _selectedTechnician = value!),
                            ),
                            const SizedBox(height: 20),

                            // معلومات العميل
                            _buildSectionTitle('معلومات العميل'),
                            const SizedBox(height: 12),

                            _buildTextFormField(
                              controller: _usernameController,
                              label: 'اسم العميل',
                              icon: Icons.person,
                              required: true,
                            ),
                            const SizedBox(height: 12),

                            _buildTextFormField(
                              controller: _phoneController,
                              label: 'رقم الهاتف',
                              icon: Icons.phone,
                              keyboardType: TextInputType.phone,
                              required: true,
                            ),
                            const SizedBox(height: 12),

                            _buildTextFormField(
                              controller: _amountController,
                              label: 'المبلغ',
                              icon: Icons.attach_money,
                              keyboardType: TextInputType.number,
                            ),
                            const SizedBox(height: 20),

                            // المعلومات التقنية
                            _buildSectionTitle('المعلومات التقنية'),
                            const SizedBox(height: 12),

                            _buildDropdownField(
                              value: _selectedFBG,
                              items: _fbgOptions.isEmpty
                                  ? [_selectedFBG]
                                  : _fbgOptions,
                              label: 'FBG',
                              icon: Icons.router,
                              onChanged: (value) =>
                                  setState(() => _selectedFBG = value!),
                            ),
                            const SizedBox(height: 12),

                            _buildTextFormField(
                              controller: _fatController,
                              label: 'FAT',
                              icon: Icons.hub,
                              required: true,
                            ),
                            const SizedBox(height: 12),

                            _buildTextFormField(
                              controller: _locationController,
                              label: 'الموقع',
                              icon: Icons.location_on,
                              required: true,
                            ),
                            const SizedBox(height: 20),

                            // الملاحظات والملخص
                            _buildSectionTitle('الملاحظات والتفاصيل'),
                            const SizedBox(height: 12),

                            _buildTextFormField(
                              controller: _notesController,
                              label: 'ملاحظات إضافية',
                              icon: Icons.note,
                              maxLines: 3,
                            ),
                            const SizedBox(height: 12),

                            _buildTextFormField(
                              controller: _summaryController,
                              label: 'ملخص المهمة (اختياري)',
                              icon: Icons.summarize,
                              maxLines: 3,
                              required: false,
                            ),
                          ],
                        ),
                      ),
                    ),
            ),

            // أزرار الإجراءات
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(12),
                  bottomRight: Radius.circular(12),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed:
                          _isLoading ? null : () => Navigator.pop(context),
                      child: const Text('إلغاء'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _saveChanges,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue.shade700,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('حفظ التغييرات'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: Colors.blue.shade800,
        ),
      ),
    );
  }

  Widget _buildTextFormField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool required = false,
    TextInputType keyboardType = TextInputType.text,
    int maxLines = 1,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        filled: true,
        fillColor: Colors.grey.shade50,
      ),
      validator: required
          ? (value) {
              if (value == null || value.trim().isEmpty) {
                return 'هذا الحقل مطلوب';
              }
              return null;
            }
          : null,
    );
  }

  Widget _buildDropdownField({
    required String value,
    required List<String> items,
    required String label,
    required IconData icon,
    required Function(String?) onChanged,
  }) {
    // التأكد من أن القيمة موجودة في القائمة
    String selectedValue = items.contains(value) && value.isNotEmpty
        ? value
        : (items.isNotEmpty ? items.first : '');

    return DropdownButtonFormField<String>(
      initialValue: selectedValue.isNotEmpty ? selectedValue : null,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        filled: true,
        fillColor: Colors.grey.shade50,
      ),
      items: items.where((item) => item.isNotEmpty).map((item) {
        return DropdownMenuItem(
          value: item,
          child: Text(item),
        );
      }).toList(),
      onChanged: onChanged,
      validator: (value) {
        if (value == null || value.isEmpty) {
          return 'يرجى اختيار $label';
        }
        return null;
      },
    );
  }

  Future<void> _saveChanges() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _isLoading = true);

    try {
      // إنشاء مهمة محدثة
      final updatedTask = widget.task.copyWith(
        title: _titleController.text.trim(),
        status: _selectedStatus,
        department: _selectedDepartment,
        leader: _selectedLeader,
        technician: _selectedTechnician,
        username: _usernameController.text.trim(),
        phone: _phoneController.text.trim(),
        fbg: _selectedFBG,
        fat: _fatController.text.trim(),
        location: _locationController.text.trim(),
        notes: _notesController.text.trim(),
        summary: _summaryController.text.trim(),
        priority: _selectedPriority,
        amount: _amountController.text.trim(),
        closedAt: (_selectedStatus == 'مكتملة' || _selectedStatus == 'ملغية')
            ? DateTime.now()
            : null,
      );

      // حفظ التغييرات في Google Sheets
      await GoogleSheetsService.updateTaskStatus(updatedTask);

      // إشعار الوالد بالتحديث
      widget.onTaskUpdated(updatedTask);

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم تحديث المهمة بنجاح'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في تحديث المهمة: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }
}
