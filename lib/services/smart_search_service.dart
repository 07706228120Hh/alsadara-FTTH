import 'package:flutter/material.dart';
import '../models/task.dart';

class SmartSearchService {
  // البحث الذكي مع اقتراحات
  static List<Task> smartSearch(List<Task> tasks, String query) {
    if (query.isEmpty) return tasks;

    query = query.toLowerCase();

    return tasks.where((task) {
      // البحث في جميع حقول المهمة
      var searchableText = [
        task.id,
        task.title,
        task.username,
        task.phone,
        task.location,
        task.notes,
        task.technician,
        task.leader,
        task.department,
        task.status,
        task.fbg,
        task.fat,
        task.amount,
      ].join(' ').toLowerCase();

      // البحث بالكلمات المفتاحية
      var queryWords = query.split(' ');
      return queryWords.every((word) => searchableText.contains(word));
    }).toList();
  }

  // اقتراحات البحث الذكية
  static List<String> getSearchSuggestions(List<Task> tasks, String query) {
    if (query.length < 2) return [];

    Set<String> suggestions = {};
    query = query.toLowerCase();

    for (var task in tasks) {
      var searchableFields = [
        task.title,
        task.username,
        task.technician,
        task.leader,
        task.location,
        task.department,
      ];

      for (var field in searchableFields) {
        if (field.toLowerCase().contains(query)) {
          suggestions.add(field);
        }
      }
    }

    return suggestions.take(5).toList();
  }

  // فلترة متقدمة بمعايير متعددة
  static List<Task> advancedFilter(
      List<Task> tasks, AdvancedFilterCriteria criteria) {
    return tasks.where((task) {
      // فلترة حسب التاريخ
      if (criteria.startDate != null &&
          task.createdAt.isBefore(criteria.startDate!)) {
        return false;
      }
      if (criteria.endDate != null &&
          task.createdAt.isAfter(criteria.endDate!)) {
        return false;
      }

      // فلترة حسب المبلغ
      var taskAmount = double.tryParse(task.amount) ?? 0;
      if (criteria.minAmount != null && taskAmount < criteria.minAmount!) {
        return false;
      }
      if (criteria.maxAmount != null && taskAmount > criteria.maxAmount!) {
        return false;
      }

      // فلترة حسب الحالة
      if (criteria.statuses.isNotEmpty &&
          !criteria.statuses.contains(task.status)) {
        return false;
      }

      // فلترة حسب الأولوية
      if (criteria.priorities.isNotEmpty &&
          !criteria.priorities.contains(task.priority)) {
        return false;
      }

      // فلترة حسب القسم
      if (criteria.departments.isNotEmpty &&
          !criteria.departments.contains(task.department)) {
        return false;
      }

      // فلترة حسب المدة
      if (criteria.maxDuration != null && task.closedAt != null) {
        var duration = task.closedAt!.difference(task.createdAt);
        if (duration > criteria.maxDuration!) {
          return false;
        }
      }

      return true;
    }).toList();
  }
}

class AdvancedFilterCriteria {
  DateTime? startDate;
  DateTime? endDate;
  double? minAmount;
  double? maxAmount;
  List<String> statuses;
  List<String> priorities;
  List<String> departments;
  Duration? maxDuration;

  AdvancedFilterCriteria({
    this.startDate,
    this.endDate,
    this.minAmount,
    this.maxAmount,
    this.statuses = const [],
    this.priorities = const [],
    this.departments = const [],
    this.maxDuration,
  });
}

// ويدجت البحث الذكي
class SmartSearchWidget extends StatefulWidget {
  final List<Task> tasks;
  final Function(List<Task>) onSearchResults;

  const SmartSearchWidget({
    super.key,
    required this.tasks,
    required this.onSearchResults,
  });

  @override
  _SmartSearchWidgetState createState() => _SmartSearchWidgetState();
}

class _SmartSearchWidgetState extends State<SmartSearchWidget> {
  final TextEditingController _searchController = TextEditingController();
  List<String> _suggestions = [];
  bool _showSuggestions = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.all(16),
      child: Column(
        children: [
          // شريط البحث
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(25),
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.withValues(alpha: 0.3),
                  blurRadius: 10,
                  offset: Offset(0, 3),
                ),
              ],
            ),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'البحث في المهام...',
                prefixIcon: Icon(Icons.search, color: Colors.blue),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          _performSearch('');
                        },
                      )
                    : IconButton(
                        icon: Icon(Icons.tune),
                        onPressed: _showAdvancedFilter,
                      ),
                border: InputBorder.none,
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 20, vertical: 15),
              ),
              onChanged: (query) {
                _performSearch(query);
                _updateSuggestions(query);
              },
            ),
          ),

          // اقتراحات البحث
          if (_showSuggestions && _suggestions.isNotEmpty)
            Container(
              margin: EdgeInsets.only(top: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(15),
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.withValues(alpha: 0.2),
                    blurRadius: 8,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                children: _suggestions
                    .map((suggestion) => ListTile(
                          leading:
                              Icon(Icons.search, size: 16, color: Colors.grey),
                          title: Text(suggestion),
                          onTap: () {
                            _searchController.text = suggestion;
                            _performSearch(suggestion);
                            setState(() {
                              _showSuggestions = false;
                            });
                          },
                        ))
                    .toList(),
              ),
            ),
        ],
      ),
    );
  }

  void _performSearch(String query) {
    var results = SmartSearchService.smartSearch(widget.tasks, query);
    widget.onSearchResults(results);
  }

  void _updateSuggestions(String query) {
    setState(() {
      _suggestions =
          SmartSearchService.getSearchSuggestions(widget.tasks, query);
      _showSuggestions = query.isNotEmpty && _suggestions.isNotEmpty;
    });
  }

  void _showAdvancedFilter() {
    showDialog(
      context: context,
      builder: (context) => AdvancedFilterDialog(
        tasks: widget.tasks,
        onApplyFilter: (filteredTasks) {
          widget.onSearchResults(filteredTasks);
        },
      ),
    );
  }
}

