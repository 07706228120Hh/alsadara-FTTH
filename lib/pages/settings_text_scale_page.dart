/// اسم الصفحة: إعدادات حجم النص
/// وصف الصفحة: صفحة إعدادات حجم النص وإمكانية الوصول
/// المؤلف: تطبيق السدارة
/// تاريخ الإنشاء: 2024
library;

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../services/app_text_scale.dart';

class SettingsTextScalePage extends StatefulWidget {
  const SettingsTextScalePage({super.key});

  @override
  State<SettingsTextScalePage> createState() => _SettingsTextScalePageState();
}

class _SettingsTextScalePageState extends State<SettingsTextScalePage> {
  double _temp = AppTextScale.instance.value;
  int? _selectedPreset; // 0 صغير - 1 افتراضي - 2 كبير
  static const _presetValues = [0.9, 1.0, 1.15];

  void _applyPreset(int index) {
    setState(() {
      _selectedPreset = index;
      _temp = _presetValues[index];
    });
    AppTextScale.instance.set(_presetValues[index]);
  }

  @override
  void initState() {
    super.initState();
    // Ensure loaded before showing
    AppTextScale.instance.load().then((_) {
      setState(() => _temp = AppTextScale.instance.value);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 50,
        title: Text(
          'حجم النص داخل التطبيق',
          style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w600),
        ),
      ),
      body: Padding(
        padding: EdgeInsets.all(16.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'اضبط مقياس النص للتطبيق فقط (لا يؤثر على إعدادات النظام).',
              style: TextStyle(fontSize: 14.sp, color: Colors.grey[700]),
            ),
            SizedBox(height: 16.h),
            ValueListenableBuilder<double>(
              valueListenable: AppTextScale.instance.notifier,
              builder: (context, scale, _) {
                return Row(
                  children: [
                    Text('صغير', style: TextStyle(fontSize: 12.sp)),
                    Expanded(
                      child: Slider(
                        value: _temp,
                        min: 0.8,
                        max: 1.3,
                        divisions: 10,
                        label: _temp.toStringAsFixed(2),
                        onChanged: (v) => setState(() {
                          _temp = v;
                          final idx = _presetValues
                              .indexWhere((p) => (p - v).abs() < 0.0001);
                          _selectedPreset = idx == -1 ? null : idx;
                        }),
                        onChangeEnd: (v) => AppTextScale.instance.set(v),
                      ),
                    ),
                    Text('كبير', style: TextStyle(fontSize: 12.sp)),
                  ],
                );
              },
            ),
            SizedBox(height: 4.h),
            Wrap(
              spacing: 8.w,
              runSpacing: 4.h,
              children: [
                _PresetChip(
                  label: 'صغير',
                  index: 0,
                  active: _selectedPreset == 0,
                  onTap: () => _applyPreset(0),
                ),
                _PresetChip(
                  label: 'افتراضي',
                  index: 1,
                  active: _selectedPreset == 1,
                  onTap: () => _applyPreset(1),
                ),
                _PresetChip(
                  label: 'كبير',
                  index: 2,
                  active: _selectedPreset == 2,
                  onTap: () => _applyPreset(2),
                ),
              ],
            ),
            SizedBox(height: 8.h),
            Row(
              children: [
                ElevatedButton.icon(
                  onPressed: () async {
                    await AppTextScale.instance.reset();
                    setState(() {
                      _temp = AppTextScale.instance.value;
                      _selectedPreset = 1; // رجوع للافتراضي
                    });
                  },
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('إعادة الافتراضي'),
                ),
                SizedBox(width: 12.w),
                OutlinedButton.icon(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.check, size: 18),
                  label: const Text('تم'),
                ),
              ],
            ),
            SizedBox(height: 24.h),
            Text('معاينة:',
                style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600)),
            SizedBox(height: 8.h),
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(12.w),
              decoration: BoxDecoration(
                color: Colors.blue.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(8.r),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('عنوان كبير',
                      style: TextStyle(
                          fontSize: 18.sp, fontWeight: FontWeight.bold)),
                  SizedBox(height: 6.h),
                  Text(
                      'هذا نص فقرة تجريبي لعرض تأثير تغيير المقياس داخل التطبيق.',
                      style: TextStyle(fontSize: 14.sp)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PresetChip extends StatelessWidget {
  final String label;
  final int index;
  final bool active;
  final VoidCallback onTap;
  const _PresetChip(
      {required this.label,
      required this.index,
      required this.active,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color =
        active ? Theme.of(context).colorScheme.primary : Colors.grey.shade400;
    final textColor = active ? Colors.white : Colors.black87;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20.r),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 6.h),
        decoration: BoxDecoration(
          color: active ? color : Colors.grey.shade200,
          borderRadius: BorderRadius.circular(20.r),
          border: Border.all(
              color: color.withValues(alpha: active ? 0.9 : 0.4), width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (active) Icon(Icons.check, size: 16.sp, color: Colors.white),
            if (active) SizedBox(width: 4.w),
            Text(label,
                style: TextStyle(
                    fontSize: 12.sp,
                    fontWeight: FontWeight.w600,
                    color: textColor)),
          ],
        ),
      ),
    );
  }
}
