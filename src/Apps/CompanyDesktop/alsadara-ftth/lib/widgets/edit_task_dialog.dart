import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/task.dart';
import '../services/task_api_service.dart';
import '../services/departments_data_service.dart';

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

  // قوائم البيانات من API
  List<String> _departments = [];
  List<String> _leaders = [];
  List<String> _technicians = [];
  List<String> _fbgOptions = [];

  @override
  void initState() {
    super.initState();
    _initializeControllers();
    _fetchDataFromApi();
  }

  void _initializeControllers() {
    _titleController = TextEditingController(text: widget.task.title);
    _usernameController = TextEditingController(text: widget.task.username);
    _phoneController = TextEditingController(text: widget.task.phone);
    _fatController = TextEditingController(text: widget.task.fat);
    _locationController = TextEditingController(text: widget.task.location);
    _notesController = TextEditingController(text: widget.task.notes);
    _summaryController = TextEditingController(text: widget.task.summary);
    _amountController = TextEditingController(text: _ThousandsSeparatorFormatter.format(widget.task.amount));

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

  Future<void> _fetchDataFromApi() async {
    try {
      if (!mounted) return;
      setState(() => _isDataLoading = true);

      // جلب بيانات الأقسام والخيارات من API
      final lookupResult = await TaskApiService.instance.getTaskLookupData();
      final lookupData = lookupResult['data'] ?? lookupResult;

      // استخراج الأقسام
      final List<dynamic> deptRaw = lookupData['departments'] ?? lookupData['Departments'] ?? [];
      final List<dynamic> departments = deptRaw.map((d) => d is Map ? (d['nameAr'] ?? d['name'] ?? d).toString() : d.toString()).toList();

      // استخراج خيارات FBG
      final List<dynamic> fbgOptions =
          lookupData['fbgOptions'] ?? lookupData['FbgOptions'] ?? [];

      // جلب الموظفين (فنيين وليدرز)
      final staffData = await TaskApiService.instance.getTaskStaff();
      final staffInner = staffData['data'] ?? staffData;

      List<String> technicians = [];
      List<String> leaders = [];

      // قراءة الليدرز من data.leaders
      final List<dynamic> leaderList = staffInner['leaders'] ?? staffInner['Leaders'] ?? [];
      for (var l in leaderList) {
        final name = (l['Name'] ?? l['name'] ?? l['FullName'] ?? '').toString().trim();
        if (name.isNotEmpty && !leaders.contains(name)) leaders.add(name);
      }

      // قراءة كل موظفي القسم من allStaff (فنيين + قادة + موظفين)
      final List<dynamic> allStaff = staffInner['allStaff'] ?? staffInner['staff'] ?? staffInner['Staff'] ?? [];
      for (var staff in allStaff) {
        final name = (staff['Name'] ?? staff['FullName'] ?? staff['fullName'] ?? '').toString().trim();
        if (name.isNotEmpty && !technicians.contains(name)) technicians.add(name);
      }

      // fallback: إذا allStaff فارغة نستخدم technicians
      if (technicians.isEmpty) {
        final List<dynamic> techList = staffInner['technicians'] ?? staffInner['Technicians'] ?? [];
        for (var t in techList) {
          final name = (t['Name'] ?? t['name'] ?? t['FullName'] ?? '').toString().trim();
          if (name.isNotEmpty && !technicians.contains(name)) technicians.add(name);
        }
      }

      if (mounted) {
        setState(() {
          _departments = departments.map((d) => d.toString()).toList();
          _fbgOptions = fbgOptions.map((f) => f.toString()).toList();
          _technicians = technicians;
          _leaders = leaders;

          // التأكد من أن القيم الحالية موجودة في القوائم
          if (!_departments.contains(_selectedDepartment) &&
              _selectedDepartment.isNotEmpty) {
            _departments.add(_selectedDepartment);
          }
          if (!_technicians.contains(_selectedTechnician) &&
              _selectedTechnician.isNotEmpty) {
            _technicians.add(_selectedTechnician);
          }
          if (!_leaders.contains(_selectedLeader) &&
              _selectedLeader.isNotEmpty) {
            _leaders.add(_selectedLeader);
          }
          if (!_fbgOptions.contains(_selectedFBG) && _selectedFBG.isNotEmpty) {
            _fbgOptions.add(_selectedFBG);
          }

          _isDataLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isDataLoading = false;
          // جلب الأقسام من الخدمة المركزية
          _departments = DepartmentsDataService.instance.isLoaded
              ? List<String>.from(
                  DepartmentsDataService.instance.departmentNames)
              : [
                  'الحسابات',
                  'الفنيين',
                  'الوكلاء',
                  'الاتصالات',
                  'اللحام',
                  'الصيانة'
                ];
          if (!_departments.contains(_selectedDepartment) &&
              _selectedDepartment.isNotEmpty) {
            _departments.add(_selectedDepartment);
          }
          _technicians =
              _selectedTechnician.isNotEmpty ? [_selectedTechnician] : [];
          _leaders = _selectedLeader.isNotEmpty ? [_selectedLeader] : [];
          _fbgOptions = _selectedFBG.isNotEmpty ? [_selectedFBG] : [];
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في تحميل البيانات'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenW = MediaQuery.of(context).size.width;
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
    final availableHeight = MediaQuery.of(context).size.height - keyboardHeight;
    final isMobile = screenW < 600;
    return Dialog(
      insetPadding: EdgeInsets.symmetric(horizontal: isMobile ? 10 : 16, vertical: isMobile ? 10 : 16),
      child: SizedBox(
        width: isMobile ? screenW - 20 : 600,
        height: availableHeight * 0.9,
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

                            _buildTaskTypeDropdown(),
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

                            _buildSearchableTechnicianField(),
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
                              inputFormatters: [_ThousandsSeparatorFormatter()],
                              suffixText: 'دينار',
                              validator: (v) {
                                if (v != null && v.isNotEmpty) {
                                  final amount = int.tryParse(v.replaceAll(',', '').trim());
                                  if (amount != null && amount < 1000) return 'المبلغ يجب أن يكون 1,000 أو أكثر';
                                }
                                return null;
                              },
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
                        padding: const EdgeInsets.symmetric(vertical: 14),
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
    List<TextInputFormatter>? inputFormatters,
    String? suffixText,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      inputFormatters: inputFormatters,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        suffixText: suffixText,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        filled: true,
        fillColor: Colors.grey.shade50,
      ),
      validator: validator ?? (required
          ? (value) {
              if (value == null || value.trim().isEmpty) {
                return 'هذا الحقل مطلوب';
              }
              return null;
            }
          : null),
    );
  }

  // أنواع المهام المتاحة
  static const _taskTypes = [
    'تركيب',
    'إصلاح',
    'صيانة دورية',
    'فحص',
    'استبدال',
    'طوارئ',
    'استشارة',
    'شراء اشتراك',
    'تجديد اشتراك',
    'استحصال مبلغ',
    'تحصيل مبلغ تجديد',
    'سحب ديلفري',
  ];

  Widget _buildTaskTypeDropdown() {
    final items = [..._taskTypes];
    final current = _titleController.text.trim();
    if (current.isNotEmpty && !items.contains(current)) {
      items.insert(0, current);
    }
    return DropdownButtonFormField<String>(
      value: items.contains(current) ? current : null,
      decoration: InputDecoration(
        labelText: 'نوع المهمة',
        prefixIcon: const Icon(Icons.category),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        filled: true,
        fillColor: Colors.grey.shade50,
      ),
      items: items.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
      onChanged: (v) {
        if (v != null) {
          setState(() => _titleController.text = v);
        }
      },
      validator: (v) => (v == null || v.isEmpty) ? 'يرجى اختيار نوع المهمة' : null,
    );
  }

  Widget _buildSearchableTechnicianField() {
    return Autocomplete<String>(
      initialValue: TextEditingValue(text: _selectedTechnician),
      optionsBuilder: (textEditingValue) {
        if (textEditingValue.text.isEmpty) return _technicians;
        return _technicians.where(
          (t) => t.contains(textEditingValue.text),
        );
      },
      fieldViewBuilder: (context, controller, focusNode, onSubmitted) {
        return TextFormField(
          controller: controller,
          focusNode: focusNode,
          decoration: InputDecoration(
            labelText: 'الفني المسؤول',
            prefixIcon: const Icon(Icons.engineering),
            suffixIcon: controller.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear, size: 18),
                    onPressed: () {
                      controller.clear();
                      setState(() => _selectedTechnician = '');
                    },
                  )
                : null,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            filled: true,
            fillColor: Colors.grey.shade50,
            hintText: 'ابحث عن فني...',
          ),
          onChanged: (v) => setState(() => _selectedTechnician = v),
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
        return Align(
          alignment: Alignment.topRight,
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(8),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: 200, maxWidth: MediaQuery.of(context).size.width < 400 ? MediaQuery.of(context).size.width - 40 : 350),
              child: ListView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: options.length,
                itemBuilder: (context, index) {
                  final option = options.elementAt(index);
                  return ListTile(
                    dense: true,
                    leading: const Icon(Icons.person, size: 18),
                    title: Text(option, style: const TextStyle(fontSize: 14)),
                    onTap: () => onSelected(option),
                  );
                },
              ),
            ),
          ),
        );
      },
      onSelected: (value) => setState(() => _selectedTechnician = value),
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
          child: Text(item, overflow: TextOverflow.ellipsis),
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
        amount: _amountController.text.replaceAll(',', '').trim(),
        closedAt: (_selectedStatus == 'مكتملة' || _selectedStatus == 'ملغية')
            ? DateTime.now()
            : null,
      );

      // حفظ التغييرات عبر API — تعديل كامل لكل الحقول
      final apiStatus = Task.mapArabicStatusToApi(updatedTask.status);
      final amountText = _amountController.text.replaceAll(',', '').trim();
      final parsedAmount = double.tryParse(amountText);
      final taskId = updatedTask.guid.isNotEmpty ? updatedTask.guid : updatedTask.id;
      final result = await TaskApiService.instance.updateTask(
        taskId,
        status: apiStatus,
        department: updatedTask.department,
        leader: updatedTask.leader,
        technician: updatedTask.technician,
        customerName: updatedTask.username,
        customerPhone: updatedTask.phone,
        fbg: updatedTask.fbg,
        fat: updatedTask.fat,
        location: updatedTask.location,
        notes: updatedTask.notes,
        summary: updatedTask.summary,
        priority: updatedTask.priority,
        amount: parsedAmount,
      );

      if (result['success'] == true) {
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
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result['message']?.toString() ?? 'فشل تحديث المهمة'),
              backgroundColor: Colors.red,
            ),
          );
        }
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

/// فورماتر يضيف فواصل المراتب (1,000,000) ويمنع الأرقام العشرية
class _ThousandsSeparatorFormatter extends TextInputFormatter {
  /// تنسيق نص عادي بفواصل المراتب
  static String format(String value) {
    final digits = value.replaceAll(RegExp(r'[^\d]'), '');
    if (digits.isEmpty) return '';
    final buffer = StringBuffer();
    final len = digits.length;
    for (int i = 0; i < len; i++) {
      if (i > 0 && (len - i) % 3 == 0) buffer.write(',');
      buffer.write(digits[i]);
    }
    return buffer.toString();
  }

  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final digitsOnly = newValue.text.replaceAll(RegExp(r'[^\d]'), '');
    if (digitsOnly.isEmpty) {
      return const TextEditingValue(
        text: '',
        selection: TextSelection.collapsed(offset: 0),
      );
    }
    final formatted = format(digitsOnly);
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}
