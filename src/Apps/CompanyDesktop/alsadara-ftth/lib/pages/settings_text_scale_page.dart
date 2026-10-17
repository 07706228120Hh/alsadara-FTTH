/// اسم الصفحة: إعدادات حجم النص
/// وصف الصفحة: صفحة إعدادات حجم النص وإمكانية الوصول
/// المؤلف: تطبيق السدارة
/// تاريخ الإنشاء: 2024
library;

import 'package:flutter/material.dart';
import '../services/app_text_scale.dart';
import '../frontend/frontend.dart';

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
    return SdPage(
      appBar: const SdAppBar(title: 'حجم النص داخل التطبيق'),
      maxWidth: SdSpace.formMax,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'اضبط مقياس النص للتطبيق فقط (لا يؤثر على إعدادات النظام).',
            style: SdText.bodySm,
          ),
          const SizedBox(height: SdSpace.md),
          SdCard(
            title: 'المقياس',
            icon: Icons.text_fields_rounded,
            tone: SdGroup.neutral.tone,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ValueListenableBuilder<double>(
                  valueListenable: AppTextScale.instance.notifier,
                  builder: (context, scale, _) {
                    return Row(
                      children: [
                        const Text('صغير', style: SdText.caption),
                        Expanded(
                          child: Slider(
                            value: _temp,
                            min: 0.8,
                            max: 1.3,
                            divisions: 10,
                            label: _temp.toStringAsFixed(2),
                            activeColor: SdColors.primary,
                            onChanged: (v) => setState(() {
                              _temp = v;
                              final idx = _presetValues
                                  .indexWhere((p) => (p - v).abs() < 0.0001);
                              _selectedPreset = idx == -1 ? null : idx;
                            }),
                            onChangeEnd: (v) => AppTextScale.instance.set(v),
                          ),
                        ),
                        const Text('كبير', style: SdText.caption),
                      ],
                    );
                  },
                ),
                const SizedBox(height: SdSpace.xs),
                SdFilterChips<int>(
                  options: const [
                    SdFilterOption(0, 'صغير'),
                    SdFilterOption(1, 'افتراضي'),
                    SdFilterOption(2, 'كبير'),
                  ],
                  selected: _selectedPreset ?? -1,
                  onSelected: _applyPreset,
                ),
              ],
            ),
          ),
          const SizedBox(height: SdSpace.md),
          Row(
            children: [
              SdButton(
                label: 'إعادة الافتراضي',
                icon: Icons.refresh,
                kind: SdButtonKind.secondary,
                onPressed: () async {
                  await AppTextScale.instance.reset();
                  setState(() {
                    _temp = AppTextScale.instance.value;
                    _selectedPreset = 1; // رجوع للافتراضي
                  });
                },
              ),
              const SizedBox(width: SdSpace.sm),
              SdButton(
                label: 'تم',
                icon: Icons.check,
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: SdSpace.xl),
          const Text('معاينة:', style: SdText.titleSm),
          const SizedBox(height: SdSpace.xs),
          SdCard(
            padding: const EdgeInsets.all(SdSpace.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text('عنوان كبير', style: SdText.title),
                SizedBox(height: 6),
                Text(
                  'هذا نص فقرة تجريبي لعرض تأثير تغيير المقياس داخل التطبيق.',
                  style: SdText.body,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
