/// اسم الصفحة: قائمة الاتصالات
/// وصف الصفحة: صفحة قائمة الاتصالات والشبكات
/// المؤلف: تطبيق السدارة
/// تاريخ الإنشاء: 2024
library;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../services/google_sheets_service.dart';
import '../../models/filter_criteria.dart';

/// صفحة اسمية الوصولات
/// تعرض الصفوف التي تحتوي على قيم في عامود فني التوصيل (AE) مجمعة حسب فني التوصيل
class ConnectionsListPage extends StatefulWidget {
  final String? specificTechnician; // عرض الوصولات لفني محدد (اختياري)
  final String? specificUser; // عرض الوصولات لمستخدم محدد (اختياري)
  final FilterCriteria?
      filterCriteria; // معايير التصفية المرسلة من الصفحة الرئيسية

  const ConnectionsListPage({
    super.key,
    this.specificTechnician,
    this.specificUser,
    this.filterCriteria,
  });

  @override
  State<ConnectionsListPage> createState() => _ConnectionsListPageState();
}

class _ConnectionsListPageState extends State<ConnectionsListPage> {
  bool isLoading = true;
  String? errorMessage;
  Map<String, List<Map<String, dynamic>>> connectionsData = {};
  Map<String, List<Map<String, dynamic>>> filteredConnectionsData = {};
  List<String> technicians = []; // قائمة فنيي التوصيل
  final TextEditingController _searchController = TextEditingController();
  bool isSearching = false;

  // متغيرات التصفية الإضافية
  bool showLocalFilters = false; // إظهار/إخفاء التصفية المحلية
  DateTime? localFromDate; // تصفية محلية من تاريخ
  DateTime? localToDate; // تصفية محلية إلى تاريخ
  String selectedTechnicianFilter = 'الكل'; // تصفية حسب الفني
  List<String> availableTechnicians = ['الكل']; // قائمة الفنيين المتاحة للتصفية

