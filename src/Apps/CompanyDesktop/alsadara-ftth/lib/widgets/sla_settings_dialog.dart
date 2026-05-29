import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/departments_data_service.dart';
import '../services/sadara_api_service.dart';
import '../services/vps_auth_service.dart';

/// حوار إعدادات SLA — لتعديل ساعات SLA لكل نوع مهمة في كل قسم
class SlaSettingsDialog extends StatefulWidget {
  const SlaSettingsDialog({super.key});

  /// عرض الحوار
  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      builder: (_) => const SlaSettingsDialog(),
    );
  }

  @override
  State<SlaSettingsDialog> createState() => _SlaSettingsDialogState();
}

class _SlaSettingsDialogState extends State<SlaSettingsDialog> {
  bool _isLoading = true;
  bool _isSaving = false;
  String? _errorMessage;

  /// بيانات الأقسام: [{id, nameAr, tasks: [{id, nameAr, slaHours}]}]
  List<_DepartmentData> _departments = [];

  /// القيم الأصلية للمقارنة (لمعرفة ما تغيّر)
  final Map<int, int> _originalSlaValues = {};

  /// القيم المعدلة: taskId -> slaHours
  final Map<int, int> _editedSlaValues = {};

  /// الأقسام المفتوحة
  final Set<int> _expandedDepartments = {};

  @override
  void initState() {
    super.initState();
    _loadDepartments();
  }

