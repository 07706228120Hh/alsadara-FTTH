/// اسم الصفحة: مقارنة البحث
/// وصف الصفحة: صفحة مقارنة نتائج البحث المختلفة
/// المؤلف: تطبيق السدارة
/// تاريخ الإنشاء: 2024
library;

import 'package:flutter/material.dart';
import 'search_users_page.dart';
import 'enhanced_search_users_page.dart';

class SearchComparisonPage extends StatelessWidget {
  const SearchComparisonPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('مقارنة أنظمة البحث'),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // عنوان
            const Text(
              'اختر نظام البحث المناسب',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.indigo,
              ),
            ),
            const SizedBox(height: 20),

            // بطاقة النظام التقليدي
            Expanded(
              child: Card(
                elevation: 4,
                child: InkWell(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const SearchUsersPage(),
                      ),
                    );
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.search,
                              size: 32,
                              color: Colors.blue.shade600,
                            ),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Text(
                                'النظام التقليدي',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blue,
                                ),
                              ),
                            ),
                            const Icon(Icons.arrow_forward_ios),
                          ],
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'المميزات:',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        _buildFeatureItem(
                          Icons.check_circle_outline,
                          'مطابقة حرفية دقيقة',
                          Colors.green,
                        ),
                        _buildFeatureItem(
                          Icons.check_circle_outline,
                          'بحث عن العلاقات العائلية',
                          Colors.green,
                        ),
                        _buildFeatureItem(
                          Icons.check_circle_outline,
                          'سرعة في المعالجة',
                          Colors.green,
                        ),
                        _buildFeatureItem(
                          Icons.check_circle_outline,
                          'واجهة بسيطة',
                          Colors.green,
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'القيود:',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        _buildFeatureItem(
                          Icons.cancel_outlined,
                          'لا يتعامل مع الأخطاء الإملائية',
                          Colors.red,
                        ),
                        _buildFeatureItem(
                          Icons.cancel_outlined,
                          'حساس للمسافات الزائدة',
                          Colors.red,
                        ),
                        _buildFeatureItem(
                          Icons.cancel_outlined,
                          'لا يدعم البحث الجزئي',
                          Colors.red,
                        ),
                        _buildFeatureItem(
                          Icons.cancel_outlined,
                          'إعدادات ثابتة',
                          Colors.red,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // بطاقة النظام المحسن
            Expanded(
              child: Card(
                elevation: 4,
                color: Colors.green.shade50,
                child: InkWell(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const EnhancedSearchUsersPage(),
                      ),
                    );
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.auto_awesome,
                              size: 32,
                              color: Colors.green.shade600,
                            ),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Text(
                                'النظام المحسن (مُوصى به)',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green,
                                ),
                              ),
                            ),
                            const Icon(Icons.arrow_forward_ios),
                          ],
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'المميزات المتقدمة:',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        _buildFeatureItem(
                          Icons.star,
                          'مطابقة ذكية مع خوارزميات التشابه',
                          Colors.amber,
                        ),
                        _buildFeatureItem(
                          Icons.star,
                          'يتعامل مع الأخطاء الإملائية',
                          Colors.amber,
                        ),
                        _buildFeatureItem(
                          Icons.star,
                          'بحث جزئي ومرن',
                          Colors.amber,
                        ),
                        _buildFeatureItem(
                          Icons.star,
                          'عرض نسبة التشابه',
                          Colors.amber,
                        ),
                        _buildFeatureItem(
                          Icons.star,
                          'إعدادات قابلة للتخصيص',
                          Colors.amber,
                        ),
                        _buildFeatureItem(
                          Icons.star,
                          'ترتيب النتائج حسب الصلة',
                          Colors.amber,
                        ),
                        _buildFeatureItem(
                          Icons.star,
                          'تطبيع النصوص العربية',
                          Colors.amber,
                        ),
                        _buildFeatureItem(
                          Icons.star,
                          'واجهة متقدمة مع ألوان وأيقونات',
                          Colors.amber,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // جدول المقارنة
            const Text(
              'مقارنة سريعة:',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: [
                  _buildComparisonRow(
                    'الميزة',
                    'التقليدي',
                    'المحسن',
                    isHeader: true,
                  ),
                  _buildComparisonRow(
                    'الأخطاء الإملائية',
                    '❌',
                    '✅',
                  ),
                  _buildComparisonRow(
                    'البحث الجزئي',
                    '❌',
                    '✅',
                  ),
                  _buildComparisonRow(
                    'نسبة التشابه',
                    '❌',
                    '✅',
                  ),
                  _buildComparisonRow(
                    'الإعدادات',
                    'ثابتة',
                    'قابلة للتخصيص',
                  ),
                  _buildComparisonRow(
                    'سرعة المعالجة',
                    'عالية',
                    'جيدة',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // توصية
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.lightbulb,
                    color: Colors.blue.shade600,
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'نُوصي باستخدام النظام المحسن للحصول على نتائج أفضل وتجربة مستخدم محسنة',
                      style: TextStyle(
                        fontWeight: FontWeight.w500,
                      ),
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

  Widget _buildFeatureItem(IconData icon, String text, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildComparisonRow(
    String feature,
    String traditional,
    String enhanced, {
    bool isHeader = false,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: isHeader ? Colors.grey.shade100 : Colors.white,
        border: Border(
          bottom: BorderSide(color: Colors.grey.shade300),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                feature,
                style: TextStyle(
                  fontWeight: isHeader ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
          ),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(color: Colors.grey.shade300),
                ),
              ),
              child: Text(
                traditional,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontWeight: isHeader ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
          ),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(color: Colors.grey.shade300),
                ),
              ),
              child: Text(
                enhanced,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontWeight: isHeader ? FontWeight.bold : FontWeight.normal,
                  color: isHeader ? null : Colors.green.shade700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