  @override
  void initState() {
    super.initState();
    // تعيين التصفية الافتراضية لعرض تاريخ اليوم
    final today = DateTime.now();
    localFromDate = DateTime(today.year, today.month, today.day);
    localToDate = DateTime(today.year, today.month, today.day);

    print(
        '🗓️ تم تعيين التصفية الافتراضية لتاريخ اليوم: ${DateFormat('dd/MM/yyyy').format(today)}');

    _loadConnectionsData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// تصفية البيانات بناءً على النص المدخل
  void _filterData(String searchText) {
    if (searchText.isEmpty) {
      setState(() {
        filteredConnectionsData = Map.from(connectionsData);
        _updateTechniciansList();
      });
      return;
    }

    Map<String, List<Map<String, dynamic>>> filtered = {};

    connectionsData.forEach((technicianName, connections) {
      List<Map<String, dynamic>> filteredConnections =
          connections.where((connection) {
        return connection['customerName']
                    ?.toString()
                    .toLowerCase()
                    .contains(searchText.toLowerCase()) ==
                true ||
            connection['phoneNumber']?.toString().contains(searchText) ==
                true ||
            connection['deviceModel']
                    ?.toString()
                    .toLowerCase()
                    .contains(searchText.toLowerCase()) ==
                true ||
            technicianName.toLowerCase().contains(searchText.toLowerCase());
      }).toList();
      if (filteredConnections.isNotEmpty) {
        filtered[technicianName] = filteredConnections;
      }
    });

    setState(() {
      filteredConnectionsData = filtered;
      _updateTechniciansList();
    });
  }

  /// تحديث قائمة فنيي التوصيل المرشحة
  void _updateTechniciansList() {
    if (widget.specificTechnician != null &&
        filteredConnectionsData.containsKey(widget.specificTechnician)) {
      technicians = [widget.specificTechnician!];
    } else {
      technicians = filteredConnectionsData.keys.toList()..sort();
    }
  }

  /// تطبيق التصفية المحلية (التاريخ + الفني)
  void _applyLocalFilters() {
    print('🔍 تطبيق التصفية المحلية:');
    print('   - من تاريخ: $localFromDate');
    print('   - إلى تاريخ: $localToDate');
    print('   - الفني المحدد: $selectedTechnicianFilter');
    print('   - عدد البيانات الأصلية: ${connectionsData.length} فني');

    Map<String, List<Map<String, dynamic>>> filtered =
        Map.from(connectionsData);

    // تصفية حسب التاريخ
    if (localFromDate != null || localToDate != null) {
      Map<String, List<Map<String, dynamic>>> dateFiltered = {};
      int totalConnectionsBeforeFilter = 0;
      int totalConnectionsAfterFilter = 0;

      filtered.forEach((technicianName, connections) {
        totalConnectionsBeforeFilter += connections.length;

        List<Map<String, dynamic>> filteredConnections =
            connections.where((connection) {
          // البحث في أعمدة التاريخ المختلفة المحتملة
          final dateStr = connection['date']?.toString() ??
              connection['تاريخ التفعيل']?.toString() ??
              connection['creationDate']?.toString() ??
              connection['planStartDate']?.toString() ??
              connection['activationDate']?.toString() ??
              connection['تاريخ البداية']?.toString() ??
              connection['تاريخ الانشاء']?.toString() ??
              '';

          if (dateStr.isEmpty) {
            print('⚠️ سجل بدون تاريخ للفني $technicianName');
            print('   - أعمدة متاحة: ${connection.keys.toList()}');
            return localFromDate == null && localToDate == null;
          }

          DateTime? recordDate = _parseConnectionDate(dateStr);
          if (recordDate == null) {
            print('❌ فشل تحليل التاريخ "$dateStr" للفني $technicianName');
            return false;
          }

          // تحقق من التاريخ من
          if (localFromDate != null) {
            if (recordDate.isBefore(DateTime(localFromDate!.year,
                localFromDate!.month, localFromDate!.day))) {
              return false;
            }
          }

          // تحقق من التاريخ إلى
          if (localToDate != null) {
            if (recordDate.isAfter(DateTime(localToDate!.year,
                localToDate!.month, localToDate!.day, 23, 59, 59))) {
              return false;
            }
          }

          return true;
        }).toList();

        totalConnectionsAfterFilter += filteredConnections.length;

        if (filteredConnections.isNotEmpty) {
          dateFiltered[technicianName] = filteredConnections;
          print('✅ الفني $technicianName: ${filteredConnections.length} اتصال');
        } else {
          print('❌ الفني $technicianName: لا توجد اتصالات في النطاق المحدد');
        }
      });

      print('📊 نتائج التصفية بالتاريخ:');
      print('   - قبل التصفية: $totalConnectionsBeforeFilter اتصال');
      print('   - بعد التصفية: $totalConnectionsAfterFilter اتصال');

      filtered = dateFiltered;
    }

    // تصفية حسب الفني
    if (selectedTechnicianFilter != 'الكل') {
      filtered = {
        if (filtered.containsKey(selectedTechnicianFilter))
          selectedTechnicianFilter: filtered[selectedTechnicianFilter]!
      };
    }

    setState(() {
      filteredConnectionsData = filtered;
      _updateTechniciansList();
    });

    print('🔍 تطبيق التصفية المحلية:');
    print('   - من تاريخ: $localFromDate');
    print('   - إلى تاريخ: $localToDate');
    print('   - الفني المحدد: $selectedTechnicianFilter');
    print('   - عدد النتائج: ${filtered.length} فني');
  }

  /// تحليل تاريخ الاتصال
  DateTime? _parseConnectionDate(String dateStr) {
    if (dateStr.trim().isEmpty) return null;

    // محاولة تحليل عدة صيغ للتاريخ
    final formats = [
      'dd/MM/yyyy',
      'MM/dd/yyyy',
      'yyyy-MM-dd',
      'dd-MM-yyyy',
      'yyyy/MM/dd',
      'dd/MM/yyyy HH:mm:ss',
      'yyyy-MM-dd HH:mm:ss',
    ];

    for (final format in formats) {
      try {
        final parsed = DateFormat(format).parse(dateStr.trim());
        print(
            '✅ تم تحليل التاريخ: "$dateStr" -> ${DateFormat('dd/MM/yyyy').format(parsed)}');
        return parsed;
      } catch (e) {
        // تجاهل الأخطاء ومحاولة الصيغة التالية
      }
    }

    print('❌ فشل في تحليل التاريخ: "$dateStr"');
    return null;
  }

  /// مسح التصفية المحلية
  void _clearLocalFilters() {
    setState(() {
      localFromDate = null;
      localToDate = null;
      selectedTechnicianFilter = 'الكل';
      filteredConnectionsData = Map.from(connectionsData);
      _updateTechniciansList();
    });
  }

  /// تعيين تصفية اليوم
  void _setTodayFilter() {
    final today = DateTime.now();
    setState(() {
      localFromDate = DateTime(today.year, today.month, today.day);
      localToDate = DateTime(today.year, today.month, today.day);
    });
    _applyLocalFilters();
    print(
        '📅 تم تعيين التصفية لتاريخ اليوم: ${DateFormat('dd/MM/yyyy').format(today)}');
  }

  /// تعيين تصفية الأمس
  void _setYesterdayFilter() {
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    setState(() {
      localFromDate = DateTime(yesterday.year, yesterday.month, yesterday.day);
      localToDate = DateTime(yesterday.year, yesterday.month, yesterday.day);
    });
    _applyLocalFilters();
    print(
        '📅 تم تعيين التصفية لتاريخ الأمس: ${DateFormat('dd/MM/yyyy').format(yesterday)}');
  }

  /// مسح تصفية التاريخ فقط
  void _clearDateFilter() {
    setState(() {
      localFromDate = null;
      localToDate = null;
    });
    _applyLocalFilters();
    print('🗑️ تم مسح تصفية التاريخ - عرض جميع التواريخ');
  }

  /// بناء زر سريع للتاريخ
  Widget _buildQuickDateButton(String text, IconData icon, VoidCallback onTap) {
    final isActive = (text == 'اليوم' && _isTodaySelected()) ||
        (text == 'الأمس' && _isYesterdaySelected()) ||
        (text == 'عرض الكل' && localFromDate == null && localToDate == null);

    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 4),
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
          decoration: BoxDecoration(
            color: isActive ? Colors.blue.shade50 : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isActive ? Colors.blue.shade300 : Colors.grey.shade300,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 16,
                color: isActive ? Colors.blue.shade700 : Colors.grey.shade600,
              ),
              const SizedBox(width: 4),
              Text(
                text,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: isActive ? Colors.blue.shade700 : Colors.grey.shade600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// فحص ما إذا كان تاريخ اليوم محدد
  bool _isTodaySelected() {
    if (localFromDate == null || localToDate == null) return false;
    final today = DateTime.now();
    final todayStart = DateTime(today.year, today.month, today.day);
    return localFromDate!.isAtSameMomentAs(todayStart) &&
        localToDate!.isAtSameMomentAs(todayStart);
  }

  /// فحص ما إذا كان تاريخ الأمس محدد
  bool _isYesterdaySelected() {
    if (localFromDate == null || localToDate == null) return false;
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    final yesterdayStart =
        DateTime(yesterday.year, yesterday.month, yesterday.day);
    return localFromDate!.isAtSameMomentAs(yesterdayStart) &&
        localToDate!.isAtSameMomentAs(yesterdayStart);
  }

  /// بناء قسم التصفية المحلية
  Widget _buildLocalFilterSection() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: 0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // عنوان التصفية
          Row(
            children: [
              Icon(Icons.tune, color: Colors.deepPurple.shade700, size: 20),
              const SizedBox(width: 8),
              const Text(
                'تصفية الوصولات',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
              const Spacer(),
              // زر مسح جميع التصفيات
              InkWell(
                onTap: _clearLocalFilters,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.clear, size: 14, color: Colors.grey.shade600),
                      const SizedBox(width: 4),
                      Text(
                        'مسح الكل',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // الصف الأول: من تاريخ - إلى تاريخ
          Row(
            children: [
              // من تاريخ
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'من تاريخ',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey.shade700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    InkWell(
                      onTap: () async {
                        final date = await showDatePicker(
                          context: context,
                          initialDate: localFromDate ?? DateTime.now(),
                          firstDate: DateTime(2020),
                          lastDate:
                              DateTime.now().add(const Duration(days: 365)),
                        );
                        if (date != null) {
                          setState(() {
                            localFromDate = date;
                          });
                          _applyLocalFilters();
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade400),
                          borderRadius: BorderRadius.circular(8),
                          color: localFromDate != null
                              ? Colors.blue.shade50
                              : Colors.grey.shade50,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.calendar_today,
                              size: 16,
                              color: localFromDate != null
                                  ? Colors.blue.shade700
                                  : Colors.grey.shade600,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              localFromDate != null
                                  ? DateFormat('dd/MM/yyyy')
                                      .format(localFromDate!)
                                  : 'اختر التاريخ',
                              style: TextStyle(
                                fontSize: 12,
                                color: localFromDate != null
                                    ? Colors.blue.shade700
                                    : Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // إلى تاريخ
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'إلى تاريخ',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey.shade700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    InkWell(
                      onTap: () async {
                        final date = await showDatePicker(
                          context: context,
                          initialDate: localToDate ?? DateTime.now(),
                          firstDate: DateTime(2020),
                          lastDate:
                              DateTime.now().add(const Duration(days: 365)),
                        );
                        if (date != null) {
                          setState(() {
                            localToDate = date;
                          });
                          _applyLocalFilters();
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade400),
                          borderRadius: BorderRadius.circular(8),
                          color: localToDate != null
                              ? Colors.blue.shade50
                              : Colors.grey.shade50,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.calendar_today,
                              size: 16,
                              color: localToDate != null
                                  ? Colors.blue.shade700
                                  : Colors.grey.shade600,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              localToDate != null
                                  ? DateFormat('dd/MM/yyyy')
                                      .format(localToDate!)
                                  : 'اختر التاريخ',
                              style: TextStyle(
                                fontSize: 12,
                                color: localToDate != null
                                    ? Colors.blue.shade700
                                    : Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // أزرار سريعة للتاريخ
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              // زر اليوم
              _buildQuickDateButton(
                'اليوم',
                Icons.today,
                () => _setTodayFilter(),
              ),
              // زر الأمس
              _buildQuickDateButton(
                'الأمس',
                Icons.history,
                () => _setYesterdayFilter(),
              ),
              // زر مسح التصفية
              _buildQuickDateButton(
                'عرض الكل',
                Icons.all_inclusive,
                () => _clearDateFilter(),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // الصف الثاني: تصفية حسب الفني
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'فني التوصيل',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: Colors.grey.shade700,
                ),
              ),
              const SizedBox(height: 4),
              Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade400),
                  borderRadius: BorderRadius.circular(8),
                  color: selectedTechnicianFilter != 'الكل'
                      ? Colors.blue.shade50
                      : Colors.grey.shade50,
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: selectedTechnicianFilter,
                    onChanged: (value) {
                      setState(() {
                        selectedTechnicianFilter = value ?? 'الكل';
                      });
                      _applyLocalFilters();
                    },
                    isExpanded: true,
                    items: availableTechnicians.map((technician) {
                      return DropdownMenuItem(
                        value: technician,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          child: Text(
                            technician,
                            style: TextStyle(
                              fontSize: 12,
                              color: selectedTechnicianFilter == technician
                                  ? Colors.blue.shade700
                                  : Colors.grey.shade800,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// وصف التصفية المحلية النشطة
  String _getLocalFilterDescription() {
    List<String> descriptions = [];

    if (localFromDate != null) {
      descriptions.add('من ${DateFormat('dd/MM/yyyy').format(localFromDate!)}');
    }

    if (localToDate != null) {
      descriptions.add('إلى ${DateFormat('dd/MM/yyyy').format(localToDate!)}');
    }

    if (selectedTechnicianFilter != 'الكل') {
      descriptions.add('فني: $selectedTechnicianFilter');
    }

    return descriptions.join(' • ');
  }

  /// تحميل بيانات الوصولات من Google Sheets
  Future<void> _loadConnectionsData() async {
    try {
      setState(() {
        isLoading = true;
        errorMessage = null;
      });

      // جلب البيانات من ورقة Account وإعادة تنظيمها حسب فنيي التوصيل
      final data = await _fetchConnectionsFromSheets();

      if (mounted) {
        setState(() {
          connectionsData = data;

          // تحديث قائمة الفنيين المتاحة للتصفية
          availableTechnicians = ['الكل'] + data.keys.toList()
            ..sort();

          // إذا كان هناك فني محدد، اعرض بياناته فقط
          if (widget.specificTechnician != null &&
              data.containsKey(widget.specificTechnician)) {
            filteredConnectionsData = {
              widget.specificTechnician!: data[widget.specificTechnician!]!
            };
          } else {
            filteredConnectionsData = Map.from(data);
          }
          _updateTechniciansList();
          isLoading = false;
        });

        // تطبيق التصفية المحلية الافتراضية (تاريخ اليوم)
        _applyLocalFilters();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          errorMessage = 'خطأ في تحميل البيانات: $e';
          isLoading = false;
        });
      }
    }
  }

  /// جلب البيانات من Google Sheets وإعادة تنظيمها حسب فني التوصيل
  Future<Map<String, List<Map<String, dynamic>>>>
      _fetchConnectionsFromSheets() async {
    try {
      print('🔍 ConnectionsListPage - بدء جلب البيانات بدون تصفية رئيسية');
      print('   - تم إلغاء تطبيق FilterCriteria من الصفحة الرئيسية');
      print('   - مستخدم محدد: ${widget.specificUser}');

      // جلب جميع البيانات بدون تطبيق تصفية رئيسية
      final rawData = await GoogleSheetsService.getFilteredConnectionsWithNotes(
        null, // إلغاء تمرير معايير التصفية الرئيسية
      );

      print('📊 تم استلام ${rawData.length} مستخدمين من الخدمة');

      // إعادة تنظيم البيانات حسب فني التوصيل بدلاً من المستخدم
      Map<String, List<Map<String, dynamic>>> reorganizedData = {};

      rawData.forEach((userName, connections) {
        // إذا تم تحديد مستخدم معين، فلتر البيانات لهذا المستخدم فقط
        if (widget.specificUser != null && userName != widget.specificUser) {
          return; // تجاهل هذا المستخدم
        }

        for (var connection in connections) {
          String technicianName = connection['deviceModel'] ?? 'غير محدد';

          if (!reorganizedData.containsKey(technicianName)) {
            reorganizedData[technicianName] = [];
          }

          // إضافة معلومة المستخدم الذي أدخل البيانات
          connection['enteredBy'] = userName;

          // طباعة أعمدة السجل الأول للمراجعة
          if (reorganizedData.isEmpty && connections.isEmpty) {
            print('🔑 أعمدة البيانات المتاحة في أول سجل:');
            for (var key in connection.keys) {
              print('   - $key: ${connection[key]}');
            }
          }

          reorganizedData[technicianName]!.add(connection);
        }
      });

      return reorganizedData;
    } catch (e) {
      throw Exception('خطأ في جلب البيانات من Google Sheets: $e');
    }
  }

  /// حساب مجموع المبالغ لقائمة وصولات
  double _calculateTotalAmount(List<Map<String, dynamic>> connections) {
    double total = 0.0;
    for (var connection in connections) {
      String priceStr = connection['planPrice'] ?? '';
      if (priceStr.isNotEmpty) {
        // تنظيف النص وإزالة الفواصل والمسافات
        priceStr = priceStr.replaceAll(',', '').replaceAll(' ', '').trim();
        // محاولة تحويل النص إلى رقم
        double? price = double.tryParse(priceStr);
        if (price != null) {
          total += price;
        }
      }
    }
    return total;
  }

  /// تنسيق المبلغ بالفواصل
  String _formatAmount(double amount) {
    if (amount == 0) return '0';
    return amount.toStringAsFixed(0).replaceAllMapped(
          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
          (Match m) => '${m[1]},',
        );
  }

  Widget _buildQuickStats() {
    int totalConnections = 0;
    double totalAmount = 0.0;
    double totalPaidAmount = 0.0;
    double totalUnpaidAmount = 0.0;
    int totalTechnicians = technicians.length;

    for (var technicianConnections in filteredConnectionsData.values) {
      totalConnections += technicianConnections.length;
      totalAmount += _calculateTotalAmount(technicianConnections);

      // حساب المبالغ المسددة وغير المسددة
      final paymentStats = _calculatePaymentStats(technicianConnections);
      totalPaidAmount += paymentStats['paidAmount']! as double;
      totalUnpaidAmount += paymentStats['unpaidAmount']! as double;
    }

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: _buildStatItem(
                      'إجمالي الفنيين',
                      totalTechnicians.toString(),
                      Icons.engineering,
                      Colors.blue),
                ),
                Container(
                  width: 1,
                  height: 40,
                  color: Colors.grey.shade300,
                ),
                Expanded(
                  child: _buildStatItem('إجمالي الوصولات',
                      totalConnections.toString(), Icons.link, Colors.orange),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // إحصائيات المبالغ المفصلة
            Row(
              children: [
                // المجموع الكلي
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        vertical: 12, horizontal: 12),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border:
                          Border.all(color: Colors.orange.shade300, width: 1.5),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.account_balance_wallet,
                                color: Colors.orange.shade700, size: 20),
                            const SizedBox(width: 6),
                            Text(
                              'الإجمالي',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: Colors.orange.shade800,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _formatAmount(totalAmount),
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.orange.shade900,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // المسدد
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        vertical: 12, horizontal: 12),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border:
                          Border.all(color: Colors.green.shade300, width: 1.5),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.check_circle,
                                color: Colors.green.shade700, size: 20),
                            const SizedBox(width: 6),
                            Text(
                              'المسدد',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: Colors.green.shade800,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _formatAmount(totalPaidAmount),
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.green.shade900,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // غير المسدد
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        vertical: 12, horizontal: 12),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border:
                          Border.all(color: Colors.red.shade300, width: 1.5),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.pending,
                                color: Colors.red.shade700, size: 20),
                            const SizedBox(width: 6),
                            Text(
                              'غير المسدد',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: Colors.red.shade800,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _formatAmount(totalUnpaidAmount),
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.red.shade900,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// بناء عنصر إحصائي
  Widget _buildStatItem(
      String label, String value, IconData icon, MaterialColor color) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey.shade600,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
            widget.specificUser != null
                ? 'وصولات المستخدم ${widget.specificUser}'
                : widget.specificTechnician != null
                    ? 'وصولات الفني ${widget.specificTechnician}'
                    : 'جميع الوصولات', // تغيير العنوان لإزالة أي إشارة للتصفية
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          // إضافة زر التصفية المحلية
          IconButton(
            icon: Icon(
              showLocalFilters ? Icons.filter_alt : Icons.filter_list,
              color: (localFromDate != null ||
                      localToDate != null ||
                      selectedTechnicianFilter != 'الكل')
                  ? Colors.orange // لون مختلف إذا كانت هناك تصفية نشطة
                  : Colors.white,
            ),
            onPressed: () {
              setState(() {
                showLocalFilters = !showLocalFilters;
              });
            },
            tooltip: showLocalFilters ? 'إخفاء التصفية' : 'إظهار التصفية',
          ),
          // إضافة أيقونة بحث
          IconButton(
            icon: Icon(isSearching ? Icons.close : Icons.search),
            onPressed: () {
              setState(() {
                isSearching = !isSearching;
                if (!isSearching) {
                  _searchController.clear();
                  _filterData('');
                }
              });
            },
            tooltip: isSearching ? 'إلغاء البحث' : 'بحث',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadConnectionsData,
            tooltip: 'تحديث البيانات',
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.deepPurple.withValues(alpha: 0.1),
              Colors.white,
            ],
          ),
        ),
        child: Column(
          children: [
            // شريط البحث
            if (isSearching)
              Container(
                margin: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: TextField(
                  controller: _searchController,
                  onChanged: _filterData,
                  decoration: const InputDecoration(
                    hintText:
                        'البحث في الأسماء، الهواتف، أسماء فنيي التوصيل...',
                    prefixIcon: Icon(Icons.search),
                    border: InputBorder.none,
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                  textInputAction: TextInputAction.search,
                ),
              ),

            // قسم التصفية المحلية
            if (showLocalFilters) _buildLocalFilterSection(),

            // إزالة مؤشر معايير التصفية من الصفحة الرئيسية لأننا ألغيناها

            // مؤشر التصفية المحلية النشطة
            if ((localFromDate != null ||
                localToDate != null ||
                selectedTechnicianFilter != 'الكل'))
              Container(
                margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.tune,
                      color: Colors.orange.shade700,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _getLocalFilterDescription(),
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.orange.shade800,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    // زر مسح التصفية المحلية
                    InkWell(
                      onTap: _clearLocalFilters,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade100,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Icon(
                          Icons.clear,
                          color: Colors.orange.shade700,
                          size: 16,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            // المحتوى الرئيسي
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Colors.deepPurple),
            ),
            SizedBox(height: 16),
            Text('جاري تحميل البيانات...'),
          ],
        ),
      );
    }

    if (errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: Colors.red.shade400),
            const SizedBox(height: 16),
            Text(errorMessage!,
                style: const TextStyle(fontSize: 16, color: Colors.red),
                textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadConnectionsData,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepPurple,
                foregroundColor: Colors.white,
              ),
              child: const Text('إعادة المحاولة'),
            ),
          ],
        ),
      );
    }

    if (filteredConnectionsData.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.info_outline, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            Text(
                _searchController.text.isNotEmpty
                    ? 'لا توجد نتائج للبحث "${_searchController.text}"'
                    : widget.specificUser != null
                        ? 'لا توجد وصولات للمستخدم ${widget.specificUser}'
                        : widget.specificTechnician != null
                            ? 'لا توجد وصولات للفني ${widget.specificTechnician}'
                            : 'لا توجد وصولات بفني توصيل محدد',
                style: const TextStyle(fontSize: 16, color: Colors.grey),
                textAlign: TextAlign.center),
            const SizedBox(height: 8),
            const Text(
                'الوصولات التي تحتوي على فني توصيل في عامود AE ستظهر هنا',
                style: TextStyle(fontSize: 14, color: Colors.grey),
                textAlign: TextAlign.center),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // إحصائيات سريعة
        _buildQuickStats(),
        const SizedBox(height: 16),

        // قائمة فنيي التوصيل والوصولات
        ...List.generate(technicians.length, (index) {
          final technicianName = technicians[index];
          final technicianConnections =
              filteredConnectionsData[technicianName]!;

          return Card(
            margin: const EdgeInsets.only(bottom: 16),
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: ExpansionTile(
              leading: CircleAvatar(
                backgroundColor: Colors.blue.shade100,
                child: Icon(
                  Icons.engineering,
                  color: Colors.blue.shade800,
                  size: 20,
                ),
              ),
              title: Text(
                technicianName,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue,
                ),
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // معلومات إضافية على اليسار (فارغة للحفاظ على المساحة)
                    const SizedBox(width: 1),
                    // المعلومات المالية على اليمين (مُبرزة)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // عدد الوصولات
                        Container(
                          height: 40,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                                color: Colors.blue.shade300, width: 1.5),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.blue.shade100,
                                blurRadius: 3,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.link,
                                  color: Colors.blue.shade700, size: 16),
                              const SizedBox(width: 6),
                              Text(
                                '${technicianConnections.length}',
                                style: TextStyle(
                                  color: Colors.blue.shade800,
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'عملية',
                                style: TextStyle(
                                  color: Colors.blue.shade600,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        // مؤشر حالة التسديد
                        Builder(
                          builder: (context) {
                            final paymentStats =
                                _calculatePaymentStats(technicianConnections);
                            final paidAmount =
                                paymentStats['paidAmount']! as double;
                            final unpaidAmount =
                                paymentStats['unpaidAmount']! as double;
                            final paidCount = paymentStats['paidCount']! as int;
                            final unpaidCount =
                                paymentStats['unpaidCount']! as int;
                            final totalAmount = paidAmount + unpaidAmount;

                            return Row(
                              children: [
                                // المجموع الكلي
                                Container(
                                  height: 40,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: Colors.orange.shade50,
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                        color: Colors.orange.shade300,
                                        width: 1.5),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.orange.shade100,
                                        blurRadius: 3,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.account_balance_wallet,
                                          color: Colors.orange.shade700,
                                          size: 16),
                                      const SizedBox(width: 6),
                                      Text(
                                        _formatAmount(totalAmount),
                                        style: TextStyle(
                                          color: Colors.orange.shade800,
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        'الكلي',
                                        style: TextStyle(
                                          color: Colors.orange.shade600,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                // عدد المسدد
                                Container(
                                  height: 40,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: Colors.green.shade50,
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                        color: Colors.green.shade300,
                                        width: 1.5),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.green.shade100,
                                        blurRadius: 3,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.check_circle,
                                          color: Colors.green.shade600,
                                          size: 16),
                                      const SizedBox(width: 6),
                                      Text(
                                        '$paidCount',
                                        style: TextStyle(
                                          color: Colors.green.shade700,
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        'مسدد',
                                        style: TextStyle(
                                          color: Colors.green.shade600,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 6),
                                // مبلغ المسدد
                                Container(
                                  height: 40,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: Colors.green.shade50,
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                        color: Colors.green.shade300,
                                        width: 1.5),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.attach_money,
                                          color: Colors.green.shade600,
                                          size: 14),
                                      const SizedBox(width: 4),
                                      Text(
                                        _formatAmount(paidAmount),
                                        style: TextStyle(
                                          color: Colors.green.shade700,
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                // عدد غير المسدد
                                Container(
                                  height: 40,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: Colors.red.shade50,
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                        color: Colors.red.shade300, width: 1.5),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.red.shade100,
                                        blurRadius: 3,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.pending,
                                          color: Colors.red.shade600, size: 16),
                                      const SizedBox(width: 6),
                                      Text(
                                        '$unpaidCount',
                                        style: TextStyle(
                                          color: Colors.red.shade700,
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        'غير مسدد',
                                        style: TextStyle(
                                          color: Colors.red.shade600,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 6),
                                // مبلغ غير المسدد
                                Container(
                                  height: 40,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: Colors.red.shade50,
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                        color: Colors.red.shade300, width: 1.5),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.attach_money,
                                          color: Colors.red.shade600, size: 14),
                                      const SizedBox(width: 4),
                                      Text(
                                        _formatAmount(unpaidAmount),
                                        style: TextStyle(
                                          color: Colors.red.shade700,
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 10),
                                // زر تسديد جميع العمليات
                                Builder(
                                  builder: (context) {
                                    final hasUnpaidConnections =
                                        technicianConnections.any(
                                            (connection) =>
                                                !_isConnectionPaid(connection));

                                    return ElevatedButton.icon(
                                      onPressed: hasUnpaidConnections
                                          ? () {
                                              _showPayAllConfirmation(
                                                  context,
                                                  technicianName,
                                                  technicianConnections);
                                            }
                                          : null,
                                      icon: Icon(
                                        Icons.payment,
                                        size: 16,
                                        color: hasUnpaidConnections
                                            ? Colors.white
                                            : Colors.grey,
                                      ),
                                      label: Text(
                                        'تسديد الكل',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: hasUnpaidConnections
                                              ? Colors.white
                                              : Colors.grey,
                                        ),
                                      ),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: hasUnpaidConnections
                                            ? Colors.green.shade600
                                            : Colors.grey.shade300,
                                        elevation: hasUnpaidConnections ? 2 : 0,
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 12, vertical: 8),
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(12),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ],
                            );
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              children: technicianConnections
                  .map((connection) => _buildConnectionCard(connection))
                  .toList(),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildConnectionCard(Map<String, dynamic> connection) {
    final isPaid = _isConnectionPaid(connection);

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isPaid ? Colors.green.shade50 : Colors.red.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isPaid ? Colors.green.shade300 : Colors.red.shade300,
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: isPaid ? Colors.green.shade100 : Colors.red.shade100,
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // زر التسديد في الأعلى
          _buildPaymentButton(connection),

          const SizedBox(height: 12),
          // معلومات العميل الأساسية
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            connection['customerName'] ?? '',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.deepPurple,
                            ),
                          ),
                        ),
                        // مؤشر حالة التسديد
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: isPaid
                                ? Colors.green.shade600
                                : Colors.red.shade600,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                isPaid ? Icons.check_circle : Icons.pending,
                                size: 14,
                                color: Colors.white,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                isPaid ? 'مسدد' : 'غير مسدد',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'رقم الهاتف: ${connection['phoneNumber'] ?? ''}',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _getStatusColor(connection['currentStatus'] ?? ''),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  connection['currentStatus'] ?? '',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // معلومات الاشتراك
          _buildInfoRow('معرف الاشتراك', connection['subscriptionId'] ?? ''),
          _buildInfoRow('نوع الباقة', connection['planName'] ?? ''),
          _buildInfoRow('السعر',
              '${connection['planPrice'] ?? ''} ${connection['currency'] ?? ''}'),
          _buildInfoRow('نوع العملية', connection['operationType'] ?? ''),
          _buildInfoRow(
              'تاريخ التفعيل', _formatDate(connection['activationDate'] ?? '')),
          _buildInfoRow('المنطقة', connection['zoneId'] ?? ''),
          _buildInfoRow('أدخل بواسطة', connection['enteredBy'] ?? 'غير محدد'),

          const SizedBox(height: 8),

          // فني التوصيل (العامود AE - السبب في ظهور هذا السجل)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
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
                    Icon(Icons.engineering,
                        color: Colors.blue.shade600, size: 16),
                    const SizedBox(width: 6),
                    Text(
                      'فني التوصيل:',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.blue.shade700,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  connection['deviceModel'] ?? 'غير محدد',
                  style: TextStyle(
                    color: Colors.blue.shade800,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value.isNotEmpty ? value : 'غير محدد',
              style: TextStyle(
                fontSize: 13,
                color: value.isNotEmpty ? Colors.black87 : Colors.grey,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'active':
      case 'نشط':
        return Colors.green;
      case 'inactive':
      case 'غير نشط':
        return Colors.red;
      case 'suspended':
      case 'معلق':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  String _formatDate(String dateStr) {
    if (dateStr.isEmpty) return '';

    try {
      final date = DateTime.parse(dateStr);
      return DateFormat('yyyy/MM/dd').format(date);
    } catch (e) {
      return dateStr; // إرجاع النص الأصلي إذا فشل التحويل
    }
  }

  /// بناء زر التسديد
  Widget _buildPaymentButton(Map<String, dynamic> connection) {
    // فحص حالة التسديد الحالية من العامود AM
    final isPaid = _isConnectionPaid(connection);

    if (isPaid) {
      // إذا كان مسدد، عرض زرين: التسديد وإلغاء التسديد
      return Row(
        children: [
          // زر حالة التسديد (غير قابل للضغط)
          Expanded(
            flex: 2,
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: null,
                icon: Icon(
                  Icons.check_circle,
                  size: 20,
                  color: Colors.white,
                ),
                label: Text(
                  '✅ تم التسديد',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green.shade600,
                  disabledBackgroundColor: Colors.green.shade600,
                  padding:
                      const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  elevation: 2,
                  shadowColor: Colors.green.shade200,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // زر إلغاء التسديد
          Expanded(
            flex: 1,
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _cancelPayment(connection),
                icon: Icon(
                  Icons.cancel,
                  size: 18,
                ),
                label: Text(
                  'إلغاء',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange.shade600,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  elevation: 2,
                  shadowColor: Colors.orange.shade200,
                ),
              ),
            ),
          ),
        ],
      );
    } else {
      // إذا كان غير مسدد، عرض زر التسديد فقط
      return SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: () => _processPayment(connection),
          icon: Icon(
            Icons.payment,
            size: 20,
          ),
          label: Text(
            '💰 تسديد المبلغ',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red.shade600,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            elevation: 4,
            shadowColor: Colors.red.shade200,
          ),
        ),
      );
    }
  }

  /// حساب إحصائيات التسديد لفني معين (المبالغ)
  Map<String, dynamic> _calculatePaymentStats(
      List<Map<String, dynamic>> connections) {
    double paidAmount = 0.0;
    double unpaidAmount = 0.0;
    int paidCount = 0;
    int unpaidCount = 0;

    for (final connection in connections) {
      final priceString = connection['planPrice']?.toString() ?? '0';
      final price = double.tryParse(priceString.replaceAll(',', '')) ?? 0.0;

      if (_isConnectionPaid(connection)) {
        paidAmount += price;
        paidCount++;
      } else {
        unpaidAmount += price;
        unpaidCount++;
      }
    }

    return {
      'paidAmount': paidAmount,
      'unpaidAmount': unpaidAmount,
      'paidCount': paidCount,
      'unpaidCount': unpaidCount,
      'total': connections.length,
      'totalAmount': paidAmount + unpaidAmount,
    };
  }

  /// فحص ما إذا كان الاتصال مسدد أم لا
  bool _isConnectionPaid(Map<String, dynamic> connection) {
    // فحص العامود AM (paymentStatus)
    final paymentStatus =
        connection['paymentStatus']?.toString().trim().toLowerCase() ?? '';

    // طباعة تشخيصية
    final customerName = connection['customerName'] ?? '';
    print('🔍 فحص حالة التسديد للعميل: $customerName');
    print('   قيمة paymentStatus: "$paymentStatus"');

    // القيم التي تشير إلى التسديد
    final isPaid = paymentStatus == 'paid' ||
        paymentStatus == 'مسدد' ||
        paymentStatus == '1' ||
        paymentStatus == 'true' ||
        paymentStatus == 'تم' ||
        paymentStatus == 'نعم';

    print('   النتيجة: ${isPaid ? "مسدد ✅" : "غير مسدد ❌"}');

    return isPaid;
  }

  /// معالجة عملية التسديد
  Future<void> _processPayment(Map<String, dynamic> connection) async {
    // عرض تأكيد
    final confirmed = await _showPaymentConfirmation(connection);
    if (!confirmed) return;

    try {
      // عرض مؤشر التحميل
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(),
        ),
      );

      // تحديث العامود AM في Google Sheets
      await _updatePaymentStatus(connection);

      // تحديث البيانات المحلية فوراً
      _updateLocalPaymentStatus(connection);

      // إغلاق مؤشر التحميل
      if (mounted) Navigator.of(context).pop();

      // عرض رسالة نجاح
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'تم تسديد المبلغ بنجاح!',
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        'العميل: ${connection['customerName'] ?? 'غير محدد'}',
                        style: const TextStyle(fontSize: 12),
                      ),
                      Text(
                        'تم تحديث البطاقة وحفظ التسديد في النظام',
                        style: const TextStyle(
                            fontSize: 11, fontStyle: FontStyle.italic),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.green.shade600,
            duration: const Duration(seconds: 4),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      // إغلاق مؤشر التحميل
      if (mounted) Navigator.of(context).pop();

      // عرض رسالة خطأ
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'حدث خطأ أثناء التسديد: $e',
                    style: const TextStyle(fontSize: 14),
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.red.shade600,
            duration: const Duration(seconds: 5),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  /// عرض تأكيد التسديد
  Future<bool> _showPaymentConfirmation(Map<String, dynamic> connection) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.payment, color: Colors.blue),
            SizedBox(width: 8),
            Text('تأكيد التسديد'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('هل تريد تسديد المبلغ للعميل:'),
            const SizedBox(height: 8),
            Text(
              connection['customerName'] ?? 'غير محدد',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: Colors.deepPurple,
              ),
            ),
            const SizedBox(height: 8),
            Text(
                'المبلغ: ${connection['planPrice'] ?? ''} ${connection['currency'] ?? ''}'),
            Text('الهاتف: ${connection['phoneNumber'] ?? ''}'),
            const SizedBox(height: 12),
            const Text(
              'سيتم تحديث حالة التسديد في النظام.',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
            child: const Text('تأكيد التسديد'),
          ),
        ],
      ),
    );

    return result ?? false;
  }

  /// تحديث حالة التسديد في Google Sheets
  Future<void> _updatePaymentStatus(Map<String, dynamic> connection) async {
    // هنا نحتاج لتحديد معرف السجل في Google Sheets لتحديث العامود AM
    final subscriptionId = connection['subscriptionId']?.toString() ?? '';
    final customerName = connection['customerName']?.toString() ?? '';

    if (subscriptionId.isEmpty && customerName.isEmpty) {
      throw Exception('لا يمكن تحديد السجل للتحديث');
    }

    // استدعاء خدمة Google Sheets لتحديث العامود AM
    await GoogleSheetsService.updatePaymentStatus(
      subscriptionId: subscriptionId,
      customerName: customerName,
      paymentStatus: 'مسدد', // القيمة التي ستحفظ في العامود AM
    );

    print('✅ تم تحديث حالة التسديد في العامود AM');
    print('   - معرف الاشتراك: $subscriptionId');
    print('   - اسم العميل: $customerName');
    print('   - الحالة: مسدد');
  }

  /// تحديث حالة التسديد في البيانات المحلية
  void _updateLocalPaymentStatus(Map<String, dynamic> connection) {
    final subscriptionId = connection['subscriptionId']?.toString() ?? '';
    final customerName = connection['customerName']?.toString() ?? '';

    print('🔄 بدء تحديث البيانات المحلية:');
    print('   - معرف الاشتراك: $subscriptionId');
    print('   - اسم العميل: $customerName');

    setState(() {
      // تحديث حالة التسديد في البيانات المحلية
      connection['paymentStatus'] = 'مسدد';
      int updatedCount = 0;

      // البحث عن الاتصال في البيانات المفلترة وتحديثه أيضاً
      for (final technicianName in filteredConnectionsData.keys) {
        final connections = filteredConnectionsData[technicianName]!;
        for (int i = 0; i < connections.length; i++) {
          final conn = connections[i];
          if ((conn['subscriptionId'] == subscriptionId &&
                  subscriptionId.isNotEmpty) ||
              (conn['customerName'] == customerName &&
                  customerName.isNotEmpty)) {
            connections[i]['paymentStatus'] = 'مسدد';
            updatedCount++;
            print('   ✅ تحديث في البيانات المفلترة - الفني: $technicianName');
            break;
          }
        }
      }

      // تحديث البيانات الأصلية أيضاً
      for (final technicianName in connectionsData.keys) {
        final connections = connectionsData[technicianName]!;
        for (int i = 0; i < connections.length; i++) {
          final conn = connections[i];
          if ((conn['subscriptionId'] == subscriptionId &&
                  subscriptionId.isNotEmpty) ||
              (conn['customerName'] == customerName &&
                  customerName.isNotEmpty)) {
            connections[i]['paymentStatus'] = 'مسدد';
            updatedCount++;
            print('   ✅ تحديث في البيانات الأصلية - الفني: $technicianName');
            break;
          }
        }
      }

      print('📊 تم تحديث $updatedCount موقع في البيانات المحلية');
    });

    print('🔄 تم تحديث البيانات المحلية - البطاقة ستصبح خضراء الآن');
  }

  /// عرض حوار تأكيد لتسديد جميع عمليات الفني
  void _showPayAllConfirmation(BuildContext context, String technicianName,
      List<Map<String, dynamic>> connections) {
    final unpaidConnections = connections
        .where((connection) => !_isConnectionPaid(connection))
        .toList();
    final totalAmount = unpaidConnections.fold<double>(0.0, (sum, connection) {
      final priceStr = connection['planPrice']?.toString() ?? '0';
      return sum + (double.tryParse(priceStr.replaceAll(',', '')) ?? 0.0);
    });

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(Icons.payment, color: Colors.green.shade600),
              const SizedBox(width: 8),
              const Text('تسديد جميع العمليات'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('هل تريد تسديد جميع عمليات الفني؟'),
              const SizedBox(height: 8),
              Text('الفني: $technicianName',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.pending,
                            color: Colors.red.shade600, size: 16),
                        const SizedBox(width: 4),
                        Text(
                            'عدد العمليات غير المسددة: ${unpaidConnections.length}'),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.attach_money,
                            color: Colors.green.shade600, size: 16),
                        const SizedBox(width: 4),
                        Text(
                            'المبلغ الإجمالي: ${_formatAmount(totalAmount)} IQD'),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('إلغاء'),
            ),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                _payAllConnections(technicianName, unpaidConnections);
              },
              icon: const Icon(Icons.check, color: Colors.white),
              label: const Text('تسديد الكل',
                  style: TextStyle(color: Colors.white)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green.shade600,
              ),
            ),
          ],
        );
      },
    );
  }

  /// تسديد جميع عمليات الفني
  Future<void> _payAllConnections(String technicianName,
      List<Map<String, dynamic>> unpaidConnections) async {
    try {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                strokeWidth: 2,
              ),
              const SizedBox(width: 16),
              Text('جاري تسديد ${unpaidConnections.length} عملية...'),
            ],
          ),
          duration: const Duration(seconds: 2),
          backgroundColor: Colors.blue.shade600,
        ),
      );

      // تسديد كل عملية
      for (final connection in unpaidConnections) {
        await _updatePaymentStatus(connection);
        // فترة انتظار قصيرة لتجنب ضغط الـ API
        await Future.delayed(const Duration(milliseconds: 100));
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 8),
                Text('تم تسديد جميع عمليات $technicianName بنجاح'),
              ],
            ),
            backgroundColor: Colors.green.shade600,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في التسديد: $e'),
            backgroundColor: Colors.red.shade600,
          ),
        );
      }
    }
  }