  Future<void> _loadDepartments() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final companyId = VpsAuthService.instance.currentCompanyId;
    if (companyId == null || companyId.isEmpty) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'لا يمكن تحديد الشركة الحالية';
      });
      return;
    }

    try {
      final response = await SadaraApiService.instance
          .get('/companies/$companyId/departments');

      final success = response['success'] ?? response['Success'];
      final responseData = response['data'] ?? response['Data'];
      if (success == true && responseData != null) {
        final data = responseData as List;
        final departments = <_DepartmentData>[];

        for (final dept in data) {
          final deptMap = Map<String, dynamic>.from(dept as Map);
          final tasks = ((deptMap['Tasks'] ?? deptMap['tasks']) as List? ?? []).map((t) {
            final taskMap = Map<String, dynamic>.from(t as Map);
            final taskId = (taskMap['Id'] ?? taskMap['id']) as int? ?? 0;
            final slaHours = (taskMap['SlaHours'] ?? taskMap['slaHours']) as int? ?? 0;
            _originalSlaValues[taskId] = slaHours;
            _editedSlaValues[taskId] = slaHours;
            return _TaskData(
              id: taskId,
              nameAr: (taskMap['NameAr'] ?? taskMap['nameAr'])?.toString() ?? '',
              slaHours: slaHours,
              isActive: (taskMap['IsActive'] ?? taskMap['isActive']) as bool? ?? true,
            );
          }).toList();

          departments.add(_DepartmentData(
            id: (deptMap['Id'] ?? deptMap['id']) as int? ?? 0,
            nameAr: (deptMap['NameAr'] ?? deptMap['nameAr'])?.toString() ?? '',
            isActive: (deptMap['IsActive'] ?? deptMap['isActive']) as bool? ?? true,
            tasks: tasks,
          ));
        }

        if (mounted) {
          setState(() {
            _departments = departments;
            _isLoading = false;
            // فتح أول قسم تلقائياً
            if (departments.isNotEmpty) {
              _expandedDepartments.add(departments.first.id);
            }
          });
        }
      } else {
        setState(() {
          _isLoading = false;
          _errorMessage = response['message']?.toString() ?? 'فشل في جلب الأقسام';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'خطأ في الاتصال بالسيرفر';
        });
      }
    }
  }

  /// هل يوجد تغييرات غير محفوظة؟
  bool get _hasChanges {
    for (final entry in _editedSlaValues.entries) {
      if (entry.value != (_originalSlaValues[entry.key] ?? 0)) return true;
    }
    return false;
  }

  /// عدد التغييرات
  int get _changesCount {
    int count = 0;
    for (final entry in _editedSlaValues.entries) {
      if (entry.value != (_originalSlaValues[entry.key] ?? 0)) count++;
    }
    return count;
  }

  /// حفظ التغييرات
  Future<void> _saveChanges() async {
    final companyId = VpsAuthService.instance.currentCompanyId;
    if (companyId == null || companyId.isEmpty) return;

    setState(() => _isSaving = true);

    int successCount = 0;
    int failCount = 0;
    final errors = <String>[];

    for (final dept in _departments) {
      for (final task in dept.tasks) {
        final newValue = _editedSlaValues[task.id] ?? 0;
        final oldValue = _originalSlaValues[task.id] ?? 0;
        if (newValue == oldValue) continue;

        try {
          final response = await SadaraApiService.instance.put(
            '/companies/$companyId/departments/${dept.id}/tasks/${task.id}',
            body: {'SlaHours': newValue},
          );

          if (response['success'] == true) {
            successCount++;
            _originalSlaValues[task.id] = newValue;
          } else {
            failCount++;
            errors.add('${task.nameAr}: ${response['message'] ?? 'خطأ'}');
          }
        } catch (e) {
          failCount++;
          errors.add('${task.nameAr}: خطأ في الاتصال');
        }
      }
    }

    // مسح كاش الأقسام حتى يُحدَّث في كل مكان
    DepartmentsDataService.instance.clearCache();

    if (mounted) {
      setState(() => _isSaving = false);

      if (failCount == 0 && successCount > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم حفظ $successCount تعديل بنجاح'),
            backgroundColor: Colors.green,
          ),
        );
      } else if (failCount > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'نجح: $successCount | فشل: $failCount\n${errors.take(3).join('\n')}',
            ),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenW = MediaQuery.of(context).size.width;
    final isMobile = screenW < 600;

    return Dialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: isMobile ? 8 : 40,
        vertical: isMobile ? 16 : 24,
      ),
      child: Container(
        width: isMobile ? screenW - 16 : (screenW * 0.7).clamp(400.0, 700.0),
        height: MediaQuery.of(context).size.height * (isMobile ? 0.9 : 0.85),
        padding: EdgeInsets.all(isMobile ? 12 : 20),
        child: Column(
          children: [
            // العنوان
            _buildHeader(),
            const Divider(thickness: 1.5),

            // المحتوى
            Expanded(child: _buildContent()),

            // أزرار الحفظ
            if (!_isLoading && _errorMessage == null) _buildFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Icon(Icons.timer_outlined, color: Colors.indigo.shade700, size: 24),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'إعدادات SLA',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              Text(
                'تعيين الحد الزمني (بالدقائق) لإنجاز كل نوع مهمة',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
        if (_hasChanges)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.orange.shade300),
            ),
            child: Text(
              '$_changesCount تعديل',
              style: TextStyle(
                fontSize: 11,
                color: Colors.orange.shade800,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        const SizedBox(width: 8),
        IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => _confirmClose(),
        ),
      ],
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('جاري تحميل الأقسام...'),
          ],
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.red.shade300),
            const SizedBox(height: 12),
            Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _loadDepartments,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('إعادة المحاولة'),
            ),
          ],
        ),
      );
    }

    if (_departments.isEmpty) {
      return const Center(
        child: Text('لا توجد أقسام مسجلة', style: TextStyle(color: Colors.grey)),
      );
    }

    return ListView.builder(
      itemCount: _departments.length,
      itemBuilder: (context, index) => _buildDepartmentTile(_departments[index]),
    );
  }

  Widget _buildDepartmentTile(_DepartmentData dept) {
    final isExpanded = _expandedDepartments.contains(dept.id);
    final activeTasks = dept.tasks.where((t) => t.isActive).toList();
    final configuredCount =
        activeTasks.where((t) => (_editedSlaValues[t.id] ?? 0) > 0).length;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isExpanded ? Colors.indigo.shade300 : Colors.grey.shade300,
          width: isExpanded ? 1.5 : 1,
        ),
        color: isExpanded ? Colors.indigo.shade50.withValues(alpha: 0.3) : null,
      ),
      child: Column(
        children: [
          // رأس القسم
          InkWell(
            onTap: () {
              setState(() {
                if (isExpanded) {
                  _expandedDepartments.remove(dept.id);
                } else {
                  _expandedDepartments.add(dept.id);
                }
              });
            },
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Icon(
                    isExpanded ? Icons.expand_less : Icons.expand_more,
                    color: Colors.indigo.shade700,
                  ),
                  const SizedBox(width: 8),
                  Icon(Icons.business, size: 20, color: Colors.indigo.shade400),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      dept.nameAr,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: dept.isActive ? Colors.black87 : Colors.grey,
                      ),
                    ),
                  ),
                  // عداد المهام المُعد لها SLA
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: configuredCount == activeTasks.length && activeTasks.isNotEmpty
                          ? Colors.green.shade50
                          : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '$configuredCount/${activeTasks.length}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: configuredCount == activeTasks.length && activeTasks.isNotEmpty
                            ? Colors.green.shade700
                            : Colors.grey.shade600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // مهام القسم
          if (isExpanded && activeTasks.isNotEmpty)
            Container(
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: Colors.grey.shade200),
                ),
              ),
              child: Column(
                children: activeTasks.map((task) => _buildTaskSlaRow(task, dept)).toList(),
              ),
            ),

          if (isExpanded && activeTasks.isEmpty)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                'لا توجد مهام في هذا القسم',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTaskSlaRow(_TaskData task, _DepartmentData dept) {
    final currentValue = _editedSlaValues[task.id] ?? 0;
    final originalValue = _originalSlaValues[task.id] ?? 0;
    final isModified = currentValue != originalValue;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: isModified ? Colors.amber.shade50 : null,
        border: Border(bottom: BorderSide(color: Colors.grey.shade100)),
      ),
      child: Row(
        children: [
          // اسم المهمة
          Expanded(
            flex: 3,
            child: Row(
              children: [
                Icon(
                  Icons.task_alt,
                  size: 16,
                  color: currentValue > 0 ? Colors.green.shade400 : Colors.grey.shade400,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    task.nameAr,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.black87,
                      fontWeight: isModified ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // حقل SLA
          SizedBox(
            width: 100,
            child: TextFormField(
              initialValue: currentValue > 0 ? '$currentValue' : '',
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(4),
              ],
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isModified ? Colors.orange.shade800 : Colors.black87,
              ),
              decoration: InputDecoration(
                hintText: '0',
                hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                suffixText: 'دقيقة',
                suffixStyle: TextStyle(fontSize: 10, color: Colors.grey.shade500),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(
                    color: isModified ? Colors.orange.shade300 : Colors.grey.shade300,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(color: Colors.indigo.shade400, width: 1.5),
                ),
              ),
              onChanged: (value) {
                final newVal = int.tryParse(value) ?? 0;
                setState(() {
                  _editedSlaValues[task.id] = newVal;
                });
              },
            ),
          ),

          // مؤشر التغيير
          SizedBox(
            width: 28,
            child: isModified
                ? IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    icon: Icon(Icons.undo, size: 16, color: Colors.grey.shade600),
                    tooltip: 'إرجاع القيمة الأصلية ($originalValue)',
                    onPressed: () {
                      setState(() {
                        _editedSlaValues[task.id] = originalValue;
                      });
                    },
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.only(top: 12),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Row(
        children: [
          // زر تعيين قيمة افتراضية لكل المهام
          TextButton.icon(
            onPressed: _showBulkSetDialog,
            icon: Icon(Icons.tune, size: 16, color: Colors.indigo.shade600),
            label: Text(
              'تعيين الكل',
              style: TextStyle(fontSize: 12, color: Colors.indigo.shade600),
            ),
          ),
          const Spacer(),
          // إلغاء
          OutlinedButton(
            onPressed: () => _confirmClose(),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
            child: const Text('إغلاق'),
          ),
          const SizedBox(width: 12),
          // حفظ
          ElevatedButton.icon(
            onPressed: _hasChanges && !_isSaving ? _saveChanges : null,
            icon: _isSaving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.save, size: 18),
            label: Text(_isSaving ? 'جاري الحفظ...' : 'حفظ التغييرات'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.indigo.shade700,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            ),
          ),
        ],
      ),
    );
  }

  /// حوار تعيين قيمة SLA لكل المهام دفعة واحدة
  void _showBulkSetDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تعيين SLA لكل المهام', style: TextStyle(fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'أدخل عدد الساعات لتطبيقه على جميع المهام التي لم يتم تعيين SLA لها (القيمة = 0)',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(4),
              ],
              textAlign: TextAlign.center,
              decoration: InputDecoration(
                hintText: 'مثال: 24',
                suffixText: 'دقيقة',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () {
              final value = int.tryParse(controller.text) ?? 0;
              if (value > 0) {
                setState(() {
                  for (final dept in _departments) {
                    for (final task in dept.tasks) {
                      if (task.isActive && (_editedSlaValues[task.id] ?? 0) == 0) {
                        _editedSlaValues[task.id] = value;
                      }
                    }
                  }
                });
              }
              Navigator.pop(ctx);
            },
            child: const Text('تطبيق'),
          ),
        ],
      ),
    );
  }

  /// تأكيد الإغلاق إذا كان هناك تغييرات
  void _confirmClose() {
    if (!_hasChanges) {
      Navigator.pop(context);
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تغييرات غير محفوظة'),
        content: Text('لديك $_changesCount تعديل غير محفوظ. هل تريد الإغلاق بدون حفظ؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('متابعة التعديل'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('إغلاق بدون حفظ', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}

/// بيانات قسم
class _DepartmentData {
  final int id;
  final String nameAr;
  final bool isActive;
  final List<_TaskData> tasks;

  _DepartmentData({
    required this.id,
    required this.nameAr,
    required this.isActive,
    required this.tasks,
  });
}

/// بيانات مهمة
class _TaskData {
  final int id;
  final String nameAr;
  final int slaHours;
  final bool isActive;

  _TaskData({
    required this.id,
    required this.nameAr,
    required this.slaHours,
    required this.isActive,
  });
}
