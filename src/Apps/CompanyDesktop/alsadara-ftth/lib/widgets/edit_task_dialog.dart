import 'package:flutter/material.dart';
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

  Future<void> _fetchDataFromApi() async {
    try {
      if (!mounted) return;
      setState(() => _isDataLoading = true);

      // جلب بيانات الأقسام والخيارات من API
      final lookupData = await TaskApiService.instance.getTaskLookupData();

      // استخراج الأقسام
      final List<dynamic> departments =
          lookupData['departments'] ?? lookupData['Departments'] ?? [];

      // استخراج خيارات FBG
      final List<dynamic> fbgOptions =
          lookupData['fbgOptions'] ?? lookupData['FbgOptions'] ?? [];

      // جلب الموظفين (فنيين وليدرز)
      final staffData = await TaskApiService.instance.getTaskStaff();
      final List<dynamic> staffList =
          staffData['staff'] ?? staffData['Staff'] ?? [];

      List<String> technicians = [];
      List<String> leaders = [];

      for (var staff in staffList) {
        final name =
            (staff['FullName'] ?? staff['fullName'] ?? '').toString().trim();
        final role = (staff['Role'] ?? staff['role'] ?? '').toString();

        if (name.isNotEmpty) {
          // Technician = 12, TechnicalLeader = 13
          if (role == '12' || role == 'Technician' || role == 'فني') {
            technicians.add(name);
          } else if (role == '13' ||
              role == 'TechnicalLeader' ||
              role == 'ليدر') {
            leaders.add(name);
          }
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
            content: Text('خطأ في تحميل البيانات: $e'),
            backgroundColor: Colors.red,
          ),
        );
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

      // حفظ التغييرات عبر API
      final apiStatus = Task.mapArabicStatusToApi(updatedTask.status);
      await TaskApiService.instance
          .updateStatus(updatedTask.id, status: apiStatus);

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