  /// إلغاء تسديد العملية
  Future<void> _cancelPayment(Map<String, dynamic> connection) async {
    // عرض حوار التأكيد
    final shouldCancel = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(Icons.cancel, color: Colors.orange.shade600),
              const SizedBox(width: 8),
              const Text('إلغاء التسديد'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('هل تريد إلغاء تسديد هذه العملية؟'),
              const SizedBox(height: 8),
              Text('العميل: ${connection['customerName'] ?? 'غير محدد'}',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text('المبلغ: ${connection['planPrice'] ?? '0'} IQD'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(false);
              },
              child: const Text('إلغاء'),
            ),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.of(context).pop(true);
              },
              icon: const Icon(Icons.check, color: Colors.white),
              label: const Text('تأكيد الإلغاء',
                  style: TextStyle(color: Colors.white)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange.shade600,
              ),
            ),
          ],
        );
      },
    );

    if (shouldCancel == true) {
      await _processCancelPayment(connection);
    }
  }

  /// معالجة إلغاء التسديد
  Future<void> _processCancelPayment(Map<String, dynamic> connection) async {
    print('🔄 بدء عملية إلغاء التسديد...');

    final subscriptionId = connection['subscriptionId']?.toString() ?? '';
    final customerName = connection['customerName']?.toString() ?? '';

    print('📋 معلومات العملية:');
    print('   - معرف الاشتراك: $subscriptionId');
    print('   - اسم العميل: $customerName');

    try {
      // تحديث في Google Sheets - إزالة حالة التسديد
      print('📊 جاري تحديث Google Sheets...');
      await GoogleSheetsService.updatePaymentStatus(
        subscriptionId: subscriptionId,
        customerName: customerName,
        paymentStatus: '', // إزالة حالة التسديد
      );
      print('✅ تم تحديث Google Sheets بنجاح');

      // تحديث البيانات المحلية
      setState(() {
        connection['paymentStatus'] = ''; // إزالة حالة التسديد

        // البحث عن الاتصال في البيانات المفلترة وتحديثه أيضاً
        for (final technicianName in filteredConnectionsData.keys) {
          final connections = filteredConnectionsData[technicianName]!;
          for (int i = 0; i < connections.length; i++) {
            final conn = connections[i];
            if ((conn['subscriptionId'] == subscriptionId &&
                    subscriptionId.isNotEmpty) ||
                (conn['customerName'] == customerName &&
                    customerName.isNotEmpty)) {
              connections[i]['paymentStatus'] = '';
              print(
                  '   ✅ تم إلغاء التسديد في البيانات المفلترة - الفني: $technicianName');
              break;
            }
          }
        }
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 8),
                const Text('تم إلغاء التسديد بنجاح'),
              ],
            ),
            backgroundColor: Colors.orange.shade600,
            duration: const Duration(seconds: 2),
          ),
        );
      }

      print('🔄 تم إلغاء التسديد - البطاقة ستصبح حمراء الآن');
    } catch (e) {
      print('❌ خطأ في إلغاء التسديد: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في إلغاء التسديد: $e'),
            backgroundColor: Colors.red.shade600,
          ),
        );
      }
    }
  }
}
