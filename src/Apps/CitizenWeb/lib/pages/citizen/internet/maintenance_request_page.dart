import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../config/app_theme.dart';

/// صفحة طلب صيانة - تنسيق موحد
class MaintenanceRequestPage extends StatefulWidget {
  const MaintenanceRequestPage({super.key});

  @override
  State<MaintenanceRequestPage> createState() => _MaintenanceRequestPageState();
}

class _MaintenanceRequestPageState extends State<MaintenanceRequestPage> {
  String? _selectedProblem;
  final _descriptionController = TextEditingController();
  bool _isLoading = false;
  bool _useCurrentLocation = true;

  final List<Map<String, dynamic>> _problems = [
    {
      'id': 'no_service',
      'label': 'انقطاع كامل',
      'icon': Icons.wifi_off,
      'color': Colors.red,
    },
    {
      'id': 'slow',
      'label': 'بطء السرعة',
      'icon': Icons.speed,
      'color': Colors.orange,
    },
    {
      'id': 'intermittent',
      'label': 'انقطاع متكرر',
      'icon': Icons.sync_problem,
      'color': Colors.amber,
    },
    {
      'id': 'router',
      'label': 'مشكلة الراوتر',
      'icon': Icons.router,
      'color': Colors.blue,
    },
    {
      'id': 'cable',
      'label': 'مشكلة الكابل',
      'icon': Icons.cable,
      'color': Colors.purple,
    },
    {
      'id': 'other',
      'label': 'أخرى',
      'icon': Icons.help_outline,
      'color': Colors.grey,
    },
  ];

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _submitRequest() async {
    if (_selectedProblem == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('يرجى اختيار نوع المشكلة')));
      return;
    }

    setState(() => _isLoading = true);
    await Future.delayed(const Duration(seconds: 2));

    if (mounted) {
      setState(() => _isLoading = false);
      _showSuccessDialog();
    }
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.successColor.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_circle,
                color: AppTheme.successColor,
                size: 60,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'تم إرسال الطلب!',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'رقم الطلب: #${DateTime.now().millisecondsSinceEpoch % 100000}',
              style: const TextStyle(color: AppTheme.textGrey),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  context.go('/citizen/home');
                },
                child: const Text('العودة للرئيسية'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppTheme.backgroundColor,
        // بدون AppBar - نستخدم هيدر مخصص
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                // ═══════════════════════════════════════
                // الهيدر: زر العودة + العنوان
                // ═══════════════════════════════════════
                _buildHeader(),
                const SizedBox(height: 16),

                // ═══════════════════════════════════════
                // المحتوى
                // ═══════════════════════════════════════
                Expanded(child: _buildContent()),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// الهيدر الموحد
  Widget _buildHeader() {
    return Row(
      children: [
        // زر العودة الموحد
        _buildBackButton(),
        const SizedBox(width: 16),
        // العنوان
        const Expanded(
          child: Text(
            'طلب صيانة',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
        ),
        // أيقونة الصفحة
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.orange,
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.build_circle, color: Colors.white, size: 24),
        ),
      ],
    );
  }

  /// زر العودة الموحد
  Widget _buildBackButton() {
    return GestureDetector(
      onTap: () => context.go('/citizen/internet'),
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: const Icon(
          Icons.arrow_forward_ios, // سهم لليمين →
          color: Colors.black87,
          size: 20,
        ),
      ),
    );
  }

  /// محتوى الصفحة
  Widget _buildContent() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableHeight = constraints.maxHeight;
        // توزيع المساحة: 45% للمشاكل، 35% للوصف، 20% للزر
        final problemsHeight = availableHeight * 0.45;
        final formHeight = availableHeight * 0.35;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // اختيار نوع المشكلة
            const Text(
              'نوع المشكلة',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            SizedBox(height: problemsHeight, child: _buildProblemsGrid()),
            const SizedBox(height: 12),

            // وصف المشكلة والموقع
            SizedBox(height: formHeight, child: _buildFormSection()),

            // زر الإرسال
            _buildSubmitButton(),
          ],
        );
      },
    );
  }

  Widget _buildProblemsGrid() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cardHeight = (constraints.maxHeight - 8) / 2;
        final cardWidth = (constraints.maxWidth - 16) / 3;
        final aspectRatio = cardWidth / cardHeight;

        return GridView.count(
          crossAxisCount: 3,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
          childAspectRatio: aspectRatio,
          physics: const NeverScrollableScrollPhysics(),
          children: _problems.map((problem) {
            final isSelected = _selectedProblem == problem['id'];
            final color = problem['color'] as Color;

            return GestureDetector(
              onTap: () => setState(() => _selectedProblem = problem['id']),
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Colors.white,
                        color.withOpacity(isSelected ? 0.15 : 0.08),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isSelected ? color : color.withOpacity(0.25),
                      width: isSelected ? 2 : 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: color.withOpacity(isSelected ? 0.25 : 0.12),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [color, color.withOpacity(0.7)],
                          ),
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: color.withOpacity(0.35),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Icon(
                          problem['icon'],
                          color: Colors.white,
                          size: 22,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        problem['label'],
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: isSelected ? color : color.withOpacity(0.9),
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _buildFormSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // وصف المشكلة
        const Text(
          'وصف المشكلة (اختياري)',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 6),
        Expanded(
          child: TextField(
            controller: _descriptionController,
            maxLines: null,
            expands: true,
            textAlignVertical: TextAlignVertical.top,
            decoration: InputDecoration(
              hintText: 'اكتب تفاصيل المشكلة...',
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Colors.black54, width: 2),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Colors.black54, width: 2),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),

        // الموقع
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.black54, width: 2),
          ),
          child: Row(
            children: [
              const Icon(Icons.location_on, color: AppTheme.primaryColor),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'استخدام موقعي الحالي',
                  style: TextStyle(fontWeight: FontWeight.w500),
                ),
              ),
              Switch(
                value: _useCurrentLocation,
                onChanged: (v) => setState(() => _useCurrentLocation = v),
                activeThumbColor: AppTheme.primaryColor,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSubmitButton() {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: ElevatedButton(
        onPressed: _isLoading ? null : _submitRequest,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.orange,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: _isLoading
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              )
            : const Text(
                'إرسال الطلب',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
      ),
    );
  }
}