// نافذة الفلترة المتقدمة
class AdvancedFilterDialog extends StatefulWidget {
  final List<Task> tasks;
  final Function(List<Task>) onApplyFilter;

  const AdvancedFilterDialog({
    super.key,
    required this.tasks,
    required this.onApplyFilter,
  });

  @override
  _AdvancedFilterDialogState createState() => _AdvancedFilterDialogState();
}

class _AdvancedFilterDialogState extends State<AdvancedFilterDialog> {
  DateTime? _startDate;
  DateTime? _endDate;
  double? _minAmount;
  double? _maxAmount;
  final List<String> _selectedStatuses = [];
  final List<String> _selectedDepartments = [];

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        padding: EdgeInsets.all(20),
        height: MediaQuery.of(context).size.height * 0.8,
        child: Column(
          children: [
            // العنوان
            Row(
              children: [
                Icon(Icons.tune, color: Colors.blue, size: 28),
                SizedBox(width: 10),
                Text(
                  'الفلترة المتقدمة',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue,
                  ),
                ),
                Spacer(),
                IconButton(
                  icon: Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),

            Divider(height: 30),

            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // فلترة بالتاريخ
                    _buildSectionTitle('التاريخ'),
                    Row(
                      children: [
                        Expanded(
                          child: _buildDateField(
                            'من تاريخ',
                            _startDate,
                            (date) => setState(() => _startDate = date),
                          ),
                        ),
                        SizedBox(width: 16),
                        Expanded(
                          child: _buildDateField(
                            'إلى تاريخ',
                            _endDate,
                            (date) => setState(() => _endDate = date),
                          ),
                        ),
                      ],
                    ),

                    SizedBox(height: 20),

                    // فلترة بالمبلغ
                    _buildSectionTitle('المبلغ'),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            decoration: InputDecoration(
                              labelText: 'الحد الأدنى',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            keyboardType: TextInputType.number,
                            onChanged: (value) {
                              _minAmount = double.tryParse(value);
                            },
                          ),
                        ),
                        SizedBox(width: 16),
                        Expanded(
                          child: TextField(
                            decoration: InputDecoration(
                              labelText: 'الحد الأقصى',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            keyboardType: TextInputType.number,
                            onChanged: (value) {
                              _maxAmount = double.tryParse(value);
                            },
                          ),
                        ),
                      ],
                    ),

                    SizedBox(height: 20),

                    // فلترة بالحالة
                    _buildSectionTitle('الحالة'),
                    Wrap(
                      spacing: 8,
                      children: ['مفتوحة', 'قيد التنفيذ', 'مكتملة', 'ملغية']
                          .map((status) => FilterChip(
                                label: Text(status),
                                selected: _selectedStatuses.contains(status),
                                onSelected: (selected) {
                                  setState(() {
                                    if (selected) {
                                      _selectedStatuses.add(status);
                                    } else {
                                      _selectedStatuses.remove(status);
                                    }
                                  });
                                },
                              ))
                          .toList(),
                    ),

                    SizedBox(height: 20),

                    // فلترة بالقسم
                    _buildSectionTitle('القسم'),
                    Wrap(
                      spacing: 8,
                      children: _getUniqueDepartments()
                          .map((dept) => FilterChip(
                                label: Text(dept),
                                selected: _selectedDepartments.contains(dept),
                                onSelected: (selected) {
                                  setState(() {
                                    if (selected) {
                                      _selectedDepartments.add(dept);
                                    } else {
                                      _selectedDepartments.remove(dept);
                                    }
                                  });
                                },
                              ))
                          .toList(),
                    ),
                  ],
                ),
              ),
            ),

            // أزرار العمل
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: _resetFilters,
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: Text('إعادة تعيين'),
                  ),
                ),
                SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _applyFilters,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: Text('تطبيق الفلترة'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: EdgeInsets.only(bottom: 12),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: Colors.grey[700],
        ),
      ),
    );
  }

  Widget _buildDateField(
      String label, DateTime? date, Function(DateTime) onChanged) {
    return InkWell(
      onTap: () async {
        var selectedDate = await showDatePicker(
          context: context,
          initialDate: date ?? DateTime.now(),
          firstDate: DateTime(2020),
          lastDate: DateTime(2030),
        );
        if (selectedDate != null) {
          onChanged(selectedDate);
        }
      },
      child: Container(
        padding: EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),
            SizedBox(height: 4),
            Text(
              date?.toString().split(' ')[0] ?? 'اختر التاريخ',
              style: TextStyle(
                fontSize: 16,
                color: date != null ? Colors.black : Colors.grey,
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<String> _getUniqueDepartments() {
    return widget.tasks
        .map((task) => task.department)
        .where((dept) => dept.isNotEmpty)
        .toSet()
        .toList();
  }

  void _resetFilters() {
    setState(() {
      _startDate = null;
      _endDate = null;
      _minAmount = null;
      _maxAmount = null;
      _selectedStatuses.clear();
      _selectedDepartments.clear();
    });
  }

  void _applyFilters() {
    var criteria = AdvancedFilterCriteria(
      startDate: _startDate,
      endDate: _endDate,
      minAmount: _minAmount,
      maxAmount: _maxAmount,
      statuses: _selectedStatuses,
      departments: _selectedDepartments,
    );

    var filteredTasks =
        SmartSearchService.advancedFilter(widget.tasks, criteria);
    widget.onApplyFilter(filteredTasks);
    Navigator.pop(context);
  }
}
