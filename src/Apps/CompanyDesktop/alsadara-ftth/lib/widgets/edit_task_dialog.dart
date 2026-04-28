import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/task.dart';
import '../services/task_api_service.dart';
import '../services/departments_data_service.dart';
import '../services/vps_auth_service.dart';
import '../inventory/services/inventory_api_service.dart';

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

  // المواد المصروفة
  List<Map<String, dynamic>> _dispensedItems = [];
  bool _isLoadingMaterials = false;
  // مواد جديدة يريد الفني إضافتها
  List<Map<String, dynamic>> _newMaterialRows = [];
  List<Map<String, dynamic>> _availableItems = [];
  List<Map<String, dynamic>> _availableWarehouses = [];

  @override
  void initState() {
    super.initState();
    _initializeControllers();
    _fetchDataFromApi();
    _loadDispensedMaterials();
    _loadInventoryData();
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

                            const SizedBox(height: 20),

                            // المواد المصروفة
                            _buildSectionTitle('المواد المصروفة'),
                            const SizedBox(height: 12),
                            _buildDispensedMaterialsSection(),
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

  // ═══════════════════════════════════════════════════════════
  //  المواد المصروفة
  // ═══════════════════════════════════════════════════════════

  Future<void> _loadDispensedMaterials() async {
    final taskGuid = widget.task.guid;
    if (taskGuid.isEmpty) return;
    setState(() => _isLoadingMaterials = true);
    try {
      final companyId = VpsAuthService.instance.currentCompanyId ?? '';
      final result = await InventoryApiService.instance
          .getDispensingsByServiceRequest(taskGuid, companyId: companyId);
      if (!mounted) return;
      final dispensings = (result['data'] as List<dynamic>?) ?? [];
      final items = <Map<String, dynamic>>[];
      for (final d in dispensings) {
        for (final item in (d['items'] as List<dynamic>?) ?? []) {
          items.add({
            'itemName': item['itemName'] ?? item['inventoryItemName'] ?? '',
            'itemSku': item['itemSku'] ?? item['sku'] ?? '',
            'quantity': item['quantity'] ?? 0,
            'returnedQuantity': item['returnedQuantity'] ?? 0,
            'voucherNumber': d['voucherNumber'] ?? '',
          });
        }
      }
      setState(() {
        _dispensedItems = items;
        _isLoadingMaterials = false;
      });
    } catch (_) {
      if (mounted) setState(() => _isLoadingMaterials = false);
    }
  }

  Future<void> _loadInventoryData() async {
    try {
      final companyId = VpsAuthService.instance.currentCompanyId ?? '';
      if (companyId.isEmpty) return;
      final itemsResult = await InventoryApiService.instance
          .getItems(companyId: companyId, pageSize: 200);
      final warehouseResult = await InventoryApiService.instance
          .getWarehouses(companyId: companyId);
      if (!mounted) return;
      setState(() {
        _availableItems = ((itemsResult['data'] as List<dynamic>?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _availableWarehouses =
            ((warehouseResult['data'] as List<dynamic>?) ?? [])
                .map((e) => Map<String, dynamic>.from(e as Map))
                .toList();
      });
    } catch (_) {}
  }

  Future<void> _submitNewMaterials() async {
    if (_newMaterialRows.isEmpty) return;
    final companyId = VpsAuthService.instance.currentCompanyId ?? '';
    if (companyId.isEmpty) return;
    // نختار أول مستودع متاح كافتراضي
    final warehouseId = _availableWarehouses.isNotEmpty
        ? _availableWarehouses.first['id']?.toString() ?? ''
        : '';
    if (warehouseId.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('لا يوجد مستودع متاح'), backgroundColor: Colors.red),
        );
      }
      return;
    }

    final taskGuid = widget.task.guid;
    // نحضّر البنود
    final items = _newMaterialRows
        .where((r) => (r['itemId'] ?? '').toString().isNotEmpty && (r['quantity'] ?? 0) > 0)
        .map((r) => {
              'inventoryItemId': r['itemId'],
              'quantity': r['quantity'],
            })
        .toList();
    if (items.isEmpty) return;

    try {
      await InventoryApiService.instance.createDispensing(data: {
        'technicianId': widget.task.technicianId,
        'warehouseId': warehouseId,
        'serviceRequestId': taskGuid,
        'type': 0, // Dispensing
        'notes': 'صرف من المهمة #${widget.task.id}',
        'companyId': companyId,
        'items': items,
      });
      if (!mounted) return;
      // نعيد تحميل المواد
      _newMaterialRows.clear();
      await _loadDispensedMaterials();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم إضافة المواد بنجاح'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Widget _buildDispensedMaterialsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // المواد المصروفة سابقاً
        if (_isLoadingMaterials)
          const Center(child: Padding(
            padding: EdgeInsets.all(12),
            child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
          ))
        else if (_dispensedItems.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.orange.shade200),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Icon(Icons.inventory_2, size: 16, color: Colors.orange.shade700),
                    const SizedBox(width: 6),
                    Text('مواد مصروفة سابقاً (${_dispensedItems.length})',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.orange.shade800)),
                  ],
                ),
                const SizedBox(height: 8),
                ..._dispensedItems.map((item) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${item['itemName']}${(item['itemSku'] ?? '').toString().isNotEmpty ? ' (${item['itemSku']})' : ''}',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.orange.shade100,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text('${item['quantity']}',
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.orange.shade900)),
                          ),
                          if ((item['returnedQuantity'] ?? 0) > 0)
                            Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: Text('مرجع: ${item['returnedQuantity']}',
                                  style: TextStyle(fontSize: 10, color: Colors.green.shade600)),
                            ),
                        ],
                      ),
                    )),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],

        // إضافة مواد جديدة
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.blue.shade50,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.blue.shade200),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.add_circle_outline, size: 16, color: Colors.blue.shade700),
                  const SizedBox(width: 6),
                  Text('إضافة مواد مصروفة',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.blue.shade800)),
                  const Spacer(),
                  InkWell(
                    onTap: () {
                      setState(() {
                        _newMaterialRows.add({'itemId': '', 'itemName': '', 'quantity': 1});
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.blue,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.add, size: 14, color: Colors.white),
                          SizedBox(width: 4),
                          Text('إضافة مادة', style: TextStyle(fontSize: 11, color: Colors.white)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              if (_newMaterialRows.isNotEmpty) ...[
                const SizedBox(height: 10),
                ..._newMaterialRows.asMap().entries.map((entry) {
                  final idx = entry.key;
                  final row = entry.value;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        // اختيار المادة
                        Expanded(
                          flex: 3,
                          child: DropdownButtonFormField<String>(
                            value: (row['itemId'] ?? '').toString().isEmpty ? null : row['itemId'].toString(),
                            isExpanded: true,
                            decoration: InputDecoration(
                              labelText: 'المادة',
                              labelStyle: const TextStyle(fontSize: 12),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                              filled: true,
                              fillColor: Colors.white,
                            ),
                            style: const TextStyle(fontSize: 12, color: Colors.black87),
                            items: _availableItems.map((item) {
                              return DropdownMenuItem<String>(
                                value: item['id']?.toString() ?? '',
                                child: Text(
                                  '${item['name'] ?? ''} (${item['sku'] ?? ''})',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              );
                            }).toList(),
                            onChanged: (val) {
                              setState(() {
                                _newMaterialRows[idx]['itemId'] = val ?? '';
                                final selected = _availableItems.firstWhere(
                                  (i) => i['id']?.toString() == val,
                                  orElse: () => {},
                                );
                                _newMaterialRows[idx]['itemName'] = selected['name'] ?? '';
                              });
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        // الكمية
                        SizedBox(
                          width: 80,
                          child: TextFormField(
                            initialValue: '${row['quantity'] ?? 1}',
                            keyboardType: TextInputType.number,
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 13),
                            decoration: InputDecoration(
                              labelText: 'العدد',
                              labelStyle: const TextStyle(fontSize: 11),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                              filled: true,
                              fillColor: Colors.white,
                            ),
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                            onChanged: (val) {
                              _newMaterialRows[idx]['quantity'] = int.tryParse(val) ?? 1;
                            },
                          ),
                        ),
                        const SizedBox(width: 4),
                        // حذف
                        InkWell(
                          onTap: () => setState(() => _newMaterialRows.removeAt(idx)),
                          child: const Icon(Icons.remove_circle, size: 22, color: Colors.red),
                        ),
                      ],
                    ),
                  );
                }),
                const SizedBox(height: 8),
                // زر الحفظ
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _submitNewMaterials,
                    icon: const Icon(Icons.save, size: 16),
                    label: const Text('حفظ المواد المصروفة', style: TextStyle(fontSize: 13)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ),
              ] else
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text('اضغط "إضافة مادة" لتسجيل المواد المستخدمة',
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                ),
            ],
          ),
        ),
      ],
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
