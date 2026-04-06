import 'package:flutter/material.dart';
import '../utils/smart_text_color.dart';
import '../models/task.dart';
import '../services/task_export_service.dart';

class ReportsPage extends StatefulWidget {
  final List<Task> tasks;
  final List<Task> filteredTasks;
  final Function(BuildContext) showFilterPopup;
  final Function(List<Task>) calculateTotalAmount;
  final Function(Task) calculateTaskDuration;

  const ReportsPage({
    super.key,
    required this.tasks,
    required this.filteredTasks,
    required this.showFilterPopup,
    required this.calculateTotalAmount,
    required this.calculateTaskDuration,
  });

  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  // Filter variables
  String? selectedDepartment;
  String? selectedTechnician;
  String? selectedFBG;
  List<Task> currentFilteredTasks = [];
  bool showFilterDetails = true; // للتحكم في إظهار/إخفاء تفاصيل التصفية

  @override
  void initState() {
    super.initState();
    // استخدام جميع المهام وليس المهام المفلترة فقط
    currentFilteredTasks = widget.tasks;
  }

  @override
  void didUpdateWidget(ReportsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tasks != widget.tasks) {
      _applyFilters();
    }
  }

  void _applyFilters() {
    setState(() {
      // تطبيق الفلاتر على جميع المهام وليس المهام المفلترة فقط
      currentFilteredTasks = widget.tasks.where((task) {
        bool matchesDepartment =
            selectedDepartment == null || task.department == selectedDepartment;
        bool matchesTechnician =
            selectedTechnician == null || task.technician == selectedTechnician;
        bool matchesFBG = selectedFBG == null || task.fbg == selectedFBG;

        return matchesDepartment && matchesTechnician && matchesFBG;
      }).toList();

      // إخفاء تفاصيل التصفية بعد التطبيق
      showFilterDetails = false;
    });
  }

  void _showCustomFilterPopup() {
    // الحصول على القيم الفريدة من جميع المهام
    Set<String> departments = widget.tasks
        .map((task) => task.department)
        .where((dept) => dept.isNotEmpty)
        .toSet();
    Set<String> technicians = widget.tasks
        .map((task) => task.technician)
        .where((tech) => tech.isNotEmpty)
        .toSet();
    Set<String> fbgs = widget.tasks
        .map((task) => task.fbg)
        .where((fbg) => fbg.isNotEmpty)
        .toSet();

    // إظهار تفاصيل التصفية عند فتح النافذة
    setState(() {
      showFilterDetails = true;
    });

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text(
            'تصفية التقارير',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          content: SizedBox(
            width: MediaQuery.of(context).size.width * 0.8,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Department Filter
                const Text('القسم:',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: selectedDepartment,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  hint: const Text('اختر القسم'),
                  items: [
                    const DropdownMenuItem<String>(
                      value: null,
                      child: Text('جميع الأقسام'),
                    ),
                    ...departments.map((dept) => DropdownMenuItem<String>(
                          value: dept,
                          child: Text(dept),
                        )),
                  ],
                  onChanged: (value) {
                    setDialogState(() {
                      selectedDepartment = value;
                    });
                  },
                ),
                const SizedBox(height: 16),

                // Technician Filter
                const Text('الفني:',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: selectedTechnician,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  hint: const Text('اختر الفني'),
                  items: [
                    const DropdownMenuItem<String>(
                      value: null,
                      child: Text('جميع الفنيين'),
                    ),
                    ...technicians.map((tech) => DropdownMenuItem<String>(
                          value: tech,
                          child: Text(tech),
                        )),
                  ],
                  onChanged: (value) {
                    setDialogState(() {
                      selectedTechnician = value;
                    });
                  },
                ),
                const SizedBox(height: 16),

                // FBG Filter
                const Text('FBG:',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: selectedFBG,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  hint: const Text('اختر FBG'),
                  items: [
                    const DropdownMenuItem<String>(
                      value: null,
                      child: Text('جميع FBG'),
                    ),
                    ...fbgs.map((fbg) => DropdownMenuItem<String>(
                          value: fbg,
                          child: Text(fbg),
                        )),
                  ],
                  onChanged: (value) {
                    setDialogState(() {
                      selectedFBG = value;
                    });
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                setState(() {
                  selectedDepartment = null;
                  selectedTechnician = null;
                  selectedFBG = null;
                  currentFilteredTasks =
                      widget.tasks; // إعادة تعيين لجميع المهام
                  showFilterDetails = false;
                });
                Navigator.pop(context);
              },
              child: const Text('مسح الكل'),
            ),
            TextButton(
              onPressed: () {
                setState(() {
                  showFilterDetails = false;
                });
                Navigator.pop(context);
              },
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () {
                _applyFilters();
                Navigator.pop(context);
              },
              child: const Text('تطبيق'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // تحديد ألوان التدرج للـ AppBar
    final gradientColors = [Colors.blueAccent, Colors.blue[700]!];

    // تحديد لون النص والأيقونات بطريقة ذكية
    final smartTextColor =
        SmartTextColor.getAppBarTextColorWithGradient(context, gradientColors);
    final smartIconColor = smartTextColor;

    return Scaffold(
      appBar: AppBar(
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: gradientColors,
            ),
          ),
        ),
        title: Text(
          'التقارير',
          style: SmartTextColor.getSmartTextStyle(
            context: context,
            fontSize: 24,
            fontWeight: FontWeight.bold,
            gradientColors: gradientColors,
          ),
        ),
        backgroundColor: Colors.transparent,
        iconTheme: IconThemeData(color: smartIconColor),
        elevation: 4,
        actions: [
          // أزرار التصدير
          PopupMenuButton<String>(
            icon: Icon(Icons.file_download_outlined, color: smartIconColor),
            tooltip: 'تصدير',
            onSelected: (value) async {
              try {
                String path;
                if (value == 'excel') {
                  path = await TaskExportService.exportToExcel(tasks: currentFilteredTasks);
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تم تصدير Excel'), backgroundColor: Colors.green));
                } else {
                  path = await TaskExportService.exportToPdf(tasks: currentFilteredTasks);
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تم تصدير PDF'), backgroundColor: Colors.green));
                }
              } catch (e) {
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ في التصدير'), backgroundColor: Colors.red));
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'excel', child: Row(children: [
                Icon(Icons.table_chart, color: Colors.green, size: 20), SizedBox(width: 8), Text('تصدير Excel'),
              ])),
              PopupMenuItem(value: 'pdf', child: Row(children: [
                Icon(Icons.picture_as_pdf, color: Colors.red, size: 20), SizedBox(width: 8), Text('تصدير PDF'),
              ])),
            ],
          ),
          IconButton(
            icon: Icon(Icons.filter_list, color: smartIconColor),
            onPressed: _showCustomFilterPopup,
            tooltip: 'تصفية',
          ),
          if (selectedDepartment != null ||
              selectedTechnician != null ||
              selectedFBG != null)
            IconButton(
              icon: Icon(Icons.clear_all, color: smartIconColor),
              onPressed: () {
                setState(() {
                  selectedDepartment = null;
                  selectedTechnician = null;
                  selectedFBG = null;
                });
                _applyFilters();
              },
              tooltip: 'مسح الفلاتر',
            ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.blue.shade50,
              Colors.white,
            ],
          ),
        ),
        child: Column(
          children: [
            // Active Filters Display - يظهر فقط عند الحاجة
            if (showFilterDetails &&
                (selectedDepartment != null ||
                    selectedTechnician != null ||
                    selectedFBG != null))
              Container(
                margin: const EdgeInsets.all(16.0),
                padding: const EdgeInsets.all(12.0),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(10.0),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'الفلاتر المطبقة:',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, size: 20),
                          onPressed: () {
                            setState(() {
                              showFilterDetails = false;
                            });
                          },
                          tooltip: 'إخفاء تفاصيل التصفية',
                        ),
                      ],
                    ),
                    Wrap(
                      spacing: 8,
                      children: [
                        if (selectedDepartment != null)
                          Chip(
                            label: Text('القسم: $selectedDepartment'),
                            deleteIcon: const Icon(Icons.close, size: 16),
                            onDeleted: () {
                              setState(() {
                                selectedDepartment = null;
                              });
                              _applyFilters();
                            },
                          ),
                        if (selectedTechnician != null)
                          Chip(
                            label: Text('الفني: $selectedTechnician'),
                            deleteIcon: const Icon(Icons.close, size: 16),
                            onDeleted: () {
                              setState(() {
                                selectedTechnician = null;
                              });
                              _applyFilters();
                            },
                          ),
                        if (selectedFBG != null)
                          Chip(
                            label: Text('FBG: $selectedFBG'),
                            deleteIcon: const Icon(Icons.close, size: 16),
                            onDeleted: () {
                              setState(() {
                                selectedFBG = null;
                              });
                              _applyFilters();
                            },
                          ),
                      ],
                    ),
                  ],
                ),
              ),

            // بطاقة الإحصائيات المحسنة - تشمل جميع الحالات
            Container(
              margin: const EdgeInsets.all(16.0),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  bool isSmallScreen = constraints.maxWidth < 700;

                  return Container(
                    padding: const EdgeInsets.all(16.0),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(15.0),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.grey.withValues(alpha: 0.3),
                          spreadRadius: 2,
                          blurRadius: 5,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: isSmallScreen
                        ? Column(
                            children: [
                              // الصف الأول
                              Row(
                                children: [
                                  Expanded(
                                    child: _buildStatCard(
                                      'المجموع الكلي',
                                      currentFilteredTasks.length.toString(),
                                      Icons.assignment,
                                      Colors.blue,
                                      isSmallScreen,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: _buildStatCard(
                                      'المكتملة',
                                      currentFilteredTasks
                                          .where(
                                              (task) => task.status == 'مكتملة')
                                          .length
                                          .toString(),
                                      Icons.check_circle,
                                      Colors.green,
                                      isSmallScreen,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              // الصف الثاني
                              Row(
                                children: [
                                  Expanded(
                                    child: _buildStatCard(
                                      'الملغية',
                                      currentFilteredTasks
                                          .where(
                                              (task) => task.status == 'ملغية')
                                          .length
                                          .toString(),
                                      Icons.cancel,
                                      Colors.red,
                                      isSmallScreen,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: _buildStatCard(
                                      'المبلغ الإجمالي',
                                      '${widget.calculateTotalAmount(currentFilteredTasks).toStringAsFixed(0)} د.ع',
                                      Icons.account_balance_wallet,
                                      Colors.orange,
                                      isSmallScreen,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          )
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              Expanded(
                                child: _buildStatCard(
                                  'المجموع الكلي',
                                  currentFilteredTasks.length.toString(),
                                  Icons.assignment,
                                  Colors.blue,
                                  isSmallScreen,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _buildStatCard(
                                  'المكتملة',
                                  currentFilteredTasks
                                      .where((task) => task.status == 'مكتملة')
                                      .length
                                      .toString(),
                                  Icons.check_circle,
                                  Colors.green,
                                  isSmallScreen,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _buildStatCard(
                                  'الملغية',
                                  currentFilteredTasks
                                      .where((task) => task.status == 'ملغية')
                                      .length
                                      .toString(),
                                  Icons.cancel,
                                  Colors.red,
                                  isSmallScreen,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _buildStatCard(
                                  'المبلغ الإجمالي',
                                  '${widget.calculateTotalAmount(currentFilteredTasks).toStringAsFixed(0)} د.ع',
                                  Icons.account_balance_wallet,
                                  Colors.orange,
                                  isSmallScreen,
                                ),
                              ),
                            ],
                          ),
                  );
                },
              ),
            ),

            // قائمة المهام
            Expanded(
              child: currentFilteredTasks.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.assignment_outlined,
                            size: 80,
                            color: Colors.grey[400],
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'لا توجد مهام تطابق الفلاتر المحددة',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey[600],
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'قم بتعديل الفلاتر أو مسحها لرؤية المزيد من المهام',
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.grey[500],
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      itemCount: currentFilteredTasks.length,
                      itemBuilder: (context, index) {
                        final task = currentFilteredTasks[index];
                        return _buildTaskCard(task);
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color,
      bool isSmallScreen) {
    return Container(
      padding: EdgeInsets.all(isSmallScreen ? 8.0 : 12.0),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12.0),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: isSmallScreen ? 24 : 32,
            color: color,
          ),
          SizedBox(height: isSmallScreen ? 6 : 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: TextStyle(
                fontSize: isSmallScreen ? 16 : 20,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ),
          SizedBox(height: isSmallScreen ? 2 : 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              title,
              style: TextStyle(
                fontSize: isSmallScreen ? 10 : 12,
                color: Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTaskCard(Task task) {
    Color statusColor = _getStatusColor(task.status);

    return Card(
      margin: const EdgeInsets.only(bottom: 12.0),
      elevation: 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12.0),
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12.0),
          border: Border(
            right: BorderSide(
              color: statusColor,
              width: 4,
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // العنوان والحالة
              Row(
                children: [
                  Expanded(
                    child: Text(
                      task.title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.blueAccent,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      task.status,
                      style: TextStyle(
                        color: statusColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // تفاصيل المهمة
              _buildDetailRow(Icons.business, 'القسم', task.department),
              _buildDetailRow(Icons.person, 'الفني', task.technician),
              _buildDetailRow(Icons.supervisor_account, 'الليدر', task.leader),
              _buildDetailRow(Icons.router, 'FBG', task.fbg),
              _buildDetailRow(Icons.phone, 'الهاتف', task.phone),
              _buildDetailRow(
                  Icons.attach_money, 'المبلغ', '${task.amount} د.ع'),
              _buildDetailRow(Icons.access_time, 'وقت التنفيذ',
                  widget.calculateTaskDuration(task)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        children: [
          Icon(
            icon,
            size: 16,
            color: Colors.grey[600],
          ),
          const SizedBox(width: 8),
          Text(
            '$label: ',
            style: TextStyle(
              fontWeight: FontWeight.w500,
              color: Colors.grey[700],
              fontSize: 14,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 14,
                color: Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'مكتملة':
        return Colors.green;
      case 'قيد التنفيذ':
        return Colors.orange;
      case 'جديدة':
        return Colors.blue;
      case 'ملغية':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }
}
